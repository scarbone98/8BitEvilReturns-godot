extends Node
## Menus: title, hero + stage select, power-up shop, collection. Then a run.

const RunScript := preload("res://src/run/run.gd")

var _screen: Node

const MIN_VIEW := Vector2(240, 400)  # the smallest view the game is laid out for

func _ready() -> void:
	_fit_screen()
	get_tree().root.size_changed.connect(_fit_screen)
	var f := Bridge.flags()
	if f.has("speed"):
		Engine.time_scale = float(f.speed)
	if f.has("char") and Db.CHARACTERS.has(f.char):
		Meta.selected = f.char
	if f.has("coop"):
		_dev_coop(f)
	elif f.has("autoplay") or f.has("dev"):
		_start_run(true)
	else:
		show_title()

## Pixel-perfect scaling that fills the screen: the largest whole-number zoom
## that still shows at least MIN_VIEW, with the view sized to fill the rest.
## (Godot's own "integer" mode leaves black bars below a 2x zoom.)
func _fit_screen() -> void:
	var win := Vector2(get_tree().root.size)
	if win.x <= 0 or win.y <= 0:
		return
	var zoom := maxf(1.0, floorf(minf(win.x / MIN_VIEW.x, win.y / MIN_VIEW.y)))
	get_tree().root.content_scale_size = Vector2i(floori(win.x / zoom), floori(win.y / zoom))

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

## A full-screen column with a title, for the menu screens.
func _page(title: String) -> VBoxContainer:
	var root := _screen_root()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8; box.offset_right = -8
	box.offset_top = 10; box.offset_bottom = -10
	box.add_theme_constant_override("separation", 6)
	root.add_child(box)
	box.add_child(UI.label(title, 10, UI.GOLD))
	return box

func _scroll(child: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(child)
	return sc

## Runs `refresh` now and whenever the profile changes, while `node` is up.
func _live(node: Node, refresh: Callable) -> void:
	refresh.call()
	Meta.changed.connect(refresh)
	node.tree_exiting.connect(func(): Meta.changed.disconnect(refresh))

# ---------------------------------------------------------------- Title

func show_title() -> void:
	var root := _screen_root()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 24; box.offset_right = -24
	box.offset_top = 16; box.offset_bottom = -16
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)
	var logo := UI.icon(Db.tex("title"), 160)
	logo.custom_minimum_size = Vector2(0, 128)
	box.add_child(logo)
	box.add_child(SheetView.new(Db.CHARACTERS[Meta.selected].run, Vector2(0, 40)))
	var play := UI.button("PLAY", show_select, 28)
	box.add_child(play)
	# A co-op game this device dropped out of: offer to jump back in.
	var session := Net.saved_session()
	if not session.is_empty():
		if session.get("host", false):
			Net.abandon(session)  # a host's fight can't survive a reload
		else:
			box.add_child(UI.button("REJOIN ROOM " + str(session.code), func():
				_watch_net()
				Net.rejoin(session)
				show_lobby(), 26))
	box.add_child(UI.button("CO-OP", show_coop, 22))
	box.add_child(UI.button("POWER UPS", show_powerups, 22))
	box.add_child(UI.button("COLLECTION", show_collection, 22))
	var stats := UI.label("", 8, UI.DIM)
	box.add_child(stats)
	_live(stats, func():
		stats.text = "Best %s   Silver %d" % [UI.time_text(Meta.best_seconds), Meta.silver])
	play.call_deferred("grab_focus")

# ---------------------------------------------------------------- Heroes

