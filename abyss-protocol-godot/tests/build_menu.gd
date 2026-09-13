extends SceneTree
const INFO = preload("res://scripts/build_info.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func frames(count := 2) -> void:
	for i in range(count): await physics_frame
	await process_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(1)

func pad(code: JoyButton, device := 3) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = device
		event.button_index = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(1)

func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/qa")
	check(root.get_texture().get_image().save_png("res://builds/qa/build-" + name + ".png") == OK, "Save overview evidence")

func reset_case(weapon := "blade") -> void:
	game.coop.enabled = false
	game.selected_weapon = weapon
	game.start_run(921)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	game.player.set_physics_process(false)
	game.player.position = Vector2(800, 650)
	game.player.aim = Vector2.RIGHT
	await frames()

func menu_cases() -> void:
	await reset_case("rail")
	game.player.weapon.tick(0.4, true, false)
	await key(KEY_TAB)
	check(game.state == "build" and not game.world.can_process(), "Tab opens a frozen overview during combat")
	check(not game.player.weapon.drawing, "Opening overview cancels charged attack")
	await key(KEY_1)
	check(game.state == "build", "Numeric reward hotkeys cannot select behind overview")
	await key(KEY_TAB)
	check(game.state == "paused", "Closing combat overview requires deliberate resume")
	await pad(JOY_BUTTON_DPAD_RIGHT)
	check(root.gui_get_focus_owner() is Button and "构筑" in root.gui_get_focus_owner().text, "Controller navigates from resume to overview")
	await pad(JOY_BUTTON_A)
	check(game.state == "build", "Nonzero controller opens overview through its button")
	await pad(JOY_BUTTON_B)
	check(game.state == "paused" and "构筑" in root.gui_get_focus_owner().text, "Controller back restores original focus")
	game.boon_choices = game.PROGRESSION.BOONS.slice(0, 3)
	game.prepare_routes()
	game.set_shop_stock("fire")
	game.scrap = 300
	for state in ["reward", "route", "shop", "rest", "paused"]:
		game.show_menu(state)
		await frames()
		var buttons: Array = game.hud.menu_buttons()
		buttons[mini(1, buttons.size() - 1)].grab_focus()
		var focus_index: int = game.hud.menu_buttons().find(root.gui_get_focus_owner())
		var before := var_to_bytes([game.rng.state, game.boon_choices, game.route_choices, game.shop_stock, game.purchased, game.scrap, game.profile.checkpoint, game.player.damage, game.player.hp, game.player.enchantments])
		await key(KEY_TAB)
		await frames(4)
		await key(KEY_ESCAPE)
		check(game.state == state, "Return to original " + state)
		check(game.hud.menu_buttons().find(root.gui_get_focus_owner()) == focus_index, "Restore choice focus in " + state)
		check(before == var_to_bytes([game.rng.state, game.boon_choices, game.route_choices, game.shop_stock, game.purchased, game.scrap, game.profile.checkpoint, game.player.damage, game.player.hp, game.player.enchantments]), "Inspection cannot reroll, spend, heal or rewrite checkpoint in " + state)
	game.open_settings()
	await frames()
	var settings_focus := root.gui_get_focus_owner()
	await key(KEY_TAB)
	check(game.state == "settings" and root.gui_get_focus_owner() != settings_focus, "Tab retains keyboard focus navigation in settings")
	game.close_settings()
	# Two independent weapons, menu ownership and reconnect while inspecting.
	game.coop.enabled = true
	game.coop.devices.assign([3, 7])
	game.coop.weapons.assign(["frost", "scatter"])
	game.start_run(921)
	game.player.enchantments = {"ice": 3, "fire": 2, "poison": 2, "shock": 3, "leech": 3, "execute": 3}
	game.open_build()
	await pad(JOY_BUTTON_DPAD_RIGHT, 7)
	check(game.build_seat == 0, "Second controller cannot steal shared menu")
	await pad(JOY_BUTTON_DPAD_RIGHT)
	await pad(JOY_BUTTON_A)
	check(game.build_seat == 1, "Pilot can inspect partner build")
	await snapshot("partner")
	game.coop.disconnected(7)
	check(game.state == "coop_lobby", "Disconnected device pauses overview")
	await pad(JOY_BUTTON_A, 8)
	await pad(JOY_BUTTON_START)
	check(game.state == "build" and game.build_seat == 1, "Re-pairing returns to inspected seat")
	await pad(JOY_BUTTON_START)
	check(game.state == "paused", "Reconnected overview still returns to pause")
	game.open_build()
	await frames()
	await snapshot("overview")
	var seen: Dictionary = {}
	for i in range(9):
		await pad(JOY_BUTTON_DPAD_DOWN)
		var focus := root.gui_get_focus_owner()
		if is_instance_valid(focus): seen[focus.get_instance_id()] = true
	check(seen.size() >= 5, "D-pad reaches scrollable information and return button")
	await snapshot("scrolled")
	game.show_menu("reward")
	game.boon_choices = [game.PROGRESSION.rune("ice"), game.PROGRESSION.rune("shock"), game.PROGRESSION.BOONS[0]]
	game.hud.show_menu("reward")
	await frames()
	await snapshot("reward")
	var viewport: Rect2 = game.get_viewport_rect().grow(1)
	for button in game.hud.menu_buttons():
		check(viewport.encloses(button.get_global_rect()), "Reward controls fit viewport with per-seat descriptions")
		for text in button.find_children("*", "Label", true, false):
			check(button.get_global_rect().grow(1).encloses(text.get_global_rect()), "Per-seat reward text fits inside its card")
	game.show_menu("shop")
	game.set_shop_stock("shock")
	game.hud.show_menu("shop")
	await frames()
	await snapshot("shop")
	for button in game.hud.menu_buttons():
		check(viewport.encloses(button.get_global_rect()), "Shop controls fit viewport with per-seat descriptions")
	for dimensions in [Vector2i(960, 600), Vector2i(2560, 1440)]:
		root.size = dimensions
		game.open_build()
		await frames(4)
		var bounds: Rect2 = game.get_viewport_rect().grow(1)
		for button in game.hud.menu_buttons():
			check(bounds.encloses(button.get_global_rect()), "Overview navigation fits " + str(dimensions))
		await snapshot("size-%d" % dimensions.x)
		game.close_build()

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	game.narrative_enabled = false
	root.add_child(game)
	await frames()
	game.muted = true
	game.apply_settings()
	await menu_cases()
	game.queue_free()
	# Let the audio thread retire its paused ambience playback before engine exit.
	await create_timer(0.2).timeout
	print("ABYSS BUILD MENU: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
