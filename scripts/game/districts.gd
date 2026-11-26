extends RefCounted
## What's where on the island. plan() lays out the roads, paved areas and named places before the land is
## shaped; populate() builds each district; scatter() grows the trees, rocks and grass in between.
## Coordinates are metres: x east, z south. The island is about 940 m across.

const M := preload("res://scripts/core/models.gd")
const MB := preload("res://scripts/core/mesh_builder.gd")
const P := preload("res://scripts/core/palette.gd")
const CARS := preload("res://scripts/game/cars.gd")
const Raceway := preload("res://scripts/game/raceway.gd")
const Circuits := preload("res://scripts/game/circuits.gd")
const Hood := preload("res://scripts/game/hood.gd")
const StreetStunts := preload("res://scripts/game/street_stunts.gd")
const Green := preload("res://scripts/game/green.gd")

const CASTLE := Vector2(-30, -362)
const SQUARE := Vector2(-110, 30)
const SKATE := Vector2(70, 90)
const BEACH_LOT := Vector2(60, 338)     # the beach car park (a big open lot: room to drift)
const FARM_LOT := Vector2(238, -14)     # the farmyard
const PARK := Vector2(-50, 150)
const CITY_X := [-260.0, -200.0, -140.0, -80.0, -20.0, 40.0, 100.0]
const CITY_Z := [-60.0, 0.0, 60.0, 120.0, 180.0]
const AVENUES := [["Harbor Avenue", -260.0], ["Oak Avenue", -200.0], ["Elm Avenue", -140.0], ["Market Street", -80.0],
	["Pine Avenue", -20.0], ["Cedar Avenue", 40.0], ["Bay Avenue", 100.0]]
const STREETS := [["North Street", -60.0], ["King Street", 0.0], ["Queen Street", 120.0], ["South Street", 180.0]]
# what each city block holds: [x index, z index] -> kind
const BLOCKS := {
	Vector2i(1, 0): "core", Vector2i(2, 0): "core", Vector2i(1, 1): "core", Vector2i(3, 1): "core", Vector2i(3, 0): "shops",
	Vector2i(2, 1): "square", Vector2i(5, 2): "skate", Vector2i(3, 3): "park", Vector2i(5, 0): "res",
	Vector2i(0, 0): "res", Vector2i(0, 1): "mixed", Vector2i(4, 0): "mixed", Vector2i(4, 1): "shops", Vector2i(5, 1): "mixed",
	Vector2i(0, 2): "mixed", Vector2i(1, 2): "shops", Vector2i(2, 2): "shops", Vector2i(3, 2): "shops", Vector2i(4, 2): "shops",
	Vector2i(0, 3): "res", Vector2i(1, 3): "res", Vector2i(2, 3): "mixed", Vector2i(4, 3): "res", Vector2i(5, 3): "res",
}
const LAKE := Vector2(285, -255)
# the stunt yard, on the meadow between South Street and the beach
const STUNT := Vector2(-170, 254)
const STUNT_HS := Vector2(70, 42)
# gas stations: where the pumps' pad is (the model's origin), which way the shop sits (model +X), and the
# concrete forecourt [centre offset along the shop axis, half size (along, across)]
const STATIONS := [
	{"name": "Castle Road", "pad": Vector2(-43.8, -128.44), "yaw": PI * 0.5, "lot": false},
	{"name": "Coast Road", "pad": Vector2(-306, -20), "yaw": 0.0, "lot": true},
	{"name": "Beach Road", "pad": Vector2(-61, 240), "yaw": 0.0, "lot": true},
	{"name": "Main Street East", "pad": Vector2(345, 50), "yaw": 0.0, "lot": true},
]
const HOUSES := ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u"]
const SHOPS := ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n"]
const TOWNHOUSES := ["house-a", "house-b", "house-c", "tower-a", "tower-b", "tower-c", "tower-d"]
const PARKED := ["sedan", "sedan-sports", "hatchback-sports", "suv", "suv-luxury", "taxi", "van", "sedan", "delivery"]   # (no kit police cars: the police drive the patrol car)

# ---------------------------------------------------------------- the plan

static func plan(I) -> void:
	# areas kept flat (the land generator reads these)
	I.flats.append([Vector2(-80, 60), Vector2(190, 135), 45.0])      # the city
	I.flats.append([Vector2(-215, -160), Vector2(80, 70), 40.0])     # Maple Hills
	I.flats.append([Vector2(300, 90), Vector2(95, 165), 55.0])       # farms
	I.flats.append([Vector2(-60, 310), Vector2(230, 60), 40.0])      # beach front
	I.flats.append([Vector2(-55, -132), Vector2(26, 22), 25.0])      # gas station
	# ---- roads
	I.add_road("Ring Road", [Vector2(-300, 80), Vector2(-335, -80), Vector2(-290, -215), Vector2(-170, -255),
		Vector2(-60, -238), Vector2(70, -250), Vector2(200, -215), Vector2(330, -130), Vector2(385, 10), Vector2(380, 160),
		Vector2(300, 250), Vector2(160, 330), Vector2(0, 352), Vector2(-150, 348), Vector2(-260, 300), Vector2(-315, 200)], "ring", true)
	# (control points spaced evenly, so the curve never overshoots)
	I.add_road("Main Street", [Vector2(-306, 61), Vector2(-260, 60), Vector2(-200, 60), Vector2(-140, 60), Vector2(-80, 60),
		Vector2(-20, 60), Vector2(40, 60), Vector2(100, 60), Vector2(150, 58), Vector2(200, 46),
		Vector2(290, 38), Vector2(388, 30)], "main")
	# the city grid: avenues north-south every 60 m, streets east-west
	for av in AVENUES:
		var pts := []
		for z in CITY_Z:
			pts.append(Vector2(av[1], z))
		I.add_road(av[0], pts, "street")
	for st in STREETS:
		var pts2 := []
		for x in CITY_X:
			pts2.append(Vector2(x, st[1]))
		I.add_road(st[0], pts2, "street")
	I.add_road("Castle Road", [Vector2(-80, -60), Vector2(-80, -150), Vector2(-80, -237)], "road")
	I.add_road("Beach Road", [Vector2(-80, 180), Vector2(-80, 260), Vector2(-80, 350)], "road")
	# Maple Hills: a loop of houses, with ways in from the city, the west and the north
	I.add_road("Maple Loop", [Vector2(-255, -105), Vector2(-288, -150), Vector2(-268, -200), Vector2(-212, -222),
		Vector2(-152, -200), Vector2(-138, -150), Vector2(-165, -106)], "lane", true)
	I.add_road("Maple Way", [Vector2(-200, -60), Vector2(-204, -82), Vector2(-208, -103)], "lane")
	I.add_road("Willow Way", [Vector2(-288, -150), Vector2(-312, -146), Vector2(-332, -140)], "lane")
	I.add_road("Birch Court", [Vector2(-212, -222), Vector2(-205, -238), Vector2(-198, -251)], "lane")
	# up the castle hill: one lazy turn around it
	# a short way up off the ring road first, so the climb never runs alongside it
	var spiral := [Vector2(CASTLE.x, -240.0)]
	for k in 16:
		var t := float(k) / 16.0
		var a := deg_to_rad(90.0 + 360.0 * t)
		var r := 106.0 - 61.0 * t
		spiral.append(CASTLE + Vector2(cos(a), sin(a)) * r)
	# and a gentle swing in through the gate
	for q in [Vector2(6, 43), Vector2(0, 33), Vector2(0, 21), Vector2(0, 10)]:
		spiral.append(CASTLE + q)
	I.add_road("Castle Climb", spiral, "mountain")
	I.add_road("Pinewood Pass", [Vector2(200, -215), Vector2(212, -275), Vector2(250, -318), Vector2(310, -324),
		Vector2(352, -292), Vector2(368, -232), Vector2(352, -170), Vector2(330, -132)], "mountain")
	I.add_road("Camp Track", [Vector2(212, -272), Vector2(224, -266), Vector2(234, -258)], "dirt")
	I.add_road("Farm Track", [Vector2(290, 36), Vector2(292, 100), Vector2(290, 170), Vector2(300, 248)], "dirt")
	I.add_road("Field Lane", [Vector2(175, 132), Vector2(222, 132), Vector2(290, 132), Vector2(378, 136)], "dirt")
	I.add_road("Barn Lane", [Vector2(235, 44), Vector2(235, 8)], "dirt")
	I.add_road("Bowl Road", [Vector2(175, 48), Vector2(175, 163)], "road")
	I.add_road("Bowl Exit", [Vector2(175, 247), Vector2(180, 285), Vector2(190, 316)], "road")
	I.add_road("Harbour Road", [Vector2(-316, 192), Vector2(-338, 172), Vector2(-352, 166)], "road")
	I.add_road("Station Lane", [Vector2(-80, -132), Vector2(-58, -132)], "lane")
	I.add_road("Stunt Lane", [Vector2(-110, 180), Vector2(-110, 196), Vector2(-110, STUNT.y - STUNT_HS.y)], "yard")
	# ---- paved areas
	I.add_lot(SQUARE, Vector2(21, 21), I.S_COBBLE)                       # town square
	I.add_lot(Vector2(175, 205), Vector2(60, 42), I.S_ASPHALT)            # the Drift Bowl
	I.add_lot(SKATE, Vector2(21, 21), I.S_CONCRETE)                      # skate park
	I.add_lot(Vector2(-392, 162), Vector2(40, 30), I.S_CONCRETE)          # harbour
	I.raises.append([Vector2(-393, 162), Vector2(43, 34), 1.4, 5.0])     # its quay, built up level to the water
	I.add_lot(BEACH_LOT, Vector2(50, 30), I.S_ASPHALT)                    # beach car park (room to drift)
	I.add_lot(FARM_LOT, Vector2(48, 36), I.S_DIRT)                        # farmyard (room to drift)
	I.add_lot(CASTLE, Vector2(23, 23), I.S_COBBLE, 0.0, false)             # castle courtyard
	I.add_lot(Vector2(-46, -132), Vector2(13, 12), I.S_CONCRETE)          # gas station
	I.add_lot(Vector2(246, -246), Vector2(14, 10), I.S_DIRT)              # campsite
	I.add_lot(STUNT, STUNT_HS, I.S_CONCRETE)                              # the stunt yard
	Hood.plan(I)                                                          # Palmer Street, the Courts, the cemetery, Sycamore Heights
	Raceway.plan(I)                                                       # the Raceway, on its peninsula
	Circuits.plan(I)                                                      # three more circuits on headlands
	for st in STATIONS:
		if st["lot"]:
			var sp: Vector2 = st["pad"]
			var ax := Vector2(cos(float(st["yaw"])), -sin(float(st["yaw"])))
			I.add_lot(sp + ax * 3.0, Vector2(16, 10) if absf(ax.x) > 0.5 else Vector2(10, 16), I.S_CONCRETE)
	# ---- named places (found as you drive)
	I.places = [
		{"name": "Downtown", "pos": Vector3(-150, 0, -20), "r": 60.0},
		{"name": "Town Square", "pos": Vector3(SQUARE.x, 0, SQUARE.y), "r": 32.0},
		{"name": "City Park", "pos": Vector3(PARK.x, 0, PARK.y), "r": 30.0},
		{"name": "Maple Hills", "pos": Vector3(-215, 0, -158), "r": 80.0},
		{"name": "Castle Hill", "pos": Vector3(CASTLE.x, 0, CASTLE.y), "r": 70.0},
		{"name": "Pinewood Lake", "pos": Vector3(LAKE.x, 0, LAKE.y), "r": 95.0},
		{"name": "Haybale Farms", "pos": Vector3(290, 0, 80), "r": 95.0},
		{"name": "The Drift Bowl", "pos": Vector3(175, 0, 205), "r": 62.0},
		{"name": "Skate Park", "pos": Vector3(SKATE.x, 0, SKATE.y), "r": 30.0},
		{"name": "Old Harbour", "pos": Vector3(-392, 0, 162), "r": 55.0},
		{"name": "Sunny Bay", "pos": Vector3(-40, 0, 385), "r": 110.0},
		{"name": "Lighthouse Point", "pos": Vector3(-300, 0, 322), "r": 40.0},
		{"name": "Stunt Yard", "pos": Vector3(STUNT.x, 0, STUNT.y), "r": 62.0},
	]
	I.places.append_array(Hood.places())

## Crop fields: ploughed soil with rows of something growing (districts._crops).
static func fields(_I) -> Array:
	return [
		{"c": Vector2(252, 92), "hs": Vector2(28, 26), "crop": "wheat"},
		{"c": Vector2(336, 92), "hs": Vector2(34, 26), "crop": "cabbage"},
		{"c": Vector2(266, 192), "hs": Vector2(16, 34), "crop": "corn"},
		{"c": Vector2(338, 192), "hs": Vector2(32, 34), "crop": "sunflower"},
		{"c": Vector2(336, -50), "hs": Vector2(26, 22), "crop": "potato"},
	]

