class_name GameRules
extends RefCounted
## The rulebook shown on the Rules screen, in reading order.
## Each section holds numbered sub-rules (1., 1.1, 1.2, ...); the numbers come from the order here.
## Undecided values are marked inline as {note}; the UI shows them in blue and in parentheses.
## A sub-rule can list `alternatives`: other versions under consideration. They keep the number
## of the rule they would replace and are shown in a different color.
## Design ideas that are not rules live in docs/ideas.md, not here.

const SECTIONS: Array[Dictionary] = [
	{
		"title": "Deck",
		"rules": [
			{
				"title": "Copies",
				"text": "Each card can appear up to 3 times in a deck.",
			},
			{
				"title": "Minimum size",
				"text": "A deck has a minimum of 50 cards.",
			},
			{
				"title": "Point budget",
				"text": "You start with 100 points. Every card has a cost, and the sum of the costs of all cards in your deck cannot exceed your points.",
			},
			{
				"title": "Bigger decks",
				"text": "A deck has no maximum size. For every card beyond 50 you gain 1 extra point, so a 51-card deck has 101 points to spend.",
			},
		],
	},
	{
		"title": "Starting the game",
		"rules": [
			{
				"title": "Who starts",
				"text": "The player with the biggest difference between usable points and points used by their deck starts the game: they act first if the timer is at 0 when the game begins. If it is tied, a coin toss decides.",
			},
			{
				"title": "Starting timer",
				"text": "The shared timer starts at 0. Mulligan penalties (see 2.4) then move it toward the player who paid them, so if both players paid the same penalty it stays at 0.",
			},
			{
				"title": "Opening hand",
				"text": "Both players shuffle their deck and draw 7 cards {may change, 6 to 8}. Going first or second makes no difference to the hand: the second player gets no extra card.",
			},
			{
				"title": "Mulligan",
				"text": "Before the game starts, both players secretly and at the same time choose any number of cards from their opening hand to replace. Put the chosen cards aside, draw the same number of new cards, then shuffle the set-aside cards into your deck. Each card replaced moves the starting timer 5 {not decided yet} toward you. There is only one round of replacing.",
				"alternatives": [
					{
						"title": "Whole-hand mulligan",
						"text": "Before the game starts, both players secretly and at the same time decide whether to mulligan. To mulligan, shuffle your hand into your deck and draw 7 cards again. Each mulligan moves the starting timer 10 toward you, and you can mulligan as many times as you want.",
					},
					{
						"title": "Coin toss and informed mulligan",
						"text": "Toss a coin. The winner chooses between going first and mulliganing second.
Going first: you mulligan without knowing what the opponent did, and you act first if the timer starts at 0.
Mulliganing second: the opponent decides their mulligan first and tells you how many cards they replaced. You then decide yours, but you can replace at most as many cards as they did, and the opponent acts first if the timer starts at 0.",
					},
				],
			},
		],
	},
	{
		"title": "Time",
		"rules": [
			{
				"title": "Shared timer",
				"text": "There are no turns and no separate clocks: both players share a single timer. It shows which player is ahead in time and by how much, meaning how much more time they have spent than their opponent. At 0 the players are even.",
			},
			{
				"title": "Playing a card",
				"text": "When you play a card, the timer moves toward you by its time cost. If the players are even, a card costing 15 puts you 15 ahead. If your opponent is 20 ahead, the same card leaves them 5 ahead.",
			},
			{
				"title": "Who acts",
				"text": "The player who is behind acts next, so the player who is ahead waits until their opponent catches up. If the timer is at 0, the player who did not act last acts.",
			},
			{
				"title": "Forced draw",
				"text": "You can pay 100 time {amount not decided yet} to draw a card: the timer moves 100 toward you. If you have no other action available, you must do this. Trying to draw from an empty deck makes you lose.",
			},
		],
	},
	{
		"title": "Card text",
		"rules": [
			{
				"title": "Phrasing",
				"text": "A common phrase is \"put X from Y into Z\". X is the game object, Y is where it starts and Z is where it ends. Y and Z can be the grave, the deck, the hand or play.",
			},
			{
				"title": "Draw",
				"text": "Draw: put the first card of your deck into your hand.",
			},
			{
				"title": "Timing +X",
				"text": "You can play this card even while you are up to X ahead on the timer.",
			},
			{
				"title": "Timing -X",
				"text": "You can play this card only while you are X or more behind on the timer.",
			},
			{
				"title": "Timing effects",
				"text": "Some effects get stronger or weaker depending on how far ahead or behind you are on the timer.",
			},
			{
				"title": "Cooldowns",
				"text": "Abilities can have a cooldown N. After you use one, put N counters on it. Whenever the timer moves X toward you, remove X counters from it. Once it has no counters left, you can use it again.",
				"alternatives": [
					{
						"title": "Cards played",
						"text": "Abilities can have a cooldown N. After you use one, put N counters on it. Whenever you play a card, remove 1 counter from it. Once it has no counters left, you can use it again.",
					},
				],
			},
		],
	},
	{
		"title": "Combat",
		"rules": [
			{
				"title": "Damage",
				"text": "Battle damage works like magic damage.",
			},
			{
				"title": "Targets",
				"text": "Instead of only hitting the player, the attacker can also choose to attack creatures.",
			},
			{
				"title": "Defending",
				"text": "The defending player can protect a creature by putting something in between.",
			},
		],
	},
]
