extends Node
## The Crawl Park: four rock-crawler courses side by side on a flattened dirt meadow between the Drift Bowl
## and Sunny Bay, built from the Lo-Fi Rock Crawler Obstacle Pack (assets/props/crawl). Each course is a lane
## of obstacles running north with a gate at the end of each; tape marks the lane. They run as trials of kind
## "crawl" (main.gd): against the clock, crawlers only, in low range; leave the tape or roll it and you're
## put back at the last gate with time added. The Scrapyard course and the park's dressing (start gates,
## floodlights, barriers, drums) come from the stunt arena kit the Stunt Yard uses (k_klyo_*).

const DIR := "res://assets/props/crawl/"
const MB := preload("res://scripts/core/mesh_builder.gd")
const M := preload("res://scripts/core/models.gd")
# the stunt kit's raised walkway for crawlers: ramps scaled so their top meets the deck exactly
const PLAT_SC := 1.2                   # a platform: 7.3 wide, 4.9 long, 2.44 m up
const RAMP_SC := 1.5                   # a ramp: 6.7 wide, 9.6 long, up to 2.44 m (14 degrees)
const C := Vector2(70, 252)            # the park's middle
const HS := Vector2(27, 60)            # its half size
const GAP := 4.0                       # flat dirt between obstacles (to settle, line up the next one)
const START_Z := 46.0                  # the start line, this far south of the middle
const PENALTY_OUT := 5.0               # seconds: over the tape
const PENALTY_ROLL := 10.0             # seconds: on its side or roof

## The courses: [id, name, the lane's x offset, medals (gold, silver, bronze seconds), obstacles [model, length],
## the tape (half the lane's width: tighter on the hard one, so the line through it matters)]
## (medals from a bot on a perfect line: 30.9 / 32.1 / 37.1 / 38.7 s; gold a little over that, bronze well over)
const COURSES := [
	["crawl_easy", "Crawl Park: Beginner", -20.25, [36.0, 46.0, 68.0],
		[["01_dirt_hill", 12.0], ["17_dirt_connector", 6.0], ["07_whoops", 12.0], ["12_log_crossing", 9.0], ["13_timber_bridge", 14.0]], 4.6],
	["crawl_flex", "Crawl Park: Articulation", -6.75, [37.0, 48.0, 71.0],
		[["06_cross_axle", 12.0], ["04_sidehill_left", 10.0], ["05_sidehill_right", 10.0], ["11_erosion_ruts", 12.0], ["08_boulder_garden", 12.0]], 4.3],
	# the Scrapyard: the stunt kit's pieces (k:) between rocks and logs
	["crawl_scrap", "Crawl Park: Scrapyard", 6.75, [43.0, 56.0, 82.0],
		[["k:platform_run", 29.04], ["12_log_crossing", 9.0], ["k:squeeze", 12.0], ["k:boulder", 8.0], ["k:tunnel", 10.0]], 4.4],
	["crawl_pro", "Crawl Park: Expert", 20.25, [45.0, 58.0, 85.0],
		[["02_shale_climb", 12.0], ["03_rock_staircase", 14.0], ["09_ridge_balance", 12.0], ["10_v_notch", 12.0], ["14_twin_track", 12.0], ["08_boulder_garden", 12.0]], 3.8],
]

var game: Node
var placed: Array = []                 # [{model, pos, course}] (for tests)

## On the map, before the ground's made: flattened dirt for the park.
static func plan(I) -> void:
	I.add_lot(C, HS, I.S_DIRT)

static func place(_I) -> Dictionary:
	return {"name": "Crawl Park", "pos": Vector3(C.x, 0, C.y), "r": 64.0}

## The courses as trials: a start line and a gate after each obstacle (facing north, -Z, the way you drive).
static func challenges(I) -> void:
	for co in COURSES:
		var x: float = C.x + float(co[2])
		var z: float = C.y + START_Z
		var gates: Array = [Transform3D(Basis(), Vector3(x, I.height_at(x, z), z))]
		z -= 2.0
		for ob in co[4]:
			z -= float(ob[1]) + GAP
			gates.append(Transform3D(Basis(), Vector3(x, I.height_at(x, z + GAP * 0.5), z + GAP * 0.5)))
		I.trials.append({"id": co[0], "name": co[1], "kind": "crawl", "gates": gates, "w": 6.0, "medals": co[3], "lane_x": x, "tape": float(co[5])})

