class_name DeckCheck
extends RefCounted
## Whether a deck may be played in a room: the deck-building rules (DeckData.problems), and in a
## Standard room, official cards only (see RoomInfo).
##
## A player's game uses it to offer only the decks that are allowed. The host's game checks again
## before the player may say they are ready (see Lobby), with its own official cards and points
## list, so a deck cannot be made to pass by changing the game. A guest's custom cards are not in
## the host's game, so the guest sends them along (send_cards).

## The most custom cards one deck can send (a deck has at most this many different cards anyway).
const MAX_SENT_CARDS := 200


## What stops `deck` from being played in a room, or [] if nothing. `cards` maps card id ->
## CardData for every card the deck may use; `official` maps the ids of the official cards (to
## anything).
static func problems(deck: DeckData, cards: Dictionary, points_list: PointsList, custom_allowed: bool, official: Dictionary) -> Array[String]:
	var found := deck.problems(cards, points_list)
	if not custom_allowed:
		var custom := 0
		for card_id in deck.counts:
			if not official.has(card_id):
				custom += deck.counts[card_id]
		if custom > 0:
			found.append("%d custom %s not allowed in a Standard room" % [custom, "card is" if custom == 1 else "cards are"])
	return found


## The custom cards of a deck, as they are sent to the host to be checked. `cards` maps card id ->
## CardData; `official` maps the official ids.
static func send_cards(deck: DeckData, cards: Dictionary, official: Dictionary) -> Array[Dictionary]:
	var sent: Array[Dictionary] = []
	for card_id in deck.counts:
		var card: CardData = cards.get(card_id)
		if card != null and not official.has(card_id):
			sent.append(card.to_dict())
	return sent


## The host's check of a deck a player sent: `deck_data` as DeckData.to_dict gives it, and
## `sent_cards` as send_cards gives them. Official cards are always the host's own, whatever was
## sent for them.
static func check_sent(deck_data: Dictionary, sent_cards: Array, custom_allowed: bool, official_cards: Dictionary, points_list: PointsList) -> Array[String]:
	var deck := DeckData.from_dict(deck_data)
	var cards := official_cards.duplicate()
	for data: Variant in sent_cards.slice(0, MAX_SENT_CARDS):
		if data is Dictionary:
			var card := CardData.from_dict(data)
			if not card.id.is_empty() and not cards.has(card.id):
				cards[card.id] = card
	return problems(deck, cards, points_list, custom_allowed, official_cards)
