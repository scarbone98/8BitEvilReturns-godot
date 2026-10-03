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
	pause.expand_icon = true
	pause.custom_minimum_size = Vector2(20, 20)
	pause.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	pause.offset_left = -26; pause.offset_right = -6
	pause.offset_top = 46; pause.offset_bottom = 66
	pause.focus_mode = FOCUS_NONE
	pause.pressed.connect(func(): pause_pressed.emit())
	add_child(pause)

var _toasts: Array = []  # [text, colour, seconds left]

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

func _draw() -> void:
	if run == null:
		return
	var p = run.player
	var view := get_viewport_rect().size
	var W := view.x
	# XP bar: the original frame art with a candy-corn cap on the left.
	var bar := Db.tex("xpbar")
	var bw := minf(W - 8, 256.0)
	var bx := (W - bw) * 0.5
	var sc := bw / 256.0
	var frac: float = clampf(run.xp / run.xp_next, 0.0, 1.0)
	draw_rect(Rect2(bx + 22 * sc, 12 * sc, 224 * sc * frac, 8 * sc), Color("5ad1ff"))
	draw_texture_rect(bar, Rect2(bx, 0, bw, 32 * sc), false)
	_text(Vector2(W - 6, 38), "LV %d" % run.level, 8, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	# Timer, the score.
	_text(Vector2(W * 0.5, 44), UI.time_text(run.time), 12, UI.PALE, HORIZONTAL_ALIGNMENT_CENTER)
	# Kills and silver.
	var sy := 28.0 + ceilf(ceili(p.max_hp() / HEART_HP) / 7.0) * 11.0 + 2.0
	draw_texture_rect(Db.tex("skull"), Rect2(6, sy, 10, 10), false)
	_text(Vector2(19, sy + 9), str(p.kills), 8)
	var coin := Db.sheet("silver")
	draw_texture_rect_region(coin._tex, Rect2(6, sy + 12, 10, 10), Rect2(0, 0, coin._w, coin._h))
	_text(Vector2(19, sy + 21), str(p.silver_found), 8)
	# Hearts.
	var hearts := ceili(p.max_hp() / HEART_HP)
	var hp: float = p.hp
	for i in hearts:
		# Seven per row keeps the hearts clear of the timer.
		var r := Rect2(6 + (i % 7) * 11, 28 + (i / 7) * 11, 10, 10)
		draw_texture_rect(Db.tex("heart_empty"), r, false)
		var fill := clampf((hp - i * HEART_HP) / HEART_HP, 0.0, 1.0)
		if fill > 0.0:
			var t := Db.tex("heart")
			draw_texture_rect_region(t, Rect2(r.position, Vector2(10 * fill, 10)), Rect2(0, 0, 16 * fill, 16))
	var ty := 64.0
	for t in _toasts:
		_text(Vector2(W * 0.5, ty), t[0], 8, Color(t[1], clampf(t[2], 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, body_font)
		ty += 11.0
	if run.mode != "solo" and Net.code != "":
		_text(Vector2(W - 6, 82), "ROOM " + Net.code, 6, UI.DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	# Owned weapons and passives along the bottom.
	var x := 4.0
	var y := view.y - 18.0
	for id in p.weapons:
		_slot(Vector2(x, y), Db.WEAPONS[id].icon, p.weapons[id].level, Db.WEAPONS[id].get("evolution", false))
		x += 17
	x = 4.0
	y -= 17
	for id in p.passives:
		_slot(Vector2(x, y), Db.PASSIVES[id].icon, p.passives[id], false)
		x += 17
	# Touch joystick.
	var js: Dictionary = p.joystick()
	if js.active:
		var o: Vector2 = js.origin
		draw_circle(o, 26, Color(1, 1, 1, 0.08))
		draw_arc(o, 26, 0, TAU, 32, Color(1, 1, 1, 0.3), 1.0)
		draw_circle(o + js.vec * 26, 9, Color(1, 1, 1, 0.35))

func _slot(at: Vector2, icon_id: String, lv: int, evolved: bool) -> void:
	draw_rect(Rect2(at, Vector2(15, 15)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(at, Vector2(15, 15)), UI.GOLD if evolved else Color(1, 1, 1, 0.25), false, 1.0)
	draw_texture_rect(Db.icon_texture(icon_id), Rect2(at + Vector2(1, 1), Vector2(13, 13)), false)
	if not evolved:
		_text(at + Vector2(9, 16), str(lv), 6, UI.GOLD)
