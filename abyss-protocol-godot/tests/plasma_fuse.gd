extends "res://tests/dash_echo.gd"
## A plasma hit primes a target; an independent weapon hit spends the charge.
const FUSE_ID := "plasma_fuse"

func mark(enemy):
	return enemy.get_node_or_null("PlasmaFuse")

func fire_at(enemy) -> void:
	game.player.aim = game.player.position.direction_to(enemy.position)
	game.player.bolt_cooldown = 0
	game.player.energy = 100
	game.player.try_bolt()
	await frames(8)

func fuse_mechanics() -> void:
	var targets := await reset_case([Vector2(90, 0), Vector2(210, 0)], false)
	var boon: Dictionary = game.PROGRESSION.rune(FUSE_ID)
	check(not boon.is_empty(), "Plasma fuse is a selectable skill blessing")
	game.PROGRESSION.apply({"stat": FUSE_ID}, game.player, 2)
	check(game.player.enchantments.get(FUSE_ID, 0) == 1, "Normal progression equips the plasma skill")
	await fire_at(targets[0])
	check(is_instance_valid(mark(targets[0])), "A real plasma impact primes the living target")
	if not is_instance_valid(mark(targets[0])): return
	var payload: float = game.player.damage * 0.6
	check(is_equal_approx(targets[0].hp, 10000 - game.player.damage * 0.85) and targets[1].hp == 10000, "Priming retains the original bolt hit and waits for a weapon")
	var left: float = mark(targets[0]).remaining
	game.show_menu("paused")
	await frames(30)
	check(mark(targets[0]).remaining == left, "Pause freezes the three-second opportunity")
	game.resume_run()
	game.player.damage = 1000
	targets[0].position += Vector2(0, 40)
	var before: float = targets[0].hp
	game.player.weapon_hit(targets[0], 10, Vector2.ZERO)
	check(is_equal_approx(targets[0].hp, before - 10 - payload) and is_equal_approx(targets[1].hp, 10000 - payload), "Weapon detonates the committed payload at the moved target")
	check(not is_instance_valid(mark(targets[0])), "Detonation immediately consumes the mark")
	game.player.weapon_hit(targets[0], 10, Vector2.ZERO)
	check(is_equal_approx(targets[1].hp, 10000 - payload), "Additional pellets cannot detonate the spent mark again")
	await snapshot("detonation")
	targets = await reset_case([Vector2(90, 0), Vector2(210, 0)], false)
	game.PROGRESSION.apply({"stat": FUSE_ID}, game.player, 2)
	await fire_at(targets[0])
	targets[0].apply_element("poison", 1)
	targets[0].freeze_for(2.5)
	targets[0].queue_redraw()
	await snapshot("primed")
	await frames(185)
	check(not is_instance_valid(mark(targets[0])) and targets[1].hp == 10000, "Expired marks disappear without automatic damage")
	targets = await reset_case([Vector2(90, 0), Vector2(210, 0)], false)
	game.PROGRESSION.apply({"stat": FUSE_ID}, game.player, 2)
	await fire_at(targets[0])
	game.player.damage = 5
	await fire_at(targets[0])
	check(is_equal_approx(mark(targets[0]).damage, payload), "A weaker refresh preserves the stronger committed charge without stacking")
	game.arena.add_wall(Rect2(945, 650, 25, 220))
	await frames()
	game.player.weapon_hit(targets[0], 10, Vector2.ZERO)
	check(targets[1].hp == 10000, "Cover blocks the follow-up blast")
	targets = await reset_case([Vector2(90, 0), Vector2(210, 0)], false)
	game.PROGRESSION.apply({"stat": FUSE_ID}, game.player, 2)
	await fire_at(targets[0])
	game.player.weapon_hit(targets[0], 20000, Vector2.ZERO)
	check(is_equal_approx(targets[1].hp, 10000 - payload), "A lethal weapon hit still detonates the already primed target")
	targets = await reset_case([Vector2(90, 0), Vector2(210, 0), Vector2(251, 0)], false)
	game.PROGRESSION.apply({"stat": FUSE_ID}, game.player, 2)
	await fire_at(targets[0])
	game.PROGRESSION.FUSE.prime(targets[1], payload, 1)
	game.player.weapon_hit(targets[0], 10, Vector2.ZERO)
	check(is_equal_approx(targets[1].hp, 10000 - payload) and targets[2].hp == 10000, "Blast stays inside 160 and cannot reach the farther target through a marked neighbor")
	check(is_instance_valid(mark(targets[1])), "The neighbor's independent fuse survives a neutral blast")
	targets = await reset_case([Vector2(90, 0)], false)
	await fire_at(targets[0])
	check(not is_instance_valid(mark(targets[0])), "Unblessed plasma never leaves a fuse")
	game.campaign_version = 1
	game.player.enchantments[FUSE_ID] = 1
	await fire_at(targets[0])
	check(not is_instance_valid(mark(targets[0])), "Legacy plasma retains its original behavior")

