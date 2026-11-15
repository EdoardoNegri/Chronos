class_name TableView
extends Control
## The table, seen from above with only a slight slant, as in MTG Arena (a small 3D scene in a
## SubViewport): the player's side (BOTTOM) near, the other side (TOP) a little further away and a
## little smaller. Each side has a field where its cards lie (no box is drawn: the whole side takes
## cards) and beside it a column with its graveyard and, under it, its deck (the size of a card on
## the field), set in from the edge of the screen and pushed to the outer edge of the side: the
## player's at the bottom right, where the hand's strip starts; the other side is the same turned
## around, its column at the top left and its cards facing the other way.
##
## The proportions are MTG Arena's: on a 16:9 screen a card on the player's field is about 6.5% of
## the screen wide, the other side's cards about 85% of that, and the player's field about three
## quarters of the screen across, with room for two rows.
##
## The camera fits itself to the screen, whatever its size: the player's side reaches BOTTOM_ROOM
## pixels above the bottom of the screen, where their hand is, and as far across as the screen goes,
## and the other side ends TOP_ROOM pixels under the top, where the other hand is. Between the two
## sides is a gap as tall as MIDDLE_BAND on screen, left free for the band the board puts there (see
## band_center).
##
## Playing alone (top_visible false) there is no other side: the band is at the top of the screen and
## the player's side, twice as deep, takes all the rest.
##
## Where a card lies on a field does not matter: the cards line up by themselves in the middle of the
## field, in one row while they fit, then shared evenly between two rows, closer together as needed.
##
## A deck is a stack as thick as the cards in it, so how full it is can be seen. A graveyard is a
## vortex (see vortex.gdshader): the cards in it cannot be seen. A card that goes into it starts from
## where it was let go on the field (from the middle of the field when it was not let go here, such
## as the other player's), and moves into the vortex getting smaller, without turning, until it is
## gone. Hovering a deck or a graveyard shows how many cards it holds.
##
## The table only shows: what happens comes out as signals. Clicking a deck that is enabled emits
## deck_pressed; clicking a graveyard emits grave_pressed (its cards are seen only that way). A card
## dragged from a hand (CardThumb.source as in hand_sources) can be dropped anywhere on that hand's
## side of the table while it accepts_drops; dropping emits card_dropped. Positions on screen are found by casting the mouse onto the table, so the slant does
## not matter.

signal deck_pressed(side: int)
signal grave_pressed(side: int)
signal card_dropped(side: int, card_id: String)
## The table was laid out again (the screen changed size, or the other side came or went), so the
## band may have moved (see band_center).
signal laid_out

const BOTTOM := 0
const TOP := 1

## Sizes on the table, in table units: a card is one unit wide, on a field and on a deck alike. A
## field is FIELD_DEPTH deep (room for two rows of cards), twice that when playing alone.
const CARD := Vector2(1.0, 1.4)
const PILE_CARD := CARD
const FIELD_DEPTH := 3.4
## How the camera looks at the table: down at PITCH degrees, seeing FOV degrees from top to bottom.
const PITCH := 80.0
const FOV := 30.0
## The band across the middle of the screen, and the room left for the hands: above the other side
## and under the player's, in pixels.
const MIDDLE_BAND := 56.0
const TOP_ROOM := 40.0
const BOTTOM_ROOM := 56.0
## The room between things and the edges of the screen, around and between the cards on a field, and
## between the two piles.
const EDGE := 0.15
const MARGIN := 0.18
const CARD_GAP := 0.16
const PILE_GAP := 0.25
## How far the column of the deck and graveyard is set in from the edge of the screen (the player's;
## the other side's as far from its corner on screen), and from the field.
const PILE_INSET := 0.5
const FIELD_TO_PILES := 0.45
## How wide the graveyard's vortex is (as a card), and how long a card takes to go into it (seconds).
const VORTEX := 1.0
const VORTEX_SECONDS := 0.7
const VORTEX_SHADER := preload("res://assets/shaders/vortex.gdshader")
## How thick one card is in a stack: thicker than a real one, so a stack shows how full it is.
const CARD_THICKNESS := 0.015
const TABLE_SIZE := Vector2(60.0, 40.0)

