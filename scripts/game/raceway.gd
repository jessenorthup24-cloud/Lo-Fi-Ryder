extends RefCounted
## The Raceway (Kenney racing kit, CC0): a race track on its own peninsula off the south-east coast, built up
## flat and reached by a road off the ring road. The Grand Prix circuit runs round the outside (a long main
## straight past the pits and grandstands, a fast right-hander, a sweeping south end, an S through the
## back and a last corner onto the straight); inside it is a tight drift course, reached across the main
## straight. Barriers line the outside of the circuit, red and white blocks the drift course, kerbs paint
## the corners, and the start gantry, banners, tents, pit garages and parked race cars dress it.
##
## Challenges here: the Raceway Grand Prix (a race, 8 cars, 3 laps), Hot Lap (a timed lap) and the Drift
## Course (drifted all the way round, through its gates).

const MB := preload("res://scripts/core/mesh_builder.gd")
const M := preload("res://scripts/core/models.gd")
const Race := preload("res://scripts/game/race.gd")

const C := Vector2(440, 430)            # the peninsula
const HS := Vector2(140, 118)
const ROUND := 50.0
const LIFT := 2.4                       # the built-up ground's height
# the Grand Prix circuit, in the order you drive it: (x, z, corner radius)
const GP := [Vector3(338, 372, 20), Vector3(548, 372, 24), Vector3(552, 515, 22), Vector3(420, 515, 15),
	Vector3(420, 462, 15), Vector3(342, 462, 18)]
const GP_W := 14.0
# the drift course in the middle
const DRIFT := [Vector3(372, 398, 10), Vector3(522, 398, 12), Vector3(524, 492, 12), Vector3(448, 492, 10),
	Vector3(448, 440, 9), Vector3(372, 440, 10)]
const DRIFT_W := 11.0
const CROSS_X := 394.0                  # where the way in crosses the main straight into the drift course
										# (on the drift course's top straight, well clear of its first corner)
const START_X := 430.0                  # the start/finish line, on the main straight

## How far inland a point is of the peninsula alone (negative: out at sea): a rounded rectangle.
static func inland(x: float, z: float) -> float:
	var q := Vector2(absf(x - C.x) - (HS.x - ROUND), absf(z - C.y) - (HS.y - ROUND))
	return -(Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - ROUND)

## The peninsula's outline (for the map).
static func outline() -> PackedVector2Array:
	var out := PackedVector2Array()
	var hc := HS - Vector2(ROUND, ROUND)
	for k in 4:
		var sx := 1.0 if k == 0 or k == 3 else -1.0
		var sz := 1.0 if k < 2 else -1.0
		var cc := C + Vector2(hc.x * sx, hc.y * sz)
		var a0: float = [0.0, PI * 0.5, PI, PI * 1.5][k]
		for i in 7:
			out.append(cc + Vector2.from_angle(a0 + PI * 0.5 * i / 6.0) * (ROUND - 4.0))
	return out

static func _pts(corners: Array) -> Array:
	var c2 := []
	var rs := []
	for q in corners:
		c2.append(Vector2(q.x, q.y))
		rs.append(float(q.z))
	return [c2, rs]

## The land, the roads and the paddock (laid out with the rest of the island's plan).
static func plan(I) -> void:
	I.raises.append([C, HS - Vector2(8, 8), LIFT, 16.0])
	var gp: Array = _pts(GP)
	var dr: Array = _pts(DRIFT)
	I.add_road("Raceway Circuit", Array(Race.rounded(gp[0], gp[1])), "track", true)
	I.add_road("Drift Course", Array(Race.rounded(dr[0], dr[1])), "drift", true)
	# the way in: off the ring road, under the railway, down past the paddock, across the main straight
	I.add_road("Raceway Road", [Vector2(300, 250), Vector2(322, 292), Vector2(352, 322), Vector2(CROSS_X, 345),
		Vector2(CROSS_X, 372), Vector2(CROSS_X, 398)], "yard")
	I.add_lot(Vector2(445.5, 343), Vector2(47.5, 14), I.S_ASPHALT)      # the paddock and pits (up to the road's edge)

