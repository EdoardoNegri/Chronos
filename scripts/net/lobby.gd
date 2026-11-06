class_name Lobby
extends Node
## The online lobby, where players find each other. One script plays all the parts, because
## Godot's remote calls (@rpc) need the same node, with the same script, on both ends of a
## connection:
##
## - A *server* keeps the rooms (a LobbyState), answers what players ask for, tells the other player
##   in a room what happens, and passes chat between them. It runs either on its own (see
##   lobby_server.tscn) or inside the game of the player who hosts a room, which is how a link
##   works: host_here() starts the server in the host's game, and the link leads to it.
## - A *player* connects to a server (connect_to_server), keeps the last list of open rooms it was
##   sent, and says what happens through signals. The host of a room is a player too: their game
##   talks to its own server directly instead of over the network.
##
## The connection is a WebSocket, so it also works through a web tunnel such as Cloudflare's, which
## is how someone far away reaches a game running on a home computer (see Reachability).

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
## The invite link of the room I am hosting here changed (or is ready, or could not be made).
signal link_changed
## An invite link was opened while the game was already running (see InviteInbox). It waits in
## pending_invite for the Play screen to follow it.
signal invite_opened

enum State { OFFLINE, CONNECTING, CONNECTED }

## The server is always peer 1 in Godot's multiplayer.
const SERVER_ID := 1
const DEFAULT_PORT := 9080
## When a port is busy, the next ones are tried.
const PORT_TRIES := 20
const CONNECT_SECONDS := 10.0
## Something is sent now and then, so a tunnel does not close a connection it thinks is idle.
const PING_SECONDS := 20.0
const MAX_CHAT_LENGTH := 200
## After the host leaves, the server stays up this long, so the other player is told first.
const CLOSE_DELAY := 0.6

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
## An invite link the game was started with, or that was opened while it ran, waiting to be used.
## {} if none.
var pending_invite: Dictionary = {}

# --- Hosting from this computer ------------------------------------------------------------

## The link to send to a friend, once it is made ("" until then), and a note about it, such as
## "Making your invite link…" or why it only works on this network.
var invite_link := ""
var link_note := ""
## Whether to look for an address someone far away can use (tests turn it off).
var find_public_address := true
var hosting_port := 0

# --- The server's side ---------------------------------------------------------------------

var is_server := false
## True when the server runs inside the game of the player who is hosting (see host_here).
var is_player := false

var _lobby := LobbyState.new()
var _reachability: Reachability
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
	# Opening a link starts the game with the link as an argument.
	var args := OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	pending_invite = InviteLink.find_in(args)


## An invite link was opened while the game was running: it waits to be followed (invite_opened).
func open_invite(invite: Dictionary) -> void:
	pending_invite = invite
	invite_opened.emit()


func _exit_tree() -> void:
	stop_hosting()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_hosting()


# =============================================================================================
# The server
# =============================================================================================


## Starts a server on its own, listening for players on `port`. Returns an error if it cannot.
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
	if is_server:
		_serve_hello(multiplayer.get_remote_sender_id(), requested_name)


@rpc("any_peer", "call_remote", "reliable")
func request_rooms() -> void:
	if is_server and _lobby.is_registered(multiplayer.get_remote_sender_id()):
		_tell(multiplayer.get_remote_sender_id(), &"on_rooms", [_lobby.directory.open_snapshot()])


@rpc("any_peer", "call_remote", "reliable")
func request_host(room_name: String, custom_cards: bool, password: String) -> void:
	if is_server:
		_serve_host(multiplayer.get_remote_sender_id(), room_name, custom_cards, password)


@rpc("any_peer", "call_remote", "reliable")
func request_join(room_id: String, password: String) -> void:
	if is_server:
		_serve_join(multiplayer.get_remote_sender_id(), room_id, password)


@rpc("any_peer", "call_remote", "reliable")
func request_leave() -> void:
	if is_server:
		_serve_leave(multiplayer.get_remote_sender_id())


## Passes a chat line to the other player in the room. (Whatever the game needs to send between
## two players later goes the same way.)
@rpc("any_peer", "call_remote", "reliable")
func request_chat(text: String) -> void:
	if is_server:
		_serve_chat(multiplayer.get_remote_sender_id(), text)


@rpc("any_peer", "call_remote", "unreliable")
func request_ping() -> void:
	pass


# What the server does with each request. `peer` is who asked: another player's peer id, or
# SERVER_ID for the host playing from the same computer.


