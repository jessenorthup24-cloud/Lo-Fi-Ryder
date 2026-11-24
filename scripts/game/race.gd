extends Node3D
## A street race: you and seven CPU drivers round a loop of the town's streets.
## The course is the corners of the loop (junction centres) with each corner rounded off into an arc; that
## smoothed line is the racing line, sampled every metre, with a speed for each metre worked out from how
## tight it bends (and how far ahead you need to brake). It's painted on the road as chevrons (blue: on the
## power, amber: the corner, red: brake), checkpoints stand across it as arches, and it's drawn on the map.
## The CPU drivers are real cars (drift_car.gd) on the same physics as you: they steer for a point ahead on
## the line (each in its own lane, moving over to pass), and hold the speed the line asks for.

const Car := preload("res://scripts/game/drift_car.gd")
const CARS := preload("res://scripts/game/cars.gd")
const M := preload("res://scripts/core/models.gd")
const MB := preload("res://scripts/core/mesh_builder.gd")

const A_LAT := 8.0          # m/s² round a corner (what these cars hold, gripping)
const A_BRAKE := 7.0
const A_ACC := 4.5
const V_MAX := 40.0
const CORNER_R := 8.0       # the street centre's corners are rounded this much (the racing line then uses the width)
const LINE_W := 3.0         # how far either side of the street's centre the racing line goes
const ROOM := 3.5           # and the furthest a car's middle goes from the centre (passing, the grid)
const CP_GAP := 75.0        # metres between checkpoints
const NAMES := ["Ruby", "Dash", "Mika", "Juno", "Oz", "Pepper", "Sol", "Kit", "Remy", "Tess"]
const AI_LAYER := 8

var game
var island
var def: Dictionary
var pts := PackedVector2Array()     # the racing line, a point every metre round the loop
var ctr := PackedVector2Array()     # the middle of the street alongside each of those points
var offs := PackedFloat32Array()    # how far the line is from the middle there (+ right)
var speed := PackedFloat32Array()   # how fast to take each metre (m/s)
var length := 0.0
var start_s := 0.0                  # the start/finish line (metres round the loop)
var cps: Array = []                 # checkpoints, metres round the loop from the start line
var gates: Array = []
var line_mi: MeshInstance3D
var racers: Array = []              # {car, name, ai, s, lane, lane_now, skill, stuck, off, flip, done, last_cp}
var state := 0                      # 0 countdown, 1 racing, 2 you've finished
var t := 0.0                        # race clock
var count := 3.5
var finished: Array = []            # racers in the order they crossed the line
var you: Dictionary
var wrong_t := 0.0
var away_t := 0.0
var laps := 3

# ---------------------------------------------------------------- the course

func setup(g, isl, d: Dictionary) -> void:
	game = g
	island = isl
	def = d
	laps = int(d.get("laps", 3))
	# the corners are junctions: use their exact centres, so the line runs down the middle of each street
	var corners: Array = []
	for q in d["corners"]:
		var best: Vector2 = q
		var bd := 18.0
		for nd in island.nodes:
			var nc: Vector2 = nd["c"]
			if nc.distance_to(q) < bd:
				bd = nc.distance_to(q)
				best = nc
		corners.append(best)
	_build_line(corners)
	# the start line: where the course passes start_x on its first straight
	var sx: Vector2 = d["start"]
	start_s = _nearest_s(sx, 0.0, length)
	var n := int(length / CP_GAP)
	for k in range(1, n):
		cps.append(length * k / n)
	cps.append(length)          # the line itself, every lap
	_paint_line()
	_build_gates()