## Drift zones, runs, time trials and coins (after the roads exist).
## The point on a road nearest to p.
static func _on_road(I, road: String, p: Vector2) -> Vector2:
	for r in I.roads:
		if r["name"] == road:
			var best := p
			var bd := INF
			for q: Vector2 in r["pts"]:
				if q.distance_squared_to(p) < bd:
					bd = q.distance_squared_to(p)
					best = q
			return best
	return p

static func challenges(I) -> void:
	I.zones = [
		{"id": "bowl", "name": "The Drift Bowl", "pos": Vector3(175, 0, 205), "r": 56.0, "time": 60.0, "medals": [6000, 15000, 30000]},
		{"id": "square", "name": "Town Square Loop", "pos": Vector3(SQUARE.x, 0, SQUARE.y), "r": 46.0, "time": 60.0, "medals": [4000, 10000, 20000]},
		{"id": "harbour", "name": "Harbour Lot", "pos": Vector3(-392, 0, 162), "r": 38.0, "time": 45.0, "medals": [3000, 8000, 16000]},
		{"id": "farmyard", "name": "Farmyard Donuts", "pos": Vector3(FARM_LOT.x, 0, FARM_LOT.y), "r": 50.0, "time": 60.0, "medals": [4000, 10000, 20000]},
		{"id": "beach", "name": "Beach Car Park", "pos": Vector3(BEACH_LOT.x, 0, BEACH_LOT.y), "r": 52.0, "time": 60.0, "medals": [4000, 10000, 20000]},
		{"id": "skate", "name": "Skate Park Jam", "pos": Vector3(SKATE.x, 0, SKATE.y), "r": 32.0, "time": 45.0, "medals": [2000, 6000, 12000]},
		{"id": "stunt", "name": "Stunt Yard Jam", "pos": Vector3(STUNT.x, 0, STUNT.y), "r": 66.0, "time": 75.0, "medals": [4000, 10000, 20000],
			"rect": Rect2(STUNT - STUNT_HS, STUNT_HS * 2.0)},
	]
	for z in I.zones:
		z["pos"].y = I.height_at(z["pos"].x, z["pos"].z)
	# street races: a loop of junction centres (the corners get rounded off), and where the start line is
	I.races = [
		{"id": "downtown", "name": "Downtown Loop", "laps": 3, "start": Vector2(-200, 60),
			"corners": [Vector2(-260, 60), Vector2(-80, 60), Vector2(-80, 120), Vector2(-140, 120), Vector2(-140, 180), Vector2(-260, 180)]},
	]
	# street races along the winding roads: places to pass through in turn (joined up along the roads)
	var ring := func(x: float, z: float) -> Vector2: return _on_road(I, "Ring Road", Vector2(x, z))
	I.races.append({"id": "ringroad", "name": "Ring Road Classic", "laps": 2, "start": ring.call(-60.0, 420.0),
		"route": [ring.call(-60.0, 420.0), ring.call(250.0, 330.0), ring.call(400.0, 60.0), ring.call(330.0, -260.0), ring.call(60.0, -470.0),
			ring.call(-250.0, -330.0), ring.call(-340.0, 0.0), ring.call(-300.0, 290.0)],
		"line_w": 3.6, "room": 4.4})
	I.races.append({"id": "northloop", "name": "Northern Loop", "laps": 2, "start": Vector2(-170, 61),
		"route": [Vector2(-170, 61), Vector2(110, 57), Vector2(330, 38), ring.call(400.0, -40.0), ring.call(330.0, -260.0), ring.call(60.0, -470.0),
			ring.call(-250.0, -330.0), ring.call(-340.0, -60.0)],
		"line_w": 3.0, "room": 3.6})
	I.races.append({"id": "beachloop", "name": "Beach Loop", "laps": 3, "start": Vector2(-80, 158),
		"route": [Vector2(-80, 158), Vector2(-80, 265), ring.call(-200.0, 380.0), ring.call(-320.0, 230.0), Vector2(-230, 61), Vector2(-80, 92)],
		"line_w": 2.9, "room": 3.4})
	# time trials and drift runs follow a road through gates
	I.trials = [
		_trial(I, "coast", "Coast Run", "Ring Road", Vector2(-316, 196), Vector2(300, 250), 6, "time", [42.0, 50.0, 62.0]),
		_trial(I, "pass", "Pinewood Pass", "Pinewood Pass", Vector2(200, -215), Vector2(330, -132), 5, "time", [24.0, 29.0, 36.0]),
		_trial(I, "climb", "Castle Climb", "Castle Climb", Vector2(-30, -237), CASTLE + Vector2(0, 30), 6, "drift", [5000, 12000, 22000]),
		_trial(I, "main", "Main Street Sprint", "Main Street", Vector2(-290, 62), Vector2(380, 30), 6, "time", [26.0, 31.0, 38.0]),
	]
	Raceway.challenges(I)
	Circuits.challenges(I)
	# coins hidden around the island
	var spots := []
	var rr := RandomNumberGenerator.new()
	rr.seed = 99
	for pl in I.places:
		if pl["name"] == "Stunt Yard":
			continue     # (coins at random there would land inside the ramps; it gets its own, below)
		var c: Vector3 = pl["pos"]
		for k in 4:
			for tries in 20:
				var a := rr.randf() * TAU
				var d := rr.randf_range(6.0, float(pl["r"]) * 0.8)
				var p := Vector3(c.x + cos(a) * d, 0, c.z + sin(a) * d)
				if I.height_at(p.x, p.z) > 0.5 and I.surface_at(p.x, p.z) != I.S_GRASS or tries == 19:
					spots.append(p)
					break
	# along the winding roads
	for r in I.roads:
		if r["kind"] != "mountain" and r["name"] != "Ring Road":
			continue
		var pts: PackedVector2Array = r["pts"]
		var step := 60 if r["kind"] == "mountain" else 110
		for k in range(30, pts.size() - 10, step):
			spots.append(Vector3(pts[k].x, 0, pts[k].y))
	for i in spots.size():
		var p: Vector3 = spots[i]
		p.y = I.height_at(p.x, p.z) + 1.3
		I.coin_spots.append({"id": "c%d" % i, "pos": p})
	# a few up in the stunt yard's air (after the rest, so the older coins keep their ids)
	var air: Array = I.stunt.get("coins", [])
	for i in air.size():
		I.coin_spots.append({"id": "c%d" % (spots.size() + i), "pos": air[i]})
	# where you start: Main Street, west end of town, facing east
	var sp := Vector3(-262, 0, 61)
	sp.y = I.height_at(sp.x, sp.z) + 0.8
	I.spawn = Transform3D(Basis(Vector3.UP, -PI * 0.5), sp)

static func _trial(I, id: String, name: String, road: String, a: Vector2, b: Vector2, n: int, kind: String, medals: Array) -> Dictionary:
	var r: Dictionary = {}
	for rd in I.roads:
		if rd["name"] == road:
			r = rd
	var pts: PackedVector2Array = r["pts"]
	var ia := _nearest(pts, a)
	var ib := _nearest(pts, b)
	var gates := []
	var dirn := 1 if ib >= ia else -1
	if r["closed"]:
		# go the short way round
		var fwd := posmod(ib - ia, pts.size())
		dirn = 1 if fwd <= pts.size() / 2 else -1
	var count := posmod((ib - ia) * dirn, pts.size()) if r["closed"] else absi(ib - ia)
	for g in n + 1:
		var k: int = posmod(ia + dirn * int(round(float(count) * g / n)), pts.size())
		var p := pts[k]
		var t: Vector2 = I._tangent(pts, k, r["closed"]) * dirn
		var y: float = I.height_at(p.x, p.y)
		gates.append(Transform3D(Basis(Vector3.UP, atan2(-t.x, -t.y)), Vector3(p.x, y, p.y)))
	return {"id": id, "name": name, "kind": kind, "gates": gates, "w": float(r["w"]), "medals": medals}

static func _nearest(pts: PackedVector2Array, p: Vector2) -> int:
	var best := 0
	var bd := 1e18
	for k in pts.size():
		var d := pts[k].distance_squared_to(p)
		if d < bd:
			bd = d
			best = k
	return best

# ---------------------------------------------------------------- helpers

static func _yaw_to(dir: Vector2) -> float:
	# a model's front (-Z) turned to face dir (x, z)
	return atan2(-dir.x, -dir.y)

static func _size(name: String) -> Vector3:
	return M.get_mesh(name).get_aabb().size

static func _road(I, name: String) -> Dictionary:
	for r in I.roads:
		if r["name"] == name:
			return r
	return {}

## Buildings along one side of a road, fronts to the road, packed with small gaps.
## side: +1 left of travel, -1 right. names: picked from in turn.
static func _row(I, road: String, side: float, from_t: float, to_t: float, names: Array, setback: float, rr: RandomNumberGenerator,
		gap := Vector2(1.0, 3.0), col := "box", landmark := false) -> Array:
	var r := _road(I, road)
	var pts: PackedVector2Array = r["pts"]
	var n := pts.size()
	var out := []
	# clear of the road, its pavement and the cells the road blocks
	setback = maxf(setback, float(r["w"]) * 0.5 + (3.0 if r["walk"] else 0.6) + 2.2)
	var k := int(from_t * (n - 1))
	var k_end := int(to_t * (n - 1))
	var guard := 0
	while k < k_end and guard < 200:
		guard += 1
		var nm: String = names[rr.randi_range(0, names.size() - 1)]
		var sz := _size(nm)
		var t: Vector2 = I._tangent(pts, k, r["closed"])
		var nrm := Vector2(-t.y, t.x) * side
		var steps := int(ceil((sz.x * 0.5 + gap.x) / I.CELL))
		var kc := mini(k + steps, n - 1)
		if kc >= k_end:
			break
		var p := pts[kc]
		t = I._tangent(pts, kc, r["closed"])
		nrm = Vector2(-t.y, t.x) * side
		var c := p + nrm * (setback + sz.z * 0.5)
		var yaw := _yaw_to(-nrm)
		if I.is_free(c, Vector2(sz.x * 0.5, sz.z * 0.5), yaw):
			I.put(nm, c.x, c.y, yaw, 1.0, col, -10000.0, landmark)
			I.block_rect(c, Vector2(sz.x * 0.5, sz.z * 0.5), yaw, 1.5)
			out.append({"name": nm, "c": c, "yaw": yaw, "n": nrm, "size": sz, "edge": setback - float(r["w"]) * 0.5})
			k = kc + int(ceil((sz.x * 0.5 + rr.randf_range(gap.x, gap.y)) / I.CELL))
		else:
			k += 2
	return out

## Things set at intervals along a road edge (lamps, parked cars...). Returns the spots.
static func _along(I, road: String, offset: float, spacing: float, start := 0.0) -> Array:
	var r := _road(I, road)
	var pts: PackedVector2Array = r["pts"]
	var out := []
	var step := maxi(1, int(spacing / I.CELL))
	for k in range(int(start / I.CELL), pts.size(), step):
		var t: Vector2 = I._tangent(pts, k, r["closed"])
		var nrm := Vector2(-t.y, t.x)
		out.append({"p": pts[k] + nrm * offset, "t": t, "n": nrm})
	return out

## A point is near a junction if two different roads pass close by.
static func _near_junction(I, p: Vector2, d := 12.0) -> bool:
	var hits := 0
	for r in I.roads:
		var pts: PackedVector2Array = r["pts"]
		for k in range(0, pts.size(), 2):
			if pts[k].distance_squared_to(p) < d * d:
				hits += 1
				break
	return hits >= 2

static func _person(I, x: float, z: float, pose := "stand", yaw := INF, y := 0.0) -> void:
	if I.audit_on:
		I.audit.append(["person " + pose, [Vector2(x, z)]])
	var pos := Vector3(x, I.height_at(x, z) + y, z)
	var pr: Dictionary = I.people.spawn(I.rng.randi_range(0, 99), pose, pos, I.rng.randf() * TAU if yaw == INF else yaw, 0)
	if pr.is_empty():
		return

static func _pet(I, animal: String, x: float, z: float) -> void:
	var nm := "k_pets_animal-" + animal
	var pr: Dictionary = I.add_anim(nm, Vector3(x, I.height_at(x, z), z), I.rng.randf() * TAU, 1.0)
	if pr.is_empty():
		return
	pr["kind"] = "critter"
	pr["style"] = {"bee": "hover", "parrot": "hover", "crab": "scuttle"}.get(animal, "hop")
	pr["home"] = pr["pos"]
	pr["cur"] = pr["yaw"]
	pr["vy"] = 0.0
	pr["y"] = 0.0
	pr["t"] = I.rng.randf_range(0.5, 3.0)
	pr["hv"] = Vector3.ZERO
	pr["squash"] = 0.0

