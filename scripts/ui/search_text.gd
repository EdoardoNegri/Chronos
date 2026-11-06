class_name SearchText
extends RefCounted
## How search fields read what is typed in them, the same everywhere (the rulebook, the card
## database, the deck builder and the room list):
##
## - Words are loose: each one must be found, anywhere and in any order, even inside a longer word,
##   so "you" also finds "your". Capitals do not matter and spaces outside quotes only separate
##   words.
## - Text in quotes ("deck has") must be found exactly as typed, spaces included: "your p" finds
##   "your points", and "you " finds "you" but not "your".
## - A quote that is not closed yet runs to the end of the text, so results narrow while typing.

const QUOTE := "\""


## What a search looks for, in the order typed, in lower case. Each term is {"text", "quoted"}: a
## loose word, or the text between a pair of quotes, spaces included.
static func terms(query: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var parts := query.replace("“", QUOTE).replace("”", QUOTE).to_lower().split(QUOTE)
	for i in parts.size():
		if i % 2 == 1:
			if not parts[i].is_empty():
				found.append({"text": parts[i], "quoted": true})
		else:
			for word in parts[i].split(" ", false):
				found.append({"text": word, "quoted": false})
	return found


## Just the texts of terms(): what has to be found, for searches where every term must be.
static func words(query: String) -> PackedStringArray:
	var found := PackedStringArray()
	for term in terms(query):
		found.append(term["text"])
	return found


## What has to be found, made quick to look for: words found inside another word are left out
## ("you" when "your" is searched for: whatever holds "your" holds "you"), and the rest come
## longest first, since they rule out most. Use it with contains_all.
static func needles(query: String) -> PackedStringArray:
	var unique: Array[String] = []
	for word in words(query):
		if not unique.has(word):
			unique.append(word)
	unique.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var found := PackedStringArray()
	for word in unique:
		var inside_another := false
		for kept in found:
			if kept.contains(word):
				inside_another = true
				break
		if not inside_another:
			found.append(word)
	return found


## Whether every word is in `haystack`, which must already be lower case.
static func contains_all(haystack: String, wanted: PackedStringArray) -> bool:
	for word in wanted:
		if not haystack.contains(word):
			return false
	return true


## Quotes in a search field come in pairs: typing " puts in both with the caret between them (or
## puts them around the selected text). Typing " right before the closing one steps over it, and
## backspace between an empty pair removes both. Connect to the field's gui_input with the field
## bound: `edit.gui_input.connect(SearchText.pair_quotes.bind(edit))`.
static func pair_quotes(event: InputEvent, edit: LineEdit) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	var text := edit.text
	var caret := edit.caret_column
	var inside_phrase := text.left(caret).count(QUOTE) % 2 == 1
	if key.unicode == QUOTE.unicode_at(0):
		if edit.has_selection():
			var from := edit.get_selection_from_column()
			var to := edit.get_selection_to_column()
			edit.deselect()
			_set_text(edit, text.left(from) + QUOTE + text.substr(from, to - from) + QUOTE + text.substr(to), to + 2)
		elif inside_phrase and text.substr(caret, 1) == QUOTE:
			edit.caret_column = caret + 1
		else:
			_set_text(edit, text.left(caret) + QUOTE + QUOTE + text.substr(caret), caret + 1)
		edit.accept_event()
	elif (
		key.keycode == KEY_BACKSPACE
		and not (key.ctrl_pressed or key.alt_pressed or key.meta_pressed)
		and not edit.has_selection()
		and caret > 0
		and text.substr(caret - 1, 2) == QUOTE + QUOTE
		and inside_phrase
	):
		_set_text(edit, text.left(caret - 1) + text.substr(caret + 1), caret - 1)
		edit.accept_event()


## Changes the field's text from code, which LineEdit does not report, so it is reported here.
static func _set_text(edit: LineEdit, text: String, caret: int) -> void:
	edit.text = text
	edit.caret_column = caret
	edit.text_changed.emit(text)
