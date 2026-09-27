extends Node2D
## The hero: movement, health, experience and the stat block weapons read.

signal leveled_up
signal died
signal hp_changed

const BASE_MOVE := 64.0
const BASE_MAGNET := 30.0
const RADIUS := 5.0
const HIT_INVULN := 0.4

# Every stat a character, passive or evolution can touch. Multipliers are
# stored as bonuses (0.1 = +10%) so they add up cleanly.
const STAT_DEFAULTS := {
	"max_hp": 100.0, "max_hp_mul": 0.0, "regen": 0.0, "armor": 0.0,
	"might": 0.0, "cooldown": 0.0, "area": 0.0, "proj_speed": 0.0,
	"duration": 0.0, "amount": 0, "move": 0.0, "magnet": 0.0,
	"growth": 0.0, "greed": 0.0,
}

var run
var character: Dictionary
var stats := {}
var hp := 100.0
var level := 1
var xp := 0.0
var xp_next := 5.0
var facing := Vector2.RIGHT
var moving := false
var weapons := {}   # id -> Weapon
var passives := {}  # id -> level
var _invuln := 0.0
var _anim := 0.0
var _hurt_flash := 0.0
var dead := false
var autopilot := false

# Touch joystick: drag anywhere on screen.
var _touch_id := -1
var _touch_origin := Vector2.ZERO
var _touch_vec := Vector2.ZERO

func setup(char_id: String) -> void:
	character = Db.CHARACTERS[char_id]
	recalc_stats()
	hp = max_hp()

func recalc_stats() -> void:
	var old_max := max_hp() if not stats.is_empty() else 0.0
	stats = STAT_DEFAULTS.duplicate()
	for k in character.get("stats", {}):
		stats[k] += character.stats[k]
	for id in passives:
		var per: Dictionary = Db.PASSIVES[id].per_level
		for k in per:
			stats[k] += per[k] * passives[id]
	stats.armor = minf(stats.armor, 0.6)
	stats.cooldown = maxf(stats.cooldown, -0.6)
	if old_max > 0.0 and max_hp() > old_max:
		hp += max_hp() - old_max
	hp_changed.emit()

func max_hp() -> float:
	return stats.max_hp * (1.0 + stats.max_hp_mul)

func magnet_radius() -> float:
	return BASE_MAGNET * (1.0 + stats.magnet)

func move_speed() -> float:
	return BASE_MOVE * (1.0 + stats.move)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			_touch_id = event.index
			_touch_origin = event.position
			_touch_vec = Vector2.ZERO
		elif not event.pressed and event.index == _touch_id:
			_touch_id = -1
			_touch_vec = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == _touch_id:
		var off: Vector2 = event.position - _touch_origin
		var maxr := 28.0
		if off.length() > maxr:
			# Drag the origin along so reversing direction is instant.
			_touch_origin = event.position - off.normalized() * maxr
			off = off.normalized() * maxr
		_touch_vec = off / maxr

func joystick() -> Dictionary:
	return {"active": _touch_id != -1, "origin": _touch_origin, "vec": _touch_vec}

