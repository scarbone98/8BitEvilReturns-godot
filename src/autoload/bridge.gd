extends Node
## Talks to the Scareathon arcade page that hosts this game in an iframe.
## Same protocol the Unity build used, so the site needs no changes:
##   game -> page  {type: "unityReady"}
##   page -> game  {type: "SCARATHON_USER", userId, accessToken, apiBaseUrl}
##   game -> page  {type: "PLAYER_DIED", score}
## Outside a browser (editor, desktop) everything here is a no-op.

signal signed_in

const API := "/8bitevilreturns"

var user_id := ""
var access_token := ""
var api_base := ""
var _on_message: JavaScriptObject  # kept alive so JS can keep calling it

## Dev flags from the command line (`-- --autoplay --give=fireball`) or the
## page URL (`?autoplay&give=fireball`). Values are strings; bare flags are "1".
func flags() -> Dictionary:
	var out := {}
	var parts: Array = []
	for a in OS.get_cmdline_user_args():
		parts.append(a.trim_prefix("--"))
	if is_web():
		var q = JavaScriptBridge.eval("location.search")
		if q is String and q.length() > 1:
			parts.append_array(q.substr(1).split("&"))
	for part in parts:
		var kv: PackedStringArray = part.split("=", true, 1)
		out[kv[0]] = kv[1].uri_decode() if kv.size() > 1 else "1"
	return out

func is_web() -> bool:
	return OS.has_feature("web")

func is_signed_in() -> bool:
	return user_id != "" and api_base != ""

func _ready() -> void:
	if not is_web():
		return
	_on_message = JavaScriptBridge.create_callback(_handle_message)
	var window := JavaScriptBridge.get_interface("window")
	window.addEventListener("message", _on_message)
	_post_to_page({"type": "unityReady"})

func _handle_message(args: Array) -> void:
	var event: JavaScriptObject = args[0]
	var data = event.data
	if data == null or typeof(data) != TYPE_OBJECT:
		return
	if str(data.type) != "SCARATHON_USER":
		return
	user_id = str(data.userId)
	access_token = str(data.accessToken)
	api_base = str(data.apiBaseUrl).trim_suffix("/")
	signed_in.emit()

func _post_to_page(msg: Dictionary) -> void:
	if not is_web():
		return
	# JSON round-trip gives the page a plain JS object.
	JavaScriptBridge.eval("window.parent && window.parent.postMessage(%s, '*')" % JSON.stringify(msg))

# ---------------------------------------------------------------- API

func report_death(seconds: int) -> void:
	_post_to_page({"type": "PLAYER_DIED", "score": seconds})

func submit_run(seconds: int, kills: int, candy: int) -> void:
	if not is_signed_in():
		return
	_request("%s%s/runs" % [api_base, API], HTTPClient.METHOD_POST,
		{"runTimeSeconds": seconds, "kills": kills, "candyCollected": candy})

func fetch_player_data(done: Callable) -> void:
	if not is_signed_in():
		return
	_request("%s%s/getUserData?userId=%s" % [api_base, API, user_id], HTTPClient.METHOD_GET, null, done)

func save_player_data(silver: int, unlocked: Array) -> void:
	if not is_signed_in():
		return
	_request("%s%s/setUserData" % [api_base, API], HTTPClient.METHOD_POST,
		{"userId": user_id, "silverAmount": silver, "unlockedCharacters": unlocked})

func unlock_character(character_name: String, cost: int, done: Callable) -> void:
	if not is_signed_in():
		return
	_request("%s%s/unlockCharacter?userId=%s" % [api_base, API, user_id], HTTPClient.METHOD_POST,
		{"characterName": character_name, "cost": cost}, done)

func _request(url: String, method: int, body, done := Callable()) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if access_token != "":
		headers.append("Authorization: Bearer " + access_token)
	http.request_completed.connect(func(_result, code, _h, bytes: PackedByteArray):
		http.queue_free()
		if done.is_valid():
			var parsed = JSON.parse_string(bytes.get_string_from_utf8())
			done.call(code, parsed if parsed != null else {}))
	http.request(url, headers, method, "" if body == null else JSON.stringify(body))
