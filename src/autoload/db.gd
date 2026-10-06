extends Node
## Every piece of game content, gathered from src/data/*.gd. To add a weapon,
## passive, enemy, hero, stage, feat or power-up, edit the matching data file;
## the run code reads these tables and never hard-codes content.

const _Sheets := preload("res://src/data/sheets.gd")
const _Weapons := preload("res://src/data/weapons.gd")
const _Passives := preload("res://src/data/passives.gd")
const _Characters := preload("res://src/data/characters.gd")
const _Enemies := preload("res://src/data/enemies.gd")
const _Stages := preload("res://src/data/stages.gd")
const _Progression := preload("res://src/data/progression.gd")
const _Quests := preload("res://src/data/quests.gd")

const SHEETS: Dictionary = _Sheets.SHEETS
const WEAPONS: Dictionary = _Weapons.WEAPONS
const WEAPON_DEFAULTS: Dictionary = _Weapons.WEAPON_DEFAULTS
const PASSIVES: Dictionary = _Passives.PASSIVES
const ELIXIRS: Dictionary = _Passives.ELIXIRS
const MAX_WEAPONS: int = _Passives.MAX_WEAPONS
const MAX_PASSIVES: int = _Passives.MAX_PASSIVES
const CHARACTERS: Dictionary = _Characters.CHARACTERS
const ENEMIES: Dictionary = _Enemies.ENEMIES
const CANDY: Array = _Enemies.CANDY
const STAGES: Dictionary = _Stages.STAGES
const PACING: Array = _Stages.PACING
const ROLE_WEIGHTS: Dictionary = _Stages.ROLE_WEIGHTS
const QUESTS: Dictionary = _Quests.QUESTS
const QUEST_CROWN_SILVER: int = _Quests.CROWN_SILVER
const FEATS: Dictionary = _Progression.FEATS
const POWERUPS: Dictionary = _Progression.POWERUPS

# ---------------------------------------------------------------- Helpers
var _tex_cache := {}
var _sheet_cache := {}

func tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		_tex_cache[name] = load("res://assets/sprites/%s.png" % name)
	return _tex_cache[name]

## A sheet entry plus its texture (_tex) and frame size (_w, _h).
func sheet(id: String) -> Dictionary:
	if not _sheet_cache.has(id):
		var s: Dictionary = SHEETS[id].duplicate()
		var t := tex(s.path)
		s["_tex"] = t
		s["_w"] = t.get_width() / int(s.frames)
		s["_h"] = t.get_height()
		_sheet_cache[id] = s
	return _sheet_cache[id]

## Source rect for a frame of a sheet at time `t` (seconds).
func frame_rect(s: Dictionary, t: float) -> Rect2:
	var f := int(t * float(s.fps)) % int(s.frames)
	return Rect2(f * s._w, 0, s._w, s._h)

var _icon_cache := {}

func icon_texture(id: String) -> Texture2D:
	# Animated 64x64 sheets become their first frame; plain icons load directly.
	if not SHEETS.has(id):
		return tex(id)
	if not _icon_cache.has(id):
		var s := sheet(id)
		var a := AtlasTexture.new()
		a.atlas = s._tex
		a.region = Rect2(0, 0, s._w, s._h)
		_icon_cache[id] = a
	return _icon_cache[id]

func upgrade_def(id: String) -> Dictionary:
	if WEAPONS.has(id): return WEAPONS[id]
	if PASSIVES.has(id): return PASSIVES[id]
	return ELIXIRS.get(id, {})

func weapon_max_level(id: String) -> int:
	return WEAPONS[id].get("levels", []).size() + 1

## Which feat (if any) unlocks this weapon, passive or stage.
var _unlocked_by := {}

func _ready() -> void:
	for f in FEATS:
		for id in FEATS[f].unlocks:
			_unlocked_by[id] = f

func feat_for(id: String) -> String:
	return _unlocked_by.get(id, "")

func is_locked_content(id: String) -> bool:
	var d: Dictionary = WEAPONS.get(id, PASSIVES.get(id, STAGES.get(id, {})))
	return d.get("locked", false)

## Base weapons only (no evolutions or unions).
## Weapons a co-op guest simulates itself so they fire the instant it does
## (damage still comes from the host). Ones that pick random targets would
## disagree with the host, so those stay host-drawn.
const PREDICTED_BEHAVIORS := ["shooter", "slash", "boomerang", "orbit", "aura", "nova", "summon", "seeker", "trail", "chain"]

func is_predicted(def: Dictionary) -> bool:
	var b: String = def.get("behavior", "")
	if b == "strike":
		return def.get("target") == "nearest" and not def.has("warn")
	return b in PREDICTED_BEHAVIORS

func base_weapons() -> Array:
	return WEAPONS.keys().filter(func(id): return not WEAPONS[id].get("evolution", false))

## Where an evolution or union comes from: [weapon, passive or weapon, "evolve"|"union"].
func recipe_for(id: String) -> Array:
	for w in WEAPONS:
		var d: Dictionary = WEAPONS[w]
		if d.has("evolve") and d.evolve.into == id:
			return [w, d.evolve.with, "evolve"]
		if d.get("union") is Dictionary and d.union.into == id:
			return [w, d.union.with, "union"]
	return []

## The quests of a map (empty if it has none).
func quests_for(stage_id: String) -> Array:
	return QUESTS.get(stage_id, {}).get("list", [])

## [have, need] for a quest check against a run's quest state (see
## Run.quest_state): whole numbers, done when have >= need.
func quest_progress(check: Dictionary, st: Dictionary) -> Array:
	if check.has("relic"):
		return [1 if st.get("relic", false) else 0, 1]
	if check.has("boss"):
		return [1 if st.get("boss_kinds", {}).has(check.boss) else 0, 1]
	if check.has("kind"):
		return [int(st.get("team_kinds", {}).get(check.kind, 0)), int(check.min)]
	if check.has("bosses"):
		return [int(st.get("bosses", 0)), int(check.bosses)]
	if check.has("run"):
		return [int(st.get(check.run, 0)), int(check.min)]
	return [0, 1]

func quest_met(check: Dictionary, st: Dictionary) -> bool:
	var p := quest_progress(check, st)
	return p[0] >= p[1]

