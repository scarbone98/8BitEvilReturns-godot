extends Node2D
## Every live projectile / effect, stored as small dictionaries and updated by
## type. A new weapon behaviour adds a spawn function here, a branch in step()
## and (if it isn't a plain sprite) a branch in _draw().

var run
var list: Array[Dictionary] = []
var _next_id := 1  # every shot gets an id so guests can follow it between snapshots

func _add(w: Weapon, type: String, extra: Dictionary) -> Dictionary:
	var s := {
		"w": w, "type": type, "pos": w.player.position, "vel": Vector2.ZERO, "t": 0.0,
		"life": 1.0, "damage": w.damage(), "pierce": w.pierce(), "hits": {},
		"rehit": -1.0, "radius": 6.0, "sheet": w.def.get("sheet", ""), "rot": 0.0,
		"scale": w.area(), "tint": w.tint(), "delay": 0.0, "id": _next_id,
	}
	_next_id = _next_id % 65535 + 1
	s.merge(extra, true)
	list.append(s)
	return s

func clear_for(w: Weapon) -> void:
	list = list.filter(func(s): return s.w != w or s.type == "fx" or s.type == "zap")

func count_for(w: Weapon) -> int:
	var n := 0
	for s in list:
		if s.w == w and s.type != "fx" and s.type != "zap":
			n += 1
	return n

# ---------------------------------------------------------------- Spawners

func bullet(w: Weapon, from: Vector2, dir: Vector2) -> void:
	var spd := w.speed()
	_add(w, "bullet", {"pos": from, "vel": dir * spd, "life": w.raw("range") / maxf(spd, 1.0),
		"rot": dir.angle() + w.def.get("rot_offset", 0.0), "radius": 5.0 * w.area(),
		"explode": w.def.get("explode", 0.0) * w.area(), "scale": w.def.get("shot_scale", 1.0)})

## A whip lash: a long, flat strip beside the hero. side is -1/1, row stacks
## extra lashes above (-) and below (+).
func slash(w: Weapon, side: float, row: float, delay: float) -> void:
	var sh := Db.sheet(w.def.sheet)
	var hw := 28.0 * w.area()
	var hh := 10.0 * w.area()
	_add(w, "slash", {"side": side, "life": float(sh.frames) / sh.fps, "delay": delay, "pierce": -1,
		"hw": hw, "hh": hh, "off": Vector2(side * (hw + 2.0), -8.0 + row * (hh * 2.0 + 2.0))})

func boomerang(w: Weapon, dir: Vector2) -> void:
	_add(w, "boomerang", {"vel": dir * w.speed(), "life": 6.0, "pierce": -1, "rehit": 0.5,
		"radius": 7.0 * w.area(), "out": w.raw("range")})

## Instant hit at a point (lightning, hands, tentacles), or after a warning
## crosshair if the weapon has `warn`.
func strike(w: Weapon, at: Vector2) -> void:
	var warn: float = w.def.get("warn", 0.0)
	if warn > 0.0:
		_add(w, "warn", {"pos": at, "life": warn, "sheet": "crosshair", "scale": 1.0})
		return
	_strike_now(w, at)

func _strike_now(w: Weapon, at: Vector2) -> void:
	var r: float = w.def.get("strike_radius", 22.0) * w.area()
	for i in run.enemies.query_circle(at, r):
		hit(w, i, w.damage(), at, w.raw("knockback"))
	var sh := Db.sheet(w.def.sheet)
	_add(w, "fx", {"pos": at, "life": float(sh.frames) / sh.fps,
		"anchor": "center" if w.def.get("centered", false) else "bottom",
		"scale": w.def.get("sheet_scale", 1.0) * w.area()})

func orbit(w: Weapon, angle: float) -> void:
	_add(w, "orbit", {"angle": angle, "life": w.duration(), "pierce": -1, "rehit": 0.4,
		"radius": 9.0 * w.area(), "orbit": w.def.get("orbit_radius", 36.0) * w.area(),
		"scale": w.area() * w.def.get("shot_scale", 1.0)})

func flask(w: Weapon, target: Vector2) -> void:
	_add(w, "flask", {"from": w.player.position, "to": target, "life": 0.5,
		"scale": 1.0 if not w.def.has("explode") else 0.9})

func pool(w: Weapon, at: Vector2, sheet: String, radius: float) -> void:
	_add(w, "pool", {"pos": at, "life": w.duration(), "pierce": -1,
		"rehit": w.def.get("tick", 0.35), "radius": radius * w.area(), "sheet": sheet})