## Lay out the obstacles: each sat on the ground at its middle, with exact collision from its own mesh.
func setup(g: Node) -> void:
	game = g
	var isl = game.island
	var mat: Material = game.toon
	for co in COURSES:
		var x: float = C.x + float(co[2])
		var z: float = C.y + START_Z - 2.0
		for ob in co[4]:
			var ln: float = ob[1]
			var mid := z - ln * 0.5
			var at := Vector3(x, _ground(isl, x, mid, ln), mid)
			if String(ob[0]).begins_with("k:"):
				_kit(String(ob[0]).trim_prefix("k:"), at, ln, String(co[0]))
			else:
				_obstacle(String(ob[0]), at, mat, String(co[0]))
			z -= ln + GAP
		_tape(isl, x, C.y + START_Z + 2.0, z + GAP, float(co[5]))
		_banner(isl, Vector3(x, 0, C.y + START_Z), String(co[1]).trim_prefix("Crawl Park: "))
	_dress(isl)
	# a few loose rocks round the edges, for looks
	var rr := RandomNumberGenerator.new()
	rr.seed = 7
	for k in 18:
		var side := -1.0 if k % 2 == 0 else 1.0
		var p := Vector3(C.x + side * (HS.x - rr.randf_range(1.5, 4.0)), 0, C.y + rr.randf_range(-HS.y + 6.0, HS.y - 6.0))
		_obstacle("15_rock_small" if rr.randf() < 0.75 else "16_rock_large", Vector3(p.x, isl.height_at(p.x, p.z), p.z), mat, "", rr.randf() * TAU)

## The lowest ground under an obstacle's length (so no edge is left standing proud of the dirt), a touch under.
static func _ground(isl, x: float, mid: float, ln: float) -> float:
	var lo := INF
	for k in 5:
		for sx in [-2.5, 0.0, 2.5]:
			lo = minf(lo, isl.height_at(x + sx, mid - ln * 0.5 + ln * k / 4.0))
	return lo - 0.03

func _obstacle(model: String, at: Vector3, mat: Material, course: String, yaw := 0.0) -> void:
	var ps: PackedScene = load(DIR + model + ".glb")
	if ps == null:
		return
	var n: Node3D = ps.instantiate()
	add_child(n)
	n.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		m.mesh = _painted(m.mesh)
		m.material_override = mat        # (the toon look, like the rest of the island)
		m.visibility_range_end = 260.0
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = m.mesh.create_trimesh_shape()
		sb.add_child(cs)
		m.add_child(sb)
	placed.append({"model": model, "pos": at, "course": course})

## The pack's colours as the toon shader's "painted as-is" (vertex alpha 0.7).
static var _paint_cache := {}
static func _painted(src: Mesh) -> Mesh:
	if _paint_cache.has(src.resource_path + str(src.get_instance_id())):
		return _paint_cache[src.resource_path + str(src.get_instance_id())]
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var a := src.surface_get_arrays(si)
		var cols = a[Mesh.ARRAY_COLOR]
		if cols == null or (cols as PackedColorArray).is_empty():
			cols = PackedColorArray()
			(cols as PackedColorArray).resize((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			(cols as PackedColorArray).fill(Color(0.6, 0.45, 0.32))
		var pc: PackedColorArray = cols
		for i in pc.size():
			pc[i].a = 0.7
		a[Mesh.ARRAY_COLOR] = pc
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	_paint_cache[src.resource_path + str(src.get_instance_id())] = out
	return out

## Boundary tape down both sides of a lane: posts every few metres, a red-and-white strip between them.
func _tape(isl, x: float, z0: float, z1: float, half: float) -> void:
	var mb := MB.new()
	for sd in [-1.0, 1.0]:
		var tx: float = x + sd * half
		var z := z0
		var prev := Vector3.INF
		var i := 0
		while z >= z1:
			var p := Vector3(tx, isl.height_at(tx, z), z)
			mb.box(p + Vector3(0, 0.45, 0), Vector3(0.08, 0.9, 0.08), MB.rgb("e9e2d6"))
			if prev != Vector3.INF:
				var midp := (prev + p) * 0.5 + Vector3(0, 0.78, 0)
				mb.box(midp, Vector3(0.03, 0.08, prev.distance_to(p)), MB.rgb("ff4646") if i % 2 == 0 else MB.rgb("f5f5f5"))
			prev = p
			z -= 3.0
			i += 1
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = game.toon
	mi.visibility_range_end = 220.0
	add_child(mi)

## A start banner over the lane, with the course's name.
func _banner(isl, at: Vector3, label: String) -> void:
	at.y = isl.height_at(at.x, at.z)
	# (the stunt kit's checkpoint gate, the same as the Stunt Yard's, over the start line)
	_piece("checkpoint_gate", at, 0.0, 1.35, "")
	var lb := Label3D.new()
	lb.text = label.to_upper()
	lb.font_size = 72
	lb.pixel_size = 0.01
	lb.outline_size = 12
	lb.modulate = Color("fff4e0")
	lb.position = at + Vector3(0, 6.6, 0.0)
	lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lb.rotation.y = PI          # (read from the south, where you line up)
	add_child(lb)


# ------------------------------------------------------------------ the stunt kit (k_klyo_*)

## One of the kit's pieces: its front (-Z) turned by yaw, scaled, sat at `at`. col: "" none, "mesh" (exact,
## from its own collision mesh if it has one), "box" (its bounds).
func _piece(name: String, at: Vector3, yaw: float, sc: float, col := "mesh") -> Node3D:
	var m: Mesh = M.get_mesh("k_klyo_" + name)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = game.toon
	mi.visibility_range_end = 260.0
	add_child(mi)
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), at)
	mi.global_transform = xf
	if col != "":
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		if col == "box":
			var bx := BoxShape3D.new()
			bx.size = m.get_aabb().size
			cs.shape = bx
			cs.position = m.get_aabb().get_center()
		else:
			var cm: Mesh = M.get_mesh("k_klyo_" + name + "_col") if ResourceLoader.exists("res://assets/kenney/k_klyo_%s_col.res" % name) else m
			cs.shape = cm.create_trimesh_shape()
		sb.add_child(cs)
		mi.add_child(sb)
	return mi

