extends Node
## Every piece of game content lives here as plain data. To add a weapon,
## passive, enemy, character or stage, add an entry below; the run code reads
## these tables and never hard-codes content.
##
## Numbers marked (orig) come straight from the Unity build's
## AbilityScriptableObjects: cooldown seconds, damage, and projectile speed in
## Unity units (x16 = pixels per second). Everything else is inferred and is
## meant to be cross-checked against the Plastic source later.

const UNIT := 16.0  # Unity pixels-per-unit, used to convert original speeds.

# Sprite sheets: horizontal strips, frame width = texture width / frames.
const SHEETS := {
	# Characters
	"run_joe": {"path": "run_joe", "frames": 4, "fps": 10},
	"run_matt": {"path": "run_matt", "frames": 4, "fps": 10},
	"run_alex": {"path": "run_alex", "frames": 4, "fps": 10},
	"run_jon": {"path": "run_jon", "frames": 4, "fps": 10},
	"idle_joe": {"path": "idle_joe", "frames": 6, "fps": 6},
	"idle_matt": {"path": "idle_matt", "frames": 6, "fps": 6},
	"idle_alex": {"path": "idle_alex", "frames": 6, "fps": 6},
	"idle_jon": {"path": "idle_jon", "frames": 5, "fps": 6},
	# Enemies
	"zombie": {"path": "zombie", "frames": 6, "fps": 8},
	"skull": {"path": "skull_enemy", "frames": 6, "fps": 10},
	"ghost": {"path": "ghost", "frames": 6, "fps": 8},
	"pumpkin": {"path": "pumpkin", "frames": 6, "fps": 10},
	"werewolf": {"path": "werewolf", "frames": 7, "fps": 12},
	"scarecrow": {"path": "scarecrow", "frames": 6, "fps": 6},
	"swampthing": {"path": "swampthing", "frames": 6, "fps": 6},
	"shadowbeast": {"path": "shadowbeast", "frames": 6, "fps": 8},
	# Weapon effects
	"fireball": {"path": "fireball", "frames": 7, "fps": 14},
	"fireball_explosion": {"path": "fireball_explosion", "frames": 7, "fps": 20},
	"lightning": {"path": "lightning", "frames": 9, "fps": 24},
	"boomerang": {"path": "boomerang", "frames": 4, "fps": 16},
	"bearclaw": {"path": "bearclaw", "frames": 11, "fps": 30},
	"crossbow_bolt": {"path": "crossbow_bolt", "frames": 1, "fps": 1},
	"cursed_sword": {"path": "cursed_sword", "frames": 6, "fps": 12},
	"acid_potion": {"path": "acid_potion", "frames": 4, "fps": 12},
	"acid_pool": {"path": "acid_pool", "frames": 6, "fps": 8},
	"bat": {"path": "bat", "frames": 4, "fps": 12},
	"wisp": {"path": "willOWisp", "frames": 6, "fps": 10},
	# Pickups
	"candy_corn": {"path": "candy_corn", "frames": 6, "fps": 8},
	"candy_bar": {"path": "candy_bar", "frames": 5, "fps": 8},
	"candy_bubblegum": {"path": "candy_bubblegum", "frames": 6, "fps": 8},
	"silver": {"path": "silver", "frames": 6, "fps": 10},
	"heart_pump": {"path": "heart_pump", "frames": 5, "fps": 8},
	# Animated passive icons (64x64 frames)
	"magic_tome": {"path": "magic_tome", "frames": 13, "fps": 10},
	"onion": {"path": "onion", "frames": 13, "fps": 10},
	"tentacle": {"path": "tentacle", "frames": 12, "fps": 10},
	"heartbeat": {"path": "heartbeat", "frames": 8, "fps": 10},
	"snail_lord": {"path": "snailLord", "frames": 13, "fps": 10},
	"vacusuck": {"path": "vacusuck", "frames": 5, "fps": 8},
	"holy_cross": {"path": "holy_cross", "frames": 10, "fps": 10},
	"merchant": {"path": "merchant_body", "frames": 5, "fps": 6},
	"street_lamp": {"path": "street_lamp", "frames": 4, "fps": 6},
}

