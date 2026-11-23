extends Node3D
## The floating diorama: generates land ahead of the car, crumbles it away behind, and answers
## "is there ground here?" for the car.
##
## Space: progress v runs up the screen (world F), lateral u runs to screen-right (world S).
## Tiles sit on a world-aligned grid, which shows as diamonds through the isometric camera.

const M := preload("res://scripts/core/models.gd")
const P := preload("res://scripts/core/palette.gd")
const MB := preload("res://scripts/core/mesh_builder.gd")
const Pool := preload("res://scripts/game/pool.gd")
const People := preload("res://scripts/game/people.gd")
const CARS := preload("res://scripts/game/cars.gd")

const T := M.T
const D := T * 0.70710678          # stripe spacing in v
const F := Vector3(-0.70710678, 0, -0.70710678)
const S := Vector3(0.70710678, 0, -0.70710678)
const NO_GROUND := -1000.0
const AHEAD := 72.0
const U_MAX := 16.5

const BIOMES := ["countryside", "seaside", "forest", "sky"]
const BIOME_NAMES := {"countryside": "Countryside", "seaside": "Seaside", "forest": "Forest & Mountains", "sky": "Sky Islands"}
const BIOME_TOP := {"countryside": P.GRASS, "seaside": P.SAND, "forest": P.GRASS_FOREST, "sky": P.GRASS_SKY}
const BIOME_SIDE := {"countryside": P.DIRT, "seaside": P.SAND_SIDE, "forest": P.DIRT, "sky": P.STONE_SIDE}
const BIOME_PATH := {"countryside": P.PATH, "seaside": P.PLANK, "forest": P.PATH, "sky": P.CLOUD}
# offroad stretches: the trail surface and the humps on it
const ROUGH_TOP := {"countryside": P.PATH, "seaside": P.SAND, "forest": P.SOIL, "sky": P.CLOUD}
const MOUND_TOP := {"countryside": P.GRASS, "seaside": P.SAND, "forest": P.MOSS, "sky": P.CLOUD}

# name: [weight, radius, knock kind, sway]   kind "flat" = no collision, "solid" = can't knock over
const DECOR := {
	"countryside": {"tree_round": [3.0, 0.45, "wood", 0.5], "tree_blossom": [2.0, 0.45, "wood", 0.5], "bush": [3.0, 0.4, "soft", 0.6],
		"flowers": [4.0, 0.0, "flat", 1.0], "tuft": [4.0, 0.0, "flat", 1.0], "hay": [1.4, 0.42, "soft", 0.0],
		"sunflower": [1.4, 0.3, "soft", 0.8], "fence": [1.6, 0.5, "wood", 0.0], "rock": [1.0, 0.36, "rock", 0.0],
		"barn": [0.22, 1.5, "solid", 0.0], "windmill": [0.2, 0.85, "solid", 0.0]},
	"forest": {"pine": [4.0, 0.42, "wood", 0.3], "pine_tall": [3.0, 0.45, "wood", 0.25], "tree_round": [1.5, 0.45, "wood", 0.5],
		"fern": [3.0, 0.0, "flat", 1.0], "mushroom": [2.0, 0.3, "soft", 0.0], "stump": [1.4, 0.3, "wood", 0.0],
		"log": [1.0, 0.55, "wood", 0.0], "rock": [1.6, 0.36, "rock", 0.0], "cabin": [0.2, 1.3, "solid", 0.0]},
	"seaside": {"umbrella": [2.0, 0.35, "soft", 0.2], "deck_chair": [1.4, 0.35, "wood", 0.0], "dune_grass": [4.0, 0.0, "flat", 1.0],
		"beach_rock": [2.0, 0.38, "rock", 0.0], "sandcastle": [1.5, 0.42, "sand", 0.0], "buoy": [1.0, 0.26, "soft", 0.0],
		"crate": [1.0, 0.36, "wood", 0.0], "hut": [0.3, 0.95, "solid", 0.0], "lighthouse": [0.15, 0.9, "solid", 0.0]},
	"sky": {"cloud_puff": [3.0, 0.45, "cloud", 0.0], "tree_puff": [2.5, 0.42, "wood", 0.5], "crystal": [2.0, 0.3, "crystal", 0.0],
		"pillar": [1.0, 0.32, "rock", 0.0], "tuft": [2.0, 0.0, "flat", 1.0], "flowers": [2.0, 0.0, "flat", 1.0]},
}
const OBSTACLES := {
	"countryside": {"hay": 2.0, "rock": 2.0, "fence": 1.5, "bush": 2.0},
	"forest": {"log": 2.0, "stump": 2.0, "rock": 2.0, "mushroom": 1.0},
	"seaside": {"sandcastle": 2.0, "crate": 2.0, "beach_rock": 2.0, "umbrella": 1.0, "buoy": 1.0},
	"sky": {"cloud_puff": 3.0, "crystal": 2.0, "pillar": 1.0},
}
const RUIN_SWAP := {}   # (the post-apocalyptic look is retired: props stay as built)
const BIG := ["barn", "windmill", "cabin", "hut", "lighthouse", "house_ruin", "house_ruin_b", "house_ruin_c", "wreck_car", "wall_ruin"]

var game: Node          # main.gd
var mat: ShaderMaterial
var mat_sway := {}      # sway amount -> material
var seed_value := 1
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var difficulty := 0.0

var pools := {}
var tiles := {}         # Vector2i -> Dictionary
var stripes := {}       # int s -> Array (tile keys)
var stripe_items := {}  # int s -> Array (items: props, coins, fuel, surfaces)
var gen_s := -12        # next stripe to generate
var crumble_s := -12    # next stripe to crumble
var crumble_v := -999.0
var falling: Array = []
var knocked: Array = []
var props_hash := {}    # Vector2i (2x2 m cells) -> Array of props
var coins: Array = []
var fuels: Array = []
var surfaces: Array = []   # ramps and bridges: {kind, origin, fwd, side, len, half_w, height, launch, s}
var surf_cells := {}       # Vector2i (4 m cell) -> Array of surfaces touching it
var bump_cells := {}       # Vector2i (4 m cell) -> Array of mounds touching it
var muds: Array = []       # mud puddles on offroad stretches: {pos, r, s, slot}
var rails: Array = []      # grind rails: {pts: [Vector3], len, va, vb, pieces}
var terra_meshes := {}     # stripe -> MeshInstance3D of the uneven ground there (offroad / canyon)
const TERRA_KINDS := ["rough", "dirt"]
var gauntlets: Array = []  # chained challenges: {va, vb, done}
var last_gauntlet_v := 0.0
var bends: Array = []      # extra S-curves in the centerline over deck challenges: {va, vb, amp, k}
var decks: Array = []      # deck challenges: {style, va, vb}
var last_deck_v := 0.0
var force_deck := ""       # testing: make the first challenge this style, early
var force_kind := ""       # testing: make the first land segment after 25 m this kind
var forced_v := -1.0
const SURF_CELL := 4.0
const NO_SURFS: Array = []
var stations: Array = []
var markers: Array = []
var lamps: Array = []
var windmills: Array = []
var segments: Array = []
var plan_v := -20.0
var next_station_v := 230.0
var station_count := 0
var next_biome_v := 420.0
var next_fuel_v := 40.0
var next_coin_v := 14.0
var pads: Array = []
var chases: Array = []       # {v_start, v_end, parked, yaw, done}
var next_chase_v := 320.0
var next_marker := 100
var biome_bag: Array = []
var cur_biome := "countryside"
var last_biome_reported := ""
var amp_phase := Vector3.ZERO
var label_font: Font
var winter_ice := false     # set by atmos: lay ice patches while it's snowing
var people: People
var places: Array = []
var anims: Array = []
var fx: Node                # set by main, for chimney smoke and puffs

# Places beside the road, per region: [type, weight]
const PLACE_TYPES := {
	"countryside": [["farm", 3.0], ["village", 3.0], ["pond", 2.0], ["orchard", 1.5]],
	"seaside": [["beach", 3.0], ["pier", 2.0], ["cafe", 1.5]],
	"forest": [["campsite", 3.0], ["mountain", 3.0], ["cabin", 1.5]],
	"sky": [["ruins", 3.0], ["balloons", 2.5], ["garden", 1.5]],
}
const TILE_POOLS := {"tile_field": 260, "tile_cobble": 260, "tile_plank": 160, "tile_pier": 60, "tile_rock": 360}

func setup(g: Node, material: ShaderMaterial, font: Font) -> void:
	game = g
	mat = material
	label_font = font
	pools["tile"] = _pool("tile", 1600, true)
	pools["under"] = _pool("under", 900, true, false)
	pools["water"] = _pool("water", 300, true, false)
	for b in DECOR:
		for nm in DECOR[b]:
			if not pools.has(nm):
				pools[nm] = _pool(nm, 260 if DECOR[b][nm][1] < 0.8 else 24, false, DECOR[b][nm][2] != "flat", DECOR[b][nm][3])
	for nm in ["coin", "fuel", "ramp", "bridge", "station", "arch", "marker", "lamp", "windmill_blades", "pad",
			"deck_plank", "deck_track_a", "deck_track_b", "deck_stilt", "deck_stand", "mound", "mud", "slick_dome", "slick_pillow",
			"rail_piece", "rail_post"]:
		if not pools.has(nm):
			var cap := {"coin": 260, "fuel": 24, "ramp": 24, "bridge": 80, "station": 6, "arch": 2, "marker": 6, "lamp": 60, "windmill_blades": 24, "pad": 30,
				"deck_plank": 220, "deck_track_a": 130, "deck_track_b": 130, "deck_stilt": 50, "deck_stand": 50,
				"mound": 220, "mud": 24, "slick_dome": 120, "slick_pillow": 200, "rail_piece": 90, "rail_post": 34}[nm] as int
			pools[nm] = _pool(nm, cap, nm == "mound", nm != "coin" and nm != "mud")
	for nm in TILE_POOLS:
		pools[nm] = _pool(nm, TILE_POOLS[nm], true)
	pools["ground_bits"] = _pool("ground_bits", 1400, false, false, 1.0)
	pools["road_bits"] = _pool("road_bits", 500, false, false, 0.6)
	people = People.new()
	add_child(people)
	people.setup(self, mat)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.16

func _pool(nm: String, cap: int, custom: bool, shadows := true, sway := 0.0) -> Pool:
	var p: Pool = Pool.new()
	var m := mat
	if sway > 0.0:
		var key := snappedf(sway, 0.1)
		if not mat_sway.has(key):
			var sm: ShaderMaterial = mat.duplicate()
			sm.set_shader_parameter("sway", key)
			mat_sway[key] = sm
		m = mat_sway[key]
	p.setup(M.get_mesh(nm), cap, m, custom, shadows)
	p.name = nm
	add_child(p)
	return p

## The shared shader parameters (season, night, wind) for every world material.
func set_shader(param: String, value) -> void:
	mat.set_shader_parameter(param, value)
	for k in mat_sway:
		mat_sway[k].set_shader_parameter(param, value)

# ------------------------------------------------------------------ run setup

func reset(seed_in: int, force_biome := "") -> void:
	seed_value = seed_in
	rng.seed = seed_in
	noise.seed = seed_in
	for k in pools:
		pools[k].clear_all()
	for m in markers:
		m["label"].queue_free()
	tiles.clear(); stripes.clear(); stripe_items.clear(); falling.clear(); knocked.clear()
	props_hash.clear(); coins.clear(); fuels.clear(); surfaces.clear(); stations.clear()
	surf_cells.clear(); bends.clear(); decks.clear(); bump_cells.clear(); muds.clear()
	rails.clear(); gauntlets.clear()
	for k in terra_meshes:
		terra_meshes[k].queue_free()
	terra_meshes.clear()
	last_gauntlet_v = 0.0
	last_deck_v = 0.0
	forced_v = -1.0
	pads.clear(); chases.clear()
	places.clear(); anims.clear()
	people.clear()
	markers.clear(); lamps.clear(); windmills.clear(); segments.clear()
	amp_phase = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	gen_s = int(floor(-16.0 / D))
	crumble_s = gen_s
	crumble_v = -999.0
	plan_v = -20.0
	next_station_v = 230.0
	station_count = 0
	next_fuel_v = 36.0
	next_coin_v = 16.0
	next_chase_v = rng.randf_range(300.0, 420.0)
	next_marker = 100
	difficulty = 0.0
	biome_bag = BIOMES.duplicate()
	_shuffle(biome_bag)
	cur_biome = biome_bag.pop_back()
	if force_biome != "":
		cur_biome = force_biome
		biome_bag.erase(force_biome)
	last_biome_reported = ""
	next_biome_v = rng.randf_range(380.0, 480.0)
	segments.append({"v0": -40.0, "v1": 14.0, "type": "start", "biome": cur_biome, "w": 6.5, "holes": [], "density": 0.0, "narrow_end": false})
	plan_v = 14.0
	_plan_until(AHEAD + 40.0)
	update_gen(0.0)
	# the starting arch
	var arch_v := 5.0
	var ap := pos_at(arch_v, 0.0)
	_add_item_prop("arch", ap, atan2(-tangent(arch_v).x, -tangent(arch_v).z), 1.0, 0.0, "flat", _stripe_of(arch_v))

func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]; a[i] = a[j]; a[j] = t

# ------------------------------------------------------------------ geometry helpers

## Cruise multiplier at distance v: the run keeps getting faster (1.0 at the start, ~1.5 by 800 m, ~1.8 late).
func pace_at(v: float) -> float:
	return 1.0 + 0.8 * (1.0 - exp(-maxf(v, 0.0) / 800.0))

func center(v: float) -> float:
	var a := clampf(1.5 + maxf(v, 0.0) / 160.0, 1.5, 6.0)
	if v < 10.0:
		a *= clampf((v + 10.0) / 20.0, 0.0, 1.0)
	var c := a * (0.62 * sin(v / 23.0 + amp_phase.x) + 0.38 * sin(v / 11.7 + amp_phase.y)) - a * (0.62 * sin(amp_phase.x) + 0.38 * sin(amp_phase.y)) * clampf(1.0 - v / 30.0, 0.0, 1.0)
	for b in bends:
		if v > b["va"] and v < b["vb"]:
			var t: float = (v - b["va"]) / (b["vb"] - b["va"])
			c += b["amp"] * sin(PI * b["k"] * t) * sin(PI * t)
	return c

func tangent(v: float) -> Vector3:
	var dc := (center(v + 0.5) - center(v - 0.5))
	return (F + S * dc).normalized()

func pos_at(v: float, u_off: float) -> Vector3:
	return F * v + S * (center(v) + u_off)

func v_of(p: Vector3) -> float:
	return p.x * F.x + p.z * F.z

func u_of(p: Vector3) -> float:
	return p.x * S.x + p.z * S.z

func _stripe_of(v: float) -> int:
	return int(round(v / D))

func _key(p: Vector3) -> Vector2i:
	return Vector2i(int(round(p.x / T)), int(round(p.z / T)))

func _hash(i: int, j: int, k: int) -> float:
	var h := hash(Vector3i(i, j, k + seed_value * 31))
	return float(h & 0xffffff) / float(0xffffff)

