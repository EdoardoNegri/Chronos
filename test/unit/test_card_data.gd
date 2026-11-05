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
	assert_true(scene.get_node("%StatsSpacer").visible, "their space is kept, so the time cost keeps its size")


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


func test_create_cards_scene_has_no_back_toggle_or_points() -> void:
	var scene: Control = load("res://scenes/create_cards.tscn").instantiate()
	add_child_autofree(scene)
	assert_null(scene.get_node_or_null("%ShowBackCheck"))
	assert_null(scene.get_node_or_null("%PointsSpin"), "the points list sets a card's points")
	assert_false(CardData.new().to_dict().has("points"))


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
	choice.hide()


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
