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


func test_create_cards_scene_can_show_the_back() -> void:
	var scene: Control = load("res://scenes/create_cards.tscn").instantiate()
	add_child_autofree(scene)
	scene.get_node("%ShowBackCheck").toggled.emit(true)
	assert_true(scene._back_view.visible)
	assert_false(scene._card_view.visible)


func test_create_cards_scene_saves_to_library_and_starts_new_cards() -> void:
	var directory := "user://test_maker_cards"
	var scene: Control = load("res://scenes/create_cards.tscn").instantiate()
	scene.card_library = CardLibrary.new(directory)
	add_child_autofree(scene)
	await scene._save_to_library()
	assert_eq(scene.card_library.load_cards().size(), 0, "a card needs a name")

	var name_edit: LineEdit = scene.get_node("%NameEdit")
	name_edit.text = "Chrono Drake"
	name_edit.text_changed.emit(name_edit.text)
	(scene.get_node("%TimeSpin") as SpinBox).value = 15
	await scene._save_to_library()
	var saved: Array[CardData] = scene.card_library.load_cards()
	assert_eq(saved.size(), 1)
	assert_eq(saved[0].time_cost, 15)

	scene._new_card()
	assert_eq(name_edit.text, "")
	assert_eq((scene.get_node("%TimeSpin") as SpinBox).value, 0.0)
	assert_eq(scene._card.id, "", "a new card gets its own id when saved")

	for stored in saved:
		scene.card_library.delete_card(stored.id)
	DirAccess.remove_absolute(directory)