# ------------------------------------------------------------------ planning

func segment_at(v: float) -> Dictionary:
	for i in range(segments.size() - 1, -1, -1):
		var s: Dictionary = segments[i]
		if v >= s["v0"]:
			return s
	return segments[0]

func _plan_until(v_target: float) -> void:
	while plan_v < v_target:
		_plan_next()

func _plan_next() -> void:
	while not bends.is_empty() and float(bends[0]["vb"]) < plan_v - 260.0:
		bends.pop_front()
	while not decks.is_empty() and float(decks[0]["vb"]) < plan_v - 260.0:
		decks.pop_front()
	while not gauntlets.is_empty() and float(gauntlets[0]["vb"]) < plan_v - 400.0:
		gauntlets.pop_front()
	var d := clampf(plan_v / 2600.0, 0.0, 1.0)
	var v0 := plan_v
	# biome change: a crossing, then the new biome
	if v0 >= next_biome_v:
		if biome_bag.is_empty():
			biome_bag = BIOMES.duplicate()
			biome_bag.erase(cur_biome)
			_shuffle(biome_bag)
		var nb: String = biome_bag.pop_back()
		var use_bridge := rng.randf() < 0.55
		_add_gap(v0, use_bridge, d, cur_biome)
		cur_biome = nb
		next_biome_v = plan_v + rng.randf_range(380.0, 520.0)
		_add_land(plan_v, 26.0, d, "plain")
		return
	if v0 >= next_station_v - 8.0:
		segments.append({"v0": v0, "v1": v0 + 20.0, "type": "station", "biome": cur_biome, "w": 6.2, "holes": [], "density": 0.0, "narrow_end": false})
		plan_v = v0 + 20.0
		var sv := v0 + 10.0
		_add_station(sv)
		station_count += 1
		next_station_v = sv + clampf(210.0 + station_count * 26.0, 210.0, 440.0)
		_add_land(plan_v, 14.0, d, "plain")
		return
	# the gauntlet: a kicker onto a grind rail, down onto a plank bridge, over humps, into a red rock canyon
	var g_ok := v0 > 220.0 and v0 - last_gauntlet_v > 380.0 and v0 - last_deck_v > 60.0 and v0 + 260.0 < next_biome_v and not _in_chase(v0)
	if (force_kind == "gauntlet" and last_gauntlet_v == 0.0 and v0 > 25.0) or (g_ok and rng.randf() < 0.22 + d * 0.1):
		_plan_gauntlet(v0, d)
		return
	# deck challenges: a long skinny plank bridge or a twisty toy race track over the drop
	# (more likely mid-chase: the cruiser is a shaky driver on narrow decks)
	var chasing := _in_chase(v0)
	var deck_ok := v0 > 150.0 and v0 - last_deck_v > (70.0 if chasing else 110.0) and v0 + 90.0 < next_biome_v
	if force_deck != "" and v0 > 30.0 and last_deck_v == 0.0:
		deck_ok = true
	if deck_ok and (rng.randf() < (0.45 if chasing else 0.2 + d * 0.12) or (force_deck != "" and last_deck_v == 0.0)):
		var style := "plank" if rng.randf() < 0.5 else "track"
		if force_deck != "" and last_deck_v == 0.0:
			style = force_deck
		_add_land(v0, rng.randf_range(16.0, 24.0), d, "plain", true)
		_add_deck(plan_v, style, d)
		last_deck_v = plan_v
		_add_land(plan_v, rng.randf_range(20.0, 30.0), d, "plain")
		return
	var len := rng.randf_range(26.0, 52.0) * lerpf(1.0, 0.75, d)
	var roll := rng.randf()
	var kind := "plain"
	if v0 > 40.0:
		if roll < 0.22 + d * 0.08: kind = "ramp_gap"
		elif roll < 0.31 + d * 0.12: kind = "bridge_gap"
		elif roll < 0.46 + d * 0.08: kind = "holes"
		elif roll < 0.54: kind = "split"
		elif roll < 0.62: kind = "narrow"
		elif roll < 0.69: kind = "stunt"
		elif roll < 0.85 and v0 > 70.0: kind = "rough" if rng.randf() < 0.5 else "dirt"
	if force_kind != "" and forced_v < 0.0 and v0 > 25.0:
		kind = force_kind
		forced_v = v0
	if kind == "rough" or kind == "dirt":
		len = maxf(len, 40.0) * 1.3
	match kind:
		"ramp_gap":
			_add_land(v0, len, d, "plain", true)
			_add_gap(plan_v, false, d, cur_biome)
		"bridge_gap":
			_add_land(v0, len, d, "plain", true)
			_add_gap(plan_v, true, d, cur_biome)
		_:
			_add_land(v0, len, d, kind)

func _in_chase(v: float) -> bool:
	for c in chases:
		if v >= float(c["v_start"]) + 20.0 and v <= float(c["v_end"]) - 30.0:
			return true
	return false

func _add_land(v0: float, len: float, d: float, kind: String, narrow_end := false) -> void:
	var w := rng.randf_range(3.9, 4.9) * lerpf(1.0, 0.8, d)
	if kind == "narrow":
		w = lerpf(2.8, 2.3, d)
	if kind == "split":
		w = maxf(w, 5.0)
	if kind == "rough" or kind == "dirt":
		w = rng.randf_range(4.8, 5.6)
	var seg := {"v0": v0, "v1": v0 + len, "type": "land", "biome": cur_biome, "w": w, "holes": [], "narrow_end": narrow_end,
		"density": lerpf(0.035, 0.11, d), "kind": kind}
	match kind:
		"holes":
			var n := rng.randi_range(2, 3 + int(d * 3.0))
			for i in n:
				var hv := v0 + 6.0 + rng.randf() * (len - 12.0)
				var r := rng.randf_range(1.3, 2.3)
				var off := rng.randf_range(-w + 1.0, w - 1.0)
				# always leave a lane open
				if absf(off) < 1.2:
					off = signf(off + 0.01) * 1.2
				seg["holes"].append({"off": off, "va": hv, "vb": hv + rng.randf_range(0.0, 4.0), "r": r})
		"split":
			seg["holes"].append({"off": 0.0, "va": v0 + 8.0, "vb": v0 + len - 8.0, "r": rng.randf_range(1.4, 2.0)})
		"stunt":
			var rv := v0 + len * 0.5
			_add_ramp(rv, rng.randf_range(-1.5, 1.5), 6.0, false)
	segments.append(seg)
	plan_v = v0 + len
	if kind == "rough":
		_plan_rough(seg, d)
	_plan_items(seg)

## A red rock canyon: a sandy wash winding between sandstone pillows, with big slickrock domes across
## the trail to crawl up and over. The domes are climbable; the pillows at the sides are walls.
func _plan_rough(seg: Dictionary, d: float) -> void:
	var v0: float = seg["v0"]
	var v1: float = seg["v1"]
	var w: float = seg["w"]
	# desert life in the cracks
	for k in rng.randi_range(3, 6):
		var bv := rng.randf_range(v0 + 3.0, v1 - 3.0)
		var bp := pos_at(bv, rng.randf_range(-w + 1.0, w - 1.0))
		if bump_at(bp) < 0.05:
			_add_item_prop("bud_glow", bp, rng.randf() * TAU, rng.randf_range(0.9, 1.3), 0.0, "flat", _stripe_of(bv))

func _add_mound(p: Vector3, r: float, h: float, top: int, rz := -1.0, n_exp := 2.0, pool := "mound", yaw := INF) -> void:
	var slot: int = pools[pool].alloc()
	if slot < 0:
		return
	if yaw == INF:
		yaw = rng.randf() * TAU
	if rz < 0.0:
		rz = r
	var m := {"kind": "mound", "pos": p, "r": r, "rz": rz, "h": h, "n": n_exp, "pool": pool, "slot": slot, "yaw": yaw,
		"s": _stripe_of(v_of(p)), "cells": []}
	pools[pool].put(slot, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(r, h, rz)), p + Vector3(0, -0.015, 0)))
	if pool == "mound":
		pools[pool].custom(slot, Color(top / 255.0, P.DIRT / 255.0, rng.randf(), 0))
	var reach := maxf(r, rz)
	for cx in range(int(floor((p.x - reach) / SURF_CELL)), int(floor((p.x + reach) / SURF_CELL)) + 1):
		for cz in range(int(floor((p.z - reach) / SURF_CELL)), int(floor((p.z + reach) / SURF_CELL)) + 1):
			var key := Vector2i(cx, cz)
			if not bump_cells.has(key):
				bump_cells[key] = []
			bump_cells[key].append(m)
			m["cells"].append(key)
	_stripe_add(m["s"], m)

func _mound_unlink(m: Dictionary) -> void:
	for key in m["cells"]:
		if bump_cells.has(key):
			bump_cells[key].erase(m)
			if bump_cells[key].is_empty():
				bump_cells.erase(key)
	m["cells"] = []

## Height of the humps at p (0 on smooth ground).
func bump_at(p: Vector3) -> float:
	if bump_cells.is_empty():
		return 0.0
	var h := 0.0
	for m in bump_cells.get(Vector2i(int(floor(p.x / SURF_CELL)), int(floor(p.z / SURF_CELL))), NO_SURFS):
		var dx: float = p.x - m["pos"].x
		var dz: float = p.z - m["pos"].z
		var cy := cos(float(m["yaw"]))
		var sy := sin(float(m["yaw"]))
		var lx := (dx * cy - dz * sy) / float(m["r"])
		var lz := (dx * sy + dz * cy) / float(m["rz"])
		var d2 := lx * lx + lz * lz
		if d2 < 1.0:
			h = maxf(h, float(m["h"]) * pow(1.0 - d2, float(m["n"])))
	return h

func _add_mud(p: Vector3, r: float) -> void:
	var slot: int = pools["mud"].alloc()
	if slot < 0:
		return
	var md := {"kind": "mud", "pos": p, "r": r, "slot": slot, "s": _stripe_of(v_of(p))}
	pools["mud"].put(slot, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(r, 1, r * rng.randf_range(0.7, 1.0))), p))
	muds.append(md)
	_stripe_add(md["s"], md)

## The mud puddle under p (or {}).
func mud_at(p: Vector3) -> Dictionary:
	for md in muds:
		var dx: float = p.x - md["pos"].x
		var dz: float = p.z - md["pos"].z
		if dx * dx + dz * dz < float(md["r"]) * float(md["r"]) * 0.8:
			return md
	return {}

func _add_gap(v0: float, bridge: bool, d: float, biome: String) -> void:
	var glen := rng.randf_range(4.2, 5.2) + d * 1.4
	if bridge:
		glen = rng.randf_range(6.0, 9.0) + d * 3.0
	var seg := {"v0": v0, "v1": v0 + glen, "type": "gap", "biome": biome, "w": 0.0, "holes": [], "density": 0.0, "narrow_end": false}
	segments.append(seg)
	if bridge:
		_add_bridge(v0 - 1.6, v0 + glen + 1.6)
	else:
		_add_ramp(v0 - 0.15, 0.0, 7.4, true)
		# a coin arc over the gap
		var t := tangent(v0)
		var base := pos_at(v0 - 0.15, 0.0)
		for k in 6:
			var dd := 1.2 + k * 1.35
			var tt := dd / 9.0
			var y := 0.9 + 7.4 * tt - 0.5 * 17.0 * tt * tt + 0.45
			_add_coin(base + t * dd + Vector3(0, y, 0), _stripe_of(v0 + dd))
	plan_v = v0 + glen

func _add_ramp(v_top: float, u_off: float, launch: float, gap_ramp: bool) -> void:
	var t := tangent(v_top)
	var top := pos_at(v_top, u_off)
	var origin := top - t * 2.4
	var side := Vector3(-t.z, 0, t.x)
	var yaw := atan2(-t.x, -t.z)
	var s := _stripe_of(v_of(origin))
	var surf := {"kind": "ramp", "origin": origin, "fwd": t, "side": side, "len": 2.4, "half_w": 1.3, "height": 0.9, "launch": launch, "s": s, "slot": -1, "gap": gap_ramp}
	surf["slot"] = pools["ramp"].alloc()
	pools["ramp"].put(surf["slot"], Transform3D(Basis(Vector3.UP, yaw), origin))
	surfaces.append(surf)
	_surf_add(surf)
	_stripe_add(s, surf)
	if not gap_ramp:
		for k in 4:
			_add_coin(origin + t * (3.0 + k * 1.3) + Vector3(0, 1.6 + sin(k * 0.8) * 0.6, 0), s + 2 + k)

func _add_bridge(va: float, vb: float) -> void:
	var a := pos_at(va, 0.0)
	var b := pos_at(vb, 0.0)
	var dir := (b - a)
	dir.y = 0
	var length := dir.length()
	dir = dir / length
	var side := Vector3(-dir.z, 0, dir.x)
	var yaw := atan2(-dir.x, -dir.z)
	var n := int(ceil(length / 1.6))
	var s := _stripe_of(va)
	var surf := {"kind": "bridge", "origin": a, "fwd": dir, "side": side, "len": n * 1.6, "half_w": 1.1, "height": 0.0, "launch": 0.0, "s": s, "slots": []}
	for k in n:
		var slot: int = pools["bridge"].alloc()
		pools["bridge"].put(slot, Transform3D(Basis(Vector3.UP, yaw), a + dir * (k * 1.6)))
		surf["slots"].append(slot)
	surfaces.append(surf)
	_surf_add(surf)
	_stripe_add(_stripe_of(va + length * 0.5), surf)
	for k in int(length / 1.6):
		_add_coin(a + dir * (0.8 + k * 1.6) + Vector3(0, 0.5, 0), _stripe_of(va + k * 1.6))