func _build_line(corners: Array) -> void:
	var n := corners.size()
	var poly := PackedVector2Array()
	for i in n:
		var c: Vector2 = corners[i]
		var a: Vector2 = corners[(i - 1 + n) % n]
		var b: Vector2 = corners[(i + 1) % n]
		var d_in := (c - a).normalized()
		var d_out := (b - c).normalized()
		var turn := d_in.angle_to(d_out)
		var tl := minf(CORNER_R * tan(absf(turn) * 0.5), minf(c.distance_to(a), c.distance_to(b)) * 0.45)
		var r := tl / maxf(tan(absf(turn) * 0.5), 0.001)
		var t1 := c - d_in * tl
		var nrm := Vector2(-d_in.y, d_in.x) * signf(turn)     # towards the inside of the bend
		var ctr := t1 + nrm * r
		var steps := maxi(4, int(r * absf(turn)))
		var a0 := (t1 - ctr).angle()
		for k in steps + 1:
			poly.append(ctr + Vector2.from_angle(a0 + turn * float(k) / steps) * r)
	# resample to a point every metre, round the loop
	var dense := PackedVector2Array()
	var total := 0.0
	for i in poly.size():
		total += poly[i].distance_to(poly[(i + 1) % poly.size()])
	var m := int(total)
	var step := total / m
	var seg := 0
	var acc := 0.0
	for k in m:
		var want := k * step
		while seg < poly.size() and acc + poly[seg].distance_to(poly[(seg + 1) % poly.size()]) < want:
			acc += poly[seg].distance_to(poly[(seg + 1) % poly.size()])
			seg += 1
		var a2 := poly[seg % poly.size()]
		var b2 := poly[(seg + 1) % poly.size()]
		var l := a2.distance_to(b2)
		dense.append(a2.lerp(b2, (want - acc) / maxf(l, 0.001)))
	# the racing line, the way a driver takes a corner: out wide on the run-up, in to the inside edge at the
	# apex, and back out wide on the exit. Each corner pulls the line its way (inside at the apex, outside
	# from a turn-in distance before and after); between two corners turning the same way it stays outside,
	# between opposite ones it crosses over.
	ctr = dense
	var cnt0 := ctr.size()
	var nrm := PackedVector2Array()
	nrm.resize(cnt0)
	for i in cnt0:
		var tg := (ctr[(i + 2) % cnt0] - ctr[(i - 2 + cnt0) % cnt0]).normalized()
		nrm[i] = Vector2(-tg.y, tg.x)
	var cinfo := []            # [index on the street's middle, +1 right / -1 left, turn-in distance]
	for i in n:
		var c: Vector2 = corners[i]
		var a: Vector2 = corners[(i - 1 + n) % n]
		var b: Vector2 = corners[(i + 1) % n]
		var turn := (c - a).normalized().angle_to((b - c).normalized())
		var best := 0
		var bd := INF
		for j in cnt0:
			var dd := ctr[j].distance_squared_to(c)
			if dd < bd:
				bd = dd
				best = j
		var room := minf(c.distance_to(a), c.distance_to(b))
		cinfo.append([best, signf(turn), clampf(room * 0.42, 12.0, 26.0)])
	offs.resize(cnt0)
	for i in cnt0:
		var num := 0.0
		var den := 0.0
		for ci in cinfo:
			var d := float(i - int(ci[0]))
			if d > cnt0 * 0.5:
				d -= cnt0
			elif d < -cnt0 * 0.5:
				d += cnt0
			var x := clampf(absf(d) / float(ci[2]), 0.0, 1.0)
			var h := float(ci[1]) * cos(PI * x)        # +inside at the apex, -outside from the turn-in point
			var w := 1.0 / pow(absf(d) + 6.0, 2.0)
			num += h * w
			den += w
		offs[i] = clampf(num / den, -1.0, 1.0) * LINE_W
	var cur := ctr.duplicate()
	for i in cnt0:
		cur[i] = ctr[i] + nrm[i] * offs[i]
	# then ease out any kinks (lightly: it mustn't pull the line in off its outside-inside-outside)
	for it in 40:
		for i in cnt0:
			var mid := (cur[(i - 3 + cnt0) % cnt0] + cur[(i + 3) % cnt0]) * 0.5
			var o := clampf((mid - ctr[i]).dot(nrm[i]), -LINE_W, LINE_W)
			offs[i] = lerpf(offs[i], o, 0.5)
			cur[i] = ctr[i] + nrm[i] * offs[i]
	# resample the line itself to a point a metre apart (it's shorter than the middle of the street)
	var ltot := 0.0
	for i in cnt0:
		ltot += cur[i].distance_to(cur[(i + 1) % cnt0])
	var m2 := int(ltot)
	var step2 := ltot / m2
	var line := PackedVector2Array()
	var mids := PackedVector2Array()
	var offs2 := PackedFloat32Array()
	var sg := 0
	var acc2 := 0.0
	for k in m2:
		var want2 := k * step2
		while sg < cnt0 and acc2 + cur[sg].distance_to(cur[(sg + 1) % cnt0]) < want2:
			acc2 += cur[sg].distance_to(cur[(sg + 1) % cnt0])
			sg += 1
		var i0 := sg % cnt0
		var i1 := (sg + 1) % cnt0
		var f := (want2 - acc2) / maxf(cur[i0].distance_to(cur[i1]), 0.001)
		line.append(cur[i0].lerp(cur[i1], f))
		mids.append(ctr[i0].lerp(ctr[i1], f))
		offs2.append(lerpf(offs[i0], offs[i1], f))
	pts = line
	ctr = mids
	offs = offs2
	length = float(pts.size())
	# how fast each metre can go: the bend, then braking for what's ahead, then accelerating out
	speed.resize(pts.size())
	var cnt := pts.size()
	for i in cnt:
		var p0 := pts[(i - 3 + cnt) % cnt]
		var p1 := pts[i]
		var p2 := pts[(i + 3) % cnt]
		var k := _curv(p0, p1, p2)
		speed[i] = minf(V_MAX, sqrt(A_LAT / maxf(k, 0.0001)))
	for _pass in 2:
		for j in range(cnt * 2, 0, -1):
			var i := j % cnt
			var nx := (i + 1) % cnt
			speed[i] = minf(speed[i], sqrt(speed[nx] * speed[nx] + 2.0 * A_BRAKE))
		for j in cnt * 2:
			var i2 := j % cnt
			var pv := (i2 - 1 + cnt) % cnt
			speed[i2] = minf(speed[i2], sqrt(speed[pv] * speed[pv] + 2.0 * A_ACC))

