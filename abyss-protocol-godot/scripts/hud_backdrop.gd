extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(0, 0, size.x, 104), Color(0.045, 0.062, 0.068, 0.94))
	draw_line(Vector2(30, 104), Vector2(size.x - 30, 104), Color("4f5857"), 1)
	draw_rect(Rect2(0, size.y - 104, size.x, 104), Color(0.045, 0.062, 0.068, 0.92))
	draw_line(Vector2(30, size.y - 104), Vector2(size.x - 30, size.y - 104), Color("4f5857"), 1)
