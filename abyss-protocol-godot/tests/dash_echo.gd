extends SceneTree
## Accepted dashes, delayed shock, shared rewards, and isolated cold continuation.
const ID := "dash_echo"
const SAVE = preload("res://scripts/run_save.gd")
const PROFILE = preload("res://scripts/profile.gd")
const FIXTURE = preload("res://tests/encounter_fixture.gd")
var game
var checks := 0
var failures := 0
var path := "user://test-dash-echo-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
var capture_dir := "res://builds/qa/dash-0300-native-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]

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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_dir))
	await frames()
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png")) == OK, "Capture native dash presentation")

func reset_case(points: Array, blessed := true) -> Array:
	game.start_run(8192)
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
	for member in game.team(): member.set_physics_process(false)
	if blessed: game.PROGRESSION.apply({"stat": ID}, game.player, 2)
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
	var targets := await reset_case([Vector2(80, 0), Vector2(230, 0)])
	check(game.player.enchantments.get(ID, 0) == 1, "Dash blessing equips through progression")
	targets[0].freeze_for(2.5)
	var damage: float = game.player.damage * 0.35
	check(game.player.try_dash(Vector2.LEFT), "Blessed dash keeps the normal accepted input")
	check(not game.player.try_dash(Vector2.LEFT) and game.player.dash_cooldown == game.player.dash_recharge, "Rejected repeat cannot spawn another pulse or shorten cooldown")
	await frames(22)
	check(targets.all(func(e): return e.hp == 10000), "Dash pulse waits the full 0.6 seconds")
	await snapshot("charging")
	game.show_menu("paused")
	await frames(50)
	check(targets.all(func(e): return e.hp == 10000), "Pause freezes the committed pulse")
	game.player.position += Vector2(500, 0)
	game.player.damage = 1000
	game.player.hp = 40
	game.player.enchantments.merge({"poison": 3, "leech": 3, "execute": 3, "fire": 3})
	game.resume_run()
	await frames(22)
	check(is_equal_approx(targets[0].hp, 10000 - damage), "Pulse retains original position and damage after the player leaves")
	check(targets[0].ice_frozen_left > 0 and targets[0].shock_guard > 0, "Shock preserves real freeze for another elemental follow-up")
	check(is_equal_approx(targets[1].hp, 10000 - damage * 0.45), "Frozen target conducts once to a neighbor outside the pulse")
	check(game.player.hp == 40 and targets[0].poison_stacks == 0 and targets[0].burn_left == 0, "Dash shock does not inherit weapon runes or leech")
	await snapshot("burst")
	var after: float = targets[0].hp
	await frames(65)
	check(targets[0].hp == after and game.get_node("World/Projectiles").get_child_count() == 0, "Pulse hits once and retires after its visual tail")
	targets = await reset_case([Vector2(-149, 0), Vector2(80, 0), Vector2(151, 0)])
	game.arena.add_wall(Rect2(835, 600, 25, 300))
	await frames()
	game.player.try_dash(Vector2.LEFT)
	game.player.hp = 0
	await frames(45)
	check(targets[0].hp < 10000, "An already committed pulse survives its owner's downed state")
	check(targets[1].hp == 10000 and targets[1].shock_guard == 0, "Solid cover blocks damage and shock")
	check(targets[2].hp == 10000, "The pulse remains bounded to radius 150")
	targets = await reset_case([Vector2(80, 0)], false)
	game.player.try_dash(Vector2.LEFT)
	await frames(45)
	check(targets[0].hp == 10000, "Unblessed dashes retain their original behavior")
	targets = await reset_case([Vector2(80, 0)], false)
	game.campaign_version = 1
	game.player.enchantments[ID] = 1
	game.player.try_dash(Vector2.LEFT)
	await frames(45)
	check(targets[0].hp == 10000, "Legacy dashes cannot trigger a modern skill")