const TABLE_COLOR := Color(0.06, 0.07, 0.13, 0.92)
const SLOT_COLOR := Color(0.55, 0.58, 0.72, 0.45)
## The sides of a stack of cards: black, as the cards' own borders are (see CardView).
const EDGE_COLOR := Color(0.0, 0.0, 0.0)
const PLACEHOLDER_COLOR := Color(0.12, 0.13, 0.2)
const INK := Color(0.97, 0.95, 0.9)

## The source (CardThumb.source) of the cards each side's hand gives, and whether each side takes
## them now.
var hand_sources: Array[StringName] = [&"hand", &"top_hand"]
var accepts_drops: Array[bool] = [false, false]
## Whether each side's deck can be clicked at all, and whether it can be now.
var deck_clickable: Array[bool] = [true, false]
var deck_enabled: Array[bool] = [false, false]
## Whether the other side of the table is shown. Playing alone it is not, and the player's side
## takes the whole screen below the band, which is then at the top.
var top_visible := true:
	set(value):
		if value == top_visible:
			return
		top_visible = value
		for node: Node3D in [_sides[TOP], _vortices[TOP]]:
			node.visible = value
		_relayout()

## The size of the screen the table fills, in pixels (this control's size, once it has one).
var _screen := Vector2(1152, 648)
## Found by fitting the camera to the screen: half the gap between the two sides, and how far the
## table reaches to each side, in table units.
var _half_gap := 0.4
var _half_width := 7.0
## How far the table reaches to each side where the player's piles are.
var _pile_half_width := 7.0
## Where the other side's deck is, mirrored onto the player's side (see pile_center): found so that
## it is as far from the top left corner of the screen as the player's is from the bottom right.
var _top_deck := Vector3(7.0, 0.0, 3.5)
var _viewport: SubViewport
var _camera: Camera3D
var _back_texture: Texture2D
var _slot_texture: Texture2D
var _badge: Label
## Per side: the Node3D holding its cards and piles.
var _sides: Array[Node3D] = []
var _cards: Array = [[], []]
var _deck_counts: Array[int] = [0, 0]
var _graves: Array = [[], []]
## What the mouse is over: [kind (&"deck", &"grave" or &""), side].
var _hovered: Array = [&"", 0]
## Each side's vortex (kept across show_side, so it keeps turning), whether the side was shown
## before (cards already in a graveyard when the board opens do not fall again), and the cards
## going down into a vortex right now.
var _vortices: Array[MeshInstance3D] = []
var _shown: Array[bool] = [false, false]
var _falling := 0
## Per side: the last card let go on its field, and where (a point of the table), so that if it goes
## into the graveyard it starts from there.
var _dropped_id: Array[String] = ["", ""]
var _dropped_at: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The 3D view is sized by hand to the screen (see _relayout), so the camera can be fitted to it.
	var container := SubViewportContainer.new()
	container.stretch = false
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(_screen)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(_viewport)

	_back_texture = _render_card_back()
	_slot_texture = _make_slot_texture()
	_build_world()
	for side in 2:
		var holder := Node3D.new()
		_viewport.add_child(holder)
		_sides.append(holder)
		var vortex := _make_vortex()
		_viewport.add_child(vortex)
		_vortices.append(vortex)

	_badge = PileBadge.make()
	add_child(_badge)
	mouse_exited.connect(_on_mouse_exited)


# --- What is shown -------------------------------------------------------------------------


