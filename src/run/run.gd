extends Node2D
## One run: builds the world, drives every system each frame, spawns waves,
## and shows the level-up / chest / pause / game-over screens.

signal quit_to_menu

const EnemiesScript := preload("res://src/run/enemies.gd")
const PlayerScript := preload("res://src/run/player.gd")
const ShotsScript := preload("res://src/run/shots.gd")
const PickupsScript := preload("res://src/run/pickups.gd")
const ObstaclesScript := preload("res://src/run/obstacles.gd")
const PopupsScript := preload("res://src/run/popups.gd")
const HudScript := preload("res://src/ui/hud.gd")

var stage: Dictionary
var player
var enemies
var shots
var pickups
var obstacles
var popups
var camera: Camera2D
var ground: Sprite2D
var front: Node2D
var hud
var ui: CanvasLayer

var time := 0.0
var kills := 0
var candy := 0
var silver_found := 0
var ended := false
var _spawn_acc: Array[float] = []
var _events_done := {}
var _pending_levels := 0
var _modal: Control
var autoplay := false
var dev := false  # dev/test runs never save or submit scores

func start(char_id: String, stage_id := "graveyard") -> void:
	stage = Db.STAGES[stage_id]
	_spawn_acc.resize(stage.spawns.size())
	_spawn_acc.fill(0.0)

	ground = Sprite2D.new()
	ground.texture = Db.tex(stage.ground)
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.region_enabled = true
	ground.region_rect = Rect2(0, 0, 640 * 3, 400 * 4)
	ground.centered = true
	add_child(ground)

	obstacles = _make(ObstaclesScript)
	obstacles.setup(stage)
	pickups = _make(PickupsScript)
	enemies = _make(EnemiesScript)
	enemies.died.connect(_on_enemy_died)
	player = _make(PlayerScript)
	player.setup(char_id)
	player.add_weapon(Db.CHARACTERS[char_id].weapon)
	player.leveled_up.connect(_on_level_up)
	player.died.connect(_on_player_died)
	front = Node2D.new()
	front.draw.connect(func(): obstacles.draw_props(front, true, player.position.y))
	add_child(front)
	shots = _make(ShotsScript)
	popups = _make(PopupsScript)

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()

	ui = CanvasLayer.new()
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	var root := Control.new()
	root.theme = UI.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	hud = HudScript.new()
	hud.run = self
	hud.pause_pressed.connect(_show_pause)
	root.add_child(hud)
	obstacles.update_around(player.position)

## Dev/testing: `give` adds weapons or passives (comma list, repeat an id to
## level it), `minute` skips ahead, `autoplay` lets a bot play.
func apply_dev_flags(f: Dictionary) -> void:
	dev = true
	autoplay = f.has("autoplay")
	player.autopilot = autoplay
	if f.has("give"):
		for id in str(f.give).split(","):
			if Db.WEAPONS.has(id) or Db.PASSIVES.has(id):
				player.upgrade(id)
	if f.has("die"):
		_on_player_died.call_deferred()
	if f.has("levelup"):
		_on_level_up.call_deferred()
	if f.has("chest"):
		pickups.drop("chest", player.position + Vector2(0, 4))
	if f.has("minute"):
		time = float(f.minute) * 60.0
		for i in stage.events.size():
			if stage.events[i].at < float(f.minute):
				_events_done[i] = true

func _make(script: Script) -> Node:
	var n: Node = script.new()
	n.set("run", self)
	add_child(n)
	return n

func view_rect() -> Rect2:
	var sz := get_viewport_rect().size
	return Rect2(camera.position - sz * 0.5, sz)

func _process(delta: float) -> void:
	if ended or get_tree().paused:
		return
	delta = minf(delta, 1.0 / 20.0)
	time += delta
	player.step(delta)
	camera.position = player.position
	obstacles.update_around(player.position)
	# Snap the tiled ground to its tile size so it never runs out.
	ground.position = (player.position / Vector2(640, 400)).floor() * Vector2(640, 400)
	_spawn(delta)
	enemies.step(delta, player.position, view_rect())
	_contact_damage()
	shots.step(delta)
	pickups.step(delta)
	popups.step(delta)
	if autoplay and int(time / 30.0) != int((time - delta) / 30.0):
		_log_status("t")
	player.queue_redraw()
	front.queue_redraw()
	obstacles.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not ended and _modal == null:
		_show_pause()

# ---------------------------------------------------------------- Spawning

