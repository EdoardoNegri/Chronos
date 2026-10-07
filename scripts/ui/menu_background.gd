extends Control
## Animated backdrop for the main menu: a dark gradient with a slowly turning clock dial.

const TOP_COLOR := Color(0.07, 0.08, 0.14)
const BOTTOM_COLOR := Color(0.02, 0.02, 0.05)
const GOLD := Color(0.86, 0.7, 0.36)
const TICK_COUNT := 60

var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	_draw_gradient()
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.46
	_draw_dial(center, radius, _time * 0.02)
	_draw_inner_ring(center, radius * 0.72, -_time * 0.05)
	_draw_hand(center, radius * 0.9, _time * TAU / 60.0)
	_draw_vignette()


func _draw_gradient() -> void:
	var points := PackedVector2Array(
		[Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]
	)
	var colors := PackedColorArray([TOP_COLOR, TOP_COLOR, BOTTOM_COLOR, BOTTOM_COLOR])
	draw_polygon(points, colors)


func _draw_dial(center: Vector2, radius: float, rotation_offset: float) -> void:
	var faint := Color(GOLD, 0.12)
	draw_arc(center, radius, 0.0, TAU, 128, faint, 2.0, true)
	draw_arc(center, radius * 0.97, 0.0, TAU, 128, Color(GOLD, 0.06), 1.0, true)
	for i in TICK_COUNT:
		var angle := rotation_offset + TAU * i / TICK_COUNT
		var major := i % 5 == 0
		var length := radius * (0.07 if major else 0.03)
		var direction := Vector2.from_angle(angle)
		var from := center + direction * (radius - length)
		var to := center + direction * radius
		draw_line(from, to, Color(GOLD, 0.28 if major else 0.12), 2.0 if major else 1.0, true)


func _draw_inner_ring(center: Vector2, radius: float, rotation_offset: float) -> void:
	var segments := 12
	var gap := 0.08
	var step := TAU / segments
	for i in segments:
		var start := rotation_offset + step * i + gap
		draw_arc(center, radius, start, start + step - gap * 2.0, 24, Color(GOLD, 0.1), 3.0, true)


func _draw_hand(center: Vector2, length: float, angle: float) -> void:
	var direction := Vector2.from_angle(angle - PI * 0.5)
	draw_line(center, center + direction * length, Color(GOLD, 0.1), 1.5, true)
	draw_circle(center, 5.0, Color(GOLD, 0.2))


func _draw_vignette() -> void:
	var edge := Color(0.0, 0.0, 0.0, 0.0)
	var dark := Color(0.0, 0.0, 0.0, 0.45)
	var band := minf(size.x, size.y) * 0.25
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), Vector2(size.x, band), Vector2(0.0, band)]),
		PackedColorArray([dark, dark, edge, edge])
	)
	draw_polygon(
		PackedVector2Array(
			[Vector2(0.0, size.y - band), Vector2(size.x, size.y - band), size, Vector2(0.0, size.y)]
		),
		PackedColorArray([edge, edge, dark, dark])
	)
