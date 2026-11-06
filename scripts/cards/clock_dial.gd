class_name ClockDial
extends Control
## A time cost shown on a clock face. A wedge fills clockwise from 12:00, so a bigger cost
## sits further round the dial. The cost is also printed inside.
## Past a full turn the wedge keeps going round: the whole dial is filled for the turns already
## made and the current turn is drawn on top in a lighter color.

## The cost of one full turn round the dial.
const FULL_TURN := 60
const FACE_COLOR := Color(0.05, 0.06, 0.1)
const INK := Color(0.95, 0.93, 0.88)
const ARC_STEPS := 48
## How much of the dial's width the number may use. Wide enough that three digits stay readable.
const TEXT_WIDTH_SHARE := 0.82
const TEXT_MAX_SIZE := 34
const TEXT_MIN_SIZE := 14
const TEXT_OUTLINE := 6

var value := 0:
	set(new_value):
		value = new_value
		_refresh()
var accent := Color(0.6, 0.62, 0.7):
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
	_label.add_theme_constant_override("outline_size", TEXT_OUTLINE)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_label)
	_refresh()


func _refresh() -> void:
	queue_redraw()
	if _label == null:
		return
	_label.text = str(value)
	var width := size.x * TEXT_WIDTH_SHARE - TEXT_OUTLINE
	# On small dials the number is also kept short enough to stay inside the circle.
	var max_size := clampi(int(size.y * 0.6), 8, TEXT_MAX_SIZE)
	var min_size := mini(TEXT_MIN_SIZE, max_size)
	_label.add_theme_font_size_override(
		"font_size",
		TextFit.font_size(_label.get_theme_font("font"), _label.text, width, max_size, min_size)
	)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	var cost := maxi(value, 0)
	@warning_ignore("integer_division")
	var full_turns := cost / FULL_TURN
	var fraction := float(cost % FULL_TURN) / FULL_TURN
	var start := -PI * 0.5
	var end := start + TAU * fraction
	# Each turn already made is drawn in a lighter color than the one before it.
	var turn_color := accent.lightened(minf(0.2 * full_turns, 0.6))

	# No ring around the edge: just the face, filled as far as the cost goes.
	draw_circle(center, radius, FACE_COLOR)
	if full_turns > 0:
		var done_color := accent.lightened(minf(0.2 * (full_turns - 1), 0.6))
		draw_circle(center, radius, Color(done_color, 0.5))
	if fraction > 0.0:
		var pie := PackedVector2Array([center])
		for i in ARC_STEPS + 1:
			pie.append(center + Vector2.from_angle(lerpf(start, end, float(i) / ARC_STEPS)) * radius)
		draw_colored_polygon(pie, Color(turn_color, 0.5))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refresh()
