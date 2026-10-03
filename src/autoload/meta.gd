extends Node
## Everything that outlives a run: silver, unlocks, feats, power-ups, lifetime
## totals and the collection. Saved on the device; when the arcade signs us
## in it also syncs to the account (see Bridge.load_save / Bridge.store_save).

signal changed

const SAVE_PATH := "user://profile_v2.json"

var silver := 0
var best_seconds := 0
var selected := "joe"
var stage := "graveyard"
var unlocked: Array = []    # heroes bought + content unlocked by feats
var feats: Array = []       # feats completed
var powerups := {}          # power-up id -> rank
var totals := {"kills": 0, "candy": 0, "chests": 0, "bosses": 0, "silver": 0, "distance": 0, "runs": 0}
var kinds := {}             # enemy -> defeated, all runs
var evolved: Array = []     # evolutions/unions ever made
var seen: Array = []        # weapons/passives ever picked up
var rev = null              # server revision of the account save; null before the first upload
var _sync_queued := false
var dev_unlock_all := false  # dev flag `unlockall`: everything open, nothing saved

func _enter_tree() -> void:
	dev_unlock_all = Bridge.flags().has("unlockall")

func _ready() -> void:
	_load()
	Bridge.signed_in.connect(_on_signed_in)

# ---------------------------------------------------------------- Queries

func is_unlocked(char_id: String) -> bool:
	if dev_unlock_all:
		return true
	var c: Dictionary = Db.CHARACTERS[char_id]
	if c.has("feat"):
		return feats.has(c.feat)
	return int(c.get("cost", 0)) == 0 or unlocked.has(char_id)

## Weapons, passives and stages marked `locked` need their feat first.
func content_unlocked(id: String) -> bool:
	if dev_unlock_all:
		return true
	return not Db.is_locked_content(id) or unlocked.has(id)

func powerup_rank(id: String) -> int:
	return int(powerups.get(id, 0))

func powerup_cost(id: String) -> int:
	var p: Dictionary = Db.POWERUPS[id]
	var bought := 0
	for k in powerups:
		bought += int(powerups[k])
	return int(p.cost * (powerup_rank(id) + 1) * (1.0 + 0.1 * bought))

## Stat bonuses from every power-up bought.
func powerup_stats() -> Dictionary:
	var out := {}
	for id in powerups:
		var p: Dictionary = Db.POWERUPS[id]
		out[p.stat] = out.get(p.stat, 0) + p.per_rank * int(powerups[id])
	return out

# ---------------------------------------------------------------- Spending

func buy_powerup(id: String) -> bool:
	var p: Dictionary = Db.POWERUPS[id]
	var cost := powerup_cost(id)
	if powerup_rank(id) >= int(p.max) or silver < cost:
		return false
	silver -= cost
	powerups[id] = powerup_rank(id) + 1
	save()
	return true

## Gives back everything spent on power-ups (prices are recomputed from scratch).
func refund_powerups() -> void:
	var ranks := powerups.duplicate()
	var refund := 0
	powerups = {}
	# Replay the purchases in a fixed order to total what they cost.
	for id in Db.POWERUPS:
		for r in int(ranks.get(id, 0)):
			refund += powerup_cost(id)
			powerups[id] = powerup_rank(id) + 1
	powerups = {}
	silver += refund
	save()

func try_unlock(char_id: String) -> bool:
	var c: Dictionary = Db.CHARACTERS[char_id]
	if is_unlocked(char_id) or c.has("feat") or silver < int(c.cost):
		return false
	silver -= int(c.cost)
	unlocked.append(char_id)
	save()
	return true

# ---------------------------------------------------------------- After a run

## `r`: run summary from Run (seconds, kills, level, chests, bosses, candy,
## healed, evolutions, unions, weapons_full, silver, distance, char, kinds,
## evolved, seen). Returns what changed, for the results screen.
func finish_run(r: Dictionary) -> Dictionary:
	var is_best: bool = int(r.seconds) > best_seconds
	best_seconds = maxi(best_seconds, int(r.seconds))
	silver += int(r.silver)
	totals.runs += 1
	for k in ["kills", "candy", "chests", "bosses", "silver", "distance"]:
		totals[k] = int(totals.get(k, 0)) + int(r.get(k, 0))
	for k in r.kinds:
		kinds[k] = int(kinds.get(k, 0)) + int(r.kinds[k])
	for id in r.evolved:
		if not evolved.has(id):
			evolved.append(id)
	for id in r.seen:
		if not seen.has(id):
			seen.append(id)
	var new_feats := []
	var new_unlocks := []
	for f in Db.FEATS:
		if feats.has(f) or not _feat_met(Db.FEATS[f].check, r):
			continue
		feats.append(f)
		new_feats.append(f)
		for id in Db.FEATS[f].unlocks:
			if not unlocked.has(id):
				unlocked.append(id)
				new_unlocks.append(id)
		for c in Db.CHARACTERS:
			if Db.CHARACTERS[c].get("feat") == f:
				new_unlocks.append(c)
	save()
	return {"best": is_best, "feats": new_feats, "unlocks": new_unlocks}

