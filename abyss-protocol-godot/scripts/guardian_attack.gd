extends Node2D
## A placed, fully warned boss attack. Drawing and hits share cached polygons.

const IDS := ["sweep", "coolant", "lattice", "heat_ring", "sequence"]
var game
var shape := "sector"
var radius := 260.0
var inner_radius := 0.0
var half_angle := 1.05
var half_width := 38.0
var heading := 0.0
var delay := 0.95
var elapsed := 0.0
var damage := 22.0
var fired := false
var regions: Array[PackedVector2Array] = []

static func placements(id: String, origin: Vector2, aim: Vector2, targets: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match id:
		"sweep": result.append({"position": origin, "shape": "sector", "radius": 260.0, "heading": aim.angle()})
		"coolant":
			for target in targets:
				for i in range(3):
					result.append({"position": target.position + aim.orthogonal() * (i - 1) * 120.0,
						"shape": "circle", "radius": 72.0, "delay": 0.95 + i * 0.3})
		"lattice":
			for i in range(2):
				result.append({"position": origin, "shape": "beam", "radius": 440.0, "heading": aim.angle() + i * PI / 2})
		"heat_ring": result.append({"position": origin, "shape": "ring", "radius": 290.0, "inner_radius": 125.0, "delay": 1.05})
		"sequence":
			for i in range(4):
				result.append({"position": origin, "shape": "sector", "radius": 360.0, "inner_radius": 80.0,
					"heading": aim.angle() + i * PI / 2, "half_angle": 0.6, "delay": 0.95 + i * 0.35})
	return result

func configure(spec: Dictionary) -> void:
	for key in spec: set(key, spec[key])
	if shape == "beam":
		regions.append(PackedVector2Array([Vector2(-radius, -half_width), Vector2(radius, -half_width), Vector2(radius, half_width), Vector2(-radius, half_width)]))
	elif shape == "circle":
		var polygon := PackedVector2Array()
		for i in range(64): polygon.append(Vector2.from_angle(TAU * i / 64) * radius)
		regions.append(polygon)
	else:
		var angle := PI if shape == "ring" else half_angle
		# Convex wedges leave an actual hole in rings and sequenced sectors.
		for i in range(64):
			var a := Vector2.from_angle(lerpf(-angle, angle, i / 64.0))
			var b := Vector2.from_angle(lerpf(-angle, angle, (i + 1) / 64.0))
			var polygon := PackedVector2Array([a * inner_radius, a * radius, b * radius])
			if inner_radius > 0: polygon.append(b * inner_radius)
			regions.append(polygon)
	for index in range(regions.size()):
		var polygon := regions[index]
		for i in range(polygon.size()): polygon[i] = polygon[i].rotated(heading)
		regions[index] = polygon

func contains_point(point: Vector2) -> bool:
	var local := to_local(point)
	return regions.any(func(polygon): return Geometry2D.is_point_in_polygon(local, polygon))

func _physics_process(delta: float) -> void:
	if game.state != "playing": return
	elapsed += delta
	if elapsed >= delay and not fired:
		fired = true
		for member in game.team():
			if contains_point(member.global_position) and game.has_sight(global_position, member.global_position):
				member.take_damage(damage, global_position, false)
	if elapsed >= delay + 0.18: queue_free()
	queue_redraw()

func _draw() -> void:
	var progress := clampf(elapsed / delay, 0, 1)
	var color := Color("ffb66d")
	var alpha := 0.1 + progress * 0.13
	if fired: alpha = 0.22 + 0.24 * float(game.settings.values.flash)
	for polygon in regions: draw_colored_polygon(polygon, Color(color, alpha))
	if shape in ["beam", "circle"]:
		var outline := regions[0].duplicate()
		outline.append(outline[0])
		draw_polyline(outline, color, 2.5, true)
	else:
		var angle := PI if shape == "ring" else half_angle
		draw_arc(Vector2.ZERO, radius, heading - angle, heading + angle, 65, color, 2.5, true)
		if inner_radius > 0:
			draw_arc(Vector2.ZERO, inner_radius, heading - angle, heading + angle, 65, color, 2.5, true)
		if shape == "sector":
			for a in [heading - angle, heading + angle]:
				var direction := Vector2.from_angle(a)
				draw_line(direction * inner_radius, direction * radius, color, 2.5, true)
	var mark := Vector2.from_angle(heading) * ((inner_radius + radius) * 0.5 if shape in ["ring", "sector"] else 0.0)
	# A closing timer and warning mark supplement colour; never change the hit area.
	draw_arc(mark, 17, -PI / 2, -PI / 2 + TAU * progress, 32, Color("fff0ce"), 2.5, true)
	draw_line(mark + Vector2(0, -8), mark + Vector2(0, 2), Color("fff0ce"), 3, true)
	draw_circle(mark + Vector2(0, 8), 1.8, Color("fff0ce"))
