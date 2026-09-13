extends SceneTree
## Native rendering stress and repeated-session cleanup. No player save access.
## Frame measurements are wall-clock samples, not a claim about other hardware.

var game
var cooperative := "--coop" in OS.get_cmdline_user_args()
var expanded := "--expanded" in OS.get_cmdline_user_args()
var guardians := "--guardians" in OS.get_cmdline_user_args()
var failures: Array[String] = []
var checks := 0
var samples: Array[float] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func frame() -> void:
	await physics_frame
	await process_frame

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Performance acceptance requires a native rendered window")
		quit(1)
		return
	root.size = Vector2i(2560, 1440) if cooperative else Vector2i(1440, 900)
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	if "--desktop-size" in OS.get_cmdline_user_args():
		game.fit_window_to_screen()
	var measured_resolution := root.size
	if cooperative:
		game.coop.enabled = true
		game.coop.devices.assign([1, 3])
		game.coop.weapons.assign(["scatter", "scatter"])
		game.configure_input()
	game.start_run(3102)
	await frame()
	if expanded:
		for enemy in get_nodes_in_group("enemies"):
			enemy.get_parent().remove_child(enemy)
			enemy.queue_free()
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		game.next_room(game.ROOMS.generate(30, "boss", rng))
		await frame()
	# More than twice the campaign's maximum population, including boss patterns.
	for i in range(28):
		var point: Vector2 = game.room_data.spawns[i % game.room_data.spawns.size()]
		game.spawn_enemy("drone" if i % 2 else "stalker", point)
	if not expanded: game.spawn_enemy("boss", Vector2(800, 280))
	for enemy in get_nodes_in_group("enemies"):
		enemy.hp = 1000000
		enemy.max_hp = 1000000
	for member in game.team():
		member.invulnerable = 1000
		member.weapon.equip("scatter")
		Input.action_press(member.action("slash"))
		member.input_armed = true
	for i in range(120):
		await frame()
	var previous := Time.get_ticks_usec()
	var peak_nodes := 0
	var peak_projectiles := 0
	for i in range(900):
		game.player.aim = Vector2.from_angle(i * 0.04)
		if i % 45 == 0:
			game.player.weapon.equip(["scatter", "sbow", "ember", "rail"][i / 45 % 4])
			game.player.slash_cooldown = 0
			game.player.weapon.fire(1.0)
		if i % 90 == 0:
			game.spawn_hazard(game.player.position + Vector2(120, 20), 95, 22)
		if guardians and i % 120 == 0:
			var id: String = game.GUARDIAN_ATTACK.IDS[(i / 120) % 5]
			for spec in game.GUARDIAN_ATTACK.placements(id, game.player.position - Vector2(180, 0), Vector2.RIGHT, game.team()):
				game.spawn_guardian_attack(spec, 22)
		await frame()
		var now := Time.get_ticks_usec()
		samples.append((now - previous) / 1000.0)
		if root.size != measured_resolution:
			check(false, "Window resizing invalidated the performance sample: %s -> %s" % [measured_resolution, root.size])
			break
		previous = now
		peak_nodes = maxi(peak_nodes, get_node_count())
		peak_projectiles = maxi(peak_projectiles, game.get_node("World/Projectiles").get_child_count())
	for member in game.team():
		Input.action_release(member.action("slash"))
	check(game.state == "playing", "Dense battle remains responsive for the whole sample")
	check(game.sound.voices.size() == 12, "Stress retains the bounded audio pool")
	game.show_menu("paused")
	game.abandon_to_title()
	game.start_run(3102)
	game.show_menu("paused")
	game.abandon_to_title()
	for i in range(8):
		await frame()
	var baseline := get_node_count()
	var orphan_baseline := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for i in range(40):
		game.start_run(7000 + i)
		for enemy in get_nodes_in_group("enemies"):
			enemy.take_damage(1000000, Vector2.ZERO)
		await frame()
		game.show_menu("paused")
		game.abandon_to_title()
		check(game.state == "title" and game.encounter.pending.is_empty(), "Restart returns to the dock and cancels pending reinforcement")
		for j in range(3):
			await frame()
		check(get_node_count() <= baseline + 4, "Restart %d returns to a stable node count" % i)
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_baseline, "Repeated sessions do not leak orphan nodes")
	samples.sort()
	var p50 := samples[int(samples.size() * 0.5)]
	var p95 := samples[int(samples.size() * 0.95)]
	var p99 := samples[int(samples.size() * 0.99)]
	check(p95 <= 25.0 and p99 <= 50.0, "Native stress frame pacing meets the local 60 Hz acceptance envelope")
	var report := {"rendering_device": RenderingServer.get_video_adapter_name(), "os": OS.get_name(), "engine": Engine.get_version_info().string,
		"cooperative": cooperative, "expanded_map": expanded, "guardian_signatures": guardians, "resolution": "%dx%d" % [root.size.x, root.size.y], "screen_scale": DisplayServer.screen_get_scale(), "samples": samples.size(), "frame_ms_p50": p50, "frame_ms_p95": p95, "frame_ms_p99": p99,
		"frame_ms_max": samples[-1], "peak_nodes": peak_nodes, "peak_projectiles": peak_projectiles,
		"restart_cycles": 40, "orphan_baseline": orphan_baseline, "failures": failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/qa"))
	var report_name := "performance" + ("-coop" if cooperative else "") + ("-expanded" if expanded else "") + ("-guardians" if guardians else "")
	var file := FileAccess.open("res://builds/qa/" + report_name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	game.queue_free()
	for i in range(6):
		await frame()
	print("ABYSS PERFORMANCE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
