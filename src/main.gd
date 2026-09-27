extends Node
## Switches between the title screen, character select and a run.

const RunScript := preload("res://src/run/run.gd")

var _screen: Node

func _ready() -> void:
	var f := Bridge.flags()
	if f.has("speed"):
		Engine.time_scale = float(f.speed)
	if f.has("autoplay") or f.has("dev"):
		if f.has("char") and Db.CHARACTERS.has(f.char):
			Meta.selected = f.char
		_start_run(true)
	else:
		show_title()

func _swap(n: Node) -> void:
	if _screen:
		_screen.queue_free()
	_screen = n
	add_child(n)

func _screen_root() -> Control:
	var layer := CanvasLayer.new()
	var root := Control.new()
	root.theme = UI.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var bg := TextureRect.new()
	bg.texture = Db.tex("gamebg")
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.modulate = Color(0.55, 0.5, 0.65)
	root.add_child(bg)
	_swap(layer)
	return root

func show_title() -> void:
	var root := _screen_root()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 24; box.offset_right = -24
	box.offset_top = 24; box.offset_bottom = -24
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	root.add_child(box)
	var logo := UI.icon(Db.tex("title"), 150)
	logo.custom_minimum_size = Vector2(0, 150)
	box.add_child(logo)
	var hero := SheetView.new(Db.CHARACTERS[Meta.selected].run, Vector2(0, 48))
	box.add_child(hero)
	var play := UI.button("PLAY", show_select, 28)
	box.add_child(play)
	var stats := UI.label("", 8, UI.DIM)
	box.add_child(stats)
	var refresh := func():
		stats.text = "Best %s   Silver %d" % [UI.time_text(Meta.best_seconds), Meta.silver]
	refresh.call()
	Meta.changed.connect(refresh)
	stats.tree_exiting.connect(func(): Meta.changed.disconnect(refresh))
	play.call_deferred("grab_focus")

func show_select() -> void:
	var root := _screen_root()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10; box.offset_right = -10
	box.offset_top = 14; box.offset_bottom = -14
	box.add_theme_constant_override("separation", 6)
	root.add_child(box)
	box.add_child(UI.label("CHOOSE YOUR HERO", 10, UI.GOLD))

	var silver_l := UI.label("", 8, UI.PALE)
	box.add_child(silver_l)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)

	# Details for the highlighted hero.
	var info := PanelContainer.new()
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 4)
	info.add_child(info_box)
	box.add_child(info)

	var start := UI.button("START", func(): _start_run(), 28)
	box.add_child(start)
	var back := UI.button("BACK", show_title, 20)
	box.add_child(back)

	var cards := {}
	var refresh: Callable
	refresh = func():
		silver_l.text = "Silver: %d" % Meta.silver
		for id in cards:
			var c: Button = cards[id]
			var ch: Dictionary = Db.CHARACTERS[id]
			var lock_l: Label = c.get_meta("lock")
			lock_l.text = "" if Meta.is_unlocked(id) else "%d" % ch.cost
			c.add_theme_stylebox_override("normal", UI.frame(id == Meta.selected))
			var view: SheetView = c.get_meta("view")
			view.tint = Color.WHITE if Meta.is_unlocked(id) else Color(0.2, 0.2, 0.25)
		for n in info_box.get_children():
			n.queue_free()
		var sel: Dictionary = Db.CHARACTERS[Meta.selected]
		var w: Dictionary = Db.WEAPONS[sel.weapon]
		info_box.add_child(UI.label(sel.name, 10, UI.GOLD))
		info_box.add_child(UI.body(sel.perk, 12))
		var wrow := HBoxContainer.new()
		wrow.alignment = BoxContainer.ALIGNMENT_CENTER
		wrow.add_child(UI.icon(Db.icon_texture(w.icon), 28))
		wrow.add_child(UI.label("Starts with " + w.name, 8, UI.PALE))
		info_box.add_child(wrow)
		if Meta.is_unlocked(Meta.selected):
			start.disabled = false
			start.text = "START"
		else:
			start.disabled = Meta.silver < int(sel.cost)
			start.text = "UNLOCK (%d SILVER)" % sel.cost
			# The merchant sells heroes.
			var m := HBoxContainer.new()
			m.alignment = BoxContainer.ALIGNMENT_CENTER
			m.add_child(SheetView.new("merchant", Vector2(48, 48)))
			var q := UI.body("\"Heroes aren't free, friend.\"", 11, UI.DIM)
			q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			m.add_child(q)
			info_box.add_child(m)

	for id in Db.CHARACTERS:
		var ch: Dictionary = Db.CHARACTERS[id]
		var c := UI.button("", func():
			Meta.selected = id
			Meta.save()
			refresh.call(), 72)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := SheetView.new(ch.idle, Vector2(0, 0))
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_top = 4; v.offset_bottom = -14
		c.add_child(v)
		var nl := UI.label(ch.name, 8)
		nl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		nl.offset_top = -14; nl.offset_bottom = -4
		c.add_child(nl)
		var ll := UI.label("", 8, UI.GOLD)
		ll.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		ll.position = Vector2(-40, 5)
		ll.size = Vector2(34, 10)
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.add_child(ll)
		c.set_meta("lock", ll)
		c.set_meta("view", v)
		cards[id] = c
		grid.add_child(c)

	start.pressed.connect(func():
		if not Meta.is_unlocked(Meta.selected):
			if Meta.try_unlock(Meta.selected):
				refresh.call())
	refresh.call()
	Meta.changed.connect(refresh)
	silver_l.tree_exiting.connect(func(): Meta.changed.disconnect(refresh))
	cards[Meta.selected].call_deferred("grab_focus")

func _start_run(dev := false) -> void:
	if not dev and not Meta.is_unlocked(Meta.selected):
		return
	var run := RunScript.new()
	run.process_mode = Node.PROCESS_MODE_PAUSABLE
	_swap(run)
	run.start(Meta.selected)
	if dev:
		run.apply_dev_flags(Bridge.flags())
	run.quit_to_menu.connect(show_select)
