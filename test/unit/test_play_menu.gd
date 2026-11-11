extends GutTest

const FakeGitHub := preload("res://test/helpers/fake_github.gd")
const TEST_PROFILE_PATH := "user://test_play_profile/profile.cfg"

## The room list the screen reads, as GitHub would keep it.
var github: FakeGitHub


func before_each() -> void:
	github = FakeGitHub.new()


func after_each() -> void:
	DirAccess.remove_absolute(TEST_PROFILE_PATH)
	DirAccess.remove_absolute(TEST_PROFILE_PATH.get_base_dir())


## A lobby for a screen to use, with its room list on the fake GitHub. It looks for no public
## address, so hosting is quick and local.
func _make_lobby(state := Lobby.State.OFFLINE) -> Lobby:
	var lobby := Lobby.new()
	lobby.board = github.make_board()
	lobby.find_public_address = false
	add_child_autofree(lobby)
	lobby.state = state
	return lobby


## The room browser with its own profile (one with this name, or none at all for a first visit) and
## its own lobby. It does not read the list or connect anywhere by itself, nor leave the screen.
func _make_scene(player_name := "Tester", lobby: Lobby = null) -> Control:
	if lobby == null:
		lobby = _make_lobby()
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


## Puts a few rooms in the list and has the screen read it. The locked ones use the password
## "time".
func _show_example_rooms(scene: Control) -> void:
	github.add_room(RoomInfo.new(&"room_2", "Temporal Rift", "Aeon", 1, 2))
	github.add_room(RoomInfo.new(&"room_2", "Paradox Lounge", "Lyra", 1, 2, false, true, "time"), "wss://lyra.example")
	github.add_room(RoomInfo.new(&"room_3", "Home Game", "Nyx", 1, 2), "ws://192.168.1.20:9080", true)
	await scene.online.board.refresh()


func _listed(scene: Control) -> Array[String]:
	var names: Array[String] = []
	for row in (scene.get_node("%RoomList") as Control).get_children():
		if not row.is_queued_for_deletion():
			names.append((row.get_node("%RoomName") as Label).text)
	return names


## The id the list gives a room, found by name.
func _id_of(scene: Control, room_name: String) -> StringName:
	return scene.online.board.rooms.get_rooms(room_name)[0].id


## Pretends the connection to a host went through.
func _connect_to_host(scene: Control) -> void:
	scene.online.state = Lobby.State.CONNECTING
	scene.online.state_changed.emit()
	scene.online.state = Lobby.State.CONNECTED
	scene.online.state_changed.emit()


# --- Name ----------------------------------------------------------------------------------


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


# --- The room list -------------------------------------------------------------------------


func test_the_list_shows_the_rooms_on_github_with_their_padlocks() -> void:
	var scene := _make_scene()
	await _show_example_rooms(scene)
	assert_eq(_listed(scene), ["Home Game", "Paradox Lounge", "Temporal Rift"] as Array[String])
	assert_eq((scene.get_node("%Status") as Label).text, "", "no count of the rooms under the list")

	var locked: Array[String] = []
	for row in (scene.get_node("%RoomList") as Control).get_children():
		if not row.is_queued_for_deletion() and (row.get_node("%LockIcon") as LockIcon).locked:
			locked.append((row.get_node("%RoomName") as Label).text)
	assert_eq(locked, ["Paradox Lounge"] as Array[String], "a room with a password has its padlock")


func test_the_list_follows_github_and_can_be_searched() -> void:
	var scene := _make_scene()
	var empty: Label = scene.get_node("%EmptyLabel")
	assert_true(empty.visible, "no rooms yet")
	assert_string_contains(empty.text, "Host one")
	await _show_example_rooms(scene)
	assert_false(empty.visible)

	(scene.get_node("%SearchEdit") as LineEdit).text = "lyra"
	scene._on_search_changed("lyra")
	assert_eq(_listed(scene), ["Paradox Lounge"] as Array[String], "the host's name is searched too")
	(scene.get_node("%SearchEdit") as LineEdit).text = "nothing like it"
	scene._on_search_changed("")
	assert_string_contains(empty.text, "No open rooms match")
	(scene.get_node("%SearchEdit") as LineEdit).text = ""
	scene._on_search_changed("")

	for issue in github.issues:
		issue["state"] = "closed"
	await scene.online.board.refresh()
	assert_true(empty.visible, "rooms that are closed drop off")


