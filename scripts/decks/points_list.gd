class_name PointsList
extends RefCounted
## What each card costs against the deck's point budget (rule 1.3). Like a banlist, the cost is
## set by this list, not by whoever made the card. Cards are listed by name (case does not
## matter), so one list works for everyone's copies of the same cards. Cards that are not on the
## list cost 0.
##
## A list file is JSON mapping card names to points, e.g. {"Chrono Drake": 4, "Zap": 1}.

const DEFAULT_PATH := "user://points_list.json"

## Where the list is kept. Importing a list replaces this file.
var path: String

var _points: Dictionary[String, int] = {}


func _init(list_path: String = DEFAULT_PATH) -> void:
	path = list_path
	if FileAccess.file_exists(path):
		set_from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))


func size() -> int:
	return _points.size()


func has_card(card: CardData) -> bool:
	return _points.has(_key(card.card_name))


func points_for(card: CardData) -> int:
	return _points.get(_key(card.card_name), 0)


## Replaces the list with the one in `source_path` and keeps it for next time.
func import_file(source_path: String) -> Error:
	# JSON.new().parse() reports a bad file through its result instead of printing an error.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(source_path)) != OK or not json.data is Dictionary:
		return ERR_PARSE_ERROR
	var parsed: Dictionary = json.data
	set_from_dict(parsed)
	var directory := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(_points, "\t"))
	file.close()
	return OK


## Replaces the list (without saving it). Entries whose points are not numbers are skipped.
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
