class_name TimeBar
extends Control
## The shared timer as a bar that grows from its middle. Green when it is the player's turn, red
## when it is the opponent's. It grows to the right, toward the player's name, by the time they have
## (how far behind they are, which is how much they can spend before the opponent acts), and to the
## left, toward the opponent's, by the time the opponent has. A full half is `full_scale` time; more
## than that still fills it.

const TRACK_COLOR := Color(0.06, 0.07, 0.12, 0.9)
const EDGE_COLOR := Color(0.3, 0.32, 0.42)
const MIDDLE_COLOR := Color(0.86, 0.7, 0.36)
const GREEN := Color(0.3, 0.8, 0.42)
const RED := Color(0.88, 0.3, 0.3)
const RADIUS := 6

## How far behind the player is: positive grows the bar to the right, negative to the left.
var value := 0:
	set(new_value):
		value = new_value
		queue_redraw()
var your_turn := false:
	set(new_value):
		your_turn = new_value
		queue_redraw()
var full_scale := 200:
	set(new_value):
		full_scale = maxi(1, new_value)
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(480, 20)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## How long the filled part is, out of half the bar (0 to 1).
func fill_fraction() -> float:
	return clampf(absf(float(value)) / full_scale, 0.0, 1.0)


func fill_color() -> Color:
	return GREEN if your_turn else RED


## The filled part, in this control (empty when there is nothing to fill).
func fill_rect() -> Rect2:
	var middle := size.x * 0.5
	var filled := (middle - 3.0) * fill_fraction()
	if filled <= 0.5:
		return Rect2()
	var left := middle if value > 0 else middle - filled
	return Rect2(left, 3.0, filled, size.y - 6.0)


func _draw() -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = TRACK_COLOR
	track.border_color = EDGE_COLOR
	track.set_border_width_all(2)
	track.set_corner_radius_all(RADIUS)
	draw_style_box(track, Rect2(Vector2.ZERO, size))

	var filled := fill_rect()
	if filled.has_area():
		var fill := StyleBoxFlat.new()
		fill.bg_color = fill_color()
		fill.set_corner_radius_all(RADIUS - 2)
		draw_style_box(fill, filled)
	draw_line(Vector2(size.x * 0.5, 0.0), Vector2(size.x * 0.5, size.y), MIDDLE_COLOR, 2.0)