func bat(w: Weapon, from: Vector2) -> void:
	_add(w, "bat", {"pos": from, "life": w.duration(), "pierce": -1, "rehit": w.def.get("bite", 0.4),
		"radius": 7.0, "target": -1, "wander": randf() * TAU, "scale": 0.5})

func wisp(w: Weapon, from: Vector2, dir: Vector2, sheet := "") -> void:
	_add(w, "wisp", {"pos": from, "vel": dir * w.speed(), "life": w.duration(), "radius": 7.0,
		"target": -1, "scale": 0.5 if w.def.sheet == "wisp" or sheet == "wisp" else 1.0,
		"sheet": sheet if sheet != "" else w.def.sheet})

func aura(w: Weapon) -> void:
	_add(w, "aura", {"life": INF, "pierce": -1, "rehit": w.def.get("tick", 0.5) * w.cooldown()})

func nova(w: Weapon) -> void:
	_add(w, "nova", {"life": 0.45, "pierce": -1, "max_r": w.raw("range") * w.area(), "radius": 0.0})

func bounce(w: Weapon, dir: Vector2) -> void:
	_add(w, "bounce", {"vel": dir * w.speed(), "life": w.duration(), "pierce": -1, "rehit": 0.4,
		"radius": (8.0 if w.def.get("retarget", false) else 6.0) * w.area()})

func turret(w: Weapon, at: Vector2) -> void:
	_add(w, "turret", {"pos": run.obstacles.free_spot(at, 6.0), "life": w.duration(), "next_zap": 0.0})

func zap(w: Weapon, points: PackedVector2Array) -> void:
	_add(w, "zap", {"points": points, "life": 0.18})

func flash(w: Weapon) -> void:
	# The screen flash fades in 0.35s; a sheet (holy cross, judgment sword)
	# plays through once above the hero, so the flash lives that long.
	var life := 0.35
	if w.def.has("sheet"):
		var sh := Db.sheet(w.def.sheet)
		life = maxf(life, float(sh.frames) / sh.fps)
	_add(w, "flash", {"life": life})

func explosion(w: Weapon, at: Vector2, r: float, dmg: float) -> void:
	for i in run.enemies.query_circle(at, r):
		hit(w, i, dmg * 0.6, at, 30.0)
	_add(w, "fx", {"pos": at, "life": 0.35, "sheet": "fireball_explosion", "scale": r / 12.0})

# ---------------------------------------------------------------- Update

func hit(w: Weapon, i: int, dmg: float, from: Vector2, kb: float) -> void:
	if run.is_guest():
		# Our own predicted shots only look the part; the host does the damage.
		if i >= 0 and i < run.enemies.flash.size():
			run.enemies.flash[i] = 0.12
			if run.autoplay and run.netsync:
				run.netsync.note_local_hit(run.enemies.uid[i])
		return
	var killed: bool = run.enemies.hurt(i, dmg, from, kb, w.player.slot)
	var ls: float = w.def.get("lifesteal", 0.0)
	if ls > 0.0:
		w.player.heal(dmg * ls)
	if killed and randf() < w.def.get("drops_silver", 0.0):
		run.pickups.drop("silver", from)

## Damages overlapping enemies; returns false once the shot's pierce runs out.
func _touch(s: Dictionary, r: float) -> bool:
	var e = run.enemies
	for i in e.query_circle(s.pos, r):
		var u: int = e.uid[i]
		if s.hits.has(u):
			if s.rehit < 0.0 or s.t - s.hits[u] < s.rehit:
				continue
		s.hits[u] = s.t
		hit(s.w, i, s.damage, s.pos, s.w.raw("knockback"))
		if s.get("explode", 0.0) > 0.0:
			explosion(s.w, s.pos, s.explode, s.damage)
		if s.pierce > 0:
			s.pierce -= 1
			if s.pierce == 0:
				return false
	return true

## Like _touch, for a rectangle centred on the shot (half-width hw, half-height hh).
func _touch_rect(s: Dictionary, hw: float, hh: float) -> void:
	var e = run.enemies
	for i in e.query_circle(s.pos, Vector2(hw, hh).length()):
		var d: Vector2 = e.pos[i] - s.pos
		var r: float = e.radius[i]
		if absf(d.x) > hw + r or absf(d.y) > hh + r:
			continue
		var u: int = e.uid[i]
		if s.hits.has(u):
			continue
		s.hits[u] = s.t
		hit(s.w, i, s.damage, s.w.player.position, s.w.raw("knockback"))

