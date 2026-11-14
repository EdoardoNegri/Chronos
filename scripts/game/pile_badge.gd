class_name PileBadge
extends RefCounted
## The badge that shows how many cards a deck or a graveyard holds, while it is hovered.

const BADGE_COLOR := Color(0.04, 0.05, 0.1, 0.85)
const INK := Color(0.97, 0.95, 0.9)


## "1 card", "12 cards".
static func count_text(count: int) -> String:
	return "%d %s" % [count, "card" if count == 1 else "cards"]


## A hidden badge, to be placed over the pile it counts.
static func make() -> Label:
	var badge := Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_color_override("font_color", INK)
	var box := StyleBoxFlat.new()
	box.bg_color = BADGE_COLOR
	box.set_corner_radius_all(8)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	badge.add_theme_stylebox_override("normal", box)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	return badge
