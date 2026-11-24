extends Node3D
## The island: one whole little world, built from code and the Kenney kits, the same every time you play.
## A town with a downtown and a plaza, a suburb, a castle on a hill, a forest lake, farms, a drift arena,
## a harbour, a beach with a pier, all joined by a ring road. Terrain is a heightfield (2.5 m grid) that the
## roads cut into; everything that never moves is merged into one mesh per 100 m chunk.

const M := preload("res://scripts/core/models.gd")
const MB := preload("res://scripts/core/mesh_builder.gd")
const P := preload("res://scripts/core/palette.gd")
const Pool := preload("res://scripts/game/pool.gd")
const People := preload("res://scripts/game/people.gd")
const Districts := preload("res://scripts/game/districts.gd")

const HALF := 600.0          # the world spans -HALF..HALF on x and z
const CELL := 2.5
const N := 481               # height samples per side
const CHUNK := 100.0         # static props merge per chunk
const TCHUNK := 30           # terrain chunk, in cells (75 m)
const ROAD_LIFT := 0.035     # road surface above the ground
const MAP_LAYER := 1 << 19   # minimap-only meshes

enum { S_GRASS, S_ASPHALT, S_CONCRETE, S_DIRT, S_SAND, S_COBBLE, S_FIELD, S_WOOD, S_FOREST }
const GRIP := [0.78, 1.0, 0.97, 0.82, 0.66, 0.93, 0.74, 0.95, 0.76]
const ROLL := ["grass", "road", "road", "gravel", "gravel", "road", "grass", "wood", "grass"]
const SURF_NAMES := ["grass", "asphalt", "concrete", "dirt", "sand", "cobble", "field", "wood", "forest"]

var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var heights := PackedFloat32Array()
var surf := PackedByteArray()
var blocked := PackedByteArray()   # roads, lots and buildings: no scattering here
var _field_masks := {}             # field centre -> which bits of it are on the field's own side of any road
var roads: Array = []
## Where roads meet. Each node: {"c": centre, "arms": [{"r", "s" (sample at the mouth), "dir" (+1: away from the
## node towards higher samples), "stop" (distance from the centre to the mouth), "walk"}], "members": [[r, s]]}
var nodes: Array = []
var lots: Array = []
var flats: Array = []              # [center, half size (Vector2), blend] areas kept flat
var audit_on := false       # tools: record where things are put, to check none sit in the road
var audit: Array = []
var raises: Array = []      # [centre, half size, height, falloff]: ground built up level (the harbour quay)
var season := 1
var mat: ShaderMaterial
var road_mat: ShaderMaterial
var water_mat: ShaderMaterial
var body: StaticBody3D
var shapes := {}                   # cached Shape3D by key
var statics := {}                  # Vector2i chunk -> {mesh name: [Transform3D]}
var far_statics := {}              # landmarks seen from anywhere: mesh name -> [Transform3D]
var pools := {}
var breakables: Array = []         # {pool, slot, pos, yaw, sc, r, kind, home, state, t}
var lamp_heads: Array = []         # the ground under each street lamp's head (where its light falls)
var lamp_on := PackedByteArray()   # (a knocked-down lamp's light goes out)
var lamp_src: Array = []           # where each lamp's light comes from (its head), lighting things in the toon shader
# ---- things that fall over when you hit them hard enough: trees (merged into the chunk meshes) and posts
var topples: Array = []            # {kind: tree/post, name, xf, key, shape, pos, r, h, state 0 up / 1 down, t, knock, restore}
var tgrid := {}                    # 10 m cell -> the topples in it
var downed: Array = []             # knocked down, waiting to come back
var chunk_mi := {}                 # chunk -> its merged props mesh
var chunk_props := {}              # chunk -> {model: [transforms]} it's built from (rebuilt without a fallen tree)
var fallers: Array = []            # falling over right now {node, xf0, axis, th, om, h, t, landed}
const TOPPLE_V := 4.5              # m/s: slower than this a tree or a post just stops you
var bgrid := {}                    # Vector2i (10 m) -> [breakable]
var anims: Array = []
var people: People
var map_root: Node3D
var zones: Array = []              # drift zones {id, name, pos, r, gold...}
var trials: Array = []             # time trials {id, name, gates: [Transform3D], ...}
var coin_spots: Array = []         # {id, pos}
var places: Array = []             # named areas {name, pos, r}
## The stunt yard: boost pads {pos, dir, hs}, hoops {pos, n, r}, loops {pos, dir}, reset spots
## [Transform3D] and its rect (x, z).
var stunt := {"pads": [], "hoops": [], "loops": [], "resets": [], "rect": Rect2()}
var stations: Array = []          # gas stations {name, pos (by the pumps), yaw}
var races: Array = []             # street races {id, name, laps, start, corners}
var spawn := Transform3D()
var sea_y := 0.0
var time := 0.0
var coast_r := PackedFloat32Array()   # coast radius per degree

func build(material: ShaderMaterial, s: int) -> void:
	mat = material
	season = s
	rng.seed = 7
	noise.seed = 11
	noise.frequency = 1.0 / 140.0
	noise.fractal_octaves = 3
	noise2.seed = 23
	noise2.frequency = 1.0 / 37.0
	road_mat = mat.duplicate()
	road_mat.set_shader_parameter("depth_bias", 0.0005)
	var steps := [["water", _water], ["coast", _coast], ["plan", func(): Districts.plan(self)], ["heights", _heights],
		["roads", _road_levels], ["network", func(): _network(); _level_junctions()], ["cut", _cut_terrain], ["surfaces", _surfaces], ["terrain", _terrain], ["road meshes", _road_meshes], ["lots", _lot_meshes],
		["bodies", _bodies], ["map", _map_meshes], ["populate", func(): Districts.populate(self)], ["scatter", func(): Districts.scatter(self)],
		["merge", _merge_statics], ["decals", _decal_mesh]]
	for st in steps:
		var t0 := Time.get_ticks_usec()
		(st[1] as Callable).call()
		timings[st[0]] = (Time.get_ticks_usec() - t0) / 1000

var timings := {}

func _bodies() -> void:
	body = StaticBody3D.new()
	body.name = "Statics"
	add_child(body)
	_ground_collider()
	people = People.new()
	people.name = "People"
	add_child(people)
	people.setup(self, mat)
	map_root = Node3D.new()
	map_root.name = "Map"
	add_child(map_root)

func _decal_mesh() -> void:
	var dm := MeshInstance3D.new()
	dm.mesh = decals.commit()
	dm.material_override = road_mat
	dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dm.name = "Decals"
	add_child(dm)

# ---------------------------------------------------------------- shape of the land

func _coast() -> void:
	coast_r.resize(360)
	for d in 360:
		var a := deg_to_rad(float(d))
		var r := 470.0
		r -= 48.0 * _bump(a, PI * 0.5, 0.9)      # the bay in the south: the beach
		r += 34.0 * _bump(a, -PI * 0.25, 0.7)    # the forest bulges out north-east
		r += 18.0 * sin(3.0 * a + 1.0) + 10.0 * sin(7.0 * a + 2.0) + 5.0 * sin(13.0 * a)
		coast_r[d] = r

func _bump(a: float, c: float, w: float) -> float:
	var d := absf(wrapf(a - c, -PI, PI))
	return clampf(1.0 - d / w, 0.0, 1.0) ** 2 * (3.0 - 2.0 * clampf(1.0 - d / w, 0.0, 1.0))

## How far inland a point is (negative: out at sea).
func inland(x: float, z: float) -> float:
	var a := atan2(z, x)
	var f := fposmod(rad_to_deg(a), 360.0)
	var i := int(f)
	var r := lerpf(coast_r[i], coast_r[(i + 1) % 360], f - i)
	return r - sqrt(x * x + z * z)

## The raw land height before roads cut in.
func h0(x: float, z: float) -> float:
	var d := inland(x, z)
	var shore := smoothstep(-55.0, 38.0, d)
	var h := lerpf(-7.0, 1.3, shore)
	var land := smoothstep(0.0, 70.0, d)
	var hill := 0.0
	# castle hill
	var cd := Vector2(x + 30.0, z + 390.0).length()
	hill += 38.0 * (1.0 - smoothstep(52.0, 178.0, cd)) * (1.0 + noise2.get_noise_2d(x, z) * 0.06 * smoothstep(55.0, 90.0, cd))
	# forest hills around the lake
	var fd := Vector2(x - 285.0, z + 255.0).length()
	var fm := 1.0 - smoothstep(120.0, 230.0, fd)
	hill += fm * (7.0 + 9.0 * noise.get_noise_2d(x, z)) * smoothstep(40.0, 80.0, fd)
	# gentle rolls everywhere else
	hill += 1.6 * noise.get_noise_2d(x * 1.7 + 300.0, z * 1.7) + 0.6
	var flat := 0.0
	for f in flats:
		var c: Vector2 = f[0]
		var hs: Vector2 = f[1]
		var q := Vector2(absf(x - c.x) - hs.x, absf(z - c.y) - hs.y)
		var dd := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
		flat = maxf(flat, 1.0 - smoothstep(0.0, float(f[2]), dd))
	h += maxf(hill, 0.0) * land * (1.0 - flat * 0.92)
	# the lake
	var ld := Vector2(x - 285.0, z + 255.0).length()
	h -= 9.5 * (1.0 - smoothstep(26.0, 52.0, ld))
	for r in raises:
		var rc: Vector2 = r[0]
		var rh: Vector2 = r[1]
		var rq := Vector2(absf(x - rc.x) - rh.x, absf(z - rc.y) - rh.y)
		var rd := Vector2(maxf(rq.x, 0.0), maxf(rq.y, 0.0)).length() + minf(maxf(rq.x, rq.y), 0.0)
		if rd < float(r[3]):
			h = lerpf(h, float(r[2]), 1.0 - smoothstep(0.0, float(r[3]), rd))
	return h

