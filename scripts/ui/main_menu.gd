extends Control
## Main menu. Each button navigates to its scene once that scene exists.

const HOVER_SCALE := Vector2(1.04, 1.04)
const ENTRANCE_DELAY := 0.06

## Button node name -> destination scene. Missing scenes are skipped until they are created.
const DESTINATIONS := {
	&"PlayButton": "res://scenes/play.tscn",
	&"DecksButton": "res://scenes/decks.tscn",
	&"DatabaseButton": "res://scenes/database.tscn",
	&"CreateCardsButton": "res://scenes/create_cards.tscn",
	&"RulesButton": "res://scenes/rules.tscn",
	&"SettingsButton": "res://scenes/settings.tscn",
}

var _hover_tweens: Dictionary[Button, Tween] = {}

@onready var _title: Label = %Title
@onready var _buttons: VBoxContainer = %Buttons


func _ready() -> void:
	for button: Button in _buttons.get_children():
		button.pressed.connect(_on_button_pressed.bind(button))
		button.mouse_entered.connect(_set_highlight.bind(button, true))
		button.mouse_exited.connect(_set_highlight.bind(button, false))
		button.focus_entered.connect(_set_highlight.bind(button, true))
		button.focus_exited.connect(_set_highlight.bind(button, false))
		button.resized.connect(_center_pivot.bind(button))
		_center_pivot(button)
	_play_entrance()


func _on_button_pressed(button: Button) -> void:
	var path: String = DESTINATIONS.get(button.name, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		print("'%s' is not implemented yet (%s)" % [button.text, path])
		return
	get_tree().change_scene_to_file(path)


func _center_pivot(button: Button) -> void:
	button.pivot_offset = button.size * 0.5


func _set_highlight(button: Button, active: bool) -> void:
	# Keep the highlight when the button is focused, e.g. by keyboard, even if the mouse leaves.
	var highlighted := active or button.has_focus()
	if _hover_tweens.has(button):
		_hover_tweens[button].kill()
	var tween := create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", HOVER_SCALE if highlighted else Vector2.ONE, 0.15)
	_hover_tweens[button] = tween


func _play_entrance() -> void:
	var items: Array[Control] = [_title]
	for button: Button in _buttons.get_children():
		items.append(button)
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in items.size():
		var item := items[i]
		item.modulate.a = 0.0
		tween.tween_property(item, "modulate:a", 1.0, 0.5).set_delay(i * ENTRANCE_DELAY)
