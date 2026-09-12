extends Node2D
## Small run state machine. Menus freeze World, never the UI or input router.

const PLAYER = preload("res://scenes/player.tscn")
const ENEMY = preload("res://scenes/enemy.tscn")
const PROJECTILE = preload("res://scenes/projectile.tscn")
const EFFECT = preload("res://scripts/effect.gd")
const FIELD = preload("res://scripts/combat_field.gd")
const HAZARD = preload("res://scripts/hazard.gd")
const WEAPONS = preload("res://scripts/weapons.gd")
const ROOMS = preload("res://scripts/rooms.gd")
const PROGRESSION = preload("res://scripts/progression.gd")
const PROFILE = preload("res://scripts/profile.gd")
const STORY = preload("res://scripts/story.gd")
const RUN_SAVE = preload("res://scripts/run_save.gd")
const SETTINGS = preload("res://scripts/settings.gd")
const CONTROLS = preload("res://scripts/controls.gd")
const SOUND = preload("res://scripts/sound.gd")
const LAST_ROOM := ROOMS.LAST_ROOM

var settings = SETTINGS.new()
var sound
var settings_return := "title"
var settings_tab := "comfort"
var settings_notice := ""
var rebind_action := ""
var using_gamepad := false
var last_gamepad_event := -1000
var auto_pause_enabled := true
var info_return := "title"
var confirm_return := "title"
var pending_action := ""
var player
var companion
var coop = preload("res://scripts/local_coop.gd").new()
var encounter = preload("res://scripts/encounter.gd").new()
var active_boss
var state := "title"
var room := 0
var campaign_version := 2
var run_length := LAST_ROOM
var kills := 0
var elapsed := 0.0
var shake := 0.0
var announcement_left := 0.0
var clear_pending := false
var muted := false
var selected_weapon := "blade"
var armory_return := "title"
var workbench_return := "title"
var profile = PROFILE.new()
var persistence_enabled := DisplayServer.get_name() != "headless"
var verification_directory := ""
var verification_stage := ""
var rng := RandomNumberGenerator.new()
var run_seed := 0
var scrap := 0
var earned_cores := 0
var room_data: Dictionary = {}
var route_choices: Array = []
var boon_choices: Array = []
var shop_stock: Array = []
var purchased: Array[String] = []
var route_history: Array[String] = []
var room_awarded := false
var result_recorded := false
var save_warning := ""
var narrative_enabled := true
var story_id := ""
var story_return := "playing"
var story_seen: Array[String] = []

@onready var world: Node2D = $World
@onready var actors: Node2D = $World/Actors
@onready var camera: Camera2D = $World/Camera
@onready var hud = $Interface/HUD
@onready var arena = $World/Arena

func _ready() -> void:
	coop.game = self
	encounter.game = self
	var release_verification := "--verify-release" in OS.get_cmdline_user_args()
	if release_verification:
		persistence_enabled = false
		auto_pause_enabled = false
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--verify-storage="):
				verification_directory = argument.trim_prefix("--verify-storage=").simplify_path()
			elif argument.begins_with("--verify-stage="):
				verification_stage = argument.trim_prefix("--verify-stage=")
		if not verification_directory.is_empty() or not verification_stage.is_empty():
			# An explicit disposable fixture is mandatory. Never fall back to user://.
			if not verification_directory.is_absolute_path() or verification_stage not in ["write", "read"] or not FileAccess.file_exists(verification_directory.path_join(".abyss-release-fixture")):
				push_error("Release storage verification requires a marked absolute fixture directory and write/read stage")
				get_tree().quit(1)
				return
			profile.save_path = verification_directory.path_join("profile.cfg")
			settings.save_path = verification_directory.path_join("settings.cfg")
			persistence_enabled = true
	if persistence_enabled:
		profile.load_progress(profile.save_path)
		selected_weapon = profile.weapon
		save_warning = profile.message
	if persistence_enabled:
		settings.load_settings(settings.save_path)
		settings_notice = settings.message
	sound = SOUND.new()
	add_child(sound)
	apply_settings()
	if persistence_enabled:
		fit_window_to_screen()
	configure_input()
	get_tree().auto_accept_quit = false
	Input.joy_connection_changed.connect(controller_changed)
	hud.game = self
	hud.build()
	show_menu("title")
	if release_verification:
		var verifier = preload("res://scripts/release_check.gd").new()
		verifier.game = self
		# Sibling lifetime lets the verifier destroy the complete game before exit.
		get_parent().add_child.call_deferred(verifier)

