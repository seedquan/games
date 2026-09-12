extends Node2D
## Dispatches genuine attack families. Shared plasma stays a separate ability.

const CATALOG = preload("res://scripts/weapons.gd")
const ART = preload("res://scripts/weapon_art.gd")
var actor
var definition: Dictionary = CATALOG.find("blade")
var charge := 0.0
var drawing := false
var combo := 0
var combo_left := 0.0
var active_glaive: WeakRef

func _ready() -> void:
	actor = get_parent()

func equip(id: String) -> bool:
	if not CATALOG.exists(id):
		return false
	definition = CATALOG.find(id)
	cancel_charge()
	combo = 0
	combo_left = 0.0
	if is_instance_valid(actor):
		actor.get_node("Sprite").update_pose()
	queue_redraw()
	return true

func cancel_charge() -> void:
	charge = 0.0
	drawing = false

func tick(delta: float, held: bool, released: bool) -> void:
	combo_left = maxf(0.0, combo_left - delta)
	if combo_left == 0.0:
		combo = 0
	if definition.has("charge"):
		if held and actor.slash_cooldown <= 0.0:
			drawing = true
			charge = minf(float(definition.charge), charge + delta)
		elif released and drawing:
			release_charge()
	elif held:
		fire()
	position = Vector2(0, -19) + actor.aim * 18.0
	rotation = actor.aim.angle()
	queue_redraw()

func release_charge() -> bool:
	if not drawing or not definition.has("charge"):
		return false
	var fraction := clampf(charge / float(definition.charge), 0.0, 1.0)
	cancel_charge()
	return fire(fraction)

func fire(charge_fraction := -1.0) -> bool:
	if actor.game.state != "playing" or actor.hp <= 0.0 or actor.slash_cooldown > 0.0:
		return false
	if definition.has("charge") and charge_fraction < 0.0:
		return false
	if definition.mode == "glaive" and active_glaive != null and is_instance_valid(active_glaive.get_ref()):
		return false
	actor.slash_cooldown = definition.cooldown
	actor.slash_left = 0.18
	actor.get_node("Sprite").update_pose()
	combo += 1
	combo_left = 0.85
	var amount: float = actor.damage * float(definition.damage) * (1.5 if actor.empowered > 0.0 else 1.0)
	match definition.mode:
		"melee": melee(amount)
		"projectile": shoot(amount, maxf(0.0, charge_fraction))
		"chain": lightning(amount, 4)
		"gravity":
			var center: Vector2 = actor.global_position + actor.aim * 120.0
			center = actor.game.clip_to_wall(actor.global_position, center)
			actor.game.spawn_field(center, actor, "gravity", amount, 170.0, 0.8)
		"glaive":
			var shot = actor.game.spawn_bolt(actor.global_position + actor.aim * 28.0, actor.aim, false, amount,
				{"visual": "glaive", "color": definition.color, "speed": definition.speed,
				"visual_offset": to_global(Vector2(18, 0)) - (actor.global_position + actor.aim * 28.0),
				"pierce": 99, "life": 2.5, "shooter": actor})
			active_glaive = weakref(shot)
	var cue: String = {"MELEE": "blade", "ENERGY": "arc", "MAGIC": "arc", "FIREARMS": "gun", "ARCHERY": "bow"}.get(definition.family, "blade")
	if definition.id in ["maul", "grav", "rail"]:
		cue = "heavy"
	actor.game.sound.play_cue(cue, 0.19)
	return true

func melee(amount: float) -> void:
	var hit: Array[Node2D] = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var offset: Vector2 = enemy.global_position - actor.global_position
		if offset.length() > float(definition.reach) + enemy.radius:
			continue
		if actor.aim.dot(offset.normalized()) < cos(float(definition.arc)):
			continue
		if not actor.game.has_sight(actor.global_position, enemy.global_position):
			continue
		var force: Vector2 = offset.normalized() * float(definition.force)
		var hit_damage := amount * (2.0 if definition.id == "fang" and combo % 3 == 0 else 1.0)
		actor.weapon_hit(enemy, hit_damage, force, definition.get("element", ""))
		if is_instance_valid(enemy) and not enemy.dead:
			if definition.id == "maul":
				enemy.frozen = maxf(enemy.frozen, 0.22)
			hit.append(enemy)
	if definition.id == "arc" and not hit.is_empty():
		chain_from(hit[0].global_position, amount * 0.6, 2, hit)
	if definition.id == "prism":
		actor.game.spawn_bolt(actor.global_position + actor.aim * 28.0, actor.aim, false, amount * 0.75,
			{"visual": "rail", "color": definition.color, "speed": 1200.0, "visual_offset": to_global(Vector2(37, 0)) - (actor.global_position + actor.aim * 28.0), "pierce": 4, "life": 0.5, "shooter": actor})
	if definition.id == "maul":
		actor.game.effect(actor.global_position + actor.aim * 65.0, Color(definition.color), 70.0)

