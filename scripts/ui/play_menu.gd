extends Control
## Room browser: search the open online rooms (ones with a free seat), join one, or host a new one.
## Games are between two players.
##
## The rooms come from the lobby server (see Lobby). The first time the player comes here they are
## asked for a name (see PlayerProfile), which is all the account there is. A room can have a
## password, which the host sets and a player joining has to type. Once a room is opened or joined,
## the room screen takes over.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const ROOM_SCENE := "res://scenes/room.tscn"
const STATUS_COLOR := Color(0.62, 0.64, 0.74)
const ERROR_COLOR := Color(0.9, 0.5, 0.45)
const SUCCESS_COLOR := Color(0.5, 0.82, 0.55)

@export var room_row_scene: PackedScene

## Who the player is online. The Profile autoload, unless a test gives another.
var profile: PlayerProfile = Profile
## The connection to the lobby server. The Online autoload, unless a test gives another.
var online: Lobby = Online
## Whether the screen connects to the server by itself, and really goes to the room screen once a
## room is opened or joined. (Tests turn these off.)
var auto_connect := true
var change_scenes := true

## The room the password dialog is asking about.
var _joining_id: StringName
var _joining_name := ""

@onready var _content: Control = %Content
@onready var _search_edit: LineEdit = %SearchEdit
@onready var _refresh_button: Button = %RefreshButton
@onready var _host_button: Button = %HostButton
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
	_back_button.pressed.connect(_go_back)
	_search_edit.text_changed.connect(_on_search_changed)
	_search_edit.gui_input.connect(SearchText.pair_quotes.bind(_search_edit))
	_refresh_button.pressed.connect(_refresh)
	_host_button.pressed.connect(_open_host_dialog)
	_create_button.pressed.connect(_create_room)
	_cancel_button.pressed.connect(_close_overlay.bind(_host_overlay))
	_room_name_edit.text_submitted.connect(func(_text: String) -> void: _create_room())
	_room_name_edit.text_changed.connect(func(_text: String) -> void: _form_error.text = "")
	_password_edit.text_submitted.connect(func(_text: String) -> void: _create_room())
	_confirm_join_button.pressed.connect(_confirm_join)
	_cancel_join_button.pressed.connect(_close_overlay.bind(_join_overlay))
	_join_password_edit.text_submitted.connect(func(_text: String) -> void: _confirm_join())
	_join_password_edit.text_changed.connect(func(_text: String) -> void: _join_error.text = "")
	_account_continue_button.pressed.connect(_create_account)
	_account_name_edit.text_submitted.connect(func(_text: String) -> void: _create_account())
	_account_name_edit.text_changed.connect(func(_text: String) -> void: _account_error.text = "")
	online.state_changed.connect(_rebuild_list)
	online.rooms_changed.connect(_rebuild_list)
	online.hosted.connect(_on_hosted)
	online.host_failed.connect(_on_host_failed)
	online.joined.connect(_on_joined)
	online.join_failed.connect(_on_join_failed)
	if not online.notice.is_empty():
		_show_status(online.notice, STATUS_COLOR)
		online.notice = ""
	_rebuild_list()
	if profile.has_account():
		_search_edit.grab_focus()
		_ensure_connected()
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
		_close_overlay(_join_overlay)
	else:
		_go_back()


func _go_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_search_changed(_text: String) -> void:
	_rebuild_list()


# --- The server ----------------------------------------------------------------------------


## Connects to the server from the settings, unless that is already done (or being done).
func _ensure_connected(force := false) -> void:
	if not auto_connect or not profile.has_account():
		return
	var up_to_date := (
		online.server_url == Lobby.normalize_url(profile.server_url)
		and online.player_name == profile.player_name
	)
	var busy := online.state == Lobby.State.CONNECTED or online.state == Lobby.State.CONNECTING
	if busy and up_to_date and (online.state == Lobby.State.CONNECTED or not force):
		return
	online.connect_to_server(profile.server_url, profile.player_name)


## Refresh asks for the rooms again, or tries to reach the server again if it is not there.
func _refresh() -> void:
	if online.state == Lobby.State.CONNECTED:
		online.refresh()
	else:
		_ensure_connected(true)


func _rebuild_list() -> void:
	for row in _room_list.get_children():
		row.queue_free()
	_host_button.disabled = online.state != Lobby.State.CONNECTED
	var query := _search_edit.text.strip_edges()
	var rooms := online.rooms.get_rooms(_search_edit.text, true)
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


## What the list says when there is nothing in it: why the server is not there, or that there are
## no rooms.
func _empty_text(query: String) -> String:
	match online.state:
		Lobby.State.CONNECTING:
			return "Connecting to the server…"
		Lobby.State.OFFLINE:
			var reason := online.error_text if not online.error_text.is_empty() else "Not connected to a server."
			return "%s\nCheck the server address in Settings, then press Refresh." % reason
	if not query.is_empty():
		return "No open rooms match “%s”." % query
	return "No open rooms right now. Host one!"


# --- Name ----------------------------------------------------------------------------------


## Saves the name typed in the first-time dialog and carries on to the rooms.
func _create_account() -> void:
	var error := profile.set_player_name(_account_name_edit.text)
	if not error.is_empty():
		_account_error.text = error
		return
	_close_overlay(_account_overlay)
	_show_status("Welcome, %s. You can change your name in Settings." % profile.player_name, SUCCESS_COLOR)
	_ensure_connected()


# --- Joining -------------------------------------------------------------------------------


## Joins a room, asking for the password first if it has one.
func _join_room(room_id: StringName) -> void:
	var room := online.rooms.get_room(room_id)
	_joining_id = room_id
	_joining_name = room.room_name if room != null else "room"
	if room != null and room.has_password():
		_join_room_label.text = "“%s” has a password." % room.room_name
		_join_password_edit.text = ""
		_join_error.text = ""
		_open_overlay(_join_overlay, _join_password_edit)
		return
	online.join_room(room_id, "")


func _confirm_join() -> void:
	online.join_room(_joining_id, _join_password_edit.text)


func _on_joined(_room: RoomInfo) -> void:
	_close_overlay(_join_overlay)
	_go_to_room()


## A wrong password keeps the dialog open to try again; anything else closes it and says why.
func _on_join_failed(error: int) -> void:
	if error == ERR_UNAUTHORIZED and _join_overlay.visible:
		_join_error.text = "That is not the password."
		_join_password_edit.select_all()
		return
	_close_overlay(_join_overlay)
	match error:
		ERR_BUSY:
			_show_status("“%s” is full or already in a game." % _joining_name, ERROR_COLOR)
		ERR_ALREADY_IN_USE:
			_show_status("You are already in a room.", ERROR_COLOR)
		ERR_CONNECTION_ERROR:
			_show_status("You are not connected to a server.", ERROR_COLOR)
		_:
			_show_status("That room no longer exists.", ERROR_COLOR)
			_refresh()


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
	# The server answers with hosted or host_failed.
	_create_button.disabled = true
	online.host_room(_room_name_edit.text.strip_edges(), custom_cards, _password_edit.text)


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


func _show_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