func configure_input() -> void:
	CONTROLS.configure(settings)
	CONTROLS.configure_seats(coop.devices)

func _input(event: InputEvent) -> void:
	if coop.route(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion and absf(event.axis_value) > 0.3:
		using_gamepad = true
		last_gamepad_event = Time.get_ticks_msec()
	elif event is InputEventKey or event is InputEventMouseButton:
		using_gamepad = false
	elif event is InputEventMouseMotion and event.relative.length() > 2.0 and Time.get_ticks_msec() - last_gamepad_event > 650:
		# Window resizing can emit pointer motion; don't let it steal active pad aim.
		using_gamepad = false
	if not rebind_action.is_empty():
		if event is InputEventJoypadButton:
			if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_run"):
				rebind_action = ""
				settings_notice = "已取消修改。"
				hud.show_menu("settings")
			get_viewport().set_input_as_handled()
		elif event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				rebind_action = ""
				settings_notice = "已取消修改。"
			else:
				settings_notice = settings.rebind(rebind_action, event.physical_keycode)
				if settings_notice.is_empty():
					rebind_action = ""
					configure_input()
					save_settings()
			get_viewport().set_input_as_handled()
			hud.show_menu("settings")
		return
	if event is InputEventKey and event.echo:
		return
	# Route global controls before focused buttons consume Escape or Start.
	if event.is_action_pressed("pause_run"):
		match state:
			"playing": show_menu("paused")
			"paused": resume_run()
			"armory": armory_back()
			"workbench": workbench_back()
			"settings": close_settings()
			"help": show_menu(info_return)
			"confirm": cancel_confirmation()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("mute"):
		muted = not muted
		apply_settings()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fullscreen"):
		set_setting("fullscreen", not settings.values.fullscreen)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("armory") and state in ["title", "dead", "victory"]:
		open_armory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and using_gamepad and state in ["settings", "help", "armory", "workbench", "confirm"]:
		match state:
			"settings": close_settings()
			"help": show_menu(info_return)
			"armory": armory_back()
			"workbench": workbench_back()
			"confirm": cancel_confirmation()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("begin_run") and state in ["title", "dead", "victory"]:
		request_new_run()
	elif state in ["reward", "route", "shop"]:
		for i in range(3):
			if event.is_action_pressed(["boon_one", "boon_two", "boon_three"][i]):
				match state:
					"reward": choose_boon(i)
					"route": choose_route(i)
					"shop": buy_item(i)

func controller_changed(_device: int, connected: bool) -> void:
	if not connected and (coop.enabled or state == "coop_lobby"):
		coop.disconnected(_device)
		return
	if not connected and using_gamepad and state == "playing":
		show_menu("paused")
		announce("手柄已断开，请重新连接或使用键鼠。", Color("ffd27a"))

func action_label(action: String) -> String:
	return CONTROLS.PAD_LABELS.get(action, "") if using_gamepad else settings.key_label(action)

func apply_settings() -> void:
	if is_instance_valid(hud):
		hud.apply_text_contrast()
	if is_instance_valid(sound):
		var master := 0.0 if muted else float(settings.values.volume)
		sound.update_gain(master * float(settings.values.effects_volume), master * float(settings.values.ambience_volume))
	if DisplayServer.get_name() != "headless":
		# FULLSCREEN is borderless on Windows; do not request EXCLUSIVE_FULLSCREEN.
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)

