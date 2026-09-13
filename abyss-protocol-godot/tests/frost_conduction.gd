extends SceneTree
## Frozen targets relay electricity through real weapon/element paths.
var game
var checks := 0
var failures := 0
var conductions := 0

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

func setup(weapon := "rifle", cooperative := false) -> Array:
	game.coop.enabled = cooperative
	game.coop.devices.assign([3, 7] if cooperative else [-1, -1])
	game.coop.weapons.assign(["frost", "storm"])
	game.selected_weapon = weapon
	game.configure_input()
	game.start_run(932)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	for member in game.team():
		member.set_physics_process(false)
		member.position = Vector2(800, 650 + member.seat * 100)
		member.aim = Vector2.RIGHT
		member.hp = 80
	var targets := []
	for point in [Vector2(900, 650), Vector2(1000, 650), Vector2(950, 790), Vector2(1100, 630), Vector2(1130, 650)]:
		var enemy = game.spawn_enemy("stalker", point)
		enemy.set_physics_process(false)
		enemy.hp = 10000
		enemy.max_hp = 10000
		targets.append(enemy)
	await frames()
	return targets

func damage_cases() -> void:
	var t := await setup()
	game.player.enchantments = {"shock": 1, "leech": 1}
	for i in range(2): t[0].apply_element("ice", 1)
	t[0].frozen = 0.22
	game.player.weapon_hit(t[0], 20, Vector2.ZERO)
	check(t[1].hp == 10000, "Chill stacks and ordinary stagger cannot replace an actual ice freeze")
	t[0].shock_guard = 0
	t[0].freeze_for(1.8)
	t[1].freeze_for(1.8)
	t[1].apply_element("poison", 20)
	var hp: float = game.player.hp
	game.player.weapon_hit(t[0], 20, Vector2.ZERO)
	check(is_equal_approx(t[0].hp, 9960), "Conduction adds no extra damage to its source")
	check(is_equal_approx(t[1].hp, 9991) and is_equal_approx(t[2].hp, 9991), "Frozen shock hits the two nearest neighbours for 45 percent")
	check(t[3].hp == 10000 and t[4].hp == 10000, "Only two neighbours are selected; distant enemies stay safe")
	check(t[0].ice_frozen_left == 1.8 and t[0].frozen == 1.8, "Conduction preserves the source freeze")
	check(t[1].poison_stacks == 1 and t[1].shock_guard == 0 and t[1].ice_frozen_left == 1.8, "Relayed damage cannot apply runes, consume states or recurse")
	check(is_equal_approx(game.player.hp - hp, 1.2), "Leech only counts the original weapon hit")
	game.player.weapon_hit(t[0], 20, Vector2.ZERO)
	check(is_equal_approx(t[1].hp, 9991), "The 0.8-second per-target shock guard prevents repeated procs")
	# Let real physics expire the guard while the freeze still holds.
	t[0].set_physics_process(true)
	await frames(49)
	t[0].set_physics_process(false)
	game.player.weapon_hit(t[0], 20, Vector2.ZERO)
	check(is_equal_approx(t[1].hp, 9982), "A later shock can conduct again while the freeze persists")
	for level in range(1, 5):
		t = await setup()
		t[0].freeze_for(1.8)
		t[0].apply_element("shock", 20 * game.PROGRESSION.element_power(level), level)
		check(is_equal_approx(10000 - t[1].hp, 9 * game.PROGRESSION.element_power(level)), "Rank %d scales the real conduction damage" % level)
	# A lethal electric hit retains the frozen target's final relay.
	t = await setup()
	t[0].hp = 5
	t[0].freeze_for(1.8)
	game.player.enchantments = {"shock": 1}
	game.player.weapon_hit(t[0], 20, Vector2.ZERO)
	check(t[0].dead and is_equal_approx(t[1].hp, 9991), "Lethal shock can conduct a stored freeze")
	t = await setup()
	t[0].hp = 5
	t[0].freeze_for(1.8)
	t[0].shock_guard = 0.4
	game.player.enchantments = {"shock": 1}
	game.player.weapon_hit(t[0], 20, Vector2.ZERO)
	check(t[0].dead and t[1].hp == 10000, "Lethal contact cannot bypass an existing shock guard")

