extends Node3D
## The railway (Kenney train kit, CC0): a viaduct all the way round the island, a little way outside the
## ring road and high enough that the roads all pass underneath it, with three trains going round it a
## third of the loop apart: a city electric, a steam train with old coaches and a goods train.
##
## The line is laid out before the town is built (its strip is kept clear, so no building or tree ends up
## under it): the ring road pushed outward and smoothed, its deck a fixed height above the ground (more
## over a dip, so the slopes stay gentle), on pillars wherever there's no road or yard underneath. The
## track is the kit's sleepers with rails run along them; the trains are solid (they'll knock you off the
## deck if you ever get up there), and drawn on the map as a line.

const M := preload("res://scripts/core/models.gd")
const MB := preload("res://scripts/core/mesh_builder.gd")

const OFFSET := 34.0        # how far outside the ring road
const CLEAR := 7.5          # the deck's top over the ground (at least)
const STEP := 2.0           # metres between the line's points
const HALF_W := 3.3         # half the deck's width
const RAIL := 0.84          # the rails either side of the middle
const RAIL_TOP := 0.36      # the rails' top over the deck
const SPEED := 16.0
const TRAINS := [
	["k_train_train-electric-city-a", "k_train_train-electric-city-c", "k_train_train-electric-city-b",
		"k_train_train-electric-city-c", "-k_train_train-electric-city-a"],
	["k_train_train-locomotive-b", "k_train_train-locomotive-passenger-a", "k_train_train-locomotive-passenger-b",
		"k_train_train-locomotive-passenger-a"],
	["k_train_train-diesel-a", "k_train_train-carriage-container-red", "k_train_train-carriage-container-blue",
		"k_train_train-carriage-tank-large", "k_train_train-carriage-container-green", "k_train_train-carriage-coal",
		"k_train_train-carriage-lumber"],
]

var island: Node
var pts := PackedVector2Array()     # the line, every STEP metres round the loop
var ys := PackedFloat32Array()      # the deck's top there
var length := 0.0
var trains: Array = []              # {s, cars: [{node, body, len}]}
var horn_t := 0.0

## The line, from the ring road. Called while the island is being laid out (before anything's put down).
func build(I) -> void:
	island = I
	var ring: Dictionary = {}
	for r in I.roads:
		if r["name"] == "Ring Road":
			ring = r
	if ring.is_empty():
		return
	var rp: PackedVector2Array = ring["pts"]
	var n := rp.size()
	# pushed outward (away from the island's middle), then smoothed and evened out
	var off := PackedVector2Array()
	for k in n:
		var t := (rp[(k + 1) % n] - rp[(k - 1 + n) % n]).normalized()
		var nrm := Vector2(-t.y, t.x)
		if nrm.dot(rp[k]) < 0.0:
			nrm = -nrm
		off.append(rp[k] + nrm * OFFSET)
	for pass_i in 4:
		var sm := PackedVector2Array()
		for k in n:
			var s := Vector2.ZERO
			for o in range(-8, 9):
				s += off[posmod(k + o, n)]
			sm.append(s / 17.0)
		off = sm
	pts = _even(off, STEP)
	var m := pts.size()
	length = m * STEP
	# the deck's height: over the highest ground near by, eased so the line climbs and falls gently,
	# and never closer than CLEAR to the ground under it
	var g := PackedFloat32Array()
	g.resize(m)
	for k in m:
		g[k] = maxf(I.height_at(pts[k].x, pts[k].y), I.sea_y)
	ys.resize(m)
	for k in m:
		var hi := -1e9
		for o in range(-6, 7):
			hi = maxf(hi, g[posmod(k + o, m)])
		ys[k] = hi + CLEAR
	for it in 4:
		var sm2 := PackedFloat32Array()
		sm2.resize(m)
		for k in m:
			var s2 := 0.0
			for o in range(-18, 19):
				s2 += ys[posmod(k + o, m)]
			sm2[k] = s2 / 37.0
		for k in m:
			ys[k] = maxf(sm2[k], g[k] + CLEAR - 0.6)
	_lay(I, g)
	_trains(I)
	_place()           # (on the line from the start, not left in a heap in the middle of town)

