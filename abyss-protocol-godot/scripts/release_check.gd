extends Node
## Opt-in, save-free verification for the actual release template, which ignores --script.

var game
var failures := 0
var checks := 0
var started_ms := 0

func _ready() -> void:
	started_ms = Time.get_ticks_msec()
	run.call_deferred()

func _process(_delta: float) -> void:
	# Wall time keeps accelerated state verification within the export timeout.
	if Time.get_ticks_msec() - started_ms > 55000:
		push_error("Release verification timed out")
		get_tree().quit(1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("Release verification: " + message)

func frame() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame

func snapshot(name: String) -> void:
	# The game already validated this disposable fixture before enabling storage.
	if DisplayServer.get_name() == "headless" or game.verification_directory.is_empty():
		return
	await frame()
	await RenderingServer.frame_post_draw
	var path: String = game.verification_directory.path_join(name + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "save rendered evidence " + name)

func run() -> void:
	if not game.verification_directory.is_empty():
		await storage_roundtrip()
		return
	check(game.state == "title", "boot title")
	check(not game.persistence_enabled, "verification cannot touch the player's saves")
	game.open_settings()
	await frame()
	check(game.state == "settings", "settings resources")
	game.close_settings()
	game.open_armory()
	check(game.WEAPONS.FORMS.size() == 18, "weapon catalog")
	game.armory_back()
	game.start_run(5819)
	await frame()
	check(game.state == "story" and game.story_id == "awakening", "opening story")
	check(is_instance_valid(game.hud.story_scene) and game.hud.story_scene.STATION.get_width() == 640 and game.hud.story_scene.PUMP.get_height() == 720, "packed narrative SVG layers")
	game.continue_story()
	game.open_build()
	await frame()
	check(game.state == "build" and not game.world.can_process(), "packed build overview freezes combat")
	check("26.0" in game.BUILD_INFO.attack_text(game.player.weapon.definition, game.player.damage), "packed overview reads current weapon")
	game.close_build()
	check(game.state == "paused", "packed overview closes safely")
	game.resume_run()
	var start: Vector2 = game.player.position
	var stick := InputEventJoypadMotion.new()
	stick.device = 3
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	Input.parse_input_event(stick)
	for i in range(12):
		await frame()
	stick.axis_value = 0.0
	Input.parse_input_event(stick)
	check(game.player.position.x > start.x + 20, "nonzero controller device moves through the packed InputMap")
	for button in [JOY_BUTTON_START, JOY_BUTTON_A]:
		for pressed in [true, false]:
			var event := InputEventJoypadButton.new()
			event.device = 3
			event.button_index = button
			event.pressed = pressed
			Input.parse_input_event(event)
			await frame()
		check(game.state == ("paused" if button == JOY_BUTTON_START else "playing"), "nonzero controller pauses and confirms resume")
	game.player.set_physics_process(false)
	# Exercise every packed weapon family against real enemy bodies.
	for form in game.WEAPONS.FORMS:
		game.player.weapon.equip(form.id)
		game.player.slash_cooldown = 0
		check(game.player.weapon.fire(1.0 if form.has("charge") else -1.0), "attack " + form.id)
		await frame()
	await complete_campaign()
	check(game.state == "victory" and game.room == game.run_length, "complete all campaign chambers and ending")
	check(game.story_seen.size() == 6, "all story assets")
	check(game.profile.checkpoint.is_empty(), "completed run invalidates checkpoint")
	game.start_run(5820)
	game.continue_story()
	game.player.invulnerable = 0
	game.player.take_damage(1000000.0, Vector2.ZERO)
	await frame()
	check(game.state == "dead", "failure screen")
	await cooperative_release()
	print("ABYSS RELEASE: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	# Audio playback references are retired by the mixer after nodes are freed.
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if failures == 0 else 1)

func clear_encounter() -> void:
	# State verification applies damage directly, but the packaged encounter must
	# schedule and finish every real warning. Never bypass or erase queued waves.
	var previous_speed := Engine.time_scale
	Engine.time_scale = 32.0
	var deadline := Time.get_ticks_msec() + 10000
	while game.state == "playing" and Time.get_ticks_msec() < deadline:
		for member in game.team():
			member.set_physics_process(false)
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.take_damage(1000000.0, Vector2.ZERO)
		await frame()
	Engine.time_scale = previous_speed
	check(game.state != "playing", "all reinforcement waves finish before the chamber reward")

func advance_campaign() -> void:
	match game.state:
		"story": game.continue_story()
		"playing": await clear_encounter()
		"reward": game.choose_boon(0)
		"route": game.choose_route(0)
		"shop", "rest": game.leave_supply()
	await frame()

func complete_campaign() -> void:
	var steps := 0
	while game.state not in ["victory", "dead"] and steps < game.run_length * 6:
		steps += 1
		await advance_campaign()

func storage_roundtrip() -> void:
	var directory: String = game.verification_directory
	check(game.persistence_enabled, "storage verification uses real persistence")
	check(game.profile.save_path == directory.path_join("profile.cfg") and game.settings.save_path == directory.path_join("settings.cfg"), "all player data is isolated in the fixture")
	check(game.save_warning.is_empty() and game.settings_notice.is_empty(), "cold-start files load without recovery warnings")
	await snapshot("title-" + game.verification_stage)
	var expected := ConfigFile.new()
	var expectation := directory.path_join("expected.cfg")
	if game.verification_stage == "write":
		check(game.profile.runs == 0 and game.profile.cores == 0 and game.profile.checkpoint.is_empty(), "fresh installation has no progress")
		game.open_armory()
		check(game.select_weapon("rail"), "loadout selection persists through normal UI action")
		game.armory_back()
		game.set_setting("volume", 0.35)
		game.set_setting("shake", 0.0)
		game.set_setting("story_motion", false)
		check(game.settings.rebind("slash", KEY_F).is_empty(), "persist a non-default input binding")
		game.save_settings()
		game.configure_input()
		game.start_run(71831)
		var guard := 0
		while not (game.room == 3 and game.state == "shop") and guard < game.run_length * 6:
			guard += 1
			await advance_campaign()
		check(game.room == 3 and game.state == "shop", "reach a checkpoint with real rewards and shop state")
		check(game.buy_item(1), "shop tuning transaction is committed")
		await snapshot("shop-write")
		for item in [["cores", game.profile.cores], ["runs", game.profile.runs], ["scrap", game.scrap], ["damage", game.player.damage], ["hp", game.player.hp], ["purchased", game.purchased], ["history", game.route_history]]:
			expected.set_value("expected", item[0], item[1])
		check(expected.save(expectation) == OK, "write an independent cross-process oracle")
		check(FileAccess.file_exists(game.profile.save_path) and FileAccess.file_exists(game.settings.save_path), "both persisted files exist before process exit")
		check(game.save_warning.is_empty(), "checkpoint save reports success")
	else:
		check(expected.load(expectation) == OK, "read first process expectations")
		check(game.selected_weapon == "rail", "cold startup restores selected loadout")
		check(is_equal_approx(game.settings.values.volume, 0.35) and game.settings.values.shake == 0.0, "settings survive process termination")
		check(not game.settings.values.story_motion, "static narrative preference survives process termination")
		check(game.settings.keys.slash == KEY_F and InputMap.action_get_events("slash").any(func(event): return event is InputEventKey and event.physical_keycode == KEY_F), "restored keyboard binding is active in InputMap")
		check(game.continue_saved_run(), "second process continues the saved rescue")
		check(game.room == 3 and game.state == "shop" and game.player.weapon.definition.id == "rail", "shop checkpoint reconstructs the correct state")
		await snapshot("shop-read")
		for item in [["cores", game.profile.cores], ["runs", game.profile.runs], ["scrap", game.scrap], ["damage", game.player.damage], ["hp", game.player.hp], ["purchased", game.purchased], ["history", game.route_history]]:
			check(item[1] == expected.get_value("expected", item[0]), "restoration neither loses nor duplicates " + str(item[0]))
		check(not game.buy_item(1), "already purchased stock cannot be bought twice")
		await complete_campaign()
		check(game.state == "victory" and game.story_seen.size() == 6, "resumed release reaches all story beats and the ending")
		await snapshot("victory-read")
		var disk_profile = game.PROFILE.new()
		disk_profile.load_progress(game.profile.save_path)
		check(disk_profile.wins == 1 and disk_profile.checkpoint.is_empty(), "victory is durable and removes the completed checkpoint")
	# A second profile in the same marked fixture protects the existing single-player oracle.
	game.profile.save_path = directory.path_join("coop-profile.cfg")
	if game.verification_stage == "write":
		game.coop.enabled = true
		game.coop.devices.assign([1, 3])
		game.coop.weapons.assign(["rail", "ember"])
		game.configure_input()
		game.create_companion()
		game.companion.hp = 53.0
		game.save_checkpoint()
		check(game.RUN_SAVE.valid(game.profile.checkpoint) and game.profile.checkpoint.version == 2, "write both actors in one co-op transaction")
		check(FileAccess.file_exists(game.profile.save_path), "co-op profile exists before process exit")
		await snapshot("coop-write")
	else:
		game.clear_world()
		game.profile = game.PROFILE.new()
		game.profile.load_progress(directory.path_join("coop-profile.cfg"))
		game.show_menu("title")
		check(game.continue_saved_run() and game.state == "coop_lobby", "second process restores co-op and waits for device pairing")
		await pair_controllers()
		check(game.state == "shop" and game.team().size() == 2, "co-op pairing returns to the saved shop")
		check(game.companion.weapon.definition.id == "ember" and game.companion.hp == 53.0 and game.player.weapon.definition.id == "rail", "co-op second-process load preserves both weapons and independent health")
		check(not game.buy_item(1), "shared co-op purchase cannot be duplicated on resume")
		await snapshot("coop-read")
		await complete_campaign()
		check(game.state == "victory" and game.team().size() == 2, "resumed co-op reaches the ending in the real release executable")
	print("ABYSS STORAGE %s: %d checks, %d failures" % [game.verification_stage.to_upper(), checks, failures])
	game.queue_free()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if failures == 0 else 1)

func pad_tap(device: int, button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = device
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await frame()

func pair_controllers() -> void:
	await pad_tap(1, JOY_BUTTON_A)
	await pad_tap(3, JOY_BUTTON_A)
	await pad_tap(1, JOY_BUTTON_START)

func cooperative_release() -> void:
	game.open_coop()
	await pair_controllers()
	check(game.state == "story" and game.team().size() == 2, "packed co-op lobby launches with two independent devices")
	game.continue_story()
	var first: Vector2 = game.player.position
	var second: Vector2 = game.companion.position
	var event := InputEventJoypadMotion.new()
	event.device = 3
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = 1.0
	Input.parse_input_event(event)
	for i in range(12):
		await frame()
	event.axis_value = 0
	Input.parse_input_event(event)
	check(game.companion.position.x > second.x + 20 and game.player.position.distance_to(first) < 1, "packed device-3 movement never moves player one")
	check(game.player.weapon != game.companion.weapon, "packed actors own separate weapon controllers")
	await complete_campaign()
	check(game.state == "victory" and game.story_seen.size() == 6, "packed co-op campaign reaches all six story beats and rescue")