func boundary_cases() -> void:
	var t := await setup()
	t[0].freeze_for(1.8)
	t[1].position = t[0].position + Vector2(220, 0)
	t[2].position = t[0].position + Vector2(220.1, 0)
	t[3].position = Vector2(1400, 850)
	t[0].apply_element("shock", 20)
	check(t[1].hp == 9991 and t[2].hp == 10000, "Conduction includes 220 range and excludes a genuine gap")
	t = await setup()
	t[0].position = Vector2(420, 290)
	t[1].position = Vector2(420, 420)
	t[2].position = Vector2(550, 270)
	t[0].freeze_for(1.8)
	check(not game.has_sight(t[0].position, t[1].position), "Cover fixture blocks the frozen source's view")
	t[0].apply_element("shock", 20)
	check(t[1].hp == 10000 and t[2].hp == 9991, "Only visible neighbours receive a relay")
	t = await setup()
	game.campaign_version = 1
	t[0].freeze_for(1.8)
	t[0].apply_element("shock", 20, 3)
	check(t[1].hp == 10000, "Legacy campaign gains no new reaction")
	game.campaign_version = 2
	# Combining fire and electricity keeps the existing shatter, after the relay.
	t = await setup()
	t[0].freeze_for(1.8)
	game.player.enchantments = {"shock": 1, "fire": 1}
	game.player.weapon_hit(t[0], 20, Vector2.ZERO)
	check(t[0].ice_frozen_left == 0 and is_equal_approx(t[1].hp, 9977), "Electricity relays then fire shatters once when both are equipped")
	t = await setup("frost", true)
	for i in range(3): game.player.weapon_hit(t[0], 1, Vector2.ZERO, "ice")
	game.companion.weapon_hit(t[0], 20, Vector2.ZERO, "shock")
	check(t[0].ice_frozen_left > 0 and is_equal_approx(t[1].hp, 9991), "Ice and electric partners can relay with innate elements")
	check(game.player.hp == 80 and game.companion.hp == 80, "Neither friendly actor takes conduction damage")
	var boss = game.spawn_enemy("warden", Vector2(950, 680))
	boss.set_physics_process(false)
	for i in range(3): boss.apply_element("ice", 1)
	boss.apply_element("shock", 20)
	check(boss.ice_frozen_left > 0 and boss.ice_guard_left == 2.2 and boss.shock_guard == 0.8, "Guardian control guards survive conduction")

func weapon_cases() -> void:
	for form in game.WEAPONS.FORMS:
		var t := await setup(form.id)
		t[0].freeze_for(10)
		game.player.enchantments = {"shock": 1}
		var before := conductions
		game.player.weapon.fire(1.0 if form.has("charge") else -1.0)
		await frames(70)
		check(conductions > before, form.id + " conducts through its actual attack family")
	# Paired input prepares frost and then casts electricity; no skill calls.
	var t := await setup("frost", true)
	for actor in game.team():
		actor.set_physics_process(true)
		var direction: Vector2 = actor.position.direction_to(t[0].position)
		Input.action_press(actor.action("aim_right"), direction.x)
		if direction.y < 0: Input.action_press(actor.action("aim_up"), -direction.y)
	await frames(2)
	Input.action_press(game.player.action("slash"))
	for i in range(90):
		await frames(1)
		if t[0].ice_frozen_left > 0: break
	Input.action_release(game.player.action("slash"))
	check(t[0].ice_frozen_left > 0, "First seat's held frost attacks prepare a freeze")
	var before := conductions
	Input.action_press(game.companion.action("slash"))
	await frames(3)
	Input.action_release(game.companion.action("slash"))
	check(conductions > before, "Second seat's electric attack conducts the partner's freeze")
	for actor in game.team():
		Input.action_release(actor.action("aim_right"))
		Input.action_release(actor.action("aim_up"))
		actor.set_physics_process(false)

