extends Control
## The room a player has opened or joined: who is in it, the deck each of them plays, and a chat
## between the two players. Whatever the game has to tell them (who joined, whether the room is in
## the room list, whether their deck can be played) comes in the chat too, from "Console".
##
## Each player chooses one of their decks that can be played in this room (see DeckCheck), by
## typing to search them. The host's game checks the deck again, and only then can the player press
## Ready, at the right of the title; their box turns green for both players to see. When both are ready, the game starts. (The
## game itself will take place here.)
##
## The back arrow (or Escape) leaves the room and goes back to the room list; if the host leaves,
## the room closes and leaves the list.
##
## A local room (see RoomInfo) is the player's alone, so it has no chat, no names of players and no
## Ready: just the title with a Start button at its right, and a deck field for each player. Any deck
## can be chosen, a deck that is not finished too. With one deck chosen the player controls one
## player; with two they control both. Below the decks are the options: values of the rules to try
## out (see GameOptions), such as the cards in the opening hand. Start starts the game.

const PLAY_SCENE := "res://scenes/play.tscn"
const GOLD := "f2cc73"
const MUTED := "9ea3bd"
## Messages from the game itself are written by "Console", in this colour.
const CONSOLE_NAME := "Console"
const CONSOLE_COLOR := "ffe14d"
## A ready player's box.
const READY_COLOR := Color(0.13, 0.36, 0.2)
const READY_BORDER := Color(0.42, 0.85, 0.52)

## Who the player is online. The Profile autoload, unless a test gives another.
var profile: PlayerProfile = Profile
## The connection to the lobby server. The Online autoload, unless a test gives another.
var online: Lobby = Online
## Whether leaving really goes to the room list (a test turns it off).
var change_scenes := true
## Where the player's decks and cards come from, and what cards cost (tests give their own).
var decks := DeckLibrary.new()
var catalog := CardCatalog.new(CardLibrary.new(CardLibrary.OFFICIAL_DIRECTORY), CardLibrary.new())
var points_list := PointsList.new()

var _opponent := ""
## Every card the player has (id -> CardData), and the ids of the official ones.
var _cards: Dictionary = {}
var _official: Dictionary = {}
## The names of the player's decks that can be played in this room, sorted.
var _allowed: Array[String] = []
## The deck sent to the host to be checked ("" if none is chosen).
var _chosen := ""
var _deck_suggestions: WordSuggestions
## In a local room: the deck chosen for the second player ("" if none), and its field's suggestions.
var _chosen_second := ""
var _second_suggestions: WordSuggestions
## What the room screen last said about readiness and the room list, so nothing is said twice.
var _was_ready := false
var _was_opponent_ready := false
var _unready_asked := false
var _last_listing_note := ""

