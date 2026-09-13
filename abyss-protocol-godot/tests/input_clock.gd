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
