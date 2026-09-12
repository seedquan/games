extends SceneTree
## Controlled combat probes, not a human playtest. Firing probes use normal
## campaign HP and real weapon/projectile paths against a stationary target.
const PROGRESSION = preload("res://scripts/progression.gd")
const CHAPTERS = preload("res://scripts/chapters.gd")
const RUN_SAVE = preload("res://scripts/run_save.gd")
var game
var failures: Array[String] = []
var checks := 0
var measurements: Array = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count := 1) -> void:
	for i in range(count):
		await physics_frame
	await process_frame

func reset_case(depth := 1, kind := "stalker", weapon := "blade", cooperative := false, version := 2):
	game.coop.enabled = cooperative
	game.coop.devices.assign([1, 3] if cooperative else [-1, -1])
	game.coop.weapons.assign([weapon, weapon])
	game.configure_input()
	game.selected_weapon = weapon
	game.start_run(93847)
	game.campaign_version = version
	game.encounter.cancel()
	game.room_awarded = true
	game.room = depth
	game.room_data.depth = depth
	game.room_data.generator = version
	game.room_data.kind = "boss" if kind in ["boss", "warden"] else "combat"
	game.room_data.region = CHAPTERS.region(depth).duplicate(true)
	for enemy in get_nodes_in_group("enemies"):
		enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	for member in game.team():
		member.set_physics_process(false)
		member.position = Vector2(800, 650)
		member.aim = Vector2.RIGHT
	var enemy = game.spawn_enemy(kind, Vector2(875 if weapon == "blade" else 1000, 650))
	enemy.set_physics_process(false)
	await frames(2)
	return enemy

func firing_probe(depth: int, kind: String, weapon: String, damage_boons: int, cooperative := false) -> Dictionary:
	var enemy = await reset_case(depth, kind, weapon, cooperative)
	for i in range(damage_boons):
		game.apply_boon({"stat": "damage"})
	var initial_hp: float = enemy.hp
	var damage: float = game.player.damage
	var ticks := 0
	while is_instance_valid(enemy) and not enemy.dead and ticks < 3600:
		for member in game.team():
			member.slash_cooldown = maxf(0, member.slash_cooldown - 1.0 / 60.0)
			member.weapon.tick(1.0 / 60.0, true, false)
		ticks += 1
		await frames()
	var result := {"depth": depth, "kind": kind, "weapon": weapon, "damage_boons": damage_boons,
		"players": 2 if cooperative else 1, "target_hp": initial_hp, "weapon_damage": damage,
		"seconds": snappedf(ticks / 60.0, 0.001), "defeated": not is_instance_valid(enemy) or enemy.dead}
	measurements.append(result)
	check(result.defeated, "Normal-health firing probe defeats %s at depth %d" % [kind, depth])
	return result

