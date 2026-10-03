extends Node2D
## One run: builds the world, drives every system each frame, spawns waves,
## and shows the level-up / chest / pause / game-over screens.
##
## mode "solo"  - one hero, everything local
##      "host"  - co-op: this game runs the fight for every hero and streams
##                it to the others (see NetSync)
##      "guest" - co-op: draws the host's fight and moves only its own hero
## Experience and level are shared by the team; every hero picks their own
## level-up card. A hero who goes down comes back at the next team level-up;
## the run ends when everyone is down.

signal quit_to_menu

const EnemiesScript := preload("res://src/run/enemies.gd")
const PlayerScript := preload("res://src/run/player.gd")
const ShotsScript := preload("res://src/run/shots.gd")
const PickupsScript := preload("res://src/run/pickups.gd")
const ObstaclesScript := preload("res://src/run/obstacles.gd")
const PopupsScript := preload("res://src/run/popups.gd")
const NetSyncScript := preload("res://src/run/netsync.gd")
const HudScript := preload("res://src/ui/hud.gd")

var mode := "solo"
var stage: Dictionary
var stage_id := "graveyard"
var heroes := {}    # seat -> hero
var player          # this device's hero
var enemies
var shots
var pickups
var obstacles
var popups
var netsync
var camera: Camera2D
var ground: Sprite2D
var world: Node2D  # y-sorted: heroes and props, so each sorts by where its feet are
var front: Node2D  # redraws enemies standing in front of a prop
var hud
var ui: CanvasLayer

var time := 0.0
var level := 1
var xp := 0.0
var xp_next := 5.0
var ended := false
var _spawn_acc: Array[float] = []
var _events_done := {}
var _pending_levels := 0
var _awaiting := {}  # host: seats still choosing a level-up card
var _sent_opts := {} # host: the cards each remote seat was offered
var net_paused := false  # host: our own connection dropped, so the fight waits
var _modal: Control
var autoplay := false
var dev := false  # dev/test runs never save
var dev_unlimited := false
var _bench := 0   # frames left to time; dev flag "bench"
var _bench_us := []
var _prof := [0, 0, 0]

func is_guest() -> bool:
	return mode == "guest"

func is_host() -> bool:
	return mode == "host"

## coop: {} for solo, or {mode: "host"|"guest", players: [{slot, name, hero}]}.
func start(char_id: String, p_stage := "graveyard", coop := {}) -> void:
	mode = coop.get("mode", "solo")
	stage_id = p_stage
	stage = Db.STAGES[stage_id]
	_spawn_acc.resize(stage.spawns.size())
	_spawn_acc.fill(0.0)

	ground = Sprite2D.new()
	ground.texture = Db.tex(stage.ground)
	ground.modulate = stage.get("tint", Color.WHITE)
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
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	obstacles.layer = world
	popups = PopupsScript.new()  # created early: heroes use its font for name tags

	if mode == "solo":
		player = _add_hero(0, char_id, "local", "")
	else:
		for p in coop.players:
			var seat := int(p.slot)
			var me := seat == Net.slot
			var hero_mode := "local" if me else ("remote" if is_host() else "puppet")
			var hero = _add_hero(seat, char_id if me else str(p.hero), hero_mode, str(p.name))
			hero.position = Vector2(seat * 24 - 36, 0)
			if me:
				player = hero
	front = Node2D.new()
	front.draw.connect(func(): enemies.draw_in_front_of_props(front))
	add_child(front)
	shots = _make(ShotsScript)
	popups.set("run", self)
	add_child(popups)

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	camera.position = player.position

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
	obstacles.update_around(_hero_positions())

	if mode != "solo":
		netsync = NetSyncScript.new()
		netsync.run = self
		netsync.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(netsync)

func _add_hero(seat: int, char_id: String, hero_mode: String, name: String):
	var h = PlayerScript.new()
	h.run = self
	h.slot = seat
	h.mode = hero_mode
	h.player_name = name
	world.add_child(h)
	var mine := hero_mode == "local"
	h.setup(char_id, Meta.powerup_stats() if mine and not dev else {})
	if mine:
		h.view_size = get_viewport_rect().size
	if not is_guest():
		h.add_weapon(Db.CHARACTERS[char_id].weapon)
	h.died.connect(_on_hero_down)
	heroes[seat] = h
	return h

## Host: a player's connection dropped. Their hero waits, untouchable; if
## they were choosing a card, they get the first one so nobody's held up.
func on_peer_away(seat: int) -> void:
	var h = heroes.get(seat)
	if h == null:
		return
	h.away = true
	print("[net] seat %d away" % seat)
	hud.toast("%s lost connection" % h.player_name, UI.DIM)
	if _awaiting.has(seat):
		var opts: Array = _sent_opts.get(seat, [])
		_picked(seat, opts[0] if not opts.is_empty() else "")

func on_peer_back(seat: int) -> void:
	var h = heroes.get(seat)
	if h == null:
		return
	h.away = false
	print("[net] seat %d back" % seat)
	h._invuln = 2.0
	hud.toast("%s is back!" % h.player_name, UI.PALE)

## Our own link dropped or came back.
func on_connection(online: bool) -> void:
	print("[net] %s %s" % [mode, "back online" if online else "connection lost, paused" if is_host() else "connection lost"])
	if is_host():
		net_paused = not online
	hud.banner("" if online else "Reconnecting...")

## A co-op player left mid-run.
func remove_hero(seat: int) -> void:
	print("[net] seat %d left for good" % seat)
	var h = heroes.get(seat)
	if h == null or h == player:
		return
	heroes.erase(seat)
	# Their bats, swords and pools go with them.
	shots.list = shots.list.filter(func(sh): return sh.w.player != h)
	h.queue_free()
	if _awaiting.erase(seat):
		_check_picks_done()
	if not is_guest() and living_heroes().is_empty():
		_game_over()

## Heroes still in the fight: not down, and their player is connected.
func living_heroes() -> Array:
	return heroes.values().filter(func(h): return not h.dead and not h.away)

## Dev/testing: `give` adds weapons or passives (comma list, repeat an id to
## level it), `minute` skips ahead, `autoplay` lets a bot play.
func apply_dev_flags(f: Dictionary) -> void:
	dev = not f.has("real")  # `real`: a bot run that saves like a normal one (for testing)
	dev_unlimited = f.has("horde")
	autoplay = f.has("autoplay")
	player.autopilot = autoplay
	if f.has("give"):
		for id in str(f.give).split(","):
			if Db.WEAPONS.has(id) or Db.PASSIVES.has(id):
				player.upgrade(id)
	if f.has("bench"):
		_bench = 400
		player.stats.armor = 1.0  # can't die while being timed
	if f.has("horde"):
		# Stress test: fill the field with this many enemies right away.
		for k in int(f.horde):
			enemies.spawn(Db.ENEMIES.keys().pick_random(), obstacles.free_spot(player.position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60, 300), 8.0))
	if f.has("propdemo"):
		_prop_demo.call_deferred()
	if f.has("die"):
		_game_over.call_deferred()
	if f.has("levelup"):
		_on_level_up.call_deferred()
	if f.has("levelup_in"):
		get_tree().create_timer(float(f.levelup_in)).timeout.connect(_on_level_up)
	if f.has("chest"):
		pickups.drop("chest", player.position + Vector2(0, 4))
	if f.has("minute"):
		time = float(f.minute) * 60.0
		for i in stage.events.size():
			if stage.events[i].at < float(f.minute):
				_events_done[i] = true

## Dev: frozen monsters behind, in front of and beside the nearest prop, to
## check they sort against it correctly. Prints where to look.
func _prop_demo() -> void:
	var best = null
	for o in obstacles.props_in(view_rect().grow(200)):
		if best == null or o.pos.distance_to(player.position) < best.pos.distance_to(player.position):
			best = o
	if best == null:
		return
	var base: Vector2 = best.pos
	for spot in [[Vector2(0, -16), "zombie"], [Vector2(2, 14), "ghost"], [Vector2(-20, 2), "zombie"], [Vector2(22, -4), "scarecrow"]]:
		enemies.spawn(spot[1], base + spot[0])
	enemies.frozen = 1.0e9
	print("[propdemo] %s at %s, offset from hero %s" % [best.kind, base, base - player.position])

