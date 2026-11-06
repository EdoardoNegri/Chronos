class_name LobbyState
extends RefCounted
## What the lobby server knows: who is connected and under what name, which room each of them is
## in (as the host or as the second player), and in their room, whether the deck they chose passed
## the host's check and whether they are ready. When both players in a room are ready, the game
## starts. It holds no sockets, so it can be tested on its own;
## the Lobby node does the talking.
##
## Players are told apart by their peer id. Each of them can be in one room at a time.

var directory := RoomDirectory.new()

var _names: Dictionary[int, String] = {}
## Room id -> peer id of its host / of the second player.
var _host_of: Dictionary[StringName, int] = {}
var _guest_of: Dictionary[StringName, int] = {}
## Peer id -> the room that player is in.
var _room_of: Dictionary[int, StringName] = {}
## Peer ids of the players whose deck passed the check, and of those who are ready.
var _deck_ok: Dictionary[int, bool] = {}
var _ready: Dictionary[int, bool] = {}


## Remembers who a connected player is. Returns an error message, or an empty string.
func register(peer: int, player_name: String) -> String:
	var error := PlayerProfile.validate_name(player_name)
	if not error.is_empty():
		return error
	_names[peer] = player_name.strip_edges()
	return ""


func is_registered(peer: int) -> bool:
	return _names.has(peer)


func name_of(peer: int) -> String:
	return _names.get(peer, "")


## Opens a room hosted by this player. Gives {"room": RoomInfo} or {"error": message}.
func host(peer: int, room_name: String, custom_cards: bool, password: String) -> Dictionary:
	if not is_registered(peer):
		return {"error": "Say who you are first."}
	if _room_of.has(peer):
		return {"error": "Leave your room first."}
	var error := directory.validate_room_name(room_name)
	if not error.is_empty():
		return {"error": error}
	var room := directory.host_room(room_name, custom_cards, password, name_of(peer))
	if room == null:
		return {"error": "Could not create the room."}
	_host_of[room.id] = peer
	_room_of[peer] = room.id
	return {"room": room}


## Seats this player in a room. Gives {"room": RoomInfo, "host_peer": int} or {"error": Error},
## where the error is what RoomDirectory.join_room says, or ERR_ALREADY_IN_USE for a player who is
## in a room already.
func join(peer: int, room_id: StringName, password: String) -> Dictionary:
	if not is_registered(peer):
		return {"error": ERR_UNAUTHORIZED}
	if _room_of.has(peer):
		return {"error": ERR_ALREADY_IN_USE}
	var error := directory.join_room(room_id, password)
	if error != OK:
		return {"error": error}
	_guest_of[room_id] = peer
	_room_of[peer] = room_id
	# Someone new: everyone says again that they are ready.
	_ready.erase(_host_of[room_id])
	return {"room": directory.get_room(room_id), "host_peer": _host_of[room_id]}


## Takes this player out of their room. A host leaving closes the room; a second player leaving
## opens the seat again. Gives {} if they were in no room, otherwise {"closed": bool, "other": peer
## id of the other player, or 0}, so the other player can be told.
func leave(peer: int) -> Dictionary:
	if not _room_of.has(peer):
		return {}
	var room_id := _room_of[peer]
	_room_of.erase(peer)
	_deck_ok.erase(peer)
	_ready.erase(peer)
	if _host_of.get(room_id, 0) == peer:
		var guest: int = _guest_of.get(room_id, 0)
		_host_of.erase(room_id)
		_guest_of.erase(room_id)
		_room_of.erase(guest)
		directory.remove_room(room_id)
		return {"closed": true, "other": guest}
	_guest_of.erase(room_id)
	directory.leave_room(room_id)
	_ready.erase(_host_of.get(room_id, 0))
	return {"closed": false, "other": _host_of.get(room_id, 0)}


## Forgets a player who disconnected, after taking them out of their room (see leave).
func unregister(peer: int) -> Dictionary:
	var result := leave(peer)
	_names.erase(peer)
	return result


## The other player in this player's room, or 0 if there is none.
func opponent_of(peer: int) -> int:
	var room_id: StringName = _room_of.get(peer, &"")
	if room_id == &"":
		return 0
	if _host_of.get(room_id, 0) == peer:
		return _guest_of.get(room_id, 0)
	return _host_of.get(room_id, 0)


## The room this player is in, or &"" if none.
func room_of(peer: int) -> StringName:
	return _room_of.get(peer, &"")


## The players in a room: its host, then the second player if there is one.
func players_in(room_id: StringName) -> Array[int]:
	var players: Array[int] = []
	if _host_of.has(room_id):
		players.append(_host_of[room_id])
	if _guest_of.has(room_id):
		players.append(_guest_of[room_id])
	return players


## Records whether the deck this player chose passed the check. A deck that did not pass also
## takes back their being ready.
func set_deck_ok(peer: int, ok: bool) -> void:
	if ok:
		_deck_ok[peer] = true
	else:
		_deck_ok.erase(peer)
		_ready.erase(peer)


func deck_ok(peer: int) -> bool:
	return _deck_ok.has(peer)


## Says whether this player is ready. Only a player in a room whose deck passed the check can be.
## Returns whether that is now so.
func set_ready(peer: int, ready: bool) -> bool:
	if ready and (not _room_of.has(peer) or not deck_ok(peer)):
		return false
	if ready:
		_ready[peer] = true
	else:
		_ready.erase(peer)
	return ready


func is_ready(peer: int) -> bool:
	return _ready.has(peer)


## Whether a room has two players and both are ready.
func both_ready(room_id: StringName) -> bool:
	var players := players_in(room_id)
	return players.size() == 2 and is_ready(players[0]) and is_ready(players[1])
