extends RefCounted
## Decks for tests.


## Three of every official card: 54 cards within the point budget, so it can be played anywhere.
static func official_deck(deck_name := "Official deck") -> DeckData:
	var deck := DeckData.new()
	deck.deck_name = deck_name
	for card in CardLibrary.new(CardLibrary.OFFICIAL_DIRECTORY).load_cards(false):
		for i in DeckData.MAX_COPIES:
			deck.add(card.id)
	return deck
