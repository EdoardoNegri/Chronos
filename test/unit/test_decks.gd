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


func test_deck_builder_lists_cards_and_adds_and_removes() -> void:
	var scene := _make_scene_with_cards(3)
	var results: Container = scene.get_node("%ResultGrid")
	var deck_grid: Container = scene.get_node("%DeckGrid")
	assert_eq(results.get_child_count(), 3)
	var card_id: String = scene._cards[0].id
	scene._add_card(card_id)
	scene._add_card(card_id)
	assert_eq(deck_grid.get_child_count(), 2)
	assert_eq(scene._deck.copies(card_id), 2)
	scene._add_card(card_id)
	scene._add_card(card_id)
	assert_eq(deck_grid.get_child_count(), 3, "capped at three copies")
	scene._remove_card(card_id)
	assert_eq(deck_grid.get_child_count(), 2)


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
	var panel: Control = scene.get_node("%FiltersScroll")
	var form: CardSearchForm = scene.get_node("%SearchForm")
	assert_false(panel.visible, "the filters start closed")
	assert_null(scene.get_node_or_null("%TypeFilter"), "the form replaces the old type dropdown")
	assert_eq(form.source(), CardSearchForm.SOURCE_BOTH, "a deck can use every card")

	button.button_pressed = true
	assert_true(panel.visible)
	assert_gt((scene.get_node("%SearchPanel") as Control).size_flags_stretch_ratio, 1.0, "the list gets more room")

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
	assert_eq((scene.get_node("%SearchPanel") as Control).size_flags_stretch_ratio, 1.0)


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
