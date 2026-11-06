extends Control
## Card maker: edit a card, see it live, and download it as a PNG. Downloaded PNGs carry the card
## with them (see CardPng), so other players can import them.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const STATUS_COLOR := Color(0.62, 0.64, 0.74)
const ERROR_COLOR := Color(0.9, 0.5, 0.45)
const SUCCESS_COLOR := Color(0.5, 0.82, 0.55)
const IMAGE_FILTERS: Array[String] = ["*.png, *.jpg, *.jpeg, *.webp ; Images"]
const PNG_FILTERS: Array[String] = ["*.png ; PNG image"]
const CARD_FILTERS: Array[String] = ["*.png ; Card PNG"]
## The preview never takes more than this share of the width, so the form keeps some room.
const MAX_PREVIEW_SHARE := 0.6
## How long a status message stays before it goes away.
const STATUS_SECONDS := 4.0

var card_library := CardLibrary.new()

var _card := CardData.new()
var _card_view := CardView.new()
var _image_dialog: FileDialog
var _save_dialog: FileDialog
var _import_dialog: FileDialog
var _save_choice: AcceptDialog
var _status_timer: Timer

@onready var _back_button: Button = %BackButton
@onready var _name_edit: LineEdit = %NameEdit
@onready var _type_option: OptionButton = %TypeOption
@onready var _subtype_edit: LineEdit = %SubtypeEdit
@onready var _time_input: NumberStepper = %TimeInput
@onready var _points_input: NumberStepper = %PointsInput
@onready var _stats_row: HBoxContainer = %StatsRow
@onready var _attack_input: NumberStepper = %AttackInput
@onready var _defense_input: NumberStepper = %DefenseInput
@onready var _rules_edit: TextEdit = %RulesEdit
@onready var _choose_image_button: Button = %ChooseImageButton
@onready var _preview: TextureRect = %Preview
@onready var _body: HBoxContainer = $Content/Layout/Body
@onready var _left_column: VBoxContainer = $Content/Layout/Body/LeftColumn
@onready var _status: Label = %Status
@onready var _save_button: Button = %SaveButton
@onready var _import_card_button: Button = %ImportCardButton
@onready var _viewport: SubViewport = %CardViewport


func _ready() -> void:
	_viewport.add_child(_card_view)
	_card_view.card = _card
	_preview.texture = _viewport.get_texture()
	_body.resized.connect(_fit_preview)
	_fit_preview()

	for card_type in CardData.TYPES:
		_type_option.add_item(card_type)
	_update_stats_row()

	_back_button.pressed.connect(_go_back)
	_name_edit.text_changed.connect(func(text: String) -> void: _edit(&"card_name", text))
	_subtype_edit.text_changed.connect(func(text: String) -> void: _edit(&"subtype", text))
	_time_input.value_changed.connect(func(value: float) -> void: _edit(&"time_cost", int(value)))
	_points_input.value_changed.connect(func(value: float) -> void: _edit(&"points", int(value)))
	_attack_input.value_changed.connect(func(value: float) -> void: _edit(&"attack", int(value)))
	_defense_input.value_changed.connect(func(value: float) -> void: _edit(&"defense", int(value)))
	_rules_edit.text_changed.connect(func() -> void: _edit(&"rules_text", _rules_edit.text))
	_type_option.item_selected.connect(_on_type_selected)
	_choose_image_button.pressed.connect(_open_image_dialog)
	_save_button.pressed.connect(_ask_how_to_save)
	_import_card_button.pressed.connect(func() -> void: _import_dialog.popup_centered_ratio(0.7))

	_image_dialog = _make_dialog(FileDialog.FILE_MODE_OPEN_FILE, IMAGE_FILTERS)
	_image_dialog.file_selected.connect(_load_image)
	_save_dialog = _make_dialog(FileDialog.FILE_MODE_SAVE_FILE, PNG_FILTERS)
	_save_dialog.file_selected.connect(_save_png)
	_import_dialog = _make_dialog(FileDialog.FILE_MODE_OPEN_FILE, CARD_FILTERS)
	_import_dialog.file_selected.connect(_import_card)
	_save_choice = _make_save_choice()

	_status_timer = Timer.new()
	_status_timer.one_shot = true
	_status_timer.timeout.connect(_status.hide)
	add_child(_status_timer)

	_name_edit.grab_focus()


## The card view is made before the screen is shown; if the screen goes away without ever being
## shown, the view was never added to it, so it is freed here.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_card_view) and _card_view.get_parent() == null:
		_card_view.free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


func _go_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _make_dialog(mode: FileDialog.FileMode, filters: Array[String]) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.use_native_dialog = true
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.filters = PackedStringArray(filters)
	add_child(dialog)
	return dialog


