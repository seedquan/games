extends Node2D
## Eight authored projections, articulated from actual post-collision displacement.

const DATA = preload("res://scripts/rig_data.gd")
const WORLD_SCALE := 0.52
const GROUND := [[145.5, 5.5, 14.0, 0], [144.0, 9.0, 5.0, 1], [139.0, 12.0, 0.0, 0],
	[144.0, 9.0, 5.0, 1], [142.5, 5.5, 14.0, 0], [142.0, 11.0, 4.0, 1],
	[145.0, 10.0, 0.0, 0], [142.5, 11.0, 4.0, 1]]
var actor
var phase := 0.0
var blend := 0.0
var motion := Vector2.RIGHT
var facing := 0
var stride := 96.0
var ground := 145.5
var pose: Array[Dictionary] = []
var grip := Vector2.ZERO
var support_grip := Vector2.ZERO
var bounce := 0.0
var projection := "side"
var direction := 1.0
var visual_attack_angle := 0.0

func _ready() -> void:
	actor = get_parent()

func advance(displacement: Vector2, delta: float, dashing: bool) -> void:
	var speed := displacement.length() / maxf(delta, 0.0001)
	var moving := minf(1.0, speed / 200.0) if not dashing else 0.0
	blend = move_toward(blend, moving, delta * 8.0)
	if speed > 2.0 and not dashing:
		motion = displacement.normalized()
		stride = move_toward(stride, clampf(speed / 2.625, 36.0 * WORLD_SCALE / 0.58, 96.0), delta * 100.0)
		phase = fposmod(phase + displacement.length() / stride, 1.0)
	update_pose()

func step(side: int) -> Vector2:
	var u := fposmod(phase + (0.5 if side > 0 else 0.0), 1.0)
	var duty := minf(0.58, 36.0 * WORLD_SCALE / stride)
	var contact := u < duty
	var swing := 0.0 if contact else (u - duty) / (1.0 - duty)
	var turn := 0.08 * duty / (1.0 - duty)
	var travel: float
	if contact:
		travel = 1.0 - 2.0 * u / duty
	elif swing < turn:
		var v := swing / turn
		travel = -1.0 - 0.08 * (2.0 * v - v * v)
	elif swing > 1.0 - turn:
		var v := (1.0 - swing) / turn
		travel = 1.0 + 0.08 * (2.0 * v - v * v)
	else:
		var v := (swing - turn) / (1.0 - 2.0 * turn)
		travel = 1.08 * (-1.0 + 2.0 * v * v * (3.0 - 2.0 * v))
	var edge := minf(1.0, minf(swing / 0.025, (1.0 - swing) / 0.025))
	var lift := 0.0 if contact else sin(swing * PI) * edge * edge * (3.0 - 2.0 * edge) * (0.35 + 0.65 * minf(1.0, stride / 96.0))
	return Vector2(travel, lift) * blend

func update_pose() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(actor.weapon):
		return
	var aim_angle: float = actor.weapon.pose_direction().angle()
	if absf(angle_difference(float(facing) * PI / 4.0, aim_angle)) > PI / 8.0 + 0.04:
		facing = posmod(roundi(aim_angle / (PI / 4.0)), 8)
	projection = "side" if facing in [0, 4] else "south" if facing == 2 else "north" if facing == 6 else "front" if facing in [1, 3] else "rear"
	direction = -1.0 if facing in [3, 4, 5] else 1.0
	var calibration: Array = GROUND[facing]
	var vertical := absf(motion.y)
	var extra := maxf(0.0, (vertical - sqrt(0.5)) / (1.0 - sqrt(0.5))) if calibration[3] else vertical
	ground = calibration[0] - (calibration[1] + calibration[2] * extra) * blend
	bounce = -absf(sin(phase * TAU)) * 1.6 * blend
	pose.clear()
	visual_attack_angle = aim_angle
	if actor.weapon.definition.mode == "melee" and actor.slash_left > 0.0:
		visual_attack_angle += actor.weapon.melee_motion().x
	if projection in ["south", "north"]:
		var left_first := step(-1).x < step(1).x
		if projection == "north":
			left_first = not left_first
		leg(-1 if left_first else 1)
		leg(1 if left_first else -1)
		arm(-1)
	else:
		leg(-1)
		arm(-1)
		leg(1)
	var hip := 82.0 if projection in ["south", "side"] else 86.0
	var crown := 7.0 if projection == "south" else 10.0 if projection == "front" else 9.0
	part("core", Vector2(80, hip + bounce), Vector2(81 if projection == "side" else 80, crown + bounce), 0.18 if projection == "side" else 0.20 if projection == "front" else 0.22)
	arm(1)
	actor.weapon.position = to_world(grip)
	actor.weapon.rotation = visual_attack_angle
	queue_redraw()

