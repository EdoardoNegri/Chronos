extends Control
## Card database. It opens on a search form: fill in what you are looking for, choose how to
## show and sort the results, and press Search (or Enter in a text field). The results are a page
## of their own; opening a card shows it large on the right, as in Create Cards, with its name,
## time cost, type, subtype, text, attack / defense and deck points on the left, each under a
## caption in a box like the fields of the search form. The back arrow (or Escape) goes from a
## card to the results, from the results back to the form as it was filled in, and from the form
## to the main menu. Clear empties the form.
##
## The search form itself is a CardSearchForm, which the deck builder uses too.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const MODES: Array[String] = ["Images", "Checklist", "Text Only"]
const MODE_IMAGES := 0
const MODE_CHECKLIST := 1
const MODE_TEXT := 2
const SORTS: Array[String] = ["Name", "Time cost", "Attack", "Defense", "Points", "Type"]
const ORDERS: Array[String] = ["Ascending", "Descending"]
## The smallest card image in the Images view; images grow so each row fills the width.
const TILE_SIZE := Vector2(186, 260)
const TILE_GAP := 14
## The narrowest text box in the Text Only view.
const TEXT_BOX_WIDTH := 300.0
const TEXT_BOX_GAP := 14
## Checklist columns: heading and share of the width.
const COLUMNS := [["Name", 3.0], ["Time", 1.0], ["Type", 3.0], ["Atk / Def", 1.0], ["Points", 1.0]]

const INK := Color(0.92, 0.9, 0.85)
const MUTED := Color(0.62, 0.64, 0.74)
const GOLD := Color(0.95, 0.8, 0.45)
const LINE := Color(0.86, 0.7, 0.36, 0.18)
## The value boxes of the card page, the same look as the text fields of the search form.
const FIELD_COLOR := Color(0.05, 0.06, 0.1, 0.9)
const FIELD_LINE := Color(0.86, 0.7, 0.36, 0.3)
const BOX_COLOR := Color(0.11, 0.12, 0.2, 0.9)
const HEADING_COLOR := Color(0.14, 0.15, 0.24, 0.95)
const HOVER := Color(1, 1, 1, 0.05)
const PLACEHOLDER := Color(0.1, 0.11, 0.18)

const NO_CARDS_TEXT := "No cards yet.\nMake some in Create Cards, or import cards there."
const NO_OFFICIAL_TEXT := "No official cards yet.\nChoose Custom cards or Both to search the ones you made or imported."
const NO_CUSTOM_TEXT := "No custom cards yet.\nMake some in Create Cards, or import cards there."
const NO_MATCHES_TEXT := "No cards match this search."

## The cards the player created or imported: the custom cards.
var card_library := CardLibrary.new()
## The official cards that come with the game.
var official_library := CardLibrary.new(CardLibrary.OFFICIAL_DIRECTORY)
var points_list := PointsList.new()

## Official and custom cards together; the catalog says which of them are custom.
var _catalog: CardCatalog
var _cards: Array[CardData] = []
var _faces: Dictionary[String, Texture2D] = {}
var _results: Array[CardData] = []
var _page := "form"
var _flow: HFlowContainer
var _flow_item_width := 0.0
var _flow_item_ratio := 0.0

@onready var _back_button: Button = %BackButton
@onready var _actions: Control = %Actions
@onready var _clear_button: Button = %ClearButton
@onready var _search_button: Button = %SearchButton
@onready var _mode_option: OptionButton = %ModeOption
@onready var _sort_option: OptionButton = %SortOption
@onready var _order_option: OptionButton = %OrderOption
@onready var _form_panel: Control = %FormPanel
@onready var _form: CardSearchForm = %SearchForm
@onready var _results_panel: Control = %ResultsPanel
@onready var _results_scroll: ScrollContainer = %ResultsScroll
@onready var _results_box: VBoxContainer = %Results
@onready var _empty_label: Label = %EmptyLabel
@onready var _detail_body: HBoxContainer = %DetailBody
@onready var _detail_panel: Control = %DetailPanel
@onready var _detail_image: TextureRect = %DetailImage
@onready var _detail_info: VBoxContainer = %DetailInfo


