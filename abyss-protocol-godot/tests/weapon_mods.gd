extends SceneTree
## Exercise actual attacks, choice input, and isolated cold-load refit persistence.
const MODS = preload("res://scripts/weapon_mods.gd")
const CATALOG = preload("res://scripts/weapons.gd")
const PROFILE = preload("res://scripts/profile.gd")
const SAVE = preload("res://scripts/run_save.gd")
const FIXTURE = preload("res://tests/encounter_fixture.gd")
var game
var checks := 0
var failures := 0
var path := "user://test-weapon-mods-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 2) -> void:
	for i in range(count): await physics_frame
	await process_frame

func spawn_game(profile = null) -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	if profile != null: game.profile = profile
	game.profile.save_path = path
	root.add_child(game)
	await frames()

func reset_case(weapon: String, modification: String, points: Array) -> Array:
	game.coop.enabled = false
	game.selected_weapon = weapon
	game.start_run(39483)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	game.player.set_physics_process(false)
	game.player.position = Vector2(800, 650)
	game.player.aim = Vector2.RIGHT
	if not modification.is_empty(): game.apply_boon(game.PROGRESSION.rune(modification))
	var targets := []
	for offset in points:
		var enemy = game.spawn_enemy("stalker", game.player.position + offset)
		enemy.hp = 10000
		enemy.max_hp = 10000
		enemy.set_physics_process(false)
		targets.append(enemy)
	await frames()
	return targets

func fire() -> void:
	game.player.slash_cooldown = 0
	check(game.player.weapon.fire(1.0), "Actual refitted weapon fires")

func all_forms() -> void:
	var before := var_to_bytes(CATALOG.FORMS)
	for form in CATALOG.FORMS:
		for id in MODS.IDS:
			var targets := await reset_case(form.id, id, [Vector2(60, 0)])
			fire()
			await frames(90 if form.mode == "gravity" else 12)
			check(targets[0].hp < 10000, "%s/%s deals actual damage" % [form.id, id])
			check(game.player.energy == 100, "Refits preserve shared ability energy")
			var effective: Dictionary = game.player.weapon.definition.duplicate(true)
			game.apply_boon(game.PROGRESSION.rune("mod_flow" if id == "mod_focus" else "mod_focus"))
			check(game.player.weapon_mod == id and game.player.weapon.definition == effective, "A second refit cannot replace or stack")
			game.player.weapon.equip(form.id)
			check(game.player.weapon.definition == effective, "Re-equipping rebuilds once instead of multiplying again")
	check(before == var_to_bytes(CATALOG.FORMS), "Every base catalog entry remains byte-identical")

func gravity_pacing() -> void:
	for version in [1, 2]:
		for id in ["", "mod_focus", "mod_flow"]:
			var targets := await reset_case("grav", "", [Vector2(120, 0)])
			game.campaign_version = version
			game.player.weapon_mod = id
			game.player.weapon.equip("grav")
			var base_damage: float = game.player.damage
			var expected := base_damage * (2.8 if version >= 2 else 1.65)
			if version >= 2 and id == "mod_flow": expected *= 0.9
			fire()
			var field = game.get_node("World/Projectiles").get_child(0)
			check(is_equal_approx(field.damage, expected), "Gravity explosion uses the campaign damage budget without changing actor growth")
			var attack_text: String = game.BUILD_INFO.attack_text(game.player.weapon.definition, base_damage)
			check("引爆 %.1f" % expected in attack_text, "Build page reports the actual gravity explosion")
			if version == 1:
				check(game.player.weapon.definition == CATALOG.find("grav"), "Legacy gravity ignores modern tuning and refit state")
			await frames(10)
			check(targets[0].hp == 10000, "Stronger gravity still waits for its visible pull before damage")
			if version == 2 and id == "mod_flow": await snapshot("gravity-pull")
			await frames(82)
			check(is_equal_approx(10000 - targets[0].hp, expected), "The real delayed well hits exactly once with the advertised damage")
			game.player.weapon.equip("grav")
			check(game.player.damage == base_damage and is_equal_approx(game.player.weapon.definition.damage * base_damage, expected), "Re-equipping neither changes growth nor stacks gravity tuning")
			var before: float = targets[0].hp
			game.player.try_freeze()
			check(is_equal_approx(before - targets[0].hp, base_damage * 0.6), "Gravity tuning leaves shared nova damage unchanged")
			game.player.try_bolt()
			var plasma = game.get_node("World/Projectiles").get_children().filter(func(n): return n.get_script() == preload("res://scripts/projectile.gd"))
			check(plasma.size() == 1 and is_equal_approx(plasma[0].damage, base_damage * 0.85), "Gravity tuning leaves shared plasma damage unchanged")

