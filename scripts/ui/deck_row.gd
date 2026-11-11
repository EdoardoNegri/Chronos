class_name DeckRow
extends PanelContainer
## One card of the deck, in the deck builder's list: a stripe in the card type's color, the name,
## the time cost, and how many copies the deck has, with − and + to take one away or add one.
## Click selects it, double-click or right click takes a copy out, and it can be dragged onto the
## list of cards to take it out (a copy at a time).

signal selected(card_id: String)
## A copy was asked for or taken out (by the buttons, a double-click or a right click).
signal added(card_id: String)
signal removed(card_id: String)

const HEIGHT := 42.0
const INK := Color(0.92, 0.9, 0.85)
const MUTED := Color(0.62, 0.64, 0.74)
const GOLD := Color(0.95, 0.8, 0.45)
const ROW_COLOR := Color(0.05, 0.06, 0.1, 0.9)
const SELECTED_COLOR := Color(0.13, 0.14, 0.23, 0.95)
const ROW_LINE := Color(0.86, 0.7, 0.36, 0.2)
const HOVER_COLOR := Color(1, 1, 1, 0.07)

var card_id := ""
## Which list this row lives in, so drop targets know where a drag came from.
var source: StringName = &""
## The row of the card shown in the card panel.
var highlighted := false:
	set(value):
		highlighted = value
		_apply_style()

var _stripe: ColorRect
var _name_label: Label
var _cost_label: Label
var _count_label: Label
var _minus_button: Button
var _plus_button: Button
var _hovered := false


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	# PASS, not STOP, so the wheel still scrolls the list and drops reach the list behind.
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_style()

	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 6)
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cells)

	_stripe = ColorRect.new()
	_stripe.custom_minimum_size = Vector2(4, 0)
	_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cells.add_child(_stripe)

	_name_label = _make_label(17, INK)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cells.add_child(_name_label)

	_cost_label = _make_label(16, MUTED)
	_cost_label.custom_minimum_size = Vector2(26, 0)
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cost_label.tooltip_text = "Time cost"
	cells.add_child(_cost_label)

	_minus_button = _make_step_button("−", "Take a copy out")
	_minus_button.pressed.connect(func() -> void: removed.emit(card_id))
	cells.add_child(_minus_button)

	_count_label = _make_label(18, GOLD)
	_count_label.custom_minimum_size = Vector2(30, 0)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cells.add_child(_count_label)

	_plus_button = _make_step_button("+", "Add a copy")
	_plus_button.pressed.connect(func() -> void: added.emit(card_id))
	cells.add_child(_plus_button)

	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))


## `accent` is the color of the card's type; `at_most` whether the deck has all the copies it may.
func setup(id: String, display_name: String, time_cost: String, accent: Color, copies: int, at_most: bool) -> void:
	card_id = id
	tooltip_text = display_name
	_name_label.text = display_name
	_cost_label.text = time_cost
	_stripe.color = accent
	_count_label.text = "×%d" % copies
	_plus_button.disabled = at_most


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_step_button(symbol: String, tip: String) -> Button:
	var button := Button.new()
	button.text = symbol
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(28, 28)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 22)
	var plain := StyleBoxEmpty.new()
	var hover := StyleBoxFlat.new()
	hover.bg_color = HOVER_COLOR
	hover.set_corner_radius_all(6)
	for state in ["normal", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, plain)
	for state in ["hover", "hover_pressed"]:
		button.add_theme_stylebox_override(state, hover)
	return button


func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	_apply_style()


func _apply_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = SELECTED_COLOR if highlighted or _hovered else ROW_COLOR
	style.border_color = ROW_LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	add_theme_stylebox_override("panel", style)


func _gui_input(event: InputEvent) -> void:
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


func _get_drag_data(_at_position: Vector2) -> Variant:
	selected.emit(card_id)
	var preview := PanelContainer.new()
	var label := _make_label(18, INK)
	label.text = _name_label.text
	preview.add_child(label)
	preview.modulate.a = 0.85
	set_drag_preview(preview)
	return {"card_id": card_id, "from": source}
