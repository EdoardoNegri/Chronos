@tool
extends EditorPlugin
## Opens two Godotty terminals as tabs in the far-left dock: one running
## Claude Code, one plain shell. Godotty never creates terminals on its own at
## startup, so a saved editor layout alone cannot restore them.
##
## Requires the Godotty GDExtension (res://addons/godotty), which provides the
## `Terminal` control.

const SLOT := EditorDock.DOCK_SLOT_LEFT_UL

var _docks: Array[EditorDock] = []


func _enter_tree() -> void:
	if not ClassDB.class_exists("Terminal"):
		push_warning("Dev Terminals: Godotty's 'Terminal' class is missing; no terminals opened.")
		return
	_docks.append(_make_dock("Claude", _find_claude(), false))
	_docks.append(_make_dock("Shell", "", true))
	for dock in _docks:
		add_dock(dock)
	_close_godotty_bottom_panel()


func _exit_tree() -> void:
	for dock in _docks:
		remove_dock(dock)
		dock.queue_free()
	_docks.clear()


## Godotty always registers a "Terminal" bottom-panel dock and marks it
## non-closable, so no saved layout can hide it. Close it here instead (it is
## closed again on every editor launch).
func _close_godotty_bottom_panel() -> void:
	# Godotty's plugin may enter the tree after this one, so retry for a bit.
	for _attempt in 30:
		await get_tree().process_frame
		for dock in EditorInterface.get_base_control().find_children("*", "EditorDock", true, false):
			if dock.default_slot == EditorDock.DOCK_SLOT_BOTTOM and dock.title == "Terminal" \
					and dock.get_child_count() > 0 and dock.get_child(0).is_class("TerminalTabs"):
				dock.closable = true
				dock.close()
				return


## `shell` is a program with no arguments (empty = Godotty's configured/auto
## shell). `login_shell` makes Godotty pass `-l`, which only suits real shells.
func _make_dock(title: String, shell: String, login_shell: bool) -> EditorDock:
	var terminal: Control = ClassDB.instantiate("Terminal")
	terminal.set("run_in_editor", true)
	terminal.set("shell", shell)
	terminal.set("login_shell", login_shell)

	var dock := EditorDock.new()
	dock.title = title
	dock.default_slot = SLOT
	dock.add_child(terminal)
	return dock


func _find_claude() -> String:
	var windows := OS.get_name() == "Windows"
	var exe := "claude.exe" if windows else "claude"
	for dir in OS.get_environment("PATH").split(";" if windows else ":", false):
		var candidate := dir.path_join(exe)
		if FileAccess.file_exists(candidate):
			return candidate
	return "claude"
