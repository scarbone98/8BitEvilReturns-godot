extends RefCounted
## Passive items. Each level adds `per_level` to the hero's stats (see
## Player.STAT_DEFAULTS). The first seven are (orig) names and descriptions
## from the Unity build; their icons are guesses. Those seven plus Ghost Step
## are what a new player starts with; the rest are `locked` until a feat
## (progression.gd).

# Slots a hero starts with; the shop sells one more of each (weapon_slots /
# passive_slots power-ups in progression.gd).
const MAX_WEAPONS := 5
const MAX_PASSIVES := 5

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
	"max_health": {"name": "Max Health", "desc": "Increase maximum Health by 15%", "icon": "heartbeat",
		"per_level": {"max_hp_mul": 0.15}, "max_level": 5},
	"vacuusuck": {"name": "VacuuSuck", "desc": "Pull candy from further away", "quote": "Hear me out...", "icon": "vacusuck",
		"per_level": {"magnet": 0.35}, "max_level": 5},
	# New
	"pocket_watch": {"name": "Pocket Watch", "desc": "Weapon effects last 10% longer", "icon": "clock", "locked": true,
		"per_level": {"duration": 0.10}, "max_level": 5},
	"lucky_trophy": {"name": "Lucky Trophy", "desc": "+10% luck: better chests, more level-up choices", "icon": "trophy_small", "locked": true,
		"per_level": {"luck": 0.10}, "max_level": 5},
	"candy_basket": {"name": "Candy Basket", "desc": "+20% silver from everything", "icon": "candybasket", "locked": true,
		"per_level": {"greed": 0.20}, "max_level": 5},
	"scope": {"name": "Scope", "desc": "Projectiles fly 10% faster", "icon": "crosshair_new", "locked": true,
		"per_level": {"proj_speed": 0.10}, "max_level": 5},
	"grave_dirt": {"name": "Grave Dirt", "desc": "Weapons hit 10% wider", "icon": "sewer", "locked": true,
		"per_level": {"area": 0.10}, "max_level": 5},
	"skull_ring": {"name": "Skull Ring", "desc": "+10% curse: tougher, faster, more monsters. More candy.", "icon": "skull", "locked": true,
		"per_level": {"curse": 0.10, "growth": 0.05}, "max_level": 5},
	"duplicator": {"name": "Duplicator", "desc": "Weapons fire 1 more projectile", "icon": "sparkle", "locked": true,
		"per_level": {"amount": 1}, "max_level": 2},
	"heart_locket": {"name": "Heart Locket", "desc": "Come back once when you fall", "icon": "heart", "locked": true,
		"per_level": {"revival": 1}, "max_level": 1},
	"ghost_step": {"name": "Ghost Step", "desc": "Move 10% faster", "icon": "ghost",
		"per_level": {"move": 0.10}, "max_level": 5},
}

# Offered when everything is maxed ("repeatable elixirs" in the original).
const ELIXIRS := {
	"elixir_heal": {"name": "Heart", "desc": "Heal 30 health", "icon": "heart", "heal": 30.0},
	"elixir_silver": {"name": "Silver Stash", "desc": "+25 silver", "icon": "silver", "silver": 25},
}
