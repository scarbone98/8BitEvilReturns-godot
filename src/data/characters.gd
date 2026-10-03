extends RefCounted
## Playable heroes. Unlock with silver (`cost`) or a feat (`feat`, see
## progression.gd). Monsters reuse their enemy sheets; `scale` shrinks big art.
## The four humans' starting weapons match Mystery Crypt.

const CHARACTERS := {
	"joe": {"name": "Joe", "perk": "All-rounder. +10% damage.", "run": "run_joe", "idle": "idle_joe",
		"weapon": "claw", "stats": {"might": 0.10}, "cost": 0},
	"matt": {"name": "Matt", "perk": "Tough. +30 max health.", "run": "run_matt", "idle": "idle_matt",
		"weapon": "cursed_sword", "stats": {"max_hp": 30.0}, "cost": 150},
	"alex": {"name": "Alex", "perk": "Ranged. Projectiles fly 20% faster.", "run": "run_alex", "idle": "idle_alex",
		"weapon": "crossbow", "stats": {"proj_speed": 0.2}, "cost": 300},
	"jon": {"name": "Jon", "perk": "Lucky. More candy, more silver.", "run": "run_jon", "idle": "idle_jon",
		"weapon": "will_o_wisp", "stats": {"growth": 0.15, "greed": 0.25}, "cost": 500},
	"mr_hat": {"name": "Mr. Hat", "perk": "The merchant himself. +50% silver, +20% luck.", "run": "merchant", "idle": "merchant", "scale": 0.25,
		"weapon": "merchant_hat", "stats": {"greed": 0.5, "luck": 0.2}, "cost": 2000},
	# Monsters, unlocked by feats
	"shambles": {"name": "Shambles", "perk": "Zombie. +40 max health, 10% slower.", "run": "zombie", "idle": "zombie",
		"weapon": "acid", "stats": {"max_hp": 40.0, "move": -0.1}, "feat": "kills_2000"},
	"bonehead": {"name": "Bonehead", "perk": "Skull. Weapons recharge 10% faster.", "run": "skull", "idle": "skull",
		"weapon": "skull_toss", "stats": {"cooldown": -0.1}, "feat": "level_25"},
	"jack": {"name": "Jack", "perk": "Pumpkin. Weapons hit 20% wider.", "run": "pumpkin", "idle": "pumpkin",
		"weapon": "pumpkin_bomb", "stats": {"area": 0.2}, "feat": "pumpkins_500"},
	"boo": {"name": "Boo", "perk": "Ghost. Comes back once, moves 10% faster.", "run": "ghost", "idle": "ghost",
		"weapon": "chain_lightning", "stats": {"revival": 1, "move": 0.1}, "feat": "chests_10"},
	"the_stalk": {"name": "The Stalk", "perk": "Scarecrow. +30% luck.", "run": "scarecrow", "idle": "scarecrow", "scale": 0.75,
		"weapon": "candy_shotgun", "stats": {"luck": 0.3}, "feat": "candy_10000"},
	"alpha": {"name": "Alpha", "perk": "Werewolf. +20% damage, 15% faster.", "run": "werewolf", "idle": "werewolf",
		"weapon": "claw", "stats": {"might": 0.2, "move": 0.15}, "feat": "survive_15"},
	"umbra": {"name": "Umbra", "perk": "Shadow Beast. +20% curse, +30% candy.", "run": "shadowbeast", "idle": "shadowbeast",
		"weapon": "bat_swarm", "stats": {"curse": 0.2, "growth": 0.3}, "feat": "bosses_10"},
	"bog_king": {"name": "Bog King", "perk": "Swamp Thing. Regenerates, +50 max health.", "run": "swampthing", "idle": "swampthing", "scale": 0.6,
		"weapon": "blood_trail", "stats": {"regen": 1.0, "max_hp": 50.0}, "feat": "survive_20"},
	"snail_king": {"name": "Snail King", "perk": "Slow. Takes 30% less damage.", "run": "snail_lord", "idle": "snail_lord", "scale": 0.4,
		"weapon": "heartbeat", "stats": {"armor": 0.3, "move": -0.25, "max_hp": 40.0}, "feat": "evolve_5"},
}
