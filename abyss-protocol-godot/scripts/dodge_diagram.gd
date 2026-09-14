extends RefCounted
## Three readable stages; animation illustrates decisions, never runs a fight.
const ART = preload("res://assets/ui/dodge_timing.svg")
const FONT = preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const LABELS = preload("res://assets/fonts/Readout.tres")

static func draw_on(canvas: Control, elapsed: float, still: bool) -> void:
	var paper := Color("e5e4d4")
	var quiet := Color("596c70")
	var orange := Color("ff8b6b")
	var teal := Color("a9d9cd")
	for x in [350, 710]: canvas.draw_line(Vector2(x, 16), Vector2(x, 145), Color("35454a"), 1)
	# Preparation is a glyph on the guardian; it is not a placed hit area.
	canvas.draw_texture_rect_region(ART, Rect2(72, 16, 82, 82), Rect2(0, 0, 96, 96))
	for point in [Vector2(211, 43), Vector2(246, 58), Vector2(211, 77)]:
		canvas.draw_arc(point, 13, 0, TAU, 24, orange if still or elapsed < 1.5 else quiet, 2, true)
	canvas.draw_line(Vector2(165, 62), Vector2(185, 62), quiet, 2)
	canvas.draw_string(LABELS, Vector2(28, 128), "01", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, orange)
	canvas.draw_string(FONT, Vector2(65, 128), "预告 · 先观察招式", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, paper)
	# An early walking response leaves the reserved blast area without a dash.
	var origin := Vector2(509, 61)
	var progress := 1.0 if still else clampf((elapsed - 1.5) / 1.9, 0, 1)
	canvas.draw_circle(origin, 43, Color(orange, 0.09))
	canvas.draw_arc(origin, 43, 0, TAU, 48, orange, 2, true)
	canvas.draw_arc(origin, maxf(1.0, 43 * progress), 0, TAU, 48, Color("ffcf9c"), 3, true)
	warning_mark(canvas, origin)
	var walking := 1.0 if still else clampf((elapsed - 1.5) / 1.15, 0, 1)
	var walker := origin + Vector2(96 * walking, 0)
	canvas.draw_texture_rect_region(ART, Rect2(walker - Vector2(24, 29), Vector2(48, 48)), Rect2(96, 0, 96, 96))
	for x in [563, 577, 591]: canvas.draw_line(Vector2(x, 80), Vector2(x + 5, 78), teal, 2, true)
	canvas.draw_string(LABELS, Vector2(383, 128), "02", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, orange)
	canvas.draw_string(FONT, Vector2(420, 128), "锁定 · 尽早移出", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, paper)
	# In slow motion, the short dash overlaps the blast, not the long warning.
	var center := Vector2(832, 61)
	var dashing := 1.0 if still else clampf((elapsed - 3.02) / 0.46, 0, 1)
	var blasted := not still and elapsed >= 3.4
	canvas.draw_circle(center, 43, Color(orange, 0.18 if blasted else 0.08))
	canvas.draw_arc(center, 43, 0, TAU, 48, orange, 2, true)
	if not blasted: canvas.draw_arc(center, maxf(1.0, 43 * progress), 0, TAU, 48, Color("ffcf9c"), 3, true)
	warning_mark(canvas, center)
	var pilot := center + Vector2(137 * dashing, 0)
	if still or (elapsed >= 3.02 and elapsed < 3.48):
		canvas.draw_texture_rect_region(ART, Rect2(center - Vector2(24, 29), Vector2(48, 48)), Rect2(96, 0, 96, 96), Color(paper, 0.25))
		canvas.draw_line(center + Vector2(20, 8), pilot + Vector2(-19, 8), teal, 3, true)
		canvas.draw_arc(pilot, 31, -1.25, 1.25, 24, teal, 3, true)
	canvas.draw_texture_rect_region(ART, Rect2(pilot - Vector2(24, 29), Vector2(48, 48)), Rect2(96, 0, 96, 96))
	canvas.draw_string(LABELS, Vector2(741, 128), "03", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, orange)
	canvas.draw_string(FONT, Vector2(778, 128), "来不及 · 再冲刺", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, paper)

static func warning_mark(canvas: Control, center: Vector2) -> void:
	canvas.draw_line(center - Vector2(8, 0), center + Vector2(8, 0), Color("ffcf9c"), 2, true)
	canvas.draw_line(center - Vector2(0, 8), center + Vector2(0, 8), Color("ffcf9c"), 2, true)
	canvas.draw_line(center - Vector2(0, 24), center - Vector2(0, 14), Color("fff0ce"), 3, true)
	canvas.draw_circle(center - Vector2(0, 10), 2, Color("fff0ce"))
