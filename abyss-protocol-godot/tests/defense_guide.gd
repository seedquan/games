extends SceneTree
## Exercise the guide through actual menus and controller events, with saves off.
var game
var checks := 0
var failures := 0
var rendered := DisplayServer.get_name() != "headless"

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frames(count := 3) -> void:
	for i in range(count): await physics_frame
	await process_frame

func confirm() -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 3
		event.button_index = JOY_BUTTON_A
		event.pressed = down
		Input.parse_input_event(event)
		await frames(1)

func finish() -> void:
	game.queue_free()
	await create_timer(0.25).timeout
	print("ABYSS DEFENSE GUIDE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func profile(demo, playback) -> void:
	playback.grab_focus()
	await confirm()
	await frames(12)
	var samples: Array[float] = []
	var active := 0
	var previous := Time.get_ticks_usec()
	for i in range(240):
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - previous) / 1000.0)
		previous = now
		if demo.is_processing(): active += 1
	samples.sort()
	check(active >= 200, "Performance sample contains active vector animation")
	check(samples[228] <= 25 and samples[237] <= 50, "Guide stays within the local 60 Hz frame envelope")
	var report := {"frames": 240, "active": active, "resolution": str(root.size), "p50_ms": samples[120], "p95_ms": samples[228], "p99_ms": samples[237], "max_ms": samples[-1]}
	FileAccess.open("res://builds/qa/defense-guide-performance.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("DEFENSE PERFORMANCE: " + JSON.stringify(report))
	demo._process(demo.DURATION)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	game.start_run(919)
	game.show_menu("paused")
	game.open_help()
	await frames()
	var demo = game.hud.menu_margin.find_child("DefenseDemo", true, false)
	var playback = game.hud.menu_margin.find_child("DefensePlayback", true, false)
	var instruction = game.hud.menu_margin.find_child("DefenseInstruction", true, false)
	check(is_instance_valid(demo) and is_instance_valid(playback) and is_instance_valid(instruction), "Guide offers an illustrated parry demonstration")
	if not is_instance_valid(demo):
		await finish()
		return
	check(not demo.is_processing(), "Guide starts as a readable static diagram")
	var before := [game.elapsed, game.player.hp, game.player.energy, game.scrap, game.profile.cores, game.rng.state]
	playback.grab_focus()
	await confirm()
	print("DEFENSE PLAYBACK START: processing=%s elapsed=%.6f" % [demo.is_processing(), demo.elapsed])
	await frames(3)
	check(demo.is_processing() and demo.elapsed > 0, "Controller starts the visual demonstration")
	check(instruction.text.contains(game.action_label("parry")), "Instruction follows the active controller binding")
	await confirm()
	var moment: float = demo.elapsed
	await frames(6)
	check(demo.paused and demo.elapsed == moment, "Controller pause freezes the illustration")
	await confirm()
	check(not demo.paused and demo.is_processing(), "Controller resumes the same illustration")
	seed(918)
	var expected := randi()
	seed(918)
	demo._process(demo.DURATION)
	check(randi() == expected, "Demonstration does not consume combat random numbers")
	check(not demo.is_processing() and playback.text == "重播演示", "Finite animation ends and offers replay")
	check(before == [game.elapsed, game.player.hp, game.player.energy, game.scrap, game.profile.cores, game.rng.state], "Guide preserves paused combat and progression")
	game.using_gamepad = false
	game.settings.keys.parry = KEY_K
	game.hud.update_status()
	check(instruction.text.contains("K"), "Guide follows a rebound keyboard parry key")
	for dimensions in [Vector2i(960, 600), Vector2i(2560, 1440)]:
		root.size = dimensions
		await frames()
		var bounds: Rect2 = game.get_viewport_rect().grow(1)
		for control in [demo, playback, instruction]:
			check(bounds.encloses(control.get_global_rect()), "First-screen illustration and playback fit " + str(dimensions))
		check(instruction.get_line_count() <= 2, "Instruction stays compact")
		if rendered:
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://builds/qa")
			check(root.get_texture().get_image().save_png("res://builds/qa/defense-guide-%d.png" % dimensions.x) == OK, "Save static guide evidence")
	if rendered:
		for phase in [2.45, 3.0]:
			demo.elapsed = phase
			demo.paused = true
			demo.queue_redraw()
			await frames()
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://builds/qa/defense-guide-phase-%d.png" % int(phase * 100)) == OK, "Save contact and return illustrations")
		demo.elapsed = demo.DURATION
		demo.paused = false
		demo.queue_redraw()
	if rendered and "--profile" in OS.get_cmdline_user_args():
		await profile(demo, playback)
	await confirm()
	demo.auto_pause_enabled = true
	demo.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(demo.paused and not demo.is_processing(), "Desktop focus loss pauses the diagram")
	demo.toggle_playback()
	demo.hide()
	check(not demo.is_processing(), "Hidden guide stops visual processing")
	game.show_menu("paused")
	await frames()
	check(not is_instance_valid(demo), "Leaving guide releases its visual node")
	game.settings.values.story_motion = false
	game.open_help()
	await frames()
	demo = game.hud.menu_margin.find_child("DefenseDemo", true, false)
	playback = game.hud.menu_margin.find_child("DefensePlayback", true, false)
	check(not demo.is_processing() and not playback.visible, "Reduced motion retains static diagram without playback")
	demo.toggle_playback()
	check(not demo.is_processing(), "Reduced motion cannot accidentally start playback")
	game.show_menu("paused")
	game.campaign_version = 1
	game.open_help()
	await frames()
	check(game.hud.menu_margin.find_child("DefenseDemo", true, false) == null, "Legacy guide does not advertise unavailable reflected shots")
	await finish()
