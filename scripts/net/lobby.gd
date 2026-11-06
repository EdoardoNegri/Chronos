class_name Lobby
extends Node
## Online play: hosting a room on this computer, joining someone else's, and everything that goes
## on in a room. Registered as the `Online` autoload.
##
## The game that hosts a room is the server: host_here() starts a WebSocket server, opens the room
## (its rules are a LobbyHost) and puts it in the room list (a RoomListing, see RoomBoard). Another
## game joins by connecting to the address in the list (connect_to_server, then join_room).
##
## Godot's remote calls (@rpc) need the same node, with the same script, on both ends of a
## connection, so this script is both ends: `request_*` calls go from a player to the host, `on_*`
## calls from the host to a player. The host's own game skips the network and calls itself.
##
## The connection is a WebSocket, so it also works through a web tunnel such as Cloudflare's, which
## is how someone far away reaches a game running on a home computer (see Reachability).

signal state_changed
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
## The host checked the deck I chose: `problems` is empty if it may be played (see DeckCheck).
signal deck_checked(problems: Array)
## Whether I or the other player in my room is ready changed (my_ready, opponent_ready).
signal ready_changed
## Both players in my room are ready: the game starts.
signal game_started
## Where the room I am hosting stands in the room list changed (see listing_note).
signal listing_changed

enum State { OFFLINE, CONNECTING, CONNECTED }

## The host is always peer 1 in Godot's multiplayer.
const SERVER_ID := 1
const DEFAULT_PORT := 9080
## When a port is busy, the next ones are tried.
const PORT_TRIES := 20
## How long one try to reach a host may take, how many tries there are, and the pause after the
## first one, which grows with each try (a host's new tunnel address can take a moment to work
## everywhere).
const CONNECT_SECONDS := 10.0
const CONNECT_TRIES := 4
const RETRY_SECONDS := 2.0
## Something is sent now and then, so a tunnel does not close a connection it thinks is idle.
const PING_SECONDS := 20.0
## After leaving, the connection stays up this long, so the other side is told first.
const CLOSE_DELAY := 0.6

var state := State.OFFLINE
## Why the connection is not up, in words (empty when it is or was never tried).
var error_text := ""
## The host's game this game is connected to, and the name I go by there.
var server_url := ""
var player_name := ""
## The room I am in, if any, and the other player in it ("" while I am waiting for one).
var room: RoomInfo
var opponent_name := ""
## Something the player should be told when they get back to the room list, once.
var notice := ""
## In my room: whether the host approved my deck, whether I and the other player are ready, and
## whether the game has started.
var deck_approved := false
var my_ready := false
var opponent_ready := false
var game_on := false
## The list of open rooms that players see (see RoomBoard). Tests give one with a fake GitHub.
var board: RoomBoard

## Whether this game hosts the room it is in, and the port its server listens on.
var is_player := false
var hosting_port := 0
## Whether hosting looks for an address someone far away can use (tests turn it off).
var find_public_address := true
## The pause after the first failed try to reach a host (tests make it short).
var retry_seconds := RETRY_SECONDS
## Where the room I am hosting stands in the room list, in words (see RoomListing).
var listing_note := ""
## The issue of my room in the list (0 while it is not in it).
var listed_issue: int:
	get:
		return _listing.issue if _listing != null else 0

var _host: LobbyHost
var _listing: RoomListing
var _connect_timer: Timer
var _ping_timer: Timer
## Tries left to reach the host, and a count that changes whenever a connection starts or ends, so
## a retry meant for an older one does nothing.
var _tries_left := 0
var _connection := 0


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
	if board == null:
		board = RoomBoard.new()
	if board.get_parent() == null:
		add_child(board)
	# Closing the window waits until the room is off the list (see _notification).
	if DisplayServer.get_name() != "headless" and is_inside_tree():
		get_tree().auto_accept_quit = false


func _exit_tree() -> void:
	stop_hosting()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# The game quits by itself once the room is off the list.
		@warning_ignore("missing_await")
		_close_game()


## Takes my room off the list before the game closes, so nobody sees a room that is not there.
func _close_game() -> void:
	if _listing != null:
		var closing := _listing
		_listing = null
		await closing.close()
	stop_hosting()
	get_tree().quit()


# --- Hosting -------------------------------------------------------------------------------


## Opens a room that runs on this computer: starts a server here, opens the room on it, and puts it
## in the room list with an address others can reach it at (see listing_note, listing_changed).
## The answer is `hosted` or `host_failed`. The server stops, and the room leaves the list, when the
## host leaves the room.
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
	_host = LobbyHost.new(_deliver)
	_host.state.register(SERVER_ID, who)
	_set_state(State.CONNECTED)
	_host.open_room(SERVER_ID, room_name, custom_cards, password)
	if room == null:
		stop_hosting()
		return
	_listing = RoomListing.new(board)
	_listing.find_public_address = find_public_address
	_listing.note_changed.connect(_on_listing_note_changed)
	add_child(_listing)
	_listing.start(room, hosting_port)


