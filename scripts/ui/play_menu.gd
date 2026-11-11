extends Control
## Online play: the list of open rooms, hosting a room, and joining one. Games are between two
## players.
##
## Hosting runs the room on the host's own computer and puts it in the room list (see Lobby and
## RoomBoard). The list is read when the screen opens, on Refresh (the circular arrow at the top
## right of the list), and every so often while it is open. The filters are in the top row, with
## nothing to open: the search field, the cards allowed and the password. The list follows them as
## they change. Joining connects straight to the host's game, at the address the list gives; a
## room whose host cannot be reached is taken off the list. The first time the player comes here
## they are asked for a name (see PlayerProfile), which is all the account there is. A room can
## have a password, which the host sets and a player joining has to type. Once a room is opened or
## joined, the room screen takes over.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const ROOM_SCENE := "res://scenes/room.tscn"
const STATUS_COLOR := Color(0.62, 0.64, 0.74)
const ERROR_COLOR := Color(0.9, 0.5, 0.45)
const SUCCESS_COLOR := Color(0.5, 0.82, 0.55)
## How often the list is read again while the screen is open.
const REFRESH_SECONDS := 30.0
## The first choice of each filter: no limit. The cards filter goes on with the game modes, the
## password filter with these (in the order of RoomDirectory.Password).
const ANY_FILTER := "Any"
const PASSWORD_FILTERS: Array[String] = [ANY_FILTER, "Locked", "Unlocked"]

@export var room_row_scene: PackedScene

## Who the player is online. The Profile autoload, unless a test gives another.
var profile: PlayerProfile = Profile
## The connection to the lobby server. The Online autoload, unless a test gives another.
var online: Lobby = Online
## Whether the screen reads the room list and connects to hosts by itself, and really goes to the
## room screen once a room is opened or joined. (Tests turn these off.)
var auto_connect := true
var change_scenes := true

## The room being joined.
var _joining_id: StringName
var _joining_name := ""
## The listed room being joined (see RoomBoard.entry_for; {} if none), and whether the connection
## to its host has started.
var _target: Dictionary = {}
var _target_started := false
var _refresh_timer: Timer

@onready var _content: Control = %Content
@onready var _search_edit: LineEdit = %SearchEdit
@onready var _cards_option: OptionButton = %CardsOption
@onready var _password_option: OptionButton = %PasswordOption
@onready var _refresh_button: Button = %RefreshButton
@onready var _host_button: Button = %HostButton
@onready var _host_gap: Control = %HostGap
@onready var _back_button: Button = %BackButton
@onready var _scroll: ScrollContainer = %Scroll
@onready var _room_list: VBoxContainer = %RoomList
@onready var _empty_label: Label = %EmptyLabel
@onready var _status: Label = %Status
@onready var _host_overlay: Control = %HostOverlay
@onready var _room_name_edit: LineEdit = %RoomNameEdit
@onready var _password_edit: LineEdit = %PasswordEdit
@onready var _game_mode_option: OptionButton = %GameModeOption
@onready var _form_error: Label = %FormError
@onready var _create_button: Button = %CreateButton
@onready var _cancel_button: Button = %CancelButton
@onready var _join_overlay: Control = %JoinOverlay
@onready var _join_room_label: Label = %JoinRoomLabel
@onready var _join_password_edit: LineEdit = %JoinPasswordEdit
@onready var _join_error: Label = %JoinError
@onready var _confirm_join_button: Button = %ConfirmJoinButton
@onready var _cancel_join_button: Button = %CancelJoinButton
@onready var _account_overlay: Control = %AccountOverlay
@onready var _account_name_edit: LineEdit = %AccountNameEdit
@onready var _account_error: Label = %AccountError
@onready var _account_continue_button: Button = %AccountContinueButton