func set_setting(id: String, value: Variant) -> void:
	if not settings.values.has(id):
		return
	settings.values[id] = value
	apply_settings()
	save_settings()

func save_settings() -> void:
	settings_notice = "设置已保存。"
	if persistence_enabled and settings.save() != OK:
		settings_notice = "设置暂时无法保存，关闭游戏后本次更改不会保留。"
	if is_instance_valid(hud) and is_instance_valid(hud.settings_feedback):
		hud.settings_feedback.text = settings_notice

func open_settings() -> void:
	settings_return = state
	settings_tab = "comfort"
	show_menu("settings")

func close_settings() -> void:
	rebind_action = ""
	show_menu(settings_return)

func choose_settings_tab(tab: String) -> void:
	rebind_action = ""
	settings_tab = tab
	hud.show_menu("settings")

func begin_rebind(action: String) -> void:
	rebind_action = action
	settings_notice = "请在键盘上按下新键；按手柄右键或菜单键取消。" if using_gamepad else "请按下新的按键；按 Esc 取消。"
	hud.show_menu("settings")

func reset_controls() -> void:
	settings.keys = SETTINGS.KEYS.duplicate()
	configure_input()
	save_settings()
	hud.show_menu("settings")

func open_help() -> void:
	info_return = state
	show_menu("help")

func request_new_run() -> void:
	if is_instance_valid(player) and not result_recorded or not profile.checkpoint.is_empty():
		request_confirmation("restart")
	else:
		start_run()

func request_confirmation(action: String) -> void:
	pending_action = action
	if state != "confirm":
		confirm_return = state
	show_menu("confirm")

func cancel_confirmation() -> void:
	pending_action = ""
	show_menu(confirm_return)

func accept_confirmation() -> void:
	if state != "confirm":
		return
	var action := pending_action
	pending_action = ""
	match action:
		"restart": start_run()
		"abandon":
			profile.checkpoint.clear()
			persist_profile()
			clear_world()
			show_menu("title")
		"quit": get_tree().quit()

func request_quit() -> void:
	if is_instance_valid(player) and not result_recorded:
		request_confirmation("quit")
	else:
		get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_node_ready():
		request_quit()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and auto_pause_enabled and state == "playing" and is_node_ready():
		show_menu("paused")

func _process(delta: float) -> void:
	if state == "playing":
		if coop.enabled and not coop.ready_to_play():
			show_menu("paused")
			coop.open_lobby(true)
			return
		elapsed += delta
		encounter.tick(delta)
		if is_instance_valid(player):
			camera.position = player.position + player.aim * 45.0
			if is_instance_valid(active_boss):
				camera.position = player.position.lerp(active_boss.position, 0.5)
			# Zoomed boss framing needs room beyond the deck; fixed camera limits
			# would otherwise recenter a viewport larger than the arena.
			var boss_framing := is_instance_valid(active_boss)
			var deck: Rect2 = arena.bounds
			camera.limit_left = -int(deck.size.x) if boss_framing else 0
			camera.limit_right = int(deck.end.x * 2) if boss_framing else int(deck.end.x)
			camera.limit_top = -int(deck.size.y) if boss_framing else -120
			camera.limit_bottom = int(deck.end.y * 2) if boss_framing else int(deck.end.y + 190)
			var desired_zoom := 1.0
			if is_instance_valid(active_boss):
				var span: Vector2 = (player.position - active_boss.position).abs()
				var available := (get_viewport_rect().size - Vector2(260, 360)).max(Vector2(100, 100))
				desired_zoom = minf(1.0, minf(available.y / (span.y + 230.0), available.x / (span.x + 230.0)))
			camera.zoom = Vector2.ONE * minf(desired_zoom, lerpf(camera.zoom.x, desired_zoom, 1.0 - exp(-5.0 * delta)))
		if coop.enabled:
			coop.frame_camera(delta)
			coop.tick(delta)
		shake = maxf(0.0, shake - delta * 30.0)
		camera.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) * float(settings.values.shake)
		if clear_pending:
			clear_pending = false
			complete_room()
	announcement_left = maxf(0.0, announcement_left - delta)
	hud.update_status()

