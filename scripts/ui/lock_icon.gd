class_name LockIcon
extends Control
## A small padlock, drawn so it needs no font or image. It always takes its space, so the buttons
## in a column of rows line up, but it only shows (and shows its tooltip) while `locked` is true.

const COLOR := Color(0.85, 0.8, 0.66)
const HOLE_COLOR := Color(0.1, 0.1, 0.16)
const TOOLTIP := "This room has a password."

var locked := false:
	set(value):
		locked = value
		tooltip_text = TOOLTIP if locked else ""
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(24, 30)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	if not locked:
		return
	var width := size.x
	var height := size.y
	# The body, in the lower part, with a keyhole.
	var top := height * 0.46
	draw_rect(Rect2(Vector2(1.0, top), Vector2(width - 2.0, height - top - 1.0)), COLOR)
	draw_circle(Vector2(width * 0.5, top + (height - top) * 0.45), 2.6, HOLE_COLOR)
	# The shackle: an arch standing on the body.
	var radius := width * 0.3
	var arch_center := Vector2(width * 0.5, top - 4.0)
	draw_arc(arch_center, radius, PI, TAU, 20, COLOR, 3.0)
	draw_line(arch_center + Vector2(-radius, 0.0), Vector2(arch_center.x - radius, top), COLOR, 3.0)
	draw_line(arch_center + Vector2(radius, 0.0), Vector2(arch_center.x + radius, top), COLOR, 3.0)