func _ready() -> void:
	for mode in RoomInfo.MODES:
		_game_mode_option.add_item(mode)
	_cards_option.add_item(ANY_FILTER)
	for mode in RoomInfo.MODES:
		_cards_option.add_item(mode)
	for choice in PASSWORD_FILTERS:
		_password_option.add_item(choice)
	_align_host_button()
	_back_button.pressed.connect(_go_back)
	_search_edit.text_changed.connect(_on_search_changed)
	_search_edit.gui_input.connect(SearchText.pair_quotes.bind(_search_edit))
	_cards_option.item_selected.connect(_on_filter_selected)
	_password_option.item_selected.connect(_on_filter_selected)
	_refresh_button.pressed.connect(_refresh)
	_host_button.pressed.connect(_open_host_dialog)
	_create_button.pressed.connect(_create_room)
	_cancel_button.pressed.connect(_close_overlay.bind(_host_overlay))
	_room_name_edit.text_submitted.connect(func(_text: String) -> void: _create_room())
	_room_name_edit.text_changed.connect(func(_text: String) -> void: _form_error.text = "")
	_password_edit.text_submitted.connect(func(_text: String) -> void: _create_room())
	_confirm_join_button.pressed.connect(_confirm_join)
	_cancel_join_button.pressed.connect(_cancel_join)
	_join_password_edit.text_submitted.connect(func(_text: String) -> void: _confirm_join())
	_join_password_edit.text_changed.connect(func(_text: String) -> void: _join_error.text = "")
	_account_continue_button.pressed.connect(_create_account)
	_account_name_edit.text_submitted.connect(func(_text: String) -> void: _create_account())
	_account_name_edit.text_changed.connect(func(_text: String) -> void: _account_error.text = "")
	online.state_changed.connect(_on_state_changed)
	online.board.rooms_changed.connect(_rebuild_list)
	online.board.failed.connect(_rebuild_list)
	online.hosted.connect(_on_hosted)
	online.host_failed.connect(_on_host_failed)
	online.joined.connect(_on_joined)
	online.join_failed.connect(_on_join_failed)
	if not online.notice.is_empty():
		_show_status(online.notice, STATUS_COLOR)
		online.notice = ""
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_SECONDS
	_refresh_timer.timeout.connect(_refresh)
	add_child(_refresh_timer)
	_rebuild_list()
	if profile.has_account():
		_search_edit.grab_focus()
		_go_online()
	else:
		_open_overlay(_account_overlay, _account_name_edit)


## Escape closes the dialog that is open. Without a name the player cannot be online, so Escape on
## the name dialog leaves for the main menu.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _host_overlay.visible:
		_close_overlay(_host_overlay)
	elif _join_overlay.visible:
		_cancel_join()
	else:
		_go_back()


## The Host Room button starts level with the line the titles over the other fields sit on, and
## ends with the fields.
func _align_host_button() -> void:
	var title := _search_edit.get_parent().get_child(0) as Label
	_host_gap.custom_minimum_size.y = roundf(title.get_theme_font("font").get_ascent(title.get_theme_font_size("font_size")))


func _go_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_search_changed(_text: String) -> void:
	_rebuild_list()


# --- Filters -------------------------------------------------------------------------------


func _on_filter_selected(_index: int) -> void:
	_rebuild_list()


## The game mode the list is limited to (one of RoomInfo.MODES), or empty for any.
func _wanted_mode() -> String:
	return "" if _cards_option.selected <= 0 else RoomInfo.MODES[_cards_option.selected - 1]


func _wanted_password() -> RoomDirectory.Password:
	return _password_option.selected as RoomDirectory.Password


## How many filters narrow the list now: the search text, the cards allowed, the password.
func _active_filters() -> int:
	var count := 0
	if not _search_edit.text.strip_edges().is_empty():
		count += 1
	if _cards_option.selected > 0:
		count += 1
	if _password_option.selected > 0:
		count += 1
	return count


# --- The room list -------------------------------------------------------------------------


## Reads the list now and keeps reading it every so often.
func _go_online() -> void:
	_refresh()
	if auto_connect:
		_refresh_timer.start()


