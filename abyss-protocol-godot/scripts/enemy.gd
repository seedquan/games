extends CharacterBody2D

const DRONE = preload("res://assets/drone.webp")
const BRUTE = preload("res://assets/brute.webp")
const CORE = preload("res://assets/core.webp")
const WARDEN = preload("res://assets/warden.webp")
const MELEE_REACH := 105.0
const MELEE_HALF_ANGLE := acos(0.1)
const ATTACK_LABELS := {"ground": "地面锁定", "spread": "扇形齐射", "radial": "环形弹幕", "shot": "瞄准射击", "melee": "近身挥击", "cross": "十字交火",
	"sweep": "盾阵横扫", "coolant": "冷凝封路", "lattice": "档案光栅", "heat_ring": "熔炉热环", "sequence": "协议重排"}

var game
var kind := "stalker"
var hp := 60.0
var max_hp := 60.0
var scrap_reward := 6
var radius := 19.0
var speed := 110.0
var damage := 13.0
var frozen := 0.0
var knockback := Vector2.ZERO
var cooldown := 1.0
var windup := 0.0
var attacking := false
var committed_direction := Vector2.RIGHT
var flash := 0.0
var dead := false
var clock := 0.0
var burn_left := 0.0
var burn_damage := 0.0
var burn_tick := 0.0
var chill_left := 0.0
var chill_stacks := 0
var shock_guard := 0.0
var ice_frozen_left := 0.0
var ice_guard_left := 0.0
var poison_left := 0.0
var poison_stacks := 0
var poison_damage := 0.0
var poison_tick := 0.0
var navigation_hold := 0.0
var pattern := 0
var elite := false
var sprite_scale := Vector2.ONE
var recoil := 0.0
var guardian_patterns: Array = []

func _ready() -> void:
	var size := 82.0
	$Sprite.texture = BRUTE
	if kind == "drone":
		hp = 42.0
		speed = 100.0
		$Sprite.texture = DRONE
	elif kind in ["boss", "warden"]:
		hp = 700.0 if kind == "boss" else 480.0
		radius = 46.0
		speed = 65.0
		damage = 22.0
		size = 185.0
		$Sprite.texture = CORE if kind == "boss" else WARDEN
		$Sprite.position.y = -45.0
		if game.room_data.kind == "boss" and game.room_data.get("generator", 1) >= 2:
			guardian_patterns = game.room_data.region.pattern.duplicate()
	if kind in ["boss", "warden"] and game.room_data.kind == "boss" and game.room_data.get("generator", 1) >= 2:
		hp = float(game.room_data.region.guardian_hp)
	else:
		hp *= 1.0 + 0.1 * (game.room - 1)
	elite = game.room_data.get("kind", "combat") == "elite"
	if elite:
		hp *= 1.5
		damage *= 1.25
		speed *= 1.12
	if game.coop.enabled:
		hp *= 1.6
	max_hp = hp
	$Sprite.scale = Vector2.ONE * size / $Sprite.texture.get_width()
	sprite_scale = $Sprite.scale
	$Collision.shape = $Collision.shape.duplicate()
	$Collision.shape.radius = radius
	cooldown = randf_range(2.2, 3.0) if game.room == 1 else randf_range(0.6, 1.4)

