extends Node
## Co-op connection to the Scareathon server's rooms (/8bitevilreturns/v2/ws).
## The server keeps the lobby and relays binary packets between the host and
## everyone else; see server/eightBitEvilV2/rooms.js in the Scareathon repo.
##
## Packets: byte 0 is the seat (the host writes who it's for, 255 = everyone;
## the server rewrites it to who sent it), byte 1 the packet type, then data.
##
## Dropping out doesn't end anything: the server holds the seat for a while
## and gives each player a token to take it back. If the socket closes, this
## reconnects with backoff and rejoins by itself. The token is also saved on
## the device so a guest can rejoin after reloading the page.

signal room_changed            # lobby roster, stage or our seat changed
signal started(stage: String, players: Array)
signal closed(reason: String)  # host left, idle, seat lost, or gave up reconnecting
signal failed(message: String)
signal packet(from: int, kind: int, data: PackedByteArray)
signal left(slot: int)
signal away(slot: int)         # another player dropped (their seat is held)
signal back(slot: int)         # ...and came back
signal connection_changed(online: bool)  # our own link dropped / returned

const BROADCAST := 255
const PATH := "/8bitevilreturns/v2/ws"
var session_path := "user://coop_session.json"
const GIVE_UP_AFTER := 95.0  # the server holds a seat for 90s in a game

var ws: WebSocketPeer
var code := ""
var slot := -1
var token := ""
var is_host := false          # this device runs the fight
var is_leader := false        # this player runs the lobby (stage, START)
var host_slot := 0            # which seat runs the fight (the server's own seat when it hosts)
var players: Array = []        # [{slot, name, hero, away}]
var stage := "graveyard"
var public_room := false       # listed for anyone to join (else code only)
var in_game := false
var starting := false          # the leader pressed start; waiting for the game to begin
var reconnecting := false
var _pending: Dictionary = {}  # first message to send once the socket opens
var _was_open := false
var _retry_in := 0.0
var _backoff := 0.5
var _down_for := 0.0
var _drop_at := -1.0           # dev flag drop_at=seconds: cut the link once, to test reconnecting
var _alive_for := 0.0

func active() -> bool:
	return slot >= 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var f := Bridge.flags()
	if f.has("drop_at"):
		_drop_at = float(f.drop_at)
	if f.has("session"):
		# Dev: separate saved seats for several copies on one machine.
		session_path = "user://coop_session_%s.json" % str(f.session).validate_filename()

func _url() -> String:
	var base := Bridge.server_url()
	return base.replace("https://", "wss://").replace("http://", "ws://") + PATH

func create(name: String, hero: String) -> void:
	_open({"type": "create", "name": name, "hero": hero})

## The Scareathon server's headless game copy taking the host seat of a room.
func host_connect(room_code: String, host_token: String) -> void:
	code = room_code
	_open({"type": "host", "code": room_code, "token": host_token})

func join(room_code: String, name: String, hero: String) -> void:
	_open({"type": "join", "code": room_code, "name": name, "hero": hero})

## Leader: list the room publicly, or keep it code-only.
func set_public(on: bool) -> void:
	pick({"public": on})

## Public rooms that can be joined right now: done.call(rooms) with
## [{code, leader, players, max, stage}], or done.call(null) if it failed.
func list_public(done: Callable) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 8.0
	req.request_completed.connect(func(result, code_, _h, body):
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code_ != 200:
			done.call(null)
			return
		var d = JSON.parse_string(body.get_string_from_utf8())
		done.call(d.get("rooms", []) if d is Dictionary else null))
	if req.request(Bridge.server_url() + "/8bitevilreturns/v2/rooms") != OK:
		req.queue_free()
		done.call(null)

func pick(fields: Dictionary) -> void:
	_send_json({"type": "pick"}.merged(fields))

func start_game() -> void:
	_send_json({"type": "start"})

## Leaving on purpose: the seat is freed for good.
func leave() -> void:
	if ws:
		_send_json({"type": "leave"})
		ws.close()
	_forget_session()
	_reset()

func _reset() -> void:
	ws = null
	code = ""
	slot = -1
	token = ""
	is_host = false
	is_leader = false
	host_slot = 0
	players = []
	public_room = false
	in_game = false
	reconnecting = false
	_was_open = false
	_retry_in = 0.0

func _open(first: Dictionary) -> void:
	if ws and not reconnecting:
		leave()
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	_was_open = false
	_alive_for = 0.0
	var err := ws.connect_to_url(_url())
	if err != OK:
		ws = null
		if reconnecting:
			_schedule_retry()
		else:
			failed.emit("Couldn't reach the server.")
		return
	_pending = first

func _send_json(msg: Dictionary) -> void:
	if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))

## Host: send to one seat or BROADCAST. Guest: `to` is ignored (always the host).
func send(to: int, kind: int, data: PackedByteArray) -> void:
	if not ws or ws.get_ready_state() != WebSocketPeer.STATE_OPEN or reconnecting:
		return
	var out := PackedByteArray([to, kind])
	out.append_array(data)
	ws.send(out, WebSocketPeer.WRITE_MODE_BINARY)

