extends "res://tests/weapon_mods.gd"
## Actual swept blade contacts, including edge hits, fast steps and solid cover.

func edge_contacts() -> void:
	for heading in range(8):
		var direction := Vector2.from_angle(heading * PI / 4)
		for gap in [18.0, 25.0]:
			var offset: Vector2 = direction * 110 + direction.orthogonal() * (19 + gap)
			var targets := await reset_case("glaive", "", [offset])
			game.player.aim = direction
			fire()
			var shot = game.get_node("World/Projectiles").get_child(0)
			check(shot.get_node("Collision").shape.radius == 21, "Modern blade uses its visible radius")
			await frames(15)
			check((targets[0].hp < 10000) == (gap < 21), "Blade edge contact / real gap at heading %d, gap %.0f" % [heading, gap])
	var targets := await reset_case("glaive", "", [Vector2(110, 37)])
	game.campaign_version = 1
	game.player.weapon.equip("glaive")
	fire()
	var shot = game.get_node("World/Projectiles").get_child(0)
	check(shot.get_node("Collision").shape.radius == 7, "Legacy blade retains its saved campaign contact rule")
	await frames(15)
	check(targets[0].hp == 10000, "Legacy edge remains unchanged")
	await reset_case("rifle", "", [])
	fire()
	shot = game.get_node("World/Projectiles").get_child(0)
	check(shot.get_node("Collision").shape.radius == 7, "Glaive shape does not mutate shared bullet resources")

func swept_contacts() -> void:
	var targets := await reset_case("glaive", "", [Vector2(125, 37), Vector2(195, 37)])
	fire()
	var shot = game.get_node("World/Projectiles").get_child(0)
	shot.set_physics_process(false)
	shot.speed = 18000
	shot._physics_process(1.0 / 60)
	for target in targets:
		check(is_equal_approx(10000 - target.hp, 26 * 1.4), "Swept edge hits each crossed body exactly once in one fast step")
	shot.begin_return()
	shot._physics_process(1.0 / 60)
	for target in targets:
		check(is_equal_approx(10000 - target.hp, 26 * 1.4 * 2), "Return sweep can hit the same edge once again")
	# A newly spawned blade may already overlap a body; cast_motion alone skips it.
	targets = await reset_case("glaive", "", [Vector2(28, 32)])
	fire()
	shot = game.get_node("World/Projectiles").get_child(0)
	shot.set_physics_process(false)
	shot._physics_process(1.0 / 60)
	check(is_equal_approx(10000 - targets[0].hp, 26 * 1.4), "Initial edge overlap still resolves one hit")

func cover_contacts() -> void:
	var targets := await reset_case("glaive", "", [Vector2(200, 0)])
	# This lip touches the blade edge but not its center ray.
	game.arena.add_wall(Rect2(915, 668, 6, 60))
	await frames()
	fire()
	var shot = game.get_node("World/Projectiles").get_child(0)
	shot.set_physics_process(false)
	shot.speed = 18000
	shot._physics_process(1.0 / 60)
	check(shot.returning and not shot.spent, "Outbound edge touching a wall starts the return")
	check(targets[0].hp == 10000, "Swept blade cannot hit a target beyond the first wall")
	check(shot.position.x < 915, "Blade stops on the near side of the cover lip")
	shot._physics_process(1.0 / 60)
	check(targets[0].hp == 10000, "Wall turn does not hit through cover on the next tick")
	targets = await reset_case("glaive", "", [Vector2(70, 0)])
	game.arena.add_wall(Rect2(915, 620, 6, 60))
	await frames()
	fire()
	shot = game.get_node("World/Projectiles").get_child(0)
	shot.set_physics_process(false)
	shot.position = Vector2(1100, 650)
	shot.speed = 18000
	shot.begin_return()
	shot._physics_process(1.0 / 60)
	check(shot.spent and targets[0].hp == 10000, "Returning blade still stops at cover before a hidden target")

func native_contact_preview() -> void:
	if DisplayServer.get_name() == "headless": return
	root.size = Vector2i(1280, 800)
	var targets := await reset_case("glaive", "mod_focus", [Vector2(110, 37)])
	fire()
	var shot = game.get_node("World/Projectiles").get_child(0)
	shot.set_physics_process(false)
	shot.position = game.player.position + Vector2(96, 0)
	shot._physics_process(1.0 / 60)
	check(targets[0].hp < 10000, "Rendered blade edge deals its actual outbound hit")
	game.hud.update_status()
	await snapshot("glaive-contact")

func run() -> void:
	await spawn_game()
	await edge_contacts()
	await swept_contacts()
	await cover_contacts()
	await native_contact_preview()
	game.queue_free()
	await frames()
	# Let the Dummy mixer retire the final attack cue after scene teardown.
	await create_timer(0.25).timeout
	print("ABYSS GLAIVE CONTACT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
