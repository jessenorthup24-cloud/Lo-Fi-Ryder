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
	{"id": "flip1", "name": "Head Over Wheels", "desc": "Land a flip or a barrel roll", "icon": "star", "stat": "flips", "target": 1, "reward": 120},
	{"id": "flip2", "name": "Double Trouble", "desc": "Two flips or rolls in one jump", "icon": "star", "stat": "max_flips", "target": 2, "reward": 300},
	{"id": "flip50", "name": "Stunt Double", "desc": "Land 50 flips and rolls", "icon": "trophy", "stat": "flips", "target": 50, "reward": 800},
	{"id": "loop", "name": "Loop The Loop", "desc": "Go all the way round the loop", "icon": "star", "stat": "loops", "target": 1, "reward": 150},
	{"id": "hoop", "name": "Golden Ticket", "desc": "Fly through the gold hoop", "icon": "star", "stat": "hoops", "target": 1, "reward": 200},
	{"id": "s5k", "name": "Showboat", "desc": "Land a 5,000 point stunt", "icon": "trophy", "stat": "max_stunt", "target": 5000, "reward": 400},
	{"id": "win1", "name": "Street King", "desc": "Win a race", "icon": "trophy", "stat": "race_wins", "target": 1, "reward": 400},
	{"id": "hard1", "name": "Hardcore", "desc": "Win a race on Hard", "icon": "trophy", "stat": "hard_wins", "target": 1, "reward": 800},
	{"id": "race_gold", "name": "Grand Champion", "desc": "Win every race (any difficulty)", "icon": "trophy", "stat": "race_golds", "target": -1, "reward": 2500},
	{"id": "esc1", "name": "Clean Getaway", "desc": "Lose the police", "icon": "eye", "stat": "escapes", "target": 1, "reward": 250},
	{"id": "esc10", "name": "Ghost Of The Streets", "desc": "Lose the police 10 times", "icon": "eye", "stat": "escapes", "target": 10, "reward": 900},
	{"id": "heat5", "name": "Most Wanted", "desc": "Reach five wanted stars", "icon": "star", "stat": "max_heat", "target": 5, "reward": 600},
	{"id": "kmh100", "name": "Ton Up", "desc": "Hit 100 km/h", "icon": "wind", "stat": "max_kmh", "target": 100, "reward": 60},
	{"id": "kmh150", "name": "Flat Out", "desc": "Hit 150 km/h", "icon": "wind", "stat": "max_kmh", "target": 150, "reward": 250},
	{"id": "air1", "name": "Liftoff", "desc": "Spend a second in the air", "icon": "star", "stat": "max_air", "target": 1.0, "reward": 100},
	{"id": "air2", "name": "Frequent Flyer", "desc": "Spend 2 seconds in the air", "icon": "star", "stat": "max_air", "target": 2.0, "reward": 300},
	{"id": "km10", "name": "Sunday Drive", "desc": "Drive 10 km", "icon": "car", "stat": "distance", "target": 10000, "reward": 100},
	{"id": "km100", "name": "Island Regular", "desc": "Drive 100 km", "icon": "car", "stat": "distance", "target": 100000, "reward": 800},
	{"id": "places", "name": "Tourist", "desc": "Find every place on the island", "icon": "map", "stat": "places", "target": -1, "reward": 400},
	{"id": "coins10", "name": "Treasure Hunter", "desc": "Find 10 hidden cash stashes", "icon": "coin", "stat": "coins_found", "target": 10, "reward": 100},
	{"id": "coins_all", "name": "Every Last One", "desc": "Find every hidden cash stash", "icon": "coin", "stat": "coins_found", "target": -1, "reward": 1500},
	{"id": "zone1", "name": "In The Zone", "desc": "Earn a medal in a drift zone", "icon": "flag", "stat": "zone_medals", "target": 1, "reward": 100},
	{"id": "zone_gold", "name": "Zone Master", "desc": "Gold in every zone", "icon": "trophy", "stat": "zone_golds", "target": -1, "reward": 1500},
	{"id": "trial1", "name": "On The Clock", "desc": "Finish a trial", "icon": "flag", "stat": "trial_medals", "target": 1, "reward": 100},
	{"id": "trial_gold", "name": "Trial Ace", "desc": "Gold in every trial", "icon": "trophy", "stat": "trial_golds", "target": -1, "reward": 1500},
	{"id": "close10", "name": "Paint Trader", "desc": "Drift close to a wall or car 10 times", "icon": "tire", "stat": "close_calls", "target": 10, "reward": 150},
	{"id": "close100", "name": "Wall Kisser", "desc": "Drift close to a wall or car 100 times", "icon": "trophy", "stat": "close_calls", "target": 100, "reward": 700},
	{"id": "knock50", "name": "Bull In A China Shop", "desc": "Knock over 50 things", "icon": "leaf", "stat": "knocks", "target": 50, "reward": 80},
	{"id": "night", "name": "Night Owl", "desc": "Drive 5 km at night", "icon": "moon", "stat": "night", "target": 5000, "reward": 150},
	{"id": "cars3", "name": "Collector", "desc": "Own 3 cars", "icon": "car", "stat": "owned", "target": 3, "reward": 200},
	{"id": "cars_all", "name": "Full Garage", "desc": "Own every car", "icon": "car", "stat": "owned", "target": -1, "reward": 3000},
	{"id": "maxup", "name": "Tuned Up", "desc": "Max out an upgrade", "icon": "gear", "stat": "maxup", "target": 5, "reward": 300},
	{"id": "grind1", "name": "Rail Rat", "desc": "Hop onto a rail and grind it", "icon": "star", "stat": "grinds", "target": 1, "reward": 100},
	{"id": "grind25", "name": "Grind Lord", "desc": "Grind 25 rails", "icon": "trophy", "stat": "grinds", "target": 25, "reward": 500},
	{"id": "crew1", "name": "Squad Up", "desc": "Call a driver to ride with you", "icon": "phone", "stat": "crew_rides", "target": 1, "reward": 100},
	{"id": "crew20", "name": "Ride Or Die", "desc": "Ride with your crew 20 times", "icon": "group", "stat": "crew_rides", "target": 20, "reward": 500},
	{"id": "legend", "name": "Living Legend", "desc": "Own a legendary car", "icon": "car", "stat": "legends", "target": 1, "reward": 1000},
]

static var coin_total := 60
static var totals := {"places": 13, "zone_golds": 7, "trial_golds": 6, "race_golds": 8}   # (set from the island when it's built)

## "Every one" trophies count however many there are on the island.
static func target(a: Dictionary) -> float:
	if int(a["target"]) < 0:
		match String(a["stat"]):
			"owned":
				return float(CARS.LIST.size())
			"coins_found":
				return float(coin_total)
		return float(totals.get(a["stat"], 1))
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
		"legends":
			var n := 0
			for id in data["owned"]:
				if bool(CARS.by_id(String(id)).get("legend", false)):
					n += 1
			return float(n)
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
