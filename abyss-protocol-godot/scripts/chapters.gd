extends RefCounted
## Five authored regional identities; room assembly, encounters and UI share them.
const ROOMS_PER_CHAPTER := 6
const REGIONS := [
	{"name": "接驳防线", "purpose": "恢复供电，夺回维修授权", "palette": "9cae9e", "deck": "202a2d", "pool": [1, 3, 4], "ranged_every": 3,
	 "guardian": "封锁卫士", "guardian_hp": 14000.0, "pattern": ["spread", "ground"], "crest": "shield"},
	{"name": "冷却花园", "purpose": "穿过冷凝环路，重启生命维持", "palette": "8fbdb8", "deck": "1d3031", "pool": [2, 3, 8], "ranged_every": 4,
	 "guardian": "冷却看守", "guardian_hp": 22000.0, "pattern": ["ground", "spread", "ground"], "crest": "crystal"},
	{"name": "记忆档案", "purpose": "绕过交叉火力，找回事故底稿", "palette": "a9a4c4", "deck": "282a39", "pool": [5, 4, 9], "ranged_every": 2,
	 "guardian": "档案裁决者", "guardian_hp": 32000.0, "pattern": ["cross", "spread", "cross"], "crest": "diamond"},
	{"name": "地热熔炉", "purpose": "穿过连桥与热井，恢复散热泵组", "palette": "c49a71", "deck": "342921", "pool": [6, 7, 1], "ranged_every": 3,
	 "guardian": "熔炉监工", "guardian_hp": 45000.0, "pattern": ["ground", "radial", "spread"], "crest": "furnace"},
	{"name": "协议中枢", "purpose": "突破最后的防线，完成维修握手", "palette": "bba892", "deck": "292e33", "pool": [7, 9, 10], "ranged_every": 2,
	 "guardian": "深渊主控体", "guardian_hp": 61000.0, "pattern": ["radial", "cross", "ground", "spread"], "crest": "core"},
]

static func number(depth: int) -> int:
	return clampi((depth - 1) / ROOMS_PER_CHAPTER, 0, REGIONS.size() - 1)

static func region(depth: int) -> Dictionary:
	return REGIONS[number(depth)]