func _curv(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ca := c.distance_to(a)
	var area := absf((b - a).cross(c - a)) * 0.5
	return 4.0 * area / maxf(ab * bc * ca, 0.0001)

## A point on the line s metres round the loop (any s; it wraps).
func at(s: float) -> Vector2:
	var cnt := pts.size()
	var f := fposmod(s, length)
	var i := int(f)
	return pts[i % cnt].lerp(pts[(i + 1) % cnt], f - float(i))

func tangent(s: float) -> Vector2:
	return (at(s + 1.5) - at(s - 1.5)).normalized()

## Right of the line, looking along it.
func right(s: float) -> Vector2:
	var tg := tangent(s)
	return Vector2(-tg.y, tg.x)

## How far the racing line is from the middle of the street at s (+: to the right).
func off_at(s: float) -> float:
	return offs[int(fposmod(s, length)) % offs.size()]

func speed_at(s: float) -> float:
	return speed[int(fposmod(s, length)) % speed.size()]

## The metre of the line nearest p, looking only within reach of a guess (or all of it with reach = length).
func _nearest_s(p: Vector2, guess: float, reach: float) -> float:
	var best := guess
	var bd := INF
	var g := int(fposmod(guess, length))
	var r := int(minf(reach, length * 0.5))
	for k in range(-r, r + 1):
		var i := posmod(g + k, pts.size())
		var d := pts[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = float(i)
	return best

## How far round a racer is: laps and all, from the start line (negative on the grid).
func _progress(r: Dictionary) -> void:
	var c: Node3D = r["car"]
	var p := Vector2(c.global_position.x, c.global_position.z)
	var loop_s := fposmod(float(r["s"]) + start_s, length)
	var ns := _nearest_s(p, loop_s, 40.0)
	var dd := ns - loop_s
	if dd > length * 0.5:
		dd -= length
	elif dd < -length * 0.5:
		dd += length
	r["s"] = float(r["s"]) + dd
	r["off_by"] = p.distance_to(at(ns))

func _paint_line() -> void:
	var mb := MB.new()
	var blue := MB.glow("5cb8ff")
	var amber := MB.glow("ffc94a")
	var red := MB.glow("ff5a4e")
	var s := 0.0
	while s < length:
		var v := speed_at(s)
		var ahead := speed_at(s + 14.0)
		var col := blue
		if ahead < v - 1.2:
			col = red
		elif v < 16.0:
			col = amber
		var c := at(s)
		var tg := tangent(s)
		var rt := Vector2(-tg.y, tg.x)
		var y := func(q: Vector2) -> float: return island.height_at(q.x, q.y) + 0.1
		# a chevron pointing along the line
		var tip := c + tg * 0.55
		for sd in [-1.0, 1.0]:
			var back: Vector2 = c + rt * 0.55 * sd
			var w: Vector2 = tg * 0.22
			var q0: Vector2 = back
			var q1: Vector2 = tip
			var q2: Vector2 = tip - w * 1.4
			var q3: Vector2 = back - w * 1.4
			var pts3 := [Vector3(q0.x, y.call(q0), q0.y), Vector3(q1.x, y.call(q1), q1.y), Vector3(q2.x, y.call(q2), q2.y), Vector3(q3.x, y.call(q3), q3.y)]
			if sd > 0:
				mb.quad(pts3[0], pts3[1], pts3[2], pts3[3], Vector3.UP, col)
			else:
				mb.quad(pts3[3], pts3[2], pts3[1], pts3[0], Vector3.UP, col)
		s += 2.2
	line_mi = MeshInstance3D.new()
	line_mi.mesh = mb.commit()
	line_mi.material_override = game.toon
	line_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line_mi)
	# and the course on the map
	var mp := PackedVector3Array()
	for i in range(0, pts.size(), 3):
		mp.append(Vector3(pts[i].x, 0, pts[i].y))
	mp.append(Vector3(pts[0].x, 0, pts[0].y))
	island.route_line(mp, Color("ff5c7a"))

func _build_gates() -> void:
	var am := M.get_mesh("arch")
	for k in cps.size():
		var s: float = start_s + float(cps[k])
		var c := at(s)
		var tg := tangent(s)
		var arch := MeshInstance3D.new()
		arch.mesh = am
		arch.material_override = game.toon
		var w := 14.0 if k == cps.size() - 1 else 11.5
		var sc := w / maxf(am.get_aabb().size.x, 0.1)
		arch.transform = Transform3D(Basis(Vector3.UP, atan2(-tg.x, -tg.y)).scaled(Vector3.ONE * sc), Vector3(c.x, island.height_at(c.x, c.y), c.y))
		add_child(arch)
		gates.append(arch)

# ---------------------------------------------------------------- the field

func grid(player_car) -> void:
	var pool := []
	for d in CARS.LIST:
		if d["id"] != String(game.save.data["car"]):
			pool.append(d)
	pool.shuffle()
	var names := NAMES.duplicate()
	names.shuffle()
	var your_slot := 5
	var up: Dictionary = game.save.data["up"]
	for slot in 8:
		var row := slot / 2
		var col := -2.6 if slot % 2 == 0 else 2.6
		var s: float = start_s - 9.0 - row * 8.0
		var c := at(s) + right(s) * (col - off_at(s))      # (either side of the street's middle)
		var tg := tangent(s)
		var xf: Transform3D = game.on_ground(Transform3D(Basis(Vector3.UP, atan2(-tg.x, -tg.y)), Vector3(c.x, island.height_at(c.x, c.y) + 0.7, c.y)))
		var r := {"name": "You", "ai": false, "s": s - start_s, "lane": 0.0, "lane_now": col - off_at(s), "skill": 1.0, "stuck": 0.0,
			"off": 0.0, "flip": 0.0, "done": -1.0, "last_cp": -1, "off_by": 0.0}
		if slot == your_slot:
			r["car"] = player_car
			player_car.place(xf)
			you = r
		else:
			var d: Dictionary = pool[slot % pool.size()]
			var car: Car = Car.new()
			car.name = "Racer_%d" % slot
			car.set_meta("racer", true)
			car.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON   # drawn smoothly, like yours
			game.add_child(car)
			var paints: int = M.paints(d).size()
			car.setup(d, game.toon, island, randi_range(0, maxi(paints - 1, 0)))
			car.tune(d, up)
			car.assist = 1.0
			car.collision_layer = AI_LAYER
			car.collision_mask = 1 | 2 | 4 | AI_LAYER
			car.place(xf)
			r["car"] = car
			r["ai"] = true
			r["name"] = names[slot % names.size()]
			# a spread of pace: the quickest a touch above the line's speeds, the slowest a little under
			r["skill"] = [1.04, 1.0, 0.97, 0.95, 0.99, 0.93, 1.02, 0.96][slot]
			r["lane"] = 0.0          # (everyone drives the racing line: off it only to get past someone)
		racers.append(r)
	for r in racers:
		(r["car"] as Car).hold = true          # on their wheels, brakes on, till GO

# ---------------------------------------------------------------- per frame

## Returns what the HUD wants. Calls game.race_done(place, time) once you cross the line for the last time.
func tick(dt: float) -> void:
	if state == 0:
		var before := ceili(count)
		count -= dt
		for r in racers:
			(r["car"] as Car).hold = true
		if ceili(count) != before and count > 0.0 and ceili(count) <= 3:
			game.ui.big_count(str(ceili(count)))
			game.sfx("checkpoint", -4.0, 0.8)
		if count <= 0.0:
			state = 1
			game.ui.big_count("GO!")
			game.sfx("go", 0.0)
			for r in racers:
				(r["car"] as Car).hold = false
				(r["car"] as Car).freeze = false
		return
	t += dt
	if game.args.has("racelog") and int(t * 10.0) != int((t - dt) * 10.0) and int(t * 10.0) % 20 == 0:
		var line := "RACE t=%.0f" % t
		for r in standings():
			line += " | %s s=%.0f v=%.0f off=%.1f%s" % [r["name"], float(r["s"]), (r["car"] as RigidBody3D).linear_velocity.length() * 3.6, float(r["off_by"]), " DONE" if float(r["done"]) >= 0.0 else ""]
		print(line)
	var robot: bool = game.args.has("raceauto")      # testing: the CPU drives your car as well
	for r in racers:
		if r.get("busted", false):
			continue          # (pulled over by the police: out of it)
		_progress(r)
		if r["ai"] or (robot and r == you and float(r["done"]) < 0.0):
			_drive(r, dt)       # (over the line: a slower lap to cool down, not stopped in anyone's way)
		if float(r["done"]) < 0.0 and float(r["s"]) >= length * laps:
			r["done"] = t
			r["skill"] = 0.7
			finished.append(r)
	_ghosts(dt)
	_you(dt)
	_gates_tick()

func _drive(r: Dictionary, dt: float) -> void:
	var c: Car = r["car"]
	var pos := c.global_position
	var v := c.linear_velocity.length()
	var s := fposmod(float(r["s"]) + start_s, length)
	var my_lat := (Vector2(pos.x, pos.z) - at(s)).dot(right(s))
	# who's around: the car ahead in my path (to follow, or pass), and who's beside me (so I don't pull into them)
	var want: float = r["lane"]
	var follow_v := INF
	var blocker := {}
	var block_ds := INF
	var olat2 := 0.0
	var others := []           # [ds, lateral] for everyone near
	for o in racers:
		if o == r:
			continue
		var ds := float(o["s"]) - float(r["s"])
		if ds < -12.0 or ds > 30.0:
			continue
		var oc: Node3D = o["car"]
		var olat := (Vector2(oc.global_position.x, oc.global_position.z) - at(s + ds)).dot(right(s + ds))
		others.append([ds, olat])
		if ds > 0.0 and absf(olat - my_lat) < 2.3 and ds < block_ds:
			block_ds = ds
			blocker = o
			olat2 = olat
	if not blocker.is_empty():
		var ov := (blocker["car"] as RigidBody3D).linear_velocity.length()
		# keep a gap of a couple of car lengths, closing it gently
		follow_v = ov + clampf((block_ds - 9.0) * 0.5, -6.0, 4.0)
		# pass on whichever side has room (and isn't someone already alongside)
		for side in ([-1.0, 1.0] if my_lat < olat2 else [1.0, -1.0]):
			var tl := clampf(olat2 + side * 2.7, -3.0, 3.0)
			if absf(tl - olat2) < 2.3:
				continue       # (no room that side: the kerb)
			var free := true
			for e in others:
				if float(e[0]) > -7.0 and float(e[0]) < block_ds + 4.0 and absf(float(e[1]) - tl) < 2.2:
					free = false
			if free:
				want = tl
				follow_v = INF if block_ds > 6.0 else follow_v
				break
	# corners are taken on the line: tuck back in behind (unless already alongside and ahead)
	var bend := speed_at(s + 18.0) < speed_at(s) - 2.0 or speed_at(s + 6.0) < 15.0
	if bend and not (not blocker.is_empty() and block_ds < 3.0):
		want *= 0.2
	r["lane_now"] = move_toward(float(r["lane_now"]), want, dt * 2.0)
	# steer for a point ahead on the line (or beside it, but never off the street)
	var la := 6.0 + v * 0.45
	var lo := clampf(off_at(s + la) + float(r["lane_now"]), -ROOM, ROOM) - off_at(s + la)
	var tp := at(s + la) + right(s + la) * lo
	var fwd := -c.global_transform.basis.z
	var to := Vector3(tp.x - pos.x, 0, tp.y - pos.z)
	var ang := atan2(fwd.z * to.x - fwd.x * to.z, fwd.x * to.x + fwd.z * to.z)
	c.steer_in = clampf(-ang * 2.4, -1.0, 1.0)
	c.handbrake = 0.0
	# hold the line's speed (looking a little ahead, so it brakes in time)
	var vt := speed_at(s + v * 0.35 + 3.0) * float(r["skill"])
	# a little help for whoever's behind you, a little restraint for whoever's well ahead
	var gap := float(r["s"]) - float(you["s"])
	vt *= clampf(1.0 - gap * 0.0006, 0.94, 1.05)
	vt = minf(vt, follow_v)
	if absf(ang) > 0.45 and v > 6.0:
		vt = minf(vt, v - 2.0)       # pointing well off the line: ease off and get it back
	if r == you and game.args.has("racetrace"):
		var lat2 := (Vector2(pos.x, pos.z) - at(s)).dot(right(s))
		print("TRACE t=%.1f s=%.0f v=%.1f vt=%.1f lat=%.1f slip=%.0f steer=%.2f ang=%.2f wheel=%.2f yaw=%.2f gr=%d thr=%.1f hb=%.1f frz=%s y=%.1f" % [t, float(r["s"]), v, vt, lat2, rad_to_deg(c.slip), c.steer_in, ang, c.steer, c.angular_velocity.y, c.grounded, c.throttle, c.handbrake, c.freeze, pos.y])
	if v < vt - 0.6:
		c.throttle = 1.0
		c.brake = 0.0
	elif v > vt + 1.2:
		c.throttle = 0.0
		c.brake = clampf((v - vt) / 4.0, 0.3, 1.0)
	else:
		c.throttle = 0.4
		c.brake = 0.0
	# stuck, off the course or on its roof: back on the line
	r["stuck"] = float(r["stuck"]) + dt if v < 1.2 else 0.0
	r["off"] = float(r["off"]) + dt if float(r["off_by"]) > 11.0 else 0.0
	r["flip"] = float(r["flip"]) + dt if c.global_transform.basis.y.y < 0.3 else 0.0
	if float(r["stuck"]) > 3.0 or float(r["off"]) > 2.5 or float(r["flip"]) > 1.2:
		if game.args.has("racelog"):
			print("RESPAWN %s stuck=%.1f off=%.1f flip=%.1f at s=%.0f" % [r["name"], float(r["stuck"]), float(r["off"]), float(r["flip"]), float(r["s"])])
		_respawn(r)

func _respawn(r: Dictionary, back := 6.0) -> void:
	var c: Car = r["car"]
	var s: float = float(r["s"]) + start_s - back
	var p := at(s) + right(s) * float(r["lane"]) * 0.5
	# back on the course as a ghost for a moment, so it can't land on (or be hit by) anyone
	if not r.has("layer"):
		r["layer"] = c.collision_layer
		r["mask"] = c.collision_mask
	r["ghost"] = 2.5
	c.collision_layer = 0
	c.collision_mask = 1
	_ghost_look(c, true)
	var tg := tangent(s)
	c.place(Transform3D(Basis(Vector3.UP, atan2(-tg.x, -tg.y)), Vector3(p.x, island.height_at(p.x, p.y) + 0.8, p.y)))
	c.linear_velocity = Vector3(tg.x, 0, tg.y) * 6.0
	r["s"] = float(r["s"]) - back
	r["stuck"] = 0.0
	r["off"] = 0.0
	r["flip"] = 0.0

## Ghosts (just put back on the course) go see-through, and solid again when their time's up.
func _ghosts(dt: float) -> void:
	for r in racers:
		if float(r.get("ghost", 0.0)) <= 0.0:
			continue
		r["ghost"] = float(r["ghost"]) - dt
		var c: Car = r["car"]
		var clear := true
		for o in racers:
			if o != r and (o["car"] as Node3D).global_position.distance_to(c.global_position) < 4.5:
				clear = false
		if float(r["ghost"]) <= 0.0 and not clear:
			r["ghost"] = 0.3        # (wait till nobody's inside it)
		elif float(r["ghost"]) <= 0.0:
			c.collision_layer = int(r["layer"])
			c.collision_mask = int(r["mask"])
			_ghost_look(c, false)

func _ghost_look(c: Car, on: bool) -> void:
	for n in c.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).transparency = 0.55 if on else 0.0

