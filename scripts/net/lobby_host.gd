class_name LobbyHost
extends RefCounted
## The rules of a room hosted on this computer, as the host's game applies them: who is in it,
## joining with the password, checking each player's deck, who is ready, starting the game, and
## passing chat between the two players.
##
## It keeps what it knows in a LobbyState and answers through `send`, so it holds no sockets: the
## Lobby node passes it what players ask for and delivers its answers (over the network, or
## straight back to the host's own game).

const MAX_CHAT_LENGTH := 200
## The second player of a local room has no connection: the host's game plays for them, under this
## peer number and name. (Real peers are positive.)
const SECOND_SEAT := -2
const SECOND_NAME := "Player 2"

## What the host knows: the players, the room, decks and readiness.
var state := LobbyState.new()
## The official cards (id -> CardData) and points list decks are checked with. Tests may set them;
## otherwise they are read from the game the first time a deck is checked.
var official_cards: Dictionary = {}
var points_list: PointsList

## Delivers a message to a player: (peer: int, method: StringName, args: Array).
var _send: Callable


func _init(send: Callable) -> void:
	_send = send


## A player connected and says who they are. The answer is on_hello_result.
func hello(peer: int, requested_name: String) -> void:
	_send.call(peer, &"on_hello_result", [state.register(peer, requested_name)])


## Opens the room this game hosts, for its own player. The answer is on_hosted. A local room (see
## RoomInfo) is only for its host: any card is allowed in it and no deck is turned down.
func open_room(
	peer: int, room_name: String, custom_cards: bool, password: String, local_room := false
) -> void:
	var result := state.host(peer, room_name, custom_cards, password, local_room)
	if result.has("error"):
		_send.call(peer, &"on_hosted", [{}, result["error"]])
	else:
		_send.call(peer, &"on_hosted", [(result["room"] as RoomInfo).to_dict(), ""])


## A player asks to join a room. The answer is on_join_result; the host hears on_opponent_joined.
func join(peer: int, room_id: String, password: String) -> void:
	var result := state.join(peer, StringName(room_id), password)
	if result.has("error"):
		_send.call(peer, &"on_join_result", [int(result["error"]), {}, ""])
		return
	var joined_room: RoomInfo = result["room"]
	_send.call(peer, &"on_join_result", [OK, joined_room.to_dict(), joined_room.host_name])
	_send.call(result["host_peer"], &"on_opponent_joined", [state.name_of(peer)])
	_send_ready_states(joined_room.id)


## The host of a local room takes the second seat, to control that player too. The host hears
## on_opponent_joined, as if someone had joined.
func seat_second_player(peer: int) -> void:
	state.register(SECOND_SEAT, SECOND_NAME)
	if state.seat_second_player(SECOND_SEAT, peer):
		_send.call(peer, &"on_opponent_joined", [SECOND_NAME])
		_send_ready_states(state.room_of(peer))


## The host of a local room gives up the second seat again, so they control one player.
func unseat_second_player(peer: int) -> void:
	if state.opponent_of(peer) == SECOND_SEAT:
		_tell_other_player(state.unregister(SECOND_SEAT))


## The host of a local room starts the game, as soon as every player in the room has a deck (which
## nothing is held against): there is nobody to wait for. Everyone in the room hears on_game_start.
func start_local_game(peer: int) -> void:
	var room_id := state.room_of(peer)
	var local := state.directory.get_room(room_id)
	if local == null or not local.local_room or local.in_game:
		return
	for player in state.players_in(room_id):
		if not state.deck_ok(player):
			_send.call(peer, &"on_deck_checked", [["Choose a deck first."]])
			return
	local.in_game = true
	for player in state.players_in(room_id):
		_send.call(player, &"on_game_start", [])


func leave(peer: int) -> void:
	_tell_other_player(state.leave(peer))


## A player's connection went: they leave their room.
func disconnected(peer: int) -> void:
	_tell_other_player(state.unregister(peer))


## Checks the deck a player chose (see DeckCheck.check_sent). The answer is on_deck_checked.
func check_deck(peer: int, deck_data: Dictionary, sent_cards: Array) -> void:
	var room_id := state.room_of(peer)
	var checked_room := state.directory.get_room(room_id)
	if checked_room == null:
		return
	if checked_room.local_room:
		# Anything goes in a local room, a deck that is not finished too.
		state.set_deck_ok(peer, true)
		_send.call(peer, &"on_deck_checked", [[]])
		return
	if official_cards.is_empty():
		official_cards = CardLibrary.new(CardLibrary.OFFICIAL_DIRECTORY).load_by_id(false)
	if points_list == null:
		points_list = PointsList.new()
	var found := DeckCheck.check_sent(deck_data, sent_cards, checked_room.custom_cards, official_cards, points_list)
	var was_ready := state.is_ready(peer)
	state.set_deck_ok(peer, found.is_empty())
	_send.call(peer, &"on_deck_checked", [found])
	if was_ready != state.is_ready(peer):
		_send_ready_states(room_id)


## A player says they are ready, or not any more. When both players are, the game starts.
func set_ready(peer: int, is_ready: bool) -> void:
	var room_id := state.room_of(peer)
	var ready_room := state.directory.get_room(room_id)
	if ready_room == null or ready_room.in_game:
		return
	if is_ready and not state.deck_ok(peer):
		_send.call(peer, &"on_deck_checked", [["Choose a deck that is allowed first."]])
		return
	state.set_ready(peer, is_ready)
	_send_ready_states(room_id)
	if state.both_ready(room_id):
		ready_room.in_game = true
		for player in state.players_in(room_id):
			_send.call(player, &"on_game_start", [])


## Passes a chat line to the other player in the room. (Whatever the game sends between the two
## players later goes the same way.)
func chat(peer: int, text: String) -> void:
	var other := state.opponent_of(peer)
	var clean := text.strip_edges().left(MAX_CHAT_LENGTH)
	if other != 0 and not clean.is_empty():
		_send.call(other, &"on_chat", [state.name_of(peer), clean])


## After someone left a room (see LobbyState.leave): tells the other player.
func _tell_other_player(left: Dictionary) -> void:
	var other: int = left.get("other", 0)
	if other == 0:
		return
	if left["closed"]:
		_send.call(other, &"on_room_closed", [])
	else:
		_send.call(other, &"on_opponent_left", [])
		_send_ready_states(state.room_of(other))


## Tells each player in a room whether they and the other player are ready.
func _send_ready_states(room_id: StringName) -> void:
	for player in state.players_in(room_id):
		_send.call(player, &"on_ready_state", [state.is_ready(player), state.is_ready(state.opponent_of(player))])
