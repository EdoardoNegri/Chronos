class_name Lobby
extends Node
## The online lobby, where players find each other. One script plays both parts, because Godot's
## remote calls (@rpc) need the same node, with the same script, on both ends of a connection:
##
## - On the lobby server (see lobby_server.tscn) it keeps the rooms (a LobbyState), answers what
##   players ask for, tells the other player in a room what happens, and passes chat between them.
## - In the game (the `Online` autoload) it connects to a server, keeps the last list of open rooms
##   it was sent, and says what happens through signals.
##
## The connection is a WebSocket, so it also works through a web tunnel such as Cloudflare's, which
## is how someone far away can reach a server running on a home computer.

signal state_changed
signal rooms_changed
## I opened a room, or could not (the message says why).
signal hosted(room: RoomInfo)
signal host_failed(message: String)
## I joined someone's room, or could not (`error` is what RoomDirectory.join_room says).
signal joined(room: RoomInfo)
signal join_failed(error: int)
signal opponent_joined(opponent_name: String)
signal opponent_left
## The host left, so the room I was in is gone.
signal room_closed
signal chat_received(from_name: String, text: String)

enum State { OFFLINE, CONNECTING, CONNECTED }

## The server is always peer 1 in Godot's multiplayer.
const SERVER_ID := 1
const DEFAULT_PORT := 9080
const CONNECT_SECONDS := 10.0
## Something is sent now and then, so a tunnel does not close a connection it thinks is idle.
const PING_SECONDS := 20.0
const MAX_CHAT_LENGTH := 200

# --- The game's side -----------------------------------------------------------------------

var state := State.OFFLINE
## Why the connection is not up, in words (empty when it is or was never tried).
var error_text := ""
var server_url := ""
var player_name := ""
## The open rooms, as the server last sent them.
var rooms := RoomDirectory.new()
## The room I am in, if any, and the other player in it ("" while I am waiting for one).
var room: RoomInfo
var opponent_name := ""
## Something the player should be told when they get back to the room list, once.
var notice := ""

# --- The server's side ---------------------------------------------------------------------

var is_server := false

var _lobby := LobbyState.new()
var _connect_timer: Timer
var _ping_timer: Timer


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_connect_timer = Timer.new()
	_connect_timer.one_shot = true
	_connect_timer.timeout.connect(_on_connect_timeout)
	add_child(_connect_timer)
	_ping_timer = Timer.new()
	_ping_timer.wait_time = PING_SECONDS
	_ping_timer.timeout.connect(_ping)
	add_child(_ping_timer)


# =============================================================================================
# The server
# =============================================================================================


## Starts listening for players on `port`. Returns an error if it cannot.
func start_server(port := DEFAULT_PORT) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(port)
	if error != OK:
		return error
	is_server = true
	multiplayer.multiplayer_peer = peer
	return OK


@rpc("any_peer", "call_remote", "reliable")
func request_hello(requested_name: String) -> void:
	if not is_server:
		return
	var peer := multiplayer.get_remote_sender_id()
	var error := _lobby.register(peer, requested_name)
	on_hello_result.rpc_id(peer, error)
	if error.is_empty():
		on_rooms.rpc_id(peer, _lobby.directory.open_snapshot())


@rpc("any_peer", "call_remote", "reliable")
func request_rooms() -> void:
	if is_server and _lobby.is_registered(multiplayer.get_remote_sender_id()):
		on_rooms.rpc_id(multiplayer.get_remote_sender_id(), _lobby.directory.open_snapshot())


@rpc("any_peer", "call_remote", "reliable")
func request_host(room_name: String, custom_cards: bool, password: String) -> void:
	if not is_server:
		return
	var peer := multiplayer.get_remote_sender_id()
	var result := _lobby.host(peer, room_name, custom_cards, password)
	if result.has("error"):
		on_hosted.rpc_id(peer, {}, result["error"])
		return
	on_hosted.rpc_id(peer, (result["room"] as RoomInfo).to_dict(), "")
	_send_rooms_to_everyone()


