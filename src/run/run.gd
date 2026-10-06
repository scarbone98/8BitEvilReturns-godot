extends Node2D
## One run: builds the world, drives every system each frame, spawns waves,
## and shows the level-up / chest / pause / game-over screens.
##
## mode "solo"  - one hero, everything local
##      "host"  - co-op: this game runs the fight for every hero and streams
##                it to the others (see NetSync)
##      "guest" - co-op: draws the host's fight and moves only its own hero
##      "server" - co-op run by the Scareathon server: a host with no hero of
##                its own; every player is a guest. Started headless.
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
var ground_fx: Node2D
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
var _log_clock := 0.0  # guests: the bot's status log (the run clock follows the host's)
var _modal: Control
var autoplay := false
# 20:00 clears the map: the field is wiped and the Reaper comes, then another
# every minute. Nightmare is the harder version of a map you've cleared.
const CLEAR_SECONDS := 1200.0
const REAPER_EVERY := 60.0
const NIGHTMARE := {"hp": 1.6, "spawn": 1.5, "speed": 1.15, "elite": 0.08, "events_at": 0.75, "silver": 1.5}
var nightmare := false
var attract := false       # the title screen's background fight: no HUD, no saving, no level-ups
var cleared := false
var reapers_slain := 0
var _reaper_clock := 0.0
var _reapers_sent := 0
var twist := ""            # this map's Nightmare twist (stages.gd), "" when not Nightmare
var _twist_clock := 0.0
const BOSS_HP_PER_LEVEL := 0.05   # +5% boss health per team level
const CONTACT_PER_MINUTE := 0.03  # +3% contact damage per minute
const SWARM_HP := 0.25       # of a normal one's health: one hit drops them (and they bite half as hard)
var _wave_acc := 0.0
var _topup_acc := 0.0
const TOPUP_RATE := 10.0     # monsters a second while under a wave's minimum
var _swarm_minute := -1
var _swarm_dir := 0.0
var _swarm_acc := 0.0
var _swarm_left := 0.0       # fodder still to come in the current swarm
var _swarm_rate := 0.0       # per second
var _swarm_sides := 1
var _hp_mul_now := 1.0     # the spawns' current toughness, for monsters twists add
var _twist_count := 0      # dev reports: heals, puddles or blasts so far
# Map quests (see quests.gd): what the whole team did this run.
var relic_found := false
var relic_pos := Vector2.INF
var relic: Node2D
var boss_kinds := {}   # boss kind -> true once one is defeated
var team_kinds := {}   # enemy kind -> defeated, every hero together
var _quest_told := {}  # quest id -> already toasted this run
var _quest_clock := 0.0
var _stuck_check := false   # dev flag stuckcheck: report monsters that stop short of the heroes
var _stuck_clock := 0.0
var _stuck_seen := {}       # uid -> position at the last sample
var _stuck_total := Vector2i.ZERO  # (stuck, checked) over the run
var _stuck_printed := -1
var dev := false  # dev/test runs never save
var dev_unlimited := false
var _bench := 0   # frames left to time; dev flag "bench"
var _bench_us := []
var _prof := [0, 0, 0]

func is_guest() -> bool:
	return mode == "guest"

func is_host() -> bool:
	return mode == "host" or mode == "server"

func is_server() -> bool:
	return mode == "server"

## A hero played on this device (never true on the server).
func _is_local(h) -> bool:
	return h != null and h.mode == "local"

