extends Node2D

var color := Color("67efe0")
var radius := 60.0
var duration := 0.4
var elapsed := 0.0

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	if radius > 35.0:
		draw_arc(Vector2.ZERO, maxf(1.0, radius * ease(progress, 0.5)), 0, TAU, 64,
			Color(color, (1.0 - progress) * 0.7), maxf(1.0, 3.0 * (1.0 - progress)), true)
	for i in range(10):
		var direction := Vector2.from_angle(float(i) / 10.0 * TAU)
		draw_line(direction * radius * progress, direction * (radius * progress + 8.0), Color(color, 1.0 - progress), 2.0, true)
