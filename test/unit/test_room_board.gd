extends GutTest

const FakeGitHub := preload("res://test/helpers/fake_github.gd")


func _board(github: FakeGitHub) -> RoomBoard:
	var board := github.make_board()
	add_child_autofree(board)
	return board


func test_a_room_is_written_to_an_issue_and_read_back() -> void:
	var room := RoomInfo.new(&"room_2", "Friday “duel”", "Aeon", 1, 2, false, true, "secret")
	var body := RoomBoard.write_issue_body(room, "wss://abc.trycloudflare.com")
	assert_true(body.begins_with(RoomBoard.MARKER))
	assert_false(body.contains("secret"), "the password never goes in the list")
	assert_false(body.contains(room.password_hash), "nor anything made from it")

	var entry := RoomBoard.read_issue({"number": 7, "body": body})
	assert_eq(entry["issue"], 7)
	assert_eq(entry["address"], "wss://abc.trycloudflare.com")
	assert_eq(entry["room_id"], "room_2", "the id the room has in its host's game")
	assert_eq(entry["room_name"], "Friday “duel”")
	assert_eq(entry["host_name"], "Aeon")
	assert_true(entry["locked"])
	assert_true(entry["custom_cards"])
	assert_false(entry["local"])


func test_issues_that_are_not_rooms_are_left_out() -> void:
	assert_eq(RoomBoard.read_issue({"number": 1, "body": "Just a question"}), {})
	assert_eq(RoomBoard.read_issue({"number": 2, "body": RoomBoard.MARKER + "\nnot json"}), {})
	assert_eq(RoomBoard.read_issue({"number": 3, "body": RoomBoard.MARKER + "\n{\"address\": \"\"}"}), {})
	var room := RoomInfo.new(&"room_2", "Room", "Aeon", 1, 2)
	var pull := {"number": 4, "body": RoomBoard.write_issue_body(room, "wss://x"), "pull_request": {}}
	assert_eq(RoomBoard.read_issue(pull), {}, "nor pull requests")
	assert_eq(RoomBoard.read_issue("nonsense"), {})


func test_refreshing_lists_the_open_rooms() -> void:
	var github := FakeGitHub.new()
	var first := github.add_room(RoomInfo.new(&"room_2", "Temporal Rift", "Aeon", 1, 2))
	github.add_room(RoomInfo.new(&"room_2", "Paradox Lounge", "Lyra", 1, 2, false, true, "time"), "wss://lyra.example")
	github.add_other_issue("Bug report", "The game crashed.")
	var board := _board(github)
	watch_signals(board)

	await board.refresh()
	assert_signal_emitted(board, "rooms_changed")
	var names: Array[String] = []
	for room in board.rooms.get_rooms():
		names.append(room.room_name)
	assert_eq(names, ["Paradox Lounge", "Temporal Rift"] as Array[String], "only rooms, by name")

	var lounge: RoomInfo = board.rooms.get_rooms("lounge")[0]
	assert_true(lounge.has_password())
	assert_true(lounge.custom_cards)
	assert_true(lounge.is_joinable())
	var entry := board.entry_for(lounge.id)
	assert_eq(entry["address"], "wss://lyra.example", "the list says where to reach it")
	assert_ne(lounge.id, board.rooms.get_rooms("temporal")[0].id, "rooms with the same id in their hosts' games stay apart")
	assert_eq(board.entry_for(StringName(str(first)))["room_name"], "Temporal Rift")


func test_a_host_posts_its_room_and_takes_it_off_again() -> void:
	var github := FakeGitHub.new()
	var board := _board(github)
	var issue: int = await board.post(RoomInfo.new(&"room_2", "Home room", "Aeon", 1, 2), "wss://abc.example")
	assert_gt(issue, 0)
	assert_true(github.is_open(issue))
	assert_eq(github.issues[0]["title"], "[Room] Home room (Aeon)", "easy to tell apart from other issues")
	await board.refresh()
	assert_eq(board.rooms.get_room_count(), 1)

	assert_true(await board.remove(issue))
	assert_false(github.is_open(issue), "the issue is closed")
	assert_eq(board.rooms.get_room_count(), 0, "and the room is gone from the list at once")