@onready var _title_label: Label = %TitleLabel
@onready var _start_button: Button = %StartButton
@onready var _info_label: Label = %InfoLabel
@onready var _players_row: Control = %PlayersRow
@onready var _chat_panel: Control = %ChatPanel
@onready var _you_panel: PanelContainer = %YouPanel
@onready var _you_label: Label = %YouLabel
@onready var _opponent_panel: PanelContainer = %OpponentPanel
@onready var _opponent_label: Label = %OpponentLabel
@onready var _deck_edit: LineEdit = %DeckEdit
@onready var _ready_button: Button = %ReadyButton
@onready var _second_row: Control = %SecondDeckRow
@onready var _second_edit: LineEdit = %SecondDeckEdit
@onready var _options_panel: Control = %OptionsPanel
@onready var _hand_stepper: NumberStepper = %HandStepper
@onready var _mulligan_stepper: NumberStepper = %MulliganStepper
@onready var _draw_stepper: NumberStepper = %DrawStepper
@onready var _timer_stepper: NumberStepper = %TimerStepper
@onready var _starter_option: OptionButton = %StarterOption
@onready var _defaults_button: Button = %DefaultsButton
@onready var _chat_log: RichTextLabel = %ChatLog
@onready var _chat_edit: LineEdit = %ChatEdit
@onready var _send_button: Button = %SendButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(_leave)
	_send_button.pressed.connect(_send)
	_chat_edit.text_submitted.connect(func(_text: String) -> void: _send())
	if online.room == null:
		# Nothing to show: the room is gone.
		_leave.call_deferred()
		return
	online.opponent_joined.connect(_on_opponent_joined)
	online.opponent_left.connect(_on_opponent_left)
	online.room_closed.connect(_on_room_closed)
	online.chat_received.connect(_on_chat_received)
	online.state_changed.connect(_on_state_changed)
	online.listing_changed.connect(_say_listing)
	online.deck_checked.connect(_on_deck_checked)
	online.ready_changed.connect(_on_ready_changed)
	online.game_started.connect(_on_game_started)
	_ready_button.pressed.connect(_toggle_ready)
	_deck_edit.text_submitted.connect(_choose_deck)
	_deck_edit.text_changed.connect(_on_deck_text_changed)
	_deck_suggestions = WordSuggestions.new()
	_deck_suggestions.whole_text = true
	_deck_suggestions.attach(_deck_edit, self, func() -> Array[String]: return _allowed)
	_deck_suggestions.accepted.connect(_choose_deck)

	var room := online.room
	_title_label.text = room.room_name
	if room.local_room:
		_setup_local_room()
		_load_decks()
		_show_ready()
		_deck_edit.grab_focus()
		return
	var info := "Hosted by %s  ·  %s" % [room.host_name, room.mode_name()]
	if room.has_password():
		info += "  ·  Password"
	_info_label.text = info
	_you_label.text = "You: %s" % profile.player_name
	_opponent = online.opponent_name
	_show_opponent()
	if _opponent.is_empty():
		_console("Waiting for another player to join.")
	else:
		_console("You joined %s." % room.room_name)
	_say_listing()
	_load_decks()
	if _allowed.is_empty():
		var which := "official cards only" if not room.custom_cards else "official and custom cards"
		_console("You have no deck that can be played in this room (%s, at least %d cards, within the point budget). Make one in Decks." % [which, DeckData.MIN_SIZE])
	else:
		_console("Choose your deck, then press Ready.")
	_show_ready()
	_chat_edit.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_leave()


## Leaves the room (it closes if it is the player's own) and goes back to the room list.
func _leave() -> void:
	online.leave_room()
	_go_to_play()


func _go_to_play() -> void:
	if change_scenes:
		get_tree().change_scene_to_file(PLAY_SCENE)


# --- Deck and ready ------------------------------------------------------------------------


## Finds the player's decks that can be played in this room.
func _load_decks() -> void:
	_cards = CardCatalog.by_id(catalog.load_cards(false))
	_official = catalog.official_ids()
	_allowed.clear()
	for deck_name in decks.list_names():
		var deck := decks.load_deck(deck_name)
		if deck == null:
			continue
		# In a local room any deck is fine, one that is not finished too.
		if online.room.local_room or DeckCheck.problems(deck, _cards, points_list, online.room.custom_cards, _official).is_empty():
			_allowed.append(deck_name)


## The allowed deck with this name (whatever its case), or "".
func _allowed_name(typed: String) -> String:
	var wanted := typed.strip_edges().to_lower()
	for deck_name in _allowed:
		if deck_name.to_lower() == wanted:
			return deck_name
	return ""


## Chooses a deck and has the host check it.
func _choose_deck(typed: String) -> void:
	var deck_name := _allowed_name(typed)
	if deck_name.is_empty():
		if not typed.strip_edges().is_empty():
			_console("You have no deck called “%s” that can be played here." % typed.strip_edges())
		return
	if deck_name == _chosen:
		return
	var deck := decks.load_deck(deck_name)
	if deck == null:
		return
	_chosen = deck_name
	_deck_edit.text = deck_name
	_deck_edit.caret_column = deck_name.length()
	_console("Checking “%s”…" % deck_name)
	online.check_deck(deck.to_dict(), DeckCheck.send_cards(deck, _cards, _official))
	_show_ready()


## Typing something else gives up the deck that was chosen.
func _on_deck_text_changed(text: String) -> void:
	if not _chosen.is_empty() and text.strip_edges() != _chosen:
		_chosen = ""
		_show_ready()


