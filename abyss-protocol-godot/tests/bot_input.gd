extends RefCounted
## Preserve one press/release edge until Godot's player physics consumes it.

var held: Dictionary = {}

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
