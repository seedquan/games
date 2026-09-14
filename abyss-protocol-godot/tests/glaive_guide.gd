extends "res://tests/weapon_mods.gd"
## A visual return lane must follow the owner and cover without changing combat.

func guide_for(shot):
	check(shot.has_method("get_return_guide"), "Returning glaive provides a floor guide")
	return shot.get_return_guide() if shot.has_method("get_return_guide") else null

func lane_cases() -> void:
	await reset_case("glaive", "mod_focus", [Vector2(150, 0)])
	fire()
	var shot = game.get_node("World/Projectiles").get_child(0)
	shot.set_physics_process(false)
	var guide = guide_for(shot)
	if guide == null: return
	guide.refresh()
	check(not guide.visible, "Outbound flight does not promise a future return path")
	shot.position = game.player.position + Vector2(330, 0)
	shot.begin_return()
	guide.refresh()
	check(guide.visible and guide.start == shot.global_position and guide.end == game.player.global_position, "Clear return lane joins the actual floor positions")
	check(not guide.blocked, "An enemy does not block a piercing return guide")
	var before := [shot.position, shot.damage, shot.life, shot.direction, shot.hit_ids.duplicate(), shot.excluded.duplicate()]
	for i in range(20): guide.refresh()
	check(before == [shot.position, shot.damage, shot.life, shot.direction, shot.hit_ids, shot.excluded], "Guide queries never change projectile state")
	game.player.position += Vector2(0, 100)
	guide.refresh()
	check(guide.end == game.player.global_position, "Moving the owner changes the return direction")
	var end: Vector2 = guide.end
	game.state = "paused"
	game.player.position += Vector2(0, 30)
	guide.refresh()
	check(guide.end == end and guide.visible, "Pause preserves the frozen floor cue")
	game.state = "playing"
	game.player.hp = 0
	guide.refresh()
	check(not guide.visible, "Downed owner hides an unusable movement cue")
	game.player.hp = 100
	guide.refresh()
	check(guide.visible, "Revived owner regains the cue")
	shot.queue_free()
	await frames()
	check(not is_instance_valid(guide), "Guide is freed together with the blade")

func wall_case() -> void:
	await reset_case("glaive", "", [])
	game.arena.add_wall(Rect2(915, 668, 6, 60))
	await frames()
	fire()
	var shot = game.get_node("World/Projectiles").get_child(0)
	shot.set_physics_process(false)
	shot.position = Vector2(1100, 650)
	shot.begin_return()
	var guide = guide_for(shot)
	if guide == null: return
	guide.refresh()
	check(guide.blocked and guide.end.x > 921, "Return guide clips the full blade width against a grazing wall lip")
	var predicted: Vector2 = guide.end
	shot.speed = 18000
	shot._physics_process(1.0 / 60)
	check(shot.spent and shot.position.distance_to(predicted) < 0.2, "Actual return impact agrees with the guide's wall endpoint")

func cooperative_case() -> void:
	game.coop.enabled = true
	game.coop.devices.assign([3, 7])
	game.coop.weapons.assign(["glaive", "glaive"])
	game.configure_input()
	game.start_run(831)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	var shots := []
	var guides := []
	for member in game.team():
		member.set_physics_process(false)
		member.position = Vector2(730 + member.seat * 230, 640 + member.seat * 100)
		member.aim = Vector2.RIGHT
		member.weapon.fire()
		var shot = member.weapon.active_glaive.get_ref()
		shot.set_physics_process(false)
		shot.position = member.position + Vector2(270, -80)
		shot.begin_return()
		member.weapon.tick(0, false, false)
		shots.append(shot)
		guides.append(guide_for(shot))
	await frames()
	for i in range(2):
		guides[i].refresh()
		check(guides[i].visible and guides[i].end == game.team()[i].global_position, "Each guide returns to its own controller seat")
	check(guides[0].identity != guides[1].identity and guides[1].arrows.size() == guides[0].arrows.size() * 2, "Seat identity uses both blue/gold and one/two chevrons")
	check(game.get_node("World/WeaponGuides").get_index() < game.get_node("World/Actors").get_index(), "Floor guides render below actors and raised cover")
	game.settings.values.high_contrast = true
	for guide in guides: guide.refresh()
	check(guides.all(func(guide): return guide.contrast), "High contrast applies to both seats without changing preferences on disk")
	if DisplayServer.get_name() != "headless":
		game.settings.values.high_contrast = false
		root.size = Vector2i(1280, 800)
		await frames(40)
		check(root.size == Vector2i(1280, 800), "Native return guides render at the requested desktop size")
		await snapshot("glaive-return-coop")
		game.settings.values.high_contrast = true
		root.size = Vector2i(960, 600)
		await frames(8)
		check(root.size == Vector2i(960, 600), "Native return guides render at the requested small size")
		await snapshot("glaive-return-small")
	game.settings.values.high_contrast = false
	var before: Vector2 = game.player.global_position
	game.player.set_physics_process(true)
	shots[0].set_physics_process(true)
	var motion := InputEventJoypadMotion.new()
	motion.device = 3
	motion.axis = JOY_AXIS_LEFT_Y
	motion.axis_value = 1.0
	Input.parse_input_event(motion)
	await frames(10)
	motion.axis_value = 0.0
	Input.parse_input_event(motion)
	check(game.player.global_position.y > before.y + 10, "A real paired-controller axis moves the owner during flight")
	check(guides[0].visible and guides[0].end == game.player.global_position and guides[0].start == shots[0].global_position, "Physics-updated guide follows live movement and flight in the same step")
	shots[0].queue_free()
	await frames()
	check(not is_instance_valid(guides[0]) and is_instance_valid(guides[1]) and guides[1].visible, "Finishing one blade leaves the other seat's guide alive")
	game.start_run(832)
	await frames()
	check(game.get_node("World/WeaponGuides").get_child_count() == 0, "Restart clears every previous return guide")
	game.campaign_version = 1
	game.player.weapon.equip("glaive")
	game.player.slash_cooldown = 0
	game.player.weapon.fire()
	check(game.player.weapon.active_glaive.get_ref().get_return_guide() == null, "Legacy flights do not create the new guide")
	game.campaign_version = 2
	game.open_help()
	check(game.hud.find_child("GlaiveReturnGuide", true, false) != null, "Chinese help includes the matching vector return diagram")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 800)
		await frames(8)
		await snapshot("glaive-return-help")

func run() -> void:
	await spawn_game()
	await lane_cases()
	await wall_case()
	await cooperative_case()
	game.queue_free()
	await frames()
	await create_timer(0.25).timeout
	print("ABYSS GLAIVE GUIDE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
