extends Node2D
## All enemies live in parallel arrays and are drawn in one pass, so a run can
## hold hundreds of them. Weapons find enemies through query_circle(), which
## uses a spatial grid rebuilt every frame.

signal died(pos: Vector2, kind: String, is_boss: bool, attacker: int, is_elite: bool)

const CELL := 32.0
# Spatial hash: grid cells anywhere in the world map into this many buckets,
# so monsters are found the same way however far apart co-op players roam.
const BUCKETS := 16384

# Per-kind lookups, built once so the hot loops never touch dictionaries.
var _kinds: Array[String] = []
var _kind_fly := PackedByteArray()
var _kind_faces := PackedInt32Array()
var _kind_alpha := PackedFloat32Array()
var _kind_sheet: Array[Dictionary] = []
var _kind_rooted := PackedByteArray()
var _kind_unstoppable := PackedByteArray()  # ignores freezes (the Reaper)
var _kind_shoot: Array[Dictionary] = []  # {} for monsters that don't shoot

var run  # Run, set by Run
var kind: Array[String] = []
var pos := PackedVector2Array()
var knock := PackedVector2Array()
var hp := PackedFloat32Array()
var max_hp := PackedFloat32Array()
var speed := PackedFloat32Array()
var damage := PackedFloat32Array()
var radius := PackedFloat32Array()
var scale_ := PackedFloat32Array()
var anim := PackedFloat32Array()
var flash := PackedFloat32Array()
var uid := PackedInt32Array()
var boss := PackedByteArray()
var kidx := PackedInt32Array()  # index into the _kind_* tables
var elite := PackedByteArray()   # Nightmare's tougher, glowing red variants
var shoot_t := PackedFloat32Array()  # seconds until a shooter fires again
# Walking round props: when a prop pushes a monster back the way it came, it
# slides along it (detour_dir) for a moment instead of pressing into it.
var detour_t := PackedFloat32Array()
var detour_dir := PackedVector2Array()
var detour_from := PackedVector2Array()  # where it was when this way round was chosen
var detour_age := PackedFloat32Array()   # seconds since then
# Safety net: a walker that hasn't got anywhere in a while (wedged somewhere
# the steering can't solve) is moved to a fresh spot just off screen near the
# heroes, so nothing is ever left stuck.
var prog_from := PackedVector2Array()
var prog_t := PackedFloat32Array()
var prog_strikes := PackedByteArray()
var prog_dist := PackedFloat32Array()  # distance to its target when the window started
var prog_det := PackedFloat32Array()   # seconds of the window spent going round props
var relocated := 0  # how many the safety net has moved (dev reports)
## Monster shots in flight (host/solo): {pos, vel, t, life, damage, sheet, rot}.
## Guests see them through the shots' draw ops.
var bullets: Array[Dictionary] = []
## Nightmare hazards (host/solo): pumpkin blasts {type "blast", fuse, damage}
## and ooze puddles {type "puddle"}; both {pos, t, life, radius}.
var hazards: Array[Dictionary] = []

func add_blast(at: Vector2, radius: float, dmg: float) -> void:
	hazards.append({"type": "blast", "pos": at, "t": 0.0, "fuse": 0.6, "life": 1.1, "radius": radius, "damage": dmg, "done": false})

func add_puddle(at: Vector2, radius: float, life: float) -> void:
	if hazards.size() < 60:
		hazards.append({"type": "puddle", "pos": at, "t": 0.0, "life": life, "radius": radius})

var _next_uid := 1
var _head := PackedInt32Array()  # first enemy in each bucket, -1 if none
var _next := PackedInt32Array()  # next enemy in the same bucket
var _cx := PackedInt32Array()    # each enemy's grid cell
var _cy := PackedInt32Array()
var _frame := 0
var frozen := 0.0  # seconds left of the clock pickup's freeze

func _ready() -> void:
	_head.resize(BUCKETS)
	for k in Db.ENEMIES:
		var d: Dictionary = Db.ENEMIES[k]
		_kinds.append(k)
		_kind_fly.append(1 if d.get("fly", false) else 0)
		_kind_faces.append(int(d.faces))
		_kind_alpha.append(d.get("alpha", 1.0))
		_kind_sheet.append(Db.sheet(d.sheet))
		_kind_rooted.append(1 if d.get("rooted", false) else 0)
		_kind_unstoppable.append(1 if d.get("unstoppable", false) else 0)
		_kind_shoot.append(d.get("shoot", {}))