func _you(dt: float) -> void:
	if state != 1:
		return
	var c: RigidBody3D = you["car"]
	# checkpoints, in order (counted over the whole race: lap 2's first one is cps.size())
	var ncp := cps.size()
	var next := int(you["last_cp"]) + 1
	if next < ncp * laps:
		var k := next % ncp
		var cp_total := float(next / ncp) * length + float(cps[k])
		if float(you["s"]) >= cp_total - 1.0:
			you["last_cp"] = next
			if k == ncp - 1:
				var lap_now := next / ncp + 2
				if lap_now <= laps:
					game.ui.popup_text("Lap %d of %d" % [lap_now, laps], Color("ffd34d"))
					game.sfx("checkpoint", -2.0, 1.2)
			else:
				game.sfx("checkpoint", -6.0)
	# the end
	if float(you["done"]) >= 0.0 and state == 1:
		state = 2
		game.race_done(place_of(you), float(you["done"]))
		return
	# going the wrong way, or lost: point it out, and if it goes on, back to the last checkpoint
	var v := c.linear_velocity
	var s := fposmod(float(you["s"]) + start_s, length)
	var tg := tangent(s)
	if Vector2(v.x, v.z).dot(tg) < -4.0:
		wrong_t += dt
		if wrong_t > 1.2 and fmod(wrong_t, 2.0) < dt:
			game.ui.popup_text("Wrong way!", Color("ff5a4e"))
	else:
		wrong_t = 0.0
	if float(you["off_by"]) > 28.0:
		away_t += dt
		if away_t > 4.0:
			away_t = 0.0
			var lc := int(you["last_cp"])
			you["s"] = (float(lc / ncp) * length + float(cps[lc % ncp])) if lc >= 0 else -9.0
			_respawn(you, 0.0)
			game.ui.popup_text("Back to the last checkpoint", Color.WHITE)
	else:
		away_t = 0.0

