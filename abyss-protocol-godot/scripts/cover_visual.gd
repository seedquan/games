extends Node2D
## Raised dressing above the exact collision footprint; sorted with characters.

const ATLAS = preload("res://assets/cover_props.webp")
var game
var cell := 0
var extent := Vector2(140, 155)
var opacity := 1.0

func _process(delta: float) -> void:
	var obscures := false
	for member in game.team():
		if member.position.y < global_position.y:
			var character := Rect2(member.position - Vector2(26, 82), Vector2(52, 100))
			var prop := Rect2(global_position - extent * Vector2(0.5, 0.82), extent)
			obscures = obscures or prop.intersects(character)
	opacity = lerpf(opacity, 0.35 if obscures else 1.0, 1.0 - exp(-16.0 * delta))
	modulate.a = opacity

func _draw() -> void:
	draw_texture_rect_region(ATLAS, Rect2(-extent * Vector2(0.5, 0.82), extent), Rect2((cell % 3) * 256, (cell / 3) * 256, 256, 256))
