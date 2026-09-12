extends SceneTree
## Copy the engine's own complete attribution data into the desktop package.

func _initialize() -> void:
	var path := "res://builds/ThirdPartyNotices.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write desktop third-party notices")
		quit(1)
		return
	file.store_string("Godot Engine\n============\n" + Engine.get_license_text() + "\n\n")
	for component in Engine.get_copyright_info():
		file.store_string(str(component.name) + "\n")
		for part in component.parts:
			file.store_string("Files: " + ", ".join(part.files) + "\n")
			file.store_string("Copyright: " + "; ".join(part.copyright) + "\n")
			file.store_string("License: " + str(part.license) + "\n\n")
	var licenses := Engine.get_license_info()
	var names: Array = licenses.keys()
	names.sort()
	for name in names:
		file.store_string(str(name) + "\n============\n" + str(licenses[name]) + "\n\n")
	file.store_string("Noto Sans CJK / Noto Serif CJK\n============\n")
	file.store_string(FileAccess.get_file_as_string("res://assets/fonts/OFL.txt"))
	file.close()
	print("ABYSS NOTICES: complete")
	quit()
