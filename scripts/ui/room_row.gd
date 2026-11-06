extends PanelContainer
## One row in the room browser: the room's name, its host and game mode, and on the far right a
## Join button, with a padlock on its left when the room has a password. The browser only lists
## rooms that can be joined, and every game has two players, so a row shows neither a status nor
## a player count.

signal join_requested(room_id: StringName)

var _room_id: StringName

@onready var _name_label: Label = %RoomName
@onready var _host_label: Label = %HostName
@onready var _join_button: Button = %JoinButton
@onready var _lock: LockIcon = %LockIcon


func setup(room: RoomInfo) -> void:
	_room_id = room.id
	_name_label.text = room.room_name
	_host_label.text = "Hosted by %s  ·  %s" % [room.host_name, room.mode_name()]
	_lock.locked = room.has_password()
	_join_button.disabled = not room.is_joinable()


func _on_join_button_pressed() -> void:
	join_requested.emit(_room_id)
