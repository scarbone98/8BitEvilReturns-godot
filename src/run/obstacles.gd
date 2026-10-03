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
	"grave_1_small": {"r": 7.0},
	"grave_2": {"r": 7.0},
	"tree": {"r": 7.0, "rare": true},
	"tree_2": {"r": 7.0, "rare": true},
	"tree_3": {"r": 7.0, "rare": true},
	"tree_4": {"r": 7.0, "rare": true},
	"tree_5": {"r": 7.0, "rare": true},
	"tree_6": {"r": 7.0, "rare": true},
	"street_lamp": {"r": 3.0, "sheet": "street_lamp"},
	"mausoleum": {"r": 30.0, "oy": 14.0, "rare": true},
}

var run
var kinds: Array = []
var _chunks := {}  # Vector2i -> Array of {kind, pos (feet), c (collision centre), r}
var _anim := 0.0

func setup(stage: Dictionary) -> void:
	kinds = stage.obstacles

func _chunk_props(c: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) ^ 0x8b17e1
	var out := []
	var n := rng.randi_range(0, 3)
	for k in n:
		var kind: String = kinds[rng.randi() % kinds.size()]
		if PROPS[kind].get("rare", false) and rng.randf() < 0.55:
			kind = "grave_1_small" if rng.randf() < 0.5 else "grave_2"
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
	return out

func _chunk(c: Vector2i) -> Array:
	var props = _chunks.get(c)
	if props == null:
		props = _chunk_props(c)
		_chunks[c] = props
	return props

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
			_chunks.erase(c)
	queue_redraw()

## Moves a circle at `p` out of any prop it overlaps.
func push_out(p: Vector2, r: float) -> Vector2:
	var c := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for o in _chunk(c + Vector2i(dx, dy)):
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

## Props below the player's feet line are drawn by the "front" layer so the
## hero walks behind tall trees and graves.
func draw_props(ci: CanvasItem, front: bool, split_y: float) -> void:
	var view: Rect2 = run.view_rect().grow(140)
	for props in _chunks.values():
		for o in props:
			if (o.pos.y > split_y) != front or not view.has_point(o.pos):
				continue
			var def: Dictionary = PROPS[o.kind]
			if def.has("sheet"):
				var s := Db.sheet(def.sheet)
				ci.draw_texture_rect_region(s._tex, Rect2(o.pos + Vector2(-s._w * 0.5, -s._h + 2), Vector2(s._w, s._h)), Db.frame_rect(s, _anim))
			else:
				var t := Db.tex(o.kind)
				var sz := Vector2(t.get_size())
				var scale := 0.5 if o.kind.begins_with("tree") else 1.0
				sz *= scale
				ci.draw_texture_rect(t, Rect2(o.pos + Vector2(-sz.x * 0.5, -sz.y + 4), sz), false)

func _draw() -> void:
	draw_props(self, false, run.player.position.y)