## Stops hosting from this computer: takes the room off the list, and closes the server, the tunnel
## and the port that were opened.
func stop_hosting() -> void:
	if _listing != null:
		# The listing frees itself once the room is off the list.
		@warning_ignore("missing_await")
		_listing.close()
		_listing = null
	if not is_player:
		return
	_close_peer()
	is_player = false
	hosting_port = 0
	_host = null
	_clear_room()
	listing_note = ""
	_set_state(State.OFFLINE)
	listing_changed.emit()


func _listen_on_a_free_port() -> Error:
	for offset in PORT_TRIES:
		var peer := WebSocketMultiplayerPeer.new()
		if peer.create_server(DEFAULT_PORT + offset) == OK:
			multiplayer.multiplayer_peer = peer
			hosting_port = DEFAULT_PORT + offset
			return OK
	return ERR_CANT_CREATE


func _on_listing_note_changed() -> void:
	if _listing != null:
		listing_note = _listing.note
		listing_changed.emit()


## Delivers what the host's rules say to a player: over the network, or straight to this game if
## the player is its host.
func _deliver(peer: int, method: StringName, args: Array) -> void:
	if peer == SERVER_ID:
		callv(method, args)
	else:
		callv("rpc_id", [peer, method] + args)


## Passes what a player asked for over the network to the host's rules.
func _from_player(action: StringName, args: Array) -> void:
	if _host != null:
		_host.callv(action, [multiplayer.get_remote_sender_id()] + args)


func _on_peer_disconnected(peer: int) -> void:
	if _host != null:
		_host.disconnected(peer)


# --- Joining -------------------------------------------------------------------------------


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


## Connects to a host's game as `who`, trying CONNECT_TRIES times. The result comes through
## state_changed: CONNECTED once the host has accepted the name, or OFFLINE with error_text saying
## why not.
func connect_to_server(url: String, who: String) -> Error:
	stop_hosting()
	disconnect_from_server()
	var address := normalize_url(url)
	if address.is_empty():
		_fail("There is no address to connect to.")
		return ERR_INVALID_PARAMETER
	server_url = address
	player_name = who
	error_text = ""
	_tries_left = CONNECT_TRIES
	var error := _try_to_connect()
	if error != OK:
		_fail("“%s” is not an address a game can be reached at." % url.strip_edges())
		return error
	_set_state(State.CONNECTING)
	return OK


## Leaves the host's game (and any room in it). Does nothing to a server that runs on this
## computer; see stop_hosting for that.
func disconnect_from_server() -> void:
	_connection += 1
	_connect_timer.stop()
	_ping_timer.stop()
	if is_player:
		return
	_close_peer()
	_clear_room()
	if state != State.OFFLINE:
		_set_state(State.OFFLINE)


func _try_to_connect() -> Error:
	_tries_left -= 1
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client(server_url)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	_connect_timer.start(CONNECT_SECONDS)
	return OK


## A try to reach the host failed: tries again after a pause while there are tries left.
func _try_failed(reason: String) -> void:
	_connect_timer.stop()
	_close_peer()
	if _tries_left <= 0:
		_give_up(reason)
		return
	var connection := _connection
	var tries_made := CONNECT_TRIES - _tries_left
	await get_tree().create_timer(retry_seconds * tries_made).timeout
	if connection != _connection or state != State.CONNECTING:
		return
	if _try_to_connect() != OK:
		_give_up(reason)


func _give_up(reason: String) -> void:
	_connection += 1
	_clear_room()
	_fail(reason)


func _on_connected_to_server() -> void:
	request_hello.rpc_id(SERVER_ID, player_name)


func _on_connection_failed() -> void:
	if state == State.CONNECTING:
		# The next try starts by itself after a pause.
		@warning_ignore("missing_await")
		_try_failed("Could not reach the game at %s." % server_url)


func _on_connect_timeout() -> void:
	if state == State.CONNECTING:
		@warning_ignore("missing_await")
		_try_failed("The game at %s did not answer." % server_url)


func _on_server_disconnected() -> void:
	if is_player:
		return
	disconnect_from_server()
	_fail("Lost the connection to the host's game.")


func _ping() -> void:
	if state == State.CONNECTED and _server_reachable():
		request_ping.rpc_id(SERVER_ID)


## Whether there is a real host on the other end to send a request to. (A remote call to oneself
## is an error in Godot, so nothing is sent when this is not so, such as in a test that pretends to
## be connected.)
func _server_reachable() -> bool:
	var peer := multiplayer.multiplayer_peer
	return (
		not is_player
		and peer != null
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		and multiplayer.get_unique_id() != SERVER_ID
	)


func _close_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


# --- In a room -----------------------------------------------------------------------------


## Joins a room in the host's game I am connected to. The answer is `joined` or `join_failed`.
func join_room(room_id: StringName, password: String) -> void:
	if state != State.CONNECTED:
		join_failed.emit(ERR_CONNECTION_ERROR)
		return
	_ask(&"join", &"request_join", [str(room_id), password])


