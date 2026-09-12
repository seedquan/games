extends SceneTree
## Every frozen map, independent of random room selection: art landmarks,
## actual physics, both navigation clearances, entry/exit safety and boss room.
const ROOMS = preload("res://scripts/rooms.gd")
const MAP = preload("res://scripts/map_art.gd")
const NAMES := ["docking", "cooling", "archive", "furnace", "core"]
# Traced dry floor landmarks in the shared 1547 x 1016 calibration frame.
const OPEN := [
	[Vector2(774, 460), Vector2(345, 435), Vector2(1200, 435), Vector2(774, 700)],
	[Vector2(774, 438), Vector2(774, 650), Vector2(400, 165), Vector2(400, 720)],
	[Vector2(774, 460), Vector2(774, 775), Vector2(290, 460), Vector2(1250, 460)],
	[Vector2(774, 438), Vector2(774, 740), Vector2(290, 430), Vector2(1255, 430)],
	[Vector2(774, 500), Vector2(525, 315), Vector2(1022, 315), Vector2(525, 710), Vector2(1022, 710)],
]
# Interior points on painted machinery, closed service bays and water.
const BLOCKED := [
	[Vector2(530, 285), Vector2(994, 285), Vector2(530, 600), Vector2(150, 425)],
	[Vector2(450, 330), Vector2(600, 545), Vector2(1100, 330), Vector2(135, 400)],
	[Vector2(500, 260), Vector2(1040, 465), Vector2(500, 680), Vector2(225, 330)],
	[Vector2(470, 430), Vector2(1075, 430), Vector2(150, 425), Vector2(1380, 425)],
	[Vector2(250, 520), Vector2(1297, 520), Vector2(774, 130), Vector2(610, 380)],
]
const GUARDIAN_BLOCKED := [
	[Vector2(510, 270), Vector2(1100, 790)],
	[Vector2(485, 468), Vector2(1060, 468)],
	[Vector2(440, 265), Vector2(1080, 265)],
	[Vector2(430, 190), Vector2(1100, 190)],
	[Vector2(305, 240), Vector2(1240, 240)],
]
var checks := 0
var failures := 0
var game

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	await process_frame
	# Keep the scene's real static bodies registered while the title menu leaves
	# gameplay actors disabled; this suite does not need to simulate combat.
	game.arena.process_mode = Node.PROCESS_MODE_ALWAYS
	var random := RandomNumberGenerator.new()
	random.seed = 297143
	var seen := {}
	for chapter in range(5):
		for guardian in [false, true]:
			var depth: int = (chapter + 1) * 6 if guardian else maxi(2, chapter * 6 + 1)
			var data := ROOMS.generate(depth, "boss" if guardian else "combat", random)
			var filename: String = NAMES[chapter] + ("-guardian" if guardian else "") + ".png"
			check(data.get("art", "") == "res://assets/map/calibrated/" + filename, "Region selects its frozen artwork: " + filename)
			seen[data.get("art", "")] = true
			game.arena.apply_room(data)
			await physics_frame
			await process_frame
			check(game.arena.map_texture != null, "Calibrated texture imports: " + filename)
			check(data.bounds == ROOMS.LARGE_BOUNDS, "Artwork, collision and navigation share the full room bounds")
			var scale_map: Vector2 = data.bounds.size / MAP.SOURCE_SIZE
			var open_points: Array = [Vector2(774, 460), Vector2(774, 700), Vector2(600, 460), Vector2(950, 460)] if guardian else OPEN[chapter]
			for source_point in open_points:
				var point: Vector2 = source_point * scale_map
				check(ROOMS.walkable(point, data.cover, 56, data.bounds, data.obstacles), "Painted dry route has large-actor clearance: " + filename + " " + str(source_point))
				check(not physical_wall(point), "Painted dry route is physically open: " + filename)
			for source_point in (GUARDIAN_BLOCKED[chapter] if guardian else BLOCKED[chapter]):
				var point: Vector2 = source_point * scale_map
				check(not ROOMS.walkable(point, data.cover, 0, data.bounds, data.obstacles), "Painted machinery/water blocks movement: " + filename)
				check(physical_wall(point), "Painted machinery/water has a real physics body: " + filename)
			for grid in [game.arena.navigation, game.arena.large_navigation]:
				verify_navigation(grid, data, filename)
			for point in [data.start, data.start + Vector2(60, 0)] + data.exits:
				check(ROOMS.walkable(point, data.cover, 56, data.bounds, data.obstacles), "Both arrivals and both exits have full clearance: " + filename)
			check(data.spawns.size() >= 5, "Artwork retains separated encounter positions: " + filename)
			if guardian:
				for index in range(16):
					var point: Vector2 = data.boss_start + Vector2.from_angle(TAU * index / 16.0) * 300.0
					check(ROOMS.walkable(point, data.cover, 56, data.bounds, data.obstacles), "Guardian retains a 600-unit diameter maneuvering circle: " + filename)
	check(seen.size() == 10, "All five exploration maps and five guardian maps were exercised")
	game.queue_free()
	await process_frame
	print("ABYSS MAP ART: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func physical_wall(point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	return not game.arena.get_world_2d().direct_space_state.intersect_point(query).is_empty()

func verify_navigation(grid: AStarGrid2D, data: Dictionary, filename: String) -> void:
	# Cardinal flood fill is independent of the AStar pathfinder under test.
	var origin: Vector2i = game.arena.nearest_cell(data.start, grid)
	var reached := {origin: true}
	var queue: Array[Vector2i] = [origin]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + offset
			if grid.region.has_point(next) and not grid.is_point_solid(next) and not reached.has(next):
				reached[next] = true
				queue.append(next)
	var available := 0
	for y in range(grid.region.size.y):
		for x in range(grid.region.size.x):
			if not grid.is_point_solid(Vector2i(x, y)): available += 1
	check(available == reached.size(), "Every floor cell is connected at navigation radius %d: %s" % [28 if grid == game.arena.navigation else 56, filename])
	for point in [data.start, data.start + Vector2(60, 0)] + data.exits + data.spawns:
		var target: Vector2i = game.arena.nearest_cell(point, grid)
		check(reached.has(target) and not grid.get_id_path(origin, target).is_empty(), "Entry, exit and hostile spawn are reachable on both grids: " + filename)
