extends Node
## Co-op traffic for a run. The host simulates; guests draw.
##
## Host -> each guest, ~15 times a second, a snapshot of what that guest can see:
##   S  time, team level/xp, their own hp/kills/silver, every hero, pickups
##   E  enemies (one or more chunks)
##   X  shot drawing ops (one or more chunks; the last one completes the frame)
## Guest -> host, ~20 times a second:
##   I  where their hero is, which way it faces, whether it's moving
## Either way, small JSON messages (J): hello, inv, levelup, pick, resume,
## chest, toast, over.
## Positions in snapshots are 16-bit offsets from the guest's own hero.

const K_SNAP := 83   # S
const K_ENEMY := 69  # E
const K_SHOTS := 88  # X
const K_INPUT := 73  # I
const K_JSON := 74   # J
const SNAP_EVERY := 1.0 / 15.0
const INPUT_EVERY := 1.0 / 20.0
const CHUNK_BYTES := 7000  # the server refuses packets over 8 KB

var run
var _clock := 0.0
var _seq := 0
var _inv_sent := {}  # seat -> inv_rev last sent
var _sheet_ids: Array = []
var _sheet_index := {}
var _char_ids: Array = []
# Guest: the frame being assembled
var _frame_seq := -1
var _frame_enemies: Array = []
var _frame_ops: Array = []
var _frame_pickups: Array = []

func _ready() -> void:
	_sheet_ids = Db.SHEETS.keys()
	_sheet_ids.sort()
	for i in _sheet_ids.size():
		_sheet_index[_sheet_ids[i]] = i
	_char_ids = Db.CHARACTERS.keys()
	Net.packet.connect(_on_packet)
	Net.left.connect(func(seat): run.remove_hero(seat))
	Net.closed.connect(func(reason): run.connection_lost(reason))
	Net.connection_changed.connect(run.on_connection)
	if run.is_host():
		Net.away.connect(run.on_peer_away)
		Net.back.connect(func(seat):
			_inv_sent.erase(seat)  # resend their inventory
			run.on_peer_back(seat))
	else:
		Net.away.connect(func(seat):
			if seat == 0:
				run.hud.banner("Host reconnecting..."))
		Net.back.connect(func(seat):
			if seat == 0:
				run.hud.banner(""))
	if run.is_guest():
		var unlocked := []
		for id in Db.WEAPONS.keys() + Db.PASSIVES.keys():
			if Meta.content_unlocked(id):
				unlocked.append(id)
		Net.send_json(0, {"t": "hello", "powerups": {} if run.dev else Meta.powerup_stats(),
			"unlocked": unlocked, "view": [run.player.view_size.x, run.player.view_size.y]})

func _process(delta: float) -> void:
	_clock += delta
	if run.is_host():
		if _clock >= SNAP_EVERY:
			_clock = 0.0
			_send_snapshots()
	elif _clock >= INPUT_EVERY:
		_clock = 0.0
		_send_input()

# ---------------------------------------------------------------- Host

func send_levelup(seat: int, options: Array, level: int) -> void:
	Net.send_json(seat, {"t": "levelup", "opts": options, "level": level})

func send_resume() -> void:
	Net.send_json(Net.BROADCAST, {"t": "resume"})

func send_chest(seat: int, gained: Array) -> void:
	Net.send_json(seat, {"t": "chest", "gained": gained})

func send_toast(seat: int, text: String) -> void:
	Net.send_json(seat, {"t": "toast", "text": text})

func send_over(seat: int, summary: Dictionary) -> void:
	Net.send_json(seat, {"t": "over", "summary": summary})

func _send_snapshots() -> void:
	_seq = (_seq + 1) & 0xFFFF
	for seat in run.heroes:
		var h = run.heroes[seat]
		if h == run.player:
			continue
		if _inv_sent.get(seat, -1) != h.inv_rev:
			_inv_sent[seat] = h.inv_rev
			Net.send_json(seat, {"t": "inv", "inv": h.inventory()})
		_send_snapshot_to(seat, h)

