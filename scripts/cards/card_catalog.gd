class_name CardCatalog
extends RefCounted
## Every card the player can use: the official cards that come with the game plus the custom
## cards they created or imported. A custom card with the id of an official card (an imported copy
## of it) is that official card, not a second card.

var official: CardLibrary
var custom: CardLibrary

var _custom_ids: Dictionary[String, bool] = {}
var _official_ids: Dictionary[String, bool] = {}


func _init(official_library: CardLibrary, custom_library: CardLibrary) -> void:
	official = official_library
	custom = custom_library


## All the cards, sorted by name. Pass `with_art` = false to skip loading the pictures.
func load_cards(with_art := true) -> Array[CardData]:
	var cards := official.load_cards(with_art)
	_official_ids.clear()
	for card in cards:
		_official_ids[card.id] = true
	_custom_ids.clear()
	for card in custom.load_cards(with_art):
		if not _official_ids.has(card.id):
			_custom_ids[card.id] = true
			cards.append(card)
	cards.sort_custom(
		func(a: CardData, b: CardData) -> bool: return a.card_name.naturalnocasecmp_to(b.card_name) < 0
	)
	return cards


## The ids of the official cards, as of the last load_cards (id -> true).
func official_ids() -> Dictionary:
	var ids := {}
	for card_id in _official_ids:
		ids[card_id] = true
	return ids


## Cards by id (id -> CardData).
static func by_id(cards: Array[CardData]) -> Dictionary:
	var found := {}
	for card in cards:
		found[card.id] = card
	return found


## Whether the card, as of the last load_cards, is a custom card.
func is_custom(card_id: String) -> bool:
	return _custom_ids.has(card_id)


## Whether the last load_cards found any custom cards.
func has_custom() -> bool:
	return not _custom_ids.is_empty()


## The rendered card, from whichever library it belongs to, or null if it has none.
func load_face(card_id: String) -> Image:
	return (custom if is_custom(card_id) else official).load_face(card_id)
