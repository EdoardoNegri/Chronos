class_name CardView
extends Control
## Draws a card at Magic: The Gathering size (2.5 x 3.5 inches, 63.5 x 88.9 mm) at 300 dpi.
## Everything is positioned in pixels, so the preview and the exported PNG match.
##
## Top: the image, with rounded top corners and the name box sitting on the text box's top line.
## Bottom: the text box. Hanging from its top line, in the middle, is the type box, as tall
## as the name box, with the attack and defense to its left and the time cost, drawn as a clock,
## to its right. The text comes below. All lines are black; the text box only has its top line.

const CARD_SIZE := Vector2(750, 1050)
## The black border: 24 px is about 2 mm at 300 dpi. Thinner than a Magic card's (about 3 mm),
## but still wider than the usual printing cut tolerance (about 1.6 mm, 1/16 inch), so an
## off-center cut eats into the border, not the picture or the boxes.
const INSET := 24.0
## Rounded corners, about 3 mm like a Magic card's.
const CORNER_RADIUS := 36
const GAP := 12.0
const BORDER := 3.0
## The text box's top line. The name box ends on it and the type box starts from it.
const LINE_Y := 600.0
## The rounding of the picture's top corners and the text box's bottom corners.
const BOX_RADIUS := 12
const NAME_HEIGHT := 68.0
const NAME_INSET := 24.0
const BAND_TOP := LINE_Y + BORDER
const BAND_HEIGHT := NAME_HEIGHT
const BAND_PADDING := 12.0
## A little shorter than the type box, so it clears the line above when centered beside it.
const DIAL_SIZE := 58.0
const STATS_WIDTH := 100.0
const STATS_FONT_SIZE := 36
const TEXT_PADDING := 20.0
const TEXT_MAX_SIZE := 34
const TEXT_MIN_SIZE := 14

## The card's outer frame: plain black, like a black-bordered Magic card.
const FRAME_COLOR := Color(0.0, 0.0, 0.0)
const BOX_COLOR := Color(0.05, 0.06, 0.1, 0.92)
const TEXT_BOX_COLOR := Color(0.11, 0.12, 0.19)
const IMAGE_COLOR := Color(0.1, 0.11, 0.18)
const INK := Color(0.95, 0.93, 0.88)
const MUTED := Color(0.5, 0.52, 0.62)
const LINE_COLOR := Color(0.0, 0.0, 0.0)
## The clock is a neutral grey, except for types with their own color.
const DEFAULT_ACCENT := Color(0.6, 0.62, 0.7)
const TYPE_ACCENTS := {
	"Creature": DEFAULT_ACCENT,
	"Spell": Color(0.45, 0.62, 0.95),
}

var card: CardData:
	set(value):
		if card != null and card.changed.is_connected(refresh):
			card.changed.disconnect(refresh)
		card = value
		if card != null:
			card.changed.connect(refresh)
		if is_node_ready():
			refresh()

var _image_rect: TextureRect
var _image_placeholder: Label
var _name_label: Label
var _stats_label: Label
var _type_box: Panel
var _type_label: Label
var _dial: ClockDial
var _text_label: RichTextLabel
var _shown_image: Image
var _shown_texture: ImageTexture


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_build()
	refresh()


func refresh() -> void:
	if not is_node_ready():
		return
	var data := card if card != null else CardData.new()
	_dial.accent = TYPE_ACCENTS.get(data.card_type, DEFAULT_ACCENT)

	_set_image(data.image)

	var shown_name := data.card_name.strip_edges()
	_name_label.text = shown_name if not shown_name.is_empty() else "Card name"
	_name_label.add_theme_color_override("font_color", INK if not shown_name.is_empty() else MUTED)
	_fit_label(_name_label, 44, 18, (_name_label.get_parent() as Control).size.x - 32.0)

	var has_stats := data.has_stats()
	_stats_label.visible = has_stats
	_stats_label.text = "%d / %d" % [data.attack, data.defense]
	_fit_label(_stats_label, STATS_FONT_SIZE, 16, _stats_label.size.x - 8.0)

	_type_label.text = data.type_line()
	_fit_label(_type_label, 34, 12, _type_box.size.x - 32.0)

	_dial.value = data.time_cost
	_fit_text(data.rules_text)