func shoot(amount: float, charge_fraction: float) -> void:
	var pellets: int = definition.get("pellets", 1)
	var spread: float = definition.get("spread", 0.0)
	var piercing: int = definition.get("pierce", 0)
	var visible_origin := to_global(muzzle_offset(charge_fraction))
	if definition.has("charge"):
		amount *= lerpf(0.65, 3.1, charge_fraction)
		if definition.id == "lbow" and charge_fraction >= 0.95:
			piercing = 3
	for i in range(pellets):
		var angle := randf_range(-spread, spread) if pellets == 1 else lerpf(-spread, spread, float(i) / float(pellets - 1))
		var direction: Vector2 = actor.aim.rotated(angle)
		var physical_origin: Vector2 = actor.global_position + direction * 28.0
		actor.game.spawn_bolt(physical_origin, direction, false, amount,
			{"visual": definition.get("visual", "plasma"), "color": definition.color,
			"speed": definition.get("speed", 720.0), "life": definition.get("life", 1.3),
			"pierce": piercing, "element": definition.get("element", ""),
			"explosion": definition.get("explosion", 0.0), "shooter": actor,
			"visual_offset": visible_origin - physical_origin})

func lightning(amount: float, count: int) -> void:
	var target = null
	var best := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var offset: Vector2 = enemy.global_position - actor.global_position
		if offset.length() < float(definition.reach) and actor.aim.dot(offset.normalized()) > 0.88:
			if offset.length_squared() < best and actor.game.has_sight(actor.global_position, enemy.global_position):
				target = enemy
				best = offset.length_squared()
	if not is_instance_valid(target):
		actor.game.beam(to_global(Vector2(36, 0)), actor.game.clip_to_wall(actor.global_position, actor.global_position + actor.aim * 220.0) + Vector2(0, -28), Color(definition.color))
		return
	var point: Vector2 = target.global_position
	actor.game.beam(to_global(Vector2(36, 0)), point + Vector2(0, -28), Color(definition.color))
	actor.weapon_hit(target, amount, actor.aim * 70.0, "shock")
	chain_from(point, amount * 0.75, count - 1, [target])

func chain_from(origin: Vector2, amount: float, count: int, visited: Array) -> void:
	var point := origin
	for step in range(count):
		var target = null
		var best := 190.0 * 190.0
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy in visited:
				continue
			var distance := point.distance_squared_to(enemy.global_position)
			if distance < best and actor.game.has_sight(point, enemy.global_position):
				target = enemy
				best = distance
		if not is_instance_valid(target):
			break
		actor.game.beam(point + Vector2(0, -28), target.global_position + Vector2(0, -28), Color(definition.color))
		point = target.global_position
		visited.append(target)
		actor.weapon_hit(target, amount, Vector2.ZERO, "shock")