func _heights() -> void:
	# the land is smooth, so sample it every 5 m and fill in between
	var n2 := (N - 1) / 2 + 1
	var coarse := PackedFloat32Array()
	coarse.resize(n2 * n2)
	for j in n2:
		var z := -HALF + j * CELL * 2.0
		for i in n2:
			coarse[j * n2 + i] = h0(-HALF + i * CELL * 2.0, z)
	heights.resize(N * N)
	for j in N:
		var j0 := j / 2
		var j1 := mini(j0 + 1, n2 - 1)
		var fz := 0.5 if j % 2 == 1 else 0.0
		for i in N:
			var i0 := i / 2
			var i1 := mini(i0 + 1, n2 - 1)
			var fx := 0.5 if i % 2 == 1 else 0.0
			var a := coarse[j0 * n2 + i0]
			var b := coarse[j0 * n2 + i1]
			var c := coarse[j1 * n2 + i0]
			var d := coarse[j1 * n2 + i1]
			heights[j * N + i] = lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)

## Ground height (bilinear over the grid, like the collision).
func height_at(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / CELL, 0.0, N - 1.001)
	var fz := clampf((z + HALF) / CELL, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := heights[j * N + i]
	var b := heights[j * N + i + 1]
	var c := heights[(j + 1) * N + i]
	var d := heights[(j + 1) * N + i + 1]
	# the same diagonal split as the mesh and the collision
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)

func normal_at(x: float, z: float) -> Vector3:
	var e := CELL
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()

func surface_at(x: float, z: float) -> int:
	var i := clampi(int(round((x + HALF) / CELL)), 0, N - 1)
	var j := clampi(int(round((z + HALF) / CELL)), 0, N - 1)
	return surf[j * N + i]

func grip_at(x: float, z: float) -> float:
	return GRIP[surface_at(x, z)]

func _cell(x: float, z: float) -> int:
	var i := clampi(int(round((x + HALF) / CELL)), 0, N - 1)
	var j := clampi(int(round((z + HALF) / CELL)), 0, N - 1)
	return j * N + i

func is_blocked(x: float, z: float) -> bool:
	return blocked[_cell(x, z)] != 0

func block_rect(c: Vector2, hs: Vector2, yaw := 0.0, pad := 1.0) -> void:
	var r := hs.length() + pad
	var bs := Basis(Vector3.UP, -yaw)
	var i0 := int((c.x - r + HALF) / CELL)
	var i1 := int((c.x + r + HALF) / CELL) + 1
	var j0 := int((c.y - r + HALF) / CELL)
	var j1 := int((c.y + r + HALF) / CELL) + 1
	for j in range(maxi(j0, 0), mini(j1, N - 1) + 1):
		for i in range(maxi(i0, 0), mini(i1, N - 1) + 1):
			var p := Vector3(-HALF + i * CELL - c.x, 0, -HALF + j * CELL - c.y)
			var l := bs * p
			if absf(l.x) <= hs.x + pad and absf(l.z) <= hs.y + pad:
				blocked[j * N + i] = 1

func is_free(c: Vector2, hs: Vector2, yaw := 0.0) -> bool:
	var bs := Basis(Vector3.UP, yaw)
	for p in [Vector3(-hs.x, 0, -hs.y), Vector3(hs.x, 0, -hs.y), Vector3(-hs.x, 0, hs.y), Vector3(hs.x, 0, hs.y), Vector3.ZERO,
			Vector3(0, 0, -hs.y), Vector3(0, 0, hs.y), Vector3(-hs.x, 0, 0), Vector3(hs.x, 0, 0)]:
		var w: Vector3 = bs * p
		if is_blocked(c.x + w.x, c.y + w.z):
			return false
	return true

# ---------------------------------------------------------------- roads

## kind: ring, main, street, lane, mountain, dirt. Points are xz control points; the road is a
## Catmull-Rom spline through them, sampled every 2.5 m.
func add_road(name: String, ctrl: Array, kind: String, closed := false) -> Dictionary:
	# ("yard": a way in to the stunt yard; traffic leaves it alone)
	var w: float = {"ring": 12.0, "main": 12.0, "road": 11.0, "street": 10.0, "lane": 8.0, "mountain": 9.0, "dirt": 6.5, "yard": 8.0}[kind]
	var pts := _spline(ctrl, closed)
	var r := {"name": name, "pts": pts, "y": PackedFloat32Array(), "w": w, "kind": kind, "closed": closed,
		"walk": kind == "street" or kind == "main", "surf": S_DIRT if kind == "dirt" else S_ASPHALT}
	roads.append(r)
	return r

func _spline(ctrl: Array, closed: bool) -> PackedVector2Array:
	var dense := PackedVector2Array()
	var n := ctrl.size()
	var segs := n if closed else n - 1
	for s in segs:
		var p0: Vector2 = ctrl[(s - 1 + n) % n] if (closed or s > 0) else ctrl[0] * 2.0 - ctrl[1]
		var p1: Vector2 = ctrl[s]
		var p2: Vector2 = ctrl[(s + 1) % n]
		var p3: Vector2 = ctrl[(s + 2) % n] if (closed or s + 2 < n) else p2 * 2.0 - p1
		var steps := maxi(2, int(p1.distance_to(p2) / 1.0))
		for k in steps:
			var t := float(k) / steps
			# centripetal-ish: plain Catmull-Rom is fine with even control points
			var t2 := t * t
			var t3 := t2 * t
			dense.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	if not closed:
		dense.append(ctrl[n - 1])
	# even spacing
	var out := PackedVector2Array()
	out.append(dense[0])
	var acc := 0.0
	for k in range(1, dense.size()):
		var a := dense[k - 1]
		var b := dense[k]
		var l := a.distance_to(b)
		while acc + l >= CELL:
			var t := (CELL - acc) / l
			a = a.lerp(b, t)
			l = a.distance_to(b)
			out.append(a)
			acc = 0.0
		acc += l
	if not closed and out[out.size() - 1].distance_to(dense[dense.size() - 1]) > 0.5:
		out.append(dense[dense.size() - 1])
	return out

func _road_levels() -> void:
	# each road's height: the land under it, smoothed so slopes stay drivable
	for r in roads:
		var pts: PackedVector2Array = r["pts"]
		var n := pts.size()
		var y := PackedFloat32Array()
		y.resize(n)
		for k in n:
			y[k] = height_at(pts[k].x, pts[k].y)
		for pass_i in 3:
			var y2 := y.duplicate()
			for k in n:
				var s := 0.0
				var c := 0
				for o in range(-6, 7):
					var kk := k + o
					if r["closed"]:
						kk = posmod(kk, n)
					elif kk < 0 or kk >= n:
						continue
					s += y[kk]
					c += 1
				y2[k] = s / c
			y = y2
		r["y"] = y

## Where roads meet they must meet at one height: every road through a junction comes level with the
## biggest road there, flat across the junction and easing back to its own line over the next stretch.
func _level_junctions() -> void:
	for nd in nodes:
		var widest := 0.0
		var max_hw := 0.0
		for m in nd["members"]:
			widest = maxf(widest, float(roads[m[0]]["w"]))
		var h := 0.0
		var cnt := 0
		for m in nd["members"]:
			var r: Dictionary = roads[m[0]]
			max_hw = maxf(max_hw, float(r["w"]) * 0.5)
			if float(r["w"]) >= widest - 0.1:
				h += _road_y_at(r, float(m[1]))
				cnt += 1
		h /= maxf(cnt, 1)
		nd["y"] = h
		var flat := max_hw + 4.0
		var blend := 26.0
		for m in nd["members"]:
			var r: Dictionary = roads[m[0]]
			var ys: PackedFloat32Array = r["y"]
			var n := ys.size()
			var s0: float = m[1]
			for k in n:
				var ds := absf(float(k) - s0)
				if r["closed"]:
					ds = minf(ds, float(n) - ds)
				var d := ds * CELL
				if d < flat + blend:
					ys[k] = lerpf(h, ys[k], smoothstep(flat, flat + blend, d))
			r["y"] = ys

func _road_y_at(r: Dictionary, sv: float) -> float:
	var ys: PackedFloat32Array = r["y"]
	var n := ys.size()
	var k := clampi(int(floor(sv)), 0, n - 1)
	var k2 := (k + 1) % n if r["closed"] else mini(k + 1, n - 1)
	return lerpf(ys[k], ys[k2], sv - floor(sv))

func _cut_terrain() -> void:
	# cut and fill: the ground meets the road flat across, blending out over the verge
	var best_d := PackedFloat32Array()
	best_d.resize(N * N)
	best_d.fill(1e9)
	var best_y := PackedFloat32Array()
	best_y.resize(N * N)
	var best_w := PackedFloat32Array()
	best_w.resize(N * N)
	for r in roads:
		var pts: PackedVector2Array = r["pts"]
		var ys: PackedFloat32Array = r["y"]
		var core: float = r["w"] * 0.5 + (3.5 if r["walk"] else 1.2)
		var reach := core + 9.0
		var n := pts.size()
		var segs := n if r["closed"] else n - 1
		for k in segs:
			var a := pts[k]
			var b := pts[(k + 1) % n]
			var ya := ys[k]
			var yb := ys[(k + 1) % n]
			var ab := b - a
			var ll := ab.length_squared()
			var i0 := maxi(int((minf(a.x, b.x) - reach + HALF) / CELL), 0)
			var i1 := mini(int((maxf(a.x, b.x) + reach + HALF) / CELL) + 1, N - 1)
			var j0 := maxi(int((minf(a.y, b.y) - reach + HALF) / CELL), 0)
			var j1 := mini(int((maxf(a.y, b.y) + reach + HALF) / CELL) + 1, N - 1)
			for j in range(j0, j1 + 1):
				var pz := -HALF + j * CELL
				for i in range(i0, i1 + 1):
					var px := -HALF + i * CELL
					var t := clampf(((px - a.x) * ab.x + (pz - a.y) * ab.y) / maxf(ll, 0.0001), 0.0, 1.0)
					var qx := a.x + ab.x * t - px
					var qz := a.y + ab.y * t - pz
					var d := sqrt(qx * qx + qz * qz)
					var idx := j * N + i
					if d < reach and d < best_d[idx]:
						best_d[idx] = d
						best_y[idx] = lerpf(ya, yb, t)
						best_w[idx] = 1.0 if d <= core else smoothstep(reach, core, d)
	for idx in N * N:
		if best_d[idx] < 1e8:
			heights[idx] = lerpf(heights[idx], best_y[idx], best_w[idx])
	# roads follow the cut ground exactly
	for r in roads:
		var pts: PackedVector2Array = r["pts"]
		var ys: PackedFloat32Array = r["y"]
		for k in pts.size():
			ys[k] = height_at(pts[k].x, pts[k].y)
		r["y"] = ys

