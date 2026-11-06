class_name RoomListing
extends Node
## Puts a room hosted on this computer in the room list and keeps it there, for as long as it is
## open:
##
## 1. finds an address others can reach the room at (see Reachability), or failing that, its address
##    on this network;
## 2. adds the room to the list (see RoomBoard.post);
## 3. says every RoomBoard.HEARTBEAT_SECONDS that the room is still there (RoomBoard.touch), which
##    also brings it back if a player wrongly took it off the list;
## 4. takes it off the list when closed (close), and then frees itself.
##
## `note` says where the room stands, in words, for the host.

signal note_changed

## Where the room stands in the list, in words, such as "Adding your room to the list…".
var note := ""
## The room's issue in the list (0 while it is not in it).
var issue := 0
## Whether to look for an address someone far away can use (tests turn it off).
var find_public_address := true

var _board: RoomBoard
var _room: RoomInfo
var _port := 0
var _address := ""
var _local := false
var _reachability: Reachability
var _heartbeat: Timer
var _closed := false


func _init(board: RoomBoard) -> void:
	_board = board


## Starts listing `room`, whose game listens on `port`. Add the listing to the tree first.
func start(room: RoomInfo, port: int) -> void:
	_room = room
	_port = port
	_set_note("Making your room reachable…")
	if not find_public_address:
		_on_address_failed("")
		return
	_reachability = Reachability.new()
	add_child(_reachability)
	_reachability.address_found.connect(_on_address_found)
	_reachability.failed.connect(_on_address_failed)
	_reachability.start(port)


func _on_address_found(address: String, _how: String) -> void:
	# Posting carries on by itself; the note says how it went.
	@warning_ignore("missing_await")
	_post(address, false)


## Without a public address the room can still be joined from the same network.
func _on_address_failed(reason: String) -> void:
	@warning_ignore("missing_await")
	_post(Reachability.local_address(_port), true, reason)


## Takes the room off the list and stops everything, then frees the listing. Await it to know the
## room is off the list.
func close() -> void:
	if _closed:
		return
	_closed = true
	if _heartbeat != null:
		_heartbeat.stop()
	if _reachability != null:
		_reachability.stop()
	var listed := issue
	issue = 0
	if listed > 0:
		await _board.remove(listed)
	queue_free()


## Puts the room in the list with the address to reach it at.
func _post(address: String, local: bool, reason := "") -> void:
	_address = address
	_local = local
	_set_note("Adding your room to the list…")
	var posted := await _board.post(_room, address, local)
	if _closed:
		# The room closed while it was being added.
		if posted > 0:
			await _board.remove(posted)
		return
	issue = posted
	if issue <= 0:
		_set_note("Your room could not be added to the list. " + _board.error_text)
		return
	_heartbeat = Timer.new()
	_heartbeat.wait_time = RoomBoard.HEARTBEAT_SECONDS
	_heartbeat.timeout.connect(_beat)
	add_child(_heartbeat)
	_heartbeat.start()
	if local:
		var local_note := "Your room is in the list, but only players on your own network can join it."
		_set_note(local_note if reason.is_empty() else local_note + " " + reason)
	else:
		_set_note("Your room is in the list. Players see it in Play.")


func _beat() -> void:
	if issue > 0 and not _closed:
		await _board.touch(issue, _room, _address, _local)


func _set_note(new_note: String) -> void:
	note = new_note
	note_changed.emit()