func _draw() -> void:
	var color := Color(definition.color)
	var recoil: float = actor.slash_left / 0.18 * 6.0 if is_instance_valid(actor) else 0.0
	match definition.family:
		"ARCHERY":
			var spec: Dictionary = ART.BOW_SPRITES[definition.id]
			var bow := bow_pose()
			var grip := Vector2(spec.grip[0], spec.grip[1])
			draw_texture_rect_region(ART.BOWS, Rect2(-grip * bow.scale, Vector2(128, 256) * bow.scale), Rect2(spec.cell * 128, 0, 128, 256))
			draw_polyline(PackedVector2Array([bow.tips[0], bow.nock, bow.tips[1]]), Color("dce9df"), 1.0, true)
			draw_line(bow.nock, bow.nock + Vector2(30, 0), color, 1.6, true)
			draw_colored_polygon(PackedVector2Array([bow.nock + Vector2(34, 0), bow.nock + Vector2(27, -2), bow.nock + Vector2(27, 2)]), color)
		"FIREARMS":
			var spec: Dictionary = ART.GUN_SPRITES[definition.id]
			var grip := Vector2(spec.grip[0], spec.grip[1])
			draw_set_transform(Vector2.ZERO, -spec.angle, Vector2.ONE * spec.scale * ART.ART_SCALE)
			draw_texture_rect_region(ART.GUNS, Rect2(-grip, Vector2(256, 96)), Rect2(0, spec.cell * 96, 256, 96))
			draw_set_transform_matrix(Transform2D.IDENTITY)
			if recoil > 1.0:
				draw_circle(gun_offset(spec.muzzle), recoil * 0.55, Color(color, 0.8))
		"MAGIC":
			draw_line(Vector2(-18, 0), Vector2(30, 0), Color("20292e"), 7.0, true)
			draw_line(Vector2(-18, -1), Vector2(30, -1), Color("a3aaa0"), 2.0, true)
			for x in [-12, -5, 2, 19, 24]:
				draw_line(Vector2(x, -3), Vector2(x, 3), Color("5c696b"), 2.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(27, 0), Vector2(36, -7), Vector2(45, 0), Vector2(36, 7)]), Color("7d8988"))
			draw_colored_polygon(PackedVector2Array([Vector2(31, 0), Vector2(36, -4), Vector2(41, 0), Vector2(36, 4)]), color)
		_:
			draw_line(Vector2(-8, 0), Vector2(12, 0), Color("20292e"), 7, true)
			for x in [-6, -2, 2, 6]:
				draw_line(Vector2(x, -3), Vector2(x, 3), Color("8c8b7c"), 1, true)
			if definition.id == "glaive":
				if active_glaive != null and is_instance_valid(active_glaive.get_ref()):
					return
				for angle in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
					var points := PackedVector2Array()
					for point in [Vector2(4, -3), Vector2(23, -9), Vector2(17, 8), Vector2(10, 3)]:
						points.append(Vector2(18, 0) + point.rotated(angle))
					draw_colored_polygon(points, Color("a1aeaa"))
					draw_line(points[0], points[1], color, 1.6, true)
				draw_circle(Vector2(18, 0), 5, Color("25363c"))
			elif definition.id in ["maul", "grav"]:
				draw_line(Vector2(6, 0), Vector2(30, 0), Color("697572"), 5, true)
				draw_colored_polygon(PackedVector2Array([Vector2(22, -13), Vector2(38, -13), Vector2(43, -8), Vector2(43, 11), Vector2(26, 14), Vector2(22, 9)]), Color("82908c"))
				draw_rect(Rect2(25, -8, 13, 17), Color("2e3c42"))
				draw_line(Vector2(40, -8), Vector2(40, 8), color, 3, true)
				if definition.id == "grav":
					draw_arc(Vector2(32, 0), 5, 0, TAU, 16, color, 2, true)
			elif definition.id == "whip":
				for link in range(7):
					var center := Vector2(12 + link * 5, sin(link * 0.9) * 5)
					draw_arc(center, 3.2, 0, TAU, 8, Color("b1b9b0"), 1.3, true)
				draw_circle(Vector2(47, sin(6 * 0.9) * 5), 3, color)
			else:
				var reach := 59.0 if definition.id == "lance" else 39.0
				draw_line(Vector2(11, -7), Vector2(11, 7), Color("a3aaa0"), 3.0, true)
				var blade := PackedVector2Array([Vector2(13, -4), Vector2(reach - 8, -5), Vector2(reach, 0), Vector2(20, 5), Vector2(13, 4)])
				draw_colored_polygon(blade, Color("9aa9a7"))
				draw_line(Vector2(14, 0), Vector2(reach, 0), Color("e0e3d5"), 1, true)
				draw_line(Vector2(20, 5), Vector2(reach, 0), color, 1.6, true)
				if definition.id == "fang":
					draw_colored_polygon(PackedVector2Array([Vector2(-8, 10), Vector2(17, 10), Vector2(23, 14), Vector2(-8, 16)]), Color("9aa9a7"))
					draw_line(Vector2(-6, 16), Vector2(23, 14), color, 1.5, true)

func gun_offset(point: Array) -> Vector2:
	var spec: Dictionary = ART.GUN_SPRITES[definition.id]
	return Vector2(point[0] - spec.grip[0], point[1] - spec.grip[1]).rotated(-spec.angle) * spec.scale * ART.ART_SCALE

func bow_pose() -> Dictionary:
	var spec: Dictionary = ART.BOW_SPRITES[definition.id]
	var fraction := clampf(charge / float(definition.get("charge", 1.0)), 0.0, 1.0)
	var stretch: Vector2 = Vector2(1 + 0.18 * fraction, 1 - 0.04 * fraction) * spec.scale * ART.ART_SCALE
	var tips: Array[Vector2] = []
	for point in spec.tips:
		tips.append(Vector2(point[0] - spec.grip[0], point[1] - spec.grip[1]) * stretch)
	return {"scale": stretch, "tips": tips, "nock": Vector2((tips[0].x + tips[1].x) * 0.5 - fraction * 7, 0)}

func support_offset() -> Vector2:
	if definition.family == "FIREARMS":
		return gun_offset(ART.GUN_SPRITES[definition.id].support)
	if definition.family == "ARCHERY":
		return bow_pose().nock
	return Vector2.ZERO

func muzzle_offset(release_fraction := 0.0) -> Vector2:
	if definition.family == "FIREARMS":
		return gun_offset(ART.GUN_SPRITES[definition.id].muzzle)
	if definition.family == "ARCHERY":
		# Reconstruct the nock on release, after charge input has been cleared.
		var old_charge := charge
		charge = float(definition.get("charge", 0.0)) * release_fraction
		var offset: Vector2 = bow_pose().nock + Vector2(34, 0)
		charge = old_charge
		return offset
	return Vector2(42, 0)
