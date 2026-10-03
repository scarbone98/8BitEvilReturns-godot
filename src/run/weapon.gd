class_name Weapon
extends RefCounted
## One owned weapon. Reads its numbers from Db.WEAPONS, adds level-ups and the
## player's stats, and fires shots into Run.shots when its cooldown is up.

var id: String
var def: Dictionary
var level := 1
var player
var run
var _mods := {}          # summed level-up changes
var _cooldown_mul := 1.0
var _timer := 0.4
var _spin := 0.0         # rotating aim for "spin" shooters
var _flip := false

func _init(weapon_id: String, p, r) -> void:
	id = weapon_id
	def = Db.WEAPONS[id]
	player = p
	run = r

func max_level() -> int:
	return Db.weapon_max_level(id)

func level_up() -> void:
	if level >= max_level():
		return
	var change: Dictionary = def.levels[level - 1]
	level += 1
	for k in change:
		if k == "desc":
			continue
		if k == "cooldown_mul":
			_cooldown_mul *= change[k]
		else:
			_mods[k] = _mods.get(k, 0) + change[k]

func raw(stat: String):
	var base = def.base.get(stat, Db.WEAPON_DEFAULTS[stat])
	return base + _mods.get(stat, 0)

func damage() -> float:
	return raw("damage") * (1.0 + player.stats.might)

func cooldown() -> float:
	return maxf(0.05, raw("cooldown") * _cooldown_mul * (1.0 + player.stats.cooldown))

func area() -> float:
	return raw("area") * (1.0 + player.stats.area)

func speed() -> float:
	return raw("speed") * (1.0 + player.stats.proj_speed)

func duration() -> float:
	return raw("duration") * (1.0 + player.stats.duration)

func amount() -> int:
	return int(raw("amount")) + int(player.stats.amount)

func pierce() -> int:
	return int(raw("pierce"))

func tint() -> Color:
	return def.get("tint", Color.WHITE)

func step(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		if fire():
			_timer = cooldown()
		else:
			_timer = 0.2  # nothing to aim at yet; check again soon

## Returns false when the weapon had nothing to do (no targets).
func fire() -> bool:
	var shots = run.shots
	var e = run.enemies
	var p: Vector2 = player.position
	match def.behavior:
		"shooter":
			var dir: Vector2 = player.facing
			if def.get("aim") == "nearest" or def.get("aim") == "auto":
				var i: int = e.nearest(p, raw("range"))
				if i != -1:
					dir = (e.pos[i] - p).normalized()
				elif def.get("aim") == "nearest":
					return false  # "auto" falls back to the way you're facing
			var n := amount()
			if def.get("aim") == "spin":
				_spin += 0.45
				for k in n:
					shots.bullet(self, p, Vector2.RIGHT.rotated(_spin + TAU * k / n))
			else:
				var gap: float = def.get("spread", 0.14)
				for k in n:
					var off := k - (n - 1) * 0.5
					shots.bullet(self, p + dir.orthogonal() * off * 4.0, dir.rotated(off * gap))
		"slash":
			var dirs := [player.facing, -player.facing, player.facing.orthogonal(), -player.facing.orthogonal()]
			for k in mini(amount(), 4):
				shots.slash(self, dirs[k], k * 0.08)
		"boomerang":
			var n := amount()
			var base_dir: Vector2 = player.facing
			var i: int = e.nearest(p, 200.0)
			if i != -1:
				base_dir = (e.pos[i] - p).normalized()
			for k in n:
				shots.boomerang(self, base_dir.rotated(TAU * k / n if n > 2 else (k - (n - 1) * 0.5) * 0.5))
		"strike":
			var view: Rect2 = run.view_rect_for(player)
			var any := false
			var taken := {}
			for k in amount():
				var i: int
				if def.get("target") == "nearest":
					i = e.nearest_excluding(p, 160.0, taken)
				else:
					i = e.random_on_screen(view)
				if i == -1:
					break
				taken[e.uid[i]] = true
				shots.strike(self, e.pos[i])
				any = true
			return any
		"orbit":
			if shots.count_for(self) > 0:
				return true
			var n := amount()
			for k in n:
				shots.orbit(self, TAU * k / n)
		"flask":
			for k in amount():
				var target := p + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(30, raw("range"))
				var i: int = e.random_on_screen(run.view_rect_for(player))
				if i != -1 and (k == 0 or def.has("explode")):
					target = e.pos[i]
				shots.flask(self, target)
		"summon":
			for k in amount():
				shots.bat(self, p + Vector2.RIGHT.rotated(TAU * k / amount()) * 12.0)
			for k in int(def.get("extra_wisps", 0)):
				shots.wisp(self, p, Vector2.RIGHT.rotated(TAU * k / def.extra_wisps), "wisp")
		"seeker":
			if e.count() == 0:
				return false
			for k in amount():
				shots.wisp(self, p, Vector2.RIGHT.rotated(TAU * k / amount()))
		"aura":
			if shots.count_for(self) == 0:
				shots.aura(self)
			return true
		"nova":
			shots.nova(self)
			if def.has("heal"):
				player.heal(float(def.heal))
			if def.get("smite", false):
				_smite()
		"smite":
			if e.count() == 0:
				return false
			_smite()
		"bounce":
			for k in amount():
				shots.bounce(self, Vector2.RIGHT.rotated(randf() * TAU))
		"chain":
			return _chain()
		"trail":
			if not player.moving:
				return true
			shots.pool(self, p + Vector2(randf_range(-3, 3), randf_range(-2, 2)), "blood_drop", 8.0)
		"turret":
			var lamps: int = shots.count_for(self)
			for k in maxi(0, amount() - lamps):
				shots.turret(self, p + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(20, 40))
	return true

## Hits everything on screen once.
func _smite() -> void:
	var e = run.enemies
	var view: Rect2 = run.view_rect_for(player)
	for i in e.count():
		if e.hp[i] > 0.0 and view.has_point(e.pos[i]):
			run.shots.hit(self, i, damage(), player.position, 0.0)
	run.shots.flash(self)

## Jumps from the nearest enemy to the next nearest, `amount` times.
func _chain() -> bool:
	var e = run.enemies
	var first: int = e.nearest(player.position, raw("range"))
	if first == -1:
		return false
	var points := PackedVector2Array([player.position])
	var taken := {}
	var at := first
	for k in amount() + 1:
		if at == -1:
			break
		var hit_pos: Vector2 = e.pos[at]
		points.append(hit_pos)
		taken[e.uid[at]] = true
		run.shots.hit(self, at, damage(), hit_pos, 10.0)
		if def.has("explode"):
			run.shots.explosion(self, hit_pos, float(def.explode) * area(), damage())
		at = e.nearest_excluding(hit_pos, 70.0 * area(), taken)
	run.shots.zap(self, points)
	return true