func _serve_hello(peer: int, requested_name: String) -> void:
	var error := _lobby.register(peer, requested_name)
	_tell(peer, &"on_hello_result", [error])
	if error.is_empty():
		_tell(peer, &"on_rooms", [_lobby.directory.open_snapshot()])


func _serve_host(peer: int, room_name: String, custom_cards: bool, password: String) -> void:
	if is_player and peer != SERVER_ID:
		_tell(peer, &"on_hosted", [{}, "Only the person running this server can open a room."])
		return
	var result := _lobby.host(peer, room_name, custom_cards, password)
	if result.has("error"):
		_tell(peer, &"on_hosted", [{}, result["error"]])
		return
	_tell(peer, &"on_hosted", [(result["room"] as RoomInfo).to_dict(), ""])
	_send_rooms_to_everyone()


func _serve_join(peer: int, room_id: String, password: String) -> void:
	var result := _lobby.join(peer, StringName(room_id), password)
	if result.has("error"):
		_tell(peer, &"on_join_result", [int(result["error"]), {}, ""])
		return
	var joined_room: RoomInfo = result["room"]
	var host_peer: int = result["host_peer"]
	_tell(peer, &"on_join_result", [OK, joined_room.to_dict(), joined_room.host_name])
	_tell(host_peer, &"on_opponent_joined", [_lobby.name_of(peer)])
	_send_rooms_to_everyone()


func _serve_leave(peer: int) -> void:
	_tell_other_player(_lobby.leave(peer))


func _serve_chat(peer: int, text: String) -> void:
	var other := _lobby.opponent_of(peer)
	var clean := text.strip_edges().left(MAX_CHAT_LENGTH)
	if other != 0 and not clean.is_empty():
		_tell(other, &"on_chat", [_lobby.name_of(peer), clean])


func _on_peer_disconnected(peer: int) -> void:
	if is_server:
		_tell_other_player(_lobby.unregister(peer))


## After someone left a room (see LobbyState.leave): tells the other player, then everyone the
## rooms that are open now.
func _tell_other_player(left: Dictionary) -> void:
	if left.is_empty():
		return
	var other: int = left["other"]
	if other != 0:
		_tell(other, &"on_room_closed" if left["closed"] else &"on_opponent_left", [])
	_send_rooms_to_everyone()


func _send_rooms_to_everyone() -> void:
	var snapshot := _lobby.directory.open_snapshot()
	for peer in _lobby.registered_peers():
		_tell(peer, &"on_rooms", [snapshot])


## Sends a message to a player: over the network, or straight to this game if it is the host's.
func _tell(peer: int, method: StringName, args: Array) -> void:
	if peer == SERVER_ID:
		if is_player:
			callv(method, args)
		return
	callv("rpc_id", [peer, method] + args)


## A server on its own, as opposed to one inside a host's game: nobody plays on it.
func _is_dedicated() -> bool:
	return is_server and not is_player


# =============================================================================================
# Hosting from this computer
# =============================================================================================


## Opens a room that runs on this computer: starts a server here, opens the room on it, and works
## out an invite link for it (see invite_link, link_changed). The answer is `hosted` or
## `host_failed`. The server stops when the host leaves the room.
func host_here(who: String, room_name: String, custom_cards: bool, password: String) -> void:
	var error := RoomDirectory.check_room_name(room_name)
	if error.is_empty() and password.length() > RoomDirectory.MAX_PASSWORD_LENGTH:
		error = "That password is too long."
	if not error.is_empty():
		host_failed.emit(error)
		return
	disconnect_from_server()
	stop_hosting()
	if _listen_on_a_free_port() != OK:
		host_failed.emit("Could not start a server on this computer.")
		return
	is_player = true
	player_name = who
	invite_link = ""
	link_note = "Making your invite link…"
	_lobby.register(SERVER_ID, who)
	_set_state(State.CONNECTED)
	_serve_host(SERVER_ID, room_name, custom_cards, password)
	if room == null:
		stop_hosting()
		return
	_start_link()


## Stops hosting from this computer: closes the server, the tunnel and the port that were opened.
func stop_hosting() -> void:
	if _reachability != null:
		_reachability.stop()
		_reachability.queue_free()
		_reachability = null
	if not is_player:
		return
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_server = false
	is_player = false
	hosting_port = 0
	_lobby = LobbyState.new()
	room = null
	opponent_name = ""
	invite_link = ""
	link_note = ""
	_set_state(State.OFFLINE)
	link_changed.emit()


