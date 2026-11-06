extends GutTest

const Decks := preload("res://test/helpers/decks.gd")
const TEST_PROFILE_PATH := "user://test_room_profile/profile.cfg"
const TEST_DECKS := "user://test_room_decks"
const TEST_CARDS := "user://test_room_cards"


func before_each() -> void:
	var decks := DeckLibrary.new(TEST_DECKS)
	var official := Decks.official_deck()
	decks.save_deck(official)
	# The same with a custom card in it: only for rooms that allow custom cards.
	var custom_card := CardData.new()
	custom_card.id = "custom_test_card"
	custom_card.card_name = "Test Golem"
	custom_card.points = 1
	CardLibrary.new(TEST_CARDS).save_card(custom_card)
	var custom := DeckData.from_dict(official.to_dict())
	custom.deck_name = "Custom deck"
	custom.add("custom_test_card")
	decks.save_deck(custom)
	# Too small to be played anywhere.
	var small := DeckData.new()
	small.deck_name = "Small deck"
	small.add("official_zap")
	decks.save_deck(small)


func after_each() -> void:
	DirAccess.remove_absolute(TEST_PROFILE_PATH)
	DirAccess.remove_absolute(TEST_PROFILE_PATH.get_base_dir())
	for folder in [TEST_DECKS, TEST_CARDS]:
		for file_name in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(folder.path_join(file_name))
		DirAccess.remove_absolute(folder)


## The room screen as the host of "Test room", with `opponent` already there if given. The room
## allows custom cards unless `standard`.
func _make_scene(opponent := "", standard := false) -> Control:
	var lobby := Lobby.new()
	add_child_autofree(lobby)
	lobby.state = Lobby.State.CONNECTED
	lobby.room = RoomInfo.new(&"room_5", "Test room", "Aeon", 1 if opponent.is_empty() else 2, 2, false, not standard, "pw")
	lobby.opponent_name = opponent
	var profile: PlayerProfile = autofree(PlayerProfile.new(TEST_PROFILE_PATH))
	profile.set_player_name("Aeon")
	var scene: Control = load("res://scenes/room.tscn").instantiate()
	scene.online = lobby
	scene.profile = profile
	scene.change_scenes = false
	scene.decks = DeckLibrary.new(TEST_DECKS)
	scene.catalog = CardCatalog.new(CardLibrary.new(CardLibrary.OFFICIAL_DIRECTORY), CardLibrary.new(TEST_CARDS))
	scene.points_list = PointsList.new("user://no_points_list.json")
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


func _console_lines(scene: Control) -> Array[String]:
	var lines: Array[String] = []
	for line in _chat_text(scene).split("\n", false):
		if line.begins_with("Console: "):
			lines.append(line.trim_prefix("Console: "))
	return lines


func test_the_room_can_only_be_left_with_the_back_arrow_and_has_no_status_box() -> void:
	var scene := _make_scene()
	assert_null(scene.get_node_or_null("%LeaveButton"), "no Leave button")
	assert_null(scene.get_node_or_null("%ListingPanel"), "no box for the room's status")
	assert_not_null(scene.get_node_or_null("%BackButton"))
	scene.online.on_opponent_joined("Bob")
	(scene.get_node("%BackButton") as Button).pressed.emit()
	assert_null(scene.online.room, "the back arrow leaves the room")


func test_the_game_speaks_in_the_chat_as_console_in_yellow() -> void:
	var scene := _make_scene()
	assert_has(_console_lines(scene), "Waiting for another player to join.")
	var chat_log: RichTextLabel = scene.get_node("%ChatLog")
	assert_string_contains(chat_log.text, "[color=#%s]Console: Waiting" % scene.CONSOLE_COLOR)


func test_the_host_is_told_in_the_chat_whether_the_room_is_listed() -> void:
	var scene := _make_scene()
	scene.online.is_player = true
	scene.online.listing_note = "Adding your room to the list…"
	scene.online.listing_changed.emit()
	scene.online.listing_changed.emit()
	scene.online.listing_note = "Your room is in the list."
	scene.online.listing_changed.emit()
	var lines := _console_lines(scene)
	assert_eq(lines.count("Adding your room to the list…"), 1, "each news once")
	assert_has(lines, "Your room is in the list.")
	scene.online.is_player = false


