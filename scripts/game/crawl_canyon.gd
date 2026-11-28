extends Node
## Red Rock Canyon: a rocky headland off the north-west coast, sculpted for rock crawling. Big hills with faces
## built to a set steepness (the hardest at the edge of what a crawler can climb, on loose sand), a long
## ridge, knolls, and the obstacle pack's pieces on the flatter stretches. Three long trails over it all, run
## as "crawl" trials (main.gd): gates along the trail, tape down both sides, crawlers only, low range.
## Reached by a dirt road off the Ring Road. (The Crawl Park, crawl_park.gd, has the short practice lanes.)

const CP := preload("res://scripts/game/crawl_park.gd")
const C := Vector2(-405, -388)          # the headland's middle
const HS := Vector2(118, 104)           # its half size
const ROUND := 52.0
const TAPE := 4.0                       # the trails' tape: this far each side of the line

## The hills, in metres from C: [x, z, height, steepest slope south, north, east, west (rise per metre),
## surface (3 dirt, 4 sand)]. A face's slope is the steepest it gets (halfway up); it eases at foot and top.
const HILLS := [
	# the Monolith: the big one, a brutal south face, a long gentle way down the north
	[0.0, -18.0, 19.0, 0.74, 0.42, 0.62, 0.62, 3],
	# the Dune: a sand hill, steep all round, loose: you'll slide back off it if you're not straight
	# (its north face, the way the trail goes up, a touch kinder: still loose and steep)
	[-74.0, 30.0, 13.0, 0.78, 0.58, 0.78, 0.78, 4],
	# Red Knoll and the Twins
	[74.0, 28.0, 11.0, 0.72, 0.72, 0.72, 0.72, 3],
	[62.0, -60.0, 12.0, 0.68, 0.68, 0.68, 0.68, 3],
	[92.0, -30.0, 8.0, 0.64, 0.64, 0.64, 0.64, 3],
]
## The Spine: a long ridge across the south, its sides falling away steeply: drive along the top.
const RIDGE := [Vector2(-60.0, 70.0), Vector2(40.0, 70.0), 7.5, 0.95]     # from, to, height, side slope

## The trails, as points in metres from C (the gates go at each; the first is the start).
## [id, name, medals (gold, silver, bronze s), points, obstacles: [index of the leg (between points i and
## i+1), how far along it (0..1), model]]
const TRAILS := [
	# (medals from a bot's clean runs: 48 s, 185 s, 228 s; gold a little over, bronze well over)
	["canyon_climb", "Red Rock: Monolith Climb", [55.0, 72.0, 105.0],
		[Vector2(0, 48), Vector2(0, 30), Vector2(0, 14), Vector2(0, -18), Vector2(0, -50), Vector2(-2, -80)],
		[[0, 0.5, "07_whoops"]]],
	["canyon_trail", "Red Rock: Canyon Trail", [212.0, 278.0, 405.0],
		[Vector2(40, 92), Vector2(84, 74), Vector2(72, 30), Vector2(50, 4), Vector2(64, -58), Vector2(30, -82),
			Vector2(-34, -78), Vector2(-74, -40), Vector2(-74, 34), Vector2(-40, 88)],
		[[0, 0.5, "06_cross_axle"], [3, 0.55, "12_log_crossing"], [5, 0.5, "11_erosion_ruts"], [6, 0.5, "08_boulder_garden"]]],
	["canyon_summit", "Red Rock: Summit Run", [262.0, 345.0, 500.0],
		[Vector2(-72, 92), Vector2(-56, 70), Vector2(36, 70), Vector2(58, 72), Vector2(60, 46), Vector2(14, 44), Vector2(0, 40),
			Vector2(0, 22), Vector2(0, -18), Vector2(40, -44), Vector2(64, -58), Vector2(92, -72), Vector2(70, -90), Vector2(-20, -84),
			Vector2(-60, -60)],
		[[4, 0.5, "03_rock_staircase"], [11, 0.5, "10_v_notch"], [12, 0.5, "14_twin_track"], [13, 0.5, "08_boulder_garden"]]],
]

var game: Node
var placed: Array = []

# ------------------------------------------------------------------ the land

## How far inland (negative: out at sea) of the headland alone: a rounded rectangle.
static func inland(x: float, z: float) -> float:
	var q := Vector2(absf(x - C.x) - (HS.x - ROUND), absf(z - C.y) - (HS.y - ROUND))
	return -(Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - ROUND)

