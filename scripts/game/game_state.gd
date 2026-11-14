class_name GameState
extends RefCounted
## A game between two seats, as the host's game keeps it: each seat's deck and hand, the shared
## timer (rule 3.1), who acts next (rule 3.3) and who has won. Seat 0 is Player 1 (the room's host),
## seat 1 is Player 2.
##
## The actions so far are the forced draw (rule 3.4), paying time to draw a card, and playing a
## card from the hand for its time cost (rule 3.2): a creature goes onto its player's field, a spell
## into their graveyard (what cards do is not played yet). Where on the field a card lies does not
## matter, and there is no limit to how many there can be. The mulligan is not played yet either;
## the game starts with the opening hands as drawn.
##
## A seat nobody sits in (a local room started with one deck) never acts: the other seat acts every
## time, whatever the timer says, so a player can try out their deck alone.
##
## It holds no network: the host applies what players ask for and sends each of them view_for(their
## seat), which shows them only what they may see.

const NO_WINNER := -1
const SEATS := 2

## Where the shared timer stands: positive means Player 1 (seat 0) is that far ahead, negative that
## Player 2 is, 0 that they are even.
var timer := 0
## What the forced draw costs (rule 3.4).
var draw_cost := GameOptions.DEFAULT_FORCED_DRAW_COST
## Each seat's deck (card ids, the top card first) and hand (card ids, in the order drawn).
var decks: Array[Array] = [[], []]
var hands: Array[Array] = [[], []]
## Each seat's field (card ids, in the order played) and graveyard (card ids, the top card last).
var fields: Array[Array] = [[], []]
var graves: Array[Array] = [[], []]
## What each seat's cards are (card id -> CardData), for their time cost and type. A card that is
## not known costs nothing and is played as a creature.
var cards: Array[Dictionary] = [{}, {}]
## Whether someone sits in each seat.
var seated: Array[bool] = [true, true]
## The seat that acted last: at 0 on the timer, the other one acts.
var last_actor := 1
var winner := NO_WINNER


## A new game: each deck shuffled, the opening hands drawn, and the timer where the options start
## it. `starter` is the seat that acts first if the timer starts at 0. An empty `second_deck` with
## `second_seated` false is a game for one player.
static func create(
	first_deck: Array[String],
	second_deck: Array[String],
	options: GameOptions,
	starter: int,
	rng: RandomNumberGenerator,
	second_seated := true,
	card_pools: Array[Dictionary] = [{}, {}],
) -> GameState:
	var game := GameState.new()
	game.cards = card_pools.duplicate()
	game.draw_cost = options.forced_draw_cost
	game.timer = options.starting_timer
	game.seated = [true, second_seated]
	game.last_actor = other(starter)
	for seat in SEATS:
		var deck: Array = (first_deck if seat == 0 else second_deck).duplicate()
		_shuffle(deck, rng)
		game.decks[seat] = deck
		for i in mini(options.hand_size, deck.size()):
			game.hands[seat].append(deck.pop_front())
	return game


## One id per copy of each card in the deck.
static func card_ids(deck: DeckData) -> Array[String]:
	var ids: Array[String] = []
	for card_id in deck.counts:
		for i in deck.counts[card_id]:
			ids.append(card_id)
	ids.sort()
	return ids


## Who acts first if the timer is at 0 (rule 2.1): the seat the options name, or the one with the
## most points left unspent (`spare_points`, one number per seat), with a coin toss if that is tied.
static func pick_starter(options: GameOptions, spare_points: Array[int], rng: RandomNumberGenerator) -> int:
	match options.starter:
		GameOptions.Starter.PLAYER_1:
			return 0
		GameOptions.Starter.PLAYER_2:
			return 1
	if spare_points[0] != spare_points[1]:
		return 0 if spare_points[0] > spare_points[1] else 1
	return rng.randi_range(0, 1)


static func other(seat: int) -> int:
	return 1 - seat


## How far ahead on the timer this seat is (negative: behind).
func time_ahead(seat: int) -> int:
	return timer if seat == 0 else -timer


## The seat that acts next (rule 3.3), or NO_WINNER once the game is over.
func actor() -> int:
	if is_over():
		return NO_WINNER
	for seat in SEATS:
		if not seated[other(seat)]:
			return seat
	if timer == 0:
		return other(last_actor)
	# The player who is behind acts.
	return 1 if timer > 0 else 0


func is_over() -> bool:
	return winner != NO_WINNER


## The forced draw (rule 3.4): this seat pays draw_cost time and draws a card. Drawing from an empty
## deck loses the game. Returns whether it was done (only the seat that acts can draw).
func forced_draw(seat: int) -> bool:
	if seat != actor():
		return false
	last_actor = seat
	timer += draw_cost if seat == 0 else -draw_cost
	if decks[seat].is_empty():
		winner = other(seat)
	else:
		hands[seat].append(decks[seat].pop_front())
	return true


## Plays a card from this seat's hand (rule 3.2): the timer moves toward them by its time cost, and
## it goes onto their field, or into their graveyard if it is a spell. Returns whether it was done
## (only the seat that acts can play, and only a card in their hand).
func play_card(seat: int, card_id: String) -> bool:
	if seat != actor() or not hands[seat].has(card_id):
		return false
	hands[seat].erase(card_id)
	last_actor = seat
	var card: CardData = cards[seat].get(card_id)
	var cost := maxi(0, card.time_cost) if card != null else 0
	timer += cost if seat == 0 else -cost
	if card != null and card.card_type == "Spell":
		graves[seat].append(card_id)
	else:
		fields[seat].append(card_id)
	return true


## What this seat's player sees: their own hand, how many cards everyone has, and the timer from
## their side. As a dictionary, so it can be sent over the network:
## seat, time_ahead (how far ahead they are, negative if behind), your_turn, hand, field and grave
## (card ids), deck_count, opponent_field and opponent_grave (card ids), opponent_hand_count,
## opponent_deck_count, opponent_seated, draw_cost, card_names (card id -> name, for the
## opponent's cards that are out, which the player may not have), and result ("" while the game is
## on, "won" or "lost").
func view_for(seat: int) -> Dictionary:
	var them := other(seat)
	var result := ""
	if is_over():
		result = "won" if winner == seat else "lost"
	return {
		"seat": seat,
		"time_ahead": time_ahead(seat),
		"your_turn": actor() == seat,
		"hand": hands[seat].duplicate(),
		"field": fields[seat].duplicate(),
		"grave": graves[seat].duplicate(),
		"deck_count": decks[seat].size(),
		"opponent_field": fields[them].duplicate(),
		"opponent_grave": graves[them].duplicate(),
		"card_names": _names_of(them, fields[them] + graves[them]),
		"opponent_hand_count": hands[them].size(),
		"opponent_deck_count": decks[them].size(),
		"opponent_seated": seated[them],
		"draw_cost": draw_cost,
		"result": result,
	}


## The names of these cards of a seat (card id -> name), as far as they are known.
func _names_of(seat: int, card_ids: Array) -> Dictionary:
	var names := {}
	for card_id: String in card_ids:
		var card: CardData = cards[seat].get(card_id)
		if card != null:
			names[card_id] = card.card_name
	return names


## Fisher-Yates, with the given generator so a test can repeat it.
static func _shuffle(cards: Array, rng: RandomNumberGenerator) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = cards[i]
		cards[i] = cards[j]
		cards[j] = swap
