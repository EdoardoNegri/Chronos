extends RefCounted
## Stands in for the GitHub repository that keeps the room list (see RoomBoard), so tests never
## reach the real one. It keeps issues in memory and answers the few requests a RoomBoard sends.

var issues: Array[Dictionary] = []
## When true, every request fails as if GitHub could not be reached.
var down := false
## Every request sent, as [method, path].
var requests: Array = []

var _next_number := 1


## A board that talks to this fake GitHub.
func make_board() -> RoomBoard:
	var board := RoomBoard.new()
	board.token = "test-token"
	board.transport = send
	# A callable does not keep this alive, so the board does.
	board.set_meta(&"fake_github", self)
	return board


## Puts a room in the list as a host would, and returns its issue number. Its host last said it
## is there at `alive` (now, by default).
func add_room(room: RoomInfo, address := "wss://host.example", local := false, alive := -1) -> int:
	var when := alive if alive >= 0 else int(Time.get_unix_time_from_system())
	return _open_issue("%s%s (%s)" % [RoomBoard.TITLE_PREFIX, room.room_name, room.host_name], RoomBoard.write_issue_body(room, address, local, when))


## Adds an issue that is not a room (someone wrote it by hand).
func add_other_issue(title: String, body: String) -> int:
	return _open_issue(title, body)


func is_open(number: int) -> bool:
	for issue in issues:
		if issue["number"] == number:
			return issue["state"] == "open"
	return false


func open_count() -> int:
	return issues.filter(func(issue: Dictionary) -> bool: return issue["state"] == "open").size()


func send(method: int, path: String, body: Dictionary) -> Dictionary:
	requests.append([method, path])
	if down:
		return {"code": 0, "data": null}
	match method:
		HTTPClient.METHOD_GET:
			var open: Array = []
			for issue in issues:
				if issue["state"] == "open":
					open.append(issue.duplicate(true))
			return {"code": 200, "data": open}
		HTTPClient.METHOD_POST:
			var number := _open_issue(str(body.get("title", "")), str(body.get("body", "")))
			return {"code": 201, "data": {"number": number}}
		HTTPClient.METHOD_PATCH:
			var number := int(path.get_file())
			for issue in issues:
				if issue["number"] == number:
					for field in ["state", "body", "title"]:
						if body.has(field):
							issue[field] = str(body[field])
					return {"code": 200, "data": issue.duplicate(true)}
			return {"code": 404, "data": null}
	return {"code": 405, "data": null}


func _open_issue(title: String, body: String) -> int:
	var number := _next_number
	_next_number += 1
	issues.append({"number": number, "title": title, "body": body, "state": "open"})
	return number
