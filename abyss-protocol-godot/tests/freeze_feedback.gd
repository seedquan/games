extends SceneTree
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
	game.coop.weapons.assign(["frost", "storm"])
	game.start_run(939)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	for member in game.team():
		member.set_physics_process(false)
		member.position = Vector2(750 + member.seat * 100, 700)
	game.elapsed = 60
	game.announcement_left = 0
	var targets := []
	for point in [Vector2(550, 450), Vector2(710, 450), Vector2(870, 450), Vector2(1030, 450)]:
		var enemy = game.spawn_enemy("stalker", point)
		enemy.hp = 10000
		enemy.max_hp = 10000
		enemy.set_physics_process(false)
		targets.append(enemy)
	await frames()
	return targets

func state_cases(t: Array) -> void:
	var enemy = t[0]
	check(enemy.ice_marker_level() == 0, "No ice marker on an untouched enemy")
	game.companion.weapon_hit(enemy, 1, Vector2.ZERO, "shock")
	check(enemy.frozen > 0 and enemy.ice_marker_level() == 0 and not enemy.freeze_outline_visible(), "Electric stagger cannot look like a completed ice freeze")
	for i in range(1, 4):
		game.player.weapon_hit(enemy, 1, Vector2.ZERO, "ice")
		check(enemy.ice_marker_level() == i, "Real ice hits reach visible stage %d" % i)
	check(enemy.freeze_outline_visible(), "Third ice hit has the real frozen outline")
	var before := var_to_bytes([enemy.hp, enemy.ice_frozen_left, enemy.chill_stacks, game.rng.state, game.profile.checkpoint])
	for i in range(20):
		enemy.ice_marker_level()
		enemy.ice_marker_rect()
		enemy.freeze_outline_visible()
	check(before == var_to_bytes([enemy.hp, enemy.ice_frozen_left, enemy.chill_stacks, game.rng.state, game.profile.checkpoint]), "Rendering queries do not change combat, RNG or saves")
	enemy.shock_guard = 0
	game.companion.weapon_hit(enemy, 1, Vector2.ZERO, "shock")
	check(enemy.ice_marker_level() == 3, "Frost conduction preserves the frozen marker")
	game.companion.weapon_hit(enemy, 1, Vector2.ZERO, "fire")
	check(enemy.ice_marker_level() == 0 and not enemy.freeze_outline_visible(), "Thermal shatter removes the frozen symbol")
	game.player.weapon_hit(enemy, 1, Vector2.ZERO, "ice")
	enemy.chill_left = 0.01
	enemy._physics_process(0.02)
	check(enemy.ice_marker_level() == 0, "Expired chill hides its partial marker")
	enemy.freeze_for(0.01)
	enemy._physics_process(0.02)
	check(enemy.ice_marker_level() == 0 and not enemy.freeze_outline_visible(), "Natural thaw removes the frozen marker")
	game.player.position = enemy.position + Vector2(0, 200)
	game.player.try_freeze()
	check(enemy.ice_marker_level() == 3, "Nova uses the same frozen symbol without needing three hits")
	var boss = game.spawn_enemy("warden", Vector2(800, 500))
	boss.set_physics_process(false)
	boss.ice_guard_left = 1.0
	for i in range(3): boss.apply_element("ice", 1)
	check(boss.ice_marker_level() == 0 and not boss.freeze_outline_visible(), "Resisting guardian never advertises an unsuccessful freeze")
	boss.apply_element("ice", 1)
	check(boss.ice_marker_level() == 1, "A resisting guardian may still show real partial chill")
	game.campaign_version = 1
	check(enemy.ice_marker_level() == 0, "Legacy keeps its original status presentation")
	enemy.ice_frozen_left = 0
	enemy.frozen = 0.2
	check(enemy.freeze_outline_visible(), "Legacy keeps the original generic control hexagon")
	game.campaign_version = 2
	enemy.freeze_for(1)
	enemy.take_damage(100000, Vector2.ZERO)
	check(enemy.ice_marker_level() == 0 and not enemy.freeze_outline_visible(), "Defeated enemies cannot retain a frozen symbol")

func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/qa")
	check(root.get_texture().get_image().save_png("res://builds/qa/freeze-" + name + ".png") == OK, "Save native frozen-state comparison")