## A deck challenge across a long drop. "plank": a skinny wooden bridge on stilts that sags and sways
## through gentle S-bends. "track": a toy race track with candy kerbs, tighter bends and little hills.
## Built from short straight pieces, each its own surface, so they crumble away one by one behind you.
func _add_deck(v0: float, style: String, d: float, straight := 0.0) -> void:
	var plank := style == "plank"
	var L := (rng.randf_range(34.0, 48.0) if plank else rng.randf_range(42.0, 60.0)) + d * 16.0
	var speed := 9.0 * pace_at(v0 + L * 0.5) * 1.05
	var r_min := maxf(6.0, speed * (0.62 if plank else 0.48))
	var k := rng.randi_range(2, 3) if plank else rng.randi_range(3, 5)
	var wv := PI * float(k) / L
	var amp := minf(rng.randf_range(2.2, 3.6) if plank else rng.randf_range(2.6, 4.4), 1.0 / (r_min * wv * wv))
	amp = minf(amp, 0.85 / wv)   # keep the steepest bit under ~40°
	if rng.randf() < 0.5:
		amp = -amp
	bends.append({"va": v0 + straight, "vb": v0 + L, "amp": amp * (L - straight) / L, "k": k})
	segments.append({"v0": v0, "v1": v0 + L, "type": "gap", "biome": cur_biome, "w": 0.0, "holes": [], "density": 0.0,
		"narrow_end": false, "kind": "deck_" + style})
	decks.append({"style": style, "va": v0, "vb": v0 + L, "done": false})
	var half := 0.95 if plank else 1.2
	var sag := rng.randf_range(0.35, 0.7) if plank else 0.0
	var hill := (rng.randf_range(0.5, 1.1) if rng.randf() < 0.7 else 0.0) if not plank else 0.0
	var humps := rng.randi_range(1, 2)
	var yfn := func(vv: float) -> float:
		var t := clampf((vv - v0) / L, 0.0, 1.0)
		return -sag * sin(PI * t) if plank else hill * pow(sin(PI * float(humps) * t), 2.0)
	var vv := v0 - 1.4
	var idx := 0
	while vv < v0 + L + 1.4:
		var step := 1.0
		var a := pos_at(vv, 0.0)
		var b := pos_at(vv + step, 0.0)
		a.y = yfn.call(vv)
		b.y = yfn.call(vv + step)
		var dir := b - a
		dir.y = 0.0
		var length := dir.length()
		dir /= length
		var side := Vector3(-dir.z, 0, dir.x)
		var yaw := atan2(-dir.x, -dir.z)
		var pitch := atan2(b.y - a.y, length)
		var pool_name := "deck_plank" if plank else ("deck_track_a" if idx % 2 == 0 else "deck_track_b")
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		var s := _stripe_of(vv + step * 0.5)
		var surf := {"kind": "deck", "style": style, "origin": a, "fwd": dir, "side": side, "len": length, "half_w": half,
			"y0": a.y, "y1": b.y, "pad": 0.22, "height": 0.0, "launch": 0.0, "s": s, "pool": pool_name, "slot": -1,
			"x_pool": "", "x_slot": -1, "basis": basis, "roll": "wood" if plank else "road"}
		surf["slot"] = pools[pool_name].alloc()
		if surf["slot"] >= 0:
			pools[pool_name].put(surf["slot"], Transform3D(basis * Basis.from_scale(Vector3(1, 1, length + 0.12)), a - dir * 0.06))
		# stilts / track stands every few pieces (not on the island overlap)
		if idx % (5 if plank else 6) == 2 and vv > v0 + 1.0 and vv < v0 + L - 2.0:
			var xp := "deck_stilt" if plank else "deck_stand"
			var xs: int = pools[xp].alloc()
			if xs >= 0:
				surf["x_pool"] = xp
				surf["x_slot"] = xs
				pools[xp].put(xs, Transform3D(Basis(Vector3.UP, yaw), a))
		surfaces.append(surf)
		_surf_add(surf)
		_stripe_add(s, surf)
		vv += step
		idx += 1
	# coins down the middle, a fuel can halfway on the long ones
	var cv := v0 + 4.0
	while cv < v0 + L - 3.0:
		var cp := pos_at(cv, 0.0)
		cp.y = yfn.call(cv) + 0.5
		_add_coin(cp, _stripe_of(cv))
		cv += 2.6
	if L > 44.0:
		var fp := pos_at(v0 + L * 0.5 + 1.3, 0.0)
		fp.y = yfn.call(v0 + L * 0.5 + 1.3)
		_add_fuel(fp, _stripe_of(v0 + L * 0.5 + 1.3))
	plan_v = v0 + L

func _plan_gauntlet(v0: float, d: float) -> void:
	last_gauntlet_v = v0
	if force_kind == "gauntlet":
		forced_v = v0
	_add_land(v0, rng.randf_range(18.0, 24.0), d, "plain", true)
	var lip_v := plan_v
	_add_ramp(lip_v - 0.15, 0.0, 7.2, true)
	var rl := rng.randf_range(18.0, 26.0) + d * 8.0
	_add_rail(lip_v, rl, d)
	_add_deck(plan_v, "plank", d, 10.0)
	last_deck_v = plan_v
	_add_land(plan_v, rng.randf_range(26.0, 34.0), d, "dirt")
	var len := rng.randf_range(44.0, 60.0)
	_add_land(plan_v, len, d, "rough")
	gauntlets.append({"va": v0, "vb": plan_v, "done": false, "warned": false})

## Height of the uneven ground in an offroad ("dirt") or canyon ("rough") section at p. Big swells,
## mid-size lumps and a little grit; in a canyon the sides climb into rock walls. Fades to flat at both ends.
func terra_h(p: Vector3, seg: Dictionary) -> float:
	var v := v_of(p)
	return _terra_h(p, seg, v, u_of(p) - center(v))

func _terra_h(p: Vector3, seg: Dictionary, v: float, du: float) -> float:
	var canyon: bool = seg.get("kind", "") == "rough"
	var fade := smoothstep(float(seg["v0"]), float(seg["v0"]) + 7.0, v) * (1.0 - smoothstep(float(seg["v1"]) - 7.0, float(seg["v1"]), v))
	var big := noise.get_noise_2d(p.x * 0.55, p.z * 0.55)
	var mid := noise.get_noise_2d(p.x * 1.5 + 40.0, p.z * 1.5 - 17.0)
	var fine := noise.get_noise_2d(p.x * 4.0 + 9.0, p.z * 4.0 + 3.0)
	var h: float
	if canyon:
		h = 0.45 + big * 0.85 + mid * 0.34 + fine * 0.035
		var wd := absf(du) - (float(seg["w"]) - 3.2)
		if wd > 0.0:
			var k := clampf(wd / 3.6, 0.0, 1.0)
			h += pow(sin(k * PI), 0.75) * (2.1 + 0.8 * mid) + (0.25 if k >= 1.0 else 0.0)
	else:
		h = 0.35 + big * 0.62 + mid * 0.34 + fine * 0.04
		h += smoothstep(1.5, 4.5, absf(du)) * 0.35 * (mid + 1.0)   # rougher off the worn track
	return h * fade

func _build_terra(s: int, list: Array) -> void:
	var b := MB.new()
	var n := 4
	var step := T / n
	var bands := [MB.rgb("c47c58"), MB.rgb("cf8b64"), MB.rgb("d99a71"), MB.rgb("e2a97f"), MB.rgb("e9b98f"), MB.rgb("efc8a3")]
	var sand := MB.rgb("e8b487")
	for tile in list:
		var seg: Dictionary = tile["terra"]
		var canyon: bool = seg.get("kind", "") == "rough"
		var pos: Vector3 = tile["pos"]
		var biome: String = seg["biome"]
		var grass := MB.pal(BIOME_TOP[biome])
		var grass_hi := MB.pal(P.GRASS_FOREST if biome != "seaside" else P.SAND)
		var soil := MB.pal(P.SOIL if biome != "seaside" else P.SAND_SIDE)
		var track := MB.pal(P.DIRT if biome != "seaside" else P.SAND_SIDE)
		var side_col := MB.rgb("b8734f") if canyon else MB.pal(BIOME_SIDE[biome])
		var tv := v_of(pos)
		var tdu := u_of(pos) - center(tv)
		var hs := []
		for a in n + 1:
			var row := []
			for c in n + 1:
				var ox := -T * 0.5 + a * step
				var oz := -T * 0.5 + c * step
				var q := pos + Vector3(ox, 0, oz)
				# (v and u shift linearly across a tile: no need to redo the centreline per vertex)
				row.append(_terra_h(q, seg, tv + ox * F.x + oz * F.z, tdu + ox * S.x + oz * S.z))
			hs.append(row)
		var rim := absf(tdu) > float(seg["w"]) - 1.6 or tv < float(seg["v0"]) + 2.5 or tv > float(seg["v1"]) - 2.5
		var nrm := func(a: int, c: int) -> Vector3:
			var hx: float = float(hs[mini(a + 1, n)][c]) - float(hs[maxi(a - 1, 0)][c])
			var hz: float = float(hs[a][mini(c + 1, n)]) - float(hs[a][maxi(c - 1, 0)])
			var dx := step * float(mini(a + 1, n) - maxi(a - 1, 0))
			var dz := step * float(mini(c + 1, n) - maxi(c - 1, 0))
			return Vector3(-hx / dx, 1.0, -hz / dz).normalized()
		for a in n:
			for c in n:
				var p00 := pos + Vector3(-T * 0.5 + a * step, hs[a][c], -T * 0.5 + c * step)
				var p10 := pos + Vector3(-T * 0.5 + (a + 1) * step, hs[a + 1][c], -T * 0.5 + c * step)
				var p01 := pos + Vector3(-T * 0.5 + a * step, hs[a][c + 1], -T * 0.5 + (c + 1) * step)
				var p11 := pos + Vector3(-T * 0.5 + (a + 1) * step, hs[a + 1][c + 1], -T * 0.5 + (c + 1) * step)
				var n00: Vector3 = nrm.call(a, c)
				var n10: Vector3 = nrm.call(a + 1, c)
				var n01: Vector3 = nrm.call(a, c + 1)
				var n11: Vector3 = nrm.call(a + 1, c + 1)
				var hm := (p00.y + p10.y + p01.y + p11.y) * 0.25
				var flat := (n00.y + n10.y + n01.y + n11.y) * 0.25
				var col: Color
				if canyon:
					col = sand if (flat > 0.94 and hm < 0.55) else bands[clampi(int((hm + 0.25) / 0.34), 0, 5)]
				else:
					# a worn dirt track down the middle; bare soil on the steep bits and in the hollows,
					# darker grass on the crests, so the lumps read
					var qdu := tdu + ((a + 0.5) * step - T * 0.5) * S.x + ((c + 0.5) * step - T * 0.5) * S.z
					if absf(qdu) < 1.25 + 0.3 * sin(hm * 7.0):
						col = track
					elif flat < 0.93 or hm < 0.12:
						col = soil
					elif hm > 0.75:
						col = grass_hi
					else:
						col = grass
				b.tri(p00, p10, p11, n00, n10, n11, col)
				b.tri(p00, p11, p01, n00, n11, n01, col)
		# skirts at the rim and the ends (inside, the neighbours' ground covers the seams)
		for e in (4 if rim else 0):
			for k in n:
				var a0: Vector2i
				var a1: Vector2i
				match e:
					0: a0 = Vector2i(k, 0); a1 = Vector2i(k + 1, 0)
					1: a0 = Vector2i(k + 1, n); a1 = Vector2i(k, n)
					2: a0 = Vector2i(0, k + 1); a1 = Vector2i(0, k)
					_: a0 = Vector2i(n, k); a1 = Vector2i(n, k + 1)
				var t0 := pos + Vector3(-T * 0.5 + a0.x * step, hs[a0.x][a0.y], -T * 0.5 + a0.y * step)
				var t1 := pos + Vector3(-T * 0.5 + a1.x * step, hs[a1.x][a1.y], -T * 0.5 + a1.y * step)
				var bot0 := Vector3(t0.x, -0.9, t0.z)
				var bot1 := Vector3(t1.x, -0.9, t1.z)
				var out := Vector3([0.0, 0.0, -1.0, 1.0][e], 0, [-1.0, 1.0, 0.0, 0.0][e])
				b.quad(t0, t1, bot1, bot0, out, side_col)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = mat
	add_child(mi)
	terra_meshes[s] = mi

## Is p on uneven ground (offroad terrain or a hump)? The car then tracks vertical speed and articulates.
func uneven_at(p: Vector3) -> bool:
	var t = tiles.get(_key(p))
	if t != null and t.has("terra") and t["state"] < 2:
		return true
	return bump_at(p) > 0.004

## A grind rail over a drop: a steel pipe on posts that the car locks onto off the kicker before it.
func _add_rail(v0: float, L: float, d: float) -> void:
	var k := 1 if rng.randf() < 0.6 else 2
	var wv := PI * float(k) / L
	var amp := minf(rng.randf_range(1.2, 2.4), 0.6 / wv) * (1.0 if rng.randf() < 0.5 else -1.0)
	bends.append({"va": v0, "vb": v0 + L, "amp": amp, "k": k})
	segments.append({"v0": v0, "v1": v0 + L, "type": "gap", "biome": cur_biome, "w": 0.0, "holes": [], "density": 0.0,
		"narrow_end": false, "kind": "rail"})
	var y := 1.7
	var rail := {"va": v0 + 1.8, "vb": v0 + L - 0.6, "pts": [], "acc": [], "len": 0.0, "pieces": [], "y": y, "falling": false}
	var vv: float = rail["va"]
	var acc := 0.0
	var prev := Vector3.ZERO
	var idx := 0
	while vv <= float(rail["vb"]) + 0.001:
		var tt := (vv - float(rail["va"])) / maxf(float(rail["vb"]) - float(rail["va"]), 1.0)
		var pnt := pos_at(vv, 0.0) + Vector3(0, y - 0.75 * smoothstep(0.55, 1.0, tt), 0)
		if idx > 0:
			acc += Vector2(pnt.x - prev.x, pnt.z - prev.z).length()
			var dir := pnt - prev
			var slot: int = pools["rail_piece"].alloc()
			var piece := {"kind": "rail_piece", "slot": slot, "pool": "rail_piece", "a": prev, "dir": dir, "s": _stripe_of(vv), "rail": rail,
				"x_slot": -1}
			if slot >= 0:
				var yaw := atan2(-dir.x, -dir.z)
				pools["rail_piece"].put(slot, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1, 1, dir.length() + 0.04)), prev))
			if idx % 3 == 0:
				var ps: int = pools["rail_post"].alloc()
				if ps >= 0:
					piece["x_slot"] = ps
					pools["rail_post"].put(ps, Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), prev))
			rail["pieces"].append(piece)
			_stripe_add(piece["s"], piece)
		rail["pts"].append(pnt)
		rail["acc"].append(acc)
		prev = pnt
		vv += 1.0
		idx += 1
	rail["len"] = acc
	rails.append(rail)
	# coins strung along the rail
	var cv := v0 + 4.0
	while cv < v0 + L - 2.0:
		_add_coin(pos_at(cv, 0.0) + Vector3(0, y + 0.55, 0), _stripe_of(cv))
		cv += 2.2
	plan_v = v0 + L

## The rail point at distance s along it: {p, dir}.
func rail_at(rail: Dictionary, s: float) -> Dictionary:
	var pts: Array = rail["pts"]
	var acc: Array = rail["acc"]
	if pts.size() < 2:
		return {"p": pts[0] if pts.size() > 0 else Vector3.ZERO, "dir": F}
	s = clampf(s, 0.0, float(rail["len"]))
	var i := 1
	while i < pts.size() - 1 and float(acc[i]) < s:
		i += 1
	var a: Vector3 = pts[i - 1]
	var b: Vector3 = pts[i]
	var seg := maxf(float(acc[i]) - float(acc[i - 1]), 0.001)
	var t := clampf((s - float(acc[i - 1])) / seg, 0.0, 1.0)
	var dir := b - a
	dir.y = 0.0
	return {"p": a.lerp(b, t), "dir": dir.normalized()}

## A rail the car (in the air at p) can lock onto: {rail, s} or {}.
func rail_catch(p: Vector3, reach: float) -> Dictionary:
	for rail in rails:
		if rail["falling"]:
			continue
		var pv := v_of(p)
		if pv < float(rail["va"]) - 1.5 or pv > float(rail["vb"]) - 1.0:
			continue
		var pts: Array = rail["pts"]
		var best := -1
		var bd := reach * reach
		for i in pts.size():
			var q: Vector3 = pts[i]
			var dd := Vector2(q.x - p.x, q.z - p.z).length_squared()
			if dd < bd:
				bd = dd
				best = i
		if best >= 0:
			var y: float = rail["y"]
			if p.y > y - 0.6 and p.y < y + 1.4:
				return {"rail": rail, "s": float(rail["acc"][best])}
	return {}

