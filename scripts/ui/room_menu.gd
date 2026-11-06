extends Control
## The room a player has opened or joined: who is in it, and a chat between the two players, which
## is also a way to see that the connection works. (The game itself will take place here.) The host
## of a room that runs on their computer also sees its invite link to send to a friend. Leaving
## goes back to the room list; if the host leaves, the room closes.

const PLAY_SCENE := "res://scenes/play.tscn"
const GOLD := "f2cc73"
const MUTED := "9ea3bd"

## Who the player is online. The Profile autoload, unless a test gives another.
var profile: PlayerProfile = Profile
## The connection to the lobby server. The Online autoload, unless a test gives another.
var online: Lobby = Online
## Whether leaving really goes to the room list (a test turns it off).
var change_scenes := true

var _opponent := ""

@onready var _title_label: Label = %TitleLabel
@onready var _info_label: Label = %InfoLabel
@onready var _you_label: Label = %YouLabel
@onready var _opponent_label: Label = %OpponentLabel
@onready var _chat_log: RichTextLabel = %ChatLog
@onready var _chat_edit: LineEdit = %ChatEdit
@onready var _send_button: Button = %SendButton
@onready var _leave_button: Button = %LeaveButton
@onready var _back_button: Button = %BackButton
@onready var _invite_panel: Control = %InvitePanel
@onready var _link_edit: LineEdit = %LinkEdit
@onready var _copy_link_button: Button = %CopyLinkButton
@onready var _link_note: Label = %LinkNote


func _ready() -> void:
	_back_button.pressed.connect(_leave)
	_leave_button.pressed.connect(_leave)
	_send_button.pressed.connect(_send)
	_chat_edit.text_submitted.connect(func(_text: String) -> void: _send())
	if online.room == null:
		# Nothing to show: the room is gone.
		_leave.call_deferred()
		return
	# A room hosted from this computer shows the link to send to a friend.
	_invite_panel.visible = online.is_player
	_copy_link_button.pressed.connect(_copy_link)
	online.link_changed.connect(_show_link)
	_show_link()
	online.opponent_joined.connect(_on_opponent_joined)
	online.opponent_left.connect(_on_opponent_left)
	online.room_closed.connect(_on_room_closed)
	online.chat_received.connect(_on_chat_received)
	online.state_changed.connect(_on_state_changed)

	var room := online.room
	_title_label.text = room.room_name
	var info := "Hosted by %s  ·  %s" % [room.host_name, room.mode_name()]
	if room.has_password():
		info += "  ·  Password"
	_info_label.text = info
	_you_label.text = "You: %s" % profile.player_name
	_opponent = online.opponent_name
	_show_opponent()
	if _opponent.is_empty():
		_add_system_line("Waiting for another player to join.")
	else:
		_add_system_line("You joined %s." % room.room_name)
	_chat_edit.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_leave()


## Leaves the room (it closes if it is the player's own) and goes back to the room list.
func _leave() -> void:
	online.leave_room()
	_go_to_play()


func _go_to_play() -> void:
	if change_scenes:
		get_tree().change_scene_to_file(PLAY_SCENE)


## Shows the invite link, or that it is being made, with a note if it has a catch.
func _show_link() -> void:
	var has_link := not online.invite_link.is_empty()
	_link_edit.text = online.invite_link
	_link_edit.placeholder_text = "" if has_link else online.link_note
	_copy_link_button.disabled = not has_link
	_link_note.text = online.link_note if has_link else ""
	_link_note.visible = not _link_note.text.is_empty()


func _copy_link() -> void:
	DisplayServer.clipboard_set(online.invite_link)
	_link_note.text = "Copied. Send it to your friend."
	_link_note.visible = true


func _send() -> void:
	var text := _chat_edit.text.strip_edges()
	if text.is_empty():
		return
	_chat_edit.clear()
	if _opponent.is_empty():
		_add_system_line("There is nobody to hear that yet.")
		return
	online.send_chat(text)
	_add_chat_line(profile.player_name, text, GOLD)


func _on_opponent_joined(who: String) -> void:
	_opponent = who
	_show_opponent()
	_add_system_line("%s joined." % who)


func _on_opponent_left() -> void:
	_add_system_line("%s left the room." % _opponent)
	_opponent = ""
	_show_opponent()


## The host left, so there is no room any more: back to the list, which says so.
func _on_room_closed() -> void:
	_go_to_play()


func _on_chat_received(from_name: String, text: String) -> void:
	_add_chat_line(from_name, text, MUTED)


## If the connection to the server goes, so does the room.
func _on_state_changed() -> void:
	if online.state != Lobby.State.CONNECTED:
		online.notice = online.error_text if not online.error_text.is_empty() else "Lost the connection to the server."
		_go_to_play()


func _show_opponent() -> void:
	_opponent_label.text = "Opponent: %s" % _opponent if not _opponent.is_empty() else "Waiting for another player…"


func _add_chat_line(who: String, text: String, color: String) -> void:
	_chat_log.append_text("[color=#%s]%s[/color]: %s\n" % [color, _escape(who), _escape(text)])


func _add_system_line(text: String) -> void:
	_chat_log.append_text("[color=#%s][i]%s[/i][/color]\n" % [MUTED, _escape(text)])


## Text a player typed must not be read as formatting.
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