func _gates_tick() -> void:
	var next := (int(you["last_cp"]) + 1) % cps.size()
	for k in gates.size():
		(gates[k] as Node3D).visible = k == next or k == (next + 1) % cps.size() or k == cps.size() - 1

# ---------------------------------------------------------------- rewind

## Where everyone is (for rewinding): the clock, and each racer's place round the course and its car.
func snapshot() -> Dictionary:
	var rs := []
	for r in racers:
		var c: RigidBody3D = r["car"]
		rs.append([float(r["s"]), int(r["last_cp"]), float(r["done"]), float(r["lane_now"]), c.global_transform, c.linear_velocity, c.angular_velocity])
	return {"t": t, "racers": rs, "finished": finished.size()}

## Rewinding: the CPU cars are held where the snapshots put them.
func rw_hold(on: bool) -> void:
	for r in racers:
		if r["ai"]:
			(r["car"] as RigidBody3D).freeze = on

## Back to a snapshot (moving: true while rewinding, just the positions; false at the end: speeds too).
func rw_apply(snap: Dictionary, moving: bool) -> void:
	t = float(snap["t"])
	var rs: Array = snap["racers"]
	for i in mini(rs.size(), racers.size()):
		var r: Dictionary = racers[i]
		var q: Array = rs[i]
		r["s"] = q[0]
		r["last_cp"] = q[1]
		r["done"] = q[2]
		r["lane_now"] = q[3]
		if r["ai"]:
			var c: RigidBody3D = r["car"]
			c.global_transform = q[4]
			if not moving:
				c.linear_velocity = q[5]
				c.angular_velocity = q[6]
				c.reset_physics_interpolation()
	while finished.size() > int(snap["finished"]):
		finished.pop_back()

