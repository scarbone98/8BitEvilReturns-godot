extends Node2D
## A hero: movement, health and the stat block its weapons read. Experience
## and level belong to the run (shared by the team in co-op).
##
## mode "local"  - this device's hero: reads input (or the test bot)
##      "remote" - on the host, another player's hero, moved by their packets
##      "puppet" - on a guest, someone else's hero, drawn from snapshots

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
	"growth": 0.0, "greed": 0.0, "luck": 0.0, "curse": 0.0, "revival": 0,
}

var run
var slot := 0
var mode := "local"
var player_name := ""
var view_size := Vector2(240, 400)  # this player's screen, for what they can see
var allowed: Callable                # id -> bool: which locked content this player has
var inv_rev := 0                     # bumps when weapons/passives change (co-op sync)
var max_hp_override := -1.0          # guests show the host's numbers
var net_target := Vector2.ZERO       # remote heroes glide toward their latest position
var away := false                    # co-op: this player's connection dropped (seat held)
# This hero's share of the run, for their results and feats
var kills := 0
var candy := 0
var silver_found := 0
var chests := 0
var bosses := 0
var evolutions := 0
var unions := 0
var weapons_full := 0
var kind_kills := {}
var made: Array = []
var character: Dictionary
var char_id := ""
var bonus := {}        # power-up stats, fixed for the run
var revivals := 0
var healed := 0.0      # for feats
var distance := 0.0
var stats := {}
var hp := 100.0
var facing := Vector2.RIGHT
var moving := false
var weapons := {}   # id -> Weapon
var passives := {}  # id -> level
var _invuln := 0.0
var _anim := 0.0
var _hurt_flash := 0.0
var dead := false
var god := false  # dev: takes no damage (stuck tests)
var stand := false  # dev: the bot picks cards but never walks
var autopilot := false

# Touch joystick: drag anywhere on screen.
var _touch_id := -1
var _touch_origin := Vector2.ZERO
var _touch_vec := Vector2.ZERO

func setup(id: String, powerup_stats := {}) -> void:
	char_id = id
	character = Db.CHARACTERS[id]
	bonus = powerup_stats
	recalc_stats()
	hp = max_hp()
	revivals = int(stats.revival)
	if not allowed.is_valid():
		# This device's hero uses this device's unlocks. Another player's hero
		# gets only what everyone has until their own unlocks arrive (never the
		# host's).
		allowed = Meta.content_unlocked if mode == "local" else func(item): return not Db.is_locked_content(item)

func recalc_stats() -> void:
	var old_max := max_hp() if not stats.is_empty() else 0.0
	stats = STAT_DEFAULTS.duplicate()
	for k in character.get("stats", {}):
		stats[k] += character.stats[k]
	for k in bonus:
		stats[k] += bonus[k]
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
	if max_hp_override >= 0.0:
		return max_hp_override
	return stats.max_hp * (1.0 + stats.max_hp_mul)

func magnet_radius() -> float:
	return BASE_MAGNET * (1.0 + stats.magnet)

var slowed := 0.0  # seconds left wading through ooze (Nightmare sewers)

func move_speed() -> float:
	return BASE_MOVE * (1.0 + stats.move) * (0.6 if slowed > 0.0 else 1.0)

## Touch: put a finger down anywhere and drag; the stick stays where the
## finger landed. Read in _input (not _unhandled_input) so a lift that lands
## on a button still lets go of the stick.
func _input(event: InputEvent) -> void:
	if mode != "local":
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_id == -1 and not get_tree().paused:
				_touch_id = event.index
				_touch_origin = event.position
				_touch_vec = Vector2.ZERO
		elif event.index == _touch_id:
			reset_touch()
	elif event is InputEventScreenDrag and event.index == _touch_id:
		var off: Vector2 = event.position - _touch_origin
		var maxr := 28.0
		_touch_vec = off.limit_length(maxr) / maxr

## Lets go of the stick (menus opening/closing, losing focus).
func reset_touch() -> void:
	_touch_id = -1
	_touch_vec = Vector2.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		reset_touch()

func joystick() -> Dictionary:
	return {"active": _touch_id != -1, "origin": _touch_origin, "vec": _touch_vec}

