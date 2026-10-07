extends Control
## Room browser: search online rooms, join one, or host a new one.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const STATUS_COLOR := Color(0.62, 0.64, 0.74)
const ERROR_COLOR := Color(0.9, 0.5, 0.45)
const SUCCESS_COLOR := Color(0.5, 0.82, 0.55)

@export var room_row_scene: PackedScene

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
@onready var _max_players_spin: SpinBox = %MaxPlayersSpin
@onready var _form_error: Label = %FormError
@onready var _create_button: Button = %CreateButton
@onready var _cancel_button: Button = %CancelButton


func _ready() -> void:
	_back_button.pressed.connect(_go_back)
	_search_edit.text_changed.connect(_on_search_changed)
	_refresh_button.pressed.connect(Rooms.refresh)
	_host_button.pressed.connect(_open_host_dialog)
	_create_button.pressed.connect(_create_room)
	_cancel_button.pressed.connect(_close_host_dialog)
	_room_name_edit.text_submitted.connect(func(_text: String) -> void: _create_room())
	_room_name_edit.text_changed.connect(func(_text: String) -> void: _form_error.text = "")
	Rooms.rooms_changed.connect(_rebuild_list)
	_rebuild_list()
	_search_edit.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _host_overlay.visible:
		_close_host_dialog()
	else:
		_go_back()


func _go_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_search_changed(_text: String) -> void:
	_rebuild_list()


func _rebuild_list() -> void:
	for row in _room_list.get_children():
		row.queue_free()
	var query := _search_edit.text.strip_edges()
	var rooms := Rooms.get_rooms(query)
	for room in rooms:
		var row: Node = room_row_scene.instantiate()
		_room_list.add_child(row)
		row.setup(room)
		row.join_requested.connect(_join_room)
	var has_rooms := not rooms.is_empty()
	_scroll.visible = has_rooms
	_empty_label.visible = not has_rooms
	if not has_rooms:
		_empty_label.text = (
			"No rooms match “%s”." % query if not query.is_empty()
			else "No rooms online yet. Host one!"
		)
	_show_status(_count_text(rooms.size(), query), STATUS_COLOR)


func _count_text(shown: int, query: String) -> String:
	var total := Rooms.get_room_count()
	if query.is_empty():
		return "%d %s online" % [total, "room" if total == 1 else "rooms"]
	return "Showing %d of %d rooms" % [shown, total]


func _join_room(room_id: StringName) -> void:
	var room_name := _find_room_name(room_id)
	match Rooms.join_room(room_id):
		OK:
			# The lobby screen does not exist yet, so stay here and confirm.
			_show_status("Joined “%s”." % room_name, SUCCESS_COLOR)
		ERR_BUSY:
			_show_status("“%s” is full or already in a game." % room_name, ERROR_COLOR)
		_:
			_show_status("That room no longer exists.", ERROR_COLOR)
			Rooms.refresh()


func _find_room_name(room_id: StringName) -> String:
	for room in Rooms.get_rooms():
		if room.id == room_id:
			return room.room_name
	return "room"


func _open_host_dialog() -> void:
	_room_name_edit.text = "%s's room" % Rooms.player_name
	_max_players_spin.value = RoomDirectory.MIN_PLAYERS
	_form_error.text = ""
	_set_dialog_open(true)
	_room_name_edit.grab_focus()
	_room_name_edit.select_all()


func _close_host_dialog() -> void:
	_set_dialog_open(false)
	_host_button.grab_focus()


func _set_dialog_open(open: bool) -> void:
	# Block keyboard focus from wandering behind the dialog while it is up.
	_content.focus_behavior_recursive = (
		Control.FOCUS_BEHAVIOR_DISABLED if open else Control.FOCUS_BEHAVIOR_INHERITED
	)
	_host_overlay.visible = open
	if open:
		_host_overlay.modulate.a = 0.0
		create_tween().tween_property(_host_overlay, "modulate:a", 1.0, 0.15)


func _create_room() -> void:
	var error := Rooms.validate_room_name(_room_name_edit.text)
	if not error.is_empty():
		_form_error.text = error
		return
	var room := Rooms.host_room(_room_name_edit.text, int(_max_players_spin.value))
	if room == null:
		_form_error.text = "Could not create the room."
		return
	_search_edit.text = ""
	_set_dialog_open(false)
	_rebuild_list()
	_show_status("Hosting “%s”. Waiting for players." % room.room_name, SUCCESS_COLOR)


func _show_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