# ---------------------------------------------------------------- building it all

static func populate(I) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 1234
	Circuits.reserve(I)
	_town(I, rr)
	_suburbs(I, rr)
	_castle(I, rr)
	_forest(I, rr)
	_farm(I, rr)
	_bowl(I, rr)
	_harbour(I, rr)
	_beach(I, rr)
	_stunt_yard(I, rr)
	Raceway.populate(I, rr)
	var rc := RandomNumberGenerator.new()
	rc.seed = 4242             # (their own seed: the rest of the island comes out as it always has)
	Circuits.populate(I, rc)
	_roadside(I, rr)
	Hood.populate(I, load("res://scripts/game/districts.gd"))
	Green.populate(I, load("res://scripts/game/districts.gd"))
	StreetStunts.populate(I, load("res://scripts/game/districts.gd"))
	challenges(I)

const STYLE := {
	"core": ["k_com_building-skyscraper-a", "k_com_building-skyscraper-b", "k_com_building-skyscraper-c", "k_com_building-skyscraper-d",
		"k_com_building-skyscraper-e", "k_com_building-l", "k_com_building-m", "k_com_building-i", "k_com_building-g", "k_com_building-f"],
	"shops": ["k_com_building-a", "k_com_building-b", "k_com_building-c", "k_com_building-d", "k_com_building-e", "k_com_building-f",
		"k_com_building-g", "k_com_building-h", "k_com_building-i", "k_com_building-k"],
	"res": ["k_mod_building-sample-house-a", "k_mod_building-sample-house-b", "k_mod_building-sample-house-c",
		"k_mod_building-sample-tower-a", "k_mod_building-sample-tower-b", "k_mod_building-sample-tower-c", "k_mod_building-sample-tower-d"],
	"mixed": ["k_mod_building-sample-tower-a", "k_mod_building-sample-tower-b", "k_mod_building-sample-tower-c",
		"k_mod_building-sample-house-c", "k_com_building-a", "k_com_building-b", "k_com_building-d", "k_com_building-h"],
}
const STRIP := {"core": 15.0, "shops": 14.0, "res": 11.5, "mixed": 13.0}

static func _town(I, rr: RandomNumberGenerator) -> void:
	# every block of the grid, filled side by side so nothing overlaps
	for xi in CITY_X.size() - 1:
		for zi in CITY_Z.size() - 1:
			var kind: String = BLOCKS.get(Vector2i(xi, zi), "mixed")
			var rect := _block_rect(I, xi, zi)
			match kind:
				"square":
					_square(I, rr, rect)
				"skate":
					_skatepark(I, rr)
				"park":
					_park(I, rr, rect)
				_:
					# the side on Main Street is always shops (or the tall ones downtown)
					var main_side := ""
					if zi == 1:
						main_side = "S"
					elif zi == 2:
						main_side = "N"
					_fill_block(I, rr, rect, kind, main_side)
	# street life. A pavement is 3 m wide: lamps stand at the kerb, people stop by the shop fronts, and the
	# middle is kept clear for walking.
	for road in _city_roads():
		var r := _road(I, road)
		var hw: float = r["w"] * 0.5
		var ri: int = I.roads.find(r)
		for side in [-1.0, 1.0]:
			for sp in _along(I, road, (hw + 0.45) * side, 24.0, 6.0 if side > 0 else 18.0):
				var p: Vector2 = sp["p"]
				if not _in_city(p) or _near_junction(I, p, 14.0) or I.on_carriageway(p, ri, 0.6):
					continue
				I.put_breakable("k_retro_detail-light-single", p.x, p.y, _yaw_to(-sp["n"] * side), 1.0, 0.3)
		var sgn := 1.0 if rr.randf() < 0.5 else -1.0
		for sp3 in _along(I, road, (hw + 2.65) * sgn, 40.0, 9.0):
			var p3: Vector2 = sp3["p"]
			if _in_city(p3) and rr.randf() < 0.5 and not _near_junction(I, p3, 12.0) and not I.on_carriageway(p3, ri, 0.8):
				_person(I, p3.x, p3.y, "stand", _yaw_to(-(sp3["n"] as Vector2) * sgn))
	# people out walking along the pavements
	for road in _city_roads():
		var r2 := _road(I, road)
		var pts: PackedVector2Array = r2["pts"]
		var hw2: float = r2["w"] * 0.5
		var ri2: int = I.roads.find(r2)
		var k := 4
		while k < pts.size() - 20:
			var len := rr.randi_range(12, 26)
			var side := 1.0 if rr.randf() < 0.5 else -1.0
			var path := PackedVector3Array()
			for q in range(k, mini(k + len, pts.size() - 1), 2):
				var t: Vector2 = I._tangent(pts, q, false)
				var pp := pts[q] + Vector2(-t.y, t.x) * (hw2 + 1.6) * side
				# along the pavement as far as the next kerb (nobody wanders into the traffic)
				if I.on_carriageway(pp, ri2, 0.5):
					break
				path.append(Vector3(pp.x, I.height_at(pp.x, pp.y) + 0.06, pp.y))
			if path.size() >= 3 and _in_city(Vector2(path[0].x, path[0].z)):
				I.people.spawn_walker(rr.randi_range(0, 99), path, rr.randf_range(1.1, 1.6))
			k += len + rr.randi_range(4, 14)
	_stations(I, rr)

## Gas stations: pull onto the pad by the pumps and stop to buy fuel and repairs (main.gd).
static func _stations(I, rr: RandomNumberGenerator) -> void:
	var sc := 4.0
	var ab: AABB = M.get_mesh("station").get_aabb()
	for st in STATIONS:
		var pad: Vector2 = st["pad"]
		var yaw: float = st["yaw"]
		var bs := Basis(Vector3.UP, yaw)
		# (put centres the model's footprint on x, z: aim it so its origin lands on the pad)
		var cen: Vector3 = bs * Vector3(ab.get_center().x, 0, ab.get_center().z) * sc
		var y: float = I.height_at(pad.x, pad.y)
		var xf: Transform3D = I.put("station", pad.x + cen.x, pad.y + cen.z, yaw, sc, "", y)
		# solid where it's solid: the shop, the two pumps, the canopy post and the sign post
		for b in [[Vector3(3.6, 0.8, 0.3), Vector3(2.0, 1.6, 2.4)], [Vector3(2.3, 0.45, -1.4), Vector3(0.38, 0.9, 0.3)],
				[Vector3(2.3, 0.45, -0.5), Vector3(0.38, 0.9, 0.3)]]:
			var c3: Vector3 = xf.origin + bs * ((b[0] as Vector3) * sc)
			I.add_box_collider(Transform3D(bs, c3), (b[1] as Vector3) * sc)
		for post in [Vector3(2.3, 0, -1.9), Vector3(-2.7, 0, 1.6)]:
			I.add_cyl_collider(xf.origin + bs * (post * sc), 0.3, 8.0)
		# where you stop to fill up: on the pad, beside the pumps
		var spot: Vector3 = xf.origin + bs * Vector3(0.9 * sc, 0, -0.9 * sc)
		I.stations.append({"name": st["name"], "pos": spot, "yaw": yaw})
		_person(I, xf.origin.x + (bs * Vector3(3.0 * sc, 0, 1.6 * sc)).x, xf.origin.z + (bs * Vector3(3.0 * sc, 0, 1.6 * sc)).z, "stand", yaw + PI * 0.5)

static func _city_roads() -> Array:
	var out := ["Main Street"]
	for av in AVENUES:
		out.append(av[0])
	for st in STREETS:
		out.append(st[0])
	return out

static func _in_city(p: Vector2) -> bool:
	return p.x > -268 and p.x < 108 and p.y > -68 and p.y < 188

## The buildable land of a block: inside its streets and pavements.
static func _block_rect(I, xi: int, zi: int) -> Rect2:
	var x0: float = CITY_X[xi]
	var x1: float = CITY_X[xi + 1]
	var z0: float = CITY_Z[zi]
	var z1: float = CITY_Z[zi + 1]
	var e := 8.4                         # half a street plus its pavement
	var em := 9.4                        # Main Street is wider
	return Rect2(x0 + e, z0 + (em if z0 == 60.0 else e), (x1 - x0) - 2.0 * e, (z1 - z0) - e - (em if z0 == 60.0 or z1 == 60.0 else e))

## Buildings shoulder to shoulder along all four sides of a block, fronts on the pavement.
## North and south rows run the full width; east and west rows fit between them.
static func _fill_block(I, rr: RandomNumberGenerator, rect: Rect2, kind: String, main_side: String) -> void:
	var depth: float = STRIP[kind]
	var sides := [
		["N", Vector2(rect.position.x, rect.position.y), Vector2(1, 0), Vector2(0, -1), rect.size.x],
		["S", Vector2(rect.end.x, rect.end.y), Vector2(-1, 0), Vector2(0, 1), rect.size.x],
		["W", Vector2(rect.position.x, rect.end.y - depth), Vector2(0, -1), Vector2(-1, 0), rect.size.y - 2.0 * depth],
		["E", Vector2(rect.end.x, rect.position.y + depth), Vector2(0, 1), Vector2(1, 0), rect.size.y - 2.0 * depth],
	]
	for sd in sides:
		var style: String = kind
		if sd[0] == main_side and kind != "core":
			style = "shops"
		_fill_side(I, rr, sd[1], sd[2], sd[3], sd[4], depth, STYLE[style], kind == "core")
	# the middle of the block: a car park, or a little garden
	var inner := rect.grow(-depth - 0.5)
	if inner.size.x > 8.0 and inner.size.y > 8.0:
		if kind == "res" or rr.randf() < 0.35:
			_garden(I, rr, inner)
		else:
			_carpark(I, rr, inner)

static func _fill_side(I, rr: RandomNumberGenerator, start: Vector2, along: Vector2, out: Vector2, length: float, depth: float,
		names: Array, core: bool) -> void:
	var pos := 0.0
	var last := ""
	var guard := 0
	while pos < length - 4.0 and guard < 40:
		guard += 1
		var room := length - pos
		var fits := []
		for nm in names:
			var sz := _size(nm)
			if sz.x <= room and sz.z <= depth and nm != last:
				fits.append(nm)
		if fits.is_empty():
			break
		var pick: String = fits[rr.randi_range(0, fits.size() - 1)]
		var sz2 := _size(pick)
		var c: Vector2 = start + along * (pos + sz2.x * 0.5) - out * (sz2.z * 0.5)
		var tall := sz2.y > 24.0
		I.put(pick, c.x, c.y, _yaw_to(out), 1.0, "box", -10000.0, core and tall)
		I.block_rect(c, Vector2(sz2.x * 0.5, sz2.z * 0.5), _yaw_to(out), 0.6)
		last = pick
		pos += sz2.x + rr.randf_range(0.3, 1.4)
	# what's left at the end of the row: a tree or a bench in the gap
	if length - pos > 3.0:
		var g: Vector2 = start + along * (pos + (length - pos) * 0.5) - out * 2.0
		I.put("k_castle_tree-small", g.x, g.y, rr.randf() * TAU, 0.6, "cyl")

static func _garden(I, rr: RandomNumberGenerator, r: Rect2) -> void:
	I.decal(r.get_center(), r.size * 0.5, 0.0, P.PATH)
	var n := int(clampf(r.size.x * r.size.y / 70.0, 1.0, 6.0))
	for k in n:
		var p := Vector2(rr.randf_range(r.position.x + 2.5, r.end.x - 2.5), rr.randf_range(r.position.y + 2.5, r.end.y - 2.5))
		I.put("k_castle_tree-large" if k % 2 == 0 else "k_sub_tree-large", p.x, p.y, rr.randf() * TAU, rr.randf_range(0.7, 0.9), "cyl")
	if r.size.x > 10.0:
		I.put_breakable("k_holi_bench", r.get_center().x, r.get_center().y, 0.0, 1.0, 0.8)
	I.block_rect(r.get_center(), r.size * 0.5, 0.0, 0.5)

static func _carpark(I, rr: RandomNumberGenerator, r: Rect2) -> void:
	I.decal(r.get_center(), r.size * 0.5, 0.0, P.ASPHALT_DK)
	var cols := int((r.size.x - 2.0) / 3.2)
	for k in cols:
		if rr.randf() < 0.65:
			var p := Vector2(r.position.x + 2.6 + k * 3.2, r.position.y + 3.0)
			if p.y < r.end.y - 2.0:
				I.put("k_car_" + PARKED[rr.randi_range(0, PARKED.size() - 1)], p.x, p.y, 0.0 if rr.randf() < 0.5 else PI, 1.0, "box")
	if r.size.y > 12.0:
		I.put("k_retro_detail-dumpster-closed", r.end.x - 2.0, r.end.y - 1.5, PI, 1.0, "box")
	I.block_rect(r.get_center(), r.size * 0.5, 0.0, 0.5)