func _on_deck_checked(problems: Array) -> void:
	if _chosen.is_empty():
		return
	if problems.is_empty():
		_console("“%s” can be played. Press Ready when you are." % _chosen)
	else:
		var reasons: Array[String] = []
		reasons.assign(problems.map(func(problem: Variant) -> String: return str(problem)))
		_console("“%s” cannot be played: %s." % [_chosen, ", ".join(reasons)])
	_show_ready()


func _toggle_ready() -> void:
	_unready_asked = online.my_ready
	online.set_ready(not online.my_ready)


func _on_ready_changed() -> void:
	if _was_ready and not online.my_ready and not _unready_asked and not online.game_on:
		_console("Press Ready again when you are.")
	if online.opponent_ready != _was_opponent_ready and not _opponent.is_empty():
		_console("%s is %s." % [_opponent, "ready" if online.opponent_ready else "not ready any more"])
	_was_ready = online.my_ready
	_was_opponent_ready = online.opponent_ready
	_unready_asked = false
	_show_ready()


func _on_game_started() -> void:
	_console("Both players are ready. The game starts!")
	_show_ready()


## The Ready button, the deck field and the green boxes, as things stand.
func _show_ready() -> void:
	if online.is_local_room():
		_show_start()
		return
	var can_be_ready := online.deck_approved and not _chosen.is_empty()
	_ready_button.disabled = online.game_on or not (can_be_ready or online.my_ready)
	_ready_button.text = "Not ready" if online.my_ready else "Ready"
	_deck_edit.editable = not online.my_ready and not online.game_on
	_paint_ready(_you_panel, online.my_ready)
	_paint_ready(_opponent_panel, online.opponent_ready and not _opponent.is_empty())


static func _paint_ready(panel: PanelContainer, is_ready: bool) -> void:
	panel.remove_theme_stylebox_override(&"panel")
	if not is_ready:
		return
	var box := panel.get_theme_stylebox(&"panel").duplicate()
	if box is StyleBoxFlat:
		(box as StyleBoxFlat).bg_color = READY_COLOR
		(box as StyleBoxFlat).border_color = READY_BORDER
	panel.add_theme_stylebox_override(&"panel", box)


## Whether the room is in the room list yet (for the host), in the chat.
func _say_listing() -> void:
	var note := online.listing_note
	if online.is_player and not note.is_empty() and note != _last_listing_note:
		_console(note)
	_last_listing_note = note


# --- A local room --------------------------------------------------------------------------


## What a local room shows: the title with its Start button, and a deck field for each player. No
## chat, no names of players, no Ready.
func _setup_local_room() -> void:
	_info_label.visible = false
	_players_row.visible = false
	_chat_panel.visible = false
	_ready_button.visible = false
	_start_button.visible = true
	_second_row.visible = true
	_options_panel.visible = true
	_setup_options()
	_deck_edit.placeholder_text = "Player 1's deck: type to search"
	_start_button.pressed.connect(online.start_local_game)
	_second_edit.text_submitted.connect(_choose_second_deck)
	_second_edit.text_changed.connect(_on_second_deck_text_changed)
	_second_suggestions = WordSuggestions.new()
	_second_suggestions.whole_text = true
	_second_suggestions.attach(_second_edit, self, func() -> Array[String]: return _allowed)
	_second_suggestions.accepted.connect(_choose_second_deck)
	online.second_deck_checked.connect(_on_second_deck_checked)


## The options of the game, which are the ones the room's game will be played with.
func _setup_options() -> void:
	for name in GameOptions.STARTER_NAMES:
		_starter_option.add_item(name)
	_show_options()
	# After the values are shown, so showing them changes nothing.
	_hand_stepper.value_changed.connect(func(value: float) -> void: online.game_options.hand_size = int(value))
	_mulligan_stepper.value_changed.connect(func(value: float) -> void: online.game_options.mulligan_cost = int(value))
	_draw_stepper.value_changed.connect(func(value: float) -> void: online.game_options.forced_draw_cost = int(value))
	_timer_stepper.value_changed.connect(func(value: float) -> void: online.game_options.starting_timer = int(value))
	_starter_option.item_selected.connect(func(index: int) -> void: online.game_options.starter = index as GameOptions.Starter)
	_defaults_button.pressed.connect(_reset_options)


