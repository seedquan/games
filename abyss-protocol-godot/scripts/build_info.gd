extends RefCounted
## Read-only combat presentation. Never applies an upgrade to preview it.

const PROGRESSION = preload("res://scripts/progression.gd")

static func attack_values(definition: Dictionary, damage: float) -> Dictionary:
	var hit := damage * float(definition.damage)
	return {"hit": hit, "quick": hit * 0.65, "charged": hit * 3.1,
		"pellets": int(definition.get("pellets", 1))}

static func attack_text(definition: Dictionary, damage: float) -> String:
	var values := attack_values(definition, damage)
	if definition.has("charge"):
		return "速放 %.1f / 满蓄力 %.1f\n蓄力 %.2f 秒 · 射击后冷却 %.2f 秒" % [values.quick, values.charged, definition.charge, definition.cooldown]
	if values.pellets > 1:
		return "每枚 %.1f × %d 枚\n全部命中 %.1f · 攻击间隔 %.2f 秒" % [values.hit, values.pellets, values.hit * values.pellets, definition.cooldown]
	var unit := "引爆" if definition.mode == "gravity" else "单次命中"
	var extra := ""
	match definition.id:
		"fang": extra = "\n连续第三击 %.1f" % (values.hit * 2)
		"prism": extra = "\n另发贯穿光束 %.1f" % (values.hit * 0.75)
		"arc": extra = "\n额外连锁两名敌人，各 %.1f" % (values.hit * 0.6)
		"storm": extra = "\n额外连锁三名敌人，各 %.1f" % (values.hit * 0.75)
		"glaive": extra = "\n去程、回程各一次；收回前不能再投掷"
	return "%s %.1f · 攻击间隔 %.2f 秒%s" % [unit, values.hit, definition.cooldown, extra]

static func damage_comparison(member, gain: float) -> String:
	var definition: Dictionary = member.weapon.definition
	var before := attack_values(definition, member.damage)
	var after := attack_values(definition, member.damage + gain)
	if definition.has("charge"):
		return "满蓄力 %.1f → %.1f" % [before.charged, after.charged]
	if before.pellets > 1:
		return "每枚 %.1f → %.1f（每次 %d 枚）" % [before.hit, after.hit, before.pellets]
	return "单次命中 %.1f → %.1f" % [before.hit, after.hit]

static func element_detail(id: String, rank: int, innate: bool, version: int) -> String:
	var level := PROGRESSION.effective_element_level(rank, innate, version)
	if level <= 0: return "尚未获得"
	var power := PROGRESSION.element_power(level)
	var control_level := level if version >= 2 else 1
	match id:
		"fire": return "燃烧 2.5 秒，每 0.5 秒造成 %.1f%% 命中伤害。" % (12 * power)
		"ice": return "三次冰霜命中冻结 %.2f 秒，首领 %.2f 秒。%s" % [PROGRESSION.ice_duration(control_level, false), PROGRESSION.ice_duration(control_level, true), "首领冻结间隔 2.2 秒。" if version >= 2 else ""]
		"shock": return "硬直 %.2f 秒，首领 %.3f 秒；每目标间隔 0.8 秒。额外伤害 %.1f%%。" % [PROGRESSION.shock_duration(control_level, false), PROGRESSION.shock_duration(control_level, true), PROGRESSION.shock_fraction(level) * power * 100 if version >= 2 else 0.0]
		"poison": return "毒素持续 4 秒，最多六层；每层每 0.5 秒造成 %.1f%% 命中伤害。" % (4 * power)
		"leech": return "回复实际伤害的 %d%%；%s" % [rank * 6, "连击回复预算 %.0f 点，每秒补充 %.0f 点。" % [PROGRESSION.leech_capacity(rank), PROGRESSION.leech_capacity(rank)] if version >= 2 else "每次命中最多回复 4 点。"]
		"execute": return "敌人耐久低于 30%% 时，武器伤害额外提高 %d%%。" % (50 + (rank - 1) * 20)
	return ""

static func element_heading(id: String, rank: int, innate: bool, version: int) -> String:
	var source := "符文 %d / 3 级" % rank
	if innate:
		source += " + 武器自带" if version >= 2 else " · 武器自带（取较高等级）"
	return "%s / %s" % [PROGRESSION.ELEMENT_LABELS[id], source]

