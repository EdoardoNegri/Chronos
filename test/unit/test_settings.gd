extends GutTest

const SCREENS: Array[String] = [
	"res://scenes/create_cards.tscn",
	"res://scenes/decks.tscn",
	"res://scenes/database.tscn",
	"res://scenes/play.tscn",
	"res://scenes/room.tscn",
	"res://scenes/rules.tscn",
]


func test_every_screen_has_back_and_settings_down_the_left_side() -> void:
	for path in SCREENS:
		var screen: Control = load(path).instantiate()
		assert_null(screen.find_child("Title"), "%s has no title" % path)
		# Both sit on the screen itself, outside the content and its margins.
		var back: Control = screen.get_node("BackButton")
		var gear: Control = screen.get_node("SettingsButton")
		assert_true(gear is SettingsButton)
		assert_eq([back.anchor_left, back.anchor_top], [0.0, 0.0], "%s: back at the top left" % path)
		assert_eq([gear.anchor_left, gear.anchor_top], [0.0, 1.0], "%s: settings at the bottom left" % path)
		var margin: int = (screen.get_node("Content") as MarginContainer).get_theme_constant("margin_left")
		assert_true(back.offset_right < margin, "%s: back fits beside the content" % path)
		assert_true(gear.offset_right < margin, "%s: settings fits beside the content" % path)
		screen.free()


func test_main_menu_has_the_gear_but_no_settings_button_in_its_list() -> void:
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	var gear: Control = menu.get_node("SettingsButton")
	assert_true(gear is SettingsButton)
	assert_eq([gear.anchor_left, gear.anchor_top], [0.0, 1.0], "bottom left, like the other screens")
	assert_null(menu.get_node("%Buttons").find_child("SettingsButton"))
	menu.free()


func test_settings_opens_over_the_screen_and_closes() -> void:
	var screen := Control.new()
	add_child_autofree(screen)
	var gear := SettingsButton.new()
	screen.add_child(gear)
	gear.owner = screen
	var settings := gear.open_settings()
	assert_not_null(settings)
	assert_eq(settings.get_parent(), screen, "it covers the screen the button is on")
	assert_null(gear.open_settings(), "only one at a time")
	settings.close()
	await get_tree().process_frame
	assert_false(is_instance_valid(settings), "closing removes it")


const TEST_PROFILE_PATH := "user://test_settings_profile/profile.cfg"


func after_each() -> void:
	DirAccess.remove_absolute(TEST_PROFILE_PATH)
	DirAccess.remove_absolute(TEST_PROFILE_PATH.get_base_dir())


func _open_settings(player_name: String) -> Control:
	var profile: PlayerProfile = autofree(PlayerProfile.new(TEST_PROFILE_PATH))
	if not player_name.is_empty():
		profile.set_player_name(player_name)
	var settings: Control = load("res://scenes/settings.tscn").instantiate()
	settings.profile = profile
	add_child_autofree(settings)
	return settings


func test_settings_lets_the_player_change_their_name() -> void:
	var settings := _open_settings("Aeon")
	var edit: LineEdit = settings.get_node("%NameEdit")
	var status: Label = settings.get_node("%NameStatus")
	assert_eq(edit.text, "Aeon", "it shows the current name")
	edit.text = "  Kairos "
	edit.text_submitted.emit(edit.text)
	assert_eq(settings.profile.player_name, "Kairos")
	assert_eq(edit.text, "Kairos")
	assert_eq(status.text, "Saved.")

	edit.text = "Orion"
	settings.close()
	assert_eq(settings.profile.player_name, "Orion", "a name typed and left without Enter still counts")


func test_settings_keeps_the_old_name_when_the_new_one_cannot_be_used() -> void:
	var settings := _open_settings("Aeon")
	var edit: LineEdit = settings.get_node("%NameEdit")
	edit.text = ""
	edit.text_submitted.emit("")
	assert_eq(settings.profile.player_name, "Aeon")
	assert_eq(edit.text, "Aeon", "the field goes back to the name that is kept")
	assert_ne((settings.get_node("%NameStatus") as Label).text, "", "and says why")
	assert_eq(edit.max_length, PlayerProfile.MAX_NAME_LENGTH, "the field stops a name from getting too long")


func test_settings_before_there_is_a_name_does_not_nag() -> void:
	var settings := _open_settings("")
	var edit: LineEdit = settings.get_node("%NameEdit")
	assert_eq(edit.text, "")
	edit.text_submitted.emit("")
	assert_eq((settings.get_node("%NameStatus") as Label).text, "", "an empty field is fine without a name")
	assert_false(settings.profile.has_account())
	edit.text = "Nova"
	edit.text_submitted.emit("Nova")
	assert_true(settings.profile.has_account(), "typing a name here is enough to have one")
	assert_eq(settings.profile.player_name, "Nova")


func test_settings_has_no_server_or_link_options() -> void:
	var settings := _open_settings("Aeon")
	assert_null(settings.get_node_or_null("%ServerEdit"), "rooms are listed without a server to set")
	assert_null(settings.get_node_or_null("%LinksCheck"), "and joined from the list, not with links")


func _texts(settings: Control) -> Array[String]:
	var texts: Array[String] = []
	for label: Label in settings.get_node("%SettingList").find_children("*", "Label", true, false):
		texts.append(label.text)
	return texts


func test_each_section_is_one_box_with_a_row_per_setting() -> void:
	var settings := _open_settings("Aeon")
	var texts := _texts(settings)
	for title in ["Display", "Fullscreen", "Online", "Name"]:
		assert_has(texts, title)
	for text in texts:
		assert_false(text.left(1).is_valid_int(), "no numbers in the titles: %s" % text)
	assert_null(settings.get_node_or_null("%SearchEdit"), "no search bar for a handful of settings")

	var check: Control = settings.get_node("%FullscreenCheck")
	var row: HBoxContainer = check.get_parent()
	var words: Array[Node] = row.get_child(0).get_children()
	assert_eq((words[0] as Label).text, "Fullscreen", "the setting's name on the left")
	assert_string_contains((words[1] as Label).text, "whole screen", "with what it does under it")
	assert_eq(row.get_child(1), check, "and its control on the right")
	assert_true(row.get_parent() is VBoxContainer, "rows sit straight in the section's box, not in a box of their own")
	var name_row: Node = (settings.get_node("%NameEdit") as Node).get_parent().get_parent()
	assert_true(name_row is HBoxContainer, "the name field is on the right of its row too")


func test_back_closes_settings() -> void:
	var settings := _open_settings("Aeon")
	(settings.get_node("%BackButton") as Button).pressed.emit()
	assert_true(settings.is_queued_for_deletion())