## The Scrapyard's kit sections, each `ln` long centred on `at`, driven north (-Z).
func _kit(kind: String, at: Vector3, ln: float, course: String) -> void:
	var z0 := at.z + ln * 0.5          # where the section starts (its south end)
	match kind:
		"platform_run":
			# up a ramp onto a raised deck two platforms long, and down the far side
			var rl := 6.4 * RAMP_SC
			var pl := 4.1 * PLAT_SC
			_piece("ramp_low", Vector3(at.x, at.y, z0 - rl * 0.5), 0.0, RAMP_SC)
			for k in 2:
				_piece("platform", Vector3(at.x, at.y, z0 - rl - pl * (k + 0.5)), 0.0, PLAT_SC)
			_piece("ramp_low", Vector3(at.x, at.y, z0 - rl - pl * 2.0 - rl * 0.5), PI, RAMP_SC)
		"squeeze":
			# oil drums in two lines: a channel not much wider than the crawler, the full length
			var k := 0
			var zz := z0 - 0.6
			while zz > z0 - ln:
				for sd in [-1.0, 1.0]:
					_piece("steel_drum", Vector3(at.x + sd * 2.15 + randf_range(-0.05, 0.05), at.y, zz), randf() * TAU, 1.6, "box")
				zz -= 1.15
				k += 1
		"boulder":
			# a big rock under one wheel track and smaller ones under the other, staggered: one side climbs, then
			# the other (dead centre the big one's under the belly and you're beached on it)
			_obstacle("16_rock_large", Vector3(at.x + 1.25, at.y, at.z + 1.2), game.toon, course)
			_obstacle("15_rock_small", Vector3(at.x - 1.3, at.y, at.z - 1.6), game.toon, course, 0.4)
			_obstacle("15_rock_small", Vector3(at.x - 1.1, at.y, at.z + 2.8), game.toon, course, 2.1)
		"tunnel":
			_piece("industrial_tunnel", Vector3(at.x, at.y, at.z), 0.0, 1.2)
	placed.append({"model": "k:" + kind, "pos": at, "course": course})

## The park's dressing from the kit: floodlights at the corners, barriers along the south end between the
## start gates, drums by the gates.
func _dress(isl) -> void:
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var p := Vector3(C.x + cx * (HS.x - 1.5), 0, C.y + cz * (HS.y - 1.5))
			p.y = isl.height_at(p.x, p.z)
			_piece("floodlight", p, atan2(cx, cz), 1.4, "box")
	var zb := C.y + START_Z + 9.0
	var bx := []
	for co in COURSES:
		for sd in [-1.0, 1.0]:
			var xb: float = snappedf(C.x + float(co[2]) + sd * 6.75, 0.01)
			if not bx.has(xb):
				bx.append(xb)
	for xb in bx:
		var p2 := Vector3(xb, 0, zb)
		p2.y = isl.height_at(p2.x, p2.z)
		_piece("jersey_barrier", p2, 0.0, 1.4, "box")
	for co in COURSES:
		var x: float = C.x + float(co[2])
		for sd in [-1.0, 1.0]:
			var d := Vector3(x + sd * 6.0, 0, C.y + START_Z + 3.0)
			d.y = isl.height_at(d.x, d.z)
			_piece("steel_drum", d, randf() * TAU, 1.3, "box")
