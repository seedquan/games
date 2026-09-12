extends Node2D
## A bounded, world-owned fire pool or gravitational well. Cleared on room exit.

var game
var shooter
var mode := "fire"
var damage := 10.0
var radius := 105.0
var duration := 2.4
var elapsed := 0.0
var tick_left := 0.0

func _physics_process(delta: float) -> void:
	if game.state != "playing":
		return
	elapsed += delta
	tick_left -= delta
	if mode == "gravity":
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if position.distance_to(enemy.position) < radius and game.has_sight(position, enemy.position):
				enemy.knockback += enemy.position.direction_to(position) * delta * 1000.0
	elif tick_left <= 0.0:
		tick_left = 0.4
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if position.distance_to(enemy.position) < radius and game.has_sight(position, enemy.position):
				if is_instance_valid(shooter):
					shooter.weapon_hit(enemy, damage * 0.16, Vector2.ZERO, "fire")
	if elapsed >= duration:
		if mode == "gravity" and is_instance_valid(shooter):
			game.effect(position, Color("b98cff"), radius, 0.5)
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if position.distance_to(enemy.position) < radius and game.has_sight(position, enemy.position):
					shooter.weapon_hit(enemy, damage, position.direction_to(enemy.position) * 400.0)
		queue_free()
	queue_redraw()

func _draw() -> void:
	var color := Color("b98cff") if mode == "gravity" else Color("ff7a3c")
	var fade := minf(1.0, (duration - elapsed) * 2.0)
	draw_circle(Vector2.ZERO, radius, Color(color, 0.08 * fade))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(color, 0.45 * fade), 2.0, true)
	for i in range(3):
		var fraction := fposmod(elapsed * 0.8 + float(i) / 3.0, 1.0)
		var ring := radius * (1.0 - fraction if mode == "gravity" else fraction)
		draw_arc(Vector2.ZERO, maxf(1.0, ring), elapsed + i, elapsed + i + PI * 1.5, 40, Color(color, 0.45 * fade), 2.0, true)
