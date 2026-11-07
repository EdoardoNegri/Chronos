extends GutTest


func test_every_section_and_rule_has_title_and_text() -> void:
	for section in GameRules.SECTIONS:
		assert_false(String(section["title"]).is_empty(), "section has a title")
		assert_false((section["rules"] as Array).is_empty(), "section has rules")
		for rule in section["rules"]:
			assert_false(String(rule["title"]).is_empty(), "rule has a title")
			assert_false(String(rule["text"]).is_empty(), "rule has text")


func test_alternatives_have_title_and_text() -> void:
	for section in GameRules.SECTIONS:
		for rule: Dictionary in section["rules"]:
			for alternative: Dictionary in rule.get("alternatives", []):
				assert_false(String(alternative["title"]).is_empty(), "alternative has a title")
				assert_false(String(alternative["text"]).is_empty(), "alternative has text")


func test_rules_scene_builds_a_heading_and_row_per_rule() -> void:
	var scene: Control = load("res://scenes/rules.tscn").instantiate()
	add_child_autofree(scene)
	var list: VBoxContainer = scene.get_node("%RuleList")
	assert_eq(list.get_child_count(), GameRules.SECTIONS.size())
	for i in GameRules.SECTIONS.size():
		var section := list.get_child(i)
		assert_eq(section.get_child_count(), 2, "section %d: heading and box" % (i + 1))
		var expected := 0
		for rule: Dictionary in GameRules.SECTIONS[i]["rules"]:
			expected += 1 + (rule.get("alternatives", []) as Array).size()
		assert_eq(_section_rules(section).get_child_count(), expected, "section %d" % (i + 1))


## The sub-rules of a section: heading, then box > margin > rules.
func _section_rules(section: Node) -> Node:
	return section.get_child(1).get_child(0).get_child(0)


func test_rules_scene_numbers_rules_and_alternatives_share_the_number() -> void:
	var scene: Control = load("res://scenes/rules.tscn").instantiate()
	add_child_autofree(scene)
	var list: VBoxContainer = scene.get_node("%RuleList")
	for i in GameRules.SECTIONS.size():
		var expected: Array[String] = []
		var rules: Array = GameRules.SECTIONS[i]["rules"]
		for r in rules.size():
			var number := "%d.%d." % [i + 1, r + 1]
			expected.append(number)
			for _alternative in (rules[r] as Dictionary).get("alternatives", []):
				expected.append(number)
		var labels: Array[String] = []
		for rule in _section_rules(list.get_child(i)).get_children():
			var number_label: Label = rule.get_child(0).get_child(0)
			labels.append(number_label.text)
		assert_eq(labels, expected, "section %d" % (i + 1))


func _titles(found: Array[Dictionary]) -> Array[String]:
	var titles: Array[String] = []
	for entry in found:
		titles.append(String(entry["title"]))
	return titles


func test_rules_search_finds_titles_and_text_ignoring_case() -> void:
	var scene: Control = load("res://scenes/rules.tscn").instantiate()
	add_child_autofree(scene)
	var by_title := _titles(scene.search("MULLIGAN"))
	assert_has(by_title, "Mulligan")
	assert_has(by_title, "Whole-hand mulligan", "alternatives are found too")
	assert_has(_titles(scene.search("coin toss")), "Who starts", "words in the text count")
	assert_has(_titles(scene.search("starting the")), "Starting the game", "sections are found")


func test_rules_search_needs_every_word() -> void:
	var scene: Control = load("res://scenes/rules.tscn").instantiate()
	add_child_autofree(scene)
	assert_eq(scene.search("mulligan zzzz").size(), 0)
	assert_eq(scene.search("   ").size(), 0, "an empty search finds nothing")


## Titles of the sub-rules shown in a section, and whether the section itself is shown.
func _shown_rules(section: Control) -> Array[String]:
	var titles: Array[String] = []
	for rule: Control in _section_rules(section).get_children():
		if rule.visible:
			titles.append((rule.get_child(0).get_child(1) as Label).text)
	return titles


func _search_for(scene: Control, query: String) -> void:
	var search_edit: LineEdit = scene.get_node("%SearchEdit")
	search_edit.text = query
	search_edit.text_changed.emit(query)


