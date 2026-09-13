extends SceneTree
const ATTACK = preload("res://scripts/guardian_attack.gd")
var game
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count := 2) -> void:
	for i in range(count): await physics_frame
	await process_frame

func reset_case(cooperative := false) -> void:
	game.coop.enabled = cooperative
	game.coop.devices.assign([1, 3] if cooperative else [-1, -1])
	game.configure_input()
	game.start_run(715)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	for member in game.team():
		member.set_physics_process(false)
		member.hp = 100
		member.invulnerable = 0
		member.position = Vector2(800, 650)
	await frames()

func geometry_cases() -> void:
	await reset_case()
	var samples := {
		"sweep": [[Vector2(180, 0), true], [Vector2(-100, 0), false], [Vector2(0, 180), false], [Vector2(270, 0), false]],
		"lattice": [[Vector2(200, 0), true], [Vector2(-200, 0), true], [Vector2(200, 45), false], [Vector2(450, 0), false]],
		"heat_ring": [[Vector2(150, 0), true], [Vector2(0, 180), true], [Vector2(120, 0), false], [Vector2(300, 0), false]],
		"sequence": [[Vector2(200, 0), true], [Vector2(70, 0), false], [Vector2(0, 200), false], [Vector2(370, 0), false]],
	}
	for id in samples:
		for heading in range(8):
			var aim := Vector2.from_angle(heading * TAU / 8.0)
			var spec: Dictionary = ATTACK.placements(id, Vector2(800, 650), aim, [game.player])[0]
			var attack = game.spawn_guardian_attack(spec, 22)
			attack.set_physics_process(false)
			for sample in samples[id]:
				var point: Vector2 = attack.position + sample[0].rotated(aim.angle())
				check(attack.contains_point(point) == sample[1], "%s heading %d has the intended safe and unsafe regions" % [id, heading])
			attack.queue_free()
	await frames()
	# Real damage timing and rendering use the same polygon data, for each shape.
	for id in ATTACK.IDS:
		var spec: Dictionary = ATTACK.placements(id, Vector2(800, 650), Vector2.RIGHT, [game.player])[0]
		var attack = game.spawn_guardian_attack(spec, 22)
		attack.set_physics_process(false)
		game.player.position = attack.position + (Vector2(180, 0) if id in ["sweep", "heat_ring", "sequence"] else Vector2.ZERO)
		game.player.hp = 100
		game.player.invulnerable = 0
		game.player.parry_left = 1
		attack._physics_process(attack.delay - 0.01)
		check(game.player.hp == 100 and not attack.fired, id + " preserves its entire warning before damage")
		attack._physics_process(0.02)
		check(game.player.hp == 78 and attack.fired, id + " damage matches its drawn region and cannot be parried")
		game.player.invulnerable = 0
		attack._physics_process(0.03)
		check(game.player.hp == 78, id + " deals damage only once")
		attack.queue_free()
	await frames()

func boundaries_and_coop() -> void:
	await reset_case(true)
	var spec := {"position": Vector2(800, 650), "shape": "beam", "radius": 440.0}
	var attack = game.spawn_guardian_attack(spec, 22)
	attack.set_physics_process(false)
	game.companion.position = Vector2(950, 650)
	game.player.invulnerable = 0.23
	attack._physics_process(attack.delay)
	check(game.player.hp == 100 and game.companion.hp == 78, "Dash immunity protects one player while the other still takes a real hit")
	attack.queue_free()
	attack = game.spawn_guardian_attack(spec, 22)
	attack.set_physics_process(false)
	game.state = "paused"
	attack._physics_process(2)
	check(attack.elapsed == 0 and not attack.fired, "Pause freezes placed warning clocks")
	game.state = "playing"
	attack.queue_free()
	game.player.position = Vector2(420, 420)
	game.player.invulnerable = 0
	game.player.hp = 100
	attack = game.spawn_guardian_attack({"position": Vector2(420, 290), "shape": "beam", "heading": PI / 2}, 22)
	attack.set_physics_process(false)
	check(attack.contains_point(game.player.position) and not game.has_sight(attack.position, game.player.position), "Cover sample is inside a warning but behind real cover")
	attack._physics_process(attack.delay)
	check(game.player.hp == 100, "Placed boss attacks respect solid cover")
	attack.queue_free()
	var placements := ATTACK.placements("coolant", Vector2.ZERO, Vector2.RIGHT, game.team())
	check(placements.size() == 6, "Cooling guardian marks three lanes for each living partner")
	for seat in range(2):
		check(placements[seat * 3 + 1].position == game.team()[seat].position, "Cooling marks each partner's actual position")
		check(placements[seat * 3].delay < placements[seat * 3 + 1].delay and placements[seat * 3 + 1].delay < placements[seat * 3 + 2].delay, "Cooling lanes detonate in a readable sequence")
	game.start_run(716)
	check(game.get_node("World/Projectiles").get_child_count() == 0, "Restart clears every placed attack")
	await frames()

func guardian_cases() -> void:
	await reset_case()
	var rng := RandomNumberGenerator.new()
	rng.seed = 901
	for i in range(5):
		game.next_room(game.ROOMS.generate((i + 1) * 6, "boss", rng))
		var boss = game.active_boss
		boss.set_physics_process(false)
		game.player.set_physics_process(false)
		boss.committed_direction = Vector2.RIGHT
		game.player.position = boss.position + Vector2(180, 0)
		check(boss.next_attack() == ATTACK.IDS[i], "Every region opens with its own signature attack")
		boss.release_attack()
		var hazards: Array = game.get_node("World/Projectiles").get_children()
		check(hazards.size() == [1, 3, 2, 1, 4][i], "Guardian releases its actual unique attack geometry")
		for hazard in hazards:
			check(hazard.get_script() == ATTACK and hazard.delay >= 0.95 and hazard.elapsed == 0, "Every placed signature gets a fresh complete warning")
			hazard.set_physics_process(false)
			hazard.elapsed = 0.55
			hazard.queue_redraw()
		await frames(70 if DisplayServer.get_name() != "headless" else 4)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://builds/qa")
			root.get_texture().get_image().save_png("res://builds/qa/guardian-%d.png" % (i + 1))
	# Old twelve-room bosses keep their original pattern source.
	game.campaign_version = 1
	game.next_room(game.ROOMS.generate(6, "boss", rng, 1))
	check(game.active_boss.guardian_patterns.is_empty() and not game.active_boss.next_attack() in ATTACK.IDS, "Legacy guardian retains its original attacks")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	game.narrative_enabled = false
	root.add_child(game)
	await frames()
	await geometry_cases()
	await boundaries_and_coop()
	await guardian_cases()
	game.queue_free()
	await create_timer(0.2).timeout
	print("ABYSS GUARDIAN ATTACKS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
