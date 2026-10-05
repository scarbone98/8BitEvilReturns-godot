extends Node2D
## Graves, trees and lamps scattered over an endless graveyard. The world is
## split into chunks; each chunk's props come from a hash of its coordinates,
## so the same spot always has the same props without storing anything, on
## every player's device. A chunk is built the first time anything asks about
## it (drawing, collision, spawning), so collision works anywhere, including
## around other players in co-op.
##
## Each chunk follows one of its stage's `layouts` (see stages.gd): neat rows
## and grids of graves, groves, a landmark with things placed around it, a
## run of fence or wall, or open ground. Coarse "neighbourhoods" (3x3 chunks)
## lean dense or sparse so the map has built-up blocks and open fields.

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
	"prop_hay_bale": {"r": 15.0, "circles": [[-8, -6, 8], [8, -6, 8]]},
	"prop_pumpkin_pile": {"r": 13.0, "circles": [[-7, -5, 7], [7, -5, 7]]},
	"prop_corn": {"r": 8.0},
	"prop_fence": {"r": 20.0, "circles": [[-14, -4, 6], [0, -4, 6], [14, -4, 6]]},
	"prop_scarecrow": {"r": 5.0, "rare": true},
	"prop_snow_pine": {"r": 8.0, "rare": true},
	"prop_snowman": {"r": 7.0},
	"prop_ice_grave": {"r": 10.0},
	"prop_snow_angel": {"r": 7.0, "rare": true},
	"prop_sewer_pipe": {"r": 20.0, "oy": 6.0, "sheet": "prop_sewer_pipe", "circles": [[-13, -8, 9], [0, -8, 9], [13, -8, 9]]},
	"prop_barrels": {"r": 14.0, "circles": [[-7, -6, 8], [7, -6, 8]]},
	"prop_brick_pillar": {"r": 8.0},
	"prop_sarcophagus": {"r": 20.0, "oy": 4.0, "circles": [[-12, -8, 9], [0, -8, 9], [12, -8, 9]]},
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
var _density := Vector2i(0, 3)  # props tried per chunk (min, max), for "scatter"
var _layouts: Array = []  # this stage's layout templates (stages.gd)
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
	_layouts = stage.get("layouts", [])

func _chunk_props(c: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) ^ 0x8b17e1
	var out := []
	var origin := Vector2(c) * CHUNK
	if _layouts.is_empty():
		_scatter(rng, origin, out)
	else:
		var layout := _pick_layout(c, rng)
		var items := _place(layout, rng)
		# Slide the whole layout somewhere inside the chunk (as far as it has
		# room), so repeats don't line up on the chunk grid.
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for item in items:
			var def: Dictionary = PROPS[item[0]]
			lo = lo.min(item[1] - Vector2(def.r, def.r + def.get("oy", 0.0)))
			hi = hi.max(item[1] + Vector2(def.r, 2.0))
		var shift := Vector2.ZERO
		if not items.is_empty():
			var room := Vector2(CHUNK * 0.5 - 4.0, CHUNK * 0.5 - 4.0)
			shift.x = rng.randf_range(-room.x - lo.x, room.x - hi.x) if room.x - hi.x > -room.x - lo.x else 0.0
			shift.y = rng.randf_range(-room.y - lo.y, room.y - hi.y) if room.y - hi.y > -room.y - lo.y else 0.0
		for item in items:
			_try_add(out, item[0], origin + Vector2(CHUNK * 0.5, CHUNK * 0.5) + item[1] + shift, 0)
		if out.is_empty() and layout.get("t") == "scatter":
			_scatter(rng, origin, out)
	# Flat decor: anywhere in the chunk, no collision.
	if not _decor.is_empty():
		for k in rng.randi_range(0, 2):
			var d: String = _decor[rng.randi() % _decor.size()]
			out.append({"kind": d, "decor": true, "pos": origin + Vector2(rng.randf_range(8, CHUNK - 8), rng.randf_range(8, CHUNK - 8)), "c": Vector2.ZERO, "r": 0.0})
	return out

