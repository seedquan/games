extends SceneTree
## Native rendering stress and repeated-session cleanup. No player save access.
## Physics-observer intervals and render-completion intervals are separate.
## Neither is an OS presentation timestamp or a claim about other hardware.

var game
var cooperative := "--coop" in OS.get_cmdline_user_args()
var expanded := "--expanded" in OS.get_cmdline_user_args()
var guardians := "--guardians" in OS.get_cmdline_user_args()
var melee := "--melee" in OS.get_cmdline_user_args()
var poison := "--poison" in OS.get_cmdline_user_args()
var refits := "--refits" in OS.get_cmdline_user_args()
var conduction := "--conduction" in OS.get_cmdline_user_args()
var failures: Array[String] = []
var checks := 0
var samples: Array[float] = []
var rendered_samples: Array[float] = []
var render_cpu_samples: Array[float] = []
var recording := false
var last_render_tick := 0
var trace_frames := "--trace-frames" in OS.get_cmdline_user_args()

func render_completed() -> void:
	if not recording: return
	var now := Time.get_ticks_usec()
	if last_render_tick > 0: rendered_samples.append((now - last_render_tick) / 1000.0)
	last_render_tick = now
	if trace_frames:
		render_cpu_samples.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))

func distribution(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {"samples": 0}
	var ordered := values.duplicate()
	ordered.sort()
	return {"samples": ordered.size(), "p50": ordered[int(ordered.size() * 0.5)],
		"p95": ordered[int(ordered.size() * 0.95)], "p99": ordered[int(ordered.size() * 0.99)], "max": ordered[-1]}

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
		if refits: game.PROGRESSION.apply(game.PROGRESSION.rune("mod_flow"), member, 2)
		Input.action_press(member.action("slash"))
		member.input_armed = true
	for i in range(120):
		await frame()
	var display_context := {"refresh_hz": DisplayServer.screen_get_refresh_rate(root.current_screen),
		"vsync_mode": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"renderer": RenderingServer.get_current_rendering_method()}
	if trace_frames: RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	RenderingServer.frame_post_draw.connect(render_completed)
	recording = true
	var first_physics_frame := Engine.get_physics_frames()
	var first_process_frame := Engine.get_process_frames()
	var previous := Time.get_ticks_usec()
	var peak_nodes := 0
	var peak_projectiles := 0
	var peak_melee_traces := 0
	var melee_frames := 0
	var poison_frames := 0
	var peak_poison_markers := 0
	var conduction_frames := 0
	var peak_conduction := 0
	for i in range(900):
		game.player.aim = Vector2.from_angle(i * 0.04)
		if i % 45 == 0:
			if melee:
				for member in game.team():
					member.weapon.equip(["fang", "blade", "lance", "maul", "arc", "whip", "prism"][(i / 45 + member.seat) % 7])
					member.slash_cooldown = 0
					member.weapon.fire()
			else:
				game.player.weapon.equip(["scatter", "sbow", "ember", "rail"][i / 45 % 4])
				game.player.slash_cooldown = 0
				game.player.weapon.fire(1.0)
		if i % 90 == 0:
			game.spawn_hazard(game.player.position + Vector2(120, 20), 95, 22)
			if poison:
				# Refresh six-frame status art across the stress population. Zero
				# poison power isolates its rendering cost from extra enemy deaths.
				var index := 0
				for enemy in get_nodes_in_group("enemies"):
					enemy.poison_stacks = 0
					for layer in range(index % 6 + 1): enemy.apply_element("poison", 0)
					index += 1
		if guardians and i % 120 == 0:
			var id: String = game.GUARDIAN_ATTACK.IDS[(i / 120) % 5]
			for spec in game.GUARDIAN_ATTACK.placements(id, game.player.position - Vector2(180, 0), Vector2.RIGHT, game.team()):
				game.spawn_guardian_attack(spec, 22)
		if conduction and i % 60 == 0:
			# A deliberate dense proc fixture; normal-rule pacing is measured by
			# the input bot. Use real freeze/shock paths and their existing guard.
			for enemy in get_nodes_in_group("enemies"):
				enemy.freeze_for(1.8)
				enemy.apply_element("shock", 40)
		await frame()
		var now := Time.get_ticks_usec()
		samples.append((now - previous) / 1000.0)
		if root.size != measured_resolution:
			check(false, "Window resizing invalidated the performance sample: %s -> %s" % [measured_resolution, root.size])
			break
		previous = now
		peak_nodes = maxi(peak_nodes, get_node_count())
		peak_projectiles = maxi(peak_projectiles, game.get_node("World/Projectiles").get_child_count())
		if poison:
			var visible_markers := 0
			for enemy in get_nodes_in_group("enemies"):
				var bounds: Rect2 = enemy.get_global_transform_with_canvas() * enemy.poison_marker_rect()
				if enemy.poison_marker_level() > 0 and bounds.intersects(game.get_viewport_rect()): visible_markers += 1
			peak_poison_markers = maxi(peak_poison_markers, visible_markers)
			if visible_markers > 0: poison_frames += 1
		if melee:
			var count: int = game.get_node("World/Effects").get_children().filter(func(node): return node.get_script() == game.player.weapon.STROKE).size()
			peak_melee_traces = maxi(peak_melee_traces, count)
			if count > 0: melee_frames += 1
		if conduction:
			var visible_links := 0
			for effect in game.get_node("World/Effects").get_children():
				if effect.get_script() != game.EFFECT or effect.reaction != "conduction": continue
				var transform: Transform2D = effect.get_global_transform_with_canvas()
				for point in effect.links:
					if Rect2(transform.origin, transform * point - transform.origin).abs().grow(5).intersects(game.get_viewport_rect()): visible_links += 1
			peak_conduction = maxi(peak_conduction, visible_links)
			if visible_links > 0: conduction_frames += 1
	recording = false
	RenderingServer.frame_post_draw.disconnect(render_completed)
	if trace_frames: RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), false)
	var physics_frames := Engine.get_physics_frames() - first_physics_frame
	var process_frames := Engine.get_process_frames() - first_process_frame
	var observer_trace := samples.duplicate() if trace_frames else []
	for member in game.team():
		Input.action_release(member.action("slash"))
	check(game.state == "playing", "Dense battle remains responsive for the whole sample")
	check(game.sound.voices.size() == 12, "Stress retains the bounded audio pool")
	if refits: check(game.team().all(func(member): return member.weapon_mod == "mod_flow" and member.weapon.definition.get("modification") == "mod_flow"), "Both seats retain real refitted attacks throughout stress")
	if melee: check(melee_frames > 450 and peak_melee_traces >= 2, "Native stress renders overlapping melee feedback for both seats")
	if poison: check(poison_frames > 450 and peak_poison_markers >= 6, "Native stress includes repeated frames with visible enemy status markers")
	if conduction: check(conduction_frames > 200 and peak_conduction >= 4, "Native stress includes visible overlapping frost conduction links")
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
	var render_timing := distribution(rendered_samples)
	check(samples.size() == 900, "Stress completes the full 900-observation window")
	check(rendered_samples.size() >= samples.size() - 1, "Render completions cover the full stress observation window")
	check(render_timing.get("p95", INF) <= 25.0 and render_timing.get("p99", INF) <= 50.0, "Rendered frame intervals meet the local 60 Hz acceptance envelope")
	var report := {"rendering_device": RenderingServer.get_video_adapter_name(), "os": OS.get_name(), "engine": Engine.get_version_info().string,
		"cooperative": cooperative, "expanded_map": expanded, "guardian_signatures": guardians, "melee_weapons": melee, "resolution": "%dx%d" % [root.size.x, root.size.y], "screen_scale": DisplayServer.screen_get_scale(), "samples": samples.size(), "frame_ms_p50": p50, "frame_ms_p95": p95, "frame_ms_p99": p99,
		"frame_ms_max": samples[-1], "peak_nodes": peak_nodes, "peak_projectiles": peak_projectiles,
		"peak_melee_traces": peak_melee_traces, "frames_with_melee": melee_frames,
		"poison_feedback": poison, "frames_with_poison": poison_frames, "peak_poison_markers": peak_poison_markers,
		"weapon_refits": refits, "frost_conduction": conduction, "frames_with_conduction": conduction_frames, "peak_conduction_links": peak_conduction,
		"restart_cycles": 40, "orphan_baseline": orphan_baseline, "failures": failures}
	report["timing_basis"] = "frame_ms_* retains physics-then-process wall intervals; rendered_frame_ms uses frame_post_draw callbacks, not OS presentation timestamps"
	report["rendered_frame_ms"] = render_timing
	report["display_context"] = display_context
	report["physics_frames"] = physics_frames
	report["process_frames"] = process_frames
	if trace_frames:
		report["render_cpu_ms"] = distribution(render_cpu_samples)
		report["frame_trace"] = {"physics_then_process_ms": observer_trace,
			"rendered_ms": rendered_samples, "render_cpu_ms": render_cpu_samples}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/qa"))
	var report_name := "performance" + ("-coop" if cooperative else "") + ("-expanded" if expanded else "") + ("-guardians" if guardians else "") + ("-melee" if melee else "") + ("-poison" if poison else "")
	if conduction: report_name += "-conduction"
	if refits: report_name += "-refits"
	# Repeated investigations must not overwrite earlier failures or release evidence.
	report_name += "-%d-%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id()]
	var file := FileAccess.open("res://builds/qa/" + report_name + ".json", FileAccess.WRITE)
	if file == null:
		push_error("Could not write performance report: %s" % FileAccess.get_open_error())
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PERFORMANCE REPORT: res://builds/qa/" + report_name + ".json")
	report.erase("frame_trace")
	print(JSON.stringify(report))
	game.queue_free()
	for i in range(6):
		await frame()
	print("ABYSS PERFORMANCE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
