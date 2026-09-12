extends RefCounted

const UPGRADES := [
	{"id": "vitality", "name": "强化机体", "description": "每级增加十点初始最大耐久。", "base_cost": 20},
	{"id": "power", "name": "武器校准", "description": "每级增加百分之五初始武器伤害。", "base_cost": 25},
	{"id": "recovery", "name": "能量回收", "description": "每级增加两点每秒能量回复。", "base_cost": 20},
]
const ELEMENTS := ["fire", "ice", "shock", "poison", "leech", "execute"]
const BOONS := [
	{"name": "锋刃增幅", "tag": "攻击强化", "description": "武器伤害提高百分之二十五。\n武器主攻击与等离子弹均生效。", "stat": "damage"},
	{"name": "修复矩阵", "tag": "生存强化", "description": "最大耐久增加二十五点。\n立即恢复四十五点耐久。", "stat": "health"},
	{"name": "相位疾行", "tag": "机动强化", "description": "移动速度提高百分之十。\n冲刺冷却缩短百分之十五。", "stat": "speed"},
	{"name": "余烬符文", "tag": "元素 · 火焰", "description": "武器命中会点燃敌人。\n火焰能与冰冻及毒素产生联动。", "stat": "fire"},
	{"name": "寒霜符文", "tag": "元素 · 冰霜", "description": "武器命中会叠加寒冷。\n累积三层后冻结目标。", "stat": "ice"},
	{"name": "伏特符文", "tag": "元素 · 电击", "description": "武器命中造成短暂硬直。\n每个目标有独立的电击间隔。", "stat": "shock"},
	{"name": "蚀毒符文", "tag": "元素 · 毒素", "description": "命中叠加持续毒素伤害。\n每个目标最多累积六层。", "stat": "poison"},
	{"name": "虹吸符文", "tag": "元素 · 汲取", "description": "武器伤害能恢复自身耐久。\n每次命中的回复量有上限。", "stat": "leech"},
	{"name": "终结符文", "tag": "元素 · 终结", "description": "对耐久低于百分之三十的目标，\n武器伤害额外提高百分之五十。", "stat": "execute"},
]

# Caps apply to new gains only. A restored legacy value is never reduced.
const MAX_DAMAGE := 156.0
const MAX_HEALTH := 350.0
const MAX_SPEED := 420.0
const MIN_DASH_RECHARGE := 0.45
const MAX_DAMAGE_GAIN := 13.0
const ELEMENT_LABELS := {"fire": "火焰", "ice": "冰霜", "shock": "电击", "poison": "毒素", "leech": "汲取", "execute": "终结"}

static func effects(boon: Dictionary, member, version := 2) -> Dictionary:
	var result: Dictionary = {}
	match boon.stat:
		"damage", "tuning":
			var fraction := 0.25 if boon.stat == "damage" else 0.15
			var gain: float = member.damage * fraction
			if version >= 2:
				gain = maxf(0.0, minf(gain, minf(MAX_DAMAGE_GAIN, MAX_DAMAGE - member.damage)))
			result.damage = gain
		"health":
			var gain := 25.0 if version < 2 else maxf(0.0, minf(25.0, MAX_HEALTH - member.max_hp))
			result.max_hp = gain
			result.hp = maxf(0.0, minf(45.0, member.max_hp + gain - member.hp))
		"speed":
			result.move_speed = member.move_speed * 0.1 if version < 2 else maxf(0.0, minf(member.move_speed * 0.1, MAX_SPEED - member.move_speed))
			result.dash_reduction = maxf(0.0, member.dash_recharge - maxf(0.3 if version < 2 else MIN_DASH_RECHARGE, member.dash_recharge * 0.85))
		_:
			if boon.stat in ELEMENTS:
				result.rune = maxi(0, 3 - int(member.enchantments.get(boon.stat, 0))) > 0
	return result

static func can_apply(boon: Dictionary, member, version := 2) -> bool:
	var changes := effects(boon, member, version)
	if version >= 2 and changes.has("damage"):
		return changes.damage >= maxf(3.0, member.damage * 0.06)
	if version >= 2 and boon.stat == "speed":
		return changes.move_speed >= member.move_speed * 0.05 or changes.dash_reduction >= member.dash_recharge * 0.05
	return changes.values().any(func(value): return float(value) > 0.00001)

static func apply(boon: Dictionary, member, version := 2) -> void:
	var changes := effects(boon, member, version)
	for stat in ["damage", "max_hp", "hp", "move_speed"]:
		if changes.has(stat): member.set(stat, member.get(stat) + changes[stat])
	if changes.has("dash_reduction"):
		member.dash_recharge -= changes.dash_reduction
	if changes.get("rune", false):
		member.enchantments[boon.stat] = mini(3, int(member.enchantments.get(boon.stat, 0)) + 1)