func count() -> int:
	return pos.size()

func spawn(k: String, at: Vector2, hp_mul := 1.0, is_boss := false, speed_mul := 1.0, is_elite := false, damage_mul := 1.0) -> void:
	var d: Dictionary = Db.ENEMIES[k]
	is_elite = is_elite and not is_boss
	var s := 2.0 if is_boss else (1.5 if is_elite else 1.0)  # whole-pixel sizes stay sharp
	if is_elite:
		hp_mul *= 3.0
	kind.append(k)
	pos.append(at)
	knock.append(Vector2.ZERO)
	var h: float = d.hp * hp_mul * (25.0 if is_boss else 1.0)
	hp.append(h)
	max_hp.append(h)
	speed.append(d.speed * speed_mul * (0.85 if is_boss else randf_range(0.9, 1.1)))
	var late: float = 1.0 if d.get("unstoppable", false) else run.contact_scale()
	damage.append(d.damage * damage_mul * late * (1.5 if is_boss else (1.3 if is_elite else 1.0)))
	radius.append(d.radius * s)
	scale_.append(s)
	anim.append(randf() * 2.0)
	flash.append(0.0)
	uid.append(_next_uid)
	boss.append(1 if is_boss else 0)
	kidx.append(_kinds.find(k))
	elite.append(1 if is_elite else 0)
	shoot_t.append(randf_range(0.5, 1.0) * float(d.get("shoot", {}).get("every", 1.0)))
	detour_t.append(0.0)
	detour_dir.append(Vector2.ZERO)
	detour_from.append(at)
	detour_age.append(0.0)
	prog_from.append(at)
	prog_t.append(0.0)
	prog_strikes.append(0)
	prog_dist.append(INF)
	prog_det.append(0.0)
	_next_uid += 1

func _remove(i: int) -> void:
	# Swap-remove keeps it O(1); uids stay stable for hit tracking.
	var last := pos.size() - 1
	if i != last:
		kind[i] = kind[last]; pos[i] = pos[last]; knock[i] = knock[last]
		hp[i] = hp[last]; max_hp[i] = max_hp[last]; speed[i] = speed[last]
		damage[i] = damage[last]; radius[i] = radius[last]; scale_[i] = scale_[last]
		anim[i] = anim[last]; flash[i] = flash[last]; uid[i] = uid[last]; boss[i] = boss[last]
		kidx[i] = kidx[last]; shoot_t[i] = shoot_t[last]; elite[i] = elite[last]
		detour_t[i] = detour_t[last]; detour_dir[i] = detour_dir[last]; detour_from[i] = detour_from[last]; detour_age[i] = detour_age[last]
		prog_from[i] = prog_from[last]; prog_t[i] = prog_t[last]; prog_strikes[i] = prog_strikes[last]
		prog_dist[i] = prog_dist[last]; prog_det[i] = prog_det[last]
	kidx.remove_at(last); shoot_t.remove_at(last); elite.remove_at(last)
	detour_t.remove_at(last); detour_dir.remove_at(last); detour_from.remove_at(last); detour_age.remove_at(last)
	prog_from.remove_at(last); prog_t.remove_at(last); prog_strikes.remove_at(last)
	prog_dist.remove_at(last); prog_det.remove_at(last)
	kind.remove_at(last); pos.remove_at(last); knock.remove_at(last)
	hp.remove_at(last); max_hp.remove_at(last); speed.remove_at(last)
	damage.remove_at(last); radius.remove_at(last); scale_.remove_at(last)
	anim.remove_at(last); flash.remove_at(last); uid.remove_at(last); boss.remove_at(last)

## Returns true if the hit killed it.
func hurt(i: int, amount: float, from: Vector2, knockback := 0.0, attacker := -1) -> bool:
	if i < 0 or i >= hp.size() or hp[i] <= 0.0:
		return false
	hp[i] -= amount
	flash[i] = 0.12
	run.popups.add(pos[i] + Vector2(0, -8 * scale_[i]), amount)
	if knockback > 0.0 and boss[i] == 0:
		# A nudge, not a launch: hits don't stack (the stronger push wins) and
		# big monsters barely budge.
		var weight := clampf(radius[i] / 6.0, 1.0, 3.0)
		var push := knockback * 1.5 / weight
		if push > knock[i].length():
			knock[i] = (pos[i] - from).normalized() * push
	if hp[i] <= 0.0:
		# Removed in the next step() so indices stay valid while weapons loop.
		died.emit(pos[i], kind[i], boss[i] == 1, attacker, elite[i] == 1)
		return true
	return false

