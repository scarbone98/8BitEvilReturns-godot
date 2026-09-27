extends Node2D
## Every live projectile / effect, stored as small dictionaries and updated by
## type. New weapon behaviours add a spawn function and a branch in step().

var run
var list: Array[Dictionary] = []

func _add(w: Weapon, type: String, extra: Dictionary) -> Dictionary:
	var s := {
		"w": w, "type": type, "pos": w.player.position, "vel": Vector2.ZERO, "t": 0.0,
		"life": 1.0, "damage": w.damage(), "pierce": w.pierce(), "hits": {},
		"rehit": -1.0, "radius": 6.0, "sheet": w.def.sheet, "rot": 0.0,
		"scale": w.area(), "tint": w.tint(), "delay": 0.0,
	}
	s.merge(extra, true)
	list.append(s)
	return s

func count_for(w: Weapon) -> int:
	var n := 0
	for s in list:
		if s.w == w:
			n += 1
	return n

# ---------------------------------------------------------------- Spawners

func bullet(w: Weapon, from: Vector2, dir: Vector2) -> void:
	var spd := w.speed()
	_add(w, "bullet", {"pos": from, "vel": dir * spd, "life": w.raw("range") / maxf(spd, 1.0),
		"rot": dir.angle() + w.def.get("rot_offset", 0.0), "radius": 5.0 * w.area(), "explode": w.def.get("explode", 0.0) * w.area()})

func slash(w: Weapon, dir: Vector2, delay: float) -> void:
	var sh := Db.sheet(w.def.sheet)
	_add(w, "slash", {"dir": dir, "life": float(sh.frames) / sh.fps, "delay": delay,
		"radius": 18.0 * w.area(), "pierce": -1, "rot": dir.angle()})

func boomerang(w: Weapon, dir: Vector2) -> void:
	_add(w, "boomerang", {"vel": dir * w.speed(), "life": 6.0, "pierce": -1, "rehit": 0.5,
		"radius": 7.0 * w.area(), "out": w.raw("range")})

func strike(w: Weapon, at: Vector2) -> void:
	var r: float = w.def.get("strike_radius", 22.0) * w.area()
	for i in run.enemies.query_circle(at, r):
		_hit(w, i, w.damage(), at, 20.0)
	var sh := Db.sheet(w.def.sheet)
	_add(w, "fx", {"pos": at, "life": float(sh.frames) / sh.fps, "anchor": "bottom"})

func orbit(w: Weapon, angle: float) -> void:
	_add(w, "orbit", {"angle": angle, "life": w.duration(), "pierce": -1, "rehit": 0.4,
		"radius": 9.0 * w.area(), "orbit": w.def.get("orbit_radius", 36.0) * w.area()})

func flask(w: Weapon, target: Vector2) -> void:
	_add(w, "flask", {"from": w.player.position, "to": target, "life": 0.5})

func bat(w: Weapon, from: Vector2) -> void:
	_add(w, "bat", {"pos": from, "life": w.duration(), "pierce": -1, "rehit": w.def.get("bite", 0.4),
		"radius": 7.0, "target": -1, "wander": randf() * TAU, "scale": 0.6})

func wisp(w: Weapon, from: Vector2, dir: Vector2) -> void:
	_add(w, "wisp", {"pos": from, "vel": dir * w.speed(), "life": w.duration(), "radius": 7.0,
		"target": -1, "scale": 0.7})

func explosion(w: Weapon, at: Vector2, r: float, dmg: float) -> void:
	for i in run.enemies.query_circle(at, r):
		_hit(w, i, dmg * 0.6, at, 30.0)
	_add(w, "fx", {"pos": at, "life": 0.35, "sheet": "fireball_explosion", "scale": r / 12.0})

# ---------------------------------------------------------------- Update

func _hit(w: Weapon, i: int, dmg: float, from: Vector2, kb: float) -> void:
	run.enemies.hurt(i, dmg, from, kb)
	var ls: float = w.def.get("lifesteal", 0.0)
	if ls > 0.0:
		w.player.heal(dmg * ls)

## Damages overlapping enemies; returns false once the shot's pierce runs out.
func _touch(s: Dictionary, r: float) -> bool:
	var e = run.enemies
	for i in e.query_circle(s.pos, r):
		var u: int = e.uid[i]
		if s.hits.has(u):
			if s.rehit < 0.0 or s.t - s.hits[u] < s.rehit:
				continue
		s.hits[u] = s.t
		_hit(s.w, i, s.damage, s.pos, s.w.raw("knockback"))
		if s.get("explode", 0.0) > 0.0:
			explosion(s.w, s.pos, s.explode, s.damage)
		if s.pierce > 0:
			s.pierce -= 1
			if s.pierce == 0:
				return false
	return true