func start_run(seed_override := 0) -> void:
	if coop.enabled and not coop.ready_to_play():
		coop.open_lobby(false)
		return
	if coop.enabled:
		selected_weapon = coop.weapons[0]
		profile.weapon = selected_weapon
	clear_world()
	campaign_version = 2
	run_length = LAST_ROOM
	run_seed = seed_override if seed_override != 0 else int(randi())
	rng.seed = run_seed
	room = 0
	kills = 0
	elapsed = 0.0
	shake = 0.0
	scrap = 0
	earned_cores = 0
	result_recorded = false
	story_seen.clear()
	route_history.clear()
	profile.runs += 1
	profile.checkpoint.clear()
	player = PLAYER.instantiate()
	player.game = self
	player.position = ROOMS.START
	player.max_hp += float(profile.upgrades.vitality) * 10.0
	player.hp = player.max_hp
	player.damage *= 1.0 + float(profile.upgrades.power) * 0.05
	player.energy_regen += float(profile.upgrades.recovery) * 2.0
	actors.add_child(player)
	player.weapon.equip(coop.weapons[0] if coop.enabled else selected_weapon)
	if coop.enabled:
		create_companion()
	camera.position = player.position
	camera.zoom = Vector2.ONE
	camera.reset_smoothing()
	next_room(ROOMS.generate(1, "combat", rng))

func clear_world() -> void:
	clear_pending = false
	encounter.cancel()
	for container in [actors, $World/Projectiles, $World/Effects]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	player = null
	companion = null
	active_boss = null

func next_room(data: Dictionary) -> void:
	encounter.cancel()
	room = data.depth
	room_data = data
	room_awarded = false
	clear_pending = false
	purchased.clear()
	route_choices.clear()
	boon_choices.clear()
	shop_stock.clear()
	for container in [$World/Projectiles, $World/Effects]:
		for node in container.get_children():
			container.remove_child(node)
			node.queue_free()
	arena.apply_room(data)
	for member in team():
		member.position = data.start + Vector2(60 * member.seat, 0)
		member.velocity = Vector2.ZERO
		member.dash_left = 0.0
		member.invulnerable = 1.2
		member.weapon.cancel_charge()
	camera.position = player.position
	camera.zoom = Vector2.ONE
	camera.reset_smoothing()
	route_history.append(data.kind)
	profile.best_depth = maxi(profile.best_depth, room)
	if data.kind == "shop":
		prepare_shop()
		show_menu("shop")
		arrival_story()
		save_checkpoint()
		return
	if data.kind == "rest":
		for member in team():
			member.hp = minf(member.max_hp, member.hp + member.max_hp * 0.35)
			member.energy = 100.0
		show_menu("rest")
		arrival_story()
		save_checkpoint()
		return
	state = "playing"
	arm_player_input()
	world.process_mode = Node.PROCESS_MODE_INHERIT
	hud.hide_menu()
	populate_room()
	if is_instance_valid(active_boss):
		camera.position = player.position.lerp(active_boss.position, 0.5)
		camera.reset_smoothing()
	announce("%02d / %s" % [room, data.name], Color(ROOMS.TYPES[data.kind].color))
	arrival_story()
	save_checkpoint()

func populate_room() -> void:
	encounter.cancel()
	if room_data.kind == "boss":
		spawn_enemy("boss" if room == run_length else "warden", room_data.get("boss_start", Vector2(800, 310)))
	else:
		encounter.start(room_data)

func arrival_story() -> void:
	var beats := {1: "awakening", 3: "records", 21: "calibration", 30: "core"} if campaign_version == 2 else {1: "awakening", 3: "records", 9: "calibration", 12: "core"}
	if beats.has(room):
		show_story(beats[room], state)

