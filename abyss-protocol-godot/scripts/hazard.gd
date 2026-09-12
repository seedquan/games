extends Node2D
## Clearly telegraphed area damage; dash can evade it, parry cannot.
var game
var radius := 105.0
var delay := 0.95
var elapsed := 0.0
var damage := 18.0

func _physics_process(delta: float) -> void:
	if game.state != "playing":
		return
	elapsed += delta
	if elapsed >= delay:
		game.effect(position, Color("ff8b6b"), radius, 0.4)
		for member in game.team():
			if position.distance_to(member.position) < radius and game.has_sight(position, member.position):
				member.take_damage(damage, position, false)
		queue_free()
	queue_redraw()

func _draw() -> void:
	var fraction := clampf(elapsed / delay, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.35, 0.25, 0.1))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 60, Color("ff8b6b"), 2.0, true)
	draw_arc(Vector2.ZERO, maxf(1.0, radius * fraction), 0, TAU, 60, Color("ffcf9c"), 3.0, true)
	draw_line(Vector2(-12, 0), Vector2(12, 0), Color("ffcf9c"), 2.0, true)
	draw_line(Vector2(0, -12), Vector2(0, 12), Color("ffcf9c"), 2.0, true)
	# A closing ring plus warning glyph remains legible without color perception.
	draw_line(Vector2(0, -25), Vector2(0, -10), Color("fff0ce"), 4.0, true)
	draw_circle(Vector2(0, -3), 2.5, Color("fff0ce"))
