extends RefCounted
# ---------------------------------------------------------------- Stages
# Each stage: a floor (`ground`, recoloured from the original with
# tools/recolor.py), the props scattered on it (`obstacles`) and flat `decor`,
# and its monsters:
#   waves: minute by minute from PACING below (VS style): each minute names
#           which `cast` roles spawn, and earlier roles stop. `pace` scales
#           the whole map's counts and rates.
#   spawns: while from <= minute < to, keep spawning `enemy` at `rate`/s
#           (only the rooted shooters now, on top of the waves).
#   events: one-shot at `at` minutes: "ring" circles the player, "boss" spawns
#           a big version that drops a chest.
# layouts: how each 160px chunk is filled, one picked per chunk by weight `w`
#   (obstacles.gd): "open" (nothing), "row" (n in a line, `gap` apart, `mix`
#   alternates kinds, `vertical` chance), "grid" (cols x rows plot, `missing`
#   chance per cell), "grove" (n within radius r), "landmark" (a `center` with
#   one `around` kind at fixed `spots`), "line" (a solid run, `hole` chance of a
#   gap), "aisle" (two facing columns, `middle` at the end), "scatter" (random).
# props_per_chunk: [min, max] props tried per chunk by "scatter" (default [0, 3]).
# twist: what this map adds on Nightmare (Run._twist_tick, Hud fog/darkness):
#   graves (graves burst into zombies), fountains (blood fountains heal
#   monsters), pumpkin_burst (pumpkins explode after dying), blizzard (snow
#   fog), ooze (pipes pour slowing puddles), darkness (only lit areas show).
# Modifiers: hp_per_minute (how fast monsters toughen: kept low, the later
# waves' tougher kinds do most of the work), speed_mul (monster
# speed), silver_bonus (extra silver at the end). `locked` stages need the feat
# that lists them in progression.gd.
# The 20 minutes every map follows, like VS: one wave a minute, and when the
# minute turns, the last wave's monsters stop coming (the ones already out
# stay). `roles` are filled from the map's cast ("all" = every role).
# `min`: monsters kept on screen; drop below and more come at once.
# `rate`: more per second on top. `swarm`: [count, seconds]: one-hit fodder
# (cast.swarm) pouring in from one side; `sides` 2 = from both.
# Calm and hard minutes alternate; from 15:00 it's everything, and bigger swarms.
# How often each role is picked within a wave: the bulk is ordinary monsters,
# the big ones are sprinkled in.
const ROLE_WEIGHTS := {"grunt": 4.0, "fodder": 4.0, "mid": 3.0, "flier": 3.0, "fast": 2.0, "tank": 1.0, "heavy": 1.0, "giant": 0.5}

const PACING := [
	{"roles": ["grunt"], "min": 10, "rate": 0.8},                          # 0
	{"roles": ["grunt", "fodder"], "min": 16, "rate": 1.2},                # 1
	{"roles": ["mid"], "min": 14, "rate": 1.0, "swarm": [40, 15]},         # 2
	{"roles": ["grunt", "flier"], "min": 28, "rate": 2.2},                 # 3 hard
	{"roles": ["mid", "tank"], "min": 18, "rate": 1.4},                    # 4
	{"roles": ["flier"], "min": 20, "rate": 1.2, "swarm": [80, 20]},       # 5
	{"roles": ["grunt", "mid", "fodder"], "min": 40, "rate": 3.0},         # 6 hard
	{"roles": ["fast", "grunt"], "min": 22, "rate": 1.5},                  # 7
	{"roles": ["grunt", "fodder"], "min": 30, "rate": 2.0, "swarm": [100, 20]},  # 8
	{"roles": ["fast", "flier", "tank"], "min": 45, "rate": 3.5},          # 9 hard
	{"roles": ["heavy", "grunt"], "min": 30, "rate": 2.2},                 # 10
	{"roles": ["fodder"], "min": 35, "rate": 2.5, "swarm": [150, 25]},     # 11
	{"roles": ["fast", "flier"], "min": 55, "rate": 4.0},                  # 12 hard
	{"roles": ["mid", "tank", "grunt"], "min": 60, "rate": 4.0},           # 13
	{"roles": ["giant", "heavy", "grunt"], "min": 35, "rate": 2.0, "swarm": [150, 20]},  # 14
	{"roles": ["all"], "min": 150, "rate": 9.0},                           # 15
	{"roles": ["all"], "min": 180, "rate": 10.0, "swarm": [220, 25]},      # 16
	{"roles": ["all"], "min": 220, "rate": 12.0},                          # 17
	{"roles": ["all"], "min": 260, "rate": 14.0, "swarm": [280, 25]},      # 18
	{"roles": ["all"], "min": 300, "rate": 16.0, "swarm": [350, 30], "sides": 2},  # 19
]

