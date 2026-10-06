extends RefCounted
## Feats (achievements) and the silver power-up shop.
##
## A feat is checked when a run ends. `check` forms:
##   {run: stat, min: n}                in one run (stats: seconds, kills, level,
##                                      chests, bosses, candy, healed, evolutions,
##                                      unions, weapons_full, silver)
##   {run: stat, min: n, char: id}      ...as that hero
##   {run: stat, min: n, stage: id}     ...on that stage
##   {total: stat, min: n}              across every run (kills, candy, chests,
##                                      bosses, silver, distance, runs)
##   {kind: enemy, min: n}              that enemy defeated, across every run
##   {evolved: n}                       n different evolutions ever made
## `unlocks` lists weapons, passives or stages it adds. Heroes name their own
## feat in characters.gd, so a feat can also exist just to unlock a hero.

const FEATS := {
	# Early ones come quickly and open up the starting pool, VS style: a new
	# player has 6 weapons and the 7 original passives, everything else is here.
	"survive_3": {"name": "Still Standing", "desc": "Survive 3 minutes", "check": {"run": "seconds", "min": 180}, "unlocks": ["cursed_sword"]},
	"level_10": {"name": "Charged Up", "desc": "Reach level 10", "check": {"run": "level", "min": 10}, "unlocks": ["lightning"]},
	"boss_1": {"name": "Big Game", "desc": "Defeat a boss", "check": {"run": "bosses", "min": 1}, "unlocks": ["scope"]},
	"zombies_300": {"name": "Zombie Stomper", "desc": "Defeat 300 zombies (all runs)", "check": {"kind": "zombie", "min": 300}, "unlocks": ["acid"]},
	"heal_100": {"name": "Heartfelt", "desc": "Recover 100 health in one run", "check": {"run": "healed", "min": 100}, "unlocks": ["heartbeat"]},
	"candy_1000": {"name": "Snack Time", "desc": "Collect 1,000 candy (all runs)", "check": {"total": "candy", "min": 1000}, "unlocks": ["onion_ring"]},
	"silver_500": {"name": "Piggy Bank", "desc": "Earn 500 silver (all runs)", "check": {"total": "silver", "min": 500}, "unlocks": ["candy_basket"]},
	"chests_run_3": {"name": "Lucky Find", "desc": "Open 3 chests in one run", "check": {"run": "chests", "min": 3}, "unlocks": ["lucky_trophy"]},
	"kills_run_500": {"name": "Night Flight", "desc": "Defeat 500 monsters in one run", "check": {"run": "kills", "min": 500}, "unlocks": ["bat_swarm"]},
	"survive_5": {"name": "Night Owl", "desc": "Survive 5 minutes", "check": {"run": "seconds", "min": 300}, "unlocks": ["pumpkin_bomb"]},
	"survive_10": {"name": "Graveyard Shift", "desc": "Survive 10 minutes", "check": {"run": "seconds", "min": 600}, "unlocks": ["crimson_crypt"]},
	"survive_15": {"name": "Howl at the Moon", "desc": "Survive 15 minutes", "check": {"run": "seconds", "min": 900}, "unlocks": ["pocket_watch"]},
	"survive_20": {"name": "Swamp Legend", "desc": "Survive 20 minutes", "check": {"run": "seconds", "min": 1200}, "unlocks": []},
	"patch_8": {"name": "Out to Pasture", "desc": "Survive 8 minutes in The Graveyard", "check": {"run": "seconds", "min": 480, "stage": "graveyard"}, "unlocks": ["pumpkin_patch"]},
	"snow_8": {"name": "Cold Snap", "desc": "Survive 8 minutes in the Pumpkin Patch", "check": {"run": "seconds", "min": 480, "stage": "pumpkin_patch"}, "unlocks": ["snowbound"]},
	"sewer_8": {"name": "Down the Drain", "desc": "Survive 8 minutes in Snowbound Cemetery", "check": {"run": "seconds", "min": 480, "stage": "snowbound"}, "unlocks": ["sewers"]},
	"crypt_10": {"name": "Deeper Still", "desc": "Survive 10 minutes in The Sewers", "check": {"run": "seconds", "min": 600, "stage": "sewers"}, "unlocks": ["crypt_depths"]},
	"crypt_15": {"name": "Bossy", "desc": "Survive 15 minutes in Crypt Depths", "check": {"run": "seconds", "min": 900, "stage": "crypt_depths"}, "unlocks": []},
	"survive_30": {"name": "Dawn", "desc": "Survive 30 minutes", "check": {"run": "seconds", "min": 1800}, "unlocks": ["duplicator"]},
	"kills_1000": {"name": "Monster Masher", "desc": "Defeat 1,000 monsters (all runs)", "check": {"total": "kills", "min": 1000}, "unlocks": ["skull_toss"]},
	"kills_2000": {"name": "Brains!", "desc": "Defeat 2,000 monsters (all runs)", "check": {"total": "kills", "min": 2000}, "unlocks": []},
	"kills_run_1500": {"name": "Carpet Cleaner", "desc": "Defeat 1,500 monsters in one run", "check": {"run": "kills", "min": 1500}, "unlocks": ["airstrike"]},
	"level_25": {"name": "Bone to Pick", "desc": "Reach level 25", "check": {"run": "level", "min": 25}, "unlocks": ["grave_dirt"]},
	"level_50": {"name": "Heart of Gold", "desc": "Reach level 50", "check": {"run": "level", "min": 50}, "unlocks": ["heart_locket"]},
	"chests_10": {"name": "Treasure Hunter", "desc": "Open 10 chests (all runs)", "check": {"total": "chests", "min": 10}, "unlocks": ["candy_shotgun"]},
	"bosses_10": {"name": "Shadow Hunter", "desc": "Defeat 10 bosses (all runs)", "check": {"total": "bosses", "min": 10}, "unlocks": []},
	"candy_10000": {"name": "Sweet Tooth", "desc": "Collect 10,000 candy (all runs)", "check": {"total": "candy", "min": 10000}, "unlocks": []},
	"evolve_1": {"name": "Evolution!", "desc": "Evolve a weapon", "check": {"run": "evolutions", "min": 1}, "unlocks": ["grave_hand"]},
	"evolve_5": {"name": "Snail's Pace", "desc": "Make 5 different evolutions (all runs)", "check": {"evolved": 5}, "unlocks": []},
	"union_1": {"name": "Better Together", "desc": "Fuse a union", "check": {"run": "unions", "min": 1}, "unlocks": ["chain_lightning"]},
	"pumpkins_500": {"name": "Pumpkin Smasher", "desc": "Defeat 500 pumpkins (all runs)", "check": {"kind": "pumpkin", "min": 500}, "unlocks": []},
	"swamp_50": {"name": "Bog Diver", "desc": "Defeat 50 swamp things (all runs)", "check": {"kind": "swampthing", "min": 50}, "unlocks": ["tentacle"]},
	"skulls_1000": {"name": "Skull Collector", "desc": "Defeat 1,000 skulls (all runs)", "check": {"kind": "skull", "min": 1000}, "unlocks": ["skull_ring"]},
	"matt_10": {"name": "Lamplighter", "desc": "Survive 10 minutes as Matt", "check": {"run": "seconds", "min": 600, "char": "matt"}, "unlocks": ["street_lamp"]},
	"alex_10": {"name": "Stake Out", "desc": "Survive 10 minutes as Alex", "check": {"run": "seconds", "min": 600, "char": "alex"}, "unlocks": ["wood_stake"]},
	"jon_10": {"name": "Coin Flip", "desc": "Survive 10 minutes as Jon", "check": {"run": "seconds", "min": 600, "char": "jon"}, "unlocks": ["silver_coin"]},
	"silver_2000": {"name": "Big Spender", "desc": "Earn 2,000 silver (all runs)", "check": {"total": "silver", "min": 2000}, "unlocks": ["merchant_hat"]},
	"heal_500": {"name": "Bloodbath", "desc": "Recover 500 health in one run", "check": {"run": "healed", "min": 500}, "unlocks": ["blood_trail"]},
	"full_slots": {"name": "Fully Loaded", "desc": "Fill every weapon slot", "check": {"run": "weapons_full", "min": 1}, "unlocks": []},
	"walk_20k": {"name": "Restless Spirit", "desc": "Walk 20,000 steps (all runs)", "check": {"total": "distance", "min": 20000}, "unlocks": ["ghost_step"]},
}

