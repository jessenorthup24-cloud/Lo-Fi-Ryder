extends Node3D
## Town traffic: little cars (Kenney car kit) driving on the right. They follow the roads from junction to
## junction and turn along smooth curves. At a junction they only go when their way across is clear:
## side roads give way to the main road, equal streets take turns, and the junctions on Main Street run
## on traffic lights. They keep their distance, don't pull into a junction they can't get out of, stop
## for you, and U-turn at dead ends. Cars that wander far from you reappear nearer by, out of sight.

const M := preload("res://scripts/core/models.gd")
const MB := preload("res://scripts/core/mesh_builder.gd")

const MODELS := ["k_car_sedan", "k_car_sedan-sports", "k_car_hatchback-sports", "k_car_suv", "k_car_suv-luxury", "k_car_taxi",
	"k_car_van", "k_car_police", "k_car_delivery", "k_car_truck", "k_car_sedan", "k_car_hatchback-sports", "k_car_taxi",
	"k_car_garbage-truck", "k_car_ambulance"]
const SPEED := {"ring": 17.0, "main": 12.5, "road": 14.0, "street": 10.0, "lane": 7.5, "mountain": 11.0}
const COUNT := 36
const TURN_V := 5.5         # m/s round a corner
const GREEN := 9.0          # traffic lights: seconds of green each way...
const CLEAR := 2.5          # ...then all red while the junction empties
const BRAKE := 4.5          # m/s² a car slows at for a stop line
enum { ROAD, TURN }

var island: Node
var mat: Material
var cars: Array = []
var rng := RandomNumberGenerator.new()
var shapes := {}
var honk := Vector3.INF     # where a car honked this frame (main plays it)
var mouths := {}            # "road:dir" -> [[sample, node, arm]]: where a car on that road, going that way, reaches a junction
var busy := {}              # node -> [[car id, in arm, out arm]] cars that have the go-ahead to cross
var paths := {}             # "node:in:out" -> [PackedVector2Array points, PackedFloat32Array lengths]
var conflicts := {}
var clock := 0.0
var heads := []             # traffic light heads {"node", "group", "red", "green"}
var stats := {"crossed": 0, "uturns": 0, "respawns": 0}
var ignore_player := false  # tools: drive as if you weren't there

func setup(isl: Node, material: Material) -> void:
	island = isl
	mat = material
	rng.seed = 5
	for ni in island.nodes.size():
		var nd: Dictionary = island.nodes[ni]
		busy[ni] = []
		for ai in nd["arms"].size():
			var a: Dictionary = nd["arms"][ai]
			var key := "%d:%d" % [a["r"], -int(a["dir"])]
			if not mouths.has(key):
				mouths[key] = []
			mouths[key].append([float(a["s"]), ni, ai])
	_build_lights()
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
		var c := {"id": i, "body": body, "mode": ROAD, "r": 0, "s": 0.0, "dir": 1, "v": 0.0, "len": ab.size.z, "w": ab.size.x,
			"wait": 0.0, "hit": 0.0, "honked": false, "plan": {}, "turn": {}}
		cars.append(c)
		_place_random(c, Vector3(-80, 0, 60), 0.0, 260.0, Vector3.ZERO)

# ------------------------------------------------------------------ where things are

func _road(ri: int) -> Dictionary:
	return island.roads[ri]

func _n(ri: int) -> int:
	return (_road(ri)["pts"] as PackedVector2Array).size()

## The lane on the right of the way you're going, at sample s: [point, heading] (2D)
func _lane(ri: int, s: float, dirn: int) -> Array:
	var r := _road(ri)
	var pts: PackedVector2Array = r["pts"]
	var n := pts.size()
	if r["closed"]:
		s = fposmod(s, float(n))
	else:
		s = clampf(s, 0.0, n - 1.001)
	var k := int(floor(s))
	var k2 := (k + 1) % n
	var p := pts[k].lerp(pts[k2], s - k)
	var t: Vector2 = (pts[k2] - pts[k]).normalized() * dirn
	var right := Vector2(-t.y, t.x)
	return [p + right * float(r["w"]) * 0.25, t]

