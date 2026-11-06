extends Control
## Settings, shown on top of whichever screen opened it (see SettingsButton). The back arrow, or
## Escape, closes it and leaves that screen as it was.

const SUCCESS_COLOR := Color(0.5, 0.82, 0.55)
const ERROR_COLOR := Color(0.9, 0.5, 0.45)

## Who the player is online. The Profile autoload, unless a test gives another.
var profile: PlayerProfile = Profile

@onready var _back_button: Button = %BackButton
@onready var _fullscreen_check: CheckButton = %FullscreenCheck
@onready var _name_edit: LineEdit = %NameEdit
@onready var _name_status: Label = %NameStatus
@onready var _server_edit: LineEdit = %ServerEdit
@onready var _server_status: Label = %ServerStatus


func _ready() -> void:
	_server_edit.text = profile.server_url
	_server_edit.text_submitted.connect(func(_text: String) -> void: _apply_server())
	_server_edit.focus_exited.connect(_apply_server)
	_server_edit.text_changed.connect(func(_text: String) -> void: _server_status.text = "")
	_fullscreen_check.button_pressed = _is_fullscreen()
	_fullscreen_check.toggled.connect(_set_fullscreen)
	_name_edit.text = profile.player_name
	_name_edit.text_submitted.connect(func(_text: String) -> void: _apply_name())
	_name_edit.focus_exited.connect(_apply_name)
	_name_edit.text_changed.connect(func(_text: String) -> void: _name_status.text = "")
	_back_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	# A name or address typed but not confirmed with Enter still counts.
	_apply_name()
	_apply_server()
	queue_free()


## Saves the server address typed in the field (empty goes back to this computer). The game
## connects to it the next time the room list is opened or refreshed.
func _apply_server() -> void:
	var typed := _server_edit.text.strip_edges()
	if typed == profile.server_url:
		return
	var error := profile.set_server_url(typed)
	_server_edit.text = profile.server_url
	if error.is_empty():
		_show_server_status("Saved. Press Refresh in Play to connect.", SUCCESS_COLOR)
	else:
		_show_server_status(error, ERROR_COLOR)


func _show_server_status(text: String, color: Color) -> void:
	_server_status.text = text
	_server_status.add_theme_color_override("font_color", color)


## Saves the name typed in the field. A name that cannot be used (empty, or too long) is not
## saved and the field goes back to the name that is.
func _apply_name() -> void:
	var typed := _name_edit.text.strip_edges()
	if typed == profile.player_name or (typed.is_empty() and not profile.has_account()):
		return
	var error := profile.set_player_name(typed)
	_name_edit.text = profile.player_name
	if error.is_empty():
		_show_name_status("Saved.", SUCCESS_COLOR)
	else:
		_show_name_status(error, ERROR_COLOR)


func _show_name_status(text: String, color: Color) -> void:
	_name_status.text = text
	_name_status.add_theme_color_override("font_color", color)


func _is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _set_fullscreen(fullscreen: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
