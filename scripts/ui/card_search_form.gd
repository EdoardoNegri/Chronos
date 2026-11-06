class_name CardSearchForm
extends VBoxContainer
## The card search form, shared by the card database and the deck builder: a name, a type, a
## subtype, card text, number filters and the "Cards" choice (official cards, custom cards or
## both). Its text fields read what is typed like every search field does (see SearchText), and
## Type and Subtype suggest words as you type (see WordSuggestions).
##
## The form is turned into a CardQuery search behind the scenes. Call setup() with the cards, then
## search() to filter them. `changed` is emitted whenever a field is edited (for searching live) and
## `submitted` when Enter is pressed in a text field.

signal changed
signal submitted

## What the "Cards" choice searches: the official cards, the custom ones (the cards the player
## created or imported), or both.
const SOURCES: Array[String] = ["Official cards", "Custom cards", "Both"]
const SOURCE_OFFICIAL := 0
const SOURCE_CUSTOM := 1
const SOURCE_BOTH := 2
## Comparisons for the number filters: label in the form and operator in the search syntax.
const COMPARISONS := [["Any", ""], ["=", "="], ["≠", "!="], ["≤", "<="], ["≥", ">="]]
## Number filters in the form: label, search keyword and highest value.
const NUMBER_FILTERS := [["Time cost", "time", 999], ["Points", "pts", 100], ["Attack", "atk", 99], ["Defense", "def", 99]]

## How wide the "Cards" choice is beside the name, as the scene has it.
const SOURCE_FIELD_WIDTH := 250.0

## In a narrow place the name and the "Cards" choice are stacked instead of side by side, and the
## number filters are one to a row, with their label on the left.
var compact := false:
	set(value):
		compact = value
		if is_node_ready():
			_apply_layout()

var _catalog: CardCatalog
var _cards: Array[CardData] = []
var _type_suggestions: WordSuggestions
var _subtype_suggestions: WordSuggestions
## For each number filter: {"comparison": OptionButton, "value": NumberStepper, "key": String}.
var _number_filters: Array[Dictionary] = []
## The box of each number filter: its label and its comparison and value.
var _number_fields: Array[BoxContainer] = []

@onready var _top_row: BoxContainer = %TopRow
@onready var _source_field: Control = %SourceField
@onready var _name_edit: LineEdit = %NameEdit
@onready var _source_option: OptionButton = %CardSourceOption
@onready var _type_edit: LineEdit = %TypeEdit
@onready var _subtype_edit: LineEdit = %SubtypeEdit
@onready var _card_text_edit: LineEdit = %CardTextEdit
@onready var _numbers_row: GridContainer = %NumbersRow


func _ready() -> void:
	for source_name in SOURCES:
		_source_option.add_item(source_name)
	_source_option.item_selected.connect(func(_index: int) -> void: changed.emit())
	_build_number_filters()
	_apply_layout()

	_type_suggestions = WordSuggestions.new()
	_type_suggestions.attach(_type_edit, self, _available_types)
	_subtype_suggestions = WordSuggestions.new()
	_subtype_suggestions.attach(_subtype_edit, self, _available_subtypes)
	for field: LineEdit in [_name_edit, _type_edit, _subtype_edit, _card_text_edit]:
		field.text_changed.connect(func(_text: String) -> void: changed.emit())
		field.text_submitted.connect(func(_text: String) -> void: submitted.emit())
		field.gui_input.connect(SearchText.pair_quotes.bind(field))


## The cards to search and which of them are custom (for the "Cards" choice and the suggestions).
func setup(cards: Array[CardData], catalog: CardCatalog) -> void:
	_cards = cards
	_catalog = catalog


## The cards that match the form, in the order given to setup().
func search(cards: Array[CardData], points_list: PointsList = null) -> Array[CardData]:
	return CardQuery.parse(form_query(), points_list).filter(cards.filter(is_searched))


