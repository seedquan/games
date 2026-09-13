extends SceneTree
## Finite combat, exact room income and bounded pressure; not a timing playtest.
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 1) -> void:
	for i in range(count): await physics_frame
	await process_frame

func room_case(depth: int, kind: String, cooperative: bool, legacy := false) -> void:
	game.coop.enabled = cooperative
	game.coop.devices.assign([1, 3] if cooperative else [-1, -1])
	game.start_run(8142)
	# This fixture jumps directly to a sampled room; normal routes arrive after clearing.
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 731 + depth
	game.next_room(game.ROOMS.generate(depth, kind, rng, 1 if legacy else 2))
	for member in game.team(): member.set_physics_process(false)
	var expected_kills: int = game.encounter.total
	var budget: int = game.encounter.scrap_budget
	var prior_scrap: int = game.scrap
	var counted := 0
	var loot := 0
	var repaired := false
	var seen := {}
	game.player.hp = 50.0
	if cooperative: game.companion.hp = 0.0 if depth == 29 else game.companion.max_hp - 1.0
	var limit := Time.get_ticks_msec() + 10000
	while game.state == "playing" and Time.get_ticks_msec() < limit:
		var enemies := get_nodes_in_group("enemies")
		check(enemies.size() <= (14 if legacy else 6), "Simultaneous pressure stays bounded")
		for enemy in enemies:
			check(not seen.has(enemy.get_instance_id()), "Each scheduled hostile contributes once")
			seen[enemy.get_instance_id()] = true
			counted += 1
			loot += enemy.scrap_reward
			enemy.take_damage(enemy.hp, Vector2.ZERO)
		await frames()
		if game.encounter.wave == 2 and not repaired:
			check(game.player.hp == 52.0, "A cleared wave repairs two integrity without reviving or overshooting")
			if cooperative:
				check(game.companion.hp == (0.0 if depth == 29 else game.companion.max_hp), "Wave repair caps partner integrity and does not revive a downed seat")
			repaired = true
	check(game.state == "reward", "Finite encounter reaches its actual reward screen")
	check(counted == expected_kills, "Every reserved reinforcement is spawned exactly once")
	check(loot == budget, "More enemies preserve the previous exact kill-income budget")
	check(game.scrap - prior_scrap == budget + (40 + depth * 5) * (2 if kind == "elite" else 1), "Room completion awards the same total income once")
	if legacy:
		check(game.encounter.waves.size() == 1 and game.player.hp == 50, "Legacy encounter count and healing remain unchanged")
	else:
		check(expected_kills >= 60 and repaired, "New rooms contain several active combat waves")
	var banked: int = game.scrap
	game.complete_room()
	check(game.scrap == banked, "Repeated room completion cannot re-award the expanded encounter")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	await frames()
	Engine.time_scale = 32
	for cooperative in [false, true]:
		for entry in [[1, "combat"], [2, "combat"], [5, "elite"], [29, "elite"]]:
			await room_case(entry[0], entry[1], cooperative)
	await room_case(1, "combat", false, true)
	await room_case(8, "elite", false, true)
	Engine.time_scale = 1
	game.queue_free()
	await create_timer(0.2).timeout
	print("ABYSS ENCOUNTER PACING: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