## Its outline (for the map).
static func outline() -> PackedVector2Array:
	var out := PackedVector2Array()
	var hc := HS - Vector2(ROUND, ROUND)
	for k in 4:
		var sx := 1.0 if k == 0 or k == 3 else -1.0
		var sz := 1.0 if k < 2 else -1.0
		var cc := C + Vector2(hc.x * sx, hc.y * sz)
		var a0: float = [0.0, PI * 0.5, PI, PI * 1.5][k]
		for i in 7:
			var a := a0 + PI * 0.5 * i / 6.0
			out.append(cc + Vector2(cos(a), sin(a)) * ROUND)
	return out

## The hills' height at a point (0 off the headland), faded out toward its shore. Round each obstacle the
## ground's levelled to the height at its middle, so the piece sits flat.
static func hills(x: float, z: float) -> float:
	var h := _raw(x, z)
	for pad in _pads():
		var dd := Vector2(x, z).distance_to(pad[0])
		if dd < float(pad[1]) + 6.0:
			h = lerpf(_raw(pad[0].x, pad[0].y), h, smoothstep(float(pad[1]), float(pad[1]) + 6.0, dd))
	return h

## Where the obstacles sit, and how far round each to level: [centre, radius] (worked out once).
static var _pad_cache: Array = []
static func _pads() -> Array:
	if not _pad_cache.is_empty():
		return _pad_cache
	for tr in TRAILS:
		var pts: Array = tr[3]
		for ob in tr[4]:
			var a: Vector2 = world(pts[int(ob[0])])
			var b: Vector2 = world(pts[int(ob[0]) + 1])
			_pad_cache.append([a.lerp(b, float(ob[1])), 8.5])
	if _pad_cache.is_empty():
		_pad_cache.append([Vector2(1e6, 1e6), 0.0])
	return _pad_cache

static func _raw(x: float, z: float) -> float:
	var d := inland(x, z)
	if d < 0.0:
		return 0.0
	var l := Vector2(x - C.x, z - C.y)
	# rough ground everywhere: rolls a metre or two high, never quite flat
	# (gentle enough that it doesn't add much to a hill's face: the faces are built to an exact steepness)
	var rough := 0.9 + 0.9 * sin(x * 0.07 + 0.7) * sin(z * 0.08 + 1.9) + 0.35 * sin(x * 0.16 + 2.3) * sin(z * 0.14 + 0.4)
	var h := 0.0
	for hl in HILLS:
		var v := l - Vector2(hl[0], hl[1])
		var hh: float = hl[2]
		# the run of each side (where the slope's at its steepest halfway: smoothstep's 1.5x)
		var rz: float = 1.5 * hh / float(hl[3] if v.y > 0.0 else hl[4])
		var rx: float = 1.5 * hh / float(hl[5] if v.x > 0.0 else hl[6])
		var e := sqrt((v.x / rx) ** 2 + (v.y / rz) ** 2)
		h = maxf(h, hh * (1.0 - smoothstep(0.0, 1.0, e)))
	# the Spine: a ridge along a line
	var a: Vector2 = RIDGE[0]
	var b: Vector2 = RIDGE[1]
	var ab := b - a
	var t := clampf((l - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var off := (l - (a + ab * t)).length()
	var end_fade := smoothstep(0.0, 0.12, t) * smoothstep(1.0, 0.88, t)
	var rr: float = 1.5 * float(RIDGE[2]) / float(RIDGE[3])
	h = maxf(h, float(RIDGE[2]) * (1.0 - smoothstep(0.0, rr, off)) * lerpf(0.55, 1.0, end_fade))
	# the rolls fade out where a hill rises, so they don't steepen its face
	h += rough * (1.0 - smoothstep(0.5, 3.0, h))
	return h * smoothstep(6.0, 40.0, d)

## What the ground is: sand on the Dune, dirt elsewhere on the headland (-1: not ours).
static func surface(x: float, z: float) -> int:
	if inland(x, z) < 4.0:
		return -1
	var l := Vector2(x - C.x, z - C.y)
	for hl in HILLS:
		if int(hl[7]) == 4 and (l - Vector2(hl[0], hl[1])).length() < 1.5 * float(hl[2]) / float(hl[3]) * 1.05:
			return 4
	return 3

## On the map, before the ground's made: the way in, off the Ring Road (dirt).
static func plan(I) -> void:
	# (it stops at the headland's edge: a road cuts its own bed into the ground, and the canyon's hills mustn't
	# be cut through)
	I.add_road("Canyon Road", [Vector2(-323, -160), Vector2(-332, -215), Vector2(-345, -262), Vector2(-356, -290)], "dirt")

static func place(_I) -> Dictionary:
	return {"name": "Red Rock Canyon", "pos": Vector3(C.x, 0, C.y), "r": 95.0}

static func world(p: Vector2) -> Vector2:
	return C + p

## The trails as trials: a gate at each point, facing along the trail.
static func challenges(I) -> void:
	for tr in TRAILS:
		var pts: Array = tr[3]
		var gates: Array = []
		for i in pts.size():
			var w: Vector2 = world(pts[i])
			var nxt := world(pts[mini(i + 1, pts.size() - 1)])
			var prv := world(pts[maxi(i - 1, 0)])
			var dir := (nxt - prv).normalized()
			var yaw := atan2(-dir.x, -dir.y)
			gates.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(w.x, I.height_at(w.x, w.y), w.y)))
		I.trials.append({"id": tr[0], "name": tr[1], "kind": "crawl", "gates": gates, "w": 6.0, "medals": tr[2], "tape": TAPE,
			"path": true, "back": 5.0})

