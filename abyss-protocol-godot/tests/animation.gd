extends SceneTree
## Tests the live caller, collision-driven gait, projected joints and weapon attachment.

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

func run() -> void:
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.narrative_enabled = false
	game.auto_pause_enabled = false
	root.add_child(game)
	game.start_run(631)
	await frames()
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	var actor = game.player
	var rig = actor.get_node("Sprite")
	check(rig.pose.size() == 11, "Normal gameplay renders an articulated body without preview flags")
	var phase: float = rig.phase
	var position: Vector2 = actor.position
	Input.action_press("move_right")
	await frames(30)
	Input.action_release("move_right")
	check(actor.position.x > position.x + 80 and rig.phase != phase and rig.blend > 0.9, "Actual resolved movement advances the live running cycle")
	actor.position = Vector2(1543, 500)
	actor.velocity = Vector2.ZERO
	Input.action_press("move_right")
	await frames(20)
	phase = rig.phase
	await frames(20)
	Input.action_release("move_right")
	check(is_equal_approx(phase, rig.phase) and rig.blend < 0.1, "A blocked player settles to idle instead of running against the wall")
	actor.position = Vector2(800, 650)
	actor.velocity = Vector2.ZERO
	actor.try_dash(Vector2.RIGHT)
	phase = rig.phase
	await frames(5)
	check(is_equal_approx(phase, rig.phase), "Dash movement does not spin the walking cycle")
	actor.set_physics_process(false)
	actor.dash_left = 0
	actor.slash_left = 0
	for facing in range(8):
		actor.aim = Vector2.from_angle(float(facing) * PI / 4.0)
		for motion_angle in range(8):
			rig.motion = Vector2.from_angle(float(motion_angle) * PI / 4.0)
			for frame in range(8):
				rig.phase = float(frame) / 8.0
				rig.blend = 1.0
				rig.update_pose()
				check(rig.facing == facing and rig.pose.size() == 11, "Every movement/facing sample draws all authored parts")
				for bone in rig.pose:
					var transform: Transform2D = bone.transform
					check(transform.is_finite() and absf(transform.determinant()) > 0.00001, "Projected bone stays finite and nondegenerate")
		for id in ["blade", "rifle", "rail", "qbow", "lbow", "sbow"]:
			actor.weapon.equip(id)
			for fraction in [0.0, 0.5, 1.0]:
				actor.weapon.charge = float(actor.weapon.definition.get("charge", 0.0)) * fraction
				actor.slash_left = 0.18 * fraction
				rig.update_pose()
				check(actor.weapon.position.distance_to(rig.to_world(rig.grip)) < 0.001, "Primary palm remains attached to the weapon grip")
				if actor.weapon.definition.family in ["FIREARMS", "ARCHERY"]:
					var expected: Vector2 = actor.weapon.position + actor.weapon.support_offset().rotated(actor.aim.angle())
					check(rig.to_world(rig.support_grip).distance_to(expected) < 0.05, "Support palm tracks the receiver or drawn bowstring")
	await preview()
	game.queue_free()
	await frames()
	print("ABYSS ANIMATION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func preview() -> void:
	if DisplayServer.get_name() == "headless":
		return
	game.show_menu("paused")
	var layer := CanvasLayer.new()
	layer.layer = 20
	root.add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color("081522")
	backdrop.size = Vector2(1440, 900)
	layer.add_child(backdrop)
	var names := ["东", "东南", "南", "西南", "西", "西北", "北", "东北"]
	for facing in range(8):
		var label = game.hud.label(names[facing], 20, Color("67efe0"))
		label.position = Vector2(80 + facing * 175, 25)
		label.add_theme_font_override("font", preload("res://assets/fonts/NotoSansCJKsc-Regular.otf"))
		layer.add_child(label)
		for row in range(4):
			var actor = game.PLAYER.instantiate()
			actor.game = game
			actor.process_mode = Node.PROCESS_MODE_DISABLED
			actor.position = Vector2(90 + facing * 175, 210 + row * 215)
			actor.scale = Vector2.ONE * 1.65
			layer.add_child(actor)
			actor.aim = Vector2.from_angle(float(facing) * PI / 4.0)
			actor.weapon.equip(["blade", "blade", "rifle", "lbow"][row])
			actor.weapon.charge = 0.9 if row == 3 else 0.0
			var rig = actor.get_node("Sprite")
			rig.blend = 1.0 if row == 1 else 0.0
			rig.phase = 0.22
			rig.motion = actor.aim
			rig.update_pose()
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/qa"))
	root.get_texture().get_image().save_png("res://builds/qa/android-poses.png")
	layer.queue_free()
	await frames()
