extends SceneTree
## Mouse activity includes held buttons and releases, not only pointer motion.

var game
var checks := 0
var failures: Array[String] = []

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

func pointer(offset: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = game.player.get_global_transform_with_canvas().origin + offset
	event.global_position = event.position
	event.relative = Vector2(8, 0)
	Input.parse_input_event(event)

func mouse_button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = game.player.get_global_transform_with_canvas().origin + Vector2(280, 0)
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)

func run() -> void:
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	game.start_run(227)
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	var target = game.spawn_enemy("stalker", game.player.position + Vector2(-140, 0))
	target.hp = 100000
	target.set_physics_process(false)
	game.player.weapon.equip("rifle")
	await frames()
	pointer(Vector2(280, 0))
	mouse_button(true)
	await frames(150)
	check(game.player.aim.x > 0.98 and "鼠标瞄准" in game.hud.controls_hint.text, "Holding mouse fire for 2.5 seconds keeps aiming at the pointer")
	mouse_button(false)
	await frames()
	check(game.player.aim.x > 0.98, "Release retains pointer aim rather than snapping to a nearby enemy")
	await frames(140)
	check(game.player.aim.x < -0.98 and "辅助锁定" in game.hud.controls_hint.text, "Enabled assistance can resume after true mouse inactivity")
	game.set_setting("aim_assist", false)
	pointer(Vector2(280, 0))
	await frames(150)
	# Move briefly after mouse inactivity: movement must not replace manual aim.
	Input.action_press("move_up")
	await frames(5)
	Input.action_release("move_up")
	check(game.player.aim.x > 0.97, "Disabling aim assistance preserves manual pointer aim while moving")
	game.player.aim = Vector2.RIGHT
	pointer(Vector2.ZERO)
	await frames()
	check(game.player.aim.length() > 0.99, "Pointer at the actor cannot create a zero-direction projectile")
	game.set_setting("aim_assist", true)
	game.player.weapon.equip("rail")
	game.player.slash_cooldown = 0
	pointer(Vector2(280, 0))
	mouse_button(true)
	await frames(150)
	mouse_button(false)
	await frames()
	var rails: Array = game.get_node("World/Projectiles").get_children().filter(func(node): return node.visual == "rail")
	check(not rails.is_empty() and rails[-1].direction.x > 0.98, "Long charge releases toward the pointer after button release")
	game.queue_free()
	await frames()
	print("ABYSS AIMING: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
