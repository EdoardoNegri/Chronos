class_name InviteInbox
extends Node
## Lets an invite link opened while the game is already running join from the game that is open,
## instead of starting a second one.
##
## The first game started listens on a port on this computer only. A game started by opening a
## link finds that port taken, so it passes the link to the open game, waits for it to say it got
## it, and closes. The open game comes to the front and goes to Play, which joins the room. If the
## player is in a room just then, the link waits until they are back on Play.

const PORT := 47613
const PLAY_SCENE := "res://scenes/play.tscn"
## How long a game started by a link waits for the open one to answer before carrying on itself.
const HAND_OFF_SECONDS := 2.0
## How long the open game keeps a connection that has not sent a whole link.
const READ_SECONDS := 5.0
const ACK := "ok\n"

## A link came in from a game started by opening it.
signal received(invite: Dictionary)

## Where links are passed. Tests use another port.
var port := PORT
## The connection to the lobby server, which keeps the link for the Play screen. The Online
## autoload, unless a test gives another.
var online: Lobby
## Whether a link that comes in brings the window forward and goes to Play (tests turn it off).
var change_scenes := true

var _server: TCPServer
## Connections from games started by a link: each is {"peer", "text", "since"}.
var _incoming: Array[Dictionary] = []


func _ready() -> void:
	if online == null:
		online = get_node_or_null(^"/root/Online") as Lobby
	# Tests and the lobby server run without a window: there is no game to hand links to.
	if DisplayServer.get_name() == "headless":
		return
	if listen():
		return
	if online == null or online.pending_invite.is_empty():
		return
	if await hand_off(online.pending_invite):
		get_tree().quit()


## Starts listening for links, which only the first game open does. Returns whether this game is
## now the one listening (false if another game already is).
func listen() -> bool:
	_server = TCPServer.new()
	if _server.listen(port, "127.0.0.1") != OK:
		_server = null
		return false
	return true


func is_listening() -> bool:
	return _server != null and _server.is_listening()


## Passes a link to the game that is listening. Returns whether it got it.
func hand_off(invite: Dictionary) -> bool:
	var link := InviteLink.make(invite["address"], StringName(invite["room_id"]), invite.get("room_name", ""), invite.get("locked", false))
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", port) != OK:
		return false
	var deadline := Time.get_ticks_msec() + int(HAND_OFF_SECONDS * 1000)
	var sent := false
	var reply := ""
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		match peer.get_status():
			StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
				return false
			StreamPeerTCP.STATUS_CONNECTED:
				if not sent:
					peer.put_data((link + "\n").to_utf8_buffer())
					sent = true
				var available := peer.get_available_bytes()
				if available > 0:
					reply += peer.get_utf8_string(available)
					if reply.begins_with(ACK):
						peer.disconnect_from_host()
						return true
		await get_tree().process_frame
	peer.disconnect_from_host()
	return false


func _process(_delta: float) -> void:
	poll()


## Takes in links from games started by opening them. Called every frame.
func poll() -> void:
	if not is_listening():
		return
	while _server.is_connection_available():
		_incoming.append({"peer": _server.take_connection(), "text": "", "since": Time.get_ticks_msec()})
	for entry in _incoming.duplicate():
		var peer: StreamPeerTCP = entry["peer"]
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			entry["text"] += peer.get_utf8_string(available)
		var text: String = entry["text"]
		var too_old: bool = Time.get_ticks_msec() - int(entry["since"]) > READ_SECONDS * 1000
		if text.contains("\n") or too_old or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_incoming.erase(entry)
			var invite := InviteLink.parse(text.get_slice("\n", 0))
			if not invite.is_empty():
				peer.put_data(ACK.to_utf8_buffer())
				_deliver(invite)
			peer.disconnect_from_host()


func _deliver(invite: Dictionary) -> void:
	received.emit(invite)
	if online != null:
		online.open_invite(invite)
	if not change_scenes:
		return
	var window := get_window()
	if window.mode == Window.MODE_MINIMIZED:
		window.mode = Window.MODE_WINDOWED
	window.grab_focus()
	DisplayServer.window_move_to_foreground()
	# The Play screen follows the link itself; from anywhere else but a room, go there.
	var current := get_tree().current_scene
	var on_play := current != null and current.scene_file_path == PLAY_SCENE
	if not on_play and (online == null or online.room == null):
		get_tree().change_scene_to_file(PLAY_SCENE)


func _exit_tree() -> void:
	if _server != null:
		_server.stop()
	for entry in _incoming:
		(entry["peer"] as StreamPeerTCP).disconnect_from_host()
	_incoming.clear()
