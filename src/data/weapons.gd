extends RefCounted
## Weapons, their evolutions and unions.
##
## Stats every weapon understands (missing = WEAPON_DEFAULTS):
##   cooldown, damage, speed (px/s), amount, area (scale), duration (s),
##   pierce (-1 = infinite), knockback (px), range (px)
## `levels` is the change at levels 2..N (add entries to add levels).
## `evolve` = {with: passive, into: weapon}: max level + that passive, then a chest.
## `union`  = {with: weapon, into: weapon}: both at max level, then a chest. The
##   two weapons become one, freeing a slot.
## `locked` weapons stay out of the level-up pool until a feat unlocks them.
## Numbers marked (orig) are from the Unity build; the rest are first-pass tuning.
##
## Behaviours (see Weapon.fire and Shots):
##   shooter   projectiles; aim = facing | nearest | auto (nearest, else facing) | spin,
##             spread (rad between shots)
##   slash     whip-style horizontal lashes on the side you last faced; more
##             amount adds the other side, then rows above and below
##   boomerang out and back, hits on both legs
##   strike    instant hit at enemies; target = random | nearest, warn = seconds of crosshair first
##   orbit     circles the hero for `duration` (speed = spin); `upright` keeps the
##             sprite unrotated. A level-up that changes the count re-forms the circle.
##   flask     lobbed; lands as a pool (pool_sheet) or explodes (explode)
##   summon    bats that hunt for `duration`; extra_wisps adds seekers too
##   seeker    homing shots that burn through `pierce` enemies
##   aura      a permanent damaging ring around the hero
##   nova      an expanding ring from the hero; heal = hp per pulse, smite = also hit the screen
##   smite     hits everything on screen
##   bounce    ricochets off the screen edges for `duration`; `retarget` thrown at
##             the nearest enemy and turns toward the nearest one on every bounce
##   chain     jumps from enemy to enemy, `amount` jumps
##   trail     leaves damaging pools behind while you move
##   turret    plants lamps that zap the nearest enemy

const WEAPON_DEFAULTS := {
	"cooldown": 1.0, "damage": 10.0, "speed": 160.0, "amount": 1, "area": 1.0,
	"duration": 1.0, "pierce": 1, "knockback": 40.0, "range": 160.0,
}

const UNIT := 16.0  # Unity pixels-per-unit, to convert original speeds

