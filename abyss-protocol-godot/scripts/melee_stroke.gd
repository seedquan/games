extends Node2D
## A short world-space trace of the resolved hit, independent of the moving owner.
## The silhouette appears immediately; the flourish never changes combat geometry.

var game
var kind := "blade"
var tint := Color("aaf6ff")
var reach := 105.0
var arc := 1.4
var elapsed := 0.0
var duration := 0.22
var combo := 1
var edge := PackedVector2Array()
var spine := PackedVector2Array()
var visual_offset := Vector2.ZERO

func configure(actor, definition: Dictionary, strike: int) -> void:
	game = actor.game
	position = actor.global_position
	rotation = actor.aim.angle()
	visual_offset = (actor.weapon.global_position - position).rotated(-rotation)
	kind = definition.id
	tint = Color(definition.color)
	reach = definition.reach
	arc = definition.arc
	combo = strike
	duration = 0.28 if kind == "maul" else 0.24 if kind == "whip" else 0.16 if kind == "fang" else 0.22
	# Clip the trace once at the same cover that blocks the hit. No physics work in draw.
	for i in range(33):
		edge.append(clipped(Vector2.from_angle(lerpf(-arc, arc, i / 32.0)) * reach))
	if kind == "whip":
		for i in range(17):
			var fraction := i / 16.0
			spine.append(clipped(Vector2(reach * fraction, sin(fraction * TAU) * 13.0 * fraction)))

func clipped(point: Vector2) -> Vector2:
	return (game.clip_to_wall(position, position + point.rotated(rotation)) - position).rotated(-rotation)

func _process(delta: float) -> void:
	if game.state != "playing": return
	elapsed += delta
	if elapsed >= duration:
		queue_free()
	queue_redraw()

func _draw() -> void:
	if edge.is_empty(): return
	var progress := clampf(elapsed / duration, 0, 1)
	var fade := 1.0 - progress
	var flash := float(game.settings.values.flash)
	var motion := progress if flash > 0.0 else 0.0
	var color := Color(tint, fade * 0.7)
	var highlight := Color(tint.lerp(Color("ece8d9"), 0.75), fade * flash * 0.85)
	# Quiet, complete footprint remains legible with flash disabled.
	draw_polyline(edge, Color(tint, fade * 0.16), 1.0, true)
	# Lift the material stroke to the captured hand, like projectile launch offsets.
	# Ground footprint and collision stay in the common floor plane.
	draw_set_transform(visual_offset)
	match kind:
		"lance":
			var tip := edge[16]
			if tip.x > 1.0:
				var base := Vector2(minf(59.0, tip.x * 0.3), 0).lerp(tip * 0.6, motion)
				var half_width := minf(5.0, tip.x * 0.08)
				draw_colored_polygon(PackedVector2Array([base, tip * 0.83 + Vector2(0, -half_width), tip,
					tip * 0.83 + Vector2(0, half_width)]), color)
				draw_line(base, tip, highlight, 2.0, true)
		"whip":
			var line := PackedVector2Array()
			for point in spine:
				line.append(point * (1.0 - 0.65 * motion * motion))
			draw_polyline(line, color, 3.0, true)
			for i in range(2, line.size(), 2):
				draw_circle(line[i], 2.0, highlight)
		"maul":
			for i in range(2, 30, 5):
				var tip := edge[i]
				var side := edge[i + 2]
				var inner := 0.46 + motion * 0.32
				# Broad chips disperse from the hammer impact; no extra circular explosion.
				draw_colored_polygon(PackedVector2Array([tip * inner, tip * 0.96,
					side * 0.9, side * (inner + 0.06)]), Color(tint, fade * 0.38))
				draw_line(tip * inner, tip * 0.96, highlight, 2.0, true)
		"fang":
			draw_sweep(edge, motion, color, 3.0, combo % 2 == 0)
			var inner := PackedVector2Array()
			for point in edge: inner.append(point * 0.73)
			draw_sweep(inner, motion, color, 2.0, combo % 2 != 0)
			if combo % 3 == 0:
				draw_line(edge[8] * 0.35, edge[24], highlight, 3.0, true)
				draw_line(edge[24] * 0.35, edge[8], highlight, 3.0, true)
		_:
			draw_sweep(edge, motion, color, 5.0 if kind == "arc" else 3.0, false)
			if kind == "prism": draw_line(edge[16] * 0.3, edge[16], highlight, 2.0, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func draw_sweep(points: PackedVector2Array, progress: float, color: Color, width: float, reverse: bool) -> void:
	var start := mini(22, int(progress * 24.0))
	var trace := PackedVector2Array()
	for i in range(start, points.size()):
		trace.append(points[points.size() - 1 - i if reverse else i])
	draw_polyline(trace, color, width, true)
