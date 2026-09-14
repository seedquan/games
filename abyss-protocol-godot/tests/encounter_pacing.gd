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

func prime_case(cooperative: bool) -> void:
	game.coop.enabled = cooperative
	game.coop.devices.assign([1, 3] if cooperative else [-1, -1])
	game.start_run(8142)
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 733
	game.next_room(game.ROOMS.generate(2, "combat", rng, 2))
	game.set_physics_process(false)
	for member in game.team(): member.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	game.player.hp = 50
	if cooperative: game.companion.hp = game.companion.max_hp - 1
	var enemies := get_nodes_in_group("enemies")
	for i in range(enemies.size() - 2): enemies[i].take_damage(enemies[i].hp, Vector2.ZERO)
	game.encounter.tick(0.01)
	check(game.encounter.pending.size() == 6, "The last two enemies prime the next full warning without waiting for an empty room")
	if game.encounter.pending.is_empty():
		game.set_physics_process(true)
		return
	check(game.player.hp == 50, "Priming a warning does not grant the clear-wave repair early")
	var first: Dictionary = game.encounter.pending[0]
	var delay: float = first.delay
	game.state = "paused"
	game.encounter.tick(3.0)
	check(first.delay == delay, "Pause freezes a primed warning while old enemies remain")
	game.state = "playing"
	game.encounter.tick(0.7)
	check(game.encounter.pending.size() == 6 and get_nodes_in_group("enemies").size() == 2, "Partial warnings cannot spawn reinforcements")
	game.encounter.tick(0.7)
	check(game.encounter.pending.size() == 6 and get_nodes_in_group("enemies").size() == 2, "Even fully warned reinforcements wait for the previous enemies to die")
	check(first.marker.progress == 1.0 and game.player.hp == 50, "A ready marker holds its complete ring without granting repair")
	if DisplayServer.get_name() != "headless" and not cooperative:
		root.size = Vector2i(1280, 800)
		await frames(12)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/qa/encounter-primed.png")
	var remaining := get_nodes_in_group("enemies")
	remaining[0].take_damage(remaining[0].hp, Vector2.ZERO)
	game.encounter.tick(0.1)
	check(get_nodes_in_group("enemies").size() == 1 and game.encounter.pending.size() == 6, "One remaining enemy still prevents any new spawns")
	if cooperative: game.companion.position = first.point
	remaining[1].take_damage(remaining[1].hp, Vector2.ZERO)
	game.encounter.tick(0.01)
	check(game.player.hp == 52, "The last old enemy unlocks exactly one repair")
	if cooperative:
		check(game.companion.hp == game.companion.max_hp, "Cleared-wave repair still caps the partner's integrity")
		check(game.encounter.pending.has(first) and first.delay > 1.2 and first.point != game.companion.position, "An occupied primed landing moves and restarts its complete warning")
	else:
		check(game.encounter.pending.is_empty() and get_nodes_in_group("enemies").size() == 6, "An already warned clear lane starts the next batch without another empty delay")
	game.encounter.tick(0.1)
	check(game.player.hp == 52 and get_nodes_in_group("enemies").size() <= 6, "Repeated ticks cannot duplicate repair or exceed six enemies")
	game.start_run(8142)
	for member in game.team(): member.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	check(game.encounter.pending.is_empty() and game.encounter.wave == 1, "Restart discards all primed warnings")
	enemies = get_nodes_in_group("enemies")
	enemies[0].take_damage(enemies[0].hp, Vector2.ZERO)
	game.encounter.tick(0.01)
	check(game.encounter.pending.is_empty(), "The opening three-enemy lesson never primes warnings before its clear")
	for enemy in get_nodes_in_group("enemies"): enemy.take_damage(enemy.hp, Vector2.ZERO)
	game.encounter.tick(0.01)
	check(game.encounter.pending.size() == 6 and game.encounter.pending[0].delay > 1.2, "The teaching wave retains a full quiet warning after all three enemies die")
	game.encounter.tick(1.3)
	enemies = get_nodes_in_group("enemies")
	game.player.hp = 50
	for i in range(enemies.size() - 2): enemies[i].take_damage(enemies[i].hp, Vector2.ZERO)
	game.encounter.tick(0.01)
	for enemy in get_nodes_in_group("enemies"): enemy.take_damage(enemy.hp, Vector2.ZERO)
	game.encounter.tick(0.2)
	check(get_nodes_in_group("enemies").is_empty() and game.encounter.pending.size() == 6 and game.encounter.pending[0].delay > 0.9, "A rapid cleanup still waits for the remainder of the complete warning")
	check(game.player.hp == 52, "Rapid cleanup grants the same single repair before the landing")
	game.encounter.tick(1.1)
	check(get_nodes_in_group("enemies").size() == 6 and game.encounter.pending.is_empty() and game.player.hp == 52, "The remaining warning releases one batch without a second repair")
	game.set_physics_process(true)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	await frames()
	for cooperative in [false, true]: await prime_case(cooperative)
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
