extends GutTest

const ALICE := 10
const BOB := 20
const CARA := 30

var _state: LobbyState


func before_each() -> void:
	_state = LobbyState.new()
	_state.register(ALICE, "Alice")
	_state.register(BOB, "Bob")


func test_players_register_with_a_name_and_nothing_else() -> void:
	assert_true(_state.is_registered(ALICE))
	assert_eq(_state.name_of(ALICE), "Alice")
	assert_eq(_state.register(CARA, "  Cara  "), "")
	assert_eq(_state.name_of(CARA), "Cara", "spaces around a name are dropped")
	assert_ne(_state.register(40, "   "), "", "a name is needed")
	assert_ne(_state.register(40, "x".repeat(PlayerProfile.MAX_NAME_LENGTH + 1)), "")
	assert_false(_state.is_registered(40), "a refused name is not kept")
	for peer in [ALICE, BOB, CARA]:
		assert_true(_state.is_registered(peer))


func test_hosting_needs_a_name_a_free_player_and_a_new_room_name() -> void:
	assert_has(_state.host(99, "Nobody", false, ""), "error")
	var made := _state.host(ALICE, "Alice's room", true, "pw")
	assert_has(made, "room")
	var room: RoomInfo = made["room"]
	assert_eq(room.host_name, "Alice", "the host is who they said they were")
	assert_true(room.custom_cards)
	assert_true(room.has_password())
	assert_has(_state.host(ALICE, "Another", false, ""), "error", "one room at a time")
	assert_has(_state.host(BOB, "alice's ROOM", false, ""), "error", "room names are unique")
	assert_has(_state.host(BOB, "", false, ""), "error")


func test_joining_checks_the_room_the_password_and_the_seat() -> void:
	var room: RoomInfo = _state.host(ALICE, "Locked", false, "pw")["room"]
	assert_eq(_state.join(BOB, room.id, "nope")["error"], ERR_UNAUTHORIZED)
	assert_eq(_state.join(BOB, &"no_such_room", "")["error"], ERR_DOES_NOT_EXIST)
	assert_eq(_state.join(99, room.id, "pw")["error"], ERR_UNAUTHORIZED, "someone who is not registered")
	var joined := _state.join(BOB, room.id, "pw")
	assert_eq(joined["host_peer"], ALICE, "the server learns who to tell")
	assert_eq(room.players, 2)
	_state.register(CARA, "Cara")
	assert_eq(_state.join(CARA, room.id, "pw")["error"], ERR_BUSY, "a third player does not fit")
	assert_eq(_state.join(BOB, room.id, "pw")["error"], ERR_ALREADY_IN_USE, "already in it")


func test_a_player_in_a_room_cannot_join_another() -> void:
	var first: RoomInfo = _state.host(ALICE, "First", false, "")["room"]
	_state.register(CARA, "Cara")
	var second: RoomInfo = _state.host(CARA, "Second", false, "")["room"]
	assert_eq(_state.join(ALICE, second.id, "")["error"], ERR_ALREADY_IN_USE)
	assert_eq(first.players, 1)


func test_each_player_knows_the_other() -> void:
	var room: RoomInfo = _state.host(ALICE, "Pair", false, "")["room"]
	assert_eq(_state.opponent_of(ALICE), 0, "nobody yet")
	_state.join(BOB, room.id, "")
	assert_eq(_state.opponent_of(ALICE), BOB)
	assert_eq(_state.opponent_of(BOB), ALICE)
	assert_eq(_state.opponent_of(CARA), 0, "not in a room")


func test_the_second_player_leaving_opens_the_seat_again() -> void:
	var room: RoomInfo = _state.host(ALICE, "Seat", false, "")["room"]
	_state.join(BOB, room.id, "")
	assert_eq(_state.directory.get_rooms("seat", true).size(), 0, "full, so not listed")
	var left := _state.leave(BOB)
	assert_eq(left, {"closed": false, "other": ALICE}, "the host is the one to tell")
	assert_eq(_state.directory.get_rooms("seat", true).size(), 1, "listed again")
	assert_eq(_state.opponent_of(ALICE), 0)
	assert_eq(_state.join(BOB, room.id, "")["room"], room, "and Bob can come back")


