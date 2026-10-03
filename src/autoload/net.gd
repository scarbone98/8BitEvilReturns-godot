extends Node
## Co-op connection to the Scareathon server's rooms (/8bitevilreturns/v2/ws).
## The server keeps the lobby and relays binary packets between the host and
## everyone else; see server/eightBitEvilV2/rooms.js in the Scareathon repo.
##
## Packets: byte 0 is the seat (the host writes who it's for, 255 = everyone;
## the server rewrites it to who sent it), byte 1 the packet type, then data.

signal room_changed            # lobby roster, stage or our seat changed
signal started(stage: String, players: Array)
signal closed(reason: String)  # host left, idle, or connection lost
signal failed(message: String)
signal packet(from: int, kind: int, data: PackedByteArray)
signal left(slot: int)

const BROADCAST := 255
const PATH := "/8bitevilreturns/v2/ws"

var ws: WebSocketPeer
var code := ""
var slot := -1
var is_host := false
var players: Array = []        # [{slot, name, hero}]
var stage := "graveyard"
var in_game := false
var _pending: Dictionary = {}  # first message to send once the socket opens
var _was_open := false

func active() -> bool:
	return ws != null and slot >= 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _url() -> String:
	var base := Bridge.server_url()
	return base.replace("https://", "wss://").replace("http://", "ws://") + PATH

func create(name: String, hero: String) -> void:
	_open({"type": "create", "name": name, "hero": hero})

func join(room_code: String, name: String, hero: String) -> void:
	_open({"type": "join", "code": room_code, "name": name, "hero": hero})

func pick(fields: Dictionary) -> void:
	_send_json({"type": "pick"}.merged(fields))

func start_game() -> void:
	_send_json({"type": "start"})

func leave() -> void:
	if ws:
		_send_json({"type": "leave"})
		ws.close()
	_reset()

func _reset() -> void:
	ws = null
	code = ""
	slot = -1
	is_host = false
	players = []
	in_game = false
	_was_open = false

func _open(first: Dictionary) -> void:
	if ws:
		leave()
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	var err := ws.connect_to_url(_url())
	if err != OK:
		ws = null
		failed.emit("Couldn't reach the server.")
		return
	_pending = first

func _send_json(msg: Dictionary) -> void:
	if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))

## Host: send to one seat or BROADCAST. Guest: `to` is ignored (always the host).
func send(to: int, kind: int, data: PackedByteArray) -> void:
	if not ws or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var out := PackedByteArray([to, kind])
	out.append_array(data)
	ws.send(out, WebSocketPeer.WRITE_MODE_BINARY)

## Small game messages as JSON inside a binary packet (type "J").
func send_json(to: int, msg: Dictionary) -> void:
	send(to, 74, JSON.stringify(msg).to_utf8_buffer())

func _process(_delta: float) -> void:
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
		while ws and ws.get_available_packet_count() > 0:
			var data := ws.get_packet()
			if ws.was_string_packet():
				_on_text(data.get_string_from_utf8())
			elif data.size() >= 2:
				packet.emit(data[0], data[1], data.slice(2))
	elif state == WebSocketPeer.STATE_CLOSED:
		var had_room := slot >= 0
		var opened := _was_open
		_reset()
		if had_room:
			closed.emit("lost")
		elif not opened:
			failed.emit("Couldn't reach the server.")

func _on_text(text: String) -> void:
	var m = JSON.parse_string(text)
	if not (m is Dictionary):
		return
	match str(m.get("type")):
		"room":
			code = str(m.code)
			slot = int(m.slot)
			is_host = bool(m.host)
			players = m.players
			stage = str(m.get("stage", "graveyard"))
			room_changed.emit()
		"start":
			in_game = true
			stage = str(m.stage)
			players = m.players
			started.emit(stage, players)
		"left":
			left.emit(int(m.slot))
		"closed":
			var reason := str(m.get("reason", ""))
			_reset()
			closed.emit(reason)
		"error":
			failed.emit(str(m.get("message", "Something went wrong.")))
