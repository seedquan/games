extends Control
## A readable visual legend for the same shapes used by enemy telegraphs.

const FONT = preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")

func _ready() -> void:
	custom_minimum_size = Vector2(1080, 310)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var red := Color("ff7088")
	var orange := Color("ffb66d")
	var paper := Color("e5e4d4")
	var centers := [Vector2(130, 67), Vector2(500, 67), Vector2(875, 67)]
	draw_circle(centers[0], 12, Color("646f6c"))
	draw_arc(centers[0], 54, -0.85, 0.85, 30, red, 3, true)
	draw_line(centers[0], centers[0] + Vector2(90, 0), Color(red, 0.5), 1, true)
	draw_circle(centers[1], 46, Color(orange, 0.13))
	draw_arc(centers[1], 46, 0, TAU, 40, orange, 2, true)
	draw_string(FONT, centers[1] + Vector2(-7, 10), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, orange)
	draw_circle(centers[2] - Vector2(40, 0), 12, Color(paper, 0.25))
	draw_circle(centers[2] + Vector2(54, 0), 12, paper)
	draw_line(centers[2] - Vector2(16, 0), centers[2] + Vector2(28, 0), paper, 2)
	draw_polyline(PackedVector2Array([centers[2] + Vector2(16, -9), centers[2] + Vector2(28, 0), centers[2] + Vector2(16, 9)]), paper, 2, true)
	for item in [[Vector2(30, 147), "红色前摇 · 离开正前方"], [Vector2(385, 147), "橙色爆区 · 移出范围"], [Vector2(765, 147), "冲刺脱离 · 短暂无敌"]]:
		draw_string(FONT, item[0], item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, paper)
	var hints := ["横扫 · 绕到侧后", "封路 · 留意落点", "光栅 · 离开光带", "热环 · 内外皆可避", "重排 · 跟随空隙"]
	for i in range(5):
		var x := 24.0 + i * 216.0
		draw_texture_rect_region(preload("res://assets/ui/boss_signatures.svg"), Rect2(x + 40, 185, 64, 64), Rect2(i * 64, 0, 64, 64))
		draw_string(FONT, Vector2(x, 283), hints[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, paper)
