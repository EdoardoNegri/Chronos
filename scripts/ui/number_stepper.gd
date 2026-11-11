class_name NumberStepper
extends PanelContainer
## A whole-number field you can type in. At its right end, behind a vertical line, + sits over
## −, split by a horizontal line. Looks like the theme's LineEdit.
##
## Holding + or − keeps stepping: after a short pause it repeats, faster the longer it is held,
## and after a while it moves in bigger steps.

signal value_changed(value: float)

## Small enough that the two stacked buttons are no taller than the text field.
const BUTTON_FONT_SIZE := 16
## Wait before a held button starts repeating, in seconds.
const HOLD_DELAY := 0.4
## Time between the first repeats; each repeat shortens it until it reaches FASTEST_INTERVAL.
const FIRST_INTERVAL := 0.12
const FASTEST_INTERVAL := 0.03
const SPEED_UP := 0.85
## After this many repeats, each repeat moves BIG_STEP at a time.
const REPEATS_BEFORE_BIG_STEPS := 30
const BIG_STEP := 5

@export var min_value := 0
@export var max_value := 999

## Whether the number can be changed, by typing or by the buttons.
var editable := true:
	set(new_value):
		editable = new_value
		if _edit != null:
			_edit.editable = editable
		_update_buttons()

var value := 0:
	set(new_value):
		var clamped := clampi(new_value, min_value, max_value)
		var changed := clamped != value
		value = clamped
		if _edit != null and not _typing:
			_edit.text = str(value)
		_update_buttons()
		if changed:
			value_changed.emit(float(value))

var _edit: LineEdit
var _minus: Button
var _plus: Button
var _frame: StyleBox
var _focus_frame: StyleBox
## True while the change comes from typing, so the text being typed is not rewritten.
var _typing := false
var _hold_timer: Timer
## +1 or -1 while a button is held, 0 otherwise.
var _hold_direction := 0
var _repeats := 0


func _ready() -> void:
	# The frame is drawn here, around the field and the buttons, so the line and buttons sit
	# inside it. Its margins go to the text instead, so the buttons can fill the full height.
	_frame = _without_margins(get_theme_stylebox("normal", "LineEdit"))
	_focus_frame = _without_margins(get_theme_stylebox("focus", "LineEdit"))
	add_theme_stylebox_override("panel", _frame)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.max_length = maxi(str(max_value).length(), str(min_value).length())
	_edit.editable = editable
	_edit.select_all_on_focus = true
	_edit.text = str(value)
	var text_style := StyleBoxEmpty.new()
	text_style.content_margin_left = 16.0
	text_style.content_margin_right = 8.0
	text_style.content_margin_top = 12.0
	text_style.content_margin_bottom = 12.0
	for state in ["normal", "focus", "read_only"]:
		_edit.add_theme_stylebox_override(state, text_style)
	_edit.text_changed.connect(_on_text_changed)
	_edit.text_submitted.connect(func(_text: String) -> void: _show_value())
	_edit.focus_entered.connect(func() -> void: add_theme_stylebox_override("panel", _focus_frame))
	_edit.focus_exited.connect(_on_focus_exited)
	row.add_child(_edit)

	# A vertical line before the buttons, then + stacked over −, split by a horizontal line.
	row.add_child(_make_line(Vector2(1, 0)))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	row.add_child(column)
	_plus = _make_button("+", 1)
	column.add_child(_plus)
	column.add_child(_make_line(Vector2(0, 1)))
	_minus = _make_button("−", -1)
	column.add_child(_minus)
	# Each button is as wide as it is tall: half the height, less the line between them.
	column.resized.connect(
		func() -> void: column.custom_minimum_size.x = maxf(0.0, (column.size.y - 1.0) * 0.5)
	)
	_update_buttons()

	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.timeout.connect(_repeat)
	add_child(_hold_timer)


## A divider in the frame's border color: `thickness` is (1, 0) for vertical, (0, 1) for
## horizontal.
func _make_line(thickness: Vector2) -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size = thickness
	line.color = _frame.border_color if _frame is StyleBoxFlat else Color(1, 1, 1, 0.2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _make_button(label: String, direction: int) -> Button:
	var button := Button.new()
	button.text = label
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	# No padding, so the buttons are no taller than the text field next to them.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.button_down.connect(_start_hold.bind(direction))
	button.button_up.connect(_stop_hold)
	return button


## One step right away, then repeating while the button stays down.
func _start_hold(direction: int) -> void:
	_hold_direction = direction
	_repeats = 0
	value += direction
	_hold_timer.start(HOLD_DELAY)


func _stop_hold() -> void:
	_hold_direction = 0
	_hold_timer.stop()


func _repeat() -> void:
	if _hold_direction == 0:
		return
	_repeats += 1
	var step := BIG_STEP if _repeats > REPEATS_BEFORE_BIG_STEPS else 1
	value += _hold_direction * step
	if value <= min_value or value >= max_value:
		_stop_hold()
		return
	_hold_timer.start(maxf(FASTEST_INTERVAL, FIRST_INTERVAL * pow(SPEED_UP, _repeats)))


func _on_text_changed(text: String) -> void:
	if not text.is_valid_int():
		return
	_typing = true
	value = int(text)
	_typing = false


func _on_focus_exited() -> void:
	add_theme_stylebox_override("panel", _frame)
	_show_value()


## Replaces whatever was typed with the actual value (empty or out of range text included).
func _show_value() -> void:
	_edit.text = str(value)


func _update_buttons() -> void:
	if _minus == null:
		return
	_minus.disabled = not editable or value <= min_value
	_plus.disabled = not editable or value >= max_value


static func _without_margins(style: StyleBox) -> StyleBox:
	var copy: StyleBox = style.duplicate() if style != null else StyleBoxEmpty.new()
	copy.content_margin_left = 0.0
	copy.content_margin_right = 0.0
	copy.content_margin_top = 0.0
	copy.content_margin_bottom = 0.0
	return copy
