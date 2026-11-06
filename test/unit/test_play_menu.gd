extends GutTest

const TEST_PROFILE_PATH := "user://test_play_profile/profile.cfg"
const SHARED_SERVER := "ws://shared.example:9080"


func after_each() -> void:
	DirAccess.remove_absolute(TEST_PROFILE_PATH)
	DirAccess.remove_absolute(TEST_PROFILE_PATH.get_base_dir())


## A lobby for a screen to use. It looks for no public address, so hosting is quick and local.
func _make_lobby(state := Lobby.State.OFFLINE) -> Lobby:
	var lobby := Lobby.new()
	lobby.find_public_address = false
	add_child_autofree(lobby)
	lobby.state = state
	return lobby


## The room browser with its own profile (one with this name, or none at all for a first visit) and
## its own lobby, in the given state. It does not connect anywhere or leave the screen. With
## `with_server` the profile names a shared server to list rooms from, which is not so by default.
func _make_scene(player_name := "Tester", state := Lobby.State.CONNECTED, with_server := true, lobby: Lobby = null) -> Control:
	if lobby == null:
		lobby = _make_lobby(state)
	var profile: PlayerProfile = autofree(PlayerProfile.new(TEST_PROFILE_PATH))
	if not player_name.is_empty():
		profile.set_player_name(player_name)
	if with_server:
		profile.set_server_url(SHARED_SERVER)
	var scene: Control = load("res://scenes/play.tscn").instantiate()
	scene.profile = profile
	scene.online = lobby
	scene.auto_connect = false
	scene.change_scenes = false
	add_child_autofree(scene)
	return scene


## Gives the screen's lobby the example rooms, as a server would.
func _show_example_rooms(scene: Control) -> RoomDirectory:
	var examples := RoomDirectory.with_examples()
	scene.online.on_rooms(examples.open_snapshot())
	return examples


func _listed(scene: Control) -> Array[String]:
	var names: Array[String] = []
	for row in (scene.get_node("%RoomList") as Control).get_children():
		if not row.is_queued_for_deletion():
			names.append((row.get_node("%RoomName") as Label).text)
	return names


func _invite(locked := false, address := "ws://friend.example:9080") -> Dictionary:
	return InviteLink.parse(InviteLink.make(address, &"room_2", "Friend's room", locked))


func test_the_first_visit_asks_for_a_name_and_nothing_else() -> void:
	var scene := _make_scene("")
	var overlay: Control = scene.get_node("%AccountOverlay")
	assert_true(overlay.visible, "a player with no name is asked for one")
	var texts: Array[String] = []
	for label: Label in overlay.find_children("*", "Label", true, false):
		texts.append(label.text)
	assert_string_contains(" ".join(texts), "no email", "it says that no email is needed")
	var fields: Array[Node] = overlay.find_children("*", "LineEdit", true, false)
	assert_eq(fields.size(), 1, "one field: the name, no email and no password")

	var name_edit: LineEdit = scene.get_node("%AccountNameEdit")
	var error: Label = scene.get_node("%AccountError")
	(scene.get_node("%AccountContinueButton") as Button).pressed.emit()
	assert_ne(error.text, "", "a name is needed to go on")
	assert_true(overlay.visible)
	assert_false(scene.profile.has_account())

	name_edit.text = "Aeon"
	name_edit.text_submitted.emit("Aeon")
	assert_false(overlay.visible, "with a name it carries on to the rooms")
	assert_eq(scene.profile.player_name, "Aeon")


func test_a_player_with_a_name_is_not_asked_again() -> void:
	var scene := _make_scene("Aeon")
	assert_false((scene.get_node("%AccountOverlay") as Control).visible)


func test_the_name_is_remembered_for_the_next_visit() -> void:
	var scene := _make_scene("")
	(scene.get_node("%AccountNameEdit") as LineEdit).text = "Kairos"
	(scene.get_node("%AccountContinueButton") as Button).pressed.emit()
	var later := _make_scene("")
	assert_eq(later.profile.player_name, "Kairos", "the saved name is read back")
	assert_false((later.get_node("%AccountOverlay") as Control).visible)