func show_story(id: String, destination: String) -> void:
	if not narrative_enabled or id in story_seen:
		return
	story_id = id
	story_return = destination
	story_seen.append(id)
	show_menu("story")

func continue_story() -> void:
	if state != "story":
		return
	if story_return == "playing":
		state = "playing"
		arm_player_input()
		world.process_mode = Node.PROCESS_MODE_INHERIT
		hud.hide_menu()
	else:
		show_menu(story_return)
	save_checkpoint()

func spawn_enemy(kind: String, point: Vector2):
	var enemy = ENEMY.instantiate()
	enemy.game = self
	enemy.kind = kind
	enemy.position = point
	actors.add_child(enemy)
	if kind in ["boss", "warden"]:
		active_boss = enemy
	return enemy

func spawn_bolt(point: Vector2, direction: Vector2, hostile: bool, damage: float, options: Dictionary = {}):
	var bolt = PROJECTILE.instantiate()
	bolt.game = self
	bolt.position = point
	bolt.direction = direction.normalized()
	bolt.hostile = hostile
	bolt.damage = damage
	bolt.configure(options)
	$World/Projectiles.add_child(bolt)
	return bolt

func spawn_field(point: Vector2, shooter: Node2D, mode: String, damage: float, radius: float, duration: float):
	var field = FIELD.new()
	field.game = self
	field.position = point
	field.shooter = shooter
	field.mode = mode
	field.damage = damage
	field.radius = radius
	field.duration = duration
	$World/Projectiles.add_child(field)
	return field

func has_sight(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func spawn_hazard(point: Vector2, radius: float, damage: float) -> void:
	var hazard = HAZARD.new()
	hazard.game = self
	hazard.position = point
	hazard.radius = radius
	hazard.damage = damage
	$World/Projectiles.add_child(hazard)

func clip_to_wall(from: Vector2, to: Vector2) -> Vector2:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.position - from.direction_to(to) * 12.0 if not hit.is_empty() else to

func beam(from: Vector2, to: Vector2, color: Color) -> void:
	var line := Line2D.new()
	line.width = 3.0
	line.default_color = color
	line.points = PackedVector2Array([from, from.lerp(to, 0.33) + Vector2(0, -7), from.lerp(to, 0.66) + Vector2(0, 7), to])
	$World/Effects.add_child(line)
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.2)
	tween.tween_callback(line.queue_free)

func open_armory() -> void:
	if state not in ["title", "dead", "victory"]:
		return
	armory_return = state
	show_menu("armory")

func select_weapon(id: String) -> bool:
	if state != "armory" or not WEAPONS.exists(id):
		return false
	selected_weapon = id
	if coop.enabled:
		coop.weapons[0] = id
	profile.weapon = id
	persist_profile()
	show_menu("armory")
	return true

func armory_back() -> void:
	if state == "armory":
		show_menu(armory_return)

func nearest_enemy(point: Vector2):
	var nearest = null
	var best := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var distance: float = point.distance_squared_to(enemy.global_position)
		if distance < best:
			best = distance
			nearest = enemy
	return nearest

func enemy_defeated(enemy: Node2D) -> void:
	if enemy == active_boss:
		active_boss = null
	kills += 1
	scrap += 20 if enemy.kind in ["boss", "warden"] else 6
	effect(enemy.position, Color("ffba79"), 80.0)
	play_tone(260.0, 0.1, 0.06)
	var sprite: Sprite2D = enemy.get_node("Sprite")
	var wreck := Sprite2D.new()
	wreck.texture = sprite.texture
	wreck.position = sprite.global_position
	wreck.rotation = sprite.rotation
	wreck.scale = sprite.scale
	wreck.flip_h = sprite.flip_h
	$World/Effects.add_child(wreck)
	var fade := wreck.create_tween().set_parallel(true)
	fade.tween_property(wreck, "modulate:a", 0.0, 0.32)
	fade.tween_property(wreck, "scale", wreck.scale * 0.85, 0.32)
	fade.chain().tween_callback(wreck.queue_free)
	if get_tree().get_nodes_in_group("enemies").is_empty():
		clear_pending = true