func _build() -> void:
	var image_width := CARD_SIZE.x - INSET * 2.0
	_make_box(Rect2(Vector2.ZERO, CARD_SIZE), FRAME_COLOR, 0, CORNER_RADIUS, CORNER_RADIUS, [])

	# The picture is clipped to this box, so it gets the box's rounded top corners.
	var image_box := _make_box(
		Rect2(INSET, INSET, image_width, LINE_Y - INSET), IMAGE_COLOR, 0, BOX_RADIUS, 0, []
	)
	image_box.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_image_placeholder = _make_label(34, MUTED)
	_image_placeholder.text = "No image"
	_image_placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
	image_box.add_child(_image_placeholder)
	_image_rect = TextureRect.new()
	_image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_image_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_box.add_child(_image_rect)

	# The text box. Its only line is the top one, which the name box and the type box share.
	var text_rect := Rect2(INSET, LINE_Y, image_width, CARD_SIZE.y - INSET - LINE_Y)
	_make_box(text_rect, TEXT_BOX_COLOR, int(BORDER), 0, BOX_RADIUS, [SIDE_TOP])

	var name_rect := Rect2(
		INSET + NAME_INSET, LINE_Y - NAME_HEIGHT, image_width - NAME_INSET * 2.0, NAME_HEIGHT
	)
	_name_label = _add_label(
		_make_box(name_rect, BOX_COLOR, int(BORDER), 12, 0, [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT]), 44
	)

	# Centered on the card, with the same room on each side for the stats and the clock. It keeps
	# its place for every card type; without stats the space beside it is empty.
	var type_left := INSET + BAND_PADDING + STATS_WIDTH + GAP
	var type_rect := Rect2(type_left, BAND_TOP, CARD_SIZE.x - type_left * 2.0, BAND_HEIGHT)
	_type_box = _make_box(type_rect, BOX_COLOR, int(BORDER), 0, 12, [SIDE_LEFT, SIDE_RIGHT, SIDE_BOTTOM])
	_type_label = _add_label(_type_box, 34)

	_stats_label = _make_label(STATS_FONT_SIZE, INK)
	_stats_label.clip_text = true
	_stats_label.position = Vector2(INSET + BAND_PADDING, BAND_TOP)
	_stats_label.size = Vector2(STATS_WIDTH, BAND_HEIGHT)
	add_child(_stats_label)

	_dial = ClockDial.new()
	_dial.size = Vector2(DIAL_SIZE, DIAL_SIZE)
	# In the middle of the space right of the type box, centered on the same line as the type
	# box and the stats.
	var right_space_center := (type_rect.end.x + CARD_SIZE.x - INSET) * 0.5
	_dial.position = Vector2(right_space_center, BAND_TOP + BAND_HEIGHT * 0.5) - Vector2.ONE * DIAL_SIZE * 0.5
	add_child(_dial)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = false
	_text_label.scroll_active = false
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_label.add_theme_color_override("default_color", INK)
	# The text starts below both the type box and the clock.
	var text_top := maxf(BAND_TOP + BAND_HEIGHT, _dial.position.y + DIAL_SIZE) + GAP
	_text_label.position = Vector2(text_rect.position.x + TEXT_PADDING, text_top)
	_text_label.size = Vector2(
		text_rect.size.x - TEXT_PADDING * 2.0, text_rect.end.y - TEXT_PADDING - text_top
	)
	add_child(_text_label)


## A rounded box with black lines on the given `sides` (Side values) only.
func _make_box(
	rect: Rect2, fill: Color, border_width: int, radius_top: int, radius_bottom: int, sides: Array
) -> Panel:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = LINE_COLOR
	for side: Side in sides:
		style.set_border_width(side, border_width)
	style.corner_radius_top_left = radius_top
	style.corner_radius_top_right = radius_top
	style.corner_radius_bottom_left = radius_bottom
	style.corner_radius_bottom_right = radius_bottom
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _add_label(box: Panel, font_size: int) -> Label:
	var label := _make_label(font_size, INK)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(label)
	return label


func _set_image(image: Image) -> void:
	if image != _shown_image:
		_shown_image = image
		_shown_texture = ImageTexture.create_from_image(image) if image != null else null
	_image_rect.texture = _shown_texture
	_image_placeholder.visible = _shown_texture == null


## Shrinks a single-line label's font until the text fits `width`.
func _fit_label(label: Label, max_size: int, min_size: int, width: float) -> void:
	var font_size := TextFit.font_size(label.get_theme_font("font"), label.text, width, max_size, min_size)
	label.add_theme_font_size_override("font_size", font_size)


## Uses the largest font size at which the rules text still fits the text box.
func _fit_text(text: String) -> void:
	_text_label.text = text
	var font_size := TEXT_MAX_SIZE
	_text_label.add_theme_font_size_override("normal_font_size", font_size)
	while font_size > TEXT_MIN_SIZE and _text_label.get_content_height() > _text_label.size.y:
		font_size -= 1
		_text_label.add_theme_font_size_override("normal_font_size", font_size)
