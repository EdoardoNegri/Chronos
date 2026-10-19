class_name TextFit
extends RefCounted
## Helpers for making text fit a space.


## The largest font size, down to min_size, at which a single line of text fits max_width.
static func font_size(font: Font, text: String, max_width: float, max_size: int, min_size: int) -> int:
	var result := max_size
	while (
		result > min_size
		and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, result).x > max_width
	):
		result -= 1
	return result
