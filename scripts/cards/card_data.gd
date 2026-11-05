class_name CardData
extends Resource
## Everything printed on a card. Call emit_changed() after editing a field so views redraw.
## What a card costs against the deck's point budget is not part of the card: see PointsList.

const TYPES: Array[String] = ["Creature", "Spell"]
## Types that show attack and defense on the card.
const TYPES_WITH_STATS: Array[String] = ["Creature"]

## Identifies the card in the library; empty until it is first saved.
var id := ""
var card_name := ""
var card_type: String = TYPES[0]
var subtype := ""
var time_cost := 0
var attack := 0
var defense := 0
var rules_text := ""
var image: Image


func to_dict() -> Dictionary:
	return {
		"id": id,
		"card_name": card_name,
		"card_type": card_type,
		"subtype": subtype,
		"time_cost": time_cost,
		"attack": attack,
		"defense": defense,
		"rules_text": rules_text,
	}


## The image is stored separately, so it is not part of the dictionary.
static func from_dict(data: Dictionary) -> CardData:
	var card := CardData.new()
	card.id = str(data.get("id", ""))
	card.card_name = str(data.get("card_name", ""))
	var type := str(data.get("card_type", TYPES[0]))
	card.card_type = type if type in TYPES else TYPES[0]
	card.subtype = str(data.get("subtype", ""))
	card.time_cost = int(data.get("time_cost", 0))
	card.attack = int(data.get("attack", 0))
	card.defense = int(data.get("defense", 0))
	card.rules_text = str(data.get("rules_text", ""))
	return card


func has_stats() -> bool:
	return card_type in TYPES_WITH_STATS


func type_line() -> String:
	var sub := subtype.strip_edges()
	return card_type if sub.is_empty() else "%s — %s" % [card_type, sub]


## A file-system safe name for exporting this card.
func file_stem() -> String:
	var stem := card_name.strip_edges().validate_filename()
	return stem if not stem.is_empty() else "card"
