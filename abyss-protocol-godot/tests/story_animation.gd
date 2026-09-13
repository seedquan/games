extends SceneTree
var game
var checks := 0
var failures := 0
var rendered := DisplayServer.get_name() != "headless"

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func frames(count := 3) -> void:
	for i in range(count): await physics_frame
	await process_frame

func confirm() -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 3
		event.button_index = JOY_BUTTON_A
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(1)

func open_scene(id: String) -> void:
	game.story_seen.erase(id)
	game.show_story(id, "playing")
	await frames()

func snapshot(id: String, moment: float) -> void:
	var scene = game.hud.story_scene
	scene.paused = true
	scene.set_process(false)
	scene.elapsed = moment
	scene.queue_redraw()
	scene.playback_changed.emit()
	await frames()
	if rendered:
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://builds/qa")
		check(root.get_texture().get_image().save_png("res://builds/qa/story-%s-%d.png" % [id, int(moment)]) == OK, "Save illustrated story frame")

func profile() -> void:
	await open_scene("ending")
	await frames(30)
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	var active_frames := 0
	for i in range(360):
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - previous) / 1000.0)
		previous = now
		if game.hud.story_scene.is_processing(): active_frames += 1
	samples.sort()
	var p95: float = samples[int(samples.size() * 0.95)]
	var p99: float = samples[int(samples.size() * 0.99)]
	check(active_frames >= 300, "Performance sample includes active SVG animation")
	check(p95 <= 25 and p99 <= 50, "Narrative animation meets the local 60 Hz frame envelope")
	var report := {"samples": samples.size(), "active_frames": active_frames, "resolution": str(root.size), "p50_ms": samples[180], "p95_ms": p95, "p99_ms": p99, "max_ms": samples[-1]}
	var file := FileAccess.open("res://builds/qa/story-performance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("STORY PERFORMANCE: " + JSON.stringify(report))

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	await frames()
	game.start_run(812)
	for id in ["awakening", "calibration", "ending"]:
		await open_scene(id)
		var scene = game.hud.story_scene
		var playback: Button = game.hud.menu_margin.find_child("StoryPlayback", true, false)
		var proceed: Button = game.hud.menu_margin.find_child("StoryContinue", true, false)
		check(root.gui_get_focus_owner() == proceed and not proceed.disabled, "Continue is immediately available in " + id)
		var before: float = game.elapsed
		await frames(5)
		check(game.elapsed == before and not game.world.can_process() and scene.elapsed > 0, "Animation advances while combat stays paused")
		playback.grab_focus()
		await confirm()
		var frozen: float = scene.elapsed
		await frames(5)
		check(scene.paused and scene.elapsed == frozen, "Nonzero controller pauses animation")
		await confirm()
		await frames(4)
		check(not scene.paused and scene.elapsed > frozen, "Nonzero controller resumes animation")
		scene._process(scene.DURATION)
		check(not scene.is_processing() and playback.text == "重播", "Finite animation stops and offers replay")
		await confirm()
		check(scene.elapsed < 1 and scene.is_processing(), "Replay starts only the visual timeline")
		for dimensions in [Vector2i(960, 600), Vector2i(2560, 1440)]:
			root.size = dimensions
			await frames()
			var bounds: Rect2 = game.get_viewport_rect().grow(1)
			for control in [scene, playback, proceed]:
				check(bounds.encloses(control.get_global_rect()), "Story controls fit " + str(dimensions))
		await snapshot(id, 0)
		await snapshot(id, 4)
		await snapshot(id, 7)
		proceed.grab_focus()
		await confirm()
		check(game.state == "playing" and game.world.can_process(), "Controller skips directly back to the original destination")
		check(not scene.is_processing(), "Hidden story animation stops processing")
		game.show_menu("paused")
		await frames()
		check(not is_instance_valid(scene), "Next menu releases the old animation node")
	game.settings.values.story_motion = false
	await open_scene("awakening")
	var still = game.hud.story_scene
	check(still.elapsed == still.DURATION and not still.is_processing(), "Reduced motion uses the final static illustration")
	check(not game.hud.menu_margin.find_child("StoryPlayback", true, false).visible, "Static mode has no inactive playback control")
	var settings_path := "res://builds/qa/story-settings-%d.cfg" % Time.get_ticks_usec()
	game.settings.save_path = settings_path
	check(game.settings.save() == OK, "Save isolated motion preference")
	var reloaded = game.SETTINGS.new()
	reloaded.load_settings(settings_path)
	check(not reloaded.values.story_motion, "Motion preference survives cold load")
	game.settings.values.story_motion = true
	await open_scene("calibration")
	game.hud.story_scene.auto_pause_enabled = true
	game.hud.story_scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.hud.story_scene.paused and not game.hud.story_scene.is_processing(), "Losing desktop focus pauses the cutscene")
	if rendered and "--profile" in OS.get_cmdline_user_args():
		await profile()
	game.queue_free()
	await create_timer(0.2).timeout
	print("ABYSS STORY ANIMATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
