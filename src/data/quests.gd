extends RefCounted
## Little per-map quests, Vampire Survivors style: each map hides a relic to
## find, has a boss to beat and one challenge. Done once per save; each pays
## silver, and finishing all three crowns the map (CROWN_SILVER more).
##
## `check` forms (all for the run just played, on that map, whole team):
##   {relic: true}        picked up the map's relic (any player)
##   {boss: enemy}        defeated that boss
##   {kind: enemy, min}   defeated that many of an enemy (team total)
##   {bosses: n}          defeated that many bosses
##   {run: stat, min}     a run stat (seconds...)
## `relic` per map: the sprite, and where it lies: `dir` (degrees, 0 = east,
## 90 = south) and `dist` (px) from where the heroes start.

const CROWN_SILVER := 300

const QUESTS := {
	"graveyard": {
		"relic": {"name": "Lost Locket", "sprite": "relic_locket", "dir": 270.0, "dist": 1400.0},
		"list": [
			{"id": "gy_relic", "name": "Lost Locket", "desc": "Find the locket buried somewhere north", "check": {"relic": true}, "silver": 150},
			{"id": "gy_boss", "name": "Scarecrow Season", "desc": "Defeat the Scarecrow", "check": {"boss": "scarecrow"}, "silver": 150},
			{"id": "gy_skulls", "name": "Skull Sweep", "desc": "Defeat 300 skulls in one run", "check": {"kind": "skull", "min": 300}, "silver": 200},
		],
	},
	"crimson_crypt": {
		"relic": {"name": "Blood Chalice", "sprite": "relic_chalice", "dir": 20.0, "dist": 1500.0},
		"list": [
			{"id": "cc_relic", "name": "Blood Chalice", "desc": "Find the chalice somewhere east", "check": {"relic": true}, "silver": 150},
			{"id": "cc_boss", "name": "Moonstruck", "desc": "Defeat the Werewolf", "check": {"boss": "werewolf"}, "silver": 150},
			{"id": "cc_ghosts", "name": "Exorcist", "desc": "Defeat 400 ghosts in one run", "check": {"kind": "ghost", "min": 400}, "silver": 200},
		],
	},
	"pumpkin_patch": {
		"relic": {"name": "Golden Gourd", "sprite": "relic_gourd", "dir": 150.0, "dist": 1400.0},
		"list": [
			{"id": "pp_relic", "name": "Golden Gourd", "desc": "Find the golden gourd somewhere south-west", "check": {"relic": true}, "silver": 150},
			{"id": "pp_boss", "name": "Strawman", "desc": "Defeat the Scarecrow", "check": {"boss": "scarecrow"}, "silver": 150},
			{"id": "pp_pumpkins", "name": "Harvest", "desc": "Defeat 600 pumpkins in one run", "check": {"kind": "pumpkin", "min": 600}, "silver": 200},
		],
	},
	"snowbound": {
		"relic": {"name": "Frozen Heart", "sprite": "relic_frozen_heart", "dir": 200.0, "dist": 1500.0},
		"list": [
			{"id": "sb_relic", "name": "Frozen Heart", "desc": "Find the frozen heart somewhere west", "check": {"relic": true}, "silver": 150},
			{"id": "sb_boss", "name": "Pack Leader", "desc": "Defeat the Werewolf", "check": {"boss": "werewolf"}, "silver": 150},
			{"id": "sb_survive", "name": "Cold Feet", "desc": "Survive 10 minutes in the snow", "check": {"run": "seconds", "min": 600}, "silver": 200},
		],
	},
	"sewers": {
		"relic": {"name": "Sewer Key", "sprite": "relic_key", "dir": 90.0, "dist": 1400.0},
		"list": [
			{"id": "sw_relic", "name": "Sewer Key", "desc": "Find the key somewhere south", "check": {"relic": true}, "silver": 150},
			{"id": "sw_boss", "name": "Bog Boss", "desc": "Defeat the Swamp Thing", "check": {"boss": "swampthing"}, "silver": 150},
			{"id": "sw_zombies", "name": "Zombie Flood", "desc": "Defeat 800 zombies in one run", "check": {"kind": "zombie", "min": 800}, "silver": 200},
		],
	},
	"crypt_depths": {
		"relic": {"name": "Crown of Bones", "sprite": "relic_crown", "dir": 315.0, "dist": 1600.0},
		"list": [
			{"id": "cd_relic", "name": "Crown of Bones", "desc": "Find the crown somewhere north-east", "check": {"relic": true}, "silver": 150},
			{"id": "cd_boss", "name": "Lights Out", "desc": "Defeat the Shadowbeast", "check": {"boss": "shadowbeast"}, "silver": 150},
			{"id": "cd_bosses", "name": "Boss Rush", "desc": "Defeat 4 bosses in one run", "check": {"bosses": 4}, "silver": 200},
		],
	},
}
