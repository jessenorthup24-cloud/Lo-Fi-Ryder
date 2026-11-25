extends RefCounted
## Stunt spots round town, on the open paved places (car parks, lots, the Bowl, the skate park): grind rails,
## kickers and low ramps from the stunt kit, a boost pad. Tap DRIFT with the wheel straight to bunny hop up
## onto a rail; lined up with it, you lock on and slide along with sparks (drift_car.gd does the riding, main
## scores it like a stunt). Rails are knocked into, not driven through (their own collision layer, which a car
## on one stops colliding with).

const MB := preload("res://scripts/core/mesh_builder.gd")
const Car := preload("res://scripts/game/drift_car.gd")
const RAIL_TOP := 0.5           # a rail's top, above the ground
const MAX_RAILS := 26
const RAIL_GAP := 45.0           # no two rails closer than this (mid to mid)

## [kind, x, z, dir x, dir z, length (rails) or scale]: rails run along dir; ramps rise along it
const SPOTS := [
	# the beach car park
	["kicker", 78, 384, -1, 0, 1.0],
	# the Drift Bowl
	["rail", 140, 178, 1, 0, 28.0], ["pad", 224, 226, -1, 0, 1.0], ["kicker", 207, 226, -1, 0, 1.2], ["low", 140, 236, 1, 0, 1.3],
	# the harbour lot
	["rail", -424, 146, 1, 0, 20.0], ["kicker", -372, 176, 0, -1, 1.0],
	# the skate park
	["rail", 56, 80, 1, 0, 16.0],
	# the Courts' parking court
	["rail", -12, -161, 1, 0, 18.0],
	# the farmyard
	["low", 252, -20, -1, 0, 1.2],
	# the stunt yard's own run-up gets a long rail too
	["rail", -232, 222, 1, 0, 26.0],
]

static func populate(I, D) -> void:
	var body := StaticBody3D.new()
	body.name = "Rails"
	body.collision_layer = Car.RAIL_LAYER
	body.collision_mask = 0
	I.add_child(body)
	var mb := MB.new()
	var spots: Array = SPOTS.duplicate()
	spots.append_array(_lot_spots(I))
	spots.append_array(_roadside_spots(I))
	var mids: Array = []
	for sp in spots:
		var kind: String = sp[0]
		var c := Vector2(float(sp[1]), float(sp[2]))
		var dir := Vector2(float(sp[3]), float(sp[4])).normalized()
		var hand: bool = (sp as Array).size() < 7          # (the hand-placed ones: look about; the lot ones: there or nowhere)
		if kind == "rail" and I.rails.size() >= MAX_RAILS:
			continue
		if kind == "rail" and not hand:
			var mid0 := c + dir * float(sp[5]) * 0.5
			var near := false
			for m in mids:
				if (m as Vector2).distance_to(mid0) < RAIL_GAP:
					near = true
			if near or not _ok(I, kind, c, dir, atan2(-dir.x, -dir.y), float(sp[5])):
				if OS.get_cmdline_user_args().has("--railwhy") and not near:
					var why := "props" if not I.prop_clear(c + dir * float(sp[5]) * 0.5, Vector2(1.6, float(sp[5]) * 0.5 + 3.0), atan2(-dir.x, -dir.y)) else "road/flat"
					print("RAILWHY ", c, " l=", sp[5], " ", why)
				continue
		else:
			c = _find_room(I, kind, c, dir, float(sp[5]))
			if is_nan(c.x):
				if hand:
					print("STUNTS no room near ", Vector2(float(sp[1]), float(sp[2])))
				continue
		if kind == "rail" and hand:
			for m in mids:
				if (m as Vector2).distance_to(c + dir * float(sp[5]) * 0.5) < 12.0:
					c = Vector2(NAN, NAN)
			if is_nan(c.x):
				continue
		match kind:
			"rail":
				var l: float = sp[5]
				var mid := c + dir * l * 0.5
				var yaw := atan2(-dir.x, -dir.y)
				var y: float = maxf(I.height_at(c.x, c.y), I.height_at(c.x + dir.x * l, c.y + dir.y * l))
				var a := Vector3(c.x, y + RAIL_TOP, c.y)
				var b := Vector3(c.x + dir.x * l, y + RAIL_TOP, c.y + dir.y * l)
				_rail_mesh(mb, a, b, y)
				var cs := CollisionShape3D.new()
				var bx := BoxShape3D.new()
				bx.size = Vector3(0.18, RAIL_TOP, l)
				cs.shape = bx
				cs.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, y + RAIL_TOP * 0.5, mid.y))
				body.add_child(cs)
				I.rails.append([a, b])
				mids.append(mid)
				I.block_rect(mid, Vector2(0.6, l * 0.5 + 0.5), yaw, 0.5)
			"kicker", "low":
				var nm := "k_klyo_ramp_kicker" if kind == "kicker" else "k_klyo_ramp_low"
				var sc: float = sp[5]
				var yaw2 := atan2(-dir.x, -dir.y)
				var hs := Vector2(2.4, 4.3) * sc
				D._piece(I, nm, c, dir, sc, I.height_at(c.x, c.y))
				I.block_rect(c, hs, yaw2, 0.5)
			"pad":
				D._pad(I, c, dir, I.height_at(c.x, c.y))
	print("STUNTS %d rails" % I.rails.size())
	_map_marks(I)
	var mi := MeshInstance3D.new()
	mi.name = "RailMeshes"
	mi.mesh = mb.commit()
	mi.material_override = I.mat
	I.add_child(mi)

