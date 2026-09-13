extends SceneTree
## Real collision deflections and independence of cosmetic/combat randomness.

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
	for i in range(count): await physics_frame
	await process_frame

func reset_case(weapon := "blade", version := 2, cooperative := false):
	game.coop.enabled = cooperative
	game.coop.devices.assign([1, 3] if cooperative else [-1, -1])
	game.coop.weapons.assign([weapon, weapon])
	game.configure_input()
	game.selected_weapon = weapon
	game.start_run(941)
	game.campaign_version = version
	game.encounter.cancel()
	game.room_awarded = true
	game.set_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	for actor in game.team():
		actor.set_physics_process(false)
		actor.position = Vector2(800, 650)
		actor.hp = 80
		actor.energy = 30
		actor.invulnerable = 0
		actor.aim = Vector2.RIGHT
	var target = game.spawn_enemy("drone", Vector2(1100, 650))
	target.set_physics_process(false)
	target.hp = 10000
	target.max_hp = 10000
	await frames()
	return target

func random_sample(extra_frames: int) -> Dictionary:
	seed(7139)
	game.start_run(7139)
	game.encounter.cancel()
	game.set_process(false)
	for actor in game.team(): actor.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	game.shake = 9.0
	for i in range(extra_frames): game._process(0.0)
	var delays := []
	for i in range(4):
		var target = game.spawn_enemy("drone", Vector2(800 + i * 60, 400))
		target.set_physics_process(false)
		delays.append(target.cooldown)
	game.player.weapon.equip("rifle")
	for i in range(5):
		game.player.slash_cooldown = 0
		game.player.weapon.fire()
	return {"delays": delays, "shots": game.get_node("World/Projectiles").get_children().map(func(node): return node.direction), "room_rng": game.rng.state}

