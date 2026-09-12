extends RefCounted
## Calibrated grip/support anchors from the original local weapon atlases.

const GUNS = preload("res://assets/weapons/guns.webp")
const BOWS = preload("res://assets/weapons/bows.webp")
const ART_SCALE := 1.3

const GUN_SPRITES := {
	"rifle": {
		"cell": 0,
		"grip": [
			78.7923,
			60.3492
		],
		"support": [
			157.8073,
			49.4717
		],
		"muzzle": [
			245.1734,
			37.3144
		],
		"angle": 0,
		"scale": 0.11666666666666667
	},
	"scatter": {
		"cell": 1,
		"grip": [
			69.1527,
			61.4826
		],
		"support": [
			156.5137,
			54.8242
		],
		"muzzle": [
			242.6613,
			41.5075
		],
		"angle": 0,
		"scale": 0.10416666666666667
	},
	"rail": {
		"cell": 2,
		"grip": [
			67.7903,
			59.7669
		],
		"support": [
			124.1058,
			66.3372
		],
		"muzzle": [
			244.5252,
			59.1696
		],
		"angle": 0.12599568216401255,
		"scale": 0.14166666666666666
	}
}

const BOW_SPRITES := {
	"qbow": {
		"cell": 0,
		"grip": [
			95.3741,
			126.2423
		],
		"tips": [
			[
				23.3889,
				11.1957
			],
			[
				24.9815,
				244.1651
			]
		],
		"scale": 0.08333333333333333
	},
	"lbow": {
		"cell": 1,
		"grip": [
			95.0579,
			123.5438
		],
		"tips": [
			[
				28.7904,
				11.3422
			],
			[
				26.3952,
				244.9761
			]
		],
		"scale": 0.11666666666666667
	},
	"sbow": {
		"cell": 2,
		"grip": [
			98.5197,
			122.3233
		],
		"tips": [
			[
				24.1333,
				11.1537
			],
			[
				21.1453,
				244.5309
			]
		],
		"scale": 0.1
	}
}