## coop: {} for solo, or {mode: "host"|"guest", players: [{slot, name, hero}]}.
func start(char_id: String, p_stage := "graveyard", coop := {}, p_nightmare := false) -> void:
	mode = coop.get("mode", "solo")
	nightmare = p_nightmare
	twist = str(Db.STAGES[p_stage].get("twist", {}).get("type", "")) if nightmare else ""
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
	ground_fx = Node2D.new()  # pools and auras, under the monsters
	add_child(ground_fx)
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
			var me := seat == Net.slot and not is_server()
			var hero_mode := "local" if me else ("remote" if is_host() else "puppet")
			var hero = _add_hero(seat, char_id if me else str(p.hero), hero_mode, str(p.name))
			hero.position = Vector2(seat * 24 - 36, 0)
			if me or (is_server() and player == null):
				player = hero  # on the server: just a reference hero, not played
	front = Node2D.new()
	front.draw.connect(func(): enemies.draw_in_front_of_props(front))
	add_child(front)
	shots = _make(ShotsScript)
	ground_fx.draw.connect(func(): shots.draw_ground(ground_fx))
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
	if twist == "blizzard" or twist == "darkness":
		var fog = preload("res://src/ui/fog.gd").new()
		fog.run = self
		fog.kind = twist
		root.add_child(fog)  # under the HUD
	hud = HudScript.new()
	hud.run = self
	hud.pause_pressed.connect(_show_pause)
	root.add_child(hud)
	obstacles.update_around(_hero_positions())
	if not attract:
		_place_relic()
	if nightmare and Db.STAGES[stage_id].has("twist"):
		var tw: Dictionary = Db.STAGES[stage_id].twist
		hud.toast.call_deferred("NIGHTMARE: %s" % tw.name, UI.RED)
		hud.toast.call_deferred(str(tw.desc), UI.RED)

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
		for k in int(Db.CHARACTERS[char_id].get("start_level", 1)) - 1:
			h.upgrade(Db.CHARACTERS[char_id].weapon)
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
	if h == null or _is_local(h):
		return
	heroes.erase(seat)
	if h == player:
		player = heroes.values()[0] if not heroes.is_empty() else null
		if player == null:
			_game_over()
			return
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
	if f.has("teleport"):
		# Dev: start somewhere far away (x,y), e.g. to test co-op players far apart.
		var xy: PackedStringArray = str(f.teleport).split(",")
		if xy.size() == 2:
			player.position = Vector2(float(xy[0]), float(xy[1]))
	if f.has("propdemo"):
		_prop_demo.call_deferred()
	if f.has("die"):
		_game_over.call_deferred()
	if f.has("down"):
		# Dev (host/server): knock co-op seat SEAT down after SECS: `down=SEAT,SECS`.
		var sd: PackedStringArray = str(f.down).split(",")
		get_tree().create_timer(float(sd[1]) if sd.size() > 1 else 5.0).timeout.connect(func():
			var h = heroes.get(int(sd[0]))
			if h and not h.dead:
				print("[dev] knocking seat %d down" % h.slot)
				h._invuln = 0.0
				h.revivals = 0
				h.take_hit(99999.0))
	if f.has("levelup"):
		_on_level_up.call_deferred()
	_stuck_check = f.has("stuckcheck")
	if _stuck_check:
		player.god = true  # can't die while measuring
	player.stand = f.has("stand")
	if f.has("trapdemo"):
		_trap_demo.call_deferred()
	if f.has("die_in"):
		get_tree().create_timer(float(f.die_in)).timeout.connect(_game_over)
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
	if not attract:
		time += delta
	if not cleared and time >= CLEAR_SECONDS:
		_clear_map()
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
	_check_relic()
	if not attract:
		_check_quests(delta)
	_ooze_check()
	if _stuck_check:
		_sample_stuck(delta)
	var t3 := Time.get_ticks_usec()
	if _bench > 0:
		_prof[0] += t1 - t0; _prof[1] += t2 - t1; _prof[2] += t3 - t2
	if autoplay and int(time / 30.0) != int((time - delta) / 30.0):
		_log_status("t")
	front.queue_redraw()
	ground_fx.queue_redraw()

## Guests: move our own hero, glide everything else toward the last snapshot.
func _guest_tick(delta: float) -> void:
	time += delta
	_log_clock += delta
	if autoplay and _log_clock >= 30.0:
		_log_clock -= 30.0
		_log_status("t")
	for h in heroes.values():
		h.step(delta, false, h == player)
	_ooze_check()
	_follow_camera()
	shots.step(delta)  # our own predicted shots
	popups.step(delta)
	shots.queue_redraw()
	front.queue_redraw()
	ground_fx.queue_redraw()

func _hero_positions() -> Array:
	return heroes.values().map(func(h): return h.position)

