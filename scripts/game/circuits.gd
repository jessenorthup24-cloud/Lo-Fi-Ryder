extends RefCounted
## Three more race circuits (Kenney racing kit, CC0), each on its own built-up headland joined onto the
## coast, reached by a road off the ring road that meets the track's main straight. Built the same way as
## the Raceway (raceway.gd: its kerbs, walls and start line), dressed from the layout itself: the start
## gantry and grandstands along the main straight, banner towers out beyond the corners, a paddock by the
## way in, trees round the edge.
##
##   Cliffside Circuit (west)  : a long main straight, then in and out through a tight infield section.
##   Eastpoint Speedway (east) : fast: two long straights and a chicane.
##   Southshore Circuit (south): technical: a hairpin notch and stop-start corners, the longest lap.

const MB := preload("res://scripts/core/mesh_builder.gd")
const M := preload("res://scripts/core/models.gd")
const Race := preload("res://scripts/game/race.gd")
const Raceway := preload("res://scripts/game/raceway.gd")

const LIFT := 2.4
const W := 13.0                 # track width
const ROUND := 40.0             # the headlands' rounded corners
# Each site: its land (centre, half size), the track (corners in driving order: x, z, radius), the start
# line (on the main straight), the way in (from near the ring road to its junction with the track), and the
# side of the main straight the stands go (+1: the track's right, as you drive).
const SITES := [
	{"id": "cliffside", "name": "Cliffside Circuit", "c": Vector2(-505, -40), "hs": Vector2(85, 140),
		"loop": [Vector3(-450, 75, 14), Vector3(-450, -155, 18), Vector3(-565, -155, 16), Vector3(-565, -60, 12),
			Vector3(-505, -40, 12), Vector3(-505, 10, 12), Vector3(-565, 30, 14), Vector3(-565, 75, 14)],
		"start": Vector2(-450, -20), "way_in": [Vector2(-340, 40), Vector2(-400, 45), Vector2(-450, 45)], "stands": 1.0, "laps": 3},
	{"id": "eastpoint", "name": "Eastpoint Speedway", "c": Vector2(510, 85), "hs": Vector2(78, 150),
		"loop": [Vector3(452, 215, 20), Vector3(452, -45, 22), Vector3(570, -45, 22), Vector3(570, 60, 16),
			Vector3(545, 90, 14), Vector3(570, 120, 14), Vector3(570, 215, 20)],
		"start": Vector2(452, 60), "way_in": [Vector2(398, 150), Vector2(425, 150), Vector2(452, 150)], "stands": 1.0, "laps": 3},
	{"id": "southshore", "name": "Southshore Circuit", "c": Vector2(-275, 482), "hs": Vector2(145, 102),
		"loop": [Vector3(-400, 405, 16), Vector3(-150, 405, 18), Vector3(-150, 480, 14), Vector3(-215, 480, 12),
			Vector3(-215, 565, 14), Vector3(-300, 565, 12), Vector3(-300, 500, 10), Vector3(-340, 500, 10),
			Vector3(-340, 565, 14), Vector3(-400, 565, 16)],
		"start": Vector2(-260, 405), "way_in": [Vector2(-224, 342), Vector2(-224, 382), Vector2(-224, 405)], "stands": -1.0, "laps": 3},
]

## How far inland a point is of the headlands alone (negative: out at sea), the nearest of them.
static func inland(x: float, z: float) -> float:
	var best := -INF
	for s in SITES:
		var c: Vector2 = s["c"]
		var hs: Vector2 = s["hs"]
		var q := Vector2(absf(x - c.x) - (hs.x - ROUND), absf(z - c.y) - (hs.y - ROUND))
		best = maxf(best, -(Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - ROUND))
	return best

## Each headland's outline (for the map).
static func outlines() -> Array:
	var out := []
	for s in SITES:
		var c: Vector2 = s["c"]
		var hs: Vector2 = s["hs"]
		var poly := PackedVector2Array()
		var hc := hs - Vector2(ROUND, ROUND)
		for k in 4:
			var sx := 1.0 if k == 0 or k == 3 else -1.0
			var sz := 1.0 if k < 2 else -1.0
			var cc := c + Vector2(hc.x * sx, hc.y * sz)
			var a0: float = [0.0, PI * 0.5, PI, PI * 1.5][k]
			for i in 7:
				poly.append(cc + Vector2.from_angle(a0 + PI * 0.5 * i / 6.0) * (ROUND - 4.0))
		out.append(poly)
	return out

static func _road_name(s: Dictionary) -> String:
	return String(s["name"])

