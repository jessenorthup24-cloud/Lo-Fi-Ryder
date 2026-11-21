extends RefCounted
## Three missions at a time. Each is checked against the current run's counters; finished ones pay
## out right away and are replaced when the run ends.

# type: [text with {n}, targets by tier, counter key]
const TYPES := {
	"dist": ["Drive {n} m in one run", [250, 400, 600, 850, 1100, 1400, 1800, 2300, 3000], "dist"],
	"coins": ["Collect {n} coins in one run", [15, 25, 40, 55, 75, 100, 130], "coins"],
	"drift": ["Drift for {n} seconds in one run", [4, 8, 12, 18, 25, 35], "drift"],
	"near": ["Get {n} near misses in one run", [3, 6, 10, 15, 22], "near"],
	"clean": ["Land {n} clean landings in one run", [2, 3, 5, 7, 10], "clean"],
	"spin": ["Land {n} air spins in one run", [1, 2, 3, 5, 8], "spins"],
	"spin720": ["Land a 720° spin", [1, 1, 2, 3], "spin720"],
	"stations": ["Refuel at {n} gas stations in one run", [1, 2, 3, 4, 5], "stations"],
	"knock": ["Knock over {n} things in one run", [5, 10, 16, 24, 35], "knocks"],
	"jumps": ["Fly off {n} ramps in one run", [2, 4, 6, 9, 12], "jumps"],
	"night": ["Drive {n} m at night", [120, 250, 400, 600], "night"],
	"regions": ["Visit {n} regions in one run", [2, 3, 4, 5], "regions"],
	"weather": ["Drive {n} m through rough weather", [80, 160, 280, 400], "weather"],
	"air": ["Stay in the air {n} s in one jump", [1, 1.1, 1.2, 1.3], "air_max"],
}

var save  # save.gd instance
var rng := RandomNumberGenerator.new()

func _init(s) -> void:
	save = s
	rng.randomize()

func ensure() -> void:
	var list: Array = save.data["missions"]
	while list.size() < 3:
		list.append(_new_mission(list))

func _new_mission(existing: Array) -> Dictionary:
	var tier := int(save.data["missions_done"]) / 3
	var used := []
	for m in existing:
		used.append(m["type"])
	var keys := TYPES.keys().filter(func(k): return not used.has(k))
	var t: String = keys[rng.randi_range(0, keys.size() - 1)]
	var targets: Array = TYPES[t][1]
	var target = targets[mini(tier, targets.size() - 1)]
	var reward := 40 + mini(tier, 12) * 15
	return {"type": t, "target": target, "reward": reward, "done": false, "paid": false}

static func text(m: Dictionary) -> String:
	var n = m["target"]
	var s: String = TYPES[m["type"]][0]
	var ns := str(n) if (n is int or float(n) == floor(float(n))) else "%.1f" % float(n)
	if m["type"] == "air":
		ns = "%.1f" % float(n)
	var out := s.replace("{n}", ns)
	if ns == "1":
		for pl in [["stations", "station"], ["ramps", "ramp"], ["seconds", "second"], ["landings", "landing"], ["spins", "spin"], ["misses", "miss"], ["coins", "coin"], ["things", "thing"], ["regions", "region"]]:
			out = out.replace(" " + pl[0] + " ", " " + pl[1] + " ")
	return out

static func value(m: Dictionary, run: Dictionary) -> float:
	return float(run.get(TYPES[m["type"]][2], 0))

## Checks the run counters; returns missions finished just now.
func check(run: Dictionary) -> Array:
	var out := []
	for m in save.data["missions"]:
		if m["done"]:
			continue
		if value(m, run) >= float(m["target"]):
			m["done"] = true
			out.append(m)
	return out

## Pays finished missions (returns coins) and swaps them for new ones.
func settle() -> int:
	var coins := 0
	var list: Array = save.data["missions"]
	for m in list.duplicate():
		if m["done"]:
			if not m["paid"]:
				coins += int(m["reward"])
				m["paid"] = true
			list.erase(m)
			save.data["missions_done"] = int(save.data["missions_done"]) + 1
	ensure()
	return coins
