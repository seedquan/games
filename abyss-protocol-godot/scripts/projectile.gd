extends Area2D
## Swept collisions and per-leg hit tracking support fast bullets and returning blades.

const GLAIVE_RADIUS := 21.0
var game
var shooter
var direction := Vector2.RIGHT
var hostile := false
var damage := 18.0
var speed := 0.0
var life := 3.0
var spent := false
var visual := "plasma"
var tint := Color("67efe0")
var element := ""
var explosion := 0.0
var pierce_remaining := 0
var flight_elapsed := 0.0
var returning := false
var return_after := 0.5
var return_multiplier := 1.0
var charge_return := false
var charge_at_turn := 0.0
var hit_ids: Array[int] = []
var excluded: Array[RID] = []
var visual_offset := Vector2.ZERO
var reflected := false
var blade_shape: CircleShape2D
var return_guide: Node2D
var fuse_damage := 0.0
var fuse_seat := 0

func configure(options: Dictionary) -> void:
	return_after = options.get("return_after", 0.5)
	return_multiplier = options.get("return_multiplier", 1.0)
	visual = options.get("visual", "plasma")
	charge_return = options.get("charge_return", false) and visual == "glaive" and not hostile and game.campaign_version >= 2
	tint = Color(options.get("color", "ff7088" if hostile else "67efe0"))
	speed = options.get("speed", 300.0 if hostile else 720.0)
	life = options.get("life", 3.0)
	pierce_remaining = options.get("pierce", 0)
	element = options.get("element", "")
	explosion = options.get("explosion", 0.0)
	shooter = options.get("shooter", null)
	fuse_damage = options.get("fuse_damage", 0.0) if not hostile and shooter == null and game.campaign_version >= 2 else 0.0
	fuse_seat = options.get("fuse_seat", 0)
	visual_offset = options.get("visual_offset", Vector2(0, -28 if hostile else -34))

func _ready() -> void:
	collision_mask = 3 if hostile else 5
	if visual == "glaive" and not hostile and game.campaign_version >= 2:
		blade_shape = CircleShape2D.new()
		blade_shape.radius = GLAIVE_RADIUS
		$Collision.shape = blade_shape
		return_guide = preload("res://scripts/glaive_return_guide.gd").new()
		return_guide.projectile = weakref(self)
		game.get_node("World/WeaponGuides").add_child(return_guide)
		tree_exiting.connect(return_guide.queue_free)
	if speed <= 0.0:
		speed = 300.0 if hostile else 720.0
	body_entered.connect(_on_body_entered)
	rotation = direction.angle()

func return_charge_fraction() -> float:
	if not charge_return: return 0.0
	return charge_at_turn if returning else clampf(flight_elapsed / maxf(return_after, 0.001), 0.0, 1.0)

func begin_return() -> void:
	if returning: return
	# All early turns, including cover, earn only the time spent outbound.
	# Commit once: a long return or repeated recall cannot build more strength.
	charge_at_turn = return_charge_fraction()
	damage *= lerpf(1.0, return_multiplier, charge_at_turn) if charge_return else return_multiplier
	returning = true
	hit_ids.clear()
	excluded.clear()

func _physics_process(delta: float) -> void:
	if spent or game.state != "playing":
		return
	flight_elapsed += delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if visual == "glaive":
		if not is_instance_valid(shooter):
			queue_free()
			return
		if not returning and flight_elapsed >= return_after:
			begin_return()
		if returning:
			if global_position.distance_to(shooter.global_position) < 26.0:
				queue_free()
				return
			direction = global_position.direction_to(shooter.global_position)
	rotation = direction.angle()
	var destination := global_position + direction * speed * delta
	# A single physics tick may cross several bodies; every pierced body is excluded
	# from subsequent sweeps, while the first wall always terminates a shot.
	for step in range(16):
		var hit: Dictionary
		if blade_shape != null:
			hit = blade_contact(destination)
		else:
			var query := PhysicsRayQueryParameters2D.create(global_position, destination, collision_mask, excluded)
			query.hit_from_inside = true
			hit = get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			global_position = destination
			break
		global_position = hit.position
		if not hit.has("collider"): break
		var was_returning := returning
		var previous_direction := direction
		_on_body_entered(hit.collider)
		if spent or (returning and not was_returning) or not direction.is_equal_approx(previous_direction):
			break
		global_position += direction * 0.1
	queue_redraw()

func get_return_guide():
	return return_guide if is_instance_valid(return_guide) else null

func blade_contact(destination: Vector2, solid_only := false) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = blade_shape
	query.transform = Transform2D(0, global_position)
	query.collision_mask = 1 if solid_only else collision_mask
	query.exclude = excluded
	query.margin = 0.01
	# cast_motion ignores bodies already touching the initial shape.
	var contacts := space.intersect_shape(query, 16)
	var stop := global_position
	if contacts.is_empty():
		query.motion = destination - global_position
		var fractions := space.cast_motion(query)
		if fractions[0] >= 1.0: return {}
		stop = global_position.lerp(destination, fractions[0])
		query.transform.origin = global_position.lerp(destination, fractions[1])
		query.motion = Vector2.ZERO
		# Resolve the colliding body just past the safe fraction, without moving
		# the blade into it. A tiny margin absorbs the physics solver's tolerance.
		query.margin = 0.1
		contacts = space.intersect_shape(query, 16)
	if contacts.is_empty(): return {"position": stop}
	# At a shared boundary, solid cover wins over an overlapping enemy.
	for contact in contacts:
		if contact.collider is StaticBody2D:
			return {"position": stop, "collider": contact.collider}
	return {"position": stop, "collider": contacts[0].collider}