func _follow_camera() -> void:
	# Follow exactly, like the original: no rounding at all. (Rounding to world
	# pixels made the view hop; rounding to screen pixels made the floor move
	# in uneven 1-2 pixel steps under a still hero.)
	camera.position = player.position
	camera.force_update_scroll()  # apply this frame, so the view never lags the hero
	obstacles.update_around(_hero_positions())
	# Snap the tiled ground to its tile size so it never runs out.
	ground.position = (player.position / Vector2(640, 400)).floor() * Vector2(640, 400)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not ended and _modal == null and not attract:
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
	if cleared:
		_reaper_tick(delta)
		return
	_twist_tick(delta)
	var nm: float = 1.0 if not nightmare else 0.0  # 1 normal, 0 nightmare (for the lerps below)
	var hp_pm: float = float(stage.hp_per_minute) * (1.0 if nm == 1.0 else NIGHTMARE.hp)
	var hp_mul := (1.0 + minute * hp_pm) * (1.0 + curse) * (1.0 + (team - 1.0) * 0.5)
	var ramp := (1.0 + minute * 0.15) * (1.0 + curse) * team * (1.0 if nm == 1.0 else NIGHTMARE.spawn) * (3.0 if attract else 1.0)
	var cap: int = (stage.max_alive if not dev_unlimited else 100000) if not attract else 70
	var speed_mul: float = stage.get("speed_mul", 1.0) * (1.0 if nm == 1.0 else NIGHTMARE.speed)
	var elite_chance: float = 0.0 if nm == 1.0 else NIGHTMARE.elite
	_hp_mul_now = hp_mul
	_wave_tick(delta, hp_mul, speed_mul, elite_chance, cap,
		float(stage.get("pace", 1.0)) * (1.0 + curse) * team * (1.0 if nm == 1.0 else NIGHTMARE.spawn) * (3.0 if attract else 1.0))
	for i in stage.spawns.size():
		var sp: Dictionary = stage.spawns[i]
		if minute < sp.from or minute >= sp.to:
			continue
		_spawn_acc[i] += sp.rate * ramp * delta
		while _spawn_acc[i] >= 1.0:
			_spawn_acc[i] -= 1.0
			if enemies.count() < cap:
				enemies.spawn(sp.enemy, _offscreen_point(Db.ENEMIES[sp.enemy].radius), hp_mul, false, speed_mul, randf() < elite_chance)
	for i in stage.events.size():
		var ev: Dictionary = stage.events[i]
		if _events_done.has(i) or minute < float(ev.at) * (1.0 if nm == 1.0 else NIGHTMARE.events_at):
			continue
		_events_done[i] = true
		match ev.type:
			"ring":
				for h in living_heroes():
					var r: float = h.view_size.length() * 0.55
					for k in ev.count:
						var at: Vector2 = h.position + Vector2.RIGHT.rotated(TAU * k / ev.count) * r
						enemies.spawn(ev.enemy, obstacles.free_spot(at, Db.ENEMIES[ev.enemy].radius), hp_mul, false, speed_mul, randf() < elite_chance)
			"boss":
				# Nightmare bosses come in pairs.
				for k in (1 if nm == 1.0 else 2):
					enemies.spawn(ev.enemy, _offscreen_point(Db.ENEMIES[ev.enemy].radius * 2.0), hp_mul * boss_level_scale(), true, speed_mul)

## This minute's wave from Db.PACING: keep at least `min` monsters out, add
## `rate` a second on top, and run the minute's swarm. `scale` is the map's
## pace times curse, team size and Nightmare.
func _wave_tick(delta: float, hp_mul: float, speed_mul: float, elite_chance: float, cap: int, scale: float) -> void:
	var wi := mini(int(time / 60.0), Db.PACING.size() - 1)
	var wave: Dictionary = Db.PACING[wi]
	var cast: Dictionary = stage.cast
	var roles: Array = Db.ROLE_WEIGHTS.keys() if wave.roles.has("all") else wave.roles
	var total := 0.0
	for r in roles:
		total += Db.ROLE_WEIGHTS[r]
	var spawn_one := func():
		var pick := randf() * total
		var k: String = cast[roles[-1]]
		for r in roles:
			pick -= Db.ROLE_WEIGHTS[r]
			if pick <= 0.0:
				k = cast[r]
				break
		enemies.spawn(k, _offscreen_point(Db.ENEMIES[k].radius), hp_mul, false, speed_mul, randf() < elite_chance)
	# Under the minimum: top up fast, but as a stream (TOPUP_RATE a second)
	# so a new wave never lands as an instant ring around you.
	var short := mini(int(wave.min * scale) - enemies.count(), cap - enemies.count())
	if short > 0:
		_topup_acc = minf(_topup_acc + TOPUP_RATE * delta, float(short))
		while _topup_acc >= 1.0:
			_topup_acc -= 1.0
			spawn_one.call()
	else:
		_topup_acc = 0.0
	_wave_acc += wave.rate * scale * delta
	while _wave_acc >= 1.0:
		_wave_acc -= 1.0
		if enemies.count() < cap:
			spawn_one.call()
	# The minute's swarm: one-hit fodder pouring in from one side (or two).
	if wave.has("swarm") and wi != _swarm_minute and not attract:
		_swarm_minute = wi
		_swarm_left = wave.swarm[0] * scale
		_swarm_rate = wave.swarm[0] * scale / float(wave.swarm[1])
		_swarm_sides = int(wave.get("sides", 1))
		_swarm_dir = randf() * TAU
		_tell_everyone("A SWARM IS COMING!" if _swarm_sides == 1 else "THEY'RE COMING FROM BOTH SIDES!", UI.GOLD)
	if _swarm_left > 0.0:
		_swarm_acc += _swarm_rate * delta
		while _swarm_acc >= 1.0 and _swarm_left > 0.0:
			_swarm_acc -= 1.0
			_swarm_left -= 1.0
			if enemies.count() < cap:
				var fodder: String = cast.swarm
				var side := _swarm_dir + (PI if _swarm_sides == 2 and randi() % 2 == 0 else 0.0)
				var at := _offscreen_point(Db.ENEMIES[fodder].radius, side + randf_range(-0.6, 0.6))
				enemies.spawn(fodder, at, hp_mul * SWARM_HP, false, speed_mul, false, 0.5)