## simulate: full rules (regen, weapons). A co-op guest's own hero passes
## simulate=false, fire=true: it fires its predicted weapons for show only.
func step(delta: float, simulate := true, fire := false) -> void:
	_anim += delta
	_invuln = maxf(0.0, _invuln - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	slowed = maxf(0.0, slowed - delta)
	if mode == "puppet":
		queue_redraw()
		return
	if dead or away:
		# Away heroes stand still, untouchable, until their player is back.
		queue_redraw()
		return
	if mode == "remote":
		# facing and moving come from their packets (see NetSync)
		var to := net_target - position
		position = net_target if to.length() > 60.0 else position.lerp(net_target, minf(1.0, delta * 15.0))
	else:
		var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if _touch_id != -1 and _touch_vec.length() > 0.15:
			dir = _touch_vec.limit_length(1.0)
		if autopilot:
			dir = Vector2.ZERO if stand else _bot_dir()
		moving = dir.length() > 0.1
		if moving:
			facing = dir.normalized()
			position += dir * move_speed() * delta
			distance += dir.length() * move_speed() * delta
			position = run.obstacles.push_out(position, RADIUS)
	if simulate:
		if stats.regen > 0.0 and hp < max_hp():
			heal(stats.regen * delta)
		for w in weapons.values():
			w.step(delta)
	elif fire:
		for w in weapons.values():
			if Db.is_predicted(w.def):
				w.step(delta)
	queue_redraw()

## Test bot: keep the nearest enemy at claw range, back off when crowded,
## grab nearby candy when it's safe.
func _bot_dir() -> Vector2:
	var e = run.enemies
	var flee := Vector2.ZERO
	var crowd := 0
	for i in e.query_circle(position, 14.0):
		var off: Vector2 = position - e.pos[i]
		flee += off.normalized()
		crowd += 1
	if crowd > 0:
		return (flee.normalized() + flee.orthogonal().normalized() * 0.4).limit_length(1.0)
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
	if _invuln > 0.0 or dead or away or god:
		return
	_invuln = HIT_INVULN
	_hurt_flash = 0.2
	hp -= amount * (1.0 - stats.armor)
	hp_changed.emit()
	if hp <= 0.0:
		if revivals > 0:
			revivals -= 1
			hp = max_hp() * 0.5
			_invuln = 2.5
			run.on_revive(self)
			return
		hp = 0.0
		dead = true
		died.emit(self)

func heal(amount: float) -> void:
	var before := hp
	hp = minf(max_hp(), hp + amount)
	healed += hp - before
	hp_changed.emit()

## Back on its feet (co-op: downed heroes return at the next team level-up).
func revive(frac := 0.5) -> void:
	dead = false
	hp = max_hp() * frac
	_invuln = 2.5
	hp_changed.emit()

# ---------------------------------------------------------------- Inventory

func add_weapon(id: String) -> void:
	var w := Weapon.new(id, self, run)
	weapons[id] = w
	inv_rev += 1
	if weapons.size() >= Db.MAX_WEAPONS:
		weapons_full = 1

func upgrade(id: String) -> void:
	if Db.WEAPONS.has(id):
		if weapons.has(id):
			weapons[id].level_up()
			inv_rev += 1
		else:
			add_weapon(id)
	elif Db.PASSIVES.has(id):
		passives[id] = passives.get(id, 0) + 1
		inv_rev += 1
		recalc_stats()
	elif Db.ELIXIRS.has(id):
		var e: Dictionary = Db.ELIXIRS[id]
		if e.has("heal"): heal(e.heal)
		if e.has("silver"): silver_found += int(e.silver)

## What a chest can turn into right now: [[weapon, into, "evolve"|"union"], ...].
## Evolve: weapon at max + its passive. Union: two weapons, both at max.
func evolvable() -> Array:
	var out := []
	for id in weapons:
		var d: Dictionary = Db.WEAPONS[id]
		if weapons[id].level < Db.weapon_max_level(id):
			continue
		var ev = d.get("evolve")
		if ev is Dictionary and passives.has(ev.with):
			out.append([id, ev.into, "evolve"])
		var un = d.get("union")
		if un is Dictionary and weapons.has(un.with) and weapons[un.with].level >= Db.weapon_max_level(un.with):
			out.append([id, un.into, "union"])
	return out

## Applies one entry from evolvable(); returns the new weapon id.
func evolve(e: Array) -> String:
	weapons.erase(e[0])
	if e[2] == "union":
		weapons.erase(Db.WEAPONS[e[0]].union.with)
		unions += 1
	else:
		evolutions += 1
	made.append(e[1])
	add_weapon(e[1])
	return e[1]

## Choices for the level-up screen. Luck can add a fourth.
func upgrade_options(n := 3) -> Array:
	if randf() < stats.luck * 0.5:
		n += 1
	var pool := []
	for id in Db.WEAPONS:
		var d: Dictionary = Db.WEAPONS[id]
		if d.get("evolution", false) or not allowed.call(id):
			continue
		if weapons.has(id):
			if weapons[id].level < Db.weapon_max_level(id):
				pool.append(id)
		elif _base_weapon_count() < Db.MAX_WEAPONS and not _owns_evolution_of(id):
			pool.append(id)
	for id in Db.PASSIVES:
		if not allowed.call(id):
			continue
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

## True if this weapon already became an evolution or union we hold.
func _owns_evolution_of(id: String) -> bool:
	var d: Dictionary = Db.WEAPONS[id]
	if d.get("evolve") is Dictionary and weapons.has(d.evolve.into):
		return true
	if d.get("union") is Dictionary and weapons.has(d.union.into):
		return true
	for w in weapons:
		var r := Db.recipe_for(w)
		if r.size() == 3 and r[2] == "union" and r[1] == id:
			return true
	return false

## Inventory as plain data, for co-op sync: {w: {id: level}, p: {id: level}}.
func inventory() -> Dictionary:
	var w := {}
	for id in weapons:
		w[id] = weapons[id].level
	return {"w": w, "p": passives.duplicate()}

## Guests mirror the inventory the host sends (weapons never fire here).
func set_inventory(inv: Dictionary) -> void:
	# Keep weapons we already have (their timers keep running), add new ones.
	var had := weapons
	weapons = {}
	for id in inv.get("w", {}):
		if Db.WEAPONS.has(id):
			var w: Weapon = had[id] if had.has(id) else Weapon.new(id, self, run)
			while w.level < int(inv.w[id]):
				w.level_up()  # also applies each level's changes, for our own shots
			weapons[id] = w
	passives.clear()
	for id in inv.get("p", {}):
		if Db.PASSIVES.has(id):
			passives[id] = int(inv.p[id])
	inv_rev += 1
	recalc_stats()  # our predicted shots use the same sizes and speeds as the host's

func level_of(id: String) -> int:
	if weapons.has(id): return weapons[id].level
	return passives.get(id, 0)

# ---------------------------------------------------------------- Drawing

func _draw() -> void:
	var s := Db.sheet(character.run if moving else character.idle)
	var src := Db.frame_rect(s, _anim)
	var k: float = character.get("scale", 1.0)
	var w: float = s._w * k
	var h: float = s._h * k
	var shadow := Db.tex("shadow_small")
	draw_texture_rect(shadow, Rect2(-7, -3, 14, 6), false, Color(1, 1, 1, 0.6))
	var rect := Rect2(-w * 0.5, -h + 2, w, h)
	var col := Color.WHITE
	if dead:
		col = Color(0.6, 0.7, 1.0, 0.35)
	elif away:
		col = Color(1, 1, 1, 0.4)
	elif _hurt_flash > 0.0:
		col = Color(1, 0.3, 0.3)
	elif _invuln > 0.0 and int(_invuln * 20) % 2 == 0:
		col = Color(1, 1, 1, 0.5)
	# Mirror around the hero's centre (a negative-width rect only shifts it).
	if facing.x < 0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
	draw_texture_rect_region(s._tex, rect, src, col)
	draw_set_transform(Vector2.ZERO)
	if dead:
		return
	if mode != "local" and player_name != "":
		var f: Font = run.popups.font
		var tag := player_name + (" (away)" if away else "")
		var tw := f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string_outline(f, Vector2(-tw * 0.5, -h - 1), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 2, Color.BLACK)
		draw_string(f, Vector2(-tw * 0.5, -h - 1), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.8, 0.5) if away else Color(0.8, 0.9, 1.0))
	# Health bar under the hero, like the original.
	var frac := clampf(hp / maxf(max_hp(), 1.0), 0.0, 1.0)
	draw_rect(Rect2(-8, 4, 16, 2), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(-8, 4, 16 * frac, 2), Color(0.85, 0.1, 0.15))
