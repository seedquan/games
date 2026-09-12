extends SceneTree
## Integration cases exercise each weapon in real scenes and the physics world.

const CATALOG = preload("res://scripts/weapons.gd")
var game
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
	await process_frame

func reset_case(id: String, points: Array) -> Array:
	game.selected_weapon = id
	game.start_run()
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	game.player.set_physics_process(false)
	game.player.position = Vector2(800, 650)
	game.player.aim = Vector2.RIGHT
	var targets: Array = []
	for point in points:
		var enemy = game.spawn_enemy("stalker", point)
		enemy.hp = 10000.0
		enemy.max_hp = 10000.0
		enemy.set_physics_process(false)
		targets.append(enemy)
	await frames(2)
	return targets

func charged_fire(fraction := 1.0) -> void:
	game.player.weapon.drawing = true
	game.player.weapon.charge = float(game.player.weapon.definition.charge) * fraction
	game.player.weapon.release_charge()

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	game.narrative_enabled = false
	root.add_child(game)
	await process_frame
	game.muted = true
	var expected := ["blade", "lance", "maul", "fang", "arc", "grav", "glaive", "whip", "prism", "ember", "frost", "storm", "rifle", "scatter", "rail", "qbow", "lbow", "sbow"]
	check(CATALOG.FORMS.size() == expected.size(), "All 18 original base forms are present")
	var shortcut := InputEventKey.new()
	shortcut.physical_keycode = KEY_TAB
	shortcut.pressed = true
	Input.parse_input_event(shortcut)
	await process_frame
	check(game.state == "armory", "Tab opens the armory even with a focused title button")
	shortcut = shortcut.duplicate()
	shortcut.pressed = false
	Input.parse_input_event(shortcut)
	for id in expected:
		check(game.select_weapon(id), "Armory can select " + id)
	check(not game.select_weapon("unknown"), "Armory rejects unknown weapons")
	game.start_run()
	await frames(2)
	check(game.player.weapon.definition.id == "sbow" and game.player.can_process(), "Armory selection survives into a live run")
	check(not game.select_weapon("blade"), "Weapon switching is locked during combat")
	# Every form must cause real damage, not merely create a cosmetic effect.
	for form in CATALOG.FORMS:
		var targets := await reset_case(form.id, [Vector2(875, 650)])
		if form.has("charge"):
			charged_fire()
		else:
			check(game.player.try_slash(), form.name + " activates")
		await frames(66 if form.mode == "gravity" else 18)
		check(targets[0].hp < 10000.0, form.name + " damages its target")
		check(game.player.energy == 100.0, form.name + " leaves shared plasma energy intact")
	# Cover blocks melee, beams, explosions, projectiles and returning blades.
	for form in CATALOG.FORMS:
		var targets := await reset_case(form.id, [Vector2(420, 420)])
		game.player.position = Vector2(420, 290)
		game.player.aim = Vector2.DOWN
		await frames(2)
		if form.has("charge"):
			charged_fire()
		else:
			game.player.try_slash()
		await frames(66 if form.mode == "gravity" else 18)
		check(targets[0].hp == 10000.0, form.name + " cannot damage through solid cover")
	var targets := await reset_case("lance", [Vector2(970, 650), Vector2(875, 725)])
	game.player.try_slash()
	check(targets[0].hp < 10000.0 and targets[1].hp == 10000.0, "Lance has long reach and a narrow thrust")
	targets = await reset_case("maul", [Vector2(875, 650)])
	game.player.try_slash()
	check(targets[0].knockback.x >= 490.0 and targets[0].frozen > 0.0, "Maul delivers heavy knockback and stagger")
	targets = await reset_case("fang", [Vector2(865, 650)])
	game.player.try_slash()
	var first: float = 10000.0 - targets[0].hp
	game.player.slash_cooldown = 0.0
	game.player.try_slash()
	game.player.slash_cooldown = 0.0
	var before: float = targets[0].hp
	game.player.try_slash()
	check(is_equal_approx(before - targets[0].hp, first * 2.0), "Twin Fang's third strike doubles the hit")
	targets = await reset_case("whip", [Vector2(995, 650)])
	game.player.try_slash()
	check(targets[0].knockback.x < -250.0, "Chain Whip pulls a distant enemy inward")
	targets = await reset_case("arc", [Vector2(900, 650), Vector2(1080, 650), Vector2(1250, 650)])
	game.player.try_slash()
	check(targets.all(func(enemy): return enemy.hp < 10000.0), "Arc Caster chains beyond its initial cone")
	targets = await reset_case("prism", [Vector2(865, 650), Vector2(1120, 650)])
	game.player.try_slash()
	await frames(22)
	check(targets.all(func(enemy): return enemy.hp < 10000.0), "Prism Saber combines close slash with a piercing beam")
	targets = await reset_case("storm", [Vector2(980, 650), Vector2(1120, 650), Vector2(1260, 650), Vector2(1400, 650), Vector2(1420, 720)])
	game.player.try_slash()
	check(targets.slice(0, 4).all(func(enemy): return enemy.hp < 10000.0) and targets[4].hp == 10000.0, "Storm Staff chains to four distinct targets only")
	targets = await reset_case("glaive", [Vector2(945, 650)])
	game.player.try_slash()
	game.player.slash_cooldown = 0.0
	check(not game.player.try_slash(), "Glaive cannot be rethrown while airborne")
	await frames(78)
	check(is_equal_approx(10000.0 - targets[0].hp, 26.0 * 0.85 * 2.0), "Glaive hits exactly once outbound and once returning")
	check(game.player.try_slash(), "Glaive becomes available after being caught")
	targets = await reset_case("grav", [Vector2(1000, 650)])
	targets[0].frozen = 10.0
	targets[0].set_physics_process(true)
	game.player.try_slash()
	await frames(20)
	check(targets[0].position.x < 990.0 and targets[0].hp == 10000.0, "Gravity well pulls before its delayed explosion")
	await frames(35)
	check(targets[0].hp < 10000.0, "Gravity well implodes after its windup")
	targets = await reset_case("scatter", [Vector2(930, 610), Vector2(930, 690)])
	game.player.try_slash()
	check(game.get_node("World/Projectiles").get_child_count() == 7, "Scattergun creates seven pellets")
	await frames(15)
	check(targets.all(func(enemy): return enemy.hp < 10000.0), "Scattergun covers both sides of its cone")
	targets = await reset_case("sbow", [Vector2(1000, 600), Vector2(1000, 650), Vector2(1000, 700)])
	game.player.try_slash()
	await frames(22)
	check(targets.all(func(enemy): return enemy.hp < 10000.0), "Stormbow hits three firing lanes with arrows")
	targets = await reset_case("rifle", [Vector2(960, 650)])
	game.player.set_physics_process(true)
	Input.action_press("slash")
	await frames(30)
	Input.action_release("slash")
	check(10000.0 - targets[0].hp >= 26.0 * 0.32 * 3.0, "Holding primary produces sustained rifle fire")
	for id in ["rail", "lbow"]:
		targets = await reset_case(id, [Vector2(950, 650), Vector2(1060, 650), Vector2(1180, 650), Vector2(1300, 650)])
		game.player.weapon.tick(0.4, true, false)
		check(game.get_node("World/Projectiles").get_child_count() == 0, id + " holds fire while charging")
		game.player.weapon.tick(0.6, true, false)
		game.player.weapon.tick(0.0, false, true)
		await frames(40)
		check(targets.all(func(enemy): return enemy.hp < 10000.0), id + " full charge penetrates a line of four enemies")
		check(10000.0 - targets[0].hp > 75.0, id + " full charge increases damage")
	targets = await reset_case("lbow", [Vector2(950, 650)])
	game.player.weapon.tick(0.5, true, false)
	game.show_menu("paused")
	check(not game.player.weapon.drawing and game.player.weapon.charge == 0.0, "Pause cancels a held charge")
	await frames(2)
	game.resume_run()
	game.player.weapon.tick(0.0, false, true)
	check(game.get_node("World/Projectiles").get_child_count() == 0, "Resuming cannot release a stale charge")
	targets = await reset_case("frost", [Vector2(920, 650)])
	for i in range(3):
		game.player.slash_cooldown = 0.0
		game.player.try_slash()
		await frames(14)
	check(targets[0].chill_stacks == 0 and targets[0].ice_frozen_left > 0.0, "Three frost hits build an actual freeze")
	before = targets[0].hp
	targets[0].apply_element("fire", 30.0)
	check(targets[0].ice_frozen_left == 0.0 and targets[0].hp == before - 21.0, "Fire detonates an ice freeze as thermal shock")
	targets = await reset_case("ember", [Vector2(945, 650), Vector2(975, 700)])
	game.player.try_slash()
	await frames(23)
	check(targets.all(func(enemy): return enemy.hp < 10000.0 and enemy.burn_left > 0.0), "Ember impact splashes and ignites nearby hostiles")
	check(game.get_node("World/Projectiles").get_children().any(func(node): return node.get_script() == game.FIELD), "Ember leaves a burning pool")
	before = targets[1].hp
	await frames(30)
	check(targets[1].hp < before, "Burning pool continues dealing damage")
	# All transient weapon state must end with its run.
	game.start_run()
	check(game.get_node("World/Projectiles").get_child_count() == 0 and game.player.weapon.charge == 0.0, "Restart clears shots, fields and charge state")
	game.queue_free()
	await process_frame
	print("ABYSS WEAPONS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
