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
var quests: Array = []      # map quests completed (ids from quests.gd)
var cleared: Array = []     # maps survived to 20:00: "stage", or "stage+nm" on Nightmare
var reapers: Array = []     # maps where the Reaper was slain, same keys
var nightmare := false      # play Nightmare (on maps where it's unlocked)
const FIRST_CLEAR_SILVER := 500
const FIRST_REAPER_SILVER := 1000
var rev = null              # server revision of the account save; null before the first upload
var _sync_queued := false
var dev_unlock_all := false  # dev flag `unlockall`: everything open, nothing saved

func _enter_tree() -> void:
	dev_unlock_all = Bridge.flags().has("unlockall")

func _ready() -> void:
	# Keeps saving while a menu has the game paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	# Map quests: the run's map only, checked against what the team did.
	var new_quests := []
	var crowned := false
	var st: Dictionary = r.get("quest", {})
	var stage_id := str(r.get("stage", ""))
	var list := Db.quests_for(stage_id)
	for q in list:
		if quests.has(q.id) or not Db.quest_met(q.check, st):
			continue
		quests.append(q.id)
		new_quests.append(q.id)
		silver += int(q.silver)
	if not new_quests.is_empty() and is_crowned(stage_id):
		crowned = true
		silver += Db.QUEST_CROWN_SILVER
	# 20:00 and the Reaper, once each per map and mode.
	var key := stage_id + ("+nm" if r.get("nightmare", false) else "")
	var first_clear := false
	var first_reaper := false
	if r.get("cleared", false) and not cleared.has(key):
		cleared.append(key)
		first_clear = true
		silver += FIRST_CLEAR_SILVER
	if int(r.get("reapers", 0)) > 0 and not reapers.has(key):
		reapers.append(key)
		first_reaper = true
		silver += FIRST_REAPER_SILVER
	save()
	return {"best": is_best, "feats": new_feats, "unlocks": new_unlocks, "quests": new_quests, "crowned": crowned,
		"first_clear": first_clear, "first_reaper": first_reaper, "nightmare": r.get("nightmare", false)}

## Nightmare opens on a map once it's been survived to 20:00.
func nightmare_unlocked(stage_id: String) -> bool:
	return cleared.has(stage_id) or dev_unlock_all

## Whether the next solo run on this map is Nightmare.
func nightmare_on(stage_id: String) -> bool:
	return nightmare and nightmare_unlocked(stage_id)

## Every quest of the map done.
func is_crowned(stage_id: String) -> bool:
	var list := Db.quests_for(stage_id)
	return not list.is_empty() and list.all(func(q): return quests.has(q.id))

func _feat_met(c: Dictionary, r: Dictionary) -> bool:
	if c.has("run"):
		if c.has("char") and r.char != c.char:
			return false
		if c.has("stage") and r.get("stage", "") != c.stage:
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
		"evolved": evolved, "seen": seen, "quests": quests, "cleared": cleared, "reapers": reapers, "nightmare": nightmare}

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
	quests = d.get("quests", [])
	cleared = d.get("cleared", [])
	reapers = d.get("reapers", [])
	nightmare = bool(d.get("nightmare", false))
	if not Db.CHARACTERS.has(selected) or not is_unlocked(selected):
		selected = "joe"
	if not Db.STAGES.has(stage) or not content_unlocked(stage):
		stage = "graveyard"

func save() -> void:
	if dev_unlock_all:
		changed.emit()
		return
	dirty = true
	_change_gen += 1
	_write_local()
	changed.emit()
	_queue_sync()

func _write_local() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		var d := to_dict()
		d["_dirty"] = dirty
		d["_rev"] = rev
		f.store_string(JSON.stringify(d))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if d is Dictionary:
		_from_dict(d)
		dirty = bool(d.get("_dirty", false))
		rev = d.get("_rev")

# Account sync. Every change marks the profile dirty (remembered on the
# device, so it survives a reload or a run played offline). Uploads go one at
# a time and retry with backoff until the server has them. A save made on
# another device meanwhile comes back as a 409 and is merged in.

var dirty := false
var _uploading := false
var _change_gen := 0      # bumps on every change, to tell if one came in mid-upload
var _retry_in := 0.0      # seconds until the next attempt, 0 = none waiting
var _backoff := 2.0
var _loaded_remote := false

func _queue_sync() -> void:
	if not Bridge.is_signed_in() or not _loaded_remote or _sync_queued or _uploading:
		return
	_sync_queued = true
	_push.call_deferred()

func _process(delta: float) -> void:
	if _retry_in > 0.0:
		_retry_in -= delta
		if _retry_in <= 0.0:
			_retry_in = 0.0
			if not _loaded_remote:
				_on_signed_in()
			elif dirty:
				_queue_sync()

func _retry_later() -> void:
	_retry_in = _backoff
	_backoff = minf(_backoff * 2.0, 60.0)

func _push() -> void:
	_sync_queued = false
	if not dirty or _uploading:
		return
	_uploading = true
	var gen := _change_gen
	Bridge.store_save(to_dict(), rev, func(code, data):
		_uploading = false
		if code == 200 and data is Dictionary:
			rev = data.get("revision", rev)
			_backoff = 2.0
			if gen == _change_gen:
				dirty = false
				_write_local()
			else:
				_queue_sync()  # something changed while uploading
		elif code == 409 and data is Dictionary:
			# Another device saved first: merge theirs in, then upload the result.
			_merge_remote(data.get("save"), data.get("revision"))
		else:
			_retry_later())

func _on_signed_in() -> void:
	Bridge.load_save(func(code, data):
		if code == 200 and data is Dictionary:
			_loaded_remote = true
			_backoff = 2.0
			_merge_remote(data.get("save"), data.get("revision"))
		else:
			_retry_later())

## Combines the account save with this device's: unlocks and feats are
## unioned, counters take the larger value. Silver is the account's unless
## this device has changes the account hasn't seen yet.
func _merge_remote(remote, remote_rev) -> void:
	rev = int(remote_rev) if remote_rev != null else null
	if not (remote is Dictionary) or remote.is_empty():
		save()  # first sign-in: upload what this device has
		return
	var mine := to_dict()
	var had_changes := dirty
	_from_dict(remote)
	if had_changes:
		silver = int(mine.silver)
	for id in mine.unlocked:
		if not unlocked.has(id): unlocked.append(id)
	for id in mine.feats:
		if not feats.has(id): feats.append(id)
	for id in mine.evolved:
		if not evolved.has(id): evolved.append(id)
	for id in mine.seen:
		if not seen.has(id): seen.append(id)
	for id in mine.get("quests", []):
		if not quests.has(id): quests.append(id)
	for id in mine.get("cleared", []):
		if not cleared.has(id): cleared.append(id)
	for id in mine.get("reapers", []):
		if not reapers.has(id): reapers.append(id)
	for id in mine.powerups:
		powerups[id] = maxi(powerup_rank(id), int(mine.powerups[id]))
	for k in totals:
		totals[k] = maxi(int(totals[k]), int(mine.totals.get(k, 0)))
	for k in mine.kinds:
		kinds[k] = maxi(int(kinds.get(k, 0)), int(mine.kinds[k]))
	best_seconds = maxi(best_seconds, int(mine.best))
	# Upload only if the merge gave the account something new.
	if to_dict().hash() != remote.hash() or had_changes:
		save()
	else:
		dirty = false
		_write_local()
		changed.emit()
