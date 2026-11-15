extends Control
## The board a game is played on, opened from the room once the game starts. What it shows comes
## from the host (Lobby.game_view, see GameState.view_for); the host also decides what may be done.
##
## The table fills the screen, seen at a slant as in MTG Arena (see TableView): the player's side
## near, a big box where their cards are played with their graveyard and deck beside it on the
## right; the opponent's side further away, turned around. Decks and graveyards are stacks as thick
## as the cards in them.
##
## On the line between the two sides is a band with the back arrow and the player's name (Player 1
## in a local room) at the left, the shared timer in the middle and the opponent's name (Player 2)
## at the right. The timer's number is how much time the player who acts has: green on the
## player's turn, red on the opponent's; an arrow beside it points at the name of whoever's turn
## it is.
##
## The hands are tucked away at the edges of the screen, the player's at the bottom and the
## opponent's at the top, face down: only a strip of each card shows until the mouse is over it,
## and then it comes up (see HandView). Playing alone there is no opponent's side at all: the band
## moves to the top of the screen and the player's side fills the rest.
##
## Clicking the deck on the player's turn draws a card for the time the rules say (rule 3.4);
## running out of cards loses. The graveyards are vortexes that hide what is in them: clicking one
## opens it over the board to look inside (see GraveViewer), either player's. Dragging a card from the hand and letting go of it anywhere on the
## player's field plays it for its time cost (rule 3.2); a spell goes to the graveyard.
##
## In a local room where the player controls both players, the board does not turn around: Player 1
## stays near, and Player 2's hand at the top is face up. On Player 2's turn, their deck draws and
## their hand plays onto their side of the table.
##
## The back arrow leaves the game and the room, and goes back to the room list.

const PLAY_SCENE := "res://scenes/play.tscn"
## How big a card is in the player's hand, and in the opponent's at the top: as in MTG Arena, a
## card in hand is about a tenth of the screen wide, half again as big as one on the field.
const HAND_CARD_SIZE := Vector2(114, 160)
const TOP_HAND_CARD_SIZE := Vector2(72, 100)
## How much of a tucked card shows, in each hand.
const HAND_SHOWN := 52.0
const TOP_HAND_SHOWN := 36.0
const BOTTOM := TableView.BOTTOM
const TOP := TableView.TOP
## Where cards dragged from each hand come from (CardThumb.source), as the fields know them.
const HAND_SOURCE := &"hand"
const TOP_HAND_SOURCE := &"top_hand"
const GREEN := Color(0.3, 0.8, 0.42)
const RED := Color(0.88, 0.3, 0.3)
const MUTED := Color(0.62, 0.64, 0.74)
const TurnArrow := preload("res://scripts/game/turn_arrow.gd")

## The connection to the room's host. The Online autoload, unless a test gives another.
var online: Lobby = Online
## Whether leaving really goes to the room list (a test turns it off).
var change_scenes := true
## Where the cards of the hand come from (tests give their own).
var catalog := CardCatalog.new(CardLibrary.new(CardLibrary.OFFICIAL_DIRECTORY), CardLibrary.new())

## Every card the player has (id -> CardData), and the pictures shown so far (id -> texture).
var _cards: Dictionary = {}
var _textures: Dictionary = {}
## The opponent left, so the game cannot go on.
var _opponent_gone := false
## The graveyard opened to look inside, and whose it is (a side of the table, -1 while closed).
var _grave_viewer: GraveViewer
var _viewer_side := -1

@onready var _time_label: Label = %TimeLabel
@onready var _opponent_label: Label = %OpponentLabel
@onready var _player_label: Label = %PlayerLabel
@onready var _left_arrow: TurnArrow = %LeftTurnArrow
@onready var _right_arrow: TurnArrow = %RightTurnArrow
@onready var _table: TableView = %Table
@onready var _band: Control = %MiddleBand
@onready var _hand: HandView = %Hand
@onready var _top_hand: HandView = %OpponentHand
@onready var _message_label: Label = %MessageLabel
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(_leave)
	_table.hand_sources = [HAND_SOURCE, TOP_HAND_SOURCE]
	_table.deck_pressed.connect(func(_side: int) -> void: draw_card())
	_table.card_dropped.connect(func(_side: int, card_id: String) -> void: play_card(card_id))
	_table.laid_out.connect(_place_band)
	_table.grave_pressed.connect(open_grave)
	_grave_viewer = GraveViewer.new()
	add_child(_grave_viewer)
	_hand.card_size = HAND_CARD_SIZE
	_hand.tucked_shown = HAND_SHOWN
	_hand.drop_target = _table
	_top_hand.card_size = TOP_HAND_CARD_SIZE
	_top_hand.tucked_shown = TOP_HAND_SHOWN
	_top_hand.from_top = true
	_top_hand.drop_target = _table
	if online.room == null:
		_leave.call_deferred()
		return
	online.game_view_changed.connect(_show)
	online.opponent_left.connect(_on_opponent_left)
	online.room_closed.connect(_go_to_play)
	online.state_changed.connect(_on_state_changed)
	_cards = CardCatalog.by_id(catalog.load_cards(false))
	_show()