func _seek(s: Dictionary, delta: float, reach: float, turn: float) -> void:
	var e = run.enemies
	var ti: int = e.index_of_uid(s.target) if s.target != -1 else -1
	if ti == -1:
		var n: int = e.nearest(s.pos, reach)
		s.target = e.uid[n] if n != -1 else -1
		ti = n
	if ti != -1:
		s.vel = s.vel.lerp((e.pos[ti] - s.pos).normalized() * s.w.speed(), minf(1.0, delta * turn))

func step(delta: float) -> void:
	var e = run.enemies
	var i := list.size() - 1
	while i >= 0:
		var s: Dictionary = list[i]
		if s.delay > 0.0:
			s.delay -= delta
			i -= 1
			continue
		s.t += delta
		var owner_pos: Vector2 = s.w.player.position
		var alive: bool = s.t < s.life
		match s.type:
			"bullet":
				s.pos += s.vel * delta
				if alive:
					alive = _touch(s, s.radius)
				if not alive and s.t >= s.life and s.get("explode", 0.0) > 0.0:
					explosion(s.w, s.pos, s.explode, s.damage)
			"slash":
				s.pos = owner_pos + s.off
				if s.t < 0.15:
					_touch_rect(s, s.hw, s.hh)
			"boomerang":
				s.rot += delta * 18.0
				var travelled: float = s.get("dist", 0.0) + s.vel.length() * delta
				s.dist = travelled
				if not s.get("back", false):
					if travelled >= s.out:
						s.back = true
				else:
					var to: Vector2 = owner_pos - s.pos
					s.vel = s.vel.lerp(to.normalized() * s.w.speed() * 1.3, minf(1.0, delta * 6.0))
					if to.length() < 8.0:
						alive = false
				s.pos += s.vel * delta
				_touch(s, s.radius)
			"orbit":
				s.angle += deg_to_rad(s.w.speed() * 4.0) * delta
				s.pos = owner_pos + Vector2.RIGHT.rotated(s.angle) * s.orbit
				s.rot = 0.0 if s.w.def.get("upright", false) else s.angle + s.w.def.get("rot_offset", 0.0)
				_touch(s, s.radius)
			"flask":
				var k: float = clampf(s.t / s.life, 0.0, 1.0)
				s.pos = s.from.lerp(s.to, k) + Vector2(0, -sin(k * PI) * 30.0)
				s.rot += delta * 12.0
				if not alive:
					if s.w.def.has("explode"):
						explosion(s.w, s.to, float(s.w.def.explode) * s.w.area(), s.damage / 0.6)
					else:
						pool(s.w, s.to, s.w.def.pool_sheet, 14.0)
			"pool":
				_touch(s, s.radius)
			"bat":
				var ti: int = e.index_of_uid(s.target) if s.target != -1 else -1
				if ti == -1:
					var n: int = e.nearest(s.pos, 140.0)
					s.target = e.uid[n] if n != -1 else -1
					ti = n
				var goal: Vector2
				if ti != -1:
					goal = e.pos[ti]
				else:
					s.wander += delta * 3.0
					goal = owner_pos + Vector2.RIGHT.rotated(s.wander) * 26.0
				s.vel = s.vel.lerp((goal - s.pos).normalized() * s.w.speed(), minf(1.0, delta * 5.0))
				s.pos += s.vel * delta
				_touch(s, s.radius)
			"wisp":
				_seek(s, delta, 220.0, 4.0)
				s.pos += s.vel * delta
				s.rot += delta * 6.0 if s.sheet == "skull_icon" else 0.0
				if alive:
					alive = _touch(s, s.radius)
			"aura":
				s.pos = owner_pos
				s.radius = s.w.raw("range") * s.w.area()
				s.damage = s.w.damage()
				_touch(s, s.radius)
			"nova":
				s.pos = owner_pos
				s.radius = s.max_r * clampf(s.t / s.life, 0.0, 1.0)
				_touch(s, s.radius)
			"bounce":
				s.pos += s.vel * delta
				var view: Rect2 = run.view_rect_for(s.w.player)
				var bounced := false
				if s.pos.x < view.position.x or s.pos.x > view.end.x:
					s.vel.x = -s.vel.x
					s.pos.x = clampf(s.pos.x, view.position.x, view.end.x)
					bounced = true
				if s.pos.y < view.position.y or s.pos.y > view.end.y:
					s.vel.y = -s.vel.y
					s.pos.y = clampf(s.pos.y, view.position.y, view.end.y)
					bounced = true
				if s.w.def.get("retarget", false):
					# Off the wall, straight at the nearest monster.
					if bounced:
						var n: int = e.nearest(s.pos, 400.0)
						if n != -1:
							s.vel = (e.pos[n] - s.pos).normalized() * s.vel.length()
					s.rot = s.vel.angle() + s.w.def.get("rot_offset", 0.0)
				elif not s.w.def.get("upright", false):
					s.rot += delta * 10.0
				_touch(s, s.radius)
			"turret":
				s.next_zap -= delta
				if s.next_zap <= 0.0:
					var n: int = e.nearest(s.pos, s.w.raw("range") * s.w.area())
					if n != -1:
						s.next_zap = s.w.def.get("zap", 0.6) * s.w.cooldown() / maxf(s.w.raw("cooldown"), 0.01)
						var top: Vector2 = s.pos + Vector2(0, -26)
						hit(s.w, n, s.w.damage(), top, 10.0)
						zap(s.w, PackedVector2Array([top, e.pos[n]]))
			"warn":
				if not alive:
					_strike_now(s.w, s.pos)
			"fx", "zap", "flash":
				pass
		if not alive:
			list.remove_at(i)
		i -= 1
	queue_redraw()

