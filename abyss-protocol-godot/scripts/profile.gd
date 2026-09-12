extends RefCounted
## Local, versioned meta progress. A staged write and backup preserve prior saves.

const WEAPONS = preload("res://scripts/weapons.gd")
const PROGRESSION = preload("res://scripts/progression.gd")
const RUN_SAVE = preload("res://scripts/run_save.gd")
const VERSION := 2
var cores := 0
var runs := 0
var wins := 0
var best_depth := 0
var weapon := "blade"
var upgrades := {"vitality": 0, "power": 0, "recovery": 0}
var save_path := "user://profile.cfg"
var writable := true
var message := ""
var preserve_backup := false
var checkpoint: Dictionary = {}

func number(value: Variant, maximum: int) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return 0
	return int(clampf(float(value), 0.0, float(maximum)))

func load_progress(path := "user://profile.cfg") -> void:
	save_path = path
	var config := ConfigFile.new()
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		return
	var loaded := config.load(path) == OK and config.has_section_key("profile", "version") if FileAccess.file_exists(path) else false
	if not loaded:
		config = ConfigFile.new()
		loaded = FileAccess.file_exists(path + ".bak") and config.load(path + ".bak") == OK and config.has_section_key("profile", "version")
		message = "已从备份恢复上次进度。" if loaded else "无法读取存档；当前进度暂时只保留在本次游戏中。"
		preserve_backup = loaded
		if not loaded:
			writable = false
			return
	if config.get_value("profile", "version") not in [1, VERSION]:
		writable = false
		message = "存档版本不兼容，原文件已保留，当前进度不会覆盖它。"
		return
	cores = number(config.get_value("profile", "cores", 0), 1000000)
	runs = number(config.get_value("profile", "runs", 0), 1000000)
	wins = mini(runs, number(config.get_value("profile", "wins", 0), 1000000))
	best_depth = number(config.get_value("profile", "best_depth", 0), 30)
	var selected: Variant = config.get_value("profile", "weapon", "blade")
	weapon = selected if selected is String and WEAPONS.exists(selected) else "blade"
	for id in upgrades:
		upgrades[id] = number(config.get_value("upgrades", id, 0), 5)
	var saved: Variant = config.get_value("run", "checkpoint", {})
	if saved is Dictionary and saved.is_empty():
		return
	if RUN_SAVE.valid(saved):
		checkpoint = saved
	else:
		writable = false
		message = "救援记录无法恢复，原文件已保留；当前游戏不会覆盖它。"

func save_progress() -> Error:
	if not writable:
		return ERR_UNAUTHORIZED
	var config := ConfigFile.new()
	for field in ["cores", "runs", "wins", "best_depth", "weapon"]:
		config.set_value("profile", field, get(field))
	config.set_value("profile", "version", VERSION)
	config.set_value("run", "checkpoint", checkpoint)
	for id in upgrades:
		config.set_value("upgrades", id, upgrades[id])
	var staged := save_path + ".tmp"
	var result := config.save(staged)
	if result != OK:
		return result
	var destination := ProjectSettings.globalize_path(save_path)
	var backup := destination + ".bak"
	if FileAccess.file_exists(save_path) and not preserve_backup:
		# Copy the known prior bytes; never destroy the destination before staging.
		result = DirAccess.copy_absolute(destination, backup)
		if result != OK:
			return result
	result = DirAccess.rename_absolute(ProjectSettings.globalize_path(staged), destination)
	if result == OK:
		preserve_backup = false
	return result

func upgrade_cost(id: String) -> int:
	for item in PROGRESSION.UPGRADES:
		if item.id == id:
			return int(item.base_cost) * (int(upgrades[id]) + 1)
	return -1

func purchase(id: String) -> bool:
	var cost := upgrade_cost(id)
	if cost < 0 or int(upgrades.get(id, 5)) >= 5 or cores < cost:
		return false
	cores -= cost
	upgrades[id] += 1
	return true
