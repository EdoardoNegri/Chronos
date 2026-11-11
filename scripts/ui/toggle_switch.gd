class_name ToggleSwitch
extends Button
## A switch that turns on and off when it is clicked, with no box around it: a rounded track and a
## round knob, at the right end of the button. Off, the track is dark with a light outline and the
## knob is at its left; on, the track is gold and the knob is at its right. The button's text, if
## it has any, is to the left of the switch.

const TRACK_SIZE := Vector2(52, 28)
## The space between the text and the switch.
const GAP := 12.0
const KNOB_MARGIN := 4.0
const ON_COLOR := Color(0.95, 0.8, 0.45)
const ON_HOVER_COLOR := Color(1, 0.9, 0.62)
const OFF_COLOR := Color(0.2, 0.22, 0.32)
const OFF_HOVER_COLOR := Color(0.28, 0.3, 0.42)
const OFF_BORDER_COLOR := Color(0.72, 0.74, 0.84)
const KNOB_ON_COLOR := Color(0.1, 0.08, 0.04)
const KNOB_OFF_COLOR := Color(0.9, 0.91, 0.96)

var _track_on: StyleBoxFlat
var _track_off: StyleBoxFlat


func _init() -> void:
	toggle_mode = true
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size.y = TRACK_SIZE.y + 8.0
	# No box in any state, but room on the right for the switch, which is drawn there.
	var room := StyleBoxEmpty.new()
	room.content_margin_right = TRACK_SIZE.x + GAP
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, room)
	_track_on = _make_track(ON_COLOR, ON_COLOR, 0)
	_track_off = _make_track(OFF_COLOR, OFF_BORDER_COLOR, 2)
	toggled.connect(func(_on: bool) -> void: queue_redraw())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _make_track(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var track := StyleBoxFlat.new()
	track.bg_color = fill
	track.border_color = border
	track.set_border_width_all(border_width)
	track.set_corner_radius_all(int(TRACK_SIZE.y * 0.5))
	return track


func _draw() -> void:
	var track_rect := Rect2(Vector2(size.x - TRACK_SIZE.x, (size.y - TRACK_SIZE.y) * 0.5), TRACK_SIZE)
	var track := _track_on if button_pressed else _track_off
	if is_hovered():
		track = track.duplicate()
		track.bg_color = ON_HOVER_COLOR if button_pressed else OFF_HOVER_COLOR
	draw_style_box(track, track_rect)
	var radius := TRACK_SIZE.y * 0.5 - KNOB_MARGIN
	var knob_x := track_rect.end.x - TRACK_SIZE.y * 0.5 if button_pressed else track_rect.position.x + TRACK_SIZE.y * 0.5
	draw_circle(
		Vector2(knob_x, track_rect.get_center().y), radius, KNOB_ON_COLOR if button_pressed else KNOB_OFF_COLOR
	)
