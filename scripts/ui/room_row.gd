extends PanelContainer
## One row in the room browser.

signal join_requested(room_id: StringName)

const STATUS_OPEN := Color(0.5, 0.82, 0.55)
const STATUS_FULL := Color(0.85, 0.5, 0.45)
const STATUS_IN_GAME := Color(0.62, 0.64, 0.74)

var _room_id: StringName

@onready var _name_label: Label = %RoomName
@onready var _host_label: Label = %HostName
@onready var _players_label: Label = %Players
@onready var _status_label: Label = %Status
@onready var _join_button: Button = %JoinButton


func setup(room: RoomInfo) -> void:
	_room_id = room.id
	_name_label.text = room.room_name
	_host_label.text = "Hosted by %s" % room.host_name
	_players_label.text = "%d / %d" % [room.players, room.max_players]
	if room.in_game:
		_set_status("In game", STATUS_IN_GAME)
	elif room.is_full():
		_set_status("Full", STATUS_FULL)
	else:
		_set_status("Open", STATUS_OPEN)
	_join_button.disabled = not room.is_joinable()


func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


func _on_join_button_pressed() -> void:
	join_requested.emit(_room_id)
