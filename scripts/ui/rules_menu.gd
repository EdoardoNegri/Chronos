extends Control
## Rulebook screen: shows the numbered sections and sub-rules from GameRules, each section in its
## own box. Ideas are not rules, so they take no number and are labeled "Idea" instead.
##
## The search bar filters the rulebook in place: a sub-rule stays only if its number, title or
## text contains every word searched for (ignoring case), and a section with none left is hidden.
## Words can be anywhere, in any order, and match inside longer words: you also finds "your".
## Spaces outside quotes only separate words. Text in quotes ("deck has") must appear exactly as
## typed, spaces included: "your p" finds "your points", and "you " finds "you" but not "your".
## Every search field works this way (see SearchText).
## A section whose own title matches keeps all its sub-rules. Matches are shown in gold.
## The back arrow (or Escape) clears the search first, then goes to the main menu.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const GOLD := Color(0.95, 0.8, 0.45)
const MUTED := Color(0.62, 0.64, 0.74)
const BODY := Color(0.92, 0.9, 0.85)
const ALT_COLOR := Color(0.45, 0.78, 0.88)
const IDEA_COLOR := Color(0.74, 0.64, 0.95)
const SECTION_PADDING := 20

## The rulebook as built, for the search. Each section: "number", "title", "control" and "rules";
## each rule: "number" ("2.4" or "Idea"), "title", "text", "control" and "body" (its text label).
var _sections: Array[Dictionary] = []

@onready var _back_button: Button = %BackButton
@onready var _search_edit: LineEdit = %SearchEdit
@onready var _rules_scroll: ScrollContainer = %RulesScroll
@onready var _rule_list: VBoxContainer = %RuleList
@onready var _no_results_label: Label = %NoResultsLabel


func _ready() -> void:
	_back_button.pressed.connect(_go_back)
	_search_edit.text_changed.connect(func(_text: String) -> void: _apply_search())
	_search_edit.gui_input.connect(SearchText.pair_quotes.bind(_search_edit))
	for i in GameRules.SECTIONS.size():
		_rule_list.add_child(_build_section(i + 1, GameRules.SECTIONS[i]))
	_apply_search()
	_search_edit.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


## Clears the search if there is one, otherwise goes to the main menu.
func _go_back() -> void:
	if not _search_edit.text.strip_edges().is_empty():
		_search_edit.clear()
		_apply_search()
	else:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# --- The rulebook --------------------------------------------------------------------------


## A section as "2. Title" with its own box underneath holding its sub-rules.
func _build_section(number: int, section: Dictionary) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.add_child(_make_label("%d. %s" % [number, section["title"]], 32, GOLD))
	var entry := {
		"number": str(number), "title": section["title"], "control": column, "rules": [],
	}
	_sections.append(entry)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	column.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, SECTION_PADDING)
	panel.add_child(margin)
	var rules := VBoxContainer.new()
	rules.add_theme_constant_override("separation", 16)
	margin.add_child(rules)

	var rule_count := 0
	for rule: Dictionary in section["rules"]:
		if rule.get("idea", false):
			rules.add_child(_add_rule(entry, "Idea", rule, IDEA_COLOR, &"IdeaRuleRow"))
			continue
		rule_count += 1
		var rule_number := "%d.%d" % [number, rule_count]
		rules.add_child(_add_rule(entry, rule_number, rule, GOLD, &"RuleRow"))
		for alternative: Dictionary in rule.get("alternatives", []):
			rules.add_child(_add_rule(entry, rule_number, alternative, ALT_COLOR, &"AlternativeRuleRow"))
	return column


