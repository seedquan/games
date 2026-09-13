extends SceneTree
## Visible stacks share the same live enemy state consumed by fire reactions.
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

func frames(count := 3) -> void:
	for i in range(count): await physics_frame
	await process_frame

func setup() -> Array:
	game.coop.enabled = true
	game.coop.devices.assign([3, 7])
	game.coop.weapons.assign(["rifle", "ember"])
	game.start_run(924)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	for member in game.team():
		member.set_physics_process(false)
		member.position = Vector2(750 + member.seat * 100, 650)
	game.player.enchantments = {"poison": 1}
	game.announcement_left = 0
	game.elapsed = 60
	var targets := []
	for point in [Vector2(650, 450), Vector2(800, 450), Vector2(950, 450)]:
		var enemy = game.spawn_enemy("stalker", point)
		enemy.hp = 10000
		enemy.max_hp = 10000
		enemy.set_physics_process(false)
		targets.append(enemy)
	await frames()
	return targets

func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/qa")
	check(root.get_texture().get_image().save_png("res://builds/qa/poison-" + name + ".png") == OK, "Save native status evidence")

func state_cases() -> void:
	var targets := await setup()
	var enemy = targets[1]
	check(enemy.has_method("poison_marker_level"), "Enemy exposes the stack count used by its poison marker")
	if not enemy.has_method("poison_marker_level"): return
	check(enemy.poison_marker_level() == 0, "An untouched enemy has no status badge")
	for count in range(1, 7):
		game.player.weapon_hit(enemy, 20, Vector2.ZERO)
		check(enemy.poison_marker_level() == count, "Actual poison hits advance visible stack " + str(count))
	game.player.weapon_hit(enemy, 20, Vector2.ZERO)
	check(enemy.poison_marker_level() == 6, "Additional hits refresh a capped six-stack marker")
	var state := var_to_bytes([enemy.hp, enemy.poison_stacks, enemy.poison_left, game.rng.state, game.profile.checkpoint])
	for i in range(20): enemy.poison_marker_level()
	check(state == var_to_bytes([enemy.hp, enemy.poison_stacks, enemy.poison_left, game.rng.state, game.profile.checkpoint]), "Rendering queries cannot deal damage, consume stacks, roll RNG or save")
	var neighbour_hp: float = targets[2].hp
	game.companion.weapon_hit(enemy, 20, Vector2.ZERO, "fire")
	check(enemy.poison_marker_level() == 0 and targets[2].hp < neighbour_hp, "Fire relay consumes the marker exactly when its real blast lands")
	for i in range(2): game.player.weapon_hit(enemy, 20, Vector2.ZERO)
	neighbour_hp = targets[2].hp
	game.companion.weapon_hit(enemy, 20, Vector2.ZERO, "fire")
	check(enemy.poison_marker_level() == 2 and targets[2].hp == neighbour_hp, "Two-stack fire cannot advertise or trigger a primed blast")
	game.player.weapon_hit(enemy, 20, Vector2.ZERO)
	check(enemy.poison_marker_level() == 3, "Third hit reaches the flame-marked frame")
	enemy.poison_left = 0.01
	enemy._physics_process(0.02)
	enemy._physics_process(0.02)
	check(enemy.poison_marker_level() == 0, "Normal poison expiry clears the visual with the live stacks")
	for i in range(3): game.player.weapon_hit(enemy, 20, Vector2.ZERO)
	game.campaign_version = 1
	check(enemy.poison_marker_level() == 0, "Legacy rules never show the modern three-stack marker")
	game.campaign_version = 2
	enemy.take_damage(100000, Vector2.ZERO)
	check(enemy.poison_marker_level() == 0, "A defeated enemy has no remaining marker")

func presentation_cases() -> void:
	var targets := await setup()
	if not targets[0].has_method("poison_marker_level"): return
	game.set_process(false)
	game.camera.position = Vector2(800, 550)
	game.camera.position_smoothing_enabled = false
	for index in range(3):
		for i in range([2, 3, 6][index]): game.player.weapon_hit(targets[index], 1, Vector2.ZERO)
		check(targets[index].poison_marker_level() == [2, 3, 6][index], "Capture uses actual hits for two, three and six layers")
	check(targets[0].POISON_METER.get_size() == Vector2(528, 24), "All six original SVG frames are imported")
	game.settings.values.flash = 0.0
	game.settings.values.high_contrast = true
	game.hud.apply_text_contrast()
	for dimension in [Vector2i(1280, 800), Vector2i(2560, 1440)]:
		root.size = dimension
		for zoom in [1.0, 0.6]:
			game.camera.zoom = Vector2.ONE * zoom
			game.camera.force_update_scroll()
			for enemy in targets:
				enemy.queue_redraw()
				var rect: Rect2 = enemy.poison_marker_rect()
				check(is_equal_approx(rect.size.x * zoom, 88.0), "Zoomed co-op preserves logical slot width")
				check(rect.end.y < -72, "Status badge leaves the enemy health bar unobscured")
			await snapshot("stacks-%d-%.1f" % [dimension.x, zoom])
	game.show_menu("paused")
	var before := var_to_bytes(targets.map(func(enemy): return [enemy.poison_stacks, enemy.poison_left, enemy.hp]))
	await frames(15)
	check(before == var_to_bytes(targets.map(func(enemy): return [enemy.poison_stacks, enemy.poison_left, enemy.hp])), "Pause keeps status and combat frozen together")
	game.open_help()
	await frames()
	var guide: TextureRect = game.hud.menu_margin.find_child("PoisonGuide", true, false)
	check(is_instance_valid(guide) and guide.texture.region == Rect2(176, 0, 88, 24), "Guide uses the exact three-stack gameplay symbol")
	if is_instance_valid(guide):
		var scroll = guide.get_parent().get_parent().get_parent()
		scroll.ensure_control_visible(guide)
		await snapshot("guide")
	game.campaign_version = 1
	game.hud.show_menu("help")
	check(game.hud.menu_margin.find_child("PoisonGuide", true, false) == null, "Legacy guide cannot advertise a three-stack threshold")
	game.start_run(925)
	check(get_nodes_in_group("enemies").all(func(enemy): return enemy.poison_marker_level() == 0), "New chamber has no stale status badges")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	game.narrative_enabled = false
	root.add_child(game)
	await frames()
	await state_cases()
	await presentation_cases()
	game.queue_free()
	await create_timer(0.2).timeout
	print("ABYSS POISON FEEDBACK: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
