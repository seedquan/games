extends SceneTree
## Verify the bot's action edges through the actual player's physics processing.
const ADAPTER = preload("res://tests/bot_input.gd")
var game
var controls = ADAPTER.new()
var checks := 0
var failures := 0
var rail_shots := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func timed_hazard(speed: int) -> void:
	controls.release()
	game.start_run(961)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	var room: Dictionary = game.room_data.duplicate(true)
	for key in ["cover", "obstacles", "furnishings", "shell"]: room[key] = []
	room.erase("art")
	game.arena.apply_room(room)
	game.player.position = Vector2(800, 650)
	game.player.aim = Vector2.RIGHT
	game.using_gamepad = true
	game.player.input_armed = true
	# A wall prevents an early dash from simply leaving the blast. Only the
	# actual player's timed invulnerability can protect this constrained position.
	game.arena.add_wall(Rect2(835, 540, 40, 220))
	await frames(3)
	var hazard = game.HAZARD.new()
	hazard.game = game
	hazard.position = game.player.position
	game.get_node("World/Projectiles").add_child(hazard)
	var dashed := false
	for i in range(65):
		controls.button("dash", is_instance_valid(hazard) and controls.blast_imminent(hazard, game.player.position))
		await physics_frame
		if game.player.dash_cooldown > 0: dashed = true
		if i == 30:
			check(not dashed, "%dx warning does not spend the dash before the blast approaches" % speed)
	controls.release()
	check(dashed and not is_instance_valid(hazard), "%dx a timed input reaches the player before the real hazard resolves" % speed)
	check(game.player.position.distance_to(Vector2(800, 650)) < 105, "%dx cover keeps the actor inside the blast for the timing check" % speed)
	check(game.player.hp == game.player.max_hp, "%dx timed invulnerability blocks the real explosion even when cover stops movement" % speed)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	game.start_run(913)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	game.player.input_armed = true
	game.get_node("World/Projectiles").child_entered_tree.connect(func(node):
		if node.get_script() == preload("res://scripts/projectile.gd") and node.visual == "rail": rail_shots += 1)
	Engine.max_physics_steps_per_frame = 64
	for speed in [1, 4, 12, 16]:
		Engine.physics_ticks_per_second = 60 * speed
		Engine.time_scale = speed
		for action in ["dash", "freeze", "parry"]:
			var key: String = game.player.action(action)
			var cooldown: String = action + "_cooldown"
			for one_tick in [true, false]:
				controls.release()
				await frames(3)
				game.player.set(cooldown, 0)
				for tick in range(8):
					controls.button(key, tick == 0 if one_tick else true)
					await physics_frame
				check(game.player.get(cooldown) > 0, "%dx %s request reaches the player; single tick=%s" % [speed, action, one_tick])
				controls.release()
				check(not Input.is_action_pressed(key), "Stopping the bot releases its held skill")
		game.player.weapon.equip("rail")
		game.player.slash_cooldown = 0
		var before := rail_shots
		for i in range(85):
			controls.button("slash", true)
			await physics_frame
		check(is_equal_approx(game.player.weapon.charge, game.player.weapon.definition.charge), "Holding reaches the actual rail charge")
		for i in range(4):
			controls.button("slash", false)
			await physics_frame
		check(rail_shots == before + 1, "Releasing emits exactly one charged shot")
		controls.release()
		await timed_hazard(speed)
	game.coop.enabled = true
	game.coop.devices.assign([1, 3])
	game.configure_input()
	game.start_run(915)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	for member in game.team(): member.input_armed = true
	await frames(3)
	for i in range(8):
		controls.button(game.companion.action("dash"), i == 0)
		await physics_frame
	check(game.companion.dash_cooldown > 0 and game.player.dash_cooldown == 0, "Second-seat edge moves only its paired actor")
	controls.release()
	Engine.time_scale = 1
	Engine.physics_ticks_per_second = 60
	game.queue_free()
	await create_timer(0.25).timeout
	print("ABYSS INPUT CLOCK: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
