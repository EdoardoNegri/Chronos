class_name WordSuggestions
extends PanelContainer
## A list under a LineEdit that completes the word being typed, from a set of known words. It floats
## above everything else and never takes focus, so typing carries on as usual, and nothing has to be
## chosen: what is typed is what the field holds. Words are separated by spaces, commas and quotes,
## so only the word at the caret is completed ("warrior el" offers "Elf").
##
## Up and Down move through the list, Enter or Tab take the highlighted one and Escape closes it.
## With nothing highlighted, Enter and Tab work as they do without the list.

## How many suggestions show before the list scrolls.
const ROWS := 5
const SEPARATORS := [" ", ",", "\"", "“", "”"]

## The suggestions listed now, and which one is highlighted (-1 for none).
var suggested: Array[String] = []
var highlighted := -1

var _edit: LineEdit
var _candidates: Callable
var _scroll: ScrollContainer
var _list: VBoxContainer


## Starts suggesting for `edit`. `candidates` returns every word that can be suggested, sorted
## (an Array[String]). The list is added to `host`.
func attach(edit: LineEdit, host: Node, candidates: Callable) -> void:
	_edit = edit
	_candidates = candidates
	theme_type_variation = &"Card"
	top_level = true
	visible = false
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)
	host.add_child(self)

	edit.text_changed.connect(func(_text: String) -> void: refresh())
	edit.focus_entered.connect(refresh)
	edit.focus_exited.connect(close)
	edit.gui_input.connect(_on_edit_input)
	# The list stays where it opened, so it closes when the form scrolls away from it.
	var node := edit.get_parent()
	while node != null and not node is ScrollContainer:
		node = node.get_parent()
	if node != null:
		(node as ScrollContainer).get_v_scroll_bar().value_changed.connect(
			func(_value: float) -> void: close()
		)


## Lists the known words that start with the word at the caret (all of them when there is none),
## leaving out words already in the field.
func refresh() -> void:
	var start := _word_start()
	var caret := _edit.caret_column
	var typed := _edit.text.substr(start, caret - start).to_lower()
	var used := {}
	for word in _words_in(_edit.text.left(start) + " " + _edit.text.substr(caret)):
		used[word] = true
	suggested.clear()
	for word: String in _candidates.call():
		var lower := word.to_lower()
		if lower.begins_with(typed) and lower != typed and not used.has(lower):
			suggested.append(word)
	highlighted = -1
	if suggested.is_empty():
		close()
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for i in suggested.size():
		var item := Button.new()
		item.text = suggested[i]
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.toggle_mode = true
		item.focus_mode = Control.FOCUS_NONE
		item.pressed.connect(accept.bind(i))
		_list.add_child(item)
	visible = true
	_place()


func close() -> void:
	visible = false
	highlighted = -1


## Puts suggestion `index` in place of the word at the caret.
func accept(index: int) -> void:
	var start := _word_start()
	var caret := _edit.caret_column
	_edit.text = _edit.text.left(start) + suggested[index] + _edit.text.substr(caret)
	_edit.caret_column = start + suggested[index].length()
	close()


## Under the field, as wide as the field, a few rows high.
func _place() -> void:
	var field := _edit.get_global_rect()
	var row := (_list.get_child(0) as Control).get_combined_minimum_size().y + _list.get_theme_constant("separation")
	_scroll.custom_minimum_size.y = minf(_list.get_combined_minimum_size().y, ROWS * row)
	custom_minimum_size.x = field.size.x
	size = Vector2(field.size.x, 0.0)
	global_position = field.position + Vector2(0.0, field.size.y + 4.0)


func _on_edit_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or not visible:
		return
	match key.keycode:
		KEY_DOWN:
			_highlight(mini(highlighted + 1, suggested.size() - 1))
		KEY_UP:
			_highlight(maxi(highlighted - 1, 0))
		KEY_ENTER, KEY_KP_ENTER, KEY_TAB:
			if highlighted < 0:
				return
			accept(highlighted)
		KEY_ESCAPE:
			close()
		_:
			return
	_edit.accept_event()


func _highlight(index: int) -> void:
	highlighted = index
	for i in _list.get_child_count():
		(_list.get_child(i) as Button).button_pressed = i == index
	_scroll.ensure_control_visible(_list.get_child(index) as Control)


## Where the word at the caret starts.
func _word_start() -> int:
	var before := _edit.text.left(_edit.caret_column)
	var start := 0
	for i in before.length():
		if before[i] in SEPARATORS:
			start = i + 1
	return start


## The words in some text, in lower case.
static func _words_in(text: String) -> PackedStringArray:
	for separator: String in SEPARATORS:
		text = text.replace(separator, " ")
	return text.to_lower().split(" ", false)
