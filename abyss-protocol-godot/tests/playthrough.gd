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
var room_limit := 30
var simulation_speed := 4
var weapon_id := "rifle"
var captured := {}
var combat_physics_frames := 0
var reactions: Dictionary = {}
var guardian_shapes := 0
var trace_damage := "--trace-damage" in OS.get_cmdline_user_args()
var damage_events: Array = []
var projectile_defense := "--projectile-defense" in OS.get_cmdline_user_args()
var countershots := 0
var controls = preload("res://tests/bot_input.gd").new()
var skill_activations := {"dash": 0, "freeze": 0, "parry": 0}
var previous_cooldowns: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func count_combat_frame() -> void:
	if is_instance_valid(game) and game.state == "playing": combat_physics_frames += 1

func axis(negative: String, positive: String, value: float, player) -> void:
	negative = player.action(negative)
	positive = player.action(positive)
	Input.action_release(negative)
	Input.action_release(positive)
	if absf(value) > 0.08:
		Input.action_press(negative if value < 0 else positive, absf(value))

func release_controls() -> void:
	controls.release()
	for action in ["slash", "bolt", "dash", "freeze", "parry", "move_left", "move_right", "move_up", "move_down", "aim_left", "aim_right", "aim_up", "aim_down"]:
		for member in game.team():
			if Input.is_action_pressed(member.action(action)): Input.action_release(member.action(action))

func combat_input(player) -> void:
	if player.hp <= 0.0:
		return
	for skill in skill_activations:
		var key: String = player.action(skill)
		var cooldown: float = player.get(skill + "_cooldown")
		if cooldown > float(previous_cooldowns.get(key, 0.0)) + 0.05: skill_activations[skill] += 1
		previous_cooldowns[key] = cooldown
	var target = game.nearest_enemy(player.position)
	if not is_instance_valid(target):
		return
	var direction: Vector2 = player.position.direction_to(target.position)
	var distance: float = player.position.distance_to(target.position)
	var definition: Dictionary = player.weapon.definition
	var close_weapon: bool = definition.mode in ["melee", "gravity"]
	var preferred: float = maxf(70, float(definition.get("reach", 160)) * 0.75) if close_weapon else 150.0 if definition.id == "scatter" else 300.0
	var movement := Vector2.ZERO
	if not game.has_sight(player.position, target.position):
		movement = game.arena.steering(player.position, target.position)
	else:
		movement = direction * clampf((distance - preferred) / 100, -1, 1) + direction.orthogonal() * 0.75
	for enemy in get_nodes_in_group("enemies"):
		var separation: Vector2 = player.position - enemy.position
		var personal_space := (55.0 if enemy == target else 90.0) if close_weapon else 140.0
		if separation.length() < personal_space:
			movement += separation.normalized() * (personal_space - separation.length()) / 55
	var next: Vector2 = player.position + movement.normalized() * 85
	if not game.ROOMS.walkable(next, game.arena.cover, 28, game.arena.bounds, game.arena.obstacles):
		movement = game.arena.steering(player.position, game.arena.bounds.get_center())
	movement = movement.limit_length()
	axis("move_left", "move_right", movement.x, player)
	axis("move_up", "move_down", movement.y, player)
	axis("aim_left", "aim_right", direction.x, player)
	axis("aim_up", "aim_down", direction.y, player)
	if definition.has("charge") and player.weapon.charge >= definition.charge:
		controls.button(player.action("slash"), false)
	else:
		controls.button(player.action("slash"), true)
	controls.button(player.action("bolt"), true)
	var wants_dash := false
	var wants_freeze := false
	var wants_parry := false
	var threats := 0
	for enemy in get_nodes_in_group("enemies"):
		if player.position.distance_to(enemy.position) < 210:
			threats += 1
		if enemy.attacking and enemy.windup < 0.2 and player.position.distance_to(enemy.position) < 160:
			wants_dash = true
			if close_weapon: wants_parry = true
	if threats >= 3:
		wants_freeze = true
	for danger in game.get_node("World/Projectiles").get_children():
		if danger.get_script() == game.HAZARD and player.position.distance_to(danger.position) < danger.radius + 35:
			wants_dash = true
		elif danger.get_script() == game.GUARDIAN_ATTACK and not danger.fired and danger.delay - danger.elapsed < 0.23 and danger.contains_point(player.position):
			wants_dash = true
		elif projectile_defense and danger.get_script() == preload("res://scripts/projectile.gd") and danger.hostile:
			var offset: Vector2 = danger.position - player.position
			var relative_velocity: Vector2 = danger.direction * danger.speed - player.velocity
			if relative_velocity.length_squared() < 1.0: continue
			var contact_time: float = -offset.dot(relative_velocity) / relative_velocity.length_squared()
			if contact_time < 0.0 or contact_time > 0.12: continue
			if (offset + relative_velocity * contact_time).length() > 30.0: continue
			if not game.has_sight(danger.position, player.position): continue
			if player.parry_cooldown <= 0.0:
				wants_parry = true
			elif player.invulnerable <= 0.0:
				wants_dash = true
	controls.button(player.action("dash"), wants_dash)
	controls.button(player.action("freeze"), wants_freeze)
	controls.button(player.action("parry"), wants_parry)

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