## Bosses grow with the team's level (like VS), so a strong build still has
## to work for them.
func boss_level_scale() -> float:
	return 1.0 + BOSS_HP_PER_LEVEL * (level - 1)

## Monsters hit a little harder as the night goes on (health grows slowly,
## so this keeps late hits worth dodging). Not the Reaper: he's tuned alone.
func contact_scale() -> float:
	return 1.0 + CONTACT_PER_MINUTE * time / 60.0

## Just off a random hero's screen, never inside a grave, tree or building.
## `angle` picks the side (NAN: anywhere around).
func _offscreen_point(r := 8.0, angle := NAN) -> Vector2:
	var alive := living_heroes()
	var h = alive.pick_random() if not alive.is_empty() else player
	var dist: float = h.view_size.length() * 0.5 + 16.0
	var p := Vector2.ZERO
	for attempt in 8:
		var a: float = randf() * TAU if is_nan(angle) else angle + randf_range(-0.15, 0.15)
		p = h.position + Vector2.RIGHT.rotated(a) * dist
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

func _on_enemy_died(at: Vector2, kind: String, is_boss: bool, attacker: int, is_elite := false) -> void:
	var h = heroes.get(attacker, player)
	h.kills += 1
	h.kind_kills[kind] = h.kind_kills.get(kind, 0) + 1
	team_kinds[kind] = team_kinds.get(kind, 0) + 1
	if twist == "pumpkin_burst" and (kind == "pumpkin" or kind == "gourd_spitter"):
		enemies.add_blast(at, 18.0, 8.0)
		_twist_count += 1
	if kind == "reaper":
		reapers_slain += 1
		_tell_everyone("THE REAPER IS SLAIN!", UI.GOLD)
		if autoplay:
			print("[reaper] slain at %s by seat %d" % [UI.time_text(time), attacker])
	if attract:
		return  # the title screen's fight drops nothing
	if is_boss:
		h.bosses += 1
		boss_kinds[kind] = true
		pickups.drop("chest", at)
		return
	var tier: int = Db.ENEMIES[kind].candy
	if is_elite:
		tier = mini(2, tier + 1)
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
	while xp >= xp_next * _xp_scale():
		xp -= xp_next * _xp_scale()
		level += 1
		# Vampire Survivors-style curve: +10 per level, steeper after 20 and 40.
		xp_next += 10.0 if level < 20 else (13.0 if level < 40 else 16.0)
		_on_level_up()

## Co-op shares one XP bar between more players fighting more monsters
## (60% more per extra player), so each level needs a little more: 25% per
## extra player keeps everyone's builds growing about as fast as solo.
func _xp_scale() -> float:
	return 1.0 + 0.25 * (heroes.size() - 1)

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
	if attract:
		return
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
		if is_server():
			_pending_levels = 0  # nobody can choose: carry on
			return
		_awaiting[player.slot] = true
	for seat in _awaiting:
		var h = heroes[seat]
		if _is_local(h):
			continue
		_sent_opts[seat] = h.upgrade_options(3)
		netsync.send_levelup(seat, _sent_opts[seat], level)
	if is_server():
		get_tree().paused = true  # the fight waits for everyone's card
	elif _awaiting.has(player.slot):
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
	if _is_local(h) and not _awaiting.is_empty():
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
	if not _is_local(h):
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

