class_name NumberedSections
extends RefCounted
## The layout the rulebook and the settings share: sections ("2. Online", or just "Online"), each
## with its own box, holding items ("2.1. Name", or just "Name") with what belongs to them in a box
## underneath. Sections numbered 0 and items numbered "" show their title alone. And
## the search that goes with it: an item stays if its number, title or text holds every word
## searched for (see SearchText); a section whose own title matches keeps all its items, and a
## section with none left is hidden.
##
## A section is a Dictionary: "number", "title", "search" (what is searched, in lower case),
## "control" (to show or hide), "list" (where its items go) and "items". An item is the same
## without "list" and "items", plus anything the screen keeps in it.

const GOLD := Color(0.95, 0.8, 0.45)
const BODY := Color(0.92, 0.9, 0.85)
const SECTION_FONT_SIZE := 32
const ITEM_FONT_SIZE := 22
const BODY_FONT_SIZE := 20
const SECTION_PADDING := 20


## A section as "2. Title" (or "Title" for number 0) with its own box underneath. Add the
## section's "control" to the page, and its items with add_item.
static func make_section(number: int, title: String, search_text := "") -> Dictionary:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	var heading := "%d. %s" % [number, title] if number > 0 else title
	column.add_child(make_label(heading, SECTION_FONT_SIZE, GOLD))
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	column.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, SECTION_PADDING)
	panel.add_child(margin)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 16)
	margin.add_child(list)
	return {
		"number": str(number),
		"title": title,
		"search": (search_text if not search_text.is_empty() else heading).to_lower(),
		"control": column,
		"list": list,
		"items": [],
	}


## Adds an item to a section: "1.2. Title" ("Idea: Title", or just "Title" for number "") in
## `accent`, with `content` in a box of style `row_style` underneath. `search_text` is what the
## search looks through besides the number and title. Returns the item, to keep more in it.
static func add_item(
	section: Dictionary,
	number: String,
	title: String,
	content: Control,
	search_text := "",
	accent := GOLD,
	row_style := &"RuleRow",
) -> Dictionary:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	if not number.is_empty():
		heading.add_child(make_label(number + (":" if not number[0].is_valid_int() else "."), ITEM_FONT_SIZE, accent))
	heading.add_child(make_label(title, ITEM_FONT_SIZE, accent))
	column.add_child(heading)
	var panel := PanelContainer.new()
	panel.theme_type_variation = row_style
	panel.add_child(content)
	column.add_child(panel)
	(section["list"] as VBoxContainer).add_child(column)
	var item := {
		"number": number,
		"title": title,
		"search": ("%s %s %s" % [number, title, search_text]).to_lower(),
		"control": column,
	}
	(section["items"] as Array).append(item)
	return item


## Whether a section or item holds every word of `terms` (see SearchText.needles).
static func matches(entry: Dictionary, terms: PackedStringArray) -> bool:
	return SearchText.contains_all(entry["search"], terms)


## Shows what `terms` match (everything when there are none) and hides the rest. Returns whether
## anything is shown.
static func filter(sections: Array[Dictionary], terms: PackedStringArray) -> bool:
	var anything_shown := false
	for section in sections:
		var keep_all := terms.is_empty() or matches(section, terms)
		var shown := 0
		for item: Dictionary in section["items"]:
			var keep := keep_all or matches(item, terms)
			(item["control"] as Control).visible = keep
			if keep:
				shown += 1
		(section["control"] as Control).visible = shown > 0
		anything_shown = anything_shown or shown > 0
	return anything_shown


## The sections and items that `terms` match themselves, in reading order. Empty for no terms.
static func search(sections: Array[Dictionary], terms: PackedStringArray) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if terms.is_empty():
		return found
	for section in sections:
		if matches(section, terms):
			found.append(section)
		for item: Dictionary in section["items"]:
			if matches(item, terms):
				found.append(item)
	return found


static func make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Text that wraps, in the item boxes' style.
static func make_body(font_size := BODY_FONT_SIZE, color := BODY) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", color)
	return label
