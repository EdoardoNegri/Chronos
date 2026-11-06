extends GutTest

const TEST_CARDS_DIR := "user://test_database_cards"
const TEST_POINTS_PATH := "user://test_database_points/points_list.json"
const TEST_OFFICIAL_DIR := "user://test_database_official"
## The "Cards" choices, in the order of the dropdown.
const SOURCE_OFFICIAL := 0
const SOURCE_CUSTOM := 1
const SOURCE_BOTH := 2


func after_each() -> void:
	await get_tree().process_frame
	for directory in [TEST_CARDS_DIR, TEST_OFFICIAL_DIR, TEST_POINTS_PATH.get_base_dir()]:
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


## A database with the sample cards as the player's custom cards. The official cards are whatever
## is in TEST_OFFICIAL_DIR (nothing unless a test saves some first). `source` is the "Cards"
## choice: SOURCE_OFFICIAL, SOURCE_CUSTOM or SOURCE_BOTH.
func _make_scene(source := SOURCE_BOTH) -> Control:
	var library := CardLibrary.new(TEST_CARDS_DIR)
	for card in _sample_cards():
		library.save_card(card, Image.create(750, 1050, false, Image.FORMAT_RGBA8))
	var scene: Control = load("res://scenes/database.tscn").instantiate()
	scene.card_library = library
	scene.official_library = CardLibrary.new(TEST_OFFICIAL_DIR)
	scene.points_list = PointsList.new(TEST_POINTS_PATH)
	add_child_autofree(scene)
	_choose_cards(scene, source)
	return scene


func _choose_cards(scene: Control, source: int) -> void:
	(scene.get_node("%SearchForm/%CardSourceOption") as OptionButton).select(source)


func _result_names(scene: Control) -> Array[String]:
	var names: Array[String] = []
	for card: CardData in scene._results:
		names.append(card.card_name)
	return names


func test_database_searches_official_cards_custom_cards_or_both() -> void:
	var official := CardLibrary.new(TEST_OFFICIAL_DIR)
	var founder := _card("Founder", "Creature", 10, 1, 1)
	official.save_card(founder, Image.create(750, 1050, false, Image.FORMAT_RGBA8))
	# A custom copy of an official card (same id) is that official card, not a second card.
	var copy := _card("Founder", "Creature", 10, 1, 1)
	copy.id = founder.id
	CardLibrary.new(TEST_CARDS_DIR).save_card(copy)

	var scene := _make_scene(SOURCE_OFFICIAL)
	var source: OptionButton = scene.get_node("%SearchForm/%CardSourceOption")
	assert_eq(source.item_count, 3)
	assert_eq(source.get_item_text(0), "Official cards", "the choice starts on official cards")
	assert_eq(source.get_item_text(1), "Custom cards")
	assert_eq(source.get_item_text(2), "Both", "the last choice is both")
	scene._search_from_form()
	assert_eq(_result_names(scene), ["Founder"] as Array[String])

	_choose_cards(scene, SOURCE_CUSTOM)
	scene._search_from_form()
	var custom := _result_names(scene)
	custom.sort()
	assert_eq(custom, ["Chrono Drake", "Clockwork Golem", "Zap"] as Array[String], "only the custom cards")

	_choose_cards(scene, SOURCE_BOTH)
	scene._search_from_form()
	assert_eq(_result_names(scene).size(), 4, "both, with the official card only once")
	assert_has(_result_names(scene), "Founder")
	assert_has(_result_names(scene), "Chrono Drake")