func _physics_process(delta: float) -> void:
	if dead or game.state != "playing" or not is_instance_valid(game.player):
		return
	clock += delta
	recoil = maxf(0.0, recoil - delta * 5.0)
	navigation_hold = maxf(0.0, navigation_hold - delta)
	shock_guard = maxf(0.0, shock_guard - delta)
	ice_frozen_left = maxf(0.0, ice_frozen_left - delta)
	ice_guard_left = maxf(0.0, ice_guard_left - delta)
	chill_left = maxf(0.0, chill_left - delta)
	if chill_left == 0.0:
		chill_stacks = 0
	if burn_left > 0.0:
		burn_left = maxf(0.0, burn_left - delta)
		burn_tick -= delta
		if burn_tick <= 0.0:
			burn_tick = 0.5
			take_damage(burn_damage, Vector2.ZERO)
			if dead:
				return
	if poison_left > 0.0:
		poison_left = maxf(0.0, poison_left - delta)
		poison_tick -= delta
		if poison_tick <= 0.0:
			poison_tick = 0.5
			take_damage(poison_damage * poison_stacks, Vector2.ZERO)
			if dead:
				return
	else:
		poison_stacks = 0
	flash = maxf(0.0, flash - delta)
	frozen = maxf(0.0, frozen - delta)
	knockback = knockback.move_toward(Vector2.ZERO, 750.0 * delta)
	if frozen > 0.0:
		velocity = knockback
		move_and_slide()
		$Sprite.modulate = Color("8cd9ff")
		queue_redraw()
		return
	$Sprite.modulate = Color.WHITE.lerp(Color(2.8, 2.0, 2.0), float(game.settings.values.flash)) if flash > 0.0 else Color.WHITE
	var target_player = game.nearest_player(global_position)
	if not is_instance_valid(target_player):
		return
	var target: Vector2 = target_player.global_position
	var distance := global_position.distance_to(target)
	var direction := global_position.direction_to(target)
	var visible: bool = game.has_sight(global_position, target)
	if not visible or get_slide_collision_count() > 0:
		navigation_hold = 0.7
	var walking: Vector2 = game.arena.steering(global_position, target, radius + 9.0) if navigation_hold > 0.0 else direction
	cooldown = maxf(0.0, cooldown - delta)
	velocity = Vector2.ZERO
	if attacking:
		windup -= delta
		if windup <= 0.0:
			attacking = false
			release_attack()
			cooldown = 1.5 if kind in ["boss", "warden"] else 1.1
	else:
		if kind == "drone":
			velocity = walking * speed * (1.0 if distance > 330.0 or not visible else -0.65 if distance < 210.0 else 0.0)
		else:
			velocity = walking * speed if distance > (85.0 if kind in ["boss", "warden"] else 49.0) else Vector2.ZERO
		var reach := 520.0 if kind in ["drone", "boss", "warden"] else 82.0
		if cooldown <= 0.0 and distance < reach and visible:
			attacking = true
			windup = 0.75 if kind in ["boss", "warden"] else 0.5
			committed_direction = direction
	# Soft separation prevents a single stack of overlapping melee bodies.
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or other.dead:
			continue
		var offset: Vector2 = global_position - other.global_position
		if offset.length_squared() < pow(radius + other.radius + 12.0, 2.0):
			velocity += offset.normalized() * 65.0
	if chill_left > 0.0:
		velocity *= 0.65
	velocity += knockback
	move_and_slide()
	$Sprite.flip_h = direction.x < -0.2
	animate_body(direction)
	queue_redraw()

func animate_body(direction: Vector2) -> void:
	var base_height := -45.0 if kind in ["boss", "warden"] else -22.0
	var stride := minf(1.0, velocity.length() / maxf(1.0, speed))
	var bob := sin(clock * (3.0 if kind == "drone" else 10.0)) * (4.0 if kind == "drone" else stride * 1.8)
	var wind := 0.0
	if attacking:
		wind = clampf(1.0 - windup / (0.75 if kind in ["boss", "warden"] else 0.5), 0.0, 1.0)
	$Sprite.position = Vector2(0, base_height + bob) - committed_direction * (wind * 6.0 + recoil * 8.0)
	$Sprite.scale = sprite_scale * Vector2(1.0 - wind * 0.05 + recoil * 0.04, 1.0 + wind * 0.06 - recoil * 0.04)
	$Sprite.rotation = clampf(direction.x * stride * sin(clock * 10.0) * 0.025, -0.04, 0.04) if kind == "stalker" else sin(clock * 1.2) * 0.025

func release_attack() -> void:
	recoil = 1.0
	var upcoming := next_attack()
	var directions := warning_shot_directions()
	pattern += 1
	if upcoming in game.GUARDIAN_ATTACK.IDS:
		var targets: Array = game.team().filter(func(member): return member.hp > 0)
		for spec in game.GUARDIAN_ATTACK.placements(upcoming, global_position, committed_direction, targets):
			game.spawn_guardian_attack(spec, damage)
	elif upcoming == "ground":
		for offset in [Vector2(-65, 0), Vector2(65, 0), Vector2(0, 110)]:
			var target = game.nearest_player(global_position)
			if is_instance_valid(target):
				game.spawn_hazard(target.position + offset, 95.0, damage)
	elif not directions.is_empty():
		for direction in directions:
			game.spawn_bolt(global_position + direction * (28.0 if kind == "drone" else 55.0), direction, true, damage)
		if kind == "boss":
			game.effect(global_position, Color("ee80eb"), 155.0)
	else:
		game.effect(global_position + committed_direction * 38.0, Color("ff7088"), 40.0, 0.2)
		for member in game.team():
			var offset: Vector2 = member.global_position - global_position
			if offset.length() < MELEE_REACH and committed_direction.dot(offset.normalized()) > cos(MELEE_HALF_ANGLE) and game.has_sight(global_position, member.position):
				member.take_damage(damage, global_position)

