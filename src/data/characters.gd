extends RefCounted
## Playable heroes. Bought with silver (`cost`). Some are hidden until a
## challenge is done first (`feat`, see progression.gd): the feat puts them up
## for sale, then they're bought like the rest. Monsters reuse their enemy sheets; `scale` shrinks big art.
## Joe starts with the CrossBow and Matt with the Claw (the user's call).
## `start_level` starts the hero's weapon already levelled (for weapons too
## slow to hold the first minute alone).

const CHARACTERS := {
	"joe": {"name": "Joe", "perk": "All-rounder. +10% damage.", "run": "run_joe", "idle": "idle_joe",
		"weapon": "crossbow", "stats": {"might": 0.10}, "cost": 0},
	"matt": {"name": "Matt", "perk": "Tough. +30 max health.", "run": "run_matt", "idle": "idle_matt",
		"weapon": "claw", "stats": {"max_hp": 30.0}, "cost": 150},
	"alex": {"name": "Alex", "perk": "Ranged. Projectiles fly 20% faster.", "run": "run_alex", "idle": "idle_alex",
		"weapon": "crossbow", "stats": {"proj_speed": 0.2}, "cost": 300},
	"jon": {"name": "Jon", "perk": "Lucky. More candy, more silver.", "run": "run_jon", "idle": "idle_jon",
		"weapon": "will_o_wisp", "stats": {"growth": 0.15, "greed": 0.25}, "cost": 500},
	"mr_hat": {"name": "Mr. Hat", "perk": "The merchant himself. +50% silver, +20% luck, starts with 3 hats.", "run": "mr_hat", "idle": "mr_hat", "scale": 0.25,
		"weapon": "merchant_hat", "start_level": 2, "stats": {"greed": 0.5, "luck": 0.2}, "feat": "silver_2000", "cost": 2000},
	# Monsters: a challenge first, then they're for sale
	"shambles": {"name": "Shambles", "perk": "Zombie. +40 max health; his Acid starts at level 2.", "run": "zombie", "idle": "zombie",
		"weapon": "acid", "start_level": 2, "stats": {"max_hp": 40.0}, "feat": "kills_2000", "cost": 400},
	"bonehead": {"name": "Bonehead", "perk": "Skull. Weapons recharge 10% faster.", "run": "skull", "idle": "skull",
		"weapon": "skull_toss", "stats": {"cooldown": -0.1}, "feat": "level_25", "cost": 600},
	"jack": {"name": "Jack", "perk": "Pumpkin. Weapons hit 20% wider.", "run": "pumpkin", "idle": "pumpkin",
		"weapon": "pumpkin_bomb", "stats": {"area": 0.2}, "feat": "pumpkins_500", "cost": 600},
	"boo": {"name": "Boo", "perk": "Ghost. Comes back once, moves 10% faster.", "run": "ghost", "idle": "ghost",
		"weapon": "chain_lightning", "stats": {"revival": 1, "move": 0.1}, "feat": "chests_10", "cost": 800},
	"the_stalk": {"name": "The Stalk", "perk": "Scarecrow. +30% luck.", "run": "scarecrow", "idle": "scarecrow", "scale": 0.5,
		"weapon": "candy_shotgun", "stats": {"luck": 0.3}, "feat": "candy_10000", "cost": 800},
	"alpha": {"name": "Alpha", "perk": "Werewolf. +20% damage, 15% faster.", "run": "werewolf", "idle": "werewolf",
		"weapon": "claw", "stats": {"might": 0.2, "move": 0.15}, "feat": "survive_15", "cost": 1000},
	"umbra": {"name": "Umbra", "perk": "Shadow Beast. +20% curse, +30% candy.", "run": "shadowbeast", "idle": "shadowbeast",
		"weapon": "bat_swarm", "stats": {"curse": 0.2, "growth": 0.3}, "feat": "bosses_10", "cost": 1200},
	"bog_king": {"name": "Bog King", "perk": "Swamp Thing. Regenerates, +50 max health.", "run": "swampthing", "idle": "swampthing", "scale": 0.5,
		"weapon": "blood_trail", "stats": {"regen": 1.0, "max_hp": 50.0}, "feat": "survive_20", "cost": 1500},
	"snail_king": {"name": "Snail King", "perk": "Slow. Takes 30% less damage.", "run": "snail_lord", "idle": "snail_lord", "scale": 0.5,
		"weapon": "heartbeat", "stats": {"armor": 0.3, "move": -0.25, "max_hp": 40.0}, "feat": "evolve_5", "cost": 1500},
}
