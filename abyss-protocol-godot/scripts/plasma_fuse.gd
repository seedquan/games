extends Node2D
## Plasma primes; a later weapon hit consumes one charge. Never chains itself.
const ID := "plasma_fuse"
const WINDOW := 3.0
const RADIUS := 160.0
const DAMAGE_FRACTION := 0.6
const DIAGRAM = preload("res://assets/ui/plasma_fuse.svg")
const CARD := {"stat": ID, "name": "共振引信", "tag": "技能 · 等离子", "description": "等离子标记敌人，再用自己或队友的主武器命中引爆。"}
var game
var damage := 0.0
var seat := 0
var remaining := WINDOW
var burst := false
var boundary := PackedVector2Array()

static func description(base_damage: float) -> String:
	return "等离子命中留下三秒引信。\n自己或队友主武器、返弹命中后引爆，范围 160，伤害 %.1f。\n不叠层；再中等离子刷新时限、保留较强引信。掩体阻挡。" % (base_damage * DAMAGE_FRACTION)

static func prime(enemy, amount: float, owner_seat: int) -> void:
	if enemy.dead or enemy.game.campaign_version < 2: return
	var fuse = enemy.get_node_or_null("PlasmaFuse")
	if not is_instance_valid(fuse):
		fuse = new()
		fuse.name = "PlasmaFuse"
		fuse.game = enemy.game
		enemy.add_child(fuse)
	if amount >= fuse.damage:
		fuse.damage = amount
		fuse.seat = owner_seat
	fuse.remaining = WINDOW
	fuse.queue_redraw()

static func trigger(enemy) -> void:
	if enemy.game.campaign_version < 2 or enemy.game.state != "playing": return
	var fuse = enemy.get_node_or_null("PlasmaFuse")
	if not is_instance_valid(fuse) or fuse.remaining <= 0: return
	# Consume before any damage or callbacks so a multi-hit attack fires once.
	var amount: float = fuse.damage
	var world = enemy.game
	var center: Vector2 = enemy.global_position
	enemy.remove_child(fuse)
	fuse.queue_free()
	for target in world.get_tree().get_nodes_in_group("enemies"):
		if target.dead or center.distance_to(target.global_position) >= RADIUS: continue
		if world.has_sight(center, target.global_position):
			target.take_damage(amount, Vector2.ZERO)
	var effect = new()
	effect.game = world
	effect.position = center
	effect.burst = true
	effect.remaining = 0.35
	for i in range(64):
		var direction := Vector2.from_angle(float(i) / 64 * TAU)
		effect.boundary.append(world.clip_to_wall(center, center + direction * RADIUS) - center)
	world.get_node("World/Effects").add_child(effect)
	world.play_tone(420.0, 0.12, 0.04)

func _physics_process(delta: float) -> void:
	if game.state != "playing": return
	remaining = maxf(0, remaining - delta)
	if remaining <= 0:
		get_parent().remove_child(self)
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var cyan := Color("a3e3df")
	if burst:
		if boundary.size() < 3: return
		var fade := remaining / 0.35
		var outline := boundary.duplicate()
		outline.append(boundary[0])
		draw_polyline(outline, Color(cyan, 0.6 * fade), 2, true)
		for i in range(0, boundary.size(), 8):
			var end: Vector2 = boundary[i] * (1 - fade * 0.8)
			draw_line(end * 0.75, end, Color(cyan, fade * (0.4 + 0.4 * game.settings.values.flash)), 3, true)
		return
	var enemy = get_parent()
	var scale := 1.0 / maxf(0.55, game.camera.zoom.x)
	var rows := int(enemy.poison_marker_level() > 0) + int(enemy.ice_marker_level() > 0)
	var top := -140.0 if enemy.kind in ["boss", "warden"] else -72.0
	var center := Vector2(0, top - (24 + 28 * rows) * scale)
	draw_circle(center, 17 * scale, Color("101e24"))
	draw_texture_rect_region(DIAGRAM, Rect2(center - Vector2(14, 14) * scale, Vector2(28, 28) * scale), Rect2(176, 32, 64, 64))
	draw_arc(center, 17 * scale, -PI / 2, -PI / 2 + TAU * remaining / WINDOW, 40, cyan, 2 * scale, true)
	for i in range(seat + 1):
		var x := float(i * 7 - seat * 3.5)
		draw_line(center + Vector2(x, 19) * scale, center + Vector2(x, 23) * scale, Color("e6b879") if seat == 1 else cyan, 2 * scale, true)
