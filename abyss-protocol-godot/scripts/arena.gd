extends Node2D
## Static geometry is drawn once and cached by the canvas renderer.

const FONT = preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const FLOOR = preload("res://assets/station.webp")
const ROOMS = preload("res://scripts/rooms.gd")
const COVER_VISUAL = preload("res://scripts/cover_visual.gd")
var bounds := ROOMS.SMALL_BOUNDS
var cover: Array = []
var room_data: Dictionary = {}
var navigation: AStarGrid2D
var large_navigation: AStarGrid2D
var scenery: Node2D
var map_texture: Texture2D
var obstacles: Array = []

func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	apply_room(ROOMS.generate(1, "combat", rng))

func apply_room(data: Dictionary) -> void:
	room_data = data
	bounds = data.get("bounds", ROOMS.SMALL_BOUNDS)
	map_texture = load(data.art) if data.has("art") else null
	cover = data.cover
	obstacles = data.get("obstacles", [])
	for body in get_children():
		remove_child(body)
		body.queue_free()
	for rect in perimeter():
		add_wall(rect)
	for rect in cover:
		add_wall(rect)
	for polygon in obstacles:
		add_polygon_wall(polygon)
	build_scenery()
	build_navigation()
	queue_redraw()

func build_scenery() -> void:
	if is_instance_valid(scenery) and not scenery.is_queued_for_deletion():
		if scenery.get_parent():
			scenery.get_parent().remove_child(scenery)
		scenery.queue_free()
	scenery = Node2D.new()
	scenery.name = "StationEquipment"
	scenery.y_sort_enabled = true
	get_parent().get_node("Actors").add_child(scenery)
	if map_texture != null: return
	var furnishings: Array = room_data.get("furnishings", cover)
	for index in range(furnishings.size()):
		var rect: Rect2 = furnishings[index]
		var columns := maxi(1, ceili(rect.size.x / 180.0))
		var rows := maxi(1, ceili(rect.size.y / 150.0))
		for row in range(rows):
			for column in range(columns):
				var prop = COVER_VISUAL.new()
				prop.game = get_parent().get_parent()
				prop.cell = (index + row + column + int(room_data.depth)) % 3
				var span := rect.size.x / columns
				prop.extent = Vector2(span + 15, clampf(span * 1.2, 100, 170))
				prop.position = rect.position + Vector2(span * (column + 0.5), rect.size.y / rows * (row + 0.65))
				scenery.add_child(prop)

func build_navigation() -> void:
	navigation = build_grid(28.0)
	large_navigation = build_grid(56.0)

func build_grid(clearance: float) -> AStarGrid2D:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, Vector2i(ceil(bounds.size / 40.0)))
	grid.cell_size = Vector2(40, 40)
	grid.offset = Vector2(20, 20)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for y in range(grid.region.size.y):
		for x in range(grid.region.size.x):
			var id := Vector2i(x, y)
			grid.set_point_solid(id, not ROOMS.walkable(grid.get_point_position(id), cover, clearance, bounds, obstacles))
	return grid

func nearest_cell(point: Vector2, grid: AStarGrid2D = null) -> Vector2i:
	if grid == null:
		grid = navigation
	var center := Vector2i(clampi(int(point.x / 40), 0, grid.region.end.x - 1), clampi(int(point.y / 40), 0, grid.region.end.y - 1))
	if not grid.is_point_solid(center):
		return center
	var best := center
	var distance := INF
	for y in range(maxi(0, center.y - 3), mini(grid.region.end.y, center.y + 4)):
		for x in range(maxi(0, center.x - 3), mini(grid.region.end.x, center.x + 4)):
			var cell := Vector2i(x, y)
			var length := point.distance_squared_to(grid.get_point_position(cell))
			if not grid.is_point_solid(cell) and length < distance:
				best = cell
				distance = length
	return best

