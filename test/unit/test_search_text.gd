extends GutTest


func _texts(terms: Array[Dictionary]) -> Array[String]:
	var texts: Array[String] = []
	for term in terms:
		texts.append(("\"%s\"" if term["quoted"] else "%s") % term["text"])
	return texts


func test_terms_are_loose_words_and_quoted_text_kept_as_typed() -> void:
	assert_eq(_texts(SearchText.terms("You  \"your P\" deck")), ["you", "\"your p\"", "deck"] as Array[String])
	assert_eq(_texts(SearchText.terms("\"you \"")), ["\"you \""] as Array[String], "spaces in quotes are kept")
	assert_eq(_texts(SearchText.terms("a \"unclosed text ")), ["a", "\"unclosed text \""] as Array[String], "an open quote runs to the end")
	assert_eq(_texts(SearchText.terms("“curly” quotes")), ["\"curly\"", "quotes"] as Array[String])
	assert_eq(SearchText.terms("   ").size(), 0)
	assert_eq(SearchText.terms("\"\"").size(), 0, "an empty pair of quotes asks for nothing")


func test_words_and_contains_all() -> void:
	assert_eq(SearchText.words("Deck \"has no\""), PackedStringArray(["deck", "has no"]))
	assert_true(SearchText.contains_all("a deck has no maximum", SearchText.words("max deck")))
	assert_false(SearchText.contains_all("a deck has no maximum", SearchText.words("\"deck no\"")))
	assert_true(SearchText.contains_all("anything", PackedStringArray()), "no words, nothing to find")


func test_quotes_are_paired_in_any_search_field() -> void:
	var edit := LineEdit.new()
	add_child_autofree(edit)
	edit.gui_input.connect(SearchText.pair_quotes.bind(edit))
	var changes: Array[String] = []
	edit.text_changed.connect(func(text: String) -> void: changes.append(text))
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_QUOTEDBL
	key.unicode = "\"".unicode_at(0)
	edit.gui_input.emit(key)
	assert_eq(edit.text, "\"\"", "typing a quote adds the closing one")
	assert_eq(edit.caret_column, 1)
	assert_eq(changes, ["\"\""] as Array[String], "and the change is reported, since the field would not")


func test_needles_leave_out_words_inside_others_and_put_the_longest_first() -> void:
	assert_eq(SearchText.needles("you decks your"), PackedStringArray(["decks", "your"]), "\"you\" is in \"your\"")
	assert_eq(SearchText.needles("a a ab"), PackedStringArray(["ab"]), "and repeats go too")
	assert_eq(SearchText.needles("\"has no\" no"), PackedStringArray(["has no"]))
	for haystack in ["your deck", "you deck", "a deck"]:
		assert_eq(
			SearchText.contains_all(haystack, SearchText.needles("you deck your")),
			SearchText.contains_all(haystack, SearchText.words("you deck your")),
			"they find the same as all the words: %s" % haystack
		)