# ---------------------------------------------------------------- Drawing
# Drawing goes through "ops" so the host can send guests exactly what it draws:
#   [OP_SPRITE, sheet, frame, centre, rotation, scale (x<0 = flipped), colour]
#   [OP_CIRCLE, centre, radius, colour]          a filled aura with a rim
#   [OP_RING, centre, radius, colour]            an expanding nova ring
#   [OP_ZAP, points, colour]                     chain / lamp lightning
#   [OP_FLASH, alpha]                            the whole screen flashes
#   [OP_PUDDLE, centre, radius, colour]          a blood puddle

const OP_SPRITE := 0
const OP_CIRCLE := 1
const OP_RING := 2
const OP_ZAP := 3
const OP_FLASH := 4
const OP_PUDDLE := 5
const GROUND := 128  # flag on an op's type: drawn on the ground, under the monsters
# Ops that follow a hero (aura, pulse, orbiting weapons, lashes) also carry the
# owner's seat as their last element, so a guest can pin them to that hero as
# drawn on its own screen instead of where the host last saw it.

var remote_ops: Array = []  # guests: the latest ops from the host

## Tags for the ops ops() just built, same order: [owner seat or -1,
## follows its owner (aura, orbit...), from a weapon guests draw themselves].
var last_tags: Array = []
var _cur: Dictionary  # the shot whose ops are being built

func _emit(out: Array, op: Array, anchored := false) -> void:
	out.append(op)
	var w = _cur.get("w")
	var owner: int = w.player.slot if w else -1
	last_tags.append([owner, anchored, w != null and Db.is_predicted(w.def)])

func _sprite(out: Array, sheet: String, frame: int, center: Vector2, rot: float, sc: Vector2, col: Color, ground := false, id := 0, anchored := false) -> void:
	_emit(out, [OP_SPRITE | (GROUND if ground else 0), sheet, frame, center, rot, sc, col, id], anchored)