# ---------------------------------------------------------------- Weapons
# Stats every weapon understands (missing = default below):
#   cooldown, damage, speed (px/s), amount, area (scale), duration (s),
#   pierce (-1 = infinite), knockback (px), range (px)
const WEAPON_DEFAULTS := {
	"cooldown": 1.0, "damage": 10.0, "speed": 160.0, "amount": 1, "area": 1.0,
	"duration": 1.0, "pierce": 1, "knockback": 40.0, "range": 160.0,
}

const MAX_WEAPONS := 6
const MAX_PASSIVES := 6

# `levels` holds the change applied at levels 2..N; add entries to add levels.
const WEAPONS := {
	"crossbow": {
		"name": "CrossBow", "quote": "IT'S HIGH NOOOON", "icon": "runic_crossbow_skill",
		"behavior": "shooter", "sheet": "crossbow_bolt", "aim": "facing", "rot_offset": PI / 4,
		"base": {"cooldown": 0.5, "damage": 5.0, "speed": 15.0 * UNIT, "pierce": 1, "range": 260.0},  # (orig) 0.5 / 5 / 15
		"levels": [
			{"desc": "Fire 1 more bolt", "amount": 1},
			{"desc": "+5 damage", "damage": 5.0},
			{"desc": "Bolts pierce 1 more", "pierce": 1},
			{"desc": "Fire 1 more bolt", "amount": 1},
			{"desc": "+5 damage", "damage": 5.0},
			{"desc": "Cooldown -20%", "cooldown_mul": 0.8},
			{"desc": "Fire 1 more bolt, pierce 1 more", "amount": 1, "pierce": 1},
		],
		"evolve": {"with": "tome_of_speed", "into": "gatling_crossbow"},
	},
	"fireball": {
		"name": "Fireball", "quote": "FLAMIN HOT", "icon": "fireball_icon",
		"behavior": "shooter", "sheet": "fireball", "aim": "nearest", "explode": 28.0,
		"base": {"cooldown": 2.0, "damage": 15.0, "speed": 20.0 * UNIT * 0.5, "pierce": 1, "range": 220.0},  # (orig) 2 / 15 / 20
		"levels": [
			{"desc": "+5 damage", "damage": 5.0},
			{"desc": "Throw 1 more fireball", "amount": 1},
			{"desc": "Bigger explosions", "area": 0.25},
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "Throw 1 more fireball", "amount": 1},
			{"desc": "Bigger explosions", "area": 0.25},
			{"desc": "+10 damage", "damage": 10.0},
		],
		"evolve": {"with": "attack_up", "into": "hellfire"},
	},
	"claw": {
		"name": "Claw", "quote": "RAWR xD", "icon": "owl_claw_skill",
		"behavior": "slash", "sheet": "bearclaw",
		"base": {"cooldown": 1.0, "damage": 25.0, "area": 1.0, "knockback": 60.0},  # (orig) 1 / 25
		"levels": [
			{"desc": "Also slash behind you", "amount": 1},
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "Bigger slashes", "area": 0.2},
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "Cooldown -15%", "cooldown_mul": 0.85},
			{"desc": "Bigger slashes", "area": 0.2},
			{"desc": "+15 damage", "damage": 15.0},
		],
		"evolve": {"with": "snail_king", "into": "bear_maul"},
	},
	"boomerang": {
		"name": "Boomerang", "quote": "OY MATE!!!", "icon": "boomerang_skill",
		"behavior": "boomerang", "sheet": "boomerang",
		"base": {"cooldown": 3.0, "damage": 10.0, "speed": 200.0, "pierce": -1, "range": 110.0},  # (orig) 3 / 10
		"levels": [
			{"desc": "Throw 1 more boomerang", "amount": 1},
			{"desc": "+5 damage", "damage": 5.0},
			{"desc": "Flies further", "range": 30.0},
			{"desc": "Throw 1 more boomerang", "amount": 1},
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "Cooldown -20%", "cooldown_mul": 0.8},
			{"desc": "Throw 1 more boomerang", "amount": 1},
		],
		"evolve": {"with": "vacuusuck", "into": "blood_moon"},
	},
	"lightning": {
		"name": "Lightning", "quote": "A shocking discovery", "icon": "lightning_skill",
		"behavior": "strike", "sheet": "lightning", "strike_radius": 22.0,
		"base": {"cooldown": 2.5, "damage": 15.0, "amount": 2},  # (orig) 2.5 / 15
		"levels": [
			{"desc": "1 more strike", "amount": 1},
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "Bigger strikes", "area": 0.25},
			{"desc": "1 more strike", "amount": 1},
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "Cooldown -20%", "cooldown_mul": 0.8},
			{"desc": "2 more strikes", "amount": 2},
		],
		"evolve": {"with": "experience_up", "into": "thunderstorm"},
	},
	"cursed_sword": {
		"name": "Cursed Sword", "quote": "BOOOOO!", "icon": "cursed_sword_skill",
		"behavior": "orbit", "sheet": "cursed_sword", "orbit_radius": 36.0, "rot_offset": PI / 4,
		"base": {"cooldown": 2.5, "damage": 10.0, "speed": 50.0, "duration": 2.5, "pierce": -1, "amount": 1},  # (orig) 2.5 / 10 / 50 (spin deg/s x ~5)
		"levels": [
			{"desc": "1 more sword", "amount": 1},
			{"desc": "+5 damage", "damage": 5.0},
			{"desc": "Spins for longer", "duration": 0.75},
			{"desc": "1 more sword", "amount": 1},
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "Bigger orbit", "area": 0.25},
			{"desc": "1 more sword", "amount": 1},
		],
		"evolve": {"with": "max_health", "into": "soul_eater"},
	},
	"acid": {
		"name": "Acid", "quote": "This tastes funny...", "icon": "potion_skill",
		"behavior": "flask", "sheet": "acid_potion", "pool_sheet": "acid_pool",
		"base": {"cooldown": 4.0, "damage": 3.0, "duration": 2.5, "area": 1.0, "range": 90.0},  # (orig) 4 / 3, "Throw 1 more flask"
		"tick": 0.35,
		"levels": [
			{"desc": "Throw 1 more flask", "amount": 1},
			{"desc": "+2 damage", "damage": 2.0},
			{"desc": "Throw 1 more flask", "amount": 1},
			{"desc": "Pools last longer", "duration": 1.0},
			{"desc": "+2 damage", "damage": 2.0},
			{"desc": "Bigger pools", "area": 0.3},
			{"desc": "Throw 1 more flask", "amount": 1},
		],
		"evolve": {"with": "health_regen", "into": "toxic_flood"},
	},
	"bat_swarm": {
		"name": "Bat Swarm", "quote": "JUSTICE!!!!!", "icon": "bat_skill",
		"behavior": "summon", "sheet": "bat",
		"base": {"cooldown": 5.0, "damage": 6.0, "speed": 150.0, "duration": 4.0, "amount": 2, "pierce": -1},  # (orig) 5 / 1 (damage is per bite)
		"bite": 0.4,
		"levels": [
			{"desc": "1 more bat", "amount": 1},
			{"desc": "+3 damage", "damage": 3.0},
			{"desc": "Bats stay longer", "duration": 1.5},
			{"desc": "1 more bat", "amount": 1},
			{"desc": "+3 damage", "damage": 3.0},
			{"desc": "Faster bats", "speed": 40.0},
			{"desc": "2 more bats", "amount": 2},
		],
		"evolve": {"with": "health_regen", "into": "vampire_swarm"},
	},
	"will_o_wisp": {
		"name": "Will-O-Wisp", "quote": "WILLY O WISPY", "icon": "wisp_skill",
		"behavior": "seeker", "sheet": "wisp",
		"base": {"cooldown": 4.0, "damage": 10.0, "speed": 90.0, "duration": 5.0, "amount": 1, "pierce": 3},  # (orig) 4 / 10
		"levels": [
			{"desc": "1 more wisp", "amount": 1},
			{"desc": "+5 damage", "damage": 5.0},
			{"desc": "Wisps burn through 2 more", "pierce": 2},
			{"desc": "1 more wisp", "amount": 1},
			{"desc": "+5 damage", "damage": 5.0},
			{"desc": "Faster wisps", "speed": 30.0},
			{"desc": "2 more wisps", "amount": 2},
		],
		"evolve": {"with": "tome_of_speed", "into": "ghost_lantern"},
	},

	# ---- Evolutions. Same behaviours, stronger base, tinted. Only "Gatling
	# Crossbow" is a confirmed original name; the rest are placeholders.
	"gatling_crossbow": {
		"name": "Gatling Crossbow", "quote": "IT'S HIGH NOOOOOOOOON", "icon": "runic_crossbow_skill",
		"evolution": true, "tint": Color(1.0, 0.75, 0.35),
		"behavior": "shooter", "sheet": "crossbow_bolt", "aim": "spin", "rot_offset": PI / 4,
		"base": {"cooldown": 0.12, "damage": 14.0, "speed": 300.0, "pierce": 3, "amount": 1, "range": 300.0},
	},
	"hellfire": {
		"name": "Hellfire", "quote": "FLAMIN HOTTER", "icon": "fireball_icon",
		"evolution": true, "tint": Color(0.6, 1.0, 0.5), "explode": 44.0,
		"behavior": "shooter", "sheet": "fireball", "aim": "nearest",
		"base": {"cooldown": 1.0, "damage": 45.0, "speed": 180.0, "pierce": 3, "amount": 3, "area": 1.5, "range": 260.0},
	},
	"bear_maul": {
		"name": "Bear Maul", "quote": "RAWR XD XD", "icon": "owl_claw_skill",
		"evolution": true, "tint": Color(1.0, 0.4, 0.4),
		"behavior": "slash", "sheet": "bearclaw",
		"base": {"cooldown": 0.6, "damage": 70.0, "area": 1.8, "amount": 4, "knockback": 90.0},
	},
	"blood_moon": {
		"name": "Blood Moon", "quote": "OY MATE, THAT'S A LOT", "icon": "boomerang_skill",
		"evolution": true, "tint": Color(1.0, 0.35, 0.4),
		"behavior": "boomerang", "sheet": "boomerang",
		"base": {"cooldown": 1.5, "damage": 35.0, "speed": 240.0, "pierce": -1, "amount": 6, "range": 150.0, "area": 1.5},
	},
	"thunderstorm": {
		"name": "Thunderstorm", "quote": "A shocking amount", "icon": "lightning_skill",
		"evolution": true, "tint": Color(0.7, 0.8, 1.0), "strike_radius": 30.0,
		"behavior": "strike", "sheet": "lightning",
		"base": {"cooldown": 1.0, "damage": 45.0, "amount": 8, "area": 1.4},
	},
	"soul_eater": {
		"name": "Soul Eater", "quote": "BOOOOOOOOO!", "icon": "cursed_sword_skill",
		"evolution": true, "tint": Color(0.75, 0.45, 1.0), "orbit_radius": 44.0, "lifesteal": 0.05,
		"behavior": "orbit", "sheet": "cursed_sword", "rot_offset": PI / 4,
		"base": {"cooldown": 0.2, "damage": 30.0, "speed": 70.0, "duration": 999.0, "pierce": -1, "amount": 5, "area": 1.3},
	},
	"toxic_flood": {
		"name": "Toxic Flood", "quote": "This tastes REALLY funny...", "icon": "potion_skill",
		"evolution": true, "tint": Color(0.7, 1.0, 0.2), "tick": 0.25,
		"behavior": "flask", "sheet": "acid_potion", "pool_sheet": "acid_pool",
		"base": {"cooldown": 3.0, "damage": 10.0, "duration": 5.0, "area": 1.8, "amount": 5, "range": 110.0},
	},
	"vampire_swarm": {
		"name": "Vampire Swarm", "quote": "JUSTICE, WITH TEETH", "icon": "bat_skill",
		"evolution": true, "tint": Color(1.0, 0.3, 0.35), "bite": 0.3, "lifesteal": 0.03,
		"behavior": "summon", "sheet": "bat",
		"base": {"cooldown": 3.0, "damage": 18.0, "speed": 210.0, "duration": 8.0, "amount": 10, "pierce": -1},
	},
	"ghost_lantern": {
		"name": "Ghost Lantern", "quote": "WILLY O WISPIEST", "icon": "wisp_skill",
		"evolution": true, "tint": Color(0.5, 1.0, 1.0),
		"behavior": "seeker", "sheet": "wisp",
		"base": {"cooldown": 1.5, "damage": 30.0, "speed": 150.0, "duration": 6.0, "amount": 6, "pierce": 8},
	},
}