func knee(hip: Vector2, ankle: Vector2) -> Vector2:
	var offset := ankle - hip
	var distance := maxf(0.001, offset.length())
	var reach := clampf(distance, 2.001, 52.499)
	var along := (25.25 * 25.25 - 27.25 * 27.25 + reach * reach) / (2.0 * reach)
	var bend := sqrt(maxf(0.0, 25.25 * 25.25 - along * along))
	return hip + offset / distance * along + Vector2(offset.y, -offset.x) / distance * bend

func leg(side: int) -> void:
	var gait := step(side)
	var travel := gait.x * 18.0
	var lift := gait.y
	var hip: Vector2
	var ankle: Vector2
	var joint: Vector2
	var toe: Vector2
	var widths := Vector3(0.14, 0.14, 0.17)
	if projection == "side":
		hip = Vector2(80 - side * 3, 82 + side * 2 + bounce)
		ankle = Vector2(lerpf(76 if side > 0 else 88, 80 - side * 3, blend) + travel * motion.x * direction,
			lerpf(135 if side > 0 else 128, 126 + side * 2 - 14 * absf(motion.y), blend) + travel * motion.y - lift * 19)
		joint = knee(hip, ankle)
		toe = ankle + Vector2(13, 6 - lift * 4)
		widths = Vector3(0.13, 0.13, 0.15)
	elif projection in ["front", "rear"]:
		hip = Vector2(80 + side * 9, 86 + side * 3 + bounce)
		var vertical := maxf(0.0, (absf(motion.y) - sqrt(0.5)) / (1.0 - sqrt(0.5)))
		var drop := 9 + 5 * vertical if projection == "front" else 11 + 4 * vertical
		ankle = Vector2(80 + side * (17 - 6 * blend) + travel * motion.x * direction,
			130 + side * 3 - drop * blend + travel * motion.y - lift * (6 if projection == "front" else 14))
		joint = knee(hip, ankle)
		toe = ankle + Vector2(7 if projection == "front" else -1, 12 - lift * 3)
	else:
		var north := projection == "north"
		hip = Vector2(80 + side * 12, (86 if north else 82) + bounce)
		ankle = Vector2(80 + side * ((20 if north else 22) - (9 if north else 11) * blend + lift * 1.5) + travel * motion.x,
			(132 if north else 124) - (10 if north else 12) * blend + travel * motion.y - lift * 12)
		joint = Vector2(80 + side * ((17 if north else 18) - (7 if north else 8) * blend + lift * 3),
			lerpf(hip.y, ankle.y, 0.52 if north else 0.51) + (0.0 if north else lift * 2))
		toe = ankle + Vector2(0 if north else side, 13 - lift * 3)
		widths.x = 0.14 if north else 0.13
	var suffix := "L" if side < 0 else "R"
	part("foot" + suffix, ankle, toe, widths.x)
	part("shin" + suffix, joint, ankle, widths.y)
	part("thigh" + suffix, hip, joint, widths.z)

func arm(side: int) -> void:
	var gait := step(-side)
	var suffix := "L" if side < 0 else "R"
	var shoulder: Vector2
	var elbow: Vector2
	var wrist: Vector2
	var width := 0.145
	if projection == "side":
		shoulder = Vector2(79 - side * 6, 44 + side * 2 + bounce)
		elbow = Vector2(shoulder.x + 2 + 2 * blend + gait.x * 9, 66 + bounce - gait.y * 4)
		wrist = Vector2(shoulder.x + 3 + 9 * blend + gait.x * 12, 85 - 5 * blend + bounce - gait.y * 8)
		width = 0.14
	elif projection in ["front", "rear"]:
		var slope := 1.0 if projection == "front" else -1.0
		shoulder = Vector2(80 + side * 15, 44 + side * 3 + bounce)
		elbow = Vector2(80 + side * 21 + gait.x * 5 * sqrt(0.5), 65 + side * 2 + bounce + slope * gait.x * 5 * sqrt(0.5))
		wrist = Vector2(80 + side * (27 - 4 * blend) + gait.x * 10 * sqrt(0.5), 84 + side * 2 + bounce + slope * gait.x * 10 * sqrt(0.5) - gait.y * 4)
	else:
		var north := projection == "north"
		shoulder = Vector2(80 + side * 18, (44 if north else 43) + bounce)
		elbow = Vector2(80 + side * (25 - 5 * blend + gait.y * 2), (65 if north else 64) + bounce + gait.x * (-3 if north else 3))
		wrist = Vector2(80 + side * ((30 if north else 31) - (7 if north else 8) * blend + gait.y * 2), (83 if north else 81) + bounce + gait.x * (-7 if north else 7) - gait.y * 3)
	# Convert to the authored direction before solving targets in screen space.
	shoulder = project_point(shoulder)
	elbow = project_point(elbow)
	wrist = project_point(wrist)
	var adjusted_width := width * (0.85 if facing == 5 else 1.0)
	if actor.weapon.definition.family in ["FIREARMS", "ARCHERY"]:
		var main: Vector2 = Vector2(80, 64) + actor.aim * 8.0
		main -= actor.aim * (actor.slash_left / 0.18 * 6.0 / WORLD_SCALE)
		var offset: Vector2 = actor.weapon.support_offset().rotated(actor.aim.angle()) / WORLD_SCALE
		main -= offset * 0.5
		var target: Vector2 = main if side > 0 else main + offset
		target.y += bounce
		var joints := support_joints("fore" + suffix, shoulder, target, adjusted_width)
		elbow = joints[0]
		wrist = joints[1]
	elif side > 0 and actor.slash_left > 0.0:
		var target := shoulder + Vector2(cos(visual_attack_angle) * 32.0, 16 + sin(visual_attack_angle) * 20.0)
		if actor.weapon.definition.mode == "melee":
			target += actor.weapon.pose_direction() * actor.weapon.melee_motion().y
		var joints := support_joints("fore" + suffix, shoulder, target, adjusted_width)
		var amount := sin(PI * clampf(actor.slash_left / 0.18, 0.0, 1.0))
		if actor.weapon.definition.mode == "melee" and actor.weapon.definition.id in ["lance", "whip", "maul"]:
			amount = pow(clampf(actor.slash_left / 0.18, 0.0, 1.0), 0.6)
		elbow = elbow.lerp(joints[0], amount)
		wrist = wrist.lerp(joints[1], amount)
	var palm := add_part("fore" + suffix, elbow, wrist, adjusted_width)
	add_part("upper" + suffix, shoulder, elbow, 0.17 * (0.85 if facing == 5 else 1.0))
	if side > 0:
		grip = palm
	else:
		support_grip = palm