func _listen_on_a_free_port() -> Error:
	for offset in PORT_TRIES:
		var peer := WebSocketMultiplayerPeer.new()
		if peer.create_server(DEFAULT_PORT + offset) == OK:
			multiplayer.multiplayer_peer = peer
			is_server = true
			hosting_port = DEFAULT_PORT + offset
			return OK
	return ERR_CANT_CREATE


func _start_link() -> void:
	link_changed.emit()
	if not find_public_address:
		_use_local_link("")
		return
	_reachability = Reachability.new()
	add_child(_reachability)
	_reachability.address_found.connect(_on_address_found)
	_reachability.failed.connect(_on_address_failed)
	_reachability.start(hosting_port)


func _on_address_found(address: String, _how: String) -> void:
	_set_link(address, "")


## Without a public address the link still works for people on the same network.
func _on_address_failed(reason: String) -> void:
	_use_local_link(reason)


func _use_local_link(reason: String) -> void:
	var note := "Only people on your own network can use this link."
	if not reason.is_empty():
		note += " " + reason
	_set_link("ws://%s:%d" % [_local_address(), hosting_port], note)


func _set_link(address: String, note: String) -> void:
	if room == null:
		return
	invite_link = InviteLink.make_best(address, room.id, room.room_name, room.locked)
	link_note = note
	link_changed.emit()


## This computer's address on the home network (or "127.0.0.1" if it has none).
static func _local_address() -> String:
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and Reachability.is_private_address(address) and not address.begins_with("127.") and not address.begins_with("169.254."):
			return address
	return "127.0.0.1"


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
	stop_hosting()
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


## Leaves the server (and any room). Does nothing to a server that runs on this computer; see
## stop_hosting for that.
func disconnect_from_server() -> void:
	_connect_timer.stop()
	_ping_timer.stop()
	if is_server:
		return
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_forget_everything()
	if state != State.OFFLINE:
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


## Opens a room on the server this game is connected to. The answer is `hosted` or `host_failed`.
## (To host from this computer instead, see host_here.)
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


## Leaves the room I am in (closing it if it is mine; a room hosted from this computer also stops
## its server shortly after, once the other player has been told).
func leave_room() -> void:
	if is_player:
		_serve_leave(SERVER_ID)
		room = null
		opponent_name = ""
		get_tree().create_timer(CLOSE_DELAY).timeout.connect(stop_hosting)
		return
	if state == State.CONNECTED and room != null and _server_reachable():
		request_leave.rpc_id(SERVER_ID)
	room = null
	opponent_name = ""


## Says something to the other player in my room.
func send_chat(text: String) -> void:
	if is_player and room != null:
		_serve_chat(SERVER_ID, text)
	elif state == State.CONNECTED and room != null and _server_reachable():
		request_chat.rpc_id(SERVER_ID, text)


@rpc("authority", "call_remote", "reliable")
func on_hello_result(error: String) -> void:
	if _is_dedicated():
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
	if _is_dedicated():
		return
	rooms.replace_from_snapshot(snapshot)
	rooms_changed.emit()


@rpc("authority", "call_remote", "reliable")
func on_hosted(room_data: Dictionary, error: String) -> void:
	if _is_dedicated():
		return
	if not error.is_empty():
		host_failed.emit(error)
		return
	room = RoomInfo.from_dict(room_data)
	opponent_name = ""
	hosted.emit(room)


@rpc("authority", "call_remote", "reliable")
func on_join_result(error: int, room_data: Dictionary, host_name: String) -> void:
	if _is_dedicated():
		return
	if error != OK:
		join_failed.emit(error)
		return
	room = RoomInfo.from_dict(room_data)
	opponent_name = host_name
	joined.emit(room)


@rpc("authority", "call_remote", "reliable")
func on_opponent_joined(who: String) -> void:
	if _is_dedicated():
		return
	opponent_name = who
	opponent_joined.emit(who)


@rpc("authority", "call_remote", "reliable")
func on_opponent_left() -> void:
	if _is_dedicated():
		return
	opponent_name = ""
	opponent_left.emit()


@rpc("authority", "call_remote", "reliable")
func on_room_closed() -> void:
	if _is_dedicated():
		return
	room = null
	opponent_name = ""
	notice = "The host closed the room."
	room_closed.emit()


@rpc("authority", "call_remote", "reliable")
func on_chat(from_name: String, text: String) -> void:
	if not _is_dedicated():
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
	if state == State.CONNECTED and _server_reachable():
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