## The land, the tracks and the ways in (with the rest of the island's plan).
static func plan(I) -> void:
	for s in SITES:
		var c: Vector2 = s["c"]
		var hs: Vector2 = s["hs"]
		I.raises.append([c, hs - Vector2(8, 8), LIFT, 16.0])
		var lp: Array = Raceway._pts(s["loop"])
		I.add_road(_road_name(s), Array(Race.rounded(lp[0], lp[1])), "track", true)
		# the way in: from the nearest point of the ring road, then on to the track
		var wi: Array = s["way_in"]
		var ring_p := _ring_near(I, wi[0])
		var path := [ring_p]
		for q in wi:
			if (q as Vector2).distance_to(ring_p) > 6.0:
				path.append(q)
		I.add_road(String(s["name"]).split(" ")[0] + " Road", path, "yard")
		# a paddock beside the way in, just off the track
		var j: Vector2 = wi[wi.size() - 1]
		var prev: Vector2 = wi[wi.size() - 2]
		var along := (j - prev).normalized()
		var side := Vector2(-along.y, along.x)
		I.add_lot(j - along * 26.0 + side * 13.0, Vector2(11, 11), I.S_ASPHALT)

## Nothing else grows or gets put on the headlands (done before the rest of the island is dressed).
static func reserve(I) -> void:
	for s in SITES:
		I.block_rect(s["c"], (s["hs"] as Vector2) - Vector2(2, 2), 0.0, 0.0)

static func _ring_near(I, p: Vector2) -> Vector2:
	for r in I.roads:
		if r["name"] == "Ring Road":
			var best := p
			var bd := INF
			for q: Vector2 in r["pts"]:
				if q.distance_squared_to(p) < bd:
					bd = q.distance_squared_to(p)
					best = q
			return best
	return p

## Everything that dresses the tracks.
static func populate(I, rr: RandomNumberGenerator) -> void:
	for s in SITES:
		_dress(I, s, rr)

static func _dress(I, s: Dictionary, rr: RandomNumberGenerator) -> void:
	var ri := Raceway._road_i(I, _road_name(s))
	var pts: PackedVector2Array = I.roads[ri]["pts"]
	var y := LIFT + 0.02
	var hw := W * 0.5
	Raceway._kerbs(I, ri, hw, true)
	Raceway._edge(I, ri, hw + 4.0, "k_race_barrierWall", 8.0, 1.5)
	# the start: the line across, the gantry over it
	var sp: Vector2 = s["start"]
	var k0 := _nearest(pts, sp)
	var t := (pts[(k0 + 1) % pts.size()] - pts[(k0 - 1 + pts.size()) % pts.size()]).normalized()
	var rgt := Vector2(-t.y, t.x)
	var c := pts[k0]
	_start_line(I, c, t)
	var heading := atan2(-t.x, -t.y)
	var gw := W + 4.0
	var ov := "k_race_overheadLights"
	var osz: Vector3 = M.ksize(ov)
	I.put(ov, c.x, c.y, heading + PI, gw / maxf(osz.x, 0.1), "", y)
	for sd: float in [-1.0, 1.0]:
		var lp := c + rgt * sd * gw * 0.48
		I.add_cyl_collider(Vector3(lp.x, y, lp.y), 0.5, 8.0)
	I.put("k_race_flagCheckers", c.x + rgt.x * (hw + 3.0), c.y + rgt.y * (hw + 3.0), heading, 1.0, "", y)
	# grandstands along the main straight, behind the wall on the stands' side, facing the track
	var sd2: float = s["stands"]
	var out := rgt * sd2
	var face := -out
	var stand_yaw := atan2(-face.x, -face.y)
	var built: Array = [c]           # (where stands and such went: the trees keep clear of them)
	var wi0: Array = s["way_in"]
	for k in 6:
		var along := (float(k) - 2.5) * 8.4
		var q := c + t * (along + 14.0) + out * (hw + 4.0 + 7.5)
		# (not across the way in)
		var gap := INF
		for m in wi0.size() - 1:
			gap = minf(gap, q.distance_to(Geometry2D.get_closest_point_to_segment(q, wi0[m], wi0[m + 1])))
		if _clear(I, ri, q, hw + 9.0) and gap > 10.0:
			I.put("k_race_grandStandCovered" if k % 3 != 1 else "k_race_grandStand", q.x, q.y, stand_yaw, 1.0, "box", y)
			built.append(q)
	# lamp posts down the other side of the straight
	for k in 4:
		var q := c + t * ((float(k) - 1.5) * 34.0) - out * (hw + 3.2)
		if _clear(I, ri, q, hw + 2.5):
			I.put("k_race_lightPostLarge", q.x, q.y, heading, 1.0, "cyl", y)
	# banner towers out beyond each corner, a billboard or two
	var loop: Array = s["loop"]
	var cen := Vector2.ZERO
	for q in loop:
		cen += Vector2(q.x, q.y)
	cen /= loop.size()
	for i in loop.size():
		var q3: Vector3 = loop[i]
		var cq := Vector2(q3.x, q3.y)
		var away := (cq - cen).normalized()
		var bp := cq + away * (hw + 9.0)
		if _clear(I, ri, bp, hw + 7.0) and _inside(s, bp, 4.0):
			I.put("k_race_bannerTowerRed" if i % 2 == 0 else "k_race_bannerTowerGreen", bp.x, bp.y, rr.randf() * TAU, 1.0, "cyl", y)
	for i in 2:
		var q3: Vector3 = loop[(i * loop.size() / 2 + 1) % loop.size()]
		var q3b: Vector3 = loop[(i * loop.size() / 2 + 2) % loop.size()]
		var mid := (Vector2(q3.x, q3.y) + Vector2(q3b.x, q3b.y)) * 0.5
		var dirv := (Vector2(q3b.x, q3b.y) - Vector2(q3.x, q3.y)).normalized()
		var nrm := Vector2(-dirv.y, dirv.x)
		if (mid + nrm - cen).length() < (mid - cen).length():
			nrm = -nrm
		var bq := mid + nrm * (hw + 10.0)
		if _clear(I, ri, bq, hw + 8.0) and _inside(s, bq, 6.0):
			var face2 := -nrm
			I.put("k_race_billboard", bq.x, bq.y, atan2(-face2.x, -face2.y), 0.9, "box", y)
	# the paddock: tents and a couple of race cars beside the way in
	var wi: Array = s["way_in"]
	var j: Vector2 = wi[wi.size() - 1]
	var prev: Vector2 = wi[wi.size() - 2]
	var al := (j - prev).normalized()
	var sd3 := Vector2(-al.y, al.x)
	var pc := j - al * 26.0 + sd3 * 13.0
	# (on the ground where they stand: the paddock's beside the built-up track, not on it)
	I.put("k_race_tentLong", pc.x - al.x * 5.0, pc.y - al.y * 5.0, atan2(-sd3.x, -sd3.y), 1.0, "box")
	var rcars := ["k_race_raceCarRed", "k_race_raceCarGreen", "k_race_raceCarOrange", "k_race_raceCarWhite"]
	for k in 2:
		var cp := pc + al * (2.0 + k * 6.0) + sd3 * 2.0
		I.put(rcars[(k + rr.randi_range(0, 3)) % 4], cp.x, cp.y, atan2(-al.x, -al.y) + rr.randf_range(-0.2, 0.2), 1.0, "box", I.height_at(cp.x, cp.y) - 0.02)
	# trees round the edge of the headland, clear of the track and the way in
	var cs: Vector2 = s["c"]
	var hs: Vector2 = s["hs"]
	var wr := Raceway._road_i(I, String(s["name"]).split(" ")[0] + " Road")
	for k in 34:
		var a := rr.randf() * TAU
		var p2 := cs + Vector2(cos(a) * (hs.x - 7.0), sin(a) * (hs.y - 7.0))
		p2 = Vector2(clampf(p2.x, cs.x - hs.x + 8.0, cs.x + hs.x - 8.0), clampf(p2.y, cs.y - hs.y + 8.0, cs.y + hs.y - 8.0))
		if not _clear(I, ri, p2, hw + 9.0) or (wr >= 0 and I.on_carriageway(p2, -1, 5.0)):
			continue
		if p2.distance_to(pc) < 18.0:
			continue
		var near_built := false
		for b in built:
			if p2.distance_to(b) < 14.0:
				near_built = true
		if near_built:
			continue
		I.put("k_race_treeLarge" if k % 3 != 0 else "k_race_treeSmall", p2.x, p2.y, rr.randf() * TAU, rr.randf_range(0.85, 1.15), "cyl", y)

