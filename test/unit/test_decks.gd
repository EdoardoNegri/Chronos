extends GutTest

const TEST_CARDS_DIR := "user://test_cards"
const TEST_DECKS_DIR := "user://test_decks"
const TEST_OFFICIAL_DIR := "user://test_official_cards"
const TEST_IMPORT_DIR := "user://test_deck_files"
const TEST_POINTS_PATH := "user://test_points/points_list.json"


func after_each() -> void:
	# Let nodes queued for deletion go before the test ends.
	await get_tree().process_frame
	for directory in [
		TEST_CARDS_DIR, TEST_OFFICIAL_DIR, TEST_DECKS_DIR, TEST_IMPORT_DIR, TEST_POINTS_PATH.get_base_dir()
	]:
		if not DirAccess.dir_exists_absolute(directory):
			continue
		for file_name in DirAccess.get_files_at(directory):
			DirAccess.remove_absolute(directory.path_join(file_name))
		DirAccess.remove_absolute(directory)


func _card(card_id: String, card_name: String, time_cost := 0, type := "Creature") -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.card_name = card_name
	card.time_cost = time_cost
	card.card_type = type
	return card


func test_no_more_than_three_copies() -> void:
	var deck := DeckData.new()
	for i in DeckData.MAX_COPIES:
		assert_true(deck.add("a"))
	assert_false(deck.add("a"), "a fourth copy is refused")
	assert_eq(deck.copies("a"), 3)
	assert_eq(deck.size(), 3)


func test_remove_drops_the_entry_at_zero() -> void:
	var deck := DeckData.new()
	deck.add("a")
	assert_true(deck.remove("a"))
	assert_false(deck.counts.has("a"))
	assert_false(deck.remove("a"), "nothing left to remove")


func test_each_card_over_fifty_adds_a_point() -> void:
	var deck := DeckData.new()
	for i in 50:
		deck.counts["card_%d" % i] = 1
	assert_eq(deck.size(), 50)
	assert_eq(deck.usable_points(), 100)
	deck.counts["extra"] = 1
	assert_eq(deck.usable_points(), 101, "51 cards give 101 points")


func _points(data: Dictionary) -> PointsList:
	var points := PointsList.new(TEST_POINTS_PATH)
	points.set_from_dict(data)
	return points


func test_problems_report_size_budget_and_missing_cards() -> void:
	var cards := {"big": _card("big", "Big")}
	var deck := DeckData.new()
	deck.counts = {"big": 2, "gone": 1}
	var found := deck.problems(cards, _points({"Big": 60}))
	assert_eq(found.size(), 3)
	assert_string_contains(found[0], "47 more cards")
	assert_string_contains(found[1], "20")
	assert_string_contains(found[2], "no longer in your library")


func test_a_full_deck_within_budget_is_legal() -> void:
	var cards := {}
	var deck := DeckData.new()
	for i in 50:
		var card := _card("c%d" % i, "Card %d" % i)
		cards[card.id] = card
		deck.counts[card.id] = 1
	var points := PointsList.new(TEST_POINTS_PATH)
	assert_eq(deck.used_points(cards, points), 0, "cards not on the list cost nothing")
	var listed := {}
	for i in 50:
		listed["Card %d" % i] = 2
	points.set_from_dict(listed)
	assert_eq(deck.used_points(cards, points), 100)
	assert_eq(deck.problems(cards, points), [] as Array[String])


func test_points_list_is_read_from_its_file_and_goes_by_name() -> void:
	_write_json(TEST_POINTS_PATH, {"Chrono Drake": 4, "Zap": 1.0, "Broken": "lots"})
	var points := PointsList.new(TEST_POINTS_PATH)
	assert_eq(points.size(), 2, "entries without a number are skipped")
	var drake := _card("someone-elses-id", "  chrono drake ")
	assert_true(points.has_card(drake))
	assert_eq(points.points_for(drake), 4, "matched by name, ignoring case and spaces")
	assert_eq(points.points_for(_card("x", "Zap")), 1)
	assert_false(points.has_card(_card("y", "Unlisted")))

	var file := FileAccess.open(TEST_POINTS_PATH, FileAccess.WRITE)
	file.store_string("not json")
	file.close()
	assert_eq(PointsList.new(TEST_POINTS_PATH).size(), 0, "a file that is not JSON gives an empty list")
	assert_eq(PointsList.new("user://test_points/missing.json").size(), 0, "so does a missing file")


func test_the_game_comes_with_a_points_list_and_players_cannot_import_one() -> void:
	assert_true(FileAccess.file_exists(PointsList.DEFAULT_PATH), "the list ships with the game")
	var scene := _make_scene_with_cards(1)
	assert_null(scene.get_node_or_null("%ImportPointsButton"), "the deck builder has no import button")