## The town square: a statue on steps, trees in a ring, benches, café tables, a holiday tree in winter.
static func _square(I, rr: RandomNumberGenerator, rect: Rect2) -> void:
	var sq := rect.get_center()
	I.put("k_arena_stairs", sq.x, sq.y, 0.0, 1.6, "box")
	I.put("k_arena_statue", sq.x, sq.y, 0.0, 1.0, "box", I.height_at(sq.x, sq.y) + 1.25)
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		var tp := sq + Vector2(cos(a), sin(a)) * 15.5
		I.put("k_castle_tree-large", tp.x, tp.y, rr.randf() * TAU, 0.85, "cyl")
		var bp := sq + Vector2(cos(a + PI / 8.0), sin(a + PI / 8.0)) * 10.5
		I.put_breakable("k_retro_detail-bench", bp.x, bp.y, _yaw_to(sq - bp), 1.0, 0.9)
		if k % 2 == 0:
			_person(I, bp.x, bp.y, "sit", _yaw_to(sq - bp), 0.55)
	for k in 4:
		var cp := sq + Vector2([-17.0, 17.0][k % 2], [-17.0, 17.0][k / 2])
		I.put_breakable("k_com_detail-parasol-" + ("a" if k % 2 == 0 else "b"), cp.x, cp.y, rr.randf() * TAU, 1.0, 1.0)
		_person(I, cp.x + 1.4, cp.y, "stand", _yaw_to(Vector2(-1, 0)))
		I.put_breakable("k_retro_detail-light-double", sq.x + [-19.5, 19.5][k % 2], sq.y + [-6.0, 6.0][k / 2], 0.0, 1.0, 0.35)
	_pet(I, "dog", sq.x + 7, sq.y + 5)
	_pet(I, "cat", sq.x - 8, sq.y - 9)
	if I.season == 3:
		I.put("k_holi_tree-decorated", sq.x, sq.y - 12, 0.0, 1.2, "cyl")
		for k in 5:
			I.put_breakable(["k_holi_present-a-cube", "k_holi_present-b-round", "k_holi_present-a-rectangle"][k % 3],
				sq.x + rr.randf_range(-3, 3), sq.y - 12 + rr.randf_range(-3, 3), rr.randf() * TAU, 1.0, 0.4)
	I.block_rect(sq, rect.size * 0.5, 0.0, 0.0)

## The city park: lawns, trees in groups, paths, benches, people having a sit.
static func _park(I, rr: RandomNumberGenerator, rect: Rect2) -> void:
	var c := rect.get_center()
	I.decal(c, Vector2(rect.size.x * 0.5, 1.6), 0.0, P.PATH)
	I.decal(c, Vector2(1.6, rect.size.y * 0.5), 0.0, P.PATH)
	for q in 4:
		var qc := c + Vector2((q % 2) * 2 - 1, (q / 2) * 2 - 1) * rect.size * 0.25
		for k in 3:
			var p := qc + Vector2(rr.randf_range(-6, 6), rr.randf_range(-6, 6))
			I.put(["k_castle_tree-large", "k_surv_tree", "k_castle_tree-small"][k], p.x, p.y, rr.randf() * TAU, rr.randf_range(0.8, 1.0), "cyl")
		var bp := qc - ((qc - c).normalized() * 6.0)
		I.put_breakable("k_holi_bench", bp.x, bp.y, _yaw_to(c - bp), 1.0, 0.8)
		_person(I, bp.x, bp.y, "sit", _yaw_to(c - bp), 0.5)
	I.put("k_arena_statue", c.x, c.y, 0.0, 0.7, "box")
	_pet(I, "dog", c.x + 4, c.y + 6)
	_pet(I, "bunny", c.x - 9, c.y + 8)
	I.block_rect(c, rect.size * 0.5, 0.0, 0.0)

static func _suburbs(I, rr: RandomNumberGenerator) -> void:
	var houses := []
	for s in HOUSES:
		houses.append("k_sub_building-type-" + s)
	var placed := []
	for side in [-1.0, 1.0]:
		placed.append_array(_row(I, "Maple Loop", side, 0.0, 1.0, houses, 8.5, rr, Vector2(5.0, 9.0)))
	placed.append_array(_row(I, "Willow Way", 1.0, 0.25, 0.9, houses, 8.5, rr, Vector2(5.0, 9.0)))
	placed.append_array(_row(I, "Birch Court", -1.0, 0.1, 0.8, houses, 8.5, rr, Vector2(5.0, 9.0)))
	for h in placed:
		var c: Vector2 = h["c"]
		var nrm: Vector2 = h["n"]
		var sz: Vector3 = h["size"]
		var along := Vector2(-nrm.y, nrm.x)
		# a driveway up the side of the house with the car on it, a mailbox at the kerb, a fenced back yard
		var front := c - nrm * (sz.z * 0.5)                   # middle of the house front
		var edge := float(h.get("edge", 3.0))                 # front of the house to the road's edge
		var side := along * (sz.x * 0.5 + 2.2)
		I.decal(front + side - nrm * (edge * 0.5 - 1.6), Vector2(1.6, edge * 0.5 + 1.6), _yaw_to(nrm), P.CONCRETE)
		if rr.randf() < 0.6:
			var dc := front + side + nrm * 2.6
			I.put("k_car_" + PARKED[rr.randi_range(0, 5)], dc.x, dc.y, _yaw_to(-nrm if rr.randf() < 0.5 else nrm), 1.0, "box")
		var mb := front - nrm * (edge - 0.8) - along * (sz.x * 0.25)
		I.put_breakable("mailbox", mb.x, mb.y, _yaw_to(-nrm), 2.2, 0.35)
		var back := c + nrm * (sz.z * 0.5 + 5.5)
		if I.is_free(back, Vector2(4.7, 4.7), _yaw_to(nrm)):
			I.put("k_sub_fence-3x3", back.x, back.y, _yaw_to(-nrm), 1.0, "box")
			I.block_rect(back, Vector2(4.8, 4.8), _yaw_to(nrm), 0.5)
		var tp := front - nrm * (edge * 0.5) - along * (sz.x * 0.5 + 1.2)
		if not I.is_blocked(tp.x, tp.y):
			I.put("k_sub_tree-large" if rr.randf() < 0.6 else "k_castle_tree-small", tp.x, tp.y, rr.randf() * TAU, rr.randf_range(0.85, 1.1), "cyl")
		if rr.randf() < 0.3:
			_pet(I, ["dog", "cat", "bunny"][rr.randi_range(0, 2)], front.x + side.x - nrm.x * 1.2, front.y + side.y - nrm.y * 1.2)
		if rr.randf() < 0.35:
			_person(I, mb.x + along.x * 1.5, mb.y + along.y * 1.5)
		if I.season == 3 and rr.randf() < 0.3:
			I.put_breakable("k_holi_snowman-hat", tp.x + nrm.x * 2.5, tp.y + nrm.y * 2.5, _yaw_to(-nrm), 1.0, 0.6)
	# the little park in the middle of the loop
	var pk := Vector2(-212, -158)
	for k in 24:
		var a := TAU * k / 24.0 + rr.randf_range(-0.12, 0.12)
		var p := pk + Vector2(cos(a), sin(a)) * rr.randf_range(8.0, 30.0)
		if not I.is_blocked(p.x, p.y):
			I.put(["k_castle_tree-large", "k_surv_tree", "k_sub_tree-large", "k_surv_tree-autumn"][k % 4], p.x, p.y, rr.randf() * TAU, rr.randf_range(0.8, 1.05), "cyl")
	# benches round a little lawn in the middle, a dog or two, kids about
	for k in 4:
		var a2 := TAU * k / 4.0 + 0.4
		var bp := pk + Vector2(cos(a2), sin(a2)) * 5.0
		if not I.is_blocked(bp.x, bp.y):
			I.put_breakable("k_holi_bench", bp.x, bp.y, _yaw_to(pk - bp), 1.0, 0.8)
			if k % 2 == 0:
				_person(I, bp.x, bp.y, "sit", _yaw_to(pk - bp), 0.5)
	_pet(I, "dog", pk.x + 3, pk.y - 9)
	_pet(I, "dog", pk.x - 12, pk.y + 4)
	_person(I, pk.x + 2, pk.y + 10)
	_person(I, pk.x - 8, pk.y - 6)
	I.put_breakable("k_holi_bench", pk.x + 5, pk.y, PI * 0.5, 1.0, 0.8)
	_person(I, pk.x + 5, pk.y, "sit", -PI * 0.5, 0.5)
	_pet(I, "dog", pk.x - 4, pk.y + 3)

static func _castle(I, rr: RandomNumberGenerator) -> void:
	var c := CASTLE
	var y: float = I.height_at(c.x, c.y)
	var seg: float = _size("k_castle_wall").x   # 8 m
	var half := 24.0
	# walls on four sides; the south side opens for the road
	for side in 4:
		var dir: Vector2 = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][side]
		var along := Vector2(-dir.y, dir.x)
		for k in 6:
			var off := -half + seg * 0.5 + k * seg
			if side == 2 and (k == 2 or k == 3):
				continue
			var p: Vector2 = c + dir * half + along * off
			I.put("k_castle_wall", p.x, p.y, _yaw_to(-dir), 1.0, "box", y - 0.3, true)
		# corner towers
		var cp: Vector2 = c + dir * half + along * half
		var hh: float = _size("k_castle_tower-square-base").y
		I.put("k_castle_tower-square-base", cp.x, cp.y, 0.0, 1.15, "box", y - 0.3, true)
		I.put("k_castle_tower-square-mid-windows", cp.x, cp.y, 0.0, 1.15, "", y - 0.3 + hh * 1.15, true)
		I.put("k_castle_tower-square-top-roof", cp.x, cp.y, 0.0, 1.15, "", y - 0.3 + hh * 2.3, true)
	# gate towers either side of the opening
	for sx in [-1.0, 1.0]:
		var gp := c + Vector2(sx * 10.5, half)
		I.put("k_castle_tower-hexagon-base", gp.x, gp.y, 0.0, 1.0, "box", y - 0.3, true)
		var hb: float = _size("k_castle_tower-hexagon-base").y
		I.put("k_castle_tower-hexagon-mid", gp.x, gp.y, 0.0, 1.0, "", y - 0.3 + hb, true)
		I.put("k_castle_tower-hexagon-roof", gp.x, gp.y, 0.0, 1.0, "", y - 0.3 + hb + _size("k_castle_tower-hexagon-mid").y, true)
		I.put("k_castle_flag-banner-long", gp.x + sx * 0.0, gp.y + 3.4, 0.0, 1.0, "", y + 4.0, true)
	# the keep in the middle
	var kh: float = _size("k_castle_tower-square-base").y * 1.5
	var kp := c + Vector2(0, -8)
	I.put("k_castle_tower-square-base", kp.x, kp.y, 0.0, 1.5, "box", y - 0.3, true)
	I.put("k_castle_tower-square-mid-windows", kp.x, kp.y, 0.0, 1.5, "", y - 0.3 + kh, true)
	I.put("k_castle_tower-square-mid-windows", kp.x, kp.y, 0.0, 1.5, "", y - 0.3 + kh * 2.0, true)
	I.put("k_castle_tower-square-top-roof-high", kp.x, kp.y, 0.0, 1.5, "", y - 0.3 + kh * 3.0, true)
	var fl: Dictionary = I.add_anim("k_castle_flag-pennant", Vector3(kp.x, y - 0.3 + kh * 3.0 + _size("k_castle_tower-square-top-roof-high").y * 1.5 * 0.9, kp.y), 0.0, 1.2)
	if not fl.is_empty():
		fl["kind"] = "flag"
	# courtyard
	I.put("k_castle_siege-trebuchet", c.x - 13, c.y + 8, PI * 0.25, 1.0, "box")
	I.put("k_castle_siege-catapult", c.x + 13, c.y + 9, -PI * 0.3, 1.0, "box")
	I.put("k_arena_statue", c.x + 12, c.y - 14, 0.0, 1.0, "box")
	for k in 4:
		# either side of the drive in, not on it
		_person(I, c.x + (1.0 if k % 2 == 0 else -1.0) * rr.randf_range(7, 15), c.y + rr.randf_range(4, 18))
	_pet(I, "parrot", c.x - 6, c.y - 10)
	# trees down the hillside and rocks by the cliffs
	for k in 40:
		var a := rr.randf() * TAU
		var d := rr.randf_range(48.0, 135.0)
		var p := c + Vector2(cos(a), sin(a)) * d
		if I.is_blocked(p.x, p.y) or I.height_at(p.x, p.y) < 1.0:
			continue
		I.put(["k_castle_tree-large", "k_castle_tree-small", "k_forest_tree"][k % 3], p.x, p.y, rr.randf() * TAU, rr.randf_range(0.8, 1.2), "cyl")
	for k in 14:
		var a := rr.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * rr.randf_range(60.0, 140.0)
		if I.is_free(p, Vector2(3.0, 3.0), 0.0):
			I.put(["k_castle_rocks-large", "k_castle_rocks-small"][k % 2], p.x, p.y, rr.randf() * TAU, rr.randf_range(0.7, 1.2), "box")