func _ready() -> void:
	for mode in MODES:
		_mode_option.add_item(mode)
	for sort in SORTS:
		_sort_option.add_item(sort)
	for order in ORDERS:
		_order_option.add_item(order)

	_back_button.pressed.connect(_go_back_one_page)
	_search_button.pressed.connect(_search_from_form)
	_clear_button.pressed.connect(_clear_form)
	_form.submitted.connect(_search_from_form)
	_results_box.resized.connect(_fit_flow)
	_detail_body.resized.connect(_fit_detail_image)

	_load_library()
	_show_page("form")
	_form.focus_name()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back_one_page()


## Card page -> results -> search form -> main menu.
func _go_back_one_page() -> void:
	match _page:
		"detail":
			_show_page("results")
		"results":
			_show_page("form")
		_:
			get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Loads the official cards and the player's custom ones.
func _load_library() -> void:
	_catalog = CardCatalog.new(official_library, card_library)
	_cards = _catalog.load_cards(false)
	_form.setup(_cards, _catalog)
	_faces.clear()
	for card in _cards:
		var face := _catalog.load_face(card.id)
		if face != null:
			face.generate_mipmaps()
			_faces[card.id] = ImageTexture.create_from_image(face)


## Shows one page: "form", "results" or "detail".
func _show_page(page: String) -> void:
	_page = page
	_form.close_suggestions()
	# Clear and Search sit under the form and belong to it.
	_actions.visible = page == "form"
	_form_panel.visible = page == "form"
	_results_panel.visible = page == "results"
	_detail_body.visible = page == "detail"


# --- Searching -----------------------------------------------------------------------------


## Filters and sorts the cards by the form, and shows the results page.
func _search_from_form() -> void:
	_results = _form.search(_cards, points_list)
	_results.sort_custom(_comes_first)
	_show_results()
	_show_page("results")


func _clear_form() -> void:
	_form.clear()
	_form.focus_name()


## Why the results are empty: nothing to search in the chosen cards, or nothing that matches.
func _empty_text() -> String:
	if _cards.any(_form.is_searched):
		return NO_MATCHES_TEXT
	match _form.source():
		CardSearchForm.SOURCE_CUSTOM:
			return NO_CUSTOM_TEXT
		CardSearchForm.SOURCE_OFFICIAL:
			if _catalog.has_custom():
				return NO_OFFICIAL_TEXT
	return NO_CARDS_TEXT


func _comes_first(a: CardData, b: CardData) -> bool:
	var a_value: Variant = _sort_value(a)
	var b_value: Variant = _sort_value(b)
	if a_value != b_value:
		return a_value > b_value if _order_option.selected == 1 else a_value < b_value
	return a.card_name.naturalnocasecmp_to(b.card_name) < 0


## The value the chosen sort orders by. Cards without attack and defense count as -1 there.
func _sort_value(card: CardData) -> Variant:
	match SORTS[_sort_option.selected]:
		"Time cost":
			return card.time_cost
		"Attack":
			return card.attack if card.has_stats() else -1
		"Defense":
			return card.defense if card.has_stats() else -1
		"Points":
			return points_list.points_for(card)
		"Type":
			return card.type_line().to_lower()
	return card.card_name.to_lower()


# --- Results -------------------------------------------------------------------------------


func _show_results() -> void:
	for child in _results_box.get_children():
		_results_box.remove_child(child)
		child.queue_free()
	_flow = null
	var empty := _results.is_empty()
	_results_scroll.visible = not empty
	_empty_label.visible = empty
	_empty_label.text = _empty_text()
	if empty:
		return

	match _mode_option.selected:
		MODE_IMAGES:
			_flow = _make_flow(TILE_GAP, TILE_SIZE.x, TILE_SIZE.y / TILE_SIZE.x)
			for card in _results:
				_flow.add_child(_make_tile(card))
		MODE_CHECKLIST:
			_results_box.add_child(_make_checklist_heading())
			for card in _results:
				_results_box.add_child(_make_checklist_row(card))
		MODE_TEXT:
			_flow = _make_flow(TEXT_BOX_GAP, TEXT_BOX_WIDTH, 0.0)
			for card in _results:
				_flow.add_child(_make_text_entry(card))
	_fit_flow()
	_results_scroll.scroll_vertical = 0


