extends Node2D
## Floating damage numbers.

const MAX := 80

var font: Font
var list: Array[Dictionary] = []

func _ready() -> void:
	font = load("res://assets/fonts/PixelifySans.ttf")

var fresh: Array = []  # host: numbers made since the last snapshot, for guests

func add(at: Vector2, amount: float) -> void:
	if fresh.size() < 200:
		fresh.append([at, amount])
	if list.size() >= MAX:
		list.pop_front()
	list.append({"pos": at + Vector2(randf_range(-3, 3), 0), "text": str(roundi(amount)), "t": 0.0})

func step(delta: float) -> void:
	var i := list.size() - 1
	while i >= 0:
		var p: Dictionary = list[i]
		p.t += delta
		p.pos.y -= 14.0 * delta
		if p.t > 0.5:
			list.remove_at(i)
		i -= 1
	queue_redraw()

func _draw() -> void:
	for p in list:
		var a := clampf(1.0 - (p.t - 0.3) / 0.2, 0.0, 1.0)
		draw_string_outline(font, p.pos, p.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 8, 2, Color(0, 0, 0, a))
		draw_string(font, p.pos, p.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(1, 1, 1, a))
