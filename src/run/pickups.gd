extends Node2D
## Things on the ground: candy (experience), silver, and rare items.

const MAX_CANDY := 450

# id -> sprite (sheet or plain texture) and what collecting it does (see Run.collect)
const ITEMS := {
	"silver": {"sheet": "silver"},
	"heart": {"tex": "heart"},
	"clock": {"tex": "clock"},
	"skull": {"tex": "skull"},
	"basket": {"tex": "candybasket"},
	"chest": {"tex": "chest"},
}

var run
var list: Array[Dictionary] = []
var _candy_count := 0

func drop_candy(at: Vector2, tier: int) -> void:
	at = run.obstacles.free_spot(at, 5.0)
	if _candy_count >= MAX_CANDY:
		# Too much on the floor: fold it into an existing candy instead.
		for p in list:
			if p.type == "candy":
				p.value += Db.CANDY[tier].xp
				p.tier = maxi(p.tier, tier)
				return
	list.append({"type": "candy", "tier": tier, "value": Db.CANDY[tier].xp, "pos": at, "t": randf(), "pull": false})
	_candy_count += 1

func drop(type: String, at: Vector2) -> void:
	# Chests don't fly to you, so one inside a building would be lost.
	at = run.obstacles.free_spot(at, 10.0 if type == "chest" else 5.0)
	list.append({"type": type, "pos": at, "t": 0.0, "pull": false, "value": 0})

func pull_all_candy() -> void:
	for p in list:
		if p.type == "candy":
			p.pull = true

## Pickups fly to the nearest living hero within their magnet range.
func step(delta: float) -> void:
	var heroes: Array = run.living_heroes()
	if heroes.is_empty():
		return
	var i := list.size() - 1
	while i >= 0:
		var p: Dictionary = list[i]
		p.t += delta
		var hero = p.get("hero")
		if hero == null or not is_instance_valid(hero) or hero.dead:
			hero = heroes[0]
			var best := INF
			for h in heroes:
				var dd: float = h.position.distance_squared_to(p.pos)
				if dd < best:
					best = dd
					hero = h
		var to: Vector2 = hero.position - p.pos
		var d := to.length()
		if p.type != "chest" and d < hero.magnet_radius():
			p.pull = true
			p.hero = hero
		if p.pull or (p.type == "chest" and d < 14.0):
			var spd: float = 60.0 + p.t * 40.0 if p.type != "chest" else 0.0
			p.pos += to.normalized() * minf(d, maxf(spd, 180.0) * delta)
		if d < 8.0 or (p.type == "chest" and d < 12.0):
			if p.type == "candy":
				_candy_count -= 1
			list.remove_at(i)
			run.collect(p, hero)
		i -= 1
	queue_redraw()

# Guests draw whatever the host's snapshot says is on the ground.
const MIRROR_TYPES := ["candy0", "candy1", "candy2", "silver", "heart", "clock", "skull", "basket", "chest"]

func mirror_code(p: Dictionary) -> int:
	return int(p.tier) if p.type == "candy" else MIRROR_TYPES.find(p.type)

func mirror_apply(entries: Array) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	list.clear()
	for e in entries:
		var code: int = e[0]
		if code < 3:
			list.append({"type": "candy", "tier": code, "pos": e[1], "t": t})
		elif code < MIRROR_TYPES.size():
			list.append({"type": MIRROR_TYPES[code], "pos": e[1], "t": t})
	queue_redraw()

func _draw() -> void:
	for p in list:
		var bob := sin(p.t * 4.0) * 1.0
		if p.type == "candy":
			var s := Db.sheet(Db.CANDY[p.tier].sheet)
			var sz := 12.0  # half of the 24px candy art
			draw_texture_rect_region(s._tex, Rect2(p.pos + Vector2(-sz * 0.5, -sz * 0.5 + bob), Vector2(sz, sz)), Db.frame_rect(s, p.t))
			continue
		var it: Dictionary = ITEMS[p.type]
		if it.has("sheet"):
			var s := Db.sheet(it.sheet)
			draw_texture_rect_region(s._tex, Rect2(p.pos + Vector2(-8, -8 + bob), Vector2(16, 16)), Db.frame_rect(s, p.t))
		else:
			var t := Db.tex(it.tex)
			# Native size, or half for the 32px chest and basket: whole pixels.
			var sz := Vector2(t.get_size())
			if sz.x > 16.0:
				sz *= 0.5
			draw_texture_rect(t, Rect2(p.pos - sz * 0.5 + Vector2(0, bob), sz), false)