func progression_cases() -> void:
	await reset_case()
	game.apply_boon({"stat": "damage"})
	check(is_equal_approx(game.player.damage, 32.5), "First damage blessing retains a tangible 25 percent gain")
	game.player.hp = 40
	game.apply_boon({"stat": "health"})
	check(game.player.max_hp == 125 and game.player.hp == 85, "Health blessing adds capacity and restores exactly the advertised amount")
	game.apply_boon({"stat": "speed"})
	check(is_equal_approx(game.player.move_speed, 308) and is_equal_approx(game.player.dash_recharge, 0.765), "First mobility blessing improves both movement and dash recovery")
	for i in range(35):
		for stat in ["damage", "health", "speed"]:
			game.apply_boon({"stat": stat})
	check(game.player.damage <= 156 and game.player.max_hp <= 350 and game.player.move_speed <= 420 and game.player.dash_recharge >= 0.44999, "Long campaigns cannot grow damage or movement exponentially")
	check(game.player.move_speed <= RUN_SAVE.STATS.move_speed[1] and game.player.max_hp <= RUN_SAVE.STATS.max_hp[1], "All repeatedly earned stats remain inside checkpoint validation ranges")
	check(not PROGRESSION.can_apply({"stat": "damage"}, game.player), "Capped damage cannot consume a reward")
	check(not PROGRESSION.can_apply({"stat": "speed"}, game.player), "Capped mobility cannot consume a reward")
	game.player.hp = game.player.max_hp - 40
	check(PROGRESSION.can_apply({"stat": "health"}, game.player), "At the capacity limit health still offers meaningful repair")
	check("40" in PROGRESSION.describe({"stat": "health"}, game.player), "Repair description uses actual missing health")
	game.apply_boon({"stat": "health"})
	check(game.player.hp == game.player.max_hp and not PROGRESSION.can_apply({"stat": "health"}, game.player), "Full-health capped repair leaves the offer pool")
	# Legacy numerical progress is not scaled down on load or on a new reward.
	game.player.damage = 400
	game.player.max_hp = 600
	game.player.hp = 530
	game.player.move_speed = 1200
	for stat in ["damage", "health", "speed"]:
		game.apply_boon({"stat": stat})
	check(game.player.damage == 400 and game.player.max_hp == 600 and game.player.move_speed == 1200, "Above-cap restored values are preserved")
	game.campaign_version = 1
	game.apply_boon({"stat": "damage"})
	check(game.player.damage == 500, "Version-one campaign retains its original multiplicative blessing")
	await reset_case(1, "stalker", "blade", true)
	game.companion.damage = 150
	game.apply_boon({"stat": "damage"})
	check(is_equal_approx(game.player.damage, 32.5) and game.companion.damage == 156, "Shared reward applies each actor's actual remaining gain")
	game.player.damage = 156
	game.companion.damage = 52
	var rng := RandomNumberGenerator.new()
	rng.seed = 903
	var offers := PROGRESSION.promised_offers(rng, false, {}, "damage", game.team(), 2)
	check(offers.any(func(boon): return boon.stat == "damage"), "A capped first actor does not hide a useful partner reward")
	# At most 29 combat rewards are possible. Sample different priorities at all
	# safe points; every offer must stay useful, unique and save-compatible.
	for priority in ["damage", "health", "speed", "fire", "ice", "shock", "poison", "leech", "execute"]:
		await reset_case()
		for room in range(1, 30):
			offers = PROGRESSION.promised_offers(rng, room == 1, game.player.enchantments, priority, game.team(), 2)
			check(offers.size() >= 1 and offers.size() <= 3, "A 29-reward %s build retains a nonempty bounded offer pool" % priority)
			check(offers.all(func(boon): return PROGRESSION.can_apply(boon, game.player)), "Every offered choice has a useful effect")
			var ids := offers.map(func(boon): return boon.stat)
			var unique: Dictionary = {}
			for id in ids: unique[id] = true
			check(unique.size() == ids.size(), "Reward choices are distinct")
			var selected: Dictionary = offers[0]
			for candidate in offers:
				if candidate.stat == priority: selected = candidate
			game.apply_boon(selected)