func _make_flow(gap: int, item_width: float, item_ratio: float) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", gap)
	flow.add_theme_constant_override("v_separation", gap)
	_flow_item_width = item_width
	_flow_item_ratio = item_ratio
	_results_box.add_child(flow)
	return flow


## Sizes the items of the Images or Text Only view so each row is full: as many as fit at their
## smallest width, then stretched to fill. Images keep the card's proportions.
func _fit_flow() -> void:
	if _flow == null or _results_box.size.x <= 0.0:
		return
	var gap := _flow.get_theme_constant("h_separation")
	var width := _results_box.size.x
	var columns := maxi(1, floori((width + gap) / (_flow_item_width + gap)))
	var item_width := floorf((width - gap * (columns - 1)) / columns)
	var item_height := roundf(item_width * _flow_item_ratio)
	for item: Control in _flow.get_children():
		item.custom_minimum_size = Vector2(item_width, item_height)


## The card image, which opens the card when clicked.
func _make_tile(card: CardData) -> Button:
	var tile := _make_clickable(card)
	var face: Texture2D = _faces.get(card.id)
	if face != null:
		var picture := TextureRect.new()
		picture.texture = face
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_fill(picture)
		tile.add_child(picture)
	else:
		var placeholder := Label.new()
		placeholder.text = card.card_name
		placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.add_theme_color_override("font_color", MUTED)
		placeholder.add_theme_stylebox_override("normal", _box(PLACEHOLDER, LINE, 1, 12))
		_fill(placeholder)
		tile.add_child(placeholder)
	tile.mouse_entered.connect(func() -> void: tile.modulate = Color(1.12, 1.12, 1.12))
	tile.mouse_exited.connect(func() -> void: tile.modulate = Color.WHITE)
	return tile


func _make_checklist_heading() -> PanelContainer:
	var heading := PanelContainer.new()
	heading.add_theme_stylebox_override("panel", _box(HEADING_COLOR, LINE, 0, 8, Vector4(12, 8, 12, 8)))
	var headings: Array[String] = []
	for column: Array in COLUMNS:
		headings.append(column[0])
	heading.add_child(_make_cells(headings, true))
	return heading


func _make_checklist_row(card: CardData) -> Button:
	var row := _make_clickable(card)
	row.custom_minimum_size = Vector2(0, 42)
	var normal := _box(Color(0, 0, 0, 0), LINE, 0, 0)
	normal.border_width_bottom = 1
	var hover := _box(HOVER, LINE, 0, 0)
	hover.border_width_bottom = 1
	row.add_theme_stylebox_override("normal", normal)
	row.add_theme_stylebox_override("hover", hover)
	row.add_theme_stylebox_override("pressed", hover)
	var stats := "%d / %d" % [card.attack, card.defense] if card.has_stats() else ""
	var values: Array[String] = [
		card.card_name, str(card.time_cost), card.type_line(), stats, _points_text(card)
	]
	var cells := _make_cells(values, false)
	_fill(cells)
	cells.offset_left = 12.0
	cells.offset_right = -12.0
	row.add_child(cells)
	return row


