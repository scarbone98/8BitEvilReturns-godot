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
const SNAP_EVERY := 1.0 / 30.0
const INPUT_EVERY := 1.0 / 30.0
# Guests draw a little behind the newest snapshot so they can blend between
# two. How far adapts to the connection: one snapshot gap plus enough to
# cover how unevenly packets have been arriving, between these bounds.
const DELAY_MIN := 0.05
const DELAY_MAX := 0.15
const CHUNK_BYTES := 7000  # the server refuses packets over 8 KB
# Bump when the snapshot format or messages change, so a player on an old page
# (or an old server copy) is told to reload instead of seeing garbage.
const PROTOCOL := 5

var run
var _clock := 0.0
var _seq := 0
var _inv_sent := {}  # seat -> inv_rev last sent
var _sheet_ids: Array = []
var _sheet_index := {}
var _char_ids: Array = []
# Guest: snapshots are buffered with the host's game time and drawn a little
# behind, blending between the two either side, so uneven packet arrival
# doesn't show as stutter.
var _frame_seq := -1
var _building := {}   # the snapshot being assembled from its S/E/X packets
var _frames: Array = []  # complete snapshots, oldest first: {t, heroes, enemies, ops, pickups}
var _render_t := -1.0
var _newest_ms := 0
var _jitter := 0.02      # smoothed gap between how far apart snapshots arrive and how far apart they are
var render_delay := 0.1  # current buffer; follows the jitter

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
		_send_hello()

## Our power-ups and unlocks, for the host to apply to our hero. Resent every
## second until the host confirms: if its game wasn't up yet, the first one
## was lost and we'd play with none of ours.
var _hello_ok := false
var _hello_clock := 0.0

func _send_hello() -> void:
	var unlocked := []
	for id in Db.WEAPONS.keys() + Db.PASSIVES.keys():
		if Meta.content_unlocked(id):
			unlocked.append(id)
	Net.send_json(0, {"t": "hello", "proto": PROTOCOL, "powerups": {} if run.dev else Meta.powerup_stats(),
		"unlocked": unlocked, "view": [run.player.view_size.x, run.player.view_size.y]})

func _process(delta: float) -> void:
	_clock += delta
	if run.is_host():
		if _clock >= SNAP_EVERY:
			_clock = fmod(_clock, SNAP_EVERY)  # keep an even rate across uneven frames
			_send_snapshots()
		return
	if _clock >= INPUT_EVERY:
		_clock = fmod(_clock, INPUT_EVERY)
		_send_input()
	if not _hello_ok:
		_hello_clock += delta
		if _hello_clock >= 1.0:
			_hello_clock = 0.0
			_send_hello()
	_interpolate(delta)

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
	# (fresh damage numbers are cleared once every guest's snapshot is built)
	for seat in run.heroes:
		var h = run.heroes[seat]
		if h.mode == "local":
			continue
		if _inv_sent.get(seat, -1) != h.inv_rev:
			_inv_sent[seat] = h.inv_rev
			Net.send_json(seat, {"t": "inv", "inv": h.inventory()})
		_send_snapshot_to(seat, h)
	run.popups.fresh.clear()

func _send_snapshot_to(seat: int, h) -> void:
	var origin: Vector2 = h.position
	var view: Rect2 = run.view_rect_for(h).grow(80)
	# S: header, heroes, pickups
	var b := StreamPeerBuffer.new()
	b.put_u16(_seq)
	b.put_float(run.time)
	b.put_u16(run.level)
	b.put_u8(int(clampf(run.xp / (run.xp_next * run._xp_scale()), 0.0, 1.0) * 255))
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
	# Damage numbers made since the last snapshot, in their view.
	var nums := []
	for n in run.popups.fresh:
		if view.has_point(n[0]):
			nums.append(n)
			if nums.size() >= 60:
				break
	b.put_u8(nums.size())
	for n in nums:
		b.put_u16(mini(roundi(n[1]), 65535))
		_put_off(b, n[0], origin)
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

const ANCHORED := 64  # on the wire: this op follows a hero; its positions are offsets from them

func _anchor_of(op: Array) -> int:
	var kind := int(op[0]) & 63
	if kind == 0 and op.size() > 8:
		return int(op[8])
	if (kind == 1 or kind == 2) and op.size() > 4:
		return int(op[4])
	return -1

