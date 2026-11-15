extends GutTest
## The board, in a local game: the table filling the screen with its fields, decks and graveyards,
## the band across the middle with the names and the timer, and the tucked-away hands.

const Decks := preload("res://test/helpers/decks.gd")
const FakeGitHub := preload("res://test/helpers/fake_github.gd")
const BOTTOM := TableView.BOTTOM
const TOP := TableView.TOP
const Board := preload("res://scripts/game/board.gd")


## A local game that has started, with both players controlled from here if `both`.
func _local_game(both: bool, options := GameOptions.new()) -> Lobby:
	var lobby := Lobby.new()
	lobby.board = FakeGitHub.new().make_board()
	lobby.find_public_address = false
	add_child_autofree(lobby)
	lobby.host_local("Aeon", "Local Room")
	lobby.game_options = options
	lobby.check_deck(Decks.official_deck().to_dict(), [])
	if both:
		lobby.control_both_players(true)
		lobby.check_deck(Decks.official_deck().to_dict(), [], LobbyHost.SECOND_SEAT)
	lobby.start_local_game()
	return lobby


## The board, laid out in a window the size of the game's (the table needs its size to find things
## on screen).
func _board(lobby: Lobby, with_pictures := false) -> Control:
	var made: Array = await _board_in_window(lobby, with_pictures)
	return made[1]


func _player_1_starts() -> GameOptions:
	var options := GameOptions.new()
	options.starter = GameOptions.Starter.PLAYER_1
	options.forced_draw_cost = 40
	return options


func _table(board: Control) -> TableView:
	return board.get_node("%Table")


## Where a pile of a side is on screen.
func _pile_point(table: TableView, side: int, kind: StringName) -> Vector2:
	return table.screen_point(table.pile_center(side, kind))


## Where a point of a side's field is on screen: its middle, moved by `offset` (table units).
func _field_point(table: TableView, side: int, offset := Vector3.ZERO) -> Vector2:
	return table.screen_point(table.field_center(side) + offset)


func _click(at: Vector2) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = at
	return click


func _hover(at: Vector2) -> InputEventMouseMotion:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	return motion


func _creature_in(hand: Array) -> String:
	var official := CardLibrary.new(CardLibrary.OFFICIAL_DIRECTORY).load_by_id(false)
	for id: String in hand:
		if official[id].card_type == "Creature":
			return id
	return ""


func test_on_your_turn_the_timer_is_green_and_clicking_the_deck_draws() -> void:
	var board: Control = await _board(_local_game(false, _player_1_starts()))
	var table := _table(board)
	var time: Label = board.get_node("%TimeLabel")
	var hand: HandView = board.get_node("%Hand")
	assert_eq(time.text, "0")
	assert_eq(time.get_theme_color("font_color"), Board.GREEN)
	assert_eq(table.deck_count(BOTTOM), 54 - GameOptions.DEFAULT_HAND_SIZE)
	assert_eq(hand.cards().size(), GameOptions.DEFAULT_HAND_SIZE)
	assert_eq(board.get_node("%PlayerLabel").text, "Aeon", "my name, at the left of the timer")
	assert_lt(
		(board.get_node("%PlayerLabel") as Control).get_global_rect().end.x,
		time.get_global_rect().position.x,
		"left of the timer"
	)
	assert_gt(
		(board.get_node("%OpponentLabel") as Control).get_global_rect().position.x,
		time.get_global_rect().end.x,
		"the opponent's right of it"
	)
	assert_true(board.get_node("%LeftTurnArrow").shown, "the arrow points at me: my turn")
	assert_false(board.get_node("%RightTurnArrow").shown)

	table._gui_input(_click(_pile_point(table, BOTTOM, &"deck")))
	assert_eq(time.text, "40", "the draw cost its time")
	assert_eq(time.get_theme_color("font_color"), Board.GREEN, "alone, it is always my turn")
	assert_eq(table.deck_count(BOTTOM), 54 - GameOptions.DEFAULT_HAND_SIZE - 1)
	assert_eq(hand.cards().size(), GameOptions.DEFAULT_HAND_SIZE + 1)

