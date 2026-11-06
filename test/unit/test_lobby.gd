extends GutTest

## The lobby: how it reads addresses, what it does with what the host says, and hosting a room on
## this computer. (The host's rules are tried in test_lobby_host.gd.)

const FakeGitHub := preload("res://test/helpers/fake_github.gd")
const Decks := preload("res://test/helpers/decks.gd")


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


func test_it_starts_offline_in_no_room() -> void:
	var lobby := _lobby()
	assert_eq(lobby.state, Lobby.State.OFFLINE)
	assert_null(lobby.room)
	assert_false(lobby.is_player)


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
	lobby.join_room(&"room_1", "")
	assert_signal_emitted_with_parameters(lobby, "join_failed", [ERR_CONNECTION_ERROR])
	lobby.leave_room()
	lobby.send_chat("hello")
	lobby.check_deck({}, [])
	lobby.set_ready(true)
	assert_null(lobby.room)
	assert_false(lobby.my_ready)


func test_a_host_that_cannot_be_reached_is_tried_again_before_giving_up() -> void:
	var lobby := _lobby()
	lobby.retry_seconds = 0.05
	watch_signals(lobby)
	# Nothing listens on port 1 of this computer, so every try fails at once.
	assert_eq(lobby.connect_to_server("ws://127.0.0.1:1", "Aeon"), OK)
	assert_eq(lobby.state, Lobby.State.CONNECTING)
	await wait_until(func() -> bool: return lobby.state == Lobby.State.OFFLINE, 30.0)
	assert_eq(lobby.state, Lobby.State.OFFLINE, "it gives up in the end")
	assert_string_contains(lobby.error_text, "Could not reach the game")
	assert_signal_emit_count(lobby, "state_changed", 2, "connecting, then offline: the tries in between are not news")


func test_leaving_or_connecting_elsewhere_stops_the_tries() -> void:
	var lobby := _lobby()
	lobby.retry_seconds = 0.3
	lobby.connect_to_server("ws://127.0.0.1:1", "Aeon")
	lobby.disconnect_from_server()
	await wait_seconds(1.0)
	assert_eq(lobby.state, Lobby.State.OFFLINE)
	assert_eq(lobby.error_text, "", "an old try does not come back to say it failed")


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


func test_a_player_ignores_what_only_a_host_should_get() -> void:
	var lobby := _lobby()
	lobby.request_hello("Bob")
	lobby.request_join("room_1", "")
	lobby.request_chat("hello")
	lobby.request_deck_check({}, [])
	lobby.request_set_ready(true)
	lobby.request_leave()
	assert_null(lobby._host, "a game that hosts nothing has no rules to apply")
	assert_null(lobby.room)


# --- Hosting from this computer ------------------------------------------------------------


## A lobby that hosts on this computer, with its room list on `github`. It looks for no public
## address, so its room is listed as one for this network.
func _hosting_lobby(github: FakeGitHub = null) -> Lobby:
	var lobby := Lobby.new()
	lobby.board = (github if github != null else FakeGitHub.new()).make_board()
	lobby.find_public_address = false
	add_child_autofree(lobby)
	return lobby


func test_hosting_here_starts_a_server_opens_the_room_and_lists_it() -> void:
	var github := FakeGitHub.new()
	var lobby := _hosting_lobby(github)
	watch_signals(lobby)
	lobby.host_here("Aeon", "Home room", true, "pw")
	assert_signal_emitted(lobby, "hosted")
	assert_true(lobby.is_player, "a server runs on this computer, and its host plays on it")
	assert_gte(lobby.hosting_port, Lobby.DEFAULT_PORT)
	assert_eq(lobby.state, Lobby.State.CONNECTED)
	assert_eq(lobby.room.room_name, "Home room")
	assert_eq(lobby.room.host_name, "Aeon")
	assert_true(lobby.room.custom_cards)
	assert_true(lobby.room.has_password())

	assert_eq(github.open_count(), 1, "the room is in the list")
	assert_gt(lobby.listed_issue, 0)
	var entry := RoomBoard.read_issue(github.issues[0])
	assert_eq(entry["room_id"], str(lobby.room.id), "the list says which room it is")
	assert_eq(entry["room_name"], "Home room")
	assert_true(entry["locked"])
	assert_true(entry["local"], "and that it is only on this network")
	assert_true(str(entry["address"]).begins_with("ws://"))
	assert_true(str(entry["address"]).ends_with(":%d" % lobby.hosting_port), "and leads to this server")
	assert_string_contains(lobby.listing_note, "your own network", "the host is told it only works nearby")
	assert_signal_emitted(lobby, "listing_changed")

	lobby.stop_hosting()
	assert_false(lobby.is_player)
	assert_eq(github.open_count(), 0, "stopping takes the room off the list")
	assert_eq(lobby.listed_issue, 0)
	assert_null(lobby.room)
	assert_eq(lobby.state, Lobby.State.OFFLINE)


