extends Control
## Rulebook screen: shows the numbered sections and sub-rules from GameRules.
## Ideas are not rules, so they take no number and are labeled "Idea" instead.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const GOLD := Color(0.95, 0.8, 0.45)
const MUTED := Color(0.62, 0.64, 0.74)
const BODY := Color(0.92, 0.9, 0.85)
const ALT_COLOR := Color(0.45, 0.78, 0.88)
const IDEA_COLOR := Color(0.74, 0.64, 0.95)
const NUMBER_WIDTH := 64
const RULE_INDENT := 24

@onready var _back_button: Button = %BackButton
@onready var _rule_list: VBoxContainer = %RuleList


func _ready() -> void:
	_back_button.pressed.connect(_go_back)
	for i in GameRules.SECTIONS.size():
		_rule_list.add_child(_build_section(i + 1, GameRules.SECTIONS[i]))
	_back_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


func _go_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _build_section(number: int, section: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.add_child(_make_label("%d. %s" % [number, section["title"]], 32, GOLD))
	var rule_count := 0
	for rule: Dictionary in section["rules"]:
		if rule.get("idea", false):
			box.add_child(_indent(_build_rule("Idea", rule, IDEA_COLOR, &"IdeaRuleRow")))
			continue
		rule_count += 1
		var rule_number := "%d.%d" % [number, rule_count]
		box.add_child(_indent(_build_rule(rule_number, rule, GOLD, &"RuleRow")))
		for alternative: Dictionary in rule.get("alternatives", []):
			box.add_child(_indent(_build_rule(rule_number, alternative, ALT_COLOR, &"AlternativeRuleRow")))
	return box


func _indent(content: Control) -> Control:
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", RULE_INDENT)
	indent.add_child(content)
	return indent


func _build_rule(number: String, rule: Dictionary, accent: Color, row_style: StringName) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = row_style

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	var number_label := _make_label(number, 24, accent)
	number_label.custom_minimum_size.x = NUMBER_WIDTH
	number_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	row.add_child(number_label)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	row.add_child(column)

	column.add_child(_make_label(rule["title"], 22, accent))
	column.add_child(_make_body(rule["text"], 20, BODY))
	return panel


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_body(text: String, font_size: int, color: Color) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", color)
	label.text = _mark_drafts(text)
	return label


## Turns each inline {note} into a blue "(note)".
func _mark_drafts(text: String) -> String:
	var open_tag := "[color=#%s](" % ALT_COLOR.to_html(false)
	return text.replace("{", open_tag).replace("}", ")[/color]")