## Shows the game's options in the fields.
func _show_options() -> void:
	var options := online.game_options
	_hand_stepper.value = options.hand_size
	_mulligan_stepper.value = options.mulligan_cost
	_draw_stepper.value = options.forced_draw_cost
	_timer_stepper.value = options.starting_timer
	_starter_option.select(options.starter)


func _reset_options() -> void:
	online.game_options.reset()
	_show_options()


## Chooses a deck for the second player, as _choose_deck does for the first. With a deck for each
## the player controls both players.
func _choose_second_deck(typed: String) -> void:
	var deck_name := _allowed_name(typed)
	if deck_name.is_empty() or deck_name == _chosen_second:
		return
	var deck := decks.load_deck(deck_name)
	if deck == null:
		return
	_chosen_second = deck_name
	_second_edit.text = deck_name
	_second_edit.caret_column = deck_name.length()
	online.control_both_players(true)
	online.check_deck(deck.to_dict(), DeckCheck.send_cards(deck, _cards, _official), LobbyHost.SECOND_SEAT)
	_show_ready()


## Typing something else gives up the second player's deck, and the player controls one player again.
func _on_second_deck_text_changed(text: String) -> void:
	if not _chosen_second.is_empty() and text.strip_edges() != _chosen_second:
		_chosen_second = ""
		online.control_both_players(false)
		_show_ready()


func _on_second_deck_checked(_problems: Array) -> void:
	_show_ready()


## The Start button and the deck fields of a local room, as things stand: Start can be pressed once
## the first player has a deck (and the second, if they have one), until the game has started.
func _show_start() -> void:
	var first_has_deck := online.deck_approved and not _chosen.is_empty()
	var second_is_fine := _chosen_second.is_empty() or online.second_approved
	_start_button.disabled = online.game_on or not (first_has_deck and second_is_fine)
	_deck_edit.editable = not online.game_on
	_second_edit.editable = not online.game_on
	# The options are fixed once the game has started.
	for stepper: NumberStepper in [_hand_stepper, _mulligan_stepper, _draw_stepper, _timer_stepper]:
		stepper.editable = not online.game_on
	_starter_option.disabled = online.game_on
	_defaults_button.disabled = online.game_on


# --- Chat ----------------------------------------------------------------------------------


func _send() -> void:
	var text := _chat_edit.text.strip_edges()
	if text.is_empty():
		return
	_chat_edit.clear()
	if _opponent.is_empty():
		_console("There is nobody to hear that yet.")
		return
	online.send_chat(text)
	_add_chat_line(profile.player_name, text, GOLD)


func _on_opponent_joined(who: String) -> void:
	_opponent = who
	if online.is_local_room():
		_show_ready()
		return
	_show_opponent()
	_console("%s joined." % who)
	_show_ready()


func _on_opponent_left() -> void:
	if online.is_local_room():
		_opponent = ""
		_show_ready()
		return
	_console("%s left the room." % _opponent)
	_opponent = ""
	_was_opponent_ready = false
	_show_opponent()
	_show_ready()


## The host left, so there is no room any more: back to the list, which says so.
func _on_room_closed() -> void:
	_go_to_play()


func _on_chat_received(from_name: String, text: String) -> void:
	_add_chat_line(from_name, text, MUTED)


## If the connection to the server goes, so does the room.
func _on_state_changed() -> void:
	if online.state != Lobby.State.CONNECTED:
		online.notice = online.error_text if not online.error_text.is_empty() else "Lost the connection to the server."
		_go_to_play()


func _show_opponent() -> void:
	_opponent_label.text = "Opponent: %s" % _opponent if not _opponent.is_empty() else "Waiting for another player…"


func _add_chat_line(who: String, text: String, color: String) -> void:
	_chat_log.text += "[color=#%s]%s[/color]: %s\n" % [color, _escape(who), _escape(text)]


## A message from the game itself, in yellow, from "Console".
func _console(text: String) -> void:
	_chat_log.text += "[color=#%s]%s: %s[/color]\n" % [CONSOLE_COLOR, CONSOLE_NAME, _escape(text)]


## Text a player typed must not be read as formatting.
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
