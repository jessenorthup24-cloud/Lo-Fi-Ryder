extends Node3D
## The floating diorama: generates land ahead of the car, crumbles it away behind, and answers
## "is there ground here?" for the car.
##
## Space: progress v runs up the screen (world F), lateral u runs to screen-right (world S).
## Tiles sit on a world-aligned grid, which shows as diamonds through the isometric camera.

const M := preload("res://scripts/core/models.gd")
const P := preload("res://scripts/core/palette.gd")
const Pool := preload("res://scripts/game/pool.gd")

const T := M.T
const D := T * 0.70710678          # stripe spacing in v
const F := Vector3(-0.70710678, 0, -0.70710678)
const S := Vector3(0.70710678, 0, -0.70710678)
const NO_GROUND := -1000.0
const AHEAD := 72.0
const U_MAX := 12.5

const BIOMES := ["countryside", "seaside", "forest", "sky"]
const BIOME_NAMES := {"countryside": "Countryside", "seaside": "Seaside", "forest": "Forest & Mountains", "sky": "Sky Islands"}
const BIOME_TOP := {"countryside": P.GRASS, "seaside": P.SAND, "forest": P.GRASS_FOREST, "sky": P.GRASS_SKY}
const BIOME_SIDE := {"countryside": P.DIRT, "seaside": P.SAND_SIDE, "forest": P.DIRT, "sky": P.STONE_SIDE}
const BIOME_PATH := {"countryside": P.PATH, "seaside": P.PLANK, "forest": P.PATH, "sky": P.CLOUD}

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
const BIG := ["barn", "windmill", "cabin", "hut", "lighthouse"]

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
var next_marker := 100
var biome_bag: Array = []
var cur_biome := "countryside"
var last_biome_reported := ""
var amp_phase := Vector3.ZERO
var label_font: Font
var winter_ice := false     # set by atmos: lay ice patches while it's snowing

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
	for nm in ["coin", "fuel", "ramp", "bridge", "station", "arch", "marker", "lamp", "windmill_blades"]:
		if not pools.has(nm):
			var cap := {"coin": 260, "fuel": 24, "ramp": 24, "bridge": 80, "station": 6, "arch": 2, "marker": 6, "lamp": 60, "windmill_blades": 24}[nm] as int
			pools[nm] = _pool(nm, cap, false, nm != "coin")
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

func center(v: float) -> float:
	var a := clampf(1.5 + maxf(v, 0.0) / 160.0, 1.5, 6.0)
	if v < 10.0:
		a *= clampf((v + 10.0) / 20.0, 0.0, 1.0)
	return a * (0.62 * sin(v / 23.0 + amp_phase.x) + 0.38 * sin(v / 11.7 + amp_phase.y)) - a * (0.62 * sin(amp_phase.x) + 0.38 * sin(amp_phase.y)) * clampf(1.0 - v / 30.0, 0.0, 1.0)

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
	var len := rng.randf_range(26.0, 52.0) * lerpf(1.0, 0.75, d)
	var roll := rng.randf()
	var kind := "plain"
	if v0 > 40.0:
		if roll < 0.24 + d * 0.08: kind = "ramp_gap"
		elif roll < 0.34 + d * 0.12: kind = "bridge_gap"
		elif roll < 0.52 + d * 0.08: kind = "holes"
		elif roll < 0.62: kind = "split"
		elif roll < 0.72: kind = "narrow"
		elif roll < 0.80: kind = "stunt"
	match kind:
		"ramp_gap":
			_add_land(v0, len, d, "plain", true)
			_add_gap(plan_v, false, d, cur_biome)
		"bridge_gap":
			_add_land(v0, len, d, "plain", true)
			_add_gap(plan_v, true, d, cur_biome)
		_:
			_add_land(v0, len, d, kind)