func support_joints(key: String, shoulder: Vector2, target: Vector2, width: float) -> Array[Vector2]:
	var source: Array = DATA.PARTS[facing][key]
	var native := Vector2(source[6] - source[4], source[7] - source[5])
	var palm := Vector2(source[8] - source[4], source[9] - source[5]).rotated(-native.angle())
	var factor := palm.x / native.length()
	var across := palm.y * width
	var offset := target - shoulder
	var distance := maxf(0.001, offset.length())
	var fore := minf(22.0, sqrt(maxf(1.0, pow(22 + distance - 0.01, 2) - across * across)) / factor)
	var palm_length := Vector2(factor * fore, across).length()
	var reach := clampf(distance, absf(22 - palm_length) + 0.001, 22 + palm_length - 0.001)
	var along := (22 * 22 - palm_length * palm_length + reach * reach) / (2 * reach)
	var bend := sqrt(maxf(0.0, 22 * 22 - along * along))
	var elbow := shoulder + offset / distance * along + Vector2(offset.y, -offset.x) / distance * bend
	if distance < 8:
		var amount := smoothstep(0, 1, 1 - distance / 8)
		elbow = elbow.lerp(shoulder + Vector2(-12 if shoulder.x < 80 else 12, 10), amount)
		fore = sqrt(maxf(0.01, elbow.distance_squared_to(target) - across * across)) / factor
	var angle := elbow.angle_to_point(target) - atan2(across, factor * fore)
	return [elbow, elbow + Vector2.from_angle(angle) * fore]

func project_point(point: Vector2) -> Vector2:
	return Vector2(80 + (point.x - 80) * direction, point.y) if projection in ["side", "front", "rear"] else point

func part(key: String, from: Vector2, to: Vector2, width: float) -> void:
	add_part(key, project_point(from), project_point(to), width * (0.85 if facing == 5 else 1.0))

func add_part(key: String, from: Vector2, to: Vector2, width: float) -> Vector2:
	var source: Array = DATA.PARTS[facing][key]
	var native := Vector2(source[6] - source[4], source[7] - source[5])
	var transform := Transform2D(from.angle_to_point(to), from) * Transform2D(0, Vector2(from.distance_to(to) / native.length(), width), 0, Vector2.ZERO) * Transform2D(-native.angle(), Vector2.ZERO)
	pose.append({"key": key, "transform": transform})
	return transform * Vector2(source[8] - source[4], source[9] - source[5]) if source.size() == 10 else to

func to_world(point: Vector2) -> Vector2:
	return (point - Vector2(80, ground)) * WORLD_SCALE

func _draw() -> void:
	var outer := Transform2D(0, Vector2.ONE * WORLD_SCALE, 0, to_world(Vector2.ZERO))
	for bone in pose:
		var source: Array = DATA.PARTS[facing][bone.key]
		draw_set_transform_matrix(outer * bone.transform)
		draw_texture_rect_region(DATA.TEXTURES[facing], Rect2(source[0] - source[4], source[1] - source[5], source[2], source[3]), Rect2(source[0] / 2.0, source[1] / 2.0, source[2] / 2.0, source[3] / 2.0))
	draw_set_transform_matrix(Transform2D.IDENTITY)
