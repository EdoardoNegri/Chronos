extends GutTest
## The game's side of the lobby: how it reads server addresses and what it does with what the
## server says. (The conversation with a real server is tried by running one; see lobby_server.tscn.)


func _lobby() -> Lobby:
	var lobby := Lobby.new()
	add_child_autofree(lobby)
	return lobby


func test_addresses_are_turned_into_websocket_addresses() -> void:
	assert_eq(Lobby.normalize_url("abc.trycloudflare.com"), "wss://abc.trycloudflare.com", "a name on the internet is secure")
	assert_eq(Lobby.normalize_url("  https://abc.trycloudflare.com/ "), "wss://abc.trycloudflare.com/")
	assert_eq(Lobby.normalize_url("http://192.168.0.5:9080"), "ws://192.168.0.5:9080")
	assert_eq(Lobby.normalize_url("127.0.0.1:9080"), "ws://127.0.0.1:9080", "this computer is not secure")
	assert_eq(Lobby.normalize_url("localhost:9080"), "ws://localhost:9080")
	assert_eq(Lobby.normalize_url("192.168.1.20:9080"), "ws://192.168.1.20:9080", "nor is the same network")
	assert_eq(Lobby.normalize_url("203.0.113.9:9080"), "ws://203.0.113.9:9080", "a bare number address has no certificate")
	assert_eq(Lobby.normalize_url("wss://x.example"), "wss://x.example", "a full address is kept")
	assert_eq(Lobby.normalize_url("ws://x.example:5"), "ws://x.example:5")
	assert_eq(Lobby.normalize_url("   "), "")


func test_it_starts_offline_with_no_rooms() -> void:
	var lobby := _lobby()
	assert_eq(lobby.state, Lobby.State.OFFLINE)
	assert_eq(lobby.rooms.get_room_count(), 0)
	assert_null(lobby.room)


func test_connecting_without_an_address_says_so() -> void:
	var lobby := _lobby()
	watch_signals(lobby)
	assert_ne(lobby.connect_to_server("   ", "Aeon"), OK)
	assert_eq(lobby.state, Lobby.State.OFFLINE)
	assert_string_contains(lobby.error_text, "address")
	assert_signal_emitted(lobby, "state_changed", "the screen is told why")


func test_nothing_can_be_asked_while_offline() -> void:
	var lobby := _lobby()
	watch_signals(lobby)
	lobby.host_room("A room", false, "")
	assert_signal_emitted(lobby, "host_failed")
	lobby.join_room(&"room_1", "")
	assert_signal_emitted_with_parameters(lobby, "join_failed", [ERR_CONNECTION_ERROR])
	lobby.leave_room()
	lobby.send_chat("hello")
	lobby.refresh()
	assert_null(lobby.room)


func test_the_server_sends_the_open_rooms_and_each_list_replaces_the_last() -> void:
	var lobby := _lobby()
	watch_signals(lobby)
	var examples := RoomDirectory.with_examples()
	lobby.on_rooms(examples.open_snapshot())
	assert_signal_emitted(lobby, "rooms_changed")
	assert_eq(lobby.rooms.get_room_count(), examples.get_room_count(true))
	assert_true(lobby.rooms.get_rooms("lounge")[0].has_password(), "a locked room shows as locked")
	lobby.on_rooms([])
	assert_eq(lobby.rooms.get_room_count(), 0)


func test_hosting_gives_a_room_or_says_why_not() -> void:
	var lobby := _lobby()
	watch_signals(lobby)
	lobby.on_hosted({}, "A room with that name already exists.")
	assert_signal_emitted_with_parameters(lobby, "host_failed", ["A room with that name already exists."])
	assert_null(lobby.room)

	var room := RoomInfo.new(&"room_9", "Mine", "Aeon", 1, 2)
	lobby.on_hosted(room.to_dict(), "")
	assert_signal_emitted(lobby, "hosted")
	assert_eq(lobby.room.room_name, "Mine")
	assert_eq(lobby.opponent_name, "", "nobody has joined yet")


func test_joining_gives_the_room_and_the_host_or_the_error() -> void:
	var lobby := _lobby()
	watch_signals(lobby)
	lobby.on_join_result(ERR_UNAUTHORIZED, {}, "")
	assert_signal_emitted_with_parameters(lobby, "join_failed", [ERR_UNAUTHORIZED])
	assert_null(lobby.room)

	var room := RoomInfo.new(&"room_9", "Theirs", "Kairos", 2, 2)
	lobby.on_join_result(OK, room.to_dict(), "Kairos")
	assert_signal_emitted(lobby, "joined")
	assert_eq(lobby.room.room_name, "Theirs")
	assert_eq(lobby.opponent_name, "Kairos", "the other player is the host")


func test_what_happens_in_the_room_is_told_through_signals() -> void:
	var lobby := _lobby()
	lobby.on_hosted(RoomInfo.new(&"r", "Mine", "Aeon", 1, 2).to_dict(), "")
	watch_signals(lobby)
	lobby.on_opponent_joined("Bob")
	assert_eq(lobby.opponent_name, "Bob")
	assert_signal_emitted_with_parameters(lobby, "opponent_joined", ["Bob"])
	lobby.on_chat("Bob", "hello")
	assert_signal_emitted_with_parameters(lobby, "chat_received", ["Bob", "hello"])
	lobby.on_opponent_left()
	assert_eq(lobby.opponent_name, "")
	assert_not_null(lobby.room, "the room is still there to be joined again")
	assert_signal_emitted(lobby, "opponent_left")
	lobby.on_room_closed()
	assert_null(lobby.room, "the host closing it ends it")
	assert_signal_emitted(lobby, "room_closed")
	assert_string_contains(lobby.notice, "host closed", "and the list will say so")


func test_a_server_ignores_what_only_a_player_should_get() -> void:
	# Both ends run this script, so each ignores the calls meant for the other.
	var lobby := _lobby()
	lobby.is_server = true
	watch_signals(lobby)
	lobby.on_rooms([{"id": "x"}])
	lobby.on_hosted({"id": "x"}, "")
	lobby.on_chat("a", "b")
	assert_signal_not_emitted(lobby, "rooms_changed")
	assert_signal_not_emitted(lobby, "hosted")
	assert_signal_not_emitted(lobby, "chat_received")
	assert_null(lobby.room)


func test_a_player_ignores_what_only_a_server_should_get() -> void:
	var lobby := _lobby()
	lobby.request_host("A room", false, "")
	lobby.request_join("room_1", "")
	lobby.request_chat("hello")
	lobby.request_leave()
	assert_eq(lobby._lobby.directory.get_room_count(), 0, "nothing was done on a player's computer")
