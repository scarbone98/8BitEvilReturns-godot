extends Node2D
## Graves, trees and lamps scattered over an endless graveyard. The world is
## split into chunks; each chunk's props come from a hash of its coordinates,
## so the same spot always has the same props without storing anything, on
## every player's device. A chunk is built the first time anything asks about
## it (drawing, collision, spawning), so collision works anywhere, including
## around other players in co-op.

const CHUNK := 160.0
const KEEP := 2         # chunks kept around each hero in each direction
const START_CLEAR := 64.0  # no props this close to where heroes start

# Collision circle per prop: radius, and how far above the sprite's feet its
# centre sits (big buildings block their whole base, not just the doorstep).
const PROPS := {
	"grave_1_small": {"r": 11.0},  # about the stone's half-width
	"grave_2": {"r": 10.0},
	"tree": {"r": 7.0, "rare": true},
	"tree_2": {"r": 7.0, "rare": true},
	"tree_3": {"r": 7.0, "rare": true},
	"tree_4": {"r": 7.0, "rare": true},
	"tree_5": {"r": 7.0, "rare": true},
	"tree_6": {"r": 7.0, "rare": true},
	"street_lamp": {"r": 3.0, "sheet": "street_lamp"},
	"mausoleum": {"r": 30.0, "oy": 14.0, "rare": true},
	"tree_owl": {"r": 7.0, "sheet": "tree_owl", "rare": true},
	"candybasket": {"r": 7.0},
	# Drawn by tools/draw_props.py
	"prop_angel": {"r": 7.0, "rare": true},
	"prop_open_grave": {"r": 10.0},
	"prop_blood_fountain": {"r": 16.0, "oy": 4.0, "sheet": "prop_blood_fountain", "rare": true},
	"prop_gibbet": {"r": 6.0},
	"prop_obelisk": {"r": 7.0, "sheet": "prop_obelisk", "rare": true},
	"prop_hay_bale": {"r": 13.0},
	"prop_pumpkin_pile": {"r": 12.0},
	"prop_corn": {"r": 8.0},
	"prop_fence": {"r": 12.0},
	"prop_scarecrow": {"r": 5.0, "rare": true},
	"prop_snow_pine": {"r": 8.0, "rare": true},
	"prop_snowman": {"r": 7.0},
	"prop_ice_grave": {"r": 10.0},
	"prop_snow_angel": {"r": 7.0, "rare": true},
	"prop_sewer_pipe": {"r": 16.0, "oy": 6.0, "sheet": "prop_sewer_pipe"},
	"prop_barrels": {"r": 13.0},
	"prop_brick_pillar": {"r": 8.0},
	"prop_sarcophagus": {"r": 15.0, "oy": 4.0},
	"prop_broken_pillar": {"r": 8.0},
	"prop_candelabra": {"r": 4.0, "sheet": "prop_candelabra"},
}

# Flat things lying on the ground: drawn under everything, no collision.
const DECOR := {
	"sewer": {},
	"skull": {},
	"blood": {},
	"prop_bones": {},
}

var run
var kinds: Array = []
var _commons: Array = []  # this stage's non-rare props, to swap in for rare ones
var _decor: Array = []    # this stage's flat decor kinds
var _density := Vector2i(0, 3)  # props tried per chunk (min, max)
var layer: Node2D  # the run's y-sorted layer: props are sprites in it, next to the heroes
var _chunks := {}  # Vector2i -> Array of {kind, pos (feet), c (collision centre), r, rect, sprite}
var _anim := 0.0
var _animated: Array = []  # sprites with frames (street lamps)

func setup(stage: Dictionary) -> void:
	kinds = stage.obstacles
	_commons = kinds.filter(func(k): return not PROPS[k].get("rare", false))
	_decor = stage.get("decor", [])
	var d: Array = stage.get("props_per_chunk", [0, 3])
	_density = Vector2i(d[0], d[1])

func _chunk_props(c: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) ^ 0x8b17e1
	var out := []
	var n := rng.randi_range(_density.x, _density.y)
	for k in n:
		var kind: String = kinds[rng.randi() % kinds.size()]
		if PROPS[kind].get("rare", false) and rng.randf() < 0.55 and not _commons.is_empty():
			kind = _commons[rng.randi() % _commons.size()]
		var def: Dictionary = PROPS[kind]
		var r: float = def.r
		# Keep big props off the chunk edge so they never overlap a neighbour's.
		var margin := maxf(12.0, r + 8.0)
		var p := Vector2(c) * CHUNK + Vector2(rng.randf_range(margin, CHUNK - margin), rng.randf_range(margin + def.get("oy", 0.0), CHUNK - margin))
		var centre := p - Vector2(0, def.get("oy", 0.0))
		if centre.length() < START_CLEAR + r:
			continue
		var ok := true
		for o in out:
			if o.c.distance_to(centre) < o.r + r + 24.0:
				ok = false
		if ok:
			out.append({"kind": kind, "pos": p, "c": centre, "r": r})
	# Flat decor: anywhere in the chunk, no collision.
	if not _decor.is_empty():
		for k in rng.randi_range(0, 2):
			var d: String = _decor[rng.randi() % _decor.size()]
			out.append({"kind": d, "decor": true, "pos": Vector2(c) * CHUNK + Vector2(rng.randf_range(8, CHUNK - 8), rng.randf_range(8, CHUNK - 8)), "c": Vector2.ZERO, "r": 0.0})
	return out