func _make_cells(cells: Array[String], heading: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in cells.size():
		var label := Label.new()
		label.text = cells[i]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = COLUMNS[i][1]
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if heading:
			label.add_theme_color_override("font_color", MUTED)
			label.add_theme_font_size_override("font_size", 15)
		else:
			label.add_theme_color_override("font_color", GOLD if i == 0 else INK)
			label.add_theme_font_size_override("font_size", 18)
		row.add_child(label)
	return row


## The card's text box, which opens the card when clicked.
func _make_text_entry(card: CardData) -> Control:
	var entry := _make_card_text_box(card)
	entry.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	entry.tooltip_text = card.card_name
	entry.gui_input.connect(
		func(event: InputEvent) -> void:
			var click := event as InputEventMouseButton
			if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
				_open_card(card.id)
	)
	return entry


func _make_clickable(card: CardData) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = card.card_name
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(_open_card.bind(card.id))
	return button


# --- One card ------------------------------------------------------------------------------


func _open_card(card_id: String) -> void:
	var card := _find_card(card_id)
	if card == null:
		return
	_detail_image.texture = _faces.get(card_id)
	_detail_image.visible = _detail_image.texture != null
	for child in _detail_info.get_children():
		_detail_info.remove_child(child)
		child.queue_free()
	_detail_info.add_child(_make_card_table(card))
	_show_page("detail")
	_fit_detail_image()


func _find_card(card_id: String) -> CardData:
	for card in _cards:
		if card.id == card_id:
			return card
	return null


## Sized like the preview in Create Cards: as wide as a card that fills the full height, leaving
## the info box on the left at least its minimum width, and at most 60% of the row.
func _fit_detail_image() -> void:
	var card_width := _detail_body.size.y * CardView.CARD_SIZE.x / CardView.CARD_SIZE.y
	var room := (
		_detail_body.size.x
		- _detail_panel.get_combined_minimum_size().x
		- _detail_body.get_theme_constant("separation")
	)
	_detail_image.custom_minimum_size.x = maxf(0.0, minf(card_width, minf(room, _detail_body.size.x * 0.6)))


## The card page's info: a field for each entry, laid out like the fields of the search form, with
## its caption above and its value in a box under it. It sits straight in the panel around it.
func _make_card_table(card: CardData) -> VBoxContainer:
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 14)
	fields.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_add_field(fields, "Name", card.card_name)
	_add_field(fields, "Time cost", str(card.time_cost))
	_add_field(fields, "Type", card.card_type)
	if not card.subtype.strip_edges().is_empty():
		_add_field(fields, "Subtype", card.subtype.strip_edges())
	if not card.rules_text.strip_edges().is_empty():
		_add_field(fields, "Text", card.rules_text.strip_edges())
	if card.has_stats():
		_add_field(fields, "Attack / Defense", "%d / %d" % [card.attack, card.defense])
	_add_field(fields, "Deck points", str(points_list.points_for(card)))
	return fields


## One field of the card page: the caption in gold, and the value in a box under it that
## looks like a text field of the search form.
func _add_field(fields: VBoxContainer, caption: String, value: String) -> void:
	var field := VBoxContainer.new()
	field.add_theme_constant_override("separation", 4)
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(_make_text(caption, 17, GOLD))
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", _box(FIELD_COLOR, FIELD_LINE, 1, 8, Vector4(16, 12, 16, 12)))
	box.add_child(_make_text(value, 20, INK))
	field.add_child(box)
	fields.add_child(field)


## The compact box of the Text Only view: name with the time cost clock, type line, card text and
## attack / defense.
func _make_card_text_box(card: CardData) -> PanelContainer:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(BOX_COLOR, LINE, 1, 10))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rows)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _make_text(card.card_name, 20, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var dial := ClockDial.new()
	dial.custom_minimum_size = Vector2.ONE * 32.0
	dial.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dial.accent = CardView.TYPE_ACCENTS.get(card.card_type, CardView.DEFAULT_ACCENT)
	dial.value = card.time_cost
	title_row.add_child(dial)
	_add_box_row(rows, title_row, false)

	_add_box_row(rows, _make_text(card.type_line(), 16, MUTED), true)
	if not card.rules_text.strip_edges().is_empty():
		_add_box_row(rows, _make_text(card.rules_text.strip_edges(), 16, INK), true)
	if card.has_stats():
		_add_box_row(rows, _make_text("%d / %d" % [card.attack, card.defense], 16, INK), true)
	return box


func _add_box_row(rows: VBoxContainer, content: Control, line_above: bool) -> void:
	if line_above:
		var line := ColorRect.new()
		line.color = LINE
		line.custom_minimum_size = Vector2(0, 1)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(line)
	var padding := MarginContainer.new()
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_theme_constant_override("margin_left", 16)
	padding.add_theme_constant_override("margin_right", 16)
	padding.add_theme_constant_override("margin_top", 10)
	padding.add_theme_constant_override("margin_bottom", 10)
	padding.add_child(content)
	rows.add_child(padding)


func _make_text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


# --- Helpers -------------------------------------------------------------------------------


func _points_text(card: CardData) -> String:
	return str(points_list.points_for(card)) if points_list.has_card(card) or card.points > 0 else ""


func _fill(control: Control) -> void:
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE



static func _box(
	fill: Color, border: Color, border_width: int, radius: int, margins := Vector4(-1, -1, -1, -1)
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	if margins.x >= 0.0:
		style.content_margin_left = margins.x
		style.content_margin_top = margins.y
		style.content_margin_right = margins.z
		style.content_margin_bottom = margins.w
	return style
