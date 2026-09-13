extends SceneTree
## Controlled real-scene reactions; durable saves and human difficulty are separate.
var game
var checks := 0
var failures: Array[String] = []
var reaction_count := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count := 2) -> void:
	for i in range(count): await physics_frame
	await process_frame

func reset_case(weapon := "blade", version := 2, cooperative := false) -> Array:
	game.coop.enabled = cooperative
	game.coop.devices.assign([1, 3] if cooperative else [-1, -1])
	game.coop.weapons.assign([weapon, "ember"])
	game.configure_input()
	game.selected_weapon = weapon
	game.start_run(921)
	game.campaign_version = version
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	for member in game.team():
		member.set_physics_process(false)
		member.position = Vector2(800, 650)
		member.aim = Vector2.RIGHT
		member.hp = 80
	var targets := []
	for point in [Vector2(875, 650), Vector2(975, 650), Vector2(1075, 650)]:
		var enemy = game.spawn_enemy("stalker", point)
		# High-health stationary fixture isolates reactions from enemy movement.
		enemy.hp = 10000
		enemy.max_hp = 10000
		enemy.set_physics_process(false)
		targets.append(enemy)
	await frames()
	return targets

func thermal_cases() -> void:
	var targets := await reset_case()
	game.player.enchantments = {"fire": 1, "leech": 1}
	targets[0].freeze_for(1.8)
	targets[1].freeze_for(1.8)
	targets[1].apply_element("poison", 20)
	game.player.weapon_hit(targets[0], 20, Vector2.ZERO)
	check(is_equal_approx(targets[0].hp, 9966), "Thermal primary receives the hit plus one 70 percent reaction")
	check(is_equal_approx(targets[1].hp, 9986) and targets[2].hp == 10000, "Thermal burst damages nearby enemies but respects 150 range")
	check(targets[0].ice_frozen_left == 0 and targets[1].ice_frozen_left > 0, "Only the ignited freeze is consumed; splash cannot chain")
	check(targets[1].poison_stacks == 1 and targets[1].burn_left == 0, "Splash adds no elemental applications")
	check(is_equal_approx(game.player.hp, 81.2), "Leech uses direct damage once, never splash or reactions")
	game.player.weapon_hit(targets[0], 20, Vector2.ZERO)
	check(is_equal_approx(targets[1].hp, 9986), "Unfrozen targets cannot repeat thermal bursts")
	for node in game.get_node("World/Effects").get_children():
		if node.get_script() == game.EFFECT and node.reaction == "thermal":
			check(node.radius == 150 and node.position == targets[0].position, "Thermal art shares damage center and full radius")
	# The strike which defeats a frozen foe still has its promised area payoff.
	targets = await reset_case()
	game.player.enchantments = {"fire": 1}
	targets[0].hp = 10
	targets[0].freeze_for(1.8)
	game.player.weapon_hit(targets[0], 20, Vector2.ZERO)
	check(targets[0].dead and is_equal_approx(targets[1].hp, 9986), "A lethal direct fire strike still detonates a stored freeze")
	# Occlusion is measured from the detonating enemy, not from the shooter.
	targets = await reset_case()
	targets[0].position = Vector2(420, 290)
	targets[1].position = Vector2(420, 420)
	check(not game.has_sight(targets[0].position, targets[1].position), "Cover fixture actually blocks line of sight")
	targets[0].freeze_for(1.8)
	targets[0].apply_element("fire", 20)
	check(targets[1].hp == 10000, "Thermal area damage cannot cross solid cover")
	# A point on the drawn boundary is included, just outside it is excluded.
	targets = await reset_case()
	targets[1].position = targets[0].position + Vector2(150, 0)
	targets[2].position = targets[0].position + Vector2(150.1, 0)
	targets[0].freeze_for(1.8)
	targets[0].apply_element("fire", 20)
	check(targets[1].hp < 10000 and targets[2].hp == 10000, "Thermal geometry agrees with the visible boundary")