func alive(i: int) -> bool:
	return i >= 0 and i < hp.size() and hp[i] > 0.0

func _sweep_dead() -> void:
	var i := hp.size() - 1
	while i >= 0:
		if hp[i] <= 0.0:
			_remove(i)
		i -= 1

## Takes every monster off the field at once, no drops (the Reaper's arrival).
func clear_all() -> void:
	var i := pos.size() - 1
	while i >= 0:
		_remove(i)
		i -= 1
	bullets.clear()
	hazards.clear()

func index_of_uid(u: int) -> int:
	# Linear, but only used for short-lived targeting by bats and wisps.
	for i in uid.size():
		if uid[i] == u and hp[i] > 0.0:
			return i
	return -1

static func _bucket(cx: int, cy: int) -> int:
	return ((cx * 73856093) ^ (cy * 19349663)) & (BUCKETS - 1)

func _rebuild_grid(_center: Vector2) -> void:
	_head.fill(-1)
	var n := pos.size()
	_next.resize(n)
	_cx.resize(n)
	_cy.resize(n)
	for i in n:
		var cx := floori(pos[i].x / CELL)
		var cy := floori(pos[i].y / CELL)
		_cx[i] = cx
		_cy[i] = cy
		var b := _bucket(cx, cy)
		_next[i] = _head[b]
		_head[b] = i

## Indices of enemies whose body overlaps the circle.
func query_circle(center: Vector2, r: float) -> Array:
	var out := []
	var reach := r + 36.0  # largest enemy radius
	var x0 := floori((center.x - reach) / CELL)
	var x1 := floori((center.x + reach) / CELL)
	var y0 := floori((center.y - reach) / CELL)
	var y1 := floori((center.y + reach) / CELL)
	var n := mini(pos.size(), _next.size())
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var i := _head[_bucket(cx, cy)]
			while i != -1:
				# A bucket can hold far-away cells too: only this cell's monsters.
				if i < n and _cx[i] == cx and _cy[i] == cy and hp[i] > 0.0:
					var rr := r + radius[i]
					if center.distance_squared_to(pos[i]) <= rr * rr:
						out.append(i)
				i = _next[i] if i < n else -1
	return out

func nearest(to: Vector2, max_dist := 1e9) -> int:
	var best := -1
	var best_d := max_dist * max_dist
	for i in pos.size():
		if hp[i] <= 0.0:
			continue
		var d := to.distance_squared_to(pos[i])
		if d < best_d:
			best_d = d
			best = i
	return best

## Nearest living enemy within max_dist whose uid isn't in `skip`.
func nearest_excluding(to: Vector2, max_dist: float, skip: Dictionary) -> int:
	var best := -1
	var best_d := max_dist * max_dist
	for i in query_circle(to, max_dist):
		if skip.has(uid[i]):
			continue
		var d := to.distance_squared_to(pos[i])
		if d < best_d:
			best_d = d
			best = i
	return best

func random_on_screen(view: Rect2) -> int:
	var candidates := []
	for i in pos.size():
		if hp[i] > 0.0 and view.has_point(pos[i]):
			candidates.append(i)
	return -1 if candidates.is_empty() else candidates.pick_random()

