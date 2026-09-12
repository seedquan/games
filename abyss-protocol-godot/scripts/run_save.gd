extends RefCounted
## Safe-point recipes contain only data, regenerated against current game definitions.

const ROOMS = preload("res://scripts/rooms.gd")
const PROGRESSION = preload("res://scripts/progression.gd")
const WEAPONS = preload("res://scripts/weapons.gd")
const STORY = preload("res://scripts/story.gd")
const STATS := {
	"hp": [0.01, 1000.0], "max_hp": [1.0, 1000.0], "energy": [0.0, 100.0],
	"energy_regen": [0.0, 100.0], "damage": [1.0, 100000.0], "move_speed": [1.0, 2000.0],
	"dash_recharge": [0.1, 10.0], "dash_cooldown": [0.0, 20.0], "slash_cooldown": [0.0, 20.0],
	"bolt_cooldown": [0.0, 20.0], "freeze_cooldown": [0.0, 20.0], "parry_cooldown": [0.0, 20.0],
}
const STATES := ["playing", "story", "reward", "route", "shop", "rest"]

static func room_recipe(data: Dictionary) -> Dictionary:
	return {"depth": data.depth, "kind": data.kind, "generation_state": data.generation_state, "generator": data.get("generator", 1)}

static func rebuild_room(recipe: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.state = recipe.generation_state
	return ROOMS.generate(recipe.depth, recipe.kind, rng, recipe.get("generator", 1))

static func capture(game) -> Dictionary:
	var stats: Dictionary = {}
	for field in STATS:
		stats[field] = game.player.get(field)
	var routes: Array = []
	for data in game.route_choices:
		routes.append(room_recipe(data))
	var boons: Array[String] = []
	for boon in game.boon_choices:
		boons.append(boon.stat)
	var stock: Array[String] = []
	for item in game.shop_stock:
		stock.append(item.id)
	var saved := {
		"campaign": game.campaign_version,
		"version": 2 if game.coop.enabled else 1, "state": game.state, "room": room_recipe(game.room_data),
		"weapon": game.player.weapon.definition.id, "stats": stats, "enchantments": game.player.enchantments.duplicate(),
		"run_seed": game.run_seed, "rng_state": game.rng.state, "kills": game.kills,
		"elapsed": game.elapsed, "scrap": game.scrap, "earned_cores": game.earned_cores,
		"routes": routes, "boons": boons, "stock": stock, "purchased": game.purchased.duplicate(),
		"history": game.route_history.duplicate(), "awarded": game.room_awarded,
		"story_id": game.story_id, "story_return": game.story_return, "story_seen": game.story_seen.duplicate(),
	}

	if game.coop.enabled:
		var partner_stats: Dictionary = {}
		for field in STATS:
			partner_stats[field] = game.companion.get(field)
		saved["partner"] = {"stats": partner_stats, "weapon": game.companion.weapon.definition.id, "enchantments": game.companion.enchantments.duplicate()}
	return saved

static func member_valid(value: Variant) -> bool:
	if value is not Dictionary or value.get("weapon") is not String or not WEAPONS.exists(value.weapon):
		return false
	if value.get("stats") is not Dictionary or value.get("enchantments") is not Dictionary:
		return false
	for field in STATS:
		if not numeric(value.stats.get(field), STATS[field][0], STATS[field][1]):
			return false
	if value.stats.hp > value.stats.max_hp:
		return false
	for tag in value.enchantments:
		if tag not in PROGRESSION.ELEMENTS or not value.enchantments[tag] is int or not numeric(value.enchantments[tag], 1, 3):
			return false
	return true

static func numeric(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func recipe_valid(value: Variant) -> bool:
	if value is not Dictionary or not value.get("generation_state") is int or not value.get("depth") is int:
		return false
	if value.get("generator", 1) not in [1, ROOMS.GENERATOR] or value.get("generator", 1) is not int:
		return false
	var depth: int = value.depth
	var legacy: bool = value.get("generator", 1) == 1
	var limit := ROOMS.LEGACY.LAST_ROOM if legacy else ROOMS.LAST_ROOM
	var kinds: Array = ROOMS.LEGACY.choices(depth) if legacy else ROOMS.choices(depth)
	return depth >= 1 and depth <= limit and value.get("kind") in (["combat"] if depth == 1 else kinds)

static func string_array(value: Variant, allowed: Array, maximum: int) -> bool:
	if value is not Array or value.size() > maximum:
		return false
	for item in value:
		if item is not String or item not in allowed:
			return false
	return true

static func valid(value: Variant) -> bool:
	if value is not Dictionary or value.get("version") not in [1, 2] or value.get("state") not in STATES:
		return false
	if value.get("campaign", 1) not in [1, 2] or value.get("campaign", 1) is not int:
		return false
	var limit := ROOMS.LAST_ROOM if value.get("campaign", 1) == 2 else 12
	if value.version == 2 and not member_valid(value.get("partner")):
		return false
	if not recipe_valid(value.get("room")) or value.get("weapon") is not String or not WEAPONS.exists(value.weapon):
		return false
	if value.room.depth > limit or value.room.get("generator", 1) != value.get("campaign", 1):
		return false
	if value.get("stats") is not Dictionary or value.get("enchantments") is not Dictionary:
		return false
	for field in STATS:
		if not numeric(value.stats.get(field), STATS[field][0], STATS[field][1]):
			return false
	if value.stats.hp > value.stats.max_hp:
		return false
	for tag in value.enchantments:
		if tag not in PROGRESSION.ELEMENTS or not value.enchantments[tag] is int or not numeric(value.enchantments[tag], 1, 3):
			return false
	for field in ["run_seed", "rng_state"]:
		if not value.get(field) is int:
			return false
	for field in ["kills", "scrap", "earned_cores"]:
		if not value.get(field) is int or not numeric(value[field], 0, 1000000):
			return false
	if not numeric(value.get("elapsed"), 0, 10000000) or not value.get("awarded") is bool:
		return false
	if not string_array(value.get("history"), ROOMS.TYPES.keys(), limit) or value.history.size() != value.room.depth or value.history.back() != value.room.kind:
		return false
	if not string_array(value.get("story_seen"), STORY.BEATS.keys(), 6) or value.get("story_id") is not String or value.get("story_return") is not String:
		return false
	if value.state == "story" and (value.story_id not in STORY.BEATS or value.story_return not in ["playing", "reward", "shop", "rest"]):
		return false
	var boons: Array = []
	for boon in PROGRESSION.BOONS:
		boons.append(boon.stat)
	if not string_array(value.get("boons"), boons, 3) or not string_array(value.get("stock"), ["repair", "tuning"] + PROGRESSION.ELEMENTS, 3):
		return false
	if not string_array(value.get("purchased"), value.stock, 3):
		return false
	if value.get("routes") is not Array or value.routes.size() > 2:
		return false
	for recipe in value.routes:
		if not recipe_valid(recipe) or recipe.depth != value.room.depth + 1 or recipe.depth > limit or recipe.get("generator", 1) != value.get("campaign", 1):
			return false
	var destination: String = value.story_return if value.state == "story" else value.state
	if destination == "reward":
		var minimum := 1 if value.get("campaign", 1) >= 2 else 3
		if value.boons.size() < minimum or not value.awarded:
			return false
		if value.get("campaign", 1) >= 2:
			var distinct := {}
			for stat in value.boons:
				if distinct.has(stat): return false
				distinct[stat] = true
	if destination == "route" and value.routes.is_empty():
		return false
	if destination == "shop" and (value.stock.size() != 3 or value.stock[0] != "repair" or value.stock[1] != "tuning" or value.stock[2] not in PROGRESSION.ELEMENTS):
		return false
	if destination in ["shop", "rest"] and value.room.kind != destination:
		return false
	if destination == "playing" and (value.room.kind not in ["combat", "elite", "boss"] or value.awarded):
		return false
	return true
