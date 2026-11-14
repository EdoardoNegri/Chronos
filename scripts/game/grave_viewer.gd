class_name GraveViewer
extends Control
## A graveyard opened to look inside, over the board: the board is dimmed and the cards in it are
## laid out in rows, the one that went in last first. Clicking outside it, the close button or
## Escape closes it. Graveyards are public, so either player's can be opened.

const CARD_SIZE := Vector2(114, 160)
const PANEL_COLOR := Color(0.05, 0.06, 0.1, 0.97)
const EDGE_COLOR := Color(0.86, 0.7, 0.36, 0.6)
const MUTED := Color(0.62, 0.64, 0.74)

var _title: Label
var _grid: HFlowContainer
var _empty: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.1
	panel.anchor_right = 0.9
	panel.anchor_top = 0.12
	panel.anchor_bottom = 0.88
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL_COLOR
	box.border_color = EDGE_COLOR
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 22)
	header.add_child(_title)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)
	_empty = Label.new()
	_empty.text = "Nothing has gone into this graveyard yet."
	_empty.add_theme_color_override("font_color", MUTED)
	column.add_child(_empty)


## Opens the graveyard: its title, and its cards in the order they went in (they are shown the
## other way round, the last first).
func open(title: String, cards: Array[Control]) -> void:
	_title.text = title
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for i in range(cards.size() - 1, -1, -1):
		var card := cards[i]
		card.custom_minimum_size = CARD_SIZE
		_grid.add_child(card)
	_empty.visible = cards.is_empty()
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func title() -> String:
	return _title.text


## The cards shown, the last that went in first.
func shown_cards() -> Array[Node]:
	return _grid.get_children()


func _on_dim_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		accept_event()
		close()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