# ---------------------------------------------------------------- Passives
# Each level adds `per_level` to the player's stats (see Player.STAT_DEFAULTS).
# Names/descriptions/quotes are (orig); icons are best guesses.
const PASSIVES := {
	"attack_up": {"name": "Attack Up", "desc": "Increases attack damage (10% increase)", "icon": "tentacle",
		"per_level": {"might": 0.10}, "max_level": 5},
	"tome_of_speed": {"name": "Tome Of Speed", "desc": "Cooldown reduction (10%)", "icon": "magic_tome",
		"per_level": {"cooldown": -0.08}, "max_level": 5},
	"snail_king": {"name": "Snail King", "desc": "Reduces incoming damage by 5%", "icon": "snail_lord",
		"per_level": {"armor": 0.05}, "max_level": 5},
	"experience_up": {"name": "Experience Up", "desc": "Increase experience gain (10%)", "icon": "onion",
		"per_level": {"growth": 0.10}, "max_level": 5},
	"health_regen": {"name": "Health Regen", "desc": "Increases health regen", "icon": "holy_cross",
		"per_level": {"regen": 0.4}, "max_level": 5},
	"max_health": {"name": "Max Health", "desc": "Increase maximum Health by 15%", "quote": "I LOVED HER!!!!", "icon": "heartbeat",
		"per_level": {"max_hp_mul": 0.15}, "max_level": 5},
	"vacuusuck": {"name": "VacuuSuck", "desc": "Pull candy from further away", "quote": "Hear me out...", "icon": "vacusuck",
		"per_level": {"magnet": 0.35}, "max_level": 5},
}

