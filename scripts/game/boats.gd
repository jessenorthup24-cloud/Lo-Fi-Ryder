extends Node3D
## Boats round the island (Kenney watercraft pack, CC0): speedboats, sailing boats, fishing boats and tugs
## going round not far off the shore, and big ships (cargo ships, a liner) further out. Each keeps to its
## own loop at its own distance from the land (worked out from the coastline, so they go round anything
## that sticks out: the harbour, the pier), rocking on the swell, with a white wake behind it. Buoys bob
## off the beach. They're to look at: nothing here is solid.

const M := preload("res://scripts/core/models.gd")

## [model, scale, speed m/s, how much of it sits below the water (fraction of its height), wake length m]
const SMALL := [
	["k_boat_boat-speed-a", 2.3, 16.0, 0.22, 30.0], ["k_boat_boat-speed-b", 2.3, 14.0, 0.22, 28.0],
	["k_boat_boat-speed-c", 2.3, 18.0, 0.22, 32.0], ["k_boat_boat-speed-d", 2.3, 13.0, 0.22, 26.0],
	["k_boat_boat-speed-e", 2.3, 15.0, 0.22, 28.0], ["k_boat_boat-speed-f", 2.3, 17.0, 0.22, 30.0],
	["k_boat_boat-sail-a", 2.8, 5.0, 0.07, 12.0], ["k_boat_boat-sail-b", 2.8, 4.5, 0.07, 12.0],
	["k_boat_boat-fishing-small", 2.8, 5.5, 0.14, 14.0], ["k_boat_boat-tug-a", 3.0, 6.5, 0.16, 16.0],
	["k_boat_boat-tug-b", 3.0, 6.0, 0.16, 16.0], ["k_boat_boat-tow-a", 2.8, 5.0, 0.14, 16.0],
]
const BIG := [
	["k_boat_ship-cargo-a", 6.0, 7.0, 0.22, 60.0], ["k_boat_ship-cargo-b", 6.0, 6.5, 0.22, 60.0],
	["k_boat_ship-ocean-liner", 6.0, 8.0, 0.12, 90.0], ["k_boat_ship-large", 5.0, 6.0, 0.1, 50.0],
	["k_boat_ship-cargo-c", 6.0, 7.5, 0.22, 60.0],
]
# places off the shore boats keep well clear of: the harbour quay and jetty, the pier [centre, radius]
const KEEP_OUT := [[Vector2(-475, 178), 48.0], [Vector2(-60, 430), 42.0]]

var island: Node
var boats: Array = []       # {mi, wake, route, th, v, dir, sink, ph}
var routes := {}            # distance off the shore -> radius from the island's middle, per degree
var buoys: Array = []
var _t := 0.0
var wake_mats: Array = []

func setup(isl: Node, mat: Material, atmos: Node) -> void:
	island = isl
	for k in 2:
		var wm := ShaderMaterial.new()
		wm.shader = preload("res://shaders/wake.gdshader")
		wm.set_shader_parameter("speed", 14.0 if k == 0 else 5.0)
		atmos.add_material(wm)
		wake_mats.append(wm)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	# small boats: each on its own loop, 55-135 m off the shore, either way round
	for i in SMALL.size():
		var d: Array = SMALL[i]
		_boat(d, mat, 55.0 + i * 7.0, rng.randf() * TAU, 1 if i % 2 == 0 else -1, rng, 800.0)
	# a second speedboat or two (they're the fun ones)
	for i in 3:
		_boat(SMALL[i * 2], mat, 145.0 + i * 10.0, rng.randf() * TAU, -1 if i % 2 == 0 else 1, rng, 800.0)
	# big ships further out
	for i in BIG.size():
		_boat(BIG[i], mat, 260.0 + i * 38.0, rng.randf() * TAU, 1 if i % 2 == 1 else -1, rng, 2200.0)
	# buoys off the beach, in a line round the bay
	for k in 9:
		var a := deg_to_rad(68.0 + k * 6.5)
		var r := _radius(_route(32.0), a)
		var p := Vector2(cos(a), sin(a)) * r
		if _kept_out(p, 6.0):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = M.get_mesh("k_boat_buoy-flag" if k % 3 == 0 else "k_boat_buoy")
		mi.material_override = mat
		mi.scale = Vector3.ONE * 1.6
		mi.visibility_range_end = 500.0
		add_child(mi)
		mi.position = Vector3(p.x, island.sea_y, p.y)
		buoys.append({"mi": mi, "ph": rng.randf() * TAU})