func shop_heavy_cases() -> void:
	# Construct a possible legal reward order with a conservative clear-reward
	# ledger. We exercise actual shop prices/caps, not a money or combat cheat.
	game.profile.upgrades = {"vitality": 5, "power": 5, "recovery": 5}
	await reset_case()
	game.scrap = 0
	var shops := 0
	var smallest_pool := 3
	var purchases := 0
	var order := ["speed", "fire", "ice", "shock", "poison", "leech", "execute", "damage", "health"]
	for depth in range(1, 30):
		var local_room: int = posmod(depth - 1, 6) + 1
		if local_room in [3, 5]:
			shops += 1
			game.state = "shop"
			game.purchased.clear()
			var element: String = PROGRESSION.ELEMENTS[0]
			for candidate in PROGRESSION.ELEMENTS:
				if int(game.player.enchantments.get(candidate, 0)) < int(game.player.enchantments.get(element, 0)):
					element = candidate
			game.set_shop_stock(element)
			for index in [2, 1]:
				if game.can_buy(index):
					check(game.buy_item(index), "Legal shop inventory spends previously earned scrap")
					purchases += 1
		else:
			# These are the existing non-elite completion/kill rewards. All
			# encounters are accounted for; no free currency is inserted.
			var count := 3 if depth == 1 else mini(3 + depth * 2, 12)
			game.scrap += 40 + depth * 5 + (20 if local_room == 6 else count * 6)
			var selected: Dictionary = {}
			for stat in order:
				if PROGRESSION.can_apply({"stat": stat}, game.player):
					selected = {"stat": stat}
					break
			check(not selected.is_empty(), "Shop-heavy legal reward order always retains a useful upgrade")
			game.apply_boon(selected)
		var offers := PROGRESSION.offers(game.rng, false, game.player.enchantments, game.team(), 2)
		check(offers.size() >= 1 and offers.size() <= 3, "Shop-heavy late-game offers stay nonempty")
		check(offers.all(func(boon): return PROGRESSION.can_apply(boon, game.player)), "Shop-heavy pool excludes saturated effects")
		smallest_pool = mini(smallest_pool, offers.size())
	check(shops == 10 and purchases >= 10 and smallest_pool <= 2, "Legal 10-shop economics can reach fewer than three valid blessings")
	measurements.append({"fixture": "Constructed legal reward order and unchanged shop/room economy", "shops": shops, "purchases": purchases, "smallest_offer_pool": smallest_pool, "remaining_scrap": game.scrap})
	game.profile.upgrades = {"vitality": 0, "power": 0, "recovery": 0}