## Paused (or in the garage): everyone waits where they are, and carries on at the same speed after.
func hold(on: bool) -> void:
	for r in racers:
		if not r["ai"]:
			continue
		var c: RigidBody3D = r["car"]
		if on and not c.freeze:
			r["held"] = [c.linear_velocity, c.angular_velocity]
			c.freeze = true
		elif not on and state != 0 and r.has("held"):
			c.freeze = false
			c.linear_velocity = r["held"][0]
			c.angular_velocity = r["held"][1]
			r.erase("held")

## 1 for the leader.
func place_of(r: Dictionary) -> int:
	var order := standings()
	return order.find(r) + 1

## Everyone in race order: those over the line first (in the order they crossed), then by distance round.
func standings() -> Array:
	var rest := []
	for r in racers:
		if not finished.has(r):
			rest.append(r)
	# (anyone the police pulled over is out of it: last)
	rest.sort_custom(func(a, b): return (-1e9 if a.get("busted", false) else float(a["s"])) > (-1e9 if b.get("busted", false) else float(b["s"])))
	return finished + rest

## The police have stopped this CPU racer: it's out of the race, parked where it was caught.
func bust(car_node: Node) -> void:
	for r in racers:
		if r["car"] == car_node and r["ai"] and not r.get("busted", false):
			r["busted"] = true
			(r["car"] as Car).hold = true
			game.ui.popup_text("%s got busted!" % r["name"], Color("5c8dff"))