func test_the_filters_open_in_a_window_that_holds_the_search_field() -> void:
	var scene := _make_scene()
	var window: Control = scene.get_node("%FiltersOverlay")
	var search: LineEdit = scene.get_node("%SearchEdit")
	assert_false(window.visible, "the filters start closed")
	assert_true(window.is_ancestor_of(search), "the search field is one of them")
	assert_false(search.is_visible_in_tree(), "so it is hidden with them")
	assert_true(window.is_ancestor_of(scene.get_node("%CardsOption")))
	assert_true(window.is_ancestor_of(scene.get_node("%PasswordOption")))
	assert_false(
		(scene.get_node("%Content") as Control).is_ancestor_of(window),
		"a window over the screen: it takes no room from the list"
	)

	await get_tree().process_frame
	var filters_button: Button = scene.get_node("%FiltersButton")
	assert_false(filters_button.button_pressed, "the button is not lit while the filters are closed")
	filters_button.pressed.emit()
	assert_true(window.visible, "the button opens the window")
	assert_true(search.is_visible_in_tree())
	assert_true(filters_button.button_pressed, "and is lit while they are open")
	await get_tree().process_frame

	var dialog: Control = scene.get_node("%FiltersDialog")
	var host: Control = scene.get_node("%HostButton")
	assert_gt(dialog.global_position.x, filters_button.global_position.x + filters_button.size.x, "it starts at the right of the Filters button")
	assert_almost_eq(dialog.global_position.y, filters_button.global_position.y, 0.5, "level with it, not under it")
	assert_lt(dialog.global_position.x + dialog.size.x, host.global_position.x, "and ends before the Host Room button")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	(scene.get_node("%FiltersBackdrop") as Control).gui_input.emit(click)
	assert_false(window.visible, "a click outside it closes it")
	assert_false(filters_button.button_pressed, "and the button goes dark again")

	filters_button.pressed.emit()
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	scene._unhandled_input(escape)
	assert_false(window.visible, "so does Escape")
	assert_null(scene.get_node_or_null("%FiltersDoneButton"), "there is no Done button: the list follows the filters as they change")


func test_refreshing_is_a_circular_arrow_at_the_top_right_of_the_list() -> void:
	var scene := _make_scene()
	await get_tree().process_frame
	var refresh: Control = scene.get_node("%RefreshButton")
	var list_panel: Control = scene.get_node("Content/Layout/ListPanel")
	assert_true(refresh is RefreshButton, "it is the arrow, not a text button")
	assert_eq((refresh as Button).text, "")
	assert_true(list_panel.is_ancestor_of(refresh), "it sits in the box of the list")
	var panel_rect := list_panel.get_global_rect()
	var corner := refresh.get_global_rect().get_center()
	assert_gt(corner.x, panel_rect.position.x + panel_rect.size.x * 0.9, "at its right")
	assert_lt(corner.y, panel_rect.position.y + 70.0, "at its top")
	assert_false((scene.get_node("Content/Layout/Toolbar") as Node).is_ancestor_of(refresh), "no longer in the toolbar")


func test_the_filters_narrow_the_list_even_when_closed() -> void:
	var scene := _make_scene()
	await _show_example_rooms(scene)
	var button: Button = scene.get_node("%FiltersButton")
	var cards: OptionButton = scene.get_node("%CardsOption")
	var password: OptionButton = scene.get_node("%PasswordOption")
	assert_eq(button.text, "Filters", "nothing narrows the list yet")

	cards.select(2)
	cards.item_selected.emit(2)
	assert_eq(cards.get_item_text(2), RoomInfo.MODE_CUSTOM)
	assert_eq(_listed(scene), ["Paradox Lounge"] as Array[String], "only rooms that allow custom cards")
	assert_eq(button.text, "Filters (1)", "the closed button says a filter is in use")

	cards.select(1)
	cards.item_selected.emit(1)
	assert_eq(_listed(scene), ["Home Game", "Temporal Rift"] as Array[String], "standard rooms")

	password.select(1)
	password.item_selected.emit(1)
	assert_eq(password.get_item_text(1), "Locked")
	assert_eq(_listed(scene), [] as Array[String], "no standard room is locked")
	assert_eq(button.text, "Filters (2)")
	var empty: Label = scene.get_node("%EmptyLabel")
	assert_true(empty.visible)
	assert_string_contains(empty.text, "these filters")

	cards.select(0)
	cards.item_selected.emit(0)
	assert_eq(_listed(scene), ["Paradox Lounge"] as Array[String], "locked rooms")
	password.select(2)
	password.item_selected.emit(2)
	assert_eq(password.get_item_text(2), "Unlocked")
	assert_eq(_listed(scene), ["Home Game", "Temporal Rift"] as Array[String], "unlocked rooms")

	(scene.get_node("%SearchEdit") as LineEdit).text = "nyx"
	scene._on_search_changed("nyx")
	assert_eq(_listed(scene), ["Home Game"] as Array[String], "with the search text as well")
	assert_eq(button.text, "Filters (2)")


