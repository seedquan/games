extends SceneTree
const ENCOUNTER_FIXTURE = preload("res://tests/encounter_fixture.gd")
const ROOMS = preload("res://scripts/rooms.gd")
const PROFILE = preload("res://scripts/profile.gd")
var checks := 0
var failures: Array[String] = []
var game

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

func clear_combat() -> void:
	await ENCOUNTER_FIXTURE.clear(game)
	await frames()

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	root.add_child(game)
	await frames()
	# Generate both mirrored variants and all room archetypes using deterministic seeds.
	var layouts: Dictionary = {}
	for seed_number in range(1, 9):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_number
		for depth in range(1, ROOMS.LAST_ROOM + 1):
			var kind := "boss" if depth % 6 == 0 else "combat"
			var room := ROOMS.generate(depth, kind, rng)
			game.arena.apply_room(room)
			layouts[str(room.cover)] = true
			check(ROOMS.walkable(room.start, room.cover, 22, game.arena.bounds, game.arena.obstacles), "Safe player spawn for seed %d room %d" % [seed_number, depth])
			check(room.spawns.size() >= 5, "Every combat layout has enough spaced spawns")
			for spawn in room.spawns:
				check(ROOMS.walkable(spawn, room.cover, 32, game.arena.bounds, game.arena.obstacles) and game.arena.path_exists(spawn, room.start), "Hostile spawn has a navigable route to the player")
			await frames(1)
	check(layouts.size() >= 8, "Campaign varies physical layouts, including mirrored assemblies")
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 901
	rng_b.seed = 901
	check(ROOMS.generate(4, "elite", rng_a) == ROOMS.generate(4, "elite", rng_b), "Equal seeds reproduce geometry and spawn order")
	game.start_run(902)
	game.player.set_physics_process(false)
	game.player.position = Vector2(420, 485)
	game.player.invulnerable = 100.0
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	var navigator = get_nodes_in_group("enemies")[0]
	navigator.position = Vector2(420, 245)
	navigator.set_physics_process(true)
	await frames(340)
	check(navigator.position.distance_to(game.player.position) < 110.0, "A live hostile navigates around solid cover instead of sticking to it")
	game.player.position = ROOMS.START
	await clear_combat()
	var banked: int = game.profile.cores
	var scrap: int = game.scrap
	game.complete_room()
	check(game.profile.cores == banked and game.scrap == scrap, "A cleared room cannot award its currencies twice")
	game.choose_boon(0)
	check(game.state == "route" and game.route_choices.size() == 2, "A combat reward leads to a branching route")
	check(not game.choose_route(99), "Invalid routes cannot advance the campaign")
	game.choose_route(1)
	check(game.room_data.kind == "elite" and get_nodes_in_group("enemies")[0].elite, "Elite route spawns strengthened enemies")
	check(not game.choose_route(0), "Repeated route activation cannot skip the chosen room")
	await clear_combat()
	game.choose_boon(0)
	game.choose_route(0)
	check(game.room == 3 and game.state == "shop" and get_nodes_in_group("enemies").is_empty(), "Supply room contains shop stock, not combat")
	game.scrap = 300
	var before: int = game.scrap
	check(not game.buy_item(0) and game.scrap == before, "Full-health repair purchase is rejected without charging")
	game.player.hp = 20
	check(game.buy_item(0) and game.player.hp == 70 and game.scrap == 250, "Repair charges exactly 50 scrap and restores 50 integrity")
	check(not game.buy_item(0) and game.scrap == 250, "Purchased stock cannot be bought twice")
	var damage: float = game.player.damage
	check(game.buy_item(1) and is_equal_approx(game.player.damage, damage * 1.15), "Weapon tuning has a real run effect")
	var element: String = game.shop_stock[2].id
	check(game.buy_item(2) and game.player.enchantments[element] == 1, "Rune purchase enchants the player")
	check(not game.buy_item(-1), "Invalid shop indexes are rejected")
	game.leave_supply()
	game.player.hp = 10
	game.choose_route(1)
	check(game.state == "rest" and game.player.hp == 45, "Repair route restores 35 percent of maximum integrity")
	game.leave_supply()
	game.leave_supply()
	check(game.player.hp == 45 and game.state == "route", "Repeated departure cannot duplicate free healing")
	game.show_menu("title")
	game.open_workbench()
	game.profile.cores = 1000
	check(game.buy_meta("vitality"), "Workbench buys a persistent chassis upgrade")
	check(game.buy_meta("power") and game.buy_meta("recovery"), "Workbench buys power and regeneration upgrades")
	check(not game.buy_meta("unknown"), "Unknown meta upgrades are rejected")
	game.start_run(903)
	check(game.player.max_hp == 110 and is_equal_approx(game.player.damage, 27.3) and game.player.energy_regen == 21, "Meta upgrades apply to the next android")
	check(game.scrap == 0 and game.player.enchantments.is_empty(), "Run scrap and runes reset while meta upgrades remain")
	# Enchantments work through the shared hit path for every weapon family.
	var target = get_nodes_in_group("enemies")[0]
	target.hp = 10000
	target.max_hp = 10000
	target.position = game.player.position + Vector2(70, 0)
	target.set_physics_process(false)
	game.player.enchantments = {"ice": 1, "poison": 1, "leech": 1}
	game.player.hp = 50
	game.player.weapon_hit(target, 20, Vector2.ZERO)
	check(target.chill_stacks == 1 and target.poison_stacks == 1 and game.player.hp > 50, "A hit simultaneously chills, poisons and restores integrity")
	game.player.enchantments = {"ice": 1}
	target.chill_stacks = 0
	game.player.weapon_hit(target, 20, Vector2.ZERO, "ice")
	check(target.chill_stacks == 1, "Matching innate and rune elements do not double-apply stacks")
	game.player.enchantments = {"execute": 1}
	target.hp = 100
	game.player.weapon_hit(target, 20, Vector2.ZERO)
	check(target.hp == 70, "Execution increases damage below the health threshold")
	target.poison_stacks = 0
	for i in range(10):
		target.apply_element("poison", 20)
	check(target.poison_stacks == 6, "Poison is capped at six stacks")
	target.apply_element("fire", 10)
	check(target.poison_stacks == 0 and target.hp < 70, "Fire consumes poison in a damaging combustion")
	# The universal nova must distinguish boss control duration and AoE parry rules.
	game.player.parry_left = 0.2
	game.player.invulnerable = 0
	var health: float = game.player.hp
	game.player.take_damage(5, game.player.position, false)
	check(game.player.hp == health - 5, "Area damage cannot be parried")
	await profile_cases()
	game.queue_free()
	await process_frame
	print("ABYSS CAMPAIGN: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func profile_cases() -> void:
	var path := "user://test-profile-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	var profile = PROFILE.new()
	profile.save_path = path
	profile.cores = 60
	profile.weapon = "lbow"
	profile.upgrades.vitality = 2
	check(profile.save_progress() == OK, "Profile writes to its isolated test path")
	profile.cores = 90
	check(profile.save_progress() == OK, "Profile update creates a backup")
	var loaded = PROFILE.new()
	loaded.load_progress(path)
	check(loaded.cores == 90 and loaded.weapon == "lbow" and loaded.upgrades.vitality == 2, "Profile round trip preserves progression and loadout")
	var broken := ConfigFile.new()
	broken.set_value("incomplete", "write", true)
	broken.save(path)
	loaded = PROFILE.new()
	loaded.load_progress(path)
	check(loaded.cores == 60 and loaded.preserve_backup, "Incomplete primary save recovers the previous valid profile")
	check(loaded.save_progress() == OK, "Recovered profile can repair the primary safely")
	var backup := ConfigFile.new()
	backup.load(path + ".bak")
	check(backup.get_value("profile", "cores") == 60, "Repair preserves the valid backup instead of copying the broken primary")
	var invalid := ConfigFile.new()
	invalid.set_value("profile", "version", 1)
	invalid.set_value("profile", "cores", 1.0e100)
	invalid.set_value("profile", "runs", "invalid")
	invalid.set_value("profile", "weapon", "unknown")
	invalid.set_value("upgrades", "vitality", 999)
	invalid.save(path)
	loaded = PROFILE.new()
	loaded.load_progress(path)
	check(loaded.cores == 1000000 and loaded.runs == 0 and loaded.weapon == "blade" and loaded.upgrades.vitality == 5, "Malformed profile values are bounded without numeric overflow")
	invalid.set_value("profile", "version", PROFILE.VERSION + 1)
	invalid.save(path)
	loaded = PROFILE.new()
	loaded.load_progress(path)
	check(not loaded.writable and loaded.save_progress() == ERR_UNAUTHORIZED, "Unknown future save versions are preserved")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