# Offered when everything is maxed ("repeatable elixirs" in the original).
const ELIXIRS := {
	"elixir_heal": {"name": "Heart", "desc": "Heal 30 health", "icon": "heart", "heal": 30.0},
	"elixir_silver": {"name": "Silver Stash", "desc": "+25 silver", "icon": "silver", "silver": 25},
}

# ---------------------------------------------------------------- Characters
# Starting weapons match the moves each hero starts with in Mystery Crypt.
const CHARACTERS := {
	"joe": {"name": "Joe", "perk": "All-rounder. +10% damage.", "run": "run_joe", "idle": "idle_joe",
		"weapon": "claw", "stats": {"might": 0.10}, "cost": 0},
	"matt": {"name": "Matt", "perk": "Tough. +30 max health.", "run": "run_matt", "idle": "idle_matt",
		"weapon": "cursed_sword", "stats": {"max_hp": 30.0}, "cost": 150},
	"alex": {"name": "Alex", "perk": "Ranged. Projectiles fly 20% faster.", "run": "run_alex", "idle": "idle_alex",
		"weapon": "crossbow", "stats": {"proj_speed": 0.2}, "cost": 300},
	"jon": {"name": "Jon", "perk": "Lucky. More candy, more silver.", "run": "run_jon", "idle": "idle_jon",
		"weapon": "will_o_wisp", "stats": {"growth": 0.15, "greed": 0.25}, "cost": 500},
}