func test_a_pile_shows_how_many_cards_it_holds_only_while_hovered() -> void:
	var board: Control = await _board(_local_game(false, _player_1_starts()))
	var table := _table(board)
	assert_false(table.is_count_shown())
	table._gui_input(_hover(_pile_point(table, BOTTOM, &"deck")))
	assert_true(table.is_count_shown())
	table._gui_input(_hover(_pile_point(table, BOTTOM, &"grave")))
	assert_true(table.is_count_shown(), "the graveyard too")
	table._gui_input(_hover(_field_point(table, BOTTOM)))
	assert_false(table.is_count_shown())


func test_with_both_players_the_board_stays_on_player_1s_side() -> void:
	var lobby := _local_game(true, _player_1_starts())
	var board: Control = await _board(lobby)
	var table := _table(board)
	var time: Label = board.get_node("%TimeLabel")
	assert_eq(time.get_theme_color("font_color"), Board.GREEN, "Player 1's turn")
	assert_eq(board.get_node("%PlayerLabel").text, "Player 1")
	assert_eq(board.get_node("%OpponentLabel").text, "Player 2")
	assert_eq(table.deck_enabled, [true, false] as Array[bool])
	table._gui_input(_click(_pile_point(table, TOP, &"deck")))
	assert_eq(lobby.game_view["time_ahead"], 0, "Player 2's deck waits on Player 1's turn")
	table._gui_input(_click(_pile_point(table, BOTTOM, &"deck")))
	assert_eq(time.get_theme_color("font_color"), Board.RED, "seen from Player 1: Player 2 has the time")
	assert_false(board.get_node("%LeftTurnArrow").shown)
	assert_true(board.get_node("%RightTurnArrow").shown, "the arrow points right, at Player 2")
	assert_eq(time.text, "40")
	assert_eq(table.deck_enabled, [false, true] as Array[bool], "now Player 2's deck, at the far side, draws")
	var their_hand: HandView = board.get_node("%OpponentHand")
	assert_eq(their_hand.cards().size(), GameOptions.DEFAULT_HAND_SIZE)
	assert_true(their_hand.cards()[0] is CardThumb, "Player 2's hand is face up: it is mine to play")
	table._gui_input(_click(_pile_point(table, TOP, &"deck")))
	assert_eq(lobby.second_game_view["time_ahead"], 0, "Player 2 drew for their time")
	assert_eq(their_hand.cards().size(), GameOptions.DEFAULT_HAND_SIZE + 1)
	assert_eq(time.get_theme_color("font_color"), Board.GREEN, "Player 1's turn again")
	assert_true(board.get_node("%LeftTurnArrow").shown, "and left, at Player 1, again")


func test_on_the_opponents_turn_the_timer_is_red_and_their_hand_is_face_down() -> void:
	var options := _player_1_starts()
	options.starter = GameOptions.Starter.PLAYER_2
	options.starting_timer = 30
	var lobby := _local_game(true, options)
	# Only Player 1's side: as a game against someone else shows it.
	lobby.controls_both = false
	var board: Control = await _board(lobby)
	var time: Label = board.get_node("%TimeLabel")
	assert_eq(time.get_theme_color("font_color"), Board.RED, "the opponent has the time")
	assert_eq(time.text, "30")
	var table := _table(board)
	assert_eq(table.deck_enabled, [false, false] as Array[bool])
	assert_false(table.deck_clickable[TOP], "the other player's deck is only shown")
	var their_hand: HandView = board.get_node("%OpponentHand")
	assert_eq(their_hand.cards().size(), GameOptions.DEFAULT_HAND_SIZE)
	assert_false(their_hand.cards()[0] is CardThumb, "only card backs")
	var dragged := {"card_id": lobby.game_view["hand"][0], "from": &"hand"}
	assert_false(table._can_drop_data(_field_point(table, BOTTOM), dragged), "no playing on their turn")