func test_without_a_token_nothing_is_sent_and_it_says_why() -> void:
	var github := FakeGitHub.new()
	var board := _board(github)
	board.token = ""
	assert_false(board.is_set_up())
	await board.refresh()
	assert_string_contains(board.error_text, "token")
	assert_eq(await board.post(RoomInfo.new(&"r", "Room", "Aeon", 1, 2), "wss://x"), 0)
	assert_eq(github.requests, [], "GitHub is never asked")


func test_when_github_cannot_be_reached_it_says_so() -> void:
	var github := FakeGitHub.new()
	github.add_room(RoomInfo.new(&"room_2", "Temporal Rift", "Aeon", 1, 2))
	var board := _board(github)
	await board.refresh()
	github.down = true
	watch_signals(board)
	await board.refresh()
	assert_signal_emitted(board, "failed")
	assert_string_contains(board.error_text, "could not be reached")
	assert_eq(board.rooms.get_room_count(), 1, "the last list stays")


func test_answers_from_github_are_explained() -> void:
	var board := RoomBoard.new()
	autofree(board)
	for code: int in [401, 403]:
		board._ok({"code": code}, "Could not")
		assert_string_contains(board.error_text, "token")
	board._ok({"code": 404}, "Could not")
	assert_string_contains(board.error_text, RoomBoard.REPOSITORY)
	assert_true(board._ok({"code": 201}, "Could not"))


func test_the_tests_never_use_the_real_token() -> void:
	assert_false(RoomBoard.use_token_file, "the pre-run hook turned the token file off")
	assert_eq(RoomBoard.load_token(), "")


func test_a_room_whose_host_went_quiet_is_left_out_and_closed() -> void:
	var github := FakeGitHub.new()
	var now := 1_000_000
	var fresh := github.add_room(RoomInfo.new(&"room_2", "Fresh", "Aeon", 1, 2), "wss://a", false, now - 60)
	var quiet := github.add_room(RoomInfo.new(&"room_2", "Quiet", "Nyx", 1, 2), "wss://b", false, now - RoomBoard.STALE_SECONDS - 1)
	var board := _board(github)
	board.clock = func() -> int: return now
	await board.refresh()
	assert_eq(board.rooms.get_room_count(), 1, "only the room whose host is still there")
	assert_eq(board.rooms.get_rooms()[0].room_name, "Fresh")
	assert_true(github.is_open(fresh))
	assert_false(github.is_open(quiet), "the quiet one is closed for everyone")


func test_touching_a_room_says_it_is_there_and_opens_it_again() -> void:
	var github := FakeGitHub.new()
	var board := _board(github)
	var room := RoomInfo.new(&"room_2", "Home room", "Aeon", 1, 2)
	board.clock = func() -> int: return 500
	var issue: int = await board.post(room, "wss://abc.example")
	await board.remove(issue)
	board.clock = func() -> int: return 900
	assert_true(await board.touch(issue, room, "wss://abc.example"))
	assert_true(github.is_open(issue))
	assert_eq(RoomBoard.read_issue(github.issues[0])["alive"], 900)


func test_running_out_of_requests_is_explained() -> void:
	var board := RoomBoard.new()
	autofree(board)
	board._ok({"code": 403, "headers": PackedStringArray(["X-RateLimit-Remaining: 0"])}, "Could not")
	assert_string_contains(board.error_text, "limit")
	board._ok({"code": 403, "headers": PackedStringArray(["X-RateLimit-Remaining: 4000"])}, "Could not")
	assert_string_contains(board.error_text, "token", "a 403 with requests left is the token")
