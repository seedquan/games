extends SceneTree
const ENCOUNTER_FIXTURE = preload("res://tests/encounter_fixture.gd")
## Two-device input, combat, recovery, safe-point persistence and widescreen UI.
var game
var checks := 0
var failures: Array[String] = []
var rendered := DisplayServer.get_name() != "headless"
var fixture := "res://builds/qa/coop-%d" % Time.get_ticks_usec()

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count := 2) -> void:
	for i in range(count):
		await physics_frame
	await process_frame

func pad(device: int, code: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = code
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(device: int, code: JoyButton) -> void:
	pad(device, code, true)
	await frames()
	pad(device, code, false)
	await frames()

func axis(device: int, code: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = code
	event.axis_value = value
	Input.parse_input_event(event)

func create_game() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	await frames()

func freeze_enemies() -> void:
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)

func screenshot(name: String) -> void:
	if rendered:
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		check(picture.get_size() == Vector2i(2560, 1440), "QHD screenshot uses a 2560 × 1440 framebuffer")
		check(picture.save_png(fixture.path_join(name + ".png")) == OK, "Save rendered " + name)

func join(first := 1, second := 3) -> void:
	await tap(first, JOY_BUTTON_A)
	await tap(second, JOY_BUTTON_A)
	check(game.coop.devices == [first, second], "Two distinct devices claim separate seats")
	await tap(first, JOY_BUTTON_START)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	root.size = Vector2i(2560, 1440)
	await create_game()
	await screenshot("title")
	game.open_coop()
	await tap(1, JOY_BUTTON_B)
	check(game.state == "title", "Unpaired controller can leave the lobby without a keyboard")
	game.open_coop()
	await tap(1, JOY_BUTTON_A)
	await tap(1, JOY_BUTTON_A)
	check(game.coop.devices == [1, -1], "One controller cannot occupy both seats")
	await tap(1, JOY_BUTTON_START)
	check(game.state == "coop_lobby" and game.player == null, "Cannot start without two controllers")
	await tap(3, JOY_BUTTON_A)
	await tap(3, JOY_BUTTON_DPAD_RIGHT)
	check(game.coop.weapons[0] == "blade" and game.coop.weapons[1] == "scatter", "Second player chooses a separate weapon")
	await tap(3, JOY_BUTTON_DPAD_LEFT)
	await screenshot("lobby")
	await tap(1, JOY_BUTTON_START)
	check(game.state == "story" and game.team().size() == 2, "Co-op starts the actual narrative campaign")
	check(game.player.weapon.definition.id == "blade" and game.companion.weapon.definition.id == "rifle", "Each loadout reaches its own actor")
	await tap(3, JOY_BUTTON_A)
	check(game.state == "story", "Second seat cannot accidentally confirm shared story")
	await tap(1, JOY_BUTTON_A)
	check(game.state == "playing", "First seat confirms story through focused UI")
	freeze_enemies()
	var first: Vector2 = game.player.position
	var second: Vector2 = game.companion.position
	axis(3, JOY_AXIS_LEFT_X, 1)
	await frames(15)
	axis(3, JOY_AXIS_LEFT_X, 0)
	await frames(10)
	check(game.companion.position.x > second.x + 35 and game.player.position.distance_to(first) < 1, "Device 3 moves only the second actor")
	second = game.companion.position
	axis(1, JOY_AXIS_LEFT_X, -1)
	await frames(15)
	axis(1, JOY_AXIS_LEFT_X, 0)
	await frames(10)
	check(game.player.position.x < first.x - 35 and game.companion.position.distance_to(second) < 1, "Device 1 moves only the first actor")
	first = game.player.position
	second = game.companion.position
	axis(7, JOY_AXIS_LEFT_X, 1)
	await frames(10)
	axis(7, JOY_AXIS_LEFT_X, 0)
	check(game.player.position.distance_to(first) < 1 and game.companion.position.distance_to(second) < 1, "Unassigned third controller cannot move either actor")
	axis(1, JOY_AXIS_RIGHT_Y, -1)
	axis(3, JOY_AXIS_RIGHT_X, 1)
	await frames()
	check(game.player.aim.dot(Vector2.UP) > 0.99 and game.companion.aim.dot(Vector2.RIGHT) > 0.99, "Simultaneous sticks retain independent aim")
	axis(1, JOY_AXIS_RIGHT_Y, 0)
	axis(3, JOY_AXIS_RIGHT_X, 0)
	for entry in [[JOY_BUTTON_RIGHT_SHOULDER, "slash_cooldown"], [JOY_BUTTON_LEFT_SHOULDER, "bolt_cooldown"], [JOY_BUTTON_A, "dash_cooldown"], [JOY_BUTTON_X, "freeze_cooldown"], [JOY_BUTTON_B, "parry_cooldown"]]:
		game.player.set(entry[1], 0.0)
		game.companion.set(entry[1], 0.0)
		await tap(3, entry[0])
		check(game.companion.get(entry[1]) > 0 and game.player.get(entry[1]) == 0, "Device 3 independently triggers " + entry[1])
	game.companion.weapon.equip("rail")
	pad(3, JOY_BUTTON_RIGHT_SHOULDER, true)
	await frames(30)
	check(game.companion.weapon.drawing and not game.player.weapon.drawing, "Second-seat charged weapon holds independently")
	await tap(1, JOY_BUTTON_START)
	check(game.state == "paused" and not game.companion.weapon.drawing, "Either seat pauses and cancels both charge states")
	pad(3, JOY_BUTTON_RIGHT_SHOULDER, false)
	await frames()
	await tap(1, JOY_BUTTON_A)
	check(game.state == "playing", "Resume requires no keyboard")
	game.player.position = Vector2(740, 800)
	game.companion.position = Vector2(810, 800)
	game.player.velocity = Vector2.ZERO
	game.companion.velocity = Vector2.ZERO
	game.player.invulnerable = 0
	game.companion.invulnerable = 0
	game.companion.take_damage(10000, Vector2(900, 800), false)
	check(game.state == "playing" and game.companion.hp == 0, "One downed teammate does not end the run")
	check(game.nearest_player(game.companion.position) == game.player, "Enemies select the surviving player")
	await frames(195)
	check(game.companion.hp > 0 and game.companion.hp < game.companion.max_hp, "Standing nearby repairs the actual downed teammate")
	game.player.position = Vector2(650, 800)
	game.companion.position = Vector2(810, 800)
	game.companion.invulnerable = 0
	var prior_hp: float = game.companion.hp
	var bolt = game.spawn_bolt(Vector2(900, 800), Vector2.LEFT, true, 7.0)
	await frames(24)
	check(game.companion.hp < prior_hp, "Actual hostile projectile hits the second player through physics")
	game.player.invulnerable = 0
	game.companion.invulnerable = 0
	var first_hp: float = game.player.hp
	prior_hp = game.companion.hp
	game.spawn_hazard(Vector2(730, 800), 150, 3)
	await frames(65)
	check(game.player.hp < first_hp and game.companion.hp < prior_hp, "One placed hazard damages both living teammates")
	game.companion.invulnerable = 0
	var stalker = game.spawn_enemy("stalker", game.companion.position - Vector2(50, 0))
	stalker.set_physics_process(false)
	stalker.committed_direction = Vector2.RIGHT
	prior_hp = game.companion.hp
	stalker.release_attack()
	check(game.companion.hp < prior_hp, "Melee damage geometry includes the second player")
	game.companion.invulnerable = 0
	game.companion.take_damage(10000, Vector2.ZERO, false)
	game.player.position = Vector2(1300, 800)
	await frames(15)
	check(game.companion.revive_progress == 0, "Revive cannot progress at a distance")
	await ENCOUNTER_FIXTURE.clear(game)
	await frames()
	check(game.state == "reward" and game.companion.hp > 0, "Clearing the room recovers the teammate before the checkpoint")
	var hp: float = game.companion.hp
	var damage: float = game.companion.damage
	game.boon_choices[0] = game.PROGRESSION.rune("damage")
	await tap(1, JOY_BUTTON_A)
	check(game.state == "route" and game.companion.damage > damage and game.companion.hp > hp, "Shared reward reaches both actors exactly once")
	var health_labels: Array = game.hud.menu_margin.find_children("*", "Label", true, false).filter(func(node): return "二号耐久" in node.text)
	check(health_labels.size() == 1 and ("二号耐久 %d / %d" % [game.companion.hp, game.companion.max_hp]) in health_labels[0].text, "Shared menu displays the second player's actual health")
	if health_labels.size() == 1:
		check(game.get_viewport_rect().encloses(health_labels[0].get_global_rect()), "Shared health readout fits the screen")
	var saved: Dictionary = game.profile.checkpoint.duplicate(true)
	check(game.RUN_SAVE.valid(saved) and saved.version == 2 and saved.partner.weapon == "rail", "Co-op checkpoint includes the second player's actual weapon")
	var invalid: Dictionary = saved.duplicate(true)
	invalid.partner.stats.hp = NAN
	check(not game.RUN_SAVE.valid(invalid), "Corrupt second-player stats cannot enter the game")
	invalid = saved.duplicate(true)
	invalid.erase("partner")
	check(not game.RUN_SAVE.valid(invalid), "Missing co-op partner is rejected")
	game.profile.save_path = fixture.path_join("profile.cfg")
	check(game.profile.save_progress() == OK, "Write co-op snapshot to isolated disk fixture")
	game.queue_free()
	await frames(8)
	await create_game()
	game.profile.load_progress(fixture.path_join("profile.cfg"))
	check(game.continue_saved_run() and game.state == "coop_lobby", "New game instance restores both actors and requires controller pairing")
	check(game.companion.damage == saved.partner.stats.damage and game.companion.weapon.definition.id == "rail", "Disk resume preserves independent stats and weapon")
	await join(1, 7)
	check(game.state == "route", "Re-pair resumes the saved menu without advancing the route")
	game.choose_route(0)
	await frames()
	freeze_enemies()
	check(game.room == 2 and game.team().size() == 2, "Both actors move into the next chamber")
	game.controller_changed(7, false)
	check(game.state == "coop_lobby" and game.coop.devices == [1, -1], "Disconnect pauses and preserves the other seat")
	await tap(3, JOY_BUTTON_A)
	await tap(1, JOY_BUTTON_START)
	check(game.state == "paused" and game.coop.devices == [1, 3], "New OS device ID reclaims the disconnected seat")
	await tap(1, JOY_BUTTON_A)
	check(game.state == "playing", "Reconnected team resumes via controller")
	root.size = Vector2i(2560, 1440)
	await frames(20)
	game.player.position = Vector2(200, 850)
	game.companion.position = Vector2(1400, 250)
	game.camera.reset_smoothing()
	await frames(45)
	var view: Rect2 = game.get_viewport_rect()
	for member in game.team():
		var projected: Vector2 = game.get_viewport().get_canvas_transform() * member.position
		check(view.grow(-85).has_point(projected), "Camera keeps each separated player on-screen")
	check(is_equal_approx(view.size.x / view.size.y, 16.0 / 9.0), "QHD uses a full 16:9 gameplay canvas without pillarboxing")
	check(game.hud.partner_panel.visible and game.hud.partner_panel.get_global_rect().end.x <= view.size.x, "Second player HUD stays within the canvas")
	await screenshot("cooperative-qhd")
	# Full state-machine campaign, validating both members at every safe point.
	for step in range(game.run_length * 5):
		if game.result_recorded:
			break
		match game.state:
			"playing":
				freeze_enemies()
				await ENCOUNTER_FIXTURE.clear(game)
				await frames()
			"story": game.continue_story()
			"reward": game.choose_boon(0)
			"route": game.choose_route(0)
			"shop", "rest": game.leave_supply()
			_: break
		if not game.result_recorded:
			check(game.RUN_SAVE.valid(game.profile.checkpoint), "Both members remain restorable at chamber %d / %s" % [game.room, game.state])
		await frames()
	check(game.room == game.run_length and game.profile.wins == 1 and game.result_recorded, "Co-op reaches the rescue ending exactly once")
	check(game.story_seen.size() == 6 and game.profile.checkpoint.is_empty(), "Co-op retains all story beats and clears finished checkpoint")
	game.narrative_enabled = false
	game.start_run(781)
	await frames()
	freeze_enemies()
	for member in game.team():
		member.invulnerable = 0
		member.take_damage(100000, Vector2.ZERO, false)
	check(game.state == "dead" and game.profile.checkpoint.is_empty(), "Both down ends the run and clears its checkpoint")
	await tap(1, JOY_BUTTON_A)
	check(game.state == "playing" and game.team().size() == 2 and game.coop.enabled, "Controller retry after defeat preserves the cooperative mode")
	freeze_enemies()
	if rendered:
		game.set_setting("fullscreen", true)
		await frames(120)
		print("FULLSCREEN EVIDENCE: " + JSON.stringify({"window": root.size, "screen": DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()), "safe_area": DisplayServer.get_display_safe_area(), "scale": DisplayServer.screen_get_scale(), "mode": DisplayServer.window_get_mode()}))
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Settings activates actual native fullscreen")
		var screen_size := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
		var safe_size := DisplayServer.get_display_safe_area().size
		check(root.size == screen_size or root.size == safe_size, "Fullscreen fills the display or its OS-reported safe area")
		await RenderingServer.frame_post_draw
		var fullscreen_image := root.get_texture().get_image()
		check(fullscreen_image.save_png(fixture.path_join("fullscreen.png")) == OK, "Save native fullscreen evidence")
		game.set_setting("fullscreen", false)
		await frames(120)
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "Fullscreen returns to windowed mode")
	for member in game.team():
		member.invulnerable = 0
		member.take_damage(100000, Vector2.ZERO, false)
	await frames()
	var dock_buttons: Array = game.hud.menu_margin.find_children("*", "Button", true, false).filter(func(node): return node.text == "返回船坞")
	check(dock_buttons.size() == 1, "Cooperative result offers a return to mode selection")
	if dock_buttons.size() == 1:
		dock_buttons[0].grab_focus()
		await tap(1, JOY_BUTTON_A)
		check(game.state == "title" and game.team().is_empty() and not game.coop.enabled, "Controller returns from cooperative defeat to the main menu")
	game.queue_free()
	await frames(8)
	print("ABYSS COOP: %d checks, %d failures" % [checks, failures.size()])
	print("COOP EVIDENCE: " + ProjectSettings.globalize_path(fixture))
	quit(0 if failures.is_empty() else 1)
