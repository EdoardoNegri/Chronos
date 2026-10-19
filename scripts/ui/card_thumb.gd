class_name CardThumb
extends Control
## A small card picture in the deck builder. Click selects it, double-click activates it, right
## click is the context action, and it can be dragged onto another list.

signal selected(card_id: String)
signal activated(card_id: String)
signal context_clicked(card_id: String)

const THUMB_SIZE := Vector2(63, 88)
const HIGHLIGHT := Color(0.95, 0.8, 0.45)
const PLACEHOLDER := Color(0.1, 0.11, 0.18)
const MUTED := Color(0.62, 0.64, 0.74)

var card_id := ""
## Which list this thumb lives in, so drop targets know where a drag came from.
var source: StringName = &""
var highlighted := false:
	set(value):
		highlighted = value
		queue_redraw()

var _face: TextureRect
var _fallback_label: Label
var _badge: Label


func _init() -> void:
	custom_minimum_size = THUMB_SIZE
	size = THUMB_SIZE
	# PASS, not STOP, so the wheel still scrolls the list and drops reach the list behind.
	mouse_filter = Control.MOUSE_FILTER_PASS

	_face = TextureRect.new()
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)

	_fallback_label = Label.new()
	_fallback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fallback_label.add_theme_font_size_override("font_size", 11)
	_fallback_label.add_theme_color_override("font_color", MUTED)
	_fallback_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fallback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fallback_label)

	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", 14)
	_badge.add_theme_color_override("font_color", Color(0.1, 0.08, 0.04))
	var pill := StyleBoxFlat.new()
	pill.bg_color = HIGHLIGHT
	pill.set_corner_radius_all(6)
	pill.content_margin_left = 5.0
	pill.content_margin_right = 5.0
	_badge.add_theme_stylebox_override("normal", pill)
	_badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_badge.offset_right = -3.0
	_badge.offset_bottom = -3.0
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.hide()
	add_child(_badge)


## `texture` may be null, in which case the card's name is shown instead of its picture.
func setup(id: String, display_name: String, texture: Texture2D) -> void:
	card_id = id
	tooltip_text = display_name
	_face.texture = texture
	_fallback_label.text = display_name
	_fallback_label.visible = texture == null
	queue_redraw()


## Shows how many copies are in the deck; nothing is shown for zero.
func set_copies(count: int) -> void:
	_badge.visible = count > 0
	_badge.text = "x%d" % count


func _draw() -> void:
	if _face.texture == null:
		draw_rect(Rect2(Vector2.ZERO, size), PLACEHOLDER)
	if highlighted:
		draw_rect(Rect2(Vector2.ZERO, size).grow(-1.5), HIGHLIGHT, false, 3.0)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_LEFT:
		if click.double_click:
			activated.emit(card_id)
		else:
			selected.emit(card_id)
	elif click.button_index == MOUSE_BUTTON_RIGHT:
		context_clicked.emit(card_id)


func _get_drag_data(_at_position: Vector2) -> Variant:
	selected.emit(card_id)
	var preview := TextureRect.new()
	preview.texture = _face.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size = THUMB_SIZE
	preview.modulate.a = 0.8
	set_drag_preview(preview)
	return {"card_id": card_id, "from": source}