## For the HUD.
func hud() -> Dictionary:
	var lap := clampi(int(floor(float(you["s"]) / length)) + 1, 1, laps)
	return {"name": def["name"], "place": place_of(you), "of": racers.size(), "lap": lap, "laps": laps, "t": t,
		"counting": state == 0}

## Where the arrow should point: the next checkpoint (and the line ahead for the turn coming up).
func guide() -> Array:
	var s := fposmod(float(you["s"]) + start_s, length)
	var aim := at(s + 28.0)
	var next := int(you["last_cp"]) + 1
	var k := next % cps.size()
	var cp_total := float(next / cps.size()) * length + float(cps[k])
	return [Vector3(aim.x, 0, aim.y), maxf(cp_total - float(you["s"]), 0.0), "Finish" if k == cps.size() - 1 and next / cps.size() == laps - 1 else ("Lap line" if k == cps.size() - 1 else "Checkpoint %d" % (k + 1))]

func cleanup() -> void:
	for r in racers:
		if r["ai"]:
			(r["car"] as Node).queue_free()
		elif r.has("layer"):
			# you, solid again
			(r["car"] as Car).collision_layer = int(r["layer"])
			(r["car"] as Car).collision_mask = int(r["mask"])
			_ghost_look(r["car"], false)
	racers.clear()
	island.route_line(PackedVector3Array(), Color.WHITE)
