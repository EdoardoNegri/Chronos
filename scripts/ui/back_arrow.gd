class_name BackArrow
extends Button
## A back button drawn as a plain arrow pointing left, with no button box around it.

const COLOR := Color(0.7, 0.72, 0.8)
const HOVER_COLOR := Color(0.97, 0.96, 0.92)
const PRESSED_COLOR := Color(0.55, 0.57, 0.65)
const HALF_LENGTH := 15.0
const HEAD := 11.0
const WIDTH := 4.0


func _init() -> void:
	flat = true
	text = ""
	tooltip_text = "Back"
	custom_minimum_size = Vector2(52, 52)
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
	var tip := center + Vector2(-HALF_LENGTH, 0.0)
	draw_line(tip, center + Vector2(HALF_LENGTH, 0.0), color, WIDTH, true)
	draw_polyline(
		PackedVector2Array([tip + Vector2(HEAD, -HEAD), tip, tip + Vector2(HEAD, HEAD)]), color, WIDTH, true
	)
