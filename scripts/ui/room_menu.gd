extends Control
## The room a player has opened or joined: who is in it, the deck each of them plays, and a chat
## between the two players. Whatever the game has to tell them (who joined, whether the room is in
## the room list, whether their deck can be played) comes in the chat too, from "Console".
##
## Each player chooses one of their decks that can be played in this room (see DeckCheck), by
## typing to search them. The host's game checks the deck again, and only then can the player press
## Ready; their box turns green for both players to see. When both are ready, the game starts. (The
## game itself will take place here.)
##
## The back arrow (or Escape) leaves the room and goes back to the room list; if the host leaves,
## the room closes and leaves the list.

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
## What the room screen last said about readiness and the room list, so nothing is said twice.
var _was_ready := false
var _was_opponent_ready := false
var _unready_asked := false
var _last_listing_note := ""

@onready var _title_label: Label = %TitleLabel
@onready var _info_label: Label = %InfoLabel
@onready var _you_panel: PanelContainer = %YouPanel
@onready var _you_label: Label = %YouLabel
@onready var _opponent_panel: PanelContainer = %OpponentPanel
@onready var _opponent_label: Label = %OpponentLabel
@onready var _deck_edit: LineEdit = %DeckEdit
@onready var _ready_button: Button = %ReadyButton
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
		if deck != null and DeckCheck.problems(deck, _cards, points_list, online.room.custom_cards, _official).is_empty():
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
	_show_opponent()
	_console("%s joined." % who)
	_show_ready()


func _on_opponent_left() -> void:
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
