extends SceneTree
const ENCOUNTER_FIXTURE = preload("res://tests/encounter_fixture.gd")
## Player services: real input dispatch, safe menus and isolated preference recovery.

const SETTINGS = preload("res://scripts/settings.gd")
var failures: Array[String] = []
var checks := 0
var game
var pad_device := 0
var temp_path := "user://test-settings-%d.cfg" % Time.get_ticks_usec()

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count := 2) -> void:
	for i in range(count):
		await physics_frame
	await process_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(code: Key) -> void:
	key(code, true)
	await frames()
	key(code, false)
	await frames()

func pad_tap(code: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = pad_device
		event.button_index = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(1)

func pad_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = pad_device
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)

func controller_devices() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	game.narrative_enabled = false
	root.add_child(game)
	await frames()
	# OS-assigned device IDs need not be zero, including after reconnection.
	# Dispatch real input on two other IDs; don't bypass InputMap with action_press.
	for device in [1, 3]:
		pad_device = device
		game.start_run(441)
		await frames()
		for enemy in get_nodes_in_group("enemies"):
			enemy.set_physics_process(false)
		var origin: Vector2 = game.player.position
		pad_axis(JOY_AXIS_LEFT_X, 1.0)
		await frames(15)
		pad_axis(JOY_AXIS_LEFT_X, 0.0)
		check(game.player.position.x > origin.x + 30.0, "Device %d moves the actual player" % device)
		pad_axis(JOY_AXIS_RIGHT_Y, -1.0)
		await frames()
		check(game.player.aim_mode == "stick" and game.player.aim.dot(Vector2.UP) > 0.99, "Device %d aims with the right stick" % device)
		pad_axis(JOY_AXIS_RIGHT_Y, 0.0)
		for pair in [[JOY_BUTTON_RIGHT_SHOULDER, "slash_cooldown"], [JOY_BUTTON_LEFT_SHOULDER, "bolt_cooldown"],
				[JOY_BUTTON_A, "dash_cooldown"], [JOY_BUTTON_X, "freeze_cooldown"], [JOY_BUTTON_B, "parry_cooldown"]]:
			await pad_tap(pair[0])
			check(game.player.get(pair[1]) > 0.0, "Device %d activates %s" % [device, pair[1]])
		await pad_tap(JOY_BUTTON_START)
		check(game.state == "paused", "Device %d pauses combat" % device)
		# Keep failures bounded if Start didn't work, so confirmation is tested independently.
		if game.state != "paused":
			game.show_menu("paused")
			await frames()
		await pad_tap(JOY_BUTTON_A)
		check(game.state == "playing", "Device %d confirms the focused resume action" % device)
		check(not Input.is_action_pressed("slash") and not Input.is_action_pressed("dash"), "Device %d releases combat buttons" % device)
	game.queue_free()
	await frames(8)
	pad_device = 0

func pad_focus(target: Control) -> bool:
	var start := root.gui_get_focus_owner()
	if not is_instance_valid(start) or not is_instance_valid(target):
		check(false, "Controller navigation requires live initial and target controls")
		return false
	# Find a route through Godot's directional focus graph, then dispatch every
	# step through actual joypad events and verify the resulting focus. No mouse,
	# direct grab_focus, or direct button signals are used to reach the target.
	var queue: Array = [[start, []]]
	var seen := {start.get_instance_id(): true}
	var route: Array = []
	var found := false
	while not queue.is_empty():
		var item: Array = queue.pop_front()
		var control: Control = item[0]
		if control == target:
			route = item[1]
			found = true
			break
		for pair in [[SIDE_LEFT, JOY_BUTTON_DPAD_LEFT], [SIDE_RIGHT, JOY_BUTTON_DPAD_RIGHT], [SIDE_TOP, JOY_BUTTON_DPAD_UP], [SIDE_BOTTOM, JOY_BUTTON_DPAD_DOWN]]:
			# Horizontal slider input changes its value instead of moving focus.
			if control is HSlider and pair[0] in [SIDE_LEFT, SIDE_RIGHT]:
				continue
			var next: Control = control.find_valid_focus_neighbor(pair[0])
			if not is_instance_valid(next) or seen.has(next.get_instance_id()):
				continue
			seen[next.get_instance_id()] = true
			queue.append([next, item[1] + [[pair[1], next]]])
	check(found, "Controller can reach " + str(target.text if target is BaseButton else target.name))
	if not found:
		return false
	for step in route:
		await pad_tap(step[0])
		var matched: bool = root.gui_get_focus_owner() == step[1]
		check(matched, "Dispatched D-pad event reaches its expected focus target")
		if not matched:
			return false
	return true

