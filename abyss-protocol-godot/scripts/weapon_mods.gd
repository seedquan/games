extends RefCounted
## One mutually exclusive, per-run refit. Definitions are copies, never catalog edits.
const WEAPONS = preload("res://scripts/weapons.gd")
const IDS := ["mod_focus", "mod_flow"]
const CARDS := [
	{"stat": "mod_focus", "name": "改装方案 一", "tag": "武器改装 · 本局限选一次", "description": "重塑当前武器的攻击方式。"},
	{"stat": "mod_flow", "name": "改装方案 二", "tag": "武器改装 · 本局限选一次", "description": "重塑当前武器的攻击方式。"},
]

static func definition(weapon: String, id: String, campaign_version := 2) -> Dictionary:
	var form: Dictionary = WEAPONS.find(weapon).duplicate(true)
	# Campaign tuning changes the primary hit, never saved actor stats or skills.
	if campaign_version < 2: return form
	if form.mode == "gravity": form.damage = 2.8
	if form.mode == "glaive":
		form.damage = 1.4
		form.manual_recall = true
		form.description = "投出旋转飞刃，去回程各命中一次。\n出手冷却后再按攻击，可提前回收。"
	if id not in IDS: return form
	var focus := id == "mod_focus"
	match form.mode:
		"melee":
			form.reach *= 1.4 if focus else 0.8
			form.arc = form.arc * 0.65 if focus else maxf(1.8, form.arc)
			if not focus: form.damage *= 0.85
		"projectile":
			if focus:
				if form.has("charge"):
					form.charge *= 0.65
					form.damage *= 0.9
				else:
					form.pierce = int(form.get("pierce", 0)) + 2
					form.spread = float(form.get("spread", 0.0)) * 0.4
					form.damage *= 0.85
			else:
				var pellets := int(form.get("pellets", 1))
				form.pellets = pellets + 2
				form.spread = maxf(0.3, float(form.get("spread", 0.0)) * 1.3)
				form.outer_multiplier = 0.35
				form.cooldown *= 1.2
		"glaive":
			form.return_after = 0.75 if focus else 0.25
			form.return_multiplier = 3.0 if focus else 1.0
			form.charge_return = focus
			form.damage *= 0.75
		"chain":
			form.chain_count = 2 if focus else 6
			form.chain_range = 280.0 if focus else 240.0
			form.reach = 600.0 if focus else 350.0
			form.damage *= 1.35 if focus else 0.8
		"gravity":
			form.field_radius = 115.0 if focus else 235.0
			form.field_duration = 0.35 if focus else 1.35
			form.cooldown = 0.8 if focus else 1.5
			form.damage *= 1.0 if focus else 0.9
	form.modification = id
	# The build page must not repeat base-form geometry after the refit.
	form.description = details(weapon, id)
	return form

static func title(weapon: String, id: String) -> String:
	var base := WEAPONS.find(weapon)
	var focus := id == "mod_focus"
	match base.mode:
		"melee": return "延展刃" if focus else "回身扫击"
		"projectile": return ("速蓄组件" if base.has("charge") else "穿透组件") if focus else "分裂齐射"
		"glaive": return "重返飞刃" if focus else "短程快返"
		"chain": return "远距双链" if focus else "六路电网"
		"gravity": return "速爆引力井" if focus else "长时聚拢"
	return "未改装"

static func details(weapon: String, id: String) -> String:
	var base := WEAPONS.find(weapon)
	if id not in IDS: return "尚未改装。清舱奖励可选择一项，本局不能更换。"
	var focus := id == "mod_focus"
	match base.mode:
		"melee":
			return "攻击距离 +40%，斩击角度收窄 35%。\n把敌人引到前方，保持距离出手。" if focus else "斩击扩至 206°，可扫到侧后方。\n攻击距离 −20%，每击伤害 −15%。"
		"projectile":
			if focus:
				return "蓄力时间 −35%，每枚伤害 −10%。\n更快松手，抓住短暂空隙。" if base.has("charge") else "额外贯穿两名敌人，散布收窄 60%。\n每枚伤害 −15%；掩体仍会挡住弹体。"
			return "每次 %d → %d 枚，弹道向两侧展开。\n原弹伤害保留；两侧弹各为原弹的 35%%。\n攻击间隔 +20%%。" % [int(base.get("pellets", 1)), int(base.get("pellets", 1)) + 2]
		"glaive":
			return "去程蓄势，0.75 秒后自动返回，回程最高三倍伤害。\n提前回收更快、威力更低；去程伤害 −25%。" if focus else "飞行 0.25 秒就返回，缩短等待。\n去回程伤害各 −25%，投掷距离减半。"
		"chain":
			return "起手距离 600，连锁距离 280。\n每击伤害 +35%，最多只命中两敌。" if focus else "最多连锁六敌，连锁距离 240。\n起手距离缩至 350，每击伤害 −20%。"
		"gravity":
			return "0.35 秒引爆，攻击间隔 0.8 秒。\n范围缩至 115，聚怪时间更短。" if focus else "范围增至 235，聚拢 1.35 秒再引爆。\n攻击间隔 1.5 秒，伤害 −10%。"
	return ""

static func preview(member, id: String) -> String:
	if not member.weapon_mod.is_empty():
		return "已装配「%s」；本局不能更换。" % title(member.weapon.definition.id, member.weapon_mod)
	return title(member.weapon.definition.id, id) + "\n" + details(member.weapon.definition.id, id)