func _y(p: Vector2) -> float:
	return island.height_at(p.x, p.y) + island.ROAD_LIFT

## The next junction mouth ahead of a car on the road: [samples to go, node, arm], or [] if none.
func _next_mouth(c: Dictionary) -> Array:
	var lst: Array = mouths.get("%d:%d" % [c["r"], c["dir"]], [])
	var best := []
	var n := _n(c["r"])
	var closed: bool = _road(c["r"])["closed"]
	for m in lst:
		var ds: float = (float(m[0]) - float(c["s"])) * int(c["dir"])
		if closed:
			ds = fposmod(ds, float(n))
		if ds >= -0.05 and (best.is_empty() or ds < float(best[0])):
			best = [ds, m[1], m[2]]
	return best

## Samples left before the road runs out (INF on a loop).
func _to_end(c: Dictionary) -> float:
	if _road(c["r"])["closed"]:
		return INF
	return (_n(c["r"]) - 1.0 - float(c["s"])) if int(c["dir"]) > 0 else float(c["s"])

# ------------------------------------------------------------------ junctions

## A way across a junction, sampled: from the in arm's mouth to the out arm's, along a smooth curve.
func _path(ni: int, ai: int, ei: int) -> Array:
	var key := "%d:%d:%d" % [ni, ai, ei]
	if paths.has(key):
		return paths[key]
	var nd: Dictionary = island.nodes[ni]
	var a: Dictionary = nd["arms"][ai]
	var e: Dictionary = nd["arms"][ei]
	var l0 := _lane(a["r"], a["s"], -int(a["dir"]))
	var l3 := _lane(e["r"], e["s"], int(e["dir"]))
	var p0: Vector2 = l0[0]
	var p3: Vector2 = l3[0]
	var h := clampf(p0.distance_to(p3) * 0.42, 1.5, 14.0)
	if ai == ei:
		h = float(a["stop"]) * 0.9     # round the junction and back the way you came
	var pts := _bezier(p0, p0 + (l0[1] as Vector2) * h, p3 - (l3[1] as Vector2) * h, p3, 18)
	paths[key] = pts
	return pts

