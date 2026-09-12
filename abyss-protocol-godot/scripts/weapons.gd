extends RefCounted
## The original 18 base forms, with native combat definitions and readable roles.
## Damage values multiply the android's run damage; cooldowns are seconds.

const FORMS := [
	{"id": "blade", "name": "刀锋", "family": "MELEE", "mode": "melee", "color": "aaf6ff", "cooldown": 0.32, "damage": 1.0, "reach": 105.0, "arc": 1.4, "force": 230.0, "description": "均衡的扇形斩击。\n适合应对多数战况。"},
	{"id": "lance", "name": "长枪", "family": "MELEE", "mode": "melee", "color": "ffd27a", "cooldown": 0.39, "damage": 1.1, "reach": 178.0, "arc": 0.3, "force": 280.0, "description": "远距离的精准突刺。\n把敌人引到同一条直线上。"},
	{"id": "maul", "name": "重锤", "family": "MELEE", "mode": "melee", "color": "ff8866", "cooldown": 0.6, "damage": 1.9, "reach": 98.0, "arc": 1.5, "force": 500.0, "description": "缓慢而沉重的打击。\n造成强力击退和短暂硬直。"},
	{"id": "fang", "name": "双牙", "family": "MELEE", "mode": "melee", "color": "ff5fa8", "cooldown": 0.18, "damage": 0.6, "reach": 83.0, "arc": 1.2, "force": 100.0, "description": "快速挥动的一对短刃。\n连续第三击造成双倍伤害。"},
	{"id": "arc", "name": "电弧", "family": "ENERGY", "mode": "melee", "color": "7fe9ff", "cooldown": 0.42, "damage": 0.85, "reach": 155.0, "arc": 1.7, "force": 100.0, "element": "shock", "description": "释放宽阔的能量扫击。\n可连锁电击额外两个目标。"},
	{"id": "grav", "name": "引力锤", "family": "ENERGY", "mode": "gravity", "color": "b98cff", "cooldown": 1.1, "damage": 1.65, "description": "放置微型引力井。\n吸引附近敌人后引爆。"},
	{"id": "glaive", "name": "回旋刃", "family": "MELEE", "mode": "glaive", "color": "7fffd0", "cooldown": 0.4, "damage": 0.85, "speed": 560.0, "description": "投出会返回的旋转飞刃。\n去程与回程各命中一次。"},
	{"id": "whip", "name": "锁链鞭", "family": "MELEE", "mode": "melee", "color": "ffcf5e", "cooldown": 0.4, "damage": 0.85, "reach": 225.0, "arc": 0.45, "force": -280.0, "description": "远距离挥出锁链。\n把命中的敌人拉向自己。"},
	{"id": "prism", "name": "棱光刃", "family": "ENERGY", "mode": "melee", "color": "9d7bff", "cooldown": 0.36, "damage": 0.65, "reach": 92.0, "arc": 1.0, "force": 150.0, "description": "短斩同时释放能量束。\n贯穿前方一列目标。"},
	{"id": "ember", "name": "火焰法杖", "family": "MAGIC", "mode": "projectile", "color": "ff7a3c", "cooldown": 0.6, "damage": 0.9, "speed": 440.0, "visual": "orb", "element": "fire", "explosion": 105.0, "description": "发射爆炸火球。\n命中后留下短暂燃烧区域。"},
	{"id": "frost", "name": "冰霜法杖", "family": "MAGIC", "mode": "projectile", "color": "7fd8ff", "cooldown": 0.44, "damage": 0.85, "speed": 620.0, "visual": "orb", "element": "ice", "pierce": 2, "description": "发射贯穿冰弹。\n连续三次冰霜命中冻结敌人。"},
	{"id": "storm", "name": "闪电法杖", "family": "MAGIC", "mode": "chain", "color": "ffe24a", "cooldown": 0.6, "damage": 1.0, "reach": 440.0, "element": "shock", "description": "向瞄准方向释放闪电。\n最多连锁四个不同目标。"},
	{"id": "rifle", "name": "速射枪", "family": "FIREARMS", "mode": "projectile", "color": "cfd8e6", "cooldown": 0.11, "damage": 0.32, "speed": 1150.0, "visual": "bullet", "spread": 0.035, "description": "按住即可持续射击。\n后坐力较低，适合持续压制。"},
	{"id": "scatter", "name": "霰弹枪", "family": "FIREARMS", "mode": "projectile", "color": "ffb86b", "cooldown": 0.68, "damage": 0.3, "speed": 930.0, "visual": "bullet", "pellets": 7, "spread": 0.46, "life": 0.48, "description": "扇形发射七枚散弹。\n近距离命中更多弹丸。"},
	{"id": "rail", "name": "轨道炮", "family": "FIREARMS", "mode": "projectile", "color": "7fd0ff", "cooldown": 0.7, "damage": 1.0, "speed": 1600.0, "visual": "rail", "pierce": 8, "charge": 0.8, "description": "按住蓄力，松开射击。\n发射高伤害贯穿轨道弹。"},
	{"id": "qbow", "name": "速射弓", "family": "ARCHERY", "mode": "projectile", "color": "bfe89a", "cooldown": 0.24, "damage": 0.8, "speed": 780.0, "visual": "arrow", "description": "快速而精准的箭矢。\n按住即可连续射箭。"},
	{"id": "lbow", "name": "长弓", "family": "ARCHERY", "mode": "projectile", "color": "d8c27a", "cooldown": 0.45, "damage": 1.0, "speed": 920.0, "visual": "arrow", "charge": 0.9, "description": "按住拉弓，松开释放重箭。\n满蓄力可贯穿四个目标。"},
	{"id": "sbow", "name": "风暴弓", "family": "ARCHERY", "mode": "projectile", "color": "8fd2ff", "cooldown": 0.55, "damage": 0.6, "speed": 740.0, "visual": "arrow", "pellets": 3, "spread": 0.24, "description": "同时射出三支箭。\n覆盖更宽的攻击区域。"},
]

static func find(id: String) -> Dictionary:
	for form in FORMS:
		if form.id == id:
			return form
	return FORMS[0]

static func exists(id: String) -> bool:
	return FORMS.any(func(form): return form.id == id)

static func family_label(family: String) -> String:
	return {"MELEE": "近战", "ENERGY": "能量", "MAGIC": "法术", "FIREARMS": "枪械", "ARCHERY": "弓术"}.get(family, "武器")