func test_the_list_shows_only_rooms_with_a_free_seat() -> void:
	var scene := _make_scene()
	var examples := _show_example_rooms(scene)
	var listed := _listed(scene)
	assert_has(listed, "Temporal Rift", "an open room is listed")
	assert_does_not_have(listed, "Last Second", "a full room is not")
	assert_does_not_have(listed, "Midnight Duel", "nor one in a game")
	assert_eq(listed.size(), examples.get_room_count(true))
	assert_eq((scene.get_node("%Status") as Label).text, "", "no count of the rooms under the list")

	var locked: Array[String] = []
	for row in (scene.get_node("%RoomList") as Control).get_children():
		if not row.is_queued_for_deletion() and (row.get_node("%LockIcon") as LockIcon).locked:
			locked.append((row.get_node("%RoomName") as Label).text)
	assert_has(locked, "Paradox Lounge", "a room with a password has its padlock")
	assert_does_not_have(locked, "Temporal Rift")


func test_the_list_follows_what_a_shared_server_sends() -> void:
	var scene := _make_scene()
	assert_true((scene.get_node("%EmptyLabel") as Label).visible, "no rooms yet")
	assert_string_contains((scene.get_node("%EmptyLabel") as Label).text, "Host one")
	_show_example_rooms(scene)
	assert_false((scene.get_node("%EmptyLabel") as Label).visible)
	scene.online.on_rooms([])
	assert_true((scene.get_node("%EmptyLabel") as Label).visible, "a room that is taken drops off")


func test_with_no_shared_server_the_list_says_how_to_play_with_a_friend() -> void:
	var scene := _make_scene("Tester", Lobby.State.OFFLINE, false)
	var empty: Label = scene.get_node("%EmptyLabel")
	assert_true(empty.visible)
	assert_string_contains(empty.text, "Host a room")
	assert_string_contains(empty.text, "link")
	assert_false((scene.get_node("%HostButton") as Button).disabled, "hosting needs no server")


func test_when_the_shared_server_is_not_there_the_list_says_why() -> void:
	var scene := _make_scene("Tester", Lobby.State.OFFLINE)
	var empty: Label = scene.get_node("%EmptyLabel")
	assert_string_contains(empty.text, "Not connected")
	assert_string_contains(empty.text, "Settings", "and where to fix it")
	assert_false((scene.get_node("%HostButton") as Button).disabled, "but a friend's room can still be hosted")

	scene.online.error_text = "Could not reach the server at ws://x."
	scene.online.state_changed.emit()
	assert_string_contains(empty.text, "Could not reach the server")

	scene.online.state = Lobby.State.CONNECTING
	scene.online.state_changed.emit()
	assert_string_contains(empty.text, "Connecting")


func test_play_menu_hosts_a_room_in_the_chosen_game_mode() -> void:
	var scene := _make_scene()
	var option: OptionButton = scene.get_node("%GameModeOption")
	assert_eq(option.get_item_text(0), "Standard")
	assert_eq(option.get_item_text(1), "Custom cards")
	scene._open_host_dialog()
	assert_eq(option.selected, 0, "rooms are standard unless the host chooses otherwise")
	assert_eq((scene.get_node("%RoomNameEdit") as LineEdit).text, "Tester's room")


func test_the_host_dialog_has_a_password_and_no_player_count() -> void:
	var scene := _make_scene()
	assert_null(scene.get_node_or_null("%MaxPlayersSpin"), "a game is between two players")
	var password: LineEdit = scene.get_node("%PasswordEdit")
	assert_true(password.secret, "the password is hidden as it is typed")
	scene._open_host_dialog()
	assert_eq(password.text, "", "no password unless one is typed")


