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

func cancel() -> void:
	for entry in pending:
		if is_instance_valid(entry.marker): entry.marker.queue_free()
	pending.clear()
	waves.clear()
	wave = 0
	spawn_cursor = 0

func start(data: Dictionary) -> void:
	cancel()
	var count := (3 if data.depth == 1 else mini(3 + data.depth * 2, 12)) + (2 if data.kind == "elite" else 0)
	count = mini(count, data.spawns.size())
	var group_size := count if data.get("generator", 1) == 1 or data.depth == 1 else 5
	while count > 0:
		waves.append(mini(count, group_size))
		count -= group_size
	wave = 1
	for i in range(waves[0]):
		game.spawn_enemy(enemy_kind(i), data.spawns[i])
	spawn_cursor = waves[0]

func enemy_kind(index: int) -> String:
	var cadence: int = game.room_data.get("region", {}).get("ranged_every", 3)
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
		if distance > score:
			score = distance
			best = candidate
	return best

func queue_wave() -> void:
	var occupied: Array = []
	for i in range(waves[wave]):
		var point := safest_point(occupied)
		occupied.append(point)
		var marker = MARKER.new()
		marker.position = point
		game.get_node("World/Effects").add_child(marker)
		pending.append({"point": point, "kind": enemy_kind(spawn_cursor), "delay": WARNING_TIME, "marker": marker})
		spawn_cursor += 1
	wave += 1
	game.announce("封锁增援 %d / %d · 远离琥珀色投送标记" % [wave, waves.size()], Color("e5b378"))

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
		game.spawn_enemy(entry.kind, entry.point)
		entry.marker.queue_free()
		pending.erase(entry)

func finished() -> bool:
	return pending.is_empty() and wave >= waves.size()