## Lets a label wrap inside the panel instead of running off a phone screen.
func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

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
	var text := "UNLOCKED " + name
	if Db.CHARACTERS.has(id) and int(Db.CHARACTERS[id].get("cost", 0)) > 0 and not Meta.is_unlocked(id):
		text = "NEW HERO FOR SALE: %s (%d silver)" % [name, int(Db.CHARACTERS[id].cost)]
	var l := _wrap(UI.label(text, 8, UI.PALE, HORIZONTAL_ALIGNMENT_LEFT if row.get_child_count() > 0 else HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(l)
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
	_add_quest_lines(box)
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
	_add_quest_lines(box)
	var back := UI.button("BACK", func(): overlay.queue_free(), 22)
	box.add_child(back)
	box.add_child(UI.button("LEAVE GAME", func():
		overlay.queue_free()
		Net.leave()
		quit_to_menu.emit(), 22))
	hud.get_parent().add_child(overlay)
	back.call_deferred("grab_focus")

func _log_status(tag: String) -> void:
	# Co-op: every hero's inventory as this device sees it, to compare host and guests.
	if mode != "solo":
		for seat in heroes:
			var h = heroes[seat]
			if mode == "host" or h == player:
				var items := []
				for id in h.weapons: items.append("%s%d" % [id, h.weapons[id].level])
				for id in h.passives: items.append("%s%d" % [id, h.passives[id]])
				items.sort()
				print("[inv %s seat%d %s] %s" % [mode, seat, h.char_id, ",".join(items)])
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
	print("[%s] %s%s %s lv%d hp%d/%d kills%d heroes%d enemies%d shots%d monster_shots%d pickups%d inside_props%d fps%d | %s" % [tag, mode, (" nightmare %s:%d" % [twist, _twist_count]) if nightmare else "", UI.time_text(time),
		level, player.hp, player.max_hp(), team_kills(), heroes.size(), enemies.count(), shots.list.size(), enemies.bullets.size(),
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

# ---------------------------------------------------------------- Map quests

## Puts this map's relic where quests.gd says (pushed clear of props, the
## same spot on every device since props are seeded by position).
func _place_relic() -> void:
	var q: Dictionary = Db.QUESTS.get(stage_id, {})
	if not q.has("relic"):
		return
	var r: Dictionary = q.relic
	relic_pos = obstacles.free_spot(Vector2.RIGHT.rotated(deg_to_rad(float(r.dir))) * float(r.dist), 10.0)
	relic = preload("res://src/run/relic.gd").new()
	relic.sprite = str(r.sprite)
	relic.position = relic_pos
	world.add_child(relic)

## Host/solo: any hero standing on the relic picks it up for the team.
func _check_relic() -> void:
	if relic_found or relic == null:
		return
	for h in living_heroes():
		if h.position.distance_to(relic_pos) < 14.0:
			on_relic_found()
			if netsync:
				netsync.send_relic()
			return

func on_relic_found() -> void:
	if relic_found:
		return
	relic_found = true
	if relic:
		relic.queue_free()
		relic = null
	hud.toast("Found the %s!" % Db.QUESTS[stage_id].relic.name, UI.GOLD)
	if autoplay:
		print("[quest] relic found at %s" % UI.time_text(time))

## What the team has done toward this map's quests so far.
## This map's quests with live progress, for the pause menus.
func _add_quest_lines(box: Control) -> void:
	var list := Db.quests_for(stage_id)
	if list.is_empty():
		return
	box.add_child(UI.label("MAP QUESTS", 8, UI.GOLD))
	var st := quest_state()
	for q in list:
		var p := Db.quest_progress(q.check, st)
		var done: bool = Meta.quests.has(q.id) or p[0] >= p[1]
		var prog := ""
		if not done and int(p[1]) > 1:
			if q.check.get("run") == "seconds":
				prog = "  %s/%s" % [UI.time_text(p[0]), UI.time_text(p[1])]
			else:
				prog = "  %d/%d" % [mini(p[0], p[1]), p[1]]
		box.add_child(UI.body(("+ " if done else "- ") + q.desc + prog, 10, UI.GOLD if done else UI.DIM))

func quest_state() -> Dictionary:
	var bosses := 0
	for h in heroes.values():
		bosses += h.bosses
	return {"relic": relic_found, "boss_kinds": boss_kinds, "team_kinds": team_kinds,
		"bosses": bosses, "seconds": int(time)}

## Host/solo: tell the player the moment a quest they haven't done is met.
## (It's saved, and its silver paid, when the run ends.)
func _check_quests(delta: float) -> void:
	_quest_clock -= delta
	if _quest_clock > 0.0:
		return
	_quest_clock = 0.5
	var st := quest_state()
	for q in Db.quests_for(stage_id):
		if Meta.quests.has(q.id) or _quest_told.has(q.id) or not Db.quest_met(q.check, st):
			continue
		_quest_told[q.id] = true
		hud.toast("QUEST COMPLETE: " + q.name, UI.GOLD)
		if autoplay:
			print("[quest] complete: %s at %s" % [q.id, UI.time_text(time)])
		if netsync:
			for seat in heroes:
				if not _is_local(heroes[seat]):
					netsync.send_quest_toast(seat, q.id, q.name)

## Dev: boxes a few zombies in a closed ring of fence posts near the hero, so
## the stuck safety net has to free them (watch "moved by the safety net").
func _trap_demo() -> void:
	var c: Vector2 = player.position + Vector2(90, 0)
	obstacles.add_ring(c, 26.0)
	for k in 3:
		enemies.spawn("zombie", c + Vector2(k * 6 - 6, 0))
	print("[trapdemo] 3 zombies boxed in at %s" % c)

## Dev: every 2s, walking monsters within 250px of a hero (but not touching
## one) that moved under 6px since the last sample while pressed against a
## prop count as stuck.
func _sample_stuck(delta: float) -> void:
	_stuck_clock -= delta
	if _stuck_clock > 0.0:
		return
	_stuck_clock = 2.0
	var now := {}
	var stuck := 0
	var checked := 0
	var heroes_at := living_heroes().map(func(h): return h.position)
	for i in enemies.count():
		var k: int = enemies.kidx[i]
		if enemies._kind_fly[k] == 1 or enemies._kind_rooted[k] == 1 or enemies.frozen > 0.0:
			continue
		var p: Vector2 = enemies.pos[i]
		var d := INF
		for hp_ in heroes_at:
			d = minf(d, p.distance_to(hp_))
		if d > 250.0 or d < 30.0:
			continue
		var u: int = enemies.uid[i]
		now[u] = p
		if _stuck_seen.has(u):
			checked += 1
			# Stuck on a prop: barely moved, and right up against one.
			if p.distance_to(_stuck_seen[u]) < 6.0 and not obstacles.is_free(p, enemies.radius[i] * 0.6 + 3.0):
				stuck += 1
	_stuck_seen = now
	_stuck_total += Vector2i(stuck, checked)
	if int(time / 30.0) != _stuck_printed:
		_stuck_printed = int(time / 30.0)
		print("[stuck] %s: %d of %d this sample; run so far %d of %d (%.1f%%); moved by the safety net %d; pickups %d" % [UI.time_text(time), stuck, checked,
			_stuck_total.x, _stuck_total.y, 100.0 * _stuck_total.x / maxf(1.0, _stuck_total.y), enemies.relocated, pickups.list.size()])

# ---------------------------------------------------------------- Title screen

const ATTRACT_WEAPONS := ["soul_eater", "hellfire", "thunderstorm", "vampire_swarm", "gatling_crossbow",
	"blood_moon", "ghost_lantern", "jacks_inferno", "eldritch_horror", "arc_reactor"]

## The title screen's fight: the hero holds the middle with a few flashy
## evolved weapons while a steady crowd walks in. Clock stopped at 3:00, no
## bosses or events, nothing saved, can't die.
func start_attract(char_id: String, p_stage: String) -> void:
	attract = true
	dev = true
	start(char_id, p_stage)
	hud.visible = false
	time = 180.0
	for i in stage.events.size():
		_events_done[i] = true
	player.god = true
	player.autopilot = true
	player.stand = true
	# One flashy evolution, and the hero's own weapon a few levels up: strong
	# enough to hold, weak enough that the crowd gets close.
	player.upgrade(ATTRACT_WEAPONS.pick_random())
	for k in 3:
		player.upgrade(Db.CHARACTERS[char_id].weapon)

# ---------------------------------------------------------------- Nightmare twists

const GRAVE_KINDS := ["grave_1_small", "grave_2", "prop_open_grave", "prop_ice_grave"]

## Host/solo: the map's twist, on Nightmare (stops at 20:00).
func _twist_tick(delta: float) -> void:
	if twist == "":
		return
	_twist_clock -= delta
	if _twist_clock > 0.0:
		return
	match twist:
		"graves":
			# A grave near a hero bursts: three zombies climb out.
			_twist_clock = 5.0
			var alive := living_heroes()
			if alive.is_empty():
				return
			var h = alive.pick_random()
			var near := []
			for o in obstacles.props_in(Rect2(h.position - Vector2(220, 220), Vector2(440, 440))):
				var d: float = o.pos.distance_to(h.position)
				if GRAVE_KINDS.has(o.kind) and d > 50.0 and d < 220.0:
					near.append(o)
			if near.is_empty():
				return
			var g = near.pick_random()
			if autoplay:
				print("[twist] a grave bursts at %s" % UI.time_text(time))
			for k in 3:
				var at: Vector2 = g.pos + Vector2((k - 1) * 10, 10)
				enemies.spawn("zombie", obstacles.free_spot(at, 6.0), _hp_mul_now, false, 1.0, randf() < NIGHTMARE.elite)
		"fountains":
			# Blood fountains heal the monsters around them, every second.
			_twist_clock = 1.0
			for o in _props_near_heroes("prop_blood_fountain", 300.0):
				for i in enemies.query_circle(o.c, 70.0):
					enemies.hp[i] = minf(enemies.max_hp[i], enemies.hp[i] + enemies.max_hp[i] * 0.04)
					_twist_count += 1
		"ooze":
			# Pipes pour ooze that slows whoever wades through it.
			_twist_clock = 4.0
			for o in _props_near_heroes("prop_sewer_pipe", 260.0):
				enemies.add_puddle(o.pos + Vector2(randf_range(-10, 10), randf_range(10, 22)), 16.0, 8.0)
				_twist_count += 1
		_:
			_twist_clock = 9999.0  # blizzard and darkness are drawn by the HUD

func _props_near_heroes(kind: String, reach: float) -> Array:
	var seen := {}
	var out := []
	for h in living_heroes():
		for o in obstacles.props_in(Rect2(h.position - Vector2(reach, reach), Vector2(reach * 2.0, reach * 2.0))):
			if o.kind == kind and not seen.has(o.pos):
				seen[o.pos] = true
				out.append(o)
	return out

## This device's own hero in ooze is slowed. The host checks its puddles;
## a guest checks the ones the host drew for it (it moves its hero itself).
func _ooze_check() -> void:
	if player == null or player.dead:
		return
	if is_guest():
		for op in shots.remote_ops:
			if int(op[0]) & 31 == shots.OP_PUDDLE and (op[3] as Color).g > (op[3] as Color).r \
					and player.position.distance_to(op[1]) < float(op[2]) + 2.0:
				player.slowed = 0.25
				return
		return
	for hz in enemies.hazards:
		if hz.type == "puddle" and player.position.distance_to(hz.pos) < hz.radius + 2.0:
			player.slowed = 0.25
			return

# ---------------------------------------------------------------- 20:00

## Host/solo: the map is cleared. Everything on the field is gone; the
## Reaper comes (and another every minute).
func _clear_map() -> void:
	cleared = true
	enemies.clear_all()
	_tell_everyone("20:00 - MAP CLEARED. THE REAPER COMES...", UI.RED)
	if autoplay:
		print("[clear] %s: field wiped, %d monsters left" % [UI.time_text(time), enemies.count()])
	_spawn_reaper()
	_reaper_clock = REAPER_EVERY

func _reaper_tick(delta: float) -> void:
	_reaper_clock -= delta
	if _reaper_clock <= 0.0:
		_reaper_clock = REAPER_EVERY
		_spawn_reaper()

func _spawn_reaper() -> void:
	# Each Reaper is half again as tough as the last.
	var hp_mul := _team_scale() * (1.5 if nightmare else 1.0) * (1.0 + 0.5 * _reapers_sent)
	_reapers_sent += 1
	enemies.spawn("reaper", _offscreen_point(20.0), hp_mul, true, 1.0)
	if autoplay:
		print("[reaper] spawned at %s" % UI.time_text(time))

## A toast on this screen and every co-op player's.
func _tell_everyone(text: String, col: Color) -> void:
	hud.toast(text, col)
	if netsync:
		for seat in heroes:
			if not _is_local(heroes[seat]):
				netsync.send_toast(seat, text)

func summary_for(h) -> Dictionary:
	var seconds := int(time)
	var earned := int((h.silver_found + seconds / 10) * (1.0 + h.stats.greed) * (1.0 + stage.get("silver_bonus", 0.0))
		* (NIGHTMARE.silver if nightmare else 1.0))
	var seen := []
	for id in h.weapons: seen.append(id)
	for id in h.passives: seen.append(id)
	return {"seconds": seconds, "kills": h.kills, "level": level, "chests": h.chests, "bosses": h.bosses,
		"candy": h.candy, "healed": int(h.healed), "evolutions": h.evolutions, "unions": h.unions,
		"weapons_full": h.weapons_full, "silver": earned, "distance": int(h.distance / 16.0),
		"char": h.char_id, "kinds": h.kind_kills, "evolved": h.made, "seen": seen, "team": heroes.size(),
		"stage": stage_id, "quest": quest_state(), "cleared": cleared, "reapers": reapers_slain, "nightmare": nightmare}

func _on_hero_down(h) -> void:
	if ended:
		return
	if is_guest():
		return
	if living_heroes().is_empty():
		_game_over()
	elif _is_local(h):
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
			if not _is_local(heroes[seat]):
				netsync.send_over(seat, summary_for(heroes[seat]))
	if is_server():
		print("[server] game over at ", UI.time_text(time))
		get_tree().create_timer(5.0, true).timeout.connect(get_tree().quit)
		return
	show_results(summary_for(player))

## Results for this device's hero; saves the run to the profile.
func show_results(r: Dictionary) -> void:
	ended = true
	var result := {"best": false, "feats": [], "unlocks": [], "quests": [], "crowned": false}
	if dev and Bridge.flags().has("fakeresults"):
		# Dev: the busiest results screen a run can give, to check it fits.
		r = r.duplicate(); r.merge({"kills": 2501, "candy": 3000, "level": 32, "silver": 1234, "cleared": true, "reapers": 2}, true)
		result = {"best": true, "feats": Db.FEATS.keys().slice(0, 6), "quests": Db.quests_for(stage_id).map(func(q): return q.id),
			"unlocks": ["cursed_sword", "lightning", "scope", "snail_king", "crimson_crypt", "bog_king"], "crowned": true,
			"first_clear": true, "first_reaper": true}
	elif not dev:
		result = Meta.finish_run(r)
		if autoplay:
			print("[result] ", result, " silver=", Meta.silver)
		Bridge.report_death(r.seconds)
	var title := "YOU DIED" if mode == "solo" else "THE HORDE WINS"
	if r.get("cleared", false):
		title = "THE REAPER WINS" if int(r.get("reapers", 0)) == 0 else "YOU FELL... A LEGEND"
	var box := _panel(title, UI.RED)
	if title.length() > 15:  # 16px letters: longer titles run off a phone
		(box.get_child(0) as Label).add_theme_font_size_override("font_size", 12)
	box.add_child(UI.label(UI.time_text(r.seconds), 24, UI.PALE))
	if result.best:
		box.add_child(UI.label("NEW BEST!", 8, UI.GOLD))
	box.add_child(_wrap(UI.label("Kills %d  Candy %d  Lv %d" % [r.kills, r.candy, r.level], 8, UI.DIM)))
	box.add_child(UI.label("+%d silver" % r.silver, 10, UI.GOLD))
	# Everything earned goes in a list that scrolls if it's taller than the
	# screen, so PLAY AGAIN never gets pushed off.
	var rewards := VBoxContainer.new()
	rewards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rewards.add_theme_constant_override("separation", 4)
	var outer := box
	box = rewards
	for f in result.feats:
		box.add_child(_wrap(UI.label("FEAT: " + Db.FEATS[f].name, 8, UI.GOLD)))
	for id in result.unlocks:
		box.add_child(_unlock_row(id))
	for id in result.get("quests", []):
		for q in Db.quests_for(stage_id):
			if q.id == id:
				box.add_child(UI.label("QUEST: %s  +%d silver" % [q.name, q.silver], 8, UI.GOLD))
	if result.get("crowned", false):
		box.add_child(UI.label("MAP CROWNED!  +%d silver" % Db.QUEST_CROWN_SILVER, 10, UI.GOLD))
	if r.get("cleared", false):
		box.add_child(UI.label(("NIGHTMARE CLEARED!" if r.get("nightmare", false) else "MAP CLEARED!")
			+ ("  +%d silver" % Meta.FIRST_CLEAR_SILVER if result.get("first_clear", false) else ""), 10, UI.GOLD))
	if int(r.get("reapers", 0)) > 0:
		box.add_child(UI.label("REAPER SLAIN x%d!" % int(r.reapers)
			+ ("  +%d silver" % Meta.FIRST_REAPER_SILVER if result.get("first_reaper", false) else ""), 10, UI.GOLD))
	if result.get("first_clear", false) and not r.get("nightmare", false):
		box.add_child(UI.label("NIGHTMARE unlocked on this map", 8, UI.RED))
	for l in rewards.get_children():
		if l is Label:
			_wrap(l)
	box = outer
	if rewards.get_child_count() > 0:
		var scroll := TouchScroll.new()
		scroll.add_child(rewards)
		# About 16px a line; at most what's left after the fixed rows.
		var room := get_viewport_rect().size.y - 230.0
		scroll.custom_minimum_size.y = clampf(rewards.get_child_count() * 16.0, 16.0, maxf(room, 48.0))
		box.add_child(scroll)
	var again := UI.button("PLAY AGAIN", func():
		get_tree().paused = false
		Net.leave()
		quit_to_menu.emit())
	box.add_child(again)
	again.call_deferred("grab_focus")

## Guests: the host left or the connection dropped.
func connection_lost(reason: String) -> void:
	if is_server():
		print("[server] room closed (%s), exiting" % reason)
		get_tree().quit()
		return
	if ended:
		return
	ended = true
	var box := _panel("DISCONNECTED", UI.RED)
	box.add_child(UI.body("The host left the game." if reason == "host" else "Lost the connection to the game.", 12))
	box.add_child(UI.button("OK", func():
		get_tree().paused = false
		quit_to_menu.emit()))
