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


# --- Hosting from this computer ------------------------------------------------------------


func _hosting_lobby() -> Lobby:
	var lobby := _lobby()
	lobby.find_public_address = false
	return lobby


func test_hosting_here_starts_a_server_opens_the_room_and_makes_a_link() -> void:
	var lobby := _hosting_lobby()
	watch_signals(lobby)
	lobby.host_here("Aeon", "Home room", true, "pw")
	assert_signal_emitted(lobby, "hosted")
	assert_true(lobby.is_server, "a server runs on this computer")
	assert_true(lobby.is_player, "and its host plays on it")
	assert_gte(lobby.hosting_port, Lobby.DEFAULT_PORT)
	assert_eq(lobby.state, Lobby.State.CONNECTED)
	assert_eq(lobby.room.room_name, "Home room")
	assert_eq(lobby.room.host_name, "Aeon")
	assert_true(lobby.room.custom_cards)
	assert_true(lobby.room.has_password())

	var invite := InviteLink.parse(lobby.invite_link)
	assert_eq(invite["room_id"], str(lobby.room.id), "the link is for this room")
	assert_eq(invite["room_name"], "Home room")
	assert_true(invite["locked"])
	assert_true(str(invite["address"]).begins_with("ws://"))
	assert_true(str(invite["address"]).ends_with(":%d" % lobby.hosting_port), "and leads to this server")
	assert_string_contains(lobby.link_note, "your own network", "it says the link only works nearby")
	assert_signal_emitted(lobby, "link_changed")

	lobby.stop_hosting()
	assert_false(lobby.is_server)
	assert_false(lobby.is_player)
	assert_eq(lobby.invite_link, "")
	assert_null(lobby.room)
	assert_eq(lobby.state, Lobby.State.OFFLINE)


func test_a_room_that_cannot_be_hosted_says_why_and_starts_nothing() -> void:
	var lobby := _hosting_lobby()
	watch_signals(lobby)
	lobby.host_here("Aeon", "   ", false, "")
	lobby.host_here("Aeon", "Fine", false, "x".repeat(RoomDirectory.MAX_PASSWORD_LENGTH + 1))
	assert_signal_emit_count(lobby, "host_failed", 2)
	assert_signal_not_emitted(lobby, "hosted")
	assert_false(lobby.is_server, "no server was started for them")
	assert_eq(lobby.state, Lobby.State.OFFLINE)


func test_hosting_again_replaces_the_room() -> void:
	var lobby := _hosting_lobby()
	lobby.host_here("Aeon", "First", false, "")
	var first_port := lobby.hosting_port
	lobby.host_here("Aeon", "Second", false, "")
	assert_eq(lobby.room.room_name, "Second")
	assert_eq(lobby._lobby.directory.get_room_count(), 1, "the old room is gone")
	assert_eq(lobby.hosting_port, first_port, "and the port it used is free again")
	lobby.stop_hosting()


func test_the_host_leaving_stops_the_server_once_the_other_player_could_be_told() -> void:
	var lobby := _hosting_lobby()
	lobby.host_here("Aeon", "Brief", false, "")
	lobby.leave_room()
	assert_null(lobby.room, "the host is out of the room at once")
	assert_true(lobby.is_server, "but the server stays a moment, so the other player is told")
	await wait_seconds(Lobby.CLOSE_DELAY + 0.4)
	assert_false(lobby.is_server, "then it stops")
	assert_eq(lobby.state, Lobby.State.OFFLINE)


func test_the_host_can_say_things_with_nobody_there_and_the_room_is_theirs_alone() -> void:
	var lobby := _hosting_lobby()
	lobby.host_here("Aeon", "Quiet", false, "")
	watch_signals(lobby)
	lobby.send_chat("anyone?")
	assert_signal_not_emitted(lobby, "chat_received", "nothing comes back from an empty room")
	lobby.stop_hosting()


func test_joining_someone_else_stops_hosting() -> void:
	var lobby := _hosting_lobby()
	lobby.host_here("Aeon", "Mine", false, "")
	lobby.connect_to_server("   ", "Aeon")
	assert_false(lobby.is_server, "hosting stops when going to someone else's server")
	assert_null(lobby.room)