## Shows one side: the cards on its field and in its graveyard (entries [id, name, picture or null],
## the graveyard's top card last), and how many cards its deck holds.
func show_side(side: int, field: Array, grave: Array, deck_count: int) -> void:
	var newly_gone: Array = []
	if _shown[side] and grave.size() > _graves[side].size():
		newly_gone = grave.slice(_graves[side].size())
	_shown[side] = true
	_cards[side] = field.duplicate()
	_graves[side] = grave.duplicate()
	_deck_counts[side] = deck_count
	var holder := _sides[side]
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	for i in field.size():
		var card := _card_face(field[i])
		card.position = card_center(side, i) + Vector3(0, 0.01, 0)
		card.rotation.y = PI if side == TOP else 0.0
		holder.add_child(card)
	var slot := _flat(PILE_CARD, _material(_slot_texture, SLOT_COLOR, true))
	slot.position = pile_center(side, &"deck") + Vector3(0, 0.002, 0)
	holder.add_child(slot)
	_add_stack(holder, side, pile_center(side, &"deck"), deck_count)
	_vortices[side].position = pile_center(side, &"grave") + Vector3(0, 0.004, 0)
	for entry: Array in newly_gone:
		var from := field_center(side)
		if entry[0] == _dropped_id[side]:
			from = _dropped_at[side]
			_dropped_id[side] = ""
		_fall_into_vortex(side, entry, from)
	_update_badge()


## The ids of the cards on a side's field, in the order played.
func cards_on(side: int) -> Array[String]:
	var ids: Array[String] = []
	for entry: Array in _cards[side]:
		ids.append(entry[0])
	return ids


func deck_count(side: int) -> int:
	return _deck_counts[side]


func grave_count(side: int) -> int:
	return _graves[side].size()


## Whether the number of cards of a pile is showing (while it is hovered).
func is_count_shown() -> bool:
	return _badge.visible


## How many cards are going down into a vortex right now.
func falling_count() -> int:
	return _falling


# --- Where things are ----------------------------------------------------------------------


## How far the player's side of the table reaches to each side of the screen, and how deep a side
## is (its field with the room around it), in table units.
func half_width() -> float:
	return _half_width


func side_depth() -> float:
	var depth := FIELD_DEPTH + EDGE * 2.0
	return depth if top_visible else depth * 2.0


## Half the gap between the two sides, under the band, in table units of depth.
func half_band() -> float:
	return _half_gap


## Where the middle of the band between the two sides is on screen, up and down.
func band_center() -> float:
	return screen_point(Vector3.ZERO).y if top_visible else MIDDLE_BAND * 0.5


## How big a field is: from the edge of the screen to the piles, and from the middle band to the edge.
func field_size() -> Vector2:
	var right := _pile_x() - PILE_CARD.x * 0.5 - FIELD_TO_PILES
	var left := -half_width() + EDGE
	return Vector2(right - left, side_depth() - EDGE * 2.0)


## Where the player's deck and graveyard are across: in a column set in from the edge of the screen.
func _pile_x() -> float:
	return _pile_half_width - PILE_INSET - PILE_CARD.x * 0.5


## The middle of a side's field.
func field_center(side: int) -> Vector3:
	var left := -half_width() + EDGE
	var x := left + field_size().x * 0.5
	var z := half_band() + EDGE + field_size().y * 0.5
	return Vector3(-x, 0.0, -z) if side == TOP else Vector3(x, 0.0, z)


## Where the card played `index`-th lies on a side's field. One row of cards sits in the middle of
## the field; when they do not fit in one, they share two rows evenly, the first nearest the middle
## of the table.
func card_center(side: int, index: int) -> Vector3:
	var count: int = maxi(1, _cards[side].size())
	var room := field_size().x - MARGIN * 2.0
	var per_row := maxi(1, floori((room + CARD_GAP) / (CARD.x + CARD_GAP)))
	var rows := 1 if count <= per_row else 2
	if rows == 2:
		per_row = ceili(count / 2.0)
	var row := floori(float(index) / per_row)
	var in_row: int = per_row if row < rows - 1 else count - per_row * (rows - 1)
	var step := CARD.x + CARD_GAP
	if in_row > 1:
		step = minf(step, (room - CARD.x) / (per_row - 1))
	var middle := field_center(BOTTOM)
	var x := middle.x + (index % per_row - (in_row - 1) * 0.5) * step
	var z := middle.z
	if rows == 2:
		var front := half_band() + EDGE + MARGIN + CARD.y * 0.5
		z = front + row * (CARD.y + CARD_GAP)
	return Vector3(-x, 0.0, -z) if side == TOP else Vector3(x, 0.0, z)


