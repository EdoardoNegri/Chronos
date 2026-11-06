class_name DeckLibrary
extends RefCounted
## The player's saved decks, one JSON file per deck in `directory`.

const DEFAULT_DIRECTORY := "user://decks"

var directory: String


func _init(library_directory: String = DEFAULT_DIRECTORY) -> void:
	directory = library_directory


## Saves the deck under its name, replacing any deck with the same name.
func save_deck(deck: DeckData) -> Error:
	if deck.deck_name.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	var file := FileAccess.open(_path(deck.deck_name), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(deck.to_dict(), "\t"))
	file.close()
	return OK


## The deck with this name, or null if there is none.
func load_deck(deck_name: String) -> DeckData:
	var path := _path(deck_name)
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return DeckData.from_dict(parsed) if parsed is Dictionary else null


## The deck stored in a JSON file somewhere else (such as a saved deck another player sent), or
## null if the file is not a deck. Nothing is saved.
func read_file(path: String) -> DeckData:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary and parsed.has("deck_name") and parsed.get("cards") is Dictionary):
		return null
	return DeckData.from_dict(parsed)


func list_names() -> Array[String]:
	var names: Array[String] = []
	if not DirAccess.dir_exists_absolute(directory):
		return names
	for file_name in DirAccess.get_files_at(directory):
		if file_name.get_extension() != "json":
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(file_name)))
		if parsed is Dictionary and not str(parsed.get("deck_name", "")).is_empty():
			names.append(str(parsed["deck_name"]))
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return names


func delete_deck(deck_name: String) -> Error:
	var path := _path(deck_name)
	return DirAccess.remove_absolute(path) if FileAccess.file_exists(path) else ERR_FILE_NOT_FOUND


func _path(deck_name: String) -> String:
	return directory.path_join("%s.json" % deck_name.strip_edges().validate_filename())
