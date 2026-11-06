class_name CardQuery
extends RefCounted
## Search syntax for the card database:
##
##   dragon              the name contains "dragon"
##   "chrono drake"      the name contains the phrase
##   t:creature          the type or subtype contains "creature"   (also type:)
##   ct:creature         the card type alone contains "creature"   (also cardtype:)
##   st:elf              the subtype alone contains "elf"          (also subtype:)
##   o:draw              the card text contains "draw"            (also text:, o:"draw a card")
##   time>=30            time cost; also : = != < <= > >=          (also cost:)
##   atk>2  def<=3       attack and defense; only creatures match  (also pow:, tou:, life:)
##   pts>=5              points from the points list               (also points:)
##   -t:spell            a - in front excludes what the term matches
##   t:spell or atk>3    either side may match
##
## Terms next to each other must all match. Unknown or malformed terms are skipped and listed in
## `warnings`.

const TEXT_FIELDS := {
	"name": "name",
	"n": "name",
	"t": "type",
	"type": "type",
	"ct": "cardtype",
	"cardtype": "cardtype",
	"st": "subtype",
	"subtype": "subtype",
	"o": "text",
	"text": "text",
	"oracle": "text",
}
const NUMBER_FIELDS := {
	"time": "time",
	"cost": "time",
	"tc": "time",
	"atk": "attack",
	"attack": "attack",
	"pow": "attack",
	"power": "attack",
	"def": "defense",
	"defense": "defense",
	"tou": "defense",
	"toughness": "defense",
	"life": "defense",
	"pts": "points",
	"points": "points",
}
const FIELD_NAMES := {
	"name": "the name",
	"type": "the type",
	"cardtype": "the card type",
	"subtype": "the subtype",
	"text": "the text",
	"time": "time cost",
	"attack": "attack",
	"defense": "defense",
	"points": "points",
}
const OPERATOR_SYMBOLS := {"=": "=", "!=": "≠", "<": "<", "<=": "≤", ">": ">", ">=": "≥"}
## How much work it is to check a term on a field: numbers are quick, text takes longer the longer
## the field. Terms are tried cheapest first, so a card that fails is found out quickly.
const FIELD_COST := {
	"time": 0, "attack": 0, "defense": 0, "points": 1,
	"cardtype": 2, "subtype": 2, "name": 3, "type": 4, "text": 5,
}
const QUOTES := ["\"", "“", "”"]

static var _term_pattern := RegEx.create_from_string("^([A-Za-z]+)(>=|<=|!=|>|<|=|:)(.*)$")

## Problems found while reading the search, for showing to the player.
var warnings: Array[String] = []

## Alternatives separated by "or". Each is a list of terms that must all match, as typed (for
## describe), and the same terms in the order they are tried (see FIELD_COST).
var _alternatives: Array[Array] = []
var _tried: Array[Array] = []
var _points_list: PointsList


static func parse(text: String, points_list: PointsList = null) -> CardQuery:
	var query := CardQuery.new()
	query._points_list = points_list
	var terms: Array[Dictionary] = []
	for token in _tokenize(text):
		if not token["quoted"] and str(token["text"]).to_lower() == "or":
			if not terms.is_empty():
				query._alternatives.append(terms)
			terms = []
			continue
		var term := query._parse_term(token)
		if not term.is_empty():
			terms.append(term)
	if not terms.is_empty():
		query._alternatives.append(terms)
	for alternative in query._alternatives:
		var ordered := alternative.duplicate()
		ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return FIELD_COST[a["field"]] < FIELD_COST[b["field"]])
		query._tried.append(ordered)
	return query


func is_empty() -> bool:
	return _alternatives.is_empty()


func matches(card: CardData) -> bool:
	if _tried.is_empty():
		return true
	# The card's text fields in lower case, made the first time a term needs them.
	var lowered := {}
	for terms in _tried:
		var all_match := true
		for term: Dictionary in terms:
			if _term_matches(term, card, lowered) == term["negate"]:
				all_match = false
				break
		if all_match:
			return true
	return false


## The cards that match, in the order given.
func filter(cards: Array[CardData]) -> Array[CardData]:
	if _tried.is_empty():
		return cards.duplicate()
	return cards.filter(matches)