static func _forest(I, rr: RandomNumberGenerator) -> void:
	# the campsite by the lake
	var cs := Vector2(246, -246)
	var fire: Dictionary = I.add_anim("flame", Vector3(cs.x, I.height_at(cs.x, cs.y) + 0.25, cs.y), 0.0, 2.6)
	if not fire.is_empty():
		fire["kind"] = "flame"
	I.put("k_surv_campfire-pit", cs.x, cs.y, 0.0, 1.0, "")
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		var lp := cs + Vector2(cos(a), sin(a)) * 3.6
		I.put("k_surv_tree-log", lp.x, lp.y, _yaw_to(cs - lp) + PI * 0.5, 0.75, "")
		_person(I, lp.x, lp.y, "sit", _yaw_to(cs - lp), 0.75)
	I.put("k_surv_tent-canvas", cs.x - 8, cs.y - 5, _yaw_to(Vector2(1, 0.5)), 1.0, "box")
	I.put("k_forest_tent", cs.x + 7, cs.y - 6, _yaw_to(Vector2(-1, 0.6)), 1.0, "box")
	I.put("k_surv_bedroll", cs.x - 3, cs.y + 6, 0.4, 1.0, "")
	I.put_breakable("k_surv_barrel", cs.x + 9, cs.y + 4, 0.0, 1.0, 0.5)
	I.put_breakable("k_surv_chest", cs.x + 10, cs.y + 6, 0.5, 1.0, 0.5)
	I.put_breakable("k_surv_signpost", cs.x - 11, cs.y + 9, 0.7, 1.0, 0.3)
	I.put("canoe", cs.x + 24, cs.y + 2, 1.2, 3.0, "")
	_pet(I, "fox", cs.x - 6, cs.y + 10)
	_pet(I, "beaver", cs.x + 26, cs.y - 6)
	_pet(I, "deer", cs.x - 30, cs.y - 20)
	# cabins and a lookout along the pass
	I.put("cabin", 330, -200, _yaw_to(Vector2(1, 0.3)), 4.5, "box")
	I.put("woodpile", 336, -192, 0.3, 3.0, "box")
	I.put("lookout", 350, -318, 0.0, 5.0, "box")
	_pet(I, "bunny", 320, -190)

static func _farm(I, rr: RandomNumberGenerator) -> void:
	var yard := Vector2(235, -14)
	I.put("barn", 235, -38, 0.0, 4.6, "box")
	I.put("silo", 258, -36, 0.0, 5.0, "box")
	I.put("silo", 266, -30, 0.0, 4.2, "box")
	var wm: Transform3D = I.put("windmill", 330, -50, 0.4, 6.0, "box")
	var bl: Dictionary = I.add_anim("windmill_blades", wm.origin, 0.4, 6.0)
	if not bl.is_empty():
		bl["kind"] = "blades"
	I.put("k_car_tractor", 212, -4, 0.8, 1.0, "box")
	I.put("k_retro_truck-flat", 255, 2, -0.3, 1.0, "box")
	for k in 8:
		var hp := yard + Vector2(rr.randf_range(-26, 26), rr.randf_range(-18, 18))
		I.put_breakable("hay", hp.x, hp.y, rr.randf() * TAU, 2.6, 1.0)
	for k in 6:
		_pet(I, ["cow", "pig", "chick", "hog", "cow", "chick"][k], yard.x + rr.randf_range(-20, 20), yard.y + rr.randf_range(-12, 14))
	_person(I, yard.x - 4, yard.y + 4)
	# fields: scarecrows, hay, sunflowers along the edges, fences by the lanes
	for f in fields(I):
		var c: Vector2 = f["c"]
		var hs: Vector2 = f["hs"]
		I.put("scarecrow", c.x, c.y, rr.randf() * TAU, 3.0, "cyl")
		for k in 5:
			var hp := c + Vector2(rr.randf_range(-hs.x, hs.x), rr.randf_range(-hs.y, hs.y)) * 0.85
			if I.is_free(hp, Vector2(1.6, 1.6), 0.0):
				I.put_breakable("hay", hp.x, hp.y, rr.randf() * TAU, 2.6, 1.0)
		for k in int(hs.x / 3.0):
			var sp := Vector2(c.x - hs.x + 1.5 + k * 6.0, c.y - hs.y - 1.0)
			if not I.is_blocked(sp.x, sp.y):
				I.put("sunflower", sp.x, sp.y, 0.0, 2.4, "")
		if rr.randf() < 0.6:
			_pet(I, ["cow", "pig", "hog"][rr.randi_range(0, 2)], c.x + hs.x * 0.5, c.y)
	_crops(I, rr)
	# fences along Field Lane
	for s in _along(I, "Field Lane", 6.0, 4.4, 6.0):
		if not I.is_blocked(s["p"].x, s["p"].y):
			I.put("k_surv_fence", s["p"].x, s["p"].y, _yaw_to(s["n"]), 2.2, "")

## The fields' rows: a ploughed ridge of soil each, with the crop growing along it. Rows run the long way
## across each field. Built as one mesh per field (no colliders: you drive straight through), only drawn
## near by, and coloured from the season palette (green shoots in spring, gold in autumn, snow in winter).
static func _crops(I, rr: RandomNumberGenerator) -> void:
	var gap := 2.4
	var keep_out := [Vector2(330, -50)]     # the windmill
	for f in fields(I):
		keep_out.append(f["c"])             # the scarecrow
	for f in fields(I):
		var c: Vector2 = f["c"]
		var hs: Vector2 = f["hs"]
		var crop: String = f["crop"]
		var along_x: bool = hs.x >= hs.y
		var ext: float = hs.x if along_x else hs.y        # half-length of a row
		var wide: float = hs.y if along_x else hs.x       # half-width of the field across the rows
		var dir := Vector2(1, 0) if along_x else Vector2(0, 1)
		var side := Vector2(0, 1) if along_x else Vector2(1, 0)
		var ridges := MB.new()
		var plants := MB.new()
		var n_rows := int((wide * 2.0 - 1.6) / gap) + 1
		var off0 := -(n_rows - 1) * gap * 0.5
		for ri in n_rows:
			var o := off0 + ri * gap
			# the ridge: a low trapezoid of turned soil, following the ground
			var step := 2.0
			var t := -ext + 0.8
			while t < ext - 0.8:
				var t2 := minf(t + step, ext - 0.8)
				var a0: Vector2 = c + dir * t + side * o
				var a1: Vector2 = c + dir * t2 + side * o
				# no ploughing across a road (or the farm track): the rows stop at its verge
				if I.field_keep(f, a0) and I.field_keep(f, a1) \
						and not (I.on_carriageway(a0, -1, 1.4) or I.on_carriageway(a1, -1, 1.4) or I.on_carriageway((a0 + a1) * 0.5, -1, 1.4)):
					_ridge(I, ridges, a0, a1, side)
				t = t2
			# the crop along it
			t = -ext + 1.2
			var spacing: float = {"wheat": 0.5, "potato": 0.5, "cabbage": 1.0, "corn": 0.9, "sunflower": 1.5}[crop]
			while t < ext - 1.2:
				var strip: bool = crop in ["wheat", "potato"]
				var p: Vector2 = c + dir * t + side * (o + (0.0 if strip else rr.randf_range(-0.12, 0.12)))
				var clear := true
				for k in keep_out:
					if p.distance_to(k) < (7.0 if k == keep_out[0] else 2.0):
						clear = false
				if clear and I.field_keep(f, p) and not I.is_blocked(p.x, p.y) and not I.on_carriageway(p, -1, 2.2 if crop in ["corn", "sunflower"] else 1.6):
					var y: float = I.height_at(p.x, p.y) + 0.2
					_plant(plants, crop, Vector3(p.x, y, p.y), Vector3(dir.x, 0, dir.y), spacing, rr)
				t += spacing * rr.randf_range(0.9, 1.1) if crop in ["cabbage", "corn", "sunflower"] else spacing
		for pair in [[ridges, 420.0], [plants, 260.0]]:
			var mb: MB = pair[0]
			if mb.is_empty():
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = mb.commit()
			mi.material_override = I.mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if crop in ["corn", "sunflower"] and mb == plants else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = pair[1]
			mi.visibility_range_end_margin = 30.0
			mi.name = "Field_%s_%s" % [crop, "rows" if mb == ridges else "crop"]
			I.add_child(mi)

## One length of ridge from a to b (side: across the row).
static func _ridge(I, mb: MB, a: Vector2, b: Vector2, side: Vector2) -> void:
	var soil := MB.pal(P.FURROW)
	var prof := [[-0.78, 0.0], [-0.32, 0.22], [0.32, 0.22], [0.78, 0.0]]
	var pa := []
	var pb := []
	for q in prof:
		var wa: Vector2 = a + side * float(q[0])
		var wb: Vector2 = b + side * float(q[0])
		pa.append(Vector3(wa.x, I.height_at(wa.x, wa.y) + float(q[1]) + 0.02, wa.y))
		pb.append(Vector3(wb.x, I.height_at(wb.x, wb.y) + float(q[1]) + 0.02, wb.y))
	for k in 3:
		var nm := ((pb[k] as Vector3) - (pa[k] as Vector3)).cross((pa[k + 1] as Vector3) - (pa[k] as Vector3)).normalized()
		if nm.y < 0.0:
			nm = -nm
		mb.quad(pa[k], pa[k + 1], pb[k + 1], pb[k], nm, soil)

