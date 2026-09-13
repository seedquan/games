extends SceneTree
const INFO = preload("res://scripts/build_info.gd")
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

func frames(count := 2) -> void:
	for i in range(count): await physics_frame
	await process_frame

func reset_case(weapon := "blade") -> void:
	game.coop.enabled = false
	game.selected_weapon = weapon
	game.start_run(921)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	game.player.set_physics_process(false)
	game.player.position = Vector2(800, 650)
	game.player.aim = Vector2.RIGHT
	await frames()

func damage_cases() -> void:
	for form in game.WEAPONS.FORMS:
		await reset_case(form.id)
		var enemy = game.spawn_enemy("stalker", Vector2(875, 650))
		enemy.hp = 10000
		enemy.max_hp = 10000
		enemy.set_physics_process(false)
		var numbers := INFO.attack_values(form, game.player.damage)
		game.player.weapon.fire(1.0 if form.has("charge") else -1.0)
		if form.mode == "melee" or form.mode == "chain":
			check(is_equal_approx(10000 - enemy.hp, numbers.hit), "Displayed direct hit matches actual " + form.id)
		elif form.mode in ["projectile", "glaive"]:
			var shots: Array = game.get_node("World/Projectiles").get_children()
			check(shots.size() == numbers.pellets, "Displayed projectile count matches " + form.id)
			for shot in shots:
				check(is_equal_approx(shot.damage, numbers.charged if form.has("charge") else numbers.hit), "Displayed projectile damage matches " + form.id)
		else:
			var fields: Array = game.get_node("World/Projectiles").get_children().filter(func(node): return node.get_script() == game.FIELD)
			check(fields.size() == 1 and is_equal_approx(fields[0].damage, numbers.hit), "Displayed gravity damage matches field")
	await reset_case("rifle")
	check("8.3 → 10.4" in INFO.damage_comparison(game.player, game.player.damage * 0.25), "Rifle reward shows actual shot rather than raw base damage")
	await reset_case("rail")
	game.player.weapon.fire(0.0)
	check(is_equal_approx(game.get_node("World/Projectiles").get_children()[0].damage, INFO.attack_values(game.player.weapon.definition, game.player.damage).quick), "Quick release matches displayed minimum")
	check("80.6 → 100.8" in INFO.damage_comparison(game.player, game.player.damage * 0.25), "Charged upgrade shows full-charge damage")

func element_cases() -> void:
	await reset_case("frost")
	var enemy = game.spawn_enemy("stalker", Vector2(875, 650))
	for version in [1, 2]:
		game.campaign_version = version
		for rank in range(4):
			game.player.enchantments = {"ice": rank} if rank > 0 else {}
			enemy.hp = 10000
			enemy.max_hp = 10000
			enemy.ice_frozen_left = 0
			enemy.frozen = 0
			enemy.chill_stacks = 0
			for i in range(3): game.player.weapon_hit(enemy, 1, Vector2.ZERO, "ice")
			var detail := INFO.element_detail("ice", rank, true, version)
			check(("%.2f 秒" % enemy.ice_frozen_left) in detail, "Current rune duration matches live freeze, including legacy and innate")
	check("尚未获得" == INFO.element_detail("fire", 0, false, 2), "Missing rune is not presented as its next rank")
	check("每次命中最多回复 4" in INFO.element_detail("leech", 3, false, 1), "Legacy leech keeps per-hit rule")
	check("3.15 → 3.15" in INFO.rune_comparison("ice", 3, true, 2), "Capped rune comparison stays unchanged")
	game.campaign_version = 2
	game.player.weapon.equip("ember")
	check(INFO.synergies(game.player).any(func(text): return "热冲击" in text and "150" in text), "Innate fire exposes the shared nova area combination")
	game.player.enchantments.poison = 1
	check(INFO.synergies(game.player).any(func(text): return "毒素爆燃" in text and "三层" in text), "Existing poison adds the primed combustion combination")
	game.campaign_version = 1
	check(not INFO.synergies(game.player).any(func(text): return "范围" in text), "Legacy descriptions do not promise area reactions")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	game.narrative_enabled = false
	root.add_child(game)
	await frames()
	game.muted = true
	await damage_cases()
	await element_cases()
	game.queue_free()
	await frames()
	print("ABYSS BUILD INFO: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