## Everything to draw inside `view`, as ops (tags in last_tags).
func ops(view: Rect2) -> Array:
	var out := []
	last_tags = []
	var cull := view.grow(64)
	for s in list:
		if s.delay > 0.0:
			continue
		_cur = s
		var col: Color = s.tint
		match s.type:
			"aura":
				_emit(out, [OP_CIRCLE | GROUND, s.pos, s.radius, Color(s.w.def.get("color", Color.WHITE), 0.45 + sin(s.t * 6.0) * 0.15)], true)
				continue
			"nova":
				_emit(out, [OP_RING, s.pos, s.radius, Color(s.w.def.get("color", Color.WHITE), 1.0 - s.t / s.life)], true)
				continue
			"zap":
				_emit(out, [OP_ZAP, s.points, Color(s.w.def.get("color", Color(0.75, 0.9, 1.0)), 1.0 - s.t / s.life)])
				continue
			"flash":
				var a: float = maxf(0.0, 1.0 - s.t / 0.35)
				if a > 0.0:
					_emit(out, [OP_FLASH, 0.35 * a])
				if s.w.def.has("sheet"):
					var fsh := Db.sheet(s.w.def.sheet)
					var f := mini(int(s.t * fsh.fps), int(fsh.frames) - 1)
					_sprite(out, s.w.def.sheet, f, s.w.player.position + Vector2(0, -32), 0.0, Vector2(0.5, 0.5), col, false, s.id, true)
				continue
		if s.sheet == "" or not cull.has_point(s.pos):
			continue
		var sh := Db.sheet(s.sheet)
		var frame := int(s.t * sh.fps) % int(sh.frames)
		var sc: float = s.scale
		match s.type:
			"slash":
				# The claw marks twice across the strip, mirrored on the left.
				frame = mini(int(s.t / s.life * sh.frames), sh.frames - 1)
				var step: float = s.hw
				for j in [-0.5, 0.5]:
					_sprite(out, s.sheet, frame, s.pos + Vector2(step * j, 0), 0.0, Vector2(sc * s.side, sc), col, false, s.id * 2 + int(j > 0.0), true)
			"fx":
				# One-shot animations play through exactly once.
				frame = mini(int(s.t / s.life * sh.frames), sh.frames - 1)
				var center: Vector2 = s.pos
				if s.get("anchor") == "bottom":
					center += Vector2(0, -sh._h * sc * 0.5 + 6)
				_sprite(out, s.sheet, frame, center, 0.0, Vector2(sc, sc), col, false, s.id)
			"warn":
				var pulse: float = (1.0 + sin(s.t * 20.0) * 0.15) * 16.0 / sh._w
				_sprite(out, s.sheet, frame, s.pos, 0.0, Vector2(pulse, pulse), Color(1, 1, 1, 0.9), false, s.id)
			"pool":
				col.a = clampf((s.life - s.t) * 2.0, 0.0, 0.85)
				if s.sheet == "blood_drop":
					_emit(out, [OP_PUDDLE | GROUND, s.pos, s.radius, col])
				else:
					var k: float = s.radius * 2.2 / sh._w
					_sprite(out, s.sheet, frame, s.pos, 0.0, Vector2(k, k), col, true, s.id)
			"turret":
				col.a = clampf((s.life - s.t) * 2.0, 0.0, 1.0)
				_sprite(out, s.sheet, frame, s.pos + Vector2(0, -sh._h * 0.5 + 4), 0.0, Vector2.ONE, col, false, s.id)
			"bat", "wisp":
				if s.rot != 0.0:
					_sprite(out, s.sheet, frame, s.pos, s.rot, Vector2(sc, sc), col, false, s.id)
				else:
					_sprite(out, s.sheet, frame, s.pos, 0.0, Vector2(-sc if s.vel.x < 0 else sc, sc), col, false, s.id)
			"orbit":
				_sprite(out, s.sheet, frame, s.pos, s.rot, Vector2(sc, sc), col, false, s.id, true)
			_:
				_sprite(out, s.sheet, frame, s.pos, s.rot, Vector2(sc, sc), col, false, s.id)
	# Monster shots and Nightmare hazards (host/solo simulate them; guests get
	# them in these ops).
	_cur = {}
	for hz in run.enemies.hazards:
		if not cull.has_point(hz.pos):
			continue
		if hz.type == "puddle":
			var fade: float = clampf((hz.life - hz.t) * 1.5, 0.0, 1.0) * clampf(hz.t * 3.0, 0.0, 1.0)
			_emit(out, [OP_PUDDLE | GROUND, hz.pos, hz.radius, Color(0.3, 1.0, 0.2, fade)])
		elif hz.t < hz.fuse:
			# The warning: a red ring that blinks faster as it's about to go.
			if int(hz.t * (8.0 + hz.t * 20.0)) % 2 == 0:
				_emit(out, [OP_RING, hz.pos, hz.radius, Color(1.0, 0.25, 0.1, 0.9)])
		else:
			var bsh := Db.sheet("bomb_blast")
			var f := mini(int((hz.t - hz.fuse) * bsh.fps), int(bsh.frames) - 1)
			_sprite(out, "bomb_blast", f, hz.pos, 0.0, Vector2(hz.radius / 16.0, hz.radius / 16.0), Color.WHITE)
	for b in run.enemies.bullets:
		if cull.has_point(b.pos):
			var bsh := Db.sheet(b.sheet)
			_sprite(out, b.sheet, int(b.t * bsh.fps) % int(bsh.frames), b.pos, b.rot, Vector2.ONE, Color.WHITE)
	_cur = {}
	return out

var _ops_cache: Array = []
var _ops_frame := -1