func _make(script: Script) -> Node:
	var n: Node = script.new()
	n.set("run", self)
	add_child(n)
	return n

## The screen area around a given hero (each player has their own).
func view_rect_for(h) -> Rect2:
	return Rect2(h.position - h.view_size * 0.5, h.view_size)

func view_rect() -> Rect2:
	var sz := get_viewport_rect().size
	return Rect2(camera.position - sz * 0.5, sz)

func _process(delta: float) -> void:
	if ended or get_tree().paused or net_paused:
		return
	if _bench > 0:
		var t0 := Time.get_ticks_usec()
		_tick(delta)
		_bench_us.append(Time.get_ticks_usec() - t0)
		for i in enemies.count():
			enemies.hp[i] = maxf(enemies.hp[i], 1.0e6)
		_bench -= 1
		if _bench == 0:
			_bench_us.sort()
			print("[bench] enemies %d  median %.2fms  p95 %.2fms  max %.2fms" % [enemies.count(),
				_bench_us[_bench_us.size() / 2] / 1000.0, _bench_us[int(_bench_us.size() * 0.95)] / 1000.0, _bench_us[-1] / 1000.0])
			print("[bench] per frame: enemies %.2fms shots %.2fms pickups %.2fms" % [_prof[0] / 400000.0, _prof[1] / 400000.0, _prof[2] / 400000.0])
			_log_status("bench")
			get_tree().quit()
		return
	_tick(delta)

func _tick(delta: float) -> void:
	delta = minf(delta, 1.0 / 20.0)
	if is_guest():
		_guest_tick(delta)
		return
	time += delta
	for h in heroes.values():
		h.step(delta)
	_follow_camera()
	_spawn(delta)
	var t0 := Time.get_ticks_usec()
	var targets := PackedVector2Array()
	for h in living_heroes():
		targets.append(h.position)
	if targets.is_empty():
		targets.append(player.position)
	enemies.step(delta, targets, view_rect())
	var t1 := Time.get_ticks_usec()
	_contact_damage()
	shots.step(delta)
	var t2 := Time.get_ticks_usec()
	pickups.step(delta)
	popups.step(delta)
	var t3 := Time.get_ticks_usec()
	if _bench > 0:
		_prof[0] += t1 - t0; _prof[1] += t2 - t1; _prof[2] += t3 - t2
	if autoplay and int(time / 30.0) != int((time - delta) / 30.0):
		_log_status("t")
	front.queue_redraw()
	obstacles.queue_redraw()

## Guests: move our own hero, glide everything else toward the last snapshot.
func _guest_tick(delta: float) -> void:
	var before := time
	time += delta
	if autoplay and int(time / 30.0) != int(before / 30.0):
		_log_status("t")
	for h in heroes.values():
		h.step(delta, false)
	_follow_camera()
	enemies.mirror_step(delta)
	popups.step(delta)
	shots.queue_redraw()
	front.queue_redraw()
	obstacles.queue_redraw()

func _hero_positions() -> Array:
	return heroes.values().map(func(h): return h.position)

func _follow_camera() -> void:
	camera.position = player.position
	obstacles.update_around(_hero_positions())
	# Snap the tiled ground to its tile size so it never runs out.
	ground.position = (player.position / Vector2(640, 400)).floor() * Vector2(640, 400)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not ended and _modal == null:
		_show_pause()

# ---------------------------------------------------------------- Spawning

## More heroes, more and tougher monsters.
func _team_scale() -> float:
	return 1.0 + 0.6 * (heroes.size() - 1)