## Spatial index for surfaces (ramps, bridges, deck pieces): which 4 m cells each one touches.
func _surf_add(s: Dictionary) -> void:
	var o: Vector3 = s["origin"]
	var f: Vector3 = s["fwd"]
	var sd: Vector3 = s["side"]
	var pad := 0.35
	var hw: float = s["half_w"] + pad
	var a: Vector3 = o - f * pad
	var b: Vector3 = o + f * (float(s["len"]) + pad)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in [a + sd * hw, a - sd * hw, b + sd * hw, b - sd * hw]:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.z))
		hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.z))
	var cells := []
	for cx in range(int(floor(lo.x / SURF_CELL)), int(floor(hi.x / SURF_CELL)) + 1):
		for cz in range(int(floor(lo.y / SURF_CELL)), int(floor(hi.y / SURF_CELL)) + 1):
			var key := Vector2i(cx, cz)
			if not surf_cells.has(key):
				surf_cells[key] = []
			surf_cells[key].append(s)
			cells.append(key)
	s["cells"] = cells

func _surf_remove(s: Dictionary) -> void:
	for key in s.get("cells", []):
		if surf_cells.has(key):
			surf_cells[key].erase(s)
			if surf_cells[key].is_empty():
				surf_cells.erase(key)
	surfaces.erase(s)

func _surfs_at(p: Vector3) -> Array:
	return surf_cells.get(Vector2i(int(floor(p.x / SURF_CELL)), int(floor(p.z / SURF_CELL))), NO_SURFS)

## The deck piece under p (or {}).
func deck_at(p: Vector3) -> Dictionary:
	for s in _surfs_at(p):
		if s["kind"] != "deck" or s.get("falling", false):
			continue
		var rel: Vector3 = p - s["origin"]
		var f: float = rel.x * s["fwd"].x + rel.z * s["fwd"].z
		if f < -0.22 or f > s["len"] + 0.22:
			continue
		var sd: float = rel.x * s["side"].x + rel.z * s["side"].z
		if absf(sd) <= s["half_w"]:
			return s
	return {}

## The deck challenge spanning progress v (or {}).
func deck_span(v: float) -> Dictionary:
	for dk in decks:
		if v >= dk["va"] and v <= dk["vb"]:
			return dk
	return {}

func _add_station(v: float) -> void:
	var t := tangent(v)
	var p := pos_at(v, 0.0)
	var yaw := atan2(-t.x, -t.z)
	var slot: int = pools["station"].alloc()
	pools["station"].put(slot, Transform3D(Basis(Vector3.UP, yaw), p))
	var side := Vector3(-t.z, 0, t.x)   # local +X in world
	# local +X of the model = Basis(UP, yaw) * X
	var bx := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var bz := Basis(Vector3.UP, yaw) * Vector3.BACK
	var st := {"kind": "station", "pos": p, "fwd": t, "x": bx, "z": bz, "used": false, "slot": slot, "s": _stripe_of(v)}
	stations.append(st)
	_stripe_add(st["s"], st)
	# solid bits: shop, pump island, sign
	for c in [[Vector3(3.6, 0, 0.3), 1.35], [Vector3(2.3, 0, -1.0), 0.55], [Vector3(-2.7, 0, 1.6), 0.18]]:
		var lp: Vector3 = c[0]
		var wp: Vector3 = p + bx * lp.x + bz * lp.z
		var prop := {"name": "", "pool": "", "slot": -1, "pos": wp, "yaw": 0.0, "scale": 1.0, "r": c[1], "kind": "solid", "state": 0, "s": st["s"], "tile": _key(wp)}
		_hash_add(prop)
		_stripe_add(st["s"], prop)

## A police chase: a cruiser waits beside the road, then the stretch ahead has boost pads.
func _plan_chase(seg: Dictionary) -> void:
	var vs: float = seg["v0"] + 10.0
	var length := rng.randf_range(360.0, 480.0)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var pv := vs - 8.0
	var t := tangent(pv)
	var p := pos_at(pv, side * minf(2.6, float(seg["w"]) - 1.2))
	chases.append({"v_start": vs, "v_end": vs + length, "parked": p, "yaw": atan2(-t.x, -t.z), "done": false})
	var v := vs + 16.0
	while v < vs + length - 10.0:
		_add_pad(v, rng.randf_range(-1.6, 1.6))
		v += rng.randf_range(30.0, 40.0)
	next_chase_v = vs + length + rng.randf_range(380.0, 620.0)

func _add_pad(v: float, off: float) -> void:
	var slot: int = pools["pad"].alloc()
	if slot < 0:
		return
	var t := tangent(v)
	var p := pos_at(v, off)
	var pad := {"kind": "pad", "pos": p, "fwd": t, "side": Vector3(-t.z, 0, t.x), "slot": slot, "s": _stripe_of(v), "used": false, "checked": false}
	pools["pad"].put(slot, Transform3D(Basis(Vector3.UP, atan2(-t.x, -t.z)), p))
	pads.append(pad)
	_stripe_add(pad["s"], pad)

func _plan_items(seg: Dictionary) -> void:
	var v0: float = seg["v0"]
	var v1: float = seg["v1"]
	_maybe_place(seg)
	if v0 >= next_chase_v and seg.get("kind", "") in ["plain", "holes", "stunt"] and not seg["narrow_end"]:
		_plan_chase(seg)
	elif v0 > 120.0 and rng.randf() < 0.18:
		_add_pad(rng.randf_range(v0 + 6.0, v1 - 6.0), rng.randf_range(-1.5, 1.5))
	# coins: lines and wiggles along the racing line
	while next_coin_v < v1 - 4.0:
		if next_coin_v > v0 + 2.0:
			var n := rng.randi_range(5, 9)
			var off := rng.randf_range(-seg["w"] * 0.55, seg["w"] * 0.55)
			var wig := rng.randf() < 0.5
			var ph := rng.randf() * TAU
			for k in n:
				var cv := next_coin_v + k * 1.25
				var o := off + (sin(ph + k * 0.7) * 1.4 if wig else 0.0)
				_add_coin(pos_at(cv, o) + Vector3(0, 0.5, 0), _stripe_of(cv), true)
		next_coin_v += rng.randf_range(18.0, 34.0)
	# fuel cans
	while next_fuel_v < v1 - 3.0:
		if next_fuel_v > v0 + 3.0:
			var off := rng.randf_range(-seg["w"] + 1.2, seg["w"] - 1.2)
			_add_fuel(pos_at(next_fuel_v, off), _stripe_of(next_fuel_v))
		next_fuel_v += rng.randf_range(44.0, 64.0) + difficulty * 40.0
	# distance markers
	while float(next_marker) < v1:
		if float(next_marker) >= v0:
			_add_marker(next_marker, seg)
		next_marker += 100
	# lamps along the path (glow at night)
	if seg["biome"] in ["countryside", "seaside", "sky"]:
		var lv := v0 + 6.0
		while lv < v1 - 4.0:
			var side_sign := 1.0 if int(lv / 14.0) % 2 == 0 else -1.0
			var lp := pos_at(lv, side_sign * minf(2.2, seg["w"] - 0.8))
			var prop := _add_item_prop("lamp", lp, 0.0, 1.0, 0.18, "metal", _stripe_of(lv))
			lamps.append(prop)
			lv += 16.0

# ------------------------------------------------------------------ places beside the road

## Rocky ridges along the forest's outer rim (they act like walls).
func _ridge(u: float, v: float, _i: int, _j: int) -> bool:
	var seg := segment_at(v)
	var w := _width_at(v, seg)
	var d := absf(u - center(v))
	return d > w - 0.7 + noise.get_noise_2d(u * 2.0 + 30.0, v * 0.5) * 0.6 and noise.get_noise_2d(u * 0.3 + 90.0, v * 0.22) > 0.05

func _place_at(u: float, v: float) -> Dictionary:
	for pl in places:
		if v < pl["va"] - 0.6 or v > pl["vb"] + 0.6:
			continue
		var d: float = (u - center(v)) * pl["side"]
		if d < pl["d_in"] - 0.6 or d > pl["d_out"] + 0.6:
			continue
		var a: float = v - pl["va"]
		var L: float = pl["vb"] - pl["va"]
		var r := 1.7
		var ca := clampf(a, r, L - r)
		var cd := minf(d, pl["d_out"] - r)
		if Vector2(a - ca, maxf(0.0, d - cd)).length() > r + 0.35:
			continue
		return {"place": pl, "a": a, "d": d}
	return {}

func _place_tile(pl: Dictionary, a: float, d: float) -> Dictionary:
	var L: float = pl["vb"] - pl["va"]
	var din: float = pl["d_in"]
	var dout: float = pl["d_out"]
	match String(pl["type"]):
		"farm":
			if a > 3.4 and a < L - 1.2 and d > din + 1.2 and d < dout - 1.0:
				return {"kind": "ground", "pool": "tile_field", "top": P.SOIL}
		"village":
			if d < din + 3.8:
				return {"kind": "ground", "pool": "tile_cobble", "top": P.COBBLE}
		"pond":
			var e := Vector2((a - L * 0.5) / (L * 0.34), (d - (din + dout) * 0.5 - 0.6) / ((dout - din) * 0.3))
			if e.length() < 1.0:
				return {"kind": "water"}
		"beach":
			if d > dout - 1.5:
				return {"kind": "water"}
			return {"kind": "ground", "top": P.SAND}
		"pier":
			if d > din + 2.4:
				if absf(a - L * 0.5) < 0.95:
					return {"kind": "pier"}
				return {"kind": "water"}
			return {"kind": "ground", "top": P.SAND}
		"cafe":
			if d < din + 3.8:
				return {"kind": "ground", "pool": "tile_plank", "top": P.PLANK}
			return {"kind": "ground", "top": P.SAND}
		"campsite":
			if Vector2(a - L * 0.5, d - (din + dout) * 0.5).length() < 2.7:
				return {"kind": "ground", "top": P.PATH}
		"mountain":
			if d > din + 1.7:
				return {"kind": "rock", "h": 0.8 + (d - din - 1.7) * 0.5 + noise.get_noise_2d(a * 0.9 + pl["va"], d) * 0.35}
		"ruins":
			if noise.get_noise_2d(a * 0.6 + pl["va"] * 0.1, d * 0.6) > -0.05:
				return {"kind": "ground", "pool": "tile_cobble", "top": P.COBBLE}
		"balloons":
			if absf(a - L * 0.5) < 3.2 and d > din + 0.8 and d < dout - 0.6:
				return {"kind": "ground", "pool": "tile_plank", "top": P.PLANK}
	return {"kind": "ground"}

func _maybe_place(seg: Dictionary) -> void:
	var len: float = seg["v1"] - seg["v0"]

	var first: bool = seg["v0"] < 60.0
	if len < 20.0 or seg["type"] != "land" or (rng.randf() > 0.9 and not first):
		return
	var biome: String = seg["biome"]
	var types: Array = PLACE_TYPES[biome]
	var total := 0.0
	for t in types:
		total += float(t[1])
	var x := rng.randf() * total
	var typ: String = types[0][0]
	for t in types:
		x -= float(t[1])
		if x <= 0.0:
			typ = t[0]
			break
	if game and game.args.has("place"):
		typ = String(game.args["place"])
	var sides := [1.0, -1.0]
	if rng.randf() < 0.5:
		sides.reverse()
	var placed := 0
	for side in sides:
		if placed > 0 and rng.randf() > 0.7 and not first:
			break
		var L := minf(rng.randf_range(11.0, 16.0), len - 8.0)
		var room := len - L - 8.0 - (10.0 if seg["narrow_end"] else 0.0)
		if room < 0.0:
			return
		var va: float = seg["v0"] + 4.0 + rng.randf() * room
		var w := float(seg["w"])
		var pl := {"type": typ, "biome": biome, "side": side, "va": va, "vb": va + L,
			"d_in": w - 0.6, "d_out": w - 0.6 + rng.randf_range(4.8, 6.0)}
		places.append(pl)
		_place_props(pl)
		placed += 1
		# the other side gets its own kind of place
		var x2 := rng.randf() * total
		for t in types:
			x2 -= float(t[1])
			if x2 <= 0.0:
				typ = t[0]
				break
		if game and game.args.has("place"):
			typ = String(game.args["place"])

func _ensure_pool(nm: String, cap := 40) -> void:
	if pools.has(nm):
		return
	var mesh: Mesh = M.parked(CARS.by_id(nm.substr(7))) if nm.begins_with("parked_") else M.get_mesh(nm)
	var p: Pool = Pool.new()
	p.setup(mesh, cap, mat, false, true)
	p.name = nm
	add_child(p)
	pools[nm] = p

func _pl_pos(pl: Dictionary, a: float, d: float) -> Vector3:
	return pos_at(pl["va"] + a, pl["side"] * d)

## Yaw that turns a model's front toward the road (or away with face = -1).
func _pl_yaw(pl: Dictionary, face := 1.0) -> float:
	var dir: Vector3 = -S * pl["side"] * face
	return atan2(-dir.x, -dir.z)

func _pl_prop(pl: Dictionary, nm: String, a: float, d: float, yaw: float, sc := 1.0, r := 0.4, kind := "wood", y := 0.0) -> Dictionary:
	var swap = RUIN_SWAP.get(nm, null)
	if swap != null:
		if String(swap[0]) == "":
			return {}
		nm = swap[0]
		r = swap[1]
		kind = swap[2]
		y = minf(y, 0.0)
	_ensure_pool(nm)
	if pools[nm].used() >= 39:
		return {}
	return _add_item_prop(nm, _pl_pos(pl, a, d) + Vector3(0, y, 0), yaw, sc, r, kind, _stripe_of(pl["va"] + a))

func _pl_person(pl: Dictionary, a: float, d: float, pose := "stand", yaw := INF, y := 0.0) -> void:
	var p := _pl_pos(pl, a, d) + Vector3(0, y, 0)
	var pr := people.spawn(rng.randi_range(0, 99), pose, p, _pl_yaw(pl) if yaw == INF else yaw, _stripe_of(pl["va"] + a))
	if not pr.is_empty():
		_stripe_add(pr["s"], {"kind": "person", "p": pr})

func _pl_anim(kind: String, prop: Dictionary, extra := {}) -> void:
	if prop.is_empty():
		return
	var an := {"kind": kind, "prop": prop, "base": prop["pos"], "ph": rng.randf() * TAU, "t": 0.0}
	an.merge(extra)
	anims.append(an)