func _surfaces() -> void:
	surf.resize(N * N)
	blocked.resize(N * N)
	for j in N:
		var z := -HALF + j * CELL
		for i in N:
			var x := -HALF + i * CELL
			var h := heights[j * N + i]
			var s := S_GRASS
			if h < 2.1 and inland(x, z) < 75.0:
				s = S_SAND
			elif Vector2(x - 285.0, z + 255.0).length() < 230.0 and h > 2.5:
				s = S_FOREST
			surf[j * N + i] = s
	for l in lots:
		_paint_rect(l["c"], l["hs"], l.get("yaw", 0.0), l["surf"], true)
	for f in Districts.fields(self):
		var fc: Vector2 = f["c"]
		var fh: Vector2 = f["hs"]
		for j in range(maxi(int((fc.y - fh.y + HALF) / CELL), 0), mini(int((fc.y + fh.y + HALF) / CELL) + 2, N)):
			for i in range(maxi(int((fc.x - fh.x + HALF) / CELL), 0), mini(int((fc.x + fh.x + HALF) / CELL) + 2, N)):
				var q := Vector2(-HALF + i * CELL, -HALF + j * CELL)
				if absf(q.x - fc.x) <= fh.x and absf(q.y - fc.y) <= fh.y and field_keep(f, q):
					surf[j * N + i] = S_FIELD
	for r in roads:
		var pts: PackedVector2Array = r["pts"]
		var hw: float = r["w"] * 0.5
		var walk: bool = r["walk"]
		for k in pts.size():
			var p := pts[k]
			var rr := hw + (3.0 if walk else 0.0) + 0.6
			for j in range(int((p.y - rr + HALF) / CELL), int((p.y + rr + HALF) / CELL) + 2):
				for i in range(int((p.x - rr + HALF) / CELL), int((p.x + rr + HALF) / CELL) + 2):
					if i < 0 or j < 0 or i >= N or j >= N:
						continue
					var d := Vector2(-HALF + i * CELL, -HALF + j * CELL).distance_to(p)
					var idx := j * N + i
					if d <= hw + 0.6:
						surf[idx] = r["surf"]
					elif walk and d <= hw + 3.2 and surf[idx] != S_ASPHALT:
						surf[idx] = S_CONCRETE
					if d <= rr:
						blocked[idx] = 1

func _paint_rect(c: Vector2, hs: Vector2, yaw: float, s: int, block: bool) -> void:
	var r := hs.length()
	var bs := Basis(Vector3.UP, -yaw)
	for j in range(maxi(int((c.y - r + HALF) / CELL), 0), mini(int((c.y + r + HALF) / CELL) + 2, N)):
		for i in range(maxi(int((c.x - r + HALF) / CELL), 0), mini(int((c.x + r + HALF) / CELL) + 2, N)):
			var l := bs * Vector3(-HALF + i * CELL - c.x, 0, -HALF + j * CELL - c.y)
			if absf(l.x) <= hs.x and absf(l.z) <= hs.y:
				surf[j * N + i] = s
				if block:
					blocked[j * N + i] = 1

## A paved (or sandy, or wooden) area: flat, drawn just above the ground.
func add_lot(c: Vector2, hs: Vector2, s: int, yaw := 0.0, flatten := true) -> void:
	lots.append({"c": c, "hs": hs, "surf": s, "yaw": yaw})
	if flatten:
		flats.append([c, hs + Vector2(2, 2), 22.0])

# ---------------------------------------------------------------- meshes

func _slot_col(slot: int) -> Color:
	return MB.pal(slot)

func _ground_slot(idx: int, x: float, z: float, slope: float) -> int:
	var s := surf[idx]
	var h := heights[idx]
	if h < -0.15:
		return P.SAND
	if slope > 0.55:
		return P.ROCK
	match s:
		S_SAND:
			return P.SAND
		S_FIELD:
			return P.SOIL     # (the rows and crops are built on top: districts._crops)
		S_DIRT:
			return P.DIRT
		S_FOREST:
			return P.GRASS_FOREST
		S_CONCRETE, S_ASPHALT, S_COBBLE:
			return P.GRASS
	if slope > 0.34:
		return P.MOSS
	return P.GRASS

func _terrain() -> void:
	var chunks := (N - 1) / TCHUNK
	var cols := PackedColorArray()
	cols.resize(N * N)
	var nrm := PackedVector3Array()
	nrm.resize(N * N)
	for j in N:
		for i in N:
			var idx := j * N + i
			var hl := heights[j * N + maxi(i - 1, 0)]
			var hr := heights[j * N + mini(i + 1, N - 1)]
			var hu := heights[maxi(j - 1, 0) * N + i]
			var hd := heights[mini(j + 1, N - 1) * N + i]
			var n := Vector3(hl - hr, 2.0 * CELL, hu - hd).normalized()
			nrm[idx] = n
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			cols[idx] = _slot_col(_ground_slot(idx, x, z, 1.0 - n.y + (1.0 - n.y)))
	for cj in chunks:
		for ci in chunks:
			var lo := 1e9
			var hi := -1e9
			for j in range(cj * TCHUNK, cj * TCHUNK + TCHUNK + 1):
				for i in range(ci * TCHUNK, ci * TCHUNK + TCHUNK + 1):
					lo = minf(lo, heights[j * N + i])
					hi = maxf(hi, heights[j * N + i])
			if hi < -3.0:
				continue
			var vv := PackedVector3Array()
			var nn := PackedVector3Array()
			var cc := PackedColorArray()
			var ii := PackedInt32Array()
			var w := TCHUNK + 1
			for j in range(cj * TCHUNK, cj * TCHUNK + w):
				for i in range(ci * TCHUNK, ci * TCHUNK + w):
					var idx := j * N + i
					vv.append(Vector3(-HALF + i * CELL, heights[idx], -HALF + j * CELL))
					nn.append(nrm[idx])
					cc.append(cols[idx])
			for j in TCHUNK:
				for i in TCHUNK:
					var a := j * w + i
					# a b / c d, split along b-c (matches height_at)
					ii.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = vv
			arr[Mesh.ARRAY_NORMAL] = nn
			arr[Mesh.ARRAY_COLOR] = cc
			arr[Mesh.ARRAY_INDEX] = ii
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if hi - lo < 6.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.name = "Ground_%d_%d" % [ci, cj]
			add_child(mi)

func _water() -> void:
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/sea.gdshader")
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(5000, 5000)
	pm.subdivide_width = 0
	sea.mesh = pm
	sea.material_override = water_mat
	sea.position.y = sea_y
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.name = "Sea"
	add_child(sea)

