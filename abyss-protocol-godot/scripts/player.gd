extends CharacterBody2D
## The android owns combat stats; the run controller owns progression.

var game
var seat := 0
var revive_progress := 0.0
var tutorial_step := 0
var tutorial_distance := 0.0
var max_hp := 100.0
var hp := 100.0
var energy := 100.0
var energy_regen := 19.0
var enchantments: Dictionary = {}
# A short recovery reserve prevents pellet count from multiplying sustain.
var leech_available := 4.0
var damage := 26.0
var move_speed := 280.0
var aim := Vector2.RIGHT
var dash_direction := Vector2.RIGHT
var dash_left := 0.0
var dash_cooldown := 0.0
var dash_recharge := 0.9
var invulnerable := 0.0
var slash_cooldown := 0.0
var slash_left := 0.0
var bolt_cooldown := 0.0
var freeze_cooldown := 0.0
var parry_left := 0.0
var parry_cooldown := 0.0
var perfect_cooldown := 0.0
var empowered := 0.0
var step_clock := 0.0
var mouse_idle := 10.0
var aim_mode := "heading"
var input_armed := false
@onready var weapon = $Weapon

func _ready() -> void:
	$Sprite.update_pose()

func action(id: String) -> String:
	return "p%d_%s" % [seat + 1, id] if game.coop.enabled else id

func _input(event: InputEvent) -> void:
	if game.coop.enabled:
		return
	if event is InputEventMouseMotion and event.relative.length() > 1:
		mouse_idle = 0.0
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		# Releasing a charged shot is still intentional mouse aim.
		mouse_idle = 0.0

func _physics_process(delta: float) -> void:
	if game.state != "playing" or hp <= 0.0:
		return
	for key in ["dash_cooldown", "invulnerable", "slash_cooldown", "slash_left",
			"bolt_cooldown", "freeze_cooldown", "parry_left", "parry_cooldown",
			"perfect_cooldown", "empowered"]:
		set(key, maxf(0.0, get(key) - delta))
	energy = minf(100.0, energy + energy_regen * delta)
	if game.campaign_version >= 2 and enchantments.has("leech"):
		var capacity: float = game.PROGRESSION.leech_capacity(int(enchantments.leech))
		leech_available = minf(capacity, leech_available + capacity * delta)
	mouse_idle += delta
	var movement := Input.get_vector(action("move_left"), action("move_right"), action("move_up"), action("move_down"))
	var stick := Input.get_vector(action("aim_left"), action("aim_right"), action("aim_up"), action("aim_down"))
	var mouse_attacking := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if (game.coop.enabled or game.using_gamepad) and stick.length() > 0.15:
		aim = stick.normalized()
		aim_mode = "stick"
	elif not (game.coop.enabled or game.using_gamepad) and (not game.settings.values.aim_assist or mouse_idle < 2.0 or mouse_attacking):
		var pointer := get_global_mouse_position() - global_position
		if pointer.length_squared() > 64.0:
			aim = pointer.normalized()
		aim_mode = "mouse"
	elif game.settings.values.aim_assist:
		var target = game.nearest_enemy(global_position)
		if is_instance_valid(target):
			aim = global_position.direction_to(target.global_position)
			aim_mode = "assist"
		elif movement.length_squared() > 0.1:
			aim = movement.normalized()
			aim_mode = "heading"
	elif movement.length_squared() > 0.1:
		aim = movement.normalized()
		aim_mode = "heading"
	if not input_armed:
		input_armed = not (Input.is_action_pressed(action("slash")) or Input.is_action_pressed(action("bolt")) or Input.is_action_pressed(action("dash")) or Input.is_action_pressed(action("freeze")) or Input.is_action_pressed(action("parry")))
	if input_armed and Input.is_action_just_pressed(action("dash")):
		try_dash(movement)
	weapon.tick(delta, input_armed and Input.is_action_pressed(action("slash")), input_armed and Input.is_action_just_released(action("slash")))
	if input_armed and Input.is_action_pressed(action("bolt")):
		try_bolt()
	if input_armed and Input.is_action_just_pressed(action("freeze")):
		try_freeze()
	if input_armed and Input.is_action_just_pressed(action("parry")):
		try_parry()
	if dash_left > 0.0:
		dash_left = maxf(0.0, dash_left - delta)
		velocity = dash_direction * 900.0
	else:
		velocity = velocity.move_toward(movement * move_speed, 2400.0 * delta)
	var previous_position := position
	var was_dashing := dash_left > 0.0
	move_and_slide()
	step_clock += delta * velocity.length() * 0.05
	tutorial_distance += position.distance_to(previous_position)
	if tutorial_step == 0 and tutorial_distance >= 80:
		tutorial_step = 1
	if tutorial_step == 1 and slash_left > 0:
		tutorial_step = 2
	if tutorial_step == 2 and dash_left > 0:
		tutorial_step = 3
	$Sprite.advance(position - previous_position, delta, was_dashing)
	$Sprite.modulate = Color.WHITE.lerp(Color(1.8, 2.3, 2.5), float(game.settings.values.flash)) if invulnerable > 0.0 else Color.WHITE
	queue_redraw()

func try_dash(direction: Vector2) -> bool:
	if dash_cooldown > 0.0:
		return false
	dash_direction = direction.normalized() if direction.length_squared() > 0.1 else aim
	dash_left = 0.18
	invulnerable = 0.23
	dash_cooldown = dash_recharge
	game.effect(global_position, Color("67efe0"), 60.0)
	game.sound.play_cue("dash", 0.24)
	return true

func try_slash() -> bool:
	return weapon.fire()