## Moves every enemy toward its nearest target (a living player).
func step(delta: float, targets: PackedVector2Array, view: Rect2) -> void:
	_sweep_dead()
	_frame += 1
	var center := Vector2.ZERO
	for t in targets:
		center += t
	center /= maxf(1.0, targets.size())
	_rebuild_grid(center)
	frozen = maxf(0.0, frozen - delta)
	var far := view.size.length() * 0.85
	var moving := frozen <= 0.0
	var knock_decay := minf(1.0, delta * 10.0)
	var obstacles = run.obstacles
	var n := pos.size()
	var nt := targets.size()
	var stagger := _frame % 3
	var half := _frame % 2
	var near := view.size * 0.5 + Vector2(64, 64)
	for i in n:
		var p := pos[i]
		var mv := moving or _kind_unstoppable[kidx[i]] == 1
		var goal := targets[0]
		var to := goal - p
		var d2 := to.length_squared()
		for t in range(1, nt):
			var o := targets[t] - p
			var od := o.length_squared()
			if od < d2:
				d2 = od
				to = o
				goal = targets[t]
		var dist := sqrt(d2)
		# Off every player's screen: update every other frame, at double step,
		# without separation. (Near *any* player counts as on screen.)
		var onscreen := absf(to.x) < near.x and absf(to.y) < near.y
		var dt := delta
		if not onscreen:
			if i % 2 != half:
				continue
			dt = delta * 2.0
		anim[i] += dt
		if flash[i] > 0.0:
			flash[i] = maxf(0.0, flash[i] - dt)
		# Enemies left far behind wrap to the other side of their target.
		if dist > far and boss[i] == 0:
			pos[i] = goal + to / dist * (far * 0.6)
			continue
		var ki := kidx[i]
		if mv and _kind_rooted[ki] == 0 and boss[i] == 0:
			prog_t[i] += dt
			if detour_t[i] > 0.0:
				prog_det[i] += dt
			if prog_t[i] > 3.0:
				# Stuck: in 3s it either barely moved, or spent most of the
				# time going round props without getting any closer. (Just not
				# getting closer isn't enough: a hero running away does that.)
				# Off screen, move it now; on screen, give it one more go first.
				# (Wedged only counts against a prop: one held up in a crowd of
				# other monsters isn't stuck, it's queueing.)
				var wedged: bool = p.distance_to(prog_from[i]) < 10.0 and not obstacles.is_free(p, radius[i] * 0.6 + 3.0)
				var circling: bool = prog_det[i] > 1.5 and dist > prog_dist[i] - 8.0
				if (wedged or circling) and dist > 40.0:
					prog_strikes[i] += 1
					if not onscreen or prog_strikes[i] >= 2:
						var ring := (view.size * 0.5).length() + 30.0
						p = obstacles.free_spot(goal + Vector2.RIGHT.rotated(randf() * TAU) * ring, radius[i])
						pos[i] = p
						knock[i] = Vector2.ZERO
						detour_t[i] = 0.0
						prog_strikes[i] = 0
						relocated += 1
				else:
					prog_strikes[i] = 0
				prog_from[i] = p
				prog_t[i] = 0.0
				prog_dist[i] = dist
				prog_det[i] = 0.0
		if _kind_rooted[ki] == 1:
			# Rooted: stays put; shooters fire at whoever is in range.
			var sh: Dictionary = _kind_shoot[ki]
			if mv and not sh.is_empty() and onscreen:
				shoot_t[i] -= dt
				if shoot_t[i] <= 0.0 and dist < float(sh.range):
					shoot_t[i] = float(sh.every) * randf_range(0.85, 1.15)
					_fire(p, to / maxf(dist, 0.001), sh, radius[i])
			continue
		var v := Vector2.ZERO
		if mv and dist > 1.0:
			v = to / dist * speed[i]
			if detour_t[i] > 0.0:
				detour_t[i] -= dt
				detour_age[i] += dt
				v = (to / dist * 0.15 + detour_dir[i]).normalized() * speed[i]
		# Separation from a few enemies sharing this cell.
		if onscreen and i < _next.size():
			var mx := _cx[i]
			var my := _cy[i]
			var j := _head[_bucket(mx, my)]
			var checked := 0
			var ri := radius[i]
			while j != -1 and checked < 6:
				if j != i and _cx[j] == mx and _cy[j] == my:
					var off := p - pos[j]
					var min_d := (ri + radius[j]) * 0.8
					var od2 := off.length_squared()
					if od2 < min_d * min_d and od2 > 0.01:
						v += off / sqrt(od2) * 30.0
					checked += 1
				j = _next[j]
		var kb := knock[i]
		if kb != Vector2.ZERO:
			v += kb
			knock[i] = kb.lerp(Vector2.ZERO, knock_decay) if kb.length_squared() > 1.0 else Vector2.ZERO
		p += v * dt
		# Obstacles are checked for a third of the enemies each frame.
		if i % 3 == stagger and _kind_fly[kidx[i]] == 0:
			var before := p
			p = obstacles.push_out(p, radius[i] * 0.6)
			var push := p - before
			if push.length_squared() > 0.01 and dist > 1.0 and mv:
				var want := to / dist
				if push.dot(want) < -0.3 * push.length():
					# Pushed back the way it wants to go: slide along the prop,
					# on the side that turns toward the target (alternating by
					# monster when it's dead ahead, so a crowd splits round it).
					var t := push.orthogonal().normalized()
					if detour_t[i] > 0.0:
						# Already going round: keep the same way...
						if detour_dir[i].dot(t) < 0.0:
							t = -t
						# ...unless it has got nowhere in 0.6s (a dead end): turn back.
						if detour_age[i] > 0.6:
							if p.distance_to(detour_from[i]) < 5.0:
								t = -t
							detour_from[i] = p
							detour_age[i] = 0.0
					else:
						var along := t.dot(want)
						if absf(along) < 0.1:
							t *= 1.0 if uid[i] % 2 == 0 else -1.0
						elif along < 0.0:
							t = -t
						detour_from[i] = p
						detour_age[i] = 0.0
					detour_dir[i] = t
					detour_t[i] = 0.7
		pos[i] = p
	_step_bullets(delta)
	_step_hazards(delta)
	queue_redraw()