## Ribbon meshes for every road, split by chunk: the carriageway, pavements that stop at the kerb of any
## road they meet (and pick up again on the far side, joined by a zebra crossing), painted lines that
## leave junctions clear, and stop lines where side roads meet.
func _road_meshes() -> void:
	var by_chunk := {}
	# where each road meets others: [sample, half span in samples, other roads there]
	var meets := {}
	for nd in nodes:
		var others := []
		for m in nd["members"]:
			others.append(m[0])
		for m in nd["members"]:
			var ri: int = m[0]
			var stop := 0.0
			for m2 in nd["members"]:
				if m2[0] != ri:
					stop = maxf(stop, float(roads[m2[0]]["w"]) * 0.5 + 3.4)
			if not meets.has(ri):
				meets[ri] = []
			meets[ri].append([float(m[1]), (stop + 1.0) / CELL, others, nd])
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var pts: PackedVector2Array = r["pts"]
		var ys: PackedFloat32Array = r["y"]
		var n := pts.size()
		var hw: float = r["w"] * 0.5
		var kind: String = r["kind"]
		var col: Color = _slot_col(P.ASPHALT_DK)
		if kind == "dirt":
			col = _slot_col(P.DIRT)
		var line_w := MB.rgb("f4f1e8")
		var line_y := MB.rgb("f6c64a")
		var segs := n if r["closed"] else n - 1
		var my_meets: Array = meets.get(ri, [])
		for k in segs:
			var a := pts[k]
			var b := pts[(k + 1) % n]
			var ya := ys[k] + ROAD_LIFT
			var yb := ys[(k + 1) % n] + ROAD_LIFT
			var ta := _tangent(pts, k, r["closed"])
			var tb := _tangent(pts, (k + 1) % n, r["closed"])
			var na := Vector2(-ta.y, ta.x)
			var nb := Vector2(-tb.y, tb.x)
			var key := Vector2i(int(floor(a.x / CHUNK)), int(floor(a.y / CHUNK)))
			if not by_chunk.has(key):
				by_chunk[key] = MB.new()
			var mb: MB = by_chunk[key]
			var up := Vector3.UP
			var pa := Vector3(a.x, ya, a.y)
			var pb := Vector3(b.x, yb, b.y)
			var la := Vector3(na.x, 0, na.y)
			var lb := Vector3(nb.x, 0, nb.y)
			if kind == "dirt":
				# a dirt track stops at the edge of a paved road (and sits a hair under it): drawn in
				# quarters so its end follows the kerb
				var lo := Vector3(0, -ROAD_LIFT * 0.4, 0)
				for u in 4:
					var t0 := u / 4.0
					var t1 := (u + 1) / 4.0
					var mid2 := a.lerp(b, (t0 + t1) * 0.5)
					if on_carriageway(mid2, ri, 0.3):
						continue
					var c0 := pa.lerp(pb, t0) + lo
					var c1 := pa.lerp(pb, t1) + lo
					var l0 := la.lerp(lb, t0).normalized()
					var l1 := la.lerp(lb, t1).normalized()
					mb.quad(c0 - l0 * hw, c1 - l1 * hw, c1 + l1 * hw, c0 + l0 * hw, up, col)
			else:
				mb.quad(pa - la * hw, pb - lb * hw, pb + lb * hw, pa + la * hw, up, col)
			# which junctions this bit of road is in (or near)
			var near_m := []
			var in_j := false
			for mt in my_meets:
				var ds := absf(float(k) + 0.5 - float(mt[0]))
				if r["closed"]:
					ds = minf(ds, float(n) - ds)
				if ds < float(mt[1]) + 4.0:
					near_m.append(mt)
				if ds < float(mt[1]):
					in_j = true
			if r["walk"]:
				var sw := _slot_col(P.CONCRETE)
				for sd in [-1.0, 1.0]:
					for u in 4:
						var t0 := u / 4.0
						var t1 := (u + 1) / 4.0
						var c0 := pa.lerp(pb, t0)
						var c1 := pa.lerp(pb, t1)
						var l0 := la.lerp(lb, t0).normalized()
						var l1 := la.lerp(lb, t1).normalized()
						if not near_m.is_empty():
							# does this bit of pavement sit on another road's carriageway?
							var mid: Vector3 = (c0 + c1) * 0.5 + (l0 + l1).normalized() * (hw + 1.5) * sd
							var blocked_here := false
							for mt in near_m:
								for oj in mt[2]:
									if oj != ri and _near_road_d(oj, Vector2(mid.x, mid.z), mt[3]) < float(roads[oj]["w"]) * 0.5 + 0.2:
										blocked_here = true
							if blocked_here:
								continue
						var i0: float = hw * sd
						var o0: float = (hw + 3.0) * sd
						var lift2 := Vector3(0, 0.04, 0)
						var p1 := c0 + l0 * i0 + lift2
						var p2 := c1 + l1 * i0 + lift2
						var p3 := c1 + l1 * o0 + lift2
						var p4 := c0 + l0 * o0 + lift2
						if sd > 0:
							mb.quad(p1, p2, p3, p4, up, sw)
						else:
							mb.quad(p4, p3, p2, p1, up, sw)
			if kind == "dirt" or in_j:
				continue
			var lift := Vector3(0, 0.015, 0)
			# centre line: dashed (solid yellow on the mountain)
			var dash := kind == "mountain" or (k / 2) % 3 != 0
			if kind != "lane" and kind != "yard" and dash:
				var cw := 0.13
				var cc: Color = line_y if kind in ["ring", "mountain", "main", "road"] else line_w
				mb.quad(pa - la * cw + lift, pb - lb * cw + lift, pb + lb * cw + lift, pa + la * cw + lift, up, cc)
			if kind in ["ring", "mountain", "main", "road"]:
				for sd in [-1.0, 1.0]:
					var e0: float = (hw - 0.55) * sd
					var e1: float = (hw - 0.35) * sd
					var q1 := pa + la * e0 + lift
					var q2 := pb + lb * e0 + lift
					var q3 := pb + lb * e1 + lift
					var q4 := pa + la * e1 + lift
					if sd > 0:
						mb.quad(q1, q2, q3, q4, up, line_w)
					else:
						mb.quad(q4, q3, q2, q1, up, line_w)
	# zebra crossings and stop lines at the mouths of junctions
	for nd in nodes:
		for arm in nd["arms"]:
			var ri: int = arm["r"]
			var r: Dictionary = roads[ri]
			if r["kind"] == "dirt":
				continue
			var hw: float = arm["hw"]
			# the widest other road here that has pavements: the zebra links them across this road
			var hw_walk := 0.0
			var hw_any := 0.0
			for m in nd["members"]:
				if m[0] != ri:
					hw_any = maxf(hw_any, float(roads[m[0]]["w"]) * 0.5)
					if roads[m[0]]["walk"]:
						hw_walk = maxf(hw_walk, float(roads[m[0]]["w"]) * 0.5)
			var white := MB.rgb("f4f1e8")
			var zebra_far := 0.0
			if hw_walk > 0.0 and r["walk"]:
				var f := _arm_frame(ri, float(arm["at"]), int(arm["dir"]), hw_walk + 1.6)
				var mbz: MB = _chunk_mb(by_chunk, f[0])
				var nstripes := int((hw * 2.0 - 1.0) / 0.9)
				for q in nstripes:
					var off: float = -hw + 0.5 + 0.225 + q * 0.9 + ((hw * 2.0 - 1.0) - nstripes * 0.9) * 0.5
					_flat_rect(mbz, f[0], f[1], f[2], f[3], off, 0.225, 1.3, white)
				zebra_far = hw_walk + 3.0
			if not arm["minor"] or r["kind"] in ["ring", "mountain"]:
				continue
			var stop_d := maxf(zebra_far + 0.5, hw_any + 1.8)
			var f2 := _arm_frame(ri, float(arm["at"]), int(arm["dir"]), stop_d)
			var mbs: MB = _chunk_mb(by_chunk, f2[0])
			# traffic heading in towards the junction keeps right: the line spans that half
			_flat_rect(mbs, f2[0], f2[1], f2[2], f2[3], (hw - 0.25) * 0.5 * -1.0, (hw - 0.25) * 0.5, 0.2, white)
	for key in by_chunk:
		var mb: MB = by_chunk[key]
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit()
		mi.material_override = road_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "Road_%d_%d" % [key.x, key.y]
		add_child(mi)

# ---------------------------------------------------------------- the road network

func _road_segs_grid() -> Dictionary:
	var grid := {}
	for ri in roads.size():
		var pts: PackedVector2Array = roads[ri]["pts"]
		var n := pts.size()
		var segs := n if roads[ri]["closed"] else n - 1
		for k in segs:
			var a := pts[k]
			var b := pts[(k + 1) % n]
			for gx in range(int(floor(minf(a.x, b.x) / 20.0)), int(floor(maxf(a.x, b.x) / 20.0)) + 1):
				for gz in range(int(floor(minf(a.y, b.y) / 20.0)), int(floor(maxf(a.y, b.y) / 20.0)) + 1):
					var key := Vector2i(gx, gz)
					if not grid.has(key):
						grid[key] = []
					grid[key].append([ri, k])
	return grid

## Nearest point on road ri to p: [distance, sample position s, point].
func road_nearest(ri: int, p: Vector2) -> Array:
	var pts: PackedVector2Array = roads[ri]["pts"]
	var n := pts.size()
	var segs := n if roads[ri]["closed"] else n - 1
	var best := [1e9, 0.0, Vector2.ZERO]
	for k in segs:
		var a := pts[k]
		var b := pts[(k + 1) % n]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := q.distance_to(p)
		if d < best[0]:
			var t := 0.0 if a.distance_squared_to(b) < 0.0001 else a.distance_to(q) / a.distance_to(b)
			best = [d, float(k) + t, q]
	return best

