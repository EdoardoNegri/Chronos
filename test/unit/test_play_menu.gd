extends GutTest

const TEST_PROFILE_PATH := "user://test_play_profile/profile.cfg"


func after_each() -> void:
	DirAccess.remove_absolute(TEST_PROFILE_PATH)
	DirAccess.remove_absolute(TEST_PROFILE_PATH.get_base_dir())


## The room browser with its own profile (one with this name, or none at all for a first visit) and
## its own lobby, in the given state. It does not connect anywhere or leave the screen.
func _make_scene(player_name := "Tester", state := Lobby.State.CONNECTED) -> Control:
	var lobby := Lobby.new()
	add_child_autofree(lobby)
	lobby.state = state
	var profile: PlayerProfile = autofree(PlayerProfile.new(TEST_PROFILE_PATH))
	if not player_name.is_empty():
		profile.set_player_name(player_name)
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


func test_the_list_follows_what_the_server_sends() -> void:
	var scene := _make_scene()
	assert_true((scene.get_node("%EmptyLabel") as Label).visible, "no rooms yet")
	assert_string_contains((scene.get_node("%EmptyLabel") as Label).text, "Host one")
	_show_example_rooms(scene)
	assert_false((scene.get_node("%EmptyLabel") as Label).visible)
	scene.online.on_rooms([])
	assert_true((scene.get_node("%EmptyLabel") as Label).visible, "a room that is taken drops off")


func test_without_a_server_the_list_says_why() -> void:
	var scene := _make_scene("Tester", Lobby.State.OFFLINE)
	var empty: Label = scene.get_node("%EmptyLabel")
	assert_true(empty.visible)
	assert_string_contains(empty.text, "Not connected")
	assert_string_contains(empty.text, "Settings", "and where to fix it")
	assert_true((scene.get_node("%HostButton") as Button).disabled, "no rooms can be opened")

	scene.online.error_text = "Could not reach the server at ws://x."
	scene.online.state_changed.emit()
	assert_string_contains(empty.text, "Could not reach the server")

	scene.online.state = Lobby.State.CONNECTING
	scene.online.state_changed.emit()
	assert_string_contains(empty.text, "Connecting")

	scene.online.state = Lobby.State.CONNECTED
	scene.online.state_changed.emit()
	assert_false((scene.get_node("%HostButton") as Button).disabled, "with a server rooms can be opened")


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


func test_creating_a_room_waits_for_the_server_and_then_goes_to_it() -> void:
	var scene := _make_scene()
	var overlay: Control = scene.get_node("%HostOverlay")
	var create: Button = scene.get_node("%CreateButton")
	var error: Label = scene.get_node("%FormError")
	scene._open_host_dialog()

	(scene.get_node("%RoomNameEdit") as LineEdit).text = "   "
	scene._create_room()
	assert_ne(error.text, "", "an empty name is refused before asking the server")
	assert_false(create.disabled)

	(scene.get_node("%RoomNameEdit") as LineEdit).text = "Taken name"
	scene._create_room()
	assert_true(create.disabled, "it waits for the server's answer")
	scene.online.on_hosted({}, "A room with that name already exists.")
	assert_eq(error.text, "A room with that name already exists.", "the server's reason is shown")
	assert_false(create.disabled, "and the player can try again")
	assert_true(overlay.visible)

	var entered := [false]
	scene.online.hosted.connect(func(_room: RoomInfo) -> void: entered[0] = true)
	scene.online.on_hosted(RoomInfo.new(&"room_5", "Taken name", "Tester", 1, 2).to_dict(), "")
	assert_false(overlay.visible, "the dialog closes when the room is open")
	assert_true(entered[0])
	assert_eq(scene.online.room.room_name, "Taken name")


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
	var lobby := Lobby.new()
	add_child_autofree(lobby)
	lobby.notice = "The host closed the room."
	var profile: PlayerProfile = autofree(PlayerProfile.new(TEST_PROFILE_PATH))
	profile.set_player_name("Tester")
	var scene: Control = load("res://scenes/play.tscn").instantiate()
	scene.profile = profile
	scene.online = lobby
	scene.auto_connect = false
	scene.change_scenes = false
	add_child_autofree(scene)
	assert_eq((scene.get_node("%Status") as Label).text, "The host closed the room.")
	assert_eq(lobby.notice, "", "it is not shown again")