func _send_snapshot_to(seat: int, h) -> void:
	var origin: Vector2 = h.position
	var view: Rect2 = run.view_rect_for(h).grow(80)
	# S: header, heroes, pickups
	var b := StreamPeerBuffer.new()
	b.put_u16(_seq)
	b.put_float(run.time)
	b.put_u16(run.level)
	b.put_u8(int(clampf(run.xp / run.xp_next, 0.0, 1.0) * 255))
	b.put_float(h.hp)
	b.put_float(h.max_hp())
	b.put_u16(mini(h.kills, 65535))
	b.put_u16(mini(h.silver_found, 65535))
	b.put_u8(1 if h.dead else 0)
	b.put_float(origin.x)
	b.put_float(origin.y)
	b.put_u8(run.heroes.size())
	for s in run.heroes:
		var o = run.heroes[s]
		b.put_u8(s)
		b.put_float(o.position.x)
		b.put_float(o.position.y)
		var flags := 0
		if o.moving: flags |= 1
		if o.facing.x < 0: flags |= 2
		if o.dead: flags |= 4
		if o._hurt_flash > 0.0: flags |= 8
		if o._invuln > 0.0: flags |= 16
		b.put_u8(flags)
		b.put_u8(int(clampf(o.hp / maxf(o.max_hp(), 1.0), 0.0, 1.0) * 255))
		b.put_u8(_char_ids.find(o.char_id))
	var picks := []
	for p in run.pickups.list:
		if view.has_point(p.pos):
			picks.append(p)
			if picks.size() >= 400:
				break
	b.put_u16(picks.size())
	for p in picks:
		b.put_u8(run.pickups.mirror_code(p))
		_put_off(b, p.pos, origin)
	Net.send(seat, K_SNAP, b.data_array)

	# E: enemies in view, chunked
	var e = run.enemies
	var chunk := StreamPeerBuffer.new()
	var count := 0
	var first := true
	var rows := StreamPeerBuffer.new()
	for i in e.count():
		if e.hp[i] <= 0.0 or not view.has_point(e.pos[i]):
			continue
		rows.put_u16(e.uid[i] & 0xFFFF)
		rows.put_u8(e.kidx[i])
		var f := 0
		if e.boss[i] == 1: f |= 1
		if e.flash[i] > 0.0: f |= 2
		if e.frozen > 0.0: f |= 4
		rows.put_u8(f)
		_put_off(rows, e.pos[i], origin)
		rows.put_u8(int(clampf(e.hp[i] / maxf(e.max_hp[i], 1.0), 0.0, 1.0) * 255))
		count += 1
		if rows.get_size() >= CHUNK_BYTES:
			_send_chunk(seat, K_ENEMY, 1 if first else 0, count, rows)
			first = false
			rows = StreamPeerBuffer.new()
			count = 0
	_send_chunk(seat, K_ENEMY, 1 if first else 0, count, rows)

	# X: shot ops in view, chunked; the last chunk completes the frame
	rows = StreamPeerBuffer.new()
	count = 0
	for op in run.shots.ops(run.view_rect_for(h)):
		_put_op(rows, op, origin)
		count += 1
		if rows.get_size() >= CHUNK_BYTES:
			_send_chunk(seat, K_SHOTS, 0, count, rows)
			rows = StreamPeerBuffer.new()
			count = 0
	_send_chunk(seat, K_SHOTS, 1, count, rows)

func _send_chunk(seat: int, kind: int, flag: int, count: int, rows: StreamPeerBuffer) -> void:
	var b := StreamPeerBuffer.new()
	b.put_u16(_seq)
	b.put_u8(flag)
	b.put_u16(count)
	b.put_data(rows.data_array)
	Net.send(seat, kind, b.data_array)

func _put_off(b: StreamPeerBuffer, p: Vector2, origin: Vector2) -> void:
	var d := p - origin
	b.put_16(int(clampf(d.x, -32000, 32000)))
	b.put_16(int(clampf(d.y, -32000, 32000)))