func _on_body_entered(body: Node2D) -> void:
	if spent or game.state != "playing" or body.get_instance_id() in hit_ids:
		return
	if body is StaticBody2D:
		if visual == "glaive" and not returning:
			begin_return()
			global_position -= direction * 10.0
			return
		finish_impact()
		return
	if hostile and body.is_in_group("player") and body.hp <= 0.0:
		if body is CollisionObject2D and body.get_rid() not in excluded:
			excluded.append(body.get_rid())
		return
	if not body.has_method("take_damage"):
		return
	# A deferred mask change may leave queued callbacks from the incoming shot.
	if not hostile and body.is_in_group("player"):
		return
	hit_ids.append(body.get_instance_id())
	if body is CollisionObject2D:
		excluded.append(body.get_rid())
	if hostile:
		var countering: bool = game.campaign_version >= 2 and body.is_in_group("player") and body.parry_left > 0.0
		body.take_damage(damage, global_position - direction * 20.0)
		if countering:
			reflect_from(body)
			return
	elif is_instance_valid(shooter):
		shooter.weapon_hit(body, damage, direction * 100.0, element)
	else:
		body.take_damage(damage, direction * 100.0)
		if fuse_damage > 0 and body.is_in_group("enemies"):
			game.PROGRESSION.FUSE.prime(body, fuse_damage, fuse_seat)
	game.effect(global_position + visual_offset, tint, 22.0, 0.18)
	if pierce_remaining > 0:
		pierce_remaining -= 1
	else:
		finish_impact()

func reflect_from(defender: Node2D) -> void:
	# Reuse the incoming projectile: no overlapping duplicates or spawn teleport.
	# Its visual offset remains fixed so the visible turn happens at contact.
	hostile = false
	reflected = true
	shooter = defender
	direction = -direction
	rotation = direction.angle()
	damage = maxf(damage, defender.damage)
	speed = maxf(620.0, speed * 1.8)
	life = 1.25
	flight_elapsed = 0.0
	returning = false
	return_after = 0.5
	return_multiplier = 1.0
	visual = "countershot"
	tint = Color("e8c17a")
	element = defender.weapon.definition.get("element", "")
	explosion = 0.0
	pierce_remaining = 0
	hit_ids.clear()
	excluded.clear()
	# Area2D callbacks can arrive while physics is flushing contact queries.
	set_deferred("collision_mask", 5)
	game.effect(global_position + visual_offset, tint, 22.0, 0.18)
	queue_redraw()

func finish_impact() -> void:
	if spent:
		return
	spent = true
	if explosion > 0.0 and is_instance_valid(shooter):
		var center := global_position - direction * 8.0
		game.effect(center, tint, explosion, 0.4)
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.get_instance_id() not in hit_ids and center.distance_to(enemy.global_position) < explosion:
				if game.has_sight(center, enemy.global_position):
					shooter.weapon_hit(enemy, damage * 0.7, center.direction_to(enemy.global_position) * 160.0, element)
		if element == "fire":
			game.spawn_field(center, shooter, "fire", damage, explosion * 0.75, 2.4)
	queue_free()

func _draw() -> void:
	# Collision proxies stay on the floor; visible projectiles share the actors'
	# raised presentation plane and start at the painted weapon's exact muzzle.
	draw_set_transform(visual_offset.rotated(-rotation))
	match visual:
		"countershot":
			draw_line(Vector2(-30, 0), Vector2(-5, 0), Color(tint, 0.45), 3.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(10, 0), Vector2(-4, -6), Vector2(-1, 0), Vector2(-4, 6)]), tint)
			draw_line(Vector2(-12, -5), Vector2(-7, 0), Color("ece8d9"), 1.5, true)
			draw_line(Vector2(-12, 5), Vector2(-7, 0), Color("ece8d9"), 1.5, true)
		"arrow":
			draw_line(Vector2(-27, 0), Vector2(5, 0), Color("ddd8bf"), 2.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(11, 0), Vector2(1, -4), Vector2(1, 4)]), tint)
			draw_line(Vector2(-25, -5), Vector2(-19, 0), tint, 2.0, true)
			draw_line(Vector2(-25, 5), Vector2(-19, 0), tint, 2.0, true)
		"glaive":
			if charge_return:
				var begin := -PI / 2 - rotation
				var end := begin + TAU * return_charge_fraction()
				draw_arc(Vector2.ZERO, 29, begin, begin + TAU, 48, Color("10191c"), 5, true)
				draw_arc(Vector2.ZERO, 29, begin, begin + TAU, 48, Color("698579"), 1, true)
				if end > begin:
					draw_arc(Vector2.ZERO, 29, begin, end, 48, Color("fff0bd"), 2.5, true)
			for i in range(3):
				var angle := flight_elapsed * 22.0 + float(i) * TAU / 3.0
				draw_arc(Vector2.ZERO, GLAIVE_RADIUS, angle, angle + 1.4, 12, tint, 5, true)
			draw_circle(Vector2.ZERO, 5, Color.WHITE)
		"orb":
			draw_circle(Vector2.ZERO, 15, Color(tint, 0.14))
			draw_circle(Vector2.ZERO, 7, tint)
			draw_circle(Vector2(2, -2), 3, Color.WHITE)
		_:
			var length := 54.0 if visual == "rail" else 22.0
			draw_line(Vector2(-length, 0), Vector2.ZERO, Color(tint, 0.18), 12.0, true)
			draw_line(Vector2(-length, 0), Vector2(3, 0), tint, 3.0 if visual == "bullet" else 5.0, true)
			draw_circle(Vector2.ZERO, 2.0, Color.WHITE)
