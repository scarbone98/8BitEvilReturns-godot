class_name SheetView
extends Control
## Plays a Db sprite sheet inside UI, scaled to fit.

var sheet_id := ""
var tint := Color.WHITE
var _t := 0.0

func _init(id := "", min_size := Vector2(32, 32)) -> void:
	sheet_id = id
	custom_minimum_size = min_size
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = TEXTURE_FILTER_NEAREST

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	if sheet_id == "":
		return
	var s := Db.sheet(sheet_id)
	var k := minf(size.x / s._w, size.y / s._h)
	k = maxf(1.0, floorf(k)) if k >= 1.0 else k
	var sz := Vector2(s._w, s._h) * k
	draw_texture_rect_region(s._tex, Rect2((size - sz) * 0.5, sz), Db.frame_rect(s, _t), tint)