## Draws a card for the player who acts, if the board lets them.
func draw_card() -> void:
	var seat := _acting_seat()
	if seat != 0 and _table.deck_enabled[_side_of(seat)]:
		online.draw_card(seat)


## Plays a card from the hand of the player who acts onto their field, if the board lets them.
func play_card(card_id: String) -> void:
	var seat := _acting_seat()
	if seat != 0 and _table.accepts_drops[_side_of(seat)]:
		online.play_card(card_id, seat)


## Who the lobby acts for now: me on my turn, the second player of my local room on theirs, or 0
## when nobody I control acts.
func _acting_seat() -> int:
	if online.game_view.get("your_turn", false):
		return Lobby.SERVER_ID
	if online.controls_both and online.second_game_view.get("your_turn", false):
		return LobbyHost.SECOND_SEAT
	return 0


## The side of the table of a seat the lobby acts for.
static func _side_of(seat: int) -> int:
	return BOTTOM if seat == Lobby.SERVER_ID else TOP


func _leave() -> void:
	online.leave_room()
	_go_to_play()


func _go_to_play() -> void:
	if change_scenes:
		get_tree().change_scene_to_file(PLAY_SCENE)


func _on_opponent_left() -> void:
	_opponent_gone = true
	_show()


## If the connection to the host goes, so does the game.
func _on_state_changed() -> void:
	if online.state != Lobby.State.CONNECTED:
		online.notice = online.error_text if not online.error_text.is_empty() else "Lost the connection to the server."
		_go_to_play()


# --- Showing the game ----------------------------------------------------------------------


func _show() -> void:
	var view := online.game_view
	if view.is_empty():
		_time_label.text = ""
		_left_arrow.shown = false
		_right_arrow.shown = false
		_table.deck_enabled = [false, false]
		_table.accepts_drops = [false, false]
		return
	var both := online.controls_both and not online.second_game_view.is_empty()
	var time_ahead := int(view["time_ahead"])
	var my_turn: bool = view["your_turn"]
	var over := not str(view["result"]).is_empty() or _opponent_gone
	var their_turn := both and not over and bool(online.second_game_view["your_turn"])

	_time_label.text = str(absi(time_ahead))
	_time_label.add_theme_color_override("font_color", GREEN if my_turn else RED)
	_time_label.tooltip_text = _standing(time_ahead)
	# The arrow points at whoever's turn it is: the player at the left, the opponent at the right.
	_left_arrow.color = GREEN
	_right_arrow.color = RED
	_left_arrow.shown = not over and my_turn
	_right_arrow.shown = not over and not my_turn
	var alone := not bool(view["opponent_seated"])
	_message_label.text = _message(view)
	_message_label.visible = not _message_label.text.is_empty()

	# The table. Alone, there is only the player's side, under the band at the top.
	var names: Dictionary = view.get("card_names", {})
	var two_players := not alone
	_table.deck_clickable = [true, both]
	_table.deck_enabled = [not over and my_turn, their_turn]
	_table.accepts_drops = [not over and my_turn, their_turn]
	_table.top_visible = two_players
	_place_band()
	_table.show_side(BOTTOM, _entries(view["field"], {}), _entries(view["grave"], {}), int(view["deck_count"]))
	_table.show_side(TOP, _entries(view["opponent_field"], names), _entries(view["opponent_grave"], names), int(view["opponent_deck_count"]))

	# The hands.
	_show_hand(view["hand"])
	_player_label.text = _name_of(view, true) if online.controls_both else profile_name()
	# Alone, the opponent's name is left out but its place kept, so the timer stays in the middle.
	_opponent_label.text = _name_of(view, false) if two_players else ""
	_top_hand.visible = two_players
	if both:
		_show_top_hand(online.second_game_view["hand"])
	else:
		_show_top_hand_backs(int(view["opponent_hand_count"]))
	# An open graveyard shows what is in it now.
	if _grave_viewer.is_open():
		open_grave(_viewer_side)


