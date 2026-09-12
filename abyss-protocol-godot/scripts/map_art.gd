extends RefCounted
## Ground collision footprints use a common 1547 x 1016 tracing frame, scaled
## with the artwork (the source canvases differ by at most one pixel per axis).
## All ten frozen calibration copies retain the user's artwork unchanged.
## Diagonal footprints preserve the dry corridors visible between equipment.
const DOCK := "res://assets/map/calibrated/docking.png"
const SOURCE_SIZE := Vector2(1547, 1016)
const SHELL := [
	Rect2(0, 0, 1547, 90), Rect2(0, 90, 86, 820), Rect2(1468, 90, 79, 820),
	Rect2(0, 910, 615, 106), Rect2(940, 910, 607, 106), Rect2(615, 993, 325, 23),
	# The two machinery bays are enclosed; their apparent floor is not a passage.
	Rect2(80, 258, 167, 335), Rect2(1293, 255, 175, 338),
	# Raised sides of the entrance vestibule and the low outer service equipment.
	Rect2(86, 810, 190, 100), Rect2(276, 875, 314, 35), Rect2(587, 817, 29, 176),
	Rect2(968, 855, 453, 55), Rect2(935, 817, 32, 176),
]
const EQUIPMENT := [
	# Four cargo islands. Small rectangles follow their stepped outlines.
	Rect2(430, 237, 207, 102), Rect2(575, 294, 101, 88),
	Rect2(871, 237, 221, 103), Rect2(871, 340, 122, 49), Rect2(1068, 335, 34, 51),
	Rect2(431, 470, 64, 184), Rect2(490, 529, 113, 119), Rect2(602, 558, 46, 87),
	Rect2(943, 528, 117, 128), Rect2(1060, 482, 49, 174), Rect2(898, 556, 46, 96),
	# Fixtures against the outer walls and machinery bays.
	Rect2(88, 89, 248, 27), Rect2(478, 85, 75, 61), Rect2(573, 85, 97, 35),
	Rect2(824, 87, 127, 38), Rect2(955, 94, 113, 51), Rect2(1219, 88, 196, 29),
	Rect2(200, 189, 96, 75), Rect2(248, 263, 44, 93),
	Rect2(1243, 190, 90, 63), Rect2(1267, 268, 27, 86),
	Rect2(194, 590, 122, 104), Rect2(248, 468, 49, 122),
	Rect2(1230, 578, 101, 128), Rect2(1250, 483, 44, 95),
	Rect2(87, 729, 49, 81), Rect2(1422, 673, 46, 237),
]

static func apply(data: Dictionary, chapter := 0, guardian := false) -> Dictionary:
	var scale_map: Vector2 = data.bounds.size / SOURCE_SIZE
	var shell: Array = []
	var equipment: Array = []
	var source := guardian_layout(chapter) if guardian else region_layout(chapter)
	for rect in source.shell: shell.append(Rect2(rect.position * scale_map, rect.size * scale_map))
	for rect in source.equipment: equipment.append(Rect2(rect.position * scale_map, rect.size * scale_map))
	var obstacles: Array = []
	for polygon in source.get("polygons", []):
		var transformed := PackedVector2Array()
		for point in polygon: transformed.append(point * scale_map)
		obstacles.append(transformed)
	data.shell = shell
	data.furnishings = equipment
	data.cover = shell + equipment
	data.obstacles = obstacles
	data.art = source.art
	data.name = source.name
	data.tactic = source.tactic
	data.start = Vector2(774, 902) * scale_map
	data.exits = [Vector2(730, 160) * scale_map, Vector2(820, 160) * scale_map] if guardian else [Vector2(391, 130) * scale_map, Vector2(1153, 130) * scale_map]
	data.boss_start = Vector2(774, 460) * scale_map
	return data