func show_select() -> void:
	var box := _page("CHOOSE YOUR HERO")
	var silver_l := UI.label("", 8, UI.PALE)
	box.add_child(silver_l)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var scroll := _scroll(grid)
	scroll.custom_minimum_size = Vector2(0, 150)
	box.add_child(scroll)

	var info := PanelContainer.new()
	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 3)
	info.add_child(info_box)
	box.add_child(info)

	# Stage picker: steps through the stages that are unlocked.
	var stage_row := HBoxContainer.new()
	var stage_l := UI.label("", 8, UI.PALE)
	stage_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stage_ids: Array = Db.STAGES.keys()
	var cycle := func(dir: int):
		var i := stage_ids.find(Meta.stage)
		for k in stage_ids.size():
			i = (i + dir + stage_ids.size()) % stage_ids.size()
			if Meta.content_unlocked(stage_ids[i]):
				break
		Meta.stage = stage_ids[i]
		Meta.save()
	stage_row.add_child(UI.button("<", func(): cycle.call(-1), 20))
	stage_row.add_child(stage_l)
	stage_row.add_child(UI.button(">", func(): cycle.call(1), 20))
	box.add_child(stage_row)
	var stage_about := UI.body("", 10, UI.DIM)
	box.add_child(stage_about)

	var start := UI.button("START", func(): pass, 28)
	box.add_child(start)
	box.add_child(UI.button("BACK", show_title, 20))

	var cards := {}
	for id in Db.CHARACTERS:
		var c := UI.button("", func():
			Meta.selected = id
			Meta.save(), 54)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := SheetView.new(Db.CHARACTERS[id].idle, Vector2.ZERO)
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_top = 4; v.offset_bottom = -12; v.offset_left = 2; v.offset_right = -2
		c.add_child(v)
		var nl := UI.label("", 6)
		nl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		nl.offset_top = -11; nl.offset_bottom = -3
		c.add_child(nl)
		c.set_meta("view", v)
		c.set_meta("name", nl)
		cards[id] = c
		grid.add_child(c)

	var refresh := func():
		silver_l.text = "Silver: %d" % Meta.silver
		for id in cards:
			var c: Button = cards[id]
			var ch: Dictionary = Db.CHARACTERS[id]
			var open := Meta.is_unlocked(id)
			var feat_locked: bool = ch.has("feat") and not open
			c.add_theme_stylebox_override("normal", UI.frame(id == Meta.selected))
			(c.get_meta("view") as SheetView).tint = Color.WHITE if open else (Color(0, 0, 0, 0.85) if feat_locked else Color(0.25, 0.25, 0.3))
			(c.get_meta("name") as Label).text = ch.name if not feat_locked else "???"
		for n in info_box.get_children():
			n.queue_free()
		var sel: Dictionary = Db.CHARACTERS[Meta.selected]
		var open := Meta.is_unlocked(Meta.selected)
		if sel.has("feat") and not open:
			info_box.add_child(UI.label("???", 10, UI.GOLD))
			info_box.add_child(UI.body("Unlock: " + Db.FEATS[sel.feat].desc, 12))
			start.disabled = true
			start.text = "LOCKED"
		else:
			var w: Dictionary = Db.WEAPONS[sel.weapon]
			info_box.add_child(UI.label(sel.name, 10, UI.GOLD))
			info_box.add_child(UI.body(sel.perk, 12))
			var wrow := HBoxContainer.new()
			wrow.alignment = BoxContainer.ALIGNMENT_CENTER
			wrow.add_child(UI.icon(Db.icon_texture(w.icon), 32))
			wrow.add_child(UI.label("Starts with " + w.name, 8, UI.PALE))
			info_box.add_child(wrow)
			if open:
				start.disabled = false
				start.text = "START"
			else:
				start.disabled = Meta.silver < int(sel.cost)
				start.text = "UNLOCK (%d SILVER)" % sel.cost
				var m := HBoxContainer.new()
				m.add_child(SheetView.new("merchant", Vector2(36, 36)))
				var q := UI.body("\"Heroes aren't free, friend.\"", 11, UI.DIM)
				q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				q.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				m.add_child(q)
				info_box.add_child(m)
		var st: Dictionary = Db.STAGES[Meta.stage]
		stage_l.text = "STAGE: " + st.name
		var locked := Db.STAGES.keys().filter(func(sid): return not Meta.content_unlocked(sid)).size()
		stage_about.text = st.get("about", "") + ("" if locked == 0 else "  (%d more to unlock)" % locked)

	start.pressed.connect(func():
		if Meta.is_unlocked(Meta.selected):
			_start_run()
		else:
			Meta.try_unlock(Meta.selected))
	_live(silver_l, refresh)
	cards[Meta.selected].call_deferred("grab_focus")

