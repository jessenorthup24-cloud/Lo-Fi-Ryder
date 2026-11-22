extends RefCounted
## Everything that persists between runs, in user://save.json.

const PATH := "user://save.json"
const UPGRADES := ["tank", "grip", "magnet", "wind"]
const UPGRADE_INFO := {
	"tank": {"name": "Fuel Tank", "desc": "Drive farther between refills"},
	"grip": {"name": "Grippy Tires", "desc": "More control on rain and ice"},
	"magnet": {"name": "Coin Magnet", "desc": "Pull in coins from farther away"},
	"wind": {"name": "Wind Fins", "desc": "Gusts push you around less"},
}
const UPGRADE_COST := [120, 300, 600, 1000, 1600]
const MAX_LEVEL := 5

var data := {}

func _init() -> void:
	data = defaults()

static func defaults() -> Dictionary:
	return {
		"version": 1,
		"coins": 0,
		"owned": ["bug"],
		"car": "bug",
		"up": {"tank": 0, "grip": 0, "magnet": 0, "wind": 0},
		"best": 0,
		"best_dist": 0,
		"runs": 0,
		"missions": [],
		"missions_done": 0,
		"daily": {"date": "", "best": 0, "best_dist": 0, "runs": 0},
		"settings": {"music": 0.75, "sfx": 0.9, "haptics": true, "shadows": true},
		"ghost": [],
		"daily_ghost": [],
		"stats": {"distance": 0.0, "coins": 0, "drift": 0.0, "spins": 0, "jumps": 0},
		"ach": {},
	}

func load_data() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var v = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (v is Dictionary):
		return
	var d := defaults()
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

func reset() -> void:
	var keep: Dictionary = data["settings"].duplicate()
	data = defaults()
	data["settings"] = keep
	save()
