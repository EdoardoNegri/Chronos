extends Control
## A small triangle beside the timer, pointing at the name of the player whose turn it is. It keeps
## its place while hidden (`shown` off), so the timer stays in the middle of the band.

const SIZE := Vector2(14, 18)

## Points to the left (at the name left of the timer) or to the right.
@export var points_left := true:
	set(value):
		points_left = value
		queue_redraw()
@export var shown := false:
	set(value):
		shown = value
		queue_redraw()
@export var color := Color.WHITE:
	set(value):
		color = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(SIZE.x, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if not shown:
		return
	var middle := size * 0.5
	var tip := Vector2(-SIZE.x * 0.5 if points_left else SIZE.x * 0.5, 0.0)
	var back := -tip.x
	draw_colored_polygon(PackedVector2Array([
		middle + tip,
		middle + Vector2(back, -SIZE.y * 0.5),
		middle + Vector2(back, SIZE.y * 0.5),
	]), color)
