class_name DeckData
extends RefCounted
## A deck: how many copies of each card, plus the deck-building rules (section 1 of the rulebook).

## Rule 1.1: copies of one card.
const MAX_COPIES := 3
## Rule 1.2: minimum deck size.
const MIN_SIZE := 50
## Rule 1.3: points to spend on the cost of the cards.
const BASE_POINTS := 100
## Rule 1.4: points gained for every card beyond MIN_SIZE.
const POINTS_PER_EXTRA_CARD := 1

var deck_name := ""
## Card id -> number of copies.
var counts: Dictionary[String, int] = {}


func size() -> int:
	var total := 0
	for copies_of_card in counts.values():
		total += copies_of_card
	return total


func copies(card_id: String) -> int:
	return counts.get(card_id, 0)


## Adds a copy. Returns false if the deck already has the maximum number of copies.
func add(card_id: String) -> bool:
	if copies(card_id) >= MAX_COPIES:
		return false
	counts[card_id] = copies(card_id) + 1
	return true


## Removes a copy. Returns false if the deck has none.
func remove(card_id: String) -> bool:
	if copies(card_id) == 0:
		return false
	if copies(card_id) == 1:
		counts.erase(card_id)
	else:
		counts[card_id] -= 1
	return true


func clear() -> void:
	counts.clear()


func usable_points() -> int:
	return BASE_POINTS + maxi(0, size() - MIN_SIZE) * POINTS_PER_EXTRA_CARD


## Points spent by the deck's cards, as `points_list` prices them. `cards` maps card id ->
## CardData; unknown ids cost nothing.
func used_points(cards: Dictionary, points_list: PointsList) -> int:
	var total := 0
	for card_id in counts:
		var card: CardData = cards.get(card_id)
		if card != null:
			total += points_list.points_for(card) * counts[card_id]
	return total


func missing_ids(cards: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	for card_id in counts:
		if not cards.has(card_id):
			missing.append(card_id)
	return missing


## What stops this deck from being legal. Empty if it is legal.
func problems(cards: Dictionary, points_list: PointsList) -> Array[String]:
	var found: Array[String] = []
	if size() < MIN_SIZE:
		var short := MIN_SIZE - size()
		found.append("Needs %d more %s" % [short, "card" if short == 1 else "cards"])
	var over := used_points(cards, points_list) - usable_points()
	if over > 0:
		found.append("Over the point budget by %d" % over)
	var missing := missing_ids(cards).size()
	if missing > 0:
		found.append("%d %s no longer in your library" % [missing, "card is" if missing == 1 else "cards are"])
	return found


## One id per copy, ordered by type, then time cost, then name.
func sorted_ids(cards: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for card_id in counts:
		for i in counts[card_id]:
			ids.append(card_id)
	ids.sort_custom(func(a: String, b: String) -> bool: return _comes_first(a, b, cards))
	return ids


func to_dict() -> Dictionary:
	return {"deck_name": deck_name, "cards": counts}


static func from_dict(data: Dictionary) -> DeckData:
	var deck := DeckData.new()
	deck.deck_name = str(data.get("deck_name", ""))
	var saved: Variant = data.get("cards", {})
	if saved is Dictionary:
		for card_id: Variant in saved:
			var copies_of_card := clampi(int(saved[card_id]), 0, MAX_COPIES)
			if copies_of_card > 0:
				deck.counts[str(card_id)] = copies_of_card
	return deck


static func _comes_first(a_id: String, b_id: String, cards: Dictionary) -> bool:
	var a: CardData = cards.get(a_id)
	var b: CardData = cards.get(b_id)
	if a == null or b == null:
		# Cards missing from the library go last.
		return a_id < b_id if a == b else a != null
	var a_type := CardData.TYPES.find(a.card_type)
	var b_type := CardData.TYPES.find(b.card_type)
	if a_type != b_type:
		return a_type < b_type
	if a.time_cost != b.time_cost:
		return a.time_cost < b.time_cost
	var by_name := a.card_name.naturalnocasecmp_to(b.card_name)
	return by_name < 0 if by_name != 0 else a_id < b_id