func _network() -> void:
	nodes.clear()
	var raw := []      # [point, [[road, s], [road, s]]]
	var grid := _road_segs_grid()
	# where two centre lines cross
	for key in grid:
		var lst: Array = grid[key]
		for i in lst.size():
			for j in range(i + 1, lst.size()):
				var e1: Array = lst[i]
				var e2: Array = lst[j]
				if e1[0] == e2[0]:
					continue
				var p1: PackedVector2Array = roads[e1[0]]["pts"]
				var p2: PackedVector2Array = roads[e2[0]]["pts"]
				var a := p1[e1[1]]
				var b := p1[(int(e1[1]) + 1) % p1.size()]
				var c := p2[e2[1]]
				var d := p2[(int(e2[1]) + 1) % p2.size()]
				var hit = Geometry2D.segment_intersects_segment(a, b, c, d)
				if hit != null:
					var hp: Vector2 = hit
					raw.append([hp, [[e1[0], float(e1[1]) + a.distance_to(hp) / maxf(a.distance_to(b), 0.001)],
						[e2[0], float(e2[1]) + c.distance_to(hp) / maxf(c.distance_to(d), 0.001)]]])
	# where a road ends on (or just short of) another
	for ri in roads.size():
		if roads[ri]["closed"]:
			continue
		var pts: PackedVector2Array = roads[ri]["pts"]
		for e in [0, pts.size() - 1]:
			for rj in roads.size():
				if rj == ri:
					continue
				var nr := road_nearest(rj, pts[e])
				if float(nr[0]) < float(roads[rj]["w"]) * 0.5 + 2.5:
					raw.append([nr[2], [[ri, float(e)], [rj, float(nr[1])]]])
	# gather the meeting points that belong together
	var groups := []
	for it in raw:
		var hit_g := -1
		for gi in groups.size():
			if (groups[gi]["c"] as Vector2).distance_to(it[0]) < 10.0:
				hit_g = gi
				break
		if hit_g < 0:
			groups.append({"c": it[0], "pts": [it[0]], "m": []})
			hit_g = groups.size() - 1
		var g: Dictionary = groups[hit_g]
		g["pts"].append(it[0])
		var cs := Vector2.ZERO
		for q in g["pts"]:
			cs += q
		g["c"] = cs / float(g["pts"].size())
		for m in it[1]:
			g["m"].append(m)
	for g in groups:
		# one position per road
		var per := {}
		for m in g["m"]:
			if not per.has(m[0]):
				per[m[0]] = []
			per[m[0]].append(m[1])
		var members := []
		for ri in per:
			var ss: Array = per[ri]
			var sum := 0.0
			for v in ss:
				sum += v
			members.append([ri, sum / ss.size()])
		if members.size() < 2:
			continue
		var node := {"c": g["c"], "members": members, "arms": []}
		# who gives way: narrower roads, and a road that ends here (the stem of a T); where equal roads
		# cross, everyone does (an all-way stop)
		var max_w := 0.0
		var ends_here := {}
		for m in members:
			max_w = maxf(max_w, float(roads[m[0]]["w"]))
			var nn: int = (roads[m[0]]["pts"] as PackedVector2Array).size()
			ends_here[m[0]] = not roads[m[0]]["closed"] and (float(m[1]) < 2.0 or float(m[1]) > nn - 3.0)
		var through := false
		for m in members:
			if not ends_here[m[0]] and float(roads[m[0]]["w"]) >= max_w - 0.1:
				through = true
		# Main Street's crossroads in town run on traffic lights (a green wave at the speed limit)
		var kinds := []
		for m in members:
			kinds.append(roads[m[0]]["kind"])
		if members.size() == 2 and "main" in kinds and "street" in kinds and not ends_here[members[0][0]] and not ends_here[members[1][0]]:
			node["signal"] = true
			node["phase"] = -float(g["c"].x) / 12.5
		for m in members:
			var ri: int = m[0]
			var r: Dictionary = roads[ri]
			var n: int = (r["pts"] as PackedVector2Array).size()
			var hw_o := 0.0
			for m2 in members:
				if m2[0] != ri:
					hw_o = maxf(hw_o, float(roads[m2[0]]["w"]) * 0.5)
			var walk: bool = r["walk"]
			var stop := hw_o + (3.8 if walk else 1.6)
			for dirn in [1, -1]:
				var sm: float = float(m[1]) + dirn * stop / CELL
				if r["closed"]:
					sm = fposmod(sm, float(n))
				elif sm < 0.0 or sm > n - 1.0:
					continue
				var minor: bool = float(r["w"]) < max_w - 0.1 or (ends_here[ri] and through) or not through
				if not ends_here[ri] and float(r["w"]) >= max_w - 0.1 and through:
					minor = false
				# an all-way stop only where equal roads cross with nobody running through
				var all_way := true
				for m3 in members:
					if float(roads[m3[0]]["w"]) != float(r["w"]) or ends_here[m3[0]]:
						all_way = false
				if all_way:
					minor = true
					node["all_way"] = true
				if node.get("signal", false):
					minor = true
				node["arms"].append({"r": ri, "s": sm, "dir": dirn, "stop": stop, "walk": walk, "hw": float(r["w"]) * 0.5,
					"at": float(m[1]), "minor": minor})
		nodes.append(node)

## Is p part of field f: inside its rectangle and not cut off from the middle of it by a road?
## (A road clipping a corner leaves that corner as plain verge.)
func field_keep(f: Dictionary, p: Vector2) -> bool:
	var c: Vector2 = f["c"]
	var hs: Vector2 = f["hs"]
	if absf(p.x - c.x) > hs.x or absf(p.y - c.y) > hs.y:
		return false
	var key := str(c)
	if not _field_masks.has(key):
		var cs := 2.0
		var nx := int(ceil(hs.x * 2.0 / cs))
		var nz := int(ceil(hs.y * 2.0 / cs))
		var o := c - hs
		var wall := PackedByteArray()
		wall.resize(nx * nz)
		# stamp the roads that cross the field onto it (they're sampled every couple of metres)
		var fr := Rect2(o, hs * 2.0)
		for r in roads:
			var rr: float = float(r["w"]) * 0.5 + 1.2
			for q in (r["pts"] as PackedVector2Array):
				if not fr.grow(rr).has_point(q):
					continue
				for j in range(maxi(int((q.y - rr - o.y) / cs), 0), mini(int((q.y + rr - o.y) / cs) + 1, nz)):
					for i in range(maxi(int((q.x - rr - o.x) / cs), 0), mini(int((q.x + rr - o.x) / cs) + 1, nx)):
						if (o + Vector2((i + 0.5) * cs, (j + 0.5) * cs)).distance_to(q) <= rr:
							wall[j * nx + i] = 1
		var keep := PackedByteArray()
		keep.resize(nx * nz)
		var start := clampi(int(hs.y / cs), 0, nz - 1) * nx + clampi(int(hs.x / cs), 0, nx - 1)
		var todo: Array[int] = []
		if wall[start] == 0:
			todo.append(start)
			keep[start] = 1
		while not todo.is_empty():
			var k: int = todo.pop_back()
			var ki := k % nx
			var kj := k / nx
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni: int = ki + d.x
				var nj: int = kj + d.y
				if ni < 0 or nj < 0 or ni >= nx or nj >= nz:
					continue
				var nk := nj * nx + ni
				if keep[nk] == 0 and wall[nk] == 0:
					keep[nk] = 1
					todo.append(nk)
		_field_masks[key] = {"o": o, "nx": nx, "nz": nz, "cs": cs, "keep": keep}
	var m: Dictionary = _field_masks[key]
	var cs2: float = m["cs"]
	var mi := clampi(int((p.x - (m["o"] as Vector2).x) / cs2), 0, int(m["nx"]) - 1)
	var mj := clampi(int((p.y - (m["o"] as Vector2).y) / cs2), 0, int(m["nz"]) - 1)
	return (m["keep"] as PackedByteArray)[mj * int(m["nx"]) + mi] == 1

## Is p on the carriageway of any road other than skip (and how far in)?
func on_carriageway(p: Vector2, skip := -1, margin := 0.0) -> bool:
	for ri in roads.size():
		if ri == skip:
			continue
		var pts: PackedVector2Array = roads[ri]["pts"]
		var hw: float = float(roads[ri]["w"]) * 0.5 + margin
		# cheap reject on the bounding box
		var bb: Rect2 = roads[ri].get("bb", Rect2())
		if bb.size == Vector2.ZERO:
			bb = Rect2(pts[0], Vector2.ZERO)
			for q in pts:
				bb = bb.expand(q)
			roads[ri]["bb"] = bb
		if not bb.grow(hw).has_point(p):
			continue
		if float(road_nearest(ri, p)[0]) < hw:
			return true
	return false

## Distance from p to road ri near the junction nd (only looks at the stretch of road around it).
func _near_road_d(ri: int, p: Vector2, nd: Dictionary) -> float:
	var s0 := -1.0
	for m in nd["members"]:
		if m[0] == ri:
			s0 = m[1]
	var pts: PackedVector2Array = roads[ri]["pts"]
	var n := pts.size()
	var closed: bool = roads[ri]["closed"]
	var best := 1e9
	for o in range(-12, 12):
		var k := int(s0) + o
		if closed:
			k = posmod(k, n)
		elif k < 0 or k >= n - 1:
			continue
		var q := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[(k + 1) % n])
		best = minf(best, q.distance_to(p))
	return best

## A point on road ri, dist metres from sample s0 in direction dirn: [point (Vector3, on the road), along
## (unit, pointing away from the junction), across (unit, to the right of along), y]
func _arm_frame(ri: int, s0: float, dirn: int, dist: float) -> Array:
	var r: Dictionary = roads[ri]
	var pts: PackedVector2Array = r["pts"]
	var n := pts.size()
	var sv := s0 + dirn * dist / CELL
	if r["closed"]:
		sv = fposmod(sv, float(n))
	else:
		sv = clampf(sv, 0.0, n - 1.001)
	var k := int(floor(sv))
	var k2 := (k + 1) % n
	var f := sv - k
	var p := pts[k].lerp(pts[k2], f)
	var t := (pts[k2] - pts[k]).normalized() * dirn
	var ys: PackedFloat32Array = r["y"]
	var y := lerpf(ys[k], ys[k2], f) + ROAD_LIFT + 0.02
	return [Vector3(p.x, y, p.y), Vector3(t.x, 0, t.y), Vector3(-t.y, 0, t.x), y]

func _chunk_mb(by_chunk: Dictionary, p: Vector3) -> MB:
	var key := Vector2i(int(floor(p.x / CHUNK)), int(floor(p.z / CHUNK)))
	if not by_chunk.has(key):
		by_chunk[key] = MB.new()
	return by_chunk[key]

## A painted rectangle on the road: centred off metres across from c, half width hx across, half length hz along.
func _flat_rect(mb: MB, c: Vector3, along: Vector3, across: Vector3, _y: float, off: float, hx: float, hz: float, col: Color) -> void:
	var m := c + across * off
	var q1 := m - across * hx - along * hz
	var q2 := m + across * hx - along * hz
	var q3 := m + across * hx + along * hz
	var q4 := m - across * hx + along * hz
	mb.quad(q4, q3, q2, q1, Vector3.UP, col)

func _tangent(pts: PackedVector2Array, k: int, closed: bool) -> Vector2:
	var n := pts.size()
	var a := pts[posmod(k - 1, n)] if (closed or k > 0) else pts[k]
	var b := pts[(k + 1) % n] if (closed or k < n - 1) else pts[k]
	return (b - a).normalized()


