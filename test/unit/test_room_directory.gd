extends GutTest

var _dir: RoomDirectory


func before_each() -> void:
	_dir = RoomDirectory.with_examples()


func test_starts_with_rooms_sorted_by_name() -> void:
	var rooms := _dir.get_rooms()
	assert_gt(rooms.size(), 0)
	for i in range(1, rooms.size()):
		assert_true(rooms[i - 1].room_name.naturalnocasecmp_to(rooms[i].room_name) <= 0)


func test_search_matches_name_case_insensitively() -> void:
	var rooms := _dir.get_rooms("  temporal ")
	assert_eq(rooms.size(), 1)
	assert_eq(rooms[0].room_name, "Temporal Rift")


func test_search_matches_host() -> void:
	var rooms := _dir.get_rooms("kairos")
	assert_eq(rooms.size(), 1)
	assert_eq(rooms[0].host_name, "Kairos")


func test_search_without_match_is_empty() -> void:
	assert_eq(_dir.get_rooms("zzzz-no-such-room").size(), 0)


func test_room_search_reads_words_and_quotes_like_every_search_field() -> void:
	assert_eq(_dir.get_rooms("rift temporal").size(), 1, "loose words, in any order")
	assert_eq(_dir.get_rooms("aeon rift").size(), 1, "the name and the host count together")
	assert_eq(_dir.get_rooms("\"temporal rift\"").size(), 1)
	assert_eq(_dir.get_rooms("\"rift temporal\"").size(), 0, "a quoted phrase keeps its order")
	assert_eq(_dir.get_rooms("emporal").size(), 1, "words match inside longer words")


func test_rooms_are_standard_unless_hosted_with_custom_cards() -> void:
	var standard := _dir.host_room("Plain game")
	var custom := _dir.host_room("With my cards", true)
	assert_false(standard.custom_cards)
	assert_eq(standard.mode_name(), RoomInfo.MODE_STANDARD)
	assert_true(custom.custom_cards)
	assert_eq(custom.mode_name(), RoomInfo.MODE_CUSTOM)


func test_room_row_shows_the_game_mode() -> void:
	var row: Node = load("res://scenes/room_row.tscn").instantiate()
	add_child_autofree(row)
	row.setup(RoomInfo.new(&"r", "Room", "Host", 1, 2, false, true))
	assert_string_contains((row.get_node("%HostName") as Label).text, "Custom cards")
	row.setup(RoomInfo.new(&"r", "Room", "Host", 1, 2))
	assert_string_contains((row.get_node("%HostName") as Label).text, "Standard")


func test_room_row_shows_a_padlock_for_a_password_and_no_player_count() -> void:
	var row: Node = load("res://scenes/room_row.tscn").instantiate()
	add_child_autofree(row)
	var lock: LockIcon = row.get_node("%LockIcon")
	var join: Control = row.get_node("%JoinButton")
	row.setup(RoomInfo.new(&"r", "Room", "Host", 1, 2))
	assert_false(lock.locked)
	assert_false((row.get_node("%HostName") as Label).text.contains("Password"), "the lock is not in the text")
	row.setup(RoomInfo.new(&"r", "Room", "Host", 1, 2, false, false, "pw"))
	assert_true(lock.locked)
	assert_eq(lock.tooltip_text, "This room has a password.")
	assert_false((row.get_node("%HostName") as Label).text.contains("Password"), "the lock is not in the text")
	assert_eq(lock.get_index(), join.get_index() - 1, "the padlock is right before Join, on its left")
	assert_eq(join.get_index(), (join.get_parent() as Node).get_child_count() - 1, "and Join is the far right")
	assert_null(row.get_node_or_null("%Players"), "every game has two players, so none is shown")
	assert_null(row.get_node_or_null("%Status"), "and every listed room is open, so no status")
	assert_eq(_labels_text(row).contains("1 / 2"), false)
	assert_eq(_labels_text(row).contains("Open"), false)


## All the text in a part of the screen.
func _labels_text(root: Node) -> String:
	var texts: Array[String] = []
	for label: Label in root.find_children("*", "Label", true, false):
		texts.append(label.text)
	return " ".join(texts)


func test_only_rooms_with_a_free_seat_can_be_asked_for() -> void:
	var all := _dir.get_rooms()
	var open := _dir.get_rooms("", true)
	assert_lt(open.size(), all.size(), "some example rooms are full or in a game")
	for room in open:
		assert_true(room.is_joinable(), "%s has a free seat" % room.room_name)
	assert_eq(_dir.get_rooms("last second", true).size(), 0, "a full room is left out")
	assert_eq(_dir.get_rooms("last second").size(), 1, "but is still there")
	assert_eq(_dir.get_rooms("midnight", true).size(), 0, "so is one in a game")
	assert_eq(_dir.get_room_count(true), open.size())
	assert_eq(_dir.get_room_count(), all.size())

	var room := _dir.host_room("Soon full")
	assert_has(_dir.get_rooms("soon full", true), room)
	_dir.join_room(room.id)
	assert_eq(_dir.get_rooms("soon full", true).size(), 0, "a room drops out of the list when it fills")