## Reads the room list again.
func _refresh() -> void:
	if auto_connect:
		# The list is rebuilt when the answer comes (rooms_changed, failed).
		@warning_ignore("missing_await")
		online.board.refresh()
	_rebuild_list()


func _rebuild_list() -> void:
	# Once a room is opened this screen is on its way out (out of the tree, freed soon), but the
	# list may still change. Rows made here would never be set up.
	if not is_inside_tree():
		return
	for row in _room_list.get_children():
		row.queue_free()
	var query := _search_edit.text.strip_edges()
	var rooms := online.board.rooms.get_rooms(_search_edit.text, true, _wanted_mode(), _wanted_password())
	for room in rooms:
		var row: Node = room_row_scene.instantiate()
		_room_list.add_child(row)
		row.setup(room)
		row.join_requested.connect(_join_room)
	var has_rooms := not rooms.is_empty()
	_scroll.visible = has_rooms
	_empty_label.visible = not has_rooms
	if not has_rooms:
		_empty_label.text = _empty_text(query)


## What the list says when there is nothing in it: that there are no rooms (also when the game has
## no GitHub token to read the list with), that it is being read, or why it could not be read.
func _empty_text(query: String) -> String:
	var board := online.board
	if not board.is_set_up():
		return "No rooms found"
	if board.refreshing and board.rooms.get_room_count() == 0:
		return "Looking for rooms…"
	if not board.error_text.is_empty():
		return "%s\nPress Refresh to try again." % board.error_text
	if _active_filters() == 1 and not query.is_empty():
		return "No open rooms match “%s”." % query
	if _active_filters() > 0:
		return "No open rooms match these filters."
	return "No open rooms right now. Host one!"


# --- Joining -------------------------------------------------------------------------------


## Joins a room from the list: connects to its host's game, then asks for the password if the room
## has one (see _join_target_room).
func _join_room(room_id: StringName) -> void:
	var entry := online.board.entry_for(room_id)
	if entry.is_empty():
		_show_status("That room is closed.", ERROR_COLOR)
		_refresh()
		return
	_target = entry
	_target_started = false
	_joining_id = StringName(entry["room_id"])
	_joining_name = entry["room_name"]
	_show_status("Joining “%s”…" % _joining_name, STATUS_COLOR)
	var address := Lobby.normalize_url(entry["address"])
	if online.state == Lobby.State.CONNECTED and online.server_url == address and online.player_name == profile.player_name:
		_join_target_room()
		return
	if auto_connect:
		online.connect_to_server(address, profile.player_name)


## The connection changed: a room being joined moves on.
func _on_state_changed() -> void:
	if _target.is_empty():
		return
	match online.state:
		Lobby.State.CONNECTING:
			_target_started = true
		Lobby.State.CONNECTED:
			_join_target_room()
		Lobby.State.OFFLINE:
			if _target_started:
				_host_unreachable()


## Connected to the host: asks for the password if the room has one, otherwise joins at once.
func _join_target_room() -> void:
	if _target.get("locked", false):
		_join_room_label.text = "“%s” has a password." % _joining_name
		_join_password_edit.text = ""
		_join_error.text = ""
		_open_overlay(_join_overlay, _join_password_edit)
		return
	online.join_room(_joining_id, "")


## The host's game could not be reached: the room is taken off the list, since its host is gone
## (unless it can only be reached on its host's network, which this computer may not be on).
func _host_unreachable() -> void:
	var entry := _target
	_target = {}
	_close_overlay(_join_overlay)
	if entry.get("local", false):
		_show_status("Could not reach “%s”. It can only be joined from its host's network." % _joining_name, ERROR_COLOR)
		return
	_show_status("Could not reach “%s”. Its host is gone, so it was taken off the list." % _joining_name, ERROR_COLOR)
	@warning_ignore("missing_await")
	_take_off_list(entry)


func _take_off_list(entry: Dictionary) -> void:
	await online.board.remove(int(entry.get("issue", 0)))
	_rebuild_list()


