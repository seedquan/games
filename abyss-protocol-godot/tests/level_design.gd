extends SceneTree
## Room topology, stable route promises and legacy checkpoint compatibility.
const ROOMS = preload("res://scripts/rooms.gd")
const LEGACY = preload("res://scripts/legacy_rooms.gd")
const SAVE = preload("res://scripts/run_save.gd")
const PROGRESSION = preload("res://scripts/progression.gd")
var checks := 0
var failures: Array[String] = []
var game

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	await process_frame
	var random := RandomNumberGenerator.new()
	random.seed = 72819
	var silhouettes := [{}, {}, {}, {}, {}]
	for depth in range(1, ROOMS.LAST_ROOM + 1):
		for kind in (["combat"] if depth == 1 else ROOMS.choices(depth)):
			var data := ROOMS.generate(depth, kind, random)
			check(data.get("generator", 1) == 2, "New rooms use an explicitly versioned topology recipe")
			check(data.has("shell") and data.has("tactic") and data.has("reward"), "Each room declares its silhouette, tactical role and reward")
			if not data.has("shell"):
				continue
			silhouettes[ROOMS.CHAPTERS.number(depth)][str(data.shell)] = true
			game.arena.apply_room(data)
			for point in [data.start, data.start + Vector2(60, 0)] + data.exits:
				check(ROOMS.walkable(point, data.cover, 32, game.arena.bounds, game.arena.obstacles), "Both arrivals and all exits have collision clearance")
				check(game.arena.path_exists(data.start, point), "Every exit is reachable from the shared entrance")
			for spawn in data.spawns:
				check(ROOMS.walkable(spawn, data.cover, 32, game.arena.bounds, game.arena.obstacles) and game.arena.path_exists(data.start, spawn), "Every hostile spawn lies in the connected traversable floor")
			check(data.spawns.size() >= 5, "Room shape retains sufficient separated encounter positions")
			if kind == "boss":
				check(ROOMS.walkable(data.boss_start, data.cover, 56, game.arena.bounds, game.arena.obstacles), "Boss starts clear of topology and furnishings")
			var recipe := SAVE.room_recipe(data)
			check(SAVE.recipe_valid(recipe) and SAVE.rebuild_room(recipe) == data, "Checkpoint restores exact geometry, reward and encounter recipe")
			await process_frame
	for pool in silhouettes:
		check(pool.size() >= 3, "Each biome offers at least three distinct physical silhouettes")
	for depth in [1, 4, 6, 9, 12]:
		random.seed = 501 + depth
		var kind := "boss" if depth % 6 == 0 else "combat"
		var original := LEGACY.generate(depth, kind, random)
		var old_recipe := {"depth": depth, "kind": kind, "generation_state": original.generation_state}
		check(SAVE.rebuild_room(old_recipe) == original, "Existing 0.10.1 checkpoint keeps its original map and RNG contract")
	var invalid := {"depth": 2, "kind": "combat", "generation_state": 55, "generator": 99}
	check(not SAVE.recipe_valid(invalid), "Unknown room generator versions are rejected rather than silently changing maps")
	for promise in ["damage", "health", "speed", "element"]:
		if not PROGRESSION.new().has_method("promised_offers"):
			check(false, "A door's reward promise must determine the actual upgrade offers")
			continue
		var offers: Array = PROGRESSION.new().call("promised_offers", random, false, {}, promise)
		var eligible := PROGRESSION.ELEMENTS if promise == "element" else [promise]
		check(offers.size() == 3 and offers.any(func(boon): return boon.stat in eligible), "Door promise appears in actual upgrade choice")
	await encounter_cases()
	game.queue_free()
	await process_frame
	print("ABYSS LEVEL DESIGN: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func encounter_cases() -> void:
	game.coop.enabled = true
	game.coop.devices.assign([1, 3])
	game.configure_input()
	game.start_run(111)
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 987
	game.next_room(ROOMS.generate(8, "elite", rng))
	for member in game.team(): member.set_physics_process(false)
	if game.get("encounter") == null:
		check(false, "Later encounters must use staged waves with spawn warnings")
		return
	var encounter = game.encounter
	check(encounter.waves.size() >= 2, "Later elite encounters have multiple waves")
	check(get_nodes_in_group("enemies").size() <= 6, "Wave staging bounds simultaneous enemies")
	var banked: int = game.profile.cores
	for enemy in get_nodes_in_group("enemies"): enemy.take_damage(1000000, Vector2.ZERO)
	await process_frame
	await process_frame
	check(game.state == "playing" and not encounter.pending.is_empty() and not game.room_awarded, "Clearing one wave starts a warning, not a room reward")
	game.complete_room()
	check(game.profile.cores == banked, "Pending reinforcements cannot award currency early")
	var remaining: float = encounter.pending[0].delay
	game.show_menu("paused")
	await create_timer(0.2).timeout
	check(is_equal_approx(encounter.pending[0].delay, remaining), "Pause freezes reinforcement warnings")
	game.resume_run()
	var old_point: Vector2 = encounter.pending[0].point
	var occupied_entry: Dictionary = encounter.pending[0]
	game.companion.position = old_point
	for entry in encounter.pending: entry.delay = 0.01
	# Reinforcement timers run on process delta. Two arbitrarily fast render
	# frames need not consume even 10 ms, especially during headless validation.
	for frame in range(30):
		await physics_frame
		await process_frame
		if occupied_entry.point != old_point or not encounter.pending.has(occupied_entry): break
	check(encounter.pending.has(occupied_entry) and occupied_entry.point != old_point and occupied_entry.delay > 1.0, "Reinforcement occupied by either player gets a new location and full warning")
	for enemy in get_nodes_in_group("enemies"):
		check(enemy.position.distance_to(game.companion.position) >= 140, "No reinforcement materializes on player two")
	game.start_run(222)
	check(encounter.pending.is_empty() and encounter.wave == 1 and get_nodes_in_group("enemies").size() == 3, "Restart cancels all old reinforcement work")