## A rule as "1.2. Title" (or "Idea: Title") with its text in a box underneath, remembered in its
## section for the search.
func _add_rule(
	section: Dictionary, number: String, rule: Dictionary, accent: Color, row_style: StringName
) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	heading.add_child(_make_label(number + (":" if number == "Idea" else "."), 22, accent))
	heading.add_child(_make_label(rule["title"], 22, accent))
	column.add_child(heading)

	var panel := PanelContainer.new()
	panel.theme_type_variation = row_style
	var body := _make_body(20, BODY)
	panel.add_child(body)
	column.add_child(panel)

	(section["rules"] as Array).append({
		"number": number, "title": rule["title"], "text": rule["text"], "control": column,
		"body": body,
	})
	return column


# --- Search --------------------------------------------------------------------------------


## The sections and sub-rules whose own number, title or text contain every word of the query,
## in reading order. Empty for an empty query.
func search(query: String) -> Array[Dictionary]:
	var terms := _words(query)
	var found: Array[Dictionary] = []
	if terms.is_empty():
		return found
	for section in _sections:
		if _matches(section, terms):
			found.append(section)
		for rule: Dictionary in section["rules"]:
			if _matches(rule, terms):
				found.append(rule)
	return found


## Shows only what the search bar matches (everything when it is empty), from the top.
func _apply_search() -> void:
	var terms := _words(_search_edit.text)
	var anything_shown := false
	for section in _sections:
		var keep_all := terms.is_empty() or _matches(section, terms)
		var shown := 0
		for rule: Dictionary in section["rules"]:
			var keep := keep_all or _matches(rule, terms)
			(rule["control"] as Control).visible = keep
			(rule["body"] as RichTextLabel).text = _rule_bbcode(rule["text"], terms)
			if keep:
				shown += 1
		(section["control"] as Control).visible = shown > 0
		anything_shown = anything_shown or shown > 0
	_rules_scroll.visible = anything_shown
	_no_results_label.visible = not anything_shown
	_rules_scroll.scroll_vertical = 0


func _matches(entry: Dictionary, terms: PackedStringArray) -> bool:
	var haystack := _plain("%s %s %s" % [entry["number"], entry["title"], entry.get("text", "")])
	return SearchText.contains_all(haystack, terms)


## What a search looks for, as every search field reads it (see SearchText).
static func _words(query: String) -> PackedStringArray:
	return SearchText.words(_plain(query))


## Lower case on one line, with {notes} as "(notes)" the way the rulebook shows them. Keeps the
## length, so positions in it match positions in the original text.
static func _plain(text: String) -> String:
	return text.to_lower().replace("{", "(").replace("}", ")").replace("\n", " ")


## The rule text as BBCode: each {note} as a blue "(note)", and the searched words in gold.
func _rule_bbcode(text: String, terms: PackedStringArray) -> String:
	var lower := _plain(text)
	var hit: Array[bool] = []
	hit.resize(text.length())
	hit.fill(false)
	for term in terms:
		var at := lower.find(term)
		while at != -1:
			for i in range(at, at + term.length()):
				hit[i] = true
			at = lower.find(term, at + term.length())

	var draft_tag := "[color=#%s]" % ALT_COLOR.to_html(false)
	var hit_tag := "[color=#%s]" % GOLD.to_html(false)
	var out := ""
	var in_draft := false
	var was_draft := false
	var was_hit := false
	for i in text.length():
		var character := text[i]
		if character == "{":
			in_draft = true
			character = "("
		var is_hit: bool = hit[i]
		# Close and reopen the colors whenever either changes, so the tags always nest.
		if in_draft != was_draft or is_hit != was_hit:
			if was_hit:
				out += "[/color]"
			if was_draft:
				out += "[/color]"
			if in_draft:
				out += draft_tag
			if is_hit:
				out += hit_tag
			was_draft = in_draft
			was_hit = is_hit
		if character == "}":
			in_draft = false
			character = ")"
		out += "[lb]" if character == "[" else character
	if was_hit:
		out += "[/color]"
	if was_draft:
		out += "[/color]"
	return out


# --- Helpers -------------------------------------------------------------------------------


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_body(font_size: int, color: Color) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", color)
	return label