## A rail down the middle of each big enough paved lot (car parks, yards, squares), along its long side, and
## a second, offset, on the biggest. Marked [.., "lot"] so they're tried just where they are.
static func _lot_spots(I) -> Array:
	var out := []
	for lt in I.lots:
		if not (int(lt["surf"]) in [I.S_ASPHALT, I.S_CONCRETE, I.S_WOOD, I.S_COBBLE]):
			continue
		var hs: Vector2 = lt["hs"]
		var c: Vector2 = lt["c"]
		var yaw: float = lt["yaw"]
		var long := maxf(hs.x, hs.y)
		if minf(hs.x, hs.y) < 5.0 or long < 9.0:
			continue
		# the lot's long axis, in the world
		var ax := Vector2(1, 0) if hs.x >= hs.y else Vector2(0, 1)
		var dir := ax.rotated(-yaw)
		var side := Vector2(-dir.y, dir.x)
		var l0 := clampf(long * 2.0 - 10.0, 10.0, 26.0)
		for l in [l0, l0 * 0.7, 10.0]:
			for off in ([0.0, -minf(hs.x, hs.y) * 0.45, minf(hs.x, hs.y) * 0.45] if minf(hs.x, hs.y) > 12.0 else [0.0, -2.5, 2.5]):
				var st: Vector2 = c + side * off - dir * float(l) * 0.5
				out.append(["rail", st.x, st.y, dir.x, dir.y, float(l), "lot"])
	return out

## Rails along the side of the streets, a few metres past the kerb, running with the road: you see them as
## you drive by, and can hop straight off the road onto one. Only on straight stretches, and only where it's
## flat and clear (no houses, trees, lamp posts, or another road).
static func _roadside_spots(I) -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	for rd in I.roads:
		if not (String(rd["kind"]) in ["street", "main", "road", "avenue", "coast"]):
			continue
		var pts: PackedVector2Array = rd["pts"]
		var w: float = rd["w"]
		var acc := rng.randf_range(10.0, 50.0)
		for k in range(1, pts.size() - 1):
			var seg: Vector2 = pts[k + 1] - pts[k]
			acc += seg.length()
			if acc < 70.0:
				continue
			# straight here? (the road a few points on goes the same way)
			var k2 := mini(k + 6, pts.size() - 1)
			var ahead: Vector2 = pts[k2] - pts[k]
			if ahead.length() < 14.0 or ahead.normalized().dot(seg.normalized()) < 0.985:
				continue
			acc = 0.0
			var dir := ahead.normalized()
			var nrm := Vector2(-dir.y, dir.x)
			for sd in [1.0, -1.0]:
				var st: Vector2 = pts[k] + nrm * sd * (w * 0.5 + 6.5)
				out.append(["rail", st.x, st.y, dir.x, dir.y, 14.0, "lot"])
	return out

## The rails on the minimap: yellow dashes, so you can find them.
static func _map_marks(I) -> void:
	if I.rails.is_empty() or I.get("map_root") == null:
		return
	var mb := MB.new()
	for r in I.rails:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		var m := (a + b) * 0.5
		var d := b - a
		mb.box(Vector3(m.x, 0.5, m.z), Vector3(3.2, 0.1, d.length() + 2.0), MB.rgb("ffd23f"), Basis(Vector3.UP, atan2(-d.x, -d.z)))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	var um := StandardMaterial3D.new()
	um.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	um.vertex_color_use_as_albedo = true
	um.vertex_color_is_srgb = true
	mi.material_override = um
	mi.layers = I.MAP_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 300.0
	mi.name = "MapRails"
	(I.map_root as Node).add_child(mi)

