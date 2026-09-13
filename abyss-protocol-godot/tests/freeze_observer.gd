extends RefCounted
## Read-only, frame-sampled diagnostics. Short-lived states between frames may
## be missed, so these are observations rather than exact element-hit counts.
## A positive shock guard may follow a successful hit in the previous frame;
## it is not proof that an attempted reaction was rejected.
var previous: Dictionary = {}
var summary := {"freeze_starts": 0, "starts_with_neighbour": 0, "starts_shock_guarded": 0,
	"frozen_enemy_frames": 0, "frames_with_neighbour": 0, "frames_shock_ready_with_neighbour": 0}

func observe(game) -> void:
	var current := {}
	var enemies: Array = game.get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy.dead or enemy.ice_frozen_left <= 0: continue
		var id: int = enemy.get_instance_id()
		current[id] = true
		var neighbour := enemies.any(func(other): return other != enemy and not other.dead and enemy.position.distance_to(other.position) <= game.PROGRESSION.CONDUCTION_RANGE and game.has_sight(enemy.position, other.position))
		summary.frozen_enemy_frames += 1
		if neighbour:
			summary.frames_with_neighbour += 1
			if enemy.shock_guard <= 0: summary.frames_shock_ready_with_neighbour += 1
		if not previous.has(id):
			summary.freeze_starts += 1
			if neighbour: summary.starts_with_neighbour += 1
			if enemy.shock_guard > 0: summary.starts_shock_guarded += 1
	previous = current