func _put_color(b: StreamPeerBuffer, c: Color) -> void:
	b.put_u8(c.r8)
	b.put_u8(c.g8)
	b.put_u8(c.b8)
	b.put_u8(c.a8)

func _put_op(b: StreamPeerBuffer, op: Array, origin: Vector2) -> void:
	b.put_u8(op[0])
	match op[0]:
		0:  # sprite
			b.put_u8(_sheet_index.get(op[1], 0))
			b.put_u8(int(op[2]) & 0xFF)
			_put_off(b, op[3], origin)
			b.put_u8(int(fposmod(op[4], TAU) / TAU * 256.0) & 0xFF)
			var sc: Vector2 = op[5]
			b.put_8(int(clampf(sc.x * 16.0, -127, 127)))
			b.put_u8(int(clampf(sc.y * 16.0, 0, 255)))
			_put_color(b, op[6])
		1, 2, 5:  # circle, ring, puddle
			_put_off(b, op[1], origin)
			b.put_u16(int(clampf(op[2] * 4.0, 0, 65535)))
			_put_color(b, op[3])
		3:  # zap
			var pts: PackedVector2Array = op[1]
			var n := mini(pts.size(), 24)
			b.put_u8(n)
			for k in n:
				_put_off(b, pts[k], origin)
			_put_color(b, op[2])
		4:  # flash
			b.put_u8(int(clampf(op[1], 0.0, 1.0) * 255))

## Packets from guests (host) or from the host (guest).
func _on_packet(from: int, kind: int, data: PackedByteArray) -> void:
	if run.ended and kind != K_JSON:
		return
	if run.is_host():
		match kind:
			K_INPUT:
				var h = run.heroes.get(from)
				if h == null or data.size() < 11:
					return
				var b := StreamPeerBuffer.new()
				b.data_array = data
				h.net_target = Vector2(b.get_float(), b.get_float())
				h.facing = Vector2(b.get_8(), b.get_8()).normalized()
				if h.facing == Vector2.ZERO:
					h.facing = Vector2.RIGHT
				h.moving = b.get_u8() == 1
			K_JSON:
				_host_json(from, _json(data))
	else:
		match kind:
			K_SNAP:
				_read_snapshot(data)
			K_ENEMY:
				_read_enemies(data)
			K_SHOTS:
				_read_shots(data)
			K_JSON:
				_guest_json(_json(data))

func _json(data: PackedByteArray) -> Dictionary:
	var m = JSON.parse_string(data.get_string_from_utf8())
	return m if m is Dictionary else {}

func _host_json(from: int, m: Dictionary) -> void:
	var h = run.heroes.get(from)
	if h == null:
		return
	match str(m.get("t")):
		"hello":
			# Their own power-ups and unlocks apply to their hero.
			var bonus := {}
			var p = m.get("powerups", {})
			if p is Dictionary:
				for k in p:
					if _stat_ok(k):
						bonus[k] = float(p[k])
			h.bonus = bonus
			h.recalc_stats()
			h.hp = h.max_hp()
			h.revivals = int(h.stats.revival)
			var unlocked: Array = m.get("unlocked", []) if m.get("unlocked") is Array else []
			h.allowed = func(id): return not Db.is_locked_content(id) or unlocked.has(id)
			var v = m.get("view")
			if v is Array and v.size() == 2:
				h.view_size = Vector2(clampf(float(v[0]), 160, 640), clampf(float(v[1]), 240, 900))
		"pick":
			run.on_remote_pick(from, str(m.get("id", "")))

func _stat_ok(k) -> bool:
	return k is String and run.player.STAT_DEFAULTS.has(k)

# ---------------------------------------------------------------- Guest

func _send_input() -> void:
	var h = run.player
	var b := StreamPeerBuffer.new()
	b.put_float(h.position.x)
	b.put_float(h.position.y)
	b.put_8(int(h.facing.x * 127))
	b.put_8(int(h.facing.y * 127))
	b.put_u8(1 if h.moving else 0)
	Net.send(0, K_INPUT, b.data_array)

