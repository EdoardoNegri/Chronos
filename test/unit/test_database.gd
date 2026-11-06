extends GutTest

const TEST_CARDS_DIR := "user://test_database_cards"
const TEST_POINTS_PATH := "user://test_database_points/points_list.json"
const TEST_DECKS_DIR := "user://test_database_decks"


func after_each() -> void:
	await get_tree().process_frame
	for directory in [TEST_CARDS_DIR, TEST_DECKS_DIR, TEST_POINTS_PATH.get_base_dir()]:
		if not DirAccess.dir_exists_absolute(directory):
			continue
		for file_name in DirAccess.get_files_at(directory):
			DirAccess.remove_absolute(directory.path_join(file_name))
		DirAccess.remove_absolute(directory)


func _card(card_name: String, type := "Creature", time_cost := 0, attack := 0, defense := 0) -> CardData:
	var card := CardData.new()
	card.card_name = card_name
	card.card_type = type
	card.time_cost = time_cost
	card.attack = attack
	card.defense = defense
	return card


func _matching(text: String, cards: Array[CardData], points: PointsList = null) -> Array[String]:
	var query := CardQuery.parse(text, points)
	var names: Array[String] = []
	for card in cards:
		if query.matches(card):
			names.append(card.card_name)
	return names


func _sample_cards() -> Array[CardData]:
	var drake := _card("Chrono Drake", "Creature", 30, 3, 4)
	drake.subtype = "Dragon"
	drake.rules_text = "When this enters, draw a card."
	var zap := _card("Zap", "Spell", 5)
	zap.rules_text = "Deal 2 damage."
	var golem := _card("Clockwork Golem", "Creature", 45, 5, 6)
	return [drake, zap, golem] as Array[CardData]


func test_words_search_names_and_quotes_keep_phrases() -> void:
	var cards := _sample_cards()
	assert_eq(_matching("", cards).size(), 3, "an empty search matches everything")
	assert_eq(_matching("drake", cards), ["Chrono Drake"] as Array[String])
	assert_eq(_matching("c o", cards), ["Chrono Drake", "Clockwork Golem"] as Array[String])
	assert_eq(_matching("\"chrono drake\"", cards), ["Chrono Drake"] as Array[String])
	assert_eq(_matching("\"drake chrono\"", cards), [] as Array[String])


func test_type_text_and_numbers() -> void:
	var cards := _sample_cards()
	assert_eq(_matching("t:spell", cards), ["Zap"] as Array[String])
	assert_eq(_matching("t:dragon", cards), ["Chrono Drake"] as Array[String], "subtypes count as type")
	assert_eq(_matching("o:\"draw a card\"", cards), ["Chrono Drake"] as Array[String])
	assert_eq(_matching("time>=30", cards), ["Chrono Drake", "Clockwork Golem"] as Array[String])
	assert_eq(_matching("cost:5", cards), ["Zap"] as Array[String])
	assert_eq(_matching("atk>3", cards), ["Clockwork Golem"] as Array[String])
	assert_eq(_matching("def<10", cards), ["Chrono Drake", "Clockwork Golem"] as Array[String], "spells have no defense")


func test_negation_or_and_points() -> void:
	var cards := _sample_cards()
	assert_eq(_matching("-t:creature", cards), ["Zap"] as Array[String])
	assert_eq(_matching("t:spell or atk>=5", cards), ["Zap", "Clockwork Golem"] as Array[String])
	assert_eq(_matching("t:creature time<40", cards), ["Chrono Drake"] as Array[String])
	var points := PointsList.new(TEST_POINTS_PATH)
	points.set_from_dict({"Zap": 2, "Clockwork Golem": 7})
	assert_eq(_matching("pts>=2", cards, points), ["Zap", "Clockwork Golem"] as Array[String])


func test_bad_terms_warn_and_are_skipped() -> void:
	var query := CardQuery.parse("rarity:rare time>=lots drake")
	assert_eq(query.warnings.size(), 2)
	assert_string_contains(query.warnings[0], "rarity:")
	assert_string_contains(query.warnings[1], "whole number")
	assert_true(query.matches(_card("Chrono Drake")), "the good term still applies")
	assert_false(query.matches(_card("Zap")))


func test_describe_reads_like_a_sentence() -> void:
	var query := CardQuery.parse("t:creature time>=30 -o:draw")
	assert_eq(
		query.describe(),
		"the type includes “creature” and time cost ≥ 30 and the text doesn't include “draw”"
	)
	assert_eq(CardQuery.parse("zap or atk>2").describe(), "the name includes “zap” or attack > 2")


func _make_scene() -> Control:
	var library := CardLibrary.new(TEST_CARDS_DIR)
	for card in _sample_cards():
		library.save_card(card, Image.create(750, 1050, false, Image.FORMAT_RGBA8))
	var scene: Control = load("res://scenes/database.tscn").instantiate()
	scene.card_library = library
	scene.deck_library = DeckLibrary.new(TEST_DECKS_DIR)
	scene.points_list = PointsList.new(TEST_POINTS_PATH)
	add_child_autofree(scene)
	return scene


## All the text shown in a part of the screen, for checking what it says.
func _texts(root: Node) -> String:
	var texts: Array[String] = []
	for label: Label in root.find_children("*", "Label", true, false):
		texts.append(label.text)
	return "
".join(texts)


