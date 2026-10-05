extends RefCounted
# ---------------------------------------------------------------- Enemies
# hp/damage are at minute 0; the stage multiplies hp as time passes.
# `faces` is the direction the art faces so it can be flipped to face the player.
# `rooted` monsters never move or get knocked back. `shoot` makes a monster
# fire a slow shot at the nearest hero within `range` every `every` seconds
# (the shot is slower than a hero walks, so it can always be dodged).
const ENEMIES := {
	"zombie": {"sheet": "zombie", "hp": 10.0, "speed": 26.0, "damage": 8.0, "radius": 6.0, "candy": 0, "faces": 1},
	"skull": {"sheet": "skull", "hp": 6.0, "speed": 48.0, "damage": 6.0, "radius": 6.0, "candy": 0, "faces": 1},
	"pumpkin": {"sheet": "pumpkin", "hp": 18.0, "speed": 30.0, "damage": 10.0, "radius": 6.0, "candy": 0, "faces": 1},
	"ghost": {"sheet": "ghost", "hp": 22.0, "speed": 34.0, "damage": 10.0, "radius": 6.0, "candy": 1, "faces": 1, "fly": true, "alpha": 0.8},
	"scarecrow": {"sheet": "scarecrow", "hp": 60.0, "speed": 24.0, "damage": 14.0, "radius": 8.0, "candy": 1, "faces": 1},
	"werewolf": {"sheet": "werewolf", "hp": 45.0, "speed": 58.0, "damage": 14.0, "radius": 9.0, "candy": 1, "faces": 1},
	"shadowbeast": {"sheet": "shadowbeast", "hp": 90.0, "speed": 40.0, "damage": 18.0, "radius": 10.0, "candy": 1, "faces": 1},
	"eye_stalk": {"sheet": "eye_stalk", "hp": 30.0, "speed": 0.0, "damage": 6.0, "radius": 7.0, "candy": 1, "faces": 1, "rooted": true,
		"shoot": {"every": 3.0, "speed": 55.0, "damage": 6.0, "range": 200.0, "sheet": "orb_purple"}},
	"gourd_spitter": {"sheet": "gourd_spitter", "hp": 30.0, "speed": 0.0, "damage": 6.0, "radius": 7.0, "candy": 1, "faces": 1, "rooted": true,
		"shoot": {"every": 2.6, "speed": 60.0, "damage": 5.0, "range": 190.0, "sheet": "seed_fire"}},
	"frost_totem": {"sheet": "frost_totem", "hp": 36.0, "speed": 0.0, "damage": 6.0, "radius": 7.0, "candy": 1, "faces": 1, "rooted": true,
		"shoot": {"every": 3.2, "speed": 58.0, "damage": 7.0, "range": 210.0, "sheet": "ice_shard", "point": true}},
	"sludge_toad": {"sheet": "sludge_toad", "hp": 40.0, "speed": 0.0, "damage": 6.0, "radius": 8.0, "candy": 1, "faces": 1, "rooted": true,
		"shoot": {"every": 3.0, "speed": 50.0, "damage": 6.0, "range": 190.0, "sheet": "goo_glob"}},
	# Comes at 20:00 (see Run.CLEAR_SECONDS), always as a boss: flies over
	# props, shrugs off freezes and knockback, hits hard, and keeps coming.
	"reaper": {"sheet": "reaper", "hp": 4000.0, "speed": 85.0, "damage": 40.0, "radius": 10.0, "candy": 2, "faces": -1,
		"fly": true, "unstoppable": true},
	"swampthing": {"sheet": "swampthing", "hp": 160.0, "speed": 28.0, "damage": 22.0, "radius": 12.0, "candy": 2, "faces": 1},
}

# Candy is the experience pickup (the run reports "candyCollected").
const CANDY := [
	{"sheet": "candy_corn", "xp": 1.0},
	{"sheet": "candy_bar", "xp": 3.0},
	{"sheet": "candy_bubblegum", "xp": 10.0},
]
