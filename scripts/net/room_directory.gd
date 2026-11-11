class_name RoomDirectory
extends RefCounted
## A list of rooms and the rules for them: names, two players to a game, passwords, who can join.
##
## The host's game keeps its room in one of these (see LobbyState), and the room list keeps the
## open rooms it last read in another, to show in the room browser (see RoomBoard).

signal rooms_changed

## Which rooms a list asks for by their password (see get_rooms).
enum Password { ANY, LOCKED, UNLOCKED }

## A game is always between two players.
const PLAYERS := 2
const MAX_NAME_LENGTH := 32
const MAX_PASSWORD_LENGTH := 32

## The name given to rooms hosted without a host name.
var player_name := "Player"

var _rooms: Array[RoomInfo] = []
var _next_id := 1


## Rooms whose name and host together hold every word of `query`, read like every search field
## reads it (see SearchText), sorted by name. With `only_open`, rooms that cannot be joined (full,
## or already in a game) are left out. `mode` keeps only the rooms of that game mode (one of
## RoomInfo.MODES; empty for any), and `password` only the locked or only the unlocked ones.
func get_rooms(
	query := "", only_open := false, mode := "", password := Password.ANY
) -> Array[RoomInfo]:
	var wanted := SearchText.needles(query)
	var result: Array[RoomInfo] = []
	for room in _rooms:
		if only_open and not room.is_joinable():
			continue
		if not mode.is_empty() and room.mode_name() != mode:
			continue
		if password == Password.LOCKED and not room.has_password():
			continue
		if password == Password.UNLOCKED and room.has_password():
			continue
		var haystack := ("%s %s" % [room.room_name, room.host_name]).to_lower()
		if SearchText.contains_all(haystack, wanted):
			result.append(room)
	result.sort_custom(_by_name)
	return result


## How many rooms there are, or with `only_open` how many of them can be joined.
func get_room_count(only_open := false) -> int:
	if not only_open:
		return _rooms.size()
	return _rooms.filter(func(room: RoomInfo) -> bool: return room.is_joinable()).size()


## The room with this id, or null.
func get_room(room_id: StringName) -> RoomInfo:
	for room in _rooms:
		if room.id == room_id:
			return room
	return null


## Replaces every room with the ones in a snapshot (rooms as RoomInfo.to_dict gives them).
func replace_from_snapshot(snapshot: Array) -> void:
	_rooms.clear()
	for entry: Variant in snapshot:
		if entry is Dictionary:
			_rooms.append(RoomInfo.from_dict(entry))
	rooms_changed.emit()


## Returns an error message, or an empty string if `room_name` could be a room's name.
static func check_room_name(room_name: String) -> String:
	var trimmed := room_name.strip_edges()
	if trimmed.is_empty():
		return "Give your room a name."
	if trimmed.length() > MAX_NAME_LENGTH:
		return "Room names can be at most %d characters." % MAX_NAME_LENGTH
	return ""


## Returns an error message, or an empty string if `room_name` can be used for a new room.
func validate_room_name(room_name: String) -> String:
	var error := check_room_name(room_name)
	if not error.is_empty():
		return error
	for room in _rooms:
		if room.room_name.to_lower() == room_name.strip_edges().to_lower():
			return "A room with that name already exists."
	return ""


## Creates a room for two players hosted by `host_name` (or `player_name`). `custom_cards` lets its
## games use custom cards too (see RoomInfo), and a `password` (empty for none) is asked of whoever
## joins. A `local_room` is only for its host, who takes both seats (see seat_second_player), and
## takes any card. Returns null if the name or the password is not allowed.
func host_room(
	room_name: String, custom_cards := false, password := "", host_name := "", local_room := false
) -> RoomInfo:
	if not validate_room_name(room_name).is_empty():
		return null
	if password.length() > MAX_PASSWORD_LENGTH:
		return null
	var room := RoomInfo.new(
		_make_id(),
		room_name.strip_edges(),
		host_name if not host_name.is_empty() else player_name,
		1,
		PLAYERS,
		false,
		custom_cards or local_room,
		password
	)
	room.local_room = local_room
	_rooms.append(room)
	rooms_changed.emit()
	return room


## Takes the second seat of a local room, which only its host can do (nobody else can join it).
## Returns false if the room is not a local room, or the seat is taken.
func seat_second_player(room_id: StringName) -> bool:
	var room := get_room(room_id)
	if room == null or not room.local_room or room.is_full():
		return false
	room.players += 1
	rooms_changed.emit()
	return true


## Seats a player in a room, giving the password if the room has one. Returns OK,
## ERR_DOES_NOT_EXIST, ERR_BUSY (full, or already in a game) or ERR_UNAUTHORIZED (the room has a
## password and this is not it).
func join_room(room_id: StringName, password := "") -> Error:
	var room := get_room(room_id)
	if room == null:
		return ERR_DOES_NOT_EXIST
	if not room.is_joinable():
		return ERR_BUSY
	if not room.accepts(password):
		return ERR_UNAUTHORIZED
	room.players += 1
	rooms_changed.emit()
	return OK


## Frees the second seat of a room, so someone else can take it.
func leave_room(room_id: StringName) -> void:
	var room := get_room(room_id)
	if room != null and room.players > 1:
		room.players -= 1
		rooms_changed.emit()


## Takes a room off the list (its host left).
func remove_room(room_id: StringName) -> void:
	var room := get_room(room_id)
	if room != null:
		_rooms.erase(room)
		rooms_changed.emit()


func _by_name(a: RoomInfo, b: RoomInfo) -> bool:
	return a.room_name.naturalnocasecmp_to(b.room_name) < 0


func _make_id() -> StringName:
	_next_id += 1
	return StringName("room_%d" % _next_id)
