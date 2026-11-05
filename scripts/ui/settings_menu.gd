extends Control
## Settings, shown on top of whichever screen opened it (see SettingsButton). The back arrow, or
## Escape, closes it and leaves that screen as it was.


@onready var _back_button: Button = %BackButton
@onready var _fullscreen_check: CheckButton = %FullscreenCheck


func _ready() -> void:
	_fullscreen_check.button_pressed = _is_fullscreen()
	_fullscreen_check.toggled.connect(_set_fullscreen)
	_back_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	queue_free()


func _is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _set_fullscreen(fullscreen: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
