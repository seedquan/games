extends SceneTree
## Normal-rules playthrough driven through Input actions. No health, damage,
## cooldown, enemy removal, or progression overrides. This is a bot, not a user study.

var game
var cooperative := "--coop" in OS.get_cmdline_user_args()
var ticks := 0
var reports: Array = []
var visited_room := 0
var room_started := 0.0
var next_progress := 60.0

func _initialize() -> void:
	run.call_deferred()

func axis(negative: String, positive: String, value: float, player) -> void:
	negative = player.action(negative)
	positive = player.action(positive)
	Input.action_release(negative)
	Input.action_release(positive)
	if absf(value) > 0.08:
		Input.action_press(negative if value < 0 else positive, absf(value))

func release_controls() -> void:
	for action in ["slash", "bolt", "dash", "freeze", "parry", "move_left", "move_right", "move_up", "move_down", "aim_left", "aim_right", "aim_up", "aim_down"]:
		for member in game.team():
			Input.action_release(member.action(action))

func combat_input(player) -> void:
	if player.hp <= 0.0:
		return
	var target = game.nearest_enemy(player.position)
	if not is_instance_valid(target):
		return
	var direction: Vector2 = player.position.direction_to(target.position)
	var distance: float = player.position.distance_to(target.position)
	var movement := Vector2.ZERO
	if not game.has_sight(player.position, target.position):
		movement = game.arena.steering(player.position, target.position)
	else:
		movement = direction * clampf((distance - 300) / 100, -1, 1) + direction.orthogonal() * 0.75
	for enemy in get_nodes_in_group("enemies"):
		var separation: Vector2 = player.position - enemy.position
		if separation.length() < 140:
			movement += separation.normalized() * (140 - separation.length()) / 55
	var next: Vector2 = player.position + movement.normalized() * 85
	if not game.ROOMS.walkable(next, game.arena.cover, 28, game.arena.bounds, game.arena.obstacles):
		movement = game.arena.steering(player.position, game.arena.bounds.get_center())
	movement = movement.limit_length()
	axis("move_left", "move_right", movement.x, player)
	axis("move_up", "move_down", movement.y, player)
	axis("aim_left", "aim_right", direction.x, player)
	axis("aim_up", "aim_down", direction.y, player)
	Input.action_press(player.action("slash"))
	Input.action_press(player.action("bolt"))
	Input.action_release(player.action("dash"))
	Input.action_release(player.action("freeze"))
	Input.action_release(player.action("parry"))
	var threats := 0
	for enemy in get_nodes_in_group("enemies"):
		if player.position.distance_to(enemy.position) < 210:
			threats += 1
		if enemy.attacking and enemy.windup < 0.2 and player.position.distance_to(enemy.position) < 160:
			Input.action_press(player.action("dash"))
	if threats >= 3:
		Input.action_press(player.action("freeze"))
	for danger in game.get_node("World/Projectiles").get_children():
		if danger.get_script() == game.HAZARD and player.position.distance_to(danger.position) < danger.radius + 35:
			Input.action_press(player.action("dash"))

func record_room() -> void:
	if visited_room != game.room:
		if visited_room:
			var entry := {"room": visited_room, "elapsed": snappedf(game.elapsed - room_started, 0.1), "hp_after": snappedf(game.player.hp, 0.1)}
			reports.append(entry)
			print("ABYSS PLAYTHROUGH ROOM: ", JSON.stringify(entry))
		visited_room = game.room
		room_started = game.elapsed
	if game.elapsed >= next_progress:
		next_progress = game.elapsed + 60.0
		print("ABYSS PLAYTHROUGH PROGRESS: ", JSON.stringify(diagnostics()))

func diagnostics() -> Dictionary:
	var actors := []
	var hostiles := []
	for member in game.team():
		actors.append({"hp": snappedf(member.hp, 0.1), "position": [snappedf(member.position.x, 0.1), snappedf(member.position.y, 0.1)]})
	for enemy in get_nodes_in_group("enemies"):
		hostiles.append({"kind": enemy.kind, "hp": snappedf(enemy.hp, 0.1), "position": [snappedf(enemy.position.x, 0.1), snappedf(enemy.position.y, 0.1)]})
	return {"room": game.room, "name": game.room_data.name, "state": game.state, "room_seconds": snappedf(game.elapsed - room_started, 0.1), "game_seconds": snappedf(game.elapsed, 0.1), "actors": actors, "enemies": hostiles, "wave": game.encounter.wave, "pending": game.encounter.pending.size()}

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	game.selected_weapon = "rifle"
	if cooperative:
		game.coop.enabled = true
		game.coop.devices.assign([1, 3])
		game.coop.weapons.assign(["rifle", "rifle"])
		game.configure_input()
	game.start_run(314159)
	game.using_gamepad = true
	# Fixed physics steps at four times wall speed; gameplay's delta stays 1/60.
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4
	var budget: float = game.run_length * 60.0
	var wall_deadline := Time.get_ticks_msec() + 600000
	while game.state not in ["victory", "dead"] and game.elapsed < budget and ticks < int(budget * 64) and Time.get_ticks_msec() < wall_deadline:
		ticks += 1
		record_room()
		match game.state:
			"story":
				release_controls()
				game.continue_story()
			"playing":
				for member in game.team():
					combat_input(member)
			"reward":
				release_controls()
				var choice := 0
				for i in range(game.boon_choices.size()):
					if game.boon_choices[i].stat in ["damage", "leech"]:
						choice = i
				game.choose_boon(choice)
			"route":
				release_controls()
				var choice := 0
				for i in range(game.route_choices.size()):
					if game.route_choices[i].kind == "rest":
						choice = i
				game.choose_route(choice)
			"shop":
				release_controls()
				for i in range(game.shop_stock.size()):
					if game.can_buy(i):
						game.buy_item(i)
				game.leave_supply()
			"rest": game.leave_supply()
		await physics_frame
		await process_frame
	release_controls()
	var report := {"driver": "Input-action bot; normal player/enemy stats; 4x simulation", "seed": 314159,
		"cooperative": cooperative, "weapon": "rifle", "result": game.state, "depth": game.room, "game_seconds": game.elapsed,
		"hp": game.player.hp, "kills": game.kills, "story_beats": game.story_seen, "rooms": reports}
	report.last_room = diagnostics()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/qa"))
	var file := FileAccess.open("res://builds/qa/playthrough-coop.json" if cooperative else "res://builds/qa/playthrough.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	var success: bool = game.state == "victory"
	game.queue_free()
	await process_frame
	quit(0 if success else 1)
