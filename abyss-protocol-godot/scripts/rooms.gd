extends RefCounted
## Seeded room assembly: layouts, spawn safety and route kinds share one contract.

const MAP_ART = preload("res://scripts/map_art.gd")
const CHAPTERS = preload("res://scripts/chapters.gd")
const LAST_ROOM := 30
const START := Vector2(800, 650)
const LEGACY = preload("res://scripts/legacy_rooms.gd")
const GENERATOR := 2
const EXIT_POINTS := [Vector2(600, 185), Vector2(1000, 185)]
const SMALL_BOUNDS := Rect2(0, 0, 1600, 1050)
const LARGE_BOUNDS := Rect2(0, 0, 3200, 2100)
const CHAMBERS = preload("res://scripts/chamber_layouts.gd")
const LAYOUTS = CHAMBERS.LAYOUTS
const REWARDS := {
	"arsenal": {"name": "武器调校", "description": "优先获得锋刃增幅，满效时改供其他强化", "color": "e9ad72", "stat": "damage"},
	"vitality": {"name": "机体补强", "description": "优先获得修复矩阵，满效时改供其他强化", "color": "a2c6a1", "stat": "health"},
	"mobility": {"name": "相位升级", "description": "优先获得相位疾行，满效时改供其他强化", "color": "89bcc7", "stat": "speed"},
	"rune": {"name": "元素缓存", "description": "优先提供未满级元素；已满级时提供基础强化", "color": "c0a0d8", "stat": "element"},
	"supplies": {"name": "补给交易", "description": "消耗本局废料购买全队补给", "color": "e9bd79", "stat": ""},
	"repair": {"name": "免费维修", "description": "全队恢复 35% 最大耐久并补满能量", "color": "a2c6a1", "stat": ""},
	"guardian": {"name": "守卫权限", "description": "击败守卫，获得额外技术核心", "color": "d99a8b", "stat": ""},
}
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
	match posmod(next_depth - 1, 6) + 1:
		3: return ["shop", "combat"]
		4: return ["combat", "rest"]
		5: return ["elite", "shop"]
		_: return ["combat", "elite"]

static func generate(depth: int, kind: String, rng: RandomNumberGenerator, generator := GENERATOR) -> Dictionary:
	if generator == 1:
		return LEGACY.generate(depth, kind, rng)
	var generation_state := rng.state
	var chapter := CHAPTERS.region(depth)
	var bounds := SMALL_BOUNDS if depth == 1 else LARGE_BOUNDS
	var start := START if depth == 1 else Vector2(1600, 1740)
	var exits: Array = EXIT_POINTS.duplicate() if depth == 1 else [Vector2(1200, 210), Vector2(2000, 210)]
	var pool: Array = chapter.pool
	var layout_index: int = 0 if depth == 1 else pool[rng.randi_range(0, pool.size() - 1)]
	if depth > 1 and kind == "combat" and (depth == 2 or depth % 6 == 1): layout_index = pool[0]
	var layout: Dictionary = LAYOUTS[layout_index]
	var furnishings: Array = layout.cover.duplicate()
	var shell: Array = layout.shell.duplicate()
	var name: String = layout.name
	var tactic: String = layout.tactic
	var motif: String = layout.motif
	if depth > 1 and rng.randf() < 0.5:
		for pieces in [furnishings, shell]:
			for i in range(pieces.size()):
				var rect: Rect2 = pieces[i]
				pieces[i] = Rect2(Vector2(bounds.end.x - rect.end.x, rect.position.y), rect.size)
	if kind == "boss":
		name = chapter.guardian
		tactic = "守卫竞技场 · 保持侧向空间，辨认攻击前摇"
		motif = "guardian"
		var arena := CHAMBERS.guardian(CHAPTERS.number(depth))
		shell = arena.shell
		furnishings = arena.cover
	elif kind in ["shop", "rest"]:
		name = "补给交换站" if kind == "shop" else "静息维修庭"
		tactic = "安全舱室 · 整备后选择下一道舱门"
		motif = "supply" if kind == "shop" else "sanctuary"
		var lounge := CHAMBERS.sanctuary()
		shell = lounge.shell
		furnishings = lounge.cover
	var art_data := {}
	if kind == "boss" or (depth > 1 and layout_index == pool[0] and kind in ["combat", "elite"]):
		art_data = MAP_ART.apply({"bounds": bounds}, CHAPTERS.number(depth), kind == "boss")
		shell = art_data.shell
		furnishings = art_data.furnishings
		name = chapter.guardian if kind == "boss" else art_data.name
		tactic = art_data.tactic
		start = art_data.start
		exits = art_data.exits
	var obstacles: Array = art_data.get("obstacles", [])
	var cover: Array = furnishings + shell
	var spawns: Array[Vector2] = []
	var rows: Array = [230.0, 460.0, 730.0, 920.0] if depth == 1 else [410.0, 820.0, 1230.0, 1630.0, 1900.0]
	var columns: Array = [220.0, 450.0, 680.0, 920.0, 1150.0, 1380.0] if depth == 1 else [440.0, 760.0, 1150.0, 1600.0, 2050.0, 2440.0, 2760.0]
	for y in rows:
		for x in columns:
			var point := Vector2(x, y)
			if point.distance_to(start) >= 280.0 and point.distance_to(start + Vector2(60, 0)) >= 280.0 and walkable(point, cover, 56.0, bounds, obstacles):
				spawns.append(point)
	for i in range(spawns.size() - 1, 0, -1):
		var swap := rng.randi_range(0, i)
		var value: Vector2 = spawns[i]
		spawns[i] = spawns[swap]
		spawns[swap] = value
	var reward: String = ["arsenal", "vitality", "mobility", "rune"][rng.randi_range(0, 3)]
	if depth == 1: reward = "arsenal"
	if kind == "shop": reward = "supplies"
	if kind == "rest": reward = "repair"
	if kind == "boss": reward = "guardian"
	var data := {"depth": depth, "kind": kind, "name": name, "cover": cover,
		"generator": GENERATOR, "generation_state": generation_state,
		"chapter": CHAPTERS.number(depth) + 1, "region": chapter.duplicate(true),
		"furnishings": furnishings, "shell": shell, "motif": motif, "tactic": tactic,
		"reward": reward, "exits": exits, "bounds": bounds, "obstacles": obstacles, "boss_start": art_data.get("boss_start", Vector2(1600, 700)),
		"layout": layout_index, "start": start, "spawns": spawns,
		"biome": chapter.name, "tint": Color(chapter.palette)}
	if not art_data.is_empty(): data.art = art_data.art
	return data

static func reward_for(data: Dictionary) -> Dictionary:
	return REWARDS.get(data.get("reward", "arsenal"), REWARDS.arsenal)

static func walkable(point: Vector2, cover: Array, radius := 22.0, bounds := SMALL_BOUNDS, obstacles: Array = []) -> bool:
	if not bounds.grow(-40.0 - radius).has_point(point):
		return false
	for rect in cover:
		if rect.grow(radius).has_point(point):
			return false
	for polygon in obstacles:
		if Geometry2D.is_point_in_polygon(point, polygon): return false
		for i in range(polygon.size()):
			var nearest := Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])
			if point.distance_squared_to(nearest) <= radius * radius: return false
	return true