const STAGES := {
	"graveyard": {
		"name": "The Graveyard", "about": "Where it all started.", "ground": "gamebg", "hp_per_minute": 0.17, "max_alive": 600,
		"obstacles": ["grave_1_small", "grave_2", "tree", "tree_2", "tree_3", "tree_4", "tree_5", "tree_6", "street_lamp", "mausoleum", "prop_angel", "prop_open_grave"],
		"twist": {"type": "graves", "name": "Restless Graves", "desc": "Graves near you burst open."},
		"layouts": [
			{"t": "open", "w": 2.5},
			{"t": "row", "w": 3, "kinds": ["grave_1_small", "grave_2"], "n": [3, 4], "gap": 30, "mix": true},
			{"t": "grid", "w": 2, "kinds": ["grave_1_small", "grave_2"], "cols": [2, 3], "rows": 2, "gap": [32, 40]},
			{"t": "grove", "w": 2, "kinds": ["tree", "tree_2", "tree_3", "tree_4", "tree_5", "tree_6"], "n": [2, 4], "r": 38},
			{"t": "landmark", "w": 1, "center": ["mausoleum"], "around": ["street_lamp"], "spots": [[-52, 8], [52, 8]]},
			{"t": "landmark", "w": 1, "center": ["prop_angel"], "around": ["grave_1_small", "grave_2"], "spots": [[-34, 18], [34, 18]]},
			{"t": "row", "w": 1, "kinds": ["prop_open_grave", "grave_2"], "n": 2, "gap": 46, "mix": true},
			{"t": "row", "w": 0.7, "kinds": ["street_lamp"], "n": 2, "gap": 70},
		],
		"cast": {"grunt": "zombie", "fodder": "skull", "mid": "pumpkin", "flier": "ghost", "tank": "scarecrow", "fast": "werewolf", "heavy": "shadowbeast", "giant": "swampthing", "swarm": "skull"},
		"pace": 1.0,
		# Stationary shooters keep coming all run, on top of the waves.
		"spawns": [
			{"enemy": "eye_stalk", "from": 2.5, "to": 30.0, "rate": 0.15},
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
		],
	},
	"crimson_crypt": {
		"name": "Crimson Crypt", "about": "The graveyard under a blood moon. Harder from the first minute.",
		"ground": "gamebg", "tint": Color(1.0, 0.55, 0.55), "hp_per_minute": 0.25, "max_alive": 600, "locked": true,
		"silver_bonus": 0.5,
		"props_per_chunk": [1, 4],
		"obstacles": ["grave_1_small", "grave_2", "tree_5", "tree_6", "mausoleum", "prop_blood_fountain", "prop_gibbet", "prop_obelisk", "prop_angel", "prop_open_grave"],
		"decor": ["blood", "prop_bones"],
		"twist": {"type": "fountains", "name": "Blood Fountains", "desc": "Fountains heal the monsters near them."},
		"layouts": [
			{"t": "open", "w": 2},
			{"t": "row", "w": 2, "kinds": ["grave_1_small", "grave_2"], "n": [3, 4], "gap": 30, "mix": true},
			{"t": "grid", "w": 1.5, "kinds": ["grave_1_small", "grave_2"], "cols": [2, 3], "rows": 2, "gap": [32, 40]},
			{"t": "landmark", "w": 0.7, "center": ["prop_blood_fountain"], "around": ["prop_obelisk"], "spots": [[-50, 4], [50, 4]]},
			{"t": "row", "w": 1, "kinds": ["prop_gibbet"], "n": 2, "gap": 56},
			{"t": "grove", "w": 1.5, "kinds": ["tree_5", "tree_6"], "n": [2, 3], "r": 36},
			{"t": "landmark", "w": 1, "center": ["prop_angel", "mausoleum"], "around": ["prop_obelisk"], "spots": [[-50, 10], [50, 10]]},
			{"t": "row", "w": 0.6, "kinds": ["prop_open_grave"], "n": 2, "gap": 46},
		],
		"cast": {"grunt": "ghost", "fodder": "skull", "mid": "scarecrow", "flier": "ghost", "tank": "scarecrow", "fast": "werewolf", "heavy": "shadowbeast", "giant": "swampthing", "swarm": "skull"},
		"pace": 1.3,
		# Stationary shooters keep coming all run, on top of the waves.
		"spawns": [
			{"enemy": "eye_stalk", "from": 1.0, "to": 30.0, "rate": 0.25},
		],
		"events": [
			{"at": 1.5, "type": "ring", "enemy": "ghost", "count": 24},
			{"at": 3.0, "type": "boss", "enemy": "werewolf"},
			{"at": 5.0, "type": "ring", "enemy": "werewolf", "count": 24},
			{"at": 6.0, "type": "boss", "enemy": "shadowbeast"},
			{"at": 9.0, "type": "boss", "enemy": "swampthing"},
			{"at": 12.0, "type": "ring", "enemy": "shadowbeast", "count": 30},
			{"at": 14.0, "type": "boss", "enemy": "swampthing"},
			{"at": 18.0, "type": "boss", "enemy": "swampthing"},
		],
	},
	"pumpkin_patch": {
		"name": "Pumpkin Patch", "about": "Rows of grinning gourds, and something in the corn.",
		"ground": "ground_pumpkin", "hp_per_minute": 0.2, "max_alive": 600, "locked": true, "silver_bonus": 0.2,
		"props_per_chunk": [1, 4],
		"obstacles": ["tree_3", "tree_owl", "candybasket", "street_lamp", "prop_hay_bale", "prop_pumpkin_pile", "prop_corn", "prop_fence", "prop_scarecrow"],
		"twist": {"type": "pumpkin_burst", "name": "Harvest Moon", "desc": "Pumpkins explode when they die. Step away!"},
		"layouts": [
			{"t": "open", "w": 2},
			{"t": "grid", "w": 2, "kinds": ["prop_pumpkin_pile"], "cols": [2, 3], "rows": 2, "gap": [40, 34], "missing": 0.25},
			{"t": "line", "w": 2, "kinds": ["prop_fence"], "n": [2, 3], "gap": 40, "hole": 0.35, "always_hole_from": 3},
			{"t": "row", "w": 2, "kinds": ["prop_corn"], "n": [3, 5], "gap": 20, "vertical": 0.15},
			{"t": "landmark", "w": 1, "center": ["prop_scarecrow"], "around": ["prop_hay_bale", "prop_pumpkin_pile"], "spots": [[-40, 10], [40, 10]]},
			{"t": "grove", "w": 1.5, "kinds": ["tree_3", "tree_owl"], "n": [1, 3], "r": 34},
			{"t": "row", "w": 1, "kinds": ["prop_hay_bale"], "n": 2, "gap": 38},
			{"t": "row", "w": 0.4, "kinds": ["candybasket", "street_lamp"], "n": 2, "gap": 46, "mix": true},
		],
		"cast": {"grunt": "pumpkin", "fodder": "skull", "mid": "zombie", "flier": "skull", "tank": "scarecrow", "fast": "werewolf", "heavy": "shadowbeast", "giant": "scarecrow", "swarm": "pumpkin"},
		"pace": 1.1,
		# Stationary shooters keep coming all run, on top of the waves.
		"spawns": [
			{"enemy": "gourd_spitter", "from": 1.5, "to": 30.0, "rate": 0.25},
		],
		"events": [
			{"at": 1.5, "type": "ring", "enemy": "pumpkin", "count": 24},
			{"at": 3.0, "type": "boss", "enemy": "scarecrow"},
			{"at": 5.0, "type": "ring", "enemy": "scarecrow", "count": 16},
			{"at": 7.0, "type": "boss", "enemy": "werewolf"},
			{"at": 9.0, "type": "ring", "enemy": "pumpkin", "count": 40},
			{"at": 11.0, "type": "boss", "enemy": "scarecrow"},
			{"at": 15.0, "type": "boss", "enemy": "shadowbeast"},
		],
	},
	"snowbound": {
		"name": "Snowbound Cemetery", "about": "Fresh snow, fast feet. Everything out here is in a hurry.",
		"ground": "ground_snow", "hp_per_minute": 0.2, "max_alive": 600, "locked": true, "silver_bonus": 0.3,
		"speed_mul": 1.15,
		"props_per_chunk": [1, 4],
		"obstacles": ["tree_5", "tree_6", "grave_1_small", "mausoleum", "prop_snow_pine", "prop_snowman", "prop_ice_grave", "prop_snow_angel"],
		"twist": {"type": "blizzard", "name": "Blizzard", "desc": "The snow closes in."},
		"layouts": [
			{"t": "open", "w": 2},
			{"t": "grove", "w": 3, "kinds": ["prop_snow_pine"], "n": [3, 5], "r": 46, "spacing": 22},
			{"t": "row", "w": 2, "kinds": ["prop_ice_grave", "grave_1_small"], "n": [3, 4], "gap": 30, "mix": true},
			{"t": "grid", "w": 1, "kinds": ["prop_ice_grave"], "cols": [2, 3], "rows": 2, "gap": [32, 40]},
			{"t": "landmark", "w": 1, "center": ["prop_snow_angel"], "around": ["prop_snowman"], "spots": [[-36, 14], [36, 14]]},
			{"t": "landmark", "w": 0.7, "center": ["mausoleum"], "around": ["prop_snow_pine"], "spots": [[-54, 4], [54, 4]]},
			{"t": "row", "w": 0.6, "kinds": ["prop_snowman"], "n": [1, 2], "gap": 40},
			{"t": "grove", "w": 1, "kinds": ["tree_5", "tree_6"], "n": [2, 3], "r": 34},
		],
		"cast": {"grunt": "zombie", "fodder": "skull", "mid": "ghost", "flier": "ghost", "tank": "shadowbeast", "fast": "werewolf", "heavy": "shadowbeast", "giant": "shadowbeast", "swarm": "skull"},
		"pace": 1.1,
		# Stationary shooters keep coming all run, on top of the waves.
		"spawns": [
			{"enemy": "frost_totem", "from": 2.0, "to": 30.0, "rate": 0.22},
		],
		"events": [
			{"at": 2.0, "type": "ring", "enemy": "ghost", "count": 24},
			{"at": 3.5, "type": "boss", "enemy": "werewolf"},
			{"at": 6.0, "type": "ring", "enemy": "werewolf", "count": 20},
			{"at": 8.0, "type": "boss", "enemy": "shadowbeast"},
			{"at": 12.0, "type": "boss", "enemy": "werewolf"},
			{"at": 16.0, "type": "boss", "enemy": "shadowbeast"},
		],
	},
	"sewers": {
		"name": "The Sewers", "about": "Wide open tunnels. Nowhere to hide from what crawls up the drains.",
		"ground": "ground_sewer", "hp_per_minute": 0.22, "max_alive": 600, "locked": true, "silver_bonus": 0.4,
		"props_per_chunk": [1, 4],
		"obstacles": ["street_lamp", "prop_sewer_pipe", "prop_barrels", "prop_brick_pillar"],
		"decor": ["sewer", "skull", "blood", "prop_bones"],
		"twist": {"type": "ooze", "name": "Ooze", "desc": "The pipes pour slowing ooze."},
		"layouts": [
			{"t": "open", "w": 2},
			{"t": "line", "w": 3, "kinds": ["prop_sewer_pipe"], "n": [2, 3], "gap": 40, "hole": 0.4, "always_hole_from": 3},
			{"t": "aisle", "w": 1.5, "kinds": ["prop_brick_pillar"], "n": 2, "gap": [64, 56], "middle": ["prop_barrels", "street_lamp"]},
			{"t": "grove", "w": 1.5, "kinds": ["prop_barrels"], "n": [1, 2], "r": 30, "spacing": 34},
			{"t": "row", "w": 1, "kinds": ["street_lamp"], "n": 2, "gap": 70},
			{"t": "row", "w": 1, "kinds": ["prop_brick_pillar"], "n": [2, 3], "gap": 40},
		],
		"cast": {"grunt": "zombie", "fodder": "skull", "mid": "zombie", "flier": "ghost", "tank": "swampthing", "fast": "skull", "heavy": "swampthing", "giant": "swampthing", "swarm": "zombie"},
		"pace": 1.15,
		# Stationary shooters keep coming all run, on top of the waves.
		"spawns": [
			{"enemy": "sludge_toad", "from": 1.5, "to": 30.0, "rate": 0.25},
		],
		"events": [
			{"at": 2.0, "type": "ring", "enemy": "zombie", "count": 30},
			{"at": 4.0, "type": "boss", "enemy": "swampthing"},
			{"at": 7.0, "type": "ring", "enemy": "swampthing", "count": 12},
			{"at": 9.0, "type": "boss", "enemy": "swampthing"},
			{"at": 13.0, "type": "boss", "enemy": "swampthing"},
		],
	},
	"crypt_depths": {
		"name": "Crypt Depths", "about": "Deep under the graveyard, where the bosses sleep. Not for long.",
		"ground": "ground_crypt", "hp_per_minute": 0.3, "max_alive": 600, "locked": true, "silver_bonus": 0.6,
		"props_per_chunk": [1, 4],
		"obstacles": ["mausoleum", "grave_1_small", "prop_sarcophagus", "prop_broken_pillar", "prop_candelabra", "prop_open_grave"],
		"decor": ["skull", "blood", "prop_bones"],
		"twist": {"type": "darkness", "name": "Lights Out", "desc": "You only see what your light and the candles show."},
		"layouts": [
			{"t": "open", "w": 1.5},
			{"t": "aisle", "w": 2.5, "kinds": ["prop_broken_pillar"], "n": [2, 3], "gap": [64, 40], "middle": ["prop_candelabra"]},
			{"t": "landmark", "w": 2, "center": ["prop_sarcophagus"], "around": ["prop_candelabra"], "spots": [[-36, 2], [36, 2]]},
			{"t": "row", "w": 1.5, "kinds": ["grave_1_small"], "n": [3, 4], "gap": 30},
			{"t": "landmark", "w": 1, "center": ["mausoleum"], "around": ["prop_candelabra"], "spots": [[-50, 8], [50, 8]]},
			{"t": "row", "w": 0.7, "kinds": ["prop_open_grave"], "n": 2, "gap": 46},
			{"t": "grid", "w": 0.7, "kinds": ["prop_sarcophagus"], "cols": 2, "rows": 2, "gap": [56, 40], "missing": 0.2},
		],
		"cast": {"grunt": "skull", "fodder": "skull", "mid": "ghost", "flier": "ghost", "tank": "shadowbeast", "fast": "werewolf", "heavy": "shadowbeast", "giant": "swampthing", "swarm": "ghost"},
		"pace": 1.25,
		# Stationary shooters keep coming all run, on top of the waves.
		"spawns": [
			{"enemy": "eye_stalk", "from": 1.0, "to": 30.0, "rate": 0.3},
		],
		"events": [
			{"at": 1.0, "type": "boss", "enemy": "shadowbeast"},
			{"at": 3.0, "type": "boss", "enemy": "werewolf"},
			{"at": 5.0, "type": "boss", "enemy": "swampthing"},
			{"at": 7.0, "type": "ring", "enemy": "shadowbeast", "count": 24},
			{"at": 8.0, "type": "boss", "enemy": "scarecrow"},
			{"at": 10.0, "type": "boss", "enemy": "shadowbeast"},
			{"at": 12.0, "type": "boss", "enemy": "swampthing"},
		],
	},
}
