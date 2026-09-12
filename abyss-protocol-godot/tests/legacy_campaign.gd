extends SceneTree
## Resume complete pre-expansion checkpoints from disk, including pending story.
const LEGACY = preload("res://scripts/legacy_rooms.gd")
const SAVE = preload("res://scripts/run_save.gd")
const PROFILE = preload("res://scripts/profile.gd")
const ENCOUNTER_FIXTURE = preload("res://tests/encounter_fixture.gd")
var checks := 0
var failures := 0
var game
var path := "user://test-legacy-campaign-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]

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
	game.auto_pause_enabled = false
	if profile != null:
		game.profile = profile
	game.profile.save_path = path
	root.add_child(game)
	await frame()
	# Enable only after _ready to keep both normal profile and settings isolated.
	game.persistence_enabled = true

func legacy_doors() -> void:
	var oracle := RandomNumberGenerator.new()
	oracle.state = game.rng.state
	var expected: Array = []
	for kind in LEGACY.choices(game.room + 1):
		expected.append(LEGACY.generate(game.room + 1, kind, oracle))
	if game.state == "reward":
		game.choose_boon(0)
	else:
		game.leave_supply()
	check(game.route_choices == expected, "Legacy door geometry and spawn order preserve the original generator sequence")
	check(game.rng.state == oracle.state, "Legacy routes never consume new layout-reroll randomness")

func advance() -> void:
	match game.state:
		"story": game.continue_story()
		"playing":
			game.player.set_physics_process(false)
			await ENCOUNTER_FIXTURE.clear(game)
		"reward", "shop", "rest": legacy_doors()
		"route": game.choose_route(0)
	await frame()

func run() -> void:
	for target in [6, 9, 12]:
		await spawn_game()
		game.start_run(13001 + target)
		# Recreate an original campaign using its retained implementation. The
		# subsequent on-disk fixture removes the fields absent from 0.10.1 saves.
		for enemy in get_nodes_in_group("enemies"):
			enemy.get_parent().remove_child(enemy)
			enemy.queue_free()
		game.campaign_version = 1
		game.run_length = LEGACY.LAST_ROOM
		game.route_history.clear()
		game.story_seen.clear()
		game.next_room(LEGACY.generate(1, "combat", game.rng))
		var steps := 0
		while not (game.room == target and game.state == "story") and steps < LEGACY.LAST_ROOM * 6:
			steps += 1
			await advance()
		check(game.room == target and game.state == "story", "Reach the authentic legacy safe point at chamber %d" % target)
		var saved: Dictionary = game.profile.checkpoint.duplicate(true)
		saved.erase("campaign")
		saved.room.erase("generator")
		for recipe in saved.routes:
			recipe.erase("generator")
		check(SAVE.valid(saved), "Checkpoint without campaign or generator fields remains supported")
		var original_room: Dictionary = game.room_data.duplicate(true)
		var cores: int = game.profile.cores
		var runs: int = game.profile.runs
		game.profile.checkpoint = saved
		check(game.profile.save_progress() == OK, "Write the complete legacy checkpoint in the isolated profile transaction")
		game.queue_free()
		await frame()
		var loaded = PROFILE.new()
		loaded.load_progress(path)
		check(loaded.writable and not loaded.checkpoint.has("campaign"), "Cold load accepts the original schema without overwriting it")
		await spawn_game(loaded)
		check(game.continue_saved_run(), "Resume the legacy checkpoint from the title")
		check(game.campaign_version == 1 and game.run_length == 12, "Legacy rescue still ends at chamber twelve")
		check(game.room_data == original_room and game.state == "story" and game.story_id == saved.story_id, "Resume preserves exact chamber geometry and the pending story")
		check(game.profile.cores == cores and game.profile.runs == runs, "Resuming legacy progress duplicates neither rewards nor deployments")
		steps = 0
		while game.state not in ["victory", "dead"] and steps < LEGACY.LAST_ROOM * 6:
			steps += 1
			await advance()
		check(game.state == "victory" and game.room == 12, "Legacy checkpoint at %d completes its twelve-chamber campaign" % target)
		check(game.story_seen == ["awakening", "records", "warden", "calibration", "core", "ending"], "Legacy story keeps all original milestones in order")
		loaded = PROFILE.new()
		loaded.load_progress(path)
		check(loaded.writable and loaded.wins == 1 and loaded.checkpoint.is_empty(), "Legacy victory is durable and cannot resume for duplicate rewards")
		game.queue_free()
		await frame()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("ABYSS LEGACY CAMPAIGN: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
