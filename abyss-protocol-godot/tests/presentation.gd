extends SceneTree
## Integration between painted weapons, floor physics, occlusion, and native HUD.

var game
var checks := 0
var failures: Array[String] = []

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

func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/qa"))
	root.get_texture().get_image().save_png("res://builds/qa/" + name + ".png")

func clear_shots() -> void:
	for shot in game.get_node("World/Projectiles").get_children():
		shot.get_parent().remove_child(shot)
		shot.queue_free()

func attack_warnings() -> void:
	# Test actual damage against the polygon sent to CanvasItem, including the
	# previously unmarked annulus (85..105) and side angles (1..1.47 radians).
	var enemy = game.spawn_enemy("stalker", Vector2(800, 525))
	enemy.set_physics_process(false)
	var points := [Vector2(95, 0), Vector2.from_angle(1.2) * 70,
		Vector2(104, 0), Vector2(110, 0), Vector2.from_angle(1.52) * 70, Vector2(-70, 0)]
	for heading in range(8):
		enemy.committed_direction = Vector2.from_angle(heading * TAU / 8.0)
		var polygon: PackedVector2Array = enemy.melee_warning_points()
		for i in range(points.size()):
			var offset: Vector2 = points[i].rotated(enemy.committed_direction.angle())
			var marked := Geometry2D.is_point_in_polygon(offset, polygon)
			check(marked == (i < 3), "Melee warning covers true reach and side angles in heading %d sample %d" % [heading, i])
			game.player.position = enemy.position + offset
			game.player.hp = game.player.max_hp
			game.player.invulnerable = 0
			game.player.parry_left = 0
			enemy.release_attack()
			check((game.player.hp < game.player.max_hp) == marked, "Actual hit agrees with visible melee sector")
	game.player.hp = game.player.max_hp
	game.player.invulnerable = 0
	game.player.position = Vector2(895, 525)
	enemy.committed_direction = Vector2.RIGHT
	enemy.attacking = true
	enemy.windup = 0.3
	enemy.queue_redraw()
	game.shake = 0
	await frames(30)
	await snapshot("melee-warning")
	enemy.queue_free()
	await frames()
	for spec in [["drone", 0, 1.0, 1], ["warden", 0, 1.0, 5], ["warden", 1, 1.0, 0], ["boss", 0, 0.75, 12], ["boss", 0, 0.4, 16]]:
		clear_shots()
		enemy = game.spawn_enemy(spec[0], Vector2(800, 390))
		enemy.set_physics_process(false)
		enemy.pattern = spec[1]
		enemy.hp = enemy.max_hp * spec[2]
		enemy.committed_direction = Vector2.DOWN
		enemy.attacking = true
		enemy.windup = 0.4
		enemy.queue_redraw()
		game.player.position = Vector2(930, 660)
		game.player.invulnerable = 0
		var directions: PackedVector2Array = enemy.warning_shot_directions()
		check(directions.size() == spec[3], "Warning uses correct shot count for %s phase %s" % [spec[0], spec[2]])
		await frames(30)
		if spec[0] in ["warden", "boss"]:
			check(str(enemy.ATTACK_LABELS[enemy.next_attack()]) in game.hud.boss_name.text, "Boss HUD describes the attack being prepared")
		await snapshot("warning-%s-%d-%d" % [spec[0], spec[1], spec[3]])
		enemy.release_attack()
		var shots: Array[Node] = game.get_node("World/Projectiles").get_children()
		if spec[3] == 0:
			check(shots.size() == 3, "Ground warning is followed by three actual zones")
			for shot in shots:
				check(shot.get_script() == game.HAZARD and shot.elapsed == 0.0 and shot.delay >= 0.9, "Targeted ground zone gets its full escape warning after placement")
		else:
			check(shots.size() == directions.size(), "Release count matches the warned rays")
			for i in range(shots.size()):
				check(shots[i].direction.distance_to(directions[i]) < 0.001, "Actual projectile follows its warned direction")
		clear_shots()
		enemy.queue_free()
		await frames()
	game.active_boss = null

