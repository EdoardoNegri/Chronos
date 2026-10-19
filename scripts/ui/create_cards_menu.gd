extends Control
## Card maker: edit a card, see it live, and download it as a PNG.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const STATUS_COLOR := Color(0.62, 0.64, 0.74)
const ERROR_COLOR := Color(0.9, 0.5, 0.45)
const SUCCESS_COLOR := Color(0.5, 0.82, 0.55)
const IMAGE_FILTERS: Array[String] = ["*.png, *.jpg, *.jpeg, *.webp ; Images"]
const PNG_FILTERS: Array[String] = ["*.png ; PNG image"]

var card_library := CardLibrary.new()

var _card := CardData.new()
var _card_view := CardView.new()
var _back_view := CardBack.new()
var _image_dialog: FileDialog
var _save_dialog: FileDialog

@onready var _back_button: Button = %BackButton
@onready var _name_edit: LineEdit = %NameEdit
@onready var _type_option: OptionButton = %TypeOption
@onready var _subtype_edit: LineEdit = %SubtypeEdit
@onready var _time_spin: SpinBox = %TimeSpin
@onready var _points_spin: SpinBox = %PointsSpin
@onready var _stats_row: HBoxContainer = %StatsRow
@onready var _attack_spin: SpinBox = %AttackSpin
@onready var _defense_spin: SpinBox = %DefenseSpin
@onready var _rules_edit: TextEdit = %RulesEdit
@onready var _choose_image_button: Button = %ChooseImageButton
@onready var _clear_image_button: Button = %ClearImageButton
@onready var _preview: TextureRect = %Preview
@onready var _show_back_check: CheckButton = %ShowBackCheck
@onready var _status: Label = %Status
@onready var _download_button: Button = %DownloadButton
@onready var _new_card_button: Button = %NewCardButton
@onready var _save_card_button: Button = %SaveCardButton
@onready var _viewport: SubViewport = %CardViewport


func _ready() -> void:
	_viewport.add_child(_card_view)
	_viewport.add_child(_back_view)
	_back_view.hide()
	_card_view.card = _card
	_preview.texture = _viewport.get_texture()

	for card_type in CardData.TYPES:
		_type_option.add_item(card_type)
	_update_stats_row()

	_back_button.pressed.connect(_go_back)
	_name_edit.text_changed.connect(func(text: String) -> void: _edit(&"card_name", text))
	_subtype_edit.text_changed.connect(func(text: String) -> void: _edit(&"subtype", text))
	_time_spin.value_changed.connect(func(value: float) -> void: _edit(&"time_cost", int(value)))
	_points_spin.value_changed.connect(func(value: float) -> void: _edit(&"points", int(value)))
	_attack_spin.value_changed.connect(func(value: float) -> void: _edit(&"attack", int(value)))
	_defense_spin.value_changed.connect(func(value: float) -> void: _edit(&"defense", int(value)))
	_rules_edit.text_changed.connect(func() -> void: _edit(&"rules_text", _rules_edit.text))
	_type_option.item_selected.connect(_on_type_selected)
	_choose_image_button.pressed.connect(_open_image_dialog)
	_clear_image_button.pressed.connect(func() -> void: _edit(&"image", null))
	_show_back_check.toggled.connect(_show_back)
	_download_button.pressed.connect(_open_save_dialog)
	_new_card_button.pressed.connect(_new_card)
	_save_card_button.pressed.connect(_save_to_library)

	_image_dialog = _make_dialog(FileDialog.FILE_MODE_OPEN_FILE, IMAGE_FILTERS)
	_image_dialog.file_selected.connect(_load_image)
	_save_dialog = _make_dialog(FileDialog.FILE_MODE_SAVE_FILE, PNG_FILTERS)
	_save_dialog.file_selected.connect(_save_png)

	_show_status("Fill in the card, save it to your library, or download it as a PNG.", STATUS_COLOR)
	_name_edit.grab_focus()


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


## Starts a blank card.
func _new_card() -> void:
	_card = CardData.new()
	_card_view.card = _card
	_sync_form()
	_show_status("Started a new card.", STATUS_COLOR)
	_name_edit.grab_focus()


## Copies the card's fields into the form controls.
func _sync_form() -> void:
	_name_edit.text = _card.card_name
	_subtype_edit.text = _card.subtype
	_type_option.select(CardData.TYPES.find(_card.card_type))
	_time_spin.value = _card.time_cost
	_points_spin.value = _card.points
	_attack_spin.value = _card.attack
	_defense_spin.value = _card.defense
	_rules_edit.text = _card.rules_text
	_update_stats_row()


## Saves the card to the library so decks can use it. Saving again updates the same card.
func _save_to_library() -> void:
	if _card.card_name.strip_edges().is_empty():
		_show_status("Give the card a name before saving it.", ERROR_COLOR)
		_name_edit.grab_focus()
		return
	# The library keeps a picture of the front, so make sure the front is what is drawn.
	if _show_back_check.button_pressed:
		_show_back_check.button_pressed = false
	await _wait_for_draw()
	await _wait_for_draw()
	var error := card_library.save_card(_card, _capture_card())
	if error == OK:
		_show_status("Saved “%s” to your library." % _card.card_name.strip_edges(), SUCCESS_COLOR)
	else:
		_show_status("Could not save the card (%s)." % error_string(error), ERROR_COLOR)


## Sets one field on the card and redraws it.
func _edit(property: StringName, value: Variant) -> void:
	_card.set(property, value)
	_card.emit_changed()


func _on_type_selected(index: int) -> void:
	_edit(&"card_type", CardData.TYPES[index])
	_update_stats_row()


## Previews, and exports, the back of the card instead of the front.
func _show_back(show_back: bool) -> void:
	_card_view.visible = not show_back
	_back_view.visible = show_back


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
	var stem := "card_back" if _back_view.visible else _card.file_stem()
	_save_dialog.current_file = "%s.png" % stem
	_save_dialog.popup_centered_ratio(0.7)


func _save_png(path: String) -> void:
	if path.get_extension().to_lower() != "png":
		path += ".png"
	await _wait_for_draw()
	var error := _capture_card().save_png(path)
	if error == OK:
		_show_status("Saved %s" % path, SUCCESS_COLOR)
	else:
		_show_status("Could not save the PNG (%s)." % error_string(error), ERROR_COLOR)


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


func _show_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