## Everything that dresses the track (after the roads and the land are in).
static func populate(I, rr: RandomNumberGenerator) -> void:
	# nothing else grows or gets put here
	I.block_rect(C, HS - Vector2(4, 4), 0.0, 0.0)
	var gi := _road_i(I, "Raceway Circuit")
	var di := _road_i(I, "Drift Course")
	var gp: PackedVector2Array = I.roads[gi]["pts"]
	var dr: PackedVector2Array = I.roads[di]["pts"]
	var y := LIFT + 0.02
	_kerbs(I, gi, GP_W * 0.5, true)
	_kerbs(I, di, DRIFT_W * 0.5, false)
	_start_line(I, gp, y)
	# the circuit's outside: a wall all round, a few metres back from the edge (open where the way in crosses)
	_edge(I, gi, GP_W * 0.5 + 4.0, "k_race_barrierWall", 8.0, 1.5)
	# the drift course's outside: red and white blocks, close to the edge (for running the wall)
	_edge(I, di, DRIFT_W * 0.5 + 1.6, "", 2.0, 1.0)
	# the pits: a row of garages facing the straight, the office at the end, race cars out front
	for k in 6:
		var gx := 410.0 + k * 8.0
		I.put("k_race_pitsGarageClosed" if k % 3 == 2 else "k_race_pitsGarage", gx, 342.5, PI, 1.0, "box", y)
	I.put("k_race_pitsOffice", 458.0, 342.5, PI, 1.0, "box", y)
	I.put("k_race_pitsOfficeRoof", 466.0, 342.5, PI, 1.0, "box", y)
	var rcars := ["k_race_raceCarRed", "k_race_raceCarGreen", "k_race_raceCarOrange", "k_race_raceCarWhite"]
	for k in 4:
		I.put(rcars[k], 414.0 + k * 13.0, 354.0, PI + rr.randf_range(-0.15, 0.15), 1.0, "box", y)
	# tents and the grandstands behind the paddock, looking over the straight
	I.put("k_race_tentLong", 426.0, 329.0, PI, 1.0, "box", y)
	I.put("k_race_tent", 448.0, 329.0, PI, 1.0, "box", y)
	I.put("k_race_tentClosed", 458.0, 329.0, PI, 1.0, "box", y)
	for k in 5:
		I.put("k_race_grandStandCovered", 494.0 + k * 8.2, 344.0, PI, 1.0, "box", y)
	# more stands on the outside of the west side, and at the south end
	for k in 3:
		I.put("k_race_grandStand", 321.5, 400.0 + k * 8.2, PI * 0.5, 1.0, "box", y)
	for k in 3:
		I.put("k_race_grandStandCovered", 470.0 + k * 8.2, 533.5, 0.0, 1.0, "box", y)
	# the start gantry over the line (lights on top), and lamp posts down the straight
	var gw := GP_W + 4.0
	var ov := "k_race_overheadLights"
	var osz: Vector3 = M.ksize(ov)
	var osc := gw / maxf(osz.x, 0.1)
	I.put(ov, START_X, 372.0, PI * 0.5, osc, "", y)
	for sd in [-1.0, 1.0]:
		I.add_cyl_collider(Vector3(START_X, y, 372.0 + sd * gw * 0.48), 0.5, 8.0)
	for k in 5:
		I.put("k_race_lightPostLarge", 370.0 + k * 40.0, 384.5, 0.0, 1.0, "cyl", y)
	# banner towers and flags at the corners, billboards on the outside
	for p in [Vector2(566, 356), Vector2(568, 530), Vector2(402, 530), Vector2(322, 476), Vector2(322, 356)]:
		I.put("k_race_bannerTowerRed" if rr.randf() < 0.5 else "k_race_bannerTowerGreen", p.x, p.y, rr.randf() * TAU, 1.0, "cyl", y)
	I.put("k_race_flagCheckers", START_X + 4.0, 362.0, PI, 1.0, "", y)
	I.put("k_race_billboard", 566.0, 440.0, -PI * 0.5, 1.0, "box", y)
	I.put("k_race_billboard", 381.0, 492.0, 0.0, 0.8, "box", y)
	I.put("k_race_billboardLow", 470.0, 456.0, PI, 1.0, "box", y)
	# trees round the edge of it all
	for k in 26:
		var a := rr.randf() * TAU
		var p2 := C + Vector2(cos(a) * (HS.x - 6.0), sin(a) * (HS.y - 6.0))
		p2 = Vector2(clampf(p2.x, C.x - HS.x + 8.0, C.x + HS.x - 8.0), clampf(p2.y, C.y - HS.y + 8.0, C.y + HS.y - 8.0))
		if _near_road(gp, p2, GP_W * 0.5 + 7.0) or _near_road(dr, p2, 20.0) or Vector2(p2.x - CROSS_X, 0).length() < 12.0 and p2.y < 380.0:
			continue
		if p2.y < 360.0 and p2.x > 380.0 and p2.x < 540.0:
			continue          # (not in the paddock or the stands)
		I.put("k_race_treeLarge" if k % 3 != 0 else "k_race_treeSmall", p2.x, p2.y, rr.randf() * TAU, rr.randf_range(0.85, 1.15), "cyl", y)