func _confirm_join() -> void:
	online.join_room(_joining_id, _join_password_edit.text)


func _on_joined(_room: RoomInfo) -> void:
	_target = {}
	_close_overlay(_join_overlay)
	_go_to_room()


## Cancelling the password question gives up on the room, and leaves its host's game.
func _cancel_join() -> void:
	_close_overlay(_join_overlay)
	if not _target.is_empty():
		_target = {}
		online.disconnect_from_server()
		_show_status("", STATUS_COLOR)


## A wrong password keeps the dialog open to try again; anything else closes it and says why.
func _on_join_failed(error: int) -> void:
	if error == ERR_UNAUTHORIZED and _join_overlay.visible:
		_join_error.text = "That is not the password."
		_join_password_edit.select_all()
		return
	_close_overlay(_join_overlay)
	var entry := _target
	_target = {}
	match error:
		ERR_BUSY:
			_show_status("“%s” is full or already in a game." % _joining_name, ERROR_COLOR)
		ERR_ALREADY_IN_USE:
			_show_status("You are already in a room.", ERROR_COLOR)
		ERR_CONNECTION_ERROR:
			_show_status("Could not reach “%s”." % _joining_name, ERROR_COLOR)
		_:
			# The host's game is there, but the room is not: it should not be in the list.
			_show_status("That room is closed.", ERROR_COLOR)
			if not entry.is_empty():
				@warning_ignore("missing_await")
				_take_off_list(entry)
	# Nothing more to do in the host's game.
	online.disconnect_from_server()


# --- Name ----------------------------------------------------------------------------------


## Saves the name typed in the first-time dialog and carries on to the rooms.
func _create_account() -> void:
	var error := profile.set_player_name(_account_name_edit.text)
	if not error.is_empty():
		_account_error.text = error
		return
	_close_overlay(_account_overlay)
	_show_status("Welcome, %s. You can change your name in Settings." % profile.player_name, SUCCESS_COLOR)
	_go_online()


# --- Hosting -------------------------------------------------------------------------------


func _open_host_dialog() -> void:
	_room_name_edit.text = "%s's room" % profile.player_name
	_password_edit.text = ""
	_game_mode_option.select(0)
	_form_error.text = ""
	_create_button.disabled = false
	_open_overlay(_host_overlay, _room_name_edit)
	_room_name_edit.select_all()


func _create_room() -> void:
	var error := RoomDirectory.check_room_name(_room_name_edit.text)
	if not error.is_empty():
		_form_error.text = error
		return
	var custom_cards := _game_mode_option.get_item_text(_game_mode_option.selected) == RoomInfo.MODE_CUSTOM
	# The room runs on this computer; hosted or host_failed comes back at once.
	_create_button.disabled = true
	online.host_here(profile.player_name, _room_name_edit.text.strip_edges(), custom_cards, _password_edit.text)


func _on_hosted(_room: RoomInfo) -> void:
	_close_overlay(_host_overlay)
	_go_to_room()


func _on_host_failed(message: String) -> void:
	_create_button.disabled = false
	_form_error.text = message


func _go_to_room() -> void:
	if change_scenes:
		get_tree().change_scene_to_file(ROOM_SCENE)


# --- Dialogs -------------------------------------------------------------------------------


## Shows a dialog over the screen and puts the caret in `field`.
func _open_overlay(overlay: Control, field: LineEdit) -> void:
	# Block keyboard focus from wandering behind the dialog while it is up.
	_content.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	overlay.visible = true
	overlay.modulate.a = 0.0
	create_tween().tween_property(overlay, "modulate:a", 1.0, 0.15)
	field.grab_focus()


func _close_overlay(overlay: Control) -> void:
	overlay.visible = false
	_content.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	_search_edit.grab_focus()


## Says something under the room list. The line only takes space while it says something, so the
## list reaches the bottom of the screen otherwise.
func _show_status(text: String, color: Color) -> void:
	_status.text = text
	_status.visible = not text.is_empty()
	_status.add_theme_color_override("font_color", color)