func _place_props(pl: Dictionary) -> void:
	var L: float = pl["vb"] - pl["va"]
	var din: float = pl["d_in"]
	var dout: float = pl["d_out"]
	var mid := (din + dout) * 0.5
	var face := _pl_yaw(pl)
	var along := atan2(-F.x, -F.z)
	match String(pl["type"]):
		"farm":
			_pl_prop(pl, "barn", 1.7, dout - 1.7, face, 1.0, 1.5, "solid")
			_pl_prop(pl, "silo", 1.4, din + 1.4, 0.0, 0.85, 0.55, "solid")
			_pl_prop(pl, "parked_tractor", 3.4 if L > 13.0 else L - 1.6, din + 0.7, along + 0.3, 1.0, 0.6, "solid")
			_pl_prop(pl, "scarecrow", L * 0.62, mid, face, 1.0, 0.25, "wood")
			var fa := 4.0
			while fa < L - 1.0:
				_pl_prop(pl, "fence", fa, din + 0.55, along + PI * 0.5, 1.0, 0.45, "wood")
				fa += 1.6
			_pl_prop(pl, "hay", L - 0.8, dout - 0.8, rng.randf() * TAU, 1.0, 0.42, "soft")
			_pl_person(pl, L * 0.45, din + 1.0)
		"village":
			var n := 2 if L < 13.0 else 3
			var houses := ["cottage_a", "cottage_b", "cottage_c"]
			for k in n:
				var ha := 2.2 + k * (L - 4.4) / maxf(1.0, n - 1)
				var h := _pl_prop(pl, houses[(k + rng.randi_range(0, 2)) % 3], ha, dout - 1.5, face, 1.0, 0.95, "solid")
				if not h.is_empty():
					var hb := Basis(Vector3.UP, face)
					_pl_anim("smoke", h, {"at": h["pos"] + hb * Vector3(0.4, 1.85, -0.25)})
				_pl_prop(pl, "flower_bed", ha + 1.0, dout - 3.0, face, 0.8, 0.3, "soft")
			_pl_prop(pl, "well", L * 0.5, din + 2.3, 0.0, 1.0, 0.45, "solid")
			_pl_prop(pl, "bench", L * 0.5 + 1.8, din + 2.4, face, 1.0, 0.45, "wood")
			_pl_person(pl, L * 0.5 + 1.8, din + 2.45, "sit", face)
			_pl_prop(pl, "lamp", 1.0, din + 0.6, 0.0, 1.0, 0.18, "metal")
			_pl_prop(pl, "lamp", L - 1.0, din + 0.6, 0.0, 1.0, 0.18, "metal")
			_pl_prop(pl, "mailbox", 2.6, din + 3.6, face, 1.0, 0.2, "metal")
			var parked: Dictionary = CARS.LIST[rng.randi_range(1, CARS.LIST.size() - 1)]
			if not (parked["id"] in ["bus", "firetruck", "dump", "monster"]):
				_pl_prop(pl, "parked_" + String(parked["id"]), L - 2.6, din + 1.4, along, 1.0, 0.6, "solid")
			_pl_person(pl, L * 0.5 - 1.4, din + 1.6)
			_pl_person(pl, L * 0.5 + 0.6, din + 1.2)
		"pond":
			var pc := Vector2(L * 0.5, mid + 0.6)
			for k in 3:
				var ang := rng.randf() * TAU
				_pl_prop(pl, "lily", pc.x + cos(ang) * L * 0.18, pc.y + sin(ang) * 1.0, rng.randf() * TAU, 1.0, 0.0, "flat", -0.28)
			for k in rng.randi_range(2, 3):
				var dk := _pl_prop(pl, "duck", pc.x, pc.y, 0.0, 1.0, 0.0, "flat", -0.3)
				_pl_anim("duck", dk, {"c": _pl_pos(pl, pc.x, pc.y) + Vector3(0, -0.3, 0), "r": rng.randf_range(0.6, 1.4), "sp": rng.randf_range(0.25, 0.5) * (1.0 if k % 2 == 0 else -1.0)})
			for k in 5:
				var ang2 := TAU * k / 5.0 + 0.3
				_pl_prop(pl, "reeds", pc.x + cos(ang2) * L * 0.38, pc.y + sin(ang2) * (dout - din) * 0.36, rng.randf() * TAU, 1.0, 0.0, "flat")
			_pl_prop(pl, "bench", 1.6, din + 1.2, face, 1.0, 0.45, "wood")
			_pl_person(pl, 1.6, din + 1.25, "sit", face + PI)
			_pl_prop(pl, "tree_round", L - 1.2, dout - 0.8, 0.0, 1.0, 0.45, "wood")
			_pl_prop(pl, "flowers", 1.2, dout - 1.0, 0.0, 1.0, 0.0, "flat")
		"orchard":
			var rows := 2 if dout - din < 6.4 else 3
			var ta := 1.6
			while ta < L - 1.0:
				for m in rows:
					_pl_prop(pl, "apple_tree", ta, din + 1.5 + m * 2.1, rng.randf() * TAU, 0.9 + rng.randf() * 0.2, 0.42, "wood")
				ta += 2.6
			_pl_prop(pl, "apple_crate", 2.8, din + 0.7, rng.randf() * TAU, 1.0, 0.3, "wood")
			_pl_prop(pl, "apple_crate", 3.4, din + 0.9, rng.randf() * TAU, 1.0, 0.3, "wood")
			_pl_person(pl, 2.9, din + 2.6)
		"beach":
			var cols := [Color("ff7a6b"), Color("6ec6ff"), Color("ffd166"), Color("8fd19e"), Color("a998f2")]
			for k in 3:
				var ta2 := 2.0 + k * (L - 4.0) / 2.0
				var tw := _pl_prop(pl, "towel", ta2, din + 2.6, face + PI * 0.5 + rng.randf_range(-0.3, 0.3), 1.0, 0.0, "flat")
				if not tw.is_empty():
					if tw["pool"] == "towel": pools["towel"].tint(tw["slot"], cols[rng.randi_range(0, cols.size() - 1)])
					if k != 1:
						_pl_person(pl, ta2, din + 2.6, "lie", tw["yaw"])
				_pl_prop(pl, "umbrella", ta2 + 0.9, din + 3.4, rng.randf() * TAU, 1.0, 0.3, "soft")
			_pl_prop(pl, "lifeguard", L * 0.5, dout - 2.6, face, 1.0, 0.75, "solid")
			_pl_person(pl, L * 0.5, dout - 2.6, "stand", face, 1.6)
			var sb := _pl_prop(pl, "surfboard", 1.2, dout - 2.0, face + 0.3, 1.0, 0.25, "wood")
			if not sb.is_empty():
				if sb["pool"] == "surfboard": pools["surfboard"].tint(sb["slot"], cols[rng.randi_range(0, cols.size() - 1)])
			_pl_prop(pl, "beach_ball", L - 1.8, din + 1.6, 0.0, 1.0, 0.2, "soft")
			_pl_prop(pl, "sandcastle", L - 1.4, dout - 2.4, rng.randf() * TAU, 0.8, 0.4, "sand")
			_pl_person(pl, L - 2.6, dout - 1.9)
		"pier":
			var pa := L * 0.5
			_pl_prop(pl, "crate", pa - 0.4, din + 2.8, rng.randf() * TAU, 0.8, 0.3, "wood")
			_pl_person(pl, pa, dout - 0.4, "sit", face + PI)
			for k in 2:
				var ba := pa + (2.2 if k == 0 else -2.4)
				var bt := _pl_prop(pl, "boat", ba, din + 3.6 + k * 1.6, along + rng.randf_range(-0.4, 0.4), 0.9, 0.0, "flat", -0.32)
				_pl_anim("bob", bt, {"amp": 0.05})
			var by := _pl_prop(pl, "buoy", L - 1.2, dout - 1.0, 0.0, 1.0, 0.0, "flat", -0.35)
			_pl_anim("bob", by, {"amp": 0.07})
			_pl_prop(pl, "dune_grass", 1.2, din + 1.0, 0.0, 1.0, 0.0, "flat")
			_pl_person(pl, pa - 1.6, din + 1.6)
		"cafe":
			_pl_prop(pl, "kiosk", L * 0.5, din + 3.2, face, 1.0, 0.7, "solid")
			_pl_person(pl, L * 0.5 - 0.3, din + 2.1, "stand", face + PI)
			_pl_person(pl, L * 0.5 + 0.4, din + 1.5, "stand", face + PI)
			for k in 2:
				var ca2 := 2.0 if k == 0 else L - 2.0
				_pl_prop(pl, "cafe_table", ca2, din + 2.0, 0.0, 1.0, 0.3, "metal")
				_pl_person(pl, ca2 + 0.55, din + 2.0, "sit", face + PI * 0.5)
			_pl_prop(pl, "deck_chair", L * 0.5 + 2.6, dout - 1.4, face, 1.0, 0.3, "wood")
			_pl_prop(pl, "umbrella", L * 0.5 - 2.6, dout - 1.4, 0.0, 1.0, 0.3, "soft")
		"campsite":
			var cc := Vector2(L * 0.5, mid)
			var fire := _pl_prop(pl, "campfire", cc.x, cc.y, 0.0, 1.0, 0.35, "rock")
			var fl := _pl_prop(pl, "flame", cc.x, cc.y, 0.0, 1.0, 0.0, "flat", 0.05)
			_pl_anim("flame", fl)
			_pl_anim("smoke", fire, {"at": _pl_pos(pl, cc.x, cc.y) + Vector3(0, 0.6, 0), "grey": true})
			var tents := [Color("ff8a5c"), Color("3db5a6"), Color("6ec6ff")]
			for k in 2:
				var tang := PI * 0.35 + k * PI * 0.75
				var tp := cc + Vector2(cos(tang), sin(tang)) * 2.3
				var tt := _pl_prop(pl, "tent", tp.x, tp.y, rng.randf() * TAU, 1.0, 0.75, "solid")
				if not tt.is_empty():
					if tt["pool"] == "tent": pools["tent"].tint(tt["slot"], tents[(k + rng.randi_range(0, 2)) % 3])
			for k in 2:
				var lang := PI * 1.2 + k * PI * 0.6
				var lp := cc + Vector2(cos(lang), sin(lang)) * 1.2
				_pl_prop(pl, "log", lp.x, lp.y, lang, 0.8, 0.0, "flat")
				var lyaw: float = atan2(-(_pl_pos(pl, cc.x, cc.y) - _pl_pos(pl, lp.x, lp.y)).x, -(_pl_pos(pl, cc.x, cc.y) - _pl_pos(pl, lp.x, lp.y)).z)
				_pl_person(pl, lp.x, lp.y, "sit", lyaw, 0.12)
			var cn := _pl_prop(pl, "canoe", 1.4, dout - 1.0, along, 1.0, 0.45, "wood")
			if not cn.is_empty():
				pools["canoe"].tint(cn["slot"], Color("ef5b4c"))
			_pl_prop(pl, "lamp", cc.x + 2.6, cc.y - 1.6, 0.0, 1.0, 0.18, "metal")
			_pl_prop(pl, "pine", L - 0.8, dout - 0.6, 0.0, 1.0, 0.42, "wood")
			_pl_prop(pl, "pine_tall", 0.8, dout - 0.8, 0.0, 1.0, 0.45, "wood")
		"mountain":
			_pl_prop(pl, "peak", L * 0.5, dout - 1.0, rng.randf() * TAU, 1.0, 1.3, "solid", 2.0)
			for k in 4:
				var ka := 1.2 + k * (L - 2.4) / 3.0
				var kd := din + 2.4 + (k % 2) * 1.2
				var kh := 0.8 + (kd - din - 1.7) * 0.5
				_pl_prop(pl, "pine" if k % 2 == 0 else "pine_tall", ka, kd, 0.0, 0.9, 0.0, "flat", kh)
			_pl_person(pl, L * 0.3, din + 0.9, "stand")
			_pl_prop(pl, "rock", L * 0.7, din + 0.9, 0.0, 1.0, 0.36, "rock")
			var fall := CPUParticles3D.new()
			fall.amount = 70
			fall.lifetime = 2.2
			fall.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			fall.emission_box_extents = Vector3(0.6, 0.1, 0.6)
			fall.direction = Vector3(0, -1, 0)
			fall.spread = 6.0
			fall.gravity = Vector3(0, -9.0, 0)
			fall.initial_velocity_min = 1.0
			fall.initial_velocity_max = 2.0
			fall.scale_amount_min = 0.6
			fall.scale_amount_max = 1.4
			var dm := SphereMesh.new()
			dm.radius = 0.12
			dm.height = 0.24
			dm.radial_segments = 6
			dm.rings = 3
			var wm := StandardMaterial3D.new()
			wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			wm.albedo_color = Color(0.85, 0.94, 1.0)
			dm.material = wm
			fall.mesh = dm
			fall.local_coords = false
			fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fall.position = _pl_pos(pl, L * 0.25, dout + 0.4) + Vector3(0, 2.2, 0)
			add_child(fall)
			var holder := {"kind": "fall", "node": fall, "pos": fall.position, "s": _stripe_of(pl["va"] + L * 0.25)}
			anims.append({"kind": "fall", "node": fall, "prop": holder, "base": fall.position, "ph": 0.0, "t": 0.0})
			_stripe_add(holder["s"], holder)
		"cabin":
			var cb := _pl_prop(pl, "cabin", L * 0.5, dout - 1.6, face, 1.0, 1.3, "solid")
			if not cb.is_empty():
				_pl_anim("smoke", cb, {"at": cb["pos"] + Basis(Vector3.UP, face) * Vector3(0.55, 2.25, -0.3)})
			_pl_prop(pl, "woodpile", L * 0.5 + 2.2, dout - 1.4, face, 1.0, 0.45, "wood")
			_pl_prop(pl, "stump", L * 0.5 - 2.0, din + 2.0, 0.0, 1.0, 0.3, "wood")
			_pl_prop(pl, "mailbox", L * 0.5 - 1.2, din + 0.8, face, 1.0, 0.2, "metal")
			_pl_person(pl, L * 0.5 - 1.4, din + 2.2)
			_pl_prop(pl, "lookout", 1.4, dout - 1.2, face, 0.9, 0.7, "solid")
			_pl_prop(pl, "fern", L - 1.0, din + 1.2, 0.0, 1.0, 0.0, "flat")
		"ruins":
			_pl_prop(pl, "ruin_arch", L * 0.5, mid, face + PI * 0.5, 1.0, 0.0, "flat")
			for sgn in [-1.0, 1.0]:
				var col := {"name": "", "pool": "", "slot": -1, "pos": _pl_pos(pl, L * 0.5 + sgn * 0.9, mid), "yaw": 0.0, "scale": 1.0, "r": 0.3, "kind": "solid", "state": 0, "s": _stripe_of(pl["va"] + L * 0.5), "tile": Vector2i.ZERO}
				_hash_add(col)
				_stripe_add(col["s"], col)
			_pl_prop(pl, "column_broken", 1.8, din + 1.4, rng.randf() * TAU, 1.0, 0.3, "rock")
			_pl_prop(pl, "column_broken", L - 1.8, dout - 1.4, rng.randf() * TAU, 1.0, 0.3, "rock")
			_pl_prop(pl, "crystal", 2.6, dout - 1.2, 0.0, 1.2, 0.3, "crystal")
			_pl_prop(pl, "pillar", L - 1.4, din + 1.2, 0.0, 1.0, 0.32, "rock")
			_pl_person(pl, L * 0.5 + 2.2, din + 1.6)
		"balloons":
			var cols2 := ["balloon", "balloon"]
			for k in 2:
				var ba2 := L * 0.5 + (k * 2 - 1) * 1.8
				var tdp := din + 2.6 + k * 1.2
				_pl_prop(pl, "tether", ba2, tdp, 0.0, 1.0, 0.3, "wood")
				var bl := _pl_prop(pl, cols2[k], ba2, tdp, rng.randf() * TAU, 0.75, 0.0, "flat", 3.6 + k * 0.6)
				var rp := _pl_prop(pl, "rope", ba2, tdp, 0.0, 1.0, 0.0, "flat", 0.55)
				_pl_anim("balloon", bl, {"rope": rp, "anchor": _pl_pos(pl, ba2, tdp) + Vector3(0, 0.55, 0)})
			_pl_person(pl, L * 0.5, din + 1.8)
			_pl_person(pl, L * 0.5 + 0.7, din + 1.3)
			_pl_prop(pl, "crate", L * 0.5 - 2.8, din + 1.4, rng.randf() * TAU, 0.8, 0.3, "wood")
		"garden":
			_pl_prop(pl, "rainbow", L * 0.5, dout - 1.4, face + PI * 0.5, 0.9, 0.0, "flat")
			for k in 3:
				_pl_prop(pl, "tree_puff", 1.6 + k * (L - 3.2) / 2.0, dout - 0.8 - (k % 2) * 1.4, 0.0, 1.0, 0.42, "wood")
			_pl_prop(pl, "flower_bed", L * 0.5, din + 1.6, face, 1.0, 0.3, "soft")
			_pl_prop(pl, "cloud_puff", 1.4, din + 1.2, 0.0, 1.0, 0.45, "cloud")
			_pl_prop(pl, "bench", L * 0.5 + 2.4, din + 2.8, face, 1.0, 0.45, "wood")
			_pl_person(pl, L * 0.5 + 2.4, din + 2.85, "sit", face)

