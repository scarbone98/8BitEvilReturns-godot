class_name HandMan
extends HBoxContainer
## The floating hand from the original, with a speech bubble. It bobs and
## sways over the level-up and treasure screens and says one line at a time,
## typed out. say() changes the line (cards call it when highlighted).

const _Quips := preload("res://src/data/quips.gd")
const TYPE_SPEED := 45.0  # characters per second

var _hand: Control
var _label: Label
var _text := ""
var _shown := 0.0
var _t := 0.0

func _init(lines: Array = _Quips.LEVEL_UP) -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 64)
	_hand = Control.new()
	_hand.custom_minimum_size = Vector2(60, 64)
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand.draw.connect(_draw_hand)
	add_child(_hand)
	var bubble := PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f4efe4")
	style.border_color = Color.BLACK
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6; style.content_margin_right = 6
	style.content_margin_top = 3; style.content_margin_bottom = 4
	bubble.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_override("font", load("res://assets/fonts/PixelifySans.ttf"))
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color("1a1020"))
	_label.custom_minimum_size = Vector2(0, 26)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bubble.add_child(_label)
	add_child(bubble)
	say(lines.pick_random() if not lines.is_empty() else "")

func say(text: String) -> void:
	if text == _text:
		return
	_text = text
	_shown = 0.0
	_label.text = ""

func _process(delta: float) -> void:
	_t += delta
	if _shown < _text.length():
		_shown += delta * TYPE_SPEED
		_label.text = _text.substr(0, int(_shown))
	_hand.queue_redraw()

func _draw_hand() -> void:
	var s := Db.sheet("hand")
	var frame := int(_t * 6.0) % int(s.frames)
	var size := Vector2(56, 56)
	# Hover: bob up and down and sway a little, like it's floating.
	var bob := sin(_t * 3.0) * 3.0
	var sway := sin(_t * 1.7) * 0.12
	_hand.draw_set_transform(Vector2(30, 34 + bob), sway, Vector2.ONE)
	# A soft shadow below, shrinking as it rises.
	var sh := 1.0 - (bob + 3.0) / 12.0
	_hand.draw_set_transform(Vector2(30, 62), 0.0, Vector2(sh, 1.0))
	_hand.draw_circle(Vector2.ZERO, 10.0, Color(0, 0, 0, 0.25))
	_hand.draw_set_transform(Vector2(30, 34 + bob), sway, Vector2.ONE)
	_hand.draw_texture_rect_region(s._tex, Rect2(-size * 0.5, size), Rect2(frame * s._w, 0, s._w, s._h))
	_hand.draw_set_transform(Vector2.ZERO)