func test_creating_a_room_starts_it_on_this_computer_with_an_invite_link() -> void:
	var scene := _make_scene("Tester", Lobby.State.OFFLINE, false)
	var overlay: Control = scene.get_node("%HostOverlay")
	var create: Button = scene.get_node("%CreateButton")
	var error: Label = scene.get_node("%FormError")
	scene._open_host_dialog()

	(scene.get_node("%RoomNameEdit") as LineEdit).text = "   "
	scene._create_room()
	assert_ne(error.text, "", "an empty name is refused")
	assert_false(create.disabled)
	assert_false(scene.online.is_server, "and no server was started for it")

	scene.online.host_failed.emit("Could not start a server on this computer.")
	assert_eq(error.text, "Could not start a server on this computer.", "a reason from the lobby is shown")
	assert_false(create.disabled, "and the player can try again")

	(scene.get_node("%RoomNameEdit") as LineEdit).text = "My room"
	(scene.get_node("%PasswordEdit") as LineEdit).text = "pw"
	scene._create_room()
	assert_false(overlay.visible, "the dialog closes when the room is open")
	assert_true(scene.online.is_player, "the room runs on this computer")
	assert_eq(scene.online.room.room_name, "My room")
	assert_true(scene.online.room.has_password())
	var link := InviteLink.parse(scene.online.invite_link)
	assert_eq(link["room_id"], str(scene.online.room.id), "the link is for this room")
	assert_true(link["locked"], "and says it has a password")
	assert_false(scene.online.invite_link.contains("pw"), "without giving the password away")


func test_creating_a_room_does_not_rebuild_the_list_once_the_screen_has_left() -> void:
	var scene := _make_scene("Tester", Lobby.State.OFFLINE, false)
	# Going to the room screen takes this screen out of the tree at once, and only then does the
	# lobby send the rooms that are open now.
	var parent := scene.get_parent()
	scene.online.hosted.connect(func(_room: RoomInfo) -> void: parent.remove_child(scene))
	scene._open_host_dialog()
	(scene.get_node("%RoomNameEdit") as LineEdit).text = "My room"
	scene._create_room()
	assert_eq(scene.online.room.room_name, "My room", "the room is open")
	assert_eq((scene.get_node("%RoomList") as Node).get_child_count(), 0, "and no rows were made off screen")


func test_joining_a_room_with_a_password_asks_for_it() -> void:
	var scene := _make_scene()
	_show_example_rooms(scene)
	var locked: RoomInfo = scene.online.rooms.get_rooms("lounge")[0]
	var overlay: Control = scene.get_node("%JoinOverlay")
	var password: LineEdit = scene.get_node("%JoinPasswordEdit")
	var error: Label = scene.get_node("%JoinError")

	scene._join_room(locked.id)
	assert_true(overlay.visible, "a locked room asks for its password first")
	assert_string_contains((scene.get_node("%JoinRoomLabel") as Label).text, "Paradox Lounge")
	assert_true(password.secret)

	scene.online.on_join_result(ERR_UNAUTHORIZED, {}, "")
	assert_ne(error.text, "", "a wrong password is said so")
	assert_true(overlay.visible, "and the dialog stays to try again")

	scene.online.on_join_result(OK, locked.to_dict(), locked.host_name)
	assert_false(overlay.visible, "the right password gets in")
	assert_eq(scene.online.room.room_name, "Paradox Lounge")
	assert_eq(scene.online.opponent_name, "Lyra")


func test_joining_a_room_without_a_password_does_not_ask() -> void:
	var scene := _make_scene()
	_show_example_rooms(scene)
	var open: RoomInfo = scene.online.rooms.get_rooms("temporal")[0]
	scene._join_room(open.id)
	assert_false((scene.get_node("%JoinOverlay") as Control).visible)


func test_a_room_that_was_just_taken_is_explained() -> void:
	var scene := _make_scene()
	_show_example_rooms(scene)
	var open: RoomInfo = scene.online.rooms.get_rooms("temporal")[0]
	scene._join_room(open.id)
	scene.online.on_join_result(ERR_BUSY, {}, "")
	assert_string_contains((scene.get_node("%Status") as Label).text, "Temporal Rift")
	assert_string_contains((scene.get_node("%Status") as Label).text, "full")
	scene.online.on_join_result(ERR_ALREADY_IN_USE, {}, "")
	assert_string_contains((scene.get_node("%Status") as Label).text, "already in a room")


