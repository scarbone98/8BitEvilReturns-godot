class_name UI
extends RefCounted
## Shared look: pixel fonts, the original's panel frames, small builders.

const GOLD := Color("ffd35a")
const RED := Color("e0433b")
const PALE := Color("e8e0f0")
const DIM := Color("9a8fb0")

static var _theme: Theme

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	var font: Font = load("res://assets/fonts/PressStart2P.ttf")
	t.default_font = font
	t.default_font_size = 8
	t.set_color("font_color", "Label", PALE)
	t.set_constant("outline_size", "Label", 0)
	t.set_color("font_color", "Button", PALE)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_focus_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_stylebox("normal", "Button", frame(false))
	t.set_stylebox("hover", "Button", frame(true))
	t.set_stylebox("pressed", "Button", frame(true))
	t.set_stylebox("focus", "Button", frame(true))
	t.set_stylebox("disabled", "Button", frame(false, 0.5))
	t.set_stylebox("panel", "PanelContainer", frame(false))
	_theme = t
	return t

## 9-slice of the original GUI_border / GUI_border_Selected art.
static func frame(selected: bool, alpha := 1.0) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = Db.tex("GUI_border_Selected" if selected else "GUI_border")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		s.set_texture_margin(side, 10)
		s.set_content_margin(side, 6)
	s.modulate_color = Color(1, 1, 1, alpha)
	return s

static func label(text: String, size := 8, color := PALE, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3 if size >= 8 else 2)
	return l

static func body(text: String, size := 11, color := PALE) -> Label:
	# The rounder Pixelify font is easier to read for longer text.
	var l := label(text, size, color)
	l.add_theme_font_override("font", load("res://assets/fonts/PixelifySans.ttf"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func button(text: String, on_press: Callable, min_h := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(on_press)
	return b

static func icon(tex: Texture2D, size := 24) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return r

static func dim_overlay() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.03, 0.01, 0.06, 0.78)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c

static func time_text(seconds: float) -> String:
	var s := int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]