func test_running_out_of_cards_ends_the_game() -> void:
	var options := _player_1_starts()
	options.hand_size = GameOptions.MAX_HAND_SIZE
	var board: Control = await _board(_local_game(false, options))
	var message: Label = board.get_node("%MessageLabel")
	# Alone, the player acts every time: draw the deck empty.
	for i in 54 - GameOptions.MAX_HAND_SIZE:
		board.draw_card()
	assert_eq(_table(board).deck_count(BOTTOM), 0)
	assert_false(message.visible, "an empty deck is fine until a card is drawn from it")
	board.draw_card()
	assert_true(message.visible)
	assert_string_contains(message.text, "You lose")
	assert_false(_table(board).deck_enabled[BOTTOM])


func test_a_big_hand_overlaps_and_scrolls() -> void:
	var options := _player_1_starts()
	options.hand_size = GameOptions.MAX_HAND_SIZE
	var board: Control = await _board(_local_game(false, options))
	var hand: HandView = board.get_node("%Hand")
	var cards := hand.cards()
	assert_lt(cards[1].position.x - cards[0].position.x, cards[0].size.x, "the cards overlap")
	assert_gt(hand.max_scroll(), 0.0, "30 cards do not fit even so")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = hand.get_global_rect().get_center()
	hand._input(wheel)
	assert_gt(hand.scroll_amount(), 0.0, "so the wheel scrolls through them")


func test_the_whole_hand_comes_up_while_the_mouse_is_on_it() -> void:
	var board: Control = await _board(_local_game(false, _player_1_starts()))
	var hand: HandView = board.get_node("%Hand")
	var card := hand.cards()[2]
	assert_false(hand.is_raised())
	for each in hand.cards():
		assert_eq(each.position.y, hand.size.y - hand.tucked_shown, "only a strip of each card shows")
	hand._input(_hover(hand.get_global_transform() * Vector2(card.position.x + 5, hand.size.y - 10)))
	assert_true(hand.is_raised())
	for each in hand.cards():
		assert_eq(each.position.y, hand.size.y - each.size.y, "every card comes up into full view")
	assert_eq(hand.hovered_card(), card)
	assert_eq(card.get_index(), hand.get_child_count() - 1, "the one under the mouse in front")
	var last := hand.cards().back() as Control
	hand._input(_hover(hand.get_global_transform() * Vector2(last.position.x + last.size.x - 5, 10)))
	assert_true(hand.is_raised(), "it stays up while the mouse is on the cards")
	assert_eq(hand.hovered_card(), last)
	hand._input(_hover(hand.get_global_transform() * Vector2(-500, 10)))
	assert_false(hand.is_raised(), "then tucks away again")

func test_hovering_a_card_in_the_hand_shows_it_big_enough_to_read() -> void:
	var board: Control = await _board(_local_game(false, _player_1_starts()), true)
	var hand: HandView = board.get_node("%Hand")
	var card := hand.cards()[2] as CardThumb
	assert_not_null(board.catalog.face_texture(card.card_id))
	assert_null(board.preview_texture())
	hand._input(_hover(hand.get_global_transform() * Vector2(card.position.x + 5, hand.size.y - 10)))
	assert_not_null(board.preview_texture(), "the card under the mouse shows big")
	assert_eq(board.preview_texture(), board.catalog.face_texture(card.card_id))
	var big: Control = board._preview
	assert_gt(big.size.y, card.size.y * 2.0, "much bigger than in the hand")
	assert_almost_eq(big.get_global_rect().end.y, board.size.y, 1.0, "growing out of the bottom of the screen")
	assert_lt(absf(big.get_global_rect().get_center().x - card.get_global_rect().get_center().x), big.size.x * 0.5, "where the card is")
	hand._input(_hover(hand.get_global_transform() * Vector2(-500, 10)))
	assert_null(board.preview_texture(), "and goes away with the mouse")


