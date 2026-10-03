extends RefCounted
# ---------------------------------------------------------------- Enemies
# hp/damage are at minute 0; the stage multiplies hp as time passes.
# `faces` is the direction the art faces so it can be flipped to face the player.
const ENEMIES := {
	"zombie": {"sheet": "zombie", "hp": 10.0, "speed": 26.0, "damage": 8.0, "radius": 6.0, "candy": 0, "faces": 1},
	"skull": {"sheet": "skull", "hp": 6.0, "speed": 48.0, "damage": 6.0, "radius": 6.0, "candy": 0, "faces": 1},
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
	{"sheet": "candy_bar", "xp": 3.0},
	{"sheet": "candy_bubblegum", "xp": 10.0},
]
