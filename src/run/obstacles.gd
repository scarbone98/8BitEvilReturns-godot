extends Node2D
## Graves, trees and lamps scattered over an endless graveyard. The world is
## split into chunks; each chunk's props come from a hash of its coordinates,
## so the same spot always has the same props without storing anything.

const CHUNK := 160.0
const KEEP := 2  # chunks kept around the camera in each direction

# Collision circle (radius, y offset from the sprite's feet) per prop.
const PROPS := {
	"grave_1_small": {"r": 6.0},
	"grave_2": {"r": 6.0},
	"tree": {"r": 7.0, "rare": true},
	"tree_2": {"r": 7.0, "rare": true},
	"tree_3": {"r": 7.0, "rare": true},
	"tree_4": {"r": 7.0, "rare": true},
	"tree_5": {"r": 7.0, "rare": true},
	"tree_6": {"r": 7.0, "rare": true},
	"street_lamp": {"r": 3.0, "sheet": "street_lamp"},
	"mausoleum": {"r": 18.0, "rare": true},
}

var run
var kinds: Array = []
var _chunks := {}  # Vector2i -> Array of {kind, pos, r}
var _anim := 0.0

func setup(stage: Dictionary) -> void:
	kinds = stage.obstacles

func _chunk_props(c: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) ^ 0x8b17e1
	var out := []
	# Leave the start area clear.
	if absi(c.x) <= 0 and absi(c.y) <= 0:
		return out
	var n := rng.randi_range(0, 3)
	for k in n:
		var kind: String = kinds[rng.randi() % kinds.size()]
		if PROPS[kind].get("rare", false) and rng.randf() < 0.55:
			kind = "grave_1_small" if rng.randf() < 0.5 else "grave_2"
		var p := Vector2(c) * CHUNK + Vector2(rng.randf_range(12, CHUNK - 12), rng.randf_range(12, CHUNK - 12))
		var ok := true
		for o in out:
			if o.pos.distance_to(p) < 40.0:
				ok = false
		if ok:
			out.append({"kind": kind, "pos": p, "r": PROPS[kind].r})
	return out

func update_around(center: Vector2) -> void:
	_anim += get_process_delta_time()
	var cc := Vector2i(floori(center.x / CHUNK), floori(center.y / CHUNK))
	var wanted := {}
	for x in range(cc.x - KEEP, cc.x + KEEP + 1):
		for y in range(cc.y - KEEP - 1, cc.y + KEEP + 2):
			var c := Vector2i(x, y)
			wanted[c] = true
			if not _chunks.has(c):
				_chunks[c] = _chunk_props(c)
	for c in _chunks.keys():
		if not wanted.has(c):
			_chunks.erase(c)
	queue_redraw()

## Moves a circle at `p` out of any prop it overlaps.
func push_out(p: Vector2, r: float) -> Vector2:
	var c := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var props = _chunks.get(c + Vector2i(dx, dy))
			if props == null:
				continue
			for o in props:
				var off: Vector2 = p - o.pos
				var min_d: float = o.r + r
				if off.length_squared() < min_d * min_d:
					if off.length_squared() < 0.001:
						off = Vector2.DOWN
					p = o.pos + off.normalized() * min_d
	return p

## Props below the player's feet line are drawn by the "front" layer so the
## hero walks behind tall trees and graves.
func draw_props(ci: CanvasItem, front: bool, split_y: float) -> void:
	for props in _chunks.values():
		for o in props:
			if (o.pos.y > split_y) != front:
				continue
			var def: Dictionary = PROPS[o.kind]
			if def.has("sheet"):
				var s := Db.sheet(def.sheet)
				ci.draw_texture_rect_region(s._tex, Rect2(o.pos + Vector2(-s._w * 0.5, -s._h + 2), Vector2(s._w, s._h)), Db.frame_rect(s, _anim))
			else:
				var t := Db.tex(o.kind)
				var sz := Vector2(t.get_size())
				var scale := 0.6 if o.kind.begins_with("tree") else 1.0
				sz *= scale
				ci.draw_texture_rect(t, Rect2(o.pos + Vector2(-sz.x * 0.5, -sz.y + 4), sz), false)

func _draw() -> void:
	draw_props(self, false, run.player.position.y)
