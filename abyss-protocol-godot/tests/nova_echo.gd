extends SceneTree
## Real nova casts, delayed elemental consequences, and reward/save contracts.
const SAVE = preload("res://scripts/run_save.gd")
const PROFILE = preload("res://scripts/profile.gd")
const FIXTURE = preload("res://tests/encounter_fixture.gd")
var game
var checks := 0
var failures := 0
var path := "user://test-nova-echo-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]

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

func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://builds/qa/nova-echo-" + name + ".png") == OK, "Capture native echo presentation")

func reset_case(points: Array, echo := true) -> Array:
	game.start_run(8172)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	var room: Dictionary = game.room_data.duplicate(true)
	for key in ["cover", "obstacles", "furnishings", "shell"]: room[key] = []
	room.erase("art")
	game.arena.apply_room(room)
	game.player.position = Vector2(800, 750)
	game.player.set_physics_process(false)
	if echo: game.PROGRESSION.apply({"stat": "nova_echo"}, game.player, 2)
	var targets := []
	for offset in points:
		var enemy = game.spawn_enemy("stalker", game.player.position + offset)
		enemy.hp = 10000
		enemy.max_hp = 10000
		enemy.set_physics_process(false)
		targets.append(enemy)
	await frames()
	return targets

func mechanics() -> void:
	var targets := await reset_case([Vector2(90, 0)])
	check(game.player.enchantments.get("nova_echo", 0) == 1, "The new blessing equips through normal progression")
	check(game.player.try_freeze(), "The shared nova casts normally")
	var after_first: float = targets[0].hp
	check(is_equal_approx(after_first, 10000 - game.player.damage * 0.6) and targets[0].ice_frozen_left > 0, "Initial nova keeps its original direct damage and freeze")
	check(not game.player.try_freeze() and is_equal_approx(game.player.freeze_cooldown, 10), "A held or repeated cast cannot bypass the original cooldown")
	await frames(35)
	check(is_equal_approx(targets[0].hp, after_first) and targets[0].burn_left == 0, "Echo does not damage or ignite before its delay")
	await snapshot("charging")
	game.show_menu("paused")
	await frames(60)
	check(is_equal_approx(targets[0].hp, after_first), "Pause freezes the pending echo")
	game.resume_run()
	game.player.position += Vector2(500, 0)
	await frames(25)
	check(targets[0].burn_left > 0 and targets[0].ice_frozen_left == 0, "The committed original position ignites and consumes its frozen target")
	check(is_equal_approx(targets[0].hp, after_first - game.player.damage * 0.45 * 1.7), "Echo direct fire damage triggers exactly one existing thermal reaction")
	await snapshot("burst")
	var after_echo: float = targets[0].hp
	await frames(70)
	check(is_equal_approx(targets[0].hp, after_echo), "Echo cannot repeat its damage or recursively spawn another echo")
	targets = await reset_case([Vector2(-30, 0), Vector2(75, 0), Vector2(300, 0)])
	game.arena.add_wall(Rect2(835, 600, 25, 300))
	await frames()
	game.player.enchantments.merge({"poison": 3, "leech": 3, "execute": 3})
	game.player.hp = 40
	check(game.player.try_freeze(), "Cover case casts a real nova")
	var blocked_hp: float = targets[1].hp
	await frames(55)
	check(targets[0].burn_left > 0, "Visible targets receive the delayed fire")
	check(is_equal_approx(targets[1].hp, blocked_hp) and targets[1].burn_left == 0, "Solid cover blocks echo damage, fire, and secondary thermal splash")
	check(targets[2].hp == 10000 and targets[2].burn_left == 0, "Echo range stays bounded")
	check(game.player.hp == 40 and targets[0].poison_stacks == 0, "A shared skill does not inherit weapon leech, execute, or poison procs")
	targets = await reset_case([Vector2(80, 0)], false)
	game.player.try_freeze()
	await frames(60)
	check(targets[0].burn_left == 0 and is_equal_approx(targets[0].hp, 10000 - game.player.damage * 0.6), "An unblessed nova retains its old behavior")

func progression() -> void:
	await reset_case([])
	var boon: Dictionary = game.PROGRESSION.rune("nova_echo")
	check(not boon.is_empty(), "The named blessing exists in the reward catalog")
	game.PROGRESSION.apply({"stat": "nova_echo"}, game.player, 2)
	check(game.player.enchantments.get("nova_echo") == 1 and not game.PROGRESSION.can_apply({"stat": "nova_echo"}, game.player, 2), "The skill blessing cannot stack or consume a redundant choice")
	game.prepare_routes()
	var captured: Dictionary = SAVE.capture(game)
	check(SAVE.valid(captured), "The new skill persists in the existing per-seat checkpoint transaction")
	captured.enchantments.nova_echo = 2
	check(not SAVE.valid(captured), "A stacked skill rank is rejected by save validation")
	game.start_run(812)
	check(not game.player.enchantments.has("nova_echo"), "New runs clear the skill blessing")
	game.campaign_version = 1
	game.PROGRESSION.apply({"stat": "nova_echo"}, game.player, 1)
	check(not game.player.enchantments.has("nova_echo"), "Legacy campaigns cannot acquire the new skill")
	for seed in range(40):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		check(game.PROGRESSION.offers(rng, false, {}, [], 1).all(func(b): return b.stat != "nova_echo"), "Legacy random rewards exclude the new skill")
	game.campaign_version = 2
	var found := false
	for seed in range(40):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		if game.PROGRESSION.offers(rng, false, {}, game.team(), 2).any(func(b): return b.stat == "nova_echo"): found = true
	check(found, "Normal modern reward generation can offer the new skill")