## One plant (or, for wheat and potatoes, one short length of a continuous row) at p, the row along dir.
static func _plant(mb: MB, crop: String, p: Vector3, dir: Vector3, spacing: float, rr: RandomNumberGenerator) -> void:
	var across := Vector3(-dir.z, 0, dir.x)
	match crop:
		"wheat", "potato":
			# a continuous band of stems along the row, its top rising and falling gently
			var tall := 0.72 if crop == "wheat" else 0.34
			var w := 0.34 if crop == "wheat" else 0.36
			var col := MB.pal(P.WHEAT if crop == "wheat" else P.LEAFY)
			var a := p - dir * spacing * 0.5
			var b := p + dir * spacing * 0.5
			var wave := func(q: Vector3) -> float:
				var u := q.x * 0.9 + q.z * 1.3
				return tall * (0.9 + 0.08 * sin(u * 2.3) + 0.05 * sin(u * 7.1 + q.x))
			var h0: float = wave.call(a)
			var h1: float = wave.call(b)
			var aL := a - across * w; var aR := a + across * w
			var bL := b - across * w; var bR := b + across * w
			var top_a := a + Vector3(0, h0, 0)
			var top_b := b + Vector3(0, h1, 0)
			var nl := (across * -1.0 + Vector3(0, 0.8, 0)).normalized()
			var nr := (across + Vector3(0, 0.8, 0)).normalized()
			mb.quad(aL, bL, top_b, top_a, nl, col)
			mb.quad(top_a, top_b, bR, aR, nr, col)
			if crop == "wheat":
				# ears poking up out of the top, so it isn't one smooth band
				var ear := MB.pal(P.HAY)
				for k in 3:
					var f := (k + rr.randf_range(0.1, 0.9)) / 3.0
					var base := a.lerp(b, f) + Vector3(0, lerpf(h0, h1, f) - 0.05, 0) + across * rr.randf_range(-w, w) * 0.5
					var tip := base + Vector3(rr.randf_range(-0.05, 0.05), rr.randf_range(0.16, 0.26), rr.randf_range(-0.05, 0.05))
					var wv := across * 0.045
					mb.tri(base - wv, base + wv, tip, dir, dir, dir, ear)
					mb.tri(base + wv, base - wv, tip, -dir, -dir, -dir, ear)
		"cabbage":
			# a pale round head sitting in a ring of darker outer leaves
			var r := rr.randf_range(0.24, 0.3)
			var leaf := MB.pal(P.LEAFY)
			var head := MB.pal(P.CABBAGE)
			var yaw := rr.randf() * TAU
			for k in 5:
				var an := yaw + TAU * k / 5.0
				var out := Vector3(cos(an), 0, sin(an))
				var o2 := out.cross(Vector3.UP).normalized()
				var lb := p + out * r * 0.5 + Vector3(0, 0.03, 0)
				var lt := p + out * r * 2.3 + Vector3(0, 0.2, 0)
				var nm := (o2.cross(lt - lb)).normalized()
				if nm.y < 0.0:
					nm = -nm
				mb.tri(lb - o2 * r * 0.7, lb + o2 * r * 0.7, lt, nm, nm, nm, leaf)
			var ring0 := []
			var ring1 := []
			for k in 6:
				var an := yaw + TAU * k / 6.0
				ring0.append(p + Vector3(cos(an) * r, 0.05, sin(an) * r))
				ring1.append(p + Vector3(cos(an + 0.5) * r * 0.75, r * 1.05, sin(an + 0.5) * r * 0.75))
			var top := p + Vector3(0, r * 1.45, 0)
			for k in 6:
				var a0: Vector3 = ring0[k]
				var a1: Vector3 = ring0[(k + 1) % 6]
				var b0: Vector3 = ring1[k]
				var b1: Vector3 = ring1[(k + 1) % 6]
				var n0 := ((a0 + a1) * 0.5 - p).normalized()
				mb.tri(a0, a1, b0, n0, n0, (n0 + Vector3.UP).normalized(), head)
				mb.tri(a1, b1, b0, n0, (n0 + Vector3.UP).normalized(), (n0 + Vector3.UP).normalized(), head)
				var n1 := ((b0 + b1) * 0.5 - p + Vector3(0, r, 0)).normalized()
				mb.tri(b0, b1, top, n1, n1, Vector3.UP, head)
		"corn", "sunflower":
			var h := rr.randf_range(1.5, 1.85) if crop == "corn" else rr.randf_range(1.6, 2.0)
			var stalk := MB.pal(P.CORN)
			var sw := 0.05
			# a thin square stalk
			for k in 4:
				var a0 := Vector3(cos(PI * 0.5 * k), 0, sin(PI * 0.5 * k)) * sw
				var a1 := Vector3(cos(PI * 0.5 * (k + 1)), 0, sin(PI * 0.5 * (k + 1))) * sw
				var nm := (a0 + a1).normalized()
				mb.quad(p + a0, p + a1, p + a1 + Vector3(0, h, 0), p + a0 + Vector3(0, h, 0), nm, stalk)
			# leaves arching out (both faces)
			for k in 3:
				var an := rr.randf() * TAU
				var out := Vector3(cos(an), 0, sin(an))
				var base := p + Vector3(0, h * (0.3 + 0.2 * k), 0)
				var tip := base + out * 0.55 + Vector3(0, 0.18, 0)
				var wv := out.cross(Vector3.UP).normalized() * 0.09
				var nm := (wv.cross(tip - base)).normalized()
				mb.tri(base - wv, base + wv, tip, nm, nm, nm, stalk)
				mb.tri(base + wv, base - wv, tip, -nm, -nm, -nm, stalk)
			if crop == "corn":
				# a tassel and a cob
				var tp := p + Vector3(0, h, 0)
				mb.tri(tp + across * 0.1, tp - across * 0.1, tp + Vector3(0, 0.3, 0), dir, dir, dir, MB.pal(P.HAY))
				mb.tri(tp - across * 0.1, tp + across * 0.1, tp + Vector3(0, 0.3, 0), -dir, -dir, -dir, MB.pal(P.HAY))
				mb.cbox(p + Vector3(0.07, h * 0.55, 0), Vector3(0.09, 0.26, 0.09), 0.0, MB.pal(P.HAY))
			else:
				# a flower head turned to the morning sun, yellow petals round a brown middle
				var face := Vector3(0.55, 0.25, 0.8).normalized()
				var hc := p + Vector3(0, h, 0) + face * 0.06
				var u := face.cross(Vector3.UP).normalized()
				var v := u.cross(face).normalized()
				var petal := MB.pal(P.FLOWER_B)
				var mid := MB.pal(P.TRUNK)
				var ring := []
				for k in 7:
					var an := TAU * k / 7.0
					ring.append(hc + (u * cos(an) + v * sin(an)) * 0.34)
				for k in 7:
					var r0: Vector3 = ring[k]
					var r1: Vector3 = ring[(k + 1) % 7]
					var m0 := hc.lerp(r0, 0.5)
					var m1 := hc.lerp(r1, 0.5)
					mb.tri(hc + face * 0.02, m0 + face * 0.02, m1 + face * 0.02, face, face, face, mid)
					mb.tri(m0, r0, r1, face, face, face, petal)
					mb.tri(m0, r1, m1, face, face, face, petal)
					mb.tri(r0, hc - face * 0.04, r1, -face, -face, -face, stalk)

static func _bowl(I, rr: RandomNumberGenerator) -> void:
	var c := Vector2(175, 205)
	var hs := Vector2(60, 42)
	var y: float = I.height_at(c.x, c.y)
	var seg: float = _size("k_arena_border-straight").x
	# low arena walls all round, with gaps where the roads come in
	for side in 4:
		var dir: Vector2 = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][side]
		var along := Vector2(-dir.y, dir.x)
		var ext: float = hs.x if side % 2 == 0 else hs.y
		var dep: float = hs.y if side % 2 == 0 else hs.x
		var k := 0
		var off := -ext + seg * 0.5
		while off < ext:
			var p: Vector2 = c + dir * (dep + 1.0) + along * off
			var gap: bool = (side == 0 or side == 2) and absf(p.x - 175.0) < 9.0
			if not gap:
				I.put("k_arena_border-straight", p.x, p.y, _yaw_to(-dir), 1.0, "box", y)
			off += seg
			k += 1
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var cp := c + Vector2(cx * (hs.x + 1.0), cz * (hs.y + 1.0))
			I.put("k_arena_column", cp.x, cp.y, 0.0, 1.0, "box", y, true)
			I.put("k_arena_banner", cp.x + cx * 0.0, cp.y - cz * 3.5, _yaw_to(Vector2(0, -cz)), 1.0, "", y)
	# grandstands with a crowd on the north side
	for k in 4:
		var sp := c + Vector2([-46.0, -24.0, 24.0, 46.0][k], -hs.y - 9.0)
		I.put("k_arena_stairs", sp.x, sp.y, PI, 1.8, "box")
		for q in 2:
			_person(I, sp.x + (q - 0.5) * 3.0, sp.y + 1.0, "stand", PI, 1.8)
	I.put("k_arena_trophy", c.x - 30, c.y - hs.y - 16, 0.0, 1.0, "box")
	I.put("k_arena_statue", c.x + 30, c.y - hs.y - 16, 0.0, 1.0, "box")
	# cones: two drift circles and a gate
	for ring in [Vector2(-25, 0), Vector2(25, 0)]:
		var rc: Vector2 = c + ring
		I.put_breakable("k_car_cone", rc.x, rc.y, 0.0, 1.0, 0.45)
		for k in 10:
			var a := TAU * k / 10.0
			var p: Vector2 = rc + Vector2(cos(a), sin(a)) * 13.0
			I.put_breakable("k_car_cone", p.x, p.y, rr.randf() * TAU, 1.0, 0.45)
	for k in 6:
		I.put_breakable("k_car_cone", c.x - 8 + (k % 2) * 16.0, c.y - 30 + (k / 2) * 6.0, 0.0, 1.0, 0.45)

static func _skatepark(I, rr: RandomNumberGenerator) -> void:
	var c := SKATE
	var y: float = I.height_at(c.x, c.y)
	# pieces you can actually ride (exact collision)
	I.put("k_skate_half-pipe", c.x - 4, c.y - 15, 0.0, 1.0, "mesh", y)
	I.put("k_skate_half-pipe", c.x + 4, c.y - 15, 0.0, 1.0, "mesh", y)
	I.put("k_skate_ramp", c.x - 15, c.y + 2, PI * 0.5, 1.0, "mesh", y)
	I.put("k_skate_ramp", c.x + 15, c.y + 2, -PI * 0.5, 1.0, "mesh", y)
	I.put("k_skate_obstacle-box", c.x, c.y + 3, 0.0, 1.0, "mesh", y)
	I.put("k_skate_ramp-rail", c.x + 10, c.y + 14, PI, 1.0, "mesh", y)
	I.put("k_skate_rail-low", c.x - 8, c.y + 13, PI * 0.5, 1.0, "", y)
	I.put_breakable("k_skate_bench", c.x - 19, c.y + 16, PI * 0.5, 1.0, 0.8)
	_person(I, c.x - 19, c.y + 16, "sit", -PI * 0.5, 0.55)
	_person(I, c.x - 17, c.y - 8)
	_person(I, c.x + 18, c.y - 8)
	I.put_breakable("k_skate_skateboard", c.x - 16, c.y - 10, 1.0, 1.0, 0.3)
	for k in 4:
		I.put("k_arena_banner", c.x + [-19.0, 19.0][k % 2], c.y + [-19.0, 19.0][k / 2], 0.0, 1.0, "", y)
	_pet(I, "dog", c.x + 18, c.y + 8)
	I.block_rect(c, Vector2(21, 21), 0.0, 0.0)

static func _harbour(I, rr: RandomNumberGenerator) -> void:
	var c := Vector2(-392, 162)
	var y: float = I.height_at(c.x, c.y)
	var dy := y + 0.15                       # the deck's top
	# the quay: a wooden deck out over the water, and a jetty off the end of it
	I.deck(Vector2(-462, 162), Vector2(30, 7), dy, 0.0)
	I.deck(Vector2(-480, 188), Vector2(5, 20), dy, 0.0)
	# ships tied up along the quay, rowing boats by the jetty (pirate kit)
	var ships := [["k_pirate_ship-large", Vector3(-462, -0.6, 140), PI * 0.5], ["k_pirate_ship-pirate-medium", Vector3(-500, -0.6, 205), 0.15],
		["k_pirate_ship-medium", Vector3(-455, -0.6, 184), -PI * 0.5]]
	for sh in ships:
		var an: Dictionary = I.add_anim(sh[0], sh[1], sh[2], 1.0)
		if not an.is_empty():
			an["kind"] = "bob"
		var sz: Vector3 = M.ksize(sh[0])
		I.add_box_collider(Transform3D(Basis(Vector3.UP, sh[2]), sh[1] + Vector3(0, 1.5, 0)), Vector3(sz.x * 0.8, 4.0, sz.z * 0.85))
	for k in 4:
		var bt: Dictionary = I.add_anim("k_pirate_boat-row-" + ("large" if k % 2 == 0 else "small"), Vector3(-472 + (k % 2) * 16.0, -0.2, 172 + k * 7.0), rr.randf_range(-0.4, 0.4), 1.0)
		if not bt.is_empty():
			bt["kind"] = "bob"
	# mooring barrels in a line along both edges of the deck; the old cannons point out to sea at its end
	for k in 5:
		I.put_breakable("k_pirate_barrel", -486.0 + k * 11.0, 155.8, 0.0, 1.0, 0.6, dy)
		I.put_breakable("k_pirate_barrel", -486.0 + k * 11.0, 168.2, 0.0, 1.0, 0.6, dy)
	I.put("k_pirate_cannon", -489, 158.5, _yaw_to(Vector2(-1, 0)), 1.0, "box", dy)
	I.put("k_pirate_cannon", -489, 165.5, _yaw_to(Vector2(-1, 0)), 1.0, "box", dy)
	I.put("k_pirate_flag-high-pennant", -434, 153, PI * 0.5, 1.0, "", y)
	# the watchtower on the corner and a shelter by the deck
	I.put("k_pirate_tower-watch", -429, 135.5, 0.0, 1.0, "box")
	I.put("k_pirate_structure-roof", -429.5, 147, PI * 0.5, 1.0, "box")
	_person(I, -428, 147.5, "sit", _yaw_to(Vector2(-1, 0)), 0.55)
	# the fish market: four stalls in a row along the north edge, a stallholder behind each
	var south := _yaw_to(Vector2(0, 1))
	for k in 4:
		var sx := -418.0 + k * 6.5
		I.put("k_pirate_structure", sx, 136.2, 0.0, 1.0, "box")
		I.put("k_pirate_crate" if k % 2 == 0 else "k_pirate_crate-bottles", sx - 1.2, 137.4, 0.0, 1.0, "")
		I.put("k_pirate_barrel" if k % 2 == 0 else "k_pirate_crate", sx + 1.2, 137.4, 0.0, 1.0, "")
		_person(I, sx, 135.2, "stand", south)
		if k % 2 == 1:
			_person(I, sx + 0.6, 141.0, "stand", _yaw_to(Vector2(0, -1)))
	I.put("k_retro_detail-dumpster-closed", -389.5, 134.2, south, 1.0, "box")
	var path := PackedVector3Array()
	for k in 6:
		var px := -421.0 + k * 5.0
		path.append(Vector3(px, I.height_at(px, 141.5) + 0.06, 141.5))
	I.people.spawn_walker(rr.randi_range(0, 99), path, 1.2)
	var dpath := PackedVector3Array()
	for k in 6:
		dpath.append(Vector3(-438.0 - k * 9.0, dy + 0.06, 160.5))
	I.people.spawn_walker(rr.randi_range(0, 99), dpath, 1.3)
	# the cargo yard: pallets in neat rows, crates stacked on them
	for gx in 4:
		for gz in 3:
			var p := Vector2(-428.5 + gx * 2.6, 178.0 + gz * 2.8)
			I.put("k_retro_pallet", p.x, p.y, 0.0, 1.0, "")
			var top: float = I.height_at(p.x, p.y) + 0.2
			if (gx + gz) % 3 == 2:
				I.put("k_pirate_crate", p.x, p.y, 0.0, 1.0, "box", top)
				I.put("k_pirate_crate", p.x, p.y, 0.0, 1.0, "", top + 0.95)
			elif (gx * 2 + gz) % 4 != 3:
				I.put_breakable("k_pirate_crate" if gx % 2 == 0 else "k_pirate_crate-bottles", p.x, p.y, 0.0, 1.0, 0.7, top)
	I.put("k_car_tractor", -416, 185, PI * 0.5, 1.0, "box")
	_person(I, -418.5, 181, "stand", _yaw_to(Vector2(-1, 0)))
	# parking bays along the south edge, nose in, lines painted between
	var vans := ["van", "truck", "delivery", "van", "truck", "sedan", "delivery", "van"]
	for k in 11:
		var bx := -406.0 + k * 3.4
		I.decal(Vector2(bx - 1.7, 189.4), Vector2(0.07, 2.4), 0.0, P.FENCE, 2.6)
		if k % 4 != 2 and k < 10:
			I.put("k_car_" + vans[k % vans.size()], bx, 189.2, PI, 1.0, "box")
	I.decal(Vector2(-370.3, 189.4), Vector2(0.07, 2.4), 0.0, P.FENCE, 2.6)
	I.decal(Vector2(-389.0, 187.0), Vector2(18.7, 0.07), 0.0, P.FENCE, 2.6)
	_person(I, -381, 185.6, "stand", _yaw_to(Vector2(0, 1)))
	# drift pylons for a figure of eight in the open middle
	for cp in [Vector2(-410, 161), Vector2(-385, 161)]:
		for k in 5:
			var a := TAU * k / 5.0
			I.put_breakable("k_car_cone", cp.x + cos(a) * 1.4, cp.y + sin(a) * 1.4, 0.0, 1.0, 0.35)
	# lamps around the edge
	for lp in [Vector2(-392, 133.4), Vector2(-354, 133.4), Vector2(-354, 190.6), Vector2(-431, 190.6), Vector2(-411, 174)]:
		I.put_breakable("k_retro_detail-light-single", lp.x, lp.y, _yaw_to(c - lp), 1.0, 0.3)
	_pet(I, "penguin", -485, 175)
	_pet(I, "parrot", -462, 160)
	# the lighthouse on its point
	I.put("lighthouse", -305, 322, 0.0, 6.0, "box", -10000.0, true)
	for k in 6:
		var a := rr.randf() * TAU
		I.put("k_pirate_rocks-sand-" + ["a", "b", "c"][k % 3], -305 + cos(a) * 13.0, 322 + sin(a) * 13.0, rr.randf() * TAU, rr.randf_range(0.6, 1.0), "box")

