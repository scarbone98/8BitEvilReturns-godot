extends RefCounted
# ---------------------------------------------------------------- Stages
# spawns: while from <= minute < to, keep spawning `enemy` at `rate`/s.
# events: one-shot at `at` minutes: "ring" circles the player, "boss" spawns
# a big version that drops a chest.
const STAGES := {
	"graveyard": {
		"name": "The Graveyard", "about": "Where it all started.", "ground": "gamebg", "hp_per_minute": 0.35, "max_alive": 600,
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
	"crimson_crypt": {
		"name": "Crimson Crypt", "about": "The graveyard under a blood moon. Harder from the first minute.",
		"ground": "gamebg", "tint": Color(1.0, 0.55, 0.55), "hp_per_minute": 0.5, "max_alive": 600, "locked": true,
		"silver_bonus": 0.5,
		"obstacles": ["grave_1_small", "grave_2", "tree", "tree_2", "tree_5", "tree_6", "mausoleum"],
		"spawns": [
			{"enemy": "skull", "from": 0.0, "to": 4.0, "rate": 1.0},
			{"enemy": "ghost", "from": 0.0, "to": 6.0, "rate": 0.6},
			{"enemy": "werewolf", "from": 1.0, "to": 30.0, "rate": 0.5},
			{"enemy": "scarecrow", "from": 2.0, "to": 10.0, "rate": 0.5},
			{"enemy": "shadowbeast", "from": 4.0, "to": 30.0, "rate": 0.6},
			{"enemy": "skull", "from": 4.0, "to": 30.0, "rate": 1.8},
			{"enemy": "swampthing", "from": 7.0, "to": 30.0, "rate": 0.5},
			{"enemy": "ghost", "from": 8.0, "to": 30.0, "rate": 1.5},
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
}