## The search in words, e.g. 'the type includes “creature” and time cost ≥ 30'.
func describe() -> String:
	var alternatives: Array[String] = []
	for terms in _alternatives:
		var pieces: Array[String] = []
		for term: Dictionary in terms:
			pieces.append(_describe_term(term))
		alternatives.append(" and ".join(pieces))
	return " or ".join(alternatives)


## Splits on spaces outside quotes. A token is {"text", "quoted"}; "quoted" is true when the
## whole token is a quoted phrase, so it is always a name search (and "or" in quotes is a word).
static func _tokenize(text: String) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	var current := ""
	var in_quotes := false
	var quoted := false
	var started := false
	for character in text:
		if character in QUOTES:
			if not in_quotes and current.lstrip("-").is_empty():
				quoted = true
			in_quotes = not in_quotes
			started = true
		elif character.strip_edges().is_empty() and not in_quotes:
			if started:
				tokens.append({"text": current, "quoted": quoted})
			current = ""
			quoted = false
			started = false
		else:
			current += character
			started = true
	if started:
		tokens.append({"text": current, "quoted": quoted})
	return tokens


func _parse_term(token: Dictionary) -> Dictionary:
	var text: String = token["text"]
	var negate := false
	if text.begins_with("-") and text.length() > 1:
		negate = true
		text = text.substr(1)
	if text.strip_edges().is_empty():
		return {}
	var found: RegExMatch = null if token["quoted"] else _term_pattern.search(text)
	if found == null:
		return {"field": "name", "op": ":", "value": text.to_lower(), "negate": negate}

	var key := found.get_string(1).to_lower()
	var operator := found.get_string(2)
	var value := found.get_string(3)
	if TEXT_FIELDS.has(key):
		if operator != ":" and operator != "=":
			warnings.append("“%s” only works with “:”, like %s:%s." % [key + operator, key, value])
			return {}
		if value.is_empty():
			return {}
		return {"field": TEXT_FIELDS[key], "op": ":", "value": value.to_lower(), "negate": negate}
	if NUMBER_FIELDS.has(key):
		if not value.is_valid_int():
			warnings.append("“%s” needs a whole number, like %s>=10." % [key + operator + value, key])
			return {}
		return {
			"field": NUMBER_FIELDS[key],
			"op": "=" if operator == ":" else operator,
			"value": int(value),
			"negate": negate,
		}
	warnings.append("Unknown filter “%s” was skipped." % (key + operator))
	return {}


func _term_matches(term: Dictionary, card: CardData, lowered: Dictionary) -> bool:
	var field: String = term["field"]
	if FIELD_COST[field] >= FIELD_COST["cardtype"]:
		if not lowered.has(field):
			lowered[field] = _field_text(card, field).to_lower()
		return (lowered[field] as String).contains(term["value"])
	var number := 0
	match field:
		"time":
			number = card.time_cost
		"attack", "defense":
			if not card.has_stats():
				return false
			number = card.attack if field == "attack" else card.defense
		"points":
			number = _points_list.points_for(card) if _points_list != null else 0
	return _compare(number, term["op"], term["value"])


static func _field_text(card: CardData, field: String) -> String:
	match field:
		"name":
			return card.card_name
		"type":
			return card.type_line()
		"cardtype":
			return card.card_type
		"subtype":
			return card.subtype
	return card.rules_text


static func _compare(number: int, operator: String, value: int) -> bool:
	match operator:
		"<":
			return number < value
		"<=":
			return number <= value
		">":
			return number > value
		">=":
			return number >= value
		"!=":
			return number != value
	return number == value


static func _describe_term(term: Dictionary) -> String:
	var field: String = term["field"]
	var description := ""
	if term["op"] == ":":
		description = "%s includes “%s”" % [FIELD_NAMES[field], term["value"]]
		if term["negate"]:
			description = "%s doesn't include “%s”" % [FIELD_NAMES[field], term["value"]]
		return description
	description = "%s %s %d" % [FIELD_NAMES[field], OPERATOR_SYMBOLS[term["op"]], term["value"]]
	return "not %s" % description if term["negate"] else description