const WEAPONS := {
	# ================================================================ Original nine
	"crossbow": {
		"name": "CrossBow", "quote": "IT'S HIGH NOOOON", "icon": "runic_crossbow_skill",
		"behavior": "shooter", "sheet": "crossbow_bolt", "aim": "auto", "rot_offset": PI / 4,
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
		"behavior": "shooter", "sheet": "fireball", "aim": "facing", "explode": 28.0,  # fires where you're heading
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
		"union": {"with": "lightning", "into": "plasma_storm"},
	},
	"claw": {
		"name": "Claw", "quote": "RAWR xD", "icon": "owl_claw_skill",
		"behavior": "slash", "sheet": "bearclaw",  # whip-style: horizontal lashes
		"base": {"cooldown": 1.0, "damage": 25.0, "area": 1.0, "knockback": 60.0},  # (orig) 1 / 25
		"levels": [
			{"desc": "Also slashes the other side", "amount": 1},
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "Longer slashes", "area": 0.15},
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "Cooldown -15%", "cooldown_mul": 0.85},
			{"desc": "Longer slashes", "area": 0.15},
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
		"union": {"with": "silver_coin", "into": "ricochet_royale"},
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
		"behavior": "bounce", "sheet": "cursed_sword", "retarget": true, "rot_offset": PI / 4,
		"base": {"cooldown": 3.0, "damage": 10.0, "speed": 200.0, "duration": 2.5, "pierce": -1, "amount": 1},  # (orig) 2.5 / 10
		"levels": [
			{"desc": "1 more sword", "amount": 1},
			{"desc": "+5 damage", "damage": 5.0},
			{"desc": "Swords fly for longer", "duration": 1.0},
			{"desc": "1 more sword", "amount": 1},
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "Bigger, faster swords", "area": 0.25, "speed": 40.0},
			{"desc": "1 more sword", "amount": 1},
		],
		"evolve": {"with": "max_health", "into": "soul_eater"},
	},
	"acid": {
		"name": "Acid", "quote": "This tastes funny...", "icon": "potion_skill",
		"behavior": "flask", "sheet": "acid_potion", "pool_sheet": "acid_pool", "tick": 0.35,
		"base": {"cooldown": 4.0, "damage": 3.0, "duration": 2.5, "area": 1.0, "range": 90.0},  # (orig) 4 / 3
		"levels": [
			{"desc": "Throw 1 more flask", "amount": 1},  # (orig) "Throw 1 more flask"
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
		"behavior": "summon", "sheet": "bat", "bite": 0.4,
		"base": {"cooldown": 5.0, "damage": 6.0, "speed": 150.0, "duration": 4.0, "amount": 2, "pierce": -1},  # (orig) 5 / 1
		"levels": [
			{"desc": "1 more bat", "amount": 1},
			{"desc": "+3 damage", "damage": 3.0},
			{"desc": "Bats stay longer", "duration": 1.5},
			{"desc": "1 more bat", "amount": 1},
			{"desc": "+3 damage", "damage": 3.0},
			{"desc": "Faster bats", "speed": 40.0},
			{"desc": "2 more bats", "amount": 2},
		],
		"evolve": {"with": "heart_locket", "into": "vampire_swarm"},
		"union": {"with": "will_o_wisp", "into": "night_parade"},
	},
	"will_o_wisp": {
		"name": "Will-O-Wisp", "quote": "WILLY O WISPY", "icon": "wisp_skill",
		"behavior": "orbit", "sheet": "wisp", "orbit_radius": 30.0, "shot_scale": 0.5, "upright": true,
		# speed is the spin, in quarter-degrees per second (see Shots.step)
		"base": {"cooldown": 0.5, "damage": 10.0, "speed": 45.0, "duration": 999.0, "amount": 2, "pierce": -1},  # (orig) 10 damage
		"levels": [
			{"desc": "1 more wisp", "amount": 1},
			{"desc": "+5 damage", "damage": 5.0},
			{"desc": "Wisps spin faster", "speed": 15.0},
			{"desc": "1 more wisp", "amount": 1},
			{"desc": "+5 damage", "damage": 5.0},
			{"desc": "Faster, wider circle", "speed": 15.0, "area": 0.25},
			{"desc": "2 more wisps", "amount": 2},
		],
		"evolve": {"with": "pocket_watch", "into": "ghost_lantern"},
	},

	# ================================================================ New weapons
	"onion_ring": {
		"name": "Onion Ring", "quote": "Smells like victory.", "icon": "onion_ring_skill",
		"behavior": "aura", "color": Color(0.85, 0.55, 0.95), "tick": 0.5,
		"base": {"damage": 4.0, "area": 1.0, "knockback": 10.0, "range": 26.0},
		"levels": [
			{"desc": "Bigger ring", "area": 0.2},
			{"desc": "+2 damage", "damage": 2.0},
			{"desc": "Hits faster", "cooldown_mul": 0.85},
			{"desc": "Bigger ring", "area": 0.2},
			{"desc": "+2 damage", "damage": 2.0},
			{"desc": "Bigger ring", "area": 0.2},
			{"desc": "+3 damage", "damage": 3.0},
		],
		"evolve": {"with": "snail_king", "into": "thriller_aura"},
	},
	"heartbeat": {
		"name": "Heartbeat", "quote": "I LOVED HER!!!!", "icon": "heartbeat_skill",
		"behavior": "nova", "color": Color(1.0, 0.35, 0.4), "heal": 1.0,
		"base": {"cooldown": 3.0, "damage": 12.0, "range": 70.0, "knockback": 50.0, "pierce": -1},
		"levels": [
			{"desc": "+6 damage", "damage": 6.0},
			{"desc": "Wider pulse", "range": 15.0},
			{"desc": "Cooldown -15%", "cooldown_mul": 0.85},
			{"desc": "+6 damage", "damage": 6.0},
			{"desc": "Wider pulse", "range": 15.0},
			{"desc": "Cooldown -15%", "cooldown_mul": 0.85},
			{"desc": "+10 damage", "damage": 10.0},
		],
		"evolve": {"with": "health_regen", "into": "tell_tale_heart"},
		"union": {"with": "holy_cross", "into": "sacred_heart"},
	},
	"holy_cross": {
		"name": "Holy Cross", "quote": "Have you ever heard of Jumanji?", "icon": "holy_cross_skill",
		"behavior": "smite", "sheet": "holy_cross",
		"base": {"cooldown": 8.0, "damage": 10.0},
		"levels": [
			{"desc": "+5 damage", "damage": 5.0},
			{"desc": "Cooldown -10%", "cooldown_mul": 0.9},
			{"desc": "+5 damage", "damage": 5.0},
			{"desc": "Cooldown -10%", "cooldown_mul": 0.9},
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "Cooldown -15%", "cooldown_mul": 0.85},
			{"desc": "+10 damage", "damage": 10.0},
		],
		"evolve": {"with": "attack_up", "into": "divine_judgment"},
	},
	"candy_shotgun": {
		"name": "Candy Corn Shotgun", "quote": "Trick AND treat.", "icon": "candy_shotgun_skill",
		"behavior": "shooter", "sheet": "candy_shot", "aim": "nearest", "spread": 0.22,
		"base": {"cooldown": 1.6, "damage": 6.0, "speed": 220.0, "amount": 3, "pierce": 1, "range": 130.0},
		"levels": [
			{"desc": "1 more candy", "amount": 1},
			{"desc": "+3 damage", "damage": 3.0},
			{"desc": "1 more candy", "amount": 1},
			{"desc": "Cooldown -15%", "cooldown_mul": 0.85},
			{"desc": "+3 damage", "damage": 3.0},
			{"desc": "Candy pierces 1 more", "pierce": 1},
			{"desc": "2 more candies", "amount": 2},
		],
		"evolve": {"with": "candy_basket", "into": "sugar_rush"},
	},
	"pumpkin_bomb": {
		"name": "Pumpkin Bomb", "quote": "Gourd-geous explosions.", "icon": "pumpkin_bomb_skill", "locked": true,
		"behavior": "flask", "sheet": "pumpkin", "explode": 30.0,
		"base": {"cooldown": 3.0, "damage": 25.0, "range": 110.0},
		"levels": [
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "1 more bomb", "amount": 1},
			{"desc": "Bigger blasts", "area": 0.2},
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "1 more bomb", "amount": 1},
			{"desc": "Cooldown -20%", "cooldown_mul": 0.8},
			{"desc": "Bigger blasts", "area": 0.3},
		],
		"evolve": {"with": "grave_dirt", "into": "jacks_inferno"},
	},
	"silver_coin": {
		"name": "Silver Coin", "quote": "Heads you lose.", "icon": "silver_coin_skill", "locked": true,
		"behavior": "bounce", "sheet": "coin_spin", "upright": true,
		"base": {"cooldown": 4.0, "damage": 8.0, "speed": 170.0, "duration": 3.0, "pierce": -1},
		"levels": [
			{"desc": "1 more coin", "amount": 1},
			{"desc": "+4 damage", "damage": 4.0},
			{"desc": "Coins last longer", "duration": 1.0},
			{"desc": "1 more coin", "amount": 1},
			{"desc": "+4 damage", "damage": 4.0},
			{"desc": "Faster coins", "speed": 40.0},
			{"desc": "1 more coin", "amount": 1},
		],
		"evolve": {"with": "lucky_trophy", "into": "jackpot"},
	},
	"skull_toss": {
		"name": "Skull Toss", "quote": "Alas, poor Yorick.", "icon": "skull_toss_skill", "locked": true,
		"behavior": "seeker", "sheet": "flame_skull",
		"base": {"cooldown": 2.0, "damage": 14.0, "speed": 130.0, "duration": 3.0, "pierce": 1},
		"levels": [
			{"desc": "1 more skull", "amount": 1},
			{"desc": "+6 damage", "damage": 6.0},
			{"desc": "Skulls hit 1 more", "pierce": 1},
			{"desc": "1 more skull", "amount": 1},
			{"desc": "+6 damage", "damage": 6.0},
			{"desc": "Cooldown -20%", "cooldown_mul": 0.8},
			{"desc": "2 more skulls", "amount": 2},
		],
		"evolve": {"with": "skull_ring", "into": "skull_storm"},
	},
	"grave_hand": {
		"name": "Grave Hand", "quote": "Somebody needs a hand.", "icon": "grave_hand_skill", "locked": true,
		"behavior": "strike", "sheet": "hand", "target": "random", "strike_radius": 18.0, "sheet_scale": 0.25,
		"base": {"cooldown": 2.2, "damage": 18.0, "amount": 2, "knockback": 0.0},
		"levels": [
			{"desc": "1 more hand", "amount": 1},
			{"desc": "+8 damage", "damage": 8.0},
			{"desc": "1 more hand", "amount": 1},
			{"desc": "Bigger grabs", "area": 0.25},
			{"desc": "+8 damage", "damage": 8.0},
			{"desc": "Cooldown -20%", "cooldown_mul": 0.8},
			{"desc": "2 more hands", "amount": 2},
		],
		"evolve": {"with": "heart_locket", "into": "necromancers_grip"},
	},
	"tentacle": {
		"name": "Tentacle", "quote": "Don't ask where it comes from.", "icon": "tentacle_skill", "locked": true,
		"behavior": "strike", "sheet": "tentacle", "target": "nearest", "strike_radius": 26.0, "sheet_scale": 0.5,
		"base": {"cooldown": 1.8, "damage": 30.0, "amount": 1, "knockback": 80.0},
		"levels": [
			{"desc": "+12 damage", "damage": 12.0},
			{"desc": "1 more tentacle", "amount": 1},
			{"desc": "Bigger slams", "area": 0.2},
			{"desc": "+12 damage", "damage": 12.0},
			{"desc": "1 more tentacle", "amount": 1},
			{"desc": "Cooldown -20%", "cooldown_mul": 0.8},
			{"desc": "+20 damage", "damage": 20.0},
		],
		"evolve": {"with": "skull_ring", "into": "eldritch_horror"},
	},
	"chain_lightning": {
		"name": "Chain Lightning", "quote": "It's electric!", "icon": "chain_lightning_skill", "locked": true,
		"behavior": "chain", "color": Color(0.6, 0.85, 1.0),
		"base": {"cooldown": 2.0, "damage": 12.0, "amount": 3, "range": 140.0},
		"levels": [
			{"desc": "Jumps 1 more", "amount": 1},
			{"desc": "+6 damage", "damage": 6.0},
			{"desc": "Jumps 1 more", "amount": 1},
			{"desc": "Cooldown -15%", "cooldown_mul": 0.85},
			{"desc": "+6 damage", "damage": 6.0},
			{"desc": "Jumps 2 more", "amount": 2},
			{"desc": "+10 damage", "damage": 10.0},
		],
		"evolve": {"with": "tome_of_speed", "into": "arc_reactor"},
	},
	"blood_trail": {
		"name": "Blood Trail", "quote": "Leave a mark.", "icon": "blood_trail_skill", "locked": true,
		"behavior": "trail", "sheet": "blood_drop", "tick": 0.4,
		"base": {"cooldown": 0.3, "damage": 5.0, "duration": 2.0, "area": 1.0},
		"levels": [
			{"desc": "+3 damage", "damage": 3.0},
			{"desc": "Pools last longer", "duration": 0.75},
			{"desc": "Bigger pools", "area": 0.25},
			{"desc": "+3 damage", "damage": 3.0},
			{"desc": "Pools last longer", "duration": 0.75},
			{"desc": "Bigger pools", "area": 0.25},
			{"desc": "+5 damage", "damage": 5.0},
		],
		"evolve": {"with": "ghost_step", "into": "river_of_blood"},
	},
	"street_lamp": {
		"name": "Street Lamp", "quote": "Light 'em up.", "icon": "street_lamp_skill", "locked": true,
		"behavior": "turret", "sheet": "street_lamp", "zap": 0.6,
		"base": {"cooldown": 6.0, "damage": 10.0, "duration": 8.0, "amount": 1, "range": 80.0},
		"levels": [
			{"desc": "1 more lamp", "amount": 1},
			{"desc": "+5 damage", "damage": 5.0},
			{"desc": "Lamps last longer", "duration": 3.0},
			{"desc": "Longer reach", "range": 20.0},
			{"desc": "1 more lamp", "amount": 1},
			{"desc": "+8 damage", "damage": 8.0},
			{"desc": "1 more lamp", "amount": 1},
		],
		"evolve": {"with": "duplicator", "into": "haunted_boulevard"},
	},
	"wood_stake": {
		"name": "Wood Stake", "quote": "Straight to the heart.", "icon": "wood_stake_skill", "locked": true,
		"behavior": "shooter", "sheet": "wood_stake", "aim": "facing", "rot_offset": PI / 2,
		"base": {"cooldown": 1.2, "damage": 20.0, "speed": 300.0, "pierce": 3, "range": 300.0, "knockback": 70.0},
		"levels": [
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "Pierces 2 more", "pierce": 2},
			{"desc": "1 more stake", "amount": 1},
			{"desc": "+10 damage", "damage": 10.0},
			{"desc": "Cooldown -20%", "cooldown_mul": 0.8},
			{"desc": "1 more stake", "amount": 1},
			{"desc": "+15 damage", "damage": 15.0},
		],
		"evolve": {"with": "scope", "into": "van_helsing"},
	},
	"airstrike": {
		"name": "Airstrike", "quote": "Incoming!", "icon": "airstrike_skill", "locked": true,
		"behavior": "strike", "sheet": "fireball_explosion", "target": "random", "warn": 0.7,
		"strike_radius": 30.0, "sheet_scale": 2.0, "centered": true,
		"base": {"cooldown": 4.0, "damage": 40.0, "amount": 1, "knockback": 60.0},
		"levels": [
			{"desc": "1 more strike", "amount": 1},
			{"desc": "+15 damage", "damage": 15.0},
			{"desc": "Bigger blasts", "area": 0.2},
			{"desc": "1 more strike", "amount": 1},
			{"desc": "+15 damage", "damage": 15.0},
			{"desc": "Cooldown -20%", "cooldown_mul": 0.8},
			{"desc": "2 more strikes", "amount": 2},
		],
		"evolve": {"with": "grave_dirt", "into": "carpet_bombing"},
	},
	"merchant_hat": {
		"name": "Merchant's Hat", "quote": "Business is booming.", "icon": "merchant_hat_skill", "locked": true,
		"behavior": "orbit", "sheet": "merchant_hat", "orbit_radius": 44.0, "shot_scale": 0.25,
		"base": {"cooldown": 3.0, "damage": 8.0, "speed": 70.0, "duration": 3.0, "pierce": -1, "amount": 2},
		"levels": [
			{"desc": "1 more hat", "amount": 1},
			{"desc": "+4 damage", "damage": 4.0},
			{"desc": "Spins for longer", "duration": 1.0},
			{"desc": "1 more hat", "amount": 1},
			{"desc": "+4 damage", "damage": 4.0},
			{"desc": "Wider orbit", "area": 0.25},
			{"desc": "2 more hats", "amount": 2},
		],
		"evolve": {"with": "candy_basket", "into": "top_hat_tornado"},
	},

	# ================================================================ Evolutions
	# Same behaviours, stronger base, tinted. Only "Gatling Crossbow" is a
	# confirmed original name; the rest are placeholders.
	"gatling_crossbow": {"name": "Gatling Crossbow", "quote": "IT'S HIGH NOOOOOOOOON", "icon": "gatling_crossbow_skill",
		"evolution": true, "behavior": "shooter", "sheet": "gatling_bolt", "aim": "spin", "rot_offset": PI / 4,
		"base": {"cooldown": 0.12, "damage": 14.0, "speed": 300.0, "pierce": 3, "amount": 1, "range": 300.0}},
	"hellfire": {"name": "Hellfire", "quote": "FLAMIN HOTTER", "icon": "hellfire_skill",
		"evolution": true, "explode": 44.0, "behavior": "shooter", "sheet": "hellfire_shot", "aim": "facing",
		"base": {"cooldown": 1.0, "damage": 45.0, "speed": 180.0, "pierce": 3, "amount": 3, "area": 1.5, "range": 260.0}},
	"bear_maul": {"name": "Bear Maul", "quote": "RAWR XD XD", "icon": "bear_maul_skill",
		"evolution": true, "tint": Color(1.0, 0.4, 0.4), "behavior": "slash", "sheet": "bearclaw",
		"base": {"cooldown": 0.6, "damage": 70.0, "area": 1.5, "amount": 4, "knockback": 90.0}},
	"blood_moon": {"name": "Blood Moon", "quote": "OY MATE, THAT'S A LOT", "icon": "blood_moon_skill",
		"evolution": true, "behavior": "boomerang", "sheet": "blood_moon_shot",
		"base": {"cooldown": 1.5, "damage": 35.0, "speed": 240.0, "pierce": -1, "amount": 6, "range": 150.0, "area": 1.5}},
	"thunderstorm": {"name": "Thunderstorm", "quote": "A shocking amount", "icon": "thunderstorm_skill",
		"evolution": true, "tint": Color(0.7, 0.8, 1.0), "strike_radius": 30.0, "behavior": "strike", "sheet": "lightning",
		"base": {"cooldown": 1.0, "damage": 45.0, "amount": 8, "area": 1.4}},
	"soul_eater": {"name": "Soul Eater", "quote": "BOOOOOOOOO!", "icon": "soul_eater_skill",
		"evolution": true, "lifesteal": 0.05, "behavior": "bounce", "sheet": "soul_eater_shot", "retarget": true, "rot_offset": PI / 4,
		"base": {"cooldown": 2.0, "damage": 30.0, "speed": 280.0, "duration": 4.0, "pierce": -1, "amount": 5, "area": 1.3}},
	"toxic_flood": {"name": "Toxic Flood", "quote": "This tastes REALLY funny...", "icon": "toxic_flood_skill",
		"evolution": true, "tint": Color(0.7, 1.0, 0.2), "tick": 0.25, "behavior": "flask", "sheet": "toxic_barrel", "pool_sheet": "acid_pool",
		"base": {"cooldown": 3.0, "damage": 10.0, "duration": 5.0, "area": 1.8, "amount": 5, "range": 110.0}},
	"vampire_swarm": {"name": "Vampire Swarm", "quote": "JUSTICE, WITH TEETH", "icon": "vampire_swarm_skill",
		"evolution": true, "bite": 0.3, "lifesteal": 0.03, "behavior": "summon", "sheet": "vampire_bat",
		"base": {"cooldown": 3.0, "damage": 18.0, "speed": 210.0, "duration": 8.0, "amount": 10, "pierce": -1}},
	"ghost_lantern": {"name": "Ghost Lantern", "quote": "WILLY O WISPIEST", "icon": "ghost_lantern_skill",
		"evolution": true, "behavior": "orbit", "sheet": "ghost_lantern_orb", "orbit_radius": 40.0, "shot_scale": 1.0, "upright": true,
		"base": {"cooldown": 0.5, "damage": 30.0, "speed": 85.0, "duration": 999.0, "amount": 7, "pierce": -1, "area": 1.2}},
	"thriller_aura": {"name": "Thriller Aura", "quote": "The funk of forty thousand years.", "icon": "thriller_aura_skill",
		"evolution": true, "tint": Color(0.6, 1.0, 0.6), "behavior": "aura", "color": Color(0.5, 1.0, 0.5), "tick": 0.3,
		"base": {"damage": 14.0, "area": 2.0, "knockback": 25.0, "range": 26.0}},
	"tell_tale_heart": {"name": "Tell-Tale Heart", "quote": "Louder! Louder!", "icon": "tell_tale_heart_skill",
		"evolution": true, "tint": Color(1.0, 0.6, 0.6), "behavior": "nova", "color": Color(1.0, 0.2, 0.3), "heal": 4.0,
		"base": {"cooldown": 1.5, "damage": 40.0, "range": 130.0, "knockback": 70.0, "pierce": -1}},
	"divine_judgment": {"name": "Divine Judgment", "quote": "Jumanji was just the beginning.", "icon": "divine_judgment_skill",
		"evolution": true, "tint": Color(1.0, 0.95, 0.6), "behavior": "smite", "sheet": "holy_cross",
		"base": {"cooldown": 3.0, "damage": 50.0}},
	"sugar_rush": {"name": "Sugar Rush", "quote": "TRICK AND TREAT AND TRICK", "icon": "sugar_rush_skill",
		"evolution": true, "behavior": "shooter", "sheet": "lollipop", "aim": "spin",
		"base": {"cooldown": 0.25, "damage": 16.0, "speed": 260.0, "amount": 3, "pierce": 3, "range": 200.0}},
	"jacks_inferno": {"name": "Jack's Inferno", "quote": "Gourd almighty.", "icon": "jacks_inferno_skill",
		"evolution": true, "behavior": "flask", "sheet": "jack_flame", "explode": 50.0,
		"base": {"cooldown": 1.2, "damage": 70.0, "amount": 4, "range": 140.0, "area": 1.4}},
	"jackpot": {"name": "Jackpot", "quote": "The house always wins.", "icon": "jackpot_skill",
		"evolution": true, "behavior": "bounce", "sheet": "gold_coin_spin", "upright": true, "drops_silver": 0.05,
		"base": {"cooldown": 2.0, "damage": 30.0, "speed": 230.0, "duration": 5.0, "pierce": -1, "amount": 6, "area": 1.4}},
	"skull_storm": {"name": "Skull Storm", "quote": "Alas, poor everybody.", "icon": "skull_storm_skill",
		"evolution": true, "behavior": "seeker", "sheet": "storm_skull",
		"base": {"cooldown": 0.8, "damage": 40.0, "speed": 180.0, "duration": 4.0, "pierce": 4, "amount": 6, "area": 1.3}},
	"necromancers_grip": {"name": "Necromancer's Grip", "quote": "Everybody needs a hand.", "icon": "necromancers_grip_skill",
		"evolution": true, "tint": Color(0.6, 1.0, 0.7), "behavior": "strike", "sheet": "hand", "target": "random", "strike_radius": 26.0, "sheet_scale": 0.5,
		"base": {"cooldown": 1.0, "damage": 50.0, "amount": 6, "knockback": 0.0}},
	"eldritch_horror": {"name": "Eldritch Horror", "quote": "It asked where YOU came from.", "icon": "eldritch_horror_skill",
		"evolution": true, "tint": Color(0.7, 0.5, 1.0), "behavior": "strike", "sheet": "tentacle", "target": "random", "strike_radius": 36.0, "sheet_scale": 1.0,
		"base": {"cooldown": 1.0, "damage": 90.0, "amount": 4, "knockback": 100.0}},
	"arc_reactor": {"name": "Arc Reactor", "quote": "It's VERY electric!", "icon": "arc_reactor_skill",
		"evolution": true, "tint": Color(0.5, 0.7, 1.0), "behavior": "chain", "color": Color(0.8, 0.95, 1.0),
		"base": {"cooldown": 0.8, "damage": 35.0, "amount": 10, "range": 180.0}},
	"river_of_blood": {"name": "River of Blood", "quote": "Leave a LOT of marks.", "icon": "river_of_blood_skill",
		"evolution": true, "tint": Color(1.0, 0.4, 0.4), "behavior": "trail", "sheet": "blood_drop", "tick": 0.25, "lifesteal": 0.02,
		"base": {"cooldown": 0.15, "damage": 16.0, "duration": 4.0, "area": 2.0}},
	"haunted_boulevard": {"name": "Haunted Boulevard", "quote": "The whole street's lit.", "icon": "haunted_boulevard_skill",
		"evolution": true, "tint": Color(1.0, 0.9, 0.5), "behavior": "turret", "sheet": "street_lamp", "zap": 0.3,
		"base": {"cooldown": 3.0, "damage": 30.0, "duration": 12.0, "amount": 5, "range": 120.0}},
	"van_helsing": {"name": "Van Helsing", "quote": "Professional help.", "icon": "van_helsing_skill",
		"evolution": true, "behavior": "shooter", "sheet": "silver_stake", "aim": "nearest", "rot_offset": PI / 2,
		"base": {"cooldown": 0.35, "damage": 55.0, "speed": 380.0, "pierce": -1, "amount": 2, "range": 360.0, "knockback": 90.0}},
	"carpet_bombing": {"name": "Carpet Bombing", "quote": "INCOMING!!!", "icon": "carpet_bombing_skill",
		"evolution": true, "tint": Color(1.0, 0.6, 0.4), "behavior": "strike", "sheet": "fireball_explosion", "target": "random", "warn": 0.5,
		"strike_radius": 40.0, "sheet_scale": 3.0, "centered": true,
		"base": {"cooldown": 1.5, "damage": 90.0, "amount": 5, "knockback": 80.0}},
	"top_hat_tornado": {"name": "Top Hat Tornado", "quote": "Business is BOOMING.", "icon": "top_hat_tornado_skill",
		"evolution": true, "tint": Color(0.7, 0.7, 1.0), "behavior": "orbit", "sheet": "merchant_hat", "orbit_radius": 56.0, "shot_scale": 0.25,
		"base": {"cooldown": 0.2, "damage": 28.0, "speed": 110.0, "duration": 999.0, "pierce": -1, "amount": 8, "area": 1.3}},

	# ================================================================ Unions
	"plasma_storm": {"name": "Plasma Storm", "quote": "FLAMIN HOT and shocking.", "icon": "plasma_storm_skill",
		"evolution": true, "union": true, "tint": Color(1.0, 0.6, 1.0), "behavior": "chain", "color": Color(1.0, 0.6, 0.9), "explode": 30.0,
		"base": {"cooldown": 0.9, "damage": 50.0, "amount": 8, "range": 180.0}},
	"ricochet_royale": {"name": "Ricochet Royale", "quote": "OY MATE, heads or tails?", "icon": "ricochet_royale_skill",
		"evolution": true, "union": true, "behavior": "bounce", "sheet": "royale_rang",
		"base": {"cooldown": 1.5, "damage": 40.0, "speed": 260.0, "duration": 6.0, "pierce": -1, "amount": 8, "area": 1.4}},
	"night_parade": {"name": "Night Parade", "quote": "JUSTICE, WILLY O WISPY", "icon": "night_parade_skill",
		"evolution": true, "union": true, "tint": Color(0.7, 0.9, 1.0), "behavior": "summon", "sheet": "bat", "bite": 0.25, "extra_wisps": 4,
		"base": {"cooldown": 2.5, "damage": 26.0, "speed": 220.0, "duration": 8.0, "amount": 12, "pierce": 8}},
	"sacred_heart": {"name": "Sacred Heart", "quote": "I LOVED HER. JUMANJI.", "icon": "sacred_heart_skill",
		"evolution": true, "union": true, "tint": Color(1.0, 0.9, 0.7), "behavior": "nova", "color": Color(1.0, 0.9, 0.5), "heal": 6.0, "smite": true, "sheet": "sacred_heart",
		"base": {"cooldown": 2.0, "damage": 60.0, "range": 160.0, "knockback": 80.0, "pierce": -1}},
}
