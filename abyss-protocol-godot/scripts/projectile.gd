extends Area2D
## Swept collisions and per-leg hit tracking support fast bullets and returning blades.

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
var hit_ids: Array[int] = []
var excluded: Array[RID] = []
var visual_offset := Vector2.ZERO

func configure(options: Dictionary) -> void:
	visual = options.get("visual", "plasma")
	tint = Color(options.get("color", "ff7088" if hostile else "67efe0"))
	speed = options.get("speed", 300.0 if hostile else 720.0)
	life = options.get("life", 3.0)
	pierce_remaining = options.get("pierce", 0)
	element = options.get("element", "")
	explosion = options.get("explosion", 0.0)
	shooter = options.get("shooter", null)
	visual_offset = options.get("visual_offset", Vector2(0, -28 if hostile else -34))

func _ready() -> void:
	collision_mask = 3 if hostile else 5
	if speed <= 0.0:
		speed = 300.0 if hostile else 720.0
	body_entered.connect(_on_body_entered)
	rotation = direction.angle()

func begin_return() -> void:
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
		if not returning and flight_elapsed >= 0.5:
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
		var query := PhysicsRayQueryParameters2D.create(global_position, destination, collision_mask, excluded)
		query.hit_from_inside = true
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			global_position = destination
			break
		global_position = hit.position
		var was_returning := returning
		_on_body_entered(hit.collider)
		if spent or (returning and not was_returning):
			break
		global_position += direction * 0.1
	queue_redraw()

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
	hit_ids.append(body.get_instance_id())
	if body is CollisionObject2D:
		excluded.append(body.get_rid())
	if hostile:
		body.take_damage(damage, global_position - direction * 20.0)
	elif is_instance_valid(shooter):
		shooter.weapon_hit(body, damage, direction * 100.0, element)
	else:
		body.take_damage(damage, direction * 100.0)
	game.effect(global_position + visual_offset, tint, 22.0, 0.18)
	if pierce_remaining > 0:
		pierce_remaining -= 1
	else:
		finish_impact()

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
		"arrow":
			draw_line(Vector2(-27, 0), Vector2(5, 0), Color("ddd8bf"), 2.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(11, 0), Vector2(1, -4), Vector2(1, 4)]), tint)
			draw_line(Vector2(-25, -5), Vector2(-19, 0), tint, 2.0, true)
			draw_line(Vector2(-25, 5), Vector2(-19, 0), tint, 2.0, true)
		"glaive":
			for i in range(3):
				var angle := flight_elapsed * 22.0 + float(i) * TAU / 3.0
				draw_arc(Vector2.ZERO, 21, angle, angle + 1.4, 12, tint, 5, true)
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
