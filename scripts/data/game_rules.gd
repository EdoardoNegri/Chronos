class_name GameRules
extends RefCounted
## The rulebook shown on the Rules screen, in reading order.
## Each section holds numbered sub-rules (1., 1.1, 1.2, ...); the numbers come from the order here.
## Undecided values are marked inline as {note}; the UI shows them in blue and in parentheses.
## A sub-rule can list `alternatives`: other versions under consideration. They keep the number
## of the rule they would replace and are shown in a different color.

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
				"text": "The player with the biggest difference between usable points and points used by their deck starts the game. If it is tied, a coin toss decides.",
			},
			{
				"title": "Starting time",
				"text": "Both players start at time 0, plus any mulligan penalty (see 2.4).",
			},
			{
				"title": "Opening hand",
				"text": "Both players shuffle their deck and draw 7 cards {may change, 6 to 8}. Going first or second makes no difference to the hand: the second player gets no extra card.",
			},
			{
				"title": "Mulligan",
				"text": "Before the game starts, both players secretly and at the same time choose any number of cards from their opening hand to replace. Put the chosen cards aside, draw the same number of new cards, then shuffle the set-aside cards into your deck. Each card replaced adds +5 time {not decided yet} to your starting time. There is only one round of replacing.",
				"alternatives": [
					{
						"title": "Whole-hand mulligan",
						"text": "Before the game starts, both players secretly and at the same time decide whether to mulligan. To mulligan, shuffle your hand into your deck and draw 7 cards again. Each mulligan adds +10 time to your starting time, and you can mulligan as many times as you want.",
					},
					{
						"title": "Coin toss and informed mulligan",
						"text": "Toss a coin. The winner chooses between going first and mulliganing second.
Going first: you mulligan without knowing what the opponent did, and you act first if the times are tied.
Mulliganing second: the opponent decides their mulligan first and tells you how many cards they replaced. You then decide yours, but you can replace at most as many cards as they did, and the opponent acts first if the times are tied.",
					},
				],
			},
		],
	},
	{
		"title": "Time",
		"rules": [
			{
				"title": "Playing a card",
				"text": "When you play a card, its time cost is added to your time: a card costing 15 moves you from 0 to 15.",
			},
			{
				"title": "Who acts",
				"text": "The player with the lowest time acts next. If both are tied, it is the turn of the player who did not act last.",
			},
			{
				"title": "Time difference",
				"text": "Only the difference between the two times matters, so the game tracks a single counter holding that difference.",
			},
			{
				"title": "Free cards with a catch",
				"text": "A card can cost 0 time and still carry a drawback or a punishment. For example, a spell that costs 0 but gives the opponent +10 time.",
			},
			{
				"title": "Forced draw",
				"text": "Since there are no turns, you can pay 100 time {amount not decided yet} to draw a card. If you have no other action available, you must do this. Trying to draw from an empty deck makes you lose.",
			},
			{
				"title": "Time limit",
				"text": "If a player reaches time 10000 {not sure about this rule}, the game ends and the player with the most life wins.",
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
				"text": "You can play this card even if your time is up to X above your opponent's.",
			},
			{
				"title": "Timing -X",
				"text": "You can play this card only if your time is X or more below your opponent's.",
			},
			{
				"title": "Timing effects",
				"text": "Some effects get stronger or weaker depending on the timing between you and your opponent.",
			},
			{
				"title": "Cooldowns",
				"text": "Abilities can have a cooldown N. After you use one, put N counters on it. Whenever your own time increases by X, remove X counters from it. Once it has no counters left, you can use it again.",
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
