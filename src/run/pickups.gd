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
	_sweep_far(heroes, delta)
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

## Every few seconds, drops loose pickups left far behind every hero (chests
## stay: they're worth walking back for), so a long run never piles them up.
const FAR_GONE := 2500.0
var _sweep_clock := 0.0
func _sweep_far(heroes: Array, delta: float) -> void:
	_sweep_clock -= delta
	if _sweep_clock > 0.0:
		return
	_sweep_clock = 5.0
	var i := list.size() - 1
	while i >= 0:
		var p: Dictionary = list[i]
		if p.type != "chest" and heroes.all(func(h): return h.position.distance_squared_to(p.pos) > FAR_GONE * FAR_GONE):
			if p.type == "candy":
				_candy_count -= 1
			list.remove_at(i)
		i -= 1

# Guests draw whatever the host's snapshot says is on the ground.
const MIRROR_TYPES := ["candy0", "candy1", "candy2", "silver", "heart", "clock", "skull", "basket", "chest"]

func mirror_code(p: Dictionary) -> int:
	return int(p.tier) if p.type == "candy" else MIRROR_TYPES.find(p.type)

func mirror_apply(entries: Array) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	list.clear()
	for e in entries:
		var code: int = e[0]
		# `t` drives the spin and bob. Snapshots don't carry it, so it's
		# a phase from the position, run on the frame clock in _draw.
		var phase := fmod(absf(e[1].x * 0.37 + e[1].y * 0.61), 10.0)
		if code < 3:
			list.append({"type": "candy", "tier": code, "pos": e[1], "t": t, "phase": phase})
		elif code < MIRROR_TYPES.size():
			list.append({"type": MIRROR_TYPES[code], "pos": e[1], "t": t, "phase": phase})
	queue_redraw()

# Redraw every frame (guests only get new positions per snapshot) so the
# screen-pixel snapping below follows the camera.
func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# The candy art is drawn at half size, so each texel is only a screen pixel
	# or two. Drawn at fractional screen positions under the (unrounded) camera,
	# nearest sampling picks different texels every frame and the candy
	# shimmers. Snapping each item's corner to a whole screen pixel keeps the
	# same texels on screen while the view slides.
	var to_screen := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var to_local := to_screen.affine_inverse()
	var clock := Time.get_ticks_msec() / 1000.0
	for p in list:
		if p.has("phase"):
			p.t = clock + p.phase  # a co-op guest's copy: animate every frame
		var bob := sin(p.t * 4.0) * 1.0
		if p.type == "candy":
			var s := Db.sheet(Db.CANDY[p.tier].sheet)
			var sz := 12.0  # half of the 24px candy art
			var at := _snap(p.pos + Vector2(-sz * 0.5, -sz * 0.5 + bob), to_screen, to_local)
			draw_texture_rect_region(s._tex, Rect2(at, Vector2(sz, sz)), Db.frame_rect(s, p.t))
			continue
		var it: Dictionary = ITEMS[p.type]
		if it.has("sheet"):
			var s := Db.sheet(it.sheet)
			var at := _snap(p.pos + Vector2(-8, -8 + bob), to_screen, to_local)
			draw_texture_rect_region(s._tex, Rect2(at, Vector2(16, 16)), Db.frame_rect(s, p.t))
		else:
			var t := Db.tex(it.tex)
			# Native size, or half for the 32px chest and basket: whole pixels.
			var sz := Vector2(t.get_size())
			if sz.x > 16.0:
				sz *= 0.5
			draw_texture_rect(t, Rect2(_snap(p.pos - sz * 0.5 + Vector2(0, bob), to_screen, to_local), sz), false)

static func _snap(at: Vector2, to_screen: Transform2D, to_local: Transform2D) -> Vector2:
	return to_local * (to_screen * at).round()