func special_weapon_continuation(weapon: String) -> void:
	game.coop.enabled = true
	game.coop.devices.assign([3, 7])
	game.coop.weapons.assign([weapon, weapon])
	game.start_run(72531)
	for actor in game.team(): actor.set_physics_process(false)
	game.apply_boon(game.PROGRESSION.rune("mod_focus"))
	game.companion.weapon_mod = ""
	game.apply_boon(game.PROGRESSION.rune("mod_flow"))
	game.apply_boon(game.PROGRESSION.rune("damage"))
	game.persistence_enabled = true
	game.save_checkpoint()
	var saved: Dictionary = game.profile.checkpoint.duplicate(true)
	check(SAVE.valid(saved) and saved.version == 3, "Special refits save through the existing cooperative checkpoint schema")
	game.queue_free()
	await frames()
	var loaded = PROFILE.new()
	loaded.load_progress(path)
	await spawn_game(loaded)
	check(game.continue_saved_run(), "Cold load restores the two-weapon team")
	check(game.player.weapon_mod == "mod_focus" and game.companion.weapon_mod == "mod_flow", "Different special-weapon refits retain their original seat")
	check(game.player.damage == saved.stats.damage and game.companion.damage == saved.partner.stats.damage, "Cold load preserves both saved growth values")
	var focus_damage := 2.8 if weapon == "grav" else 1.4 * 0.75
	var flow_damage := 2.8 * 0.9 if weapon == "grav" else 1.4 * 0.75
	check(is_equal_approx(game.player.weapon.definition.damage, focus_damage) and is_equal_approx(game.companion.weapon.definition.damage, flow_damage), "Cold load rebuilds both tuned attacks exactly once")
	if weapon == "glaive":
		check(game.player.weapon.definition.return_multiplier == 3 and game.companion.weapon.definition.return_multiplier == 1, "Cold glaive load retains the heavy return reward only on its selected seat")

func glaive_pacing() -> void:
	for setup in [[2, ""], [2, "mod_focus"], [2, "mod_flow"], [1, "mod_focus"]]:
		var t := await reset_case("glaive", "", [Vector2(100, 0)])
		game.campaign_version = setup[0]
		game.player.weapon_mod = setup[1]
		game.player.weapon.equip("glaive")
		var expected: float = game.player.damage * (1.4 if setup[0] == 2 else 0.85)
		if setup[0] == 2 and not setup[1].is_empty(): expected *= 0.75
		var return_scale := 3.0 if setup == [2, "mod_focus"] else 1.0
		fire()
		var shot = game.get_node("World/Projectiles").get_child(0)
		check(is_equal_approx(shot.damage, expected), "Glaive outbound collision carries the campaign damage budget")
		check(is_equal_approx(shot.return_multiplier, return_scale), "Heavy return carries its explicit damage reward")
		if setup[0] == 1:
			check(game.player.weapon.definition == CATALOG.find("glaive"), "Legacy glaive retains the original flight and damage even with refit state")
		var cooldown: float = game.player.slash_cooldown
		game.player.slash_cooldown = 0
		check(not game.player.weapon.fire(), "Stronger glaive cannot be thrown again before it is caught")
		game.player.slash_cooldown = cooldown
		var description: String = game.BUILD_INFO.attack_text(game.player.weapon.definition, game.player.damage)
		check("回程命中 %.1f" % (expected * return_scale) in description, "Build page shows the actual tuned return hit")
		await frames(100)
		check(is_equal_approx(10000 - t[0].hp, expected * (1 + return_scale)), "Actual projectile deals one outbound and one return hit with no duplicate damage")
		var definition: Dictionary = game.player.weapon.definition.duplicate(true)
		game.player.weapon.equip("glaive")
		check(game.player.weapon.definition == definition and game.player.damage == 26, "Re-equipping does not stack glaive tuning or alter actor growth")
		var hp: float = t[0].hp
		game.player.try_freeze()
		check(is_equal_approx(hp - t[0].hp, game.player.damage * 0.6), "Glaive tuning does not increase the shared nova")