func _lot_meshes() -> void:
	var mb := MB.new()
	for l in lots:
		var c: Vector2 = l["c"]
		var hs: Vector2 = l["hs"]
		var yaw: float = l.get("yaw", 0.0)
		var slot: int = {S_ASPHALT: P.ASPHALT_DK, S_CONCRETE: P.CONCRETE, S_COBBLE: P.COBBLE, S_DIRT: P.DIRT, S_SAND: P.SAND,
			S_WOOD: P.PLANK}.get(int(l["surf"]), P.CONCRETE)
		var bs := Basis(Vector3.UP, yaw)
		# a grid of quads that follows the ground
		var nx := maxi(1, int(hs.x * 2.0 / 5.0))
		var nz := maxi(1, int(hs.y * 2.0 / 5.0))
		for j in nz:
			for i in nx:
				var corners := []
				for o in [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]:
					var lp := Vector3(-hs.x + o.x * hs.x * 2.0 / nx, 0, -hs.y + o.y * hs.y * 2.0 / nz)
					var wp := bs * lp + Vector3(c.x, 0, c.y)
					wp.y = height_at(wp.x, wp.z) + ROAD_LIFT * 1.5
					corners.append(wp)
				mb.quad(corners[3], corners[2], corners[1], corners[0], Vector3.UP, _slot_col(slot))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = road_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Lots"
	add_child(mi)

# ---------------------------------------------------------------- collision

func _ground_collider() -> void:
	var hm := HeightMapShape3D.new()
	hm.map_width = N
	hm.map_depth = N
	var data := PackedFloat32Array()
	data.resize(N * N)
	for k in N * N:
		data[k] = heights[k] / CELL
	hm.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.scale = Vector3.ONE * CELL
	cs.name = "Ground"
	body.add_child(cs)

func _shape_box(size: Vector3) -> BoxShape3D:
	var key := "b%.1f_%.1f_%.1f" % [size.x, size.y, size.z]
	if not shapes.has(key):
		var b := BoxShape3D.new()
		b.size = size
		shapes[key] = b
	return shapes[key]

func _shape_cyl(r: float, h: float) -> CylinderShape3D:
	var key := "c%.2f_%.1f" % [r, h]
	if not shapes.has(key):
		var c := CylinderShape3D.new()
		c.radius = r
		c.height = h
		shapes[key] = c
	return shapes[key]

## Everything solid besides the ground lives on one body straight in the physics server (thousands of
## shapes; far cheaper than a node each).
var props_body := RID()

func _props_body() -> RID:
	if not props_body.is_valid():
		props_body = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(props_body, PhysicsServer3D.BODY_MODE_STATIC)
		if is_inside_tree():
			PhysicsServer3D.body_set_space(props_body, get_world_3d().space)
		PhysicsServer3D.body_set_collision_layer(props_body, 1)
		PhysicsServer3D.body_set_collision_mask(props_body, 0)
	return props_body

## The stunt pieces you drive on (ramps, the loop, half-pipes) get a body of their own, so the car can tell
## riding up a wall of the loop from scraping a real wall.
var stunt_body := RID()

func _stunt_body() -> RID:
	if not stunt_body.is_valid():
		stunt_body = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(stunt_body, PhysicsServer3D.BODY_MODE_STATIC)
		if is_inside_tree():
			PhysicsServer3D.body_set_space(stunt_body, get_world_3d().space)
		PhysicsServer3D.body_set_collision_layer(stunt_body, 1)
		PhysicsServer3D.body_set_collision_mask(stunt_body, 0)
	return stunt_body

func _enter_tree() -> void:
	for b in [props_body, stunt_body]:
		if (b as RID).is_valid():
			PhysicsServer3D.body_set_space(b, get_world_3d().space)

func _exit_tree() -> void:
	if props_body.is_valid():
		PhysicsServer3D.free_rid(props_body)
		props_body = RID()
	if stunt_body.is_valid():
		PhysicsServer3D.free_rid(stunt_body)
		stunt_body = RID()

## A stunt piece's exact shape, on the stunt body. Uses the model's own simple collision mesh when it
## comes with one (<name>_col), else its triangles.
func add_stunt_collider(name: String, xf: Transform3D) -> void:
	var sc := xf.basis.get_scale().x
	var key := "s%s_%.3f" % [name, sc]
	if not shapes.has(key):
		var src := name
		if name.begins_with("k_") and ResourceLoader.exists("res://assets/kenney/%s_col.res" % name):
			src = name + "_col"
		var faces := M.get_mesh(src).get_faces()
		for i in faces.size():
			faces[i] *= sc
		var sh := ConcavePolygonShape3D.new()
		sh.set_faces(faces)
		sh.backface_collision = true     # (so a hard-pressed car can't slip through the back of a deck)
		shapes[key] = sh
	PhysicsServer3D.body_add_shape(_stunt_body(), (shapes[key] as Shape3D).get_rid(), Transform3D(xf.basis.orthonormalized(), xf.origin))

func add_box_collider(xf: Transform3D, size: Vector3) -> void:
	PhysicsServer3D.body_add_shape(_props_body(), _shape_box(size).get_rid(), xf)

## (returns the collider's index on the props body, so it can be switched off if the thing falls over)
func add_cyl_collider(p: Vector3, r: float, h: float) -> int:
	var i := PhysicsServer3D.body_get_shape_count(_props_body())
	PhysicsServer3D.body_add_shape(_props_body(), _shape_cyl(r, h).get_rid(), Transform3D(Basis(), p + Vector3(0, h * 0.5, 0)))
	return i

## The exact shape of a mesh (ramps, half-pipes) to drive on.
func add_mesh_collider(name: String, xf: Transform3D) -> void:
	# (the scale goes into the shape: a scaled concave shape is asking for trouble)
	var sc := xf.basis.get_scale().x
	var key := "m%s_%.3f" % [name, sc]
	if not shapes.has(key):
		var faces := M.get_mesh(name).get_faces()
		for i in faces.size():
			faces[i] *= sc
		var sh := ConcavePolygonShape3D.new()
		sh.set_faces(faces)
		shapes[key] = sh
	PhysicsServer3D.body_add_shape(_props_body(), (shapes[key] as Shape3D).get_rid(), Transform3D(xf.basis.orthonormalized(), xf.origin))

# ---------------------------------------------------------------- placing things

## Puts a model in the world for good. col: "box" (its bounds), "cyl" (a trunk), "mesh", "stunt" (exact,
## on the stunt body), "" (none).
## Returns its transform. y < -1000: sits on the ground.
func put(name: String, x: float, z: float, yaw := 0.0, sc := 1.0, col := "box", y := -10000.0, landmark := false) -> Transform3D:
	var m := M.get_mesh(name)
	var ab := m.get_aabb()
	var bs := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
	# x, z is the middle of the footprint
	var cen := bs * Vector3(ab.get_center().x, 0, ab.get_center().z)
	x -= cen.x
	z -= cen.z
	if y < -1000.0:
		# rest on the lowest ground under the footprint so nothing floats
		y = height_at(x, z)
		if ab.size.x * sc > 3.0 or ab.size.z * sc > 3.0:
			for o in [Vector3(ab.position.x, 0, ab.position.z), Vector3(ab.end.x, 0, ab.position.z),
					Vector3(ab.position.x, 0, ab.end.z), Vector3(ab.end.x, 0, ab.end.z)]:
				var w: Vector3 = bs * o
				y = minf(y, height_at(x + w.x, z + w.z))
			y -= 0.05
	var xf := Transform3D(bs, Vector3(x, y, z))
	var ckey := Vector2i(int(floor(x / CHUNK)), int(floor(z / CHUNK)))
	if audit_on and col != "":
		var pts := [Vector2(x + cen.x, z + cen.z)]
		for o in [] if col == "cyl" else [Vector3(ab.position.x, 0, ab.position.z), Vector3(ab.end.x, 0, ab.position.z), Vector3(ab.position.x, 0, ab.end.z), Vector3(ab.end.x, 0, ab.end.z)]:
			var w2: Vector3 = bs * o
			pts.append(Vector2(x + w2.x, z + w2.z))
		audit.append([name, pts])
	if landmark:
		if not far_statics.has(name):
			far_statics[name] = []
		far_statics[name].append(xf)
	else:
		var key := Vector2i(int(floor(x / CHUNK)), int(floor(z / CHUNK)))
		if not statics.has(key):
			statics[key] = {}
		if not statics[key].has(name):
			statics[key][name] = []
		statics[key][name].append(xf)
	match col:
		"box":
			var c := ab.get_center() * sc
			var size := ab.size * sc * 0.96
			add_box_collider(Transform3D(Basis(Vector3.UP, yaw), xf.origin + Basis(Vector3.UP, yaw) * c), size)
		"cyl":
			var cr := clampf(minf(ab.size.x, ab.size.z) * sc * 0.12, 0.18, 0.6)
			var si := add_cyl_collider(xf.origin, cr, ab.size.y * sc)
			if not landmark and _toppleable(name):
				_add_topple({"kind": "tree", "name": name, "xf": xf, "key": ckey, "shape": si, "pos": xf.origin, "r": cr, "h": ab.size.y * sc})
		"mesh":
			add_mesh_collider(name, xf)
		"stunt":
			add_stunt_collider(name, xf)
	return xf