func trace_hit(effect) -> void:
	# Observe the existing, synchronous player-hit effect; no combat interception.
	# This diagnostic marker is emitted only after real HP loss in player.gd.
	if not trace_damage or effect.get_script() != game.EFFECT or effect.color != Color("ff6a80") or effect.radius != 50.0:
		return
	if damage_events.size() >= 512: return
	var member = game.player
	for candidate in game.team():
		if candidate.position.distance_squared_to(effect.position) < member.position.distance_squared_to(effect.position): member = candidate
	var enemies := []
	for enemy in get_nodes_in_group("enemies"):
		enemies.append({"kind": enemy.kind, "distance": member.position.distance_to(enemy.position), "attacking": enemy.attacking,
			"windup": enemy.windup, "frozen": enemy.frozen, "position": [enemy.position.x, enemy.position.y]})
	var shots := []
	for shot in game.get_node("World/Projectiles").get_children():
		if shot.get_script() == preload("res://scripts/projectile.gd") and shot.hostile and shot.position.distance_to(member.position) < 100:
			shots.append({"position": [shot.position.x, shot.position.y], "direction": [shot.direction.x, shot.direction.y], "speed": shot.speed})
	var event := {"room": game.room, "seconds": game.elapsed, "seat": member.seat, "hp_after": member.hp,
		"position": [member.position.x, member.position.y], "dash_cooldown": member.dash_cooldown,
		"parry_cooldown": member.parry_cooldown, "energy": member.energy, "enemies": enemies, "shots": shots,
		"stack": get_stack().map(func(entry): return {"source": entry.source, "function": entry.function})}
	damage_events.append(event)
	print("ABYSS PLAYTHROUGH HIT: ", JSON.stringify(event))