func step(delta: float) -> void:
	var e = run.enemies
	var player_pos: Vector2 = run.player.position
	var i := list.size() - 1
	while i >= 0:
		var s: Dictionary = list[i]
		if s.delay > 0.0:
			s.delay -= delta
			i -= 1
			continue
		s.t += delta
		var alive: bool = s.t < s.life
		match s.type:
			"bullet":
				s.pos += s.vel * delta
				if alive:
					alive = _touch(s, s.radius)
				if not alive and s.t >= s.life and s.get("explode", 0.0) > 0.0:
					explosion(s.w, s.pos, s.explode, s.damage)
			"slash":
				s.pos = player_pos + s.dir * 16.0 * s.scale
				if s.t < 0.15:
					_touch(s, s.radius)
			"boomerang":
				s.rot += delta * 18.0
				var travelled: float = s.get("dist", 0.0) + s.vel.length() * delta
				s.dist = travelled
				if not s.get("back", false):
					if travelled >= s.out:
						s.back = true
				else:
					var to: Vector2 = player_pos - s.pos
					s.vel = s.vel.lerp(to.normalized() * s.w.speed() * 1.3, minf(1.0, delta * 6.0))
					if to.length() < 8.0:
						alive = false
				s.pos += s.vel * delta
				_touch(s, s.radius)
			"orbit":
				s.angle += deg_to_rad(s.w.speed() * 4.0) * delta
				s.pos = player_pos + Vector2.RIGHT.rotated(s.angle) * s.orbit
				s.rot = s.angle + s.w.def.get("rot_offset", 0.0)
				_touch(s, s.radius)
			"flask":
				var k: float = clampf(s.t / s.life, 0.0, 1.0)
				s.pos = s.from.lerp(s.to, k) + Vector2(0, -sin(k * PI) * 30.0)
				s.rot += delta * 12.0
				if not alive:
					_add(s.w, "pool", {"pos": s.to, "life": s.w.duration(), "pierce": -1,
						"rehit": s.w.def.get("tick", 0.35), "radius": 14.0 * s.w.area(),
						"sheet": s.w.def.pool_sheet})
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
					goal = player_pos + Vector2.RIGHT.rotated(s.wander) * 26.0
				s.vel = s.vel.lerp((goal - s.pos).normalized() * s.w.speed(), minf(1.0, delta * 5.0))
				s.pos += s.vel * delta
				_touch(s, s.radius)
			"wisp":
				var ti: int = e.index_of_uid(s.target) if s.target != -1 else -1
				if ti == -1:
					var n: int = e.nearest(s.pos, 220.0)
					s.target = e.uid[n] if n != -1 else -1
					ti = n
				if ti != -1:
					s.vel = s.vel.lerp((e.pos[ti] - s.pos).normalized() * s.w.speed(), minf(1.0, delta * 4.0))
				s.pos += s.vel * delta
				if alive:
					alive = _touch(s, s.radius)
			"fx":
				pass
		if not alive:
			list.remove_at(i)
		i -= 1
	queue_redraw()

func _draw() -> void:
	for s in list:
		if s.delay > 0.0:
			continue
		var sh := Db.sheet(s.sheet)
		var src := Db.frame_rect(sh, s.t)
		var sc: float = s.scale
		var w: float = sh._w * sc
		var h: float = sh._h * sc
		var col: Color = s.tint
		match s.type:
			"fx":
				# One-shot animations play through exactly once.
				var f := mini(int(s.t / s.life * sh.frames), sh.frames - 1)
				src = Rect2(f * sh._w, 0, sh._w, sh._h)
				var off := Vector2(-w * 0.5, -h + 6) if s.get("anchor") == "bottom" else Vector2(-w, -h) * 0.5
				draw_texture_rect_region(sh._tex, Rect2(s.pos + off, Vector2(w, h)), src, col)
			"pool":
				col.a = clampf((s.life - s.t) * 2.0, 0.0, 0.85)
				var pw: float = s.radius * 2.2
				draw_texture_rect_region(sh._tex, Rect2(s.pos - Vector2(pw, pw) * 0.5, Vector2(pw, pw)), src, col)
			"bat", "wisp":
				var flip: bool = s.vel.x < 0
				var r := Rect2(s.pos - Vector2(w, h) * 0.5, Vector2(w, h))
				if flip:
					r = Rect2(r.position.x + w, r.position.y, -w, h)
				draw_texture_rect_region(sh._tex, r, src, col)
			"slash":
				var f := mini(int(s.t / s.life * sh.frames), sh.frames - 1)
				src = Rect2(f * sh._w, 0, sh._w, sh._h)
				draw_set_transform(s.pos, s.rot, Vector2(sc, sc))
				draw_texture_rect_region(sh._tex, Rect2(-sh._w * 0.5, -sh._h * 0.5, sh._w, sh._h), src, col)
				draw_set_transform(Vector2.ZERO)
			_:
				draw_set_transform(s.pos, s.rot, Vector2(sc, sc) if s.type != "bullet" else Vector2.ONE)
				draw_texture_rect_region(sh._tex, Rect2(-sh._w * 0.5, -sh._h * 0.5, sh._w, sh._h), src, col)
				draw_set_transform(Vector2.ZERO)
