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
	list.append({"type": type, "pos": at, "t": 0.0, "pull": false, "value": 0})

func pull_all_candy() -> void:
	for p in list:
		if p.type == "candy":
			p.pull = true

func step(delta: float) -> void:
	var player = run.player
	var ppos: Vector2 = player.position
	var mag: float = player.magnet_radius()
	var i := list.size() - 1
	while i >= 0:
		var p: Dictionary = list[i]
		p.t += delta
		var to: Vector2 = ppos - p.pos
		var d := to.length()
		if p.type != "chest" and d < mag:
			p.pull = true
		if p.pull or (p.type == "chest" and d < 14.0):
			var spd: float = 60.0 + p.t * 40.0 if p.type != "chest" else 0.0
			p.pos += to.normalized() * minf(d, maxf(spd, 180.0) * delta)
		if d < 8.0 or (p.type == "chest" and d < 12.0):
			if p.type == "candy":
				_candy_count -= 1
			list.remove_at(i)
			run.collect(p)
		i -= 1
	queue_redraw()

func _draw() -> void:
	for p in list:
		var bob := sin(p.t * 4.0) * 1.0
		if p.type == "candy":
			var s := Db.sheet(Db.CANDY[p.tier].sheet)
			var sz := 12.0 if p.tier == 0 else 14.0
			draw_texture_rect_region(s._tex, Rect2(p.pos + Vector2(-sz * 0.5, -sz * 0.5 + bob), Vector2(sz, sz)), Db.frame_rect(s, p.t))
			continue
		var it: Dictionary = ITEMS[p.type]
		if it.has("sheet"):
			var s := Db.sheet(it.sheet)
			draw_texture_rect_region(s._tex, Rect2(p.pos + Vector2(-6, -6 + bob), Vector2(12, 12)), Db.frame_rect(s, p.t))
		else:
			var t := Db.tex(it.tex)
			var sz := Vector2(t.get_size()).clamp(Vector2.ZERO, Vector2(18, 18))
			if p.type == "chest":
				sz = Vector2(20, 20)
			draw_texture_rect(t, Rect2(p.pos - sz * 0.5 + Vector2(0, bob), sz), false)
