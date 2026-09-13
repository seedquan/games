extends RefCounted
## One room owns its queued reinforcements. No timers can survive a transition.
const WARNING_TIME := 1.25
const SAFE_DISTANCE := 155.0
const MARKER = preload("res://scripts/reinforcement_marker.gd")
var game
var waves: Array = []
var wave := 0
var pending: Array = []
var spawn_cursor := 0
var total := 0
var scrap_budget := 0

func cancel() -> void:
	for entry in pending:
		if is_instance_valid(entry.marker): entry.marker.queue_free()
	pending.clear()
	waves.clear()
	wave = 0
	spawn_cursor = 0
	total = 0
	scrap_budget = 0

func start(data: Dictionary) -> void:
	cancel()
	var original_count := mini((3 if data.depth == 1 else mini(3 + data.depth * 2, 12)) + (2 if data.kind == "elite" else 0), data.spawns.size())
	var legacy: bool = data.get("generator", 1) == 1
	var count: int = original_count if legacy else (63 if data.depth == 1 else 72 + game.ROOMS.CHAPTERS.number(data.depth) * 4 + (10 if data.kind == "elite" else 0))
	if not legacy and game.coop.enabled: count = ceili(count * 1.05)
	total = count
	scrap_budget = original_count * 6
	var group_size := original_count if legacy else mini(6, data.spawns.size())
	if data.depth == 1 and not legacy:
		waves.append(3)
		count -= 3
	while count > 0:
		waves.append(mini(count, group_size))
		count -= group_size
	wave = 1
	for i in range(waves[0]):
		spawn(enemy_kind(i), data.spawns[i])

func spawn(kind: String, point: Vector2) -> void:
	var enemy = game.spawn_enemy(kind, point)
	# More combat must not multiply shop buying power. Distribute the previous
	# room's fixed kill budget exactly, with no fractional currency or lost remainder.
	enemy.scrap_reward = (spawn_cursor + 1) * scrap_budget / total - spawn_cursor * scrap_budget / total
	spawn_cursor += 1

func enemy_kind(index: int) -> String:
	var cadence: int = game.room_data.get("region", {}).get("ranged_every", 3)
	if game.room_data.get("generator", 1) >= 2:
		if game.room == 1: return "drone" if wave >= 3 and index % 5 == 0 else "stalker"
		if wave % 3 == 0: cadence = 2
		elif wave % 3 == 1: cadence = 4
	return "drone" if game.room > 1 and index % cadence == 0 else "stalker"

func clearance(point: Vector2) -> float:
	var distance := INF
	for member in game.team():
		distance = minf(distance, point.distance_to(member.position))
	return distance

func safest_point(excluded: Array) -> Vector2:
	var best: Vector2 = game.room_data.spawns[0]
	var score := -INF
	for candidate in game.room_data.spawns:
		if excluded.has(candidate): continue
		var distance := clearance(candidate)
		var candidate_score: float = distance
		if game.room_data.get("generator", 1) >= 2:
			# Keep reinforcements in fighting range and spread them around cover,
			# instead of repeatedly piling into the farthest corner of a large map.
			var separation := 650.0
			for other in excluded: separation = minf(separation, candidate.distance_to(other))
			candidate_score = -absf(distance - 650.0) + separation
			if distance < SAFE_DISTANCE: candidate_score -= 10000.0
		if candidate_score > score:
			score = candidate_score
			best = candidate
	return best

func queue_wave() -> void:
	if game.room_data.get("generator", 1) >= 2:
		for member in game.team():
			if member.hp > 0: member.hp = minf(member.max_hp, member.hp + 2.0)
	wave += 1
	var occupied: Array = []
	for i in range(waves[wave - 1]):
		var point := safest_point(occupied)
		occupied.append(point)
		var marker = MARKER.new()
		marker.position = point
		game.get_node("World/Effects").add_child(marker)
		pending.append({"point": point, "kind": enemy_kind(spawn_cursor + i), "delay": WARNING_TIME, "marker": marker})

func tick(delta: float) -> void:
	if game.state != "playing": return
	if pending.is_empty() and wave < waves.size() and game.get_tree().get_nodes_in_group("enemies").is_empty():
		queue_wave()
	for entry in pending.duplicate():
		entry.delay -= delta
		entry.marker.progress = 1.0 - maxf(0, entry.delay) / WARNING_TIME
		entry.marker.queue_redraw()
		if entry.delay > 0: continue
		if clearance(entry.point) < SAFE_DISTANCE:
			var occupied: Array = pending.map(func(other): return other.point)
			entry.point = safest_point(occupied)
			entry.marker.position = entry.point
			entry.delay = WARNING_TIME
			entry.marker.progress = 0.0
			continue
		spawn(entry.kind, entry.point)
		entry.marker.queue_free()
		pending.erase(entry)

func finished() -> bool:
	return pending.is_empty() and wave >= waves.size()
