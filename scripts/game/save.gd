extends RefCounted
## Everything that persists, in user://save.json.

const PATH := "user://save.json"
const UPGRADES := ["engine", "turbo", "tyres", "steering", "nitrous"]
const UPGRADE_INFO := {
	"engine": {"name": "Engine Tune", "desc": "More pull out of corners and drifts", "icon": "gear"},
	"turbo": {"name": "Turbo", "desc": "A higher top speed", "icon": "wind"},
	"tyres": {"name": "Sport Tyres", "desc": "More grip when you want it", "icon": "tire"},
	"steering": {"name": "Angle Kit", "desc": "More steering lock for deeper drifts", "icon": "star"},
	"nitrous": {"name": "Nitrous Tank", "desc": "A bigger bottle: longer boosts", "icon": "wind"},
}
const NEON_KIT := 400
const UPGRADE_COST := [250, 600, 1200, 2200, 3600]
const MAX_LEVEL := 5
const OLD_UPGRADE_COST := [120, 300, 600, 1000, 1600]

var data := {}

func _init() -> void:
	data = defaults()

static func defaults() -> Dictionary:
	return {
		"version": 2,
		"coins": 0,
		"owned": ["bug"],
		"car": "bug",
		"up": {"engine": 0, "turbo": 0, "tyres": 0, "steering": 0, "nitrous": 0},
		"tune": {},           # car id -> {"camber": 0..5, "height": -2..2, "neon": 0 (off) or a colour}
		"neon_kit": false,    # bought the underglow (all cars)
		"settings": {"music": 0.75, "sfx": 0.9, "haptics": true, "shadows": true, "assist": true, "cam": 0, "clock": true, "speedfx": true, "fps": false},
		"stats": {},
		"zones": {},          # zone id -> best score
		"trials": {},         # trial id -> best (time or points)
		"races": {},          # race id -> best time
		"medals": {},         # id -> 0 none, 1 bronze, 2 silver, 3 gold
		"coins_taken": [],
		"places": [],
		"ach": {},
		"pos": [],            # where you parked last time [x, y, z, yaw]
		"paint": {},          # car id -> paint job it's wearing (0: factory)
		"paints": {},         # car id -> [paint jobs bought]
		"seen_help": false,
	}

func load_data() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var v = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (v is Dictionary):
		return
	var d := defaults()
	if int(v.get("version", 1)) < 2:
		# from the endless-road days: keep your coins and cars, refund the old upgrades, retire the old trophies
		d["coins"] = int(v.get("coins", 0))
		d["owned"] = v.get("owned", ["bug"])
		d["car"] = String(v.get("car", "bug"))
		if v.get("settings") is Dictionary:
			for k in v["settings"]:
				d["settings"][k] = v["settings"][k]
		if v.get("up") is Dictionary:
			for u in v["up"]:
				for l in int(v["up"][u]):
					d["coins"] += OLD_UPGRADE_COST[mini(l, OLD_UPGRADE_COST.size() - 1)]
		d["migrated"] = true
		data = d
		return
	_merge(d, v)
	data = d

func _merge(into: Dictionary, from: Dictionary) -> void:
	for k in from:
		if into.has(k) and into[k] is Dictionary and from[k] is Dictionary:
			_merge(into[k], from[k])
		else:
			into[k] = from[k]

func save() -> void:
	var f := FileAccess.open(PATH + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH + ".tmp"), ProjectSettings.globalize_path(PATH))

func level(u: String) -> int:
	return int(data["up"].get(u, 0))

func upgrade_cost(u: String) -> int:
	var l := level(u)
	return UPGRADE_COST[l] if l < MAX_LEVEL else -1

func setting(k: String):
	return data["settings"].get(k)

func owns(id: String) -> bool:
	return data["owned"].has(id)

func stat(k: String) -> float:
	return float(data["stats"].get(k, 0.0))

func add_stat(k: String, v: float) -> void:
	data["stats"][k] = stat(k) + v

func max_stat(k: String, v: float) -> void:
	data["stats"][k] = maxf(stat(k), v)

func reset() -> void:
	var keep: Dictionary = data["settings"].duplicate()
	data = defaults()
	data["settings"] = keep
	save()
