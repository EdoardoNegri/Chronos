class_name RefreshButton
extends Button
## A refresh button drawn as a circular arrow, with no button box around it.

const COLOR := Color(0.7, 0.72, 0.8)
const HOVER_COLOR := Color(0.95, 0.8, 0.45)
const PRESSED_COLOR := Color(0.55, 0.57, 0.65)
const RADIUS := 10.0
const WIDTH := 3.0
const HEAD := 8.0
## The circle starts at 6 o'clock and goes round the long way, counterclockwise through 3 and 12,
## to the arrow head at 9 o'clock. The gap is the bottom left, between the head and the start.
## (Angles run clockwise from 3 o'clock, as on the screen.)
const START_ANGLE := PI * 0.5
const HEAD_ANGLE := -PI


func _init() -> void:
	flat = true
	text = ""
	tooltip_text = "Refresh the list of rooms"
	custom_minimum_size = Vector2(40, 40)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var color := COLOR
	if is_pressed():
		color = PRESSED_COLOR
	elif is_hovered():
		color = HOVER_COLOR
	var center := size * 0.5
	draw_arc(center, RADIUS, HEAD_ANGLE, START_ANGLE, 48, color, WIDTH, true)

	# The head sits at the end of the arc and points the way it was going (counterclockwise, so
	# down at 9 o'clock, into the gap).
	var radial := Vector2.from_angle(HEAD_ANGLE)
	var forward := Vector2(radial.y, -radial.x)
	var tip := center + radial * RADIUS + forward * HEAD * 0.8
	var base := center + radial * RADIUS - forward * HEAD * 0.2
	draw_colored_polygon(
		PackedVector2Array([tip, base + radial * HEAD * 0.75, base - radial * HEAD * 0.75]), color
	)