func test_host_room_adds_it_and_emits() -> void:
	watch_signals(_dir)
	var before := _dir.get_room_count()
	var room := _dir.host_room("  My Room ")
	assert_not_null(room)
	assert_eq(room.room_name, "My Room")
	assert_eq(room.host_name, _dir.player_name)
	assert_eq(room.players, 1)
	assert_eq(_dir.get_room_count(), before + 1)
	assert_signal_emitted(_dir, "rooms_changed")


func test_host_room_rejects_bad_names_and_passwords() -> void:
	assert_ne(_dir.validate_room_name("   "), "")
	assert_ne(_dir.validate_room_name("x".repeat(RoomDirectory.MAX_NAME_LENGTH + 1)), "")
	assert_ne(_dir.validate_room_name("temporal RIFT"), "", "duplicate names are rejected")
	assert_null(_dir.host_room("Fine Name", false, "x".repeat(RoomDirectory.MAX_PASSWORD_LENGTH + 1)))
	assert_not_null(_dir.host_room("Fine Name", false, "x".repeat(RoomDirectory.MAX_PASSWORD_LENGTH)))


func test_every_game_is_between_two_players() -> void:
	assert_eq(RoomDirectory.PLAYERS, 2)
	for room in _dir.get_rooms():
		assert_eq(room.max_players, 2, "%s holds two players" % room.room_name)
		assert_lte(room.players, 2)
	var hosted := _dir.host_room("Just us")
	assert_eq(hosted.max_players, 2, "a hosted room cannot be made bigger")
	assert_eq(_dir.join_room(hosted.id), OK, "the second player fits")
	assert_true(hosted.is_full())
	assert_eq(_dir.join_room(hosted.id), ERR_BUSY, "and there is no room for a third")


func test_a_room_with_a_password_needs_it_to_be_joined() -> void:
	var room := _dir.host_room("Private", false, "secret")
	assert_true(room.has_password())
	assert_ne(room.password_hash, "secret", "the password itself is not kept")
	assert_eq(_dir.join_room(room.id), ERR_UNAUTHORIZED, "no password")
	assert_eq(_dir.join_room(room.id, "Secret"), ERR_UNAUTHORIZED, "capitals count in a password")
	assert_eq(room.players, 1, "a refused player does not take the seat")
	assert_eq(_dir.join_room(room.id, "secret"), OK)
	assert_eq(room.players, 2)

	var open := _dir.host_room("Open door")
	assert_false(open.has_password())
	assert_eq(_dir.join_room(open.id, "anything"), OK, "a room without a password ignores one")


func test_the_example_rooms_include_locked_ones() -> void:
	var locked := _dir.get_rooms("lounge")[0]
	assert_true(locked.has_password())
	assert_eq(_dir.join_room(locked.id, "wrong"), ERR_UNAUTHORIZED)
	assert_eq(_dir.join_room(locked.id, "time"), OK)


func test_join_open_room_adds_a_player() -> void:
	var room := _dir.get_rooms("temporal")[0]
	var players := room.players
	assert_eq(_dir.join_room(room.id), OK)
	assert_eq(room.players, players + 1)


func test_join_full_or_running_room_is_refused() -> void:
	var full := _dir.get_rooms("last second")[0]
	var running := _dir.get_rooms("midnight")[0]
	assert_eq(_dir.join_room(full.id), ERR_BUSY)
	assert_eq(_dir.join_room(running.id), ERR_BUSY)


func test_join_unknown_room_fails() -> void:
	assert_eq(_dir.join_room(&"nope"), ERR_DOES_NOT_EXIST)


func test_a_room_travels_as_a_snapshot_without_its_password() -> void:
	var room := _dir.host_room("Snapshot room", true, "secret", "Aeon")
	var data := room.to_dict()
	assert_false(data.has("password_hash"), "the password hash never leaves the server")
	assert_true(data["locked"])
	var copy := RoomInfo.from_dict(data)
	assert_eq(copy.room_name, "Snapshot room")
	assert_eq(copy.host_name, "Aeon")
	assert_true(copy.custom_cards)
	assert_true(copy.has_password(), "a player still sees that the room is locked")
	assert_eq(copy.max_players, 2)

	var others := RoomDirectory.new()
	others.replace_from_snapshot(_dir.open_snapshot())
	assert_eq(others.get_room_count(), _dir.get_room_count(true), "only open rooms are sent")
	others.replace_from_snapshot([])
	assert_eq(others.get_room_count(), 0, "a new snapshot replaces the old one")


func test_a_seat_can_be_freed_and_a_room_removed() -> void:
	var room := _dir.host_room("Two seats")
	_dir.join_room(room.id)
	assert_true(room.is_full())
	_dir.leave_room(room.id)
	assert_false(room.is_full(), "the second player leaving opens the seat")
	assert_eq(room.players, 1, "but the host stays")
	_dir.leave_room(room.id)
	assert_eq(room.players, 1, "and the host cannot leave through the seat")
	_dir.remove_room(room.id)
	assert_null(_dir.get_room(room.id))
	assert_eq(_dir.join_room(room.id), ERR_DOES_NOT_EXIST)


func test_a_host_name_can_be_given() -> void:
	assert_eq(_dir.host_room("Named host", false, "", "Kairos").host_name, "Kairos")
	assert_eq(_dir.host_room("Default host").host_name, _dir.player_name)
