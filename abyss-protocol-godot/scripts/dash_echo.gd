extends Node2D
## A committed dash-origin shock. Shared skill damage never inherits weapon procs.
const ID := "dash_echo"
const DELAY := 0.6
const RADIUS := 150.0
const DAMAGE_FRACTION := 0.35
const DIAGRAM = preload("res://assets/ui/dash_echo.svg")
const CARD := {"stat": ID, "name": "雷霆残影", "tag": "技能 · 冲刺", "description": "冲刺起点留下残影，短暂延迟后向周围放电。"}
var game
var damage := 0.0
var elapsed := 0.0
var fired := false
var seat := 0
var boundary := PackedVector2Array()

func _ready() -> void:
	for i in range(64):
		var direction := Vector2.from_angle(float(i) / 64 * TAU)
		var clipped: Vector2 = game.clip_to_wall(global_position, global_position + direction * RADIUS)
		boundary.append(direction * clampf((clipped - global_position).dot(direction), 0, RADIUS))

static func description(base_damage: float) -> String:
	return "冲刺起点留下残影，0.6 秒后放电。\n范围 150，造成 %.1f 电击伤害；冻结目标可接霜链。\n沿用冲刺冷却；掩体阻挡。不可叠加。" % (base_damage * DAMAGE_FRACTION)

func _physics_process(delta: float) -> void:
	if game.state != "playing": return
	elapsed += delta
	if not fired and elapsed >= DELAY:
		fired = true
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.dead or global_position.distance_to(enemy.global_position) >= RADIUS: continue
			if not game.has_sight(global_position, enemy.global_position): continue
			enemy.take_damage(damage, Vector2.ZERO)
			enemy.apply_element("shock", damage)
		game.play_tone(680.0, 0.12, 0.035)
	if elapsed >= DELAY + 0.3: queue_free()
	queue_redraw()

func _draw() -> void:
	if boundary.size() < 3: return
	var tint := Color("91dbe8")
	var owner_tint := Color("e6b879") if seat == 1 else tint
	var fade := 1.0 - clampf((elapsed - DELAY) / 0.3, 0, 1)
	var flash: float = game.settings.values.flash
	draw_colored_polygon(boundary, Color(tint, fade * (0.025 + (0.04 * flash if fired else 0.0))))
	var outline := boundary.duplicate()
	outline.append(boundary[0])
	draw_polyline(outline, Color(tint, 0.48 * fade), 2, true)
	draw_texture_rect_region(DIAGRAM, Rect2(-25, -25, 50, 50), Rect2(248, 8, 128, 128), Color(1, 1, 1, fade))
	# Seat ticks and the static border remain readable with flashes disabled.
	for i in range(seat + 1):
		var x := float(i * 8 - seat * 4)
		draw_line(Vector2(x, 28), Vector2(x, 34), Color(owner_tint, fade), 3, true)
	if not fired:
		draw_arc(Vector2.ZERO, 39, -PI / 2, -PI / 2 + TAU * minf(1, elapsed / DELAY), 36, Color(owner_tint, fade), 2, true)
	else:
		var expansion := clampf((elapsed - DELAY) / 0.3, 0, 1)
		for i in range(0, boundary.size(), 8):
			var end: Vector2 = boundary[i] * expansion
			draw_line(end * 0.7, end, Color(tint, fade * (0.5 + flash * 0.3)), 2, true)