@rpc("any_peer", "call_remote", "reliable")
func request_join(room_id: String, password: String) -> void:
	if not is_server:
		return
	var peer := multiplayer.get_remote_sender_id()
	var result := _lobby.join(peer, StringName(room_id), password)
	if result.has("error"):
		on_join_result.rpc_id(peer, int(result["error"]), {}, "")
		return
	var joined_room: RoomInfo = result["room"]
	var host_peer: int = result["host_peer"]
	on_join_result.rpc_id(peer, OK, joined_room.to_dict(), joined_room.host_name)
	on_opponent_joined.rpc_id(host_peer, _lobby.name_of(peer))
	_send_rooms_to_everyone()


@rpc("any_peer", "call_remote", "reliable")
func request_leave() -> void:
	if is_server:
		_tell_other_player(_lobby.leave(multiplayer.get_remote_sender_id()))


## Passes a chat line to the other player in the room. (Whatever the game needs to send between
## two players later goes the same way.)
@rpc("any_peer", "call_remote", "reliable")
func request_chat(text: String) -> void:
	if not is_server:
		return
	var peer := multiplayer.get_remote_sender_id()
	var other := _lobby.opponent_of(peer)
	var clean := text.strip_edges().left(MAX_CHAT_LENGTH)
	if other != 0 and not clean.is_empty():
		on_chat.rpc_id(other, _lobby.name_of(peer), clean)


@rpc("any_peer", "call_remote", "unreliable")
func request_ping() -> void:
	pass


func _on_peer_disconnected(peer: int) -> void:
	if not is_server:
		return
	_tell_other_player(_lobby.unregister(peer))


## After someone left a room (see LobbyState.leave): tells the other player, then everyone the
## rooms that are open now.
func _tell_other_player(left: Dictionary) -> void:
	if left.is_empty():
		return
	var other: int = left["other"]
	if other != 0:
		if left["closed"]:
			on_room_closed.rpc_id(other)
		else:
			on_opponent_left.rpc_id(other)
	_send_rooms_to_everyone()


func _send_rooms_to_everyone() -> void:
	var snapshot := _lobby.directory.open_snapshot()
	for peer in _lobby.registered_peers():
		on_rooms.rpc_id(peer, snapshot)


# =============================================================================================
# The game
# =============================================================================================


## The address a player typed, as a WebSocket address: "abc.trycloudflare.com" becomes
## "wss://abc.trycloudflare.com", and a computer on the same network or this one ("192.168.0.5:9080",
## "localhost") becomes "ws://...". An address that already starts with ws:// or wss:// is kept, and
## http(s):// is read as the same with a w. Empty stays empty.
static func normalize_url(text: String) -> String:
	var url := text.strip_edges()
	if url.is_empty():
		return ""
	if url.begins_with("ws://") or url.begins_with("wss://"):
		return url
	if url.begins_with("https://"):
		return "wss://" + url.trim_prefix("https://")
	if url.begins_with("http://"):
		return "ws://" + url.trim_prefix("http://")
	var host := url.split("/")[0].split(":")[0]
	var is_local := (
		host == "localhost"
		or host.begins_with("127.")
		or host.begins_with("192.168.")
		or host.begins_with("10.")
		or host.is_valid_ip_address()
	)
	return ("ws://" if is_local else "wss://") + url


## Connects to a lobby server as `who`. The result comes through state_changed: CONNECTED once the
## server has accepted the name, or OFFLINE with error_text saying why not.
func connect_to_server(url: String, who: String) -> Error:
	disconnect_from_server()
	var address := normalize_url(url)
	if address.is_empty():
		_fail("There is no server address. Set one in Settings.")
		return ERR_INVALID_PARAMETER
	server_url = address
	player_name = who
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client(address)
	if error != OK:
		_fail("“%s” is not a server address." % url.strip_edges())
		return error
	multiplayer.multiplayer_peer = peer
	error_text = ""
	_set_state(State.CONNECTING)
	_connect_timer.start(CONNECT_SECONDS)
	return OK


## Leaves the server (and any room).
func disconnect_from_server() -> void:
	_connect_timer.stop()
	_ping_timer.stop()
	if multiplayer.multiplayer_peer != null and not is_server:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_forget_everything()
	_set_state(State.OFFLINE)


func is_connected_to_server() -> bool:
	return state == State.CONNECTED


## Whether there is a real server on the other end to send a request to. (A remote call to oneself
## is an error in Godot, so nothing is sent when this is not so, such as in a test that pretends to
## be connected.)
func _server_reachable() -> bool:
	var peer := multiplayer.multiplayer_peer
	return (
		not is_server
		and peer != null
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		and multiplayer.get_unique_id() != SERVER_ID
	)


