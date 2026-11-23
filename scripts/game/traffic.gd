extends Node3D
## Town traffic: little cars (Kenney car kit) driving the roads on the right-hand side. They keep their
## distance, wait their turn where roads cross, stop for you, and turn onto another road at the end of
## one. Cars that wander far from you quietly reappear on a road nearer by, so there's always traffic.

const M := preload("res://scripts/core/models.gd")

const MODELS := ["k_car_sedan", "k_car_sedan-sports", "k_car_hatchback-sports", "k_car_suv", "k_car_suv-luxury", "k_car_taxi",
	"k_car_van", "k_car_police", "k_car_delivery", "k_car_truck", "k_car_sedan", "k_car_hatchback-sports", "k_car_taxi",
	"k_car_garbage-truck", "k_car_ambulance"]
const SPEED := {"ring": 17.0, "main": 12.5, "road": 14.0, "street": 10.0, "lane": 7.5, "mountain": 11.0}
const COUNT := 36

var island: Node
var mat: Material
var cars: Array = []
var ends := {}          # "road:end" -> [[road index, sample, dir], ...] where you can carry on
var rng := RandomNumberGenerator.new()
var shapes := {}
var honk := Vector3.INF     # where a car honked this frame (main plays it)

func setup(isl: Node, material: Material) -> void:
	island = isl
	mat = material
	rng.seed = 5
	_link_roads()
	for i in COUNT:
		var nm: String = MODELS[i % MODELS.size()]
		var mi := MeshInstance3D.new()
		mi.mesh = M.get_mesh(nm)
		mi.material_override = mat
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		body.collision_layer = 2
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var ab: AABB = mi.mesh.get_aabb()
		if not shapes.has(nm):
			var b := BoxShape3D.new()
			b.size = ab.size * Vector3(0.9, 0.8, 0.95)
			shapes[nm] = b
		cs.shape = shapes[nm]
		cs.position = ab.get_center()
		body.add_child(cs)
		body.add_child(mi)
		add_child(body)
		var c := {"id": i, "body": body, "r": 0, "s": 0.0, "dir": 1, "v": 0.0, "len": ab.size.z, "wait": 0.0, "hit": 0.0, "honked": false}
		cars.append(c)
		_place_random(c, Vector3(-80, 0, 60), 0.0, 260.0)

