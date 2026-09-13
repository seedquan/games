extends SceneTree
const ENCOUNTER_FIXTURE = preload("res://tests/encounter_fixture.gd")
## Exercises the real scenes and physics; no test framework dependencies.

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
	await process_frame

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	game.narrative_enabled = false
	root.add_child(game)
	await process_frame
	game.muted = true
	check(game.state == "title", "Boot presents the title menu")
	game.start_run()
	await frames(2)
	check(game.room == 1 and get_nodes_in_group("enemies").size() == 3, "First room starts with three hostiles for onboarding")
	var player = game.player
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	var initial: Vector2 = player.position
	Input.action_press("move_right")
	await frames(15)
	Input.action_release("move_right")
	check(player.position.x > initial.x + 30.0, "Movement input advances the CharacterBody2D")
	player.position = Vector2(1540, 500)
	Input.action_press("move_right")
	await frames(20)
	Input.action_release("move_right")
	check(player.position.x <= 1544.0, "Station walls physically stop the player")
	player.position = Vector2(800, 650)
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	player.invulnerable = 0.0
	check(player.try_dash(Vector2.RIGHT), "Dash activates when ready")
	check(not player.try_dash(Vector2.RIGHT), "Dash cannot ignore its cooldown")
	var old_hp: float = player.hp
	check(not player.take_damage(15, Vector2(780, 650)) and player.hp == old_hp, "Dash absorbs damage")
	check(player.empowered > 0 and player.dash_cooldown == 0.0, "Perfect dodge grants overdrive and resets dash")
	player.dash_left = 0.0
	player.invulnerable = 0.0
	check(player.try_parry(), "Parry activates")
	check(not player.take_damage(15, Vector2(780, 650)) and player.hp == old_hp, "Parry blocks a timed attack")
	player.invulnerable = 0.0
	check(player.take_damage(15, Vector2(780, 650)) and player.hp == old_hp - 15, "Ordinary damage reduces integrity")
	var enemy = get_nodes_in_group("enemies")[0]
	enemy.position = player.position + Vector2(65, 0)
	player.aim = Vector2.RIGHT
	var enemy_hp: float = enemy.hp
	player.try_slash()
	check(enemy.hp < enemy_hp, "Melee arc damages a hostile in front")
	var behind = get_nodes_in_group("enemies")[1]
	behind.position = player.position + Vector2(-65, 0)
	var behind_hp: float = behind.hp
	player.slash_cooldown = 0.0
	player.try_slash()
	check(behind.hp == behind_hp, "Melee arc excludes a hostile behind the android")
	check(player.try_freeze() and behind.frozen > 0.0, "Nova freezes nearby hostiles")
	check(not player.try_freeze(), "Nova respects its cooldown")
	player.energy = 10.0
	check(not player.try_bolt(), "Plasma cannot fire without enough energy")
	player.energy = 100.0
	check(player.try_bolt() and player.energy == 76.0, "Plasma consumes energy")
	# A real Area2D overlap must deliver one hit, not one hit per frame.
	var target = game.spawn_enemy("stalker", Vector2(1000, 650))
	target.set_physics_process(false)
	var target_hp: float = target.hp
	game.spawn_bolt(Vector2(940, 650), Vector2.RIGHT, false, 10.0)
	await frames(15)
	check(target.hp < target_hp, "Moving plasma collides with and damages a hostile")
	# Verify projectile masks and cover with an isolated target.
	for bolt in game.get_node("World/Projectiles").get_children():
		bolt.queue_free()
	await frames(2)
	target.position = Vector2(420, 430)
	target_hp = target.hp
	game.spawn_bolt(Vector2(420, 265), Vector2.DOWN, false, 10.0)
	await frames(20)
	check(target.hp == target_hp, "Cover blocks plasma before it reaches a target")
	player.invulnerable = 0.0
	player.parry_left = 0.0
	old_hp = player.hp
	game.spawn_bolt(player.position - Vector2(60, 0), Vector2.RIGHT, true, 8.0)
	await frames(20)
	check(player.hp == old_hp - 8.0, "Hostile plasma hits the player exactly once")
	game.show_menu("paused")
	var paused_time: float = game.elapsed
	await frames(4)
	check(game.elapsed == paused_time and not player.can_process(), "Pause stops world simulation and run timer")
	game.resume_run()
	check(game.state == "playing", "Resume restores the run")
	await ENCOUNTER_FIXTURE.clear(game)
	await frames(3)
	check(game.state == "reward", "Room clear opens upgrade selection")
	var old_damage: float = player.damage
	game.choose_boon(0)
	check(game.state == "route" and game.room == 1 and player.damage == old_damage * 1.25, "Upgrade applies before choosing the next route")
	game.choose_boon(0)
	check(game.room == 1, "Repeated reward input cannot skip a room")
	game.choose_route(0)
	check(game.room == 2, "Route choice advances exactly one room")
	while game.room < game.LAST_ROOM:
		if game.state == "playing":
			await ENCOUNTER_FIXTURE.clear(game)
			await frames(2)
			check(game.state == "reward", "Combat room %d reaches reward" % game.room)
			game.choose_boon(0)
		elif game.state in ["shop", "rest"]:
			game.leave_supply()
		if game.state != "route":
			check(false, "Unexpected campaign state: " + game.state)
			quit(1)
			return
		game.choose_route(0)
	check(game.room == game.LAST_ROOM and get_nodes_in_group("enemies").size() == 1, "Final room contains a single boss")
	var boss = get_nodes_in_group("enemies")[0]
	check(boss.kind == "boss" and boss.hp > 700.0, "Boss has its own archetype and scaled health")
	boss.release_attack()
	check(game.get_node("World/Projectiles").get_child_count() >= 12, "Boss emits its radial bullet pattern")
	boss.take_damage(boss.hp, Vector2.ZERO)
	await frames(3)
	check(game.state == "victory", "Boss defeat completes the run")
	game.start_run()
	check(game.room == 1 and game.kills == 0 and game.player.hp == 100.0, "Restart clears previous run progression")
	game.player.invulnerable = 0.0
	game.player.set_physics_process(false)
	game.spawn_bolt(game.player.position - Vector2(60, 0), Vector2.RIGHT, true, 1000.0)
	await frames(20)
	check(game.state == "dead", "Lethal projectile damage safely opens the game-over menu")
	game.start_run()
	check(get_nodes_in_group("player").size() == 1 and get_nodes_in_group("enemies").size() == 3, "Restart leaves no stale players or hostiles")
	game.queue_free()
	await process_frame
	print("ABYSS SMOKE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