func test_points_list_overrides_the_points_on_the_card() -> void:
	var points := _points({"Zap": 1})
	var zap := _card("z", "Zap")
	zap.points = 5
	var own := _card("o", "Own price")
	own.points = 3
	assert_eq(points.points_for(zap), 1, "a card on the list costs what the list says")
	assert_eq(points.points_for(own), 3, "a card not on the list costs what its maker set")
	assert_false(points.has_card(own))
	assert_eq(points.points_for(_card("n", "Free")), 0)

	var deck := DeckData.new()
	deck.counts = {"z": 2, "o": 1}
	assert_eq(deck.used_points({"z": zap, "o": own}, points), 5, "2 x 1 from the list + 3 from the card")


func test_sorted_ids_go_by_type_then_time_then_name_and_repeat_copies() -> void:
	var cards := {
		"spell": _card("spell", "Zap", 5, "Spell"),
		"slow": _card("slow", "Slow", 30),
		"fast_b": _card("fast_b", "Beta", 10),
		"fast_a": _card("fast_a", "Alpha", 10),
	}
	var deck := DeckData.new()
	deck.counts = {"spell": 1, "slow": 1, "fast_b": 2, "fast_a": 1}
	assert_eq(
		deck.sorted_ids(cards), ["fast_a", "fast_b", "fast_b", "slow", "spell"] as Array[String]
	)


func test_deck_dict_roundtrip_clamps_copies() -> void:
	var deck := DeckData.from_dict({"deck_name": "Mine", "cards": {"a": 2, "b": 9, "c": 0}})
	assert_eq(deck.deck_name, "Mine")
	assert_eq(deck.copies("a"), 2)
	assert_eq(deck.copies("b"), DeckData.MAX_COPIES)
	assert_false(deck.counts.has("c"))


func test_deck_library_saves_loads_lists_and_deletes() -> void:
	var library := DeckLibrary.new(TEST_DECKS_DIR)
	var deck := DeckData.new()
	assert_eq(library.save_deck(deck), ERR_INVALID_PARAMETER, "a deck needs a name")
	deck.deck_name = "Time: Lords"
	deck.add("a")
	deck.add("a")
	assert_eq(library.save_deck(deck), OK)
	assert_eq(library.list_names(), ["Time: Lords"] as Array[String])
	var loaded := library.load_deck("Time: Lords")
	assert_eq(loaded.copies("a"), 2)
	assert_null(library.load_deck("nope"))
	assert_eq(library.delete_deck("Time: Lords"), OK)
	assert_eq(library.list_names(), [] as Array[String])


