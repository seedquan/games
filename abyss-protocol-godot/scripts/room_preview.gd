extends Control
## Route thumbnail uses the same solid geometry as physics, never a decorative map.
var room: Dictionary = {}
var map_texture: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_texture = load(room.art) if room.has("art") else null
	resized.connect(queue_redraw)

func _draw() -> void:
	if room.is_empty(): return
	var bounds: Rect2 = room.get("bounds", Rect2(0, 0, 1600, 1050))
	var factor := minf((size.x - 20.0) / bounds.size.x, (size.y - 12.0) / bounds.size.y)
	var offset := (size - bounds.size * factor) * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color("111a1e"))
	draw_rect(Rect2(offset, bounds.size * factor), Color("53605b"))
	for rect in room.get("shell", []):
		draw_rect(Rect2(offset + rect.position * factor, rect.size * factor), Color("111a1e"))
	for rect in room.get("furnishings", room.cover):
		draw_rect(Rect2(offset + rect.position * factor, rect.size * factor), Color("a6ada0"))
	if map_texture != null:
		draw_texture_rect(map_texture, Rect2(offset, bounds.size * factor), false)
	draw_circle(offset + room.start * factor, 3.5, Color("abe0d1"))
	for point in room.get("exits", [Vector2(600, 185), Vector2(1000, 185)]):
		draw_rect(Rect2(offset + point * factor - Vector2(4, 3), Vector2(8, 6)), Color("efb779"))