## Small game messages as JSON inside a binary packet (type "J").
func send_json(to: int, msg: Dictionary) -> void:
	send(to, 74, JSON.stringify(msg).to_utf8_buffer())

# ---------------------------------------------------------------- Reconnecting

func _lost_link() -> void:
	if not reconnecting:
		reconnecting = true
		_down_for = 0.0
		_backoff = 0.5
		connection_changed.emit(false)
	_schedule_retry()

func _schedule_retry() -> void:
	ws = null
	_retry_in = _backoff
	_backoff = minf(_backoff * 2.0, 5.0)

func _give_up(reason: String) -> void:
	_forget_session()
	_reset()
	closed.emit(reason)

# ---------------------------------------------------------------- Saved session (rejoin after a reload)

func _save_session() -> void:
	if OS.has_feature("server"):
		return
	var f := FileAccess.open(session_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"code": code, "token": token, "host": is_host, "at": Time.get_unix_time_from_system()}))

func _forget_session() -> void:
	if FileAccess.file_exists(session_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(session_path))

## A recent co-op seat this device can take back, or {}.
func saved_session() -> Dictionary:
	if not FileAccess.file_exists(session_path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(session_path))
	if not (d is Dictionary) or Time.get_unix_time_from_system() - float(d.get("at", 0)) > GIVE_UP_AFTER:
		_forget_session()
		return {}
	return d

func rejoin(session: Dictionary) -> void:
	code = str(session.code)
	token = str(session.token)
	_open({"type": "rejoin", "code": code, "token": token})

## A host that reloaded can't bring its fight back: close the room now so the
## others aren't left waiting.
func abandon(session: Dictionary) -> void:
	_forget_session()
	var sock := WebSocketPeer.new()
	if sock.connect_to_url(_url()) == OK:
		_abandon_step(sock, session, 0)

func _abandon_step(sock: WebSocketPeer, session: Dictionary, tries: int) -> void:
	sock.poll()
	if sock.get_ready_state() == WebSocketPeer.STATE_OPEN:
		sock.send_text(JSON.stringify({"type": "rejoin", "code": session.code, "token": session.token}))
		sock.send_text(JSON.stringify({"type": "leave"}))
		get_tree().create_timer(0.5, true).timeout.connect(sock.close)
	elif tries < 100 and sock.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		get_tree().create_timer(0.05, true).timeout.connect(_abandon_step.bind(sock, session, tries + 1))

# ---------------------------------------------------------------- Polling

func _process(delta: float) -> void:
	if reconnecting:
		_down_for += delta
		if _down_for > GIVE_UP_AFTER:
			_give_up("lost")
			return
		if not ws:
			_retry_in -= delta
			if _retry_in <= 0.0:
				_open({"type": "rejoin", "code": code, "token": token})
			return
	if not ws:
		return
	ws.poll()
	var state := ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			if not _pending.is_empty():
				_send_json(_pending)
				_pending = {}
		_alive_for += delta
		if _drop_at > 0.0 and in_game and _alive_for > _drop_at:
			_drop_at = -1.0
			print("[net] dropping the connection on purpose (drop_at)")
			ws.close()
			return
		while ws and ws.get_available_packet_count() > 0:
			var data := ws.get_packet()
			if ws.was_string_packet():
				_on_text(data.get_string_from_utf8())
			elif data.size() >= 2:
				packet.emit(data[0], data[1], data.slice(2))
	elif state == WebSocketPeer.STATE_CLOSED:
		if slot >= 0 or reconnecting:
			_lost_link()  # we had a seat: get it back
		else:
			var opened := _was_open
			_reset()
			if not opened:
				failed.emit("Couldn't reach the server.")

func _on_text(text: String) -> void:
	var m = JSON.parse_string(text)
	if not (m is Dictionary):
		return
	match str(m.get("type")):
		"room":
			code = str(m.code)
			slot = int(m.slot)
			token = str(m.get("token", token))
			is_host = bool(m.host)
			is_leader = bool(m.get("leader", m.host))
			host_slot = int(m.get("host_slot", 0))
			players = m.players
			stage = str(m.get("stage", "graveyard"))
			public_room = bool(m.get("public", false))
			starting = bool(m.get("starting", false))
			_save_session()
			if reconnecting:
				reconnecting = false
				print("[net] reconnected to ", code)
				connection_changed.emit(true)
			room_changed.emit()
			# Rejoining a game that's already going (e.g. after a reload).
			if bool(m.get("started", false)) and not in_game:
				in_game = true
				started.emit(stage, players)
		"start":
			in_game = true
			starting = false
			stage = str(m.stage)
			players = m.players
			# Who runs the fight: the server's game copy, or (if it couldn't
			# start one) the player who made the room.
			host_slot = int(m.get("host", 0))
			is_host = slot == host_slot
			started.emit(stage, players)
		"left":
			left.emit(int(m.slot))
		"away":
			away.emit(int(m.slot))
		"back":
			back.emit(int(m.slot))
		"closed":
			_give_up(str(m.get("reason", "")))
		"error":
			if str(m.get("code")) == "gone":
				_give_up("gone")
			else:
				failed.emit(str(m.get("message", "Something went wrong.")))