func _step_hazards(delta: float) -> void:
	var i := hazards.size() - 1
	while i >= 0:
		var hz: Dictionary = hazards[i]
		hz.t += delta
		if hz.type == "blast" and not hz.done and hz.t >= hz.fuse:
			hz.done = true
			for h in run.living_heroes():
				if h.position.distance_to(hz.pos) < hz.radius + h.RADIUS:
					h.take_hit(hz.damage)
		if hz.t >= hz.life:
			hazards.remove_at(i)
		i -= 1

func _fire(from: Vector2, dir: Vector2, sh: Dictionary, r: float) -> void:
	var spd: float = float(sh.speed)
	bullets.append({"pos": from + dir * r + Vector2(0, -6), "vel": dir * spd, "t": 0.0,
		"life": float(sh.range) * 1.4 / spd, "damage": float(sh.damage), "sheet": str(sh.sheet),
		"rot": dir.angle() if sh.get("point", false) else 0.0})

## Moves monster shots; they hurt the first hero they touch and stop at props.
func _step_bullets(delta: float) -> void:
	if bullets.is_empty():
		return
	var heroes: Array = run.living_heroes()
	var i := bullets.size() - 1
	while i >= 0:
		var b: Dictionary = bullets[i]
		b.t += delta
		b.pos += b.vel * delta
		var gone: bool = b.t > b.life or not run.obstacles.is_free(b.pos, 1.5)
		if not gone:
			for h in heroes:
				if h.position.distance_squared_to(b.pos) < (h.RADIUS + 3.0) * (h.RADIUS + 3.0):
					h.take_hit(b.damage)
					gone = true
					break
		if gone:
			bullets.remove_at(i)
		i -= 1
# On a guest nothing is simulated: NetSync hands over the already-smoothed
# enemy list every frame.

## entries: [uid, kind index, flags (1 boss, 2 hurt, 4 frozen), position, hp fraction]
func mirror_set(entries: Array, delta: float) -> void:
	var old_anim := {}
	for i in uid.size():
		old_anim[uid[i]] = anim[i]
	var n := entries.size()
	pos.resize(n); anim.resize(n); uid.resize(n); kidx.resize(n); scale_.resize(n); shoot_t.resize(n); elite.resize(n)
	detour_t.resize(n); detour_dir.resize(n); detour_from.resize(n); detour_age.resize(n)
	prog_from.resize(n); prog_t.resize(n); prog_strikes.resize(n); prog_dist.resize(n); prog_det.resize(n)
	flash.resize(n); boss.resize(n); hp.resize(n); max_hp.resize(n); radius.resize(n); knock.resize(n)
	kind.clear()
	for i in n:
		var e: Array = entries[i]
		var k: int = e[1]
		uid[i] = e[0]
		kidx[i] = k
		kind.append(_kinds[k])
		pos[i] = e[3]
		anim[i] = old_anim.get(e[0], randf()) + delta
		boss[i] = 1 if e[2] & 1 else 0
		elite[i] = 1 if e[2] & 8 else 0
		scale_[i] = 2.0 if e[2] & 1 else (1.3 if e[2] & 8 else 1.0)
		flash[i] = 0.1 if e[2] & 2 else 0.0
		radius[i] = Db.ENEMIES[_kinds[k]].radius * scale_[i]
		hp[i] = e[4]
		max_hp[i] = 1.0
	frozen = 1.0 if n > 0 and entries[0][2] & 4 else 0.0
	# Our own predicted shots look monsters up through the grid.
	_rebuild_grid(Vector2.ZERO)
	queue_redraw()

