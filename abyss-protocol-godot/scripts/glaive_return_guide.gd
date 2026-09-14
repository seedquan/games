extends Node2D
## A read-only floor cue for the blade's current homing direction, below actors.

var projectile: WeakRef
var start := Vector2.ZERO
var end := Vector2.ZERO
var blocked := false
var identity := Color("8bb5bf")
var contrast := false
var seat := 0
var dashes := PackedVector2Array()
var arrows := PackedVector2Array()

func _ready() -> void:
	process_physics_priority = 10
	refresh()

func _physics_process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	var shot = projectile.get_ref() if projectile != null else null
	if not is_instance_valid(shot):
		queue_free()
		return
	if shot.game.state == "paused": return
	visible = false
	if shot.game.state != "playing" or shot.is_queued_for_deletion() or shot.spent or not shot.returning:
		return
	if not is_instance_valid(shot.shooter) or shot.shooter.hp <= 0: return
	start = shot.global_position
	end = shot.shooter.global_position
	var contact: Dictionary = shot.blade_contact(end, true)
	blocked = not contact.is_empty()
	if blocked: end = contact.position
	seat = shot.shooter.seat
	identity = Color("8bb5bf") if seat == 0 else Color("e6b879")
	contrast = shot.game.settings.values.high_contrast
	var distance := start.distance_to(end)
	if distance < 48: return
	var direction := start.direction_to(end)
	var finish := distance if blocked else distance - 30
	dashes.clear()
	arrows.clear()
	for step in range(12, int(finish), 24):
		dashes.append(to_local(start + direction * step))
		dashes.append(to_local(start + direction * minf(step + 10, finish)))
	for mark in range(1 + seat):
		var point := start + direction * (finish * 0.7 - mark * 12)
		for side in [-1.0, 1.0]:
			arrows.append(to_local(point - direction * 7 + direction.orthogonal() * side * 5))
			arrows.append(to_local(point))
	visible = true
	queue_redraw()

func _draw() -> void:
	var color := Color(identity, 0.95 if contrast else 0.7)
	var ink := Color("10191c")
	var width := 2.0 if contrast else 1.5
	draw_multiline(dashes, Color(ink, 0.9), width + 2.5, true)
	draw_multiline(dashes, color, width, true)
	draw_multiline(arrows, ink, 4.5, true)
	draw_multiline(arrows, Color(identity, 1.0), 2.0, true)
	draw_circle(to_local(start), 4, color, false, 1.5, true)
	if blocked:
		var side := start.direction_to(end).orthogonal() * 7
		draw_line(to_local(end - side), to_local(end + side), ink, 5, true)
		draw_line(to_local(end - side), to_local(end + side), color, 2.5, true)