func _spawn(delta: float) -> void:
	var minute := time / 60.0
	var hp_mul := 1.0 + minute * float(stage.hp_per_minute)
	var ramp := 1.0 + minute * 0.15
	for i in stage.spawns.size():
		var sp: Dictionary = stage.spawns[i]
		if minute < sp.from or minute >= sp.to:
			continue
		_spawn_acc[i] += sp.rate * ramp * delta
		while _spawn_acc[i] >= 1.0:
			_spawn_acc[i] -= 1.0
			if enemies.count() < stage.max_alive:
				enemies.spawn(sp.enemy, _offscreen_point(), hp_mul)
	for i in stage.events.size():
		var ev: Dictionary = stage.events[i]
		if _events_done.has(i) or minute < ev.at:
			continue
		_events_done[i] = true
		match ev.type:
			"ring":
				var r := get_viewport_rect().size.length() * 0.55
				for k in ev.count:
					enemies.spawn(ev.enemy, player.position + Vector2.RIGHT.rotated(TAU * k / ev.count) * r, hp_mul)
			"boss":
				enemies.spawn(ev.enemy, _offscreen_point(), hp_mul, true)

func _offscreen_point() -> Vector2:
	var sz := get_viewport_rect().size
	return player.position + Vector2.RIGHT.rotated(randf() * TAU) * (sz.length() * 0.5 + 16.0)

func _contact_damage() -> void:
	var worst := 0.0
	for i in enemies.query_circle(player.position, player.RADIUS):
		worst = maxf(worst, enemies.damage[i])
	if worst > 0.0:
		player.take_hit(worst)

# ---------------------------------------------------------------- Drops

func _on_enemy_died(at: Vector2, kind: String, is_boss: bool) -> void:
	kills += 1
	if is_boss:
		pickups.drop("chest", at)
		return
	var tier: int = Db.ENEMIES[kind].candy
	if tier < 2 and randf() < 0.04:
		tier += 1
	pickups.drop_candy(at, tier)
	var r := randf()
	if r < 0.004:
		pickups.drop("basket", at)
	elif r < 0.007:
		pickups.drop("clock", at)
	elif r < 0.009:
		pickups.drop("skull", at)
	elif r < 0.019:
		pickups.drop("heart", at)
	elif r < 0.05 * (1.0 + player.stats.greed):
		pickups.drop("silver", at + Vector2(4, 0))

func collect(p: Dictionary) -> void:
	match p.type:
		"candy":
			candy += 1
			player.add_xp(p.value)
		"silver":
			silver_found += 1
		"heart":
			player.heal(30.0)
		"clock":
			enemies.frozen = 6.0
		"basket":
			pickups.pull_all_candy()
		"skull":
			var view := view_rect()
			for i in enemies.count():
				if view.has_point(enemies.pos[i]) and enemies.boss[i] == 0:
					enemies.hurt(i, 99999.0, player.position)
		"chest":
			_open_chest()

# ---------------------------------------------------------------- Screens

func _set_modal(c: Control) -> void:
	if _modal:
		_modal.queue_free()
	_modal = c
	if c:
		hud.get_parent().add_child(c)
		get_tree().paused = true
	else:
		get_tree().paused = false

func _panel(title: String, title_col := UI.GOLD) -> VBoxContainer:
	var overlay := UI.dim_overlay()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10; box.offset_right = -10
	box.offset_top = 40; box.offset_bottom = -20
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	overlay.add_child(box)
	box.add_child(UI.label(title, 16, title_col))
	_set_modal(overlay)
	return box

func _on_level_up() -> void:
	_pending_levels += 1
	if _modal == null:
		_show_level_up()

func _show_level_up() -> void:
	var box := _panel("LEVEL UP!")
	box.add_child(UI.label("Choose one", 8, UI.DIM))
	var first: Button
	for id in player.upgrade_options(3):
		var b := _upgrade_card(id, func():
			player.upgrade(id)
			_pending_levels -= 1
			_set_modal(null)
			if _pending_levels > 0:
				_show_level_up())
		box.add_child(b)
		if first == null:
			first = b
	first.call_deferred("grab_focus")
	if autoplay:
		first.call_deferred("emit_signal", "pressed")