## Whether the "Cards" choice covers this card.
func is_searched(card: CardData) -> bool:
	if _catalog == null:
		return true
	match _source_option.selected:
		SOURCE_OFFICIAL:
			return not _catalog.is_custom(card.id)
		SOURCE_CUSTOM:
			return _catalog.is_custom(card.id)
	return true


## The "Cards" choice: SOURCE_OFFICIAL, SOURCE_CUSTOM or SOURCE_BOTH.
func source() -> int:
	return _source_option.selected


func set_source(index: int) -> void:
	_source_option.select(index)


## How many things the form filters by (the "Cards" choice is not counted).
func active_count() -> int:
	var count := 0
	for field: LineEdit in [_name_edit, _type_edit, _subtype_edit, _card_text_edit]:
		if not field.text.strip_edges().is_empty():
			count += 1
	for entry in _number_filters:
		if (entry["comparison"] as OptionButton).selected > 0:
			count += 1
	return count


## Empties every field; the "Cards" choice stays as it is.
func clear() -> void:
	for field: LineEdit in [_name_edit, _type_edit, _subtype_edit, _card_text_edit]:
		field.clear()
	for entry in _number_filters:
		(entry["value"] as NumberStepper).value = 0
		(entry["comparison"] as OptionButton).select(0)
		_dim_unused(entry)
	close_suggestions()
	changed.emit()


func focus_name() -> void:
	_name_edit.grab_focus()


func close_suggestions() -> void:
	if _type_suggestions != null:
		_type_suggestions.close()
		_subtype_suggestions.close()


# --- The query -----------------------------------------------------------------------------


## The form as a search in CardQuery's syntax, e.g. 'drake ct:creature st:elf time>=20'. Name and
## card text read like every search field does (see SearchText). Type and subtype take
## alternatives: separate words find cards with any of them ("warrior elf": all warriors and all
## elves), and the words between a pair of quotes must all match ("warrior elf": only cards that are
## both). A CardQuery cannot group alternatives, so each combination is written out in full and
## they are joined with "or".
func form_query() -> String:
	var names := PackedStringArray()
	for term in SearchText.terms(_name_edit.text):
		names.append(_quoted(term) if term["quoted"] else _quote_if_needed(term["text"]))
	var texts := PackedStringArray()
	for term in SearchText.terms(_card_text_edit.text):
		texts.append("o:" + (_quoted(term) if term["quoted"] else _quote_if_needed(term["text"])))
	var numbers := PackedStringArray()
	for entry in _number_filters:
		var operator: String = COMPARISONS[(entry["comparison"] as OptionButton).selected][1]
		if not operator.is_empty():
			numbers.append("%s%s%d" % [entry["key"], operator, (entry["value"] as NumberStepper).value])

	var queries := PackedStringArray()
	for type_terms in _alternatives(_type_edit.text, "ct"):
		for subtype_terms in _alternatives(_subtype_edit.text, "st"):
			var terms := PackedStringArray()
			terms.append_array(names)
			terms.append_array(type_terms)
			terms.append_array(subtype_terms)
			terms.append_array(texts)
			terms.append_array(numbers)
			queries.append(" ".join(terms))
	return " or ".join(queries)


## What a Type or Subtype field asks for, as alternatives that are each a list of search terms
## (`key`:word) that must all match: one alternative per loose word, and one per pair of quotes,
## holding all the words inside it. A field with no words is a single alternative with no terms.
static func _alternatives(field_text: String, key: String) -> Array[PackedStringArray]:
	var alternatives: Array[PackedStringArray] = []
	for term in SearchText.terms(field_text.replace(",", " ")):
		var alternative := PackedStringArray()
		for word in (term["text"] as String).split(" ", false):
			alternative.append("%s:%s" % [key, _quote_if_needed(word)])
		if not alternative.is_empty():
			alternatives.append(alternative)
	if alternatives.is_empty():
		alternatives.append(PackedStringArray())
	return alternatives


## A term typed in quotes, as a quoted phrase in the search (so always a name search).
static func _quoted(term: Dictionary) -> String:
	return "\"%s\"" % term["text"]