# ---------------------------------------------------------------- Power ups

func show_powerups() -> void:
	var box := _page("POWER UPS")
	var silver_l := UI.label("", 8, UI.PALE)
	box.add_child(silver_l)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	box.add_child(_scroll(list))
	var rows := {}
	for id in Db.POWERUPS:
		var p: Dictionary = Db.POWERUPS[id]
		var b := UI.button("", func(): Meta.buy_powerup(id), 34)
		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 6; row.offset_right = -6
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 6)
		var ic := UI.icon(Db.icon_texture(p.icon), 32)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", 1)
		var name_l := UI.label(p.name, 8, UI.PALE, HORIZONTAL_ALIGNMENT_LEFT)
		col.add_child(name_l)
		var desc_l := UI.body(p.desc, 10, UI.DIM)
		desc_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		col.add_child(desc_l)
		row.add_child(col)
		var price := UI.label("", 8, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		row.add_child(price)
		b.add_child(row)
		b.set_meta("name", name_l)
		b.set_meta("price", price)
		rows[id] = b
		list.add_child(b)
	box.add_child(UI.button("REFUND ALL", func(): Meta.refund_powerups(), 20))
	box.add_child(UI.button("BACK", show_title, 20))
	_live(silver_l, func():
		silver_l.text = "Silver: %d" % Meta.silver
		for id in rows:
			var p: Dictionary = Db.POWERUPS[id]
			var rank := Meta.powerup_rank(id)
			var maxed := rank >= int(p.max)
			(rows[id].get_meta("name") as Label).text = "%s %s" % [p.name, "*".repeat(rank) + ".".repeat(int(p.max) - rank)]
			(rows[id].get_meta("price") as Label).text = "MAX" if maxed else str(Meta.powerup_cost(id))
			rows[id].disabled = maxed or Meta.silver < Meta.powerup_cost(id))
	rows.values()[0].call_deferred("grab_focus")

# ---------------------------------------------------------------- Collection

func show_collection(tab := "feats") -> void:
	var box := _page("COLLECTION")
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for t in [["feats", "FEATS"], ["weapons", "WEAPONS"], ["passives", "ITEMS"]]:
		var b := UI.button(t[1], func(): show_collection(t[0]), 20)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("normal", UI.frame(t[0] == tab))
		tabs.add_child(b)
	box.add_child(tabs)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	box.add_child(_scroll(list))
	match tab:
		"feats":
			(box.get_child(0) as Label).text = "FEATS  %d/%d" % [Meta.feats.size(), Db.FEATS.size()]
			for f in Db.FEATS:
				var d: Dictionary = Db.FEATS[f]
				var done := Meta.feats.has(f)
				var rewards := []
				for id in d.unlocks:
					rewards.append(_content_name(id))
				for c in Db.CHARACTERS:
					if Db.CHARACTERS[c].get("feat") == f:
						rewards.append(Db.CHARACTERS[c].name)
				var text: String = d.desc
				if not rewards.is_empty():
					text += ("  -> " + ", ".join(rewards)) if done else "  -> ???"
				list.add_child(_entry(d.name, text, done))
		"weapons":
			var found := 0
			for id in Db.base_weapons():
				var d: Dictionary = Db.WEAPONS[id]
				var known := Meta.content_unlocked(id)
				var text: String = ('"%s"' % d.quote) if known else "Unlock: " + _unlock_hint(id)
				for key in ["evolve", "union"]:
					if d.get(key) is Dictionary and known:
						var into: Dictionary = Db.WEAPONS[d[key].into]
						var made := Meta.evolved.has(d[key].into)
						found += int(made)
						text += "\n+ %s -> %s" % [Db.upgrade_def(d[key].with).name, into.name if made else "???"]
				list.add_child(_entry(d.name if known else "???", text, known, d.icon))
			(box.get_child(0) as Label).text = "EVOLUTIONS  %d/%d" % [Meta.evolved.size(), Db.WEAPONS.size() - Db.base_weapons().size()]
		"passives":
			for id in Db.PASSIVES:
				var d: Dictionary = Db.PASSIVES[id]
				var known := Meta.content_unlocked(id)
				list.add_child(_entry(d.name if known else "???", d.desc if known else "Unlock: " + _unlock_hint(id), known, d.icon))
	box.add_child(UI.button("BACK", show_title, 20))

func _entry(title: String, text: String, lit: bool, icon_id := "") -> Control:
	var p := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if icon_id != "":
		var ic := UI.icon(Db.icon_texture(icon_id), 32)
		ic.modulate = Color.WHITE if lit else Color(0, 0, 0, 0.8)
		row.add_child(ic)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	col.add_child(UI.label(title, 8, UI.GOLD if lit else UI.DIM, HORIZONTAL_ALIGNMENT_LEFT))
	var t := UI.body(text, 10, UI.PALE if lit else UI.DIM)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(t)
	row.add_child(col)
	p.add_child(row)
	return p

func _content_name(id: String) -> String:
	if Db.STAGES.has(id): return Db.STAGES[id].name
	if Db.CHARACTERS.has(id): return Db.CHARACTERS[id].name
	return Db.upgrade_def(id).get("name", id)

func _unlock_hint(id: String) -> String:
	var f := Db.feat_for(id)
	return Db.FEATS[f].desc if f != "" else "?"

# ---------------------------------------------------------------- Co-op

const CODE_KEYS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

func _my_name() -> String:
	return Db.CHARACTERS[Meta.selected].name

func show_coop(error := "") -> void:
	var box := _page("CO-OP")
	box.add_child(UI.body("Up to 4 players, each on their own phone or computer. Everyone plays the hero they've picked.", 11, UI.DIM))
	var hero := HBoxContainer.new()
	hero.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_child(SheetView.new(Db.CHARACTERS[Meta.selected].idle, Vector2(28, 28)))
	hero.add_child(UI.label("You: " + _my_name(), 8, UI.PALE))
	box.add_child(hero)
	if error != "":
		box.add_child(UI.body(error, 11, UI.RED))
	box.add_child(UI.button("HOST A ROOM", func():
		_watch_net()
		Net.create(_my_name(), Meta.selected)
		show_lobby(), 26))
	box.add_child(UI.label("JOIN WITH A CODE", 8, UI.GOLD))
	var code_l := UI.label("_ _ _ _", 16, UI.PALE)
	box.add_child(code_l)
	var typed := [""]
	var refresh := func():
		var t: String = typed[0]
		var shown := []
		for i in 4:
			shown.append(t[i] if i < t.length() else "_")
		code_l.text = " ".join(shown)
	var keys := GridContainer.new()
	keys.columns = 8
	keys.add_theme_constant_override("h_separation", 2)
	keys.add_theme_constant_override("v_separation", 2)
	for ch in CODE_KEYS:
		var k := UI.button(ch, func():
			if typed[0].length() < 4:
				typed[0] += ch
				refresh.call(), 22)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keys.add_child(k)
	box.add_child(keys)
	var row := HBoxContainer.new()
	var del := UI.button("DEL", func():
		typed[0] = typed[0].substr(0, maxi(0, typed[0].length() - 1))
		refresh.call(), 22)
	del.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(del)
	var join := UI.button("JOIN", func():
		if typed[0].length() == 4:
			_watch_net()
			Net.join(typed[0], _my_name(), Meta.selected)
			show_lobby(), 22)
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(join)
	box.add_child(row)
	box.add_child(UI.button("BACK", show_title, 20))

var _net_watched := false

## Lobby and run hooks, connected once.
func _watch_net() -> void:
	if _net_watched:
		return
	_net_watched = true
	Net.failed.connect(func(msg):
		if not Net.in_game:
			Net.leave()
			show_coop(msg))
	Net.closed.connect(func(reason):
		if not Net.in_game and _screen is CanvasLayer:
			show_coop("The host closed the room." if reason == "host" else "Lost the connection."))
	Net.started.connect(func(stage, players):
		_start_coop(stage, players))

func show_lobby() -> void:
	var box := _page("CO-OP ROOM")
	var code_l := UI.label("CONNECTING...", 24, UI.GOLD)
	box.add_child(code_l)
	box.add_child(UI.body("Friends tap CO-OP, then type this code.", 11, UI.DIM))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(list)
	var stage_l := UI.label("", 8, UI.PALE)
	box.add_child(stage_l)
	var stage_btn := UI.button("CHANGE STAGE", func():
		var ids: Array = Db.STAGES.keys().filter(func(sid): return Meta.content_unlocked(sid))
		Net.pick({"stage": ids[(ids.find(Net.stage) + 1) % ids.size()]}), 20)
	box.add_child(stage_btn)
	var start := UI.button("START", func(): Net.start_game(), 28)
	box.add_child(start)
	var wait := UI.label("Waiting for the host to start...", 8, UI.DIM)
	box.add_child(wait)
	box.add_child(UI.button("LEAVE", func():
		Net.leave()
		show_coop(), 20))
	var refresh := func():
		if not is_instance_valid(code_l):
			return
		code_l.text = Net.code if Net.code != "" else "CONNECTING..."
		for n in list.get_children():
			n.queue_free()
		for p in Net.players:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var hid := str(p.hero) if Db.CHARACTERS.has(str(p.hero)) else "joe"
			row.add_child(SheetView.new(Db.CHARACTERS[hid].idle, Vector2(28, 28)))
			row.add_child(UI.label("%s%s" % [p.name, "  (host)" if int(p.slot) == 0 else ""], 8, UI.PALE, HORIZONTAL_ALIGNMENT_LEFT))
			list.add_child(row)
		stage_l.text = "STAGE: " + Db.STAGES.get(Net.stage, Db.STAGES.graveyard).name
		stage_btn.visible = Net.is_host
		start.visible = Net.is_host
		wait.visible = not Net.is_host and Net.code != ""
	refresh.call()
	Net.room_changed.connect(refresh)
	code_l.tree_exiting.connect(func(): Net.room_changed.disconnect(refresh))

func _start_coop(stage_id: String, players: Array) -> void:
	# Play the hero the room has us down as (matters when rejoining after a reload).
	for p in players:
		if int(p.slot) == Net.slot and Db.CHARACTERS.has(str(p.hero)):
			Meta.selected = str(p.hero)
	var run := RunScript.new()
	run.process_mode = Node.PROCESS_MODE_PAUSABLE
	_swap(run)
	if not Db.STAGES.has(stage_id):
		stage_id = "graveyard"
	run.start(Meta.selected, stage_id, {"mode": "host" if Net.is_host else "guest", "players": players})
	var f := Bridge.flags()
	if f.has("autoplay"):
		run.apply_dev_flags(f)
	run.quit_to_menu.connect(func():
		Net.leave()
		show_title())

## Dev: `coop=host` makes a room and starts once `players=N` have joined;
## `coop=join&room=CODE` joins one. Add `autoplay` for bots.
func _dev_coop(f: Dictionary) -> void:
	_watch_net()
	if f.coop == "host":
		Net.create(_my_name(), Meta.selected)
		var want := int(f.get("players", "2"))
		Net.room_changed.connect(func():
			if Net.code != "":
				print("[room] ", Net.code, " players ", Net.players.size())
			if Net.players.size() >= want and not Net.in_game:
				Net.start_game())
	elif f.coop == "rejoin":
		var session := Net.saved_session()
		print("[net] rejoining ", session.get("code", "?"))
		Net.rejoin(session)
	else:
		Net.join(str(f.get("room", "")), _my_name(), Meta.selected)
	show_lobby()

# ---------------------------------------------------------------- Run

func _start_run(dev := false) -> void:
	if not dev and not Meta.is_unlocked(Meta.selected):
		return
	var run := RunScript.new()
	run.process_mode = Node.PROCESS_MODE_PAUSABLE
	_swap(run)
	run.start(Meta.selected, Meta.stage if not dev else str(Bridge.flags().get("stage", "graveyard")))
	if dev:
		run.apply_dev_flags(Bridge.flags())
	run.quit_to_menu.connect(show_select)