func menu_cases() -> void:
	await setup()
	var member = game.player
	var frozen_state := var_to_bytes([member.enchantments, member.damage, game.rng.state, game.profile.checkpoint])
	var shock: String = game.hud.upgrade_details(game.PROGRESSION.rune("shock"), member)
	check("选后可用" in shock and "霜链" in shock and "冰冻新星" in shock, "Any weapon can preview its nova plus shock combination")
	check(frozen_state == var_to_bytes([member.enchantments, member.damage, game.rng.state, game.profile.checkpoint]), "Combo previews are read-only")
	member.weapon.equip("storm")
	check("霜链" in game.hud.upgrade_details(game.PROGRESSION.rune("ice"), member), "Innate electricity enables the ice reward combo")
	member.enchantments = {"shock": 3}
	shock = game.hud.upgrade_details(game.PROGRESSION.rune("shock"), member)
	check("已有联动" in shock and "选后可用" not in shock, "Capped shock describes an existing combo")
	check(game.BUILD_INFO.has_reaction(member) and game.BUILD_INFO.synergies(member).any(func(s): return "霜链" in s and "220" in s and "45%" in s), "Build overview explains the actual conduction rules")
	await setup("frost", true)
	member = game.player
	check("队友接力" in game.hud.upgrade_details(game.PROGRESSION.rune("ice"), member), "Ice seat can preview its electric partner's relay")
	member.enchantments = {"fire": 1, "shock": 1}
	check("热冲击 / 霜链" in game.hud.upgrade_details(game.PROGRESSION.rune("ice"), member), "A mixed build explains both ways to use frozen targets")
	for dimensions in [Vector2i(960, 600), Vector2i(2560, 1440)]:
		root.size = dimensions
		game.boon_choices = [game.PROGRESSION.rune("ice"), game.PROGRESSION.rune("shock"), game.PROGRESSION.rune("fire")]
		for state in ["reward", "shop"]:
			game.set_shop_stock("shock")
			game.show_menu(state)
			await frames(4)
			for option in game.hud.menu_buttons():
				check(game.get_viewport_rect().grow(1).encloses(option.get_global_rect()), "Conduction choice fits " + state + str(dimensions))
				for text in option.find_children("*", "Label", true, false):
					check(option.get_global_rect().grow(1).encloses(text.get_global_rect()), "Conduction description fits its card")
			if DisplayServer.get_name() != "headless" and dimensions.x == 960 and state == "shop":
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute("res://builds/qa")
				check(root.get_texture().get_image().save_png("res://builds/qa/frost-conduction-shop.png") == OK, "Save small-window shop layout")
		game.open_build()
		await frames(4)
		for button in game.hud.menu_buttons():
			check(game.get_viewport_rect().grow(1).encloses(button.get_global_rect()), "Three-row combo overview keeps navigation on screen")
		if DisplayServer.get_name() != "headless" and dimensions.x == 960:
			var scroll: ScrollContainer = game.hud.menu_margin.find_child("BuildScroll", true, false)
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
			await frames(4)
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://builds/qa/frost-conduction-build.png") == OK, "Save small-window three-recipe overview")
		game.close_build()
	game.campaign_version = 1
	check("霜链" not in game.hud.upgrade_details(game.PROGRESSION.rune("shock"), member), "Legacy choice never promises conduction")
	check(not game.BUILD_INFO.synergies(member).any(func(s): return "霜链" in s), "Legacy overview retains old combinations")
	game.open_help()
	await frames()
	check(game.hud.menu_margin.find_child("ConductionGuide", true, false) == null, "Legacy guide hides the new recipe")

func presentation_cases() -> void:
	var t := await setup("storm")
	game.settings.values.flash = 0
	root.size = Vector2i(1280, 800)
	await frames(12)
	t[0].freeze_for(1.8)
	t[0].apply_element("shock", 20)
	var effects: Array = game.get_node("World/Effects").get_children().filter(func(n): return n.get_script() == game.EFFECT and n.reaction == "conduction")
	check(effects.size() == 1, "A relay creates one bounded visual object")
	if effects.is_empty(): return
	var trace = effects[0]
	check(trace.radius == 0 and trace.links.size() == 2, "Art draws only the two actual links, not a misleading area ring")
	check((trace.position + trace.links[0]).is_equal_approx(t[1].position + Vector2(0, -28)), "First link ends at the actual nearest target's raised body")
	check(trace.intensity == 0, "A zero-flash preference preserves static line geometry")
	game.show_menu("paused")
	await frames()
	var elapsed: float = trace.elapsed
	await frames(8)
	check(trace.elapsed == elapsed, "Pause freezes conduction traces")
	game.resume_run()
	if DisplayServer.get_name() != "headless":
		for enemy in t: enemy.queue_redraw()
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://builds/qa")
		check(root.get_texture().get_image().save_png("res://builds/qa/frost-conduction.png") == OK, "Save native zero-flash conduction evidence")
	await frames(40)
	check(not is_instance_valid(trace), "Conduction trace retires after resume")
	game.open_help()
	await frames()
	var guide = game.hud.menu_margin.find_child("ConductionGuide", true, false)
	check(is_instance_valid(guide) and guide.texture.region == Rect2(0, 144, 480, 72), "Guide reuses the exact conduction row from the combo atlas")
	if DisplayServer.get_name() != "headless" and is_instance_valid(guide):
		guide.get_parent().get_children()[-1].grab_focus()
		await frames(8)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://builds/qa/frost-conduction-guide.png") == OK, "Save native recipe guide evidence")
	game.start_run(934)
	check(game.get_node("World/Effects").get_child_count() == 0, "Restart clears all conduction traces")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	await frames()
	game.get_node("World/Effects").child_entered_tree.connect(func(n):
		if n.get_script() == game.EFFECT and n.reaction == "conduction": conductions += 1)
	await damage_cases()
	await boundary_cases()
	await weapon_cases()
	await menu_cases()
	await presentation_cases()
	game.queue_free()
	await create_timer(0.2).timeout
	print("ABYSS FROST CONDUCTION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
