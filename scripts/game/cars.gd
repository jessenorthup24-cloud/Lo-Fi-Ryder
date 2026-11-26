extends RefCounted
## The car collection (models from the Tiny Car Pack and Designersoup's Low Poly Car Pack 1, CC0, baked into assets/cars).
## power / speed / grip: 1.0 = the Sunny Bug. drift: above 1 the tail lets go more easily.

const LIST := [
	{"id": "bug", "name": "Sunny Bug", "price": 0, "model": "13_4", "power": 1.0, "speed": 1.0, "grip": 1.0, "drift": 1.05, "engine": "small", "pitch": 1.15},
	{"id": "roadster", "name": "Pop-Up 86", "price": 600, "model": "10_1", "power": 1.05, "speed": 1.02, "grip": 0.98, "drift": 1.25, "engine": "small", "pitch": 1.18},
	{"id": "pickup", "name": "Rally Box", "price": 900, "model": "5_1", "power": 1.1, "speed": 1.0, "grip": 1.02, "drift": 1.15, "engine": "small", "pitch": 1.1},
	{"id": "pebble", "name": "Pebble", "price": 1000, "model": "ds_bubble", "power": 1.02, "speed": 0.98, "grip": 1.0, "drift": 1.22, "engine": "small", "pitch": 1.28},
	{"id": "mini", "name": "Minnow", "price": 1200, "model": "8_1", "power": 1.0, "speed": 1.04, "grip": 1.08, "drift": 1.0, "engine": "small", "pitch": 1.25},
	{"id": "camper", "name": "Roof Rack", "price": 1500, "model": "12_2", "power": 1.12, "speed": 0.98, "grip": 0.98, "drift": 1.1, "engine": "truck", "pitch": 1.05},
	{"id": "taxi", "name": "Marmalade", "price": 1900, "model": "9_4", "power": 1.18, "speed": 1.04, "grip": 1.0, "drift": 1.2, "engine": "v8", "pitch": 1.0},
	{"id": "jeep", "name": "Scout", "price": 2300, "model": "12_4", "power": 1.15, "speed": 1.0, "grip": 1.06, "drift": 1.05, "engine": "truck", "pitch": 1.12},
	{"id": "trailhand", "name": "Trailhand", "price": 2500, "model": "ds_box4x4", "power": 1.14, "speed": 0.98, "grip": 1.1, "drift": 1.0, "engine": "truck", "pitch": 0.98},
	{"id": "wagon", "name": "Ducktail", "price": 2800, "model": "4_1", "power": 1.2, "speed": 1.06, "grip": 1.06, "drift": 1.15, "engine": "small", "pitch": 1.08},
	{"id": "police", "name": "Patrol", "price": 3300, "model": "3_2", "power": 1.25, "speed": 1.08, "grip": 1.08, "drift": 1.12, "engine": "v8", "pitch": 1.08},
	{"id": "icecream", "name": "Sky Bug", "price": 3800, "model": "13_5", "power": 1.2, "speed": 1.05, "grip": 1.04, "drift": 1.2, "engine": "small", "pitch": 1.2},
	{"id": "bushwhacker", "name": "Bushwhacker", "price": 4100, "model": "ds_ute", "power": 1.26, "speed": 1.04, "grip": 1.1, "drift": 1.18, "engine": "truck", "pitch": 0.94},
	{"id": "mail", "name": "Grand Tourer", "price": 4500, "model": "6_1", "power": 1.3, "speed": 1.12, "grip": 1.1, "drift": 1.1, "engine": "v8", "pitch": 1.02},
	{"id": "tractor", "name": "Sky Dart", "price": 5200, "model": "7_1", "power": 1.3, "speed": 1.12, "grip": 1.1, "drift": 1.18, "engine": "small", "pitch": 1.3},
	{"id": "firetruck", "name": "Redline", "price": 6000, "model": "11_1", "power": 1.38, "speed": 1.15, "grip": 1.12, "drift": 1.15, "engine": "small", "pitch": 1.35},
	{"id": "bus", "name": "Yellow Jacket", "price": 6800, "model": "1_1", "power": 1.36, "speed": 1.12, "grip": 1.06, "drift": 1.3, "engine": "v8", "pitch": 0.95},
	{"id": "dump", "name": "Bluebolt", "price": 7600, "model": "2_1", "power": 1.42, "speed": 1.18, "grip": 1.14, "drift": 1.15, "engine": "small", "pitch": 1.4},
	{"id": "wedge", "name": "Steel Wedge", "price": 8000, "model": "ds_wedge", "power": 1.4, "speed": 1.16, "grip": 1.06, "drift": 1.32, "engine": "small", "pitch": 1.04},
	{"id": "racer", "name": "Quicksilver", "price": 8500, "model": "11_4", "power": 1.48, "speed": 1.22, "grip": 1.16, "drift": 1.12, "engine": "small", "pitch": 1.42},
	{"id": "hotrod", "name": "Midnight", "price": 9500, "model": "9_3", "power": 1.55, "speed": 1.2, "grip": 1.02, "drift": 1.4, "engine": "v8", "pitch": 0.88},
	{"id": "monster", "name": "Nightshade", "price": 11000, "model": "3_1", "power": 1.6, "speed": 1.25, "grip": 1.12, "drift": 1.3, "engine": "v8", "pitch": 0.92},
	{"id": "longbow", "name": "Longbow", "price": 13500, "model": "ds_gt", "power": 1.64, "speed": 1.27, "grip": 1.18, "drift": 1.3, "engine": "v8", "pitch": 0.86},
	# legendary: the Haywire (its own model, tools/cars/bake_glb_car.gd), built to slide
	# legendary: the Mountain Ghost, a panda-coloured hatch with pop-up lights: light, high-revving, balanced in a slide
	{"id": "ae86", "name": "Mountain Ghost", "price": 20000, "model": "ae86", "legend": true, "power": 1.4, "speed": 1.16, "grip": 1.16, "drift": 1.55, "engine": "small", "pitch": 1.22},
	{"id": "hoon", "name": "Haywire", "price": 20000, "model": "hoon", "legend": true, "power": 1.7, "speed": 1.24, "grip": 1.1, "drift": 1.6, "engine": "v8", "pitch": 0.9},
]

static func by_id(id: String) -> Dictionary:
	for d in LIST:
		if d["id"] == id:
			return d
	return LIST[0]

static func index_of(id: String) -> int:
	for i in LIST.size():
		if LIST[i]["id"] == id:
			return i
	return 0
