class_name CardLibrary
extends RefCounted
## The player's saved cards. Each card is stored in `directory` as three files:
## <id>.json (the fields), <id>.art.png (the picture) and <id>.png (the rendered card, at
## half size, used for thumbnails).

const DEFAULT_DIRECTORY := "user://cards"
## The official cards that come with the game, in the same format. The player's own library
## (DEFAULT_DIRECTORY) holds the custom cards: the ones they created or imported.
const OFFICIAL_DIRECTORY := "res://official_cards"
const FACE_SIZE := Vector2i(375, 525)

var directory: String


func _init(library_directory: String = DEFAULT_DIRECTORY) -> void:
	directory = library_directory


## Saves the card, giving it an id on first save. `face` is the full-size rendered card.
func save_card(card: CardData, face: Image = null) -> Error:
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	if card.id.is_empty():
		card.id = new_id()

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


## Every saved card by id (id -> CardData).
func load_by_id(with_art := true) -> Dictionary:
	return CardCatalog.by_id(load_cards(with_art))


## A fresh card id.
static func new_id() -> String:
	return Crypto.new().generate_random_bytes(6).hex_encode()


## Adds a card from a PNG made with "Download PNG" (see CardPng) to the library, replacing the
## card with the same id if there is one. Returns the card, or null if the file is not a card.
func import_png(path: String) -> CardData:
	var bytes := FileAccess.get_file_as_bytes(path)
	var card := CardPng.read_card(bytes)
	if card == null:
		return null
	if card.id.is_empty():
		card.id = new_id()
	var face := Image.new()
	if face.load_png_from_buffer(bytes) != OK:
		face = null
	return card if save_card(card, face) == OK else null


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
