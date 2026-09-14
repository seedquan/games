extends RefCounted
## Preserve one press/release edge until Godot's player physics consumes it.

var held: Dictionary = {}

func blast_imminent(hazard: Node2D, point: Vector2) -> bool:
	# The visible closing ring provides the same imminent window as guardian
	# warnings. An early dash can expire before the delayed blast reaches us.
	return hazard.delay - hazard.elapsed < 0.23 and point.distance_to(hazard.position) < hazard.radius + 35

func button(action: String, down: bool) -> void:
	if down:
		if not Input.is_action_pressed(action): Input.action_press(action)
		held[action] = true
	else:
		if Input.is_action_pressed(action): Input.action_release(action)
		held.erase(action)

func release() -> void:
	for action in held: Input.action_release(action)
	held.clear()