## Something you can knock over (lamps, benches, cones...). It springs back once you're gone.
func put_breakable(name: String, x: float, z: float, yaw := 0.0, sc := 1.0, r := 0.5, y := -10000.0) -> void:
	if name == "k_retro_detail-light-single":
		# this model's arm reaches out along +Z (everything else faces -Z): turn it round so the lamp
		# hangs out over the road (or path) it was set facing, not over the pavement
		yaw += PI
	if audit_on:
		audit.append([name, [Vector2(x, z)]])
	if not pools.has(name):
		var p: Pool = Pool.new()
		# (thin posts don't cast shadows: a pole's shadow is thinner than the shadow map can draw, and flickers)
		p.setup(M.get_mesh(name), 200, mat, false, not _is_post(name))
		p.name = "B_" + name
		add_child(p)
		pools[name] = p
	var slot: int = pools[name].alloc()
	if slot < 0:
		return
	var ab := M.get_mesh(name).get_aabb()
	var cen := Basis(Vector3.UP, yaw) * Vector3(ab.get_center().x, 0, ab.get_center().z) * sc
	x -= cen.x
	z -= cen.z
	if y < -1000.0:
		y = height_at(x, z)
	var pos := Vector3(x, y, z)
	var b := {"pool": name, "slot": slot, "pos": pos, "home": pos, "yaw": yaw, "sc": sc, "r": r, "state": 0, "t": 0.0,
		"vel": Vector3.ZERO, "spin": Vector3.ZERO, "basis": Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)}
	pools[name].put(slot, Transform3D(b["basis"], pos))
	breakables.append(b)
	if name == "k_retro_detail-light-single" or name == "k_retro_detail-light-double":
		# where the light falls: out in front of the head, over the road (a park's double lamp: round both heads)
		var reach := 0.92 * sc
		b["heads"] = []
		for hz in ([reach + 2.2] if name.ends_with("single") else [reach, -reach]):
			b["heads"].append(lamp_heads.size())
			lamp_heads.append(pos + Basis(Vector3.UP, yaw) * Vector3(0, 0, float(hz)))
			var hz2: float = reach if name.ends_with("single") else float(hz)
			lamp_src.append(pos + Basis(Vector3.UP, yaw) * Vector3(0, 4.1 * sc, hz2 + (0.6 if name.ends_with("single") else 0.0)))
			lamp_on.append(1)
	var g := Vector2i(int(floor(x / 10.0)), int(floor(z / 10.0)))
	if not bgrid.has(g):
		bgrid[g] = []
	bgrid[g].append(b)

## Something that moves on its own (a windmill's blades, a pet, a boat). Districts drives it.
func add_anim(name: String, pos: Vector3, yaw := 0.0, sc := 1.0) -> Dictionary:
	if not pools.has(name):
		var p: Pool = Pool.new()
		p.setup(M.get_mesh(name), 48, mat, false, true)
		p.name = "A_" + name
		add_child(p)
		pools[name] = p
	var slot: int = pools[name].alloc()
	if slot < 0:
		return {}
	var an := {"pool": name, "slot": slot, "pos": pos, "yaw": yaw, "sc": sc, "ph": rng.randf() * TAU}
	pools[name].put(slot, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), pos))
	anims.append(an)
	return an

var decals := MB.new()

## A flat patch drawn on the ground (driveways, paths).
func decal(c: Vector2, hs: Vector2, yaw: float, slot: int, lift := 1.2) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var cs := []
	for o in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var w: Vector3 = bs * Vector3(o.x * hs.x, 0, o.y * hs.y) + Vector3(c.x, 0, c.y)
		w.y = height_at(w.x, w.z) + ROAD_LIFT * lift
		cs.append(w)
	decals.quad(cs[3], cs[2], cs[1], cs[0], Vector3.UP, _slot_col(slot))

## A wooden deck on posts (quays, the pier) you can drive onto, with a ramp up from the land side.
func deck(c: Vector2, hs: Vector2, top: float, yaw := 0.0) -> void:
	var mb := MB.new()
	var bs := Basis(Vector3.UP, yaw)
	var plank := _slot_col(P.PLANK)
	var dark := _slot_col(P.WOOD_DARK)
	var n := int(hs.y * 2.0 / 0.9)
	for k in n:
		var z := -hs.y + (k + 0.5) * hs.y * 2.0 / n
		mb.box(Vector3(0, top - 0.12, z), Vector3(hs.x * 2.0, 0.24, hs.y * 2.0 / n - 0.08), plank if k % 3 != 1 else _slot_col(P.TRUNK), bs)
	for px in [-hs.x + 0.4, hs.x - 0.4]:
		var z := -hs.y + 1.0
		while z < hs.y:
			var ground := minf(height_at(c.x + (bs * Vector3(px, 0, z)).x, c.y + (bs * Vector3(px, 0, z)).z), top - 0.3)
			var ph := top - ground + 1.5
			mb.box(Vector3(px, top - ph * 0.5, z), Vector3(0.45, ph, 0.45), dark, bs)
			z += 4.5
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = mat
	mi.position = Vector3(c.x, 0, c.y)
	mi.name = "Deck"
	add_child(mi)
	add_box_collider(Transform3D(bs, Vector3(c.x, top - 0.5, c.y)), Vector3(hs.x * 2.0, 1.0, hs.y * 2.0))
	for k in range(-int(hs.y), int(hs.y), 3):
		for sd in [-1.0, 1.0]:
			blocked[_cell(c.x + (bs * Vector3(sd * hs.x, 0, k)).x, c.y + (bs * Vector3(sd * hs.x, 0, k)).z)] = 1

## Knock over anything the car runs into. Returns how hard the car was slowed (0..1).
func hit_breakables(p: Vector3, vel: Vector3, radius: float) -> Array:
	var hits := []
	var g := Vector2i(int(floor(p.x / 10.0)), int(floor(p.z / 10.0)))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cell: Array = bgrid.get(g + Vector2i(dx, dz), [])
			for b in cell:
				if b["state"] != 0:
					continue
				var d: Vector3 = b["pos"] - p
				d.y = 0.0
				if d.length() < radius + float(b["r"]) and absf(b["pos"].y - p.y) < 3.0:
					if _is_post(b["pool"]):
						# a lamp or a signpost: it folds over at the base and falls (and its light goes out)
						b["state"] = 2
						b["t"] = 0.0
						pools[b["pool"]].put(b["slot"], Transform3D(Basis().scaled(Vector3.ONE * 0.001), b["home"]))
						var ab: AABB = M.get_mesh(b["pool"]).get_aabb()
						fall(M.get_mesh(b["pool"]), Transform3D(b["basis"], b["home"]), vel, ab.size.y * float(b["sc"]))
						_lamp_light(b, false)
						hits.append(b)
						continue
					var push := vel * 0.9 + Vector3(0, 3.5 + vel.length() * 0.18, 0)
					b["state"] = 1
					b["t"] = 0.0
					b["vel"] = push + d.normalized() * 2.0
					b["spin"] = Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6))
					hits.append(b)
	return hits

static func _is_post(pool_name: String) -> bool:
	return pool_name.contains("light-single") or pool_name.contains("light-double") or pool_name.contains("signpost")

func _lamp_light(b: Dictionary, on: bool) -> void:
	if not b.has("heads"):
		return
	for hi in b["heads"]:
		lamp_on[int(hi)] = 1 if on else 0

func _tick_breakables(dt: float, car_pos: Vector3) -> void:
	for b in breakables:
		if b["state"] == 0:
			continue
		b["t"] += dt
		if b["state"] == 1:
			b["vel"].y -= 18.0 * dt
			b["pos"] += b["vel"] * dt
			var s: Vector3 = b["spin"]
			b["basis"] = (Basis(Vector3(1, 0, 0), s.x * dt) * Basis(Vector3.UP, s.y * dt) * Basis(Vector3(0, 0, 1), s.z * dt)) * b["basis"]
			var gy := height_at(b["pos"].x, b["pos"].z)
			if b["pos"].y < gy:
				b["pos"].y = gy
				b["vel"] *= Vector3(0.5, -0.25, 0.5)
				b["spin"] *= 0.5
			var k := 1.0 - clampf((b["t"] - 3.0) / 1.0, 0.0, 1.0)
			pools[b["pool"]].put(b["slot"], Transform3D(b["basis"].scaled(Vector3.ONE * maxf(k, 0.001)), b["pos"]))
			if b["t"] > 4.0:
				b["state"] = 2
				pools[b["pool"]].put(b["slot"], Transform3D(Basis().scaled(Vector3.ONE * 0.001), b["home"]))
		elif b["state"] == 2:
			# back where it was once nobody's looking
			if b["t"] > 25.0 and (b["home"] as Vector3).distance_to(car_pos) > 60.0:
				b["state"] = 0
				_lamp_light(b, true)
				b["pos"] = b["home"]
				b["basis"] = Basis(Vector3.UP, b["yaw"]).scaled(Vector3.ONE * float(b["sc"]))
				pools[b["pool"]].put(b["slot"], Transform3D(b["basis"], b["pos"]))

## Merge every static model into one mesh per chunk (plus one for the landmarks).
func _merge_statics() -> void:
	chunk_props = statics.duplicate()
	for key in statics:
		var cm := _chunk_mesh(key)
		if cm == null:
			continue
		var mi := MeshInstance3D.new()
		chunk_mi[key] = mi
		mi.mesh = cm
		mi.material_override = mat
		mi.visibility_range_end = 330.0
		mi.visibility_range_end_margin = 30.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mi.name = "Props_%d_%d" % [key.x, key.y]
		add_child(mi)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for nm in far_statics:
		var m := M.get_mesh(nm)
		for xf in far_statics[nm]:
			st2.append_from(m, 0, xf)
	if not far_statics.is_empty():
		var mi2 := MeshInstance3D.new()
		mi2.mesh = st2.commit()
		mi2.material_override = mat
		mi2.name = "Landmarks"
		add_child(mi2)
	statics = {}
	far_statics.clear()

## A chunk's props merged into one mesh (from chunk_props: a fallen tree is left out).
func _chunk_mesh(key: Vector2i) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for nm in chunk_props[key]:
		var m := M.get_mesh(nm)
		for xf in chunk_props[key][nm]:
			st.append_from(m, 0, xf)
			any = true
	return st.commit() if any else null

# ---------------------------------------------------------------- knocking things over

static func _toppleable(name: String) -> bool:
	return name.contains("tree") or name.contains("palm") or name == "pine_tall"

func _add_topple(tr: Dictionary) -> void:
	tr["state"] = 0
	tr["t"] = 0.0
	topples.append(tr)
	var p: Vector3 = tr["pos"]
	var g := Vector2i(int(floor(p.x / 10.0)), int(floor(p.z / 10.0)))
	if not tgrid.has(g):
		tgrid[g] = []
	tgrid[g].append(tr)