func _put_op(b: StreamPeerBuffer, op: Array, origin: Vector2) -> void:
	var owner := _anchor_of(op)
	var hero = run.heroes.get(owner) if owner >= 0 else null
	if hero:
		b.put_u8(int(op[0]) | ANCHORED)
		b.put_u8(owner)
		origin = hero.position  # positions become offsets from the owner
	else:
		b.put_u8(op[0])  # type, with the ground flag
	match int(op[0]) & 63:
		0:  # sprite
			b.put_u16(int(op[7]) & 0xFFFF if op.size() > 7 else 0)
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
			if int(m.get("proto", 0)) != PROTOCOL:
				Net.send_json(from, {"t": "outdated"})
			Net.send_json(from, {"t": "hello_ok"})
			if h.get_meta("hello", false):
				return  # already applied (it's resent until confirmed)
			h.set_meta("hello", true)
			print("[net] seat %d's power-ups: %s" % [from, m.get("powerups", {})])
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
	var t := b.get_float()
	run.time = t
	run.level = b.get_u16()
	run.xp_next = 1.0
	run.xp = b.get_u8() / 255.0 * run._xp_scale()  # the HUD divides by the scale again
	var me = run.player
	me.hp = b.get_float()
	me.max_hp_override = b.get_float()
	me.kills = b.get_u16()
	me.silver_found = b.get_u16()
	me.dead = b.get_u8() == 1
	_origin = Vector2(b.get_float(), b.get_float())
	var heroes := {}
	var n := b.get_u8()
	for k in n:
		var seat := b.get_u8()
		var pos := Vector2(b.get_float(), b.get_float())
		var flags := b.get_u8()
		var hp_frac := b.get_u8() / 255.0
		b.get_u8()  # hero index (the roster already says)
		heroes[seat] = [pos, flags, hp_frac]
	var pickups := []
	var np := b.get_u16()
	for k in np:
		var code := b.get_u8()
		pickups.append([code, _off(b, _origin)])
	var nn := b.get_u8()
	for k in nn:
		var amount := b.get_u16()
		run.popups.add(_off(b, _origin), amount)
	_nums_seen += nn
	_building = {"t": t, "heroes": heroes, "pickups": pickups, "enemies": [], "ops": []}