func presentation_cases() -> void:
	var t := await setup()
	game.set_process(false)
	game.camera.position = Vector2(800, 550)
	game.camera.position_smoothing_enabled = false
	t[0].apply_element("shock", 1)
	for i in range(1, 4):
		for j in range(i): game.player.weapon_hit(t[i], 1, Vector2.ZERO, "ice")
	# Both states share the narrow space above a target without hiding health.
	t[2].apply_element("poison", 1)
	t[3].apply_element("poison", 1)
	game.settings.values.flash = 0
	for enemy in t: enemy._physics_process(0.01)
	check(t[0].get_node("Sprite").modulate != t[3].get_node("Sprite").modulate, "Stagger and actual ice use distinct body colors even with flash disabled")
	for dimensions in [Vector2i(960, 600), Vector2i(2560, 1440)]:
		root.size = dimensions
		for zoom in [1.0, 0.6]:
			game.camera.zoom = Vector2.ONE * zoom
			game.camera.force_update_scroll()
			for enemy in t:
				var rect: Rect2 = enemy.ice_marker_rect()
				check(is_equal_approx(rect.size.x * zoom, 64), "Co-op camera keeps the ice slots legible")
				check(rect.end.y < -72, "Ice marker leaves enemy health visible")
				if enemy.poison_marker_level() > 0: check(not rect.intersects(enemy.poison_marker_rect()), "Ice and poison markers never overlap")
				enemy.queue_redraw()
			await snapshot("states-%d-%.1f" % [dimensions.x, zoom])
	check(t[0].ICE_METER.get_size() == Vector2(192, 24), "All three original SVG states are imported")
	game.show_menu("paused")
	t[3].set_physics_process(true)
	var before := var_to_bytes(t.map(func(e): return [e.ice_frozen_left, e.chill_left, e.hp]))
	await frames(15)
	check(before == var_to_bytes(t.map(func(e): return [e.ice_frozen_left, e.chill_left, e.hp])), "Pause preserves ice state and marker together")
	var frozen_left: float = t[3].ice_frozen_left
	game.resume_run()
	await frames()
	check(t[3].ice_frozen_left < frozen_left and t[3].ice_marker_level() == 3, "Resume advances the real freeze timer while its marker remains valid")
	t[3].set_physics_process(false)
	game.open_help()
	await frames()
	var guide = game.hud.menu_margin.find_child("FreezeGuide", true, false)
	check(is_instance_valid(guide) and guide.texture == t[0].ICE_METER, "Guide shares all three live marker frames")
	if is_instance_valid(guide):
		guide.get_parent().get_children()[-1].grab_focus()
		await snapshot("guide")
	game.campaign_version = 1
	game.hud.show_menu("help")
	check(game.hud.menu_margin.find_child("FreezeGuide", true, false) == null, "Legacy guide does not advertise new markers")
	game.start_run(940)
	check(get_nodes_in_group("enemies").all(func(e): return e.ice_marker_level() == 0), "Restart clears all ice feedback")

func observer_cases() -> void:
	var t := await setup()
	var observer = preload("res://tests/freeze_observer.gd").new()
	t[0].freeze_for(1.8)
	t[0].shock_guard = 0.8
	var state := var_to_bytes([t[0].hp, t[0].ice_frozen_left, t[0].shock_guard, game.rng.state])
	observer.observe(game)
	check(observer.summary.freeze_starts == 1 and observer.summary.starts_with_neighbour == 1 and observer.summary.starts_shock_guarded == 1, "Observer separates freeze start, proximity and shock guard")
	check(state == var_to_bytes([t[0].hp, t[0].ice_frozen_left, t[0].shock_guard, game.rng.state]), "Freeze observer never changes the sampled state")
	t[0].shock_guard = 0
	observer.observe(game)
	check(observer.summary.freeze_starts == 1 and observer.summary.frames_shock_ready_with_neighbour == 1, "A held freeze is one start with a later ready frame")
	for i in range(1, 4): t[i].position += Vector2(2000, 0)
	observer.observe(game)
	check(observer.summary.frames_with_neighbour == 2 and observer.summary.frozen_enemy_frames == 3, "Observer counts isolated freeze frames separately")
	t[0].ice_frozen_left = 0
	observer.observe(game)
	check(observer.previous.is_empty(), "Observer releases expired entity identities")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	game.narrative_enabled = false
	root.add_child(game)
	await frames()
	var t := await setup()
	check(t[0].has_method("ice_marker_level") and t[0].has_method("freeze_outline_visible"), "Rendering must distinguish actual ice freeze from electric stagger")
	if t[0].has_method("ice_marker_level"):
		await state_cases(t)
		await presentation_cases()
	await observer_cases()
	game.queue_free()
	await create_timer(0.2).timeout
	print("ABYSS FREEZE FEEDBACK: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