func _add_land(v0: float, len: float, d: float, kind: String, narrow_end := false) -> void:
	var w := rng.randf_range(5.2, 7.0) * lerpf(1.0, 0.66, d)
	if kind == "narrow":
		w = lerpf(3.0, 2.4, d)
	if kind == "split":
		w = maxf(w, 5.6)
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
	_plan_items(seg)

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
	_stripe_add(_stripe_of(va + length * 0.5), surf)
	for k in int(length / 1.6):
		_add_coin(a + dir * (0.8 + k * 1.6) + Vector3(0, 0.5, 0), _stripe_of(va + k * 1.6))

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

func _plan_items(seg: Dictionary) -> void:
	var v0: float = seg["v0"]
	var v1: float = seg["v1"]
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
		return 0
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
		var jitter := (_hash(i, j, 1) - 0.5) * 0.06
		var top: int = BIOME_TOP[biome]
		var side: int = BIOME_SIDE[biome]
		var surface := "ground"
		var dist := absf(u - c)
		if rule == 2:
			top = P.WATER
			surface = "water"
		elif dist < 1.15 and seg["type"] != "start":
			top = BIOME_PATH[biome]
		elif biome == "seaside" and dist > 3.2 and _hash(i, j, 2) < 0.5:
			top = P.GRASS
		elif biome == "forest" and _hash(i, j, 9) < 0.08:
			top = P.STONE
		if winter_ice and rule == 1 and dist < 3.0 and noise.get_noise_2d(u * 0.7 + 50.0, v * 0.7) > 0.25:
			top = P.ICE
			surface = "ice"
		var tile := {"key": key, "pos": pos, "y": jitter, "s": s, "state": 0, "t": 0.0, "surface": surface,
			"slot": -1, "under": -1, "rot": Vector3.ZERO, "spin": Vector3.ZERO, "vy": 0.0}
		var pool_name := "water" if rule == 2 else "tile"
		tile["pool"] = pool_name
		tile["slot"] = pools[pool_name].alloc()
		if tile["slot"] < 0:
			continue
		pools[pool_name].put(tile["slot"], Transform3D(Basis(), pos + Vector3(0, jitter, 0)))
		pools[pool_name].custom(tile["slot"], Color(top / 255.0, side / 255.0, _hash(i, j, 3), 0))
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
		if rim and rule == 1:
			var us: int = pools["under"].alloc()
			if us >= 0:
				var sc := 0.75 + _hash(i, j, 4) * 0.5
				pools["under"].put(us, Transform3D(Basis(Vector3.UP, _hash(i, j, 5) * TAU).scaled(Vector3(sc, 0.6 + _hash(i, j, 6) * 0.9, sc)), pos + Vector3(0, jitter, 0)))
				pools["under"].custom(us, Color(top / 255.0, side / 255.0, _hash(i, j, 3), 0))
				tile["under"] = us
		tiles[key] = tile
		keys.append(key)
		if rule == 1 and seg["type"] != "station":
			_maybe_prop(tile, u, v, c, seg, rim)
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
		h = t["y"]
	for s in surfaces:
		var rel: Vector3 = p - s["origin"]
		var f: float = rel.x * s["fwd"].x + rel.z * s["fwd"].z
		if f < -0.05 or f > s["len"] + 0.05:
			continue
		var sd: float = rel.x * s["side"].x + rel.z * s["side"].z
		if absf(sd) > s["half_w"]:
			continue
		if s.get("falling", false):
			continue
		var y: float = s["height"] * clampf(f / s["len"], 0.0, 1.0) if s["kind"] == "ramp" else 0.0
		if s["kind"] == "ramp":
			y += _tile_y_under(s["origin"])
		h = maxf(h, y)
	return h

func _tile_y_under(p: Vector3) -> float:
	var t = tiles.get(_key(p))
	return t["y"] if t != null else 0.0