## Opens a side's graveyard over the board, to see the cards in it.
func open_grave(side: int) -> void:
	var view := online.game_view
	if view.is_empty():
		return
	_viewer_side = side
	var mine := side == BOTTOM
	var ids: Array = view["grave"] if mine else view["opponent_grave"]
	var names: Dictionary = {} if mine else view.get("card_names", {})
	var whose := "Your graveyard" if mine and not online.controls_both else "%s's graveyard" % _name_of(view, mine)
	var cards: Array[Control] = []
	for entry: Array in _entries(ids, names):
		var thumb := CardThumb.new()
		thumb.source = &"grave"
		thumb.setup(entry[0], entry[1], entry[2])
		cards.append(thumb)
	_grave_viewer.open("%s  ·  %s" % [whose, PileBadge.count_text(ids.size())], cards)


## The band on the line between the two sides of the table (see TableView.band_center), or at the
## top of the screen when there is only one side.
func _place_band() -> void:
	var top := _table.band_center() - TableView.MIDDLE_BAND * 0.5
	_band.anchor_top = 0.0
	_band.anchor_bottom = 0.0
	_band.offset_top = top
	_band.offset_bottom = top + TableView.MIDDLE_BAND
	_band.grow_vertical = Control.GROW_DIRECTION_END


## The name the player goes by in the room.
func profile_name() -> String:
	return online.player_name if not online.player_name.is_empty() else "You"


## How the timer stands for the player, in words.
static func _standing(time_ahead: int) -> String:
	if time_ahead == 0:
		return "Even"
	return "%d %s" % [absi(time_ahead), "ahead" if time_ahead > 0 else "behind"]


## The name of the player at the bottom (`me`) or of their opponent.
func _name_of(view: Dictionary, me: bool) -> String:
	var seat := int(view["seat"])
	if not me:
		seat = GameState.other(seat)
	if online.controls_both:
		return "Player %d" % (seat + 1)
	if me:
		return "You"
	return online.opponent_name if not online.opponent_name.is_empty() else "Opponent"


## What is said in the middle of the board once the game is over ("" while it is on).
func _message(view: Dictionary) -> String:
	var result := str(view["result"])
	if result.is_empty():
		return "%s left the game." % _name_of(view, false) if _opponent_gone else ""
	var won := result == "won"
	if online.controls_both:
		var winner := _name_of(view, won)
		var loser := _name_of(view, not won)
		return "%s wins!\n%s's deck ran out." % [winner, loser]
	if won:
		return "You win!\n%s's deck ran out." % _name_of(view, false)
	return "You lose.\nYour deck ran out."


## The player's hand.
func _show_hand(hand: Array) -> void:
	_hand.show_cards(_hand_cards(hand, HAND_SOURCE, "your side of the table"))


## The hand of the second player I control, face up, at the top.
func _show_top_hand(hand: Array) -> void:
	_top_hand.show_cards(_hand_cards(hand, TOP_HAND_SOURCE, "their side of the table"))


## The opponent's hand at the top, face down.
func _show_top_hand_backs(count: int) -> void:
	var backs: Array[Control] = []
	for i in count:
		var holder := Control.new()
		holder.custom_minimum_size = TOP_HAND_CARD_SIZE
		holder.mouse_filter = Control.MOUSE_FILTER_PASS
		var back := CardBack.new()
		back.scale = Vector2.ONE * (TOP_HAND_CARD_SIZE.x / CardBack.CARD_SIZE.x)
		holder.add_child(back)
		backs.append(holder)
	_top_hand.show_cards(backs)


func _hand_cards(hand: Array, source: StringName, field: String) -> Array[Control]:
	var thumbs: Array[Control] = []
	for entry: Array in _entries(hand, {}):
		var thumb := CardThumb.new()
		thumb.source = source
		thumb.setup(entry[0], entry[1], entry[2])
		thumb.tooltip_text = "%s: drag it onto %s to play it" % [entry[1], field]
		thumbs.append(thumb)
	return thumbs


## Cards to show, each as [id, name, picture or null]. A card the player does not have is named
## from `names` (what the host told), or "Unknown card".
func _entries(card_ids: Array, names: Dictionary) -> Array:
	var entries := []
	for card_id: Variant in card_ids:
		var id := str(card_id)
		var card: CardData = _cards.get(id)
		var card_name: String = card.card_name if card != null else str(names.get(id, "Unknown card"))
		entries.append([id, card_name, _texture(id) if card != null else null])
	return entries


func _texture(card_id: String) -> Texture2D:
	if not _textures.has(card_id):
		var face := catalog.load_face(card_id)
		if face != null:
			face.generate_mipmaps()
		_textures[card_id] = ImageTexture.create_from_image(face) if face != null else null
	return _textures[card_id]