# ------------------------------------------------------------------ built in the world

func setup(g: Node) -> void:
	game = g
	var isl = game.island
	# (the gates were set before the ground was made: sit them on it now)
	for t in isl.trials:
		if String(t["id"]).begins_with("canyon"):
			var gs: Array = t["gates"]
			for i in gs.size():
				var gx: Transform3D = gs[i]
				gx.origin.y = isl.height_at(gx.origin.x, gx.origin.z)
				gs[i] = gx
	var park: Node = game.crawl_park
	for tr in TRAILS:
		var pts: Array = tr[3]
		# obstacles on their legs, turned along them
		for ob in tr[4]:
			var a := world(pts[int(ob[0])])
			var b := world(pts[int(ob[0]) + 1])
			var p: Vector2 = a.lerp(b, float(ob[1]))
			var dir := (b - a).normalized()
			var yaw := atan2(-dir.x, -dir.y)
			var at := Vector3(p.x, isl.height_at(p.x, p.y) - 0.03, p.y)
			park.call("_obstacle", String(ob[2]), at, game.toon, String(tr[0]), yaw)
			placed.append({"model": ob[2], "pos": at, "course": tr[0]})
		# tape down both sides of every leg, posts following the ground
		var mb: Object = CP.MB.new()
		for i in pts.size() - 1:
			var a2 := world(pts[i])
			var b2 := world(pts[i + 1])
			var d2 := (b2 - a2)
			var side := Vector2(-d2.y, d2.x).normalized()
			var n := maxi(int(d2.length() / 3.0), 1)
			for sd in [-1.0, 1.0]:
				var prev := Vector3.INF
				for k in n + 1:
					var q: Vector2 = a2 + d2 * float(k) / n + side * float(sd) * TAPE
					var p3 := Vector3(q.x, isl.height_at(q.x, q.y), q.y)
					mb.box(p3 + Vector3(0, 0.45, 0), Vector3(0.08, 0.9, 0.08), CP.MB.rgb("e9e2d6"))
					if prev != Vector3.INF:
						var mid := (prev + p3) * 0.5 + Vector3(0, 0.78, 0)
						var span := p3 - prev
						var bs := Basis.looking_at(span.normalized(), Vector3.UP) if span.length() > 0.01 else Basis()
						mb.box(mid, Vector3(0.03, 0.08, span.length()), CP.MB.rgb("ff4646") if k % 2 == 0 else CP.MB.rgb("f5f5f5"), bs)
					prev = p3
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit()
		mi.material_override = game.toon
		mi.visibility_range_end = 300.0
		add_child(mi)
		# the start gate (the stunt kit's) and the name over it
		var s0 := world(pts[0])
		var s1 := world(pts[1])
		var sd2 := (s1 - s0).normalized()
		park.call("_piece", "checkpoint_gate", Vector3(s0.x, isl.height_at(s0.x, s0.y), s0.y), atan2(-sd2.x, -sd2.y), 1.35, "")
		var lb := Label3D.new()
		lb.text = String(tr[1]).trim_prefix("Red Rock: ").to_upper()
		lb.font_size = 72
		lb.pixel_size = 0.01
		lb.outline_size = 12
		lb.modulate = Color("fff4e0")
		lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		lb.position = Vector3(s0.x, isl.height_at(s0.x, s0.y) + 6.6, s0.y)
		add_child(lb)
	# a flag on top of the Monolith
	var top := world(Vector2(HILLS[0][0], HILLS[0][1]))
	park.call("_piece", "floodlight", Vector3(top.x + 6.0, isl.height_at(top.x + 6.0, top.y), top.y), 0.0, 1.4, "box")
