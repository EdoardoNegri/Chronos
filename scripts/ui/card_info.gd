class_name CardInfo
extends VBoxContainer
## The details of one card in the deck builder, under its picture: the name and type, then small
## boxes (like the fields of the search form) with its time cost, deck points, attack and defense
## and how many copies the deck has, and the card's text.

const GOLD := Color(0.95, 0.8, 0.45)
const INK := Color(0.92, 0.9, 0.85)
const MUTED := Color(0.62, 0.64, 0.74)
const FIELD_COLOR := Color(0.05, 0.06, 0.1, 0.9)
const FIELD_LINE := Color(0.86, 0.7, 0.36, 0.3)
const NOTHING_TEXT := "Select a card to see it here."


func _init() -> void:
	add_theme_constant_override("separation", 8)


## Nothing selected.
func show_nothing() -> void:
	_clear()
	var hint := _make_text(NOTHING_TEXT, 17, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)


## `points` is what the card costs in a deck; `on_list` whether the points list names it (if not it
## costs what its maker set). `copies` is how many the deck has, of at most `max_copies`.
func show_card(card: CardData, points: int, on_list: bool, copies: int, max_copies: int) -> void:
	_clear()
	add_child(_make_text(card.card_name, 22, GOLD))
	add_child(_make_text(card.type_line(), 16, MUTED))

	var boxes := GridContainer.new()
	boxes.columns = 3
	boxes.add_theme_constant_override("h_separation", 6)
	boxes.add_theme_constant_override("v_separation", 6)
	add_child(boxes)
	boxes.add_child(_make_field("Time cost", str(card.time_cost)))
	var points_field := _make_field("Points", str(points))
	if not on_list:
		points_field.tooltip_text = "Not on the points list: it costs what its maker set."
	boxes.add_child(points_field)
	boxes.add_child(_make_field("In deck", "%d / %d" % [copies, max_copies]))
	if card.has_stats():
		boxes.add_child(_make_field("Attack", str(card.attack)))
		boxes.add_child(_make_field("Defense", str(card.defense)))

	var rules := card.rules_text.strip_edges()
	if not rules.is_empty():
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", _box(8, 6))
		box.add_child(_make_text(rules, 17, INK))
		add_child(box)


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


## A caption in gold over a value, in a box.
func _make_field(caption: String, value: String) -> Control:
	var field := VBoxContainer.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_constant_override("separation", 2)
	var caption_label := _make_text(caption, 13, GOLD)
	# Never wrapped: the boxes share a narrow row.
	caption_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	field.add_child(caption_label)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(8, 5))
	box.add_child(_make_text(value, 18, INK))
	field.add_child(box)
	return field


func _make_text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _box(margin_x: int, margin_y: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = FIELD_COLOR
	style.border_color = FIELD_LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = margin_x
	style.content_margin_right = margin_x
	style.content_margin_top = margin_y
	style.content_margin_bottom = margin_y
	return style