func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, steps: int) -> Array:
	var pts := PackedVector2Array()
	var cum := PackedFloat32Array()
	for i in steps + 1:
		var t := float(i) / steps
		var u := 1.0 - t
		pts.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
		cum.append(0.0 if i == 0 else cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	return [pts, cum]

## Two ways across a junction that would hit each other.
func _conflict(ni: int, a1: int, e1: int, a2: int, e2: int) -> bool:
	var key := "%d:%d:%d:%d:%d" % [ni, a1, e1, a2, e2]
	if conflicts.has(key):
		return conflicts[key]
	var p1: PackedVector2Array = _path(ni, a1, e1)[0]
	var p2: PackedVector2Array = _path(ni, a2, e2)[0]
	var hit := false
	for q1 in p1:
		for q2 in p2:
			if q1.distance_squared_to(q2) < 2.9 * 2.9:
				hit = true
				break
		if hit:
			break
	conflicts[key] = hit
	return hit

func _choose_exit(ni: int, ai: int) -> int:
	var nd: Dictionary = island.nodes[ni]
	var a: Dictionary = nd["arms"][ai]
	var tin: Vector2 = _lane(a["r"], a["s"], -int(a["dir"]))[1]
	var opts := []
	var total := 0.0
	for ei in nd["arms"].size():
		if ei == ai:
			continue
		var e: Dictionary = nd["arms"][ei]
		if not SPEED.has(_road(e["r"])["kind"]):
			continue
		var tout: Vector2 = _lane(e["r"], e["s"], int(e["dir"]))[1]
		if tin.dot(tout) < -0.45:
			continue    # a hairpin back the way you came: not round here
		var wgt := 3.0 if tin.dot(tout) > 0.85 else 1.6
		opts.append([ei, wgt])
		total += wgt
	if opts.is_empty():
		return ai
	var pick := rng.randf() * total
	for o in opts:
		pick -= float(o[1])
		if pick <= 0.0:
			return o[0]
	return opts[opts.size() - 1][0]

## Who goes first when two ways across cross: straight on and right turns (0), then left turns across
## the oncoming lane (1), then U-turns (2).
func _rank(ni: int, ai: int, ei: int) -> int:
	if ai == ei:
		return 2
	var nd: Dictionary = island.nodes[ni]
	var a: Dictionary = nd["arms"][ai]
	var e: Dictionary = nd["arms"][ei]
	var tin: Vector2 = _lane(a["r"], a["s"], -int(a["dir"]))[1]
	var tout: Vector2 = _lane(e["r"], e["s"], int(e["dir"]))[1]
	return 1 if tin.x * tout.y - tin.y * tout.x < -0.5 else 0

func _turning(ni: int, ai: int, ei: int) -> bool:
	var nd: Dictionary = island.nodes[ni]
	var a: Dictionary = nd["arms"][ai]
	var e: Dictionary = nd["arms"][ei]
	var tin: Vector2 = _lane(a["r"], a["s"], -int(a["dir"]))[1]
	var tout: Vector2 = _lane(e["r"], e["s"], int(e["dir"]))[1]
	return tin.dot(tout) < 0.85

## Which way the lights are green at a junction: 0 along Main Street, 1 across it, -1 all red.
func _green(nd: Dictionary) -> int:
	var t := fmod(clock + float(nd.get("phase", 0.0)), (GREEN + CLEAR) * 2.0)
	if t < GREEN:
		return 0
	if t < GREEN + CLEAR:
		return -1
	if t < GREEN * 2.0 + CLEAR:
		return 1
	return -1

func _last_green(nd: Dictionary) -> int:
	var t := fmod(clock + float(nd.get("phase", 0.0)), (GREEN + CLEAR) * 2.0)
	return 0 if t < GREEN + CLEAR else 1

func _group(arm: Dictionary) -> int:
	return 0 if _road(arm["r"])["kind"] == "main" else 1

## May this car start across the junction now?
func _may_go(c: Dictionary, ni: int, ai: int, ei: int) -> bool:
	var nd: Dictionary = island.nodes[ni]
	var arm: Dictionary = nd["arms"][ai]
	if nd.get("signal", false) and _green(nd) != _group(arm):
		# someone who's been waiting to turn may still clear the junction as the lights change
		if not (_green(nd) == -1 and _last_green(nd) == _group(arm) and float(c["wait"]) > 2.0 and _rank(ni, ai, ei) > 0):
			c["why"] = "red"
			return false
	if not _exit_clear(c, ni, ei):
		c["why"] = "exit"
		return false
	for o in busy[ni]:
		if int(o[0]) == int(c["id"]) or int(o[1]) == ai:
			continue
		if _conflict(ni, ai, ei, o[1], o[2]):
			c["why"] = "crossing %d" % o[0]
			return false
	# turning left across the oncoming lane: let them through first (unless you've waited an age)
	var rank := _rank(ni, ai, ei)
	if rank > 0 and float(c["wait"]) < 12.0:
		for o in cars:
			if o == c or o["mode"] != ROAD or o["plan"].is_empty() or int(o["plan"]["ni"]) != ni or o["plan"]["ok"]:
				continue
			var oai: int = o["plan"]["ai"]
			if oai == ai or _rank(ni, oai, o["plan"]["ei"]) >= rank:
				continue
			if nd.get("signal", false) and _group(nd["arms"][oai]) != _group(arm):
				continue
			var onm := _next_mouth(o)
			if not onm.is_empty() and float(onm[0]) * island.CELL < 22.0 and _conflict(ni, ai, ei, oai, o["plan"]["ei"]):
				c["why"] = "yield %d" % o["id"]
				return false
	if nd.get("signal", false):
		return true
	# a side road gives way to anyone coming along the main road
	if arm["minor"]:
		for o in cars:
			if o == c or o["mode"] != ROAD or o["plan"].is_empty() or int(o["plan"]["ni"]) != ni:
				continue
			var oa: Dictionary = nd["arms"][o["plan"]["ai"]]
			if oa["minor"]:
				continue
			var nm := _next_mouth(o)
			if not nm.is_empty() and float(nm[0]) * island.CELL < 24.0 and float(o["v"]) > 0.5 \
					and _conflict(ni, ai, ei, o["plan"]["ai"], o["plan"]["ei"]):
				c["why"] = "give way %d" % o["id"]
				return false
	# where equal streets cross, whoever has been waiting longest goes first
	if nd.get("all_way", false):
		for o in cars:
			if o != c and o["mode"] == ROAD and not o["plan"].is_empty() and int(o["plan"]["ni"]) == ni and not o["plan"]["ok"] \
					and float(o["wait"]) > float(c["wait"]) + 0.3 and int(o["plan"]["ai"]) != ai \
					and _conflict(ni, ai, ei, o["plan"]["ai"], o["plan"]["ei"]):
				c["why"] = "after %d" % o["id"]
				return false
	return true

## Room to come out the other side (so nobody stops in the middle of a junction).
func _exit_clear(c: Dictionary, ni: int, ei: int) -> bool:
	var e: Dictionary = island.nodes[ni]["arms"][ei]
	var room: float = (float(c["len"]) + 5.0) / island.CELL
	for o in cars:
		if o == c or o["mode"] != ROAD or int(o["r"]) != int(e["r"]) or int(o["dir"]) != int(e["dir"]):
			continue
		var ds: float = (float(o["s"]) - float(e["s"])) * int(e["dir"])
		if ds >= -0.5 and ds < room and float(o["v"]) < 2.0:
			return false
	return true

func _release(c: Dictionary) -> void:
	for ni in busy:
		var lst: Array = busy[ni]
		for i in range(lst.size() - 1, -1, -1):
			if int(lst[i][0]) == int(c["id"]):
				lst.remove_at(i)

# ------------------------------------------------------------------ placing cars

func _place_random(c: Dictionary, near: Vector3, rmin: float, rmax: float, view: Vector3) -> void:
	_release(c)
	var roads: Array = island.roads
	for tries in 60:
		var ri := rng.randi_range(0, roads.size() - 1)
		var r: Dictionary = roads[ri]
		if not SPEED.has(r["kind"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		if pts.size() < 10:
			continue
		var k := rng.randi_range(3, pts.size() - 4)
		var dirn := 1 if rng.randf() < 0.5 else -1
		var l := _lane(ri, float(k), dirn)
		var p: Vector2 = l[0]
		var d := Vector2(near.x, near.z).distance_to(p)
		if d < rmin or d > rmax:
			continue
		# out of sight: behind the camera, or far off
		if view != Vector3.ZERO and d < 160.0:
			var to := Vector3(p.x - near.x, 0, p.y - near.z).normalized()
			if to.dot(view) > -0.1:
				continue
		# not in a junction, and not on top of anyone
		var ok := true
		for nd in island.nodes:
			if (nd["c"] as Vector2).distance_to(p) < 22.0:
				ok = false
				break
		if ok:
			for o in cars:
				var op: Vector3 = (o["body"] as Node3D).global_position
				if o != c and Vector2(op.x, op.z).distance_to(p) < 14.0:
					ok = false
					break
		if not ok:
			continue
		c["mode"] = ROAD
		c["r"] = ri
		c["s"] = float(k)
		c["dir"] = dirn
		c["v"] = SPEED[r["kind"]] * 0.6
		c["plan"] = {}
		c["turn"] = {}
		c["wait"] = 0.0
		c["jumped"] = true
		_put(c)
		stats["respawns"] += 1
		return

func _put(c: Dictionary) -> void:
	var p := Vector2.ZERO
	var t := Vector2(0, -1)
	if c["mode"] == ROAD:
		var l := _lane(c["r"], c["s"], c["dir"])
		p = l[0]
		var l2 := _lane(c["r"], float(c["s"]) + 0.6 * int(c["dir"]), c["dir"])
		t = ((l2[0] as Vector2) - p)
		if t.length() < 0.001:
			t = l[1]
	else:
		var tr: Dictionary = c["turn"]
		var pts: PackedVector2Array = tr["pts"]
		var cum: PackedFloat32Array = tr["cum"]
		var u: float = tr["u"]
		var i := 0
		while i < cum.size() - 2 and cum[i + 1] < u:
			i += 1
		var f := clampf((u - cum[i]) / maxf(cum[i + 1] - cum[i], 0.001), 0.0, 1.0)
		p = pts[i].lerp(pts[i + 1], f)
		t = pts[i + 1] - pts[i]
	t = t.normalized()
	var pos := Vector3(p.x, _y(p), p.y)
	var ahead := Vector3(p.x + t.x, _y(p + t), p.y + t.y)
	(c["body"] as Node3D).global_transform = Transform3D(Basis.looking_at((ahead - pos).normalized(), Vector3.UP), pos)

# ------------------------------------------------------------------ every frame

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

func tick(dt: float, player: Vector3, _player_vel: Vector3, view := Vector3.ZERO) -> void:
	honk = Vector3.INF
	clock += dt
	_lights_tick()
	var heads2 := []
	for c in cars:
		var bn: Node3D = c["body"]
		heads2.append([bn.global_position, -bn.global_transform.basis.z])
	for i in cars.size():
		var c: Dictionary = cars[i]
		var pos: Vector3 = heads2[i][0]
		var fwd: Vector3 = heads2[i][1]
		if pos.distance_to(player) > 280.0:
			_place_random(c, player, 90.0, 220.0, view)
			continue
		var r := _road(c["r"])
		var want: float = SPEED.get(r["kind"], 10.0) if c["mode"] == ROAD else TURN_V
		var look: float = 5.0 + float(c["len"]) * 0.5 + float(c["v"]) * 0.9
		var blocked := false
		var by_you := false
		# where this car is about to drive
		var fut := _future(c, look + 2.0)
		var p2 := Vector2(pos.x, pos.z)
		# you
		var tp := player - pos
		tp.y = 0.0
		if not ignore_player and tp.length() < look + 8.0 and _on_path(fut, Vector2(player.x, player.z), 2.7, p2):
			blocked = true
			by_you = true
		if float(c["hit"]) > 0.0:
			c["hit"] = float(c["hit"]) - dt
			blocked = true
		# someone in the way (if two are in each other's way, the lower number goes first)
		if not blocked:
			for j in cars.size():
				if j == i:
					continue
				var op: Vector3 = heads2[j][0]
				var o2 := Vector2(op.x, op.z)
				if o2.distance_to(p2) > look + 4.0:
					continue
				if not _on_path(fut, o2, 2.15, p2):
					continue
				if j > i and _on_path(_future(cars[j], 5.0 + float(cars[j]["len"]) * 0.5 + float(cars[j]["v"]) * 0.9 + 2.0), p2, 2.15, o2):
					continue
				blocked = true
				c["why"] = "car %d" % j
				break
		if c["mode"] == ROAD:
			want = _approach(c, want)
		if blocked:
			want = 0.0
		if float(c["v"]) < 0.5 and want < 0.5:
			c["wait"] = float(c["wait"]) + dt
			# kept waiting by you: a toot
			if by_you and float(c["wait"]) > 2.5 and not c["honked"] and tp.length() < 30.0:
				c["honked"] = true
				honk = pos
		elif float(c["v"]) > 1.0:
			c["wait"] = 0.0
			c["honked"] = false
		c["v"] = move_toward(c["v"], want, dt * (8.0 if want < float(c["v"]) else 3.0))
		_advance(c, float(c["v"]) * dt)
		_put(c)

## Points (every 1.5 m) along where a car will be driving over the next dist metres.
func _future(c: Dictionary, dist: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var step := 1.5
	var left := dist
	if c["mode"] == ROAD:
		var nm := _next_mouth(c)
		var s0: float = c["s"]
		var to_mouth: float = INF if nm.is_empty() else float(nm[0]) * island.CELL
		var d := step
		while d <= minf(left, to_mouth):
			out.append(_lane(c["r"], s0 + int(c["dir"]) * d / island.CELL, c["dir"])[0])
			d += step
		if nm.is_empty() or d <= to_mouth or not c["plan"].get("ok", false):
			return out
		left -= to_mouth
		var pth := _path(c["plan"]["ni"], c["plan"]["ai"], c["plan"]["ei"])
		var pts: PackedVector2Array = pth[0]
		var cum: PackedFloat32Array = pth[1]
		for k in pts.size():
			if cum[k] > left:
				break
			out.append(pts[k])
		return out
	var tr: Dictionary = c["turn"]
	var pts2: PackedVector2Array = tr["pts"]
	var cum2: PackedFloat32Array = tr["cum"]
	var u: float = tr["u"]
	for k in pts2.size():
		if cum2[k] <= u:
			continue
		if cum2[k] - u > left:
			return out
		out.append(pts2[k])
	if not tr.get("uturn", false):
		left -= cum2[cum2.size() - 1] - u
		var e: Dictionary = island.nodes[tr["ni"]]["arms"][tr["to"]]
		var d2 := step
		while d2 <= left:
			out.append(_lane(e["r"], float(e["s"]) + int(e["dir"]) * d2 / island.CELL, e["dir"])[0])
			d2 += step
	return out

## Is q within r of the path ahead (and actually ahead of from)?
func _on_path(fut: PackedVector2Array, q: Vector2, r: float, from: Vector2) -> bool:
	var r2 := r * r
	for p in fut:
		if p.distance_squared_to(q) < r2:
			return from.distance_squared_to(q) > 1.0
	return false

## Slowing for (and waiting at) the next junction or the end of the road. Returns the speed to aim for.
func _approach(c: Dictionary, want: float) -> float:
	var nm := _next_mouth(c)
	var half: float = float(c["len"]) * 0.5 + 0.4
	if nm.is_empty():
		# a dead end: slow down and turn round
		var te: float = _to_end(c) * island.CELL
		if te < 30.0:
			want = minf(want, maxf(3.0, te * 0.4))
		return want
	var ni: int = nm[1]
	var ai: int = nm[2]
	var d_m: float = float(nm[0]) * island.CELL
	if c["plan"].is_empty() or int(c["plan"]["ni"]) != ni or int(c["plan"]["ai"]) != ai:
		c["plan"] = {"ni": ni, "ai": ai, "ei": _choose_exit(ni, ai), "ok": false}
	var plan: Dictionary = c["plan"]
	if _turning(ni, ai, plan["ei"]):
		want = minf(want, TURN_V + maxf(d_m - 6.0, 0.0) * 0.35)
	if not plan["ok"]:
		var stop_at := d_m - half
		var v: float = c["v"]
		if stop_at < v * v / (2.0 * BRAKE) + 8.0:
			if _may_go(c, ni, ai, plan["ei"]):
				plan["ok"] = true
				busy[ni].append([c["id"], ai, plan["ei"]])
		if not plan["ok"]:
			want = minf(want, sqrt(maxf(0.0, 2.0 * BRAKE * maxf(stop_at - 0.2, 0.0))))
			if stop_at < 0.3:
				want = 0.0
	return want

func _advance(c: Dictionary, dist: float) -> void:
	if c["mode"] == ROAD:
		var nm := _next_mouth(c)
		var ds: float = dist / island.CELL
		if not nm.is_empty() and c["plan"].get("ok", false) and float(nm[0]) <= ds:
			# into the junction
			var plan: Dictionary = c["plan"]
			var pth := _path(plan["ni"], plan["ai"], plan["ei"])
			c["mode"] = TURN
			c["turn"] = {"pts": pth[0], "cum": pth[1], "u": 0.0, "ni": plan["ni"], "to": plan["ei"]}
			stats["crossed"] += 1
			return
		if nm.is_empty() and _to_end(c) <= ds + 0.6:
			# turn round at the end of the road
			var l0 := _lane(c["r"], c["s"], c["dir"])
			var l3 := _lane(c["r"], c["s"], -int(c["dir"]))
			var pth := _bezier(l0[0], (l0[0] as Vector2) + (l0[1] as Vector2) * 4.5, (l3[0] as Vector2) - (l3[1] as Vector2) * 4.5, l3[0], 14)
			c["mode"] = TURN
			c["turn"] = {"pts": pth[0], "cum": pth[1], "u": 0.0, "ni": -1, "uturn": true}
			stats["uturns"] += 1
			return
		c["s"] = float(c["s"]) + int(c["dir"]) * ds
		if _road(c["r"])["closed"]:
			c["s"] = fposmod(c["s"], float(_n(c["r"])))
	else:
		var tr: Dictionary = c["turn"]
		tr["u"] = float(tr["u"]) + dist
		var cum: PackedFloat32Array = tr["cum"]
		if float(tr["u"]) >= cum[cum.size() - 1]:
			# out the other side
			if tr.get("uturn", false):
				c["dir"] = -int(c["dir"])
			else:
				var e: Dictionary = island.nodes[tr["ni"]]["arms"][tr["to"]]
				c["r"] = e["r"]
				c["s"] = float(e["s"])
				c["dir"] = int(e["dir"])
				_release(c)
			c["mode"] = ROAD
			c["plan"] = {}
			c["turn"] = {}

# ------------------------------------------------------------------ traffic lights

func _build_lights() -> void:
	var post := MB.new()
	for ni in island.nodes.size():
		var nd: Dictionary = island.nodes[ni]
		if not nd.get("signal", false):
			continue
		for ai in nd["arms"].size():
			var a: Dictionary = nd["arms"][ai]
			# on the kerb at the right of the cars coming in, just before the stop line, facing them
			var l := _lane(a["r"], a["s"], -int(a["dir"]))
			var t: Vector2 = l[1]
			var right := Vector2(-t.y, t.x)
			var mouth := (l[0] as Vector2) - right * float(_road(a["r"])["w"]) * 0.25
			var p := mouth + right * (float(a["hw"]) + 0.55) - t * 0.6
			var y: float = island.height_at(p.x, p.y)
			var b := Basis.looking_at(Vector3(-t.x, 0, -t.y), Vector3.UP)
			post.cyl(Vector3(p.x, y, p.y), 0.09, 3.3, MB.rgb("4a4d52"), 8)
			var hp := Vector3(p.x, y + 3.0, p.y)
			post.box(hp, Vector3(0.42, 1.05, 0.3), MB.rgb("2b2d31"), b)
			var lamps := {}
			for nm in ["red", "amber", "green"]:
				var dy: float = {"red": 0.3, "amber": 0.0, "green": -0.3}[nm]
				var lp := hp + Vector3(0, dy, 0) + b * Vector3(0, 0, -0.16)
				post.box(lp, Vector3(0.24, 0.24, 0.04), MB.rgb("17181a"), b)
				if nm == "amber":
					continue
				var on := MB.new()
				on.box(lp + b * Vector3(0, 0, -0.025), Vector3(0.22, 0.22, 0.03), MB.glow("ff4b3e" if nm == "red" else "54e08a"), b)
				var mi := MeshInstance3D.new()
				mi.mesh = on.commit()
				mi.material_override = mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				lamps[nm] = mi
			heads.append({"node": ni, "group": _group(a), "red": lamps["red"], "green": lamps["green"]})
			island.add_cyl_collider(Vector3(p.x, y, p.y), 0.15, 3.3)
	if not post.is_empty():
		var pm := MeshInstance3D.new()
		pm.mesh = post.commit()
		pm.material_override = mat
		add_child(pm)

func _lights_tick() -> void:
	for h in heads:
		var go: bool = _green(island.nodes[h["node"]]) == int(h["group"])
		(h["green"] as Node3D).visible = go
		(h["red"] as Node3D).visible = not go
