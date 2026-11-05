class_name CardPng
extends RefCounted
## Card PNGs that can be imported back as cards. The downloaded PNG is the card as drawn, with the
## card's fields and art stored in an extra PNG chunk that image viewers ignore. Sending someone
## the PNG is enough for them to add the card to their library.

## Ancillary, private and safe to copy, so PNG readers skip it and editors may keep it.
const CHUNK_TYPE := "chCd"
const FORMAT := 1
const SIGNATURE := [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

static var _crc_table: PackedInt64Array


## `png` with the card stored in it.
static func write_card(png: PackedByteArray, card: CardData) -> PackedByteArray:
	var payload := {"format": FORMAT, "card": card.to_dict(), "art": ""}
	if card.image != null and not card.image.is_empty():
		payload["art"] = Marshalls.raw_to_base64(card.image.save_png_to_buffer())
	var chunk := _chunk(CHUNK_TYPE, JSON.stringify(payload).to_utf8_buffer())
	var iend := _find_chunk(png, "IEND")
	if iend < 0:
		return png
	var result := png.slice(0, iend)
	result.append_array(chunk)
	result.append_array(png.slice(iend))
	return result


## The card stored in `png`, with its art, or null if there is none.
static func read_card(png: PackedByteArray) -> CardData:
	var start := _find_chunk(png, CHUNK_TYPE)
	if start < 0:
		return null
	var length := _read_u32(png, start)
	var data := png.slice(start + 8, start + 8 + length)
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("card") is Dictionary:
		return null
	var card := CardData.from_dict(parsed["card"])
	var art := str(parsed.get("art", ""))
	if not art.is_empty():
		var image := Image.new()
		if image.load_png_from_buffer(Marshalls.base64_to_raw(art)) == OK:
			card.image = image
	return card


## Offset of the first chunk of this type, or -1.
static func _find_chunk(png: PackedByteArray, type: String) -> int:
	if png.size() < SIGNATURE.size() or png.slice(0, SIGNATURE.size()) != PackedByteArray(SIGNATURE):
		return -1
	var offset := SIGNATURE.size()
	while offset + 12 <= png.size():
		var length := _read_u32(png, offset)
		if png.slice(offset + 4, offset + 8).get_string_from_ascii() == type:
			return offset
		offset += 12 + length
	return -1


static func _chunk(type: String, data: PackedByteArray) -> PackedByteArray:
	var typed := type.to_ascii_buffer()
	typed.append_array(data)
	var chunk := _u32(data.size())
	chunk.append_array(typed)
	chunk.append_array(_u32(_crc32(typed)))
	return chunk


## PNG numbers are big-endian.
static func _read_u32(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]


static func _u32(value: int) -> PackedByteArray:
	return PackedByteArray([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])


static func _crc32(bytes: PackedByteArray) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for n in 256:
			var c := n
			for k in 8:
				c = (0xEDB88320 ^ (c >> 1)) if c & 1 else c >> 1
			_crc_table[n] = c
	var crc := 0xFFFFFFFF
	for byte in bytes:
		crc = _crc_table[(crc ^ byte) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF
