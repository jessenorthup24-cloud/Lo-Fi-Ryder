extends RefCounted
## Lifetime achievements. Each one watches a stat: a lifetime total, a best-in-one-run ("max_" keys),
## or something about the garage. Unlocking pays coins once. Progress during a run counts live.

const CARS := preload("res://scripts/game/cars.gd")

const LIST := [
	{"id": "first_run", "name": "First Spin", "desc": "Finish your first run", "icon": "flag", "stat": "runs", "target": 1, "reward": 20},
	{"id": "d500", "name": "Sunday Driver", "desc": "Drive 500 m in one run", "icon": "map", "stat": "max_dist", "target": 500, "reward": 50},
	{"id": "d1000", "name": "Long Haul", "desc": "Drive 1,000 m in one run", "icon": "map", "stat": "max_dist", "target": 1000, "reward": 120},
	{"id": "d2000", "name": "Horizon Chaser", "desc": "Drive 2,000 m in one run", "icon": "map", "stat": "max_dist", "target": 2000, "reward": 300},
	{"id": "total10k", "name": "Road Trip", "desc": "Drive 10 km in total", "icon": "car", "stat": "distance", "target": 10000, "reward": 150},
	{"id": "total50k", "name": "Cross Country", "desc": "Drive 50 km in total", "icon": "car", "stat": "distance", "target": 50000, "reward": 500},
	{"id": "fast", "name": "Fast Lane", "desc": "Cruise at 50 km/h", "icon": "wind", "stat": "max_kmh", "target": 50, "reward": 80},
	{"id": "faster", "name": "Speed Demon", "desc": "Cruise at 55 km/h", "icon": "wind", "stat": "max_kmh", "target": 55, "reward": 200},
	{"id": "coins500", "name": "Piggy Bank", "desc": "Collect 500 coins in total", "icon": "coin", "stat": "coins", "target": 500, "reward": 60},
	{"id": "coins100", "name": "Coin Rush", "desc": "Collect 100 coins in one run", "icon": "coin", "stat": "max_coins_run", "target": 100, "reward": 120},
	{"id": "drift3", "name": "Sideways", "desc": "Hold one drift for 3 seconds", "icon": "tire", "stat": "max_drift", "target": 3, "reward": 60},
	{"id": "chain3", "name": "Snake Charmer", "desc": "Link a drift chain x3", "icon": "tire", "stat": "max_chain", "target": 3, "reward": 80},
	{"id": "drift300", "name": "Tire Smoke", "desc": "Drift for 5 minutes in total", "icon": "tire", "stat": "drift", "target": 300, "reward": 150},
	{"id": "jumps50", "name": "Hang Time", "desc": "Fly off 50 ramps", "icon": "star", "stat": "jumps", "target": 50, "reward": 80},
	{"id": "spin720", "name": "Twirl", "desc": "Land a 720° air spin", "icon": "star", "stat": "spin720", "target": 1, "reward": 100},
	{"id": "spins25", "name": "Merry-Go-Round", "desc": "Land 25 air spins", "icon": "star", "stat": "spins", "target": 25, "reward": 120},
	{"id": "clean25", "name": "Feather Landing", "desc": "Make 25 clean landings", "icon": "check", "stat": "clean", "target": 25, "reward": 80},
	{"id": "near50", "name": "Close Shave", "desc": "Get 50 close calls", "icon": "vibe", "stat": "near", "target": 50, "reward": 80},
	{"id": "knock100", "name": "Clumsy Cruiser", "desc": "Knock over 100 things", "icon": "leaf", "stat": "knocks", "target": 100, "reward": 60},
	{"id": "plank1", "name": "Tightrope", "desc": "Cross a skinny plank bridge", "icon": "flag", "stat": "planks", "target": 1, "reward": 60},
	{"id": "track1", "name": "Race Day", "desc": "Finish a toy race track", "icon": "flag", "stat": "tracks", "target": 1, "reward": 60},
	{"id": "deck10", "name": "Daredevil", "desc": "Cross 10 bridges or tracks", "icon": "trophy", "stat": "decks", "target": 10, "reward": 200},
	{"id": "grind100", "name": "Rail Rider", "desc": "Grind 100 m of rails", "icon": "star", "stat": "grind", "target": 100, "reward": 120},
	{"id": "gauntlet1", "name": "Gauntlet Runner", "desc": "Clear a gauntlet: ramp, rail, bridge, canyon", "icon": "trophy", "stat": "gauntlets", "target": 1, "reward": 150},
	{"id": "copfall", "name": "Lead Them Astray", "desc": "Watch a cruiser go over the edge", "icon": "flag", "stat": "police_fell", "target": 1, "reward": 80},
	{"id": "chase1", "name": "Getaway", "desc": "Escape a police chase", "icon": "flag", "stat": "chases", "target": 1, "reward": 80},
	{"id": "chase5", "name": "Most Wanted", "desc": "Escape 5 police chases", "icon": "trophy", "stat": "chases", "target": 5, "reward": 250},
	{"id": "regions4", "name": "Globetrotter", "desc": "Visit all 4 regions in one run", "icon": "map", "stat": "max_regions", "target": 4, "reward": 250},
	{"id": "stations10", "name": "Pit Stop", "desc": "Refuel at 10 gas stations", "icon": "fuel", "stat": "stations", "target": 10, "reward": 80},
	{"id": "night1k", "name": "Night Owl", "desc": "Drive 1,000 m at night", "icon": "moon", "stat": "night", "target": 1000, "reward": 100},
	{"id": "weather1k", "name": "All Weather", "desc": "Drive 1,000 m in rough weather", "icon": "rain", "stat": "weather", "target": 1000, "reward": 100},
	{"id": "score5k", "name": "High Roller", "desc": "Score 5,000 in one run", "icon": "trophy", "stat": "max_score", "target": 5000, "reward": 200},
	{"id": "daily1", "name": "Daily Driver", "desc": "Drive a daily run", "icon": "calendar", "stat": "daily_runs", "target": 1, "reward": 30},
	{"id": "cars5", "name": "Collector", "desc": "Own 5 cars", "icon": "car", "stat": "owned", "target": 5, "reward": 150},
	{"id": "cars_all", "name": "Full Garage", "desc": "Own every car", "icon": "car", "stat": "owned", "target": -1, "reward": 1000},
	{"id": "maxup", "name": "Tuned Up", "desc": "Max out an upgrade", "icon": "gear", "stat": "maxup", "target": 5, "reward": 200},
]

static func target(a: Dictionary) -> float:
	if a["stat"] == "owned" and int(a["target"]) < 0:
		return float(CARS.LIST.size())
	return float(a["target"])

## Current progress toward a, counting the run in progress (live) on top of the saved stats.
static func value(a: Dictionary, data: Dictionary, live: Dictionary) -> float:
	var key: String = a["stat"]
	match key:
		"runs":
			return float(data["runs"])
		"owned":
			return float(data["owned"].size())
		"maxup":
			var m := 0
			for u in data["up"]:
				m = maxi(m, int(data["up"][u]))
			return float(m)
	var base := float(data["stats"].get(key, 0))
	if live.has(key):
		if key.begins_with("max_"):
			base = maxf(base, float(live[key]))
		else:
			base += float(live[key])
	return base

static func unlocked(data: Dictionary, id: String) -> bool:
	return bool(data["ach"].get(id, false))

static func count(data: Dictionary) -> int:
	var n := 0
	for a in LIST:
		if unlocked(data, a["id"]):
			n += 1
	return n

## Unlock everything that's now reached; pays the coins into the save. Returns the new ones.
static func check(data: Dictionary, live: Dictionary) -> Array:
	var out := []
	for a in LIST:
		if unlocked(data, a["id"]):
			continue
		if value(a, data, live) >= target(a):
			data["ach"][a["id"]] = true
			data["coins"] = int(data["coins"]) + int(a["reward"])
			out.append(a)
	return out

## Fold a finished run's counters into the lifetime stats.
static func fold(data: Dictionary, live: Dictionary) -> void:
	var st: Dictionary = data["stats"]
	for key in live:
		if key.begins_with("max_"):
			st[key] = maxf(float(st.get(key, 0)), float(live[key]))
		else:
			st[key] = float(st.get(key, 0)) + float(live[key])