## Ducks paddle, boats bob, balloons float, fires flicker, chimneys smoke.
func _tick_anims(dt: float, time: float, car_pos: Vector3) -> void:
	var dead := []
	for an in anims:
		var pr: Dictionary = an["prop"]
		if pr.get("state", 0) != 0 or pr.get("gone", false):
			dead.append(an)
			continue
		var base: Vector3 = an["base"]
		if base.distance_to(car_pos) > 42.0:
			continue
		var ph: float = an["ph"]
		match String(an["kind"]):
			"duck":
				var ang: float = ph + time * an["sp"]
				var p: Vector3 = an["c"] + Vector3(cos(ang), 0, sin(ang)) * an["r"] + Vector3(0, sin(time * 3.0 + ph) * 0.01, 0)
				var tng := Vector3(-sin(ang), 0, cos(ang)) * signf(an["sp"])
				pools[pr["pool"]].put(pr["slot"], Transform3D(Basis(Vector3.UP, atan2(-tng.x, -tng.z)), p))
				pr["pos"] = p
			"bob":
				var y := sin(time * 1.4 + ph) * float(an.get("amp", 0.05))
				var roll := sin(time * 1.1 + ph) * 0.06
				pools[pr["pool"]].put(pr["slot"], Transform3D(Basis(Vector3.UP, pr["yaw"]) * Basis(Vector3.BACK, roll), base + Vector3(0, y, 0)))
			"balloon":
				var by := base + Vector3(sin(time * 0.5 + ph) * 0.15, sin(time * 0.8 + ph) * 0.25, cos(time * 0.4 + ph) * 0.15)
				pools[pr["pool"]].put(pr["slot"], Transform3D(Basis(Vector3.UP, pr["yaw"] + time * 0.1).scaled(Vector3.ONE * pr["scale"]), by))
				var rp: Dictionary = an.get("rope", {})
				if not rp.is_empty() and rp.get("state", 0) == 0:
					var anchor: Vector3 = an["anchor"]
					var bottom := by + Vector3(0, -1.55 * pr["scale"], 0)
					var v := bottom - anchor
					var y_axis := v.normalized()
					var x_axis := y_axis.cross(Vector3.FORWARD).normalized()
					if x_axis.length() < 0.1:
						x_axis = Vector3.RIGHT
					var z_axis := x_axis.cross(y_axis)
					pools[rp["pool"]].put(rp["slot"], Transform3D(Basis(x_axis, y_axis * v.length(), z_axis), anchor))
			"flame":
				var k := 1.0 + sin(time * 17.0 + ph) * 0.15 + sin(time * 9.0) * 0.1
				pools[pr["pool"]].put(pr["slot"], Transform3D(Basis(Vector3.UP, time * 2.0).scaled(Vector3(1.0 / k, k * 1.1, 1.0 / k)), base))
			"smoke":
				an["t"] -= dt
				if an["t"] <= 0.0 and fx and base.distance_to(car_pos) < 30.0:
					an["t"] = 0.45
					var col := Color(0.82, 0.8, 0.8) if an.get("grey", false) else Color(0.92, 0.92, 0.95)
					fx.puff(an["at"], col, 0.34, Vector3(0.25, 0.0, 0.1), 1.8, 0.75)
	for an in dead:
		if an["kind"] == "fall" and is_instance_valid(an["node"]):
			an["node"].queue_free()
		anims.erase(an)
	var old := []
	for pl in places:
		if pl["vb"] < crumble_v - 5.0:
			old.append(pl)
	for pl in old:
		places.erase(pl)

func _add_coin(p: Vector3, s: int, on_ground := false) -> void:
	var slot: int = pools["coin"].alloc()
	if slot < 0:
		return
	var c := {"pos": p, "slot": slot, "s": s, "taken": false, "t": 0.0, "ground": on_ground, "checked": not on_ground, "vel": Vector3.ZERO, "fall": false}
	coins.append(c)
	_stripe_add(s, c)

func _add_fuel(p: Vector3, s: int) -> void:
	var slot: int = pools["fuel"].alloc()
	if slot < 0:
		return
	var f := {"pos": p, "slot": slot, "s": s, "taken": false, "checked": false, "fall": false, "vel": Vector3.ZERO}
	fuels.append(f)
	_stripe_add(s, f)

func _add_marker(m: int, seg: Dictionary) -> void:
	var v := float(m)
	var p := pos_at(v, minf(seg["w"] - 0.6, 3.4))
	var prop := _add_item_prop("marker", p, atan2(-S.x, -S.z) + PI * 0.5 + 0.0, 1.0, 0.2, "wood", _stripe_of(v))
	var lbl := Label3D.new()
	lbl.text = "%d m" % m
	lbl.font = label_font
	lbl.font_size = 72
	lbl.pixel_size = 0.009
	lbl.modulate = Color("3f8f6b")
	lbl.outline_size = 0
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = p + Vector3(0, 1.45, 0)
	lbl.outline_size = 14
	lbl.outline_modulate = Color("fff3dd")
	lbl.no_depth_test = false
	add_child(lbl)
	markers.append({"label": lbl, "prop": prop, "s": _stripe_of(v)})

func _add_item_prop(nm: String, p: Vector3, yaw: float, sc: float, r: float, kind: String, s: int) -> Dictionary:
	var slot: int = pools[nm].alloc()
	var prop := {"name": nm, "pool": nm, "slot": slot, "pos": p, "yaw": yaw, "scale": sc, "r": r, "kind": kind, "state": 0, "s": s, "tile": _key(p), "item": true}
	pools[nm].put(slot, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), p))
	if r > 0.0 and kind != "flat":
		_hash_add(prop)
	_stripe_add(s, prop)
	return prop

func _stripe_add(s: int, item) -> void:
	if not stripe_items.has(s):
		stripe_items[s] = []
	stripe_items[s].append(item)

func _hash_add(prop: Dictionary) -> void:
	var k := Vector2i(int(floor(prop["pos"].x / 2.0)), int(floor(prop["pos"].z / 2.0)))
	if not props_hash.has(k):
		props_hash[k] = []
	props_hash[k].append(prop)

func _hash_remove(prop: Dictionary) -> void:
	var k := Vector2i(int(floor(prop["pos"].x / 2.0)), int(floor(prop["pos"].z / 2.0)))
	if props_hash.has(k):
		props_hash[k].erase(prop)

# ------------------------------------------------------------------ ground rules

func _width_at(v: float, seg: Dictionary) -> float:
	var w: float = seg["w"]
	var idx := segments.find(seg)
	if idx > 0:
		var prev: Dictionary = segments[idx - 1]
		if prev["type"] != "gap":
			w = lerpf(prev["w"], w, smoothstep(0.0, 7.0, v - seg["v0"]))
	if seg["narrow_end"]:
		w = lerpf(w, 1.55, smoothstep(seg["v1"] - 9.0, seg["v1"] - 1.0, v))
	return w

func _ground_rule(u: float, v: float) -> int:
	# 0 none, 1 ground, 2 pond (water)
	var seg := segment_at(v)
	if seg["type"] == "gap":
		return 0
	var c := center(v)
	var w := _width_at(v, seg)
	if seg["type"] == "start":
		var du := u - c
		var dv := v - 2.0
		if du * du / 42.0 + dv * dv / 150.0 < 1.0:
			return 1
		return 0
	# landing pad after a gap is wider
	var idx := segments.find(seg)
	if idx > 0 and segments[idx - 1]["type"] == "gap":
		w = maxf(w, lerpf(4.5, w, smoothstep(0.0, 6.0, v - seg["v0"])))
	var edge := noise.get_noise_2d(u, v) * 1.1
	if seg["narrow_end"]:
		edge *= 1.0 - smoothstep(seg["v1"] - 10.0, seg["v1"] - 3.0, v)
	if absf(u - c) > w + edge:
		var pl := _place_at(u, v)
		if pl.is_empty():
			return 0
		return 2 if _place_tile(pl["place"], pl["a"], pl["d"])["kind"] == "water" else 1
	for h in seg["holes"]:
		var va: float = h["va"]
		var vb: float = h["vb"]
		var r: float = h["r"]
		if v < va - r or v > vb + r:
			continue
		var dv := clampf(v, va, vb)
		var hu: float = center(dv) + float(h["off"])
		var du := u - hu
		var ddv := v - dv
		if du * du + ddv * ddv < r * r:
			return 2 if seg["biome"] != "sky" else 0
	return 1

# ------------------------------------------------------------------ generation

func update_gen(car_v: float) -> void:
	difficulty = clampf(car_v / 2600.0, 0.0, 1.0)
	_plan_until(car_v + AHEAD + 30.0)
	var target := int(ceil((car_v + AHEAD) / D))
	while gen_s <= target:
		_gen_stripe(gen_s)
		gen_s += 1
	# drop old segments
	while segments.size() > 3 and segments[1]["v1"] < crumble_v - 30.0:
		segments.pop_front()

func _gen_stripe(s: int) -> void:
	var terra_tiles: Array = []
	_gen_stripe_tiles(s, terra_tiles)
	if not terra_tiles.is_empty():
		_build_terra(s, terra_tiles)

func _gen_stripe_tiles(s: int, terra_tiles: Array) -> void:
	var v := s * D
	var c := center(v)
	var seg := segment_at(v)
	var biome: String = seg["biome"]
	var keys := []
	# i + j = -s ; u = (2i + s) * D
	var i0 := int(ceil(((c - U_MAX) / D - s) * 0.5))
	var i1 := int(floor(((c + U_MAX) / D - s) * 0.5))
	for i in range(i0, i1 + 1):
		var j := -s - i
		var u := (2 * i + s) * D
		var rule := _ground_rule(u, v)
		if rule == 0:
			continue
		var key := Vector2i(i, j)
		var pos := Vector3(i * T, 0, j * T)
		var jitter := 0.0   # (flat ground: no per-tile steps)
		var top: int = BIOME_TOP[biome]
		var side: int = BIOME_SIDE[biome]
		var surface := "ground"
		var dist := absf(u - c)
		if rule == 2:
			top = P.WATER
			surface = "water"
		elif dist < 1.15 and seg["type"] != "start":
			top = BIOME_PATH[biome]
		# patches come in smooth clumps (noise), not single odd tiles
		elif biome == "seaside" and dist > 3.2 and noise.get_noise_2d(u * 0.9 + 31.0, v * 0.9) > 0.12:
			top = P.GRASS
		elif biome == "forest" and dist > 1.6 and noise.get_noise_2d(u * 1.1 - 21.0, v * 1.1) > 0.5:
			top = P.STONE
		if rule == 1 and seg.get("kind", "") == "rough":
			top = P.RED_SAND
			side = P.RED_ROCK
			surface = "slick"
		elif rule == 1 and seg.get("kind", "") == "dirt":
			surface = "dirt"
		if winter_ice and rule == 1 and surface != "slick" and dist < 3.0 and noise.get_noise_2d(u * 0.7 + 50.0, v * 0.7) > 0.25:
			top = P.ICE
			surface = "ice"
		var pool_name := "water" if rule == 2 else "tile"
		var height := jitter
		var in_place := false
		var plc := _place_at(u, v) if dist > 1.5 else {}
		if not plc.is_empty():
			var pt := _place_tile(plc["place"], plc["a"], plc["d"])
			in_place = true
			match String(pt["kind"]) if not (pt["kind"] == "water" and rule != 2) else "ground":
				"water":
					pool_name = "water"
					top = P.WATER
					surface = "water"
				"pier":
					pool_name = "tile_pier"
					top = P.PLANK
					surface = "ground"
				"rock":
					pool_name = "tile_rock"
					top = P.MOSS
					side = P.ROCK
					height = float(pt["h"])
					surface = "ground"
				_:
					if pt.has("pool"):
						pool_name = pt["pool"]
					if pt.has("top"):
						top = pt["top"]
		elif biome == "forest" and rule == 1 and dist > 3.2 and seg["type"] == "land" and _ridge(u, v, i, j):
			pool_name = "tile_rock"
			top = P.MOSS
			side = P.ROCK
			height = 0.7 + _hash(i, j, 15) * 0.8
		var tile := {"key": key, "pos": pos, "y": height, "s": s, "state": 0, "t": 0.0, "surface": surface, "top": top,
			"slot": -1, "under": -1, "rot": Vector3.ZERO, "spin": Vector3.ZERO, "vy": 0.0, "place": in_place, "bits": -1,
			"ry": 0.0 if pool_name == "tile_rock" else height, "sy": height if pool_name == "tile_rock" else 1.0}
		tile["pool"] = pool_name
		var terra: bool = rule == 1 and seg.get("kind", "") in TERRA_KINDS and pool_name == "tile"
		if terra:
			tile["terra"] = seg
			tile["slot"] = -1
			terra_tiles.append(tile)
			tiles[key] = tile
			keys.append(key)
			continue
		tile["slot"] = pools[pool_name].alloc()
		if tile["slot"] < 0:
			continue
		if pool_name == "tile_rock":
			pools[pool_name].put(tile["slot"], Transform3D(Basis().scaled(Vector3(1, height, 1)), pos))
		else:
			pools[pool_name].put(tile["slot"], Transform3D(Basis(), pos + Vector3(0, jitter, 0)))
		pools[pool_name].custom(tile["slot"], Color(top / 255.0, side / 255.0, 0.5, 0))
		if pool_name == "tile_pier":
			# water under the pier
			var ws: int = pools["water"].alloc()
			if ws >= 0:
				pools["water"].put(ws, Transform3D(Basis(), pos))
				pools["water"].custom(ws, Color(P.WATER / 255.0, P.SAND_SIDE / 255.0, 0.5, 0))
				tile["under"] = ws
				tile["under_pool"] = "water"
		# hanging rock under tiles on the island rim
		var rim := false
		for nb: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni := i + nb.x
			var nj := j + nb.y
			var nu := (ni - nj) * D
			var nv := -(ni + nj) * D
			if _ground_rule(nu, nv) == 0:
				rim = true
				break
		if rim and rule == 1 and tile["under"] < 0:
			var us: int = pools["under"].alloc()
			if us >= 0:
				var sc := 0.75 + _hash(i, j, 4) * 0.5
				pools["under"].put(us, Transform3D(Basis(Vector3.UP, _hash(i, j, 5) * TAU).scaled(Vector3(sc, 0.6 + _hash(i, j, 6) * 0.9, sc)), pos + Vector3(0, jitter, 0)))
				pools["under"].custom(us, Color(top / 255.0, side / 255.0, _hash(i, j, 3), 0))
				tile["under"] = us
		tiles[key] = tile
		keys.append(key)
		if rule == 1 and seg["type"] != "station" and not in_place and pool_name == "tile":
			_maybe_prop(tile, u, v, c, seg, rim)
			# cracked old road, with grass and flowers finding the gaps
			if false:
				var rb: int = pools["road_bits"].alloc()
				if rb >= 0:
					pools["road_bits"].put(rb, Transform3D(Basis(Vector3.UP, floor(_hash(i, j, 19) * 4.0) * PI * 0.5), pos + Vector3(0, height, 0)))
					tile["bits"] = rb
					tile["bits_pool"] = "road_bits"
			# tiny ground detail (blades, pebbles, flowers) on plain tiles
			elif dist > 1.2 and not tile.has("prop") and _hash(i, j, 16) < 0.55 and surface == "ground" and biome != "sky":
				var bs: int = pools["ground_bits"].alloc()
				if bs >= 0:
					var o := Vector3((_hash(i, j, 17) - 0.5) * 0.9, height, (_hash(i, j, 18) - 0.5) * 0.9)
					pools["ground_bits"].put(bs, Transform3D(Basis(Vector3.UP, _hash(i, j, 19) * TAU).scaled(Vector3.ONE * (0.8 + _hash(i, j, 20) * 0.6)), pos + o))
					tile["bits"] = bs
	stripes[s] = keys

