extends Node2D
## All enemies live in parallel arrays and are drawn in one pass, so a run can
## hold hundreds of them. Weapons find enemies through query_circle(), which
## uses a spatial grid rebuilt every frame.

signal died(pos: Vector2, kind: String, is_boss: bool)

const CELL := 32.0

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

var _next_uid := 1
var _grid := {}
var frozen := 0.0  # seconds left of the clock pickup's freeze

func count() -> int:
	return pos.size()

func spawn(k: String, at: Vector2, hp_mul := 1.0, is_boss := false) -> void:
	var d: Dictionary = Db.ENEMIES[k]
	var s := 3.0 if is_boss else 1.0
	kind.append(k)
	pos.append(at)
	knock.append(Vector2.ZERO)
	var h: float = d.hp * hp_mul * (25.0 if is_boss else 1.0)
	hp.append(h)
	max_hp.append(h)
	speed.append(d.speed * (0.85 if is_boss else randf_range(0.9, 1.1)))
	damage.append(d.damage * (1.5 if is_boss else 1.0))
	radius.append(d.radius * s)
	scale_.append(s)
	anim.append(randf() * 2.0)
	flash.append(0.0)
	uid.append(_next_uid)
	boss.append(1 if is_boss else 0)
	_next_uid += 1

func _remove(i: int) -> void:
	# Swap-remove keeps it O(1); uids stay stable for hit tracking.
	var last := pos.size() - 1
	if i != last:
		kind[i] = kind[last]; pos[i] = pos[last]; knock[i] = knock[last]
		hp[i] = hp[last]; max_hp[i] = max_hp[last]; speed[i] = speed[last]
		damage[i] = damage[last]; radius[i] = radius[last]; scale_[i] = scale_[last]
		anim[i] = anim[last]; flash[i] = flash[last]; uid[i] = uid[last]; boss[i] = boss[last]
	kind.remove_at(last); pos.remove_at(last); knock.remove_at(last)
	hp.remove_at(last); max_hp.remove_at(last); speed.remove_at(last)
	damage.remove_at(last); radius.remove_at(last); scale_.remove_at(last)
	anim.remove_at(last); flash.remove_at(last); uid.remove_at(last); boss.remove_at(last)

## Returns true if the hit killed it.
func hurt(i: int, amount: float, from: Vector2, knockback := 0.0) -> bool:
	if i < 0 or i >= hp.size() or hp[i] <= 0.0:
		return false
	hp[i] -= amount
	flash[i] = 0.12
	run.popups.add(pos[i] + Vector2(0, -8 * scale_[i]), amount)
	if knockback > 0.0 and boss[i] == 0:
		knock[i] += (pos[i] - from).normalized() * knockback * 6.0
	if hp[i] <= 0.0:
		# Removed in the next step() so indices stay valid while weapons loop.
		died.emit(pos[i], kind[i], boss[i] == 1)
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

func index_of_uid(u: int) -> int:
	# Linear, but only used for short-lived targeting by bats and wisps.
	for i in uid.size():
		if uid[i] == u and hp[i] > 0.0:
			return i
	return -1

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))

func _rebuild_grid() -> void:
	_grid.clear()
	for i in pos.size():
		var c := _cell(pos[i])
		if _grid.has(c):
			_grid[c].append(i)
		else:
			_grid[c] = [i]

## Indices of enemies whose body overlaps the circle.
func query_circle(center: Vector2, r: float) -> Array:
	var out := []
	var reach := r + 36.0  # largest enemy radius
	var c0 := _cell(center - Vector2(reach, reach))
	var c1 := _cell(center + Vector2(reach, reach))
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			var bucket = _grid.get(Vector2i(cx, cy))
			if bucket == null:
				continue
			for i in bucket:
				if hp[i] > 0.0:
					var rr := r + radius[i]
					if center.distance_squared_to(pos[i]) <= rr * rr:
						out.append(i)
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

func random_on_screen(view: Rect2) -> int:
	var candidates := []
	for i in pos.size():
		if hp[i] > 0.0 and view.has_point(pos[i]):
			candidates.append(i)
	return -1 if candidates.is_empty() else candidates.pick_random()

func step(delta: float, player_pos: Vector2, view: Rect2) -> void:
	_sweep_dead()
	_rebuild_grid()
	frozen = maxf(0.0, frozen - delta)
	var far := view.size.length() * 0.85
	for i in pos.size():
		anim[i] += delta
		flash[i] = maxf(0.0, flash[i] - delta)
		var p := pos[i]
		var to_player := player_pos - p
		var dist := to_player.length()
		# Enemies left far behind wrap to the other side of the player.
		if dist > far and boss[i] == 0:
			pos[i] = player_pos + to_player.normalized() * (far * 0.6)
			continue
		var v := Vector2.ZERO
		if frozen <= 0.0 and dist > 1.0:
			v = to_player / dist * speed[i]
		# Separation from the few enemies sharing this cell.
		var bucket = _grid.get(_cell(p))
		if bucket != null:
			var n := 0
			for j in bucket:
				if j == i or j >= pos.size():
					continue
				var off := p - pos[j]
				var min_d := (radius[i] + radius[j]) * 0.8
				var d2 := off.length_squared()
				if d2 < min_d * min_d and d2 > 0.01:
					v += off / sqrt(d2) * 30.0
				n += 1
				if n > 6:
					break
		v += knock[i]
		knock[i] = knock[i].lerp(Vector2.ZERO, minf(1.0, delta * 10.0))
		p += v * delta
		if not Db.ENEMIES[kind[i]].get("fly", false):
			p = run.obstacles.push_out(p, radius[i] * 0.6)
		pos[i] = p
	queue_redraw()

func _draw() -> void:
	var player_x: float = run.player.position.x
	for i in pos.size():
		var d: Dictionary = Db.ENEMIES[kind[i]]
		var s := Db.sheet(d.sheet)
		var src := Db.frame_rect(s, anim[i])
		var w: float = s._w * scale_[i]
		var h: float = s._h * scale_[i]
		var flip := (player_x < pos[i].x) == (int(d.faces) > 0)
		var rect := Rect2(pos[i].x - w * 0.5, pos[i].y - h + radius[i] * 0.5, w, h)
		if flip:
			rect = Rect2(rect.position.x + w, rect.position.y, -w, h)
		var col := Color(1, 1, 1, d.get("alpha", 1.0))
		if flash[i] > 0.0:
			col = Color(1, 0.35, 0.35, col.a)
		elif frozen > 0.0:
			col = Color(0.6, 0.8, 1.0, col.a)
		draw_texture_rect_region(s._tex, rect, src, col)
		if boss[i] == 1:
			var bw := 30.0
			var by := pos[i].y + radius[i] * 0.5 + 3
			draw_rect(Rect2(pos[i].x - bw * 0.5, by, bw, 3), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(pos[i].x - bw * 0.5, by, bw * hp[i] / max_hp[i], 3), Color(0.9, 0.15, 0.2))