func next_attack() -> String:
	if not guardian_patterns.is_empty():
		return guardian_patterns[pattern % guardian_patterns.size()]
	if kind == "warden":
		return "ground" if (pattern + 1) % 2 == 0 else "spread"
	return "radial" if kind == "boss" else "shot" if kind == "drone" else "melee"

func warning_shot_directions() -> PackedVector2Array:
	var directions := PackedVector2Array()
	match next_attack():
		"shot": directions.append(committed_direction)
		"spread":
			for angle in [-0.3, -0.15, 0.0, 0.15, 0.3]:
				directions.append(committed_direction.rotated(angle))
		"cross":
			for i in range(4):
				directions.append(committed_direction.rotated(i * PI / 2))
		"radial":
			var count := 16 if hp < max_hp * 0.5 else 12
			for i in range(count):
				directions.append(Vector2.from_angle(committed_direction.angle() + TAU * float(i) / count))
	return directions

func melee_warning_points() -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	for i in range(49):
		var angle := committed_direction.angle() + lerpf(-MELEE_HALF_ANGLE, MELEE_HALF_ANGLE, i / 48.0)
		points.append(Vector2.from_angle(angle) * MELEE_REACH)
	return points

func draw_attack_warning(color: Color) -> void:
	if next_attack() in game.GUARDIAN_ATTACK.IDS:
		# This is a preparation glyph; placed shapes receive their own full timer.
		var index: int = game.GUARDIAN_ATTACK.IDS.find(next_attack())
		draw_texture_rect_region(preload("res://assets/ui/boss_signatures.svg"), Rect2(-36, 78, 72, 72), Rect2(index * 64, 0, 64, 64))
	elif next_attack() == "melee":
		var points := melee_warning_points()
		draw_colored_polygon(points, Color(color, 0.1))
		points.append(Vector2.ZERO)
		draw_polyline(points, Color("ffe1cf"), 2.0, true)
		draw_arc(Vector2.ZERO, MELEE_REACH, committed_direction.angle() - MELEE_HALF_ANGLE, committed_direction.angle() + MELEE_HALF_ANGLE, 49, color, 3.0, true)
	elif next_attack() == "ground":
		# A cluster glyph signals the coming targeted ground zones; each zone gets
		# its own full warning delay after placement, before it can cause damage.
		draw_arc(Vector2.ZERO, 110, 0, TAU, 60, Color("ffbc7f"), 3.0, true)
		for offset in [Vector2(-115, 10), Vector2(115, 10), Vector2(0, 110)]:
			draw_arc(offset, 22, 0, TAU, 24, Color("ffe7d1"), 2.0, true)
			draw_line(offset - Vector2(6, 0), offset + Vector2(6, 0), Color("ffe7d1"), 2.0, true)
	else:
		var end := 440.0 if kind == "drone" else 240.0 if kind == "warden" else 165.0
		var start := 28.0 if kind == "drone" else 55.0
		for direction in warning_shot_directions():
			draw_line(direction * start, direction * end, Color(color, 0.65), 2.0, true)
			var tip := direction * end
			draw_line(tip, tip - direction.rotated(0.45) * 12.0, Color("ffe7d1"), 2.0, true)
			draw_line(tip, tip - direction.rotated(-0.45) * 12.0, Color("ffe7d1"), 2.0, true)

func take_damage(amount: float, force: Vector2) -> void:
	if dead:
		return
	if flash <= 0:
		game.sound.play_cue("impact", 0.13)
	hp = maxf(0.0, hp - amount)
	knockback += force * (0.25 if kind in ["boss", "warden"] else 1.0)
	flash = 0.12
	game.effect(global_position + Vector2(0, -20), Color("ffd090"), 25.0, 0.2)
	if hp <= 0.0:
		dead = true
		remove_from_group("enemies")
		game.enemy_defeated(self)
		queue_free()

