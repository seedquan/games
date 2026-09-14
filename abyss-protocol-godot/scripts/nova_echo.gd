extends Node2D
## One committed, world-owned nova echo. Pauses with combat and clears on exit.
const ID := "nova_echo"
const DELAY := 0.8
const RADIUS := 270.0
const DAMAGE_FRACTION := 0.45
const DIAGRAM = preload("res://assets/ui/nova_echo.svg")
const CARD := {"stat": ID, "name": "霜火回响", "tag": "技能 · 新星", "description": "新星冻结后，在施放位置留下延迟的火焰回响。"}
var game
var damage := 0.0
var elapsed := 0.0
var fired := false
var boundary := PackedVector2Array()

static func description(base_damage: float) -> String:
	return "新星施放 0.8 秒后，原位置爆发火焰。\n范围 270，造成 %.1f 火焰伤害，可引爆冻结与毒素。\n保留十秒冷却；掩体阻挡回响。不可叠加。" % (base_damage * DAMAGE_FRACTION)

func _ready() -> void:
	for i in range(72):
		var direction := Vector2.from_angle(float(i) / 72.0 * TAU)
		var clipped: Vector2 = game.clip_to_wall(global_position, global_position + direction * RADIUS)
		boundary.append(direction * clampf((clipped - global_position).dot(direction), 0, RADIUS))

func _physics_process(delta: float) -> void:
	if game.state != "playing": return
	elapsed += delta
	if not fired and elapsed >= DELAY:
		fired = true
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.dead or global_position.distance_to(enemy.global_position) >= RADIUS: continue
			if not game.has_sight(global_position, enemy.global_position): continue
			# Shared skills do not inherit weapon runes, leech or execute. Fire
			# uses the existing nonrecursive thermal/poison reaction rules.
			enemy.take_damage(damage, Vector2.ZERO)
			enemy.apply_element("fire", damage)
		game.play_tone(360.0, 0.18, 0.04)
	if elapsed >= DELAY + 0.45: queue_free()
	queue_redraw()

func _draw() -> void:
	if boundary.size() < 3: return
	var warm := Color("e6b879")
	var fade := 1.0 - clampf((elapsed - DELAY) / 0.45, 0.0, 1.0)
	var flash: float = game.settings.values.flash
	draw_colored_polygon(boundary, Color(warm, (0.025 + (0.045 * flash if fired else 0.0)) * fade))
	var outline := boundary.duplicate()
	outline.append(boundary[0])
	draw_polyline(outline, Color(warm, 0.42 * fade), 2.0, true)
	# The center glyph and fixed boundary remain legible with flashes disabled.
	draw_texture_rect_region(DIAGRAM, Rect2(-27, -27, 54, 54), Rect2(240, 0, 144, 144), Color(1, 1, 1, fade))
	if not fired:
		draw_arc(Vector2.ZERO, 32, -PI / 2, -PI / 2 + TAU * minf(1, elapsed / DELAY), 36, Color("b3e8f2"), 2, true)
	else:
		var expansion := clampf((elapsed - DELAY) / 0.45, 0.0, 1.0)
		for i in range(0, boundary.size(), 6):
			var end: Vector2 = boundary[i] * expansion
			draw_line(end * 0.85, end, Color(warm, fade * (0.35 + flash * 0.4)), 2, true)