# ---------------------------------------------------------------- Enemies
# hp/damage are at minute 0; the stage multiplies hp as time passes.
# `faces` is the direction the art faces so it can be flipped to face the player.
const ENEMIES := {
	"zombie": {"sheet": "zombie", "hp": 10.0, "speed": 26.0, "damage": 8.0, "radius": 6.0, "candy": 0, "faces": 1},
	"skull": {"sheet": "skull", "hp": 6.0, "speed": 48.0, "damage": 6.0, "radius": 6.0, "candy": 0, "faces": 1, "fly": true},
	"pumpkin": {"sheet": "pumpkin", "hp": 18.0, "speed": 30.0, "damage": 10.0, "radius": 6.0, "candy": 0, "faces": 1},
	"ghost": {"sheet": "ghost", "hp": 22.0, "speed": 34.0, "damage": 10.0, "radius": 6.0, "candy": 1, "faces": 1, "fly": true, "alpha": 0.8},
	"scarecrow": {"sheet": "scarecrow", "hp": 60.0, "speed": 24.0, "damage": 14.0, "radius": 8.0, "candy": 1, "faces": 1},
	"werewolf": {"sheet": "werewolf", "hp": 45.0, "speed": 58.0, "damage": 14.0, "radius": 9.0, "candy": 1, "faces": 1},
	"shadowbeast": {"sheet": "shadowbeast", "hp": 90.0, "speed": 40.0, "damage": 18.0, "radius": 10.0, "candy": 1, "faces": 1},
	"swampthing": {"sheet": "swampthing", "hp": 160.0, "speed": 28.0, "damage": 22.0, "radius": 12.0, "candy": 2, "faces": 1},
}

