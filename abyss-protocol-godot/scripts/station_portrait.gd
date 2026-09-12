extends Control
## Original vector key art: the damaged habitat above a planet's night side.
## Fixed geometry keeps menu rendering cheap and needs no external textures.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var scale_factor := minf(size.x / 640.0, size.y / 720.0)
	draw_set_transform((size - Vector2(640, 720) * scale_factor) * 0.5, 0, Vector2.ONE * scale_factor)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31207
	for i in range(58):
		var point := Vector2(rng.randf_range(20, 630), rng.randf_range(0, 690))
		draw_circle(point, rng.randf_range(0.5, 1.3), Color(0.79, 0.78, 0.70, rng.randf_range(0.12, 0.55)))
	# The planet is a broad quiet mass; its thin atmosphere frames the station.
	draw_circle(Vector2(500, 800), 400, Color("302d29"))
	draw_arc(Vector2(500, 800), 400, PI, TAU, 120, Color("8b765a"), 3.0, true)
	for i in range(12):
		draw_arc(Vector2(500, 800), 392 - i * 7, PI + 0.25, TAU - 0.28, 90, Color(0.37, 0.32, 0.25, 0.11), 3.0, true)
	draw_circle(Vector2(554, 867), 391, Color("161d20"))
	# Oblique habitat ring, split into industrial modules with visible structure.
	var center := Vector2(328, 310)
	for i in range(48):
		var a := float(i) / 48.0 * TAU
		if i in [4, 5, 6]:
			continue
		var b := a + TAU / 48.0 * 0.88
		var upper := PackedVector2Array([orbit(center, a, 245), orbit(center, b, 245), orbit(center, b, 204), orbit(center, a, 204)])
		var side := PackedVector2Array([upper[0], upper[1], upper[1] + Vector2(0, 24), upper[0] + Vector2(0, 24)])
		draw_colored_polygon(side, Color("171f23"))
		draw_polyline(PackedVector2Array([side[3], side[2]]), Color("455052"), 1.0, true)
		draw_colored_polygon(upper, Color("424847") if i > 23 else Color("2c3639"))
		draw_polyline(PackedVector2Array([upper[0], upper[1], upper[2], upper[3], upper[0]]), Color("64706c"), 1.0, true)
		if i % 3 == 0:
			draw_line(orbit(center, a + 0.03, 229), orbit(center, b - 0.02, 229), Color("b99560"), 2.0, true)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var end := orbit(center, angle, 208)
		draw_line(center + Vector2(0, 12), end + Vector2(0, 12), Color("0e171b"), 18, true)
		draw_line(center, end, Color("52605f"), 10, true)
		draw_line(center - Vector2(0, 4), end - Vector2(0, 4), Color("8c9185"), 1, true)
	# Spine, radiator wings, command capsule, and a single warm rescue beacon.
	var axis := Vector2(0.36, -0.93)
	for sign_value in [-1, 1]:
		var anchor: Vector2 = center + axis * sign_value * 78
		for wing in [-1, 1]:
			var across: Vector2 = axis.orthogonal() * wing
			var corners := PackedVector2Array([anchor, anchor + axis * 56, anchor + axis * 56 + across * 126, anchor + across * 126])
			draw_colored_polygon(corners, Color("263c40"))
			draw_polyline(PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]]), Color("617471"), 1, true)
			for rib in range(1, 8):
				draw_line(anchor + across * rib * 16, anchor + axis * 56 + across * rib * 16, Color("435954"), 1, true)
	draw_line(center - axis * 181, center + axis * 190, Color("10191d"), 38, true)
	draw_line(center - axis * 181, center + axis * 190, Color("68716a"), 24, true)
	draw_line(center - axis * 181 + Vector2(-6, 0), center + axis * 190 + Vector2(-6, 0), Color("a6a491"), 3, true)
	draw_circle(center, 35, Color("152027"))
	draw_arc(center, 29, 0, TAU, 32, Color("b7b6a1"), 4, true)
	draw_circle(center, 15, Color("535d57"))
	draw_line(center + axis * 190, center + axis * 225, Color("989c8e"), 2, true)
	draw_circle(center + axis * 228, 4, Color("efb16c"))
	# Caption leaders are structural, not decorative charts.
	draw_polyline(PackedVector2Array([center + Vector2(162, 50), Vector2(542, 425), Vector2(600, 425)]), Color("7c8176"), 1, true)
	draw_circle(center + Vector2(162, 50), 3, Color("e6b879"))

func orbit(center: Vector2, angle: float, radius: float) -> Vector2:
	return center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.54).rotated(-0.26)