func pad_activate(caption: String) -> bool:
	for control in game.hud.menu_margin.find_children("*", "BaseButton", true, false):
		if caption in control.text and not control.disabled:
			if not await pad_focus(control):
				return false
			await pad_tap(JOY_BUTTON_A)
			return true
	check(false, "Controller action exists: " + caption)
	return false

func controller_menus() -> void:
	pad_device = 3
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	await frames()
	await pad_activate("武器库")
	check(game.state == "armory", "Controller opens armory from the dock")
	for control in game.hud.menu_margin.find_children("*", "Button", true, false):
		await pad_focus(control)
	await pad_activate(game.WEAPONS.FORMS[-1].name)
	check(game.selected_weapon == game.WEAPONS.FORMS[-1].id, "Controller selects the last weapon in the scrolling catalog")
	await pad_tap(JOY_BUTTON_B)
	check(game.state == "title", "Controller returns from the armory")
	await pad_activate("设置")
	var volume: HSlider = game.hud.menu_margin.find_child("volume", true, false)
	await pad_focus(volume)
	var previous: float = game.settings.values.volume
	await pad_tap(JOY_BUTTON_DPAD_LEFT)
	check(game.settings.values.volume < previous, "Controller adjusts the focused audio slider")
	await pad_activate("键盘按键")
	check(game.settings_tab == "keys", "Controller switches settings tabs")
	for cancel_key in [JOY_BUTTON_B, JOY_BUTTON_START]:
		await pad_activate(SETTINGS.LABELS.slash)
		var old_keys: Dictionary = game.settings.keys.duplicate()
		check(game.rebind_action == "slash", "Controller enters keyboard capture")
		check("等待按键" in root.gui_get_focus_owner().text, "Capture focus remains on the operation being rebound")
		if cancel_key == JOY_BUTTON_B:
			await snapshot("controller-key-capture")
		await pad_tap(JOY_BUTTON_DPAD_DOWN)
		await pad_tap(JOY_BUTTON_A)
		check(game.rebind_action == "slash" and game.state == "settings", "Controller navigation and confirm cannot activate another menu during capture")
		await pad_tap(cancel_key)
		check(game.rebind_action.is_empty() and game.state == "settings", "Controller cancel leaves capture and stays in settings")
		check(game.settings.keys == old_keys, "Controller cancel preserves all keyboard bindings")
		# Recover only after a failed assertion so the rest of the audit can run.
		if not game.rebind_action.is_empty():
			await tap(KEY_ESCAPE)
	await pad_tap(JOY_BUTTON_B)
	check(game.state == "title", "Controller closes settings after capture cancellation")
	await pad_activate("操作指南")
	for control in game.hud.menu_margin.find_children("*", "Label", true, false):
		if control.focus_mode == Control.FOCUS_ALL:
			await pad_focus(control)
	await pad_tap(JOY_BUTTON_B)
	check(game.state == "title", "Controller reads the scrolling guide and returns")
	# Currency is a fixture for purchase navigation, not normal-run balance data.
	game.profile.cores = 1000
	await pad_activate("工作台")
	for control in game.hud.menu_margin.find_children("*", "Button", true, false):
		if not control.disabled:
			await pad_focus(control)
	await pad_activate("强化机体")
	check(game.profile.upgrades.vitality == 1, "Controller buys a permanent upgrade through its focused button")
	await pad_tap(JOY_BUTTON_B)
	check(game.state == "title", "Controller returns from the upgrade workbench")
	await pad_activate("开始救援")
	game.scrap = 1000
	check(game.state == "story", "Controller starts a narrative rescue")
	var guard := 0
	var visited := {}
	while game.state not in ["victory", "dead"] and guard < game.run_length * 5:
		guard += 1
		visited[game.state] = true
		match game.state:
			"playing":
				# Resolve combat fixtures directly: this suite verifies menus only.
				await ENCOUNTER_FIXTURE.clear(game)
				await frames()
			"story", "reward": await pad_tap(JOY_BUTTON_A)
			"route":
				var rest := false
				for destination in game.route_choices:
					if destination.kind == "rest":
						rest = true
				if rest:
					await pad_activate("维修站")
				else:
					await pad_tap(JOY_BUTTON_A)
			"shop":
				for i in range(game.shop_stock.size()):
					if game.can_buy(i):
						await pad_activate(game.shop_stock[i].name)
						check(game.shop_stock[i].id in game.purchased, "Controller purchase survives menu reconstruction")
				await pad_activate("继续救援")
			"rest": await pad_tap(JOY_BUTTON_A)
			_:
				check(false, "Unexpected controller campaign state: " + game.state)
				break
	check(game.state == "victory" and game.room == game.run_length and game.story_seen.size() == 6, "Controller menus reach the complete ending and all six story beats")
	check(visited.has("shop") and visited.has("rest") and visited.has("reward") and visited.has("route"), "Controller route covers supply, recovery and reward menus")
	await pad_activate("武器库")
	await pad_tap(JOY_BUTTON_B)
	check(game.state == "victory", "Armory returns to the ending that opened it")
	await pad_tap(JOY_BUTTON_A)
	check(game.state == "story" and game.room == 1, "Controller starts another run from the ending")
	game.queue_free()
	await frames(8)

