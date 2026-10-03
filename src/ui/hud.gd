extends Control
## In-run heads-up display, drawn directly for crisp pixels.

signal pause_pressed

const HEART_HP := 20.0

var run
var font: Font
var body_font: Font

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	font = load("res://assets/fonts/PressStart2P.ttf")
	body_font = load("res://assets/fonts/PixelifySans.ttf")
	var pause := Button.new()
	pause.icon = Db.tex("GUI_button_small")
	pause.flat = true
	pause.expand_icon = false
	pause.custom_minimum_size = Vector2(16, 16)
	pause.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	pause.offset_left = -22; pause.offset_right = -6
	pause.offset_top = 46; pause.offset_bottom = 62
	pause.focus_mode = FOCUS_NONE
	pause.pressed.connect(func(): pause_pressed.emit())
	add_child(pause)

var _toasts: Array = []  # [text, colour, seconds left]
var _banner := ""

## A message that stays up until cleared with "" (e.g. "Reconnecting...").
func banner(text: String) -> void:
	_banner = text

## A short message under the timer (chest contents in co-op, "you're down"...).
func toast(text: String, col := UI.PALE) -> void:
	_toasts.append([text, col, 2.5])
	if _toasts.size() > 4:
		_toasts.pop_front()

func _process(d: float) -> void:
	for t in _toasts:
		t[2] -= d
	_toasts = _toasts.filter(func(t): return t[2] > 0.0)
	queue_redraw()

func _text(pos: Vector2, text: String, size := 8, col := UI.PALE, align := HORIZONTAL_ALIGNMENT_LEFT, f: Font = null) -> void:
	f = f if f else font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		pos.x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		pos.x -= w
	draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color.BLACK)
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

## Draws a texture centred in a box at a whole-pixel scale (1x, 1/2, 1/4, 2x...).
func _icon(t: Texture2D, center: Vector2, box: float) -> void:
	var sz := Vector2(t.get_size())
	var k := UI.pixel_scale(maxf(sz.x, sz.y), box)
	draw_texture_rect(t, Rect2((center - sz * k * 0.5).floor(), sz * k), false)

func _draw() -> void:
	if run == null:
		return
	var p = run.player
	var view := get_viewport_rect().size
	var W := view.x
	# XP bar from the original art at 1x: the candy cap and left end, the bar
	# body stretched from a single plain column, and the right end.
	var bar := Db.tex("xpbar")
	var x0 := 4.0
	var x1 := W - 4.0
	var mid_from := x0 + 40.0
	var mid_to := x1 - 16.0
	draw_texture_rect_region(bar, Rect2(x0, 0, 40, 32), Rect2(0, 0, 40, 32))
	draw_texture_rect_region(bar, Rect2(mid_from, 0, mid_to - mid_from, 32), Rect2(60, 0, 1, 32))
	draw_texture_rect_region(bar, Rect2(mid_to, 0, 16, 32), Rect2(240, 0, 16, 32))
	var frac: float = clampf(run.xp / run.xp_next, 0.0, 1.0)
	var fill_from := x0 + 26.0
	var fill_len := (x1 - 4.0) - fill_from
	draw_rect(Rect2(fill_from, 13, floorf(fill_len * frac), 6), Color("5ad1ff"))
	_text(Vector2(W - 6, 38), "LV %d" % run.level, 8, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	# Timer, the score.
	_text(Vector2(W * 0.5, 44), UI.time_text(run.time), 12, UI.PALE, HORIZONTAL_ALIGNMENT_CENTER)
	# Hearts at exactly half size, seven to a row so they stay clear of the timer.
	var hearts := ceili(p.max_hp() / HEART_HP)
	var hp: float = p.hp
	for i in hearts:
		var r := Rect2(6 + (i % 7) * 10, 30 + (i / 7) * 10, 8, 8)
		draw_texture_rect(Db.tex("heart_empty"), r, false)
		var fill := clampf((hp - i * HEART_HP) / HEART_HP, 0.0, 1.0)
		if fill > 0.0:
			# Fill in whole source pixels so the half-heart edge stays crisp.
			var cols := ceilf(16.0 * fill / 2.0) * 2.0
			draw_texture_rect_region(Db.tex("heart"), Rect2(r.position, Vector2(cols * 0.5, 8)), Rect2(0, 0, cols, 16))
	# Kills and silver, icons at their native 16px.
	var sy := 30.0 + ceilf(hearts / 7.0) * 10.0 + 2.0
	draw_texture_rect(Db.tex("skull"), Rect2(4, sy, 16, 16), false)
	_text(Vector2(22, sy + 12), str(p.kills), 8)
	var coin := Db.sheet("silver")
	draw_texture_rect_region(coin._tex, Rect2(4, sy + 17, 16, 16), Rect2(0, 0, coin._w, coin._h))
	_text(Vector2(22, sy + 29), str(p.silver_found), 8)
	if _banner != "":
		var by := view.y * 0.4
		draw_rect(Rect2(0, by - 14, W, 22), Color(0, 0, 0, 0.6))
		var dots := ".".repeat(int(Time.get_ticks_msec() / 400) % 4)
		_text(Vector2(W * 0.5, by + 2), _banner.trim_suffix("...") + dots, 8, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var ty := 64.0
	for t in _toasts:
		_text(Vector2(W * 0.5, ty), t[0], 8, Color(t[1], clampf(t[2], 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, body_font)
		ty += 11.0
	if run.mode != "solo" and Net.code != "":
		_text(Vector2(W - 6, 82), "ROOM " + Net.code, 6, UI.DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	# Owned weapons and passives along the bottom.
	var x := 4.0
	var y := view.y - 21.0
	for id in p.weapons:
		_slot(Vector2(x, y), Db.WEAPONS[id].icon, p.weapons[id].level, Db.WEAPONS[id].get("evolution", false))
		x += 20
	x = 4.0
	y -= 20
	for id in p.passives:
		_slot(Vector2(x, y), Db.PASSIVES[id].icon, p.passives[id], false)
		x += 20
	# Touch joystick.
	var js: Dictionary = p.joystick()
	if js.active:
		var o: Vector2 = js.origin
		draw_circle(o, 26, Color(1, 1, 1, 0.08))
		draw_arc(o, 26, 0, TAU, 32, Color(1, 1, 1, 0.3), 1.0)
		draw_circle(o + js.vec * 26, 9, Color(1, 1, 1, 0.35))

func _slot(at: Vector2, icon_id: String, lv: int, evolved: bool) -> void:
	draw_rect(Rect2(at, Vector2(18, 18)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(at, Vector2(18, 18)), UI.GOLD if evolved else Color(1, 1, 1, 0.25), false, 1.0)
	_icon(Db.icon_texture(icon_id), at + Vector2(9, 9), 16.0)
	if not evolved:
		_text(at + Vector2(12, 19), str(lv), 6, UI.GOLD)
