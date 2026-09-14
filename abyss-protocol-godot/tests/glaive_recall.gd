extends "res://tests/weapon_mods.gd"
## Primary-input edges control one existing blade, never create another projectile.

func attack(down: bool) -> void:
	if not is_instance_valid(game.player): return
	if down: Input.action_press(game.player.action("slash"))
	else: Input.action_release(game.player.action("slash"))

func setup_recall(version := 2, modification := "mod_focus") -> Array:
	attack(false)
	Input.action_release("aim_right")
	var targets := await reset_case("glaive", "", [Vector2(130, 0)])
	game.campaign_version = version
	game.player.weapon_mod = modification
	game.player.weapon.equip("glaive")
	game.using_gamepad = true
	Input.action_press("aim_right")
	game.player.set_physics_process(true)
	await frames()
	return targets

func input_recall() -> void:
	var targets := await setup_recall()
	attack(true)
	await frames(27)
	var shot = game.player.weapon.active_glaive.get_ref()
	check(is_instance_valid(shot) and not shot.returning, "Holding primary keeps the full outbound flight")
	check(game.player.slash_cooldown == 0, "Recovery finishes before the heavy blade's automatic return")
	var outbound: float = game.player.damage * 1.4 * 0.75
	check(is_equal_approx(10000 - targets[0].hp, outbound), "The actual outbound flight hits once before recall")
	attack(false)
	await frames()
	attack(true)
	await frames()
	check(shot.returning and shot.flight_elapsed < shot.return_after, "A fresh attack after recovery recalls the existing blade early")
	check(game.get_node("World/Projectiles").get_child_count() == 1, "Recall never throws a second blade")
	attack(false)
	await frames(60)
	check(is_equal_approx(10000 - targets[0].hp, outbound * 4), "Recalled heavy blade deals one unchanged triple return hit")
	check(not is_instance_valid(shot), "Recalled blade reaches its owner and is cleaned up")

func recall_boundaries() -> void:
	await setup_recall()
	attack(true)
	await frames(4)
	var shot = game.player.weapon.active_glaive.get_ref()
	var outbound: float = shot.damage
	attack(false)
	await frames()
	attack(true)
	await frames(23)
	check(not shot.returning, "An early press cannot bypass recovery or become a queued recall when held")
	check(game.player.weapon.can_recall(), "The actual blade becomes recallable once recovery ends")
	game.hud.update_status()
	check(game.hud.skills[0].text.begins_with("回收\n"), "HUD names the available recall action")
	check(game.hud.skill_icons[0].modulate == game.hud.MINT, "Available recall has a ready primary icon")
	if DisplayServer.get_name() != "headless":
		shot.set_physics_process(false)
		root.size = Vector2i(1280, 800)
		await frames(8)
		check(root.size == Vector2i(1280, 800), "Recall action renders at the standard desktop size")
		await snapshot("glaive-recall-ready")
		shot.set_physics_process(true)
	game.player.hp = 0
	check(not game.player.weapon.can_recall(), "Downed owner cannot recall")
	game.player.hp = 100
	game.show_menu("paused")
	var paused_time: float = shot.flight_elapsed
	attack(false)
	await frames()
	attack(true)
	await frames()
	check(not shot.returning and shot.flight_elapsed == paused_time, "Menu input cannot recall or advance the blade")
	game.resume_run()
	await frames()
	check(not shot.returning and not game.player.input_armed, "A held resume press cannot leak into recall")
	attack(false)
	await frames()
	attack(true)
	await frames()
	check(shot.returning, "A released and newly pressed attack can recall after resume")
	var return_damage: float = shot.damage
	attack(false)
	await frames()
	attack(true)
	await frames()
	check(is_equal_approx(shot.damage, outbound * 3) and shot.damage == return_damage, "Repeated recall presses never multiply damage again")
	check(not game.player.weapon.can_recall(), "Returning blade is not another recall opportunity")
	game.hud.update_status()
	check("回收中" in game.hud.skills[0].text, "Returning blade retains its in-flight status")
	attack(false)
	await setup_recall(1)
	attack(true)
	await frames(25)
	shot = game.player.weapon.active_glaive.get_ref()
	shot.set_physics_process(false)
	attack(false)
	await frames()
	attack(true)
	await frames()
	check(not shot.returning and not game.player.weapon.can_recall(), "Legacy campaign retains automatic-only return")
	attack(false)
	await setup_recall(2, "mod_flow")
	attack(true)
	await frames(20)
	shot = game.player.weapon.active_glaive.get_ref()
	check(shot.returning and not game.player.weapon.can_recall(), "Quick-return refit still returns at its shorter flight time")
	attack(false)
	await frames(50)
	check(not game.player.weapon.can_recall(), "Expired weak references are not recallable")