func test_hovering_a_card_on_the_field_shows_it_big_beside_it() -> void:
	var lobby := _local_game(false, _player_1_starts())
	var board: Control = await _board(lobby, true)
	var table := _table(board)
	var card_id: String = _creature_in(lobby.game_view["hand"])
	if card_id.is_empty():
		pending("no creature in this opening hand")
		return
	board.play_card(card_id)
	assert_eq(table.cards_on(BOTTOM), [card_id] as Array[String])
	table._gui_input(_hover(table.screen_point(table.card_center(BOTTOM, 0))))
	assert_eq(table.hovered_card(), [BOTTOM, 0])
	assert_not_null(board.preview_texture())
	assert_eq(board.preview_texture(), board.catalog.face_texture(card_id), "the card shows big")
	assert_gt((board._preview as Control).size.y, table.card_screen_rect(BOTTOM, 0).size.y * 2.0, "much bigger")
	var big := (board._preview as Control).get_global_rect()
	assert_false(big.intersects(table.card_screen_rect(BOTTOM, 0)), "beside it, not over it")
	assert_true(board.get_viewport_rect().encloses(big), "and on screen")
	table._gui_input(_hover(_field_point(table, BOTTOM, Vector3(0, 0, 1.5))))
	assert_null(board.preview_texture(), "off the card it goes away")


func test_a_card_let_go_over_the_hand_but_above_it_still_reaches_the_field() -> void:
	var lobby := _local_game(false, _player_1_starts())
	var board: Control = await _board(lobby)
	var hand: HandView = board.get_node("%Hand")
	var card_id: String = lobby.game_view["hand"][0]
	var dragged := {"card_id": card_id, "from": &"hand"}
	assert_false(hand._can_drop_data(Vector2(hand.size.x * 0.5, hand.size.y - 10), dragged), "not on the hand itself")
	var above := Vector2(hand.size.x * 0.5, 20)
	assert_true(hand._can_drop_data(above, dragged), "above it, the field is there")
	hand._drop_data(above, dragged)
	assert_eq((lobby.game_view["hand"] as Array).size(), GameOptions.DEFAULT_HAND_SIZE - 1)

func test_a_card_let_go_anywhere_on_your_side_is_played() -> void:
	var lobby := _local_game(true, _player_1_starts())
	var board: Control = await _board(lobby)
	var table := _table(board)
	var official := CardLibrary.new(CardLibrary.OFFICIAL_DIRECTORY).load_by_id(false)
	var card_id: String = _creature_in(lobby.game_view["hand"])
	if card_id.is_empty():
		pending("no creature in this opening hand")
		return
	var dragged := {"card_id": card_id, "from": &"hand"}
	# Near a corner of the field: the slant is taken into account.
	var corner := _field_point(table, BOTTOM, Vector3(table.field_size().x * 0.45, 0, table.field_size().y * 0.4))
	assert_true(table.in_field(BOTTOM, corner))
	assert_false(table._can_drop_data(corner, {"card_id": card_id, "from": &"field"}), "only from a hand")
	assert_false(table._can_drop_data(_field_point(table, TOP), dragged), "not onto the other side")
	var far_corner := table.screen_point(Vector3(-table.half_width() + 0.2, 0, table.half_band() + 0.1))
	assert_true(table.in_field(BOTTOM, far_corner), "the whole side takes cards, not only around the field")
	assert_false(table.in_field(TOP, far_corner))
	assert_true(table.in_field(BOTTOM, _pile_point(table, BOTTOM, &"deck")), "even beside the piles")
	assert_true(table._can_drop_data(corner, dragged))
	table._drop_data(corner, dragged)
	assert_eq(lobby.game_view["field"], [card_id])
	assert_eq(lobby.game_view["time_ahead"], official[card_id].time_cost, "Player 1 spent the card's time")
	assert_eq(table.cards_on(BOTTOM), [card_id] as Array[String], "and it lies on Player 1's field")

	# Player 2 plays from the hand at the top onto the far field.
	var theirs := _creature_in(lobby.second_game_view["hand"])
	if theirs.is_empty() or not lobby.second_game_view["your_turn"]:
		return
	var from_top := {"card_id": theirs, "from": &"top_hand"}
	assert_false(table._can_drop_data(_field_point(table, TOP), dragged), "not from Player 1's hand")
	assert_true(table._can_drop_data(_field_point(table, TOP), from_top))
	table._drop_data(_field_point(table, TOP), from_top)
	assert_eq(table.cards_on(TOP), [theirs] as Array[String])


