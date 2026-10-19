extends Control
## Deck builder, laid out like EDOPro's: the selected card on the left, the deck in the middle
## and the searchable card list on the right.
##
## Double-click or right-click a card in the list to add it, and the same on a deck card to
## remove it. Cards can also be dragged between the two.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const NEW_DECK_TEXT := "New deck"
const ALL_TYPES_TEXT := "All types"
const SOURCE_DECK := &"deck"
const SOURCE_RESULTS := &"results"
const STATUS_COLOR := Color(0.62, 0.64, 0.74)
const ERROR_COLOR := Color(0.9, 0.5, 0.45)
const SUCCESS_COLOR := Color(0.5, 0.82, 0.55)
const INK_COLOR := Color(0.92, 0.9, 0.85)
const NO_CARDS_TEXT := "No cards in your library yet.\nMake some in Create Cards and save them."

var card_library := CardLibrary.new()
var deck_library := DeckLibrary.new()

var _cards: Array[CardData] = []
var _cards_by_id: Dictionary[String, CardData] = {}
var _textures: Dictionary[String, Texture2D] = {}
var _deck := DeckData.new()
var _selected_id := ""
var _result_thumbs: Dictionary[String, CardThumb] = {}

@onready var _back_button: Button = %BackButton
@onready var _preview: TextureRect = %Preview
@onready var _details: RichTextLabel = %Details
@onready var _deck_option: OptionButton = %DeckOption
@onready var _name_edit: LineEdit = %NameEdit
@onready var _save_button: Button = %SaveButton
@onready var _delete_button: Button = %DeleteButton
@onready var _clear_button: Button = %ClearButton
@onready var _count_label: Label = %CountLabel
@onready var _points_label: Label = %PointsLabel
@onready var _validity_label: Label = %ValidityLabel
@onready var _deck_scroll: ScrollContainer = %DeckScroll
@onready var _deck_grid: HFlowContainer = %DeckGrid
@onready var _status: Label = %Status
@onready var _search_edit: LineEdit = %SearchEdit
@onready var _type_filter: OptionButton = %TypeFilter
@onready var _result_count: Label = %ResultCount
@onready var _result_scroll: ScrollContainer = %ResultScroll
@onready var _result_grid: HFlowContainer = %ResultGrid
@onready var _empty_label: Label = %EmptyLabel


func _ready() -> void:
	_back_button.pressed.connect(_go_back)
	_search_edit.text_changed.connect(func(_text: String) -> void: _refresh_results())
	_type_filter.item_selected.connect(func(_index: int) -> void: _refresh_results())
	_deck_option.item_selected.connect(_on_deck_option_selected)
	_name_edit.text_changed.connect(func(text: String) -> void: _deck.deck_name = text)
	_save_button.pressed.connect(_save_deck)
	_delete_button.pressed.connect(_delete_deck)
	_clear_button.pressed.connect(_clear_deck)
	_deck_scroll.set_drag_forwarding(Callable(), _can_drop_on_deck, _drop_on_deck)
	_result_scroll.set_drag_forwarding(Callable(), _can_drop_on_results, _drop_on_results)

	_type_filter.add_item(ALL_TYPES_TEXT)
	for card_type in CardData.TYPES:
		_type_filter.add_item(card_type)

	_load_library()
	_refresh_deck_options()
	_refresh_results()
	_refresh_deck()
	_show_details("")
	_search_edit.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


func _go_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# --- Library -------------------------------------------------------------------------------


func _load_library() -> void:
	_cards = card_library.load_cards(false)
	for card in _cards:
		_cards_by_id[card.id] = card
		var face := card_library.load_face(card.id)
		if face != null:
			face.generate_mipmaps()
			_textures[card.id] = ImageTexture.create_from_image(face)


func _make_thumb(card_id: String, source: StringName) -> CardThumb:
	var card: CardData = _cards_by_id.get(card_id)
	var thumb := CardThumb.new()
	thumb.source = source
	thumb.setup(card_id, card.card_name if card != null else "Missing card", _textures.get(card_id))
	thumb.selected.connect(_select)
	return thumb