func test_database_starts_on_the_form_and_searches_from_it() -> void:
	var scene := _make_scene()
	assert_true((scene.get_node("%FormPanel") as Control).visible, "it opens on the search form")
	assert_false((scene.get_node("%ResultsPanel") as Control).visible)
	assert_null(scene.find_child("SearchEdit"), "there is no search bar to type in")

	(scene.get_node("%NameEdit") as LineEdit).text = "chrono"
	var type_option: OptionButton = scene.get_node("%TypeOption")
	type_option.select(CardData.TYPES.find("Creature") + 1)
	(scene.get_node("%CardTextEdit") as LineEdit).text = "draw a card"
	var time_filter: Dictionary = scene._number_filters[0]
	(time_filter["value"] as NumberStepper).value = 20
	assert_eq((time_filter["comparison"] as OptionButton).selected, 1, "picking a number turns Any into =")
	(time_filter["comparison"] as OptionButton).select(4)  # ≥
	assert_eq(scene.form_query(), "chrono t:creature o:\"draw a card\" time>=20")
	(scene.get_node("%SearchButton") as Button).pressed.emit()

	assert_true((scene.get_node("%ResultsPanel") as Control).visible)
	assert_false((scene.get_node("%Actions") as Control).visible, "Clear and Search are only on the form")
	assert_eq(scene._results.size(), 1)
	assert_eq(scene._results[0].card_name, "Chrono Drake")

	(scene.get_node("%BackButton") as Button).pressed.emit()
	assert_true((scene.get_node("%FormPanel") as Control).visible, "back goes from the results to the form")
	assert_eq((scene.get_node("%NameEdit") as LineEdit).text, "chrono", "still filled in")
	(scene.get_node("%ClearButton") as Button).pressed.emit()
	assert_eq(scene.form_query(), "", "Clear empties the form")


func test_comparisons_and_the_mouse_wheel() -> void:
	var scene := _make_scene()
	var comparison: OptionButton = scene._number_filters[0]["comparison"]
	var labels: Array[String] = []
	for i in comparison.item_count:
		labels.append(comparison.get_item_text(i))
	assert_eq(labels, ["Any", "=", "≠", "≤", "≥"] as Array[String])
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	comparison.gui_input.emit(wheel)
	comparison.gui_input.emit(wheel)
	assert_eq(comparison.selected, 2, "scrolling down steps through the choices")
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	for i in 5:
		comparison.gui_input.emit(wheel)
	assert_eq(comparison.selected, 0, "and stops at the first one")
	assert_eq(scene._number_filters.size(), 4)
	assert_eq((scene.get_node("%NumbersRow") as GridContainer).columns, 2, "two filters to a row")


func test_database_sorts_and_shows_results_as_chosen_on_the_form() -> void:
	var scene := _make_scene()
	var search: Button = scene.get_node("%SearchButton")
	var results: VBoxContainer = scene.get_node("%Results")
	search.pressed.emit()
	assert_eq(results.get_child(0).get_child_count(), 3, "an empty form finds every card, as images")

	var sort: OptionButton = scene.get_node("%SortOption")
	assert_true(scene.get_node("%FormPanel").is_ancestor_of(sort), "sorting is part of the form")
	var type_option: OptionButton = scene.get_node("%TypeOption")
	type_option.select(CardData.TYPES.find("Creature") + 1)
	sort.select(1)  # Time cost
	search.pressed.emit()
	assert_eq(scene._results.size(), 2)
	assert_eq(scene._results[0].card_name, "Chrono Drake")
	(scene.get_node("%OrderOption") as OptionButton).select(1)  # Descending
	search.pressed.emit()
	assert_eq(scene._results[0].card_name, "Clockwork Golem", "descending puts the most expensive first")

	var mode: OptionButton = scene.get_node("%ModeOption")
	mode.select(1)
	search.pressed.emit()
	await get_tree().process_frame
	assert_eq(results.get_child_count(), 3, "checklist: a heading and two rows")
	mode.select(2)
	search.pressed.emit()
	await get_tree().process_frame
	assert_eq(results.get_child(0).get_child_count(), 2, "text only: a box per card")

	(scene.get_node("%NameEdit") as LineEdit).text = "nothing matches this"
	search.pressed.emit()
	assert_true((scene.get_node("%EmptyLabel") as Label).visible)


func test_database_opens_a_card_with_its_decks_and_goes_back() -> void:
	var scene := _make_scene()
	(scene.get_node("%SearchButton") as Button).pressed.emit()
	var golem: CardData = null
	for card: CardData in scene._cards:
		if card.card_name == "Clockwork Golem":
			golem = card
	var deck := DeckData.new()
	deck.deck_name = "Gears"
	deck.add(golem.id)
	deck.add(golem.id)
	scene.deck_library.save_deck(deck)

	scene._open_card(golem.id)
	assert_true((scene.get_node("%DetailPanel") as Control).visible)
	assert_false((scene.get_node("%ResultsPanel") as Control).visible)
	var details := _texts(scene.get_node("%DetailInfo"))
	assert_string_contains(details, "Clockwork Golem")
	assert_string_contains(details, "5 / 6")
	assert_string_contains(details, "Not listed")
	assert_string_contains(_texts(scene.get_node("%DecksColumn")), "Gears  ×2")
	assert_not_null((scene.get_node("%DetailImage") as TextureRect).texture)

	(scene.get_node("%BackButton") as Button).pressed.emit()
	assert_true((scene.get_node("%ResultsPanel") as Control).visible, "back goes from a card to the results")
