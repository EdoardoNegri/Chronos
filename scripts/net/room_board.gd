class_name RoomBoard
extends Node
## The list of open rooms, kept as issues in the game's own GitHub repository (REPOSITORY): one open
## issue per room, titled "[Room] ...", holding what a player needs to reach it (see entry_for).
## There is no server of our own. Other issues in the repository are left alone.
##
## - A host posts its room once its address is known (post), says every HEARTBEAT_SECONDS that it
##   is still there (touch), and closes the issue when it leaves (remove). See RoomListing.
## - Players list the open issues (refresh) to fill the room browser. A room whose host has not
##   said it is there for STALE_SECONDS (their game crashed, say) is left out and closed.
## - A room whose host cannot be reached is closed by the player who failed to reach it; if the host
##   is in fact there, its next heartbeat opens the issue again.
##
## Writing issues needs a GitHub token, read from TOKEN_PATH, which is not in the repository and
## goes into exported games (see export_presets.cfg). It must only be allowed to read and write
## the issues of REPOSITORY, never its code.

signal rooms_changed
## A request to GitHub failed; error_text says why.
signal failed

## The repository the rooms are kept in, as "owner/name".
const REPOSITORY := "EdoardoNegri/Chronos"
const TOKEN_PATH := "res://secrets/github_token.txt"
const API := "https://api.github.com"
## Room issues start their title with this, so they are easy to tell apart on GitHub.
const TITLE_PREFIX := "[Room] "
## Issues holding rooms start their body with this, so anything else in the repository is left out.
const MARKER := "chronos-room"
const FORMAT := 1
const REQUEST_SECONDS := 15.0
## How often a host says its room is still there, and after how long without that a room is gone.
const HEARTBEAT_SECONDS := 5 * 60
const STALE_SECONDS := 20 * 60

## Whether boards read the token file. The tests turn it off for the whole run (see
## test/hooks/pre_run.gd), so no test ever writes to the real list.
static var use_token_file := true

## The open rooms from the last refresh, as shown in the room browser. Their ids are the issue
## numbers, which are unique (the host's own room ids are not: see entry_for).
var rooms := RoomDirectory.new()
## Why the last request failed, in words ("" if it did not).
var error_text := ""
## Whether a refresh is under way.
var refreshing := false
## Sends a request to GitHub: (method: HTTPClient.Method, path: String, body: Dictionary) ->
## {"code": int, "data": Variant, "headers": PackedStringArray}. Tests give a fake GitHub.
var transport: Callable
var token := ""
## The time now, in seconds (tests give their own clock).
var clock: Callable = func() -> int: return int(Time.get_unix_time_from_system())

var _entries: Dictionary[StringName, Dictionary] = {}


func _init() -> void:
	transport = _send
	token = load_token()


## The token in TOKEN_PATH, or "" if there is none.
static func load_token() -> String:
	if not use_token_file or not FileAccess.file_exists(TOKEN_PATH):
		return ""
	return FileAccess.get_file_as_string(TOKEN_PATH).strip_edges()


## Whether there is a token to reach the list with.
func is_set_up() -> bool:
	return not token.is_empty()


## Lists the open rooms again (rooms_changed, or failed). Rooms whose host has gone quiet are
## left out and closed.
func refresh() -> void:
	if refreshing:
		return
	if not is_set_up():
		_fail("The room list is not set up: the game has no GitHub token (%s)." % TOKEN_PATH)
		return
	refreshing = true
	var result: Dictionary = await transport.call(HTTPClient.METHOD_GET, "/issues?state=open&per_page=100", {})
	refreshing = false
	if not _ok(result, "Could not get the room list"):
		return
	error_text = ""
	_entries.clear()
	var now: int = clock.call()
	var snapshot: Array[Dictionary] = []
	var issues: Variant = result["data"]
	for issue: Variant in issues if issues is Array else []:
		var entry := read_issue(issue)
		if entry.is_empty():
			continue
		if now - int(entry["alive"]) > STALE_SECONDS:
			# Nobody waits for it: the room is already left out of the list.
			@warning_ignore("missing_await")
			_close_quietly(entry["issue"])
			continue
		var id := StringName(str(entry["issue"]))
		_entries[id] = entry
		snapshot.append(_room_of(id, entry).to_dict())
	rooms.replace_from_snapshot(snapshot)
	rooms_changed.emit()


## What a listed room needs to be reached: {"issue", "address", "room_id" (the room's id in its
## host's game), "room_name", "host_name", "locked", "custom_cards", "local", "alive"}, or {} if the
## room is not in the list.
func entry_for(room_id: StringName) -> Dictionary:
	return _entries.get(room_id, {})


## Puts a room in the list, reachable at `address` (`local` if only on the host's network).
## Returns the issue number, or 0 if it could not be posted (failed says why).
func post(room: RoomInfo, address: String, local := false) -> int:
	if not is_set_up():
		_fail("The room list is not set up: the game has no GitHub token.")
		return 0
	var body := {
		"title": "%s%s (%s)" % [TITLE_PREFIX, room.room_name, room.host_name],
		"body": write_issue_body(room, address, local, clock.call()),
	}
	var result: Dictionary = await transport.call(HTTPClient.METHOD_POST, "/issues", body)
	if not _ok(result, "Could not add the room to the list"):
		return 0
	var data: Variant = result["data"]
	return int((data as Dictionary).get("number", 0)) if data is Dictionary else 0