## This frame's ops (worked out once, shared by the ground and top layers).
func frame_ops() -> Array:
	if run.is_guest():
		# The host's picture, plus our own weapons, simulated here so they fire
		# the instant we do (the host's copies of those are left out).
		var f2 := Engine.get_process_frames()
		if f2 != _ops_frame:
			_ops_frame = f2
			_ops_cache = remote_ops + ops(run.view_rect())
		return _ops_cache
	var f := Engine.get_process_frames()
	if f != _ops_frame:
		_ops_frame = f
		_ops_cache = ops(run.view_rect())
	return _ops_cache

func _draw() -> void:
	exec_ops(self, frame_ops(), run.view_rect(), false)

## Pools, puddles and auras: drawn by the run's ground layer, under the monsters.
func draw_ground(ci: CanvasItem) -> void:
	exec_ops(ci, frame_ops(), run.view_rect(), true)

func exec_ops(ci: CanvasItem, list_ops: Array, view: Rect2, ground: bool) -> void:
	for op in list_ops:
		if (int(op[0]) & GROUND != 0) != ground:
			continue
		match int(op[0]) & ~GROUND:
			OP_SPRITE:
				var sh := Db.sheet(op[1])
				var src := Rect2(int(op[2]) % int(sh.frames) * sh._w, 0, sh._w, sh._h)
				var sc: Vector2 = op[5]
				if op[4] == 0.0 and sc.x > 0.0 and sc.y > 0.0:
					# Unrotated and unflipped: draw straight.
					var w: float = sh._w * sc.x
					var h: float = sh._h * sc.y
					ci.draw_texture_rect_region(sh._tex, Rect2(op[3] - Vector2(w, h) * 0.5, Vector2(w, h)), src, op[6])
				else:
					# Rotated or mirrored (negative x scale) around its centre.
					ci.draw_set_transform(op[3], op[4], sc)
					ci.draw_texture_rect_region(sh._tex, Rect2(-sh._w * 0.5, -sh._h * 0.5, sh._w, sh._h), src, op[6])
					ci.draw_set_transform(Vector2.ZERO)
			OP_CIRCLE:
				var c: Color = op[3]
				ci.draw_circle(op[1], op[2], Color(c, 0.13))
				ci.draw_arc(op[1], op[2], 0, TAU, 40, c, 1.0)
			OP_RING:
				var c: Color = op[3]
				ci.draw_arc(op[1], maxf(op[2], 1.0), 0, TAU, 48, c, 3.0)
				ci.draw_arc(op[1], maxf(op[2] - 4.0, 1.0), 0, TAU, 48, Color(c, c.a * 0.4), 2.0)
			OP_ZAP:
				var pts: PackedVector2Array = op[1]
				for k in range(1, pts.size()):
					_jagged(ci, pts[k - 1], pts[k], op[2])
			OP_FLASH:
				ci.draw_rect(view, Color(1, 1, 0.85, op[1]))
			OP_PUDDLE:
				var col: Color = op[3]
				if col.g > col.r:
					# Sewer ooze (Nightmare): bright green with a lighter sheen.
					ci.draw_circle(op[1], op[2], Color(0.3, 0.75, 0.1, col.a * 0.75))
					ci.draw_circle(op[1] + Vector2(-op[2] * 0.3, -op[2] * 0.3), op[2] * 0.4, Color(0.75, 1.0, 0.35, col.a * 0.6))
					continue
				var c := Color(0.55, 0.02, 0.06, col.a * 0.8) * Color(col.r, col.g, col.b, 1.0)
				ci.draw_circle(op[1], op[2], c)
				ci.draw_circle(op[1] + Vector2(-op[2] * 0.3, -op[2] * 0.3), op[2] * 0.35, Color(0.9, 0.2, 0.25, col.a * 0.5))

## A lightning-style line between two points.
func _jagged(ci: CanvasItem, a: Vector2, b: Vector2, c: Color) -> void:
	var pts := PackedVector2Array([a])
	var n := maxi(2, int(a.distance_to(b) / 10.0))
	var side := (b - a).orthogonal().normalized()
	for k in range(1, n):
		pts.append(a.lerp(b, float(k) / n) + side * randf_range(-4, 4))
	pts.append(b)
	# coloured glow, hot near-white core
	ci.draw_polyline(pts, Color(c, c.a * 0.6), 3.0)
	ci.draw_polyline(pts, Color(c.lerp(Color.WHITE, 0.7), c.a), 1.0)