func test_the_host_leaving_closes_the_room_and_frees_the_other_player() -> void:
	var room: RoomInfo = _state.host(ALICE, "Gone", false, "")["room"]
	_state.join(BOB, room.id, "")
	var left := _state.leave(ALICE)
	assert_eq(left, {"closed": true, "other": BOB}, "the second player is the one to tell")
	assert_null(_state.directory.get_room(room.id))
	assert_eq(_state.opponent_of(BOB), 0)
	assert_has(_state.host(BOB, "Mine now", false, ""), "room", "Bob can open a room of their own")
	assert_eq(_state.leave(CARA), {}, "leaving without a room does nothing")


func test_a_disconnected_player_is_forgotten_and_leaves_their_room() -> void:
	var room: RoomInfo = _state.host(ALICE, "Dropped", false, "")["room"]
	_state.join(BOB, room.id, "")
	var gone := _state.unregister(BOB)
	assert_eq(gone["other"], ALICE)
	assert_false(_state.is_registered(BOB))
	assert_eq(room.players, 1)
	assert_true(_state.is_registered(ALICE), "the host stays")


func test_what_is_sent_about_rooms_never_includes_the_password() -> void:
	_state.host(ALICE, "Secret", false, "pw")
	for room in _state.directory.get_rooms():
		var entry := room.to_dict()
		assert_false(entry.has("password_hash"))
		assert_false(str(entry).contains(RoomInfo.hash_password("pw")), "not even as text")


# --- Decks and ready -----------------------------------------------------------------------


func test_only_a_player_whose_deck_passed_can_be_ready() -> void:
	var room: RoomInfo = _state.host(ALICE, "Duel", false, "")["room"]
	assert_false(_state.set_ready(ALICE, true), "no deck checked yet")
	_state.set_deck_ok(ALICE, true)
	assert_true(_state.set_ready(ALICE, true))
	assert_true(_state.is_ready(ALICE))
	assert_false(_state.both_ready(room.id), "one player is not a game")
	_state.set_deck_ok(ALICE, false)
	assert_false(_state.is_ready(ALICE), "a deck that fails a new check takes back being ready")
	assert_false(_state.set_ready(CARA, true), "nor can someone in no room")


func test_the_game_starts_when_both_players_are_ready() -> void:
	var room: RoomInfo = _state.host(ALICE, "Duel", false, "")["room"]
	_state.join(BOB, room.id, "")
	assert_eq(_state.players_in(room.id), [ALICE, BOB] as Array[int])
	assert_eq(_state.room_of(BOB), room.id)
	for peer in [ALICE, BOB]:
		_state.set_deck_ok(peer, true)
		_state.set_ready(peer, true)
	assert_true(_state.both_ready(room.id))
	_state.set_ready(BOB, false)
	assert_false(_state.both_ready(room.id), "taking it back stops it")


func test_someone_joining_or_leaving_means_saying_ready_again() -> void:
	var room: RoomInfo = _state.host(ALICE, "Duel", false, "")["room"]
	_state.set_deck_ok(ALICE, true)
	_state.set_ready(ALICE, true)
	_state.join(BOB, room.id, "")
	assert_false(_state.is_ready(ALICE), "a new player: the host says it again")
	assert_true(_state.deck_ok(ALICE), "with the same deck")
	_state.set_ready(ALICE, true)
	_state.set_deck_ok(BOB, true)
	_state.set_ready(BOB, true)
	_state.leave(BOB)
	assert_false(_state.is_ready(ALICE), "the other player left")
	assert_false(_state.deck_ok(BOB), "and whoever leaves forgets their deck")