static func _road(I, name: String) -> Dictionary:
	for r in I.roads:
		if r["name"] == name:
			return r
	return {}

static func _road_i(I, name: String) -> int:
	for ri in I.roads.size():
		if I.roads[ri]["name"] == name:
			return ri
	return -1

## A loop's centre line, `sub` points to each of its samples, with the direction at each: the same curve the
## track's surface is drawn on.
static func _dense(I, pts: PackedVector2Array, sub: int) -> Array:
	var ps := PackedVector2Array()
	var ts := PackedVector2Array()
	for k in pts.size():
		for u in sub:
			var at: Array = I.loop_at(pts, k, float(u) / sub)
			ps.append(at[0])
			ts.append(at[1])
	return [ps, ts]

static func _near_road(pts: PackedVector2Array, p: Vector2, d: float) -> bool:
	for q in pts:
		if q.distance_to(p) < d:
			return true
	return false

static func _kerbs(I, ri: int, hw: float, both: bool) -> void:
	var d: Array = _dense(I, I.roads[ri]["pts"], 4)
	var ps: PackedVector2Array = d[0]
	var ts: PackedVector2Array = d[1]
	var n := ps.size()
	var step := ps[0].distance_to(ps[1])
	# where it bends tighter than about a 70 m radius, run on 4 m either side
	var on := PackedByteArray()
	on.resize(n)
	var side := PackedFloat32Array()          # which side the bend's inside is (+1: the right-hand side)
	side.resize(n)
	var ext := int(ceil(4.0 / step))
	var w := int(ceil(2.5 / step))            # the bend judged over 5 m, so the little wobble where an arc
	for i in n:                               # meets a straight doesn't count as a bend the other way
		var ta := ts[posmod(i - w, n)]
		var tb := ts[(i + w) % n]
		var turn := ta.cross(tb)
		var b := absf(ta.angle_to(tb)) / (2.0 * w * step)
		if b > 1.0 / 70.0:
			for j in range(-ext, ext + 2):
				on[posmod(i + j, n)] = 1
				side[posmod(i + j, n)] = signf(turn)
	var mb := MB.new()
	var red := MB.rgb("d9433b")
	var white := MB.rgb("f2efe9")
	var stripe := maxi(1, int(round(1.9 / step)))        # stripes about 2 m long
	var i0 := hw - 0.35
	var i1 := hw + 0.9
	# number the stripes from the start of each run of kerb, so every run starts on red
	var run_k := 0
	for i in n:
		var j := (i + 1) % n
		if on[i] == 0 or on[j] == 0:
			run_k = 0
			continue
		var col := red if (run_k / stripe) % 2 == 0 else white
		run_k += 1
		var ra := Vector2(-ts[i].y, ts[i].x)
		var rb := Vector2(-ts[j].y, ts[j].x)
		for sd: float in [-1.0, 1.0]:
			if not both and sd != side[i]:
				continue
			var mid := (ps[i] + ps[j]) * 0.5 + (ra + rb).normalized() * (i0 + i1) * 0.5 * sd
			if I.on_carriageway(mid, ri, 0.8):
				continue
			var a0 := ps[i] + ra * i0 * sd
			var a1 := ps[i] + ra * i1 * sd
			var b0 := ps[j] + rb * i0 * sd
			var b1 := ps[j] + rb * i1 * sd
			if sd > 0:
				mb.quad(_v(I, a0), _v(I, b0), _v(I, b1), _v(I, a1), Vector3.UP, col)
			else:
				mb.quad(_v(I, a1), _v(I, b1), _v(I, b0), _v(I, a0), Vector3.UP, col)
	_mesh(I, mb, "Kerbs")

