class_name HandView
extends Control
## A hand of cards, tucked away at the edge of the screen: only a strip of each card shows, side by
## side, overlapping more as the hand grows. When the mouse comes onto the hand, the whole hand comes
## up into full view, and the card under the mouse comes to the front; when the mouse leaves it, the
## hand tucks away again. When even overlapping they do not fit, the mouse wheel scrolls through them.
##
## The player's hand is tucked under the bottom edge; the hand at the top (`from_top`) above the top
## edge. The control is as tall as a card, over the table: a card dragged from the hand and let go
## above the strip is passed on to `drop_target` (the table), so the whole field takes cards.

## How much of a tucked card shows, and the gap between cards when they all fit.
const MIN_SHOWN := 0.32
const GAP := 6.0

var card_size := Vector2(126, 176):
	set(value):
		card_size = value
		_layout()
## How tall the strip of a tucked card is.
var tucked_shown := 52.0:
	set(value):
		tucked_shown = value
		_layout()
var from_top := false
## Where a card let go over this hand, above its strip, is dropped instead.
var drop_target: Control

var _scroll := 0.0
## Whether the hand is up, and the card under the mouse while it is.
var _raised := false
var _hovered: Control
## The cards in the order of the hand (the one under the mouse is also the last child, so it is
## drawn and picked up in front of the others).
var _cards: Array[Control] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(_layout)


## Shows these cards in the hand (made to card_size), in order. The hand stays up if it was.
func show_cards(cards: Array[Control]) -> void:
	_hovered = null
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cards = cards.duplicate()
	for card in cards:
		card.custom_minimum_size = card_size
		card.size = card_size
		add_child(card)
	_layout()


## The cards in the order of the hand.
func cards() -> Array[Control]:
	return _cards


## The card under the mouse while the hand is up (null if none).
func hovered_card() -> Control:
	return _hovered


## Whether the whole hand is up, in full view.
func is_raised() -> bool:
	return _raised


## How far the hand is scrolled, and how far it can be.
func scroll_amount() -> float:
	return _scroll


func max_scroll() -> float:
	return maxf(0.0, _total_width() - size.x)


## The hand follows the mouse wherever it is (moving onto a card that sits over other controls, or
## off the hand altogether), so it watches every mouse event rather than only the ones it is sent.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventMouseMotion or event is InputEventMouseButton):
		return
	var local := make_input_local(event) as InputEventMouse
	if event is InputEventMouseMotion:
		_hover_at(local.position)
	elif Rect2(Vector2.ZERO, size).has_point(local.position):
		_scroll_by(local as InputEventMouseButton)


func _scroll_by(wheel: InputEventMouseButton) -> void:
	if not wheel.pressed:
		return
	var direction := 0.0
	if wheel.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT]:
		direction = 1.0
	elif wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT]:
		direction = -1.0
	if direction != 0.0 and max_scroll() > 0.0:
		_scroll = clampf(_scroll + direction * _step(), 0.0, max_scroll())
		get_viewport().set_input_as_handled()
		_layout()


# --- Dropping through to the table ---------------------------------------------------------


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return _passes_drop(at_position) and drop_target._can_drop_data(_in_target(at_position), data)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	drop_target._drop_data(_in_target(at_position), data)


## Whether a card let go here goes on to the table: off the strip, where the hand is out of the way.
func _passes_drop(at: Vector2) -> bool:
	if drop_target == null:
		return false
	return at.y > tucked_shown if from_top else at.y < size.y - tucked_shown


func _in_target(at: Vector2) -> Vector2:
	return drop_target.get_global_transform().affine_inverse() * (get_global_transform() * at)


# --- Laying out ----------------------------------------------------------------------------


## Brings the hand up when the mouse comes onto it (onto the strips that show), keeps it up while
## the mouse is anywhere on the cards, and tucks it away once the mouse leaves them. The card under
## the mouse comes to the front.
func _hover_at(point: Vector2) -> void:
	var raised := _cards_area(true).has_point(point) if _raised else _cards_area(false).has_point(point)
	var found: Control = null
	if raised:
		for i in range(_cards.size() - 1, -1, -1):
			if Rect2(_cards[i].position.x, _out_y(), card_size.x, card_size.y).has_point(point):
				found = _cards[i]
				break
	if raised == _raised and found == _hovered:
		return
	_raised = raised
	_hovered = found
	# Back in the order of the hand, then the one under the mouse in front.
	for i in _cards.size():
		move_child(_cards[i], i)
	if found != null:
		move_child(found, -1)
	_layout()


## Where the cards are: up in full view, or just their strips while tucked away.
func _cards_area(raised: bool) -> Rect2:
	if _cards.is_empty():
		return Rect2()
	var left := _cards[0].position.x
	var width: float = _cards.back().position.x + card_size.x - left
	if raised:
		return Rect2(left, _out_y(), width, card_size.y)
	var y := 0.0 if from_top else size.y - tucked_shown
	return Rect2(left, y, width, tucked_shown)


func _out_y() -> float:
	return 0.0 if from_top else size.y - card_size.y


## From the left edge of one card to the next.
func _step() -> float:
	var count := _cards.size()
	if count <= 1:
		return card_size.x + GAP
	var fitting := (size.x - card_size.x) / (count - 1)
	return clampf(fitting, card_size.x * MIN_SHOWN, card_size.x + GAP)


func _total_width() -> float:
	var count := _cards.size()
	return 0.0 if count == 0 else (count - 1) * _step() + card_size.x


func _layout() -> void:
	var count := _cards.size()
	if count == 0:
		return
	_scroll = clampf(_scroll, 0.0, max_scroll())
	var step := _step()
	var total := _total_width()
	var left := (size.x - total) * 0.5 if total <= size.x else -_scroll
	var tucked_y := tucked_shown - card_size.y if from_top else size.y - tucked_shown
	var y := _out_y() if _raised else tucked_y
	for i in count:
		_cards[i].position = Vector2(left + i * step, y)
