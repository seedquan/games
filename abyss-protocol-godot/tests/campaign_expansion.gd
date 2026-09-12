extends SceneTree
const ROOMS = preload("res://scripts/rooms.gd")
const SAVE = preload("res://scripts/run_save.gd")
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
	check(ROOMS.LAST_ROOM >= 30, "Five complete six-chamber regions are playable")
	if ROOMS.LAST_ROOM < 30:
		print("ABYSS EXPANSION: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	await process_frame
	var shapes := {}
	var regions := {}
	var guardians := {}
	var random := RandomNumberGenerator.new()
	random.seed = 321981
	for depth in range(1, ROOMS.LAST_ROOM + 1):
		check(ROOMS.choices(depth) == ["boss"] if depth % 6 == 0 else true, "Every region ends at an unavoidable guardian")
		var data := ROOMS.generate(depth, "combat" if depth == 1 else ROOMS.choices(depth)[0], random)
		game.arena.apply_room(data)
		var identity := str([data.bounds, data.cover, data.get("obstacles", [])])
		if not shapes.has(identity):
			shapes[identity] = true
			for grid in [game.arena.navigation, game.arena.large_navigation]:
				verify_connected(grid, data)
		regions[data.biome] = true
		if depth % 6 == 0: guardians[data.name] = true
		check(SAVE.recipe_valid(SAVE.room_recipe(data)), "Expanded room recipe validates at depth %d" % depth)
		check(SAVE.rebuild_room(SAVE.room_recipe(data)) == data, "Expanded room reconstructs all region data")
		if depth > 1:
			var bounds: Rect2 = data.get("bounds", Rect2(0, 0, 1600, 1050))
			check(bounds.get_area() >= 1600 * 1050 * 4, "Main chambers have at least four times the original floor envelope")
	check(regions.size() == 5 and guardians.size() == 5, "Five distinct regions and five named guardians exist")
	await camera_cases(random)
	game.queue_free()
	await process_frame
	print("ABYSS EXPANSION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func verify_connected(grid: AStarGrid2D, data: Dictionary) -> void:
	# Independent cardinal flood fill proves all navigation cells belong to one floor.
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
	var total := 0
	for y in range(grid.region.size.y):
		for x in range(grid.region.size.x):
			if not grid.is_point_solid(Vector2i(x, y)): total += 1
	if total != reached.size():
		var isolated: Array = []
		for y in range(grid.region.size.y):
			for x in range(grid.region.size.x):
				var id := Vector2i(x, y)
				if not grid.is_point_solid(id) and not reached.has(id): isolated.append(grid.get_point_position(id))
		print("ISOLATED FLOOR: ", data.name, " radius=", 28 if grid == game.arena.navigation else 56, " cells=", isolated.size(), " ", isolated.slice(0, 12))
	check(total == reached.size(), "All floor cells are connected for both actor radii: " + data.name)
	check(grid.region.size.x == int(data.bounds.size.x / 40), "Navigation spans the entire deck width")
	for point in [data.start, data.start + Vector2(60, 0)] + data.exits + data.spawns:
		check(reached.has(game.arena.nearest_cell(point, grid)), "Arrival, exit and spawn reach every floor region")

func camera_cases(rng: RandomNumberGenerator) -> void:
	game.coop.enabled = true
	game.coop.devices.assign([1, 3])
	game.configure_input()
	game.start_run(533)
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	game.next_room(ROOMS.generate(30, "boss", rng))
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	for member in game.team(): member.set_physics_process(false)
	# Opposite distant corners, including a boss, used to exceed the fixed min zoom.
	game.player.position = Vector2(500, 1700)
	game.companion.position = Vector2(2700, 400)
	for resolution in [Vector2i(1280, 800), Vector2i(2560, 1440)]:
		root.size = resolution
		for frame in range(3): await process_frame
		game.camera.reset_smoothing()
		game.camera.force_update_scroll()
		var viewport: Rect2 = game.get_viewport_rect()
		for actor in [game.player, game.companion, game.active_boss]:
			var projected: Vector2 = game.get_viewport().get_canvas_transform() * actor.position
			check(viewport.grow(-85).has_point(projected), "Shared camera frames distant partners and guardian at " + str(resolution))