static func arc_slice(center: Vector2, radius: Vector2, start: float, end: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(33):
		points.append(center + Vector2.from_angle(lerpf(start, end, index / 32.0)) * radius)
	return points

static func polygon(coords: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(0, coords.size(), 2): result.append(Vector2(coords[i], coords[i + 1]))
	return result

static func region_layout(chapter: int) -> Dictionary:
	var border: Array = [Rect2(0, 0, 1547, 90), Rect2(0, 90, 62, 822), Rect2(1490, 90, 57, 822),
		Rect2(0, 912, 620, 104), Rect2(934, 912, 613, 104), Rect2(620, 993, 314, 23),
		Rect2(590, 817, 32, 176), Rect2(934, 817, 33, 176)]
	if chapter == 1:
		var polygons: Array = []
		# The 40-pixel maintenance bridges end at solid center plinths. Wider
		# rectangular cutouts would let actors step into the painted water.
		for center in [Vector2(518, 438), Vector2(1028, 438)]:
			var radius := Vector2(188, 190)
			var cut := asin(20.0 / radius.y)
			polygons.append(arc_slice(center, radius, PI + cut, TAU - cut))
			polygons.append(arc_slice(center, radius, cut, PI - cut))
			polygons.append(arc_slice(center, Vector2(55, 55), 0, TAU * 32.0 / 33.0))
		return {"art": "res://assets/map/calibrated/cooling.png", "name": "双环冷却花园", "tactic": "双池温室 · 沿外环绕行，维修桥连接侧厅",
			"shell": border + [Rect2(60, 819, 530, 93), Rect2(967, 819, 523, 93), Rect2(213, 246, 33, 134), Rect2(213, 497, 33, 119), Rect2(1293, 247, 38, 134), Rect2(1293, 497, 38, 119)],
			"equipment": [Rect2(76, 91, 48, 149), Rect2(1413, 91, 70, 149), Rect2(188, 91, 127, 6), Rect2(468, 89, 117, 68), Rect2(594, 89, 129, 30), Rect2(828, 89, 136, 31), Rect2(979, 89, 110, 68), Rect2(1225, 89, 132, 8), Rect2(62, 258, 151, 358), Rect2(1331, 258, 159, 358), Rect2(618, 754, 82, 63), Rect2(846, 754, 82, 63)],
			"polygons": polygons + [polygon([213,248, 224,208, 293,179, 350,167, 350,185, 285,215, 246,260]), polygon([1334,248, 1323,208, 1254,179, 1197,167, 1197,185, 1262,215, 1301,260]), polygon([213,603, 253,640, 294,685, 351,713, 351,747, 287,724, 233,679, 201,628]), polygon([1334,603, 1294,640, 1253,685, 1196,713, 1196,747, 1260,724, 1314,679, 1346,628])]}
	if chapter == 2:
		return {"art": "res://assets/map/calibrated/archive.png", "name": "双翼记忆档案", "tactic": "三排档案岛 · 横向连接两翼，沿中线连续换位",
			"shell": border + [Rect2(61, 846, 529, 66), Rect2(967, 846, 523, 66), Rect2(205, 251, 48, 147), Rect2(205, 555, 48, 173), Rect2(1295, 251, 48, 147), Rect2(1295, 555, 48, 173)],
			"equipment": [Rect2(61, 90, 249, 30), Rect2(471, 90, 203, 42), Rect2(876, 90, 210, 42), Rect2(1245, 90, 245, 38), Rect2(106, 137, 140, 58), Rect2(1300, 157, 114, 52), Rect2(61, 282, 40, 438), Rect2(1450, 282, 40, 438), Rect2(378, 205, 242, 127), Rect2(933, 205, 239, 127), Rect2(334, 394, 258, 135), Rect2(957, 394, 255, 135), Rect2(375, 615, 249, 130), Rect2(922, 615, 253, 130), Rect2(60, 434, 60, 86), Rect2(1430, 434, 60, 86), Rect2(258, 714, 45, 74), Rect2(1244, 714, 45, 74)]}
	if chapter == 3:
		# Reactor corners are beveled. Their bounding boxes would close the
		# passages between the reactors and the side-bay machinery to large actors.
		return {"art": "res://assets/map/calibrated/furnace.png", "name": "双桥地热泵站", "tactic": "双桥热井 · 上下平台与两侧通路连成回环",
			"shell": border + [Rect2(61, 253, 188, 363), Rect2(1297, 253, 193, 363), Rect2(61, 795, 529, 117), Rect2(967, 795, 523, 117)],
			"equipment": [Rect2(62, 89, 246, 28), Rect2(62, 116, 172, 127), Rect2(1235, 89, 255, 28), Rect2(1320, 116, 170, 127), Rect2(471, 89, 73, 54), Rect2(550, 89, 56, 30), Rect2(1007, 89, 73, 54), Rect2(943, 89, 56, 30), Rect2(384, 224, 81, 65), Rect2(590, 215, 64, 81), Rect2(884, 215, 69, 81), Rect2(1084, 224, 76, 65), Rect2(591, 374, 70, 146), Rect2(882, 374, 70, 146), Rect2(382, 599, 82, 64), Rect2(591, 611, 70, 95), Rect2(882, 611, 70, 95), Rect2(1085, 599, 82, 64), Rect2(199, 615, 103, 86), Rect2(1246, 615, 105, 86)],
			"polygons": [polygon([388,259, 566,259, 608,303, 608,573, 567,617, 388,617, 348,574, 348,300]), polygon([1159,259, 981,259, 939,303, 939,573, 980,617, 1159,617, 1199,574, 1199,300])]}
	if chapter == 4:
		# The three equipment bays are enclosed, while all four diagonal doorways
		# connect the central octagon to the outer loop. Trace diagonal walls too.
		# Bottom machinery uses its ground footprint, below its raised upper edge.
		return {"art": "res://assets/map/calibrated/core.png", "name": "三瓣协议中庭", "tactic": "四道斜门 · 中庭连接外环，借短墙切断火线",
			"shell": border + [Rect2(62, 834, 528, 78), Rect2(967, 834, 523, 78), Rect2(575, 90, 397, 132)],
			"equipment": [Rect2(150, 88, 174, 52), Rect2(1222, 88, 174, 52), Rect2(85, 166, 29, 122), Rect2(1434, 166, 29, 122)],
			"polygons": [polygon([62,90, 241,90, 62,243]), polygon([1485,90, 1306,90, 1485,243]), polygon([65,317, 307,267, 423,373, 423,644, 337,729, 65,729]), polygon([1482,317, 1240,267, 1124,373, 1124,644, 1210,729, 1482,729]), polygon([452,90, 526,90, 600,213, 677,213, 677,282, 569,282, 453,162]), polygon([1095,90, 1021,90, 947,213, 870,213, 870,282, 978,282, 1094,162]), polygon([245,292, 312,236, 353,236, 453,348, 453,456, 410,456, 410,376, 318,296, 285,326]), polygon([1302,292, 1235,236, 1194,236, 1094,348, 1094,456, 1137,456, 1137,376, 1229,296, 1262,326]), polygon([410,552, 455,552, 455,665, 353,765, 294,743, 410,646]), polygon([1137,552, 1092,552, 1092,665, 1194,765, 1253,743, 1137,646]), polygon([556,755, 671,755, 671,806, 619,806, 619,903, 568,903]), polygon([991,755, 876,755, 876,806, 928,806, 928,903, 979,903]), polygon([560,392, 638,316, 681,337, 602,433, 560,433]), polygon([987,392, 909,316, 866,337, 945,433, 987,433]), polygon([558,560, 604,558, 681,638, 668,679, 630,679, 558,606]), polygon([989,560, 943,558, 866,638, 879,679, 917,679, 989,606])]}
	return {"art": DOCK, "name": "接驳货运厅", "tactic": "四组货箱 · 中央与两侧宽路互通，沿箱角换线", "shell": SHELL, "equipment": EQUIPMENT}

static func guardian_layout(chapter: int) -> Dictionary:
	# Artwork 6–10 was authored as arena counterparts to the five exploration maps.
	var names := ["docking", "cooling", "archive", "furnace", "core"]
	var shell: Array = [Rect2(0, 0, 1547, 88), Rect2(0, 88, 91, 824), Rect2(1456, 88, 91, 824), Rect2(0, 912, 669, 104), Rect2(881, 912, 666, 104), Rect2(669, 993, 212, 23), Rect2(628, 836, 42, 157), Rect2(881, 836, 42, 157)]
	var equipment: Array = []
	var polygons: Array = []
	match chapter:
		0:
			equipment = [Rect2(445, 216, 152, 111), Rect2(1033, 216, 152, 111), Rect2(445, 737, 152, 111), Rect2(1033, 737, 152, 111), Rect2(94, 88, 567, 39), Rect2(884, 88, 570, 39), Rect2(93, 855, 535, 57), Rect2(923, 855, 531, 57)]
			polygons = [polygon([91,88, 193,88, 193,153, 91,245]), polygon([1456,88, 1354,88, 1354,153, 1456,245]), polygon([91,748, 213,859, 213,912, 91,912]), polygon([1456,748, 1334,859, 1334,912, 1456,912])]
		1:
			shell += [Rect2(91, 88, 370, 159), Rect2(1086, 88, 370, 159), Rect2(91, 738, 370, 174), Rect2(1086, 738, 370, 174), Rect2(91, 322, 50, 334), Rect2(1406, 322, 50, 334)]
			equipment = [Rect2(423, 384, 124, 168), Rect2(998, 384, 124, 168), Rect2(460, 88, 225, 41), Rect2(868, 88, 218, 41), Rect2(460, 836, 167, 76), Rect2(923, 836, 163, 76)]
			polygons = [polygon([91,247, 461,194, 419,264, 336,307, 91,307]), polygon([1456,247, 1086,194, 1128,264, 1211,307, 1456,307]), polygon([91,738, 461,790, 419,712, 336,661, 91,661]), polygon([1456,738, 1086,790, 1128,712, 1211,661, 1456,661])]
		2:
			shell += [Rect2(91, 302, 170, 355), Rect2(1286, 302, 170, 355)]
			equipment = [Rect2(333, 187, 228, 161), Rect2(970, 187, 228, 161), Rect2(333, 702, 228, 148), Rect2(970, 702, 228, 148), Rect2(91, 88, 574, 45), Rect2(884, 88, 572, 45), Rect2(91, 854, 537, 58), Rect2(923, 854, 533, 58)]
		3:
			shell += [Rect2(91, 258, 164, 417), Rect2(1292, 258, 164, 417)]
			equipment = [Rect2(352, 134, 173, 103), Rect2(1022, 134, 173, 103), Rect2(352, 777, 173, 120), Rect2(1022, 777, 173, 120), Rect2(91, 88, 574, 40), Rect2(884, 88, 572, 40), Rect2(91, 867, 537, 45), Rect2(923, 867, 533, 45)]
			polygons = [polygon([91,88, 218,88, 218,147, 91,259]), polygon([1456,88, 1329,88, 1329,147, 1456,259]), polygon([91,674, 283,870, 283,912, 91,912]), polygon([1456,674, 1264,870, 1264,912, 1456,912])]
		4:
			shell += [Rect2(91, 343, 75, 243), Rect2(1381, 343, 75, 243)]
			equipment = [Rect2(246, 162, 118, 168), Rect2(1183, 162, 118, 168), Rect2(246, 693, 118, 168), Rect2(1183, 693, 118, 168), Rect2(481, 88, 179, 76), Rect2(887, 88, 179, 76), Rect2(471, 843, 157, 69), Rect2(923, 843, 157, 69)]
			polygons = [polygon([91,88, 223,88, 91,258]), polygon([1456,88, 1324,88, 1456,258]), polygon([91,689, 296,912, 91,912]), polygon([1456,689, 1251,912, 1456,912])]
	return {"art": "res://assets/map/calibrated/" + names[chapter] + "-guardian.png", "name": "区域守卫竞技场", "tactic": "守卫竞技场 · 外环留出闪避空间，利用设备阻隔火线", "shell": shell, "equipment": equipment, "polygons": polygons}