func test_a_notice_waiting_for_the_player_is_shown_once() -> void:
	var lobby := _make_lobby()
	lobby.notice = "The host closed the room."
	var scene := _make_scene("Tester", Lobby.State.OFFLINE, true, lobby)
	assert_eq((scene.get_node("%Status") as Label).text, "The host closed the room.")
	assert_eq(lobby.notice, "", "it is not shown again")


# --- Invite links --------------------------------------------------------------------------


func test_a_link_opened_while_on_this_screen_joins_the_room_in_it() -> void:
	var lobby := _make_lobby(Lobby.State.CONNECTED)
	lobby.server_url = "ws://friend.example:9080"
	lobby.player_name = "Tester"
	var scene := _make_scene("Tester", Lobby.State.CONNECTED, false, lobby)
	lobby.open_invite(_invite())
	assert_eq(lobby.pending_invite, {}, "it is used once")
	assert_string_contains((scene.get_node("%Status") as Label).text, "Friend's room", "it says which room it is joining")
	lobby.on_join_result(OK, RoomInfo.new(&"room_2", "Friend's room", "Kairos", 2, 2).to_dict(), "Kairos")
	assert_eq(lobby.room.room_name, "Friend's room", "and joins it")
	assert_eq(lobby.opponent_name, "Kairos")


func test_a_link_to_a_room_with_a_password_asks_for_it_once_connected() -> void:
	var lobby := _make_lobby(Lobby.State.OFFLINE)
	var scene := _make_scene("Tester", Lobby.State.OFFLINE, false, lobby)
	var overlay: Control = scene.get_node("%JoinOverlay")
	scene._start_invite(_invite(true))
	assert_false(overlay.visible, "not before the host has been reached")
	lobby.state = Lobby.State.CONNECTED
	lobby.state_changed.emit()
	assert_true(overlay.visible, "then the password is asked for")
	assert_string_contains((scene.get_node("%JoinRoomLabel") as Label).text, "Friend's room")

	lobby.on_join_result(ERR_UNAUTHORIZED, {}, "")
	assert_ne((scene.get_node("%JoinError") as Label).text, "")
	assert_true(overlay.visible, "a wrong password can be tried again")
	lobby.on_join_result(OK, RoomInfo.new(&"room_2", "Friend's room", "Kairos", 2, 2, false, false, "pw").to_dict(), "Kairos")
	assert_false(overlay.visible)
	assert_eq(lobby.room.room_name, "Friend's room")


func test_cancelling_the_password_question_gives_up_on_the_link() -> void:
	var lobby := _make_lobby(Lobby.State.OFFLINE)
	var scene := _make_scene("Tester", Lobby.State.OFFLINE, false, lobby)
	scene._start_invite(_invite(true))
	lobby.state = Lobby.State.CONNECTED
	lobby.state_changed.emit()
	(scene.get_node("%CancelJoinButton") as Button).pressed.emit()
	assert_false((scene.get_node("%JoinOverlay") as Control).visible)
	assert_eq(scene._invite, {}, "nothing is followed any more")


func test_a_host_that_cannot_be_reached_is_said_so() -> void:
	var lobby := _make_lobby(Lobby.State.OFFLINE)
	var scene := _make_scene("Tester", Lobby.State.OFFLINE, false, lobby)
	scene._start_invite(_invite())
	lobby.state = Lobby.State.CONNECTING
	lobby.state_changed.emit()
	lobby.state = Lobby.State.OFFLINE
	lobby.state_changed.emit()
	var status := (scene.get_node("%Status") as Label).text
	assert_string_contains(status, "Could not reach")
	assert_string_contains(status, "Friend's room")


