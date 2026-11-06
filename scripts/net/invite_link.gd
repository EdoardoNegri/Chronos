class_name InviteLink
extends RefCounted
## The link a host sends to a friend. Opening it starts the game (if it was told to open these
## links, see LinkHandler) and takes the friend into the room, asking for the password if there is
## one. It holds where the host's game can be reached and which room, and nothing secret: the
## password is never in it.
##
## A link looks like  chronos://join?d=<the details, packed>  . Many chat apps do not make a link
## like that clickable, so it can also be wrapped in a web page address (PAGE_URL, see
## web/join.html), which any chat app lets you click and which then opens the game.

const SCHEME := "chronos"
## Where web/join.html is published (by .github/workflows/pages.yml, on GitHub Pages). Empty would
## mean there is no such page, and links would only be the chronos:// kind.
const PAGE_URL := "https://edoardonegri.github.io/Chronos/join.html"


## The link for a room, as chronos://join?d=... . `address` is where the host's game can be reached
## (a ws:// or wss:// address), `locked` says there is a password to ask for.
static func make(address: String, room_id: StringName, room_name: String, locked: bool) -> String:
	return "%s://join?d=%s" % [SCHEME, _pack(address, room_id, room_name, locked)]


## The same link inside a web page address, or "" if there is no page (PAGE_URL).
static func make_web(address: String, room_id: StringName, room_name: String, locked: bool) -> String:
	if PAGE_URL.is_empty():
		return ""
	return "%s#%s" % [PAGE_URL, _pack(address, room_id, room_name, locked)]


## The link to send: the web one if there is a page for it, otherwise the chronos:// one.
static func make_best(address: String, room_id: StringName, room_name: String, locked: bool) -> String:
	var web := make_web(address, room_id, room_name, locked)
	return web if not web.is_empty() else make(address, room_id, room_name, locked)


## What a link says, as {"address", "room_id", "room_name", "locked"}, or {} if `text` is not a link
## (or is a broken one). It reads either kind, with or without spaces around it.
static func parse(text: String) -> Dictionary:
	var packed := ""
	var trimmed := text.strip_edges()
	if trimmed.begins_with(SCHEME + "://"):
		var at := trimmed.find("d=")
		if at >= 0:
			packed = trimmed.substr(at + 2).split("&")[0]
	elif trimmed.begins_with("http://") or trimmed.begins_with("https://"):
		var hash_at := trimmed.find("#")
		if hash_at >= 0:
			packed = trimmed.substr(hash_at + 1)
	if packed.is_empty():
		return {}
	return _unpack(packed)


## The first link among command line arguments (what Windows passes when a link is opened), or {}.
static func find_in(args: PackedStringArray) -> Dictionary:
	for arg in args:
		var invite := parse(arg)
		if not invite.is_empty():
			return invite
	return {}


static func _pack(address: String, room_id: StringName, room_name: String, locked: bool) -> String:
	var json := JSON.stringify({"a": address, "r": str(room_id), "n": room_name, "l": locked})
	return Marshalls.utf8_to_base64(json).replace("+", "-").replace("/", "_").replace("=", "")


static func _unpack(packed: String) -> Dictionary:
	# Anything that is not packed text is turned away before it reaches the decoder, which would
	# report an error instead of just saying no.
	if packed.length() % 4 == 1 or not RegEx.create_from_string("^[A-Za-z0-9_-]+$").search(packed):
		return {}
	var standard := packed.replace("-", "+").replace("_", "/")
	while standard.length() % 4 != 0:
		standard += "="
	var json := JSON.new()
	if json.parse(Marshalls.base64_to_utf8(standard)) != OK or not json.data is Dictionary:
		return {}
	var data: Dictionary = json.data
	var address := str(data.get("a", ""))
	var room_id := str(data.get("r", ""))
	if address.is_empty() or room_id.is_empty():
		return {}
	return {
		"address": address,
		"room_id": room_id,
		"room_name": str(data.get("n", "")),
		"locked": bool(data.get("l", false)),
	}