func geometry_cases() -> void:
	var t := await reset_case("lance", "mod_focus", [Vector2(240, 0), Vector2(100, 65)])
	fire()
	check(t[0].hp < 10000 and t[1].hp == 10000, "Extended thrust reaches the far body but rejects the side target")
	t = await reset_case("lance", "mod_flow", [Vector2(0, 100), Vector2(200, 0)])
	fire()
	check(t[0].hp < 10000 and t[1].hp == 10000, "Broad lance hits the flank but loses forward reach")
	var strokes: Array = game.get_node("World/Effects").get_children().filter(func(n): return n.get_script() == preload("res://scripts/melee_stroke.gd"))
	check(strokes.size() == 1 and is_equal_approx(strokes[0].arc, game.player.weapon.definition.arc) and is_equal_approx(strokes[0].reach, game.player.weapon.definition.reach) and strokes[0].broad_sweep, "Broad damage shares the real stroke geometry and sweep art")
	await snapshot("sweep")
	t = await reset_case("rifle", "mod_focus", [Vector2(80, 0), Vector2(140, 0), Vector2(200, 0), Vector2(260, 0)])
	fire()
	await frames(20)
	check(t.slice(0, 3).all(func(e): return e.hp < 10000) and t[3].hp == 10000, "One refitted bullet pierces exactly three enemies")
	t = await reset_case("qbow", "mod_flow", [Vector2(170, 0).rotated(-0.3), Vector2(170, 0), Vector2(170, 0).rotated(0.3)])
	fire()
	var volley: Array = game.get_node("World/Projectiles").get_children()
	check(volley.size() == 3, "Split bow emits three independent arrows")
	check(is_equal_approx(volley[1].damage, game.player.damage * 0.8) and is_equal_approx(volley[0].damage, volley[1].damage * 0.35) and is_equal_approx(volley[2].damage, volley[0].damage), "Split bow preserves main-arrow damage and uses two weak side arrows")
	check(is_equal_approx(game.player.slash_cooldown, 0.24 * 1.2), "Split volley pays its slower attack interval")
	await frames(20)
	check(t.all(func(e): return e.hp < 10000), "All three visible spread paths can hit")
	for id in ["rail", "lbow"]:
		await reset_case(id, "mod_flow", [])
		fire()
		var shots: Array = game.get_node("World/Projectiles").get_children()
		check(shots.size() == 3 and shots.all(func(s): return s.pierce_remaining == (8 if id == "rail" else 3)), "Charged split volleys retain full-charge penetration")
		check("侧弹" in game.BUILD_INFO.attack_text(game.player.weapon.definition, game.player.damage), "Charged build description includes its actual volley")
	t = await reset_case("glaive", "mod_focus", [Vector2(100, 0)])
	fire()
	var shot = game.get_node("World/Projectiles").get_child(0)
	var outgoing: float = shot.damage
	await frames(20)
	check(not shot.returning and is_equal_approx(10000 - t[0].hp, outgoing), "Heavy glaive outbound hit uses its reduced damage")
	game.show_menu("paused")
	var timer: float = shot.flight_elapsed
	await frames(8)
	check(shot.flight_elapsed == timer and not shot.returning, "Pause holds the refitted return clock")
	game.resume_run()
	await frames(75)
	check(is_equal_approx(10000 - t[0].hp, outgoing * 4), "Guided return applies exactly three times outbound damage, once per leg")
	await reset_case("glaive", "mod_flow", [])
	fire()
	shot = game.get_node("World/Projectiles").get_child(0)
	await frames(18)
	check(is_instance_valid(shot) and shot.returning, "Short flight returns after a quarter second")
	for id in MODS.IDS:
		t = await reset_case("storm", id, [Vector2(80, 0), Vector2(170, 0), Vector2(260, 0), Vector2(350, 0), Vector2(440, 0), Vector2(530, 0)])
		fire()
		check(t.filter(func(e): return e.hp < 10000).size() == (2 if id == "mod_focus" else 6), "Lightning resolves the advertised distinct target limit")
		t = await reset_case("grav", id, [Vector2(120, 190)])
		fire()
		var fields: Array = game.get_node("World/Projectiles").get_children().filter(func(n): return n.get_script() == preload("res://scripts/combat_field.gd"))
		check(fields.size() == 1 and fields[0].radius == (115 if id == "mod_focus" else 235), "Gravity rendering and pull use the advertised radius")
		await frames(90)
		check((t[0].hp < 10000) == (id == "mod_flow"), "Only the wide well pulls and damages the distant target")
	# Every modified family still respects the actual room wall.
	for form in CATALOG.FORMS:
		for id in MODS.IDS:
			t = await reset_case(form.id, id, [])
			game.player.position = Vector2(420, 290)
			game.player.aim = Vector2.DOWN
			var enemy = game.spawn_enemy("stalker", Vector2(420, 420))
			enemy.hp = 10000
			enemy.set_physics_process(false)
			await frames()
			fire()
			await frames(90 if form.mode == "gravity" else 20)
			check(enemy.hp == 10000, "%s/%s cannot bypass cover" % [form.id, id])

