extends RefCounted
## Stunt spots round town, on the open paved places (car parks, lots, the Bowl, the skate park): grind rails,
## kickers and low ramps from the stunt kit, a boost pad. Tap DRIFT with the wheel straight to bunny hop up
## onto a rail; lined up with it, you lock on and slide along with sparks (drift_car.gd does the riding, main
## scores it like a stunt). Rails are knocked into, not driven through (their own collision layer, which a car
## on one stops colliding with).

const MB := preload("res://scripts/core/mesh_builder.gd")
const Car := preload("res://scripts/game/drift_car.gd")
const RAIL_TOP := 0.42          # a rail's top, above the ground

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
	for sp in SPOTS:
		var kind: String = sp[0]
		var c := Vector2(float(sp[1]), float(sp[2]))
		var dir := Vector2(float(sp[3]), float(sp[4])).normalized()
		c = _find_room(I, kind, c, dir, float(sp[5]))
		if is_nan(c.x):
			print("STUNTS no room near ", Vector2(float(sp[1]), float(sp[2])))
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
	var mi := MeshInstance3D.new()
	mi.name = "RailMeshes"
	mi.mesh = mb.commit()
	mi.material_override = I.mat
	I.add_child(mi)

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
			return I.prop_clear(mid, Vector2(1.6, v * 0.5 + 3.0), yaw) and not _on_road(I, mid, v * 0.5 + 1.0)
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
		if float(nr[0]) < float(rd["w"]) * 0.5 + 3.5 + r:
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
		mb.box(Vector3(p.x, ground + RAIL_TOP * 0.5, p.z), Vector3(0.09, RAIL_TOP, 0.09), steel)
	# the bar: yellow and black bands
	var bas := Basis(Vector3.UP, atan2(-dir.x, -dir.z))
	var seg := 1.1
	var m := int(ceil(l / seg))
	for k in m:
		var p2 := a + dir * minf(seg * (k + 0.5), l - seg * 0.5)
		mb.box(Vector3(p2.x, a.y - 0.05, p2.z), Vector3(0.14, 0.1, seg), MB.rgb("f2c94c") if k % 2 == 0 else MB.rgb("2f2d2a"), bas)