func test_a_room_that_cannot_be_listed_still_opens_and_says_why() -> void:
	var github := FakeGitHub.new()
	github.down = true
	var lobby := _hosting_lobby(github)
	lobby.host_here("Aeon", "Home room", false, "")
	assert_eq(lobby.room.room_name, "Home room", "the room is open")
	assert_eq(lobby.listed_issue, 0)
	assert_string_contains(lobby.listing_note, "could not be added")
	lobby.stop_hosting()


func test_a_room_that_cannot_be_hosted_says_why_and_starts_nothing() -> void:
	var lobby := _hosting_lobby()
	watch_signals(lobby)
	lobby.host_here("Aeon", "   ", false, "")
	lobby.host_here("Aeon", "Fine", false, "x".repeat(RoomDirectory.MAX_PASSWORD_LENGTH + 1))
	assert_signal_emit_count(lobby, "host_failed", 2)
	assert_signal_not_emitted(lobby, "hosted")
	assert_false(lobby.is_player, "no server was started for them")
	assert_eq(lobby.state, Lobby.State.OFFLINE)


func test_hosting_again_replaces_the_room() -> void:
	var lobby := _hosting_lobby()
	lobby.host_here("Aeon", "First", false, "")
	var first_port := lobby.hosting_port
	lobby.host_here("Aeon", "Second", false, "")
	assert_eq(lobby.room.room_name, "Second")
	assert_eq(lobby._host.state.directory.get_room_count(), 1, "the old room is gone")
	assert_eq(lobby.hosting_port, first_port, "and the port it used is free again")
	lobby.stop_hosting()


func test_the_host_leaving_stops_the_server_once_the_other_player_could_be_told() -> void:
	var lobby := _hosting_lobby()
	lobby.host_here("Aeon", "Brief", false, "")
	lobby.leave_room()
	assert_null(lobby.room, "the host is out of the room at once")
	assert_true(lobby.is_player, "but the server stays a moment, so the other player is told")
	await wait_seconds(Lobby.CLOSE_DELAY + 0.4)
	assert_false(lobby.is_player, "then it stops")
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
	assert_false(lobby.is_player, "hosting stops when going to someone else's game")
	assert_null(lobby.room)


# --- Decks and ready, for the host ---------------------------------------------------------


func _official_deck_data() -> Dictionary:
	return Decks.official_deck().to_dict()


func test_the_host_checks_their_own_deck_and_can_be_ready_alone_without_starting() -> void:
	var lobby := _hosting_lobby()
	lobby.host_here("Aeon", "Duel", false, "")
	watch_signals(lobby)
	lobby.set_ready(true)
	assert_signal_emitted_with_parameters(lobby, "deck_checked", [["Choose a deck that is allowed first."]])
	assert_false(lobby.my_ready, "not without a checked deck")

	lobby.check_deck({"deck_name": "Tiny", "cards": {"official_zap": 1}}, [])
	assert_false(lobby.deck_approved)
	lobby.check_deck(_official_deck_data(), [])
	assert_true(lobby.deck_approved, "a legal deck passes")
	lobby.set_ready(true)
	assert_true(lobby.my_ready)
	assert_false(lobby.opponent_ready)
	assert_signal_emitted(lobby, "ready_changed")
	assert_signal_not_emitted(lobby, "game_started", "a game needs two players")

	lobby.check_deck({"deck_name": "Tiny", "cards": {"official_zap": 1}}, [])
	assert_false(lobby.my_ready, "a deck that fails takes back being ready")
	lobby.stop_hosting()
	assert_false(lobby.deck_approved, "and leaving forgets it all")


func test_a_standard_room_refuses_custom_cards_at_the_hosts_end() -> void:
	var lobby := _hosting_lobby()
	lobby.host_here("Aeon", "Duel", false, "")
	var deck := _official_deck_data()
	deck["cards"]["custom_1"] = 1
	var custom := {"id": "custom_1", "card_name": "Homebrew", "points": 0}
	lobby.check_deck(deck, [custom])
	assert_false(lobby.deck_approved)
	lobby.stop_hosting()
	lobby.host_here("Aeon", "Custom duel", true, "")
	lobby.check_deck(deck, [custom])
	assert_true(lobby.deck_approved, "a custom cards room takes them")
	lobby.stop_hosting()