static func describe(boon: Dictionary, member, version := 2) -> String:
	if version < 2: return boon.get("description", "")
	var changes := effects(boon, member, version)
	match boon.stat:
		"damage", "tuning":
			if changes.damage <= 0: return "武器增幅已达上限。"
			return "武器伤害 %.1f → %.1f（+%d%%）。\n主武器与等离子弹同步增强。" % [member.damage, member.damage + changes.damage, roundi(changes.damage / member.damage * 100)]
		"health":
			return "最大耐久 %d → %d。\n立即恢复 %d 点耐久。" % [member.max_hp, member.max_hp + changes.max_hp, changes.hp]
		"speed":
			return "移动速度 %d → %d。\n冲刺冷却 %.2f → %.2f 秒。" % [member.move_speed, member.move_speed + changes.move_speed, member.dash_recharge, member.dash_recharge - changes.dash_reduction]
		_:
			var level := mini(3, int(member.enchantments.get(boon.stat, 0)) + 1)
			var effective := effective_element_level(level, member.weapon.definition.get("element", "") == boon.stat, version)
			var detail := ""
			match boon.stat:
				"fire": detail = "命中燃烧 2.5 秒。\n每 0.5 秒造成 %.1f%% 命中伤害。\n可引爆冰冻与毒素。" % (12.0 * element_power(effective))
				"ice": detail = "三次命中冻结 %.2f 秒。\n首领冻结 %.2f 秒。\n首领每 2.2 秒最多冻结一次。" % [ice_duration(effective, false), ice_duration(effective, true)]
				"shock": detail = "命中硬直 %.2f 秒，首领减半以上。\n每目标间隔 0.8 秒。\n额外造成 %.1f%% 命中伤害。" % [shock_duration(effective, false), shock_fraction(effective) * element_power(effective) * 100.0]
				"poison": detail = "毒素持续 4 秒，最多六层。\n每层每 0.5 秒造成\n%.1f%% 命中伤害。" % (4.0 * element_power(effective))
				"leech": detail = "命中回复实际伤害的 %d%%。\n连击最多立即回复 %.0f 点。\n持续命中每秒再回复 %.0f 点。" % [level * 6, leech_capacity(level), leech_capacity(level)]
				"execute": detail = "对耐久低于 30%% 的目标，\n武器伤害额外提高 %d%%。" % (50 + (level - 1) * 20)
			return detail

static func effective_element_level(rune_level: int, innate: bool, version := 2) -> int:
	return rune_level + int(innate) if version >= 2 else maxi(rune_level, int(innate))

static func element_power(level: int) -> float:
	return 1.0 + 0.35 * (clampi(level, 1, 4) - 1)

static func ice_duration(level: int, guardian: bool) -> float:
	return (0.6 + 0.12 * (level - 1)) if guardian else (1.8 + 0.45 * (level - 1))

static func shock_duration(level: int, guardian: bool) -> float:
	return (0.1 + 0.025 * (level - 1)) if guardian else (0.22 + 0.06 * (level - 1))

static func shock_fraction(level: int) -> float:
	return 0.18 * maxf(0.0, level - 1)

static func leech_capacity(level: int) -> float:
	return 2.0 + 2.0 * clampi(level, 1, 3)

static func eligible(boon: Dictionary, enchants: Dictionary, members: Array, version: int) -> bool:
	if not members.is_empty():
		return members.any(func(member): return can_apply(boon, member, version))
	return int(enchants.get(boon.stat, 0)) < 3

static func offers(rng: RandomNumberGenerator, first_room: bool, enchants: Dictionary, members: Array = [], version := 1) -> Array:
	var pool: Array = BOONS.filter(func(boon): return eligible(boon, enchants, members, version))
	var result: Array = []
	if first_room:
		for boon in BOONS.slice(0, 3):
			if boon in pool:
				result.append(boon)
				pool.erase(boon)
	while result.size() < 3 and not pool.is_empty():
		var index := rng.randi_range(0, pool.size() - 1)
		result.append(pool[index])
		pool.remove_at(index)
	return result

static func rune(id: String) -> Dictionary:
	for boon in BOONS:
		if boon.stat == id:
			return boon
	return {}

static func promised_offers(rng: RandomNumberGenerator, first_room: bool, enchants: Dictionary, promise: String, members: Array = [], version := 1) -> Array:
	var result := offers(rng, first_room, enchants, members, version)
	var matching: Array = []
	for boon in BOONS:
		if (boon.stat == promise or (promise == "element" and boon.stat in ELEMENTS)) and eligible(boon, enchants, members, version):
			matching.append(boon)
	if not matching.is_empty() and not result.any(func(boon): return boon in matching):
		result[0] = matching[rng.randi_range(0, matching.size() - 1)]
	return result
