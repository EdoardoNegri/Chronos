class_name ClockDial
extends Control
## A time cost shown on a clock face. The hand turns clockwise from 12:00 and the arc behind it
## is colored, so a bigger cost sits further round the dial. The cost is also printed inside.

## The cost at which the hand has gone all the way round and is back at 12:00.
const FULL_TURN := 60
const FACE_COLOR := Color(0.05, 0.06, 0.1)
const INK := Color(0.95, 0.93, 0.88)
const RING_WIDTH := 7.0
const ARC_STEPS := 48

var value := 0:
	set(new_value):
		value = new_value
		_refresh()
var accent := Color(0.86, 0.7, 0.36):
	set(new_value):
		accent = new_value
		queue_redraw()

var _label: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", INK)
	_label.add_theme_color_override("font_outline_color", FACE_COLOR)
	_label.add_theme_constant_override("outline_size", 8)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_label)
	_refresh()


func _refresh() -> void:
	queue_redraw()
	if _label == null:
		return
	_label.text = str(value)
	var width := size.x * 0.56
	_label.add_theme_font_size_override(
		"font_size", TextFit.font_size(_label.get_theme_font("font"), _label.text, width, 34, 14)
	)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - RING_WIDTH * 0.5
	var fraction := clampf(float(value) / FULL_TURN, 0.0, 1.0)
	var start := -PI * 0.5
	var end := start + TAU * fraction

	draw_circle(center, radius, FACE_COLOR)
	draw_arc(center, radius, 0.0, TAU, ARC_STEPS * 2, Color(accent, 0.25), RING_WIDTH, true)
	if fraction > 0.0:
		var pie := PackedVector2Array([center])
		for i in ARC_STEPS + 1:
			pie.append(center + Vector2.from_angle(lerpf(start, end, float(i) / ARC_STEPS)) * radius)
		draw_colored_polygon(pie, Color(accent, 0.5))
		draw_arc(center, radius, start, end, ARC_STEPS, accent, RING_WIDTH, true)

	# The hand runs from the middle to the ring, behind the number.
	var direction := Vector2.from_angle(end)
	draw_line(center, center + direction * radius, accent.lightened(0.45), 5.0, true)
	# A tick marks 12:00, where every cost starts from.
	draw_line(center + Vector2.UP * radius * 0.84, center + Vector2.UP * radius, INK, 3.0, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refresh()
