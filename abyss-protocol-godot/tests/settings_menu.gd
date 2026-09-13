extends "res://tests/production.gd"
## Exercise settings through real pointer and nonzero-device controller events.

func click(control: Control) -> void:
	check(is_instance_valid(control), "Pointer target exists")
	if not is_instance_valid(control): return
	var point := control.get_global_rect().get_center()
	menu_pointer(point)
	menu_mouse(point, true)
	await frames(1)
	menu_mouse(point, false)
	await frames()

func named(caption: String) -> Button:
	for node in game.hud.menu_buttons():
		if node.text == caption: return node
	return null

func inspect_settings(context: String) -> void:
	menu_pointer(Vector2(-100, -100))
	await frames()
	inspect_menu(context)
	var bounds: Rect2 = game.hud.menu_margin.get_global_rect()
	for control in game.hud.menu_buttons():
		check(bounds.encloses(control.get_global_rect()), context + " contains " + control.text)
		inspect_button_contrast(control, BaseButton.DRAW_NORMAL, context + " " + control.text)

func run() -> void:
	root.size = Vector2i(1280, 800)
	pad_device = 3
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	await frames()
	var full := named("全屏")
	await click(full)
	check(game.settings.values.fullscreen and full.text == "退出全屏", "Title pointer enables fullscreen and updates label")
	if DisplayServer.get_name() != "headless":
		await create_timer(1.5).timeout
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Title action enters OS fullscreen")
	await tap(KEY_F11)
	check(not game.settings.values.fullscreen and full.text == "全屏", "F11 updates title action")
	if DisplayServer.get_name() != "headless":
		await create_timer(1.5).timeout
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "F11 restores OS window")
	await pad_activate("设置")
	for tab in [["display", "画面与舒适度"], ["audio", "声音"], ["keys", "键盘按键"], ["controller", "手柄与辅助"]]:
		await pad_activate(tab[1])
		check(game.settings_tab == tab[0], "Controller selects " + tab[0])
		await inspect_settings(tab[0])
		await snapshot("settings-" + tab[0])
		# Every action must be reachable through actual directional input.
		for control in game.hud.menu_buttons():
			await pad_focus(control)
	await pad_activate("声音")
	var volume: HSlider = game.hud.menu_margin.find_child("volume", true, false)
	await pad_focus(volume)
	for i in range(20): await pad_tap(JOY_BUTTON_DPAD_LEFT)
	check(game.settings.values.volume == 0 and game.sound.gain == 0, "Controller can silence actual sound output")
	for i in range(20): await pad_tap(JOY_BUTTON_DPAD_RIGHT)
	check(game.settings.values.volume == 1, "Controller can reach maximum output")
	await click(named("试听战斗提示音"))
	await tap(KEY_M)
	check(game.sound.gain == 0 and "已静音" in game.hud.settings_view.preview_caption.text, "Mute refreshes output explanation")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(game.hud.settings_view.preview.channel_levels == [0.0, 0.0, 0.0], "Muted illustration matches actual output")
	await tap(KEY_M)
	await pad_activate("画面与舒适度")
	var contrast: Button = game.hud.menu_margin.find_child("high_contrast", true, false)
	await click(contrast)
	check(game.settings.values.high_contrast and contrast.text == "已开启", "Pointer toggle applies contrast immediately")
	await inspect_settings("high contrast")
	var motion: Button = game.hud.menu_margin.find_child("story_motion", true, false)
	await pad_focus(motion)
	await pad_tap(JOY_BUTTON_A)
	check(not game.settings.values.story_motion and motion.text == "已关闭", "Controller selects static narrative illustrations")
	# Save only preferences in a unique fixture; never enable profile persistence.
	game.settings.save_path = temp_path
	check(game.settings.save() == OK, "Save edited preferences in isolated fixture")
	var reloaded = SETTINGS.new()
	reloaded.load_settings(temp_path)
	check(reloaded.values == game.settings.values, "Cold settings instance preserves all UI edits")
	await pad_tap(JOY_BUTTON_B)
	check(game.state == "title" and root.gui_get_focus_owner().text == "设置", "Return restores exact entry focus")
	game.start_run(998)
	await frames()
	await tap(KEY_ESCAPE)
	await click(named("全屏"))
	check(game.state == "paused" and game.settings.values.fullscreen, "Pause fullscreen action preserves pause")
	await tap(KEY_F11)
	await pad_activate("设置")
	var before := var_to_bytes([game.elapsed, game.rng.state, game.player.position, game.player.hp, game.player.energy, game.scrap, game.profile.checkpoint])
	game.set_setting("shake", 0.0)
	game.set_setting("flash", 0.0)
	await click(named("预览震动与闪光"))
	await frames(20)
	check(game.hud.settings_view.preview.preview_offset == Vector2.ZERO and game.hud.settings_view.preview.preview_flash == 0, "Zero intensity suppresses preview effects")
	game.set_setting("shake", 1.0)
	game.set_setting("flash", 1.0)
	await click(named("预览震动与闪光"))
	await frames(28)
	if DisplayServer.get_name() != "headless":
		check(game.hud.settings_view.preview.preview_offset.length() > 0 and game.hud.settings_view.preview.preview_flash > 0, "Nonzero preview visibly demonstrates effects")
	await frames(60)
	check(before == var_to_bytes([game.elapsed, game.rng.state, game.player.position, game.player.hp, game.player.energy, game.scrap, game.profile.checkpoint]), "Previews cannot advance combat, alter RNG, heal, spend or save run")
	for dimensions in [Vector2i(960, 600), Vector2i(1280, 800), Vector2i(2560, 1440)]:
		root.size = dimensions
		await frames(4)
		for tab in ["display", "audio", "keys", "controller"]:
			game.choose_settings_tab(tab)
			await frames()
			await inspect_settings("%s %s" % [dimensions, tab])
		await snapshot("settings-size-%d" % dimensions.x)
	await pad_tap(JOY_BUTTON_B)
	check(game.state == "paused" and not game.world.can_process(), "Settings exit requires deliberate combat resume")
	game.coop.enabled = true
	game.coop.devices.assign([3, 7])
	game.start_run(999)
	game.show_menu("paused")
	game.open_settings()
	await frames()
	var pilot_focus := root.gui_get_focus_owner()
	pad_device = 7
	await pad_tap(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == pilot_focus, "Partner cannot steal shared settings focus")
	game.coop.disconnected(7)
	check(game.state == "coop_lobby", "Disconnect while configuring pauses for pairing")
	pad_device = 8
	await pad_tap(JOY_BUTTON_A)
	pad_device = 3
	await pad_tap(JOY_BUTTON_START)
	check(game.state == "settings" and not game.world.can_process(), "Pairing restores settings without advancing combat")
	await pad_tap(JOY_BUTTON_B)
	check(game.state == "paused", "Reconnected settings returns to pause")
	game.queue_free()
	await frames(15)
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(temp_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path + suffix))
	print("ABYSS SETTINGS MENU: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
