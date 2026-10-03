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
	pause.offset_left = -24; pause.offset_right = -4
	pause.offset_top = 2; pause.offset_bottom = 22
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
	# Laid out like the original: silver, kills and the menu on top; time and
	# level under them; then the candy XP bar and the hearts.
	var coin := Db.sheet("silver")
	draw_texture_rect_region(coin._tex, Rect2(6, 4, 16, 16), Rect2(0, 0, coin._w, coin._h))
	_text(Vector2(24, 17), "x%d" % p.silver_found, 8, UI.PALE, HORIZONTAL_ALIGNMENT_LEFT, body_font)
	var kills := str(p.kills)
	var kw := body_font.get_string_size(kills, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_texture_rect(Db.tex("skull"), Rect2(W * 0.5 - (16 + 4 + kw) * 0.5, 4, 16, 16), false)
	_text(Vector2(W * 0.5 - (16 + 4 + kw) * 0.5 + 20, 17), kills, 11, UI.PALE, HORIZONTAL_ALIGNMENT_LEFT, body_font)
	_text(Vector2(W * 0.5, 34), UI.time_text(run.time), 11, UI.PALE, HORIZONTAL_ALIGNMENT_CENTER, body_font)
	_text(Vector2(W - 6, 34), "Level: %d" % run.level, 11, UI.PALE, HORIZONTAL_ALIGNMENT_RIGHT, body_font)
	# XP bar: the original art stretched across, segments and all (drawn at
	# screen resolution, so the slight stretch doesn't show).
	var bar := Db.tex("xpbar")
	var top := 36.0
	var x0 := 2.0
	var x1 := W - 2.0
	var bsc := (x1 - x0) / 256.0
	draw_texture_rect(bar, Rect2(x0, top, x1 - x0, 32), false)
	var frac: float = clampf(run.xp / (run.xp_next * run._xp_scale()), 0.0, 1.0)
	var fill_from := x0 + 26.0 * bsc
	var fill_len := (x1 - 6.0 * bsc) - fill_from
	draw_rect(Rect2(fill_from, top + 13, fill_len * frac, 6), Color("f28a2e"))
	# Hearts at their native size, ten to a row.
	var hearts := ceili(p.max_hp() / HEART_HP)
	var hp: float = p.hp
	for i in hearts:
		var r := Rect2(6 + (i % 10) * 16, top + 30 + (i / 10) * 16, 16, 16)
		draw_texture_rect(Db.tex("heart_empty"), r, false)
		var fill := clampf((hp - i * HEART_HP) / HEART_HP, 0.0, 1.0)
		if fill > 0.0:
			var cols := ceilf(16.0 * fill)
			draw_texture_rect_region(Db.tex("heart"), Rect2(r.position, Vector2(cols, 16)), Rect2(0, 0, cols, 16))
	if _banner != "":
		var by := view.y * 0.4
		draw_rect(Rect2(0, by - 14, W, 22), Color(0, 0, 0, 0.6))
		var dots := ".".repeat(int(Time.get_ticks_msec() / 400) % 4)
		_text(Vector2(W * 0.5, by + 2), _banner.trim_suffix("...") + dots, 8, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var ty := 110.0
	for t in _toasts:
		_text(Vector2(W * 0.5, ty), t[0], 8, Color(t[1], clampf(t[2], 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, body_font)
		ty += 11.0
	if run.mode != "solo" and Net.code != "":
		_text(Vector2(W - 6, 100), "ROOM " + Net.code, 8, UI.DIM, HORIZONTAL_ALIGNMENT_RIGHT, body_font)
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
	_offscreen_arrows(view)
	# Touch joystick.
	var js: Dictionary = p.joystick()
	if js.active:
		var o: Vector2 = js.origin
		draw_circle(o, 26, Color(1, 1, 1, 0.08))
		draw_arc(o, 26, 0, TAU, 32, Color(1, 1, 1, 0.3), 1.0)
		draw_circle(o + js.vec * 26, 9, Color(1, 1, 1, 0.35))

const SEAT_COLORS := [Color("ffd35a"), Color("6ae0ff"), Color("ff7ab6"), Color("7dff6a")]

## Co-op: an arrow at the screen edge pointing to each player who's off screen.
func _offscreen_arrows(view: Vector2) -> void:
	var cam: Vector2 = run.camera.position
	var half := view * 0.5
	var inset := half - Vector2(14, 14)
	for h in run.heroes.values():
		if h == run.player:
			continue
		var d: Vector2 = h.position - cam
		if absf(d.x) < half.x - 4.0 and absf(d.y) < half.y - 4.0:
			continue
		# Where the line to them crosses the screen edge (inset a little).
		var k := minf(inset.x / maxf(absf(d.x), 0.001), inset.y / maxf(absf(d.y), 0.001))
		var at := half + d * k
		var dir := d.normalized()
		var col: Color = SEAT_COLORS[h.slot % SEAT_COLORS.size()]
		if h.dead or h.away:
			col = Color(col, 0.45)
		var tip := at + dir * 7.0
		var side := dir.orthogonal() * 5.0
		var pts := PackedVector2Array([tip, at - dir * 4.0 + side, at - dir * 4.0 - side])
		draw_colored_polygon(pts, col)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color.BLACK, 1.0)
		var label: String = h.player_name
		var lw := body_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var lp := at - dir * 12.0 + Vector2(-lw * 0.5, 3)
		lp.x = clampf(lp.x, 2.0, view.x - lw - 2.0)
		lp.y = clampf(lp.y, 10.0, view.y - 2.0)
		_text(lp, label, 8, col, HORIZONTAL_ALIGNMENT_LEFT, body_font)

func _slot(at: Vector2, icon_id: String, lv: int, evolved: bool) -> void:
	draw_rect(Rect2(at, Vector2(18, 18)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(at, Vector2(18, 18)), UI.GOLD if evolved else Color(1, 1, 1, 0.25), false, 1.0)
	_icon(Db.icon_texture(icon_id), at + Vector2(9, 9), 16.0)
	if not evolved:
		_text(at + Vector2(12, 19), str(lv), 6, UI.GOLD)