func run() -> void:
	path = "user://test-plasma-fuse-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	capture_dir = "res://builds/qa/plasma-0320-native-%d" % OS.get_process_id()
	await spawn_game()
	await fuse_mechanics()
	await fuse_progression()
	await fuse_coop()
	game.queue_free()
	await create_timer(0.3).timeout
	print("ABYSS PLASMA FUSE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func fuse_progression() -> void:
	await reset_case([], false)
	game.PROGRESSION.apply({"stat": FUSE_ID}, game.player, 2)
	game.prepare_routes()
	var saved: Dictionary = SAVE.capture(game)
	check(SAVE.valid(saved), "Fuse blessing is accepted in the existing modern checkpoint")
	for value in [0, 2, 1.0, true, "1", null]:
		var bad := saved.duplicate(true)
		bad.enchantments[FUSE_ID] = value
		check(not SAVE.valid(bad), "Invalid fuse rank cannot enter a checkpoint")
	check(not game.PROGRESSION.can_apply({"stat": FUSE_ID}, game.player, 2), "Fuse blessing cannot be selected twice")
	game.start_run(32)
	game.PROGRESSION.apply({"stat": FUSE_ID}, game.player, 1)
	check(not game.player.enchantments.has(FUSE_ID), "Legacy reward application cannot equip the modern fuse")
	var found := false
	var excluded := true
	for value in range(80):
		var rng := RandomNumberGenerator.new()
		rng.seed = value
		found = found or game.PROGRESSION.offers(rng, false, {}, game.team(), 2).any(func(b): return b.stat == FUSE_ID)
		excluded = excluded and game.PROGRESSION.offers(rng, true, {}, game.team(), 2).all(func(b): return b.stat != FUSE_ID)
		excluded = excluded and game.PROGRESSION.offers(rng, false, {}, [], 1).all(func(b): return b.stat != FUSE_ID)
	check(found and excluded, "Normal offers include fuse while opening and legacy pools remain unchanged")
	game.boon_choices = [game.PROGRESSION.rune(FUSE_ID), game.PROGRESSION.rune("health"), game.PROGRESSION.rune("damage")]
	game.show_menu("reward")
	await frames()
	var diagram = game.PROGRESSION.FUSE.DIAGRAM
	check(game.hud.menu_margin.find_children("*", "TextureRect", true, false).any(func(t): return t.texture == diagram), "Reward uses the plasma-prime-weapon SVG")
	for dimensions in [Vector2i(960, 600), Vector2i(2560, 1440)]:
		root.size = dimensions
		await frames()
		for control in game.hud.menu_buttons():
			check(game.get_viewport_rect().grow(1).encloses(control.get_global_rect()), "Fuse reward controls fit the viewport")
		await snapshot("reward-%d" % dimensions.x)
	game.PROGRESSION.apply({"stat": FUSE_ID}, game.player, 2)
	game.open_build()
	await frames()
	check(game.hud.menu_margin.find_children("*", "Label", true, false).any(func(t): return "共振引信" in t.text), "Build explains the equipped fuse and actual blast damage")
	game.hud.update_status()
	check("引信" in game.hud.skills[1].text, "Equipped plasma skill has a compact HUD label")
	await snapshot("build")

func pad_button(device: int, button: int, down: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = down
	Input.parse_input_event(event)

func fuse_coop() -> void:
	game.coop.enabled = true
	game.coop.devices.assign([3, 7])
	game.coop.weapons.assign(["blade", "rifle"])
	game.configure_input()
	var targets := await reset_case([Vector2(90, 0), Vector2(210, 0)], false)
	game.companion.position = game.player.position + Vector2(0, 80)
	game.PROGRESSION.apply({"stat": FUSE_ID}, game.player, 2)
	game.companion.enchantments = {"fire": 3, "poison": 3}
	game.settings.values.flash = 0
	for member in game.team():
		member.set_physics_process(true)
		member.input_armed = true
	game.using_gamepad = true
	pad_button(3, JOY_BUTTON_LEFT_SHOULDER, true)
	await frames(2)
	pad_button(3, JOY_BUTTON_LEFT_SHOULDER, false)
	await frames(8)
	check(is_instance_valid(mark(targets[0])) and game.companion.energy == 100, "First physical-device event primes without using partner energy")
	pad_button(7, JOY_BUTTON_RIGHT_SHOULDER, true)
	await frames(2)
	pad_button(7, JOY_BUTTON_RIGHT_SHOULDER, false)
	await frames(10)
	for member in game.team(): member.set_physics_process(false)
	check(not is_instance_valid(mark(targets[0])) and targets[1].hp < 10000, "Second controller's weapon can detonate the first player's fuse")
	check(game.team().all(func(m): return m.hp == m.max_hp), "The cooperative blast has no friendly fire")
	check(targets[1].burn_left == 0 and targets[1].poison_stacks == 0 and targets[1].shock_guard == 0, "Fuse blast does not inherit weapon elements or recurse through reactions")
	await snapshot("coop-low-flash")
	# Resume with a normal encounter; the focused combat fixture cancels waves.
	game.start_run(275)
	for member in game.team(): member.set_physics_process(false)
	await FIXTURE.clear(game)
	game.PROGRESSION.apply({"stat": FUSE_ID}, game.player, 2)
	game.persistence_enabled = true
	game.boon_choices = [game.PROGRESSION.rune(FUSE_ID), game.PROGRESSION.rune("health"), game.PROGRESSION.rune("damage")]
	game.save_checkpoint()
	game.queue_free()
	await frames()
	var loaded = PROFILE.new()
	loaded.load_progress(path)
	await spawn_game(loaded)
	var continued: bool = loaded.writable and game.continue_saved_run()
	check(continued, "A fresh game loads the pending fuse choice from disk")
	if not continued: return
	check(game.player.enchantments.get(FUSE_ID) == 1 and not game.companion.enchantments.has(FUSE_ID) and game.boon_choices[0].stat == FUSE_ID, "Cold load preserves separate seats and the pending skill")
	game.coop.devices.assign([3, 7])
	game.configure_input()
	game.show_menu("reward")
	game.persistence_enabled = true
	var before := var_to_bytes([game.player.enchantments, game.companion.enchantments, game.rng.state])
	var details: String = game.hud.team_upgrade_details(game.boon_choices[0])
	check("已获得" in details and "二号席" in details and details.count("三秒") == 1, "Shared preview distinguishes the already-equipped player")
	check(before == var_to_bytes([game.player.enchantments, game.companion.enchantments, game.rng.state]), "Preview cannot change growth or future random offers")
	game.choose_boon(0)
	game.queue_free()
	await frames()
	loaded = PROFILE.new()
	loaded.load_progress(path)
	await spawn_game(loaded)
	check(loaded.writable and game.continue_saved_run() and game.team().all(func(m): return m.enchantments.get(FUSE_ID) == 1), "Second cold load preserves the shared reward on both players")
	game.persistence_enabled = false
	game.coop.devices.assign([3, 7])
	game.configure_input()
	game.start_run(34)
	check(game.team().all(func(m): return not m.enchantments.has(FUSE_ID)), "A new run resets the per-run fuse blessing")