## Leaves the room I am in. A room hosted here closes, and its server stops once the other player
## has been told; a guest leaves the host's game shortly after saying so.
func leave_room() -> void:
	if is_player:
		_host.leave(SERVER_ID)
		_clear_room()
		get_tree().create_timer(CLOSE_DELAY).timeout.connect(stop_hosting)
		return
	if room != null:
		_ask(&"leave", &"request_leave", [])
	_clear_room()
	get_tree().create_timer(CLOSE_DELAY).timeout.connect(_leave_host.bind(_connection))


## Leaves the host's game after leaving its room, unless something else happened meanwhile.
func _leave_host(connection: int) -> void:
	if connection == _connection and room == null:
		disconnect_from_server()


## Asks the host to check the deck I chose: `deck_data` and `sent_cards` as DeckData.to_dict and
## DeckCheck.send_cards give them. The answer is deck_checked.
func check_deck(deck_data: Dictionary, sent_cards: Array) -> void:
	deck_approved = false
	if room != null:
		_ask(&"check_deck", &"request_deck_check", [deck_data, sent_cards])


## Says I am ready to play (or not any more). The answer is ready_changed, and game_started once
## both players are ready.
func set_ready(is_ready: bool) -> void:
	if room != null:
		_ask(&"set_ready", &"request_set_ready", [is_ready])


## Says something to the other player in my room.
func send_chat(text: String) -> void:
	if room != null:
		_ask(&"chat", &"request_chat", [text])


## Sends a request to the host: straight to its rules when this game is the host, otherwise over
## the network.
func _ask(action: StringName, request: StringName, args: Array) -> void:
	if _host != null:
		_host.callv(action, [SERVER_ID] + args)
	elif state == State.CONNECTED and _server_reachable():
		callv("rpc_id", [SERVER_ID, request] + args)


func _clear_room() -> void:
	room = null
	opponent_name = ""
	deck_approved = false
	my_ready = false
	opponent_ready = false
	game_on = false


func _fail(message: String) -> void:
	error_text = message
	if state != State.OFFLINE:
		_set_state(State.OFFLINE)
	else:
		# Listeners hear why even if they were told "offline" already.
		state_changed.emit()


func _set_state(new_state: State) -> void:
	if state != new_state:
		state = new_state
		state_changed.emit()


# --- From a player to the host -------------------------------------------------------------


@rpc("any_peer", "call_remote", "reliable")
func request_hello(requested_name: String) -> void:
	_from_player(&"hello", [requested_name])


@rpc("any_peer", "call_remote", "reliable")
func request_join(room_id: String, password: String) -> void:
	_from_player(&"join", [room_id, password])


@rpc("any_peer", "call_remote", "reliable")
func request_leave() -> void:
	_from_player(&"leave", [])


@rpc("any_peer", "call_remote", "reliable")
func request_chat(text: String) -> void:
	_from_player(&"chat", [text])


@rpc("any_peer", "call_remote", "reliable")
func request_deck_check(deck_data: Dictionary, sent_cards: Array) -> void:
	_from_player(&"check_deck", [deck_data, sent_cards])


@rpc("any_peer", "call_remote", "reliable")
func request_set_ready(is_ready: bool) -> void:
	_from_player(&"set_ready", [is_ready])


@rpc("any_peer", "call_remote", "unreliable")
func request_ping() -> void:
	pass


# --- From the host to a player -------------------------------------------------------------


@rpc("authority", "call_remote", "reliable")
func on_hello_result(error: String) -> void:
	_connect_timer.stop()
	if error.is_empty():
		_ping_timer.start()
		_set_state(State.CONNECTED)
	else:
		disconnect_from_server()
		_fail(error)


@rpc("authority", "call_remote", "reliable")
func on_hosted(room_data: Dictionary, error: String) -> void:
	if not error.is_empty():
		host_failed.emit(error)
		return
	_clear_room()
	room = RoomInfo.from_dict(room_data)
	hosted.emit(room)


@rpc("authority", "call_remote", "reliable")
func on_join_result(error: int, room_data: Dictionary, host_name: String) -> void:
	if error != OK:
		join_failed.emit(error)
		return
	_clear_room()
	room = RoomInfo.from_dict(room_data)
	opponent_name = host_name
	joined.emit(room)


@rpc("authority", "call_remote", "reliable")
func on_opponent_joined(who: String) -> void:
	opponent_name = who
	opponent_joined.emit(who)


@rpc("authority", "call_remote", "reliable")
func on_opponent_left() -> void:
	opponent_name = ""
	opponent_ready = false
	opponent_left.emit()


@rpc("authority", "call_remote", "reliable")
func on_deck_checked(problems: Array) -> void:
	deck_approved = problems.is_empty()
	deck_checked.emit(problems)


@rpc("authority", "call_remote", "reliable")
func on_ready_state(mine: bool, theirs: bool) -> void:
	my_ready = mine
	opponent_ready = theirs
	ready_changed.emit()


@rpc("authority", "call_remote", "reliable")
func on_game_start() -> void:
	game_on = true
	game_started.emit()


@rpc("authority", "call_remote", "reliable")
func on_room_closed() -> void:
	_clear_room()
	notice = "The host closed the room."
	room_closed.emit()


@rpc("authority", "call_remote", "reliable")
func on_chat(from_name: String, text: String) -> void:
	chat_received.emit(from_name, text)
