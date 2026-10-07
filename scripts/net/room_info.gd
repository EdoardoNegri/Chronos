class_name RoomInfo
extends RefCounted
## A joinable room as shown in the room browser.

var id: StringName
var room_name: String
var host_name: String
var players: int
var max_players: int
var in_game: bool


func _init(
	p_id: StringName,
	p_room_name: String,
	p_host_name: String,
	p_players: int,
	p_max_players: int,
	p_in_game := false
) -> void:
	id = p_id
	room_name = p_room_name
	host_name = p_host_name
	players = p_players
	max_players = p_max_players
	in_game = p_in_game


func is_full() -> bool:
	return players >= max_players


func is_joinable() -> bool:
	return not is_full() and not in_game
