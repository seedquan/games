extends RefCounted
## Seeded room assembly: layouts, spawn safety and route kinds share one contract.

const LAST_ROOM := 12
const START := Vector2(800, 650)
const LAYOUTS := [
	{"name": "接驳船坞", "cover": [Rect2(360, 320, 125, 65), Rect2(1115, 320, 125, 65), Rect2(360, 730, 125, 65), Rect2(1115, 730, 125, 65)]},
	{"name": "货运长廊", "cover": [Rect2(500, 330, 90, 230), Rect2(1010, 330, 90, 230), Rect2(660, 230, 280, 60), Rect2(650, 820, 300, 60)]},
	{"name": "冷却回廊", "cover": [Rect2(300, 270, 230, 70), Rect2(1070, 710, 230, 70), Rect2(310, 690, 110, 170), Rect2(1180, 230, 110, 170), Rect2(740, 320, 120, 100)]},
	{"name": "反应堆环廊", "cover": [Rect2(420, 320, 110, 110), Rect2(1070, 320, 110, 110), Rect2(420, 710, 110, 110), Rect2(1070, 710, 110, 110)]},
	{"name": "装配车间", "cover": [Rect2(280, 340, 180, 80), Rect2(700, 250, 200, 80), Rect2(1140, 340, 180, 80), Rect2(280, 730, 180, 80), Rect2(1140, 730, 180, 80)]},
	{"name": "数据档案室", "cover": [Rect2(400, 200, 70, 260), Rect2(1130, 570, 70, 260), Rect2(650, 270, 300, 70), Rect2(650, 820, 300, 70)]},
]
const TYPES := {
	"combat": {"title": "封锁舱室", "description": "清理守卫，恢复通行。\n获得强化、废料与技术核心。", "color": "67efe0"},
	"elite": {"title": "精英封锁区", "description": "敌人的耐久和攻击更强。\n舱室废料与核心奖励翻倍。", "color": "ff987d"},
	"shop": {"title": "补给交换站", "description": "用本局废料购买维修、\n武器调校或元素符文。", "color": "ffd27a"},
	"rest": {"title": "维修站", "description": "恢复最大耐久的百分之三十五，\n并补满能量，无需战斗。", "color": "9adcbc"},
	"boss": {"title": "守卫封锁门", "description": "击败区域守卫。\n夺回通往下一区域的权限。", "color": "e68eef"},
}

static func choices(next_depth: int) -> Array[String]:
	if next_depth % 6 == 0:
		return ["boss"]
	match next_depth:
		3, 9: return ["shop", "combat"]
		4, 10: return ["combat", "rest"]
		5, 11: return ["elite", "shop"]
		_: return ["combat", "elite"]

static func generate(depth: int, kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var generation_state := rng.state
	var layout_index := 0 if depth == 1 else rng.randi_range(1, LAYOUTS.size() - 1)
	var layout: Dictionary = LAYOUTS[layout_index]
	var cover: Array = layout.cover.duplicate()
	var name: String = layout.name
	if depth > 1 and rng.randf() < 0.5:
		for i in range(cover.size()):
			var rect: Rect2 = cover[i]
			cover[i] = Rect2(Vector2(1600 - rect.end.x, rect.position.y), rect.size)
	if kind == "boss":
		name = "深渊核心" if depth == LAST_ROOM else "封锁卫士控制室"
		cover = [Rect2(260, 260, 100, 100), Rect2(1240, 260, 100, 100), Rect2(260, 760, 100, 100), Rect2(1240, 760, 100, 100)]
	elif kind in ["shop", "rest"]:
		name = "补给交换站" if kind == "shop" else "维修站"
		cover = [Rect2(320, 340, 240, 80), Rect2(1040, 340, 240, 80)]
	var spawns: Array[Vector2] = []
	# A stable, spaced lattice avoids overlaps. The run RNG varies spawn order.
	for y in [190.0, 480.0, 910.0]:
		for x in [190.0, 440.0, 680.0, 920.0, 1160.0, 1410.0]:
			var point := Vector2(x, y)
			if point.distance_to(START) >= 280.0 and walkable(point, cover, 32.0):
				spawns.append(point)
	for i in range(spawns.size() - 1, 0, -1):
		var swap := rng.randi_range(0, i)
		var value: Vector2 = spawns[i]
		spawns[i] = spawns[swap]
		spawns[swap] = value
	return {"depth": depth, "kind": kind, "name": name, "cover": cover,
		"generation_state": generation_state,
		"layout": layout_index, "start": START, "spawns": spawns,
		"biome": "下层熔炉区" if depth > 6 else "失联空间站",
		"tint": Color("c594bb") if depth > 6 else Color("85bdbd")}

static func walkable(point: Vector2, cover: Array, radius := 22.0) -> bool:
	if not Rect2(40 + radius, 40 + radius, 1520 - radius * 2, 970 - radius * 2).has_point(point):
		return false
	for rect in cover:
		if rect.grow(radius).has_point(point):
			return false
	return true