func ui_and_storage() -> void:
	game.coop.enabled = true
	game.coop.devices.assign([3, 7])
	game.coop.weapons.assign(["storm", "blade"])
	game.configure_input()
	game.start_run(275)
	for member in game.team(): member.set_physics_process(false)
	await FIXTURE.clear(game)
	game.PROGRESSION.apply({"stat": "nova_echo"}, game.player, 2)
	# Deliberate UI/save fixture: real cleared reward state, a pending partially
	# eligible team skill, and two normal choices. Normal-run evidence uses the bot.
	game.boon_choices = [game.PROGRESSION.rune("nova_echo"), game.PROGRESSION.rune("health"), game.PROGRESSION.rune("damage")]
	game.persistence_enabled = true
	game.save_checkpoint()
	var pending: Dictionary = game.profile.checkpoint.duplicate(true)
	check(SAVE.valid(pending) and pending.boons[0] == "nova_echo" and not pending.partner.enchantments.has("nova_echo"), "One checkpoint retains pending reward IDs and independently equipped seats")
	var before := var_to_bytes([game.player.enchantments, game.companion.enchantments, game.rng.state, game.profile.checkpoint])
	var description: String = game.hud.team_upgrade_details(game.boon_choices[0])
	check("已获得" in description and "0.8" in description and "二号席" in description, "A shared card distinguishes the equipped seat from its eligible partner")
	check(description.count("新星施放") == 1, "An already equipped seat does not repeat the full shared skill description")
	for i in range(12): game.hud.team_upgrade_details(game.boon_choices[0])
	check(before == var_to_bytes([game.player.enchantments, game.companion.enchantments, game.rng.state, game.profile.checkpoint]), "Skill preview cannot equip, reroll or rewrite a save")
	for size in [Vector2i(960, 600), Vector2i(2560, 1440)]:
		root.size = size
		game.hud.show_menu("reward")
		await frames()
		for button in game.hud.menu_buttons():
			check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(button.get_global_rect()), "Skill reward controls fit the native viewport")
		check(game.hud.menu_margin.find_children("*", "TextureRect", true, false).any(func(t): return t.texture == game.PROGRESSION.NOVA.DIAGRAM), "Reward card shows the authored freeze-to-fire diagram")
		await snapshot("reward-%d" % size.x)
	game.open_build()
	await frames()
	check(game.hud.menu_margin.find_children("*", "Label", true, false).any(func(t): return "霜火回响" in t.text), "Build page includes the equipped skill with actual values")
	await snapshot("build")
	game.hud.update_status()
	check("霜火" in game.hud.skills[3].text and "霜火" not in game.hud.partner_skills[3].text, "HUD identifies the upgraded nova only for its owner")
	game.queue_free()
	await frames()
	var loaded = PROFILE.new()
	loaded.load_progress(path)
	await spawn_game(loaded)
	check(game.continue_saved_run() and game.state == "coop_lobby", "Cold load restores pending skill selection before controller pairing")
	check(game.boon_choices.map(func(b): return b.stat) == pending.boons, "Pending skill choices do not reroll on cold load")
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
	check(game.state == "route" and game.team().all(func(m): return m.enchantments.get("nova_echo") == 1), "Actual reward confirmation equips the eligible partner exactly once")
	var saved: Dictionary = game.profile.checkpoint.duplicate(true)
	for invalid in [0, 2, 1.0, true, "1", null]:
		var bad := saved.duplicate(true)
		bad.partner.enchantments.nova_echo = invalid
		check(not SAVE.valid(bad), "Malformed or stacked partner skill rank is rejected")
	game.queue_free()
	await frames()
	loaded = PROFILE.new()
	loaded.load_progress(path)
	await spawn_game(loaded)
	check(loaded.writable and game.continue_saved_run() and game.team().all(func(m): return m.enchantments.get("nova_echo") == 1), "Both equipped skills survive a second cold load")
	game.coop.devices.assign([3, 7])
	game.configure_input()
	game.show_menu("paused")
	game.resume_run()
	for member in game.team(): member.input_armed = true
	var press := InputEventJoypadButton.new()
	press.device = 7
	press.button_index = JOY_BUTTON_X
	press.pressed = true
	Input.parse_input_event(press)
	await frames()
	press = press.duplicate()
	press.pressed = false
	Input.parse_input_event(press)
	check(game.companion.freeze_cooldown > 0 and game.player.freeze_cooldown == 0, "A real second-controller nova press remains independently routed")
	check(game.get_node("World/Projectiles").get_children().any(func(n): return n.get_script() == game.PROGRESSION.NOVA), "The restored skill creates a real delayed echo")
	game.persistence_enabled = false
	game.start_run(915)
	await frames()
	check(game.get_node("World/Projectiles").get_child_count() == 0 and game.team().all(func(m): return not m.enchantments.has("nova_echo")), "New runs clear pending echoes and both per-run skills")

func run() -> void:
	await spawn_game()
	await mechanics()
	await progression()
	await ui_and_storage()
	game.queue_free()
	await frames()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	await create_timer(0.25).timeout
	print("ABYSS NOVA ECHO: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
