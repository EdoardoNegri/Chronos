extends RefCounted
## What the Dev Refresh plugin looks at: the signal file the Stop hook writes when Claude finishes,
## and the files that make up the game. (Its own class, so it can be tested without an editor.)

## The folders and files that make up the game. Changes to anything else (the tests, the docs, the
## editor's own files) do not count.
const DEFAULT_FOLDERS: Array[String] = ["scripts", "scenes", "assets", "official_cards"]
const DEFAULT_FILES: Array[String] = ["project.godot", "points_list.json"]
## Written by the Stop hook of .claude/settings.json.
const DEFAULT_SIGNAL_FILE := "res://.godot/claude_done"
## Files the editor makes by itself.
const IGNORED_EXTENSIONS: Array[String] = ["import", "uid", "tmp"]

var root: String
var folders: Array[String]
var files: Array[String]
var signal_file: String


func _init(
	project_root := "res://",
	watched_folders := DEFAULT_FOLDERS,
	watched_files := DEFAULT_FILES,
	signal_path := DEFAULT_SIGNAL_FILE
) -> void:
	root = project_root
	folders = watched_folders
	files = watched_files
	signal_file = signal_path


## When the signal file was last written (0 if it never was).
func signal_time() -> int:
	return FileAccess.get_modified_time(ProjectSettings.globalize_path(signal_file))


## A number that changes whenever one of the game's files is added, removed or saved again.
func fingerprint() -> int:
	var entries := PackedStringArray()
	for folder in folders:
		_collect(root.path_join(folder), entries)
	for file in files:
		_add_entry(root.path_join(file), entries)
	return "\n".join(entries).hash()


func _collect(folder: String, entries: PackedStringArray) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for sub_folder in dir.get_directories():
		_collect(folder.path_join(sub_folder), entries)
	for file in dir.get_files():
		if not IGNORED_EXTENSIONS.has(file.get_extension()):
			_add_entry(folder.path_join(file), entries)


func _add_entry(path: String, entries: PackedStringArray) -> void:
	var modified := FileAccess.get_modified_time(path)
	if modified != 0:
		entries.append("%s:%d" % [path, modified])