## Points every `step` metres round a closed line.
func _even(src: PackedVector2Array, step: float) -> PackedVector2Array:
	var total := 0.0
	var n := src.size()
	for k in n:
		total += src[k].distance_to(src[(k + 1) % n])
	var cnt := int(total / step)
	var st := total / cnt
	var out := PackedVector2Array()
	var seg := 0
	var acc := 0.0
	for k in cnt:
		var want := k * st
		while acc + src[seg % n].distance_to(src[(seg + 1) % n]) < want:
			acc += src[seg % n].distance_to(src[(seg + 1) % n])
			seg += 1
		var a := src[seg % n]
		var b := src[(seg + 1) % n]
		out.append(a.lerp(b, (want - acc) / maxf(a.distance_to(b), 0.001)))
	return out

## Where the line is s metres round (deck top), and which way it runs there.
func at(s: float) -> Vector3:
	var f := fposmod(s / STEP, float(pts.size()))
	var k := int(f)
	var k2 := (k + 1) % pts.size()
	var p := pts[k].lerp(pts[k2], f - k)
	return Vector3(p.x, lerpf(ys[k], ys[k2], f - k), p.y)

## The deck, the track, the pillars, the colliders and the map line; the strip it runs along is kept
## clear of everything else.
func _lay(I, g: PackedFloat32Array) -> void:
	var m := pts.size()
	var deck := MB.rgb("cfc8bd")
	var side := MB.rgb("a8a196")
	var under := MB.rgb("8e877d")
	var wall := MB.rgb("ddd6cb")
	var ballast := MB.rgb("7b746d")
	var steel := MB.rgb("8d949c")
	var chunk := 60
	var sleeper: Mesh = M.get_mesh("k_train_spline-segment")
	var ssz: Vector3 = M.ksize("k_train_spline-segment")
	# (the deck goes in three stretches' worth per mesh: fewer draws when the whole loop's in view; the
	# sleepers stay in short stretches, each drawn only near enough to see them)
	var mb := MB.new()
	for c0 in range(0, m, chunk):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = sleeper
		var sleepers := []
		for k in range(c0, mini(c0 + chunk, m)):
			var a := at(k * STEP)
			var b := at((k + 1) * STEP)
			var t := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
			var rt := Vector3(-t.z, 0, t.x)
			var ta := _right(k)
			var tb := _right(k + 1)
			# the deck: top, sides, underneath
			mb.quad(a - ta * HALF_W, b - tb * HALF_W, b + tb * HALF_W, a + ta * HALF_W, Vector3.UP, deck)
			for sd0 in [-1.0, 1.0]:
				var sd: float = sd0
				var ea := a + ta * HALF_W * sd
				var eb := b + tb * HALF_W * sd
				mb.quad(ea, eb, eb - Vector3(0, 1.3, 0), ea - Vector3(0, 1.3, 0), rt * sd, side)
				# a low wall along each edge
				var wa := a + ta * (HALF_W - 0.15) * sd
				var wb := b + tb * (HALF_W - 0.15) * sd
				mb.quad(wa + Vector3(0, 0.55, 0), wb + Vector3(0, 0.55, 0), eb + Vector3(0, 0.55, 0), ea + Vector3(0, 0.55, 0), Vector3.UP, wall)
				mb.quad(wa, wb, wb + Vector3(0, 0.55, 0), wa + Vector3(0, 0.55, 0), -rt * sd, wall)
				mb.quad(ea, eb, eb + Vector3(0, 0.55, 0), ea + Vector3(0, 0.55, 0), rt * sd, wall)
				# a rail
				var ra := a + ta * RAIL * sd + Vector3(0, RAIL_TOP, 0)
				var rb := b + tb * RAIL * sd + Vector3(0, RAIL_TOP, 0)
				var w2 := 0.07
				mb.quad(ra - ta * w2, rb - tb * w2, rb + tb * w2, ra + ta * w2, Vector3.UP, steel)
				mb.quad(ra + ta * w2, rb + tb * w2, rb + tb * w2 - Vector3(0, 0.16, 0), ra + ta * w2 - Vector3(0, 0.16, 0), rt, steel)
				mb.quad(ra - ta * w2, rb - tb * w2, rb - tb * w2 - Vector3(0, 0.16, 0), ra - ta * w2 - Vector3(0, 0.16, 0), -rt, steel)
			mb.quad(a - ta * HALF_W - Vector3(0, 1.3, 0), b - tb * HALF_W - Vector3(0, 1.3, 0), b + tb * HALF_W - Vector3(0, 1.3, 0),
				a + ta * HALF_W - Vector3(0, 1.3, 0), Vector3.DOWN, under)
			# the ballast bed
			mb.quad(a - ta * 1.7 + Vector3(0, 0.06, 0), b - tb * 1.7 + Vector3(0, 0.06, 0), b + tb * 1.7 + Vector3(0, 0.06, 0),
				a + ta * 1.7 + Vector3(0, 0.06, 0), Vector3.UP, ballast)
			# sleepers, every 1 m
			for q in 2:
				var sp := at(k * STEP + q * 1.0) + Vector3(0, 0.08, 0)
				var bs := Basis.looking_at(t, Vector3.UP).scaled(Vector3.ONE)
				sleepers.append(Transform3D(bs * Basis.from_scale(Vector3(2.6 / maxf(ssz.x, 0.01), 1.0, 1.0)), sp))
			# the collider: a box along this stretch of deck
			if k % 3 == 0:
				var c := at((k + 1.5) * STEP)
				var e := at((k + 3) * STEP) - at(k * STEP)
				var cb := Basis.looking_at(e.normalized(), Vector3.UP)
				I.add_box_collider(Transform3D(cb, c - Vector3(0, 0.65, 0)), Vector3(HALF_W * 2.0, 1.3, e.length() + 0.4))
		if (c0 / chunk) % 3 == 2 or c0 + chunk >= m:
			var mi := MeshInstance3D.new()
			mi.mesh = mb.commit()
			mi.material_override = I.mat
			mi.name = "Viaduct_%d" % c0
			add_child(mi)
			mb = MB.new()
		mm.instance_count = sleepers.size()
		for i in sleepers.size():
			mm.set_instance_transform(i, sleepers[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = I.mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 240.0
		mmi.visibility_range_end_margin = 20.0
		mmi.name = "Sleepers_%d" % c0
		add_child(mmi)
	# pillars, every 14 m or so, wherever there's no road or yard under (then the next clear spot)
	var pmb := MB.new()
	var conc := MB.rgb("bdb6ab")
	var k2 := 0
	while k2 < m:
		var p := pts[k2]
		if I.is_blocked(p.x, p.y) or I.is_blocked(p.x + 1.5, p.y) or I.is_blocked(p.x - 1.5, p.y) \
				or I.is_blocked(p.x, p.y + 1.5) or I.is_blocked(p.x, p.y - 1.5):
			k2 += 1
			continue
		var top := ys[k2] - 1.3
		var base := g[k2] - 1.0
		var t2 := (pts[(k2 + 1) % m] - pts[(k2 - 1 + m) % m]).normalized()
		var bs2 := Basis.looking_at(Vector3(t2.x, 0, t2.y), Vector3.UP)
		pmb.cbox(Vector3(p.x, (top + base) * 0.5, p.y), Vector3(1.7, top - base, 1.7), 0.12, conc, bs2)
		pmb.cbox(Vector3(p.x, top - 0.35, p.y), Vector3(HALF_W * 1.6, 0.7, 1.9), 0.1, conc, bs2)
		I.add_cyl_collider(Vector3(p.x, base, p.y), 1.0, top - base)
		k2 += 7
	var pmi := MeshInstance3D.new()
	pmi.mesh = pmb.commit()
	pmi.material_override = I.mat
	pmi.name = "Pillars"
	add_child(pmi)
	# keep its strip clear of buildings, trees and the rest (the roads already there pass under)
	for k in m:
		I.block_rect(pts[k], Vector2(HALF_W + 2.5, STEP), 0.0, 0.5)
	# on the map: a dark line with a pale dash down the middle
	var map := MB.new()
	for k in m:
		var a2 := pts[k]
		var b2 := pts[(k + 1) % m]
		var t3 := (b2 - a2).normalized()
		var r3 := Vector2(-t3.y, t3.x)
		I.mb_quad_flat(map, a2 - r3 * 2.6, b2 - r3 * 2.6, b2 + r3 * 2.6, a2 + r3 * 2.6, 0.3, MB.rgb("6f6259"))
		if k % 4 < 2:
			I.mb_quad_flat(map, a2 - r3 * 0.8, b2 - r3 * 0.8, b2 + r3 * 0.8, a2 + r3 * 0.8, 0.35, MB.rgb("e9e2d6"))
	I._map_mesh(map, "MapRail")

## Which way is right of the line at point k (flat).
func _right(k: int) -> Vector3:
	var m := pts.size()
	var t := (pts[(k + 1) % m] - pts[(k - 1 + m) % m]).normalized()
	return Vector3(-t.y, 0, t.x)

func _trains(I) -> void:
	for ti in TRAINS.size():
		var cars := []
		for nm0 in TRAINS[ti]:
			var nm := String(nm0)
			var back := nm.begins_with("-")       # (the last cab of a city train faces the other way)
			nm = nm.trim_prefix("-")
			var mi := MeshInstance3D.new()
			mi.mesh = M.get_mesh(nm)
			mi.material_override = I.mat
			mi.visibility_range_end = 350.0         # (a train's still a landmark at that, and past it a few pixels)
			mi.visibility_range_end_margin = 30.0
			var sz: Vector3 = M.ksize(nm)
			var body := AnimatableBody3D.new()
			body.sync_to_physics = false
			body.collision_layer = 1
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = sz * Vector3(0.95, 0.9, 0.97)
			cs.shape = bx
			cs.position = Vector3(0, sz.y * 0.45, 0)
			body.add_child(cs)
			body.add_child(mi)
			if back:
				mi.rotation.y = PI
			add_child(body)
			cars.append({"body": body, "len": sz.z})
		# the rumble and clatter goes with the front car (heard as it passes), and it sounds its horn
		var lead: Node3D = cars[0]["body"]
		var rumble := AudioStreamPlayer3D.new()
		var st = load("res://assets/audio/sfx/train_loop.wav")
		if st is AudioStreamWAV:
			st = (st as AudioStreamWAV).duplicate()
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = int(st.get_length() * st.mix_rate)
		rumble.stream = st
		rumble.bus = "SFX"
		rumble.unit_size = 16.0
		rumble.max_distance = 240.0
		rumble.volume_db = -3.0
		rumble.autoplay = true
		lead.add_child(rumble)
		var horn := AudioStreamPlayer3D.new()
		horn.stream = load("res://assets/audio/sfx/train_horn.wav")
		horn.bus = "SFX"
		horn.unit_size = 40.0
		horn.max_distance = 600.0
		horn.volume_db = -4.0
		lead.add_child(horn)
		trains.append({"s": length * ti / TRAINS.size(), "cars": cars, "horn": horn, "rumble": rumble})

## Paused (or back at the title): the rumble goes quiet.
func quiet(on: bool) -> void:
	for tr in trains:
		(tr["rumble"] as AudioStreamPlayer3D).stream_paused = on

func tick(dt: float, near_pos: Vector3) -> void:
	if pts.is_empty():
		return
	horn_t -= dt
	for tr in trains:
		tr["s"] = fposmod(float(tr["s"]) + SPEED * dt, length)
	_place()
	for tr in trains:
		# a toot as it comes up on you (now and then)
		var lead: Node3D = tr["cars"][0]["body"]
		if horn_t <= 0.0 and lead.global_position.distance_to(near_pos) < 150.0:
			horn_t = 40.0
			(tr["horn"] as AudioStreamPlayer3D).play()

func _place() -> void:
	for tr in trains:
		var s: float = tr["s"]           # (the front of the car being placed)
		# each car rides between two points on the line (its bogies), so it follows the bends
		for c in tr["cars"]:
			var l: float = c["len"]
			var mid := s - l * 0.5
			var f := at(mid - l * 0.35)
			var r := at(mid + l * 0.35)
			var fwd := (r - f)
			if fwd.length() > 0.01:
				var pos := (f + r) * 0.5 + Vector3(0, RAIL_TOP - 0.02, 0)
				(c["body"] as Node3D).global_transform = Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), pos)
			s -= l + 0.4

## How far the nearest train's front is from p.
func nearest(p: Vector3) -> float:
	var best := INF
	for tr in trains:
		var c0: Dictionary = tr["cars"][0]
		best = minf(best, (c0["body"] as Node3D).global_position.distance_to(p))
	return best
