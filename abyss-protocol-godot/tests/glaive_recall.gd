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
	var return_damage: float = shot.damage
	check(return_damage > outbound * 2 and return_damage < outbound * 2.5, "Early recall trades part of the heavy return bonus for a shorter flight")
	attack(false)
	await frames(60)
	check(is_equal_approx(10000 - targets[0].hp, outbound + return_damage), "Actual recalled hit uses exactly the strength committed at the turn")
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
	check(shot.damage < outbound * 3 and shot.damage == return_damage, "Repeated recall presses never grow or multiply the committed return damage")
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

func return_momentum() -> void:
	attack(false)
	Input.action_release("aim_right")
	var targets := await reset_case("glaive", "mod_focus", [Vector2(130, 0)])
	fire()
	var shot = game.player.weapon.active_glaive.get_ref()
	shot.set_physics_process(false)
	var outbound: float = shot.damage
	shot.position = game.player.position + Vector2(300, 0)
	shot.flight_elapsed = 0.375
	check(is_equal_approx(shot.return_charge_fraction(), 0.5), "Charge cue reflects elapsed outbound time")
	game.show_menu("paused")
	await frames(4)
	check(is_equal_approx(shot.return_charge_fraction(), 0.5), "Paused time cannot fill the outbound charge cue")
	game.resume_run()
	shot.begin_return()
	check(is_equal_approx(shot.damage, outbound * 2), "Half of the heavy outbound time earns a double return instead of a free triple hit")
	var committed: float = shot.damage
	shot.flight_elapsed = 2.0
	shot.begin_return()
	check(shot.damage == committed, "Time spent returning cannot increase the already committed hit")
	check(is_equal_approx(shot.return_charge_fraction(), 0.5), "Return cue holds the actual committed charge")
	shot.speed = 18000
	shot._physics_process(1.0 / 60)
	check(is_equal_approx(10000 - targets[0].hp, committed), "Swept return collision delivers the committed partial charge exactly once")
	var description: String = game.BUILD_INFO.attack_text(game.player.weapon.definition, game.player.damage)
	check("最大回程命中" in description and "蓄势" in description, "Build explains that the displayed heavy return is a charged maximum")
	check("蓄势" in game.PROGRESSION.MODS.details("glaive", "mod_focus"), "Refit choice explains the flight-time tradeoff before selection")
	# Real cover ends the outbound leg immediately; it cannot grant free full charge.
	await reset_case("glaive", "mod_focus", [Vector2(200, 0)])
	game.arena.add_wall(Rect2(915, 668, 6, 60))
	await frames()
	fire()
	shot = game.player.weapon.active_glaive.get_ref()
	shot.set_physics_process(false)
	outbound = shot.damage
	shot.speed = 18000
	shot._physics_process(1.0 / 60)
	check(shot.returning and shot.damage > outbound and shot.damage < outbound * 1.1, "Immediate cover turn earns only the outbound time actually travelled")
	# Normal and quick-return blades retain their fixed equal-strength legs.
	for modification in ["", "mod_flow"]:
		await reset_case("glaive", modification, [])
		fire()
		shot = game.player.weapon.active_glaive.get_ref()
		shot.set_physics_process(false)
		outbound = shot.damage
		shot.flight_elapsed = 0.1
		shot.begin_return()
		check(shot.damage == outbound, "Non-heavy blade keeps equal outbound and return damage: " + modification)
	await reset_case("glaive", "mod_focus", [Vector2(130, 0)])
	fire()
	shot = game.player.weapon.active_glaive.get_ref()
	shot.set_physics_process(false)
	outbound = shot.damage
	shot.flight_elapsed = 0.75
	shot.begin_return()
	check(is_equal_approx(shot.damage, outbound * 3), "Waiting for the full outbound time retains the triple return payoff")

func native_momentum_preview() -> void:
	if DisplayServer.get_name() == "headless": return
	await reset_case("glaive", "mod_focus", [Vector2(200, 0)])
	root.size = Vector2i(1280, 800)
	fire()
	var shot = game.player.weapon.active_glaive.get_ref()
	shot.set_physics_process(false)
	shot.position = game.player.position + Vector2(160, 0)
	shot.flight_elapsed = 0.375
	shot.queue_redraw()
	await frames(8)
	check(root.size == Vector2i(1280, 800), "Heavy charge cue renders at the standard desktop size")
	await snapshot("momentum-half")
	game.settings.values.high_contrast = true
	game.settings.values.flash = false
	shot.flight_elapsed = 0.75
	shot.begin_return()
	shot.queue_redraw()
	await snapshot("momentum-full")
	game.open_build()
	await snapshot("momentum-build")

func run() -> void:
	await spawn_game()
	await input_recall()
	await recall_boundaries()
	await cooperative_recall()
	await keyboard_recall()
	await mouse_recall()
	await return_momentum()
	await native_momentum_preview()
	attack(false)
	Input.action_release("aim_right")
	game.queue_free()
	await create_timer(0.5).timeout
	print("ABYSS GLAIVE RECALL: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
