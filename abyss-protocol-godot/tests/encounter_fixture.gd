extends RefCounted
## State-machine tests resolve damage directly, but consume real staged waves.
## Normal gameplay bots do not use this fixture or alter player/enemy stats.
static func clear(game) -> void:
	var tree: SceneTree = game.get_tree()
	var previous_speed := Engine.time_scale
	Engine.time_scale = 4.0
	var deadline := Time.get_ticks_msec() + 12000
	while game.state == "playing" and Time.get_ticks_msec() < deadline:
		for enemy in tree.get_nodes_in_group("enemies"):
			enemy.take_damage(1000000.0, Vector2.ZERO)
		await tree.physics_frame
		await tree.process_frame
	Engine.time_scale = previous_speed
	if game.state == "playing":
		push_error("Encounter fixture timed out while consuming real reinforcement warnings")