func complete_room() -> void:
	if state != "playing" or room_awarded or not encounter.finished() or not get_tree().get_nodes_in_group("enemies").is_empty():
		return
	room_awarded = true
	for member in team():
		if member.hp <= 0.0:
			member.revive()
	var multiplier := 2 if room_data.kind == "elite" else 1
	scrap += (40 + room * 5) * multiplier
	var cores := (3 + room / 3) * multiplier
	if room_data.kind == "boss":
		cores += 15
	profile.cores += cores
	earned_cores += cores
	if room == run_length:
		finish_run(true)
	else:
		var promise: String = ROOMS.reward_for(room_data).stat if room_data.get("generator", 1) >= 2 else ""
		boon_choices = PROGRESSION.promised_offers(rng, room == 1, player.enchantments, promise, team(), campaign_version)
		show_menu("reward")
		if room == 6:
			show_story("warden", "reward")
		save_checkpoint()

func apply_boon(boon: Dictionary) -> void:
	for member in team():
		PROGRESSION.apply(boon, member, campaign_version)

func choose_boon(index: int) -> void:
	if state != "reward" or index < 0 or index >= boon_choices.size():
		return
	apply_boon(boon_choices[index])
	for member in team():
		member.hp = minf(member.max_hp, member.hp + 12.0)
		member.energy = 100.0
	prepare_routes()

func prepare_routes() -> void:
	route_choices.clear()
	var kinds: Array = ROOMS.LEGACY.choices(room + 1) if campaign_version == 1 else ROOMS.choices(room + 1)
	for kind in kinds:
		var choice := ROOMS.generate(room + 1, kind, rng, campaign_version)
		# Existing checkpoints retain the original one-draw-per-door RNG sequence.
		if campaign_version == 2:
			for attempt in range(24):
				if choice.name != room_data.name and not route_choices.any(func(other): return other.name == choice.name): break
				choice = ROOMS.generate(room + 1, kind, rng, campaign_version)
		route_choices.append(choice)
	show_menu("route")
	save_checkpoint()

func choose_route(index: int) -> bool:
	if state != "route" or index < 0 or index >= route_choices.size():
		return false
	var choice: Dictionary = route_choices[index]
	if choice.depth != room + 1:
		return false
	next_room(choice)
	return true

func prepare_shop() -> void:
	var element: String = PROGRESSION.ELEMENTS[rng.randi_range(0, PROGRESSION.ELEMENTS.size() - 1)]
	set_shop_stock(element)

func set_shop_stock(element: String) -> void:
	shop_stock = [
		{"id": "repair", "name": "应急维修", "description": "恢复五十点耐久。", "cost": 50},
		{"id": "tuning", "name": "武器调校", "description": "本局武器伤害提高百分之十五。", "cost": 90},
		{"id": element, "name": PROGRESSION.rune(element).name, "description": "附魔所有武器命中，最高三级。", "cost": 75},
	]

func can_buy(index: int) -> bool:
	if state != "shop" or index < 0 or index >= shop_stock.size():
		return false
	var item: Dictionary = shop_stock[index]
	if item.id in purchased or scrap < int(item.cost):
		return false
	if item.id == "repair":
		return team().any(func(member): return member.hp < member.max_hp)
	if campaign_version >= 2:
		return team().any(func(member): return PROGRESSION.can_apply({"stat": item.id}, member, campaign_version))
	return int(player.enchantments.get(item.id, 0)) < 3

func buy_item(index: int) -> bool:
	if not can_buy(index):
		return false
	var item: Dictionary = shop_stock[index]
	scrap -= item.cost
	purchased.append(item.id)
	match item.id:
		"repair":
			for member in team():
				member.hp = minf(member.max_hp, member.hp + 50.0)
		"tuning":
			for member in team():
				if campaign_version >= 2:
					PROGRESSION.apply({"stat": "tuning"}, member, campaign_version)
				else:
					member.damage *= 1.15
		_: apply_boon({"stat": item.id})
	show_menu("shop")
	save_checkpoint()
	return true