## Which roads you can turn onto from the end of each road.
func _link_roads() -> void:
	var roads: Array = island.roads
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		if r["closed"] or not SPEED.has(r["kind"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		for e in [0, pts.size() - 1]:
			var p := pts[e]
			var opts := []
			for rj in roads.size():
				if rj == ri or not SPEED.has(roads[rj]["kind"]):
					continue
				var op: PackedVector2Array = roads[rj]["pts"]
				var best := -1
				var bd := 64.0
				for k in op.size():
					var d := op[k].distance_squared_to(p)
					if d < bd:
						bd = d
						best = k
				if best >= 0:
					var n := op.size()
					if roads[rj]["closed"] or best < n - 3:
						opts.append([rj, best, 1])
					if roads[rj]["closed"] or best > 2:
						opts.append([rj, best, -1])
			ends["%d:%d" % [ri, e]] = opts

func _place_random(c: Dictionary, near: Vector3, rmin: float, rmax: float) -> void:
	var roads: Array = island.roads
	for tries in 40:
		var ri := rng.randi_range(0, roads.size() - 1)
		var r: Dictionary = roads[ri]
		if not SPEED.has(r["kind"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		var k := rng.randi_range(2, pts.size() - 3)
		var d := Vector2(near.x, near.z).distance_to(pts[k])
		if d < rmin or d > rmax:
			continue
		var dirn := 1 if rng.randf() < 0.5 else -1
		# don't drop it on top of someone
		var p := _pos(ri, float(k), dirn)
		var clear := true
		for o in cars:
			if o != c and (o["body"] as Node3D).global_position.distance_to(p) < 12.0:
				clear = false
				break
		if not clear:
			continue
		c["r"] = ri
		c["s"] = float(k)
		c["dir"] = dirn
		c["v"] = SPEED[r["kind"]] * 0.6
		_put(c)
		return

## Where a car is: the lane on the right of the way it's going.
func _pos(ri: int, s: float, dirn: int) -> Vector3:
	var r: Dictionary = island.roads[ri]
	var pts: PackedVector2Array = r["pts"]
	var n := pts.size()
	var k := clampi(int(floor(s)), 0, n - 1)
	var k2 := (k + 1) % n if r["closed"] else mini(k + 1, n - 1)
	var f: float = s - floor(s)
	var p := pts[k].lerp(pts[k2], f)
	var t: Vector2 = (pts[k2] - pts[k]).normalized() if k2 != k else island._tangent(pts, k, r["closed"])
	var d := t * dirn
	var right := Vector2(-d.y, d.x)
	var off: float = float(r["w"]) * 0.25
	var q := p + right * off
	return Vector3(q.x, island.height_at(q.x, q.y) + island.ROAD_LIFT, q.y)

func _put(c: Dictionary) -> void:
	var r: Dictionary = island.roads[c["r"]]
	var p := _pos(c["r"], c["s"], c["dir"])
	var ahead := _pos(c["r"], c["s"] + 1.2 * c["dir"], c["dir"])
	var fwd := ahead - p
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, -1)
	var b := Basis.looking_at(fwd.normalized(), Vector3.UP)
	(c["body"] as Node3D).global_transform = Transform3D(b, p)

## You ran into someone: they stop for a few seconds (and let you know about it).
func hit(p: Vector3) -> bool:
	for c in cars:
		var bn: Node3D = c["body"]
		if bn.global_position.distance_to(p) < float(c["len"]) * 0.5 + 3.6:
			if float(c["hit"]) <= 0.0:
				honk = bn.global_position
			c["hit"] = 3.5
			c["v"] = 0.0
			return true
	return false

func tick(dt: float, player: Vector3, player_vel: Vector3) -> void:
	honk = Vector3.INF
	# where everyone is heading next
	var heads := []
	for c in cars:
		var bn: Node3D = c["body"]
		var fwd := -bn.global_transform.basis.z
		heads.append([bn.global_position, fwd])
	for i in cars.size():
		var c: Dictionary = cars[i]
		var r: Dictionary = island.roads[c["r"]]
		var pos: Vector3 = heads[i][0]
		var fwd: Vector3 = heads[i][1]
		# far from you: come back somewhere nearer
		if pos.distance_to(player) > 280.0:
			_place_random(c, player, 90.0, 220.0)
			continue
		var want: float = SPEED.get(r["kind"], 10.0)
		var look: float = 6.0 + c["len"] * 0.5 + float(c["v"]) * 0.9
		var blocked := false
		var by_you := false
		# you
		var tp := player - pos
		tp.y = 0.0
		var ahead_d := tp.dot(fwd)
		if ahead_d > 0.0 and ahead_d < look + 4.0 and absf(tp.dot(Vector3(-fwd.z, 0, fwd.x))) < 3.2:
			blocked = true
			by_you = true
		if float(c["hit"]) > 0.0:
			c["hit"] = float(c["hit"]) - dt
			blocked = true
		# other cars (the lower number goes first if two are waiting on each other)
		if not blocked:
			for j in cars.size():
				if j == i:
					continue
				var op: Vector3 = heads[j][0]
				var rel := op - pos
				rel.y = 0.0
				var ad := rel.dot(fwd)
				if ad <= 0.0 or ad > look:
					continue
				if absf(rel.dot(Vector3(-fwd.z, 0, fwd.x))) > 3.0:
					continue
				var ofwd: Vector3 = heads[j][1]
				var back := -rel
				var they_see_me: bool = back.dot(ofwd) > 0.0 and back.dot(ofwd) < look and absf(back.dot(Vector3(-ofwd.z, 0, ofwd.x))) < 3.0
				if they_see_me and i < j:
					continue
				blocked = true
				break
		if blocked:
			want = 0.0
			c["wait"] += dt
			# kept waiting by you: a toot
			if by_you and float(c["wait"]) > 2.5 and not c["honked"] and tp.length() < 30.0:
				c["honked"] = true
				honk = pos
		else:
			c["wait"] = 0.0
			c["honked"] = false
		c["v"] = move_toward(c["v"], want, dt * (7.0 if want < c["v"] else 3.0))
		c["s"] += float(c["dir"]) * float(c["v"]) * dt / island.CELL
		var n: int = (r["pts"] as PackedVector2Array).size()
		if r["closed"]:
			c["s"] = fposmod(c["s"], float(n))
		elif c["s"] < 0.0 or c["s"] > n - 1.0:
			_next_road(c, 0 if c["s"] < 0.0 else n - 1)
		_put(c)

## At the end of a road: carry on along another one (or turn round if it's a dead end).
func _next_road(c: Dictionary, end: int) -> void:
	var opts: Array = ends.get("%d:%d" % [c["r"], end], [])
	if opts.is_empty():
		c["dir"] = -int(c["dir"])
		c["s"] = clampf(c["s"], 0.0, float((island.roads[c["r"]]["pts"] as PackedVector2Array).size() - 1))
		return
	var o: Array = opts[rng.randi_range(0, opts.size() - 1)]
	c["r"] = o[0]
	c["s"] = float(o[1]) + 0.5 * int(o[2])
	c["dir"] = o[2]
