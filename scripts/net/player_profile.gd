class_name PlayerProfile
extends Node
## Who the player is when they play online: just a name. There is no email and no password, so the
## first time they go online they only pick a name, and they can change it in the settings. The
## profile also remembers which lobby server to use. It is kept in a small file, so it is still
## there the next time the game starts.
##
## Registered as the `Profile` autoload.

signal name_changed(new_name: String)

const DEFAULT_PATH := "user://profile.cfg"
const MAX_NAME_LENGTH := 20
## Where the lobby server is until the player says otherwise: this computer. There is no public
## server yet, so to play with someone else one of you runs the server (see Lobby) and both put its
## address in the settings.
const DEFAULT_SERVER_URL := "ws://127.0.0.1:9080"

var path: String
## Empty until the player has picked a name (that is, has no account yet).
var player_name := ""
var server_url := DEFAULT_SERVER_URL

var _file := ConfigFile.new()


func _init(profile_path: String = DEFAULT_PATH) -> void:
	path = profile_path
	if _file.load(path) == OK:
		player_name = str(_file.get_value("profile", "name", "")).strip_edges()
		var saved_server := str(_file.get_value("online", "server", "")).strip_edges()
		if not saved_server.is_empty():
			server_url = saved_server


## Whether the player has picked a name yet.
func has_account() -> bool:
	return not player_name.is_empty()


## An error message if `name_to_check` cannot be a name, or an empty string if it can.
static func validate_name(name_to_check: String) -> String:
	var trimmed := name_to_check.strip_edges()
	if trimmed.is_empty():
		return "Pick a name."
	if trimmed.length() > MAX_NAME_LENGTH:
		return "Names can be at most %d characters." % MAX_NAME_LENGTH
	return ""


## Sets the name and keeps it for next time. Returns an error message, or an empty string if the
## name was accepted.
func set_player_name(new_name: String) -> String:
	var error := validate_name(new_name)
	if not error.is_empty():
		return error
	var trimmed := new_name.strip_edges()
	_file.set_value("profile", "name", trimmed)
	error = _save()
	if not error.is_empty():
		return error
	if trimmed != player_name:
		player_name = trimmed
		name_changed.emit(player_name)
	return ""


## Sets the address of the lobby server and keeps it. Empty goes back to the default. Returns an
## error message, or an empty string.
func set_server_url(new_url: String) -> String:
	var trimmed := new_url.strip_edges()
	if trimmed.is_empty():
		trimmed = DEFAULT_SERVER_URL
	_file.set_value("online", "server", trimmed)
	var error := _save()
	if error.is_empty():
		server_url = trimmed
	return error


func _save() -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return "" if _file.save(path) == OK else "Could not save your settings."
