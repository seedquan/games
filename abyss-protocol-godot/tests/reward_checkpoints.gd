extends SceneTree
## Capped upgrades can leave one or two useful rewards; both must survive disk.
const PROFILE = preload("res://scripts/profile.gd")
const SAVE = preload("res://scripts/run_save.gd")
const PROGRESSION = preload("res://scripts/progression.gd")
const ENCOUNTER_FIXTURE = preload("res://tests/encounter_fixture.gd")
var checks := 0
var failures := 0
var game
var path := "user://test-reward-checkpoint-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frame() -> void:
	await physics_frame
	await process_frame

func spawn_game(profile = null) -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	if profile != null: game.profile = profile
	game.profile.save_path = path
	root.add_child(game)
	await frame()
	game.persistence_enabled = true

func run() -> void:
	for count in [1, 2]:
		await spawn_game()
		game.start_run(99231 + count)
		# Deliberately assemble the capped edge state, then let real combat and
		# progression generate its offers and perform the normal save transaction.
		game.player.damage = PROGRESSION.MAX_DAMAGE
		game.player.max_hp = PROGRESSION.MAX_HEALTH
		game.player.hp = PROGRESSION.MAX_HEALTH
		game.player.move_speed = PROGRESSION.MAX_SPEED
		game.player.dash_recharge = PROGRESSION.MIN_DASH_RECHARGE
		for element in PROGRESSION.ELEMENTS: game.player.enchantments[element] = 3
		for index in range(count): game.player.enchantments[PROGRESSION.ELEMENTS[index]] = 2
		game.player.set_physics_process(false)
		await ENCOUNTER_FIXTURE.clear(game)
		check(game.state == "reward" and game.boon_choices.size() == count, "Real capped progression produces exactly %d useful reward choices" % count)
		var before: Dictionary = game.profile.checkpoint.duplicate(true)
		check(SAVE.valid(before), "A %d-choice reward checkpoint validates" % count)
		var banked: int = game.profile.cores
		var runs: int = game.profile.runs
		game.queue_free()
		await frame()
		var loaded = PROFILE.new()
		loaded.load_progress(path)
		check(loaded.writable and loaded.checkpoint.boons == before.boons, "Cold loading retains the partial reward list and writable profile")
		await spawn_game(loaded)
		check(game.continue_saved_run() and game.state == "reward", "Continue returns to the exact outstanding reward decision")
		check(game.boon_choices.map(func(boon): return boon.stat) == before.boons, "Resume neither rerolls nor pads the remaining useful choices")
		check(game.profile.cores == banked and game.profile.runs == runs, "Reward resume duplicates neither cores nor deployments")
		var chosen: String = game.boon_choices[0].stat
		game.choose_boon(0)
		check(game.player.enchantments[chosen] == 3 and game.state == "route", "A restored choice upgrades the rune and advances to routes")
		game.complete_room()
		check(game.profile.cores == banked, "Choosing a restored reward cannot award the chamber twice")
		loaded = PROFILE.new()
		loaded.load_progress(path)
		check(loaded.writable and loaded.checkpoint.state == "route" and loaded.checkpoint.enchantments[chosen] == 3, "The chosen upgrade persists in the same valid route transaction")
		var invalid := before.duplicate(true)
		invalid.boons = []
		check(not SAVE.valid(invalid), "An empty reward would strand the player and is rejected")
		invalid = before.duplicate(true)
		invalid.boons = [chosen, chosen]
		check(not SAVE.valid(invalid), "Duplicate choices are rejected for new campaigns")
		invalid = before.duplicate(true)
		invalid.boons = ["damage", "health", "speed", "fire"]
		check(not SAVE.valid(invalid), "Rewards exceeding the three-slot UI remain invalid")
		var story := before.duplicate(true)
		story.state = "story"
		story.story_id = "warden"
		story.story_return = "reward"
		check(SAVE.valid(story), "Pending guardian story can return to a partial reward decision")
		var legacy := before.duplicate(true)
		legacy.erase("campaign")
		legacy.room.erase("generator")
		check(not SAVE.valid(legacy), "Original campaigns still require the original three-choice reward shape")
		legacy.boons = ["damage", "health", "speed"]
		check(SAVE.valid(legacy), "The complete original reward schema remains supported")
		game.queue_free()
		await frame()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("ABYSS REWARD CHECKPOINTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