# Permanent stat boosts bought with silver. Each rank adds `per_rank` to the
# hero's stats. Price of the next rank: cost * (rank + 1), plus 10% for every
# rank bought across the whole shop (so order matters a little, like VS).
const POWERUPS := {
	"might": {"name": "Might", "desc": "+5% damage", "icon": "tentacle", "stat": "might", "per_rank": 0.05, "max": 5, "cost": 40},
	"armor": {"name": "Armor", "desc": "-3% damage taken", "icon": "snail_lord", "stat": "armor", "per_rank": 0.03, "max": 3, "cost": 60},
	"max_health": {"name": "Max Health", "desc": "+10% max health", "icon": "heartbeat", "stat": "max_hp_mul", "per_rank": 0.10, "max": 3, "cost": 40},
	"recovery": {"name": "Recovery", "desc": "+0.2 health per second", "icon": "holy_cross", "stat": "regen", "per_rank": 0.2, "max": 5, "cost": 40},
	"cooldown": {"name": "Cooldown", "desc": "-2.5% weapon cooldown", "icon": "magic_tome", "stat": "cooldown", "per_rank": -0.025, "max": 2, "cost": 90},
	"area": {"name": "Area", "desc": "+5% weapon size", "icon": "sewer", "stat": "area", "per_rank": 0.05, "max": 2, "cost": 60},
	"speed": {"name": "Speed", "desc": "+10% projectile speed", "icon": "crosshair_new", "stat": "proj_speed", "per_rank": 0.10, "max": 2, "cost": 30},
	"duration": {"name": "Duration", "desc": "+15% effect duration", "icon": "clock", "stat": "duration", "per_rank": 0.15, "max": 2, "cost": 60},
	"amount": {"name": "Amount", "desc": "+1 projectile", "icon": "sparkle", "stat": "amount", "per_rank": 1, "max": 1, "cost": 500},
	"move_speed": {"name": "Move Speed", "desc": "+5% move speed", "icon": "ghost", "stat": "move", "per_rank": 0.05, "max": 2, "cost": 60},
	"magnet": {"name": "Magnet", "desc": "+25% pickup range", "icon": "vacusuck", "stat": "magnet", "per_rank": 0.25, "max": 2, "cost": 30},
	"luck": {"name": "Luck", "desc": "+10% luck", "icon": "trophy_small", "stat": "luck", "per_rank": 0.10, "max": 3, "cost": 60},
	"growth": {"name": "Growth", "desc": "+3% experience", "icon": "onion", "stat": "growth", "per_rank": 0.03, "max": 5, "cost": 90},
	"greed": {"name": "Greed", "desc": "+10% silver", "icon": "candybasket", "stat": "greed", "per_rank": 0.10, "max": 5, "cost": 30},
	"curse": {"name": "Curse", "desc": "+10% curse: harder, but more candy", "icon": "skull", "stat": "curse", "per_rank": 0.10, "max": 5, "cost": 160},
	"revival": {"name": "Revival", "desc": "Come back once per run", "icon": "heart", "stat": "revival", "per_rank": 1, "max": 1, "cost": 1000},
	# Heroes start with 5 weapon and 5 passive slots; these add the sixth.
	"weapon_slot": {"name": "Weapon Slot", "desc": "+1 weapon slot", "icon": "weapon_slot_icon", "stat": "weapon_slots", "per_rank": 1, "max": 1, "cost": 800},
	"passive_slot": {"name": "Passive Slot", "desc": "+1 passive slot", "icon": "passive_slot_icon", "stat": "passive_slots", "per_rank": 1, "max": 1, "cost": 600},
}
