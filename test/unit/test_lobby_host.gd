extends GutTest
## The rules of a hosted room, between a host (peer 1) and a guest (peer 2), without a network:
## every message the rules send is kept in `sent`.

const Decks := preload("res://test/helpers/decks.gd")
const HOST := 1
const GUEST := 2

## Every message sent, as [peer, method, args].
var sent: Array = []
var host: LobbyHost


func before_each() -> void:
	sent.clear()
	host = LobbyHost.new(func(peer: int, method: StringName, args: Array) -> void: sent.append([peer, method, args]))
	host.points_list = PointsList.new("user://no_points_list.json")
	host.state.register(HOST, "Aeon")
	host.open_room(HOST, "Duel", false, "pw")


## The messages a player got, by name, newest last.
func _got(peer: int, method: StringName) -> Array:
	return sent.filter(func(message: Array) -> bool: return message[0] == peer and message[1] == method)


func _join_guest() -> void:
	host.hello(GUEST, "Bob")
	host.join(GUEST, "room_2", "pw")


func _room_id() -> StringName:
	return host.state.room_of(HOST)


func test_the_host_opens_the_room_and_a_guest_joins_with_the_password() -> void:
	assert_eq(_got(HOST, &"on_hosted")[0][2][1], "", "the room is open")
	host.hello(GUEST, "Bob")
	assert_eq(_got(GUEST, &"on_hello_result")[0][2], [""], "the name is accepted")
	host.join(GUEST, str(_room_id()), "wrong")
	assert_eq(_got(GUEST, &"on_join_result")[0][2][0], ERR_UNAUTHORIZED)
	host.join(GUEST, str(_room_id()), "pw")
	assert_eq(_got(GUEST, &"on_join_result")[1][2][0], OK)
	assert_eq(_got(GUEST, &"on_join_result")[1][2][2], "Aeon", "the guest learns who the host is")
	assert_eq(_got(HOST, &"on_opponent_joined")[0][2], ["Bob"], "and the host who joined")


func test_the_game_starts_once_both_decks_passed_and_both_are_ready() -> void:
	host.hello(GUEST, "Bob")
	host.join(GUEST, str(_room_id()), "pw")
	var deck := Decks.official_deck().to_dict()
	host.set_ready(GUEST, true)
	assert_eq(_got(GUEST, &"on_deck_checked").back()[2], [["Choose a deck that is allowed first."]])

	host.check_deck(HOST, deck, [])
	host.check_deck(GUEST, deck, [])
	assert_eq(_got(GUEST, &"on_deck_checked").back()[2], [[]], "the deck passes")
	host.set_ready(HOST, true)
	assert_eq(_got(GUEST, &"on_ready_state").back()[2], [false, true], "the guest sees the host is ready")
	assert_eq(_got(HOST, &"on_game_start"), [], "not yet")
	host.set_ready(GUEST, true)
	assert_eq(_got(HOST, &"on_ready_state").back()[2], [true, true])
	assert_eq(_got(HOST, &"on_game_start").size(), 1, "both are told the game starts")
	assert_eq(_got(GUEST, &"on_game_start").size(), 1)
	host.set_ready(GUEST, false)
	assert_eq(_got(HOST, &"on_ready_state").back()[2], [true, true], "nothing changes once the game is on")


func test_a_deck_that_fails_takes_back_being_ready() -> void:
	host.check_deck(HOST, Decks.official_deck().to_dict(), [])
	host.set_ready(HOST, true)
	host.check_deck(HOST, {"deck_name": "Tiny", "cards": {"official_zap": 1}}, [])
	assert_eq(_got(HOST, &"on_ready_state").back()[2], [false, false])


func test_chat_goes_to_the_other_player_only() -> void:
	host.hello(GUEST, "Bob")
	host.join(GUEST, str(_room_id()), "pw")
	host.chat(GUEST, "  hello  ")
	assert_eq(_got(HOST, &"on_chat").back()[2], ["Bob", "hello"])
	host.chat(GUEST, "x".repeat(LobbyHost.MAX_CHAT_LENGTH + 50))
	assert_eq((_got(HOST, &"on_chat").back()[2][1] as String).length(), LobbyHost.MAX_CHAT_LENGTH, "long lines are cut")
	host.chat(GUEST, "   ")
	assert_eq(_got(HOST, &"on_chat").size(), 2, "empty lines are not passed on")


func test_a_guest_who_leaves_or_drops_frees_the_seat_and_the_host_is_told() -> void:
	host.hello(GUEST, "Bob")
	host.join(GUEST, str(_room_id()), "pw")
	host.disconnected(GUEST)
	assert_eq(_got(HOST, &"on_opponent_left").size(), 1)
	assert_eq(_got(HOST, &"on_ready_state").back()[2], [false, false], "the host says ready again")
	host.hello(GUEST, "Bob")
	host.join(GUEST, str(_room_id()), "pw")
	assert_eq(_got(GUEST, &"on_join_result").back()[2][0], OK, "the seat is free again")


func test_the_host_leaving_closes_the_room_for_the_guest() -> void:
	host.hello(GUEST, "Bob")
	host.join(GUEST, str(_room_id()), "pw")
	host.leave(HOST)
	assert_eq(_got(GUEST, &"on_room_closed").size(), 1)
	assert_null(host.state.directory.get_room(&"room_2"))


func test_someone_who_never_said_who_they_are_gets_nowhere() -> void:
	host.join(3, str(_room_id()), "pw")
	assert_eq(_got(3, &"on_join_result")[0][2][0], ERR_UNAUTHORIZED)
	host.check_deck(3, Decks.official_deck().to_dict(), [])
	host.set_ready(3, true)
	host.chat(3, "hi")
	assert_eq(_got(3, &"on_deck_checked"), [], "outside a room nothing is checked")
	assert_eq(_got(HOST, &"on_chat"), [])
