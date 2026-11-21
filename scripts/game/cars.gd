extends RefCounted
## The toy car collection. grip/drift/bounce are gentle personality tweaks (1.0 = the Bug).

const LIST := [
	{"id": "bug", "name": "Sunny Bug", "price": 0, "shape": "round", "body": "f6d36b", "accent": "fff3d9", "grip": 1.0, "drift": 1.0, "bounce": 1.15},
	{"id": "camper", "name": "Camper", "price": 150, "shape": "van", "body": "4fb3a9", "accent": "fff6e8", "grip": 0.95, "drift": 1.05, "bounce": 1.3},
	{"id": "pickup", "name": "Red Pickup", "price": 250, "shape": "pickup", "body": "e85a4f", "accent": "c9cfd8", "grip": 1.0, "drift": 1.1, "bounce": 1.1},
	{"id": "mini", "name": "Mini", "price": 350, "shape": "mini", "body": "d94a4a", "accent": "ffffff", "grip": 1.08, "drift": 0.95, "bounce": 1.0},
	{"id": "taxi", "name": "Taxi", "price": 450, "shape": "taxi", "body": "ffcf3f", "accent": "ffcf3f", "hub": "3a3540", "grip": 1.02, "drift": 1.05, "bounce": 1.0},
	{"id": "jeep", "name": "Trail Jeep", "price": 550, "shape": "jeep", "body": "8aa05a", "accent": "8aa05a", "hub": "3a3540", "grip": 1.05, "drift": 0.95, "bounce": 1.4},
	{"id": "wagon", "name": "Woody", "price": 700, "shape": "wagon", "body": "f2e3c6", "accent": "f2e3c6", "grip": 0.98, "drift": 1.1, "bounce": 1.1},
	{"id": "roadster", "name": "Roadster", "price": 850, "shape": "roadster", "body": "9fe0c8", "accent": "e8d9c4", "grip": 1.1, "drift": 1.05, "bounce": 0.9},
	{"id": "police", "name": "Patrol", "price": 1000, "shape": "police", "body": "3a3f4a", "accent": "ffffff", "grip": 1.08, "drift": 1.1, "bounce": 0.95},
	{"id": "icecream", "name": "Ice Cream", "price": 1200, "shape": "icecream", "body": "fff6ee", "accent": "ff9fbf", "hub": "ff9fbf", "grip": 0.95, "drift": 1.1, "bounce": 1.35},
	{"id": "mail", "name": "Mail Van", "price": 1400, "shape": "mail", "body": "ffffff", "accent": "4b7bd6", "hub": "4b7bd6", "grip": 1.0, "drift": 1.0, "bounce": 1.25},
	{"id": "tractor", "name": "Tractor", "price": 1600, "shape": "tractor", "body": "5fae4f", "accent": "ffd166", "hub": "ffd166", "grip": 1.15, "drift": 0.85, "bounce": 1.45},
	{"id": "firetruck", "name": "Fire Engine", "price": 1900, "shape": "firetruck", "body": "e8473f", "accent": "c9cfd8", "grip": 1.05, "drift": 1.0, "bounce": 1.1},
	{"id": "bus", "name": "School Bus", "price": 2200, "shape": "bus", "body": "ffc531", "accent": "3a3540", "hub": "3a3540", "grip": 1.0, "drift": 1.15, "bounce": 1.2},
	{"id": "dump", "name": "Dump Truck", "price": 2500, "shape": "dump", "body": "ffa23a", "accent": "ffcf6b", "hub": "3a3540", "grip": 1.1, "drift": 0.95, "bounce": 1.3},
	{"id": "racer", "name": "Racer No. 7", "price": 2900, "shape": "racer", "body": "4b7bd6", "accent": "ffffff", "grip": 1.15, "drift": 1.15, "bounce": 0.85},
	{"id": "hotrod", "name": "Hot Rod", "price": 3400, "shape": "hotrod", "body": "2f2b38", "accent": "c9a37a", "hub": "ff6b3d", "grip": 1.05, "drift": 1.2, "bounce": 1.0},
	{"id": "monster", "name": "Monster", "price": 4000, "shape": "monster", "body": "9b6fd6", "accent": "3a3540", "hub": "ffd166", "grip": 1.1, "drift": 1.0, "bounce": 1.5},
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
