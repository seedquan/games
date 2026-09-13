extends SceneTree
## Resolve real swings against circular bodies, including sector corners and cover.
const CATALOG = preload("res://scripts/weapons.gd")
var game
var target
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func frames(count := 2) -> void:
	for i in range(count): await physics_frame
	await process_frame

func clear_attacks() -> void:
	for path in ["World/Effects", "World/Projectiles"]:
		for node in game.get_node(path).get_children():
			node.get_parent().remove_child(node)
			node.queue_free()

func swing(actor, point: Vector2) -> bool:
	clear_attacks()
	target.position = point
	target.hp = 10000
	target.shock_guard = 0
	actor.slash_cooldown = 0
	actor.weapon.fire()
	return target.hp < 10000

func geometry_cases() -> void:
	var actor = game.player
	actor.position = Vector2(800, 650)
	for form in CATALOG.FORMS:
		if form.mode != "melee": continue
		actor.weapon.equip(form.id)
		for heading in range(8):
			actor.aim = Vector2.from_angle(heading * PI / 4)
			for body_radius in [19.0, 46.0]:
				target.radius = body_radius
				target.get_node("Collision").shape.radius = body_radius
				var tip := Vector2.from_angle(form.arc) * float(form.reach)
				var normal := Vector2.from_angle(form.arc + PI / 2)
				var corner_out := Vector2.from_angle(form.arc + PI / 4)
				var cases := [
					["side contact", tip * 0.6 + normal * (body_radius - 1), true],
					["side gap", tip * 0.6 + normal * (body_radius + 1), false],
					["other side contact", (tip * 0.6 + normal * (body_radius - 1)) * Vector2(1, -1), true],
					["tip contact", Vector2(float(form.reach) + body_radius - 1, 0), true],
					["tip gap", Vector2(float(form.reach) + body_radius + 1, 0), false],
					["corner contact", tip + corner_out * (body_radius - 1), true],
					["corner gap", tip + corner_out * (body_radius + 1), false],
					["behind gap", Vector2(-body_radius - 2, 0), false],
					["origin contact", Vector2.ZERO, true],
				]
				for entry in cases:
					var hit := swing(actor, actor.position + entry[1].rotated(actor.aim.angle()))
					check(hit == entry[2], "%s/%d/r%.0f: %s" % [form.id, heading, body_radius, entry[0]])
		await frames()
	# Exact tangency and a narrowly separated body exercise floating point boundaries.
	actor.weapon.equip("lance")
	actor.aim = Vector2.RIGHT
	target.radius = 19
	target.get_node("Collision").shape.radius = 19
	var edge := Vector2.from_angle(0.3) * 100
	var normal := Vector2.from_angle(0.3 + PI / 2)
	check(swing(actor, actor.position + edge + normal * 19), "A tangent body touches the thrust")
	check(not swing(actor, actor.position + edge + normal * 19.1), "A small genuine gap still misses")
	# Legacy continuation retains the saved campaign's original targeting rule.
	game.campaign_version = 1
	check(not swing(actor, actor.position + edge + normal * 18), "Legacy angular edge remains center-based")
	check(swing(actor, actor.position + Vector2(180, 0)), "Legacy forward reach remains intact")
	game.campaign_version = 2
	actor.position = Vector2(420, 290)
	actor.aim = Vector2.DOWN
	await frames()
	check(not swing(actor, Vector2(420, 420)), "A body in range behind solid cover remains protected")
	check(not swing(actor, Vector2(449, 415)), "Angular body contact cannot bypass cover")

func input_and_elements() -> void:
	for actor in game.team():
		actor.position = Vector2(800, 650)
		actor.weapon.equip("lance")
		actor.enchantments = {"poison": 1}
		actor.aim = Vector2.RIGHT
		actor.slash_cooldown = 0
		target.position = actor.position + Vector2(110, 48)
		target.hp = 10000
		target.poison_stacks = 0
		target.poison_left = 0
		clear_attacks()
		game.using_gamepad = true
		actor.set_physics_process(true)
		Input.action_press(actor.action("aim_right"))
		Input.action_press(actor.action("slash"))
		await frames(2)
		Input.action_release(actor.action("slash"))
		Input.action_release(actor.action("aim_right"))
		actor.set_physics_process(false)
		check(is_equal_approx(target.hp, 10000 - actor.damage * 1.1), "Seat %d input lands one ordinary-damage contact" % actor.seat)
		check(target.poison_stacks == 1, "Seat %d contact applies the actual rune once" % actor.seat)
		var hp: float = target.hp
		actor.slash_cooldown = 0
		game.state = "paused"
		check(not actor.weapon.fire() and target.hp == hp, "Paused input cannot resolve another contact")
		game.state = "playing"
		actor.enchantments.clear()
		actor.position = Vector2(1100, 850)

func native_capture() -> void:
	if DisplayServer.get_name() == "headless": return
	var actor = game.player
	actor.position = Vector2(800, 650)
	game.team()[1].position = Vector2(650, 650)
	actor.weapon.equip("lance")
	actor.enchantments = {"poison": 1}
	actor.aim = Vector2.RIGHT
	target.poison_stacks = 0
	target.poison_left = 0
	await frames(12)
	check(swing(actor, actor.position + Vector2(110, 48)), "Rendered edge contact resolves through live fire")
	target.queue_redraw()
	game.state = "paused"
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/qa")
	check(root.get_texture().get_image().save_png("res://builds/qa/melee-contact.png") == OK, "Save native contact evidence")

func run() -> void:
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	game.coop.enabled = true
	game.coop.devices.assign([3, 7])
	game.coop.weapons.assign(["lance", "lance"])
	game.configure_input()
	game.start_run(924)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	for actor in game.team(): actor.set_physics_process(false)
	target = game.spawn_enemy("stalker", Vector2(900, 650))
	target.hp = 10000
	target.max_hp = 10000
	target.set_physics_process(false)
	await frames()
	await geometry_cases()
	await input_and_elements()
	await native_capture()
	print("ABYSS MELEE CONTACT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await frames(3)
	# Allow the Dummy mixer to retire its last playback, as in release teardown.
	await create_timer(0.2).timeout
	quit(0 if failures == 0 else 1)