func run() -> void:
	# Enemy attack offsets and scattered projectiles use the global RNG.
	seed(314159)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rooms="): room_limit = clampi(argument.get_slice("=", 1).to_int(), 1, 30)
		if argument.begins_with("--speed="): simulation_speed = clampi(argument.get_slice("=", 1).to_int(), 1, 16)
		if argument.begins_with("--weapon="): weapon_id = argument.get_slice("=", 1)
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	game.get_node("World/Effects").child_entered_tree.connect(trace_hit)
	game.get_node("World/Effects").child_entered_tree.connect(func(node):
		if node.get_script() == game.EFFECT and not node.reaction.is_empty():
			reactions[node.reaction] = int(reactions.get(node.reaction, 0)) + 1)
	game.get_node("World/Projectiles").child_entered_tree.connect(func(node):
		if node.get_script() == game.GUARDIAN_ATTACK: guardian_shapes += 1
		elif node.get_script() == preload("res://scripts/projectile.gd"):
			node.tree_exiting.connect(func():
				if node.reflected: countershots += 1))
	if not game.WEAPONS.exists(weapon_id):
		push_error("Unknown playthrough weapon")
		quit(1)
		return
	game.selected_weapon = weapon_id
	if cooperative:
		game.coop.enabled = true
		game.coop.devices.assign([1, 3])
		game.coop.weapons.assign([weapon_id, weapon_id])
		game.configure_input()
	game.start_run(314159)
	game.using_gamepad = true
	# Accelerate only wall time; gameplay's physics delta remains 1/60.
	Engine.max_physics_steps_per_frame = 64
	Engine.physics_ticks_per_second = 60 * simulation_speed
	physics_frame.connect(count_combat_frame)
	Engine.time_scale = simulation_speed
	var budget: float = game.run_length * 240.0
	var wall_deadline := Time.get_ticks_msec() + 600000
	while game.state not in ["victory", "dead"] and game.elapsed < budget and game.room <= room_limit and ticks < int(budget * 64) and Time.get_ticks_msec() < wall_deadline:
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
		# Sample input every simulated physics step, including accelerated runs.
		# Waiting for render here reduces bot reaction speed as simulation speed rises.
		await physics_frame
		if DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args() and game.state == "playing" and game.room == visited_room and game.room in [1, 2, 6] and not captured.has(game.room) and game.elapsed - room_started > 20:
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://builds/qa")
			root.get_texture().get_image().save_png("res://builds/qa/pacing-%s-%d.png" % [weapon_id, game.room])
			captured[game.room] = true
	release_controls()
	record_room()
	var report := {"driver": "Input-action bot; normal player/enemy stats; %dx simulation" % simulation_speed, "seed": 314159,
		"cooperative": cooperative, "weapon": weapon_id, "result": "segment_complete" if game.room > room_limit else game.state, "depth": game.room, "game_seconds": game.elapsed,
		"hp": game.player.hp, "kills": game.kills, "story_beats": game.story_seen, "rooms": reports}
	report.last_room = diagnostics()
	report.input_updates = ticks
	report.input_clock = "physics_frame"
	report.global_rng_seed = 314159
	report.element_reactions = reactions
	report.guardian_shapes = guardian_shapes
	report.defense_policy = "projectile-aware" if projectile_defense else "melee/area only"
	report.input_adapter = "state transitions only"
	report.skill_activations = skill_activations
	report.countershots = countershots
	if trace_damage: report.damage_events = damage_events
	report.builds = game.team().map(func(member): return {"weapon": member.weapon.definition.id, "damage": member.damage, "runes": member.enchantments.duplicate()})
	report.physics_seconds = combat_physics_frames / 60.0
	report.clock_difference = absf(game.elapsed - combat_physics_frames / 60.0)
	var clocks_match: bool = report.clock_difference <= maxf(2.0, game.elapsed * 0.01)
	if not clocks_match: push_error("Playthrough dropped physics steps; room timing is invalid")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/qa"))
	var output := "res://builds/qa/playthrough-coop.json" if cooperative else "res://builds/qa/playthrough.json"
	if weapon_id != "rifle" or room_limit < 30: output = "res://builds/qa/playthrough-%s-%s-%d.json" % [weapon_id, "coop" if cooperative else "solo", room_limit]
	if projectile_defense: output = output.trim_suffix(".json") + "-defense.json"
	if trace_damage: output = output.trim_suffix(".json") + "-damage-trace.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	var success: bool = (game.state == "victory" or game.room > room_limit) and clocks_match
	physics_frame.disconnect(count_combat_frame)
	Engine.time_scale = 1
	Engine.physics_ticks_per_second = 60
	game.queue_free()
	await create_timer(0.2).timeout
	quit(0 if success else 1)