## Clear of the track: further than d from its middle.
static func _clear(I, ri: int, p: Vector2, d: float) -> bool:
	for q: Vector2 in I.roads[ri]["pts"]:
		if q.distance_squared_to(p) < d * d:
			return false
	return true

static func _inside(s: Dictionary, p: Vector2, margin: float) -> bool:
	var c: Vector2 = s["c"]
	var hs: Vector2 = s["hs"]
	return absf(p.x - c.x) < hs.x - margin and absf(p.y - c.y) < hs.y - margin

static func _nearest(pts: PackedVector2Array, p: Vector2) -> int:
	var best := 0
	for k in pts.size():
		if pts[k].distance_squared_to(p) < pts[best].distance_squared_to(p):
			best = k
	return best

## The chequered start/finish line across the track at c (t: the way it runs).
static func _start_line(I, c: Vector2, t: Vector2) -> void:
	var mb := MB.new()
	var r := Vector2(-t.y, t.x)
	var sq := 1.0
	var cols := int(W / sq)
	for row in 2:
		for i in cols:
			var col := MB.rgb("1f1f22") if (i + row) % 2 == 0 else MB.rgb("f4f1ea")
			var p0 := c + r * (-W * 0.5 + i * sq) + t * (row - 1) * sq
			var p1 := p0 + r * sq
			var p2 := p1 + t * sq
			var p3 := p0 + t * sq
			mb.quad(Raceway._v(I, p0), Raceway._v(I, p1), Raceway._v(I, p2), Raceway._v(I, p3), Vector3.UP, col)
	Raceway._mesh(I, mb, "StartLine")

## The races, one round each circuit.
static func challenges(I) -> void:
	for s in SITES:
		I.races.append({"id": s["id"], "name": s["name"], "laps": int(s["laps"]), "start": s["start"],
			"corners": s["loop"], "track": true, "line_w": 4.4, "room": 5.0, "gate_w": W + 4.0, "label": "Race: "})
