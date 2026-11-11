extends GutTest


func test_type_line_includes_subtype_only_when_set() -> void:
	var card := CardData.new()
	card.card_type = "Creature"
	assert_eq(card.type_line(), "Creature")
	card.subtype = "  Dragon "
	assert_eq(card.type_line(), "Creature — Dragon")


func test_only_creatures_have_stats() -> void:
	var card := CardData.new()
	card.card_type = "Creature"
	assert_true(card.has_stats())
	card.card_type = "Spell"
	assert_false(card.has_stats())


func test_file_stem_is_safe_and_never_empty() -> void:
	var card := CardData.new()
	assert_eq(card.file_stem(), "card")
	card.card_name = "  Chrono: Drake/2? "
	assert_eq(card.file_stem(), "Chrono_ Drake_2_")


func test_card_view_follows_data_changes() -> void:
	var card := CardData.new()
	var view := CardView.new()
	add_child_autofree(view)
	view.card = card
	card.time_cost = 15
	card.emit_changed()
	assert_eq(view.size, CardView.CARD_SIZE)
	assert_eq(view._dial.value, 15)


func test_create_cards_scene_edits_the_card() -> void:
	var scene: Control = load("res://scenes/create_cards.tscn").instantiate()
	add_child_autofree(scene)
	var type_option: OptionButton = scene.get_node("%TypeOption")
	var stats_row: Control = scene.get_node("%StatsRow")
	assert_eq(type_option.item_count, CardData.TYPES.size())
	assert_true(stats_row.visible, "creatures show attack and defense")
	type_option.select(CardData.TYPES.find("Spell"))
	type_option.item_selected.emit(type_option.selected)
	assert_false(stats_row.visible, "spells do not")
	assert_eq(stats_row.get_parent().name, &"Form", "attack and defense have a line of their own")
	assert_ne(stats_row.get_parent().name, &"CostRow")


func test_clock_dial_prints_the_full_cost_past_a_full_turn() -> void:
	var dial := ClockDial.new()
	add_child_autofree(dial)
	dial.size = Vector2(96, 96)
	dial.value = ClockDial.FULL_TURN * 2
	assert_eq(dial._label.text, str(ClockDial.FULL_TURN * 2), "the number is never clamped")


func test_card_back_has_card_size_and_title_centers_first_o() -> void:
	var back := CardBack.new()
	add_child_autofree(back)
	assert_eq(back.size, CardBack.CARD_SIZE)
	var font := back.get_theme_default_font()
	var center := CardBack.CARD_SIZE * 0.5
	var origin := back.title_origin(center)
	var through_o := font.get_string_size(
		CardBack.TITLE.substr(0, CardBack.FIRST_O + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, CardBack.TITLE_SIZE
	).x
	var o_width := font.get_string_size("O", HORIZONTAL_ALIGNMENT_LEFT, -1, CardBack.TITLE_SIZE).x
	assert_almost_eq(origin.x + through_o - o_width * 0.5, center.x, 0.01, "first O is centered")
	assert_eq(CardBack.TITLE[CardBack.FIRST_O], "O")


func test_create_cards_scene_has_points_but_no_back_toggle() -> void:
	var scene: Control = load("res://scenes/create_cards.tscn").instantiate()
	add_child_autofree(scene)
	assert_null(scene.get_node_or_null("%ShowBackCheck"))
	var points_input: NumberStepper = scene.get_node("%PointsInput")
	assert_eq(points_input.get_parent().get_parent().name, &"CostRow", "points sit beside the time cost")
	points_input.value = 7
	assert_eq(scene._card.points, 7, "the field sets the card's points")
	assert_eq(CardData.from_dict(scene._card.to_dict()).points, 7, "and they are saved with the card")
	assert_eq(CardData.new().points, 0)


func test_create_cards_scene_saves_to_library() -> void:
	var directory := "user://test_maker_cards"
	var scene: Control = load("res://scenes/create_cards.tscn").instantiate()
	scene.card_library = CardLibrary.new(directory)
	add_child_autofree(scene)
	await scene._save_to_library()
	assert_eq(scene.card_library.load_cards().size(), 0, "a card needs a name")

	var name_edit: LineEdit = scene.get_node("%NameEdit")
	name_edit.text = "Chrono Drake"
	name_edit.text_changed.emit(name_edit.text)
	(scene.get_node("%TimeInput") as NumberStepper).value = 15
	await scene._save_to_library()
	var saved: Array[CardData] = scene.card_library.load_cards()
	assert_eq(saved.size(), 1)
	assert_eq(saved[0].time_cost, 15)

	var saved_id: String = saved[0].id
	await scene._save_to_library()
	assert_eq(scene.card_library.load_cards().size(), 1, "saving again updates the same card")
	assert_eq(scene.card_library.load_cards()[0].id, saved_id)

	for stored in saved:
		scene.card_library.delete_card(stored.id)
	DirAccess.remove_absolute(directory)


func test_create_cards_save_button_asks_library_or_png() -> void:
	var scene: Control = load("res://scenes/create_cards.tscn").instantiate()
	add_child_autofree(scene)
	assert_null(scene.get_node_or_null("%NewCardButton"))
	assert_null(scene.get_node_or_null("%DownloadButton"))
	var choice: AcceptDialog = scene._save_choice
	assert_false(choice is ConfirmationDialog, "no Cancel button, only the X")
	assert_eq(choice.ok_button_text, "Save to library")
	(scene.get_node("%SaveButton") as Button).pressed.emit()
	assert_true(choice.visible, "pressing Save asks how to save")
	assert_null(choice.gui_get_focus_owner(), "neither choice starts out selected")
	choice.hide()


func test_importing_a_card_png_shows_its_point_cost() -> void:
	var directory := "user://test_import_points"
	DirAccess.make_dir_recursive_absolute(directory)
	var card := CardData.new()
	card.id = "abc123"
	card.card_name = "Chrono Drake"
	card.points = 6
	var plain := Image.create(744, 1040, false, Image.FORMAT_RGBA8).save_png_to_buffer()
	var path := directory.path_join("shared.png")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(CardPng.write_card(plain, card))
	file.close()

	var scene: Control = load("res://scenes/create_cards.tscn").instantiate()
	scene.card_library = CardLibrary.new(directory)
	add_child_autofree(scene)
	scene._import_card(path)
	assert_eq(int((scene.get_node("%PointsInput") as NumberStepper).value), 6, "the cost shows in the form")
	assert_eq(scene.card_library.load_cards()[0].points, 6, "and it is kept in the library")

	scene.card_library.delete_card("abc123")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)