func preferences() -> void:
	var settings = SETTINGS.new()
	settings.save_path = temp_path
	settings.values.volume = 0.35
	settings.values.shake = 0.0
	settings.values.flash = 0.0
	settings.values.high_contrast = true
	check(settings.rebind("slash", KEY_F).is_empty(), "Accept a valid unused physical key")
	check(not settings.rebind("dash", KEY_F).is_empty(), "Reject duplicate combat bindings")
	check(not settings.rebind("dash", KEY_ESCAPE).is_empty(), "Escape remains available for menus")
	check(settings.save() == OK, "Persist preferences to an isolated file")
	var loaded = SETTINGS.new()
	loaded.load_settings(temp_path)
	check(is_equal_approx(loaded.values.volume, 0.35) and loaded.values.shake == 0.0 and loaded.values.flash == 0.0, "Audio and motion preferences survive a fresh instance")
	check(loaded.keys.slash == KEY_F, "Physical binding survives restart")
	check(loaded.values.high_contrast, "Text contrast preference survives a fresh settings instance")
	loaded.values.volume = 0.6
	check(loaded.save() == OK, "A second save retains a valid previous generation")
	var broken := ConfigFile.new()
	broken.set_value("incomplete", "write", true)
	broken.save(temp_path)
	var recovered = SETTINGS.new()
	recovered.load_settings(temp_path)
	check(recovered.writable and is_equal_approx(recovered.values.volume, 0.35), "Corrupt primary recovers settings from backup")
	check(recovered.save() == OK, "Recovered settings can be saved")
	var backup := ConfigFile.new()
	check(backup.load(temp_path + ".bak") == OK and backup.get_value("settings", "volume") == 0.35, "Recovery never copies corrupt bytes over the valid backup")
	var future := ConfigFile.new()
	future.set_value("settings", "version", 999)
	future.save(temp_path)
	var future_bytes := FileAccess.get_file_as_bytes(temp_path)
	var future_settings = SETTINGS.new()
	future_settings.load_settings(temp_path)
	check(not future_settings.writable and future_settings.save() == ERR_UNAUTHORIZED, "Unknown future schemas are read-only")
	check(FileAccess.get_file_as_bytes(temp_path) == future_bytes, "Future settings bytes are preserved")
	future.set_value("settings", "version", 1)
	future.set_value("settings", "volume", INF)
	future.set_value("settings", "shake", -9)
	future.set_value("settings", "fullscreen", "not a bool")
	future.set_value("keys", "slash", KEY_W)
	future.save(temp_path)
	var hostile = SETTINGS.new()
	hostile.load_settings(temp_path)
	check(hostile.values.volume == SETTINGS.DEFAULTS.volume and hostile.values.shake == 0.0, "Nonfinite values are rejected; numeric values are bounded")
	check(hostile.values.fullscreen == false and hostile.keys == SETTINGS.KEYS, "Invalid booleans and conflicting maps fall back safely")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(temp_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path + suffix))

