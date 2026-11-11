extends GutTest


## The text of a rule of the rulebook, found by its title.
func _rule_text(rule_title: String) -> String:
	for section: Dictionary in GameRules.SECTIONS:
		for rule: Dictionary in section["rules"]:
			if rule["title"] == rule_title:
				return rule["text"]
	return ""


func test_the_defaults_are_what_the_rulebook_says() -> void:
	var options := GameOptions.new()
	assert_true(options.is_default())
	assert_string_contains(_rule_text("Opening hand"), "draw %d cards" % options.hand_size)
	assert_string_contains(_rule_text("Mulligan"), "timer %d" % options.mulligan_cost)
	assert_string_contains(_rule_text("Forced draw"), "pay %d time" % options.forced_draw_cost)
	assert_string_contains(_rule_text("Starting timer"), "starts at %d" % options.starting_timer)
	assert_eq(options.starter, GameOptions.Starter.AUTOMATIC, "who starts is decided by points, as rule 2.1 says")


func test_values_are_kept_within_their_ranges() -> void:
	var options := GameOptions.new()
	options.hand_size = 500
	options.mulligan_cost = -3
	options.forced_draw_cost = 99999
	options.starting_timer = -99999
	assert_eq(options.hand_size, GameOptions.MAX_HAND_SIZE)
	assert_eq(options.mulligan_cost, 0)
	assert_eq(options.forced_draw_cost, GameOptions.MAX_FORCED_DRAW_COST)
	assert_eq(options.starting_timer, -GameOptions.MAX_STARTING_TIMER, "the timer can start toward Player 2")
	options.starting_timer = 40
	assert_eq(options.starting_timer, 40, "or toward Player 1")


func test_changed_options_are_not_default_until_reset() -> void:
	var options := GameOptions.new()
	options.hand_size = 6
	options.starter = GameOptions.Starter.PLAYER_2
	assert_false(options.is_default())
	options.reset()
	assert_true(options.is_default())
	assert_eq(options.hand_size, GameOptions.DEFAULT_HAND_SIZE)
	assert_eq(options.starter, GameOptions.Starter.AUTOMATIC)


func test_options_travel_as_a_dictionary_and_a_bad_one_gives_the_defaults() -> void:
	var options := GameOptions.new()
	options.hand_size = 8
	options.mulligan_cost = 10
	options.forced_draw_cost = 50
	options.starting_timer = -20
	options.starter = GameOptions.Starter.PLAYER_1
	var back := GameOptions.from_dict(options.to_dict())
	assert_eq(back.to_dict(), options.to_dict())

	assert_true(GameOptions.from_dict({}).is_default(), "what is missing is the default")
	var odd := GameOptions.from_dict({"hand_size": 1000, "starter": 17})
	assert_eq(odd.hand_size, GameOptions.MAX_HAND_SIZE, "out of range is brought in")
	assert_eq(odd.starter, GameOptions.Starter.AUTOMATIC, "and an unknown starter is Automatic")