func test_cards_on_a_field_line_up_by_themselves() -> void:
	var board: Control = await _board(_local_game(false, _player_1_starts()))
	var table := _table(board)
	var cards := func(count: int) -> Array:
		var entries := []
		for i in count:
			entries.append(["card_%d" % i, "Card %d" % i, null])
		return entries
	table.show_side(BOTTOM, cards.call(3), [], 0)
	var first := table.card_center(BOTTOM, 0)
	assert_eq(first.z, table.card_center(BOTTOM, 2).z, "a few cards make one row")
	var middle := (first.x + table.card_center(BOTTOM, 2).x) * 0.5
	assert_almost_eq(middle, table.field_center(BOTTOM).x, 0.001, "in the middle of the field")
	table.show_side(BOTTOM, cards.call(24), [], 0)
	assert_eq(table.card_center(BOTTOM, 0).z, table.card_center(BOTTOM, 23).z, "many still make one row")
	assert_lt(table.card_center(BOTTOM, 1).x - table.card_center(BOTTOM, 0).x, TableView.CARD.x, "overlapping")
	table.show_side(BOTTOM, cards.call(40), [], 0)
	for i in 40:
		var center := table.card_center(BOTTOM, i)
		assert_true(TableView._covers(table.field_center(BOTTOM), table.field_size(), center), "all on the field")
	table.show_side(TOP, cards.call(3), [], 0)
	assert_gt(table.card_center(TOP, 0).x, table.card_center(TOP, 2).x, "the other side runs the other way")

## Plays spells (drawing until there is one, alone the player acts every time) until `count` are in
## the graveyard. Returns them in the order played.
func _play_spells(board: Control, lobby: Lobby, count: int) -> Array:
	var official := CardLibrary.new(CardLibrary.OFFICIAL_DIRECTORY).load_by_id(false)
	var is_spell := func(id: String) -> bool: return official[id].card_type == "Spell"
	var played := []
	while played.size() < count:
		while not (lobby.game_view["hand"] as Array).any(is_spell):
			board.draw_card()
		var spell: String = (lobby.game_view["hand"] as Array).filter(is_spell)[0]
		board.play_card(spell)
		played.append(spell)
	return played


func test_a_spell_shrinks_into_the_graveyards_vortex() -> void:
	var lobby := _local_game(false, _player_1_starts())
	var board: Control = await _board(lobby)
	var table := _table(board)
	_play_spells(board, lobby, 1)
	assert_eq(table.grave_count(BOTTOM), 1)
	assert_eq(table.falling_count(), 1, "the card goes down into the vortex")
	await wait_seconds(TableView.VORTEX_SECONDS * 0.5)
	var falling: Node3D = table._viewport.get_children().back()
	assert_lt(falling.scale.x, 1.0, "getting smaller")
	assert_eq(falling.rotation.y, 0.0, "without turning")
	await wait_seconds(TableView.VORTEX_SECONDS + 0.3)
	assert_eq(table.falling_count(), 0, "and is gone")


func test_the_graveyard_is_above_the_deck() -> void:
	var board: Control = await _board(_local_game(true, _player_1_starts()))
	var table := _table(board)
	var deck := _pile_point(table, BOTTOM, &"deck")
	var grave := _pile_point(table, BOTTOM, &"grave")
	assert_lt(grave.y, deck.y, "my graveyard above my deck")
	assert_eq(table.pile_center(BOTTOM, &"grave").x, table.pile_center(BOTTOM, &"deck").x, "in the same column")
	var their_deck := _pile_point(table, TOP, &"deck")
	var their_grave := _pile_point(table, TOP, &"grave")
	assert_gt(their_grave.y, their_deck.y, "theirs the other way round, toward the middle")