func progression() -> void:
	await reset_case([])
	var boon: Dictionary = game.PROGRESSION.rune(ID)
	check(not boon.is_empty(), "Named dash blessing exists in the reward catalog")
	check(not game.PROGRESSION.can_apply({"stat": ID}, game.player, 2), "A skill cannot stack")
	game.prepare_routes()
	var saved: Dictionary = SAVE.capture(game)
	check(SAVE.valid(saved), "Equipped dash skill belongs to the existing checkpoint transaction")
	for bad_rank in [0, 2, 1.0, true, "1", null]:
		var bad := saved.duplicate(true)
		bad.enchantments[ID] = bad_rank
		check(not SAVE.valid(bad), "Malformed or stacked skill rank is rejected")
	game.start_run(8193)
	check(not game.player.enchantments.has(ID), "New rescue resets per-run dash growth")
	game.PROGRESSION.apply({"stat": ID}, game.player, 1)
	check(not game.player.enchantments.has(ID), "Legacy progression excludes the new skill")
	var found := false
	var legacy_excluded := true
	var opening_kept := true
	var promise_kept := true
	for seed in range(50):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		found = found or game.PROGRESSION.offers(rng, false, {}, game.team(), 2).any(func(b): return b.stat == ID)
		legacy_excluded = legacy_excluded and game.PROGRESSION.offers(rng, false, {}, [], 1).all(func(b): return b.stat != ID)
		opening_kept = opening_kept and game.PROGRESSION.offers(rng, true, {}, game.team(), 2).all(func(b): return b.stat != ID)
		promise_kept = promise_kept and game.PROGRESSION.promised_offers(rng, false, {}, "element", game.team(), 2).any(func(b): return b.stat in game.PROGRESSION.ELEMENTS)
	check(found and legacy_excluded and opening_kept and promise_kept, "Modern rewards offer the skill while preserving opening refits, elemental promises and legacy pools")

func ui_and_storage() -> void:
	game.coop.enabled = true
	game.coop.devices.assign([3, 7])
	game.coop.weapons.assign(["frost", "blade"])
	game.configure_input()
	game.start_run(275)
	for member in game.team(): member.set_physics_process(false)
	await FIXTURE.clear(game)
	game.PROGRESSION.apply({"stat": ID}, game.player, 2)
	game.boon_choices = [game.PROGRESSION.rune(ID), game.PROGRESSION.rune("health"), game.PROGRESSION.rune("damage")]
	game.persistence_enabled = true
	game.save_checkpoint()
	var pending: Dictionary = game.profile.checkpoint.duplicate(true)
	check(SAVE.valid(pending) and pending.boons[0] == ID and not pending.partner.enchantments.has(ID), "Pending skill and independently equipped seats share one valid checkpoint")
	var before := var_to_bytes([game.player.enchantments, game.companion.enchantments, game.rng.state, game.profile.checkpoint])
	var description: String = game.hud.team_upgrade_details(game.boon_choices[0])
	check("已获得" in description and "0.6" in description and "二号席" in description and description.count("冲刺起点") == 1, "Reward preview distinguishes the already equipped seat without repeating the full description")
	for i in range(10): game.hud.team_upgrade_details(game.boon_choices[0])
	check(before == var_to_bytes([game.player.enchantments, game.companion.enchantments, game.rng.state, game.profile.checkpoint]), "Read-only skill preview cannot equip, reroll or save")
	var diagram = load("res://assets/ui/dash_echo.svg") if ResourceLoader.exists("res://assets/ui/dash_echo.svg") else null
	check(diagram != null and diagram.get_size() == Vector2(384, 144), "Dash-to-shock illustration is a bundled vector resource")
	for size in [Vector2i(960, 600), Vector2i(2560, 1440)]:
		root.size = size
		game.hud.show_menu("reward")
		await frames()
		for button in game.hud.menu_buttons():
			check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(button.get_global_rect()), "Skill reward controls fit the viewport")
		check(diagram != null and game.hud.menu_margin.find_children("*", "TextureRect", true, false).any(func(t): return t.texture == diagram), "Reward uses the dash-to-shock illustration")
		await snapshot("reward-%d" % size.x)
	game.open_build()
	await frames()
	check(game.hud.menu_margin.find_children("*", "Label", true, false).any(func(t): return "雷霆残影" in t.text), "Build shows the equipped dash skill and its actual damage")
	await snapshot("build")
	game.hud.update_status()
	check("雷步" in game.hud.skills[2].text and "雷步" not in game.hud.partner_skills[2].text, "Only the equipped seat gets the upgraded dash HUD")
	game.queue_free()
	await frames()
	var loaded = PROFILE.new()
	loaded.load_progress(path)
	await spawn_game(loaded)
	check(loaded.writable and game.continue_saved_run() and game.state == "coop_lobby", "Cold continuation restores the pending choice before pairing")
	check(game.boon_choices.map(func(b): return b.stat) == pending.boons, "Cold continuation preserves the promised skill selection")
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
	check(game.state == "route" and game.team().all(func(m): return m.enchantments.get(ID) == 1), "Real reward confirmation equips the partner once")
	game.queue_free()
	await frames()
	loaded = PROFILE.new()
	loaded.load_progress(path)
	await spawn_game(loaded)
	check(loaded.writable and game.continue_saved_run() and game.team().all(func(m): return m.enchantments.get(ID) == 1), "Both skill owners survive a second cold load")
	game.coop.devices.assign([3, 7])
	game.configure_input()
	game.show_menu("paused")
	game.resume_run()
	for member in game.team(): member.input_armed = true
	var press := InputEventJoypadButton.new()
	press.device = 7
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	Input.parse_input_event(press)
	await frames()
	press = press.duplicate()
	press.pressed = false
	Input.parse_input_event(press)
	check(game.companion.dash_cooldown > 0 and game.player.dash_cooldown == 0, "A real nonzero second controller routes dash independently")
	check(game.get_node("World/Projectiles").get_children().any(func(n): return n.get_script() == game.PROGRESSION.DASH), "Restored skill produces a real delayed pulse through controller input")
	game.persistence_enabled = false
	game.start_run(915)
	await frames()
	check(game.get_node("World/Projectiles").get_child_count() == 0 and game.team().all(func(m): return not m.enchantments.has(ID)), "Restart clears committed pulses and per-run skills")