func _spawn(delta: float) -> void:
	var minute := time / 60.0
	var curse := 0.0
	for h in heroes.values():
		curse = maxf(curse, h.stats.curse)
	var team := _team_scale()
	var hp_mul := (1.0 + minute * float(stage.hp_per_minute)) * (1.0 + curse) * (1.0 + (team - 1.0) * 0.5)
	var ramp := (1.0 + minute * 0.15) * (1.0 + curse) * team
	var cap: int = stage.max_alive if not dev_unlimited else 100000
	for i in stage.spawns.size():
		var sp: Dictionary = stage.spawns[i]
		if minute < sp.from or minute >= sp.to:
			continue
		_spawn_acc[i] += sp.rate * ramp * delta
		while _spawn_acc[i] >= 1.0:
			_spawn_acc[i] -= 1.0
			if enemies.count() < cap:
				enemies.spawn(sp.enemy, _offscreen_point(Db.ENEMIES[sp.enemy].radius), hp_mul)
	for i in stage.events.size():
		var ev: Dictionary = stage.events[i]
		if _events_done.has(i) or minute < ev.at:
			continue
		_events_done[i] = true
		match ev.type:
			"ring":
				for h in living_heroes():
					var r: float = h.view_size.length() * 0.55
					for k in ev.count:
						var at: Vector2 = h.position + Vector2.RIGHT.rotated(TAU * k / ev.count) * r
						enemies.spawn(ev.enemy, obstacles.free_spot(at, Db.ENEMIES[ev.enemy].radius), hp_mul)
			"boss":
				enemies.spawn(ev.enemy, _offscreen_point(Db.ENEMIES[ev.enemy].radius * 2.0), hp_mul, true)

## Just off a random hero's screen, never inside a grave, tree or building.
func _offscreen_point(r := 8.0) -> Vector2:
	var alive := living_heroes()
	var h = alive.pick_random() if not alive.is_empty() else player
	var dist: float = h.view_size.length() * 0.5 + 16.0
	var p := Vector2.ZERO
	for attempt in 8:
		p = h.position + Vector2.RIGHT.rotated(randf() * TAU) * dist
		if obstacles.is_free(p, r):
			return p
	return obstacles.free_spot(p, r)

func _contact_damage() -> void:
	for h in living_heroes():
		var worst := 0.0
		for i in enemies.query_circle(h.position, h.RADIUS):
			worst = maxf(worst, enemies.damage[i])
		if worst > 0.0:
			h.take_hit(worst)

# ---------------------------------------------------------------- Drops

func _on_enemy_died(at: Vector2, kind: String, is_boss: bool, attacker: int) -> void:
	var h = heroes.get(attacker, player)
	h.kills += 1
	h.kind_kills[kind] = h.kind_kills.get(kind, 0) + 1
	if is_boss:
		h.bosses += 1
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
	elif r < 0.05 * (1.0 + h.stats.greed):
		pickups.drop("silver", at + Vector2(4, 0))

func team_kills() -> int:
	var n := 0
	for h in heroes.values():
		n += h.kills
	return n

func collect(p: Dictionary, h) -> void:
	match p.type:
		"candy":
			h.candy += 1
			add_xp(p.value * (1.0 + h.stats.growth))
		"silver":
			h.silver_found += 2
		"heart":
			h.heal(30.0)
		"clock":
			enemies.frozen = 6.0
		"basket":
			pickups.pull_all_candy()
		"skull":
			var view := view_rect_for(h)
			for i in enemies.count():
				if view.has_point(enemies.pos[i]) and enemies.boss[i] == 0:
					enemies.hurt(i, 99999.0, h.position, 0.0, h.slot)
		"chest":
			h.chests += 1
			_open_chest(h)

func add_xp(amount: float) -> void:
	xp += amount
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		# Vampire Survivors-style curve: +10 per level, steeper after 20.
		xp_next += 10.0 if level < 20 else 13.0
		_on_level_up()

# ---------------------------------------------------------------- Screens

func _set_modal(c: Control) -> void:
	# A finger held down when a menu pops up never reports lifting: let go.
	for h in heroes.values():
		h.reset_touch()
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
	if _modal == null and _awaiting.is_empty():
		_next_level_up()