func test_only_the_decks_that_can_be_played_in_the_room_are_offered() -> void:
	var custom_room := _make_scene()
	assert_eq(custom_room._allowed, ["Custom deck", "Official deck"] as Array[String], "too small a deck is left out")
	var standard_room := _make_scene("", true)
	assert_eq(standard_room._allowed, ["Official deck"] as Array[String], "custom cards are not allowed in a Standard room")

	var edit: LineEdit = custom_room.get_node("%DeckEdit")
	edit.text = "cust"
	edit.caret_column = 4
	custom_room._deck_suggestions.refresh()
	assert_eq(custom_room._deck_suggestions.suggested, ["Custom deck"] as Array[String], "typing searches the names")
	edit.text = "deck"
	custom_room._deck_suggestions.refresh()
	assert_eq(custom_room._deck_suggestions.suggested.size(), 2, "anywhere in the name")
	custom_room._deck_suggestions.accept(1)
	assert_eq(edit.text, "Official deck", "a suggestion fills in the whole name")
	assert_eq(custom_room._chosen, "Official deck", "and chooses it")
	# The suggestion buttons that were replaced are freed at the end of the frame.
	await get_tree().process_frame


func test_a_room_with_no_deck_that_can_be_played_says_so() -> void:
	for file_name in DirAccess.get_files_at(TEST_DECKS):
		DirAccess.remove_absolute(TEST_DECKS.path_join(file_name))
	var scene := _make_scene()
	var said := " ".join(_console_lines(scene))
	assert_string_contains(said, "no deck that can be played")
	assert_true((scene.get_node("%ReadyButton") as Button).disabled)


func test_ready_can_only_be_pressed_once_the_host_has_checked_the_deck() -> void:
	var scene := _make_scene("Bob")
	var ready_button: Button = scene.get_node("%ReadyButton")
	var edit: LineEdit = scene.get_node("%DeckEdit")
	assert_true(ready_button.disabled, "nothing chosen yet")

	edit.text = "official DECK"
	edit.text_submitted.emit(edit.text)
	assert_eq(edit.text, "Official deck")
	assert_has(_console_lines(scene), "Checking “Official deck”…")
	assert_true(ready_button.disabled, "not before the host says the deck can be played")

	scene.online.on_deck_checked(["Over the point budget by 3"])
	assert_true(ready_button.disabled)
	assert_has(_console_lines(scene), "“Official deck” cannot be played: Over the point budget by 3.")

	scene.online.on_deck_checked([])
	assert_false(ready_button.disabled, "the host's check is what allows it")
	assert_has(_console_lines(scene), "“Official deck” can be played. Press Ready when you are.")

	edit.text = "Something else"
	edit.text_changed.emit(edit.text)
	assert_true(ready_button.disabled, "typing another deck gives up the one that was checked")


func test_a_deck_that_is_not_there_is_said_so() -> void:
	var scene := _make_scene()
	var edit: LineEdit = scene.get_node("%DeckEdit")
	edit.text = "Small deck"
	edit.text_submitted.emit(edit.text)
	assert_has(_console_lines(scene), "You have no deck called “Small deck” that can be played here.")
	assert_eq(scene._chosen, "")


func _is_green(panel: PanelContainer) -> bool:
	var box := panel.get_theme_stylebox(&"panel") as StyleBoxFlat
	return box != null and box.bg_color == load("res://scripts/ui/room_menu.gd").READY_COLOR


func test_ready_players_turn_green_for_both_and_the_game_starts_when_both_are() -> void:
	var scene := _make_scene("Bob")
	var ready_button: Button = scene.get_node("%ReadyButton")
	var edit: LineEdit = scene.get_node("%DeckEdit")
	var you: PanelContainer = scene.get_node("%YouPanel")
	var them: PanelContainer = scene.get_node("%OpponentPanel")
	edit.text = "Official deck"
	edit.text_submitted.emit(edit.text)
	scene.online.on_deck_checked([])
	assert_false(_is_green(you))

	scene.online.on_ready_state(true, false)
	assert_true(_is_green(you), "my box turns green")
	assert_false(_is_green(them))
	assert_eq(ready_button.text, "Not ready", "and Ready can be taken back")
	assert_false(ready_button.disabled)
	assert_false(edit.editable, "the deck cannot change while ready")

	scene.online.on_ready_state(true, true)
	assert_true(_is_green(them), "the other player's box turns green when they are ready")
	assert_has(_console_lines(scene), "Bob is ready.")

	scene.online.on_game_start()
	assert_has(_console_lines(scene), "Both players are ready. The game starts!")
	assert_true(ready_button.disabled, "nothing more to press")

	scene.online.on_ready_state(false, false)
	assert_false(_is_green(you))
	assert_false(_is_green(them))


func test_someone_new_in_the_room_means_saying_ready_again() -> void:
	var scene := _make_scene()
	var edit: LineEdit = scene.get_node("%DeckEdit")
	edit.text = "Official deck"
	edit.text_submitted.emit(edit.text)
	scene.online.on_deck_checked([])
	scene.online.on_ready_state(true, false)
	scene.online.on_opponent_joined("Bob")
	scene.online.on_ready_state(false, false)
	assert_has(_console_lines(scene), "Press Ready again when you are.")
	assert_false((scene.get_node("%ReadyButton") as Button).disabled, "the deck is still the checked one")