func step(delta: float) -> void:
	if dead:
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _touch_id != -1 and _touch_vec.length() > 0.15:
		dir = _touch_vec.limit_length(1.0)
	if autopilot:
		dir = _bot_dir()
	moving = dir.length() > 0.1
	if moving:
		facing = dir.normalized()
		position += dir * move_speed() * delta
		position = run.obstacles.push_out(position, RADIUS)
	_anim += delta
	_invuln = maxf(0.0, _invuln - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	if stats.regen > 0.0 and hp < max_hp():
		heal(stats.regen * delta)
	for w in weapons.values():
		w.step(delta)
	queue_redraw()

## Test bot: keep the nearest enemy at claw range, back off when crowded,
## grab nearby candy when it's safe.
func _bot_dir() -> Vector2:
	var e = run.enemies
	var away := Vector2.ZERO
	var crowd := 0
	for i in e.query_circle(position, 14.0):
		var off: Vector2 = position - e.pos[i]
		away += off.normalized()
		crowd += 1
	if crowd > 0:
		return (away.normalized() + away.orthogonal().normalized() * 0.4).limit_length(1.0)
	for p in run.pickups.list:
		if p.pos.distance_to(position) < 70.0:
			return (p.pos - position).normalized()
	var n: int = e.nearest(position)
	if n != -1:
		var to: Vector2 = e.pos[n] - position
		if to.length() > 24.0:
			return to.normalized()
		return to.orthogonal().normalized() * 0.5
	return Vector2.RIGHT.rotated(_anim * 0.4) * 0.5

func take_hit(amount: float) -> void:
	if _invuln > 0.0 or dead:
		return
	_invuln = HIT_INVULN
	_hurt_flash = 0.2
	hp -= amount * (1.0 - stats.armor)
	hp_changed.emit()
	if hp <= 0.0:
		hp = 0.0
		dead = true
		died.emit()

func heal(amount: float) -> void:
	hp = minf(max_hp(), hp + amount)
	hp_changed.emit()

func add_xp(amount: float) -> void:
	xp += amount * (1.0 + stats.growth)
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		# Vampire Survivors-style curve: +10 per level, steeper after 20.
		xp_next += 10.0 if level < 20 else 13.0
		leveled_up.emit()

# ---------------------------------------------------------------- Inventory

func add_weapon(id: String) -> void:
	var w := Weapon.new(id, self, run)
	weapons[id] = w

func upgrade(id: String) -> void:
	if Db.WEAPONS.has(id):
		if weapons.has(id):
			weapons[id].level_up()
		else:
			add_weapon(id)
	elif Db.PASSIVES.has(id):
		passives[id] = passives.get(id, 0) + 1
		recalc_stats()
	elif Db.ELIXIRS.has(id):
		var e: Dictionary = Db.ELIXIRS[id]
		if e.has("heal"): heal(e.heal)
		if e.has("silver"): run.silver_found += int(e.silver)

## Weapons at max level whose partner passive we own, ready to evolve.
func evolvable() -> Array:
	var out := []
	for id in weapons:
		var w: Weapon = weapons[id]
		var ev = Db.WEAPONS[id].get("evolve")
		if ev and w.level >= Db.weapon_max_level(id) and passives.has(ev.with):
			out.append(id)
	return out

func evolve(id: String) -> String:
	var into: String = Db.WEAPONS[id].evolve.into
	weapons.erase(id)
	add_weapon(into)
	return into

## Choices for the level-up screen.
func upgrade_options(n := 3) -> Array:
	var pool := []
	for id in Db.WEAPONS:
		var d: Dictionary = Db.WEAPONS[id]
		if d.get("evolution", false):
			continue
		if weapons.has(id):
			if weapons[id].level < Db.weapon_max_level(id):
				pool.append(id)
		elif _base_weapon_count() < Db.MAX_WEAPONS and not _owns_evolution_of(id):
			pool.append(id)
	for id in Db.PASSIVES:
		var lv: int = passives.get(id, 0)
		if lv > 0 and lv < Db.PASSIVES[id].max_level:
			pool.append(id)
		elif lv == 0 and passives.size() < Db.MAX_PASSIVES:
			pool.append(id)
	pool.shuffle()
	var out := pool.slice(0, n)
	if out.is_empty():
		out = Db.ELIXIRS.keys()
	return out

func _base_weapon_count() -> int:
	return weapons.size()

func _owns_evolution_of(id: String) -> bool:
	var ev = Db.WEAPONS[id].get("evolve")
	return ev != null and weapons.has(ev.into)

func level_of(id: String) -> int:
	if weapons.has(id): return weapons[id].level
	return passives.get(id, 0)

# ---------------------------------------------------------------- Drawing

func _draw() -> void:
	var s := Db.sheet(character.run if moving else character.idle)
	var src := Db.frame_rect(s, _anim)
	var w: float = s._w
	var h: float = s._h
	var shadow := Db.tex("shadow_small")
	draw_texture_rect(shadow, Rect2(-7, -3, 14, 6), false, Color(1, 1, 1, 0.6))
	var rect := Rect2(-w * 0.5, -h + 2, w, h)
	if facing.x < 0:
		rect = Rect2(rect.position.x + w, rect.position.y, -w, h)
	var col := Color.WHITE
	if _hurt_flash > 0.0:
		col = Color(1, 0.3, 0.3)
	elif _invuln > 0.0 and int(_invuln * 20) % 2 == 0:
		col = Color(1, 1, 1, 0.5)
	draw_texture_rect_region(s._tex, rect, src, col)
	# Health bar under the hero, like the original.
	var frac := hp / max_hp()
	draw_rect(Rect2(-8, 4, 16, 2), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(-8, 4, 16 * frac, 2), Color(0.85, 0.1, 0.15))
