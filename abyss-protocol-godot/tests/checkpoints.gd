extends SceneTree
const ENCOUNTER_FIXTURE = preload("res://tests/encounter_fixture.gd")
## Recreate the game from disk at every safe state on both campaign branches.

const PROFILE = preload("res://scripts/profile.gd")
const RUN_SAVE = preload("res://scripts/run_save.gd")
var game
var checks := 0
var failures: Array[String] = []
var path := "user://test-checkpoint-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]

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

func spawn_game(profile = null) -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	if profile != null:
		game.profile = profile
		game.selected_weapon = profile.weapon
	game.profile.save_path = path
	root.add_child(game)
	await frames()
	# Enable only after _ready: isolate normal profile and settings from this test.
	game.persistence_enabled = true

func reboot() -> bool:
	var before: Dictionary = game.profile.checkpoint.duplicate(true)
	check(RUN_SAVE.valid(before), "Current safe point validates: " + game.state)
	if not RUN_SAVE.valid(before):
		return false
	var cores: int = game.profile.cores
	var runs: int = game.profile.runs
	check(FileAccess.file_exists(path), "Transition automatically writes checkpoint and meta progress")
	game.queue_free()
	await frames()
	var loaded = PROFILE.new()
	loaded.load_progress(path)
	check(loaded.writable and equivalent(loaded.checkpoint, before), "Safe point round-trips through ConfigFile")
	await spawn_game(loaded)
	check(game.continue_saved_run(), "Title can resume the saved rescue")
	await frames()
	check(game.profile.cores == cores and game.profile.runs == runs, "Continue neither duplicates cores nor counts as a new run")
	check(game.rng.state == before.rng_state, "Continue restores the future choice RNG")
	check(game.room_data == RUN_SAVE.rebuild_room(before.room), "Continue reproduces geometry and enemy spawn order")
	check(game.player.enchantments == before.enchantments and is_equal_approx(game.player.damage, before.stats.damage), "Continue preserves weapon damage and all runes")
	check(is_equal_approx(game.player.hp, before.stats.hp) and game.purchased == before.purchased, "Continue cannot duplicate healing or reset purchased stock")
	check(game.player.weapon.definition.id == before.weapon, "Continue restores this run's weapon")
	if before.state == "playing":
		check(game.state == "paused" and not game.player.can_process(), "Combat resumes behind a pause screen")
		game.resume_run()
	else:
		check(game.state == before.state, "Menus and story resume at the saved decision")
	game.player.set_physics_process(false)
	return true

func run() -> void:
	for branch in [0, 1]:
		await spawn_game()
		game.selected_weapon = "lbow" if branch == 0 else "frost"
		game.start_run(713 + branch)
		var steps := 0
		while game.state not in ["victory", "dead"] and steps < game.run_length * 5:
			steps += 1
			if game.state == "story" and game.story_id == "ending":
				game.continue_story()
				break
			if not await reboot():
				break
			match game.state:
				"story": game.continue_story()
				"playing":
					var banked: int = game.profile.cores
					await ENCOUNTER_FIXTURE.clear(game)
					await frames()
					check(game.profile.cores > banked, "Clearing a restored combat room still rewards progression")
					var after: int = game.profile.cores
					game.complete_room()
					check(game.profile.cores == after, "Repeated clear after restore cannot duplicate a reward")
				"reward": game.choose_boon(steps % 3)
				"route": game.choose_route(mini(branch, game.route_choices.size() - 1))
				"shop":
					if game.can_buy(1):
						game.buy_item(1)
						var spent: int = game.scrap
						await reboot()
						check(not game.buy_item(1) and game.scrap == spent, "Bought tuning stays sold after a disk round-trip")
					game.leave_supply()
				"rest": game.leave_supply()
		check(game.state == "victory", "A campaign repeatedly resumed from disk reaches victory on branch %d" % branch)
		check(game.profile.checkpoint.is_empty(), "A successful run cannot be resumed for duplicate victory rewards")
		game.start_run(991)
		game.continue_story()
		game.player.invulnerable = 0
		game.player.take_damage(1000000, Vector2.ZERO)
		check(game.state == "dead" and game.profile.checkpoint.is_empty(), "Death invalidates the safe point")
		game.queue_free()
		await frames()
	await malformed_cases()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("ABYSS CHECKPOINTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func malformed_cases() -> void:
	await spawn_game()
	game.start_run(882)
	game.continue_story()
	var saved: Dictionary = game.profile.checkpoint.duplicate(true)
	for field in saved.keys():
		var missing := saved.duplicate(true)
		missing.erase(field)
		check(not RUN_SAVE.valid(missing), "Incomplete safe point rejects missing field " + field)
	for change in [["hp", NAN], ["hp", 0], ["max_hp", "invalid"], ["damage", INF]]:
		var bad := saved.duplicate(true)
		bad.stats[change[0]] = change[1]
		check(not RUN_SAVE.valid(bad), "Invalid stats cannot instantiate an unstable player")
	var wrong := saved.duplicate(true)
	wrong.room.kind = "unknown"
	check(not RUN_SAVE.valid(wrong), "Unknown room types are rejected before reconstruction")
	wrong = saved.duplicate(true)
	wrong.routes = [{"depth": 2, "kind": "boss", "generation_state": 1}]
	check(not RUN_SAVE.valid(wrong), "Invalid route recipes are rejected")
	wrong = saved.duplicate(true)
	wrong.version = 100
	game.profile.checkpoint = wrong
	game.profile.save_progress()
	var loaded = PROFILE.new()
	loaded.load_progress(path)
	check(not loaded.writable and loaded.checkpoint.is_empty(), "Unsupported checkpoint schemas preserve the original profile file")
	# A process interruption can leave only the backup generation.
	game.profile.checkpoint = saved
	game.profile.save_progress()
	game.profile.save_progress()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	loaded = PROFILE.new()
	loaded.load_progress(path)
	check(loaded.writable and equivalent(loaded.checkpoint, saved), "Missing primary recovers the complete backup checkpoint")
	# Old meta-only profiles migrate without losing progress.
	var legacy := ConfigFile.new()
	legacy.set_value("profile", "version", 1)
	legacy.set_value("profile", "cores", 135)
	legacy.set_value("upgrades", "power", 3)
	legacy.save(path)
	loaded = PROFILE.new()
	loaded.load_progress(path)
	check(loaded.cores == 135 and loaded.upgrades.power == 3 and loaded.checkpoint.is_empty(), "Version one progress migrates without inventing a current run")
	check(loaded.save_progress() == OK, "Migrated progress writes the current schema")
	game.queue_free()
	await frames()

func equivalent(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_FLOAT, TYPE_INT] and typeof(b) in [TYPE_FLOAT, TYPE_INT]:
		# ConfigFile uses human-readable float precision; RNG state stays int64.
		return a == b if a is int and b is int else is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not equivalent(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not equivalent(a[i], b[i]):
				return false
		return true
	return a == b
