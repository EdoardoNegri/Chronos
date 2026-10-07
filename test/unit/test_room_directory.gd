extends GutTest

var _dir: RoomDirectory


func before_each() -> void:
	_dir = autofree(RoomDirectory.new())


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


func test_host_room_adds_it_and_emits() -> void:
	watch_signals(_dir)
	var before := _dir.get_room_count()
	var room := _dir.host_room("  My Room ", 4)
	assert_not_null(room)
	assert_eq(room.room_name, "My Room")
	assert_eq(room.host_name, _dir.player_name)
	assert_eq(room.players, 1)
	assert_eq(_dir.get_room_count(), before + 1)
	assert_signal_emitted(_dir, "rooms_changed")


func test_host_room_rejects_bad_names_and_sizes() -> void:
	assert_ne(_dir.validate_room_name("   "), "")
	assert_ne(_dir.validate_room_name("x".repeat(RoomDirectory.MAX_NAME_LENGTH + 1)), "")
	assert_ne(_dir.validate_room_name("temporal RIFT"), "", "duplicate names are rejected")
	assert_null(_dir.host_room("Fine Name", 1))
	assert_null(_dir.host_room("Fine Name", RoomDirectory.MAX_PLAYERS + 1))


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