func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://builds/qa/mods-" + name + ".png") == OK, "Capture native refit presentation")

func choice_and_save() -> void:
	game.coop.enabled = true
	game.coop.devices.assign([3, 7])
	game.coop.weapons.assign(["lance", "rail"])
	game.start_run(72531)
	for actor in game.team(): actor.set_physics_process(false)
	game.persistence_enabled = true
	await FIXTURE.clear(game)
	check(game.state == "reward" and game.boon_choices.slice(0, 2).map(func(b): return b.stat) == MODS.IDS, "First real cleared chamber offers both mutually exclusive refits")
	var original: Dictionary = game.profile.checkpoint.duplicate(true)
	var state := var_to_bytes([game.rng.state, game.profile.checkpoint, game.player.weapon.definition, game.player.weapon_mod])
	var description: String = game.hud.team_upgrade_details(game.boon_choices[0])
	check("一号席" in description and "延展刃" in description and "二号席" in description and "速蓄组件" in description, "Shared card explains different weapon benefits by seat")
	for i in range(15): game.hud.team_upgrade_details(game.boon_choices[1])
	check(state == var_to_bytes([game.rng.state, game.profile.checkpoint, game.player.weapon.definition, game.player.weapon_mod]), "Preview cannot apply, reroll or save a refit")
	for size in [Vector2i(960, 600), Vector2i(2560, 1440)]:
		root.size = size
		game.hud.show_menu("reward")
		await frames()
		var buttons: Array = game.hud.menu_buttons()
		for button in buttons:
			check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(button.get_global_rect()), "Reward buttons remain within the viewport")
		await snapshot("reward-%d" % size.x)
	game.queue_free()
	await frames()
	var loaded = PROFILE.new()
	loaded.load_progress(path)
	await spawn_game(loaded)
	check(game.continue_saved_run() and game.state == "coop_lobby", "Cold reward load restores the team before device pairing")
	check(game.boon_choices.map(func(b): return b.stat) == original.boons, "Pending refit choices survive disk without reroll")
	game.coop.devices.assign([3, 7])
	game.configure_input()
	game.show_menu("reward")
	game.persistence_enabled = true
	var key := InputEventKey.new()
	key.physical_keycode = KEY_1
	key.pressed = true
	Input.parse_input_event(key)
	await frames()
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	check(game.state == "route" and game.team().all(func(a): return a.weapon_mod == "mod_focus"), "Real reward key installs each weapon's corresponding refit")
	var saved: Dictionary = game.profile.checkpoint.duplicate(true)
	check(SAVE.valid(saved) and saved.version == 3 and saved.cooperative and saved.partner.weapon_mod == "mod_focus", "One transaction captures both refits and explicit cooperation")
	var unchanged: Dictionary = game.player.weapon.definition.duplicate(true)
	game.companion.weapon_mod = ""
	game.companion.weapon.equip("rail")
	check("本局不能更换" in game.hud.team_upgrade_details(game.PROGRESSION.rune("mod_flow")), "Partial-team preview identifies the occupied slot")
	game.apply_boon(game.PROGRESSION.rune("mod_flow"))
	check(game.player.weapon.definition == unchanged and game.companion.weapon_mod == "mod_flow" and game.companion.weapon.definition.pellets == 3, "A shared refit preserves the occupied seat and equips only the eligible seat")
	for i in range(20):
		var offers: Array = game.PROGRESSION.offers(game.rng, false, {}, game.team(), 2)
		check(offers.all(func(b): return b.stat not in MODS.IDS), "Occupied refit slots produce no useless cards")
	game.open_build()
	await snapshot("build")
	game.queue_free()
	await frames()
	loaded = PROFILE.new()
	loaded.load_progress(path)
	await spawn_game(loaded)
	check(game.continue_saved_run(), "Cold route load continues")
	check(is_equal_approx(game.player.weapon.definition.reach, 178 * 1.4) and is_equal_approx(game.companion.weapon.definition.charge, 0.8 * 0.65), "Cold load restores both actual mechanics without applying twice")
	for bad in [null, 1, [], "unknown"]:
		var invalid := saved.duplicate(true)
		invalid.weapon_mod = bad
		check(not SAVE.valid(invalid), "Malformed primary refit is rejected")
		invalid = saved.duplicate(true)
		invalid.partner.weapon_mod = bad
		check(not SAVE.valid(invalid), "Malformed partner refit is rejected")
	for field in ["weapon_mod", "cooperative"]:
		var invalid := saved.duplicate(true)
		invalid.erase(field)
		check(not SAVE.valid(invalid), "Version 3 requires " + field)
	var future := saved.duplicate(true)
	future.version = 4
	var config := ConfigFile.new()
	check(config.load(path) == OK, "Read only the test fixture")
	config.set_value("run", "checkpoint", future)
	check(config.save(path) == OK, "Write a future checkpoint to the isolated fixture")
	loaded = PROFILE.new()
	loaded.load_progress(path)
	var future_bytes := FileAccess.get_file_as_bytes(path)
	check(not loaded.writable and loaded.save_progress() == ERR_UNAUTHORIZED and future_bytes == FileAccess.get_file_as_bytes(path), "Future run schemas protect the entire existing profile from overwrite")
	# Old solo/co-op checkpoints are still accepted and carry no refit state.
	for version in [1, 2]:
		var legacy := original.duplicate(true)
		legacy.version = version
		legacy.erase("cooperative")
		legacy.erase("weapon_mod")
		legacy.boons = ["damage", "health", "speed"]
		if version == 1: legacy.erase("partner")
		else: legacy.partner.erase("weapon_mod")
		check(SAVE.valid(legacy) and SAVE.cooperative(legacy) == (version == 2), "Original schema %d remains valid" % version)
		game.queue_free()
		await frames()
		loaded = PROFILE.new()
		loaded.checkpoint = legacy
		await spawn_game(loaded)
		check(game.continue_saved_run() and game.player.weapon_mod.is_empty(), "Old schema restores unmodified weapon")
	game.persistence_enabled = false
	game.coop.enabled = false
	game.start_run(625)
	check(game.player.weapon_mod.is_empty(), "A new rescue resets the refit slot")
	game.campaign_version = 1
	game.apply_boon(game.PROGRESSION.rune("mod_focus"))
	check(game.player.weapon_mod.is_empty() and game.PROGRESSION.offers(game.rng, true, {}, game.team(), 1).map(func(b): return b.stat) == ["damage", "health", "speed"], "Legacy rescue cannot acquire new refits and keeps its first offers")

func run() -> void:
	await spawn_game()
	if "--gravity-only" not in OS.get_cmdline_user_args(): await glaive_pacing()
	if "--glaive-only" in OS.get_cmdline_user_args():
		game.queue_free()
		await frames()
		print("ABYSS GLAIVE PACING: %d checks, %d failures" % [checks, failures])
		quit(0 if failures == 0 else 1)
		return
	await gravity_pacing()
	if "--gravity-only" in OS.get_cmdline_user_args():
		game.queue_free()
		await frames()
		print("ABYSS GRAVITY PACING: %d checks, %d failures" % [checks, failures])
		quit(0 if failures == 0 else 1)
		return
	for weapon in ["grav", "glaive"]: await special_weapon_continuation(weapon)
	await all_forms()
	await geometry_cases()
	await choice_and_save()
	game.queue_free()
	await frames()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	# AudioServer releases stopped playback on its own mix cycle.
	await create_timer(0.25).timeout
	print("ABYSS WEAPON MODS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
