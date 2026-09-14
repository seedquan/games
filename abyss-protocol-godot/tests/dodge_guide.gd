extends "res://tests/production.gd"
## Real menu input, readable timing, and a purely illustrative paused world.

func finish_dodge() -> void:
	game.queue_free()
	await create_timer(0.25).timeout
	print("ABYSS DODGE GUIDE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func capture_dodge(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var path := "res://builds/qa/dodge-guide-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	await frames()
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(path.path_join(name + ".png")) == OK, "Capture native timing illustration")

func run() -> void:
	pad_device = 3
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	game.start_run(1031)
	game.show_menu("paused")
	game.open_help()
	await frames()
	var demo = game.hud.menu_margin.find_child("DefenseDemo", true, false)
	var dodge = game.hud.menu_margin.find_child("DodgeMode", true, false)
	check(is_instance_valid(dodge), "Defense guide offers a distinct dodge timing mode")
	if not is_instance_valid(dodge):
		await finish_dodge()
		return
	var playback = game.hud.menu_margin.find_child("DefensePlayback", true, false)
	var instruction = game.hud.menu_margin.find_child("DefenseInstruction", true, false)
	var before := var_to_bytes([game.elapsed, game.player.position, game.player.hp, game.player.energy, game.scrap, game.profile.cores, game.rng.state])
	await pad_activate("冲刺避爆")
	check(not demo.is_processing() and "冲刺" in instruction.text, "Choosing dodge mode shows a static explanation first")
	check(game.action_label("dash") in instruction.text, "Static dodge instruction uses the active controller binding")
	await pad_activate("播放演示")
	await frames(5)
	check(demo.is_processing() and "预告" in instruction.text, "Playback first explains the boss preparation cue")
	await confirm_playback()
	var stopped: float = demo.elapsed
	await frames(6)
	check(demo.paused and demo.elapsed == stopped, "Real controller input pauses the timing animation")
	await confirm_playback()
	check(not demo.paused and demo.is_processing(), "Real controller input resumes the same timing")
	# Inspect the drawn phases at readable slow-motion positions.
	for phase in [1.0, 2.4, 3.18, 3.5]:
		demo.elapsed = phase
		demo.paused = true
		demo.queue_redraw()
		game.hud.refresh_defense_demo()
		await capture_dodge("phase-%d" % int(phase * 100))
	check("爆发" in instruction.text, "Late phase identifies the actual blast rather than the preparation cue")
	demo.paused = false
	demo._process(demo.DURATION)
	check(not demo.is_processing() and playback.text == "重播演示", "Finite dodge illustration ends with replay available")
	game.using_gamepad = false
	game.settings.keys.dash = KEY_K
	game.hud.update_status()
	check("K" in instruction.text, "Dodge explanation follows a rebound keyboard key")
	for dimensions in [Vector2i(960, 600), Vector2i(2560, 1440)]:
		root.size = dimensions
		await frames()
		await pad_focus(playback)
		await frames()
		var bounds: Rect2 = game.get_viewport_rect().grow(1)
		for control in [demo, dodge, playback, instruction]:
			check(bounds.encloses(control.get_global_rect()), "Timing controls fit viewport " + str(dimensions))
		check(instruction.get_line_count() <= 2, "Timing instruction stays compact")
		await capture_dodge("static-%d" % dimensions.x)
	await pad_activate("弹反返弹")
	check(not demo.is_processing() and "弹反" in instruction.text, "Switching modes restores the readable parry diagram")
	check(before == var_to_bytes([game.elapsed, game.player.position, game.player.hp, game.player.energy, game.scrap, game.profile.cores, game.rng.state]), "Both illustrations leave combat and progression unchanged")
	game.show_menu("paused")
	game.settings.values.story_motion = false
	game.open_help()
	await frames()
	await pad_activate("冲刺避爆")
	demo = game.hud.menu_margin.find_child("DefenseDemo", true, false)
	playback = game.hud.menu_margin.find_child("DefensePlayback", true, false)
	check(not demo.is_processing() and not playback.visible, "Reduced motion keeps the dodge diagram but hides playback")
	demo.toggle_playback()
	check(not demo.is_processing(), "Reduced motion cannot accidentally start the animation")
	await finish_dodge()

func confirm_playback() -> void:
	await pad_tap(JOY_BUTTON_A)
