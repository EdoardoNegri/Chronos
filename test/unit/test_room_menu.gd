extends GutTest

const TEST_PROFILE_PATH := "user://test_room_profile/profile.cfg"


func after_each() -> void:
	DirAccess.remove_absolute(TEST_PROFILE_PATH)
	DirAccess.remove_absolute(TEST_PROFILE_PATH.get_base_dir())


## The room screen as the host of "Test room", with `opponent` already there if given.
func _make_scene(opponent := "") -> Control:
	var lobby := Lobby.new()
	add_child_autofree(lobby)
	lobby.state = Lobby.State.CONNECTED
	lobby.room = RoomInfo.new(&"room_5", "Test room", "Aeon", 1 if opponent.is_empty() else 2, 2, false, true, "pw")
	lobby.opponent_name = opponent
	var profile: PlayerProfile = autofree(PlayerProfile.new(TEST_PROFILE_PATH))
	profile.set_player_name("Aeon")
	var scene: Control = load("res://scenes/room.tscn").instantiate()
	scene.online = lobby
	scene.profile = profile
	add_child_autofree(scene)
	return scene


func _chat_text(scene: Control) -> String:
	return (scene.get_node("%ChatLog") as RichTextLabel).get_parsed_text()


func test_the_room_shows_who_is_in_it() -> void:
	var scene := _make_scene()
	assert_eq((scene.get_node("%TitleLabel") as Label).text, "Test room")
	assert_string_contains((scene.get_node("%InfoLabel") as Label).text, "Custom cards")
	assert_string_contains((scene.get_node("%InfoLabel") as Label).text, "Password")
	assert_eq((scene.get_node("%YouLabel") as Label).text, "You: Aeon")
	assert_string_contains((scene.get_node("%OpponentLabel") as Label).text, "Waiting")
	assert_string_contains(_chat_text(scene), "Waiting for another player")


func test_a_player_who_joins_and_leaves_is_shown() -> void:
	var scene := _make_scene()
	scene.online.on_opponent_joined("Bob")
	assert_eq((scene.get_node("%OpponentLabel") as Label).text, "Opponent: Bob")
	assert_string_contains(_chat_text(scene), "Bob joined.")
	scene.online.on_opponent_left()
	assert_string_contains((scene.get_node("%OpponentLabel") as Label).text, "Waiting")
	assert_string_contains(_chat_text(scene), "Bob left the room.")


func test_a_player_who_joins_someone_elses_room_sees_them_at_once() -> void:
	var scene := _make_scene("Kairos")
	assert_eq((scene.get_node("%OpponentLabel") as Label).text, "Opponent: Kairos")
	assert_string_contains(_chat_text(scene), "You joined Test room.")


func test_chat_goes_both_ways() -> void:
	var scene := _make_scene("Bob")
	var edit: LineEdit = scene.get_node("%ChatEdit")
	edit.text = "  hello bob  "
	edit.text_submitted.emit(edit.text)
	assert_string_contains(_chat_text(scene), "Aeon: hello bob")
	assert_eq(edit.text, "", "the box is emptied for the next line")
	scene.online.on_chat("Bob", "hello alice")
	assert_string_contains(_chat_text(scene), "Bob: hello alice")


func test_chat_with_nobody_there_says_so_and_empty_lines_are_not_sent() -> void:
	var scene := _make_scene()
	var edit: LineEdit = scene.get_node("%ChatEdit")
	edit.text = "anyone?"
	edit.text_submitted.emit(edit.text)
	assert_string_contains(_chat_text(scene), "nobody to hear")
	assert_false(_chat_text(scene).contains("Aeon: anyone?"))
	var before := _chat_text(scene)
	edit.text = "   "
	edit.text_submitted.emit(edit.text)
	assert_eq(_chat_text(scene), before)


func test_chat_text_is_not_read_as_formatting() -> void:
	var scene := _make_scene("Bob")
	scene.online.on_chat("Bob", "[b]not bold[/b] [url=x]link[/url]")
	assert_string_contains(_chat_text(scene), "[b]not bold[/b] [url=x]link[/url]")


func test_leaving_empties_the_room() -> void:
	var scene := _make_scene("Bob")
	scene.change_scenes = false
	scene._leave()
	assert_null(scene.online.room, "the player is out of the room")
	assert_eq(scene.online.opponent_name, "")