func _clear_children(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


# --- Card list (right) ---------------------------------------------------------------------


func _refresh_results() -> void:
	_clear_children(_result_grid)
	_result_thumbs.clear()
	var query := _search_edit.text.strip_edges().to_lower()
	var type_index := _type_filter.selected
	for card in _cards:
		if type_index > 0 and card.card_type != CardData.TYPES[type_index - 1]:
			continue
		if not query.is_empty() and not _matches(card, query):
			continue
		var thumb := _make_thumb(card.id, SOURCE_RESULTS)
		thumb.activated.connect(_add_card)
		thumb.context_clicked.connect(_add_card)
		_result_grid.add_child(thumb)
		_result_thumbs[card.id] = thumb

	var has_library := not _cards.is_empty()
	var has_results := not _result_thumbs.is_empty()
	_result_scroll.visible = has_results
	_empty_label.visible = not has_results
	_empty_label.text = NO_CARDS_TEXT if not has_library else "No cards match your search."
	_result_count.text = "%d of %d cards" % [_result_thumbs.size(), _cards.size()]
	_update_badges()
	_apply_highlight()


func _matches(card: CardData, query: String) -> bool:
	return (
		card.card_name.to_lower().contains(query)
		or card.subtype.to_lower().contains(query)
		or card.rules_text.to_lower().contains(query)
	)


func _update_badges() -> void:
	for card_id in _result_thumbs:
		_result_thumbs[card_id].set_copies(_deck.copies(card_id))


# --- Deck (middle) -------------------------------------------------------------------------


func _refresh_deck() -> void:
	_clear_children(_deck_grid)
	for card_id in _deck.sorted_ids(_cards_by_id):
		var thumb := _make_thumb(card_id, SOURCE_DECK)
		thumb.activated.connect(_remove_card)
		thumb.context_clicked.connect(_remove_card)
		_deck_grid.add_child(thumb)

	var problems := _deck.problems(_cards_by_id)
	var used := _deck.used_points(_cards_by_id)
	var usable := _deck.usable_points()
	_count_label.text = "Cards: %d" % _deck.size()
	_points_label.text = "Points: %d / %d" % [used, usable]
	_count_label.add_theme_color_override(
		"font_color", INK_COLOR if _deck.size() >= DeckData.MIN_SIZE else ERROR_COLOR
	)
	_points_label.add_theme_color_override("font_color", INK_COLOR if used <= usable else ERROR_COLOR)
	if problems.is_empty():
		_validity_label.text = "Legal deck"
		_validity_label.add_theme_color_override("font_color", SUCCESS_COLOR)
	else:
		_validity_label.text = " · ".join(problems)
		_validity_label.add_theme_color_override("font_color", ERROR_COLOR)
	_validity_label.tooltip_text = "\n".join(problems)

	_update_badges()
	_apply_highlight()
	if not _selected_id.is_empty():
		_show_details(_selected_id)


func _add_card(card_id: String) -> void:
	_select(card_id)
	if not _deck.add(card_id):
		var card: CardData = _cards_by_id.get(card_id)
		_show_status(
			"A deck can have at most %d copies of “%s”." % [DeckData.MAX_COPIES, card.card_name],
			ERROR_COLOR
		)
		return
	_show_status("", STATUS_COLOR)
	_refresh_deck()


func _remove_card(card_id: String) -> void:
	if _deck.remove(card_id):
		_refresh_deck()


func _clear_deck() -> void:
	_deck.clear()
	_show_status("", STATUS_COLOR)
	_refresh_deck()


func _can_drop_on_deck(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("from") == SOURCE_RESULTS


func _drop_on_deck(_at_position: Vector2, data: Variant) -> void:
	_add_card(data["card_id"])


func _can_drop_on_results(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("from") == SOURCE_DECK


func _drop_on_results(_at_position: Vector2, data: Variant) -> void:
	_remove_card(data["card_id"])


# --- Saved decks ---------------------------------------------------------------------------


## Fills the deck picker. Selects `select_name` if it is saved, otherwise "New deck".
func _refresh_deck_options(select_name := "") -> void:
	_deck_option.clear()
	_deck_option.add_item(NEW_DECK_TEXT)
	var names := deck_library.list_names()
	for deck_name in names:
		_deck_option.add_item(deck_name)
	_deck_option.select(names.find(select_name) + 1)


func _on_deck_option_selected(index: int) -> void:
	if index == 0:
		_set_deck(DeckData.new())
		return
	var deck_name := _deck_option.get_item_text(index)
	var deck := deck_library.load_deck(deck_name)
	if deck == null:
		_show_status("Could not open “%s”." % deck_name, ERROR_COLOR)
		return
	_set_deck(deck)
	_show_status("Opened “%s”." % deck_name, STATUS_COLOR)


func _set_deck(deck: DeckData) -> void:
	_deck = deck
	_name_edit.text = deck.deck_name
	_show_status("", STATUS_COLOR)
	_refresh_deck()


func _save_deck() -> void:
	_deck.deck_name = _name_edit.text.strip_edges()
	var error := deck_library.save_deck(_deck)
	if error == ERR_INVALID_PARAMETER:
		_show_status("Give the deck a name first.", ERROR_COLOR)
		_name_edit.grab_focus()
	elif error != OK:
		_show_status("Could not save the deck (%s)." % error_string(error), ERROR_COLOR)
	else:
		_refresh_deck_options(_deck.deck_name)
		var legal := _deck.problems(_cards_by_id).is_empty()
		_show_status(
			"Saved “%s”." % _deck.deck_name if legal else "Saved “%s”, but it is not legal yet." % _deck.deck_name,
			SUCCESS_COLOR
		)


func _delete_deck() -> void:
	if _deck_option.selected == 0:
		_show_status("Pick a saved deck to delete it.", ERROR_COLOR)
		return
	var deck_name := _deck_option.get_item_text(_deck_option.selected)
	if deck_library.delete_deck(deck_name) != OK:
		_show_status("Could not delete “%s”." % deck_name, ERROR_COLOR)
		return
	_refresh_deck_options()
	_set_deck(DeckData.new())
	_show_status("Deleted “%s”." % deck_name, STATUS_COLOR)


# --- Card details (left) -------------------------------------------------------------------


func _select(card_id: String) -> void:
	_selected_id = card_id
	_show_details(card_id)
	_apply_highlight()


func _apply_highlight() -> void:
	for grid: Container in [_deck_grid, _result_grid]:
		for thumb: CardThumb in grid.get_children():
			thumb.highlighted = thumb.card_id == _selected_id


func _show_details(card_id: String) -> void:
	var card: CardData = _cards_by_id.get(card_id)
	_preview.texture = _textures.get(card_id)
	if card == null:
		_details.text = "[color=#9ea3bd]Select a card to see it here.[/color]"
		return
	var text := "[font_size=22][color=#f2cc73]%s[/color][/font_size]\n" % _escape(card.card_name)
	text += "[color=#9ea3bd]%s[/color]\n" % _escape(card.type_line())
	text += "Time cost %d   ·   Points %d\n" % [card.time_cost, card.points]
	if card.has_stats():
		text += "Attack %d   ·   Defense %d\n" % [card.attack, card.defense]
	text += "In deck: %d / %d\n\n" % [_deck.copies(card_id), DeckData.MAX_COPIES]
	text += _escape(card.rules_text)
	_details.text = text


func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _show_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