# Candy is the experience pickup (the run reports "candyCollected").
const CANDY := [
	{"sheet": "candy_corn", "xp": 1.0},
	{"sheet": "candy_bar", "xp": 5.0},
	{"sheet": "candy_bubblegum", "xp": 20.0},
]

# ---------------------------------------------------------------- Stages
# spawns: while from <= minute < to, keep spawning `enemy` at `rate`/s.
# events: one-shot at `at` minutes: "ring" circles the player, "boss" spawns
# a big version that drops a chest.
const STAGES := {
	"graveyard": {
		"name": "The Graveyard", "ground": "gamebg", "hp_per_minute": 0.35, "max_alive": 320,
		"obstacles": ["grave_1_small", "grave_2", "tree", "tree_2", "tree_3", "tree_4", "tree_5", "tree_6", "street_lamp", "mausoleum"],
		"spawns": [
			{"enemy": "zombie", "from": 0.0, "to": 3.0, "rate": 0.6},
			{"enemy": "skull", "from": 0.75, "to": 5.0, "rate": 0.4},
			{"enemy": "pumpkin", "from": 1.5, "to": 7.0, "rate": 0.5},
			{"enemy": "zombie", "from": 3.0, "to": 30.0, "rate": 1.0},
			{"enemy": "ghost", "from": 3.0, "to": 10.0, "rate": 0.6},
			{"enemy": "scarecrow", "from": 5.0, "to": 12.0, "rate": 0.35},
			{"enemy": "werewolf", "from": 7.0, "to": 30.0, "rate": 0.6},
			{"enemy": "skull", "from": 8.0, "to": 30.0, "rate": 1.2},
			{"enemy": "shadowbeast", "from": 10.0, "to": 30.0, "rate": 0.5},
			{"enemy": "ghost", "from": 12.0, "to": 30.0, "rate": 1.0},
			{"enemy": "swampthing", "from": 14.0, "to": 30.0, "rate": 0.3},
		],
		"events": [
			{"at": 2.0, "type": "ring", "enemy": "skull", "count": 16},
			{"at": 4.0, "type": "boss", "enemy": "scarecrow"},
			{"at": 6.0, "type": "ring", "enemy": "pumpkin", "count": 30},
			{"at": 8.0, "type": "boss", "enemy": "werewolf"},
			{"at": 10.0, "type": "ring", "enemy": "ghost", "count": 36},
			{"at": 12.0, "type": "boss", "enemy": "shadowbeast"},
			{"at": 15.0, "type": "boss", "enemy": "swampthing"},
			{"at": 18.0, "type": "ring", "enemy": "werewolf", "count": 40},
			{"at": 20.0, "type": "boss", "enemy": "swampthing"},
		],
	},
}

# ---------------------------------------------------------------- Helpers
var _tex_cache := {}
var _sheet_cache := {}

func tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		_tex_cache[name] = load("res://assets/sprites/%s.png" % name)
	return _tex_cache[name]

## A sheet entry plus its texture (_tex) and frame size (_w, _h).
func sheet(id: String) -> Dictionary:
	if not _sheet_cache.has(id):
		var s: Dictionary = SHEETS[id].duplicate()
		var t := tex(s.path)
		s["_tex"] = t
		s["_w"] = t.get_width() / int(s.frames)
		s["_h"] = t.get_height()
		_sheet_cache[id] = s
	return _sheet_cache[id]

## Source rect for a frame of a sheet at time `t` (seconds).
func frame_rect(s: Dictionary, t: float) -> Rect2:
	var f := int(t * float(s.fps)) % int(s.frames)
	return Rect2(f * s._w, 0, s._w, s._h)

var _icon_cache := {}

func icon_texture(id: String) -> Texture2D:
	# Animated 64x64 sheets become their first frame; plain icons load directly.
	if not SHEETS.has(id):
		return tex(id)
	if not _icon_cache.has(id):
		var s := sheet(id)
		var a := AtlasTexture.new()
		a.atlas = s._tex
		a.region = Rect2(0, 0, s._w, s._h)
		_icon_cache[id] = a
	return _icon_cache[id]

func upgrade_def(id: String) -> Dictionary:
	if WEAPONS.has(id): return WEAPONS[id]
	if PASSIVES.has(id): return PASSIVES[id]
	return ELIXIRS.get(id, {})

func weapon_max_level(id: String) -> int:
	return WEAPONS[id].get("levels", []).size() + 1