## The start/finish line: a band of black and white squares across the straight.
static func _start_line(I, pts: PackedVector2Array, y: float) -> void:
	var mb := MB.new()
	var best := 0
	for k in pts.size():
		if absf(pts[k].x - START_X) + absf(pts[k].y - 372.0) < absf(pts[best].x - START_X) + absf(pts[best].y - 372.0):
			best = k
	var c := pts[best]
	var t := (pts[(best + 1) % pts.size()] - pts[(best - 1 + pts.size()) % pts.size()]).normalized()
	var r := Vector2(-t.y, t.x)
	var sq := 1.0
	var cols := int(GP_W / sq)
	for row in 2:
		for i in cols:
			var col := MB.rgb("1f1f22") if (i + row) % 2 == 0 else MB.rgb("f4f1ea")
			var p0 := c + r * (-GP_W * 0.5 + i * sq) + t * (row - 1) * sq
			var p1 := p0 + r * sq
			var p2 := p1 + t * sq
			var p3 := p0 + t * sq
			mb.quad(_v(I, p0), _v(I, p1), _v(I, p2), _v(I, p3), Vector3.UP, col)
	_mesh(I, mb, "StartLine")

## A point painted on the road surface.
static func _v(I, p: Vector2) -> Vector3:
	return Vector3(p.x, I.height_at(p.x, p.y) + I.ROAD_LIFT + 0.03, p.y)

