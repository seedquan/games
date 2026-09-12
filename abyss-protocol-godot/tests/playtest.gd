extends SceneTree
## Manual native acceptance harness. Normal gameplay, with player saves disabled.

func _initialize() -> void:
	start.call_deferred()

func start() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	game.fit_window_to_screen()
	print("Manual acceptance session: player saves disabled; normal combat rules.")
