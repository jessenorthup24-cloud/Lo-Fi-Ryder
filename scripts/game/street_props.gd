extends Node3D
## The bits that make a street look lived in, put where they'd really be: dumpsters round the sides and
## backs of buildings (off the street, against a wall, room to get at them), rubbish bags piled by them,
## loose papers blown about by the bins and along the shopfronts, and benches backed onto shopfronts facing
## the street (clear of doors, ATMs and each other). Placed once, by looking for real walls (tall and wide:
## a building, not a fence or a post), on flat ground in the busy parts of town.

const Flatten := preload("res://scripts/core/flatten.gd")
const Districts := preload("res://scripts/game/districts.gd")

## [file, its widest side on the ground (m), solid box (w, h, d) or none]
const KINDS := {
	"dumpster": ["res://assets/props/street/dumpster.fbx", 2.0, Vector3(2.0, 1.5, 1.15)],
	"rubbish": ["res://assets/props/street/rubbish.glb", 1.3, Vector3.ZERO],
	"papers": ["res://assets/props/street/papers.fbx", 0.9, Vector3.ZERO],
	"bench": ["res://assets/props/street/bench.glb", 1.8, Vector3(1.8, 0.5, 0.6)],
}
## Where to look (the parts of town with buildings), how far round each, and how many of each to put there.
const AREAS := [
	["Downtown", 110.0, 4, 3], ["Town Square", 90.0, 2, 3], ["Palmer Street", 90.0, 2, 2], ["Old Harbour", 90.0, 2, 1],
	["Sunny Bay", 90.0, 2, 2], ["Maple Hills", 80.0, 1, 1], ["Sycamore Heights", 80.0, 1, 1], ["The Courts", 70.0, 1, 1],
]

var game: Node
var placed: Array = []          # {kind, pos, n (the wall's facing)}
var _scenes := {}               # kind: [PackedScene, scale, lift]
var _space: PhysicsDirectSpaceState3D

func build(g: Node) -> void:
	game = g
	_space = get_world_3d().direct_space_state
	for k in KINDS:
		_scenes[k] = _fit(k)
	for a in AREAS:
		for pl in game.island.places:
			if pl["name"] != a[0]:
				continue
			var anchor: Vector3 = pl["pos"]
			# dumpsters round the sides and backs, rubbish and papers by them
			for i in int(a[2]):
				var sp := _wall_spot(anchor, float(a[1]), "side", 30.0)
				if sp.is_empty():
					break
				var n: Vector3 = sp["n"]
				var t := Vector3(n.z, 0, -n.x)
				_put("dumpster", sp["pos"] + n * 0.18, atan2(n.x, n.z))
				if randf() < 0.75:
					_put("rubbish", sp["pos"] + t * (1.75 if randf() < 0.5 else -1.75) + n * 0.15, randf() * TAU)
				for k in randi_range(1, 3):
					_paper(sp["pos"] + n * randf_range(1.2, 3.0) + t * randf_range(-3.0, 3.0))
			# benches backed onto shopfronts, facing the street
			for i in int(a[3]):
				var sp2 := _wall_spot(anchor, float(a[1]), "front", 22.0)
				if sp2.is_empty():
					break
				var n2: Vector3 = sp2["n"]
				_put("bench", sp2["pos"] + n2 * 0.05, atan2(n2.x, n2.z) + PI)          # (the model sits facing -Z: its back to the wall)
				if randf() < 0.5:
					_paper(sp2["pos"] + n2 * randf_range(1.5, 3.0) + Vector3(n2.z, 0, -n2.x) * randf_range(-2.0, 2.0))

## The model scaled to its size, sat on the ground: [scene, scale, lift (to put its bottom at 0)].
func _fit(kind: String) -> Array:
	var ps: PackedScene = load(KINDS[kind][0])
	var n: Node3D = ps.instantiate()
	var box := _bounds(n, Transform3D())
	# its parts made one mesh (a bag of rubbish was 32 draw calls, each time it was put down)
	var flat := Flatten.build(n)
	n.free()
	var w := maxf(box.size.x, box.size.z)
	var sc: float = float(KINDS[kind][1]) / maxf(w, 1e-6)
	return [ps, sc, -box.position.y * sc, box.get_center() * sc, box.size.z > box.size.x * 1.15,
		flat[0] if not flat.is_empty() else null, flat[2] if not flat.is_empty() else GeometryInstance3D.SHADOW_CASTING_SETTING_ON]

static func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var here := xf * ((n as Node3D).transform if n is Node3D else Transform3D())
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = here * (n as MeshInstance3D).get_aabb()
		first = false
	for c in n.get_children():
		var b := _bounds(c, here)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out

