extends GutTest


func test_it_turns_on_and_off_with_no_box_and_room_for_the_switch() -> void:
	var toggle := ToggleSwitch.new()
	toggle.text = "Public"
	add_child_autofree(toggle)
	await get_tree().process_frame
	assert_true(toggle.toggle_mode, "it is switched on and off by clicking")
	assert_false(toggle.button_pressed, "off to begin with")
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		assert_true(toggle.get_theme_stylebox(state) is StyleBoxEmpty, "no box around it (%s)" % state)

	var font := toggle.get_theme_font("font")
	var text_width := font.get_string_size("Public", HORIZONTAL_ALIGNMENT_LEFT, -1, toggle.get_theme_font_size("font_size")).x
	assert_gte(
		toggle.get_combined_minimum_size().x,
		text_width + ToggleSwitch.GAP + ToggleSwitch.TRACK_SIZE.x,
		"the text and the switch do not overlap"
	)
	assert_gte(toggle.get_combined_minimum_size().y, ToggleSwitch.TRACK_SIZE.y, "and the switch fits in its height")

	watch_signals(toggle)
	toggle.button_pressed = true
	assert_signal_emitted(toggle, "toggled")
	assert_true(toggle.button_pressed)
	toggle.queue_redraw()
	await get_tree().process_frame