func _maybe_prop(tile: Dictionary, u: float, v: float, c: float, seg: Dictionary, rim: bool) -> void:
	var i: int = tile["key"].x
	var j: int = tile["key"].y
	if seg["type"] == "start" and absf(u - c) < 3.0 and v > -6.0:
		return
	var dist := absf(u - c)
	var w := _width_at(v, seg)
	var roll := _hash(i, j, 7)
	var biome: String = seg["biome"]
	var choice := ""
	if dist < w - 1.3:
		if dist < 1.2 and seg["type"] != "start":
			if roll < seg["density"] * 0.7:
				choice = _pick(OBSTACLES[biome], _hash(i, j, 8))
		elif roll < seg["density"] + 0.05:
			choice = _pick(OBSTACLES[biome], _hash(i, j, 8))
		elif roll < seg["density"] + 0.17:
			choice = _pick_decor(biome, _hash(i, j, 8), true)
	else:
		if roll < 0.42:
			choice = _pick_decor(biome, _hash(i, j, 8), rim)
	if choice == "":
		return
	var info: Array = DECOR[biome][choice] if DECOR[biome].has(choice) else [1.0, 0.4, "wood", 0.0]
	if choice in BIG:
		# big buildings need solid ground around them and stay off the racing line
		if dist < 3.0:
			return
		for o in [Vector3(1.4, 0, 0), Vector3(-1.4, 0, 0), Vector3(0, 0, 1.4), Vector3(0, 0, -1.4)]:
			var q: Vector3 = tile["pos"] + o
			if _ground_rule(u_of(q), v_of(q)) != 1:
				return
	var off := Vector3((_hash(i, j, 10) - 0.5) * 0.5, 0, (_hash(i, j, 11) - 0.5) * 0.5)
	if info[1] >= 0.8:
		off = Vector3.ZERO
	var yaw := _hash(i, j, 12) * TAU
	if choice == "fence":
		yaw = atan2(-S.x, -S.z) + (PI * 0.5 if _hash(i, j, 13) < 0.5 else 0.0)
	var sc := 0.85 + _hash(i, j, 14) * 0.3
	if choice in BIG:
		sc = 1.0
		yaw = atan2(S.x, S.z) + (PI if u < c else 0.0) + PI * 0.5
	var p: Vector3 = tile["pos"] + off + Vector3(0, tile["y"], 0)
	var slot: int = pools[choice].alloc()
	if slot < 0:
		return
	var prop := {"name": choice, "pool": choice, "slot": slot, "pos": p, "yaw": yaw, "scale": sc, "r": info[1] * sc,
		"kind": info[2], "state": 0, "s": tile["s"], "tile": tile["key"], "near": 9.0, "rot": Vector3.ZERO}
	pools[choice].put(slot, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), p))
	if prop["kind"] != "flat":
		_hash_add(prop)
	_stripe_add(tile["s"], prop)
	tile["prop"] = true
	if choice == "windmill":
		var bs: int = pools["windmill_blades"].alloc()
		prop["blades"] = bs
		windmills.append(prop)

func _pick(table: Dictionary, r: float) -> String:
	var total := 0.0
	for k in table:
		total += float(table[k])
	var x := r * total
	for k in table:
		x -= float(table[k])
		if x <= 0.0:
			return k
	return table.keys()[0]

func _pick_decor(biome: String, r: float, allow_big: bool) -> String:
	var table := {}
	for k in DECOR[biome]:
		if not allow_big and k in BIG:
			continue
		table[k] = DECOR[biome][k][0]
	return _pick(table, r)

# ------------------------------------------------------------------ queries

func ground_at(p: Vector3) -> float:
	var h := NO_GROUND
	var key := _key(p)
	var t = tiles.get(key)
	if t != null and t["state"] < 2 and t["surface"] != "water":
		h = (terra_h(p, t["terra"]) if t.has("terra") else float(t["y"])) + bump_at(p)
	for s in _surfs_at(p):
		var rel: Vector3 = p - s["origin"]
		var f: float = rel.x * s["fwd"].x + rel.z * s["fwd"].z
		var pad: float = s.get("pad", 0.05)
		if f < -pad or f > s["len"] + pad:
			continue
		var sd: float = rel.x * s["side"].x + rel.z * s["side"].z
		if absf(sd) > s["half_w"]:
			continue
		if s.get("falling", false):
			continue
		var y := 0.0
		match s["kind"]:
			"ramp":
				y = s["height"] * clampf(f / s["len"], 0.0, 1.0) + _tile_y_under(s["origin"])
			"deck":
				y = lerpf(s["y0"], s["y1"], clampf(f / s["len"], 0.0, 1.0))
		h = maxf(h, y)
	return h

func _tile_y_under(p: Vector3) -> float:
	var t = tiles.get(_key(p))
	return t["y"] if t != null else 0.0

## The ramp under a point (or {}), so the car knows when it leaves a kicker's lip.
func ramp_at(p: Vector3) -> Dictionary:
	for s in _surfs_at(p):
		if s["kind"] != "ramp":
			continue
		var rel: Vector3 = p - s["origin"]
		var f: float = rel.x * s["fwd"].x + rel.z * s["fwd"].z
		var sd: float = rel.x * s["side"].x + rel.z * s["side"].z
		if f >= -0.05 and f <= s["len"] + 0.2 and absf(sd) <= s["half_w"]:
			return s
	return {}

## What the tyres are rolling on, for the sound: road, grass, gravel, wood or snow.
func roll_at(p: Vector3, winter: bool) -> String:
	for s in _surfs_at(p):
		var rel: Vector3 = p - s["origin"]
		var f: float = rel.x * s["fwd"].x + rel.z * s["fwd"].z
		var sd: float = rel.x * s["side"].x + rel.z * s["side"].z
		var pad: float = s.get("pad", 0.05)
		if f >= -pad and f <= s["len"] + pad and absf(sd) <= s["half_w"] and not s.get("falling", false):
			return s.get("roll", "wood")
	for st in stations:
		if p.distance_to(st["pos"]) < 2.6:
			return "road"
	var t = tiles.get(_key(p))
	if t == null:
		return "road"
	if t.has("terra"):
		return "gravel"
	var top: int = t.get("top", P.GRASS)
	match top:
		P.PATH, P.SAND, P.HAY:
			return "snow" if winter and top != P.SAND else "gravel"
		P.PLANK:
			return "wood"
		P.STONE, P.ICE, P.CLOUD, P.METAL, P.WALL:
			return "road"
	return "snow" if winter else "grass"

func surface_at(p: Vector3) -> String:
	var t = tiles.get(_key(p))
	if t == null or t["state"] >= 2:
		return "deck" if not deck_at(p).is_empty() else "none"
	return t["surface"]

func water_at(p: Vector3) -> bool:
	var t = tiles.get(_key(p))
	return t != null and t["surface"] == "water"

func biome_at(v: float) -> String:
	return segment_at(v)["biome"]

func tile_shaking(p: Vector3) -> bool:
	var t = tiles.get(_key(p))
	return t != null and t["state"] == 1

## Collisions with scenery. Returns events for the car to react to.
func collide(p: Vector3, radius: float, vel: Vector3, fwd: Vector3) -> Array:
	var out := []
	var base := Vector2i(int(floor(p.x / 2.0)), int(floor(p.z / 2.0)))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var k := base + Vector2i(dx, dz)
			if not props_hash.has(k):
				continue
			for prop in props_hash[k].duplicate():
				if prop["state"] != 0:
					continue
				var d: Vector3 = p - prop["pos"]
				d.y = 0
				var dist := d.length()
				var min_d: float = radius + prop["r"]
				var clearance := dist - min_d
				if clearance < 0.0:
					if prop["kind"] == "solid":
						out.append({"type": "solid", "normal": d.normalized() if dist > 0.001 else -fwd, "depth": -clearance, "prop": prop})
					else:
						_knock(prop, vel, p)
						out.append({"type": "knock", "kind": prop["kind"], "pos": prop["pos"], "prop": prop})
				elif clearance < 0.55 and prop["kind"] != "solid" and vel.length() > 4.0:
					prop["near"] = minf(prop.get("near", 9.0), clearance)
				if prop.get("near", 9.0) < 0.55 and not prop.get("near_done", false):
					var rel: Vector3 = prop["pos"] - p
					if rel.dot(fwd) < -0.4:
						prop["near_done"] = true
						out.append({"type": "near", "pos": prop["pos"]})
	return out

func _knock(prop: Dictionary, vel: Vector3, from: Vector3) -> void:
	_hash_remove(prop)
	if prop["kind"] == "cloud" or prop["kind"] == "sand":
		prop["state"] = 3
		pools[prop["pool"]].release(prop["slot"])
		prop["slot"] = -1
		return
	prop["state"] = 1
	var away: Vector3 = (prop["pos"] - from)
	away.y = 0
	away = away.normalized() if away.length() > 0.01 else vel.normalized()
	var heavy := 0.6 if prop["kind"] == "rock" else 1.0
	prop["vel"] = (vel * 0.75 + away * 2.5) * heavy + Vector3(0, 4.2 * heavy, 0)
	prop["spin"] = Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6)) * heavy
	prop["rot"] = Vector3.ZERO
	prop["life"] = 0.0
	knocked.append(prop)

## Pickups near the car: returns [{"type": "coin"/"fuel", "pos"}].
func collect(p: Vector3, magnet: float, dt: float) -> Array:
	var out := []
	for c in coins:
		if c["taken"] or c["fall"]:
			continue
		var d: Vector3 = p + Vector3(0, 0.45, 0) - c["pos"]
		var dl := d.length()
		if dl < magnet and dl > 0.75:
			c["pos"] += d.normalized() * minf(dl, (10.0 + (magnet - dl) * 6.0) * dt)
			dl = (p + Vector3(0, 0.45, 0) - c["pos"]).length()
		if dl < 0.8:
			c["taken"] = true
			pools["coin"].release(c["slot"])
			out.append({"type": "coin", "pos": c["pos"]})
	for f in fuels:
		if f["taken"] or f["fall"]:
			continue
		var d2: Vector3 = p - f["pos"]
		d2.y *= 0.5
		if d2.length() < 0.95:
			f["taken"] = true
			pools["fuel"].release(f["slot"])
			out.append({"type": "fuel", "pos": f["pos"]})
	for pad in pads:
		if pad["used"] or not pad["checked"]:
			continue
		var rp: Vector3 = p - pad["pos"]
		if absf(rp.y) < 0.8 and absf(rp.dot(pad["fwd"])) < 1.15 and absf(rp.dot(pad["side"])) < 1.15:
			pad["used"] = true
			out.append({"type": "boost", "pos": pad["pos"]})
	for st in stations:
		if st["used"]:
			continue
		var rel: Vector3 = p - st["pos"]
		var lx: float = rel.dot(st["x"])
		var lz: float = rel.dot(st["z"])
		if absf(lx) < 2.4 and absf(lz) < 2.1 and absf(rel.y) < 1.0:
			st["used"] = true
			out.append({"type": "station", "pos": st["pos"]})
	return out

## Distance along the edge-normal to the nearest drop, sampled to the car's sides.
func edge_skim(p: Vector3, side: Vector3) -> bool:
	if ground_at(p) == NO_GROUND or not deck_at(p).is_empty():
		return false
	return ground_at(p + side * 0.95) == NO_GROUND or ground_at(p - side * 0.95) == NO_GROUND

# ------------------------------------------------------------------ per-frame

var honk_pending := false

func tick(dt: float, car_v: float, crumble_speed: float, crumbling: bool, time: float, car_pos := Vector3.ZERO, car_vel := Vector3.ZERO) -> void:
	if people.tick(dt, car_pos, car_vel, time):
		honk_pending = true
	people.tick_visibility()
	update_gen(car_v)
	if crumbling:
		crumble_v += crumble_speed * dt
		var target := int(floor(crumble_v / D))
		while crumble_s <= target:
			_crumble_stripe(crumble_s)
			crumble_s += 1
	_tick_falling(dt)
	_tick_knocked(dt)
	_tick_coins(dt, time)
	_tick_pads()
	_tick_anims(dt, time, car_pos)
	for wm in windmills:
		if wm["state"] == 0 and wm.has("blades"):
			var yaw: float = wm["yaw"]
			var bs := Basis(Vector3.UP, yaw)
			var hub: Vector3 = wm["pos"] + bs * Vector3(0, 2.2, 0.78)
			pools["windmill_blades"].put(wm["blades"], Transform3D(bs * Basis(Vector3.BACK, time * 1.2), hub))
	for k in pools:
		var pl: Pool = pools[k]
		pl.visible = pl.used() > 0