func _put(kind: String, at: Vector3, yaw: float) -> void:
	var f: Array = _scenes[kind]
	var m: Node3D
	if f[5] != null:
		m = Node3D.new()
		var one := MeshInstance3D.new()
		one.mesh = f[5]
		one.cast_shadow = f[6]
		m.add_child(one)
	else:
		m = (f[0] as PackedScene).instantiate()
	add_child(m)
	at.y = game.island.height_at(at.x, at.z)
	var c: Vector3 = f[3]
	# (along the wall: a model that's long front to back is turned a quarter)
	var b := Basis(Vector3.UP, yaw + (PI * 0.5 if bool(f[4]) and kind != "papers" and kind != "rubbish" else 0.0))
	# (centred on the spot: the model's own middle, not wherever its origin is)
	m.global_transform = Transform3D(b.scaled(Vector3.ONE * float(f[1])), at + b * Vector3(-c.x, 0, -c.z) + Vector3(0, float(f[2]), 0))
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 70.0 if kind == "papers" else 150.0
		if kind == "papers":
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box: Vector3 = KINDS[kind][2]
	if box != Vector3.ZERO:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = box
		cs.shape = bx
		sb.add_child(cs)
		add_child(sb)
		sb.global_transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, box.y * 0.5, 0))     # (x along the wall)
	placed.append({"kind": kind, "pos": at, "yaw": yaw})

## A sheet or two of paper on the ground (flat, any way round), if it's open flat ground there.
func _paper(at: Vector3) -> void:
	var isl = game.island
	if absf(isl.height_at(at.x, at.z) - isl.height_at(at.x + 0.5, at.z)) > 0.08:
		return
	var h := _ray(Vector3(at.x, isl.height_at(at.x, at.z) + 0.6, at.z), Vector3.DOWN, 0.7)
	if not h.is_empty() and (h["position"] as Vector3).y > isl.height_at(at.x, at.z) + 0.08:
		return          # (on top of something)
	_put("papers", at + Vector3(0, 0.015, 0), randf() * TAU)

func _ray(from: Vector3, d: Vector3, len: float) -> Dictionary:
	return _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + d * len, 1))

## A spot against a building's wall near the anchor. side: "front" (facing onto a street: a bench) or
## "side" (round the side or the back, away from the street: a dumpster). Clear of doors, ATMs, banks and
## anything already put down (sep metres apart).
func _wall_spot(anchor: Vector3, r: float, side: String, sep: float) -> Dictionary:
	var cands: Array = []
	for tries in 260:
		var q := anchor + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * sqrt(randf()) * r
		q.y = game.island.height_at(q.x, q.z)
		var d := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var hit := _ray(q + Vector3(0, 1.0, 0), d, 8.0)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if absf(n.y) > 0.15:
			continue
		n.y = 0.0
		n = n.normalized()
		var c := _fit_wall(hit["position"], n, side, sep)
		if not c.is_empty():
			cands.append(c)
			if cands.size() >= 6:
				break
	if cands.is_empty():
		return {}
	cands.sort_custom(func(a, b): return float(a["score"]) < float(b["score"]))
	return cands[0]

func _fit_wall(w: Vector3, n: Vector3, side: String, sep: float) -> Dictionary:
	var isl = game.island
	var t := Vector3(n.z, 0, -n.x)
	var base := Vector3(w.x, 0, w.z) + n * 0.6
	base.y = isl.height_at(base.x, base.z)
	var half := 1.3
	# a building's wall: still there 3.4 m up, and along it both ways
	for o in [Vector3(0, 3.4, 0), t * half + Vector3(0, 1.0, 0), -t * half + Vector3(0, 1.0, 0), t * half + Vector3(0, 3.0, 0), -t * half + Vector3(0, 3.0, 0)]:
		var h := _ray(base + n * 0.6 + (o as Vector3), -n, 1.8)
		if h.is_empty() or absf((h["normal"] as Vector3).dot(n)) < 0.92:
			return {}
	for o in [Vector3.ZERO, n * 1.8, t * half, -t * half]:
		var pp: Vector3 = base + (o as Vector3)
		if absf(isl.height_at(pp.x, pp.z) - base.y) > 0.25:
			return {}
	for d in [n * 2.2, t * 1.4, -t * 1.4, n * 1.4 + t * 1.2, n * 1.4 - t * 1.2]:
		if not _ray(base + Vector3(0, 0.6, 0), d, 1.0).is_empty():
			return {}
	var me: Array = game.router.nearest_near(Vector2(base.x, base.z), 30.0)
	if int(me[0]) < 0:
		return {}
	var rw: float = float(isl.roads[int(me[0])]["w"]) * 0.5
	var off: float = float(me[2]) - rw
	if off < 1.5:
		return {}          # (not in the road)
	var rp: Vector2 = game.router.road_at(int(me[0]), float(me[1]))
	var to_road := Vector3(rp.x - base.x, 0, rp.y - base.z).normalized()
	var facing := to_road.dot(n)
	var score := 0.0
	if side == "front":
		if facing < 0.6 or off > 9.0:
			return {}          # (a shopfront, on the pavement by the street)
		score = off
	else:
		if facing > 0.35:
			return {}          # (round the side or the back)
		score = -off * 0.2 + randf() * 4.0
	# clear of doors, banks, ATMs and what's already here
	for id in game.shops.shops:
		if base.distance_to(game.shops.shops[id]["door"]) < 5.0:
			return {}
	for b in game.bank.banks:
		if base.distance_to(b["door"]) < 7.0:
			return {}
	for a in game.bank.atms:
		if base.distance_to(a["pos"]) < 4.0:
			return {}
	for p in placed:
		if p["kind"] != "papers" and base.distance_to(p["pos"]) < sep:
			return {}
	return {"pos": base, "n": n, "score": score}