func weapon_hit(enemy: Node2D, amount: float, force: Vector2, element := "") -> void:
	if not is_instance_valid(enemy) or enemy.dead:
		return
	if enchantments.has("execute") and enemy.hp < enemy.max_hp * 0.3:
		amount *= 1.5 + (float(enchantments.execute) - 1.0) * 0.2
	var actual_damage := minf(enemy.hp, amount)
	enemy.take_damage(amount, force)
	if hp > 0.0 and enchantments.has("leech"):
		var recovery := minf(4.0, actual_damage * 0.06 * float(enchantments.leech))
		if game.campaign_version >= 2:
			var capacity: float = game.PROGRESSION.leech_capacity(int(enchantments.leech))
			recovery = minf(minf(capacity, leech_available), actual_damage * 0.06 * float(enchantments.leech))
			recovery = minf(recovery, max_hp - hp)
			leech_available = maxf(0.0, leech_available - recovery)
		hp = minf(max_hp, hp + recovery)
	# Innate and rune effects remain one application. New campaigns add their
	# ranks so the first matching rune actually strengthens an elemental weapon.
	for tag in ["ice", "poison", "shock", "fire"]:
		if enemy.dead and (tag != "fire" or game.campaign_version < 2):
			continue
		var level: int = game.PROGRESSION.effective_element_level(int(enchantments.get(tag, 0)), element == tag, game.campaign_version)
		if level > 0:
			enemy.apply_element(tag, amount * game.PROGRESSION.element_power(level), level if game.campaign_version >= 2 else 1)

func try_bolt() -> bool:
	if bolt_cooldown > 0.0 or energy < 24.0:
		return false
	energy -= 24.0
	bolt_cooldown = 0.23
	game.spawn_bolt(global_position + aim * 28.0, aim, false, damage * 0.85)
	game.play_tone(650.0, 0.07, 0.05)
	return true

func try_freeze() -> bool:
	if freeze_cooldown > 0.0:
		return false
	freeze_cooldown = 10.0
	game.effect(global_position, Color("a0e4ff"), 270.0, 0.65)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(enemy.global_position) < 270.0:
			enemy.freeze_for(1.2 if enemy.kind in ["boss", "warden"] else 2.5)
			enemy.take_damage(damage * 0.6, Vector2.ZERO)
	game.play_tone(1000.0, 0.25, 0.07)
	return true

func try_parry() -> bool:
	if parry_cooldown > 0.0:
		return false
	parry_left = 0.18
	parry_cooldown = 0.65
	return true

func take_damage(amount: float, source: Vector2, parryable := true) -> bool:
	if hp <= 0.0:
		return false
	if parry_left > 0.0 and parryable:
		parry_left = 0.0
		invulnerable = 0.35
		energy = minf(100.0, energy + 25.0)
		empowered = 2.0
		game.announce("弹反成功 · 超载反击", Color("ffd090"))
		game.effect(global_position, Color("ffd090"), 155.0)
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if global_position.distance_to(enemy.global_position) < 155.0:
				enemy.frozen = 0.9
				enemy.take_damage(damage, global_position.direction_to(enemy.global_position) * 330.0)
		return false
	if invulnerable > 0.0:
		if dash_left > 0.0 and perfect_cooldown <= 0.0:
			perfect_cooldown = 1.6
			dash_cooldown = 0.0
			empowered = 2.0
			game.announce("完美闪避", Color("67efe0"))
		return false
	hp = maxf(0.0, hp - amount)
	invulnerable = 0.7
	velocity += source.direction_to(global_position) * 200.0
	game.shake = 9.0
	game.effect(global_position, Color("ff6a80"), 50.0)
	game.play_tone(90.0, 0.14, 0.12)
	if hp <= 0.0:
		velocity = Vector2.ZERO
		weapon.cancel_charge()
		game.player_disabled(self)
	return true

func revive() -> void:
	hp = maxf(1.0, max_hp * 0.35)
	revive_progress = 0.0
	invulnerable = 2.0
	input_armed = false
	queue_redraw()

func _draw() -> void:
	var identity := Color("8bb5bf") if seat == 0 else Color("e6b879")
	if game.coop.enabled:
		draw_circle(Vector2(0, -112), 14, Color("111d22"))
		draw_string(ThemeDB.fallback_font, Vector2(-5, -107), str(seat + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, identity)
		draw_arc(Vector2.ZERO, 29, 0, TAU, 40, identity, 3, true)
	if hp <= 0.0:
		draw_line(Vector2(-12, -12), Vector2(12, 12), identity, 4, true)
		draw_line(Vector2(-12, 12), Vector2(12, -12), identity, 4, true)
		draw_arc(Vector2.ZERO, 36, -PI / 2, -PI / 2 + TAU * revive_progress / 3.0, 48, identity, 5, true)
		return
	draw_circle(Vector2(0, 4), 24, Color(0.0, 0.0, 0.0, 0.4))
	draw_arc(Vector2.ZERO, 23.0, 0.0, TAU, 40, Color("67efe0"), 1.5, true)
	draw_line(aim * 27.0, aim * 43.0, Color("e3fff9"), 2.0, true)
	if dash_left > 0.0:
		draw_line(-dash_direction * 20.0, -dash_direction * 90.0, Color(0.4, 1.0, 0.9, 0.4), 18.0, true)
	if weapon.drawing:
		var fraction: float = weapon.charge / float(weapon.definition.charge)
		draw_rect(Rect2(-26, -81, 52, 5), Color("263343"))
		draw_rect(Rect2(-26, -81, 52 * fraction, 5), Color(weapon.definition.color))
	if parry_left > 0.0:
		draw_arc(Vector2.ZERO, 42.0, 0, TAU, 48, Color("ffd090"), 4.0, true)