## Makes the preview as wide as a card that fills the full height, so it is as big as it can be.
func _fit_preview() -> void:
	var card_width := _body.size.y * CardView.CARD_SIZE.x / CardView.CARD_SIZE.y
	var room := (
		_body.size.x
		- _left_column.get_combined_minimum_size().x
		- _body.get_theme_constant("separation")
	)
	_preview.custom_minimum_size.x = maxf(0.0, minf(card_width, minf(room, _body.size.x * MAX_PREVIEW_SHARE)))


## Asks whether to save the card to the library or download it as a PNG.
func _make_save_choice() -> AcceptDialog:
	# An AcceptDialog has no Cancel button; the window's X (or Escape) closes it.
	var dialog := AcceptDialog.new()
	dialog.title = "Save card"
	dialog.dialog_text = "Save this card to your library, or download it as a PNG?"
	dialog.ok_button_text = "Save to library"
	dialog.add_button("Download PNG", false, "png")
	dialog.confirmed.connect(_save_to_library)
	dialog.custom_action.connect(
		func(action: StringName) -> void:
			if action == &"png":
				dialog.hide()
				_open_save_dialog()
	)
	add_child(dialog)
	return dialog


func _ask_how_to_save() -> void:
	_save_choice.popup_centered()
	# A dialog focuses its first button when it opens, which made "Save to library" look chosen.
	_save_choice.gui_release_focus()


## Shows `card` in the editor.
func _open_card(card: CardData) -> void:
	_card = card
	_card_view.card = _card
	_sync_form()


## Copies the card's fields into the form controls.
func _sync_form() -> void:
	_name_edit.text = _card.card_name
	_subtype_edit.text = _card.subtype
	_type_option.select(CardData.TYPES.find(_card.card_type))
	_time_input.value = _card.time_cost
	_points_input.value = _card.points
	_attack_input.value = _card.attack
	_defense_input.value = _card.defense
	_rules_edit.text = _card.rules_text
	_update_stats_row()


## Saves the card to the library so decks can use it. Saving again updates the same card.
func _save_to_library() -> void:
	if _card.card_name.strip_edges().is_empty():
		_show_status("Give the card a name before saving it.", ERROR_COLOR)
		_name_edit.grab_focus()
		return
	await _wait_for_draw()
	var error := card_library.save_card(_card, _capture_card())
	if error == OK:
		_show_status("Saved “%s” to your library." % _card.card_name.strip_edges(), SUCCESS_COLOR)
	else:
		_show_status("Could not save the card (%s)." % error_string(error), ERROR_COLOR)


## Adds a card someone else made to the library and opens it.
func _import_card(path: String) -> void:
	var card := card_library.import_png(path)
	if card == null:
		_show_status(
			"“%s” is not a card. Only PNGs made with Download PNG can be imported." % path.get_file(),
			ERROR_COLOR
		)
		return
	_open_card(card)
	_show_status("Imported “%s” into your library." % card.card_name.strip_edges(), SUCCESS_COLOR)


## Sets one field on the card and redraws it.
func _edit(property: StringName, value: Variant) -> void:
	_card.set(property, value)
	_card.emit_changed()


func _on_type_selected(index: int) -> void:
	_edit(&"card_type", CardData.TYPES[index])
	_update_stats_row()


## Attack and defense have their own line, which is only there for cards that have stats.
func _update_stats_row() -> void:
	_stats_row.visible = _card.has_stats()


func _open_image_dialog() -> void:
	_image_dialog.popup_centered_ratio(0.7)


func _load_image(path: String) -> void:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		_show_status("Could not open “%s” as an image." % path.get_file(), ERROR_COLOR)
		return
	_edit(&"image", image)
	_show_status("Loaded “%s”." % path.get_file(), STATUS_COLOR)


func _open_save_dialog() -> void:
	_save_dialog.current_file = "%s.png" % _card.file_stem()
	_save_dialog.popup_centered_ratio(0.7)


## Saves the card as a PNG with the card stored inside it, so it can be imported again.
func _save_png(path: String) -> void:
	if path.get_extension().to_lower() != "png":
		path += ".png"
	# The id travels with the PNG, so every copy someone imports is the same card.
	if _card.id.is_empty():
		_card.id = CardLibrary.new_id()
	await _wait_for_draw()
	var image := _capture_card()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if image == null or file == null:
		var error := FileAccess.get_open_error() if file == null else ERR_UNAVAILABLE
		_show_status("Could not save the PNG (%s)." % error_string(error), ERROR_COLOR)
		return
	file.store_buffer(CardPng.write_card(image.save_png_to_buffer(), _card))
	file.close()
	_show_status("Saved %s" % path, SUCCESS_COLOR)


## Waits until the card viewport has drawn the latest edit, so reading it back is up to date.
func _wait_for_draw() -> void:
	# The headless renderer never draws, so a draw signal would never come.
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw


## The card as currently drawn, or null where nothing is drawn (the headless renderer).
func _capture_card() -> Image:
	return null if DisplayServer.get_name() == "headless" else _viewport.get_texture().get_image()


## Shows a message under the buttons for a few seconds.
func _show_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
	_status.show()
	_status_timer.start(STATUS_SECONDS)