## The spot, or the nearest clear patch within 14 m of it (NAN if none): flat, no props, off the roads.
static func _find_room(I, kind: String, c: Vector2, dir: Vector2, v: float) -> Vector2:
	var yaw := atan2(-dir.x, -dir.y)
	for r in [0.0, 3.0, 6.0, 9.0, 12.0, 14.0]:
		var n: int = 1 if r == 0.0 else 8
		for k in n:
			var a := TAU * k / n
			var p: Vector2 = c + Vector2(cos(a), sin(a)) * r
			if _ok(I, kind, p, dir, yaw, v):
				return p
	return Vector2(NAN, NAN)

static func _ok(I, kind: String, c: Vector2, dir: Vector2, yaw: float, v: float) -> bool:
	match kind:
		"rail":
			var mid := c + dir * v * 0.5
			var b := c + dir * v
			if absf(I.height_at(c.x, c.y) - I.height_at(b.x, b.y)) > 0.12 or absf(I.height_at(mid.x, mid.y) - I.height_at(c.x, c.y)) > 0.12:
				return false
			# clear beside it, and a good run-out off each end (you come off fast)
			if not I.prop_clear(mid, Vector2(1.6, v * 0.5 + 3.0), yaw) or not I.prop_clear(mid, Vector2(0.9, v * 0.5 + 12.0), yaw):
				return false
			for k in 5:
				if _on_road(I, c + dir * v * k / 4.0, 0.0):
					return false
			return true
		"kicker", "low":
			var hs := Vector2(2.4, 4.3) * v
			var run := c - dir * 10.0     # a clear run-up too
			return I.prop_clear(c, hs, yaw) and I.prop_clear(run, Vector2(2.0, 5.0), yaw) and not _on_road(I, c, hs.length())
		"pad":
			return I.prop_clear(c, Vector2(2.0, 3.0), yaw)
	return true

## Too near a road to put something solid down (the lots are fine).
static func _on_road(I, p: Vector2, r: float) -> bool:
	for rd in I.roads:
		var nr: Array = I.road_nearest(I.roads.find(rd), p)
		if float(nr[0]) < float(rd["w"]) * 0.5 + 3.0 + r:
			return true
	return false

## A rail: yellow-capped steel on posts every couple of metres, end posts each end.
static func _rail_mesh(mb, a: Vector3, b: Vector3, ground: float) -> void:
	var l := Vector2(b.x - a.x, b.z - a.z).length()
	var dir := (b - a) / maxf(l, 0.01)
	var n := int(ceil(l / 2.2))
	var steel := MB.rgb("8d949c")
	for k in n + 1:
		var p := a + dir * (l * k / n)
		mb.box(Vector3(p.x, ground + RAIL_TOP * 0.5, p.z), Vector3(0.13, RAIL_TOP, 0.13), steel)
		mb.box(Vector3(p.x, ground + 0.02, p.z), Vector3(0.4, 0.04, 0.4), MB.rgb("2f2d2a"))
	# a marker pole beside each end (no collider: just so you spot them from down the street)
	var side := Vector3(-dir.z, 0, dir.x)
	for e in [a, b]:
		var mp: Vector3 = e + side * 1.9
		mb.box(Vector3(mp.x, ground + 0.8, mp.z), Vector3(0.1, 1.6, 0.1), MB.rgb("2f2d2a"))
		mb.box(Vector3(mp.x, ground + 1.45, mp.z), Vector3(0.16, 0.3, 0.16), MB.rgb("ffd23f"))
		mb.box(Vector3(mp.x, ground + 1.15, mp.z), Vector3(0.16, 0.3, 0.16), MB.rgb("ffd23f"))
	# the bar: yellow and black bands
	var bas := Basis(Vector3.UP, atan2(-dir.x, -dir.z))
	var seg := 1.1
	var m := int(ceil(l / seg))
	for k in m:
		var p2 := a + dir * minf(seg * (k + 0.5), l - seg * 0.5)
		mb.box(Vector3(p2.x, a.y - 0.07, p2.z), Vector3(0.2, 0.14, seg), MB.rgb("ffd23f") if k % 2 == 0 else MB.rgb("2f2d2a"), bas)