func pad_button(device: int, down: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = JOY_BUTTON_RIGHT_SHOULDER
	event.pressed = down
	Input.parse_input_event(event)

func cooperative_recall() -> void:
	await setup_recall()
	attack(false)
	game.coop.enabled = true
	game.coop.devices.assign([1, 3])
	game.coop.weapons.assign(["glaive", "glaive"])
	game.configure_input()
	game.start_run(8142)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	for member in game.team():
		member.position = Vector2(800, 650 + member.seat * 150)
		member.weapon_mod = "mod_focus"
		member.weapon.equip("glaive")
		Input.action_press(member.action("aim_right"))
	await frames()
	pad_button(1, true)
	pad_button(3, true)
	await frames(27)
	var first = game.player.weapon.active_glaive.get_ref()
	var second = game.companion.weapon.active_glaive.get_ref()
	pad_button(3, false)
	await frames()
	pad_button(3, true)
	await frames()
	check(second.returning and not first.returning, "Actual device 3 shoulder input recalls only its paired player's blade")
	check(second.shooter == game.companion and first.shooter == game.player, "Cooperative recall preserves ownership")
	game.hud.update_status()
	check(game.hud.skills[0].text == "回收\n" + game.CONTROLS.PAD_LABELS.slash and "回收中" in game.hud.partner_skills[0].text, "Each seat shows its own available action and flight state")
	pad_button(1, false)
	pad_button(3, false)
	for member in game.team(): Input.action_release(member.action("aim_right"))
	game.start_run(8142)
	await frames()
	check(not is_instance_valid(first) and not is_instance_valid(second), "Restart removes both recalled and outbound blades")
	check(not game.player.weapon.can_recall() and not game.companion.weapon.can_recall(), "Restart cannot recall a previous run's blade")

func keyboard_recall() -> void:
	await setup_recall()
	game.settings.keys.slash = KEY_F
	game.configure_input()
	game.using_gamepad = false
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	Input.parse_input_event(key)
	await frames(27)
	var shot = game.player.weapon.active_glaive.get_ref()
	game.hud.update_status()
	check(game.hud.skills[0].text == "回收\nF", "Recall uses the actual rebound keyboard prompt")
	check(game.hud.skill_icons[0].texture.resource_path.ends_with("recall_action.svg"), "Recall has its own return-arrow action icon")
	key.echo = true
	Input.parse_input_event(key)
	await frames()
	check(not shot.returning, "Keyboard auto-repeat cannot recall a held attack")
	key = key.duplicate()
	key.echo = false
	key.pressed = false
	Input.parse_input_event(key)
	await frames()
	key = key.duplicate()
	key.pressed = true
	Input.parse_input_event(key)
	await frames()
	check(shot.returning, "A real rebound-key press recalls the blade")
	key.pressed = false
	Input.parse_input_event(key)
	game.open_help()
	var tip = game.hud.find_child("GlaiveReturnInstruction", true, false)
	check(tip != null and "再次按 F" in tip.text and "冷却" in tip.text, "Help teaches recall timing with the current binding")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(960, 600)
		await frames(10)
		check(root.size == Vector2i(960, 600), "Recall help renders at the small desktop size")
		await snapshot("glaive-recall-help")

func mouse_recall() -> void:
	await setup_recall()
	game.using_gamepad = false
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = game.player.get_global_transform_with_canvas().origin + Vector2(280, 0)
	event.global_position = event.position
	event.pressed = true
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	await frames(27)
	var shot = game.player.weapon.active_glaive.get_ref()
	check(not shot.returning, "Held mouse keeps the blade outbound until a second click")
	event = event.duplicate()
	event.pressed = false
	event.button_mask = 0
	Input.parse_input_event(event)
	await frames()
	event = event.duplicate()
	event.pressed = true
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	await frames()
	check(shot.returning, "A second real mouse click recalls the same projectile")
	event.pressed = false
	event.button_mask = 0
	Input.parse_input_event(event)

func run() -> void:
	await spawn_game()
	await input_recall()
	await recall_boundaries()
	await cooperative_recall()
	await keyboard_recall()
	await mouse_recall()
	attack(false)
	Input.action_release("aim_right")
	game.queue_free()
	await create_timer(0.5).timeout
	print("ABYSS GLAIVE RECALL: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
