extends RefCounted
## Pace notes, like a rally co-driver's: what's coming up on the road ahead, worked out from the line
## itself. Each note is where it is (metres along) and the sign for it: a corner and how tight (L1, the
## tightest, to L5, a kink; the same for R), a hairpin, an S, a crest or a dip; "!!" on one that bites
## (a tight corner at the end of a long, fast run). The HUD shows the next one and how far off it is.

const STEP := 3.0          # (metres between the points it looks at)

## Notes for a racing line: `pts` a point a metre apart (2D), `hy` the ground height at each (or empty),
## round a loop.
static func from_line(pts: PackedVector2Array, hy: PackedFloat32Array, closed := true) -> Array:
	var n := int(pts.size() / STEP)
	if n < 8:
		return []
	var p := PackedVector2Array()
	var y := PackedFloat32Array()
	for i in n:
		var k := int(i * STEP)
		p.append(pts[k])
		y.append(hy[k] if k < hy.size() else 0.0)
	# heading change at each point, eased over its neighbours
	var dth := PackedFloat32Array()
	dth.resize(n)
	for i in n:
		var a := p[(i - 1 + n) % n] if closed or i > 0 else p[0]
		var b := p[i]
		var c := p[(i + 1) % n] if closed or i < n - 1 else p[n - 1]
		var h1 := (b - a).angle()
		var h2 := (c - b).angle()
		dth[i] = wrapf(h2 - h1, -PI, PI) if (b - a).length() > 0.01 and (c - b).length() > 0.01 else 0.0
	var sm := PackedFloat32Array()
	sm.resize(n)
	for i in n:
		var t := 0.0
		for o in [-2, -1, 0, 1, 2]:
			var j: int = i + o
			if closed:
				j = (j + n) % n
			t += dth[clampi(j, 0, n - 1)]
		sm[i] = t / 5.0
	# corners: runs bending one way, tighter than a 90 m radius
	var k0 := STEP / 90.0
	var corners: Array = []
	var i := 0
	while i < n:
		if absf(sm[i]) < k0:
			i += 1
			continue
		var sgn := signf(sm[i])
		var j := i
		var total := 0.0
		var peak := 0.0
		var peak_i := i
		while j < n + (n if closed else 0) and signf(sm[j % n]) == sgn and absf(sm[j % n]) >= k0 * 0.7:
			total += sm[j % n]
			if absf(sm[j % n]) > peak:
				peak = absf(sm[j % n])
				peak_i = j % n
			j += 1
		corners.append({"a": i, "b": j, "total": total, "r": STEP / maxf(peak, 0.0001), "peak": peak_i})
		i = j
	# (a corner going on round the same way after a few metres' let-up: one corner)
	var merged: Array = []
	for c in corners:
		if not merged.is_empty():
			var m: Dictionary = merged.back()
			if signf(float(m["total"])) == signf(float(c["total"])) and (int(c["a"]) - int(m["b"])) * STEP < 12.0:
				m["b"] = c["b"]
				m["total"] = float(m["total"]) + float(c["total"])
				if float(c["r"]) < float(m["r"]):
					m["r"] = c["r"]
				continue
		merged.append(c)
	var notes: Array = []
	var prev_end := -1000.0
	var skip := false
	for ci in merged.size():
		if skip:
			skip = false
			continue
		var c: Dictionary = merged[ci]
		var ang := rad_to_deg(absf(float(c["total"])))
		if ang < 18.0:
			continue
		var left := float(c["total"]) > 0.0
		# (screen and map: an angle going up is a turn to the left, looking down the road from above... in
		# Godot's 2D (x right, y down the map's z), a positive turn's a right one: flip)
		left = not left
		var r := float(c["r"])
		var sev := 1 if r < 14.0 else (2 if r < 24.0 else (3 if r < 38.0 else (4 if r < 60.0 else 5)))
		var s := int(c["a"]) * STEP
		var sign := ("L%d" if left else "R%d") % sev
		if ang > 140.0 and sev <= 2:
			sign = "uturn_l" if left else "uturn_r"
		# an S: straight into one the other way
		if ci + 1 < merged.size():
			var nx: Dictionary = merged[ci + 1]
			if signf(float(nx["total"])) != signf(float(c["total"])) and (int(nx["a"]) - int(c["b"])) * STEP < 14.0 \
					and rad_to_deg(absf(float(nx["total"]))) > 25.0 and sev >= 3:
				sign = "s_l" if left else "s_r"
				skip = true
		var danger := sev <= 2 and s - prev_end > 120.0
		notes.append({"s": s, "sign": sign, "sev": sev, "danger": danger, "len": (int(c["b"]) - int(c["a"])) * STEP})
		prev_end = int(c["b"]) * STEP
	# crests and dips (not in a corner)
	if y.size() == n:
		var w := int(30.0 / STEP)
		for q in range(0, n, 2):
			var lo := INF
			var hi := -INF
			for o in range(-w, w + 1):
				var jj := q + o
				if not closed and (jj < 0 or jj >= n):
					continue
				var v := y[(jj + n) % n]
				lo = minf(lo, v)
				hi = maxf(hi, v)
			var kind := ""
			if y[q] >= hi - 0.05 and y[q] - lo > 2.5:
				kind = "crest"
			elif y[q] <= lo + 0.05 and hi - y[q] > 2.5:
				kind = "dip"
			if kind == "":
				continue
			var sq := q * STEP
			var clash := false
			for nt in notes:
				if absf(float(nt["s"]) - sq) < 40.0:
					clash = true
					break
			if not clash:
				notes.append({"s": sq - 20.0, "sign": kind, "sev": 6, "danger": false, "len": 0.0})
	notes.sort_custom(func(a, b): return float(a["s"]) < float(b["s"]))
	return notes

## Notes for a run of gates (a trial): the turn at each gate, by how sharp it is.
static func from_gates(gates: Array) -> Array:
	var notes: Array = []
	var s := 0.0
	for i in range(1, gates.size()):
		var a: Vector3 = (gates[i - 1] as Transform3D).origin
		var b: Vector3 = (gates[i] as Transform3D).origin
		s += Vector2(b.x - a.x, b.z - a.z).length()
		if i + 1 >= gates.size():
			break
		var c: Vector3 = (gates[i + 1] as Transform3D).origin
		var d1 := Vector2(b.x - a.x, b.z - a.z)
		var d2 := Vector2(c.x - b.x, c.z - b.z)
		if d1.length() < 0.5 or d2.length() < 0.5:
			continue
		var turn := wrapf(d2.angle() - d1.angle(), -PI, PI)
		var ang := rad_to_deg(absf(turn))
		if ang < 15.0:
			continue
		var left := turn < 0.0
		var sev := 1 if ang > 120.0 else (2 if ang > 85.0 else (3 if ang > 58.0 else (4 if ang > 32.0 else 5)))
		var sign := ("L%d" if left else "R%d") % sev
		if ang > 150.0:
			sign = "uturn_l" if left else "uturn_r"
		notes.append({"s": s, "sign": sign, "sev": sev, "danger": sev == 1 and d1.length() > 80.0, "len": 0.0, "gate": i})
	return notes

## The distance plate for d metres off (the biggest one that isn't past it), "" close in.
static func plate(d: float) -> String:
	for v in [2000, 1000, 500, 300, 200, 150, 100, 50]:
		if d >= float(v):
			return "d%d" % v
	return ""
