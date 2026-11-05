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
		var expected := 1
		for rule: Dictionary in GameRules.SECTIONS[i]["rules"]:
			expected += 1 + (rule.get("alternatives", []) as Array).size()
		assert_eq(list.get_child(i).get_child_count(), expected, "section %d" % (i + 1))


func test_ideas_have_no_alternatives() -> void:
	for section in GameRules.SECTIONS:
		for rule: Dictionary in section["rules"]:
			if rule.get("idea", false):
				assert_false(rule.has("alternatives"), "idea \"%s\" has no alternatives" % rule["title"])


func test_rules_scene_labels_ideas_and_skips_them_in_numbering() -> void:
	var scene: Control = load("res://scenes/rules.tscn").instantiate()
	add_child_autofree(scene)
	var list: VBoxContainer = scene.get_node("%RuleList")
	var time_index := -1
	for i in GameRules.SECTIONS.size():
		if GameRules.SECTIONS[i]["title"] == "Time":
			time_index = i
	assert_ne(time_index, -1, "there is a Time section")
	var labels: Array[String] = []
	for row in list.get_child(time_index).get_children().slice(1):
		var number_label: Label = row.get_child(0).get_child(0).get_child(0)
		labels.append(number_label.text)
	var n := time_index + 1
	assert_eq(labels, ["%d.1" % n, "%d.2" % n, "%d.3" % n, "%d.4" % n, "Idea"])