func run() -> void:
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	var regular := random_sample(0)
	var more_frames := random_sample(170)
	check(regular.delays == more_frames.delays, "Extra render frames cannot reroll enemy attack offsets")
	check(regular.shots == more_frames.shots, "Extra render frames cannot reroll weapon spread")
	check(regular.room_rng == more_frames.room_rng, "Presentation cannot alter route or blessing RNG")
	var target = await reset_case()
	game.player.try_parry()
	var shot = game.spawn_bolt(Vector2(840, 650), Vector2.LEFT, true, 13)
	await frames(10)
	var reflected: Array = game.get_node("World/Projectiles").get_children().filter(func(node): return not node.hostile)
	check(reflected.size() == 1, "Successful parry returns exactly one friendly projectile")
	check(game.player.hp == 80 and game.player.energy == 55 and game.player.empowered == 2.0, "Existing parry defense and energy reward remain intact")
	await frames(35)
	check(target.hp < 10000, "Returned projectile can hit the ranged attacker through real collision")
	await family_and_boundary_cases()
	await paired_and_pause_cases()
	await input_and_preview()
	game.queue_free()
	await frames(4)
	await create_timer(0.25).timeout
	print("ABYSS COUNTERSHOTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func incoming(actor, power := 13.0):
	return game.spawn_bolt(actor.position + Vector2(40, 0), Vector2.LEFT, true, power)

func returned() -> Array:
	return game.get_node("World/Projectiles").get_children().filter(func(node): return node.reflected)

func family_and_boundary_cases() -> void:
	for form in game.WEAPONS.FORMS:
		var target = await reset_case(form.id)
		game.player.enchantments = {"poison": 1}
		game.player.try_parry()
		var shot = incoming(game.player)
		var identity: int = shot.get_instance_id()
		var offset: Vector2 = shot.visual_offset
		await frames(8)
		var counters := returned()
		check(counters.size() == 1, "Every weapon can parry: " + form.id)
		if counters.is_empty(): continue
		shot = counters[0]
		check(shot.get_instance_id() == identity and shot.visual_offset == offset, "Deflection reuses its projectile and preserves the visible contact point")
		check(not shot.hostile and shot.collision_mask == 5 and shot.shooter == game.player and shot.direction == Vector2.RIGHT, "Return collision mask, owner and direction change together")
		check(shot.damage == 26 and shot.element == form.get("element", "") and shot.pierce_remaining == 0 and shot.explosion == 0, "Countershot scales with base damage and inherits the innate element")
		await frames(35)
		check(target.hp < 10000 and target.poison_stacks == 1, "Actual return hit applies its rune once: " + form.id)
		if form.get("element", "") == "fire": check(target.burn_left > 0, "Fire staff counter ignites its attacker")
		if form.get("element", "") == "ice": check(target.chill_stacks == 1, "Ice staff counter adds one innate chill stack")
		check(returned().is_empty(), "One countershot cannot pierce or persist after its hit")
	var target = await reset_case()
	game.player.damage = 78
	game.player.try_parry()
	incoming(game.player, 90)
	await frames(8)
	check(returned().size() == 1 and returned()[0].damage == 90, "A stronger incoming projectile retains its damage")
	await frames(35)
	check(target.hp == 9910, "High incoming damage is applied exactly once")
	target = await reset_case()
	game.player.damage = 78
	game.player.try_parry()
	incoming(game.player)
	await frames(43)
	check(target.hp == 9922, "Weapon calibration raises the actual return damage floor")
	# Exercise the Area2D signal itself with the sweep disabled at first contact.
	target = await reset_case()
	game.player.try_parry()
	var overlapping = game.spawn_bolt(game.player.position, Vector2.LEFT, true, 13)
	overlapping.set_physics_process(false)
	await frames(3)
	check(overlapping.reflected and overlapping.collision_mask == 5, "Overlapping body signal defers its collision change safely")
	overlapping.set_physics_process(true)
	await frames(35)
	check(target.hp == 9974, "Signal-path return exits defender and hits the attacker once")
	await reset_case()
	game.player.try_parry()
	var miss = game.spawn_bolt(game.player.position + Vector2(0, 40), Vector2.UP, true, 13)
	await frames(8)
	check(is_instance_valid(miss) and miss.reflected, "An off-target return starts normally")
	await frames(80)
	check(not is_instance_valid(miss) and returned().is_empty(), "Missed return expires without leaving a projectile")
	# Expired parry and ordinary invulnerability never turn into a counter.
	for mode in ["late", "invulnerable", "legacy", "downed"]:
		target = await reset_case("blade", 1 if mode == "legacy" else 2)
		if mode == "legacy": game.player.try_parry()
		if mode == "invulnerable": game.player.invulnerable = 0.7
		if mode == "downed": game.player.hp = 0
		incoming(game.player)
		await frames(12)
		check(returned().is_empty(), "No return outside a live modern parry: " + mode)
		check(target.hp == 10000, "Non-countering contact cannot hurt attacker")
	# Return trajectory still collides with solid cover.
	target = await reset_case()
	game.player.position = Vector2(420, 290)
	target.position = Vector2(420, 420)
	game.player.try_parry()
	var covered_shot = game.spawn_bolt(game.player.position + Vector2(0, 24), Vector2.UP, true, 13)
	var covered_result := {"reflected": false}
	covered_shot.tree_exiting.connect(func(): covered_result.reflected = covered_shot.reflected)
	await frames(40)
	check(covered_result.reflected, "Cover fixture actually returns its incoming projectile")
	check(target.hp == 10000 and target.frozen == 0 and returned().is_empty(), "Solid cover stops the return and the close parry burst")
	target = await reset_case("blade", 1)
	game.player.position = Vector2(420, 290)
	target.position = Vector2(420, 420)
	game.player.try_parry()
	game.player.take_damage(13, game.player.position + Vector2(0, 24))
	check(target.hp == 9974 and target.frozen == 0.9, "Legacy close parry burst keeps its previous cover behavior")
	# A fire counter can detonate a freeze prepared by a teammate or the nova.
	target = await reset_case("ember")
	var neighbour = game.spawn_enemy("stalker", target.position + Vector2(0, 85))
	neighbour.hp = 10000
	neighbour.max_hp = 10000
	neighbour.set_physics_process(false)
	target.freeze_for(2.0)
	game.player.enchantments = {"leech": 1}
	game.player.try_parry()
	incoming(game.player)
	await frames(43)
	check(target.hp < 9974 and neighbour.hp < 10000, "Parry return can trigger a genuine thermal area reaction")
	check(is_equal_approx(game.player.hp, 81.56), "Return hit uses the existing leech reserve, never reaction splash")

func paired_and_pause_cases() -> void:
	var target = await reset_case("blade", 2, true)
	game.companion.position = Vector2(950, 650)
	game.companion.enchantments = {"poison": 3}
	game.player.enchantments = {"fire": 1}
	game.player.try_parry()
	var shot = incoming(game.player)
	await frames(8)
	check(returned().size() == 1, "First seat can counter in local co-op")
	if returned().is_empty(): return
	shot = returned()[0]
	game.show_menu("paused")
	await frames()
	var point: Vector2 = shot.position
	var remaining: float = shot.life
	await frames(18)
	check(shot.position == point and shot.life == remaining, "Pausing freezes counter flight and lifetime")
	game.resume_run()
	await frames(35)
	check(game.companion.hp == 80 and target.burn_left > 0 and target.poison_stacks == 0, "Return passes through teammate and belongs to its actual defender")
	# Reverse seats and send a volley: only the first contact spends the parry window.
	target = await reset_case("blade", 2, true)
	game.player.position = Vector2(950, 650)
	game.companion.enchantments = {"poison": 1}
	game.companion.try_parry()
	for i in range(4): incoming(game.companion)
	await frames(8)
	check(returned().size() == 1 and returned()[0].shooter == game.companion, "Second seat returns one projectile from a simultaneous volley")
	check(game.companion.energy == 55 and game.companion.hp == 80, "Volley does not repeat energy or invulnerability rewards")
	await frames(35)
	check(target.poison_stacks == 1 and game.player.hp == 80, "Second seat's counter applies its own rune without friendly fire")
	await reset_case()
	game.player.try_parry()
	incoming(game.player)
	await frames(8)
	game.next_room(game.ROOMS.generate(2, "combat", game.rng))
	check(returned().is_empty(), "Changing rooms clears countershots")

func input_and_preview() -> void:
	await reset_case("frost", 2, true)
	game.companion.position = Vector2(700, 730)
	game.player.input_armed = true
	game.player.set_physics_process(true)
	var button := InputEventJoypadButton.new()
	button.device = 1
	button.button_index = JOY_BUTTON_B
	button.pressed = true
	Input.parse_input_event(button)
	await frames(2)
	incoming(game.player)
	button = button.duplicate()
	button.pressed = false
	Input.parse_input_event(button)
	await frames(7)
	check(not returned().is_empty() and game.player.empowered > 0, "Physical input pipeline on device one triggers the actual parry")
	game.player.set_physics_process(false)
	if DisplayServer.get_name() != "headless":
		game.hud.update_status()
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/qa"))
		root.get_texture().get_image().save_png("res://builds/qa/parry-countershot.png")
		game.show_menu("paused")
		game.open_build()
		await frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/qa/parry-build-info.png")