func _read_enemies(data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	if b.get_u16() != _frame_seq or _building.is_empty():
		return
	b.get_u8()
	var n := b.get_u16()
	for k in n:
		var u := b.get_u16()
		var ki := b.get_u8()
		var f := b.get_u8()
		var pos := _off(b, _origin)
		var hp_frac := b.get_u8() / 255.0
		_building.enemies.append([u, ki, f, pos, hp_frac])

func _read_shots(data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	if b.get_u16() != _frame_seq or _building.is_empty():
		return
	var last := b.get_u8() == 1
	var n := b.get_u16()
	var ops: Array = _building.ops
	for k in n:
		var raw := b.get_u8()
		var owner := b.get_u8() if raw & ANCHORED else -1
		var base := Vector2.ZERO if owner >= 0 else _origin  # anchored: keep offsets
		raw &= ~ANCHORED
		var op := raw & 63
		match op:
			0:
				var id := b.get_u16()
				var sheet: String = _sheet_ids[mini(b.get_u8(), _sheet_ids.size() - 1)]
				var frame := b.get_u8()
				var pos := _off(b, base)
				var rot := b.get_u8() / 256.0 * TAU
				var sc := Vector2(b.get_8() / 16.0, b.get_u8() / 16.0)
				var o := [raw, sheet, frame, pos, rot, sc, _get_color(b), id]
				if owner >= 0:
					o.append(owner)
				ops.append(o)
			1, 2, 5:
				var pos := _off(b, base)
				var r := b.get_u16() / 4.0
				var o := [raw, pos, r, _get_color(b)]
				if owner >= 0:
					o.append(owner)
				ops.append(o)
			3:
				var m := b.get_u8()
				var pts := PackedVector2Array()
				for i in m:
					pts.append(_off(b, _origin))
				ops.append([raw, pts, _get_color(b)])
			4:
				ops.append([raw, b.get_u8() / 255.0])
	if last:
		# A paused host keeps sending the same moment: replace rather than stack.
		if not _frames.is_empty() and _frames[-1].t >= _building.t:
			_frames[-1] = _building
		else:
			_frames.append(_building)
		# How unevenly snapshots arrive: compare the real gap with the game-time gap.
		var now_ms := Time.get_ticks_msec()
		if _frames.size() >= 2 and _newest_ms > 0:
			var real_gap := (now_ms - _newest_ms) / 1000.0
			var game_gap: float = _frames[-1].t - _frames[-2].t
			if game_gap > 0.0 and real_gap < 1.0:
				var err := absf(real_gap - game_gap)
				# Rise fast on a bad patch, settle slowly once it's calm.
				_jitter = lerpf(_jitter, err, 0.3 if err > _jitter else 0.02)
		_newest_ms = now_ms
		_building = {}
		run.pickups.mirror_apply(_frames[-1].pickups)

## Draws the world render_delay behind the newest snapshot, blending between
## the two snapshots either side of that moment.
func _interpolate(delta: float) -> void:
	if _frames.is_empty():
		return
	var newest: Dictionary = _frames[-1]
	var since := minf((Time.get_ticks_msec() - _newest_ms) / 1000.0, 0.25)
	var want := clampf(SNAP_EVERY + _jitter * 2.5, DELAY_MIN, DELAY_MAX)
	render_delay = lerpf(render_delay, want, minf(1.0, delta * 2.0))
	var target: float = newest.t + since - render_delay
	if _render_t < 0.0 or absf(target - _render_t) > 0.5:
		_render_t = target
	else:
		_render_t = lerpf(_render_t + delta, target, 0.1)
	_render_t = minf(_render_t, newest.t)
	while _frames.size() > 2 and _frames[1].t <= _render_t:
		_frames.pop_front()
	var a: Dictionary = _frames[0]
	var bf: Dictionary = _frames[1] if _frames.size() > 1 else a
	var k := 1.0 if bf.t <= a.t else clampf((_render_t - a.t) / (bf.t - a.t), 0.0, 1.0)
	# Enemies
	var prev := {}
	for e in a.enemies:
		prev[e[0]] = e
	var list := []
	for e in bf.enemies:
		var p = prev.get(e[0])
		list.append([e[0], e[1], e[2], p[3].lerp(e[3], k) if p != null else e[3], e[4]])
	run.enemies.mirror_set(list, delta)
	if run.autoplay:
		_measure(list)
	# Other heroes
	for seat in bf.heroes:
		var h = run.heroes.get(seat)
		if h == null or h == run.player:
			continue
		var cur: Array = bf.heroes[seat]
		var was = a.heroes.get(seat)
		h.position = was[0].lerp(cur[0], k) if was != null else cur[0]
		var flags: int = cur[1]
		h.moving = flags & 1 != 0
		h.facing = Vector2.LEFT if flags & 2 else Vector2.RIGHT
		h.dead = flags & 4 != 0
		h._hurt_flash = 0.1 if flags & 8 else 0.0
		h._invuln = 0.1 if flags & 16 else 0.0
		h.max_hp_override = 100.0
		h.hp = cur[2] * 100.0
	# Shots: sprites with an id glide between snapshots; effects that follow a
	# hero are pinned to that hero as drawn here (our own: where we really are).
	var prev_ops := {}
	for op in a.ops:
		if (int(op[0]) & 63) == 0 and op[7] != 0:
			prev_ops[op[7]] = op
	var ops := []
	for op in bf.ops:
		var kind := int(op[0]) & 63
		var owner := _anchor_of(op)
		var base := Vector2.ZERO
		if owner >= 0:
			var h = run.heroes.get(owner)
			if h == null:
				continue
			base = h.position
		if kind == 0:
			var o: Array = op.slice(0, 8)
			if op[7] != 0 and prev_ops.has(op[7]) and _anchor_of(prev_ops[op[7]]) == owner:
				var p: Array = prev_ops[op[7]]
				o[3] = p[3].lerp(op[3], k)
				o[4] = lerp_angle(p[4], op[4], k)
			o[3] += base
			ops.append(o)
		elif owner >= 0:
			var o: Array = op.slice(0, 4)
			o[1] += base
			ops.append(o)
		else:
			ops.append(op)
	run.shots.remote_ops = ops
	run.shots.queue_redraw()
	if run.autoplay:
		for op in ops:
			if (int(op[0]) & 63) == 2:  # a pulse ring: is it centred on its owner here?
				_ring_seen += 1
				_ring_off = maxf(_ring_off, (op[1] - run.player.position).length())

# Test bots: the biggest frame-to-frame jump of any enemy, reported every 10s.
var _nums_seen := 0
var _ring_seen := 0
var _ring_off := 0.0
var _last_pos := {}
var _max_jump := 0.0
var _jump_clock := 0.0

func _measure(list: Array) -> void:
	var now := {}
	for e in list:
		now[e[0]] = e[3]
		if _last_pos.has(e[0]):
			_max_jump = maxf(_max_jump, (e[3] - _last_pos[e[0]]).length())
	_last_pos = now
	_jump_clock += get_process_delta_time()
	if _jump_clock >= 10.0:
		print("[smooth] biggest enemy jump between frames: %.1f px, buffer %d ms; pulse rings drawn %d, furthest from our hero %.1f px; damage numbers received %d" % [_max_jump, roundi(render_delay * 1000.0), _ring_seen, _ring_off, _nums_seen])
		_nums_seen = 0
		_ring_seen = 0
		_ring_off = 0.0
		_jump_clock = 0.0
		_max_jump = 0.0

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
		"outdated":
			run.hud.banner("A new version is out: reload the page")
		"hello_ok":
			_hello_ok = true
		"over":
			var r: Dictionary = m.get("summary", {})
			run.show_results(r)