func test_clear_empties_the_filters() -> void:
	var scene := _make_scene()
	await _show_example_rooms(scene)
	var search: LineEdit = scene.get_node("%SearchEdit")
	var cards: OptionButton = scene.get_node("%CardsOption")
	var password: OptionButton = scene.get_node("%PasswordOption")
	search.text = "lyra"
	cards.select(2)
	password.select(1)
	scene._rebuild_list()
	assert_eq(_listed(scene), ["Paradox Lounge"] as Array[String])
	assert_eq((scene.get_node("%FiltersButton") as Button).text, "Filters (3)")

	(scene.get_node("%ClearFiltersButton") as Button).pressed.emit()
	assert_eq(search.text, "")
	assert_eq(cards.selected, 0)
	assert_eq(password.selected, 0)
	assert_eq(_listed(scene), ["Home Game", "Paradox Lounge", "Temporal Rift"] as Array[String])
	assert_eq((scene.get_node("%FiltersButton") as Button).text, "Filters")


func test_the_list_says_why_it_is_empty() -> void:
	var scene := _make_scene()
	var empty: Label = scene.get_node("%EmptyLabel")
	github.down = true
	await scene.online.board.refresh()
	assert_string_contains(empty.text, "could not be reached")
	assert_string_contains(empty.text, "Refresh", "and what to do")
	assert_false((scene.get_node("%HostButton") as Button).disabled, "a room can still be hosted")

	scene.online.board.token = ""
	scene._rebuild_list()
	assert_eq(empty.text, "No rooms found", "without a token it just says there are no rooms")


# --- Hosting -------------------------------------------------------------------------------


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


func test_creating_a_room_starts_it_on_this_computer_and_puts_it_in_the_list() -> void:
	var scene := _make_scene()
	var overlay: Control = scene.get_node("%HostOverlay")
	var create: Button = scene.get_node("%CreateButton")
	var error: Label = scene.get_node("%FormError")
	scene._open_host_dialog()

	(scene.get_node("%RoomNameEdit") as LineEdit).text = "   "
	scene._create_room()
	assert_ne(error.text, "", "an empty name is refused")
	assert_false(create.disabled)
	assert_false(scene.online.is_player, "and no server was started for it")
	assert_eq(github.open_count(), 0, "nor anything put in the list")

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
	assert_eq(github.open_count(), 1, "the room is in the list")
	var entry := RoomBoard.read_issue(github.issues[0])
	assert_eq(entry["room_id"], str(scene.online.room.id), "with the id to join it by")
	assert_true(entry["locked"], "it says it has a password")
	assert_false(str(github.issues[0]["body"]).contains("pw"), "without giving the password away")

	scene.online.stop_hosting()
	assert_eq(github.open_count(), 0, "closing the room takes it off the list")


func test_creating_a_room_does_not_rebuild_the_list_once_the_screen_has_left() -> void:
	var scene := _make_scene()
	# Going to the room screen takes this screen out of the tree at once, and the list can still
	# change after that.
	var parent := scene.get_parent()
	scene.online.hosted.connect(func(_room: RoomInfo) -> void: parent.remove_child(scene))
	scene._open_host_dialog()
	(scene.get_node("%RoomNameEdit") as LineEdit).text = "My room"
	scene._create_room()
	assert_eq(scene.online.room.room_name, "My room", "the room is open")
	scene.online.board.rooms_changed.emit()
	assert_eq((scene.get_node("%RoomList") as Node).get_child_count(), 0, "and no rows were made off screen")


# --- Joining -------------------------------------------------------------------------------


func test_joining_a_room_with_a_password_asks_for_it_once_the_host_is_reached() -> void:
	var scene := _make_scene()
	await _show_example_rooms(scene)
	var overlay: Control = scene.get_node("%JoinOverlay")
	var password: LineEdit = scene.get_node("%JoinPasswordEdit")
	var error: Label = scene.get_node("%JoinError")

	scene._join_room(_id_of(scene, "lounge"))
	assert_string_contains((scene.get_node("%Status") as Label).text, "Joining “Paradox Lounge”")
	assert_false(overlay.visible, "not before the host has been reached")
	_connect_to_host(scene)
	assert_true(overlay.visible, "then the password is asked for")
	assert_string_contains((scene.get_node("%JoinRoomLabel") as Label).text, "Paradox Lounge")
	assert_true(password.secret)

	scene.online.on_join_result(ERR_UNAUTHORIZED, {}, "")
	assert_ne(error.text, "", "a wrong password is said so")
	assert_true(overlay.visible, "and the dialog stays to try again")

	var room := RoomInfo.new(&"room_2", "Paradox Lounge", "Lyra", 2, 2, false, true, "time")
	scene.online.on_join_result(OK, room.to_dict(), "Lyra")
	assert_false(overlay.visible, "the right password gets in")
	assert_eq(scene.online.room.room_name, "Paradox Lounge")
	assert_eq(scene.online.opponent_name, "Lyra")


