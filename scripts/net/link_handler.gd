class_name LinkHandler
extends RefCounted
## Makes Windows open chronos:// links with this game, so that a friend who clicks an invite link
## gets the game started and taken into the room. It adds one entry for the current user in the
## registry (HKCU, so no administrator rights); unregister() takes it away again.
##
## Windows runs `<this game> -- "<the link>"`, and the game finds the link among its arguments (see
## Lobby and InviteLink).

var scheme: String


func _init(link_scheme: String = InviteLink.SCHEME) -> void:
	scheme = link_scheme


## Only Windows is handled here.
func is_supported() -> bool:
	return OS.get_name() == "Windows"


## The command Windows should run for a link. From the editor, it has to name the project too.
func command() -> String:
	var program := OS.get_executable_path().replace("/", "\\")
	if OS.has_feature("editor"):
		var project := ProjectSettings.globalize_path("res://").trim_suffix("/").replace("/", "\\")
		return "\"%s\" --path \"%s\" -- \"%%1\"" % [program, project]
	return "\"%s\" -- \"%%1\"" % program


## Whether links are set up to open this game.
func is_registered() -> bool:
	if not is_supported():
		return false
	var output: Array = []
	var code := OS.execute("reg", ["query", _key("shell\\open\\command"), "/ve"], output)
	return code == 0 and not output.is_empty() and str(output[0]).contains(command())


## Sets links up to open this game. Returns OK, or an error.
func register() -> Error:
	if not is_supported():
		return ERR_UNAVAILABLE
	# The entries go in through a .reg file: the command has quotes in it, which a command line
	# does not carry over to the registry correctly.
	var reg_path := "user://link_setup.reg"
	var file := FileAccess.open(reg_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	# Registry files are UTF-16 with a byte order mark, so paths with accents survive.
	file.store_buffer(PackedByteArray([0xFF, 0xFE]))
	file.store_buffer(_reg_file_text().to_utf16_buffer())
	file.close()
	var code := OS.execute("reg", ["import", ProjectSettings.globalize_path(reg_path)], [])
	DirAccess.remove_absolute(reg_path)
	return OK if code == 0 else FAILED


## Takes the setup away again.
func unregister() -> Error:
	if not is_supported():
		return ERR_UNAVAILABLE
	return OK if OS.execute("reg", ["delete", _key(""), "/f"], []) == 0 else FAILED


## The registry entries as the text of a .reg file.
func _reg_file_text() -> String:
	var escaped_command := command().replace("\\", "\\\\").replace("\"", "\\\"")
	var lines := [
		"Windows Registry Editor Version 5.00",
		"",
		"[%s]" % _key("").replace("HKCU", "HKEY_CURRENT_USER"),
		"@=\"URL:%s link\"" % scheme,
		"\"URL Protocol\"=\"\"",
		"",
		"[%s]" % _key("shell\\open\\command").replace("HKCU", "HKEY_CURRENT_USER"),
		"@=\"%s\"" % escaped_command,
		"",
	]
	return "\r\n".join(lines)


func _key(sub_key: String) -> String:
	var key := "HKCU\\Software\\Classes\\" + scheme
	return key if sub_key.is_empty() else key + "\\" + sub_key