## The middle of a side's graveyard (&"grave") or deck (&"deck") on the table: in a column beside
## the field, the deck at the outer edge of the side (for the player, where the hand's strip starts)
## and the graveyard just inside it (toward the middle of the table). The other side's are as far
## from their corner of the screen (top left) as the player's are from theirs (bottom right).
func pile_center(side: int, kind: StringName) -> Vector3:
	var deck := Vector3(_pile_x(), 0.0, half_band() + side_depth() - PILE_CARD.y * 0.5)
	if side == TOP:
		deck = _top_deck
	var at := deck
	if kind == &"grave":
		at.z -= PILE_CARD.y * 0.5 + PILE_GAP + VORTEX * 0.5
	return -at if side == TOP else at


## Where a point of the table is on screen.
func screen_point(table_point: Vector3) -> Vector2:
	return _camera.unproject_position(table_point)


## The point of the table under a point of the screen (null if the table is not there).
func table_point(at: Vector2) -> Variant:
	var origin := _camera.project_ray_origin(at)
	var direction := _camera.project_ray_normal(at)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)


## Whether a point of the screen is on a side of the table (its half; alone, the whole table).
func in_field(side: int, at: Vector2) -> bool:
	var point: Variant = table_point(at)
	if point == null:
		return false
	var z: float = (point as Vector3).z
	return z >= 0.0 if side == BOTTOM else z <= 0.0


## The pile under a point of the screen: [&"deck" or &"grave", side], or [&"", 0].
func pile_at(at: Vector2) -> Array:
	var point: Variant = table_point(at)
	if point != null:
		for side in 2:
			if side == TOP and not top_visible:
				continue
			if _covers(pile_center(side, &"deck"), PILE_CARD, point):
				return [&"deck", side]
			var to_vortex: Vector3 = point - pile_center(side, &"grave")
			if Vector2(to_vortex.x, to_vortex.z).length() <= VORTEX * 0.5:
				return [&"grave", side]
	return [&"", 0]


static func _covers(center: Vector3, area: Vector2, point: Vector3) -> bool:
	return absf(point.x - center.x) <= area.x * 0.5 and absf(point.z - center.z) <= area.y * 0.5


# --- Mouse and drops -----------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		_set_hovered(pile_at(motion.position))
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var pile := pile_at(click.position)
		var side: int = pile[1]
		if pile[0] == &"deck" and deck_clickable[side] and deck_enabled[side]:
			accept_event()
			deck_pressed.emit(side)
		elif pile[0] == &"grave":
			accept_event()
			grave_pressed.emit(side)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var side := _side_for(data)
	return side != -1 and in_field(side, at_position)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var side := _side_for(data)
	var point: Variant = table_point(at_position)
	_dropped_id[side] = str(data["card_id"])
	_dropped_at[side] = point if point != null else field_center(side)
	card_dropped.emit(side, str(data["card_id"]))


## The side whose hand a dragged card comes from, if that side takes cards now (otherwise -1).
func _side_for(data: Variant) -> int:
	if not data is Dictionary:
		return -1
	var side := hand_sources.find(data.get("from", &""))
	return side if side != -1 and accepts_drops[side] else -1


func _on_mouse_exited() -> void:
	_set_hovered([&"", 0])