func test_joining_a_room_without_a_password_does_not_ask() -> void:
	var scene := _make_scene()
	await _show_example_rooms(scene)
	scene._join_room(_id_of(scene, "temporal"))
	_connect_to_host(scene)
	assert_false((scene.get_node("%JoinOverlay") as Control).visible)
	assert_eq(scene._joining_id, &"room_2", "it asks the host for the room by the host's own id")


func test_cancelling_the_password_question_leaves_the_host() -> void:
	var scene := _make_scene()
	await _show_example_rooms(scene)
	scene._join_room(_id_of(scene, "lounge"))
	_connect_to_host(scene)
	(scene.get_node("%CancelJoinButton") as Button).pressed.emit()
	assert_false((scene.get_node("%JoinOverlay") as Control).visible)
	assert_eq(scene._target, {}, "nothing is being joined any more")
	assert_eq(scene.online.state, Lobby.State.OFFLINE)


func test_a_host_that_cannot_be_reached_is_taken_off_the_list() -> void:
	var scene := _make_scene()
	await _show_example_rooms(scene)
	var id := _id_of(scene, "temporal")
	scene._join_room(id)
	scene.online.state = Lobby.State.CONNECTING
	scene.online.state_changed.emit()
	scene.online.state = Lobby.State.OFFLINE
	scene.online.state_changed.emit()
	await get_tree().process_frame
	var status := (scene.get_node("%Status") as Label).text
	assert_string_contains(status, "Could not reach “Temporal Rift”")
	assert_string_contains(status, "taken off the list")
	assert_false(github.is_open(int(str(id))), "its issue is closed for everyone")
	assert_does_not_have(_listed(scene), "Temporal Rift")


func test_a_room_only_reachable_on_its_hosts_network_is_left_in_the_list() -> void:
	var scene := _make_scene()
	await _show_example_rooms(scene)
	var id := _id_of(scene, "home game")
	scene._join_room(id)
	scene.online.state = Lobby.State.CONNECTING
	scene.online.state_changed.emit()
	scene.online.state = Lobby.State.OFFLINE
	scene.online.state_changed.emit()
	assert_string_contains((scene.get_node("%Status") as Label).text, "host's network")
	assert_true(github.is_open(int(str(id))), "this computer may just not be on that network")


func test_a_room_that_is_gone_from_its_hosts_game_is_taken_off_the_list() -> void:
	var scene := _make_scene()
	await _show_example_rooms(scene)
	var id := _id_of(scene, "temporal")
	scene._join_room(id)
	_connect_to_host(scene)
	scene.online.on_join_result(ERR_DOES_NOT_EXIST, {}, "")
	await get_tree().process_frame
	assert_string_contains((scene.get_node("%Status") as Label).text, "closed")
	assert_false(github.is_open(int(str(id))))
	assert_eq(scene.online.state, Lobby.State.OFFLINE, "and the host's game is left")


func test_a_room_that_was_just_taken_is_explained() -> void:
	var scene := _make_scene()
	await _show_example_rooms(scene)
	var id := _id_of(scene, "temporal")
	scene._join_room(id)
	_connect_to_host(scene)
	scene.online.on_join_result(ERR_BUSY, {}, "")
	assert_string_contains((scene.get_node("%Status") as Label).text, "Temporal Rift")
	assert_string_contains((scene.get_node("%Status") as Label).text, "full")
	assert_true(github.is_open(int(str(id))), "a full room stays in the list")


func test_a_room_no_longer_in_the_list_is_said_to_be_closed() -> void:
	var scene := _make_scene()
	scene._join_room(&"12345")
	assert_string_contains((scene.get_node("%Status") as Label).text, "closed")


func test_a_notice_waiting_for_the_player_is_shown_once() -> void:
	var lobby := _make_lobby()
	lobby.notice = "The host closed the room."
	var scene := _make_scene("Tester", lobby)
	assert_eq((scene.get_node("%Status") as Label).text, "The host closed the room.")
	assert_eq(lobby.notice, "", "it is not shown again")