func start_crumble(at_v: float) -> void:
	crumble_v = at_v

func _crumble_stripe(s: int) -> void:
	if terra_meshes.has(s):
		falling.append({"kind": "terra", "node": terra_meshes[s], "ft": 0.0, "fy": 0.0, "fvy": 0.0})
		terra_meshes.erase(s)
	if stripes.has(s):
		for key in stripes[s]:
			var t = tiles.get(key)
			if t == null or t["state"] != 0:
				continue
			t["state"] = 1
			t["t"] = -randf() * 0.35
			falling.append(t)
		stripes.erase(s)
	if stripe_items.has(s):
		for it in stripe_items[s]:
			if it.has("kind") and (it["kind"] == "ramp" or it["kind"] == "bridge" or it["kind"] == "deck"):
				it["falling"] = true
				it["ft"] = 0.0
				it["fy"] = 0.0
				it["fvy"] = 0.0
				falling.append(it)
			elif it.get("kind", "") == "mound":
				_mound_unlink(it)
				it["falling"] = true
				it["ft"] = 0.0
				it["fy"] = 0.0
				it["fvy"] = 0.0
				falling.append(it)
			elif it.get("kind", "") == "rail_piece":
				it["rail"]["falling"] = true
				it["falling"] = true
				it["ft"] = 0.0
				it["fy"] = 0.0
				it["fvy"] = 0.0
				falling.append(it)
			elif it.get("kind", "") == "mud":
				pools["mud"].release(it["slot"])
				muds.erase(it)
			elif it.get("kind", "") == "person":
				people.vanish(it["p"], fx)
			elif it.get("kind", "") == "fall":
				it["state"] = 3
			elif it.get("kind", "") == "pad":
				pools["pad"].release(it["slot"])
				pads.erase(it)
			elif it.has("taken"):
				if not it["taken"]:
					it["fall"] = true
					it["vel"] = Vector3(0, 0, 0)
			elif it.has("kind") and it["kind"] == "station":
				it["used"] = true
				it["falling"] = true
				it["ft"] = 0.0
				it["fy"] = 0.0
				it["fvy"] = 0.0
				falling.append(it)
			elif it.has("state"):
				if it.get("pool", "") == "":
					_hash_remove(it)
					it["state"] = 3
				elif it["state"] == 0:
					_hash_remove(it)
					it["state"] = 2
					it["vel"] = Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
					it["spin"] = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
					it["rot"] = Vector3.ZERO
					it["life"] = -randf() * 0.35 - 0.45
					knocked.append(it)
		stripe_items.erase(s)
	for m in markers.duplicate():
		if m["s"] <= s:
			m["label"].queue_free()
			markers.erase(m)

func _tick_falling(dt: float) -> void:
	var done := []
	for t in falling:
		if t.has("key"):
			t["t"] += dt
			var pool: Pool = pools[t["pool"]]
			if t["slot"] < 0:
				t["t"] += dt
				if t["t"] >= 0.45:
					t["state"] = 2
					done.append(t)
					tiles.erase(t["key"])
					if t["under"] >= 0:
						pools[t.get("under_pool", "under")].release(t["under"])
				continue
			if t["state"] == 1:
				if t["t"] >= 0.45:
					t["state"] = 2
					t["vy"] = 0.0
					if t["bits"] >= 0:
						pools[t.get("bits_pool", "ground_bits")].release(t["bits"])
						t["bits"] = -1
					t["spin"] = Vector3(randf_range(-1.2, 1.2), randf_range(-0.6, 0.6), randf_range(-1.2, 1.2))
					if randf() < 0.18:
						game.world_event("crumble", {"pos": t["pos"]})
				elif t["t"] > 0.0:
					var sh: float = sin(t["t"] * 70.0) * 0.035 * (t["t"] / 0.45)
					var o: Vector3 = t["pos"] + Vector3(sh, t["ry"] - t["t"] * 0.06, -sh)
					pool.put(t["slot"], Transform3D(Basis().scaled(Vector3(1, t["sy"], 1)), o))
					_under_put(t, o, Basis())
				continue
			t["vy"] -= 16.0 * dt
			t["ry"] += t["vy"] * dt
			t["rot"] += t["spin"] * dt
			var b: Basis = Basis.from_euler(t["rot"])
			pool.put(t["slot"], Transform3D(b.scaled(Vector3(1, t["sy"], 1)), t["pos"] + Vector3(0, t["ry"], 0)))
			_under_put(t, t["pos"] + Vector3(0, t["ry"], 0), b)
			if t["ry"] < -40.0:
				pool.release(t["slot"])
				if t["under"] >= 0:
					pools[t.get("under_pool", "under")].release(t["under"])
				tiles.erase(t["key"])
				done.append(t)
		elif t["kind"] == "terra":
			t["ft"] += dt
			var node: MeshInstance3D = t["node"]
			if t["ft"] < 0.45:
				var sh: float = sin(float(t["ft"]) * 70.0) * 0.03 * (float(t["ft"]) / 0.45)
				node.position = Vector3(sh, -t["ft"] * 0.06, -sh)
				continue
			t["fvy"] -= 16.0 * dt
			t["fy"] += t["fvy"] * dt
			node.position = Vector3(0, t["fy"], 0)
			if t["fy"] < -40.0:
				node.queue_free()
				done.append(t)
		elif t["kind"] == "rail_piece":
			t["ft"] += dt
			if t["ft"] < 0.3:
				continue
			t["fvy"] -= 16.0 * dt
			t["fy"] += t["fvy"] * dt
			var dir: Vector3 = t["dir"]
			var ryaw := atan2(-dir.x, -dir.z)
			var tilt := Basis(Vector3.RIGHT, t["fy"] * 0.03)
			if t["slot"] >= 0:
				pools["rail_piece"].put(t["slot"], Transform3D(Basis(Vector3.UP, ryaw) * tilt * Basis.from_scale(Vector3(1, 1, dir.length() + 0.04)), t["a"] + Vector3(0, t["fy"], 0)))
			if t["x_slot"] >= 0:
				pools["rail_post"].put(t["x_slot"], Transform3D(Basis(Vector3.UP, ryaw) * tilt, t["a"] + Vector3(0, t["fy"], 0)))
			if t["fy"] < -40.0:
				if t["slot"] >= 0:
					pools["rail_piece"].release(t["slot"])
				if t["x_slot"] >= 0:
					pools["rail_post"].release(t["x_slot"])
				done.append(t)
				rails.erase(t["rail"])
		elif t["kind"] == "mound":
			t["ft"] += dt
			if t["ft"] < 0.45:
				continue
			t["fvy"] -= 16.0 * dt
			t["fy"] += t["fvy"] * dt
			pools[t["pool"]].put(t["slot"], Transform3D(Basis(Vector3.UP, t["yaw"]) * Basis.from_scale(Vector3(t["r"], t["h"], t["rz"])), t["pos"] + Vector3(0, t["fy"], 0)))
			if t["fy"] < -40.0:
				pools[t["pool"]].release(t["slot"])
				done.append(t)
		else:
			# ramp / bridge / station
			t["ft"] += dt
			if t["ft"] < 0.4:
				continue
			t["fvy"] -= 16.0 * dt
			t["fy"] += t["fvy"] * dt
			var off := Vector3(0, t["fy"], 0)
			var yaw := atan2(-t["fwd"].x, -t["fwd"].z)
			var tilt := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -t["fy"] * 0.04)
			if t["kind"] == "deck":
				if not t.has("spin"):
					t["spin"] = Vector3(randf_range(-0.9, 0.9), randf_range(-0.4, 0.4), randf_range(-0.9, 0.9))
				var rot := Basis.from_euler(t["spin"] * (t["ft"] - 0.4))
				var bb: Basis = rot * t["basis"]
				if t["slot"] >= 0:
					pools[t["pool"]].put(t["slot"], Transform3D(bb * Basis.from_scale(Vector3(1, 1, t["len"] + 0.12)), t["origin"] - t["fwd"] * 0.06 + off))
				if t["x_slot"] >= 0:
					pools[t["x_pool"]].put(t["x_slot"], Transform3D(rot * Basis(Vector3.UP, yaw), t["origin"] + off))
			elif t["kind"] == "ramp":
				pools["ramp"].put(t["slot"], Transform3D(tilt, t["origin"] + off))
			elif t["kind"] == "bridge":
				for k in t["slots"].size():
					pools["bridge"].put(t["slots"][k], Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, t["fy"] * 0.03 * (k - t["slots"].size() * 0.5)), t["origin"] + t["fwd"] * (k * 1.6) + off * (0.6 + 0.4 * k / maxf(1.0, t["slots"].size()))))
			elif t["kind"] == "station":
				pools["station"].put(t["slot"], Transform3D(tilt, t["pos"] + off))
			if t["fy"] < -40.0:
				if t["kind"] == "deck":
					if t["slot"] >= 0:
						pools[t["pool"]].release(t["slot"])
					if t["x_slot"] >= 0:
						pools[t["x_pool"]].release(t["x_slot"])
					_surf_remove(t)
				elif t["kind"] == "ramp":
					pools["ramp"].release(t["slot"])
					_surf_remove(t)
				elif t["kind"] == "bridge":
					for sl in t["slots"]:
						pools["bridge"].release(sl)
					_surf_remove(t)
				else:
					pools["station"].release(t["slot"])
					stations.erase(t)
				done.append(t)
	for t in done:
		falling.erase(t)

func _under_put(t: Dictionary, origin: Vector3, b: Basis) -> void:
	if t["under"] < 0:
		return
	if t.get("under_pool", "under") == "water":
		pools["water"].put(t["under"], Transform3D(b, origin))
	else:
		pools["under"].put(t["under"], _under_xf(t, origin, b))

func _under_xf(t: Dictionary, origin: Vector3, b := Basis()) -> Transform3D:
	var i: int = t["key"].x
	var j: int = t["key"].y
	var sc := 0.75 + _hash(i, j, 4) * 0.5
	var ub := Basis(Vector3.UP, _hash(i, j, 5) * TAU).scaled(Vector3(sc, 0.6 + _hash(i, j, 6) * 0.9, sc))
	return Transform3D(b * ub, origin)

func _tick_knocked(dt: float) -> void:
	var done := []
	for pr in knocked:
		pr["life"] += dt
		if pr["life"] < 0.0:
			continue
		pr["vel"].y -= 18.0 * dt
		var np: Vector3 = pr["pos"] + pr["vel"] * dt
		var g := ground_at(np) if pr["state"] == 1 else NO_GROUND
		if g != NO_GROUND and np.y < g and pr["vel"].y < 0.0 and np.y > g - 0.5:
			np.y = g
			pr["vel"] = Vector3(pr["vel"].x * 0.55, -pr["vel"].y * 0.32, pr["vel"].z * 0.55)
			pr["spin"] *= 0.6
			if pr["vel"].length() < 0.6:
				pr["vel"] = Vector3.ZERO
				pr["spin"] = Vector3.ZERO
		pr["pos"] = np
		pr["rot"] += pr["spin"] * dt
		var b: Basis = Basis(Vector3.UP, pr["yaw"]) * Basis.from_euler(pr["rot"])
		pools[pr["pool"]].put(pr["slot"], Transform3D(b.scaled(Vector3.ONE * pr["scale"]), np))
		if pr.get("blades", -1) >= 0:
			pools["windmill_blades"].put(pr["blades"], Transform3D(b, np + b * Vector3(0, 2.2, 0.78)))
		var rest: bool = pr["vel"] == Vector3.ZERO and pr["state"] == 1
		if np.y < -40.0 or (rest and pr["life"] > 6.0):
			var t = tiles.get(_key(np))
			if rest and t != null and t["state"] == 0:
				# stays lying on the ground until its tile crumbles
				_stripe_add(t["s"], pr)
				pr["state"] = 0
				pr["kind"] = "flat"
			else:
				pools[pr["pool"]].release(pr["slot"])
				if pr.get("blades", -1) >= 0:
					pools["windmill_blades"].release(pr["blades"])
				windmills.erase(pr)
				lamps.erase(pr)
			done.append(pr)
	for pr in done:
		knocked.erase(pr)

func _tick_pads() -> void:
	for pad in pads.duplicate():
		if pad["checked"] or pad["s"] >= gen_s - 1:
			continue
		pad["checked"] = true
		var g := ground_at(pad["pos"])
		var bad := g == NO_GROUND or water_at(pad["pos"])
		# keep pads on flat ground: not on a ramp, not at a drop
		for o in [-1.6, 0.0, 1.6]:
			var q: Vector3 = pad["pos"] + pad["fwd"] * o
			if ground_at(q) == NO_GROUND or not ramp_at(q).is_empty():
				bad = true
		if bad:
			pools["pad"].release(pad["slot"])
			pads.erase(pad)
			continue
		pad["pos"].y = g
		pools["pad"].put(pad["slot"], Transform3D(Basis(Vector3.UP, atan2(-pad["fwd"].x, -pad["fwd"].z)), pad["pos"]))

func _tick_coins(dt: float, time: float) -> void:
	var done := []
	for c in coins:
		if c["taken"]:
			done.append(c)
			continue
		if not c["checked"] and c["s"] < gen_s - 1:
			c["checked"] = true
			var cg := ground_at(c["pos"])
			if cg == NO_GROUND:
				pools["coin"].release(c["slot"])
				c["taken"] = true
				continue
			# sit on uneven ground instead of inside it
			c["pos"].y = maxf(c["pos"].y, cg + 0.5)
		if c["fall"]:
			c["vel"].y -= 16.0 * dt
			c["pos"] += c["vel"] * dt
			if c["pos"].y < -30.0:
				pools["coin"].release(c["slot"])
				c["taken"] = true
				continue
		var spin: float = time * 3.0 + c["pos"].x * 0.3
		var bob: float = sin(time * 3.0 + c["pos"].z) * 0.06
		pools["coin"].put(c["slot"], Transform3D(Basis(Vector3.UP, spin), c["pos"] + Vector3(0, bob, 0)))
	for c in done:
		coins.erase(c)
	var fdone := []
	for f in fuels:
		if f["taken"]:
			fdone.append(f)
			continue
		if not f["checked"] and f["s"] < gen_s - 1:
			f["checked"] = true
			if ground_at(f["pos"]) == NO_GROUND:
				pools["fuel"].release(f["slot"])
				f["taken"] = true
				continue
			f["pos"].y = ground_at(f["pos"])
		if f["fall"]:
			f["vel"].y -= 16.0 * dt
			f["pos"] += f["vel"] * dt
			if f["pos"].y < -30.0:
				pools["fuel"].release(f["slot"])
				f["taken"] = true
				continue
		var bob: float = 0.12 + sin(time * 2.5 + f["pos"].x) * 0.08
		pools["fuel"].put(f["slot"], Transform3D(Basis(Vector3.UP, time * 1.4), f["pos"] + Vector3(0, bob, 0)))
	for f in fdone:
		fuels.erase(f)

## The current biome as the car sees it; reports a change once.
func biome_changed(car_v: float) -> String:
	var b := biome_at(car_v)
	if b != last_biome_reported:
		last_biome_reported = b
		return b
	return ""