## Host/solo: everyone alive picks a card. Remote players get theirs over the network.
func _next_level_up() -> void:
	_awaiting = {}
	_sent_opts = {}
	for seat in heroes:
		if not heroes[seat].dead and not heroes[seat].away:
			_awaiting[seat] = true
	if _awaiting.is_empty():
		_awaiting[player.slot] = true
	for seat in _awaiting:
		var h = heroes[seat]
		if h == player:
			continue
		_sent_opts[seat] = h.upgrade_options(3)
		netsync.send_levelup(seat, _sent_opts[seat], level)
	if _awaiting.has(player.slot):
		show_level_up(player.upgrade_options(3), func(id): _picked(player.slot, id))
	else:
		_show_waiting()

## A hero chose a card (from this device or a remote player).
func _picked(seat: int, id: String) -> void:
	if not _awaiting.has(seat):
		return
	var h = heroes.get(seat)
	if h and id != "" and (Db.upgrade_def(id).size() > 0):
		h.upgrade(id)
	_awaiting.erase(seat)
	if seat == player.slot and not _awaiting.is_empty():
		_show_waiting()
	_check_picks_done()

func on_remote_pick(seat: int, id: String) -> void:
	_picked(seat, id)

func _check_picks_done() -> void:
	if not _awaiting.is_empty():
		return
	_pending_levels -= 1
	# Downed heroes come back with the team's level-up.
	for h in heroes.values():
		if h.dead and not h.away:
			h.revive(0.5)
			on_revive(h)
	if _pending_levels > 0:
		_next_level_up()
		return
	_set_modal(null)
	if is_host():
		netsync.send_resume()

func _show_waiting() -> void:
	var box := _panel("LEVEL UP!")
	box.add_child(UI.label("Waiting for the others...", 8, UI.DIM))

## The card picker. on_pick(id) is called once with the chosen id.
func show_level_up(options: Array, on_pick: Callable) -> void:
	var box := _panel("LEVEL UP!")
	var hand := HandMan.new()
	box.add_child(hand)
	box.move_child(hand, 0)
	box.add_child(UI.label("Choose one", 8, UI.DIM))
	var first: Button
	var chosen := [false]
	for id in options:
		var b := _upgrade_card(id, func():
			if chosen[0]:
				return
			chosen[0] = true
			on_pick.call(id))
		box.add_child(b)
		if first == null:
			first = b
	first.call_deferred("grab_focus")
	# The hand reads out whichever card you move to. Hooked up after the first
	# card's automatic focus so the opening one-liner gets its moment.
	(func():
		for i in options.size():
			var card: Button = box.get_child(box.get_child_count() - options.size() + i)
			var line := _card_line(options[i])
			card.focus_entered.connect(func(): hand.say(line))
			card.mouse_entered.connect(func(): hand.say(line))).call_deferred()
	if autoplay:
		first.call_deferred("emit_signal", "pressed")

## What the hand man says about a card: the item's own quote if it has one.
func _card_line(id: String) -> String:
	var d: Dictionary = Db.upgrade_def(id)
	if d.has("quote"):
		return '"%s"' % d.quote
	return d.get("desc", "")

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
	var ic := UI.icon(Db.icon_texture(d.icon), 32)
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

