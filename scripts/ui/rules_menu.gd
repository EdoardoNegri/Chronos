extends Control
## Rulebook screen: shows the numbered sections and sub-rules from GameRules, each section in its
## own box (see NumberedSections, which the settings share).
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
const GOLD := NumberedSections.GOLD
const ALT_COLOR := Color(0.45, 0.78, 0.88)

## The rulebook as built, for the search (see NumberedSections). Each rule also keeps its "text"
## and "body" (its text label, where the searched words are shown).
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
	var entry := NumberedSections.make_section(number, section["title"], _plain("%d %s" % [number, section["title"]]))
	_sections.append(entry)
	for i in section["rules"].size():
		var rule: Dictionary = section["rules"][i]
		var rule_number := "%d.%d" % [number, i + 1]
		_add_rule(entry, rule_number, rule, GOLD, &"RuleRow")
		for alternative: Dictionary in rule.get("alternatives", []):
			_add_rule(entry, rule_number, alternative, ALT_COLOR, &"AlternativeRuleRow")
	return entry["control"]


## A rule as "1.2. Title" with its text in a box underneath.
func _add_rule(section: Dictionary, number: String, rule: Dictionary, accent: Color, row_style: StringName) -> void:
	var body := NumberedSections.make_body()
	var item := NumberedSections.add_item(section, number, rule["title"], body, _plain(rule["text"]), accent, row_style)
	item["text"] = rule["text"]
	item["body"] = body


# --- Search --------------------------------------------------------------------------------


## The sections and sub-rules whose own number, title or text contain every word of the query,
## in reading order. Empty for an empty query.
func search(query: String) -> Array[Dictionary]:
	return NumberedSections.search(_sections, _words(query))


## Shows only what the search bar matches (everything when it is empty), from the top.
func _apply_search() -> void:
	var terms := _words(_search_edit.text)
	var anything_shown := NumberedSections.filter(_sections, terms)
	for section in _sections:
		for rule: Dictionary in section["items"]:
			(rule["body"] as RichTextLabel).text = _rule_bbcode(rule["text"], terms)
	_rules_scroll.visible = anything_shown
	_no_results_label.visible = not anything_shown
	_rules_scroll.scroll_vertical = 0


## What a search looks for, as every search field reads it (see SearchText).
static func _words(query: String) -> PackedStringArray:
	return SearchText.needles(_plain(query))


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