func run() -> void:
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	game.narrative_enabled = false
	root.add_child(game)
	game.start_run(719)
	game.player.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	await frames()
	var weapon = game.player.weapon
	for id in ["rifle", "scatter", "rail", "qbow", "lbow", "sbow", "ember", "frost", "glaive", "prism"]:
		weapon.equip(id)
		for heading in range(8):
			game.player.aim = Vector2.from_angle(heading * TAU / 8.0)
			game.player.slash_cooldown = 0
			weapon.active_glaive = null
			check(weapon.fire(1.0), id + " fires in heading " + str(heading))
			var painted_tip := Vector2(42, 0)
			if weapon.definition.family == "FIREARMS":
				var spec: Dictionary = weapon.ART.GUN_SPRITES[id]
				painted_tip = Vector2(spec.muzzle[0] - spec.grip[0], spec.muzzle[1] - spec.grip[1]).rotated(-spec.angle) * spec.scale * weapon.ART.ART_SCALE
			elif weapon.definition.family == "ARCHERY":
				weapon.charge = float(weapon.definition.get("charge", 0.0))
				painted_tip = weapon.bow_pose().nock + Vector2(34, 0)
				weapon.charge = 0
			elif id == "glaive":
				painted_tip = Vector2(18, 0)
			elif id == "prism":
				painted_tip = Vector2(37, 0)
			for shot in game.get_node("World/Projectiles").get_children():
				check((shot.global_position + shot.visual_offset).distance_to(weapon.to_global(painted_tip)) < 0.1, id + " originates at painted tip; pellets share the muzzle")
				check(is_equal_approx(shot.global_position.distance_to(game.player.global_position), 28.0), id + " keeps existing ground collision origin")
				shot.get_parent().remove_child(shot)
				shot.queue_free()
		await frames()
	# Raised equipment must fade only when the character passes behind it.
	var prop = game.arena.scenery.get_child(0)
	game.player.position = prop.global_position - Vector2(0, 15)
	await frames(20)
	check(prop.opacity < 0.5, "Foreground equipment reveals the player behind it")
	game.player.position = prop.global_position + Vector2(0, 50)
	await frames(20)
	check(prop.opacity > 0.95, "Equipment becomes solid again in front of the player")
	# Camera bounds keep the player's body out of the HUD at both vertical limits.
	for point in [Vector2(800, 70), Vector2(800, 980)]:
		game.player.position = point
		game.camera.position = point
		game.camera.reset_smoothing()
		await frames(12)
		var screen: Vector2 = game.player.get_global_transform_with_canvas().origin
		check(screen.y > 170 and screen.y < 710, "Camera keeps edge movement in the usable combat area")
	await attack_warnings()
	game.next_room(game.ROOMS.generate(game.run_length, "boss", game.rng))
	game.player.position = game.room_data.start
	game.player.set_physics_process(false)
	game.player.weapon.equip("rifle")
	var boss = game.active_boss
	boss.set_physics_process(false)
	boss.hp = boss.max_hp * 0.4
	game.announcement_left = 0
	await frames()
	check(game.hud.boss_panel.visible and "过载" in game.hud.boss_name.text, "Final boss exposes actual overdrive state")
	check(is_equal_approx(game.hud.boss_integrity.value, boss.hp), "Boss health matches damage state")
	game.spawn_hazard(game.player.position + Vector2(190, -80), 95, 22)
	game.player.aim = Vector2.UP
	game.player.slash_cooldown = 0
	game.player.weapon.fire()
	await frames(5)
	var boss_screen: Vector2 = boss.get_global_transform_with_canvas().origin
	check(boss_screen.y - 138 * game.camera.zoom.y > 165 and boss_screen.y + 120 * game.camera.zoom.y < 620, "Boss framing keeps its windup artwork below the HUD")
	await snapshot("boss-combat")
	game.player.position = Vector2(800, 980)
	boss.position = Vector2(800, 100)
	await frames(90)
	var player_screen: Vector2 = game.player.get_global_transform_with_canvas().origin
	boss_screen = boss.get_global_transform_with_canvas().origin
	check(player_screen.y < 736 and boss_screen.y - 138 * game.camera.zoom.y > 165, "Distant boss and player remain visible together: player=%s boss=%s zoom=%s" % [player_screen, boss_screen, game.camera.zoom])
	game.finish_run(true)
	await frames()
	await snapshot("victory")
	game.queue_free()
	await frames(5)
	print("ABYSS PRESENTATION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
