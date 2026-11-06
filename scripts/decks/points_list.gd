class_name PointsList
extends RefCounted
## What each card costs against the deck's point budget (rule 1.3). Like a banlist, a card on
## this list costs what the list says, whatever its maker put on it. Cards are listed by name (case
## does not matter), so one list works for everyone's copies of the same cards. Cards that are not
## on the list cost the points their maker gave them (0 unless set).
##
## The list comes with the game: it is read from DEFAULT_PATH when the game starts, and players do
## not import one. It is a JSON file mapping card names to points, e.g.
## {"Chrono Drake": 4, "Zap": 1}.

const DEFAULT_PATH := "res://points_list.json"

## Where the list was read from.
var path: String

var _points: Dictionary[String, int] = {}


func _init(list_path: String = DEFAULT_PATH) -> void:
	path = list_path
	if not FileAccess.file_exists(path):
		return
	# JSON.new().parse() reports a bad file through its result instead of printing an error.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) == OK:
		set_from_dict(json.data)


func size() -> int:
	return _points.size()


func has_card(card: CardData) -> bool:
	return _points.has(_key(card.card_name))


## What the card costs: the list's number if the card is on the list, otherwise its own points.
func points_for(card: CardData) -> int:
	return _points.get(_key(card.card_name), card.points)


## Replaces the list. Entries whose points are not numbers are skipped.
func set_from_dict(data: Variant) -> void:
	_points.clear()
	if not data is Dictionary:
		return
	for card_name: Variant in data:
		var points: Variant = data[card_name]
		if (points is int or points is float) and not _key(str(card_name)).is_empty():
			_points[_key(str(card_name))] = maxi(0, int(points))


static func _key(card_name: String) -> String:
	return card_name.strip_edges().to_lower()
