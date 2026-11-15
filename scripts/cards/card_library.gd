class_name CardLibrary
extends RefCounted
## A library of cards, kept in `directory`:
##
##   cards.json      every card's fields, one entry per card, sorted by name: open it to change a
##                   card or to look one up (search with Ctrl+F)
##   <id>.png        the rendered card, at half size, used for thumbnails
##   <id>.art.png    the card's picture, when it has one
##
## The official cards that come with the game are in OFFICIAL_DIRECTORY; the player's own cards (the
## ones they created or imported) are in DEFAULT_DIRECTORY. Pictures are read only when asked for,
## so a big library loads as quickly as a small one.
##
## The official cards can only be changed in the editor: in the exported game they are packed inside
## the exe, and the library refuses to change them (`read_only`). A custom card with the id of an
## official card does not replace it either (see CardCatalog).
##
## Libraries saved before cards.json kept each card's fields in its own <id>.json; they are moved
## into cards.json the first time the library is read.

const DEFAULT_DIRECTORY := "user://cards"
const OFFICIAL_DIRECTORY := "res://official_cards"
const CARDS_FILE := "cards.json"
const FACE_SIZE := Vector2i(375, 525)

var directory: String
## Whether the cards cannot be changed: saving, importing and deleting do nothing. True for a library
## inside the game (res://, the official cards) when it runs outside the editor.
var read_only: bool


func _init(library_directory: String = DEFAULT_DIRECTORY) -> void:
	directory = library_directory
	read_only = directory.begins_with("res://") and not OS.has_feature("editor")


## Saves the card, giving it an id on first save. `face` is the full-size rendered card.
func save_card(card: CardData, face: Image = null) -> Error:
	if read_only:
		return ERR_FILE_NO_PERMISSION
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	if card.id.is_empty():
		card.id = new_id()
	var cards := load_cards(false).filter(func(each: CardData) -> bool: return each.id != card.id)
	cards.append(card)
	error = _write_cards(cards)
	if error != OK:
		return error

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
	var path := directory.path_join(CARDS_FILE)
	var entries: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else _move_old_files()
	if not entries is Array:
		return cards
	for entry: Variant in entries:
		if not entry is Dictionary:
			continue
		var card := CardData.from_dict(entry)
		if card.id.is_empty():
			continue
		if with_art:
			card.image = _load_image(card.id, "art.png")
		cards.append(card)
	_sort(cards)
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
	if read_only:
		return null
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


## Removes the card and its pictures. A library left empty has no cards.json either.
func delete_card(card_id: String) -> void:
	if read_only:
		return
	var cards := load_cards(false).filter(func(each: CardData) -> bool: return each.id != card_id)
	if cards.is_empty():
		DirAccess.remove_absolute(directory.path_join(CARDS_FILE))
	else:
		_write_cards(cards)
	for extension in ["art.png", "png"]:
		_remove(card_id, extension)


static func _sort(cards: Array) -> void:
	cards.sort_custom(
		func(a: CardData, b: CardData) -> bool: return a.card_name.naturalnocasecmp_to(b.card_name) < 0
	)


## Writes cards.json, sorted by name, each card's fields in the order they are printed.
func _write_cards(cards: Array) -> Error:
	_sort(cards)
	var entries := cards.map(func(card: CardData) -> Dictionary: return card.to_dict())
	var file := FileAccess.open(directory.path_join(CARDS_FILE), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(entries, "\t", false) + "\n")
	file.close()
	return OK


## Reads the cards of a library saved before cards.json (one <id>.json per card) and, where the
## library can be written, moves them into cards.json. Returns the cards' fields (empty if none).
func _move_old_files() -> Array:
	var entries := []
	var old_files: Array[String] = []
	for file_name in DirAccess.get_files_at(directory):
		if file_name.get_extension() != "json" or file_name == CARDS_FILE:
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(file_name)))
		if parsed is Dictionary:
			entries.append(parsed)
			old_files.append(file_name)
	if entries.is_empty() or read_only:
		return entries
	var cards: Array[CardData] = []
	for entry: Dictionary in entries:
		cards.append(CardData.from_dict(entry))
	if _write_cards(cards) == OK:
		for file_name in old_files:
			DirAccess.remove_absolute(directory.path_join(file_name))
	return entries


func _path(card_id: String, extension: String) -> String:
	return directory.path_join("%s.%s" % [card_id, extension])


## A picture of the card. Inside the game (res://) the pictures are imported, and in the exported game
## only the imported copy is there, so they are read as resources; elsewhere straight from the file.
func _load_image(card_id: String, extension: String) -> Image:
	var path := _path(card_id, extension)
	if path.begins_with("res://"):
		var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
		return texture.get_image() if texture != null else null
	return Image.load_from_file(path) if FileAccess.file_exists(path) else null


func _remove(card_id: String, extension: String) -> void:
	var path := _path(card_id, extension)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