func _press_key(edit: LineEdit, keycode: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	edit.gui_input.emit(key)


## Types into a field the way a player does: the text, with the caret at its end.
func _type_into(scene: Control, field: String, text: String) -> void:
	var edit: LineEdit = scene.get_node(field)
	edit.text = text
	edit.caret_column = text.length()
	edit.text_changed.emit(text)


func _type_subtype(scene: Control, text: String) -> void:
	_type_into(scene, "%SearchForm/%SubtypeEdit", text)


func _save_official(card_name: String, type := "Creature", subtype := "", text := "") -> void:
	var card := _card(card_name, type)
	card.subtype = subtype
	card.rules_text = text
	CardLibrary.new(TEST_OFFICIAL_DIR).save_card(card, Image.create(750, 1050, false, Image.FORMAT_RGBA8))


## Fills the named fields of the form (and no others), searches, and gives the names found, sorted.
func _search_for(scene: Control, fields: Dictionary) -> Array[String]:
	scene._clear_form()
	for field: String in fields:
		(scene.get_node(field) as LineEdit).text = fields[field]
	scene._search_from_form()
	var names := _result_names(scene)
	names.sort()
	return names


func test_subtype_field_suggests_available_subtypes_by_their_start() -> void:
	_save_official("Founder", "Creature", "Drake")
	_save_official("Hermit", "Creature", "Dwarf")
	_save_official("Scribe", "Creature", "Mage")
	# "Dragon" (Chrono Drake) is a custom card's subtype and no official card has it.
	var scene := _make_scene(SOURCE_OFFICIAL)
	var suggestions: WordSuggestions = scene._form._subtype_suggestions

	_type_subtype(scene, "")
	assert_eq(suggestions.suggested, ["Drake", "Dwarf", "Mage"] as Array[String], "all of them to start with")
	assert_true(suggestions.visible)
	_type_subtype(scene, "d")
	assert_eq(suggestions.suggested, ["Drake", "Dwarf"] as Array[String], "the ones that start with the text")
	_type_subtype(scene, "DRA")
	assert_eq(suggestions.suggested, ["Drake"] as Array[String], "capitals do not matter")
	_type_subtype(scene, "ake")
	assert_false(suggestions.visible, "only the start of a subtype counts")
	_type_subtype(scene, "Drake")
	assert_false(suggestions.visible, "nothing is suggested once the text is already a subtype")

	_choose_cards(scene, SOURCE_BOTH)
	_type_subtype(scene, "dr")
	assert_eq(suggestions.suggested, ["Dragon", "Drake"] as Array[String], "custom subtypes join in with Both")
	_choose_cards(scene, SOURCE_CUSTOM)
	_type_subtype(scene, "")
	assert_eq(suggestions.suggested, ["Dragon"] as Array[String], "and are the only ones with Custom cards")


func test_suggestions_complete_the_word_being_typed() -> void:
	_save_official("Founder", "Creature", "Warrior Elf")
	_save_official("Hermit", "Creature", "Dwarf Mage")
	var scene := _make_scene(SOURCE_OFFICIAL)
	var suggestions: WordSuggestions = scene._form._subtype_suggestions

	_type_subtype(scene, "")
	assert_eq(suggestions.suggested, ["Dwarf", "Elf", "Mage", "Warrior"] as Array[String], "a word each")
	_type_subtype(scene, "warrior ")
	assert_eq(suggestions.suggested, ["Dwarf", "Elf", "Mage"] as Array[String], "not the words already there")
	_type_subtype(scene, "warrior e")
	assert_eq(suggestions.suggested, ["Elf"] as Array[String], "the word being typed is the one completed")
	suggestions.accept(0)
	assert_eq((scene.get_node("%SearchForm/%SubtypeEdit") as LineEdit).text, "warrior Elf", "the rest is left alone")

	_type_subtype(scene, "\"warrior m")
	assert_eq(suggestions.suggested, ["Mage"] as Array[String], "also inside quotes")
	suggestions.accept(0)
	assert_eq((scene.get_node("%SearchForm/%SubtypeEdit") as LineEdit).text, "\"warrior Mage")


func test_type_field_suggests_the_card_types() -> void:
	_save_official("Founder", "Creature")
	_save_official("Bolt", "Spell")
	var scene := _make_scene(SOURCE_OFFICIAL)
	var suggestions: WordSuggestions = scene._form._type_suggestions
	_type_into(scene, "%SearchForm/%TypeEdit", "")
	assert_eq(suggestions.suggested, ["Creature", "Spell"] as Array[String])
	_type_into(scene, "%SearchForm/%TypeEdit", "sp")
	assert_eq(suggestions.suggested, ["Spell"] as Array[String])
	_type_into(scene, "%SearchForm/%TypeEdit", "creature s")
	assert_eq(suggestions.suggested, ["Spell"] as Array[String], "after one type, the next word")


func test_a_subtype_only_on_custom_cards_can_still_be_typed_and_searched() -> void:
	_save_official("Founder", "Creature", "Drake")
	var scene := _make_scene(SOURCE_BOTH)

	_type_subtype(scene, "Dragon")
	assert_false(scene._form._subtype_suggestions.visible, "Dragon is a full subtype already, so nothing is suggested")
	scene._search_from_form()
	assert_eq(_result_names(scene), ["Chrono Drake"] as Array[String], "the typed subtype is searched")

	_choose_cards(scene, SOURCE_OFFICIAL)
	_type_subtype(scene, "Drag")
	assert_eq(scene._form._subtype_suggestions.suggested.size(), 0, "official cards offer nothing starting with Drag")
	scene._search_from_form()
	assert_eq(_result_names(scene).size(), 0, "typing it without a suggestion searches as typed")


func test_suggestions_work_from_the_keyboard_and_the_mouse() -> void:
	_save_official("Founder", "Creature", "Drake")
	_save_official("Hermit", "Creature", "Dwarf")
	var scene := _make_scene(SOURCE_OFFICIAL)
	var edit: LineEdit = scene.get_node("%SearchForm/%SubtypeEdit")
	var suggestions: WordSuggestions = scene._form._subtype_suggestions

	_type_subtype(scene, "d")
	assert_eq(suggestions.highlighted, -1, "nothing is highlighted until you move to it")
	_press_key(edit, KEY_DOWN)
	_press_key(edit, KEY_DOWN)
	assert_eq(suggestions.highlighted, 1)
	_press_key(edit, KEY_UP)
	assert_eq(suggestions.highlighted, 0)
	_press_key(edit, KEY_ENTER)
	assert_eq(edit.text, "Drake", "Enter takes the highlighted suggestion")
	assert_false(suggestions.visible)

	_type_subtype(scene, "d")
	_press_key(edit, KEY_ESCAPE)
	assert_false(suggestions.visible, "Escape closes the list")
	assert_eq(edit.text, "d", "and keeps what was typed")

	_type_subtype(scene, "d")
	suggestions.accept(1)
	assert_eq(edit.text, "Dwarf", "a click takes that suggestion")

	_type_subtype(scene, "d")
	scene._search_from_form()
	assert_false(suggestions.visible, "the list is gone on the results page")


func test_name_and_card_text_read_like_the_rules_search() -> void:
	_save_official("Young Drake", "Creature", "Dragon", "Draw a card.")
	_save_official("You Win", "Spell", "", "Deal 2 damage.")
	_save_official("Your Guard", "Creature", "Warrior")
	var scene := _make_scene(SOURCE_OFFICIAL)

	assert_eq(_search_for(scene, {"%SearchForm/%NameEdit": "you"}), ["You Win", "Young Drake", "Your Guard"] as Array[String], "a loose word is found inside longer words")
	assert_eq(_search_for(scene, {"%SearchForm/%NameEdit": "\"you \""}), ["You Win"] as Array[String], "quoted text counts its spaces")
	assert_eq(_search_for(scene, {"%SearchForm/%NameEdit": "\"your p"}).size(), 0, "an unclosed quote runs to the end")
	assert_eq(_search_for(scene, {"%SearchForm/%NameEdit": "drake young"}), ["Young Drake"] as Array[String], "loose words, in any order")
	assert_eq(_search_for(scene, {"%SearchForm/%NameEdit": "\"young drake\""}), ["Young Drake"] as Array[String])
	assert_eq(_search_for(scene, {"%SearchForm/%NameEdit": "\"drake young\""}).size(), 0, "a quoted phrase keeps its order")

	assert_eq(_search_for(scene, {"%SearchForm/%CardTextEdit": "card draw"}), ["Young Drake"] as Array[String], "every loose word, any order")
	assert_eq(_search_for(scene, {"%SearchForm/%CardTextEdit": "\"draw a card\""}), ["Young Drake"] as Array[String])
	assert_eq(_search_for(scene, {"%SearchForm/%CardTextEdit": "\"draw card\""}).size(), 0, "a phrase is found exactly as typed")


func test_subtype_words_are_alternatives_and_quoted_words_must_all_match() -> void:
	_save_official("Elf Scout", "Creature", "Elf")
	_save_official("Warrior Elf", "Creature", "Warrior Elf")
	_save_official("Orc Warrior", "Creature", "Orc Warrior")
	_save_official("Plain Mage", "Creature", "Mage")
	_save_official("Elf Blessing", "Spell", "Elf")
	var scene := _make_scene(SOURCE_OFFICIAL)

	assert_eq(
		_search_for(scene, {"%SearchForm/%SubtypeEdit": "warrior elf"}),
		["Elf Blessing", "Elf Scout", "Orc Warrior", "Warrior Elf"] as Array[String],
		"warrior elf: all warriors and all elves"
	)
	assert_eq(
		_search_for(scene, {"%SearchForm/%SubtypeEdit": "\"warrior elf\""}),
		["Warrior Elf"] as Array[String],
		"\"warrior elf\": only the cards that are both"
	)
	assert_eq(
		_search_for(scene, {"%SearchForm/%SubtypeEdit": "\"elf warrior\""}),
		["Warrior Elf"] as Array[String],
		"in either order"
	)
	assert_eq(
		_search_for(scene, {"%SearchForm/%SubtypeEdit": "\"warrior elf\" mage"}),
		["Plain Mage", "Warrior Elf"] as Array[String],
		"a quoted group and a loose word are alternatives"
	)
	assert_eq(
		_search_for(scene, {"%SearchForm/%SubtypeEdit": "wa"}),
		["Orc Warrior", "Warrior Elf"] as Array[String],
		"part of a subtype is enough"
	)
	assert_eq(
		_search_for(scene, {"%SearchForm/%SubtypeEdit": "warrior, mage"}),
		["Orc Warrior", "Plain Mage", "Warrior Elf"] as Array[String],
		"commas work as spaces"
	)

	assert_eq(
		_search_for(scene, {"%SearchForm/%TypeEdit": "spell", "%SearchForm/%SubtypeEdit": "elf"}),
		["Elf Blessing"] as Array[String],
		"type and subtype both have to match"
	)
	assert_eq(
		_search_for(scene, {"%SearchForm/%TypeEdit": "spell creature", "%SearchForm/%SubtypeEdit": "\"warrior elf\""}),
		["Warrior Elf"] as Array[String],
		"type words are alternatives too"
	)
	assert_eq(
		_search_for(scene, {"%SearchForm/%TypeEdit": "\"creature spell\""}).size(),
		0,
		"a card has one type, so it cannot be both"
	)
	assert_eq(_search_for(scene, {"%SearchForm/%TypeEdit": "creature spell"}).size(), 5, "but it can be either")


func test_type_search_does_not_match_a_subtype_that_contains_the_word() -> void:
	_save_official("Caster", "Creature", "Spellcaster")
	_save_official("Bolt", "Spell")
	var scene := _make_scene(SOURCE_OFFICIAL)
	assert_eq(_search_for(scene, {"%SearchForm/%TypeEdit": "spell"}), ["Bolt"] as Array[String], "only the card type counts")
	assert_eq(_search_for(scene, {"%SearchForm/%SubtypeEdit": "spell"}), ["Caster"] as Array[String], "and only the subtype here")


func test_form_query_spells_out_the_alternatives() -> void:
	var scene := _make_scene(SOURCE_BOTH)
	scene._clear_form()
	(scene.get_node("%SearchForm/%NameEdit") as LineEdit).text = "drake \"two words\""
	(scene.get_node("%SearchForm/%TypeEdit") as LineEdit).text = "creature"
	(scene.get_node("%SearchForm/%SubtypeEdit") as LineEdit).text = "warrior \"elf mage\""
	assert_eq(
		scene._form.form_query(),
		"drake \"two words\" ct:creature st:warrior or drake \"two words\" ct:creature st:elf st:mage"
	)
	scene._clear_form()
	assert_eq(scene._form.form_query(), "", "an empty form searches for everything")

func test_database_says_why_a_choice_has_no_cards() -> void:
	var scene := _make_scene(SOURCE_OFFICIAL)
	var empty: Label = scene.get_node("%EmptyLabel")
	scene._search_from_form()
	assert_true(empty.visible)
	assert_string_contains(empty.text, "No official cards", "only custom cards exist")
	_choose_cards(scene, SOURCE_BOTH)
	scene._search_from_form()
	assert_false(empty.visible)

	for card: CardData in scene.card_library.load_cards():
		scene.card_library.delete_card(card.id)
	scene._load_library()
	_choose_cards(scene, SOURCE_CUSTOM)
	scene._search_from_form()
	assert_string_contains(empty.text, "No custom cards")
	_choose_cards(scene, SOURCE_BOTH)
	scene._search_from_form()
	assert_string_contains(empty.text, "No cards yet")


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

	(scene.get_node("%SearchForm/%NameEdit") as LineEdit).text = "chrono"
	(scene.get_node("%SearchForm/%TypeEdit") as LineEdit).text = "creature"
	(scene.get_node("%SearchForm/%CardTextEdit") as LineEdit).text = "draw a card"
	var time_filter: Dictionary = scene._form._number_filters[0]
	(time_filter["value"] as NumberStepper).value = 20
	assert_eq((time_filter["comparison"] as OptionButton).selected, 1, "picking a number turns Any into =")
	(time_filter["comparison"] as OptionButton).select(4)  # ≥
	assert_eq(scene._form.form_query(), "chrono ct:creature o:draw o:a o:card time>=20", "every word of the text")
	(scene.get_node("%SearchButton") as Button).pressed.emit()

	assert_true((scene.get_node("%ResultsPanel") as Control).visible)
	assert_false((scene.get_node("%Actions") as Control).visible, "Clear and Search are only on the form")
	assert_eq(scene._results.size(), 1)
	assert_eq(scene._results[0].card_name, "Chrono Drake")

	(scene.get_node("%BackButton") as Button).pressed.emit()
	assert_true((scene.get_node("%FormPanel") as Control).visible, "back goes from the results to the form")
	assert_eq((scene.get_node("%SearchForm/%NameEdit") as LineEdit).text, "chrono", "still filled in")
	(scene.get_node("%ClearButton") as Button).pressed.emit()
	assert_eq(scene._form.form_query(), "", "Clear empties the form")


func test_comparisons_and_the_mouse_wheel() -> void:
	var scene := _make_scene()
	var comparison: OptionButton = scene._form._number_filters[0]["comparison"]
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
	assert_eq(scene._form._number_filters.size(), 4)
	assert_eq((scene.get_node("%SearchForm/%NumbersRow") as GridContainer).columns, 2, "two filters to a row")


func test_database_sorts_and_shows_results_as_chosen_on_the_form() -> void:
	var scene := _make_scene()
	var search: Button = scene.get_node("%SearchButton")
	var results: VBoxContainer = scene.get_node("%Results")
	search.pressed.emit()
	assert_eq(results.get_child(0).get_child_count(), 3, "an empty form finds every card, as images")

	var sort: OptionButton = scene.get_node("%SortOption")
	assert_true(scene.get_node("%FormPanel").is_ancestor_of(sort), "sorting is part of the form")
	(scene.get_node("%SearchForm/%TypeEdit") as LineEdit).text = "creature"
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

	(scene.get_node("%SearchForm/%NameEdit") as LineEdit).text = "nothing matches this"
	search.pressed.emit()
	assert_true((scene.get_node("%EmptyLabel") as Label).visible)


func test_database_opens_a_card_as_a_table_and_goes_back() -> void:
	var scene := _make_scene()
	scene.points_list.set_from_dict({"Clockwork Golem": 7})
	(scene.get_node("%SearchButton") as Button).pressed.emit()
	var golem: CardData = null
	for card: CardData in scene._cards:
		if card.card_name == "Clockwork Golem":
			golem = card

	scene._open_card(golem.id)
	assert_true((scene.get_node("%DetailPanel") as Control).visible)
	assert_false((scene.get_node("%ResultsPanel") as Control).visible)
	var details := _texts(scene.get_node("%DetailInfo"))
	assert_string_contains(details, "Clockwork Golem")
	assert_string_contains(details, "5 / 6")
	assert_string_contains(details, "Deck points", "the cost is a row of the table")
	assert_string_contains(details, "7", "as the points list sets it")
	assert_false(details.contains(golem.id), "the card id is not shown")
	assert_false(details.contains("Card id"))
	assert_false(details.contains("Up to"), "nor how many copies a deck may have")
	assert_null(scene.get_node_or_null("%DecksColumn"), "nor the decks that use the card")
	assert_not_null((scene.get_node("%DetailImage") as TextureRect).texture)

	(scene.get_node("%BackButton") as Button).pressed.emit()
	assert_true((scene.get_node("%ResultsPanel") as Control).visible, "back goes from a card to the results")


func test_a_search_describes_itself_as_typed_and_filters_the_same_whatever_the_order() -> void:
	var cards := CardLibrary.new(CardLibrary.OFFICIAL_DIRECTORY).load_cards(false)
	var query := CardQuery.parse("o:a time>=2 -t:spell")
	assert_eq(query.describe(), "the text includes “a” and time cost ≥ 2 and the type doesn't include “spell”", "the description keeps the order typed")
	var by_hand: Array[CardData] = []
	for card in cards:
		if card.rules_text.to_lower().contains("a") and card.time_cost >= 2 and not card.type_line().to_lower().contains("spell"):
			by_hand.append(card)
	assert_eq(query.filter(cards), by_hand, "and finds what checking each card by hand finds")
	assert_eq(CardQuery.parse("").filter(cards), cards, "an empty search keeps every card")
