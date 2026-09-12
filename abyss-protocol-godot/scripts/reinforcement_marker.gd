extends Node2D
## An amber delivery signal is distinct from red damaging floor warnings.
const FONT = preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
var progress := 0.0

func _draw() -> void:
	var ink := Color("f1be77")
	draw_circle(Vector2.ZERO, 37, Color(0.08, 0.07, 0.04, 0.85))
	draw_arc(Vector2.ZERO, 34, -PI * 0.5, -PI * 0.5 + TAU * maxf(progress, 0.02), 40, ink, 3, true)
	for angle in [0, PI * 0.5, PI, PI * 1.5]:
		var point := Vector2.from_angle(angle) * 46
		draw_line(point, point * 1.2, ink, 3)
	draw_string(FONT, Vector2(-16, 5), "增援", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)