func combustion_cases() -> void:
	var targets := await reset_case()
	game.player.enchantments = {"fire": 1, "poison": 1}
	for hit in range(2):
		game.player.weapon_hit(targets[0], 20, Vector2.ZERO)
		check(targets[0].poison_stacks == hit + 1 and targets[1].hp == 10000, "Combined fire/poison keeps early poison stacks")
	game.player.weapon_hit(targets[0], 20, Vector2.ZERO)
	check(targets[0].poison_stacks == 0 and targets[0].poison_left == 0 and targets[0].poison_damage == 0, "Third combined hit consumes the complete poison charge")
	check(is_equal_approx(targets[0].hp, 9929.2) and is_equal_approx(targets[1].hp, 9989.2), "Three-stack combustion deals 54 percent to target and neighbours")
	check(targets[2].hp == 10000, "Combustion respects its 185 range")
	for tier in range(1, 4):
		targets = await reset_case()
		for i in range(6): targets[0].apply_element("poison", 20)
		game.player.enchantments = {"fire": tier}
		game.player.weapon_hit(targets[0], 20, Vector2.ZERO)
		var expected: float = 6 * 20 * game.PROGRESSION.element_power(tier) * 0.18
		check(is_equal_approx(10000 - targets[1].hp, expected), "Rank-%d fire increases real six-stack blast damage" % tier)
	targets = await reset_case()
	for i in range(3): targets[0].apply_element("poison", 20)
	targets[0].hp = 10
	game.player.enchantments = {"fire": 1}
	game.player.weapon_hit(targets[0], 20, Vector2.ZERO)
	check(targets[0].dead and is_equal_approx(targets[1].hp, 9989.2), "Lethal fire can ignite previously primed poison")

func coop_and_legacy_cases() -> void:
	var targets := await reset_case("frost", 2, true)
	for i in range(3): game.player.weapon_hit(targets[0], 1, Vector2.ZERO, "ice")
	check(targets[0].ice_frozen_left > 0, "One partner can prepare an innate ice freeze")
	game.companion.weapon_hit(targets[0], 20, Vector2.ZERO, "fire")
	check(is_equal_approx(targets[1].hp, 9986), "The other partner can detonate with innate fire")
	check(game.player.hp == 80 and game.companion.hp == 80, "Area reactions cannot hurt either friendly actor")
	var boss = game.spawn_enemy("warden", Vector2(950, 650))
	boss.set_physics_process(false)
	for i in range(3): boss.apply_element("ice", 1)
	check(boss.ice_guard_left == 2.2, "Guardian freeze guard starts normally")
	boss.apply_element("fire", 20)
	for i in range(3): boss.apply_element("ice", 1)
	check(boss.ice_frozen_left == 0 and boss.ice_guard_left == 2.2, "Shattering does not reset the guardian's freeze resistance")
	targets = await reset_case("blade", 1)
	game.player.enchantments = {"fire": 1, "poison": 1}
	targets[0].freeze_for(1.8)
	game.player.weapon_hit(targets[0], 20, Vector2.ZERO)
	check(is_equal_approx(targets[0].hp, 9962.4) and targets[0].poison_stacks == 0, "Legacy consumes its first poison stack and keeps old single-target damage")
	check(targets[1].hp == 10000, "Legacy reactions remain single-target")

func weapon_cases() -> void:
	for form in game.WEAPONS.FORMS:
		var targets := await reset_case(form.id)
		game.player.enchantments = {"fire": 1}
		targets[0].freeze_for(10)
		var before := reaction_count
		game.player.weapon.fire(1.0 if form.has("charge") else -1.0)
		await frames(70)
		check(reaction_count > before and targets[0].ice_frozen_left == 0, form.id + " triggers thermal reactions through its real attack path")

func native_capture() -> void:
	if DisplayServer.get_name() == "headless": return
	var targets := await reset_case("grav")
	game.player.enchantments = {"fire": 2, "poison": 2, "ice": 1}
	targets[0].freeze_for(1.8)
	for i in range(3): targets[0].apply_element("poison", 20)
	game.player.weapon_hit(targets[0], 40, Vector2.ZERO)
	for node in game.get_node("World/Effects").get_children():
		if node.get_script() == game.EFFECT and not node.reaction.is_empty():
			node.elapsed = 0.15
			node.set_process(false)
			node.queue_redraw()
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/qa")
	root.get_texture().get_image().save_png("res://builds/qa/element-reactions.png")
	game.open_build()
	await frames()
	var scroll: ScrollContainer = game.hud.menu_margin.find_child("BuildScroll", true, false)
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/qa/element-reactions-build.png")
	game.start_run(922)
	check(game.get_node("World/Effects").get_child_count() == 0, "Restart clears reaction visual nodes")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	game.narrative_enabled = false
	root.add_child(game)
	await frames()
	game.get_node("World/Effects").child_entered_tree.connect(func(node):
		if node.get_script() == game.EFFECT and not node.reaction.is_empty(): reaction_count += 1)
	await thermal_cases()
	await combustion_cases()
	await coop_and_legacy_cases()
	await weapon_cases()
	await native_capture()
	game.queue_free()
	# Let the audio server release the last pooled cue before engine shutdown.
	await create_timer(0.2).timeout
	print("ABYSS ELEMENT REACTIONS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
