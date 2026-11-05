class_name SettingsButton
extends Button
## The gear at the top right of every screen. It opens Settings on top of the current screen, so
## closing Settings returns to that screen exactly as it was.

const SETTINGS_SCENE := "res://scenes/settings.tscn"
const COLOR := Color(0.7, 0.72, 0.8)
const HOVER_COLOR := Color(0.97, 0.96, 0.92)
const PRESSED_COLOR := Color(0.55, 0.57, 0.65)
const TEETH := 8
const OUTER_RADIUS := 15.0
const INNER_RADIUS := 11.0
const HOLE_RADIUS := 4.5
const WIDTH := 3.0


func _init() -> void:
	flat = true
	text = ""
	tooltip_text = "Settings"
	custom_minimum_size = Vector2(52, 52)
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	pressed.connect(open_settings)


## Shows Settings over the current screen. Returns the Settings screen, or null if it is
## already open.
func open_settings() -> Control:
	# The screen this button belongs to (its scene's root), or the current scene.
	var screen: Node = owner if owner != null else get_tree().current_scene
	if screen == null or screen.has_node("Settings"):
		return null
	var settings: Control = load(SETTINGS_SCENE).instantiate()
	settings.name = "Settings"
	# Keys must not keep going to a field that was being typed in underneath.
	get_viewport().gui_release_focus()
	screen.add_child(settings)
	return settings


func _draw() -> void:
	var color := COLOR
	if is_pressed():
		color = PRESSED_COLOR
	elif is_hovered():
		color = HOVER_COLOR
	var center := size * 0.5
	var step := TAU / TEETH
	var outline := PackedVector2Array()
	for tooth in TEETH:
		var middle := tooth * step
		outline.append(center + Vector2.from_angle(middle - step * 0.32) * INNER_RADIUS)
		outline.append(center + Vector2.from_angle(middle - step * 0.17) * OUTER_RADIUS)
		outline.append(center + Vector2.from_angle(middle + step * 0.17) * OUTER_RADIUS)
		outline.append(center + Vector2.from_angle(middle + step * 0.32) * INNER_RADIUS)
	outline.append(outline[0])
	draw_polyline(outline, color, WIDTH, true)
	draw_arc(center, HOLE_RADIUS, 0.0, TAU, 24, color, WIDTH, true)