func _off(b: StreamPeerBuffer, origin: Vector2) -> Vector2:
	return origin + Vector2(b.get_16(), b.get_16())

var _origin := Vector2.ZERO

func _read_snapshot(data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	_frame_seq = b.get_u16()
	run.time = b.get_float()
	run.level = b.get_u16()
	run.xp_next = 1.0
	run.xp = b.get_u8() / 255.0
	var me = run.player
	me.hp = b.get_float()
	me.max_hp_override = b.get_float()
	me.kills = b.get_u16()
	me.silver_found = b.get_u16()
	me.dead = b.get_u8() == 1
	_origin = Vector2(b.get_float(), b.get_float())
	var n := b.get_u8()
	for k in n:
		var seat := b.get_u8()
		var pos := Vector2(b.get_float(), b.get_float())
		var flags := b.get_u8()
		var hp_frac := b.get_u8() / 255.0
		var ci := b.get_u8()
		var h = run.heroes.get(seat)
		if h == null or h == me:
			continue
		h.position = pos
		h.moving = flags & 1 != 0
		h.facing = Vector2.LEFT if flags & 2 else Vector2.RIGHT
		h.dead = flags & 4 != 0
		h._hurt_flash = 0.1 if flags & 8 else 0.0
		h._invuln = 0.1 if flags & 16 else 0.0
		h.max_hp_override = 100.0
		h.hp = hp_frac * 100.0
	_frame_pickups = []
	var np := b.get_u16()
	for k in np:
		var code := b.get_u8()
		_frame_pickups.append([code, _off(b, _origin)])
	_frame_enemies = []
	_frame_ops = []

func _read_enemies(data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	if b.get_u16() != _frame_seq:
		return
	b.get_u8()
	var n := b.get_u16()
	for k in n:
		var u := b.get_u16()
		var ki := b.get_u8()
		var f := b.get_u8()
		var pos := _off(b, _origin)
		var hp_frac := b.get_u8() / 255.0
		_frame_enemies.append([u, ki, f, pos, hp_frac])

func _read_shots(data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	if b.get_u16() != _frame_seq:
		return
	var last := b.get_u8() == 1
	var n := b.get_u16()
	for k in n:
		var op := b.get_u8()
		match op:
			0:
				var sheet: String = _sheet_ids[mini(b.get_u8(), _sheet_ids.size() - 1)]
				var frame := b.get_u8()
				var pos := _off(b, _origin)
				var rot := b.get_u8() / 256.0 * TAU
				var sc := Vector2(b.get_8() / 16.0, b.get_u8() / 16.0)
				_frame_ops.append([0, sheet, frame, pos, rot, sc, _get_color(b)])
			1, 2, 5:
				var pos := _off(b, _origin)
				var r := b.get_u16() / 4.0
				_frame_ops.append([op, pos, r, _get_color(b)])
			3:
				var m := b.get_u8()
				var pts := PackedVector2Array()
				for i in m:
					pts.append(_off(b, _origin))
				_frame_ops.append([3, pts, _get_color(b)])
			4:
				_frame_ops.append([4, b.get_u8() / 255.0])
	if last:
		run.enemies.mirror_apply(_frame_enemies)
		run.pickups.mirror_apply(_frame_pickups)
		run.shots.remote_ops = _frame_ops
		run.shots.queue_redraw()

func _get_color(b: StreamPeerBuffer) -> Color:
	return Color8(b.get_u8(), b.get_u8(), b.get_u8(), b.get_u8())

func _guest_json(m: Dictionary) -> void:
	match str(m.get("t")):
		"inv":
			run.player.set_inventory(m.get("inv", {}))
		"levelup":
			var opts: Array = m.get("opts", [])
			run.show_level_up(opts, func(id):
				Net.send_json(0, {"t": "pick", "id": id})
				run._show_waiting())
		"resume":
			run._set_modal(null)
		"chest":
			run.show_chest_note(m.get("gained", []))
		"toast":
			run.hud.toast(str(m.get("text", "")), UI.RED)
		"over":
			var r: Dictionary = m.get("summary", {})
			run.show_results(r)
