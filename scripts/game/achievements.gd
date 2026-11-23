extends RefCounted
## Trophies. Each one watches a lifetime stat (or something about the garage) and pays coins once.

const CARS := preload("res://scripts/game/cars.gd")

const LIST := [
	{"id": "first", "name": "Sideways", "desc": "Bank your first drift", "icon": "tire", "stat": "drifts", "target": 1, "reward": 50},
	{"id": "d1k", "name": "Smoky", "desc": "Bank a 1,000 point drift", "icon": "tire", "stat": "max_drift", "target": 1000, "reward": 80},
	{"id": "d5k", "name": "Long Slide", "desc": "Bank a 5,000 point drift", "icon": "tire", "stat": "max_drift", "target": 5000, "reward": 200},
	{"id": "d20k", "name": "Endless Smoke", "desc": "Bank a 20,000 point drift", "icon": "tire", "stat": "max_drift", "target": 20000, "reward": 600},
	{"id": "x5", "name": "Combo Chef", "desc": "Reach a x5 drift combo", "icon": "star", "stat": "max_combo", "target": 5, "reward": 120},
	{"id": "x10", "name": "Combo King", "desc": "Reach a x10 drift combo", "icon": "star", "stat": "max_combo", "target": 10, "reward": 400},
	{"id": "t50k", "name": "Rubber Burner", "desc": "Drift 50,000 points in total", "icon": "tire", "stat": "drift_points", "target": 50000, "reward": 150},
	{"id": "t500k", "name": "Tyre Shop Regular", "desc": "Drift 500,000 points in total", "icon": "tire", "stat": "drift_points", "target": 500000, "reward": 600},
	{"id": "t5m", "name": "Drift Legend", "desc": "Drift 5,000,000 points in total", "icon": "trophy", "stat": "drift_points", "target": 5000000, "reward": 2500},
	{"id": "kmh100", "name": "Ton Up", "desc": "Hit 100 km/h", "icon": "wind", "stat": "max_kmh", "target": 100, "reward": 60},
	{"id": "kmh150", "name": "Flat Out", "desc": "Hit 150 km/h", "icon": "wind", "stat": "max_kmh", "target": 150, "reward": 250},
	{"id": "air1", "name": "Liftoff", "desc": "Spend a second in the air", "icon": "star", "stat": "max_air", "target": 1.0, "reward": 100},
	{"id": "air2", "name": "Frequent Flyer", "desc": "Spend 2 seconds in the air", "icon": "star", "stat": "max_air", "target": 2.0, "reward": 300},
	{"id": "km10", "name": "Sunday Drive", "desc": "Drive 10 km", "icon": "car", "stat": "distance", "target": 10000, "reward": 100},
	{"id": "km100", "name": "Island Regular", "desc": "Drive 100 km", "icon": "car", "stat": "distance", "target": 100000, "reward": 800},
	{"id": "places", "name": "Tourist", "desc": "Find every place on the island", "icon": "map", "stat": "places", "target": 12, "reward": 400},
	{"id": "coins10", "name": "Treasure Hunter", "desc": "Find 10 hidden coins", "icon": "coin", "stat": "coins_found", "target": 10, "reward": 100},
	{"id": "coins_all", "name": "Every Last One", "desc": "Find every hidden coin", "icon": "coin", "stat": "coins_found", "target": -1, "reward": 1500},
	{"id": "zone1", "name": "In The Zone", "desc": "Earn a medal in a drift zone", "icon": "flag", "stat": "zone_medals", "target": 1, "reward": 100},
	{"id": "zone_gold", "name": "Zone Master", "desc": "Gold in every drift zone", "icon": "trophy", "stat": "zone_golds", "target": 6, "reward": 1500},
	{"id": "trial1", "name": "On The Clock", "desc": "Finish a trial", "icon": "flag", "stat": "trial_medals", "target": 1, "reward": 100},
	{"id": "trial_gold", "name": "Trial Ace", "desc": "Gold in every trial", "icon": "trophy", "stat": "trial_golds", "target": 4, "reward": 1500},
	{"id": "knock50", "name": "Bull In A China Shop", "desc": "Knock over 50 things", "icon": "leaf", "stat": "knocks", "target": 50, "reward": 80},
	{"id": "night", "name": "Night Owl", "desc": "Drive 5 km at night", "icon": "moon", "stat": "night", "target": 5000, "reward": 150},
	{"id": "cars3", "name": "Collector", "desc": "Own 3 cars", "icon": "car", "stat": "owned", "target": 3, "reward": 200},
	{"id": "cars_all", "name": "Full Garage", "desc": "Own every car", "icon": "car", "stat": "owned", "target": -1, "reward": 3000},
	{"id": "maxup", "name": "Tuned Up", "desc": "Max out an upgrade", "icon": "gear", "stat": "maxup", "target": 5, "reward": 300},
]

static var coin_total := 60

static func target(a: Dictionary) -> float:
	if int(a["target"]) < 0:
		return float(CARS.LIST.size()) if a["stat"] == "owned" else float(coin_total)
	return float(a["target"])

static func value(a: Dictionary, data: Dictionary) -> float:
	var key: String = a["stat"]
	match key:
		"owned":
			return float(data["owned"].size())
		"maxup":
			var m := 0
			for u in data["up"]:
				m = maxi(m, int(data["up"][u]))
			return float(m)
		"places":
			return float(data["places"].size())
		"coins_found":
			return float(data["coins_taken"].size())
	return float(data["stats"].get(key, 0))

static func unlocked(data: Dictionary, id: String) -> bool:
	return bool(data["ach"].get(id, false))

static func count(data: Dictionary) -> int:
	var n := 0
	for a in LIST:
		if unlocked(data, a["id"]):
			n += 1
	return n

## Unlock everything that's now reached; pays the coins into the save. Returns the new ones.
static func check(data: Dictionary) -> Array:
	var out := []
	for a in LIST:
		if unlocked(data, a["id"]):
			continue
		if value(a, data) >= target(a):
			data["ach"][a["id"]] = true
			data["coins"] = int(data["coins"]) + int(a["reward"])
			out.append(a)
	return out