func _feat_met(c: Dictionary, r: Dictionary) -> bool:
	if c.has("run"):
		if c.has("char") and r.char != c.char:
			return false
		return float(r.get(c.run, 0)) >= float(c.min)
	if c.has("total"):
		return float(totals.get(c.total, 0)) >= float(c.min)
	if c.has("kind"):
		return int(kinds.get(c.kind, 0)) >= int(c.min)
	if c.has("evolved"):
		return evolved.size() >= int(c.evolved)
	return false

# ---------------------------------------------------------------- Saving

func to_dict() -> Dictionary:
	return {"version": 1, "silver": silver, "best": best_seconds, "selected": selected, "stage": stage,
		"unlocked": unlocked, "feats": feats, "powerups": powerups, "totals": totals, "kinds": kinds,
		"evolved": evolved, "seen": seen}

func _from_dict(d: Dictionary) -> void:
	silver = int(d.get("silver", 0))
	best_seconds = int(d.get("best", 0))
	selected = str(d.get("selected", "joe"))
	stage = str(d.get("stage", "graveyard"))
	unlocked = d.get("unlocked", [])
	feats = d.get("feats", [])
	powerups = d.get("powerups", {})
	var t: Dictionary = d.get("totals", {})
	for k in totals:
		totals[k] = int(t.get(k, 0))
	kinds = d.get("kinds", {})
	evolved = d.get("evolved", [])
	seen = d.get("seen", [])
	if not Db.CHARACTERS.has(selected) or not is_unlocked(selected):
		selected = "joe"
	if not Db.STAGES.has(stage) or not content_unlocked(stage):
		stage = "graveyard"

func save() -> void:
	if dev_unlock_all:
		changed.emit()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict()))
	changed.emit()
	_queue_sync()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if d is Dictionary:
		_from_dict(d)

# Account sync: one upload at a time, batched to the end of the frame.
func _queue_sync() -> void:
	if not Bridge.is_signed_in() or _sync_queued:
		return
	_sync_queued = true
	_push.call_deferred()

func _push() -> void:
	_sync_queued = false
	Bridge.store_save(to_dict(), rev, func(code, data):
		if code == 200 and data is Dictionary:
			rev = data.get("revision", rev)
		elif code == 409 and data is Dictionary:
			# Another device saved first: take theirs, then keep whatever is better.
			_merge_remote(data.get("save"), data.get("revision")))

func _on_signed_in() -> void:
	Bridge.load_save(func(code, data):
		if code == 200 and data is Dictionary:
			_merge_remote(data.get("save"), data.get("revision")))

## Combines the account save with this device's: unlocks and feats are
## unioned, counters take the larger value, silver takes the account's.
func _merge_remote(remote, remote_rev) -> void:
	rev = int(remote_rev) if remote_rev != null else null
	if not (remote is Dictionary) or remote.is_empty():
		save()  # first sign-in: upload what this device has
		return
	var mine := to_dict()
	_from_dict(remote)
	for id in mine.unlocked:
		if not unlocked.has(id): unlocked.append(id)
	for id in mine.feats:
		if not feats.has(id): feats.append(id)
	for id in mine.evolved:
		if not evolved.has(id): evolved.append(id)
	for id in mine.seen:
		if not seen.has(id): seen.append(id)
	for id in mine.powerups:
		powerups[id] = maxi(powerup_rank(id), int(mine.powerups[id]))
	for k in totals:
		totals[k] = maxi(int(totals[k]), int(mine.totals.get(k, 0)))
	for k in mine.kinds:
		kinds[k] = maxi(int(kinds.get(k, 0)), int(mine.kinds[k]))
	best_seconds = maxi(best_seconds, int(mine.best))
	save()