func element_cases() -> void:
	var enemy = await reset_case(30, "boss")
	# Element samples need enough room to observe effects without ending combat;
	# all damage goes through the same live player/enemy methods as normal play.
	for tier in range(1, 4):
		enemy.frozen = 0
		enemy.ice_frozen_left = 0
		enemy.ice_guard_left = 0
		enemy.chill_stacks = 0
		game.player.enchantments = {"ice": tier}
		for i in range(3): game.player.weapon_hit(enemy, 1, Vector2.ZERO)
		check(is_equal_approx(enemy.ice_frozen_left, 0.6 + 0.12 * (tier - 1)), "Ice rank %d produces its actual guardian freeze duration" % tier)
		enemy.ice_frozen_left = 0.01
		enemy.frozen = 0.01
		for i in range(12): game.player.weapon_hit(enemy, 1, Vector2.ZERO)
		check(is_equal_approx(enemy.ice_frozen_left, 0.01), "Rapid repeated hits cannot refresh guardian ice inside its recovery window")
		enemy._physics_process(2.21)
		for i in range(3): game.player.weapon_hit(enemy, 1, Vector2.ZERO)
		check(enemy.ice_frozen_left > 0.59, "Guardian can freeze again after the full recovery window")
	var frozen_durations: Array = []
	for tier in range(1, 4):
		enemy.shock_guard = 0
		enemy.frozen = 0
		game.player.enchantments = {"shock": tier}
		var before: float = enemy.hp
		game.player.weapon_hit(enemy, 20, Vector2.ZERO)
		var first: float = before - enemy.hp
		frozen_durations.append(enemy.frozen)
		before = enemy.hp
		game.player.weapon_hit(enemy, 20, Vector2.ZERO)
		check(is_equal_approx(before - enemy.hp, 20), "Shock's per-target guard rejects repeat proc damage")
		check((first == 20 if tier == 1 else first > 20), "Higher shock ranks add real damage while rank one preserves its control baseline")
	check(frozen_durations[0] < frozen_durations[1] and frozen_durations[1] < frozen_durations[2], "Shock ranks increase actual control duration")
	enemy = await reset_case(30, "boss", "frost")
	game.player.enchantments = {"ice": 1}
	for i in range(3): game.player.weapon_hit(enemy, 1, Vector2.ZERO, "ice")
	check(enemy.chill_stacks == 0 and is_equal_approx(enemy.ice_frozen_left, 0.72), "Matching innate ice and rank-one rune apply one stronger stack per hit")
	for tag in ["fire", "poison"]:
		game.player.enchantments = {}
		enemy.burn_damage = 0
		enemy.poison_damage = 0
		game.player.weapon_hit(enemy, 20, Vector2.ZERO, tag)
		var baseline: float = enemy.burn_damage if tag == "fire" else enemy.poison_damage
		game.player.enchantments = {tag: 1}
		game.player.weapon_hit(enemy, 20, Vector2.ZERO, tag)
		var upgraded: float = enemy.burn_damage if tag == "fire" else enemy.poison_damage
		check(is_equal_approx(upgraded, baseline * 1.35), "First matching %s rune improves the existing damage effect by 35 percent" % tag)
	for tier in range(1, 4):
		enemy = await reset_case(30, "boss")
		game.player.hp = 40
		game.player.enchantments = {"leech": tier}
		game.player.leech_available = PROGRESSION.leech_capacity(tier)
		for i in range(7): game.player.weapon_hit(enemy, 45, Vector2.ZERO)
		var capacity: float = PROGRESSION.leech_capacity(tier)
		check(is_equal_approx(game.player.hp, 40 + capacity), "Seven simultaneous pellets cannot multiply rank-%d healing beyond its reserve" % tier)
		for i in range(60): game.player._physics_process(1.0 / 60.0)
		var before: float = game.player.hp
		for i in range(7): game.player.weapon_hit(enemy, 45, Vector2.ZERO)
		check(is_equal_approx(game.player.hp - before, capacity), "One normal second refills the advertised healing budget")
	enemy = await reset_case(30, "boss", "blade", false, 1)
	game.player.hp = 40
	game.player.enchantments = {"leech": 3}
	for i in range(7): game.player.weapon_hit(enemy, 45, Vector2.ZERO)
	check(game.player.hp == 68, "Legacy campaign preserves its original per-hit leech")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	game.narrative_enabled = false
	root.add_child(game)
	await process_frame
	game.muted = true
	game.set_process(false)
	# Same 1/60 simulation step with shorter wall time; no combat stats are sped up.
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4
	await progression_cases()
	await shop_heavy_cases()
	await element_cases()
	var blade_base := await firing_probe(1, "stalker", "blade", 0)
	var blade_blessed := await firing_probe(1, "stalker", "blade", 1)
	check(blade_blessed.seconds < blade_base.seconds * 0.75, "First damage boon changes the opening blade kill from three hits to two")
	var rifle_base := await firing_probe(1, "stalker", "rifle", 0)
	var rifle_blessed := await firing_probe(1, "stalker", "rifle", 1)
	check(rifle_blessed.seconds < rifle_base.seconds * 0.85, "First damage boon noticeably reduces actual rifle time to kill")
	for depth in [6, 12, 18, 24, 30]:
		var index: int = CHAPTERS.number(depth)
		var probe := await firing_probe(depth, "boss" if depth == 30 else "warden", "rifle", 2 + index)
		check(probe.seconds >= 8 and probe.seconds <= 24, "Uninterrupted region-%d guardian firing stays inside the 8–24 second diagnostic band" % (index + 1))
	var capped := await firing_probe(30, "boss", "rifle", 29)
	check(capped.seconds >= 9, "Even maximum primary-weapon growth leaves time for the final guardian's attack cycle")
	var partnered := await firing_probe(30, "boss", "rifle", 6, true)
	check(partnered.target_hp == 4600 * 1.6, "Co-op keeps its authored 1.6 health multiplier")
	var solo: Dictionary = measurements.filter(func(row): return row.get("depth", 0) == 30 and row.get("damage_boons", 0) == 6 and row.get("players", 0) == 1)[0]
	check(partnered.seconds / solo.seconds > 0.7 and partnered.seconds / solo.seconds < 0.9, "Two equal firing players gain a bounded clear-speed advantage")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/qa"))
	var file := FileAccess.open("res://builds/qa/balance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"method": "Stationary-target combat fixture; real attacks, unmodified campaign HP, normal cooldowns; not human acceptance", "checks": checks, "failures": failures, "measurements": measurements}, "\t"))
	file.close()
	for result in measurements: print(JSON.stringify(result))
	game.queue_free()
	await process_frame
	print("ABYSS BALANCE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
