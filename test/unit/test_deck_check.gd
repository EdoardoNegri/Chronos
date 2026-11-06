extends GutTest

const Decks := preload("res://test/helpers/decks.gd")


func _official_cards() -> Dictionary:
	return CardLibrary.new(CardLibrary.OFFICIAL_DIRECTORY).load_by_id(false)


func _official_deck(_official: Dictionary) -> DeckData:
	return Decks.official_deck()


func _custom_card(points := 1) -> CardData:
	var card := CardData.new()
	card.id = "custom_1"
	card.card_name = "Homebrew"
	card.points = points
	return card


func _no_points_list() -> PointsList:
	return PointsList.new("user://no_points_list.json")


func test_a_legal_deck_of_official_cards_can_be_played_anywhere() -> void:
	var official := _official_cards()
	var deck := _official_deck(official)
	assert_eq(DeckCheck.problems(deck, official, _no_points_list(), false, official), [] as Array[String])
	assert_eq(DeckCheck.problems(deck, official, _no_points_list(), true, official), [] as Array[String])


func test_custom_cards_are_only_allowed_where_the_room_says_so() -> void:
	var official := _official_cards()
	var deck := _official_deck(official)
	deck.add("custom_1")
	var cards := official.duplicate()
	cards["custom_1"] = _custom_card()
	assert_eq(DeckCheck.problems(deck, cards, _no_points_list(), true, official), [] as Array[String])
	var standard := DeckCheck.problems(deck, cards, _no_points_list(), false, official)
	assert_eq(standard, ["1 custom card is not allowed in a Standard room"] as Array[String])


func test_the_deck_building_rules_still_apply() -> void:
	var official := _official_cards()
	var deck := DeckData.new()
	deck.add("official_zap")
	assert_string_contains(DeckCheck.problems(deck, official, _no_points_list(), true, official)[0], "more cards")


func test_the_host_checks_a_sent_deck_with_its_own_official_cards() -> void:
	var official := _official_cards()
	var deck := _official_deck(official)
	deck.add("custom_1")
	var sent := DeckCheck.send_cards(deck, {"custom_1": _custom_card()}.merged(official), official)
	assert_eq(sent.size(), 1, "only the custom cards are sent")
	assert_eq(sent[0]["card_name"], "Homebrew")
	assert_eq(DeckCheck.check_sent(deck.to_dict(), sent, true, official, _no_points_list()), [] as Array[String])

	# A player who changed an official card's points in their game gains nothing: the host's
	# official cards count, whatever was sent for them.
	var cheaper: Array = sent.duplicate(true)
	var zap := (official["official_epoch_titan"] as CardData).to_dict()
	zap["points"] = 0
	cheaper.append(zap)
	var expensive := DeckData.from_dict(deck.to_dict())
	assert_eq(DeckCheck.check_sent(expensive.to_dict(), cheaper, true, official, _no_points_list()), [] as Array[String])

	var too_dear := DeckCheck.check_sent(deck.to_dict(), [_custom_card(50).to_dict()], true, official, _no_points_list())
	assert_string_contains(too_dear[0], "Over the point budget", "a custom card's points count")
	var missing := DeckCheck.check_sent(deck.to_dict(), [], true, official, _no_points_list())
	assert_string_contains(missing[0], "no longer in your library", "a card that was not sent is missing")