func steering(from: Vector2, to: Vector2, clearance := 28.0) -> Vector2:
	var grid := large_navigation if clearance > 40.0 else navigation
	var path := grid.get_point_path(nearest_cell(from, grid), nearest_cell(to, grid))
	if path.size() < 2:
		return from.direction_to(to)
	return from.direction_to(path[1])

func path_exists(from: Vector2, to: Vector2) -> bool:
	return not navigation.get_id_path(nearest_cell(from), nearest_cell(to)).is_empty()

func add_wall(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = rect.get_center()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func add_polygon_wall(polygon: PackedVector2Array) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionPolygon2D.new()
	shape.polygon = polygon
	body.add_child(shape)
	add_child(body)

func perimeter() -> Array[Rect2]:
	return [Rect2(0, 0, bounds.size.x, 40), Rect2(0, bounds.end.y - 40, bounds.size.x, 40),
		Rect2(0, 40, 40, bounds.size.y - 80), Rect2(bounds.end.x - 40, 40, 40, bounds.size.y - 80)]

func _draw() -> void:
	if map_texture != null:
		draw_texture_rect(map_texture, bounds, false)
		return
	var region: Dictionary = room_data.get("region", {})
	var hot: bool = region.get("name", "") == "地热熔炉" if not region.is_empty() else int(room_data.get("depth", 1)) > 6
	var accent := Color(region.get("palette", "b88b63" if hot else "9cae9e"))
	var scale_map := bounds.size / ROOMS.SMALL_BOUNDS.size
	# Large deck plates carry the perspective; fine texture stays subordinate.
	draw_rect(bounds, Color(region.get("deck", "252a2b" if hot else "202a2d")))
	draw_texture_rect(FLOOR, bounds, true, Color(0.7, 0.72, 0.65, 0.16))
	for x in range(80, int(bounds.end.x - 40), 160):
		for y in range(90, int(bounds.end.y - 160), 160):
			var plate := Rect2(x, y, 156, 156)
			draw_rect(plate, Color(0.65, 0.67, 0.59, 0.015 if (x / 160 + y / 160) % 2 == 0 else 0.035))
			draw_line(plate.position, plate.position + Vector2(156, 0), Color(0.72, 0.76, 0.69, 0.075))
			draw_line(plate.position, plate.position + Vector2(0, 156), Color(0.02, 0.03, 0.035, 0.45))
	# Recessed service lanes and actual station fixtures replace decorative rings.
	for x in [190, bounds.end.x - 220]:
		draw_rect(Rect2(x, 110, 30, bounds.size.y - 220), Color("141e22"))
		for y in range(120, int(bounds.end.y - 120), 16):
			draw_line(Vector2(x + 5, y), Vector2(x + 25, y), Color("3b4545"), 2)
	for y in [130, bounds.end.y - 122]:
		draw_line(Vector2(260, y), Vector2(bounds.end.x - 260, y), Color(accent, 0.19), 2)
		for x in range(int(bounds.size.x / 2 - 140), int(bounds.size.x / 2 + 140), 42):
			draw_line(Vector2(x, y - 7), Vector2(x + 16, y + 7), Color(accent, 0.26), 5)
	# Raised perimeter walls and warm utility lights make room boundaries explicit.
	for rect in perimeter():
		draw_rect(rect, Color("111a1e"))
		draw_rect(rect, Color("53605c"), false, 2)
	for x in range(120, int(bounds.end.x - 70), 180):
		draw_rect(Rect2(x, 25, 54, 7), Color("c4c8ad"))
		draw_rect(Rect2(x, bounds.end.y - 34, 54, 7), Color("c4c8ad"))
	for rect in room_data.get("furnishings", cover):
		draw_rect(Rect2(rect.position + Vector2(6, 13), rect.size), Color(0.015, 0.025, 0.03, 0.5))
		draw_rect(rect, Color("303a3c"))
		draw_rect(rect, Color("6b7269"), false, 2)
		for x in range(8, int(rect.size.x) - 8, 22):
			draw_line(rect.position + Vector2(x, rect.size.y - 6), rect.position + Vector2(x + 8, rect.size.y - 6), Color("a39470"), 3)
	draw_chamber_architecture(accent, hot)
	var stencil := Color(accent, 0.36)
	draw_string(FONT, Vector2(bounds.size.x / 2 - 150, 260), "%02d" % room_data.get("depth", 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 64, stencil)
	draw_string(FONT, Vector2(bounds.size.x / 2 - 150, 294), room_data.get("name", "接驳船坞"), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, stencil)
	if room_data.get("kind", "combat") == "boss":
		for radius in [168, 188]:
			draw_arc(room_data.get("boss_start", Vector2(800, 310)), radius, 0, TAU, 64, Color(accent, 0.14), 4, true)
	elif room_data.get("kind", "combat") in ["shop", "rest"]:
		draw_rect(Rect2(Vector2(660, 470) * scale_map, Vector2(280, 280) * scale_map), Color(accent, 0.08))
		draw_line(Vector2(745, 610) * scale_map, Vector2(855, 610) * scale_map, Color(accent, 0.35), 24)
		draw_line(Vector2(800, 555) * scale_map, Vector2(800, 665) * scale_map, Color(accent, 0.35), 24)

func draw_chamber_architecture(accent: Color, hot: bool) -> void:
	# Cut solid bulkheads out of the deck drawing. Their footprints are the exact
	# rectangles added to physics and pathfinding, with an inset raised rim.
	var motif: String = room_data.get("motif", "dock")
	var strips: Array = []
	match motif:
		"cargo": strips = [Rect2(760, 360, 80, 410)]
		"coolant", "crucible": strips = [Rect2(560, 310, 34, 460), Rect2(1006, 310, 34, 460)]
		"junction": strips = [Rect2(380, 574, 840, 30)]
		"archive": strips = [Rect2(554, 330, 34, 420), Rect2(1012, 330, 34, 420)]
		"furnace": strips = [Rect2(535, 338, 26, 404), Rect2(1039, 338, 26, 404)]
		"assembly": strips = [Rect2(555, 385, 28, 410), Rect2(930, 410, 28, 380)]
		_: strips = [Rect2(750, 340, 100, 155)]
	var scale_map := bounds.size / ROOMS.SMALL_BOUNDS.size
	for source in strips:
		var strip := Rect2(source.position * scale_map, source.size * scale_map)
		draw_rect(strip, Color("a98762") * Color(1, 1, 1, 0.13) if hot else Color(0.47, 0.71, 0.72, 0.10))
		draw_rect(strip.grow(-5), Color(accent, 0.16), false, 1)
	for rect in room_data.get("shell", []):
		draw_rect(rect, Color("080f14"))
		draw_rect(rect.grow(-8), Color("101a20"), false, 12)
		draw_rect(rect, Color("768276"), false, 3)
		for x in range(int(rect.position.x + 20), int(rect.end.x - 14), 32):
			draw_line(Vector2(x, rect.end.y - 9), Vector2(x + 10, rect.end.y - 9), Color(accent, 0.46), 3)
		if rect.size.x > 200 and rect.size.y > 150:
			var center: Vector2 = rect.get_center()
			draw_circle(center, 26, Color("26363b"))
			draw_arc(center, 18, 0, TAU, 24, Color(accent, 0.23), 3, true)
	# Twin pressure doors form a consistent visual destination at the far end.
	for i in range(room_data.get("exits", []).size()):
		var point: Vector2 = room_data.exits[i]
		var frame := Rect2(point - Vector2(73, 60), Vector2(146, 92))
		draw_rect(frame.grow(8), Color("0d181e"))
		draw_rect(frame, Color("56625e"), false, 4)
		draw_rect(frame.grow(-6), Color("263638"))
		draw_line(point + Vector2(0, -50), point + Vector2(0, 20), Color("10191e"), 4)
		draw_rect(Rect2(point + Vector2(-28, -54), Vector2(56, 5)), Color("c19d71"))
		draw_string(FONT, point + Vector2(-49, 55), "舱门 %02d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b8bca9"))
