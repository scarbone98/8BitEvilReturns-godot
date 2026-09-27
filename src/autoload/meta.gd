extends Node
## Progress that outlives a run: silver, unlocked characters, best time.
## Saved locally; when the arcade page signs us in, the server copy wins for
## silver and unlocks (the server only stores those two).

signal changed

const SAVE_PATH := "user://profile.json"

var silver := 0
var unlocked: Array = []  # character display names, as the server stores them
var best_seconds := 0
var selected := "joe"

func _ready() -> void:
	_load()
	Bridge.signed_in.connect(_on_signed_in)

func is_unlocked(id: String) -> bool:
	var c: Dictionary = Db.CHARACTERS[id]
	return int(c.cost) == 0 or unlocked.has(c.name)

func add_silver(amount: int) -> void:
	silver += amount
	_save()
	Bridge.save_player_data(silver, unlocked)

func try_unlock(id: String) -> bool:
	var c: Dictionary = Db.CHARACTERS[id]
	if is_unlocked(id) or silver < int(c.cost):
		return false
	silver -= int(c.cost)
	unlocked.append(c.name)
	_save()
	# The server checks and deducts the cost itself, then we take its numbers.
	Bridge.unlock_character(c.name, int(c.cost), func(code, data):
		if code == 200 and data is Dictionary:
			_apply_server(data.get("playerData", {})))
	return true

func record_run(seconds: int) -> bool:
	var is_best := seconds > best_seconds
	best_seconds = maxi(best_seconds, seconds)
	_save()
	return is_best

func _on_signed_in() -> void:
	Bridge.fetch_player_data(func(code, data):
		if code == 200 and data is Dictionary:
			_apply_server(data))

func _apply_server(d: Dictionary) -> void:
	if d.has("silverAmount"):
		silver = int(d.silverAmount)
	if d.get("unlockedCharacters") is Array:
		unlocked = d.unlockedCharacters
	_save()
	changed.emit()

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"silver": silver, "unlocked": unlocked, "best": best_seconds, "selected": selected}))
	changed.emit()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if d is Dictionary:
		silver = int(d.get("silver", 0))
		unlocked = d.get("unlocked", [])
		best_seconds = int(d.get("best", 0))
		selected = str(d.get("selected", "joe"))
		if not Db.CHARACTERS.has(selected):
			selected = "joe"

func save() -> void:
	_save()
