class_name RoomDirectory
extends Node
## Source of truth for the online room list, registered as the `Rooms` autoload.
##
## This is a local stand-in with fake rooms. The UI only talks to the signals and methods
## below, so a real backend can replace the bodies of refresh/host_room/join_room without
## touching any screen.

signal rooms_changed

const MIN_PLAYERS := 2
const MAX_PLAYERS := 8
const MAX_NAME_LENGTH := 32

var player_name := "Player"

var _rooms: Array[RoomInfo] = []
var _next_id := 1


func _init() -> void:
	_seed_fake_rooms()


## Rooms whose name or host contains `query` (case-insensitive), sorted by name.
func get_rooms(query := "") -> Array[RoomInfo]:
	var needle := query.strip_edges().to_lower()
	var result: Array[RoomInfo] = []
	for room in _rooms:
		if (
			needle.is_empty()
			or room.room_name.to_lower().contains(needle)
			or room.host_name.to_lower().contains(needle)
		):
			result.append(room)
	result.sort_custom(_by_name)
	return result


func get_room_count() -> int:
	return _rooms.size()


## Re-fetches the list from the backend and emits `rooms_changed` when done.
func refresh() -> void:
	rooms_changed.emit()


## Returns an error message, or an empty string if `room_name` can be used for a new room.
func validate_room_name(room_name: String) -> String:
	var trimmed := room_name.strip_edges()
	if trimmed.is_empty():
		return "Give your room a name."
	if trimmed.length() > MAX_NAME_LENGTH:
		return "Room names can be at most %d characters." % MAX_NAME_LENGTH
	for room in _rooms:
		if room.room_name.to_lower() == trimmed.to_lower():
			return "A room with that name already exists."
	return ""


## Creates a room hosted by the local player. Returns null if the name or size is invalid.
func host_room(room_name: String, max_players: int) -> RoomInfo:
	if not validate_room_name(room_name).is_empty():
		return null
	if max_players < MIN_PLAYERS or max_players > MAX_PLAYERS:
		return null
	var room := RoomInfo.new(_make_id(), room_name.strip_edges(), player_name, 1, max_players)
	_rooms.append(room)
	rooms_changed.emit()
	return room


## Joins a room as the local player. Returns OK, ERR_DOES_NOT_EXIST or ERR_BUSY.
func join_room(room_id: StringName) -> Error:
	for room in _rooms:
		if room.id != room_id:
			continue
		if not room.is_joinable():
			return ERR_BUSY
		room.players += 1
		rooms_changed.emit()
		return OK
	return ERR_DOES_NOT_EXIST


func _by_name(a: RoomInfo, b: RoomInfo) -> bool:
	return a.room_name.naturalnocasecmp_to(b.room_name) < 0


func _make_id() -> StringName:
	_next_id += 1
	return StringName("room_%d" % _next_id)


func _seed_fake_rooms() -> void:
	var seeds := [
		["Temporal Rift", "Aeon", 1, 2, false],
		["Midnight Duel", "Kairos", 2, 2, true],
		["Casual Hourglass", "Sandy", 1, 4, false],
		["Beginners Welcome", "Tempus", 3, 4, false],
		["Ranked Clash", "Vesper", 2, 2, false],
		["Paradox Lounge", "Lyra", 1, 6, false],
		["Last Second", "Orion", 4, 4, false],
		["Deck Testing", "Nyx", 1, 2, false],
	]
	for entry: Array in seeds:
		_rooms.append(RoomInfo.new(_make_id(), entry[0], entry[1], entry[2], entry[3], entry[4]))
