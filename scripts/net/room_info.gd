class_name RoomInfo
extends RefCounted
## A joinable room as shown in the room browser.

## Standard games use the official cards only. Custom cards games also allow the cards players
## created or imported.
const MODE_STANDARD := "Standard"
const MODE_CUSTOM := "Custom cards"
const MODES: Array[String] = [MODE_STANDARD, MODE_CUSTOM]

var id: StringName
var room_name: String
var host_name: String
var players: int
var max_players: int
var in_game: bool
var custom_cards: bool
## Whether the room has a password. This is all a player browsing rooms ever learns about it.
var locked: bool
## What the room's password hashes to, or empty. Only the server that checks the password has it,
## and the password itself is never kept.
var password_hash: String


func _init(
	p_id: StringName,
	p_room_name: String,
	p_host_name: String,
	p_players: int,
	p_max_players: int,
	p_in_game := false,
	p_custom_cards := false,
	p_password := ""
) -> void:
	id = p_id
	room_name = p_room_name
	host_name = p_host_name
	players = p_players
	max_players = p_max_players
	in_game = p_in_game
	custom_cards = p_custom_cards
	password_hash = hash_password(p_password)
	locked = not password_hash.is_empty()


## The room as it is sent to players: everything but the password hash.
func to_dict() -> Dictionary:
	return {
		"id": str(id),
		"room_name": room_name,
		"host_name": host_name,
		"players": players,
		"max_players": max_players,
		"in_game": in_game,
		"custom_cards": custom_cards,
		"locked": locked,
	}


static func from_dict(data: Dictionary) -> RoomInfo:
	var room := RoomInfo.new(
		StringName(str(data.get("id", ""))),
		str(data.get("room_name", "")),
		str(data.get("host_name", "")),
		int(data.get("players", 0)),
		int(data.get("max_players", 2)),
		bool(data.get("in_game", false)),
		bool(data.get("custom_cards", false))
	)
	room.locked = bool(data.get("locked", false))
	return room


func mode_name() -> String:
	return MODE_CUSTOM if custom_cards else MODE_STANDARD


func has_password() -> bool:
	return locked


## Whether `password` lets a player in: any password for an open room, the right one otherwise.
## Only the server knows the hash, so only it can say yes to a locked room.
func accepts(password: String) -> bool:
	if not locked:
		return true
	return not password_hash.is_empty() and hash_password(password) == password_hash


static func hash_password(password: String) -> String:
	return "" if password.is_empty() else password.sha256_text()


func is_full() -> bool:
	return players >= max_players


func is_joinable() -> bool:
	return not is_full() and not in_game
