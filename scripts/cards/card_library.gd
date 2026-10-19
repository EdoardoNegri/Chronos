class_name CardLibrary
extends RefCounted
## The player's saved cards. Each card is stored in `directory` as three files:
## <id>.json (the fields), <id>.art.png (the picture) and <id>.png (the rendered card, at
## half size, used for thumbnails).

const DEFAULT_DIRECTORY := "user://cards"
const FACE_SIZE := Vector2i(372, 520)

var directory: String


func _init(library_directory: String = DEFAULT_DIRECTORY) -> void:
	directory = library_directory


## Saves the card, giving it an id on first save. `face` is the full-size rendered card.
func save_card(card: CardData, face: Image = null) -> Error:
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	if card.id.is_empty():
		card.id = Crypto.new().generate_random_bytes(6).hex_encode()

	var file := FileAccess.open(_path(card.id, "json"), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(card.to_dict(), "\t"))
	file.close()

	if card.image != null:
		error = card.image.save_png(_path(card.id, "art.png"))
		if error != OK:
			return error
	else:
		_remove(card.id, "art.png")
	if face != null and not face.is_empty():
		var small := face.duplicate() as Image
		small.resize(FACE_SIZE.x, FACE_SIZE.y, Image.INTERPOLATE_LANCZOS)
		error = small.save_png(_path(card.id, "png"))
	return error


## Every saved card, sorted by name. Pass `with_art` = false to skip loading the pictures.
func load_cards(with_art := true) -> Array[CardData]:
	var cards: Array[CardData] = []
	if not DirAccess.dir_exists_absolute(directory):
		return cards
	for file_name in DirAccess.get_files_at(directory):
		if file_name.get_extension() != "json":
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(file_name)))
		if not parsed is Dictionary:
			continue
		var card := CardData.from_dict(parsed)
		if card.id.is_empty():
			continue
		if with_art:
			card.image = _load_image(card.id, "art.png")
		cards.append(card)
	cards.sort_custom(
		func(a: CardData, b: CardData) -> bool: return a.card_name.naturalnocasecmp_to(b.card_name) < 0
	)
	return cards


## The rendered card, or null if it was never saved with one.
func load_face(card_id: String) -> Image:
	return _load_image(card_id, "png")


func delete_card(card_id: String) -> void:
	for extension in ["json", "art.png", "png"]:
		_remove(card_id, extension)


func _path(card_id: String, extension: String) -> String:
	return directory.path_join("%s.%s" % [card_id, extension])


func _load_image(card_id: String, extension: String) -> Image:
	var path := _path(card_id, extension)
	return Image.load_from_file(path) if FileAccess.file_exists(path) else null


func _remove(card_id: String, extension: String) -> void:
	var path := _path(card_id, extension)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