func test_pressing_a_graveyard_shows_whats_inside() -> void:
	var lobby := _local_game(false, _player_1_starts())
	var board: Control = await _board(lobby)
	var table := _table(board)
	var viewer: GraveViewer = board._grave_viewer
	table._gui_input(_click(_pile_point(table, BOTTOM, &"grave")))
	assert_true(viewer.is_open(), "an empty graveyard opens too")
	assert_eq(viewer.shown_cards().size(), 0)
	viewer.close()
	var played := _play_spells(board, lobby, 2)
	assert_false(viewer.is_open(), "nothing shows what is inside until it is pressed")
	table._gui_input(_click(_pile_point(table, BOTTOM, &"grave")))
	assert_true(viewer.is_open())
	assert_string_contains(viewer.title(), "Your graveyard")
	var shown := viewer.shown_cards()
	assert_eq(shown.size(), 2)
	assert_eq((shown[0] as CardThumb).card_id, played[1], "the last that went in first")
	assert_eq((shown[1] as CardThumb).card_id, played[0])
	(viewer.get_node("%CloseButton") if viewer.has_node("%CloseButton") else viewer.find_child("CloseButton", true, false)).pressed.emit()
	assert_false(viewer.is_open(), "Close closes it")


func test_the_graveyard_count_shows_while_hovered() -> void:
	var board: Control = await _board(_local_game(true, _player_1_starts()))
	var table := _table(board)
	table._gui_input(_hover(_pile_point(table, TOP, &"grave")))
	assert_true(table.is_count_shown(), "the other player's too")

func test_alone_you_see_only_your_side() -> void:
	var duel: Control = await _board(_local_game(true, _player_1_starts()))
	var alone: Control = await _board(_local_game(false, _player_1_starts()))
	assert_true(_table(duel).top_visible)
	assert_false(_table(alone).top_visible)
	assert_false(alone.get_node("%OpponentHand").visible)
	assert_true(duel.get_node("%OpponentHand").visible)
	assert_eq(alone.get_node("%OpponentLabel").text, "", "no opponent's name")
	assert_eq(duel.get_node("%OpponentLabel").text, "Player 2")
	var band: Control = alone.get_node("%MiddleBand")
	var screen := alone.get_viewport_rect().size
	assert_eq(band.get_global_rect().position.y, 0.0, "alone, the band is at the top")
	assert_almost_eq(
		(duel.get_node("%MiddleBand") as Control).get_global_rect().get_center().y,
		_table(duel).screen_point(Vector3.ZERO).y,
		1.0,
		"with two, on the line between the sides"
	)
	var table := _table(alone)
	var field_top := table.screen_point(table.field_center(BOTTOM) - Vector3(0, 0, table.field_size().y * 0.5))
	var field_bottom := table.screen_point(table.field_center(BOTTOM) + Vector3(0, 0, table.field_size().y * 0.5))
	assert_between(field_top.y, TableView.MIDDLE_BAND, TableView.MIDDLE_BAND + 25.0, "my field starts under the band")
	assert_between(screen.y - field_bottom.y, TableView.BOTTOM_ROOM, TableView.BOTTOM_ROOM + 45.0, "and reaches the hand")
	var duel_table := _table(duel)
	assert_gt(table.field_size().y, duel_table.field_size().y * 1.8, "so it is about twice as deep as with two")

