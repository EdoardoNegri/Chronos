extends GutTest

const TEST_CARDS_DIR := "user://test_cards"
const TEST_DECKS_DIR := "user://test_decks"


func after_each() -> void:
	# Let nodes queued for deletion go before the test ends.
	await get_tree().process_frame
	for directory in [TEST_CARDS_DIR, TEST_DECKS_DIR]:
		if not DirAccess.dir_exists_absolute(directory):
			continue
		for file_name in DirAccess.get_files_at(directory):
			DirAccess.remove_absolute(directory.path_join(file_name))
		DirAccess.remove_absolute(directory)


func _card(card_id: String, card_name: String, points: int, time_cost := 0, type := "Creature") -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.card_name = card_name
	card.points = points
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


func test_problems_report_size_budget_and_missing_cards() -> void:
	var cards := {"big": _card("big", "Big", 60)}
	var deck := DeckData.new()
	deck.counts = {"big": 2, "gone": 1}
	var found := deck.problems(cards)
	assert_eq(found.size(), 3)
	assert_string_contains(found[0], "47 more cards")
	assert_string_contains(found[1], "20")
	assert_string_contains(found[2], "no longer in your library")


func test_a_full_deck_within_budget_is_legal() -> void:
	var cards := {}
	var deck := DeckData.new()
	for i in 50:
		var card := _card("c%d" % i, "Card %d" % i, 2)
		cards[card.id] = card
		deck.counts[card.id] = 1
	assert_eq(deck.used_points(cards), 100)
	assert_eq(deck.problems(cards), [] as Array[String])


func test_sorted_ids_go_by_type_then_time_then_name_and_repeat_copies() -> void:
	var cards := {
		"spell": _card("spell", "Zap", 1, 5, "Spell"),
		"slow": _card("slow", "Slow", 1, 30),
		"fast_b": _card("fast_b", "Beta", 1, 10),
		"fast_a": _card("fast_a", "Alpha", 1, 10),
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


func test_card_library_roundtrip_with_art_and_face() -> void:
	var library := CardLibrary.new(TEST_CARDS_DIR)
	var card := _card("", "Chrono Drake", 4, 15)
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
	assert_eq(loaded[0].points, 4)
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
	var card := _card("", "First name", 1)
	library.save_card(card)
	card.card_name = "Second name"
	library.save_card(card)
	var loaded := library.load_cards()
	assert_eq(loaded.size(), 1)
	assert_eq(loaded[0].card_name, "Second name")


func _make_scene_with_cards(count: int) -> Control:
	var library := CardLibrary.new(TEST_CARDS_DIR)
	for i in count:
		library.save_card(_card("", "Card %d" % i, 2, i), Image.create(744, 1040, false, Image.FORMAT_RGBA8))
	var scene: Control = load("res://scenes/decks.tscn").instantiate()
	scene.card_library = library
	scene.deck_library = DeckLibrary.new(TEST_DECKS_DIR)
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


func test_deck_builder_search_and_type_filter() -> void:
	var scene := _make_scene_with_cards(3)
	var results: Container = scene.get_node("%ResultGrid")
	var search: LineEdit = scene.get_node("%SearchEdit")
	search.text = "card 1"
	search.text_changed.emit(search.text)
	assert_eq(results.get_child_count(), 1)
	search.text = ""
	search.text_changed.emit("")
	var filter: OptionButton = scene.get_node("%TypeFilter")
	filter.select(CardData.TYPES.find("Spell") + 1)
	filter.item_selected.emit(filter.selected)
	assert_eq(results.get_child_count(), 0, "no spells in this library")


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