## Something standing that a car can knock over (a traffic light): knock(vel) when it goes, restore() when
## it comes back. Returns its record.
func add_post(p: Vector3, r: float, h: float, knock: Callable, restore: Callable) -> Dictionary:
	var tr := {"kind": "post", "shape": add_cyl_collider(p, r, h), "pos": p, "r": r, "h": h, "knock": knock, "restore": restore}
	_add_topple(tr)
	return tr

## A car at p going at vel, radius big: knocks over whatever it's about to hit (fast enough). Returns them.
func hit_topples(p: Vector3, vel: Vector3, radius: float) -> Array:
	var hits := []
	var v := Vector2(vel.x, vel.z).length()
	if v < TOPPLE_V:
		return hits
	var g := Vector2i(int(floor(p.x / 10.0)), int(floor(p.z / 10.0)))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for tr in tgrid.get(g + Vector2i(dx, dz), []):
				if tr["state"] != 0:
					continue
				var tp: Vector3 = tr["pos"]
				if Vector2(tp.x - p.x, tp.z - p.z).length() < radius + float(tr["r"]) and absf(tp.y - p.y) < 3.0:
					_knock(tr, vel)
					hits.append(tr)
	return hits

func _knock(tr: Dictionary, vel: Vector3) -> void:
	tr["state"] = 1
	tr["t"] = 0.0
	downed.append(tr)
	PhysicsServer3D.body_set_shape_disabled(props_body, int(tr["shape"]), true)
	if tr["kind"] == "tree":
		var lst: Array = chunk_props[tr["key"]][tr["name"]]
		lst.erase(tr["xf"])
		_rebuild_chunk(tr["key"])
		fall(M.get_mesh(tr["name"]), tr["xf"], vel, float(tr["h"]))
	else:
		(tr["knock"] as Callable).call(vel)

func _rebuild_chunk(key: Vector2i) -> void:
	if chunk_mi.has(key):
		(chunk_mi[key] as MeshInstance3D).mesh = _chunk_mesh(key)

## Something falls over from its base, away from what hit it (a copy: the real one's already hidden).
func fall(mesh: Mesh, xf: Transform3D, vel: Vector3, h: float) -> void:
	var dir := Vector3(vel.x, 0, vel.z)
	if dir.length() < 0.1:
		dir = Vector3.FORWARD
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.transform = xf
	if h < 5.0:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	var hh := maxf(h, 1.0)
	fallers.append({"node": node, "xf0": xf, "axis": Vector3.UP.cross(dir.normalized()).normalized(),      # (so the top goes the way you were going)
		"th": 0.12, "om": clampf(dir.length() / hh * 0.9, 0.7, 3.2), "h": hh, "t": 0.0, "landed": false})

func _tick_fallers(dt: float, car_pos: Vector3) -> void:
	for i in range(fallers.size() - 1, -1, -1):
		var f: Dictionary = fallers[i]
		f["t"] = float(f["t"]) + dt
		var lie := 1.42               # (lying down: the crown or the lamp head holds it a little off flat)
		if not f["landed"]:
			# a falling stick: the further over, the faster it goes
			f["om"] = float(f["om"]) + 1.5 * 9.8 / float(f["h"]) * sin(float(f["th"])) * dt
			f["th"] = float(f["th"]) + float(f["om"]) * dt
			if float(f["th"]) >= lie:
				f["th"] = lie
				f["om"] = -float(f["om"]) * 0.18
				if absf(float(f["om"])) < 0.15:
					f["landed"] = true
					f["t"] = 0.0
		var node: MeshInstance3D = f["node"]
		var xf0: Transform3D = f["xf0"]
		var sink := 0.0
		if f["landed"] and float(f["t"]) > 8.0:
			sink = (float(f["t"]) - 8.0) * 0.6          # then it sinks away
		node.transform = Transform3D(Basis(f["axis"], float(f["th"])) * xf0.basis, xf0.origin - Vector3(0, sink, 0))
		if sink > 2.5:
			node.queue_free()
			fallers.remove_at(i)
	# what's down comes back once you're well away
	for i in range(downed.size() - 1, -1, -1):
		var tr: Dictionary = downed[i]
		tr["t"] = float(tr["t"]) + dt
		if float(tr["t"]) > 40.0 and (tr["pos"] as Vector3).distance_to(car_pos) > 90.0:
			tr["state"] = 0
			downed.remove_at(i)
			PhysicsServer3D.body_set_shape_disabled(props_body, int(tr["shape"]), false)
			if tr["kind"] == "tree":
				(chunk_props[tr["key"]][tr["name"]] as Array).append(tr["xf"])
				_rebuild_chunk(tr["key"])
			else:
				(tr["restore"] as Callable).call()

# ---------------------------------------------------------------- minimap

func _map_meshes() -> void:
	# land: the coastline filled in
	var poly := PackedVector2Array()
	for d in range(0, 360, 2):
		var a := deg_to_rad(float(d))
		var r: float = coast_r[d] - 6.0
		poly.append(Vector2(cos(a), sin(a)) * r)
	var tris := Geometry2D.triangulate_polygon(poly)
	var mb := MB.new()
	var land := MB.rgb("9fd67c")
	for t in range(0, tris.size(), 3):
		var a := poly[tris[t]]
		var b := poly[tris[t + 1]]
		var c := poly[tris[t + 2]]
		mb.tri(Vector3(a.x, -5, a.y), Vector3(c.x, -5, c.y), Vector3(b.x, -5, b.y), Vector3.UP, Vector3.UP, Vector3.UP, land)
	_map_mesh(mb, "MapLand")
	# roads, drawn fat so they read on the little map
	var rb := MB.new()
	for r in roads:
		var pts: PackedVector2Array = r["pts"]
		var n := pts.size()
		var hw: float = maxf(float(r["w"]) * 0.9, 6.0)
		var col := MB.rgb("ffffff") if r["kind"] != "dirt" else MB.rgb("e8c79a")
		var segs := n if r["closed"] else n - 1
		for k in range(0, segs, 2):
			var a := pts[k]
			var b := pts[mini(k + 2, n - 1) if not r["closed"] else (k + 2) % n]
			var dd := (b - a).normalized()
			var nn := Vector2(-dd.y, dd.x) * hw
			mb_quad_flat(rb, a - nn - dd * 2.0, b - nn + dd * 2.0, b + nn + dd * 2.0, a + nn - dd * 2.0, 0.0, col)
	for l in lots:
		var c: Vector2 = l["c"]
		var hs: Vector2 = l["hs"]
		var bs := Basis(Vector3.UP, l.get("yaw", 0.0))
		var cs := []
		for o in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var w: Vector3 = bs * Vector3(o.x * hs.x, 0, o.y * hs.y)
			cs.append(Vector2(c.x + w.x, c.y + w.z))
		mb_quad_flat(rb, cs[0], cs[1], cs[2], cs[3], -0.5, MB.rgb("f3ead8"))
	_map_mesh(rb, "MapRoads")

func mb_quad_flat(mb: MB, a: Vector2, b: Vector2, c: Vector2, d: Vector2, y: float, col: Color) -> void:
	mb.quad(Vector3(d.x, y, d.y), Vector3(c.x, y, c.y), Vector3(b.x, y, b.y), Vector3(a.x, y, a.y), Vector3.UP, col)

func _map_mesh(mb: MB, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	var um := StandardMaterial3D.new()
	um.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	um.vertex_color_use_as_albedo = true
	um.vertex_color_is_srgb = true
	mi.material_override = um
	mi.layers = MAP_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 300.0
	mi.name = nm
	map_root.add_child(mi)
	return mi

## A marker on the minimap (a flat coloured disc).
## The GPS route drawn on the map (both the minimap and the big one): a bright line with a dark edge.
var _route_mi: MeshInstance3D

func route_line(pts: PackedVector3Array, col: Color) -> void:
	if _route_mi == null:
		_route_mi = _map_mesh(MB.new(), "Route")
		_route_mi.position.y = 300.4
	if pts.size() < 2:
		_route_mi.mesh = null
		return
	var mb := MB.new()
	for layer in [[4.6, MB.rgb(col.darkened(0.55)), 0.0], [3.0, MB.rgb(col), 0.05]]:
		var hw: float = layer[0]
		var c: Color = layer[1]
		var y: float = layer[2]
		for i in pts.size() - 1:
			var a := Vector3(pts[i].x, y, pts[i].z)
			var b := Vector3(pts[i + 1].x, y, pts[i + 1].z)
			var d := b - a
			if d.length() < 0.01:
				continue
			var n := Vector3(-d.z, 0, d.x).normalized() * hw
			mb.quad(a + n, b + n, b - n, a - n, Vector3.UP, c)
			# a round joint, so bends don't show gaps
			for k in 8:
				var a0 := TAU * k / 8.0
				var a1 := TAU * (k + 1) / 8.0
				mb.tri(b, b + Vector3(cos(a1), 0, sin(a1)) * hw, b + Vector3(cos(a0), 0, sin(a0)) * hw, Vector3.UP, Vector3.UP, Vector3.UP, c)
	_route_mi.mesh = mb.commit()

func map_marker(pos: Vector3, col: Color, r := 9.0) -> MeshInstance3D:
	var mb := MB.new()
	var segs := 16
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		mb.tri(Vector3(0, 0, 0), Vector3(cos(a1) * r, 0, sin(a1) * r), Vector3(cos(a0) * r, 0, sin(a0) * r), Vector3.UP, Vector3.UP, Vector3.UP, MB.rgb(col))
	var mi := _map_mesh(mb, "Marker")
	mi.position = Vector3(pos.x, 301.0, pos.z)
	return mi

# ---------------------------------------------------------------- per frame

func tick(dt: float, car_pos: Vector3, car_vel: Vector3) -> void:
	time += dt
	_tick_breakables(dt, car_pos)
	_tick_fallers(dt, car_pos)
	Districts.tick_anims(self, dt, car_pos)
	people.tick(dt, car_pos, car_vel, time)
	people.tick_visibility()
	for p in pools.values():
		p.visible = p.used() > 0
