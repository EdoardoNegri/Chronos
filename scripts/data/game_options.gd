class_name GameOptions
extends RefCounted
## The values of the rules that a local room lets its host change, to try them out. The defaults are
## the rulebook's (see GameRules: the opening hand, the mulligan, the forced draw, the starting
## timer and who starts), including the ones that are not decided yet. A game reads them from
## Lobby.game_options when it starts; an ordinary room always plays with the defaults.

## Who acts first when the timer is at 0. "Automatic" is rule 2.1 (by points; a coin toss if tied).
enum Starter { AUTOMATIC, PLAYER_1, PLAYER_2 }

const STARTER_NAMES: Array[String] = ["Automatic", "Player 1", "Player 2"]

const DEFAULT_HAND_SIZE := 7
const DEFAULT_MULLIGAN_COST := 5
const DEFAULT_FORCED_DRAW_COST := 100
const DEFAULT_STARTING_TIMER := 0

const MAX_HAND_SIZE := 30
const MAX_MULLIGAN_COST := 100
const MAX_FORCED_DRAW_COST := 1000
## The timer starts anywhere from this far toward Player 2 to this far toward Player 1.
const MAX_STARTING_TIMER := 1000

## Cards each player draws at the start.
var hand_size := DEFAULT_HAND_SIZE:
	set(value):
		hand_size = clampi(value, 0, MAX_HAND_SIZE)
## How far each card replaced in the mulligan moves the starting timer toward the player.
var mulligan_cost := DEFAULT_MULLIGAN_COST:
	set(value):
		mulligan_cost = clampi(value, 0, MAX_MULLIGAN_COST)
## What drawing a card by paying time costs: the timer moves this far toward the player.
var forced_draw_cost := DEFAULT_FORCED_DRAW_COST:
	set(value):
		forced_draw_cost = clampi(value, 0, MAX_FORCED_DRAW_COST)
## Where the shared timer starts: positive is toward Player 1 (they are ahead), negative toward
## Player 2, 0 is even.
var starting_timer := DEFAULT_STARTING_TIMER:
	set(value):
		starting_timer = clampi(value, -MAX_STARTING_TIMER, MAX_STARTING_TIMER)
var starter := Starter.AUTOMATIC


## Whether every value is the rulebook's.
func is_default() -> bool:
	return to_dict() == GameOptions.new().to_dict()


## Back to the rulebook's values.
func reset() -> void:
	hand_size = DEFAULT_HAND_SIZE
	mulligan_cost = DEFAULT_MULLIGAN_COST
	forced_draw_cost = DEFAULT_FORCED_DRAW_COST
	starting_timer = DEFAULT_STARTING_TIMER
	starter = Starter.AUTOMATIC


func to_dict() -> Dictionary:
	return {
		"hand_size": hand_size,
		"mulligan_cost": mulligan_cost,
		"forced_draw_cost": forced_draw_cost,
		"starting_timer": starting_timer,
		"starter": starter,
	}


## Options from a dictionary as to_dict gives it. What is missing is the default, and what is out of
## range is brought into it.
static func from_dict(data: Dictionary) -> GameOptions:
	var options := GameOptions.new()
	options.hand_size = int(data.get("hand_size", DEFAULT_HAND_SIZE))
	options.mulligan_cost = int(data.get("mulligan_cost", DEFAULT_MULLIGAN_COST))
	options.forced_draw_cost = int(data.get("forced_draw_cost", DEFAULT_FORCED_DRAW_COST))
	options.starting_timer = int(data.get("starting_timer", DEFAULT_STARTING_TIMER))
	var chosen := int(data.get("starter", Starter.AUTOMATIC))
	options.starter = chosen if chosen >= 0 and chosen < STARTER_NAMES.size() else Starter.AUTOMATIC
	return options
