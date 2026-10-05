extends Node2D
## A map's quest relic lying on the ground: bobbing, glinting, waiting to be
## picked up (see Run._check_relic). Position is its feet, in the y-sorted world.

var sprite := ""
var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var tex := Db.tex(sprite)
	var sz := Vector2(tex.get_size())
	var bob := roundf(sin(_t * 3.0) * 1.5)
	# a soft gold glow on the ground, pulsing
	var a := 0.25 + sin(_t * 4.0) * 0.1
	draw_circle(Vector2(0, -1), 9.0, Color(1.0, 0.85, 0.3, a))
	draw_texture_rect(tex, Rect2(Vector2(-sz.x * 0.5, -sz.y - 3 + bob), sz), false)
	# a glint that sweeps every couple of seconds
	var g := fmod(_t, 2.2)
	if g < 0.3:
		var p := Vector2(-sz.x * 0.5 + sz.x * (g / 0.3), -sz.y * 0.6 + bob)
		draw_rect(Rect2(p, Vector2(1, 1)), Color.WHITE)
		draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), Color(1, 1, 1, 0.6))
		draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), Color(1, 1, 1, 0.6))
