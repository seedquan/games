extends SceneTree
## Native room gallery, route UI and non-exclusive fullscreen. Isolated saves.
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 3) -> void:
	for i in range(count): await physics_frame
	await process_frame

func snapshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	print("GALLERY FRAME ", name, " size=", root.size, " mode=", DisplayServer.window_get_mode(), " minimum=", root.min_size)
	check(img.get_size() == Vector2i(2560, 1440), "Gallery is rendered at 2560 by 1440")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/qa"))
	check(img.save_png("res://builds/qa/level-" + name + ".png") == OK, "Save actual native room/UI image")

func enter_room(data: Dictionary) -> void:
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	game.next_room(data)
	for member in game.team(): member.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Level presentation requires native rendering")
		quit(1)
		return
	root.size = Vector2i(2560, 1440)
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	game.narrative_enabled = false
	root.add_child(game)
	game.coop.enabled = true
	game.coop.devices.assign([1, 3])
	game.configure_input()
	game.start_run(72219)
	await frames()
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	var seen := {}
	var artwork := {}
	for index in range(160):
		var data: Dictionary = game.ROOMS.generate(2 + (index % 5) * 6, "combat", rng)
		var identity: String = data.get("art", str(data.layout))
		if seen.has(identity): continue
		seen[identity] = true
		if data.has("art"): artwork[data.art] = true
		enter_room(data)
		# Explicit overview for inspecting the full collision silhouette.
		game.set_process(false)
		game.camera.limit_left = -2000
		game.camera.limit_right = 4000
		game.camera.limit_top = -2000
		game.camera.limit_bottom = 4000
		game.camera.position = game.arena.bounds.get_center()
		game.camera.zoom = Vector2.ONE * 0.31
		game.camera.reset_smoothing()
		game.hud.update_status()
		await frames()
		await snapshot("region-%d-room-%02d" % [data.chapter, data.layout])
	check(seen.size() >= 10, "Regional pools render artwork and at least ten distinct room identities")
	for depth in [6, 12, 18, 24, 30]:
		var data: Dictionary = game.ROOMS.generate(depth, "boss", rng)
		enter_room(data)
		artwork[data.art] = true
		game.camera.position = game.arena.bounds.get_center()
		game.camera.zoom = Vector2.ONE * 0.31
		game.camera.reset_smoothing()
		await frames()
		await snapshot("region-%d-guardian" % data.chapter)
	check(artwork.size() == 10, "Every supplied exploration and guardian map renders in its real room")
	game.set_process(true)
	var playable: Dictionary = game.ROOMS.generate(26, "combat", rng)
	for attempt in range(100):
		if playable.has("art"): break
		playable = game.ROOMS.generate(26, "combat", rng)
	check(playable.has("art"), "Shared combat view uses the supplied calibrated artwork")
	enter_room(playable)
	await frames(30)
	await snapshot("shared-combat")
	game.boon_choices = game.PROGRESSION.promised_offers(rng, true, {}, "damage", game.team(), game.campaign_version)
	game.show_menu("reward")
	await frames()
	for control in game.hud.menu_margin.find_children("*", "Button", true, false):
		check(root.get_visible_rect().encloses(control.get_global_rect()), "Blessing descriptions fit the QHD display")
	await snapshot("blessings")
	game.room = 1
	game.route_history.assign(["combat"])
	game.prepare_routes()
	await frames()
	for control in game.hud.menu_margin.find_children("*", "Button", true, false):
		check(root.get_visible_rect().encloses(control.get_global_rect()), "Route buttons fit the QHD display")
	await snapshot("routes")
	game.open_settings()
	await frames()
	await snapshot("settings")
	var before_fullscreen := root.size
	print("WINDOW BEFORE FULLSCREEN: ", before_fullscreen)
	game.set_setting("fullscreen", true)
	await frames(120)
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Uses native fullscreen rather than exclusive display takeover")
	game.set_setting("fullscreen", false)
	await frames(120)
	print("WINDOW AFTER FULLSCREEN: ", root.size, " display=", DisplayServer.window_get_size())
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "Returns to a normal decorated window")
	check(root.size == before_fullscreen, "Fullscreen round trip restores the previous window size")
	game.queue_free()
	await frames()
	print("ABYSS LEVEL PRESENTATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