func coop_relay() -> void:
	var targets := await reset_case([Vector2(80, 0), Vector2(230, 0)], false)
	game.companion.position = game.player.position
	game.player.position += Vector2(0, -200)
	game.settings.values.flash = 0.0
	game.PROGRESSION.apply({"stat": ID}, game.companion, 2)
	check("雷霆残影" in game.BUILD_INFO.reaction_hint("ice", game.player, game.companion), "Ice reward identifies the partner's delayed dash shock")
	check(game.BUILD_INFO.synergies(game.companion).any(func(t): return "雷霆残影" in t), "Build explains how dash shock can join a frozen target")
	check(not game.BUILD_INFO.has_element(game.companion, "shock"), "A dash skill is not mislabeled as a weapon shock rune")
	for member in game.team():
		member.set_physics_process(true)
		member.input_armed = true
	for pair in [[3, JOY_BUTTON_X], [7, JOY_BUTTON_A]]:
		var press := InputEventJoypadButton.new()
		press.device = pair[0]
		press.button_index = pair[1]
		press.pressed = true
		Input.parse_input_event(press)
	await frames()
	for pair in [[3, JOY_BUTTON_X], [7, JOY_BUTTON_A]]:
		var release := InputEventJoypadButton.new()
		release.device = pair[0]
		release.button_index = pair[1]
		Input.parse_input_event(release)
	for member in game.team(): member.set_physics_process(false)
	check(game.player.freeze_cooldown > 0 and game.companion.dash_cooldown > 0, "Two controller inputs independently cast nova and dash")
	check(targets[0].ice_frozen_left > 0 and targets[1].hp == 10000, "First player's nova freezes the source while the relay target is outside nova range")
	var before: float = targets[0].hp
	await snapshot("coop-low-flash")
	await frames(40)
	var damage: float = game.companion.damage * 0.35
	check(is_equal_approx(targets[0].hp, before - damage) and is_equal_approx(targets[1].hp, 10000 - damage * 0.45), "Second player's dash conducts from the first player's freeze")
	check(game.team().all(func(m): return m.hp == m.max_hp), "Shared shock and relay never damage either ally")

func run() -> void:
	await spawn_game()
	await mechanics()
	await progression()
	await ui_and_storage()
	await coop_relay()
	game.queue_free()
	await frames()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	await create_timer(0.25, true, false, true).timeout
	print("ABYSS DASH ECHO: %d checks, %d failures" % [checks, failures])
	if DisplayServer.get_name() != "headless": print("DASH CAPTURES: " + ProjectSettings.globalize_path(capture_dir))
	quit(0 if failures == 0 else 1)