## Says a listed room is still there, and opens its issue again if someone closed it. Returns
## whether that worked.
func touch(issue: int, room: RoomInfo, address: String, local := false) -> bool:
	if issue <= 0 or not is_set_up():
		return false
	var body := {"state": "open", "body": write_issue_body(room, address, local, clock.call())}
	var result: Dictionary = await transport.call(HTTPClient.METHOD_PATCH, "/issues/%d" % issue, body)
	return _ok(result, "Could not keep the room in the list")


## Takes a room off the list. Returns whether that worked.
func remove(issue: int) -> bool:
	if issue <= 0 or not is_set_up():
		return false
	var id := StringName(str(issue))
	if _entries.has(id):
		_entries.erase(id)
		rooms.remove_room(id)
		rooms_changed.emit()
	var result: Dictionary = await transport.call(HTTPClient.METHOD_PATCH, "/issues/%d" % issue, {"state": "closed"})
	return _ok(result, "Could not take the room off the list")


## The text of a room's issue: a marker line, then the room as JSON. `alive` is when the host last
## said the room is there.
static func write_issue_body(room: RoomInfo, address: String, local := false, alive := 0) -> String:
	var data := {
		"format": FORMAT,
		"address": address,
		"room_id": str(room.id),
		"room_name": room.room_name,
		"host_name": room.host_name,
		"locked": room.locked,
		"custom_cards": room.custom_cards,
		"local": local,
		"alive": alive,
	}
	return "%s\n%s" % [MARKER, JSON.stringify(data)]


## A listed room from an issue as GitHub sends it, or {} if the issue is not a room.
static func read_issue(issue: Variant) -> Dictionary:
	if not issue is Dictionary or (issue as Dictionary).has("pull_request"):
		return {}
	var text := str(issue.get("body", "")).strip_edges()
	if not text.begins_with(MARKER):
		return {}
	var json := JSON.new()
	if json.parse(text.trim_prefix(MARKER).strip_edges()) != OK or not json.data is Dictionary:
		return {}
	var data: Dictionary = json.data
	var address := str(data.get("address", ""))
	var room_id := str(data.get("room_id", ""))
	if address.is_empty() or room_id.is_empty():
		return {}
	return {
		"issue": int(issue.get("number", 0)),
		"address": address,
		"room_id": room_id,
		"room_name": str(data.get("room_name", "Room")).left(RoomDirectory.MAX_NAME_LENGTH),
		"host_name": str(data.get("host_name", "Player")).left(PlayerProfile.MAX_NAME_LENGTH),
		"locked": bool(data.get("locked", false)),
		"custom_cards": bool(data.get("custom_cards", false)),
		"local": bool(data.get("local", false)),
		"alive": int(data.get("alive", 0)),
	}


## The room browser's view of a listed room.
static func _room_of(id: StringName, entry: Dictionary) -> RoomInfo:
	var room := RoomInfo.new(id, entry["room_name"], entry["host_name"], 1, RoomDirectory.PLAYERS, false, entry["custom_cards"])
	room.locked = entry["locked"]
	return room


## Closes a room nobody is waiting on the answer for.
func _close_quietly(issue: int) -> void:
	await transport.call(HTTPClient.METHOD_PATCH, "/issues/%d" % issue, {"state": "closed"})


func _ok(result: Dictionary, what: String) -> bool:
	var code := int(result.get("code", 0))
	if code >= 200 and code < 300:
		return true
	var headers: PackedStringArray = result.get("headers", PackedStringArray())
	if (code == 403 or code == 429) and _header(headers, "x-ratelimit-remaining") == "0":
		_fail("%s: GitHub's limit of requests for the room list was reached. Try again in a few minutes." % what)
		return false
	match code:
		0:
			_fail("%s: GitHub could not be reached." % what)
		401, 403:
			_fail("%s: GitHub refused the game's token (%d)." % [what, code])
		404:
			_fail("%s: the repository %s was not found, or the token cannot see it." % [what, REPOSITORY])
		_:
			_fail("%s (GitHub answered %d)." % [what, code])
	return false


func _fail(message: String) -> void:
	error_text = message
	failed.emit()


## The value of a response header, or "".
static func _header(headers: PackedStringArray, header_name: String) -> String:
	var prefix := header_name.to_lower() + ":"
	for header in headers:
		if header.to_lower().begins_with(prefix):
			return header.substr(prefix.length()).strip_edges()
	return ""


## Sends a request to the GitHub API for REPOSITORY.
func _send(method: HTTPClient.Method, path: String, body: Dictionary) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = REQUEST_SECONDS
	add_child(request)
	var headers := PackedStringArray([
		"Accept: application/vnd.github+json",
		"Authorization: Bearer " + token,
		"X-GitHub-Api-Version: 2022-11-28",
		"User-Agent: Chronos-game",
		"Content-Type: application/json",
	])
	var url := "%s/repos/%s%s" % [API, REPOSITORY, path]
	var payload := "" if body.is_empty() else JSON.stringify(body)
	if request.request(url, headers, method, payload) != OK:
		request.queue_free()
		return {"code": 0, "data": null, "headers": PackedStringArray()}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"code": 0, "data": null, "headers": PackedStringArray()}
	var text := (response[3] as PackedByteArray).get_string_from_utf8()
	return {"code": response[1], "data": JSON.parse_string(text) if not text.is_empty() else null, "headers": response[2]}