func inspect_menu(context: String) -> void:
	var focus := root.gui_get_focus_owner()
	check(is_instance_valid(focus) and focus.is_visible_in_tree(), context + " has a visible focus target")
	for node in game.hud.menu_margin.get_children():
		check(node.get_minimum_size().x <= 1260 and node.get_minimum_size().y <= 720, context + " fits the reference viewport")

func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var directory := "res://builds/qa"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var ignore := FileAccess.open("res://builds/.gdignore", FileAccess.WRITE)
	ignore.close()
	root.get_texture().get_image().save_png(directory + "/" + name + ".png")

func run() -> void:
	preferences()
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	# Automation can lose macOS focus when tool output is shown. Test focus loss
	# explicitly below, independently of foreground changes outside this window.
	game.auto_pause_enabled = false
	root.add_child(game)
	await frames()
	inspect_menu("title")
	await snapshot("title")
	game.open_settings()
	await frames()
	inspect_menu("settings")
	await snapshot("settings")
	game.set_setting("volume", 0.25)
	game.set_setting("effects_volume", 0.4)
	check(is_equal_approx(game.sound.gain, 0.1), "Audio sliders affect the actual voice output")
	await tap(KEY_M)
	check(game.muted and game.sound.gain == 0.0 and (DisplayServer.get_name() == "headless" or game.sound.ambience.stream_paused), "Mute silences voices and ambience")
	await tap(KEY_M)
	check(not game.muted and is_equal_approx(game.sound.gain, 0.1), "Unmute restores configured output levels")
	game.choose_settings_tab("keys")
	await frames()
	inspect_menu("key bindings")
	game.begin_rebind("slash")
	await tap(KEY_F)
	check(game.settings.keys.slash == KEY_F and game.rebind_action.is_empty(), "UI captures a physical key and commits a binding")
	game.using_gamepad = false
	check(game.action_label("slash") == "F", "HUD shortcut labels reflect the active keyboard binding")
	game.begin_rebind("dash")
	await tap(KEY_F)
	check(not game.rebind_action.is_empty() and game.settings.keys.dash == KEY_SPACE, "UI keeps listening after a binding conflict")
	await tap(KEY_ESCAPE)
	check(game.state == "settings" and game.rebind_action.is_empty(), "Escape cancels rebinding without closing settings")
	await tap(KEY_ESCAPE)
	check(game.state == "title", "Settings returns to its exact entry menu")
	game.open_help()
	await frames()
	inspect_menu("guide")
	await snapshot("guide")
	game.set_setting("high_contrast", true)
	var guide_heading = game.hud.menu_margin.find_children("*", "Label", true, false)[0]
	check(guide_heading.get_theme_constant("outline_size") == 2, "High contrast updates the current menu immediately")
	await snapshot("guide-high-contrast")
	game.set_setting("high_contrast", false)
	check(guide_heading.get_theme_constant("outline_size") == 0, "Disabling high contrast restores the original text style")
	await tap(KEY_ESCAPE)
	game.start_run(441)
	await frames()
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	await tap(KEY_ESCAPE)
	check(game.state == "paused", "Physical Escape pauses combat")
	game.open_settings()
	await frames()
	check(not game.player.can_process(), "Settings opened from pause keep the world stopped")
	await tap(KEY_ESCAPE)
	check(game.state == "paused", "Closing pause settings does not resume combat unexpectedly")
	game.request_new_run()
	await frames()
	check(game.state == "confirm" and game.room == 1, "Restart requires an explicit in-game confirmation")
	inspect_menu("confirmation")
	await tap(KEY_ESCAPE)
	check(game.state == "paused", "Cancelling restart preserves the paused run")
	game.request_quit()
	game.request_quit()
	game.cancel_confirmation()
	check(game.state == "paused", "Repeated native close requests retain the original return state")
	game.resume_run()
	await frames()
	var first: Vector2 = game.player.position
	key(KEY_D, true)
	await frames(15)
	key(KEY_D, false)
	check(game.player.position.x > first.x + 30.0, "Physical key dispatch moves the actual player")
	key(KEY_F, true)
	await frames()
	key(KEY_F, false)
	check(game.player.slash_cooldown > 0, "Rebound primary key attacks in real gameplay")
	game.show_menu("paused")
	await frames()
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	Input.parse_input_event(pad)
	await frames()
	check(game.player.dash_left == 0.0, "Confirming resume does not also dash")
	pad.pressed = false
	Input.parse_input_event(pad)
	await frames()
	check(game.state == "playing" and game.using_gamepad, "Controller confirmation activates focused resume")
	pad.pressed = true
	Input.parse_input_event(pad)
	await frames()
	check(game.player.dash_cooldown > 0, "A fresh controller press activates dash after resume")
	pad.pressed = false
	Input.parse_input_event(pad)
	await frames()
	game.controller_changed(0, false)
	check(game.state == "paused", "Disconnecting the active controller pauses combat")
	game.resume_run()
	game.auto_pause_enabled = true
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.state == "paused", "Application focus loss pauses combat")
	game.auto_pause_enabled = false
	game.reset_controls()
	# reset_controls refreshes the settings UI only; restore the appropriate menu.
	game.show_menu("paused")
	game.set_setting("shake", 0.0)
	game.set_setting("flash", 0.0)
	game.resume_run()
	game.shake = 9.0
	game.player.invulnerable = 1.0
	await frames()
	check(game.camera.offset == Vector2.ZERO and game.player.get_node("Sprite").modulate == Color.WHITE, "Motion and flash options affect rendered gameplay")
	await snapshot("combat")
	var voices: int = game.sound.get_child_count()
	var cue = game.sound.cue(650.0, 0.07)
	check(cue == game.sound.cue(650.0, 0.07), "Repeated sound requests reuse cached PCM")
	for i in range(200):
		game.play_tone(650.0, 0.07, 0.05)
	check(game.sound.get_child_count() == voices, "Dense combat cannot grow the voice node pool")
	game.show_menu("paused")
	game.abandon_to_title()
	await frames()
	check(game.state == "title" and game.player == null and not game.profile.checkpoint.is_empty(), "Returning to the dock keeps a resumable checkpoint")
	inspect_menu("saved rescue title")
	await snapshot("continue-title")
	for dimensions in [Vector2i(960, 600), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		root.size = dimensions
		await frames()
		inspect_menu("saved rescue title at " + str(dimensions))
		if dimensions == Vector2i(960, 600):
			await snapshot("continue-title-small")
	if DisplayServer.get_name() != "headless":
		game.fit_window_to_screen()
		await frames()
		var usable := DisplayServer.screen_get_usable_rect()
		var actual := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
		check(usable.encloses(actual), "Default window fits the current Mac usable desktop")
		var scale := maxf(1.0, DisplayServer.screen_get_scale())
		if Vector2(usable.size).x / scale >= 1100 and Vector2(usable.size).y / scale >= 750:
			check(actual.size.x / scale >= 960, "Retina default is at least 960 desktop points wide, not a half-size physical-pixel window")
		await snapshot("title-default-desktop")
	root.size = Vector2i(1280, 800)
	check(game.continue_saved_run() and game.state == "paused", "Dock continuation rebuilds the active room safely")
	check(not game.continue_saved_run(), "Repeated continue cannot create another player")
	await frames()
	game.queue_free()
	await frames(8)
	await controller_devices()
	await controller_menus()
	print("ABYSS PRODUCTION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