func leave_supply() -> void:
	if state in ["shop", "rest"]:
		prepare_routes()

func open_workbench() -> void:
	if state not in ["title", "dead", "victory"]:
		return
	workbench_return = state
	show_menu("workbench")

func workbench_back() -> void:
	if state == "workbench":
		show_menu(workbench_return)

func buy_meta(id: String) -> bool:
	if state != "workbench" or not profile.purchase(id):
		return false
	persist_profile()
	show_menu("workbench")
	return true

func persist_profile() -> void:
	if persistence_enabled:
		var result: Error = profile.save_progress()
		if result != OK:
			save_warning = "进度保存失败（错误码 %d），请暂时保留当前游戏。" % int(result)
		else:
			save_warning = ""

func save_checkpoint() -> void:
	if result_recorded or state not in RUN_SAVE.STATES or not is_instance_valid(player):
		return
	profile.checkpoint = RUN_SAVE.capture(self)
	persist_profile()

func continue_saved_run() -> bool:
	if state != "title" or not RUN_SAVE.valid(profile.checkpoint):
		return false
	var saved: Dictionary = profile.checkpoint.duplicate(true)
	clear_world()
	campaign_version = saved.get("campaign", 1)
	run_length = LAST_ROOM if campaign_version == 2 else 12
	room_data = RUN_SAVE.rebuild_room(saved.room)
	room = room_data.depth
	run_seed = saved.run_seed
	rng.state = saved.rng_state
	kills = saved.kills
	elapsed = saved.elapsed
	scrap = saved.scrap
	earned_cores = saved.earned_cores
	result_recorded = false
	room_awarded = saved.awarded
	story_id = saved.story_id
	story_return = saved.story_return
	story_seen.assign(saved.story_seen)
	route_history.assign(saved.history)
	purchased.assign(saved.purchased)
	boon_choices.clear()
	for stat in saved.boons:
		boon_choices.append(PROGRESSION.rune(stat))
	route_choices.clear()
	for recipe in saved.routes:
		route_choices.append(RUN_SAVE.rebuild_room(recipe))
	shop_stock.clear()
	if saved.stock.size() == 3:
		set_shop_stock(saved.stock[2])
	player = PLAYER.instantiate()
	player.game = self
	player.position = room_data.start
	for field in RUN_SAVE.STATS:
		player.set(field, saved.stats[field])
	player.enchantments = saved.enchantments.duplicate()
	player.invulnerable = 1.2
	actors.add_child(player)
	player.weapon.equip(saved.weapon)
	coop.enabled = saved.get("version", 1) == 2
	if coop.enabled:
		coop.weapons.assign([saved.weapon, saved.partner.weapon])
		create_companion(saved.partner)
	arena.apply_room(room_data)
	camera.position = player.position
	camera.zoom = Vector2.ONE
	camera.reset_smoothing()
	var destination: String = saved.story_return if saved.state == "story" else saved.state
	if destination == "playing":
		populate_room()
	show_menu("paused" if saved.state == "playing" else saved.state)
	if coop.enabled:
		coop.devices.assign([-1, -1])
		configure_input()
		coop.open_lobby(true)
	return true

func abandon_to_title() -> void:
	if state == "paused":
		persist_profile()
		clear_world()
		show_menu("title")

func show_menu(menu: String) -> void:
	state = menu
	if menu != "settings":
		rebind_action = ""
	for member in team():
		member.weapon.cancel_charge()
		member.input_armed = false
	# Damage can end a run inside Area2D.body_entered; defer disabling bodies.
	sync_world_process.call_deferred()
	camera.offset = Vector2.ZERO
	hud.show_menu(menu)