func _upgrade_card(id: String, on_pick: Callable) -> Button:
	var d: Dictionary = Db.upgrade_def(id)
	var lv: int = player.level_of(id)
	var desc := ""
	var tag := ""
	if Db.WEAPONS.has(id):
		tag = "NEW!" if lv == 0 else "LV %d" % (lv + 1)
		desc = '"%s"' % d.quote if lv == 0 else d.levels[lv - 1].desc
	elif Db.PASSIVES.has(id):
		tag = "NEW!" if lv == 0 else "LV %d" % (lv + 1)
		desc = d.desc
	else:
		desc = d.desc
	var b := UI.button("", on_pick, 66)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8; row.offset_right = -8
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var ic := UI.icon(Db.icon_texture(d.icon), 36)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := UI.label(d.name, 8, UI.PALE, HORIZONTAL_ALIGNMENT_LEFT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	top.add_child(UI.label(tag, 8, UI.GOLD if tag == "NEW!" else UI.DIM))
	col.add_child(top)
	var dl := UI.body(desc, 11, UI.DIM)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(dl)
	row.add_child(col)
	b.add_child(row)
	return b

func _open_chest() -> void:
	var gained := []  # [id, text]
	var ev: Array = player.evolvable()
	if not ev.is_empty():
		var into: String = player.evolve(ev.pick_random())
		gained.append([into, "EVOLVED!"])
	else:
		var n := 1 if randf() < 0.7 else (3 if randf() < 0.3 else 2)
		for k in n:
			var opts: Array = player.upgrade_options(1)
			if opts.is_empty():
				break
			player.upgrade(opts[0])
			gained.append([opts[0], "LV %d" % player.level_of(opts[0]) if player.level_of(opts[0]) > 0 else ""])
	var box := _panel("TREASURE!")
	for g in gained:
		var d: Dictionary = Db.upgrade_def(g[0])
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		row.add_child(UI.icon(Db.icon_texture(d.icon), 32))
		var l := UI.label("%s  %s" % [d.name, g[1]], 8, UI.GOLD if g[1] == "EVOLVED!" else UI.PALE)
		row.add_child(l)
		box.add_child(row)
	var ok := UI.button("OK", func():
		_set_modal(null)
		if _pending_levels > 0:
			_show_level_up())
	box.add_child(ok)
	ok.call_deferred("grab_focus")
	if autoplay:
		get_tree().create_timer(0.6, true).timeout.connect(func(): ok.emit_signal("pressed"))

func _show_pause() -> void:
	if _modal or ended:
		return
	var box := _panel("PAUSED", UI.PALE)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 4)
	for id in player.weapons:
		grid.add_child(UI.icon(Db.icon_texture(Db.WEAPONS[id].icon), 28))
	for id in player.passives:
		grid.add_child(UI.icon(Db.icon_texture(Db.PASSIVES[id].icon), 28))
	var c := CenterContainer.new()
	c.add_child(grid)
	box.add_child(c)
	box.add_child(UI.label("Time %s   Kills %d" % [UI.time_text(time), kills], 8, UI.DIM))
	var resume := UI.button("RESUME", func(): _set_modal(null))
	box.add_child(resume)
	box.add_child(UI.button("GIVE UP", func():
		_set_modal(null)
		_on_player_died()))
	resume.call_deferred("grab_focus")

func _log_status(tag: String) -> void:
	var inv := []
	for id in player.weapons: inv.append("%s%d" % [id, player.weapons[id].level])
	for id in player.passives: inv.append("%s%d" % [id, player.passives[id]])
	print("[%s] %s lv%d hp%d/%d kills%d enemies%d shots%d pickups%d fps%d | %s" % [tag, UI.time_text(time),
		player.level, player.hp, player.max_hp(), kills, enemies.count(), shots.list.size(),
		pickups.list.size(), Engine.get_frames_per_second(), ", ".join(inv)])

func _on_player_died() -> void:
	if ended:
		return
	ended = true
	if autoplay:
		_log_status("DIED")
	var seconds := int(time)
	var bonus := seconds / 20
	var earned := int((silver_found + bonus) * (1.0 + player.stats.greed))
	var best := false
	if not dev:
		Meta.add_silver(earned)
		best = Meta.record_run(seconds)
		Bridge.submit_run(seconds, kills, candy)
		Bridge.report_death(seconds)
	var box := _panel("YOU DIED", UI.RED)
	box.add_child(UI.label(UI.time_text(seconds), 24, UI.PALE))
	if best:
		box.add_child(UI.label("NEW BEST!", 8, UI.GOLD))
	box.add_child(UI.label("Kills %d   Candy %d" % [kills, candy], 8, UI.DIM))
	box.add_child(UI.label("Level %d" % player.level, 8, UI.DIM))
	box.add_child(UI.label("+%d silver" % earned, 10, UI.GOLD))
	var again := UI.button("PLAY AGAIN", func():
		get_tree().paused = false
		quit_to_menu.emit())
	box.add_child(again)
	again.call_deferred("grab_focus")