## The ramp under a point (or {}), so the car knows when it leaves a kicker's lip.
func ramp_at(p: Vector3) -> Dictionary:
	for s in surfaces:
		if s["kind"] != "ramp":
			continue
		var rel: Vector3 = p - s["origin"]
		var f: float = rel.x * s["fwd"].x + rel.z * s["fwd"].z
		var sd: float = rel.x * s["side"].x + rel.z * s["side"].z
		if f >= -0.05 and f <= s["len"] + 0.2 and absf(sd) <= s["half_w"]:
			return s
	return {}

func surface_at(p: Vector3) -> String:
	var t = tiles.get(_key(p))
	if t == null:
		return "none"
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
	if ground_at(p) == NO_GROUND:
		return false
	return ground_at(p + side * 0.95) == NO_GROUND or ground_at(p - side * 0.95) == NO_GROUND

# ------------------------------------------------------------------ per-frame

func tick(dt: float, car_v: float, crumble_speed: float, crumbling: bool, time: float) -> void:
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
			if it.has("kind") and (it["kind"] == "ramp" or it["kind"] == "bridge"):
				it["falling"] = true
				it["ft"] = 0.0
				it["fy"] = 0.0
				it["fvy"] = 0.0
				falling.append(it)
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
			if t["state"] == 1:
				if t["t"] >= 0.45:
					t["state"] = 2
					t["vy"] = 0.0
					t["spin"] = Vector3(randf_range(-1.2, 1.2), randf_range(-0.6, 0.6), randf_range(-1.2, 1.2))
					if randf() < 0.18:
						game.world_event("crumble", {"pos": t["pos"]})
				elif t["t"] > 0.0:
					var sh: float = sin(t["t"] * 70.0) * 0.035 * (t["t"] / 0.45)
					var o: Vector3 = t["pos"] + Vector3(sh, t["y"] - t["t"] * 0.06, -sh)
					pool.put(t["slot"], Transform3D(Basis(), o))
					if t["under"] >= 0:
						pools["under"].put(t["under"], _under_xf(t, o))
				continue
			t["vy"] -= 16.0 * dt
			t["y"] += t["vy"] * dt
			t["rot"] += t["spin"] * dt
			var b: Basis = Basis.from_euler(t["rot"])
			pool.put(t["slot"], Transform3D(b, t["pos"] + Vector3(0, t["y"], 0)))
			if t["under"] >= 0:
				pools["under"].put(t["under"], _under_xf(t, t["pos"] + Vector3(0, t["y"], 0), b))
			if t["y"] < -40.0:
				pool.release(t["slot"])
				if t["under"] >= 0:
					pools["under"].release(t["under"])
				tiles.erase(t["key"])
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
			if t["kind"] == "ramp":
				pools["ramp"].put(t["slot"], Transform3D(tilt, t["origin"] + off))
			elif t["kind"] == "bridge":
				for k in t["slots"].size():
					pools["bridge"].put(t["slots"][k], Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, t["fy"] * 0.03 * (k - t["slots"].size() * 0.5)), t["origin"] + t["fwd"] * (k * 1.6) + off * (0.6 + 0.4 * k / maxf(1.0, t["slots"].size()))))
			elif t["kind"] == "station":
				pools["station"].put(t["slot"], Transform3D(tilt, t["pos"] + off))
			if t["fy"] < -40.0:
				if t["kind"] == "ramp":
					pools["ramp"].release(t["slot"])
					surfaces.erase(t)
				elif t["kind"] == "bridge":
					for sl in t["slots"]:
						pools["bridge"].release(sl)
					surfaces.erase(t)
				else:
					pools["station"].release(t["slot"])
					stations.erase(t)
				done.append(t)
	for t in done:
		falling.erase(t)

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

func _tick_coins(dt: float, time: float) -> void:
	var done := []
	for c in coins:
		if c["taken"]:
			done.append(c)
			continue
		if not c["checked"] and c["s"] < gen_s - 1:
			c["checked"] = true
			if ground_at(c["pos"]) == NO_GROUND:
				pools["coin"].release(c["slot"])
				c["taken"] = true
				continue
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