func test_the_table_fills_the_screen_whatever_its_size() -> void:
	var board: Control = await _board(_local_game(true, _player_1_starts()))
	var table := _table(board)
	for screen: Vector2 in [Vector2(1152, 648), Vector2(1600, 1000)]:
		table.size = screen
		var mine := table.field_center(BOTTOM)
		var half := Vector3(table.field_size().x, 0, table.field_size().y) * 0.5
		var near_left := table.screen_point(mine + Vector3(-half.x, 0, half.z))
		var deck := table.screen_point(table.pile_center(BOTTOM, &"deck") + Vector3(TableView.PILE_CARD.x * 0.5, 0, 0))
		assert_lt(near_left.x, 60.0, "my field reaches the left edge")
		assert_between(screen.y - near_left.y, TableView.BOTTOM_ROOM, TableView.BOTTOM_ROOM + 45.0, "and the hand under it")
		assert_between(deck.x, screen.x - 100.0, screen.x - 15.0, "my deck near the right edge, set in from it")
		var theirs := table.field_center(TOP)
		var far := table.screen_point(theirs - Vector3(0, 0, table.field_size().y * 0.5))
		assert_between(far.y, TableView.TOP_ROOM, TableView.TOP_ROOM + 25.0, "theirs ends under their hand")
		var band := table.band_center()
		assert_lt(table.screen_point(theirs + Vector3(0, 0, half.z)).y, band - TableView.MIDDLE_BAND * 0.5, "above the band")
		assert_gt(table.screen_point(mine - Vector3(0, 0, half.z)).y, band + TableView.MIDDLE_BAND * 0.5, "mine below it")


func test_the_table_is_seen_from_above_with_a_slight_slant() -> void:
	var board: Control = await _board(_local_game(true, _player_1_starts()))
	var table := _table(board)
	var mine := table.field_center(BOTTOM)
	var theirs := table.field_center(TOP)
	var my_width := table.screen_point(mine + Vector3(1, 0, 0)).x - table.screen_point(mine).x
	var their_width := table.screen_point(theirs + Vector3(1, 0, 0)).x - table.screen_point(theirs).x
	assert_between(my_width / their_width, 1.02, 1.15, "the near side looks only a little bigger than the far one")
	var my_depth := table.screen_point(mine + Vector3(0, 0, 1)).y - table.screen_point(mine).y
	assert_between(my_depth / my_width, 0.9, 1.05, "and the table is hardly foreshortened")

## The board in a viewport of its own, which takes mouse events as the game window does.
## The cards have no pictures unless `with_pictures` (the official ones'), so the board opens quickly.
func _board_in_window(lobby: Lobby, with_pictures := false) -> Array:
	var window := SubViewport.new()
	window.size = Vector2i(1152, 648)
	add_child_autofree(window)
	var board: Control = load("res://scenes/board.tscn").instantiate()
	board.online = lobby
	board.change_scenes = false
	if not with_pictures:
		board.catalog = CardCatalog.new(CardLibrary.new("user://test_board_no_cards"), CardLibrary.new("user://test_board_no_cards"))
	window.add_child(board)
	await wait_physics_frames(3)
	return [window, board]


