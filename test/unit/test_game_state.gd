extends GutTest
## The game as the host keeps it: dealing, the shared timer, who acts, and the forced draw.


func _ids(prefix: String, count: int) -> Array[String]:
	var ids: Array[String] = []
	for i in count:
		ids.append("%s_%d" % [prefix, i])
	return ids


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return rng


func _game(options := GameOptions.new(), starter := 0, first_size := 20, second_size := 20) -> GameState:
	return GameState.create(_ids("a", first_size), _ids("b", second_size), options, starter, _rng())


func test_each_player_draws_the_opening_hand_from_their_own_deck() -> void:
	var game := _game()
	for seat in 2:
		assert_eq(game.hands[seat].size(), GameOptions.DEFAULT_HAND_SIZE)
		assert_eq(game.decks[seat].size(), 20 - GameOptions.DEFAULT_HAND_SIZE)
	assert_true(game.hands[0].all(func(id: String) -> bool: return id.begins_with("a_")))
	assert_true(game.hands[1].all(func(id: String) -> bool: return id.begins_with("b_")))


func test_the_decks_are_shuffled() -> void:
	var game := _game()
	var order: Array = game.hands[0] + game.decks[0]
	assert_ne(order, _ids("a", 20) as Array)
	order.sort()
	var sorted := _ids("a", 20)
	sorted.sort()
	assert_eq(order, sorted as Array, "the same cards")


func test_the_starter_acts_first_at_zero() -> void:
	assert_eq(_game(GameOptions.new(), 0).actor(), 0)
	assert_eq(_game(GameOptions.new(), 1).actor(), 1)


func test_the_player_who_is_behind_acts() -> void:
	var options := GameOptions.new()
	options.starting_timer = 30
	var game := _game(options)
	assert_eq(game.time_ahead(0), 30, "Player 1 is ahead")
	assert_eq(game.time_ahead(1), -30)
	assert_eq(game.actor(), 1, "so Player 2 acts")


func test_a_forced_draw_moves_the_timer_toward_the_player_and_draws() -> void:
	var options := GameOptions.new()
	options.forced_draw_cost = 40
	var game := _game(options, 0)
	assert_false(game.forced_draw(1), "only the player who acts can draw")
	assert_true(game.forced_draw(0))
	assert_eq(game.timer, 40, "Player 1 is 40 ahead")
	assert_eq(game.hands[0].size(), GameOptions.DEFAULT_HAND_SIZE + 1)
	assert_eq(game.actor(), 1, "now Player 2 acts")
	assert_true(game.forced_draw(1))
	assert_eq(game.timer, 0, "even again")
	assert_eq(game.actor(), 0, "at 0, the player who did not act last acts")


func test_drawing_from_an_empty_deck_loses() -> void:
	var options := GameOptions.new()
	options.hand_size = 2
	var game := _game(options, 0, 2, 20)
	assert_true(game.forced_draw(0))
	assert_true(game.is_over())
	assert_eq(game.winner, 1)
	assert_eq(game.actor(), GameState.NO_WINNER, "nobody acts any more")
	assert_eq(game.view_for(0)["result"], "lost")
	assert_eq(game.view_for(1)["result"], "won")


func test_alone_the_player_acts_every_time() -> void:
	var game := GameState.create(_ids("a", 20), [], GameOptions.new(), 1, _rng(), false)
	assert_eq(game.hands[1].size(), 0)
	assert_eq(game.actor(), 0)
	game.forced_draw(0)
	game.forced_draw(0)
	assert_eq(game.actor(), 0, "even far ahead")
	assert_false(game.view_for(0)["opponent_seated"])


func test_a_view_shows_the_own_hand_and_only_counts_of_the_other() -> void:
	var options := GameOptions.new()
	options.starting_timer = -25
	var game := _game(options)
	var view := game.view_for(1)
	assert_eq(view["seat"], 1)
	assert_eq(view["time_ahead"], 25, "Player 2 is 25 ahead")
	assert_false(view["your_turn"])
	assert_eq(view["hand"], game.hands[1])
	assert_eq(view["opponent_hand_count"], GameOptions.DEFAULT_HAND_SIZE)
	assert_eq(view["opponent_deck_count"], 20 - GameOptions.DEFAULT_HAND_SIZE)
	assert_false(view.has("opponent_hand"), "the other hand stays hidden")
	assert_true(game.view_for(0)["your_turn"])


func test_the_starter_is_who_the_options_say_or_whoever_has_more_points_left() -> void:
	var options := GameOptions.new()
	assert_eq(GameState.pick_starter(options, [3, 10], _rng()), 1)
	assert_eq(GameState.pick_starter(options, [10, 3], _rng()), 0)
	options.starter = GameOptions.Starter.PLAYER_2
	assert_eq(GameState.pick_starter(options, [10, 3], _rng()), 1)
	options.starter = GameOptions.Starter.AUTOMATIC
	var tosses := {}
	var rng := _rng()
	for i in 40:
		tosses[GameState.pick_starter(options, [5, 5], rng)] = true
	assert_eq(tosses.size(), 2, "a tie is a coin toss")


func test_card_ids_lists_every_copy() -> void:
	var deck := DeckData.new()
	deck.add("x")
	deck.add("x")
	deck.add("y")
	assert_eq(GameState.card_ids(deck), ["x", "x", "y"] as Array[String])


func _card(id: String, type: String, time_cost: int) -> CardData:
	var card := CardData.new()
	card.id = id
	card.card_name = id.capitalize()
	card.card_type = type
	card.time_cost = time_cost
	return card


## Player 1 starts with a creature (cost 15) and a spell (cost 10) in a hand of two.
func _game_with_cards() -> GameState:
	var options := GameOptions.new()
	options.hand_size = 2
	var first: Array[String] = ["golem", "zap"]
	var pool := {"golem": _card("golem", "Creature", 15), "zap": _card("zap", "Spell", 10)}
	var pools: Array[Dictionary] = [pool, {}]
	return GameState.create(first, _ids("b", 10), options, 0, _rng(), true, pools)


func test_playing_a_card_spends_its_time_cost() -> void:
	var game := _game_with_cards()
	assert_false(game.play_card(1, "b_0"), "only the player who acts can play")
	assert_false(game.play_card(0, "missing"), "only a card in the hand")
	assert_true(game.play_card(0, "golem"))
	assert_eq(game.timer, 15, "the timer moved toward Player 1 by the cost")
	assert_eq(game.hands[0], ["zap"])
	assert_eq(game.fields[0], ["golem"], "a creature goes onto the field")
	assert_eq(game.actor(), 1)


func test_a_spell_goes_to_the_graveyard() -> void:
	var game := _game_with_cards()
	game.play_card(0, "zap")
	assert_eq(game.timer, 10)
	assert_eq(game.fields[0], [])
	assert_eq(game.graves[0], ["zap"])


func test_the_opponent_sees_the_cards_that_are_out_by_name() -> void:
	var game := _game_with_cards()
	game.play_card(0, "golem")
	var view := game.view_for(1)
	assert_eq(view["opponent_field"][0], "golem")
	assert_eq(view["card_names"], {"golem": "Golem"})
	assert_eq(game.view_for(0)["field"][0], "golem")


func test_there_is_no_limit_to_the_cards_on_a_field() -> void:
	var options := GameOptions.new()
	options.hand_size = 12
	var game := GameState.create(_ids("a", 12), [], options, 0, _rng(), false)
	for i in 12:
		assert_true(game.play_card(0, game.hands[0][0]))
	assert_eq(game.fields[0].size(), 12)
