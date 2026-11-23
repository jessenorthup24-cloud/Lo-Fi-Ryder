extends RefCounted
## The toy car collection (models from the Tiny Car Pack, baked into assets/cars).
## grip/drift/bounce are gentle personality tweaks (1.0 = the Bug).

const LIST := [
	{"id": "bug", "name": "Sunny Bug", "price": 0, "model": "13_4", "grip": 1.0, "drift": 1.0, "bounce": 1.15, "engine": "small", "pitch": 1.15},
	{"id": "camper", "name": "Roof Rack", "price": 150, "model": "12_2", "grip": 0.96, "drift": 1.05, "bounce": 1.3, "engine": "truck", "pitch": 1.05},
	{"id": "pickup", "name": "Rally Box", "price": 250, "model": "5_1", "grip": 1.02, "drift": 1.15, "bounce": 1.15, "engine": "small", "pitch": 1.1},
	{"id": "mini", "name": "Minnow", "price": 350, "model": "8_1", "grip": 1.08, "drift": 0.95, "bounce": 1.05, "engine": "small", "pitch": 1.25},
	{"id": "taxi", "name": "Marmalade", "price": 450, "model": "9_4", "grip": 0.98, "drift": 1.2, "bounce": 1.0, "engine": "v8", "pitch": 1.0},
	{"id": "jeep", "name": "Scout", "price": 550, "model": "12_4", "grip": 1.05, "drift": 0.95, "bounce": 1.4, "engine": "truck", "pitch": 1.12},
	{"id": "wagon", "name": "Ducktail", "price": 700, "model": "4_1", "grip": 1.08, "drift": 1.1, "bounce": 1.0, "engine": "small", "pitch": 1.08},
	{"id": "roadster", "name": "Pop-Up 86", "price": 850, "model": "10_1", "grip": 1.0, "drift": 1.25, "bounce": 1.0, "engine": "small", "pitch": 1.18},
	{"id": "police", "name": "Patrol", "price": 1000, "model": "3_2", "grip": 1.08, "drift": 1.1, "bounce": 0.95, "engine": "v8", "pitch": 1.08},
	{"id": "icecream", "name": "Sky Bug", "price": 1200, "model": "13_5", "grip": 1.0, "drift": 1.05, "bounce": 1.25, "engine": "small", "pitch": 1.2},
	{"id": "mail", "name": "Grand Tourer", "price": 1400, "model": "6_1", "grip": 1.12, "drift": 1.05, "bounce": 0.95, "engine": "v8", "pitch": 1.02},
	{"id": "tractor", "name": "Sky Dart", "price": 1600, "model": "7_1", "grip": 1.12, "drift": 1.1, "bounce": 0.9, "engine": "small", "pitch": 1.3},
	{"id": "firetruck", "name": "Redline", "price": 1900, "model": "11_1", "grip": 1.15, "drift": 1.05, "bounce": 0.9, "engine": "small", "pitch": 1.35},
	{"id": "bus", "name": "Yellow Jacket", "price": 2200, "model": "1_1", "grip": 1.02, "drift": 1.2, "bounce": 1.0, "engine": "v8", "pitch": 0.95},
	{"id": "dump", "name": "Bluebolt", "price": 2500, "model": "2_1", "grip": 1.15, "drift": 1.1, "bounce": 0.9, "engine": "small", "pitch": 1.4},
	{"id": "racer", "name": "Quicksilver", "price": 2900, "model": "11_4", "grip": 1.18, "drift": 1.1, "bounce": 0.85, "engine": "small", "pitch": 1.42},
	{"id": "hotrod", "name": "Midnight", "price": 3400, "model": "9_3", "grip": 1.0, "drift": 1.3, "bounce": 1.0, "engine": "v8", "pitch": 0.88},
	{"id": "monster", "name": "Nightshade", "price": 4000, "model": "3_1", "grip": 1.15, "drift": 1.15, "bounce": 0.9, "engine": "v8", "pitch": 0.92},
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