func _set_hovered(pile: Array) -> void:
	_hovered = pile
	var side: int = pile[1]
	var clickable: bool = pile[0] == &"grave" or (pile[0] == &"deck" and deck_clickable[side] and deck_enabled[side])
	for each in 2:
		var lit: bool = pile[0] == &"grave" and side == each
		(_vortices[each].material_override as ShaderMaterial).set_shader_parameter(&"glow", 1.0 if lit else 0.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW
	_update_badge()


## Shows the number of cards of the hovered pile, over it.
func _update_badge() -> void:
	var kind: StringName = _hovered[0]
	_badge.visible = kind != &""
	if kind == &"":
		return
	var side: int = _hovered[1]
	var count := deck_count(side) if kind == &"deck" else grave_count(side)
	_badge.text = PileBadge.count_text(count) + (" in the graveyard" if kind == &"grave" else "")
	_badge.reset_size()
	var top := pile_center(side, kind)
	if kind == &"deck":
		top.y = count * CARD_THICKNESS
	_badge.position = screen_point(top) - _badge.size * 0.5


# --- Building the 3D scene -----------------------------------------------------------------


func _build_world() -> void:
	# Looking down at a slant; where from is fitted to the screen once it has a size (_relayout).
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.far = 400.0
	_viewport.add_child(_camera)
	_camera.current = true

	var table := _flat(TABLE_SIZE, _material(null, TABLE_COLOR, true))
	table.position.y = -0.01
	_viewport.add_child(table)
	resized.connect(_on_resized)


## Fits the camera to the screen (see the top of this script). The gap the band needs depends on
## the fit, and changes it a little, so it is found in a few rounds. Then how far the table reaches
## across, at the near edge, where it reaches least far.
func _fit_camera() -> void:
	_half_gap = 0.4 if top_visible else 0.0
	if top_visible:
		for i in 3:
			_fit_distance()
			var across_middle := screen_point(Vector3(0, 0, 0.5)).y - screen_point(Vector3(0, 0, -0.5)).y
			_half_gap = (MIDDLE_BAND * 0.5 + 4.0) / maxf(1.0, across_middle)
	_fit_distance()
	_half_width = _reach_at(_screen.y - BOTTOM_ROOM)
	_pile_half_width = _reach_at(screen_point(pile_center(BOTTOM, &"deck")).y)
	# The other side's deck: its outer corner as far from the top left of the screen as the player's
	# is from the bottom right.
	var my_deck := pile_center(BOTTOM, &"deck")
	var gap := Vector2(
		_screen.x - screen_point(my_deck + Vector3(PILE_CARD.x * 0.5, 0.0, 0.0)).x,
		_screen.y - screen_point(my_deck + Vector3(0.0, 0.0, PILE_CARD.y * 0.5)).y
	)
	var far_edge: Vector3 = table_point(Vector2(_screen.x * 0.5, gap.y))
	var deck_z := far_edge.z + PILE_CARD.y * 0.5
	var left_edge: Vector3 = table_point(Vector2(gap.x, screen_point(Vector3(0.0, 0.0, deck_z)).y))
	_top_deck = -Vector3(left_edge.x + PILE_CARD.x * 0.5, 0.0, deck_z)


## How far the table reaches to the right edge of the screen, at a height on the screen.
func _reach_at(screen_y: float) -> float:
	var point: Variant = table_point(Vector2(_screen.x - 1.0, screen_y))
	return absf((point as Vector3).x) if point != null else 7.0


## Places the camera, looking down at PITCH, so that the near edge of the table (the player's side)
## is BOTTOM_ROOM above the bottom of the screen and the far edge (the other side's, or alone the
## inner edge of the player's, under the band) where it should be. Along the middle of the screen, a
## point of the table seen at an angle `a` below the horizon is tan(a - PITCH) / tan(FOV / 2) of half
## the screen below its middle, which gives the two angles; the camera's height is what puts the two
## edges at them.
func _fit_distance() -> void:
	var near_z := _half_gap + side_depth()
	var far_z := -near_z if top_visible else _half_gap
	var far_y := TOP_ROOM if top_visible else MIDDLE_BAND
	var pitch := deg_to_rad(PITCH)
	var near_angle := _angle_at(_screen.y - BOTTOM_ROOM)
	var far_angle := _angle_at(far_y)
	var height := (near_z - far_z) / (1.0 / tan(far_angle) - 1.0 / tan(near_angle))
	var from := Vector3(0.0, height, near_z + height / tan(near_angle))
	_camera.look_at_from_position(from, from + Vector3(0.0, -sin(pitch), -cos(pitch)), Vector3.UP)


## How far below the horizon the camera sees, at a height on the screen (down the middle).
func _angle_at(screen_y: float) -> float:
	var half_fov := deg_to_rad(FOV) * 0.5
	return deg_to_rad(PITCH) + atan((2.0 * screen_y / _screen.y - 1.0) * tan(half_fov))


## The screen changed size: the fields stretch to fill it, and everything is laid out again.
func _on_resized() -> void:
	if not size.x > 0.0 or not size.y > 0.0 or size == _screen:
		return
	_screen = size
	_relayout()


func _ready() -> void:
	if size.x > 0.0 and size.y > 0.0:
		_screen = size
	_relayout()


## Lays everything out again for the screen and for whether the other side is shown.
func _relayout() -> void:
	# Before _ready the camera is not in the tree yet, so nothing can be measured; _ready does it.
	if _camera == null or not is_node_ready():
		return
	# The fit measures where things are on screen, so the 3D view must be the screen's size first.
	_viewport.size = Vector2i(_screen)
	_fit_camera()
	for side in 2:
		show_side(side, _cards[side], _graves[side], _deck_counts[side])
	laid_out.emit()


## A flat rectangle lying on the table, `area` wide and deep.
static func _flat(area: Vector2, material: Material) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = area
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	return node


## A flat color or picture, not lit, so it looks the same everywhere on the table.
static func _material(texture: Texture2D, color := Color.WHITE, see_through := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if see_through:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


## A card lying face up: its picture, or its name on a plain card when it has none.
func _card_face(entry: Array) -> Node3D:
	var texture: Texture2D = entry[2]
	var card := _flat(CARD, _material(texture, Color.WHITE if texture != null else PLACEHOLDER_COLOR))
	if texture == null:
		var label := Label3D.new()
		label.text = entry[1]
		label.font_size = 40
		label.pixel_size = 0.004
		label.width = 220.0
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.modulate = INK
		label.rotation.x = -PI * 0.5
		label.position.y = 0.002
		card.add_child(label)
	return card


## A stack of `count` cards, face down: as thick as they are.
func _add_stack(holder: Node3D, side: int, center: Vector3, count: int) -> void:
	if count <= 0:
		return
	var height := count * CARD_THICKNESS
	var box := BoxMesh.new()
	box.size = Vector3(PILE_CARD.x, height, PILE_CARD.y)
	var edges := MeshInstance3D.new()
	edges.mesh = box
	edges.material_override = _material(null, EDGE_COLOR)
	edges.position = center + Vector3(0, height * 0.5, 0)
	holder.add_child(edges)
	var face := _flat(PILE_CARD, _material(_back_texture))
	face.position = center + Vector3(0, height + 0.003, 0)
	face.rotation.y = PI if side == TOP else 0.0
	holder.add_child(face)


## A graveyard's vortex: a round disc lying on the table, turning (see vortex.gdshader).
func _make_vortex() -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = VORTEX_SHADER
	var vortex := _flat(Vector2(VORTEX, VORTEX), null)
	vortex.material_override = material
	return vortex


## A card going into a side's graveyard: lying where it was let go (`from`, a point of the table),
## it moves to the vortex and into it, getting smaller (without turning) until it is gone.
func _fall_into_vortex(side: int, entry: Array, from: Vector3) -> void:
	var card := _card_face(entry)
	var center := pile_center(side, &"grave")
	card.position = Vector3(from.x, 0.05, from.z)
	card.rotation.y = PI if side == TOP else 0.0
	_viewport.add_child(card)
	_falling += 1
	var fall := create_tween().set_parallel()
	fall.tween_property(card, "position", center + Vector3(0, 0.01, 0), VORTEX_SECONDS).set_ease(Tween.EASE_IN)
	fall.tween_property(card, "scale", Vector3.ONE * 0.05, VORTEX_SECONDS).set_ease(Tween.EASE_IN)
	fall.chain().tween_callback(func() -> void:
		card.queue_free()
		_falling -= 1
	)


## The card back (see CardBack), drawn once into a texture.
func _render_card_back() -> Texture2D:
	var render := SubViewport.new()
	render.size = Vector2i(CardBack.CARD_SIZE * 0.5)
	render.transparent_bg = true
	render.render_target_update_mode = SubViewport.UPDATE_ONCE
	var back := CardBack.new()
	back.scale = Vector2.ONE * 0.5
	render.add_child(back)
	add_child(render)
	return render.get_texture()


## The outline of a pile's place: a thin border with a faint inside, white so the material can
## color it.
static func _make_slot_texture() -> Texture2D:
	var width := 114
	var height := 154
	var border := 4
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0.12))
	for y in height:
		for x in width:
			if x < border or y < border or x >= width - border or y >= height - border:
				image.set_pixel(x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(image)