## The old rule: a few random props at random spots.
func _scatter(rng: RandomNumberGenerator, origin: Vector2, out: Array) -> void:
	for k in rng.randi_range(_density.x, _density.y):
		var kind: String = kinds[rng.randi() % kinds.size()]
		if PROPS[kind].get("rare", false) and rng.randf() < 0.55 and not _commons.is_empty():
			kind = _commons[rng.randi() % _commons.size()]
		var r: float = PROPS[kind].r
		var margin := maxf(12.0, r + 8.0)
		_try_add(out, kind, origin + Vector2(rng.randf_range(margin, CHUNK - margin), rng.randf_range(margin + PROPS[kind].get("oy", 0.0), CHUNK - margin)), -1)

## Neighbourhoods: every 3x3 block of chunks leans sparse, normal or dense,
## which scales how often a chunk is left open.
func _pick_layout(c: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	var block := Vector2i(floori(c.x / 3.0), floori(c.y / 3.0))
	var lean := absi(hash(block) ^ 0x51ed27) % 4  # 0 sparse, 1-2 normal, 3 dense
	var open_mul: float = [3.0, 1.0, 1.0, 0.25][lean]
	var total := 0.0
	for l in _layouts:
		total += float(l.get("w", 1.0)) * (open_mul if l.t == "open" else 1.0)
	var roll := rng.randf() * total
	for l in _layouts:
		roll -= float(l.get("w", 1.0)) * (open_mul if l.t == "open" else 1.0)
		if roll <= 0.0:
			return l
	return _layouts[-1]

func _pick(rng: RandomNumberGenerator, list: Array) -> String:
	return list[rng.randi() % list.size()]

func _irange(rng: RandomNumberGenerator, v) -> int:
	return rng.randi_range(int(v[0]), int(v[1])) if v is Array else int(v)

## A layout's props as [kind, offset from the chunk centre (feet)].
func _place(l: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out := []
	var jit := func(): return Vector2(rng.randf_range(-2, 2), rng.randf_range(-1, 1))
	match str(l.t):
		"row":
			# A straight row, one kind (or alternating `kinds` if `mix`).
			var n := _irange(rng, l.n)
			var gap: float = l.gap
			var kind := _pick(rng, l.kinds)
			var vertical: bool = rng.randf() < float(l.get("vertical", 0.0))
			for i in n:
				var k: String = l.kinds[i % l.kinds.size()] if l.get("mix", false) else kind
				var off := (i - (n - 1) * 0.5) * gap
				out.append([k, (Vector2(0, off) if vertical else Vector2(off, 0)) + jit.call()])
		"grid":
			# Rows of graves like a cemetery plot, an odd one missing.
			var cols := _irange(rng, l.cols)
			var rows := _irange(rng, l.rows)
			var g: Array = l.gap
			for y in rows:
				for x in cols:
					if rng.randf() < float(l.get("missing", 0.15)):
						continue
					var at := Vector2((x - (cols - 1) * 0.5) * float(g[0]), (y - (rows - 1) * 0.5) * float(g[1]))
					out.append([_pick(rng, l.kinds), at + jit.call()])
		"grove":
			# A loose cluster, nothing too close together.
			var n := _irange(rng, l.n)
			var rad: float = l.r
			var spots: Array = []
			for tries in n * 6:
				if spots.size() >= n:
					break
				var p := Vector2.RIGHT.rotated(rng.randf() * TAU) * sqrt(rng.randf()) * rad
				if spots.all(func(q): return q.distance_to(p) > float(l.get("spacing", 18.0))):
					spots.append(p)
			for p in spots:
				out.append([_pick(rng, l.kinds), p])
		"landmark":
			# A centrepiece, with accents set symmetrically around it.
			out.append([_pick(rng, l.center), Vector2.ZERO])
			var accent := _pick(rng, l.around)
			for spot in l.spots:
				out.append([accent, Vector2(spot[0], spot[1])])
		"line":
			# A solid run (fence, wall) with an optional gap to walk through.
			var n := _irange(rng, l.n)
			var w: float = l.gap
			# Long runs always leave a way through (`always_hole_from` pieces up),
			# never at the very end, so nothing walks into a dead end.
			var need_hole: bool = n >= int(l.get("always_hole_from", 99))
			var hole := rng.randi_range(1, n - 2) if need_hole else (rng.randi_range(0, n) if rng.randf() < float(l.get("hole", 0.0)) else -1)
			for i in n:
				if i == hole:
					continue
				out.append([_pick(rng, l.kinds), Vector2((i - (n - 1) * 0.5) * w, 0)])
		"aisle":
			# Two columns facing each other, things down the middle.
			var n := _irange(rng, l.n)
			var gx: float = l.gap[0]
			var gy: float = l.gap[1]
			for i in n:
				var y := (i - (n - 1) * 0.5) * gy
				out.append([_pick(rng, l.kinds), Vector2(-gx * 0.5, y)])
				out.append([_pick(rng, l.kinds), Vector2(gx * 0.5, y)])
			if l.has("middle"):
				out.append([_pick(rng, l.middle), Vector2(0, (n - 1) * 0.5 * gy)])
		"scatter", "open":
			pass
	return out

## Adds a prop if it fits: inside the chunk, clear of the start, and not on
## top of another prop.
func _try_add(out: Array, kind: String, p: Vector2, group: int) -> void:
	var def: Dictionary = PROPS[kind]
	var r: float = def.r
	var centre := p - Vector2(0, def.get("oy", 0.0))
	var cc := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	# Keep each prop's whole footprint inside its own chunk so neighbours never overlap.
	var lo := p - Vector2(r, r + def.get("oy", 0.0))
	var hi := p + Vector2(r, 2.0)
	var o0 := Vector2(cc) * CHUNK
	if lo.x < o0.x + 2.0 or hi.x > o0.x + CHUNK - 2.0 or lo.y < o0.y + 2.0 or hi.y > o0.y + CHUNK - 2.0:
		return
	if centre.length() < START_CLEAR + r:
		return
	var cs := []
	for cir in def.get("circles", []):
		cs.append([p + Vector2(cir[0], cir[1]), float(cir[2])])
	for o in out:
		if o.get("decor", false):
			continue
		var min_gap := 2.0 if group >= 0 and o.get("group", -2) == group else 20.0
		if o.c.distance_to(centre) < o.r + r + min_gap - (14.0 if group >= 0 and o.get("group", -2) == group else 0.0):
			return
	out.append({"kind": kind, "pos": p, "c": centre, "r": r, "cs": cs, "group": group})

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
				if not o.get("cs", []).is_empty():
					for cir in o.cs:
						p = _push_circle(p, r, cir[0], cir[1])
					continue
				p = _push_circle(p, r, o.c, o.r)
	return p

## Dev (trapdemo): a closed ring of collision circles round `c`, added to its
## chunk, with no sprites.
func add_ring(c: Vector2, radius: float) -> void:
	var cs := []
	for k in 24:
		cs.append([c + Vector2.RIGHT.rotated(TAU * k / 24.0) * radius, 5.0])
	var props: Array = _chunk(Vector2i(floori(c.x / CHUNK), floori(c.y / CHUNK)))
	props.append({"kind": "trap", "pos": c, "c": c, "r": radius + 5.0, "cs": cs, "group": -9, "rect": Rect2(c, Vector2.ZERO)})

func _push_circle(p: Vector2, r: float, c: Vector2, cr: float) -> Vector2:
	var off: Vector2 = p - c
	var min_d: float = cr + r
	if off.length_squared() < min_d * min_d:
		if off.length_squared() < 0.001:
			off = Vector2.DOWN
		return c + off.normalized() * min_d
	return p

## True if a circle at `p` touches no prop.
func is_free(p: Vector2, r: float) -> bool:
	var c := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for o in _chunk(c + Vector2i(dx, dy)):
				if o.get("decor", false):
					continue
				if not o.get("cs", []).is_empty():
					for cir in o.cs:
						if p.distance_squared_to(cir[0]) < (cir[1] + r) * (cir[1] + r):
							return false
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