static func _mesh(I, mb: MB, nm: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = I.road_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = nm
	I.add_child(mi)

## A barrier along the outside of a loop, `off` metres out from the middle: kit wall pieces (or, with no
## model, red and white blocks of our own), solid. It follows the curve the track is drawn on, in pieces of
## about `piece` metres fitted evenly into each unbroken run, so it closes up round the corners and stops
## square either side of where another road comes through.
static func _edge(I, ri: int, off: float, model: String, piece: float, clear: float) -> void:
	var d: Array = _dense(I, I.roads[ri]["pts"], 4)
	var ps: PackedVector2Array = d[0]
	var ts: PackedVector2Array = d[1]
	var n := ps.size()
	# outward: whichever side faces east at the loop's most easterly point
	var e := 0
	for i in n:
		if ps[i].x > ps[e].x:
			e = i
	var sgn := 1.0 if -ts[e].y > 0.0 else -1.0
	var line := PackedVector2Array()
	var free := PackedByteArray()
	free.resize(n)
	var start := -1
	for i in n:
		var q := ps[i] + Vector2(-ts[i].y, ts[i].x) * sgn * off
		line.append(q)
		free[i] = 0 if I.on_carriageway(q, ri, clear) else 1
		if free[i] == 0 and start < 0:
			start = i
	# the unbroken runs of it (all the way round, closed, if nothing crosses)
	var runs := []
	var cur := PackedVector2Array()
	var closed := start < 0
	var cnt := n + 1 if closed else n
	for j in cnt:
		var i := (maxi(start, 0) + j) % n
		if free[i] == 1:
			cur.append(line[i])
		elif cur.size() > 0:
			runs.append(cur)
			cur = PackedVector2Array()
	if cur.size() > 0:
		runs.append(cur)
	var mb := MB.new()
	var idx := 0
	for run: PackedVector2Array in runs:
		var acc := PackedFloat32Array([0.0])
		for i in range(1, run.size()):
			acc.append(acc[i - 1] + run[i].distance_to(run[i - 1]))
		var total: float = acc[acc.size() - 1]
		if total < piece * 0.4:
			continue
		var m := maxi(1, int(round(total / piece)))
		var at := 0
		var a := run[0]
		for p in m:
			var want := total * (p + 1) / m
			while at < run.size() - 2 and acc[at + 1] < want:
				at += 1
			var b := run[at].lerp(run[at + 1], clampf((want - acc[at]) / maxf(acc[at + 1] - acc[at], 0.001), 0.0, 1.0))
			var dirv := (b - a).normalized()
			var c := (a + b) * 0.5
			var yaw := atan2(-dirv.x, -dirv.y)
			var len := a.distance_to(b)
			if model != "":
				var msz: Vector3 = M.ksize(model)
				I.put(model, c.x, c.y, yaw + PI * 0.5, len / maxf(msz.x, 0.1), "box", LIFT)
			else:
				var col := MB.rgb("d9433b") if idx % 2 == 0 else MB.rgb("f2efe9")
				mb.cbox(Vector3(c.x, LIFT + 0.45, c.y), Vector3(0.9, 0.9, len - 0.05), 0.08, col, Basis(Vector3.UP, yaw))
				I.add_box_collider(Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, LIFT + 0.45, c.y)), Vector3(0.9, 0.9, len))
			idx += 1
			a = b
	if not mb.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit()
		mi.material_override = I.mat
		mi.name = "Blocks"
		I.add_child(mi)

## The challenges: the Grand Prix, a hot lap of the circuit and the drift course.
static func challenges(I) -> void:
	I.races.append({"id": "raceway", "name": "Raceway Grand Prix", "laps": 3, "start": Vector2(START_X - 40.0, 372),
		"corners": GP, "track": true, "line_w": 4.8, "room": 5.4, "gate_w": GP_W + 4.0, "label": "Race: "})
	I.trials.append(_lap(I, "hotlap", "Raceway Hot Lap", "Raceway Circuit", Vector2(START_X, 372), 7, "time", [31.0, 36.0, 44.0]))
	I.trials.append(_lap(I, "driftcourse", "Raceway Drift Course", "Drift Course", Vector2(CROSS_X + 14.0, 398), 8, "drift", [6000, 14000, 26000]))

## A trial right round a loop, from `a` back to it, through n gates.
static func _lap(I, id: String, name: String, road: String, a: Vector2, n: int, kind: String, medals: Array) -> Dictionary:
	var r := _road(I, road)
	var pts: PackedVector2Array = r["pts"]
	var ia := 0
	for k in pts.size():
		if pts[k].distance_to(a) < pts[ia].distance_to(a):
			ia = k
	var gates := []
	for g in n + 1:
		var k2: int = posmod(ia + int(round(float(pts.size() - 2) * g / n)), pts.size())
		var p := pts[k2]
		var t: Vector2 = I._tangent(pts, k2, true)
		gates.append(Transform3D(Basis(Vector3.UP, atan2(-t.x, -t.y)), Vector3(p.x, I.height_at(p.x, p.y), p.y)))
	return {"id": id, "name": name, "kind": kind, "gates": gates, "w": float(r["w"]), "medals": medals}