static func _beach(I, rr: RandomNumberGenerator) -> void:
	# shops along the sea front, facing the beach across the ring road
	var shops := []
	for s in ["a", "b", "c", "d", "e", "h"]:
		shops.append("k_com_building-" + s)
	var ring := _road(I, "Ring Road")
	var pts: PackedVector2Array = ring["pts"]
	var ia := _nearest(pts, Vector2(-210, 336))
	var ib := _nearest(pts, Vector2(-80, 350))
	_row(I, "Ring Road", 1.0 if _side_north(I, ring, ia) < 0 else -1.0, float(mini(ia, ib)) / (pts.size() - 1), float(maxi(ia, ib)) / (pts.size() - 1), shops, 9.0, rr, Vector2(1.0, 3.0))
	# the pier
	I.deck(Vector2(-60, 425), Vector2(5, 40), 1.3, 0.0)
	for k in 6:
		I.put_breakable("k_retro_detail-light-single", -55.5 if k % 2 == 0 else -64.5, 395 + k * 13.0, PI * 0.5 if k % 2 == 0 else -PI * 0.5, 1.0, 0.3, 1.45)
	_person(I, -57, 458, "sit", PI, 1.45)
	# sand: parasols, towels with sunbathers, a lifeguard, sandcastles (a busy beach, not a scattering)
	for k in 76:
		var p := Vector2(rr.randf_range(-260, 160), rr.randf_range(372, 404))
		if I.height_at(p.x, p.y) < 0.35 or I.is_blocked(p.x, p.y) or absf(p.x + 60) < 10:
			continue
		match k % 4:
			0, 1:
				I.put_breakable("umbrella", p.x, p.y, rr.randf() * TAU, 2.4, 0.6)
				I.put("towel", p.x + 2.0, p.y + 1.0, rr.randf_range(-0.4, 0.4), 2.2, "")
				if rr.randf() < 0.6:
					_person(I, p.x + 2.0, p.y + 1.0, "lie", rr.randf_range(-0.4, 0.4))
			2:
				I.put_breakable("sandcastle", p.x, p.y, rr.randf() * TAU, 2.0, 0.6)
			3:
				I.put_breakable("beach_ball", p.x, p.y, 0.0, 2.0, 0.4)
				_person(I, p.x + 1.5, p.y)
	I.put("lifeguard", -130, 395, PI, 2.4, "box")
	_person(I, -130, 395, "stand", PI, 2.6)
	I.put("lifeguard", 40, 400, PI, 2.4, "box")
	I.put("kiosk", -10, 372, PI, 2.6, "box")
	_person(I, -8, 377)
	for k in 5:
		_pet(I, "crab", rr.randf_range(-250, 150), rr.randf_range(398, 410))
	for k in 8:
		var p := Vector2(rr.randf_range(-250, 150), rr.randf_range(384, 410))
		if not I.is_blocked(p.x, p.y) and I.height_at(p.x, p.y) > -0.5:
			I.put("k_pirate_rocks-sand-" + ["a", "b", "c"][k % 3], p.x, p.y, rr.randf() * TAU, rr.randf_range(0.5, 0.9), "box")
	# palm trees along the back of the beach
	for k in 34:
		var p := Vector2(rr.randf_range(-280, 190), rr.randf_range(362, 392))
		if I.is_blocked(p.x, p.y) or I.height_at(p.x, p.y) < 0.3 or absf(p.x + 60.0) < 9.0:
			continue
		I.put("k_pirate_palm-" + ["straight", "bend", "detailed-straight", "detailed-bend"][k % 4], p.x, p.y, rr.randf() * TAU, rr.randf_range(0.85, 1.15), "cyl")
	for k in 3:
		var bt: Dictionary = I.add_anim("k_pirate_boat-row-" + ("large" if k % 2 == 0 else "small"), Vector3(-48 - k * 3.0, -0.15, 438 + k * 9.0), rr.randf_range(-0.5, 0.5), 1.0)
		if not bt.is_empty():
			bt["kind"] = "bob"
	# beach car park
	for k in 6:
		I.put("k_car_" + PARKED[rr.randi_range(0, PARKED.size() - 1)], 40 + k * 8.0, 368, PI, 1.0, "box")

static func _side_north(I, r: Dictionary, k: int) -> float:
	var t: Vector2 = I._tangent(r["pts"], k, r["closed"])
	return Vector2(-t.y, t.x).y

## Lamps along the ring road and a few road signs.
# ---------------------------------------------------------------- the stunt yard
# Ramps and platforms from Klyo Games' stunt arena kits (CC BY 4.0), and a loop built to match.
# A lap runs clockwise: in under the gate and down the east side through the loop, west along the south
# side over Big Air (boost, kicker, gold hoop), up the half-pipe on the west side, and east along the
# north side over the platform run and through the tunnel.

## A stunt piece facing dir (its front, -Z, that way), standing at height y, solid to drive on.
static func _piece(I, name: String, c: Vector2, dir: Vector2, sc: float, y: float, col := "stunt", landmark := false) -> void:
	I.put(name, c.x, c.y, _yaw_to(dir), sc, col, y, landmark)

## A boost pad, sunk so only its top shows: you drive straight over it.
static func _pad(I, c: Vector2, dir: Vector2, y: float) -> void:
	var sc := 1.4
	I.put("k_klyo_boost_pad", c.x, c.y, _yaw_to(dir), sc, "", y - 0.15 * sc)
	I.stunt["pads"].append({"pos": Vector3(c.x, y, c.y), "dir": Vector3(dir.x, 0, dir.y), "hs": Vector2(1.8, 2.75) * sc})

static func _stunt_yard(I, rr: RandomNumberGenerator) -> void:
	var st: Dictionary = I.stunt
	var y0: float = I.height_at(STUNT.x, STUNT.y) + 0.02
	st["rect"] = Rect2(STUNT - STUNT_HS, STUNT_HS * 2.0)
	var E := Vector2(1, 0)
	var W := Vector2(-1, 0)
	var S := Vector2(0, 1)
	var NN := Vector2(0, -1)
	var coins := []
	# ---- the lap, painted in dark asphalt on the concrete
	# (in 5 m tiles, so it follows the ground the way the concrete does)
	for r in [Rect2(-238, 217, 136, 14), Rect2(-124, 217, 22, 77), Rect2(-238, 277, 136, 16), Rect2(-241, 217, 16, 76)]:
		var nx := ceili(r.size.x / 5.0)
		var nz := ceili(r.size.y / 5.0)
		var ts := Vector2(r.size.x / nx, r.size.y / nz)
		for i in nx:
			for j in nz:
				I.decal(r.position + ts * Vector2(i + 0.5, j + 0.5), ts * 0.5, 0.0, P.ASPHALT_DK, 2.2)
	# ---- in under a gate, straight down to the loop with a boost pad on the way
	_piece(I, "k_klyo_checkpoint_gate", Vector2(-110, 216.0), S, 1.4, y0, "mesh")
	_pad(I, Vector2(-110, 236), S, y0)
	# (in on the lane at x = -110 from z = 250, out 7 m to the west of it)
	var lb := Basis(Vector3.UP, _yaw_to(S))
	var lo := Vector3(-110.0 - M.LOOP_SHIFT * 0.5, y0, 250.0)          # where the track starts
	var lcen: Vector3 = lb * M.get_mesh("stunt_loop").get_aabb().get_center()
	I.put("stunt_loop", lo.x + lcen.x, lo.z + lcen.z, _yaw_to(S), 1.0, "stunt", y0, true)
	var ltop: Vector3 = lo + lb * M.loop_top()
	st["loops"].append({"pos": Vector3(ltop.x, y0, ltop.z), "dir": Vector3(0, 0, 1), "side": Vector3(-1, 0, 0)})
	coins.append(ltop - Vector3(0, 1.4, 0))
	# ---- Big Air: boost, kicker, and a gold hoop to fly through, with the whole south side to land on
	_pad(I, Vector2(-132, 284), W, y0)
	_piece(I, "k_klyo_ramp_kicker", Vector2(-152, 284), W, 1.4, y0)
	var hx := -152.0 - 4.0 * 1.4 - 6.5
	var hsc := 2.2
	_piece(I, "k_klyo_gold_hoop", Vector2(hx, 284), W, hsc, y0, "mesh")
	var hy := y0 + 3.06 * hsc
	st["hoops"].append({"pos": Vector3(hx, hy, 284), "n": Vector3(-1, 0, 0), "r": 4.6})
	coins.append(Vector3(hx, hy, 284))
	# ---- two half-pipes end to end up the west side (sunk a touch, so the floor meets the yard flush)
	for k in 2:
		_piece(I, "k_klyo_half_pipe", Vector2(-233.3, 270.0 - k * 12.75), NN, 1.5, y0 - 0.1)
	var hp_half := 8.498 * 1.5 * 0.5
	var lip_c: float = M.get_mesh("hp_lip").get_aabb().get_center().z
	I.put("hp_lip", -233.3, 270.0 + hp_half + lip_c, 0.0, 1.0, "stunt", y0)
	I.put("hp_lip", -233.3, 257.25 - hp_half - lip_c, PI, 1.0, "stunt", y0)
	coins.append(Vector3(-233.3 + 4.3, y0 + 3.0, 263.6))
	# ---- the platform run: up a ramp onto a deck, over the gap, down again
	var x := -222.0
	var zr := 224.0
	var deck := 2.03 * 1.5
	_piece(I, "k_klyo_ramp_low", Vector2(x + 6.08, zr), E, 1.9, y0)
	for k in 2:
		_piece(I, "k_klyo_platform", Vector2(x + 12.16 + 3.075 + k * 6.15, zr), E, 1.5, y0)
	var gx := x + 12.16 + 12.3 + 2.55
	_piece(I, "k_klyo_gap_jump_pair", Vector2(gx, zr), E, 1.5, y0 + deck)
	for k in 2:
		_piece(I, "k_klyo_platform", Vector2(gx + 2.55 + 3.075 + k * 6.15, zr), E, 1.5, y0)
	_piece(I, "k_klyo_ramp_low", Vector2(gx + 2.55 + 12.3 + 6.08, zr), W, 1.9, y0)
	coins.append(Vector3(gx, y0 + deck + 4.5, zr))
	_piece(I, "k_klyo_industrial_tunnel", Vector2(-150, 224), E, 1.5, y0, "mesh")
	# ---- in the middle: a container to jump, cones to drift round, oil drums
	_piece(I, "k_klyo_ramp_low", Vector2(-202, 262), E, 1.4, y0)
	_piece(I, "k_klyo_container", Vector2(-185, 262), S, 1.0, y0, "box")
	for k in 8:
		var cx := -205.0 + k * 9.0
		I.put_breakable("k_car_cone", cx, 244.0 + (2.2 if k % 2 == 0 else -2.2), 0.0, 1.0, 0.3, y0)
	for d in [Vector2(-146, 268), Vector2(-145, 269.2), Vector2(-146.3, 269.5), Vector2(-212, 274), Vector2(-211, 275)]:
		I.put("k_klyo_steel_drum", d.x, d.y, rr.randf() * TAU, 1.2, "cyl", y0)
	# ---- edges: barriers where a run ends, floodlights at the corners, a crowd outside
	for k in 12:
		_piece(I, "k_klyo_jersey_barrier", Vector2(-103.0 - k * 3.4, 294.5), W, 1.4, y0, "box")
	for k in 7:
		_piece(I, "k_klyo_jersey_barrier", Vector2(-101.5, 268.0 + k * 3.4), S, 1.4, y0, "box")
	for c in [Vector2(-237, 215), Vector2(-237, 293), Vector2(-103, 248), Vector2(-160, 215), Vector2(-185, 293)]:
		I.put("k_klyo_floodlight", c.x, c.y, _yaw_to(STUNT - c), 1.0, "cyl", y0, true)
	for k in 6:
		var px := -228.0 + k * 17.0 + rr.randf_range(-2.0, 2.0)
		_person(I, px, 208.5, "stand", _yaw_to(S))
		_person(I, px + rr.randf_range(-12.0, 12.0) + 4.0, 300.5, "stand", _yaw_to(NN))
	# ---- after a crash, back to the start of the nearest run
	for rs in [[Vector2(-110, 222), S], [Vector2(-122, 289), W], [Vector2(-233, 289), NN], [Vector2(-232, 230), E], [Vector2(-212, 262), E]]:
		var c2: Vector2 = rs[0]
		st["resets"].append(Transform3D(Basis(Vector3.UP, _yaw_to(rs[1])), Vector3(c2.x, y0 + 0.9, c2.y)))
	st["coins"] = coins