func test_rules_search_filters_the_rulebook_in_place() -> void:
	var scene: Control = load("res://scenes/rules.tscn").instantiate()
	add_child_autofree(scene)
	var list: VBoxContainer = scene.get_node("%RuleList")
	var deck: Control = list.get_child(0)
	var starting: Control = list.get_child(1)

	_search_for(scene, "mulligan")
	assert_false(deck.visible, "a section with no matching sub-rules is hidden")
	assert_true(starting.visible)
	var shown := _shown_rules(starting)
	assert_has(shown, "Mulligan")
	assert_does_not_have(shown, "Who starts", "sub-rules without the word are hidden")

	_search_for(scene, "deck")
	assert_true(deck.visible)
	assert_eq(
		_shown_rules(deck).size(), _section_rules(deck).get_child_count(),
		"a section whose title matches keeps all its sub-rules"
	)

	_search_for(scene, "zzzz")
	assert_true((scene.get_node("%NoResultsLabel") as Control).visible, "says nothing matched")
	assert_false((scene.get_node("%RulesScroll") as Control).visible)

	_search_for(scene, "")
	assert_true((scene.get_node("%RulesScroll") as Control).visible, "empty search shows everything")
	for section: Control in list.get_children():
		assert_true(section.visible)
		assert_eq(_shown_rules(section).size(), _section_rules(section).get_child_count())


func test_rules_search_quotes_mean_an_exact_phrase() -> void:
	var scene: Control = load("res://scenes/rules.tscn").instantiate()
	add_child_autofree(scene)
	var phrase := _titles(scene.search("\"deck has\""))
	assert_has(phrase, "Minimum size")
	assert_has(phrase, "Bigger decks")
	assert_does_not_have(phrase, "Deck", "the section title alone has no \"deck has\"")
	assert_has(_titles(scene.search("has deck")), "Minimum size", "loose words can be in any order")
	assert_eq(scene.search("\"has deck\"").size(), 0, "a phrase must be in that order")
	assert_eq(_titles(scene.search("\"deck has\" 101")), ["Bigger decks"] as Array[String], "phrase and word together")
	assert_has(_titles(scene.search("\"deck ha")), "Minimum size", "an unclosed quote runs to the end")


func test_rules_search_counts_spaces_only_inside_quotes() -> void:
	var scene: Control = load("res://scenes/rules.tscn").instantiate()
	add_child_autofree(scene)
	# "Draw" says "your deck" but never the word "you" on its own, and "Point budget" says
	# "your points".
	var loose := _titles(scene.search("you"))
	assert_has(loose, "Draw", "a loose word also matches inside longer words")
	assert_has(loose, "Point budget")

	var with_space := _titles(scene.search("\"you \""))
	assert_has(with_space, "Point budget", "\"you \" finds the word you")
	assert_does_not_have(with_space, "Draw", "the space keeps \"your\" out")
	assert_eq(_titles(scene.search("\"YOU \"")), with_space, "quoted text still ignores case")

	var partial := _titles(scene.search("\"your p\""))
	assert_has(partial, "Point budget", "\"your p\" finds \"your points\"")
	assert_does_not_have(partial, "Draw")
	assert_eq(scene.search("\"your  p\"").size(), 0, "two spaces in quotes are two spaces")

	assert_eq(_titles(scene.search("  you   ")), loose, "spaces outside quotes are ignored")
	assert_has(_titles(scene.search("\"your p")), "Point budget", "an unclosed quote runs to the end")


func _press(edit: LineEdit, keycode: Key, unicode := 0) -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = keycode
	key.unicode = unicode
	edit.gui_input.emit(key)


func test_rules_search_pairs_quotes() -> void:
	var scene: Control = load("res://scenes/rules.tscn").instantiate()
	add_child_autofree(scene)
	var edit: LineEdit = scene.get_node("%SearchEdit")
	var quote := "\"".unicode_at(0)

	_press(edit, KEY_QUOTEDBL, quote)
	assert_eq(edit.text, "\"\"", "typing a quote adds the closing one")
	assert_eq(edit.caret_column, 1, "with the caret between them")

	edit.text = "\"deck has\""
	edit.caret_column = 9
	_press(edit, KEY_QUOTEDBL, quote)
	assert_eq(edit.text, "\"deck has\"", "typing the closing quote steps over it")
	assert_eq(edit.caret_column, 10)

	edit.text = "a \"\""
	edit.caret_column = 3
	_press(edit, KEY_BACKSPACE)
	assert_eq(edit.text, "a ", "backspace in an empty pair removes both")

	edit.text = "deck has"
	edit.select(0, 8)
	_press(edit, KEY_QUOTEDBL, quote)
	assert_eq(edit.text, "\"deck has\"", "quotes go around the selection")
