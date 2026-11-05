extends GutTest

const SCREENS: Array[String] = [
	"res://scenes/create_cards.tscn",
	"res://scenes/decks.tscn",
	"res://scenes/database.tscn",
	"res://scenes/play.tscn",
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