func _move_mouse(window: SubViewport, to: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.global_position = to
	window.push_input(motion)
	await wait_process_frames(1)


func test_moving_the_mouse_onto_the_hand_brings_it_up() -> void:
	var made: Array = await _board_in_window(_local_game(false, _player_1_starts()))
	var window: SubViewport = made[0]
	var hand: HandView = made[1].get_node("%Hand")
	var card := hand.cards()[2]
	await _move_mouse(window, card.get_global_rect().position + Vector2(10, 10))
	assert_true(hand.is_raised(), "a real mouse over the strips brings the hand up")
	for each in hand.cards():
		assert_lt(each.get_global_rect().end.y, 648.5, "all of every card in view")
	await _move_mouse(window, Vector2(576, 200))
	assert_false(hand.is_raised(), "and moving away tucks it again")


func test_the_sizes_are_those_of_mtg_arena() -> void:
	var board: Control = await _board(_local_game(true, _player_1_starts()))
	var table := _table(board)
	var width := board.get_viewport_rect().size.x
	var across := func(at: Vector3) -> float:
		return table.screen_point(at + Vector3(0.5, 0, 0)).x - table.screen_point(at - Vector3(0.5, 0, 0)).x
	var mine: float = across.call(table.field_center(BOTTOM))
	var theirs: float = across.call(table.field_center(TOP))
	assert_between(mine / width, 0.09, 0.115, "a card on my field is about a tenth of the screen wide")
	assert_between(theirs / mine, 0.8, 0.95, "the other side's a little smaller")
	var half := Vector3(table.field_size().x * 0.5, 0, 0)
	var field := table.screen_point(table.field_center(BOTTOM) + half).x - table.screen_point(table.field_center(BOTTOM) - half).x
	assert_gt(field / width, 0.7, "my field is about three quarters of the screen across")
	var hand: HandView = board.get_node("%Hand")
	assert_between(hand.card_size.x / width, 0.09, 0.11, "a card in hand about a tenth")


func test_a_spell_shrinks_from_where_it_was_let_go() -> void:
	var lobby := _local_game(false, _player_1_starts())
	var board: Control = await _board(lobby)
	var table := _table(board)
	var official := CardLibrary.new(CardLibrary.OFFICIAL_DIRECTORY).load_by_id(false)
	var is_spell := func(id: String) -> bool: return official[id].card_type == "Spell"
	while not (lobby.game_view["hand"] as Array).any(is_spell):
		board.draw_card()
	var spell: String = (lobby.game_view["hand"] as Array).filter(is_spell)[0]
	var corner := table.field_center(BOTTOM) - Vector3(table.field_size().x * 0.4, 0, 0)
	var at := table.screen_point(corner)
	var dragged := {"card_id": spell, "from": &"hand"}
	assert_true(table._can_drop_data(at, dragged))
	table._drop_data(at, dragged)
	assert_eq(table.falling_count(), 1)
	var falling: Node3D = table._viewport.get_children().back()
	assert_almost_eq(falling.position.x, corner.x, 0.05, "it starts where it was let go")
	assert_almost_eq(falling.position.z, corner.z, 0.05)
	await wait_seconds(TableView.VORTEX_SECONDS * 0.5)
	var vortex := table.pile_center(BOTTOM, &"grave")
	assert_lt(absf(falling.position.x - vortex.x), absf(corner.x - vortex.x), "and moves to the vortex")
	assert_lt(falling.scale.x, 1.0, "getting smaller")


func test_the_deck_is_a_card_and_sits_at_the_outer_edge_of_its_side() -> void:
	var board: Control = await _board(_local_game(true, _player_1_starts()))
	var table := _table(board)
	var across := func(at: Vector3) -> float:
		return table.screen_point(at + Vector3(0.5, 0, 0)).x - table.screen_point(at - Vector3(0.5, 0, 0)).x
	var deck := table.pile_center(BOTTOM, &"deck")
	assert_between(TableView.PILE_CARD.x / TableView.CARD.x, 0.55, 0.7, "the deck smaller than a card on the field")
	var grave := table.pile_center(BOTTOM, &"grave")
	var screen := board.get_viewport_rect().size
	var deck_bottom := table.screen_point(deck + Vector3(0, 0, TableView.PILE_CARD.y * 0.5)).y
	assert_almost_eq(screen.y - deck_bottom, TableView.BOTTOM_ROOM, 2.0, "my deck down where the hand's strip starts")
	var their_deck := table.pile_center(TOP, &"deck")
	var their_top := table.screen_point(their_deck - Vector3(0, 0, TableView.PILE_CARD.y * 0.5)).y
	assert_almost_eq(their_top, screen.y - deck_bottom, 1.0, "theirs as far from the top")
	var their_left := table.screen_point(their_deck - Vector3(TableView.PILE_CARD.x * 0.5, 0, 0)).x
	var my_right := table.screen_point(deck + Vector3(TableView.PILE_CARD.x * 0.5, 0, 0)).x
	assert_almost_eq(their_left, screen.x - my_right, 1.0, "and from the left as mine from the right")
	var their_grave := table.pile_center(TOP, &"grave")
	assert_eq(their_grave.x, their_deck.x, "their graveyard in the same column")
	assert_gt(their_grave.z, their_deck.z, "toward the middle")
	assert_lt(grave.z, deck.z, "the graveyard above the deck")
	var field_right := table.field_center(BOTTOM).x + table.field_size().x * 0.5
	assert_gt(deck.x - TableView.PILE_CARD.x * 0.5, field_right, "right of my field")