## Opens a chest for hero h. Solo it pauses for the treasure screen; in co-op
## the fight keeps going and the opener just sees a note.
func _open_chest(h) -> void:
	var gained := []  # [id, text]
	var ev: Array = h.evolvable()
	if not ev.is_empty():
		var pick: Array = ev.pick_random()
		var into: String = h.evolve(pick)
		gained.append([into, "UNION!" if pick[2] == "union" else "EVOLVED!"])
	else:
		# Luck makes the bigger chests likelier.
		var luck: float = h.stats.luck
		var n := 1 if randf() > 0.3 + luck * 0.3 else (3 if randf() < 0.3 + luck * 0.2 else 2)
		for k in n:
			var opts: Array = h.upgrade_options(1)
			if opts.is_empty():
				break
			h.upgrade(opts[0])
			gained.append([opts[0], "LV %d" % h.level_of(opts[0]) if h.level_of(opts[0]) > 0 else ""])
	if autoplay:
		print("[chest] ", ", ".join(gained.map(func(g): return "%s %s" % g)))
	if h != player:
		netsync.send_chest(h.slot, gained)
		return
	if mode != "solo":
		show_chest_note(gained)
		return
	var box := _panel("TREASURE!")
	var hand := HandMan.new(preload("res://src/data/quips.gd").TREASURE)
	box.add_child(hand)
	box.move_child(hand, 0)
	for g in gained:
		var d: Dictionary = Db.upgrade_def(g[0])
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		row.add_child(UI.icon(Db.icon_texture(d.icon), 32))
		var l := UI.label("%s  %s" % [d.name, g[1]], 8, UI.GOLD if g[1].ends_with("!") else UI.PALE)
		row.add_child(l)
		box.add_child(row)
	var ok := UI.button("OK", func():
		_set_modal(null)
		if _pending_levels > 0:
			_next_level_up())
	box.add_child(ok)
	ok.call_deferred("grab_focus")
	if autoplay:
		get_tree().create_timer(0.6, true).timeout.connect(func(): ok.emit_signal("pressed"))

func show_chest_note(gained: Array) -> void:
	for g in gained:
		hud.toast("%s %s" % [Db.upgrade_def(g[0]).get("name", g[0]), g[1]], UI.GOLD if str(g[1]).ends_with("!") else UI.PALE)

func _unlock_row(id: String) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	var name := ""
	if Db.CHARACTERS.has(id):
		var c: Dictionary = Db.CHARACTERS[id]
		name = c.name
		row.add_child(SheetView.new(c.idle, Vector2(20, 20)))
	elif Db.STAGES.has(id):
		name = Db.STAGES[id].name
	else:
		var d: Dictionary = Db.upgrade_def(id)
		name = d.name
		row.add_child(UI.icon(Db.icon_texture(d.icon), 16))
	row.add_child(UI.label("UNLOCKED " + name, 8, UI.PALE))
	return row

func _show_pause() -> void:
	if _modal or ended:
		return
	if mode != "solo":
		_show_coop_menu()
		return
	var box := _panel("PAUSED", UI.PALE)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 4)
	for id in player.weapons:
		grid.add_child(UI.icon(Db.icon_texture(Db.WEAPONS[id].icon), 32))
	for id in player.passives:
		grid.add_child(UI.icon(Db.icon_texture(Db.PASSIVES[id].icon), 32))
	var c := CenterContainer.new()
	c.add_child(grid)
	box.add_child(c)
	box.add_child(UI.label("Time %s   Kills %d" % [UI.time_text(time), player.kills], 8, UI.DIM))
	var resume := UI.button("RESUME", func(): _set_modal(null))
	box.add_child(resume)
	box.add_child(UI.button("GIVE UP", func():
		_set_modal(null)
		_game_over()))
	resume.call_deferred("grab_focus")

## Co-op can't pause for everyone: this menu only offers to leave.
func _show_coop_menu() -> void:
	var overlay := UI.dim_overlay()
	overlay.color.a = 0.5
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 6)
	overlay.add_child(box)
	box.add_child(UI.label("CO-OP  " + Net.code, 10, UI.GOLD))
	box.add_child(UI.label("The fight goes on!", 8, UI.DIM))
	var back := UI.button("BACK", func(): overlay.queue_free(), 22)
	box.add_child(back)
	box.add_child(UI.button("LEAVE GAME", func():
		overlay.queue_free()
		Net.leave()
		quit_to_menu.emit(), 22))
	hud.get_parent().add_child(overlay)
	back.call_deferred("grab_focus")

