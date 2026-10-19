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
