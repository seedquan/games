extends RefCounted
## Preferences are isolated from progression and validated before applying to the OS.

const DEFAULTS := {
	"volume": 0.8, "effects_volume": 0.8, "ambience_volume": 0.5,
	"fullscreen": false, "shake": 0.65, "flash": 0.4, "aim_assist": true, "tutorial": true, "high_contrast": false,
}
const KEYS := {
	"move_up": KEY_W, "move_down": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
	"slash": KEY_J, "bolt": KEY_E, "dash": KEY_SPACE, "freeze": KEY_Q, "parry": KEY_L,
}
const LABELS := {
	"move_up": "向上移动", "move_down": "向下移动", "move_left": "向左移动", "move_right": "向右移动",
	"slash": "主武器", "bolt": "等离子弹", "dash": "冲刺", "freeze": "冰冻新星", "parry": "弹反",
}
const RESERVED := [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_TAB, KEY_M, KEY_P, KEY_F11,
	KEY_1, KEY_2, KEY_3, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
var values: Dictionary = DEFAULTS.duplicate()
var keys: Dictionary = KEYS.duplicate()
var save_path := "user://settings.cfg"
var writable := true
var preserve_backup := false
var message := ""

func valid_key(key: int) -> bool:
	return (key >= KEY_A and key <= KEY_Z or key == KEY_SPACE or key == KEY_SHIFT or key == KEY_CTRL) and key not in RESERVED

func load_settings(path := "user://settings.cfg") -> void:
	save_path = path
	var config := ConfigFile.new()
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		return
	var loaded := config.load(path) == OK and config.has_section_key("settings", "version") if FileAccess.file_exists(path) else false
	if not loaded:
		config = ConfigFile.new()
		loaded = FileAccess.file_exists(path + ".bak") and config.load(path + ".bak") == OK and config.has_section_key("settings", "version")
		preserve_backup = loaded
		message = "已从备份恢复设置。" if loaded else "设置文件无法读取，使用默认设置；原文件已保留。"
		if not loaded:
			writable = false
			return
	if config.get_value("settings", "version") != 1:
		writable = false
		message = "设置来自其他版本，使用默认设置；原文件已保留。"
		return
	for id in DEFAULTS:
		var value: Variant = config.get_value("settings", id, DEFAULTS[id])
		if DEFAULTS[id] is bool:
			values[id] = value if value is bool else DEFAULTS[id]
		elif typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value)):
			values[id] = clampf(float(value), 0.0, 1.0)
	# Validate the complete map together: partial duplicate maps can trap movement.
	var proposed: Dictionary = {}
	var seen: Array[int] = []
	for action in KEYS:
		var key: Variant = config.get_value("keys", action, KEYS[action])
		if key is not int or not valid_key(key) or key in seen:
			message = "部分按键设置无效，已恢复默认按键。"
			return
		proposed[action] = key
		seen.append(key)
	keys = proposed

func rebind(action: String, key: int) -> String:
	if not keys.has(action) or not valid_key(key):
		return "请选择字母、空格、Shift 或 Ctrl；菜单快捷键会保留。"
	for other in keys:
		if other != action and keys[other] == key:
			return "此键已用于“%s”，请先修改该操作。" % LABELS[other]
	keys[action] = key
	return ""

func key_label(action: String) -> String:
	var key: int = keys.get(action, KEY_NONE)
	return "空格" if key == KEY_SPACE else OS.get_keycode_string(key)

func save() -> Error:
	if not writable:
		return ERR_UNAUTHORIZED
	var config := ConfigFile.new()
	config.set_value("settings", "version", 1)
	for id in values:
		config.set_value("settings", id, values[id])
	for action in keys:
		config.set_value("keys", action, keys[action])
	var result := config.save(save_path + ".tmp")
	if result != OK:
		return result
	var target := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path) and not preserve_backup:
		result = DirAccess.copy_absolute(target, target + ".bak")
		if result != OK:
			return result
	result = DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path + ".tmp"), target)
	if result == OK:
		preserve_backup = false
	return result