static func _roadside(I, rr: RandomNumberGenerator) -> void:
	for s in _along(I, "Ring Road", 7.6, 44.0, 10.0):
		var p: Vector2 = s["p"]
		if I.is_blocked(p.x, p.y) or I.height_at(p.x, p.y) < 0.4:
			continue
		I.put_breakable("k_retro_detail-light-single", p.x, p.y, _yaw_to(-s["n"]), 1.0, 0.3)
	for road in ["Castle Climb", "Pinewood Pass"]:
		for side in [-1.0, 1.0]:
			for s in _along(I, road, 5.6 * side, 9.0, 3.0 if side > 0 else 7.0):
				var p: Vector2 = s["p"]
				# barrier posts on the outside of bends
				if rr.randf() < 0.55 and I.height_at(p.x, p.y) > 0.5 and not _near_junction(I, p, 14.0):
					I.put_breakable("k_retro_detail-barrier-type-a", p.x, p.y, _yaw_to(s["t"]) + PI * 0.5, 1.0, 0.5)

# ---------------------------------------------------------------- the green stuff

static func scatter(I) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 4321
	var autumn: bool = I.season == 2
	var cell := 8.0
	var steps := int(I.HALF * 2.0 / cell)
	for gj in steps:
		for gi in steps:
			var x: float = -I.HALF + (gi + rr.randf()) * cell
			var z: float = -I.HALF + (gj + rr.randf()) * cell
			var roll := rr.randf()
			var h: float = I.height_at(x, z)
			if h < 1.0 or I.is_blocked(x, z):
				continue
			var s: int = I.surface_at(x, z)
			var fd := Vector2(x, z).distance_to(LAKE)
			var cd := Vector2(x, z).distance_to(CASTLE)
			if s == I.S_FOREST or fd < 210.0:
				var dens := 0.78 if fd < 200.0 else 0.4
				if roll < dens:
					var t := rr.randf()
					var nm := "k_forest_tree" if t < 0.45 else ("k_forest_tree-high" if t < 0.7 else ("k_surv_tree-tall" if t < 0.88 else "pine_tall"))
					if autumn and t > 0.85:
						nm = "k_surv_tree-autumn-tall"
					var sc := rr.randf_range(0.8, 1.25) * (2.8 if nm == "pine_tall" else 1.0)
					I.put(nm, x, z, rr.randf() * TAU, sc, "cyl")
				elif roll < dens + 0.06 and I.is_free(Vector2(x, z), Vector2(1.8, 1.8), 0.0):
					I.put(["k_forest_rocks-low", "k_surv_rock-b", "k_surv_rock-c"][rr.randi_range(0, 2)], x, z, rr.randf() * TAU, rr.randf_range(0.8, 1.4), "box")
				elif roll < dens + 0.12:
					I.put("k_forest_plant", x, z, rr.randf() * TAU, rr.randf_range(0.9, 1.4), "")
				continue
			if s == I.S_SAND or s == I.S_FIELD:
				if s == I.S_SAND and roll < 0.03:
					I.put("dune_grass", x, z, rr.randf() * TAU, 2.5, "")
				continue
			if cd < 150.0:
				continue   # the castle hill does its own trees
			if _in_town(x, z) and roll > 0.02:
				continue   # towns keep their own trees
			# meadows: lone trees, little copses, rocks, grass
			var clump: float = I.noise2.get_noise_2d(x * 0.4, z * 0.4)
			var p_tree := 0.05 + maxf(clump, 0.0) * 0.5
			if roll < p_tree:
				var t2 := rr.randf()
				var nm2 := "k_surv_tree" if t2 < 0.35 else ("k_castle_tree-large" if t2 < 0.65 else ("k_surv_tree-tall" if t2 < 0.85 else "k_castle_tree-small"))
				if autumn and t2 < 0.5:
					nm2 = "k_surv_tree-autumn" if t2 < 0.25 else "k_surv_tree-autumn-tall"
				I.put(nm2, x, z, rr.randf() * TAU, rr.randf_range(0.8, 1.2), "cyl")
			elif roll < p_tree + 0.03 and I.normal_at(x, z).y < 0.97:
				I.put(["k_surv_rock-a", "k_surv_rock-c", "k_surv_rock-flat-grass"][rr.randi_range(0, 2)], x, z, rr.randf() * TAU, rr.randf_range(0.7, 1.3), "box")
			elif roll < p_tree + 0.2:
				I.put("k_surv_grass-large", x, z, rr.randf() * TAU, rr.randf_range(0.8, 1.3), "")
			elif roll < p_tree + 0.24 and I.season < 2:
				I.put("flowers", x, z, rr.randf() * TAU, 2.0, "")
	# a few snowmen and presents around in winter
	if I.season == 3:
		for k in 30:
			var x2 := rr.randf_range(-400, 400)
			var z2 := rr.randf_range(-400, 400)
			if I.height_at(x2, z2) > 1.0 and not I.is_blocked(x2, z2) and I.inland(x2, z2) > 30:
				I.put_breakable(["k_holi_snowman", "k_holi_snowman-hat", "k_holi_candy-cane-red", "k_holi_present-b-round"][k % 4],
					x2, z2, rr.randf() * TAU, 1.0, 0.6)

static func _in_town(x: float, z: float) -> bool:
	return _in_city(Vector2(x, z)) or Vector2(x, z).distance_to(Vector2(-215, -158)) < 88.0 or Hood.in_hood(x, z)

# ---------------------------------------------------------------- moving bits

static func tick_anims(I, dt: float, car_pos: Vector3) -> void:
	Hood.ghost_tick(I, I.night)
	var t: float = I.time
	for an in I.anims:
		var pos: Vector3 = an["pos"]
		if pos.distance_squared_to(car_pos) > 160.0 * 160.0:
			continue
		var pool = I.pools[an["pool"]]
		var ph: float = an["ph"]
		match an.get("kind", ""):
			"blades":
				pool.put(an["slot"], Transform3D(Basis(Vector3.UP, an["yaw"]) * Basis(Vector3(0, 0, 1), t * 0.9 + ph).scaled(Vector3.ONE * an["sc"]), pos))
			"flame":
				var s := 1.0 + sin(t * 13.0 + ph) * 0.08 + sin(t * 7.3) * 0.06
				pool.put(an["slot"], Transform3D(Basis(Vector3.UP, t * 2.0).scaled(Vector3(an["sc"], an["sc"] * s * 1.1, an["sc"])), pos))
			"flag":
				pool.put(an["slot"], Transform3D(Basis(Vector3.UP, an["yaw"] + sin(t * 1.5 + ph) * 0.4).scaled(Vector3.ONE * an["sc"]), pos))
			"bob":
				var b := Basis(Vector3.UP, an["yaw"]) * Basis(Vector3(1, 0, 0), sin(t * 1.1 + ph) * 0.05) * Basis(Vector3(0, 0, 1), sin(t * 0.8 + ph) * 0.06)
				pool.put(an["slot"], Transform3D(b.scaled(Vector3.ONE * an["sc"]), pos + Vector3(0, sin(t * 1.3 + ph) * 0.12, 0)))
			"critter":
				_critter(I, an, pool, dt, t, car_pos)

static func _critter(I, an: Dictionary, pool, dt: float, time: float, car_pos: Vector3) -> void:
	var ph: float = an["ph"]
	var home: Vector3 = an["home"]
	var cp: Vector3 = an["pos"]
	var to_car := car_pos - cp
	to_car.y = 0.0
	var dist := to_car.length()
	var sc: float = an["sc"]
	if an["style"] == "hover":
		var ang := time * 0.8 + ph
		var hp := home + Vector3(cos(ang) * 1.6, 1.6 + sin(time * 2.6 + ph) * 0.25, sin(ang) * 1.6)
		var tng := Vector3(-sin(ang), 0, cos(ang))
		pool.put(an["slot"], Transform3D(Basis(Vector3.UP, atan2(-tng.x, -tng.z)).scaled(Vector3.ONE * sc), hp))
		return
	an["t"] -= dt
	var grounded: bool = an["y"] <= 0.0 and an["vy"] == 0.0
	if grounded and dist < 4.5:
		var away := -to_car.normalized() if dist > 0.01 else Vector3.RIGHT
		an["vy"] = 4.2
		an["hv"] = away * 4.5
		an["yaw"] = atan2(-away.x, -away.z)
	elif grounded and an["t"] <= 0.0:
		an["t"] = randf_range(1.0, 3.2)
		var want: float = an["yaw"] + randf_range(-1.0, 1.0)
		var step := 1.0
		if dist < 18.0:
			want = atan2(-to_car.x, -to_car.z)
			step = 0.0
		var back := home - cp
		back.y = 0.0
		if back.length() > 3.0:
			want = atan2(-back.x, -back.z)
			step = 1.4
		an["yaw"] = want
		if an["style"] == "scuttle":
			an["vy"] = 1.6
			an["hv"] = Basis(Vector3.UP, want) * Vector3(1.0 if randf() < 0.5 else -1.0, 0, 0) * 1.4
		else:
			an["vy"] = 3.0
			an["hv"] = Basis(Vector3.UP, want) * Vector3(0, 0, -step)
	if an["vy"] != 0.0 or an["y"] > 0.0:
		an["vy"] -= 14.0 * dt
		an["y"] += an["vy"] * dt
		cp += an["hv"] * dt
		var off := cp - home
		off.y = 0.0
		if off.length() > 6.0:
			cp = home + off.normalized() * 6.0
		if an["y"] <= 0.0:
			an["y"] = 0.0
			an["vy"] = 0.0
			an["hv"] = Vector3.ZERO
			an["squash"] = 1.0
	cp.y = I.height_at(cp.x, cp.z)
	an["squash"] = move_toward(an["squash"], 0.0, dt * 5.0)
	an["cur"] = lerp_angle(an["cur"], an["yaw"], 1.0 - exp(-dt * 9.0))
	an["pos"] = cp
	var sy := 1.0 + clampf(float(an["vy"]) * 0.03, -0.1, 0.12) - float(an["squash"]) * 0.16
	var sxz := 1.0 / sqrt(maxf(0.5, sy))
	pool.put(an["slot"], Transform3D(Basis(Vector3.UP, an["cur"]).scaled(Vector3(sxz, sy, sxz) * sc), cp + Vector3(0, an["y"], 0)))
