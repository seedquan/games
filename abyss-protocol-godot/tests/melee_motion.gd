extends SceneTree
## Real attacks: persistent contact traces, distinct follow-through and paired actors.

const STROKE = preload("res://scripts/melee_stroke.gd")
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
	for i in range(count): await physics_frame
	await process_frame

func strokes() -> Array:
	return game.get_node("World/Effects").get_children().filter(func(node): return node.get_script() == STROKE)

func strike(actor, id: String, direction: Vector2):
	actor.weapon.equip(id)
	actor.aim = direction
	actor.slash_cooldown = 0
	actor.weapon.fire()
	return strokes()[-1]

func run() -> void:
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	game.coop.enabled = true
	game.coop.devices.assign([1, 3])
	game.coop.weapons.assign(["lance", "maul"])
	game.configure_input()
	game.start_run(631)
	game.encounter.cancel()
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	for actor in game.team(): actor.set_physics_process(false)
	await frames()
	var actor = game.player
	var rig = actor.get_node("Sprite")
	actor.position = Vector2(800, 650)
	var target = game.spawn_enemy("stalker", Vector2(875, 650))
	target.set_physics_process(false)
	target.hp = 10000
	target.max_hp = 10000
	var trace = strike(actor, "lance", Vector2.RIGHT)
	check(is_equal_approx(target.hp, 10000 - actor.damage * 1.1), "Thrust applies its original damage immediately")
	check(is_equal_approx(actor.slash_cooldown, 0.39), "Animation does not change lance cadence")
	var origin: Transform2D = trace.global_transform
	var launch_offset: Vector2 = trace.visual_offset
	check((trace.position + launch_offset.rotated(trace.rotation)).distance_to(actor.weapon.global_position) < 0.001, "Material stroke starts at the actual hand while the footprint stays on the floor")
	actor.position += Vector2(120, 90)
	actor.aim = Vector2.LEFT
	actor.slash_left = 0.09
	rig.update_pose()
	check(trace.global_transform.is_equal_approx(origin), "Moving and reversing aim cannot drag resolved hit trace")
	check(trace.visual_offset == launch_offset, "Turning cannot drag the captured hand offset")
	check(absf(rig.visual_attack_angle) < 0.001 and rig.facing == 0, "Thrust keeps its committed facing during follow-through")
	check(actor.weapon.position.distance_to(rig.to_world(rig.grip)) < 0.001, "Extended thrust preserves palm attachment")
	actor.slash_left = 0
	rig.update_pose()
	check(rig.facing == 4, "After recovery the body follows new input")
	var prior_hp: float = target.hp
	await frames(20)
	check(target.hp == prior_hp and not is_instance_valid(trace), "Residue never reapplies damage and frees itself")
	# Cover limits the painted range at the same wall that rejects the actual attack.
	actor.position = Vector2(420, 290)
	target.position = Vector2(420, 420)
	await frames()
	trace = strike(actor, "whip", Vector2.DOWN)
	check(trace.edge[16].length() < 225 and target.hp == prior_hp, "Chain trace and real hit both stop at cover")
	for id in ["blade", "lance", "maul", "fang", "arc", "whip", "prism"]:
		trace = strike(actor, id, Vector2.DOWN)
		await frames()
		check(trace.edge[16].length() < 83, "Clipped close-wall geometry renders safely: " + id)
	actor.position = Vector2(800, 650)
	for id in ["blade", "lance", "maul", "fang", "arc", "whip", "prism"]:
		for heading in range(8):
			var direction := Vector2.from_angle(heading * PI / 4)
			trace = strike(actor, id, direction)
			check(trace.kind == id and trace.edge.size() == 33, "Real attack creates its own footprint: %s/%d" % [id, heading])
			check(absf(angle_difference(trace.rotation, direction.angle())) < 0.001, "Trace faces the resolved attack")
			for fraction in [1.0, 0.75, 0.5, 0.25]:
				actor.slash_left = fraction * 0.18
				rig.update_pose()
				check(actor.weapon.transform.is_finite() and actor.weapon.position.distance_to(rig.to_world(rig.grip)) < 0.001, "Animated contact maintains a finite grip")
				for bone in rig.pose:
					check(bone.transform.is_finite() and absf(bone.transform.determinant()) > 0.00001, "All joints remain valid during attack")
			trace.queue_free()
		await frames()
	# The third slash remains a real double hit, now with a matching cross-cut cue.
	actor.weapon.equip("fang")
	target.position = actor.position + Vector2(60, 0)
	actor.aim = Vector2.RIGHT
	var damages: Array[float] = []
	var swings: Array[float] = []
	for i in range(3):
		actor.slash_cooldown = 0
		prior_hp = target.hp
		actor.weapon.fire()
		damages.append(prior_hp - target.hp)
		swings.append(actor.weapon.melee_motion().x)
		check(strokes()[-1].combo == i + 1, "Trace reflects the actual fang combo step")
	check(is_equal_approx(damages[2], damages[0] * 2) and swings[0] * swings[1] < 0, "Fang alternates swings and emphasizes its real third hit")
	# Two simultaneous attacks snapshot their own position, direction, and weapon.
	trace = strike(actor, "lance", Vector2.RIGHT)
	var other = strike(game.companion, "maul", Vector2.LEFT)
	check(trace != other and trace.kind == "lance" and other.kind == "maul" and absf(angle_difference(trace.rotation, other.rotation)) > 3, "Paired actors have independent simultaneous strokes")
	game.show_menu("paused")
	await frames()
	var paused_elapsed: float = trace.elapsed
	await frames(15)
	check(trace.elapsed == paused_elapsed, "Pause freezes attack residue")
	game.resume_run()
	await frames(25)
	check(not is_instance_valid(trace) and not is_instance_valid(other), "Both strokes finish after resume")
	# Native preview uses live fire callers; no independent duplicate artwork.
	await preview()
	if game.state == "paused": game.resume_run()
	await live_input()
	strike(actor, "whip", Vector2.RIGHT)
	game.next_room(game.ROOMS.generate(2, "combat", game.rng))
	check(strokes().is_empty(), "Changing chambers clears residual attacks")
	game.queue_free()
	await frames(6)
	# The silent audio driver still retires its last playback on the mixer thread.
	await create_timer(0.25).timeout
	print("ABYSS MELEE MOTION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func live_input() -> void:
	# Exercise the real player physics caller, including an immediate aim reversal.
	game.player.weapon.equip("lance")
	game.companion.weapon.equip("maul")
	for actor in game.team():
		actor.slash_cooldown = 0
		actor.input_armed = true
		actor.set_physics_process(true)
		Input.action_press(actor.action("aim_right"))
		Input.action_press(actor.action("slash"))
	await frames(2)
	var trace = strokes().filter(func(node): return node.kind == "lance")[-1]
	var origin: Transform2D = trace.global_transform
	for actor in game.team():
		Input.action_release(actor.action("aim_right"))
		Input.action_press(actor.action("aim_left"))
		Input.action_press(actor.action("move_down"))
	await frames(2)
	check(game.player.aim.x < -0.99 and game.player.velocity.y > 0, "Attack follow-through does not block new aim or movement")
	check(game.player.get_node("Sprite").facing == 0 and trace.global_transform.is_equal_approx(origin), "Physics tick retains the committed thrust and world trace while aim changes")
	for actor in game.team():
		for action in ["slash", "aim_left", "move_down"]: Input.action_release(actor.action(action))
		actor.set_physics_process(false)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/qa/melee-motion-combat.png")

func preview() -> void:
	if DisplayServer.get_name() == "headless": return
	game.show_menu("paused")
	var layer := CanvasLayer.new()
	layer.layer = 20
	root.add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color("19232a")
	backdrop.size = Vector2(1440, 900)
	layer.add_child(backdrop)
	var title = game.hud.label("出手与回收", 32, Color("ece8d9"))
	title.position = Vector2(48, 24)
	layer.add_child(title)
	var ids := ["lance", "maul", "whip", "fang"]
	for row in range(4):
		var label = game.hud.label(game.player.weapon.CATALOG.find(ids[row]).name, 22, Color("ece8d9"))
		label.position = Vector2(48, 165 + row * 195)
		layer.add_child(label)
		for col in range(4):
			var subject = game.PLAYER.instantiate()
			subject.game = game
			subject.process_mode = Node.PROCESS_MODE_DISABLED
			subject.position = Vector2(220 + col * 315, 205 + row * 195)
			layer.add_child(subject)
			subject.weapon.equip(ids[row])
			subject.aim = Vector2.RIGHT
			subject.weapon.combo = 2 if col == 3 else col
			var point: Vector2 = subject.position
			subject.position = Vector2(800, 650)
			game.state = "playing"
			subject.weapon.fire()
			game.state = "paused"
			var trace = strokes()[-1]
			trace.reparent(layer)
			subject.position = point
			subject.slash_left = 0.18 * (1.0 - col * 0.23)
			subject.get_node("Sprite").update_pose()
			trace.position = point
			trace.elapsed = col * trace.duration * 0.23
			trace.process_mode = Node.PROCESS_MODE_DISABLED
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/qa"))
	root.get_texture().get_image().save_png("res://builds/qa/melee-motion.png")
	game.settings.values.flash = 0.0
	for node in layer.get_children():
		if node.get_script() == STROKE: node.queue_redraw()
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/qa/melee-motion-no-flash.png")
	game.settings.values.flash = 1.0
	layer.queue_free()
	await frames()