func apply_element(element: String, power: float, level := 1) -> void:
	if dead:
		# A lethal fire hit can still detonate the states already on its target.
		if element == "fire" and game.campaign_version >= 2:
			fire_reactions(power)
		return
	match element:
		"fire":
			burn_left = 2.5
			burn_damage = maxf(burn_damage, power * 0.12)
			fire_reactions(power)
		"ice":
			chill_left = 3.0
			chill_stacks += 1
			if chill_stacks >= 3:
				chill_stacks = 0
				var guardian := kind in ["boss", "warden"]
				if game.campaign_version < 2:
					freeze_for(0.6 if guardian else 1.8)
				elif not guardian or ice_guard_left <= 0.0:
					freeze_for(game.PROGRESSION.ice_duration(level, guardian))
					if guardian: ice_guard_left = 2.2
		"poison":
			poison_stacks = mini(6, poison_stacks + 1)
			poison_left = 4.0
			poison_damage = maxf(poison_damage, power * 0.04)
		"shock":
			if shock_guard <= 0.0:
				var guardian := kind in ["boss", "warden"]
				var duration: float = (0.1 if guardian else 0.22) if game.campaign_version < 2 else game.PROGRESSION.shock_duration(level, guardian)
				frozen = maxf(frozen, duration)
				shock_guard = 0.8
				if game.campaign_version >= 2 and level > 1:
					take_damage(power * game.PROGRESSION.shock_fraction(level), Vector2.ZERO)

func fire_reactions(power: float) -> void:
	var modern: bool = game.campaign_version >= 2
	if ice_frozen_left > 0.0:
		# Consume before applying damage. Splash uses direct damage, so it cannot
		# recursively detonate neighbours or multiply elemental/leech procs.
		frozen = 0.0
		ice_frozen_left = 0.0
		reaction_burst(power * 0.7, 150.0 if modern else 0.0, "thermal")
	if poison_stacks >= (3 if modern else 1):
		var burst := poison_stacks * power * 0.18
		poison_stacks = 0
		poison_left = 0.0
		if modern: poison_damage = 0.0
		reaction_burst(burst, 185.0 if modern else 0.0, "combustion")

func reaction_burst(amount: float, reach: float, reaction: String) -> void:
	var origin := global_position
	var color := Color("a0e4ff") if reaction == "thermal" else Color("b9df7b")
	take_damage(amount, Vector2.ZERO)
	if reach > 0.0:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy == self or enemy.dead:
				continue
			if origin.distance_to(enemy.global_position) <= reach and game.has_sight(origin, enemy.global_position):
				enemy.take_damage(amount, Vector2.ZERO)
		game.reaction_effect(origin, color, reach, reaction)
	elif reaction == "combustion":
		game.effect(origin, Color("ffd27a"), 70.0)
	game.announce("热冲击" if reaction == "thermal" else "毒素爆燃", color)

func freeze_for(duration: float) -> void:
	frozen = maxf(frozen, duration)
	ice_frozen_left = maxf(ice_frozen_left, duration)

func _draw() -> void:
	draw_circle(Vector2(0, 5), radius * 1.3, Color(0, 0, 0, 0.4))
	var color := Color("ed80eb") if kind == "boss" else Color("ff7088")
	draw_arc(Vector2.ZERO, radius + 4.0, 0, TAU, 40, Color(color, 0.5), 1.5, true)
	if hp < max_hp:
		var top := -140.0 if kind in ["boss", "warden"] else -72.0
		draw_rect(Rect2(-25, top, 50, 4), Color("263343"))
		draw_rect(Rect2(-25, top, 50 * hp / max_hp, 4), color)
	if attacking:
		draw_attack_warning(color)
	if frozen > 0.0:
		draw_arc(Vector2.ZERO, radius + 10.0, 0, TAU, 6, Color("a0e4ff"), 2.0, true)
	elif chill_left > 0.0:
		draw_arc(Vector2.ZERO, radius + 8.0, 0, TAU * float(chill_stacks) / 3.0, 30, Color("7fd8ff"), 2.0, true)
	if burn_left > 0.0:
		draw_arc(Vector2.ZERO, radius + 13.0, clock, clock + PI * 1.5, 30, Color("ff7a3c"), 2.0, true)
	if poison_stacks > 0:
		draw_arc(Vector2.ZERO, radius + 16.0, 0, TAU * poison_stacks / 6.0, 40, Color("b9df7b"), 3.0, true)
	if elite:
		draw_arc(Vector2.ZERO, radius + 6.0, 0, TAU, 6, Color("ffd27a"), 2.0, true)
