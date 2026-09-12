extends RefCounted
## One binding table drives gameplay, remapping and contextual prompts.

const BUTTONS := {
	"slash": JOY_BUTTON_RIGHT_SHOULDER, "bolt": JOY_BUTTON_LEFT_SHOULDER,
	"dash": JOY_BUTTON_A, "freeze": JOY_BUTTON_X, "parry": JOY_BUTTON_B,
	"pause_run": JOY_BUTTON_START,
}
const PAD_LABELS := {"slash": "右肩键", "bolt": "左肩键", "dash": "下键", "freeze": "左键", "parry": "右键"}

static func configure(settings) -> void:
	var keys: Dictionary = settings.keys.duplicate()
	keys.merge({"pause_run": KEY_ESCAPE, "mute": KEY_M, "fullscreen": KEY_F11,
		"begin_run": KEY_ENTER, "armory": KEY_TAB, "boon_one": KEY_1, "boon_two": KEY_2, "boon_three": KEY_3})
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.22)
		InputMap.action_erase_events(action)
		add_key(action, keys[action])
	for pair in [["move_up", KEY_UP], ["move_down", KEY_DOWN], ["move_left", KEY_LEFT], ["move_right", KEY_RIGHT], ["pause_run", KEY_P]]:
		add_key(pair[0], pair[1])
	for pair in [["slash", MOUSE_BUTTON_LEFT], ["bolt", MOUSE_BUTTON_RIGHT]]:
		var event := InputEventMouseButton.new()
		event.button_index = pair[1]
		InputMap.action_add_event(pair[0], event)
	for action in BUTTONS:
		var event := InputEventJoypadButton.new()
		# -1 matches every OS-assigned controller ID, including after reconnect.
		event.device = -1
		event.button_index = BUTTONS[action]
		InputMap.action_add_event(action, event)
	# Godot's built-in UI actions may only contain keyboard events.
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B],
			["ui_up", JOY_BUTTON_DPAD_UP], ["ui_down", JOY_BUTTON_DPAD_DOWN],
			["ui_left", JOY_BUTTON_DPAD_LEFT], ["ui_right", JOY_BUTTON_DPAD_RIGHT]]:
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = pair[1]
		if not InputMap.action_has_event(pair[0], event):
			InputMap.action_add_event(pair[0], event)
	for pair in [["move_left", JOY_AXIS_LEFT_X, -1.0], ["move_right", JOY_AXIS_LEFT_X, 1.0],
			["move_up", JOY_AXIS_LEFT_Y, -1.0], ["move_down", JOY_AXIS_LEFT_Y, 1.0],
			["aim_left", JOY_AXIS_RIGHT_X, -1.0], ["aim_right", JOY_AXIS_RIGHT_X, 1.0],
			["aim_up", JOY_AXIS_RIGHT_Y, -1.0], ["aim_down", JOY_AXIS_RIGHT_Y, 1.0]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0], 0.22)
		# Aim actions aren't part of the keyboard table and need explicit clearing.
		if str(pair[0]).begins_with("aim_"):
			InputMap.action_erase_events(pair[0])
		var event := InputEventJoypadMotion.new()
		event.device = -1
		event.axis = pair[1]
		event.axis_value = pair[2]
		InputMap.action_add_event(pair[0], event)

static func add_key(action: String, key: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)

static func configure_seats(devices: Array[int]) -> void:
	for seat in range(2):
		var prefix := "p%d_" % (seat + 1)
		for action in ["move_left", "move_right", "move_up", "move_down", "aim_left", "aim_right", "aim_up", "aim_down", "slash", "bolt", "dash", "freeze", "parry"]:
			var name: String = prefix + action
			if not InputMap.has_action(name):
				InputMap.add_action(name, 0.22)
			Input.action_release(name)
			InputMap.action_erase_events(name)
			if devices[seat] < 0:
				continue
			for original in InputMap.action_get_events(action):
				if original is InputEventJoypadButton or original is InputEventJoypadMotion:
					var event = original.duplicate()
					event.device = devices[seat]
					InputMap.action_add_event(name, event)
