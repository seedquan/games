extends Node2D

var color := Color("67efe0")
var radius := 60.0
var duration := 0.4
var elapsed := 0.0
var reaction := ""
var intensity := 1.0

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	if not reaction.is_empty():
		draw_reaction(progress)
		return
	if radius > 35.0:
		draw_arc(Vector2.ZERO, maxf(1.0, radius * ease(progress, 0.5)), 0, TAU, 64,
			Color(color, (1.0 - progress) * 0.7), maxf(1.0, 3.0 * (1.0 - progress)), true)
	for i in range(10):
		var direction := Vector2.from_angle(float(i) / 10.0 * TAU)
		draw_line(direction * radius * progress, direction * (radius * progress + 8.0), Color(color, 1.0 - progress), 2.0, true)

func draw_reaction(progress: float) -> void:
	# The full boundary appears immediately and matches the damage radius.
	# Small authored shards/embers distinguish player combos from enemy hazards.
	var fade := 1.0 - progress
	if fade < 0.03: return
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(color, fade * 0.65), 2.0, true)
	var outward := radius * (0.18 + 0.75 * ease(progress, 0.5))
	var tint := color.lerp(Color("ffd27a"), progress)
	for i in range(12):
		var direction := Vector2.from_angle(float(i) / 12.0 * TAU)
		var side := direction.orthogonal()
		var center := direction * outward
		var size := (12.0 if reaction == "thermal" else 8.0) * fade
		if reaction == "thermal":
			draw_colored_polygon(PackedVector2Array([center + direction * size, center + side * size * 0.4,
				center - direction * size * 0.65, center - side * size * 0.4]), Color(tint, fade * (0.4 + intensity * 0.5)))
		else:
			draw_arc(center, maxf(1.0, size), 0, TAU, 8, Color(tint, fade * (0.4 + intensity * 0.5)), 2, true)
