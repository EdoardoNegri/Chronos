class_name CardBack
extends Control
## The back of a card during play: a blue card with a yellow hourglass in the middle and the
## name over it. The text is placed so the middle of its first "O" sits on the hourglass's waist.

const CARD_SIZE := CardView.CARD_SIZE
const BACK_COLOR := Color(0.09, 0.2, 0.5)
const EDGE_COLOR := Color(0.05, 0.11, 0.3)
const YELLOW := Color(0.98, 0.82, 0.25)
const INK := Color(0.97, 0.95, 0.9)
const OUTLINE := Color(0.04, 0.09, 0.26)

const TITLE := "CHRONOS"
const TITLE_SIZE := 96
const TITLE_OUTLINE := 16
## Index of the first "O" in TITLE.
const FIRST_O := 3

const GLASS_HALF_HEIGHT := 270.0
const GLASS_HALF_WIDTH := 150.0
const WAIST_HALF_WIDTH := 12.0
const CAP_HEIGHT := 36.0
const CAP_OVERHANG := 26.0
const GLASS_STEPS := 40


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := CARD_SIZE * 0.5
	_draw_card(center)
	_draw_hourglass(center)
	_draw_title(center)


## Where the title's baseline starts so that its first "O" is centered on `center`.
func title_origin(center: Vector2) -> Vector2:
	var font := get_theme_default_font()
	var through_o := font.get_string_size(
		TITLE.substr(0, FIRST_O + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE
	).x
	var o_width := font.get_string_size(TITLE[FIRST_O], HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x
	var baseline := center.y + (font.get_ascent(TITLE_SIZE) - font.get_descent(TITLE_SIZE)) * 0.5
	return Vector2(center.x - (through_o - o_width * 0.5), baseline)


func _draw_card(center: Vector2) -> void:
	var outer := StyleBoxFlat.new()
	outer.bg_color = BACK_COLOR
	outer.border_color = YELLOW
	outer.set_border_width_all(6)
	outer.set_corner_radius_all(30)
	draw_style_box(outer, Rect2(Vector2.ZERO, CARD_SIZE))

	var inner := StyleBoxFlat.new()
	inner.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	inner.border_color = Color(YELLOW, 0.45)
	inner.set_border_width_all(3)
	inner.set_corner_radius_all(18)
	draw_style_box(inner, Rect2(Vector2.ONE * 26.0, CARD_SIZE - Vector2.ONE * 52.0))

	# A soft pool of darker blue behind the hourglass.
	draw_circle(center, 330.0, Color(EDGE_COLOR, 0.35))


func _draw_hourglass(center: Vector2) -> void:
	var glass_height := GLASS_HALF_HEIGHT - CAP_HEIGHT
	var top := _bulb(center, -1.0, glass_height, 0.0, 1.0)
	var bottom := _bulb(center, 1.0, glass_height, 0.0, 1.0)

	draw_colored_polygon(top, Color(YELLOW, 0.14))
	draw_colored_polygon(bottom, Color(YELLOW, 0.14))

	# Sand: what is left in the top bulb, the stream, and the pile in the bottom bulb.
	draw_colored_polygon(_bulb(center, -1.0, glass_height, 0.0, 0.5), YELLOW)
	draw_line(center, center + Vector2(0.0, glass_height * 0.46), YELLOW, 5.0, true)
	var pile := _bulb(center, 1.0, glass_height, 0.55, 1.0)
	pile.insert(0, center + Vector2(0.0, glass_height * 0.4))
	draw_colored_polygon(pile, YELLOW)

	for bulb in [top, bottom]:
		var outline: PackedVector2Array = bulb
		outline.append(outline[0])
		draw_polyline(outline, YELLOW, 9.0, true)

	var cap := StyleBoxFlat.new()
	cap.bg_color = YELLOW
	cap.set_corner_radius_all(10)
	var cap_width := (GLASS_HALF_WIDTH + CAP_OVERHANG) * 2.0
	draw_style_box(cap, Rect2(center.x - cap_width * 0.5, center.y - GLASS_HALF_HEIGHT, cap_width, CAP_HEIGHT))
	draw_style_box(cap, Rect2(center.x - cap_width * 0.5, center.y + GLASS_HALF_HEIGHT - CAP_HEIGHT, cap_width, CAP_HEIGHT))


## The glass between distance fractions `from` and `to` (0 at the waist, 1 at the cap) of one
## bulb. `direction` is -1 for the top bulb and +1 for the bottom one.
func _bulb(center: Vector2, direction: float, height: float, from: float, to: float) -> PackedVector2Array:
	var right := PackedVector2Array()
	var left := PackedVector2Array()
	for i in GLASS_STEPS + 1:
		var u := lerpf(from, to, float(i) / GLASS_STEPS)
		var half_width := (
			WAIST_HALF_WIDTH
			+ (GLASS_HALF_WIDTH - WAIST_HALF_WIDTH) * pow(sin(u * PI * 0.5), 0.7)
		)
		var y := center.y + direction * height * u
		right.append(Vector2(center.x + half_width, y))
		left.append(Vector2(center.x - half_width, y))
	left.reverse()
	right.append_array(left)
	return right


func _draw_title(center: Vector2) -> void:
	var font := get_theme_default_font()
	var origin := title_origin(center)
	draw_string_outline(
		font, origin, TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, TITLE_OUTLINE, OUTLINE
	)
	draw_string(font, origin, TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, INK)