static func rune_comparison(id: String, rank: int, innate: bool, version: int) -> String:
	var next := mini(3, rank + 1)
	var levels := [PROGRESSION.effective_element_level(rank, innate, version), PROGRESSION.effective_element_level(next, innate, version)]
	var first: Array[float] = []
	var second: Array[float] = []
	for i in range(2):
		var level: int = levels[i]
		var rune_rank := rank if i == 0 else next
		var power := PROGRESSION.element_power(level) if level > 0 else 0.0
		var control := level if version >= 2 else 1
		match id:
			"fire": first.append(12 * power)
			"poison": first.append(4 * power)
			"ice":
				first.append(PROGRESSION.ice_duration(control, false) if level > 0 else 0.0)
				second.append(PROGRESSION.ice_duration(control, true) if level > 0 else 0.0)
			"shock":
				first.append(PROGRESSION.shock_duration(control, false) if level > 0 else 0.0)
				second.append(PROGRESSION.shock_fraction(level) * power * 100 if version >= 2 else 0.0)
			"leech":
				first.append(rune_rank * 6.0)
				second.append((PROGRESSION.leech_capacity(rune_rank) if version >= 2 else 4.0) if rune_rank > 0 else 0.0)
			"execute": first.append(50.0 + (rune_rank - 1) * 20.0 if rune_rank > 0 else 0.0)
	match id:
		"fire": return "燃烧每跳 %.1f%% → %.1f%%\n每 0.5 秒结算，持续 2.5 秒。" % first
		"poison": return "每层毒伤 %.1f%% → %.1f%%\n每 0.5 秒结算，最多六层。" % first
		"ice": return "冻结 %.2f → %.2f 秒\n首领 %.2f → %.2f 秒" % (first + second)
		"shock": return "硬直 %.2f → %.2f 秒\n额外伤害 %.1f%% → %.1f%%" % (first + second)
		"leech": return "伤害吸取 %.0f%% → %.0f%%\n%s %.0f → %.0f 点" % [first[0], first[1], "回复预算" if version >= 2 else "每击上限", second[0], second[1]]
		"execute": return "目标耐久低于 30%% 时\n增伤 %.0f%% → %.0f%%" % first
	return ""

static func synergies(member) -> Array[String]:
	var active: Dictionary = member.enchantments.duplicate()
	var innate: String = member.weapon.definition.get("element", "")
	if not innate.is_empty(): active[innate] = 1
	var result: Array[String] = []
	var modern: bool = member.game.campaign_version >= 2
	if active.get("fire", 0) > 0:
		# Every build can freeze with its shared nova, even without an ice rune.
		result.append("热冲击：冻结后接火焰。解除冻结，范围 150，额外造成 70% 火焰命中伤害。" if modern else "热冲击：先用冰冻新星或冰霜冻结，再用火焰命中，解除冻结并造成额外伤害。")
		if active.get("poison", 0) > 0:
			result.append("毒素爆燃：至少三层毒后接火焰。消耗毒层，范围 185，每层造成 18% 火焰命中伤害。" if modern else "毒素爆燃：火焰命中会消耗目标已有毒层，层数越多，爆燃越强。")
	elif modern and (active.get("ice", 0) > 0 or active.get("poison", 0) > 0):
		result.append("联动机会：获得火焰，或让火焰队友引爆你冻结、叠毒的敌人。冻结触发热冲击，三层以上毒素触发爆燃。")
	if modern and active.get("fire", 0) > 0:
		result.append("队友可接力，引力井可先聚怪。爆发不伤友方，实体掩体可阻挡。")
	if result.is_empty(): result.append("完美闪避与成功弹反可短暂提高主武器伤害 50%。抓住敌人攻击前摇反击。")
	return result

static func has_reaction(member) -> bool:
	return member.game.campaign_version >= 2 and (["fire", "ice", "poison"].any(func(id): return member.enchantments.get(id, 0) > 0 or member.weapon.definition.get("element", "") == id))

static func reaction_hint(id: String, version: int) -> String:
	if version < 2: return ""
	match id:
		"fire": return "冰冻 + 火焰 → 范围热冲击"
		"ice": return "冻结后接火焰 → 碎冰波及邻敌"
		"poison": return "三层毒 + 火焰 → 范围爆燃"
	return ""