func _boat(d: Array, mat: Material, off: float, th: float, dirn: int, rng: RandomNumberGenerator, vis: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = M.get_mesh(d[0])
	mi.material_override = mat
	mi.scale = Vector3.ONE * float(d[1]) / M.kscale(d[0])
	mi.visibility_range_end = vis
	add_child(mi)
	var sz: Vector3 = M.ksize(d[0]) * float(d[1]) / M.kscale(d[0])
	var wake := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(sz.x * 3.4, float(d[4]))
	wake.mesh = pm
	wake.material_override = wake_mats[0 if float(d[2]) > 10.0 else 1]
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wake.visibility_range_end = vis * 0.6
	add_child(wake)
	boats.append({"mi": mi, "wake": wake, "route": _route(off), "th": th, "v": float(d[2]) * rng.randf_range(0.85, 1.1),
		"dir": dirn, "sink": sz.y * float(d[3]), "len": sz.z, "wl": float(d[4]), "ph": rng.randf() * TAU,
		"fast": float(d[2]) > 10.0})

## The loop off metres out from the land: its radius from the middle of the island for every degree.
func _route(off: float) -> PackedFloat32Array:
	var key := int(off)
	if routes.has(key):
		return routes[key]
	var rs := PackedFloat32Array()
	rs.resize(360)
	for dg in 360:
		var a := deg_to_rad(float(dg))
		var dv := Vector2(cos(a), sin(a))
		var last := 300.0
		var r := 300.0
		while r < 1500.0:
			var p := dv * r
			if island.inland(p.x, p.y) > -off or _kept_out(p, off - 45.0):
				last = r
			r += 6.0
		rs[dg] = last + 6.0
	# never cutting in (the widest of the nearby degrees), then smoothed so the loop has no kinks
	var wide := PackedFloat32Array()
	wide.resize(360)
	for dg in 360:
		var m := 0.0
		for o in range(-4, 5):
			m = maxf(m, rs[posmod(dg + o, 360)])
		wide[dg] = m
	for pass_i in 3:
		var sm := PackedFloat32Array()
		sm.resize(360)
		for dg in 360:
			var s := 0.0
			for o in range(-5, 6):
				s += wide[posmod(dg + o, 360)]
			sm[dg] = maxf(s / 11.0, rs[dg])
		wide = sm
	routes[key] = wide
	return wide

func _kept_out(p: Vector2, extra: float) -> bool:
	for k in KEEP_OUT:
		if p.distance_to(k[0]) < float(k[1]) + maxf(extra, 0.0):
			return true
	return false

func _radius(rs: PackedFloat32Array, a: float) -> float:
	var f := fposmod(rad_to_deg(a), 360.0)
	var i := int(f)
	return lerpf(rs[i], rs[(i + 1) % 360], f - float(i))

func _at(rs: PackedFloat32Array, a: float) -> Vector2:
	return Vector2(cos(a), sin(a)) * _radius(rs, a)

func tick(dt: float) -> void:
	_t += dt
	var sy: float = island.sea_y
	for b in boats:
		var rs: PackedFloat32Array = b["route"]
		var r := _radius(rs, b["th"])
		b["th"] = float(b["th"]) + float(b["dir"]) * float(b["v"]) / maxf(r, 1.0) * dt
		var th: float = b["th"]
		var p := _at(rs, th)
		var ahead := _at(rs, th + float(b["dir"]) * 0.01)
		var f := (ahead - p).normalized()
		var yaw := atan2(-f.x, -f.y)
		var ph: float = b["ph"]
		# on the swell: a slow rise and fall, a little roll and pitch (and a fast boat rides bow-up)
		var bob := sin(_t * 1.3 + ph) * 0.18
		var roll := sin(_t * 0.9 + ph * 1.7) * (0.05 if not b["fast"] else 0.03)
		var pitch := sin(_t * 1.1 + ph * 0.6) * 0.025 + (0.07 if b["fast"] else 0.0)
		var mi: MeshInstance3D = b["mi"]
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
		mi.global_transform = Transform3D(basis.scaled(mi.scale), Vector3(p.x, sy - float(b["sink"]) + bob, p.y))
		# the wake trails out behind, flat on the water
		var wl: float = b["wl"]
		var stern := p - f * float(b["len"]) * 0.45
		var wc := stern - f * wl * 0.5
		(b["wake"] as Node3D).global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(wc.x, sy + 0.05, wc.y))
	for bu in buoys:
		var mi2: MeshInstance3D = bu["mi"]
		var ph2: float = bu["ph"]
		mi2.position.y = sy - 0.5 + sin(_t * 1.6 + ph2) * 0.2
		mi2.rotation = Vector3(sin(_t * 1.2 + ph2) * 0.12, ph2, cos(_t * 1.0 + ph2) * 0.12)