func test_number_stepper_steps_types_and_clamps() -> void:
	var stepper := NumberStepper.new()
	stepper.max_value = 99
	add_child_autofree(stepper)
	watch_signals(stepper)
	var buttons: Array[Node] = stepper.find_children("*", "Button", true, false)
	var plus: Button = buttons[0]
	var minus: Button = buttons[1]
	assert_eq([plus.text, minus.text], ["+", "−"], "+ is stacked over −")
	stepper.size = Vector2(300, 53)
	await wait_physics_frames(2)
	assert_almost_eq(plus.size.x, plus.size.y, 1.0, "the buttons are square")
	assert_true(minus.disabled, "cannot go below the minimum")
	for i in 2:
		plus.button_down.emit()
		plus.button_up.emit()
	assert_eq(stepper.value, 2)
	assert_signal_emit_count(stepper, "value_changed", 2)
	minus.button_down.emit()
	minus.button_up.emit()
	assert_eq(stepper.value, 1)

	var edit: LineEdit = stepper.find_children("*", "LineEdit", true, false)[0]
	edit.text = "42"
	edit.text_changed.emit("42")
	assert_eq(stepper.value, 42, "typing a number sets it")
	stepper.value = 500
	assert_eq(stepper.value, 99, "clamped to the maximum")
	assert_eq(edit.text, "99")
	assert_true(plus.disabled)
	edit.text = "abc"
	edit.text_changed.emit("abc")
	edit.text_submitted.emit("abc")
	assert_eq(edit.text, "99", "text that is not a number goes back to the value")


func test_number_stepper_holding_speeds_up() -> void:
	var stepper := NumberStepper.new()
	add_child_autofree(stepper)
	stepper._start_hold(1)
	assert_eq(stepper.value, 1, "one step right away")
	for i in NumberStepper.REPEATS_BEFORE_BIG_STEPS:
		stepper._repeat()
	assert_eq(stepper.value, 1 + NumberStepper.REPEATS_BEFORE_BIG_STEPS)
	var before: int = stepper.value
	stepper._repeat()
	assert_eq(stepper.value, before + NumberStepper.BIG_STEP, "long holds take bigger steps")
	assert_almost_eq(stepper._hold_timer.wait_time, NumberStepper.FASTEST_INTERVAL, 0.001, "and repeat fastest")
	stepper._stop_hold()
	before = stepper.value
	stepper._repeat()
	assert_eq(stepper.value, before, "letting go stops it")


func test_number_stepper_can_go_below_zero_and_be_locked() -> void:
	var stepper := NumberStepper.new()
	stepper.min_value = -100
	stepper.max_value = 100
	add_child_autofree(stepper)
	stepper.value = -40
	assert_eq(stepper.value, -40, "a range that starts below 0")
	assert_eq(stepper._edit.text, "-40")
	stepper._edit.text = "-250"
	stepper._edit.text_changed.emit("-250")
	assert_eq(stepper.value, -100, "typing is kept in the range")
	assert_gte(stepper._edit.max_length, "-100".length(), "the minus sign has room")

	stepper.editable = false
	assert_false(stepper._edit.editable, "locked: nothing can be typed")
	assert_true(stepper._plus.disabled)
	assert_true(stepper._minus.disabled, "and the buttons do nothing")
	stepper.editable = true
	assert_true(stepper._edit.editable)
	assert_false(stepper._plus.disabled)