func sync_world_process() -> void:
	# Read the latest state, not a queued menu's stale value (rapid restart/back).
	world.process_mode = Node.PROCESS_MODE_INHERIT if state == "playing" else Node.PROCESS_MODE_DISABLED

func resume_run() -> void:
	if coop.enabled and not coop.ready_to_play():
		coop.open_lobby(true)
		return
	if state != "paused":
		return
	state = "playing"
	arm_player_input()
	world.process_mode = Node.PROCESS_MODE_INHERIT
	hud.hide_menu()

func arm_player_input() -> void:
	for member in team():
		member.input_armed = true
		for action in ["slash", "bolt", "dash", "freeze", "parry"]:
			if Input.is_action_pressed(member.action(action)):
				member.input_armed = false

func team() -> Array:
	var members: Array = []
	for member in [player, companion]:
		if is_instance_valid(member):
			members.append(member)
	return members

func nearest_player(point: Vector2):
	var nearest = null
	var distance := INF
	for member in team():
		if member.hp > 0.0 and point.distance_squared_to(member.position) < distance:
			distance = point.distance_squared_to(member.position)
			nearest = member
	return nearest

func create_companion(saved: Dictionary = {}) -> void:
	companion = PLAYER.instantiate()
	companion.game = self
	companion.seat = 1
	companion.position = player.position + Vector2(60, 0)
	for field in RUN_SAVE.STATS:
		companion.set(field, saved.stats[field] if not saved.is_empty() else player.get(field))
	companion.enchantments = saved.enchantments.duplicate() if not saved.is_empty() else {}
	actors.add_child(companion)
	companion.weapon.equip(coop.weapons[1])

func player_disabled(_member) -> void:
	if nearest_player(Vector2.ZERO) == null:
		finish_run(false)
	else:
		announce("队友已离线 · 靠近停留三秒可修复", Color("e6b879"))

func start_single_rescue() -> void:
	coop.enabled = false
	request_new_run()

func open_coop() -> void:
	coop.open_lobby(false)

func leave_result() -> void:
	if state not in ["dead", "victory"]:
		return
	clear_world()
	coop.enabled = false
	show_menu("title")

func finish_run(won: bool) -> void:
	if result_recorded:
		return
	result_recorded = true
	sound.play_cue("clear" if won else "heavy", 0.3)
	if won:
		profile.wins += 1
		profile.cores += 30
		earned_cores += 30
	profile.checkpoint.clear()
	persist_profile()
	clear_pending = false
	show_menu("victory" if won else "dead")
	if won:
		show_story("ending", "victory")

func announce(message: String, color: Color) -> void:
	announcement_left = 2.0
	hud.announcement.text = message
	hud.set_label_color(hud.announcement, color)

func effect(point: Vector2, color: Color, radius: float, duration := 0.4) -> void:
	var ring = EFFECT.new()
	ring.position = point
	ring.color = color
	ring.radius = radius
	ring.duration = duration
	$World/Effects.add_child(ring)

func play_tone(frequency: float, duration: float, volume: float) -> void:
	if not muted and is_instance_valid(sound):
		sound.play_tone(frequency, duration, volume)

func fit_window_to_screen() -> void:
	if DisplayServer.get_name() == "headless" or settings.values.fullscreen:
		return
	var screen := DisplayServer.window_get_current_screen()
	var area := DisplayServer.screen_get_usable_rect(screen)
	# Godot's native window sizes are physical pixels on macOS. Express the
	# intended desktop size in points so Retina does not halve the game's UI.
	var scale := maxf(1.0, DisplayServer.screen_get_scale(screen))
	var available := Vector2(area.size) - Vector2(48, 80) * scale
	var desired := Vector2(1280, 800) * scale
	var factor := minf(1.0, minf(available.x / desired.x, available.y / desired.y))
	var fitted := Vector2i(desired * factor)
	DisplayServer.window_set_size(fitted)
	DisplayServer.window_set_position(area.position + (area.size - fitted) / 2)