## Puts text that would otherwise be read as syntax (spaces, ":", a leading "-", "or") in quotes.
static func _quote_if_needed(text: String) -> String:
	var plain := text.replace("\"", "")
	var needs_quotes := (
		plain.contains(" ")
		or plain.contains(":")
		or plain.begins_with("-")
		or plain.to_lower() == "or"
	)
	return "\"%s\"" % plain if needs_quotes else plain


# --- Number filters ------------------------------------------------------------------------


## Lays the form out for a wide or a narrow (compact) place.
func _apply_layout() -> void:
	_top_row.vertical = compact
	_source_field.custom_minimum_size.x = 0.0 if compact else SOURCE_FIELD_WIDTH
	_numbers_row.columns = 1 if compact else 2
	for field in _number_fields:
		field.vertical = not compact
		field.add_theme_constant_override("separation", 12 if compact else 4)


## A field per number filter, two to a row: a comparison (Any, =, ≠, ≤, ≥) and a value.
func _build_number_filters() -> void:
	for filter: Array in NUMBER_FILTERS:
		var field := BoxContainer.new()
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_number_fields.append(field)
		var label := Label.new()
		label.theme_type_variation = &"FieldLabel"
		label.text = filter[0]
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		field.add_child(label)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var comparison := OptionButton.new()
		for item: Array in COMPARISONS:
			comparison.add_item(item[0])
		comparison.custom_minimum_size = Vector2(92, 0)
		row.add_child(comparison)
		var value := NumberStepper.new()
		value.max_value = filter[2]
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(value)
		field.add_child(row)
		_numbers_row.add_child(field)

		var entry := {"comparison": comparison, "value": value, "key": filter[1]}
		_number_filters.append(entry)
		# Picking a number means you want to filter by it, so "Any" becomes "=".
		value.value_changed.connect(
			func(_number: float) -> void:
				if comparison.selected == 0:
					comparison.select(1)
				_dim_unused(entry)
				changed.emit()
		)
		comparison.item_selected.connect(
			func(_index: int) -> void:
				_dim_unused(entry)
				changed.emit()
		)
		comparison.gui_input.connect(_scroll_choice.bind(comparison))
		_dim_unused(entry)


## The mouse wheel over a comparison steps through its choices without opening it.
func _scroll_choice(event: InputEvent, choice: OptionButton) -> void:
	var wheel := event as InputEventMouseButton
	if wheel == null or not wheel.pressed:
		return
	var step := 0
	if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
		step = -1
	elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step = 1
	if step == 0:
		return
	# Taken here, so the form does not scroll as well.
	choice.accept_event()
	var index := clampi(choice.selected + step, 0, choice.item_count - 1)
	if index != choice.selected:
		choice.select(index)
		choice.item_selected.emit(index)


## A number that is not used ("Any") is shown faded.
func _dim_unused(entry: Dictionary) -> void:
	var value: Control = entry["value"]
	value.modulate.a = 0.45 if (entry["comparison"] as OptionButton).selected == 0 else 1.0


# --- Suggestions ---------------------------------------------------------------------------


## The card types of the cards the "Cards" choice covers. Types and subtypes found only on custom
## cards are left out while it is on "Official cards", but can still be typed to search for them.
func _available_types() -> Array[String]:
	var found: Dictionary[String, bool] = {}
	for card in _cards:
		if is_searched(card):
			found[card.card_type] = true
	var names: Array[String] = []
	for card_type in CardData.TYPES:
		if found.has(card_type):
			names.append(card_type)
	return names


## The subtypes of those cards, one word each (a card can have several, like "Warrior Elf"), sorted.
func _available_subtypes() -> Array[String]:
	var found: Dictionary[String, String] = {}
	for card in _cards:
		if not is_searched(card):
			continue
		for word in card.subtype.replace(",", " ").split(" ", false):
			if not found.has(word.to_lower()):
				found[word.to_lower()] = word
	var names: Array[String] = []
	names.assign(found.values())
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return names
