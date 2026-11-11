class_name DeckRow
extends HBoxContainer
## One card of the deck, in the deck builder's list. A box with the card's name, at its left, and, at
## its right end behind a line that runs the whole height of the box, + over
## − (like the number fields' buttons) to add or take out a copy. Outside the box: how many copies
## the deck has, and what those copies cost in deck points together. The box and the two numbers are
## the same distance apart, and the numbers have a column each (see make_titles for the titles over
## them).
## Click the box to select the card; double-click it or right click it to take a copy out; drag it
## onto the list of cards to take it out (a copy at a time).

signal selected(card_id: String)
## A copy was taken out with a double-click or a right click.
signal removed(card_id: String)
## The number of copies was changed with + or −.
signal copies_changed(card_id: String, copies: int)

const HEIGHT := 40.0
const INK := Color(0.92, 0.9, 0.85)
const GOLD := Color(0.95, 0.8, 0.45)
const ROW_COLOR := Color(0.05, 0.06, 0.1, 0.9)
const SELECTED_COLOR := Color(0.13, 0.14, 0.23, 0.95)
const ROW_LINE := Color(0.86, 0.7, 0.36, 0.2)
## Small enough that the two stacked buttons fit in the row.
const BUTTON_FONT_SIZE := 13
## The space between the box and the copies, and between the copies and their cost, and how wide the
## column of each of the two numbers is.
const GAP := 10
const NUMBER_WIDTH := 46.0
## How far the name starts from the left of the box. The title over the names starts there too.
const NAME_INDENT := 12.0

var card_id := ""
## Which list this row lives in, so drop targets know where a drag came from.
var source: StringName = &""
## The row of the card shown in the card panel.
var highlighted := false:
	set(value):
		highlighted = value
		_apply_style()
## How many copies of the card the deck has.
var copies := 0

var _box: PanelContainer
var _name_label: Label
## The line between the name and + / −.
var _divider: ColorRect
var _plus_button: Button
var _minus_button: Button
var _count_label: Label
var _total_label: Label
## What one copy costs in deck points.
var _points_each := 0
var _hovered := false


## The titles over the columns of the list: the card, its copies and their cost in points. They are
## made here so that they line up with the rows.
static func make_titles() -> HBoxContainer:
	var titles := HBoxContainer.new()
	titles.add_theme_constant_override("separation", GAP)
	var card := _make_title("Card", HORIZONTAL_ALIGNMENT_LEFT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var indent := StyleBoxEmpty.new()
	indent.content_margin_left = NAME_INDENT
	card.add_theme_stylebox_override("normal", indent)
	titles.add_child(card)
	for text in ["Copies", "Points"]:
		var title := _make_title(text, HORIZONTAL_ALIGNMENT_CENTER)
		title.custom_minimum_size.x = NUMBER_WIDTH
		titles.add_child(title)
	return titles


static func _make_title(text: String, alignment: HorizontalAlignment) -> Label:
	var title := Label.new()
	title.text = text
	title.theme_type_variation = &"FieldLabel"
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = alignment
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return title


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	# PASS, not STOP, so the wheel still scrolls the list and drops reach the list behind.
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_constant_override("separation", GAP)

	_box = PanelContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_style()
	_box.gui_input.connect(_on_box_input)
	_box.mouse_entered.connect(_set_hovered.bind(true))
	_box.mouse_exited.connect(_set_hovered.bind(false))
	_box.set_drag_forwarding(_get_box_drag_data, Callable(), Callable())
	add_child(_box)

	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 10)
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(cells)
	_name_label = _make_label(17, INK)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cells.add_child(_name_label)

	# A vertical line from the top of the box to its bottom, right against + stacked over −, which
	# are split by a horizontal line that starts at it, as in a number field. (Nothing between
	# them: the space of the row would push the line away from the buttons.)
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 0)
	cells.add_child(steps)
	_divider = _make_line(Vector2(1, 0))
	steps.add_child(_divider)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 0)
	steps.add_child(buttons)
	_plus_button = _make_button("+", "Add a copy", 1)
	buttons.add_child(_plus_button)
	buttons.add_child(_make_line(Vector2(0, 1)))
	_minus_button = _make_button("−", "Take a copy out", -1)
	buttons.add_child(_minus_button)

	_count_label = _make_label(20, GOLD)
	_count_label.custom_minimum_size = Vector2(NUMBER_WIDTH, 0)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.tooltip_text = "Copies in the deck"
	_count_label.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_count_label)

	_total_label = _make_label(18, INK)
	_total_label.custom_minimum_size = Vector2(NUMBER_WIDTH, 0)
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total_label.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_total_label)


## `points_each` is what one copy costs in deck points.
func setup(id: String, display_name: String, copy_count: int, points_each: int) -> void:
	card_id = id
	_box.tooltip_text = display_name
	_name_label.text = display_name
	_points_each = points_each
	copies = copy_count
	_show_copies()


## Changes the number of copies (as + and − do), within what a deck can have.
func set_copies(count: int) -> void:
	var new_count := clampi(count, 0, DeckData.MAX_COPIES)
	if new_count == copies:
		return
	copies = new_count
	_show_copies()
	copies_changed.emit(card_id, copies)


## The number of copies, their total cost in deck points, and whether + can still add one.
func _show_copies() -> void:
	_count_label.text = str(copies)
	_total_label.text = str(_points_each * copies)
	_total_label.tooltip_text = "Deck points of these copies (%d each)" % _points_each
	_plus_button.disabled = copies >= DeckData.MAX_COPIES


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## A divider in the border color of the box: `thickness` is (1, 0) for vertical, (0, 1) for
## horizontal.
func _make_line(thickness: Vector2) -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size = thickness
	line.color = ROW_LINE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _make_button(symbol: String, tip: String, change: int) -> Button:
	var button := Button.new()
	button.text = symbol
	button.tooltip_text = tip
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(22, 0)
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	# No padding, so the buttons are no taller than the row.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(func() -> void: set_copies(copies + change))
	return button


func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	_apply_style()


## The box has no room of its own above, below and at the right of what is in it, but its border, so
## the line and the buttons fill it right up to that. The name starts NAME_INDENT from the left.
func _apply_style() -> void:
	if _box == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = SELECTED_COLOR if highlighted or _hovered else ROW_COLOR
	style.border_color = ROW_LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = NAME_INDENT
	style.content_margin_right = 1.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	_box.add_theme_stylebox_override("panel", style)


func _on_box_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_LEFT:
		if click.double_click:
			removed.emit(card_id)
		else:
			selected.emit(card_id)
	elif click.button_index == MOUSE_BUTTON_RIGHT:
		removed.emit(card_id)


func _get_box_drag_data(_at_position: Vector2) -> Variant:
	selected.emit(card_id)
	var preview := PanelContainer.new()
	var label := _make_label(18, INK)
	label.text = _name_label.text
	preview.add_child(label)
	preview.modulate.a = 0.85
	_box.set_drag_preview(preview)
	return {"card_id": card_id, "from": source}