func _write_json(path: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func test_deck_library_reads_a_deck_file_without_saving_it() -> void:
	var library := DeckLibrary.new(TEST_DECKS_DIR)
	var path := TEST_IMPORT_DIR.path_join("shared.json")
	_write_json(path, {"deck_name": "Shared", "cards": {"a": 2, "b": 9}})
	var deck := library.read_file(path)
	assert_eq(deck.deck_name, "Shared")
	assert_eq(deck.copies("a"), 2)
	assert_eq(deck.copies("b"), DeckData.MAX_COPIES)
	assert_eq(library.list_names(), [] as Array[String], "reading a file saves nothing")

	_write_json(path, {"Chrono Drake": 4})
	assert_null(library.read_file(path), "a points list is not a deck")
	_write_json(path, [1, 2])
	assert_null(library.read_file(path), "neither is a list")
	assert_null(library.read_file(TEST_IMPORT_DIR.path_join("missing.json")))


func test_card_library_roundtrip_with_art_and_face() -> void:
	var library := CardLibrary.new(TEST_CARDS_DIR)
	var card := _card("", "Chrono Drake", 15)
	card.subtype = "Dragon"
	card.rules_text = "Draw a card."
	card.image = Image.create(8, 8, false, Image.FORMAT_RGB8)
	var face := Image.create(744, 1040, false, Image.FORMAT_RGBA8)
	assert_eq(library.save_card(card, face), OK)
	assert_false(card.id.is_empty(), "saving gives the card an id")

	var loaded := library.load_cards()
	assert_eq(loaded.size(), 1)
	assert_eq(loaded[0].id, card.id)
	assert_eq(loaded[0].card_name, "Chrono Drake")
	assert_eq(loaded[0].time_cost, 15)
	assert_eq(loaded[0].rules_text, "Draw a card.")
	assert_not_null(loaded[0].image)
	assert_null(library.load_cards(false)[0].image, "art is skipped on request")
	assert_eq(library.load_face(card.id).get_size(), CardLibrary.FACE_SIZE)

	library.delete_card(card.id)
	assert_eq(library.load_cards().size(), 0)
	assert_null(library.load_face(card.id))


func test_saving_a_card_again_updates_it() -> void:
	var library := CardLibrary.new(TEST_CARDS_DIR)
	var card := _card("", "First name")
	library.save_card(card)
	card.card_name = "Second name"
	library.save_card(card)
	var loaded := library.load_cards()
	assert_eq(loaded.size(), 1)
	assert_eq(loaded[0].card_name, "Second name")


func _make_scene_with_cards(count: int) -> Control:
	var library := CardLibrary.new(TEST_CARDS_DIR)
	for i in count:
		library.save_card(_card("", "Card %d" % i, i), Image.create(744, 1040, false, Image.FORMAT_RGBA8))
	var scene: Control = load("res://scenes/decks.tscn").instantiate()
	scene.card_library = library
	scene.official_library = CardLibrary.new(TEST_OFFICIAL_DIR)
	scene.deck_library = DeckLibrary.new(TEST_DECKS_DIR)
	scene.points_list = PointsList.new(TEST_POINTS_PATH)
	add_child_autofree(scene)
	return scene


## The text of every label under a node, one after the other.
func _texts(root: Node) -> String:
	var texts: Array[String] = []
	for label: Label in root.find_children("*", "Label", true, false):
		texts.append(label.text)
	return " | ".join(texts)


## The row of the deck for a card, by its place in the list.
func _row(deck_list: Node, index: int) -> DeckRow:
	return deck_list.get_child(index) as DeckRow


func test_deck_builder_lists_cards_and_adds_and_removes() -> void:
	var scene := _make_scene_with_cards(3)
	var results: Container = scene.get_node("%ResultGrid")
	var deck_list: Container = scene.get_node("%DeckList")
	assert_eq(results.get_child_count(), 3)
	assert_eq(deck_list.get_child_count(), 0)
	var card_id: String = scene._cards[0].id
	scene._add_card(card_id)
	scene._add_card(card_id)
	assert_eq(deck_list.get_child_count(), 1, "one row for a card, however many copies")
	assert_eq(scene._deck.copies(card_id), 2)
	assert_eq(_row(deck_list, 0).copies, 2, "the row says how many copies")
	scene._add_card(card_id)
	scene._add_card(card_id)
	assert_eq(scene._deck.copies(card_id), 3, "capped at three copies")
	assert_eq(_row(deck_list, 0).copies, 3)
	assert_true(_row(deck_list, 0)._plus_button.disabled, "+ is off at three copies")
	scene._remove_card(card_id)
	assert_eq(scene._deck.copies(card_id), 2)
	assert_eq(_row(deck_list, 0).copies, 2)
	scene._remove_card(card_id)
	scene._remove_card(card_id)
	assert_eq(deck_list.get_child_count(), 0, "the row goes with the last copy")


func test_a_deck_row_has_plus_and_minus_in_its_name_box_and_the_copies_and_their_cost_outside_it() -> void:
	var scene := _make_scene_with_cards(2)
	scene.points_list = _points({"Card 1": 4})
	var card: CardData = scene._cards[1]
	scene._add_card(card.id)
	scene._add_card(card.id)
	await get_tree().process_frame
	await get_tree().process_frame
	var row: DeckRow = _row(scene.get_node("%DeckList"), 0)
	var box: Control = row._box
	var count: Label = row._count_label
	var total: Label = row._total_label

	assert_true(box.is_ancestor_of(row._plus_button), "+ is in the box")
	assert_true(box.is_ancestor_of(row._minus_button), "and so is −")
	assert_lt(row._plus_button.global_position.y, row._minus_button.global_position.y, "with + over −")
	assert_gte(row._plus_button.global_position.x, box.global_position.x + box.size.x * 0.5, "at the right end of the box")
	var in_the_box: Array[String] = []
	for label: Label in box.find_children("*", "Label", true, false):
		in_the_box.append(label.text)
	assert_eq(in_the_box, ["Card 1"] as Array[String], "only the name is in the box: no time cost, no copies")

	assert_false(box.is_ancestor_of(count), "the copies are outside the box")
	assert_eq(count.text, "2")
	assert_gte(count.global_position.x, box.get_global_rect().end.x, "at its right")
	assert_eq(total.text, "8", "and the total cost: 2 copies at 4 points")
	assert_gte(total.global_position.x, count.get_global_rect().end.x - 1.0, "at the right of the copies")

	row._plus_button.pressed.emit()
	assert_eq(count.text, "3")
	assert_eq(total.text, "12", "the total follows the number of copies")
	assert_eq(scene._deck.copies(card.id), 3, "and the deck follows + and −")
	assert_true(row._plus_button.disabled, "no more than three copies")
	row._minus_button.pressed.emit()
	assert_eq(scene._deck.copies(card.id), 2)
	assert_eq(count.text, "2")


func test_plus_and_minus_of_a_row_change_the_deck_and_a_row_with_no_copies_goes() -> void:
	var scene := _make_scene_with_cards(3)
	var deck_list: Container = scene.get_node("%DeckList")
	# The cards cost 0, 1 and 2, so the cheapest comes first.
	for card: CardData in scene._cards:
		scene._add_card(card.id)
	var names: Array[String] = []
	for row: DeckRow in deck_list.get_children():
		names.append(scene._cards_by_id[row.card_id].card_name)
	assert_eq(names, ["Card 0", "Card 1", "Card 2"] as Array[String])

	var middle: DeckRow = _row(deck_list, 1)
	var middle_id := middle.card_id
	middle._plus_button.pressed.emit()
	middle._plus_button.pressed.emit()
	assert_eq(scene._deck.copies(middle_id), 3, "+ adds copies")
	assert_same(_row(deck_list, 1), middle, "the row stays")
	assert_eq(scene._deck.size(), 5)
	assert_eq((scene.get_node("%CountLabel") as Label).text, "5", "and the count follows")

	for i in 3:
		middle._minus_button.pressed.emit()
	assert_eq(scene._deck.copies(middle_id), 0, "− takes them out")
	assert_eq(deck_list.get_child_count(), 2, "and the row goes with the last one")

	var first: DeckRow = _row(deck_list, 0)
	var first_id := first.card_id
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	first._on_box_input(click)
	assert_eq(scene._deck.copies(first_id), 0, "a right click on the box takes a copy out")


func test_the_deck_counts_cards_and_points_with_no_line_about_what_it_needs() -> void:
	var scene := _make_scene_with_cards(2)
	var hint: Label = scene.get_node("%EmptyDeckLabel")
	assert_true(hint.visible, "an empty deck says how to fill it")
	assert_eq((scene.get_node("%CountLabel") as Label).text, "0")
	scene._add_card(scene._cards[0].id)
	assert_false(hint.visible)
	assert_eq((scene.get_node("%CountLabel") as Label).text, "1")
	assert_eq((scene.get_node("%PointsLabel") as Label).text, "0", "the points the deck uses")
	assert_eq((scene.get_node("%PointsAvailableLabel") as Label).text, "/ 100", "and the points there are")
	assert_null(scene.get_node_or_null("%ValidityLabel"), "there is no line about what the deck needs")
	assert_false(_texts(scene).contains("Needs"))
	assert_false(_texts(scene).contains("Legal deck"))


func test_the_points_there_are_are_outside_the_points_box() -> void:
	var scene := _make_scene_with_cards(1)
	await get_tree().process_frame
	await get_tree().process_frame
	var box: Control = scene.get_node("%PointsLabel").get_parent()
	var available: Control = scene.get_node("%PointsAvailableLabel")
	assert_false(box.is_ancestor_of(available), "not in the box")
	assert_gte(available.global_position.x, box.get_global_rect().end.x, "but at its right")


func test_the_card_info_is_at_the_right_of_the_deck_and_the_cards() -> void:
	var scene := _make_scene_with_cards(1)
	await get_tree().process_frame
	await get_tree().process_frame
	var deck: Control = scene.get_node("%DeckList").get_parent().get_parent().get_parent().get_parent().get_parent()
	var cards: Control = scene.get_node("%SearchPanel")
	var info: Control = (scene.get_node("%Info") as Control).get_parent().get_parent().get_parent().get_parent()
	assert_lt(deck.global_position.x, cards.global_position.x, "the deck is on the left")
	assert_gte(info.global_position.x, cards.get_global_rect().end.x, "and the card info after the cards, on the right")


func test_selecting_a_card_shows_its_picture_and_details() -> void:
	var scene := _make_scene_with_cards(2)
	var info: Control = scene.get_node("%Info")
	assert_string_contains(_texts(info), CardInfo.NOTHING_TEXT, "nothing is selected at first")
	assert_null((scene.get_node("%Preview") as TextureRect).texture)

	var card: CardData = scene._cards[1]
	scene._select(card.id)
	var details := _texts(info)
	assert_string_contains(details, card.card_name)
	for caption in ["Time cost", "Points", "In deck", "Attack", "Defense"]:
		assert_string_contains(details, caption, "a creature shows its %s" % caption)
	assert_string_contains(details, "0 / 3", "none of it is in the deck yet")
	assert_not_null((scene.get_node("%Preview") as TextureRect).texture)

	scene._add_card(card.id)
	assert_string_contains(_texts(info), "1 / 3", "the details follow the deck")


func test_deck_builder_offers_official_and_custom_cards() -> void:
	var official := CardLibrary.new(TEST_OFFICIAL_DIR)
	var founder := _card("", "Founder", 10)
	official.save_card(founder, Image.create(744, 1040, false, Image.FORMAT_RGBA8))
	# A custom copy of an official card (same id) is that official card, not a second card.
	var copy := _card(founder.id, "Founder", 10)
	CardLibrary.new(TEST_CARDS_DIR).save_card(copy)

	var scene := _make_scene_with_cards(2)
	var results: Container = scene.get_node("%ResultGrid")
	assert_eq(results.get_child_count(), 3, "the official card and the two custom ones, once each")
	assert_has(scene._cards_by_id, founder.id)
	scene._add_card(founder.id)
	assert_eq(scene._deck.copies(founder.id), 1, "an official card can go in a deck")
	assert_not_null(scene._textures.get(founder.id), "and it shows its picture")


func test_card_catalog_merges_official_and_custom_cards() -> void:
	var official := CardLibrary.new(TEST_OFFICIAL_DIR)
	var custom := CardLibrary.new(TEST_CARDS_DIR)
	var zed := _card("", "Zed")
	official.save_card(zed, Image.create(744, 1040, false, Image.FORMAT_RGBA8))
	var alpha := _card("", "Alpha")
	custom.save_card(alpha, Image.create(744, 1040, false, Image.FORMAT_RGBA8))
	custom.save_card(_card(zed.id, "Zed"))

	var catalog := CardCatalog.new(official, custom)
	var names: Array[String] = []
	for card in catalog.load_cards():
		names.append(card.card_name)
	assert_eq(names, ["Alpha", "Zed"] as Array[String], "sorted by name, the copy of Zed only once")
	assert_true(catalog.is_custom(alpha.id))
	assert_false(catalog.is_custom(zed.id), "a copy of an official card is the official card")
	assert_true(catalog.has_custom())
	assert_not_null(catalog.load_face(alpha.id))
	assert_not_null(catalog.load_face(zed.id), "faces come from the library the card belongs to")


func test_deck_builder_search_box() -> void:
	var scene := _make_scene_with_cards(3)
	var results: Container = scene.get_node("%ResultGrid")
	var search: LineEdit = scene.get_node("%SearchEdit")
	search.text = "card 1"
	search.text_changed.emit(search.text)
	assert_eq(results.get_child_count(), 1)
	search.text = ""
	search.text_changed.emit("")
	assert_eq(results.get_child_count(), 3)


## Types into a field of the filters the way a player does, so the list updates.
func _type_filter(form: CardSearchForm, field: String, text: String) -> void:
	var edit: LineEdit = form.get_node(field)
	edit.text = text
	edit.text_changed.emit(text)


func test_deck_builder_filters_are_the_database_search_form() -> void:
	var scene := _make_scene_with_cards(3)
	var results: Container = scene.get_node("%ResultGrid")
	var button: Button = scene.get_node("%FiltersButton")
	var panel: Control = scene.get_node("%FiltersOverlay")
	var form: CardSearchForm = scene.get_node("%SearchForm")
	assert_false(panel.visible, "the filters start closed")
	assert_null(scene.get_node_or_null("%TypeFilter"), "the form replaces the old type dropdown")
	assert_eq(form.source(), CardSearchForm.SOURCE_BOTH, "a deck can use every card")

	button.button_pressed = true
	assert_true(panel.visible)
	assert_true(results.is_visible_in_tree(), "the cards stay in view while the filters are open")

	_type_filter(form, "%TypeEdit", "spell")
	assert_eq(results.get_child_count(), 0, "no spells in this library")
	assert_eq(button.text, "Filters (1)", "the button says how many filters are in use")
	_type_filter(form, "%TypeEdit", "creature")
	assert_eq(results.get_child_count(), 3)

	var time_filter: Dictionary = form._number_filters[0]
	(time_filter["value"] as NumberStepper).value = 1
	(time_filter["comparison"] as OptionButton).select(4)  # ≥
	(time_filter["comparison"] as OptionButton).item_selected.emit(4)
	assert_eq(results.get_child_count(), 2, "time cost 1 or more: Card 1 and Card 2")
	assert_eq(button.text, "Filters (2)")

	var search: LineEdit = scene.get_node("%SearchEdit")
	search.text = "card 2"
	search.text_changed.emit(search.text)
	assert_eq(results.get_child_count(), 1, "the search box and the filters apply together")

	(scene.get_node("%ClearFiltersButton") as Button).pressed.emit()
	assert_eq(results.get_child_count(), 1, "clearing the filters leaves the search box")
	assert_eq(button.text, "Filters")
	search.text = ""
	search.text_changed.emit("")
	assert_eq(results.get_child_count(), 3)

	(form.get_node("%CardSourceOption") as OptionButton).select(CardSearchForm.SOURCE_OFFICIAL)
	(form.get_node("%CardSourceOption") as OptionButton).item_selected.emit(CardSearchForm.SOURCE_OFFICIAL)
	assert_eq(results.get_child_count(), 0, "the Cards choice works here too: there are no official cards")

	button.button_pressed = false
	assert_false(panel.visible)


func test_the_filters_panel_covers_the_left_side_and_stops_before_the_cards() -> void:
	var scene := _make_scene_with_cards(3)
	await get_tree().process_frame
	var button: Button = scene.get_node("%FiltersButton")
	var drawer: Control = scene.get_node("%FiltersDrawer")
	var body: Control = scene.get_node("%Body")
	var cards: Control = scene.get_node("%SearchPanel")
	button.button_pressed = true
	await get_tree().process_frame
	assert_almost_eq(drawer.global_position.x, body.global_position.x, 0.5, "it starts at the left edge")
	assert_lt(drawer.global_position.x + drawer.size.x, cards.global_position.x, "and stops before the cards")
	assert_lte(drawer.global_position.y, body.global_position.y, "from the top of the columns or higher")
	assert_gte(
		drawer.global_position.y + drawer.size.y, body.global_position.y + body.size.y - 0.5, "to the bottom of them"
	)
	assert_eq(
		(scene.get_node("%FiltersOverlay") as Control).mouse_filter,
		Control.MOUSE_FILTER_IGNORE,
		"clicks outside the panel reach the cards"
	)

	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	scene._unhandled_input(escape)
	assert_false((scene.get_node("%FiltersOverlay") as Control).visible, "Escape closes it")
	assert_false(button.button_pressed, "and the button is not lit any more")


func test_the_card_pictures_fill_each_row_of_the_list() -> void:
	var scene := _make_scene_with_cards(6)
	await get_tree().process_frame
	await get_tree().process_frame
	var grid: Control = scene.get_node("%ResultGrid")
	var thumbs := grid.get_children()
	assert_eq(thumbs.size(), 6)
	var first: Control = thumbs[0]
	assert_gte(first.custom_minimum_size.x, scene.RESULT_MIN_WIDTH, "no smaller than the smallest size")
	assert_almost_eq(
		first.custom_minimum_size.y / first.custom_minimum_size.x,
		CardThumb.THUMB_SIZE.y / CardThumb.THUMB_SIZE.x,
		0.02,
		"with the card's proportions"
	)
	# Each row is full: the pictures of the first row end where the list does.
	var right_edge := 0.0
	for thumb: Control in thumbs:
		if is_equal_approx(thumb.global_position.y, first.global_position.y):
			right_edge = maxf(right_edge, thumb.global_position.x + thumb.size.x)
	assert_almost_eq(right_edge, grid.global_position.x + grid.size.x, 1.5)


func test_deck_builder_search_reads_words_and_quotes_like_every_search_field() -> void:
	var scene := _make_scene_with_cards(3)
	var results: Container = scene.get_node("%ResultGrid")
	var search: LineEdit = scene.get_node("%SearchEdit")
	for query in ["1 card", "CARD 1", "\"card 1\""]:
		search.text = query
		search.text_changed.emit(query)
		assert_eq(results.get_child_count(), 1, "“%s” finds Card 1" % query)
	search.text = "\"1 card\""
	search.text_changed.emit(search.text)
	assert_eq(results.get_child_count(), 0, "a quoted phrase keeps its order")
	search.text = "card"
	search.text_changed.emit("card")
	assert_eq(results.get_child_count(), 3)


func test_deck_builder_saves_and_reopens_a_deck() -> void:
	var scene := _make_scene_with_cards(2)
	var card_id: String = scene._cards[0].id
	scene._add_card(card_id)
	var name_edit: LineEdit = scene.get_node("%NameEdit")
	scene._save_deck()
	assert_eq(scene.deck_library.list_names().size(), 0, "a deck needs a name")
	name_edit.text = "Test deck"
	name_edit.text_changed.emit("Test deck")
	scene._save_deck()
	assert_eq(scene.deck_library.list_names(), ["Test deck"] as Array[String])
	scene._clear_deck()
	assert_eq(scene._deck.size(), 0)
	var option: OptionButton = scene.get_node("%DeckOption")
	assert_eq(option.get_item_text(option.selected), "Test deck")
	scene._on_deck_option_selected(option.selected)
	assert_eq(scene._deck.copies(card_id), 1)


func test_deck_builder_imports_a_deck_from_the_picker() -> void:
	var scene := _make_scene_with_cards(2)
	assert_null(scene.get_node_or_null("%ImportCardsButton"), "cards are imported in Create Cards")
	var option: OptionButton = scene.get_node("%DeckOption")
	assert_eq(option.get_item_text(0), "New deck")
	assert_eq(option.get_item_text(1), "Import deck...", "the import sits right under New deck")

	var card_id: String = scene._cards[0].id
	var path := TEST_IMPORT_DIR.path_join("shared.json")
	_write_json(path, {"deck_name": "Shared", "cards": {card_id: 2}})
	scene._import_deck(path)
	assert_eq(scene._deck.copies(card_id), 2)
	assert_eq((scene.get_node("%NameEdit") as LineEdit).text, "Shared")
	assert_eq(option.selected, 0, "an imported deck is a new deck until it is saved")
	assert_eq(scene.deck_library.list_names().size(), 0, "importing saves nothing by itself")

	scene._save_deck()
	assert_eq(scene.deck_library.list_names(), ["Shared"] as Array[String])
	assert_eq(option.get_item_text(option.selected), "Shared")
	assert_eq(option.selected, 2, "saved decks come after New deck and Import deck...")

	_write_json(path, {"Chrono Drake": 4})
	scene._import_deck(path)
	assert_eq(scene._deck.copies(card_id), 2, "a file that is not a deck changes nothing")
	assert_string_contains((scene.get_node("%Status") as Label).text, "is not a deck")


func test_deck_builder_drag_and_drop_rules() -> void:
	var scene := _make_scene_with_cards(1)
	var card_id: String = scene._cards[0].id
	assert_true(scene._can_drop_on_deck(Vector2.ZERO, {"card_id": card_id, "from": &"results"}))
	assert_false(scene._can_drop_on_deck(Vector2.ZERO, {"card_id": card_id, "from": &"deck"}))
	assert_false(scene._can_drop_on_results(Vector2.ZERO, "not a drag"))
	scene._drop_on_deck(Vector2.ZERO, {"card_id": card_id, "from": &"results"})
	assert_eq(scene._deck.copies(card_id), 1)
	scene._drop_on_results(Vector2.ZERO, {"card_id": card_id, "from": &"deck"})
	assert_eq(scene._deck.copies(card_id), 0)


func test_card_png_carries_the_card_and_imports() -> void:
	var card := _card("abc123", "Chrono Drake", 15)
	card.subtype = "Dragon"
	card.points = 4
	card.rules_text = "Draw a card. ✓"
	card.image = Image.create(8, 8, false, Image.FORMAT_RGB8)
	card.image.fill(Color.RED)
	var face := Image.create(744, 1040, false, Image.FORMAT_RGBA8)
	var plain := face.save_png_to_buffer()
	assert_null(CardPng.read_card(plain), "an ordinary PNG holds no card")

	var png := CardPng.write_card(plain, card)
	var still_an_image := Image.new()
	assert_eq(still_an_image.load_png_from_buffer(png), OK, "the PNG still opens as an image")
	assert_eq(still_an_image.get_size(), Vector2i(744, 1040))
	var read := CardPng.read_card(png)
	assert_eq(read.id, "abc123")
	assert_eq(read.card_name, "Chrono Drake")
	assert_eq(read.rules_text, "Draw a card. ✓")
	assert_eq(read.points, 4, "the deck point cost travels in the PNG")
	assert_eq(read.image.get_pixel(0, 0), Color.RED)

	DirAccess.make_dir_recursive_absolute(TEST_CARDS_DIR)
	var path := TEST_CARDS_DIR.path_join("shared.png.in")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(png)
	file.close()
	var library := CardLibrary.new(TEST_CARDS_DIR)
	var imported := library.import_png(path)
	assert_eq(imported.id, "abc123", "the card keeps its id, so imports of it match")
	var loaded := library.load_cards()
	assert_eq(loaded.size(), 1)
	assert_eq(loaded[0].card_name, "Chrono Drake")
	assert_eq(loaded[0].points, 4, "and is kept when the card is imported")
	assert_not_null(loaded[0].image)
	assert_eq(library.load_face("abc123").get_size(), CardLibrary.FACE_SIZE)

	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(plain)
	file.close()
	assert_null(library.import_png(path), "a plain PNG is refused")


func test_the_list_has_titles_over_card_copies_and_points_lined_up_with_the_rows() -> void:
	var scene := _make_scene_with_cards(20)
	var titles_box: Control = scene.get_node("%DeckTitles")
	assert_false(titles_box.visible, "no rows, no titles")
	scene._add_card(scene._cards[0].id)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(titles_box.is_visible_in_tree())
	var labels: Array[Node] = titles_box.find_children("*", "Label", true, false)
	var titles: Array[String] = []
	for label: Label in labels:
		titles.append(label.text)
	assert_eq(titles, ["Card", "Copies", "Points"] as Array[String])

	var deck_list: Container = scene.get_node("%DeckList")
	var row := _row(deck_list, 0)
	assert_lte(titles_box.get_global_rect().end.y, row.global_position.y + 1.0, "over the rows")
	assert_almost_eq(
		(labels[1] as Control).get_global_rect().get_center().x, row._count_label.get_global_rect().get_center().x, 1.0, "Copies is over the copies"
	)
	assert_almost_eq(
		(labels[2] as Control).get_global_rect().get_center().x, row._total_label.get_global_rect().get_center().x, 1.0, "Points over the points"
	)

	# With many rows the list has a scroll bar: the titles still line up with the rows.
	for card: CardData in scene._cards:
		scene._add_card(card.id)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true((scene.get_node("%DeckScroll") as ScrollContainer).get_v_scroll_bar().visible, "the list scrolls")
	var first := _row(deck_list, 0)
	assert_almost_eq(
		(labels[2] as Control).get_global_rect().get_center().x, first._total_label.get_global_rect().get_center().x, 1.0, "still over the points"
	)


func test_the_line_before_plus_and_minus_is_attached_to_the_box_and_the_buttons_reach_its_edge() -> void:
	var scene := _make_scene_with_cards(1)
	scene._add_card(scene._cards[0].id)
	await get_tree().process_frame
	await get_tree().process_frame
	var row := _row(scene.get_node("%DeckList"), 0)
	var box: Control = row._box
	var line: Control = row._divider
	assert_almost_eq(line.global_position.y, box.global_position.y + 1.0, 0.5, "the line starts at the top border of the box")
	assert_almost_eq(line.get_global_rect().end.y, box.get_global_rect().end.y - 1.0, 0.5, "and runs to the bottom border")
	assert_almost_eq(
		row._plus_button.global_position.x, line.get_global_rect().end.x, 0.5, "with + and − right against it, no space between"
	)
	assert_almost_eq(row._minus_button.global_position.x, row._plus_button.global_position.x, 0.5, "in one column")
	assert_almost_eq(
		row._plus_button.get_global_rect().end.x, box.get_global_rect().end.x, 1.5, "+ and − reach the right edge of the box"
	)
	assert_almost_eq(row._plus_button.global_position.y, box.global_position.y + 1.0, 1.5, "+ is at the top")
	assert_almost_eq(row._minus_button.get_global_rect().end.y, box.get_global_rect().end.y, 1.5, "and − at the bottom")


func test_the_box_and_the_two_numbers_are_the_same_distance_apart() -> void:
	var scene := _make_scene_with_cards(1)
	scene._add_card(scene._cards[0].id)
	await get_tree().process_frame
	await get_tree().process_frame
	var row := _row(scene.get_node("%DeckList"), 0)
	var between_box_and_copies: float = row._count_label.global_position.x - row._box.get_global_rect().end.x
	var between_copies_and_points: float = row._total_label.global_position.x - row._count_label.get_global_rect().end.x
	assert_almost_eq(between_box_and_copies, between_copies_and_points, 1.0, "the same space on both sides of the copies")
	assert_almost_eq(between_box_and_copies, float(DeckRow.GAP), 1.0)
	assert_almost_eq(row._count_label.size.x, row._total_label.size.x, 0.5, "and the two numbers have columns of the same width")


func test_a_deck_row_has_no_stripe_and_its_name_and_the_title_over_it_start_at_the_left() -> void:
	var scene := _make_scene_with_cards(1)
	scene._add_card(scene._cards[0].id)
	await get_tree().process_frame
	await get_tree().process_frame
	var row := _row(scene.get_node("%DeckList"), 0)
	var box: Control = row._box
	for rect: ColorRect in box.find_children("*", "ColorRect", true, false):
		assert_lte(rect.custom_minimum_size.x, 1.0, "nothing at the left of the name but its margin: only thin lines are left")
	var name_label: Label = row._name_label
	assert_eq(name_label.horizontal_alignment, HORIZONTAL_ALIGNMENT_LEFT)
	assert_almost_eq(name_label.global_position.x - box.global_position.x, DeckRow.NAME_INDENT, 1.0, "the name starts at the left of the box")

	var title: Label = (scene.get_node("%DeckTitles") as Control).find_children("*", "Label", true, false)[0]
	assert_eq(title.text, "Card")
	assert_eq(title.horizontal_alignment, HORIZONTAL_ALIGNMENT_LEFT)
	assert_almost_eq(
		title.global_position.x + DeckRow.NAME_INDENT, name_label.global_position.x, 1.0, "and the title starts where the names do"
	)