## Asks the server for the open rooms again (it also sends them whenever they change).
func refresh() -> void:
	if state == State.CONNECTED and _server_reachable():
		request_rooms.rpc_id(SERVER_ID)


## Opens a room. The answer is `hosted` or `host_failed`.
func host_room(room_name: String, custom_cards: bool, password: String) -> void:
	if state != State.CONNECTED:
		host_failed.emit("You are not connected to a server.")
		return
	if _server_reachable():
		request_host.rpc_id(SERVER_ID, room_name, custom_cards, password)


## Joins a room. The answer is `joined` or `join_failed`.
func join_room(room_id: StringName, password: String) -> void:
	if state != State.CONNECTED:
		join_failed.emit(ERR_CONNECTION_ERROR)
		return
	if _server_reachable():
		request_join.rpc_id(SERVER_ID, str(room_id), password)


## Leaves the room I am in (closing it if it is mine).
func leave_room() -> void:
	if state == State.CONNECTED and room != null and _server_reachable():
		request_leave.rpc_id(SERVER_ID)
	room = null
	opponent_name = ""


## Says something to the other player in my room.
func send_chat(text: String) -> void:
	if state == State.CONNECTED and room != null and _server_reachable():
		request_chat.rpc_id(SERVER_ID, text)


@rpc("authority", "call_remote", "reliable")
func on_hello_result(error: String) -> void:
	if is_server:
		return
	_connect_timer.stop()
	if error.is_empty():
		_ping_timer.start()
		_set_state(State.CONNECTED)
	else:
		disconnect_from_server()
		_fail(error)


@rpc("authority", "call_remote", "reliable")
func on_rooms(snapshot: Array) -> void:
	if is_server:
		return
	rooms.replace_from_snapshot(snapshot)
	rooms_changed.emit()


@rpc("authority", "call_remote", "reliable")
func on_hosted(room_data: Dictionary, error: String) -> void:
	if is_server:
		return
	if not error.is_empty():
		host_failed.emit(error)
		return
	room = RoomInfo.from_dict(room_data)
	opponent_name = ""
	hosted.emit(room)


@rpc("authority", "call_remote", "reliable")
func on_join_result(error: int, room_data: Dictionary, host_name: String) -> void:
	if is_server:
		return
	if error != OK:
		join_failed.emit(error)
		return
	room = RoomInfo.from_dict(room_data)
	opponent_name = host_name
	joined.emit(room)


@rpc("authority", "call_remote", "reliable")
func on_opponent_joined(who: String) -> void:
	if is_server:
		return
	opponent_name = who
	opponent_joined.emit(who)


@rpc("authority", "call_remote", "reliable")
func on_opponent_left() -> void:
	if is_server:
		return
	opponent_name = ""
	opponent_left.emit()


@rpc("authority", "call_remote", "reliable")
func on_room_closed() -> void:
	if is_server:
		return
	room = null
	opponent_name = ""
	notice = "The host closed the room."
	room_closed.emit()


@rpc("authority", "call_remote", "reliable")
func on_chat(from_name: String, text: String) -> void:
	if not is_server:
		chat_received.emit(from_name, text)


func _on_connected_to_server() -> void:
	request_hello.rpc_id(SERVER_ID, player_name)


func _on_connection_failed() -> void:
	disconnect_from_server()
	_fail("Could not reach the server at %s." % server_url)


func _on_connect_timeout() -> void:
	if state == State.CONNECTING:
		disconnect_from_server()
		_fail("The server at %s did not answer." % server_url)


func _on_server_disconnected() -> void:
	if is_server:
		return
	disconnect_from_server()
	_fail("Lost the connection to the server.")


func _ping() -> void:
	if state == State.CONNECTED:
		request_ping.rpc_id(SERVER_ID)


## Records why there is no connection. Listeners hear it even if they were told "offline" already.
func _fail(message: String) -> void:
	error_text = message
	if state != State.OFFLINE:
		_set_state(State.OFFLINE)
	else:
		state_changed.emit()


func _forget_everything() -> void:
	rooms.replace_from_snapshot([])
	room = null
	opponent_name = ""


func _set_state(new_state: State) -> void:
	if state != new_state:
		state = new_state
		state_changed.emit()