func _chunk(c: Vector2i) -> Array:
	var props = _chunks.get(c)
	if props == null:
		props = _chunk_props(c)
		for o in props:
			_make_sprite(o)
		_chunks[c] = props
	return props

## Each prop is a Sprite2D in the y-sorted layer, its origin at its feet, so
## heroes walk in front of or behind it by where they stand.
func _make_sprite(o: Dictionary) -> void:
	if o.get("decor", false):
		var t := Db.tex(o.kind)
		o["rect"] = Rect2(o.pos - Vector2(t.get_size()) * 0.5, t.get_size())
		return  # drawn flat by this node, under everything
	var def: Dictionary = PROPS[o.kind]
	var sp := Sprite2D.new()
	sp.centered = false
	sp.position = o.pos
	var w: float
	var h: float
	var lift := 4.0
	if def.has("sheet"):
		var sh := Db.sheet(def.sheet)
		sp.texture = sh._tex
		sp.hframes = int(sh.frames)
		w = sh._w
		h = sh._h
		lift = 2.0
		_animated.append(sp)
	else:
		sp.texture = Db.tex(o.kind)
		w = sp.texture.get_width()
		h = sp.texture.get_height()
	var k := 0.5 if o.kind.begins_with("tree") else 1.0
	sp.scale = Vector2(k, k)
	sp.offset = Vector2(-w * 0.5, -h + lift / k)
	# Where it's drawn, for sorting enemies against it.
	o["rect"] = Rect2(o.pos + Vector2(-w * 0.5 * k, -h * k + lift), Vector2(w * k, h * k))
	o["sprite"] = sp
	if layer:
		layer.add_child(sp)

func _free_chunk(c: Vector2i) -> void:
	for o in _chunks[c]:
		var sp: Sprite2D = o.get("sprite")
		if sp:
			_animated.erase(sp)
			sp.queue_free()
	_chunks.erase(c)

## Props near enough to `view` to matter for drawing.
func props_in(view: Rect2) -> Array:
	var out := []
	for props in _chunks.values():
		for o in props:
			if not o.get("decor", false) and view.intersects(o.rect):
				out.append(o)
	return out

## Keeps the chunks around every hero, drops the rest.
func update_around(centers: Array) -> void:
	_anim += get_process_delta_time()
	var wanted := {}
	for center in centers:
		var cc := Vector2i(floori(center.x / CHUNK), floori(center.y / CHUNK))
		for x in range(cc.x - KEEP, cc.x + KEEP + 1):
			for y in range(cc.y - KEEP - 1, cc.y + KEEP + 2):
				var c := Vector2i(x, y)
				wanted[c] = true
				_chunk(c)
	for c in _chunks.keys():
		if not wanted.has(c):
			_free_chunk(c)
	var f := int(_anim * 6.0)
	for sp in _animated:
		sp.frame = f % sp.hframes
	queue_redraw()

func _draw() -> void:
	var view: Rect2 = run.view_rect().grow(32)
	for props in _chunks.values():
		for o in props:
			if o.get("decor", false) and view.has_point(o.pos):
				var t := Db.tex(o.kind)
				draw_texture_rect(t, Rect2((o.pos - Vector2(t.get_size()) * 0.5).floor(), t.get_size()), false, Color(1, 1, 1, 0.75))

## Moves a circle at `p` out of any prop it overlaps.
func push_out(p: Vector2, r: float) -> Vector2:
	var c := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for o in _chunk(c + Vector2i(dx, dy)):
				if o.get("decor", false):
					continue
				var off: Vector2 = p - o.c
				var min_d: float = o.r + r
				if off.length_squared() < min_d * min_d:
					if off.length_squared() < 0.001:
						off = Vector2.DOWN
					p = o.c + off.normalized() * min_d
	return p

## True if a circle at `p` touches no prop.
func is_free(p: Vector2, r: float) -> bool:
	var c := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for o in _chunk(c + Vector2i(dx, dy)):
				if o.get("decor", false):
					continue
				var min_d: float = o.r + r
				if p.distance_squared_to(o.c) < min_d * min_d:
					return false
	return true

## The nearest spot to `p` where a circle of radius r fits: pushed clear of
## props, checked again in case that landed it in a neighbouring one.
func free_spot(p: Vector2, r: float) -> Vector2:
	for k in 4:
		if is_free(p, r):
			return p
		p = push_out(p, r + 1.0)
	return p

