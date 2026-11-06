extends GutTest

## A port of its own, so the tests never meet a game that is really open.
const TEST_PORT := 47699


func _invite() -> Dictionary:
	return InviteLink.parse(InviteLink.make("ws://friend.example:9080", &"room_2", "Friend's room", true))


## An inbox in the tree that does not touch the window or the scene.
func _make_inbox(lobby: Lobby = null) -> InviteInbox:
	var inbox := InviteInbox.new()
	inbox.port = TEST_PORT
	inbox.change_scenes = false
	inbox.online = lobby
	add_child_autofree(inbox)
	return inbox


func test_only_the_first_game_listens() -> void:
	var first := _make_inbox()
	var second := _make_inbox()
	assert_true(first.listen(), "the first game open listens")
	assert_false(second.listen(), "a second one finds the port taken")
	assert_false(second.is_listening())


func test_a_link_handed_to_the_open_game_waits_there_to_be_followed() -> void:
	var lobby := Lobby.new()
	add_child_autofree(lobby)
	var open_game := _make_inbox(lobby)
	assert_true(open_game.listen())
	watch_signals(open_game)
	watch_signals(lobby)

	var started_by_link := _make_inbox()
	var handed_off: bool = await started_by_link.hand_off(_invite())

	assert_true(handed_off, "the open game says it got the link")
	assert_signal_emitted(open_game, "received")
	assert_signal_emitted(lobby, "invite_opened")
	assert_eq(lobby.pending_invite["room_id"], "room_2", "the link waits for the Play screen")
	assert_eq(lobby.pending_invite["room_name"], "Friend's room")
	assert_true(lobby.pending_invite["locked"])


func test_with_no_open_game_the_link_is_not_handed_off() -> void:
	var started_by_link := _make_inbox()
	var handed_off: bool = await started_by_link.hand_off(_invite())
	assert_false(handed_off, "the game carries on and follows the link itself")


func test_something_that_is_not_a_link_is_ignored() -> void:
	var lobby := Lobby.new()
	add_child_autofree(lobby)
	var open_game := _make_inbox(lobby)
	assert_true(open_game.listen())
	watch_signals(open_game)

	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", TEST_PORT)
	for _frame in 30:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		await get_tree().process_frame
	peer.put_data("hello\n".to_utf8_buffer())
	for _frame in 10:
		await get_tree().process_frame
	peer.disconnect_from_host()

	assert_signal_not_emitted(open_game, "received")
	assert_eq(lobby.pending_invite, {})
