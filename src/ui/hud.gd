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

func _process(_d: float) -> void:
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
	var frac: float = clampf(p.xp / p.xp_next, 0.0, 1.0)
	draw_rect(Rect2(bx + 22 * sc, 12 * sc, 224 * sc * frac, 8 * sc), Color("5ad1ff"))
	draw_texture_rect(bar, Rect2(bx, 0, bw, 32 * sc), false)
	_text(Vector2(W - 6, 38), "LV %d" % p.level, 8, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	# Timer, the score.
	_text(Vector2(W * 0.5, 44), UI.time_text(run.time), 12, UI.PALE, HORIZONTAL_ALIGNMENT_CENTER)
	# Kills and silver.
	draw_texture_rect(Db.tex("skull"), Rect2(6, 50, 10, 10), false)
	_text(Vector2(19, 59), str(run.kills), 8)
	var coin := Db.sheet("silver")
	draw_texture_rect_region(coin._tex, Rect2(6, 62, 10, 10), Rect2(0, 0, coin._w, coin._h))
	_text(Vector2(19, 71), str(run.silver_found), 8)
	# Hearts.
	var hearts := ceili(p.max_hp() / HEART_HP)
	var hp: float = p.hp
	for i in hearts:
		var r := Rect2(6 + i * 11, 28, 10, 10)
		draw_texture_rect(Db.tex("heart_empty"), r, false)
		var fill := clampf((hp - i * HEART_HP) / HEART_HP, 0.0, 1.0)
		if fill > 0.0:
			var t := Db.tex("heart")
			draw_texture_rect_region(t, Rect2(r.position, Vector2(10 * fill, 10)), Rect2(0, 0, 16 * fill, 16))
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
