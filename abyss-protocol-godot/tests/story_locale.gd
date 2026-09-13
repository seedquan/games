extends SceneTree
const ENCOUNTER_FIXTURE = preload("res://tests/encounter_fixture.gd")
## Covers the player-facing Chinese UI and story milestones on a complete route.
const FONT = preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
var game
var failures: Array[String] = []
var checks := 0
var checked_chars: Dictionary = {}
var english := RegEx.new()

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

func inspect_ui(context: String) -> void:
	var pending: Array[Node] = [game.hud]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if (node is Label or node is Button) and node.is_visible_in_tree():
			var text: String = node.text
			for match_text in english.search_all(text):
				var token: String = match_text.get_string()
				check(token in ["WASD", "Esc", "Tab", "J", "E", "Q", "L", "M", "F"], context + " has an untranslated UI token: " + token)
			for i in range(text.length()):
				var code := text.unicode_at(i)
				if code >= 0x2000 and not checked_chars.has(code):
					checked_chars[code] = true
					check(FONT.has_char(code), "Bundled font covers U+%04X" % code)
	# Menu content must fit the designed viewport; scrolling is allowed in the armory.
	for content in game.hud.menu_margin.get_children():
		check(content.get_minimum_size().y <= 720.0, context + " fits vertically at 1440x900")
		check(content.get_minimum_size().x <= 1260.0, context + " fits horizontally at 1440x900")

func run() -> void:
	root.size = Vector2i(1440, 900)
	english.compile("[A-Za-z]+")
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	await frames()
	inspect_ui("title")
	game.open_armory()
	await frames()
	inspect_ui("armory")
	for form in game.WEAPONS.FORMS:
		check(english.search(form.name + form.description) == null, "Chinese weapon name and description: " + form.id)
	game.armory_back()
	game.open_workbench()
	await frames()
	inspect_ui("workbench")
	game.start_run(1701)
	await frames()
	check(game.state == "story" and game.story_id == "awakening", "Starting a run presents the rescue premise")
	var story_order: Array[String] = []
	var safety := 0
	while game.state != "victory" and safety < game.run_length * 5:
		safety += 1
		await frames()
		inspect_ui(game.state)
		match game.state:
			"story":
				story_order.append(game.story_id)
				var time: float = game.elapsed
				await frames(4)
				check(game.elapsed == time and not game.player.can_process(), "Story pauses combat and the run timer")
				game.continue_story()
				var destination: String = game.state
				game.continue_story()
				check(game.state == destination, "Repeated story activation cannot advance twice")
			"playing":
				if game.room == 1:
					game.show_menu("paused")
					await frames()
					inspect_ui("pause")
					game.resume_run()
				game.player.set_physics_process(false)
				await ENCOUNTER_FIXTURE.clear(game)
				await frames()
			"reward": game.choose_boon(0)
			"route": game.choose_route(0)
			"shop", "rest": game.leave_supply()
			_:
				check(false, "Unexpected narrative state: " + game.state)
				break
	check(game.state == "victory", "The full story route reaches a rescue ending")
	check(story_order == ["awakening", "records", "warden", "calibration", "core", "ending"], "Story reveals evidence, authorization and resolution in causal order")
	await frames()
	inspect_ui("victory")
	# Take the opposite branch at every choice: combat replaces supplies at 3/9,
	# and repair replaces combat at 4/10. All essential story beats must survive.
	game.start_run(1702)
	var alternate: Array[String] = []
	safety = 0
	while game.state != "victory" and safety < game.run_length * 5:
		safety += 1
		await frames()
		match game.state:
			"story":
				alternate.append(game.story_id)
				game.continue_story()
			"playing":
				game.player.set_physics_process(false)
				await ENCOUNTER_FIXTURE.clear(game)
				await frames()
			"reward": game.choose_boon(0)
			"route": game.choose_route(game.route_choices.size() - 1)
			"shop", "rest":
				inspect_ui(game.state)
				game.leave_supply()
			_: break
	check(game.state == "victory" and alternate == story_order, "Opposite routes preserve every required story milestone and ending")
	var earned: int = game.profile.cores
	var wins: int = game.profile.wins
	game.finish_run(true)
	check(game.profile.cores == earned and game.profile.wins == wins, "Ending cannot duplicate victory rewards")
	game.start_run(1701)
	await frames()
	check(game.story_seen == ["awakening"], "A new run resets narrative milestones")
	game.continue_story()
	game.player.invulnerable = 0
	game.player.take_damage(1000000.0, Vector2.ZERO)
	await frames()
	inspect_ui("death")
	check(game.state == "dead" and "ending" not in game.story_seen, "Failure does not show a successful rescue")
	game.queue_free()
	await process_frame
	print("ABYSS STORY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
