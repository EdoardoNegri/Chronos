extends Control
## Settings, shown on top of whichever screen opened it (see SettingsButton). Each section has a
## gold title and one box, like the rulebook's (see NumberedSections), with a row per setting: its
## name, and under it in grey what it does, on the left; its control on the right.
##
## The back arrow, or Escape, closes Settings and leaves that screen as it was.

const SUCCESS_COLOR := Color(0.5, 0.82, 0.55)
const ERROR_COLOR := Color(0.9, 0.5, 0.45)
const NAME_COLOR := Color(0.92, 0.9, 0.85)
const HINT_COLOR := Color(0.62, 0.64, 0.74)
const NAME_FONT_SIZE := 20
const HINT_FONT_SIZE := 16
const NAME_HINT := "Shown to the players you meet online. No email needed."
const FULLSCREEN_HINT := "Use the whole screen for the game."

## Who the player is online. The Profile autoload, unless a test gives another.
var profile: PlayerProfile = Profile

var _fullscreen_check: CheckButton
var _name_edit: LineEdit
var _name_status: Label

@onready var _back_button: Button = %BackButton
@onready var _setting_list: VBoxContainer = %SettingList


func _ready() -> void:
	_build_display()
	_build_online()
	_back_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	# A name typed but not confirmed with Enter still counts.
	_apply_name()
	queue_free()


# --- The settings --------------------------------------------------------------------------


func _build_display() -> void:
	var rows := _add_section("Display")
	_fullscreen_check = CheckButton.new()
	_fullscreen_check.button_pressed = _is_fullscreen()
	_fullscreen_check.toggled.connect(_set_fullscreen)
	_add_row(rows, "Fullscreen", FULLSCREEN_HINT, _fullscreen_check, &"FullscreenCheck")


func _build_online() -> void:
	var rows := _add_section("Online")
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(320, 0)
	_name_edit.max_length = PlayerProfile.MAX_NAME_LENGTH
	_name_edit.placeholder_text = "Not set yet"
	_name_edit.text = profile.player_name
	_name_edit.text_submitted.connect(func(_text: String) -> void: _apply_name())
	_name_edit.focus_exited.connect(_apply_name)
	_name_edit.text_changed.connect(func(_text: String) -> void: _show_name_status("", SUCCESS_COLOR))
	column.add_child(_name_edit)
	_name_status = Label.new()
	_name_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_name_status.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	_name_status.visible = false
	column.add_child(_name_status)
	_add_row(rows, "Name", NAME_HINT, column, &"")
	_own(_name_edit, &"NameEdit")
	_own(_name_status, &"NameStatus")


## A section: its title, and one box for its rows. Returns where the rows go.
func _add_section(title: String) -> VBoxContainer:
	var section := NumberedSections.make_section(0, title)
	_setting_list.add_child(section["control"])
	var rows: VBoxContainer = section["list"]
	rows.add_theme_constant_override("separation", 14)
	return rows


## A row: the setting's name with what it does under it on the left, its control on the right, and
## a line between it and the row before. `unique_name` lets the control be found with %Name (as
## tests do), unless it is empty.
func _add_row(rows: VBoxContainer, title: String, hint: String, control: Control, unique_name: StringName) -> void:
	if rows.get_child_count() > 0:
		rows.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_child(NumberedSections.make_label(title, NAME_FONT_SIZE, NAME_COLOR))
	var hint_label := NumberedSections.make_label(hint, HINT_FONT_SIZE, HINT_COLOR)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(hint_label)
	row.add_child(text)
	control.size_flags_horizontal = Control.SIZE_SHRINK_END
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	rows.add_child(row)
	if not unique_name.is_empty():
		_own(control, unique_name)


func _own(control: Control, unique_name: StringName) -> void:
	control.name = unique_name
	control.owner = self
	control.unique_name_in_owner = true


# --- Name ----------------------------------------------------------------------------------


## Saves the name typed in the field. A name that cannot be used (empty, or too long) is not
## saved and the field goes back to the name that is.
func _apply_name() -> void:
	var typed := _name_edit.text.strip_edges()
	if typed == profile.player_name or (typed.is_empty() and not profile.has_account()):
		return
	var error := profile.set_player_name(typed)
	_name_edit.text = profile.player_name
	if error.is_empty():
		_show_name_status("Saved.", SUCCESS_COLOR)
	else:
		_show_name_status(error, ERROR_COLOR)


## Says how saving the name went, under the field (the line only takes space while it says
## something).
func _show_name_status(text: String, color: Color) -> void:
	_name_status.text = text
	_name_status.visible = not text.is_empty()
	_name_status.add_theme_color_override("font_color", color)


# --- Display -------------------------------------------------------------------------------


func _is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _set_fullscreen(fullscreen: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