func _log_status(tag: String) -> void:
	var inv := []
	for id in player.weapons: inv.append("%s%d" % [id, player.weapons[id].level])
	for id in player.passives: inv.append("%s%d" % [id, player.passives[id]])
	# Anything sitting inside a grave, tree or building (should stay 0).
	var stuck := 0
	for i in enemies.count():
		if enemies.hp[i] > 0.0 and enemies._kind_fly[enemies.kidx[i]] == 0 and not obstacles.is_free(enemies.pos[i], 0.0):
			stuck += 1
	for p in pickups.list:
		if not obstacles.is_free(p.pos, 0.0):
			stuck += 1
	print("[%s] %s %s lv%d hp%d/%d kills%d heroes%d enemies%d shots%d pickups%d inside_props%d fps%d | %s" % [tag, mode, UI.time_text(time),
		level, player.hp, player.max_hp(), team_kills(), heroes.size(), enemies.count(), shots.list.size(),
		pickups.list.size(), stuck, Engine.get_frames_per_second(), ", ".join(inv)])

## A revival: clear the hero some room and carry on.
func on_revive(h) -> void:
	if is_guest():
		return
	for i in enemies.query_circle(h.position, 80.0):
		if enemies.boss[i] == 0:
			enemies.hurt(i, 99999.0, h.position, 0.0, h.slot)
		else:
			enemies.knock[i] += (enemies.pos[i] - h.position).normalized() * 400.0

func summary_for(h) -> Dictionary:
	var seconds := int(time)
	var earned := int((h.silver_found + seconds / 10) * (1.0 + h.stats.greed) * (1.0 + stage.get("silver_bonus", 0.0)))
	var seen := []
	for id in h.weapons: seen.append(id)
	for id in h.passives: seen.append(id)
	return {"seconds": seconds, "kills": h.kills, "level": level, "chests": h.chests, "bosses": h.bosses,
		"candy": h.candy, "healed": int(h.healed), "evolutions": h.evolutions, "unions": h.unions,
		"weapons_full": h.weapons_full, "silver": earned, "distance": int(h.distance / 16.0),
		"char": h.char_id, "kinds": h.kind_kills, "evolved": h.made, "seen": seen, "team": heroes.size()}

func _on_hero_down(h) -> void:
	if ended:
		return
	if is_guest():
		return
	if living_heroes().is_empty():
		_game_over()
	elif h == player:
		hud.toast("You're down! Back at the next level up.", UI.RED)
	else:
		netsync.send_toast(h.slot, "You're down! Back at the next level up.")

## Host/solo: the run is over for everyone.
func _game_over() -> void:
	if ended:
		return
	ended = true
	if autoplay:
		_log_status("DIED")
	if is_host():
		for seat in heroes:
			if heroes[seat] != player:
				netsync.send_over(seat, summary_for(heroes[seat]))
	show_results(summary_for(player))

## Results for this device's hero; saves the run to the profile.
func show_results(r: Dictionary) -> void:
	ended = true
	var result := {"best": false, "feats": [], "unlocks": []}
	if not dev:
		result = Meta.finish_run(r)
		if autoplay:
			print("[result] ", result, " silver=", Meta.silver)
		Bridge.report_death(r.seconds)
	var box := _panel("YOU DIED" if mode == "solo" else "THE HORDE WINS", UI.RED)
	box.add_child(UI.label(UI.time_text(r.seconds), 24, UI.PALE))
	if result.best:
		box.add_child(UI.label("NEW BEST!", 8, UI.GOLD))
	box.add_child(UI.label("Kills %d   Candy %d   Lv %d" % [r.kills, r.candy, r.level], 8, UI.DIM))
	box.add_child(UI.label("+%d silver" % r.silver, 10, UI.GOLD))
	for f in result.feats:
		box.add_child(UI.label("FEAT: " + Db.FEATS[f].name, 8, UI.GOLD))
	for id in result.unlocks:
		box.add_child(_unlock_row(id))
	var again := UI.button("PLAY AGAIN", func():
		get_tree().paused = false
		Net.leave()
		quit_to_menu.emit())
	box.add_child(again)
	again.call_deferred("grab_focus")

## Guests: the host left or the connection dropped.
func connection_lost(reason: String) -> void:
	if ended:
		return
	ended = true
	var box := _panel("DISCONNECTED", UI.RED)
	box.add_child(UI.body("The host left the game." if reason == "host" else "Lost the connection to the game.", 12))
	box.add_child(UI.button("OK", func():
		get_tree().paused = false
		quit_to_menu.emit()))