func test_a_room_that_is_gone_is_said_so_when_following_a_link() -> void:
	var lobby := _make_lobby(Lobby.State.CONNECTED)
	lobby.server_url = "ws://friend.example:9080"
	lobby.player_name = "Tester"
	var scene := _make_scene("Tester", Lobby.State.CONNECTED, false, lobby)
	scene._start_invite(_invite())
	lobby.on_join_result(ERR_DOES_NOT_EXIST, {}, "")
	assert_string_contains((scene.get_node("%Status") as Label).text, "closed")
	assert_eq(scene._invite, {})


func test_a_link_the_game_was_started_with_is_followed() -> void:
	var lobby := _make_lobby(Lobby.State.CONNECTED)
	lobby.server_url = "ws://friend.example:9080"
	lobby.player_name = "Tester"
	lobby.pending_invite = _invite()
	var scene := _make_scene("Tester", Lobby.State.CONNECTED, false, lobby)
	assert_eq(lobby.pending_invite, {}, "it is used once")
	assert_string_contains((scene.get_node("%Status") as Label).text, "Joining")
	lobby.on_join_result(OK, RoomInfo.new(&"room_2", "Friend's room", "Kairos", 2, 2).to_dict(), "Kairos")
	assert_eq(lobby.room.room_name, "Friend's room")


func test_a_link_opened_before_there_is_a_name_waits_for_one() -> void:
	var lobby := _make_lobby(Lobby.State.CONNECTED)
	lobby.server_url = "ws://friend.example:9080"
	lobby.pending_invite = _invite()
	var scene := _make_scene("", Lobby.State.CONNECTED, false, lobby)
	assert_true((scene.get_node("%AccountOverlay") as Control).visible, "the name comes first")
	assert_eq(scene._invite, {}, "the link has not been followed yet")
	var edit: LineEdit = scene.get_node("%AccountNameEdit")
	edit.text = "Kairos"
	edit.text_submitted.emit("Kairos")
	assert_eq(scene._invite["room_id"], "room_2", "and then the link is followed")


# --- The question about opening invite links -----------------------------------------------


## Stands in for the real link setup, which would change the registry.
class FakeLinks:
	extends LinkHandler
	var registered := false

	func is_supported() -> bool:
		return true

	func register() -> Error:
		registered = true
		return OK


func _links_dialog(scene: Control) -> ConfirmationDialog:
	for child in scene.get_children():
		if child is ConfirmationDialog:
			return child
	return null


func test_the_game_asks_before_it_lets_links_open_it() -> void:
	var scene := _make_scene()
	var fake := FakeLinks.new()
	scene.links = fake
	scene._offer_links_once(true)
	var dialog := _links_dialog(scene)
	assert_not_null(dialog, "the question is shown")
	assert_true(dialog.visible)
	assert_false(fake.registered, "nothing is changed until the player says yes")
	assert_eq(dialog.ok_button_text, "Yes, allow")
	assert_eq(dialog.cancel_button_text, "Not now")
	assert_string_contains(dialog.dialog_text, "Settings", "it says it can be turned off again")

	dialog.confirmed.emit()
	assert_true(fake.registered, "yes sets links up")
	assert_true(scene.profile.links_setup_done, "and it is not asked again")
	assert_string_contains((scene.get_node("%Status") as Label).text, "now open Chronos")


func test_saying_not_now_changes_nothing_and_is_not_asked_again() -> void:
	var scene := _make_scene()
	var fake := FakeLinks.new()
	scene.links = fake
	scene._offer_links_once(true)
	_links_dialog(scene).canceled.emit()
	assert_false(fake.registered)
	assert_true(scene.profile.links_setup_done)
	var before := scene.get_child_count()
	scene._offer_links_once()
	assert_eq(scene.get_child_count(), before, "the question is not asked again")


func test_the_question_is_not_asked_when_running_from_the_editor() -> void:
	var scene := _make_scene()
	scene.links = FakeLinks.new()
	scene._offer_links_once()
	assert_null(_links_dialog(scene), "only the real game asks")