func _draw() -> void:
	var view: Rect2 = run.view_rect().grow(48)
	var player_x: float = run.player.position.x
	for i in pos.size():
		if view.has_point(pos[i]):
			_draw_one(self, i, player_x)

## Where an enemy's feet are, for sorting against props.
func feet_y(i: int) -> float:
	return pos[i].y + radius[i] * 0.5

func _rect(i: int) -> Rect2:
	var s: Dictionary = _kind_sheet[kidx[i]]
	var w: float = s._w * scale_[i]
	var h: float = s._h * scale_[i]
	return Rect2(pos[i].x - w * 0.5, feet_y(i) - h, w, h)

## Enemies are drawn under the props and heroes. This draws, on top, the few
## that overlap a prop while standing in front of it, so a grave never covers
## a monster that's nearer the camera than it.
func draw_in_front_of_props(ci: CanvasItem) -> void:
	var view: Rect2 = run.view_rect().grow(48)
	var player_x: float = run.player.position.x
	var picked := {}
	for o in run.obstacles.props_in(view):
		var r: Rect2 = o.rect
		var base: float = o.pos.y + 4.0
		for i in query_circle(r.get_center(), r.size.length() * 0.5 + 24.0):
			if not picked.has(i) and feet_y(i) > base and _rect(i).intersects(r):
				picked[i] = true
	var order: Array = picked.keys()
	order.sort_custom(func(a, b): return feet_y(a) < feet_y(b))
	for i in order:
		_draw_one(ci, i, player_x)

func _draw_one(ci: CanvasItem, i: int, player_x: float) -> void:
	var k := kidx[i]
	var s: Dictionary = _kind_sheet[k]
	var src := Db.frame_rect(s, anim[i])
	var rect := _rect(i)
	var w := rect.size.x
	var h := rect.size.y
	var flip := (player_x < pos[i].x) == (_kind_faces[k] > 0)
	var col := Color(1, 1, 1, _kind_alpha[k])
	if flash[i] > 0.0:
		col = Color(1, 0.35, 0.35, col.a)
	elif frozen > 0.0 and _kind_unstoppable[k] == 0:
		col = Color(0.6, 0.8, 1.0, col.a)
	elif elite[i] == 1:
		# Elites smoulder: a red tint that pulses.
		var glow := 0.5 + sin(anim[i] * 6.0) * 0.12
		col = Color(1.0, glow, glow * 0.85, col.a)
	if elite[i] == 1:
		# Elites stand in a pulsing ember ring...
		var pulse := 0.5 + sin(anim[i] * 5.0) * 0.5
		var feet := Vector2(pos[i].x, feet_y(i))
		ci.draw_set_transform(feet, 0.0, Vector2(1.0, 0.45))
		ci.draw_circle(Vector2.ZERO, w * 0.42 + pulse, Color(1.0, 0.25, 0.1, 0.25 + pulse * 0.2), false, 1.0)
		ci.draw_circle(Vector2.ZERO, w * 0.3, Color(0.8, 0.05, 0.05, 0.18))
		ci.draw_set_transform(Vector2.ZERO)
	if flip:
		# Mirror around the enemy's centre line.
		ci.draw_set_transform(Vector2(pos[i].x, 0.0), 0.0, Vector2(-1, 1))
		ci.draw_texture_rect_region(s._tex, Rect2(-w * 0.5, rect.position.y, w, h), src, col)
		ci.draw_set_transform(Vector2.ZERO)
	else:
		ci.draw_texture_rect_region(s._tex, rect, src, col)
	if elite[i] == 1:
		# ...with a flaming skull bobbing over their heads.
		var m := Db.sheet("elite_mark")
		var bob := roundf(sin(anim[i] * 3.0))
		ci.draw_texture_rect_region(m._tex, Rect2(roundf(pos[i].x - m._w * 0.5), rect.position.y - m._h - 1 + bob, m._w, m._h),
			Db.frame_rect(m, anim[i]))
	if boss[i] == 1:
		var bw := 30.0
		var by := feet_y(i) + 3
		ci.draw_rect(Rect2(pos[i].x - bw * 0.5, by, bw, 3), Color(0, 0, 0, 0.7))
		ci.draw_rect(Rect2(pos[i].x - bw * 0.5, by, bw * hp[i] / max_hp[i], 3), Color(0.9, 0.15, 0.2))
