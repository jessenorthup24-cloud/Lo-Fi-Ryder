extends RefCounted
## Every model in the game, built from code, plus the Tiny Car Pack cars and the Kenney (CC0) kits baked into
## assets/. Meshes are cached by name.

const MB := preload("res://scripts/core/mesh_builder.gd")
const P := preload("res://scripts/core/palette.gd")

const T := 1.6   # tile size (world units = meters)

static var _cache := {}

static func get_mesh(name: String) -> ArrayMesh:
	if _cache.has(name):
		return _cache[name]
	if name.begins_with("k_"):
		_cache[name] = _k_mesh(name)
		return _cache[name]
	var m: ArrayMesh = load("res://scripts/core/models.gd").call("_m_" + name)
	_cache[name] = m
	return m

static func p(i: int) -> Color:
	return MB.pal(i)

# ---------------------------------------------------------------- terrain

static func _m_tile() -> ArrayMesh:
	var b := MB.new()
	# flat, square-edged and a hair oversized so neighbouring tiles read as one continuous ground
	b.cbox(Vector3(0, -0.13, 0), Vector3(T + 0.004, 0.26, T + 0.004), 0.0, MB.SIDE, Basis(), MB.TOP)
	b.box(Vector3(0, -0.7, 0), Vector3(T * 0.97, 0.9, T * 0.97), MB.SIDE)
	return b.commit()

static func _m_under() -> ArrayMesh:
	# hanging rock under edge tiles; side slot from the instance
	var b := MB.new()
	b.cbox(Vector3(0, -1.35, 0), Vector3(T * 0.82, 0.5, T * 0.82), 0.08, MB.SIDE)
	b.cbox(Vector3(0.1, -1.8, -0.05), Vector3(T * 0.55, 0.45, T * 0.55), 0.08, MB.SIDE)
	b.cyl(Vector3(0.05, -2.3, 0), T * 0.22, 0.6, MB.SIDE, 6, Basis(), 0.0, false, false)
	return b.commit()

static func _m_water() -> ArrayMesh:
	var b := MB.new()
	b.box(Vector3(0, -0.32, 0), Vector3(T, 0.06, T), MB.TOP)
	b.box(Vector3(0, -0.75, 0), Vector3(T * 0.97, 0.8, T * 0.97), MB.SIDE)
	return b.commit()

# ---------------------------------------------------------------- shared props

static func _m_coin() -> ArrayMesh:
	var b := MB.new()
	var rot := Basis(Vector3.RIGHT, PI * 0.5)
	b.cyl(Vector3.ZERO, 0.28, 0.08, MB.rgb("ffc93c"), 16, rot)
	b.cyl(Vector3(0, 0, 0.0), 0.18, 0.1, MB.rgb("ffe27a"), 16, rot)
	return b.commit()

static func _m_fuel() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, 0.32, 0), Vector3(0.42, 0.56, 0.24), 0.05, MB.rgb("ec4b3f"))
	b.cbox(Vector3(0, 0.32, 0), Vector3(0.44, 0.2, 0.2), 0.02, MB.rgb("d23a30"))
	b.cyl(Vector3(0.12, 0.66, 0), 0.05, 0.12, MB.rgb("ffd36b"), 8)
	b.cbox(Vector3(-0.06, 0.64, 0), Vector3(0.18, 0.06, 0.08), 0.02, MB.rgb("c43328"))
	return b.commit()

static func _m_ramp() -> ArrayMesh:
	# 2.6 wide, 2.4 long, rises 0.9 toward -Z; origin at the low front edge center
	var b := MB.new()
	b.wedge(Vector3(0, 0, -1.2), Vector3(2.6, 0.9, 2.4), p(P.PLANK), Basis())
	for i in 4:
		var z := -0.3 - i * 0.6
		var y := 0.9 * (-z) / 2.4
		b.box(Vector3(0, y + 0.02, z), Vector3(2.5, 0.04, 0.08), MB.rgb("a8703f"), Basis(Vector3.RIGHT, -atan(0.9 / 2.4)))
	b.cbox(Vector3(-1.25, 0.45, -2.25), Vector3(0.14, 0.9, 0.14), 0.03, MB.rgb("8a5a35"))
	b.cbox(Vector3(1.25, 0.45, -2.25), Vector3(0.14, 0.9, 0.14), 0.03, MB.rgb("8a5a35"))
	# chevrons
	b.box(Vector3(-0.5, 0.92, -2.42), Vector3(0.5, 0.06, 0.05), MB.rgb("ffd166"))
	b.box(Vector3(0.5, 0.92, -2.42), Vector3(0.5, 0.06, 0.05), MB.rgb("ffd166"))
	return b.commit()

static func _m_pad() -> ArrayMesh:
	# boost pad, 2.0 wide and 2.2 long, chevrons point along -Z
	var b := MB.new()
	b.cbox(Vector3(0, 0.03, 0), Vector3(2.0, 0.07, 2.2), 0.04, MB.rgb("4a4652"))
	b.cbox(Vector3(0, 0.05, 0), Vector3(1.8, 0.05, 2.0), 0.03, MB.rgb("5c5866"))
	for k in 3:
		var z := 0.55 - k * 0.55
		for sgn in [-1.0, 1.0]:
			var bs := Basis(Vector3.UP, -sgn * 0.75)
			b.box(Vector3(sgn * 0.28, 0.085, z - 0.05), Vector3(0.78, 0.04, 0.16), MB.glow("ffb84d" if k != 1 else "ff7a4d"), bs)
	for sgn in [-1.0, 1.0]:
		b.box(Vector3(sgn * 0.92, 0.085, 0), Vector3(0.08, 0.04, 2.0), MB.glow("fff0a8"))
	return b.commit()

static func _m_bridge() -> ArrayMesh:
	# one 1.6 long plank section along -Z, 2.2 wide, top at y=0
	var b := MB.new()
	for i in 4:
		var z := -0.2 - i * 0.4
		b.cbox(Vector3(randf_range(-0.03, 0.03), -0.07, z), Vector3(2.2, 0.12, 0.36), 0.03, p(P.PLANK))
	b.box(Vector3(-1.0, -0.2, -0.8), Vector3(0.12, 0.14, 1.6), MB.rgb("8a5a35"))
	b.box(Vector3(1.0, -0.2, -0.8), Vector3(0.12, 0.14, 1.6), MB.rgb("8a5a35"))
	b.cyl(Vector3(-1.08, 0.25, -0.8), 0.05, 0.5, MB.rgb("8a5a35"), 6)
	b.cyl(Vector3(1.08, 0.25, -0.8), 0.05, 0.5, MB.rgb("8a5a35"), 6)
	b.box(Vector3(-1.08, 0.46, -0.8), Vector3(0.04, 0.04, 1.6), MB.rgb("e9d2b0"))
	b.box(Vector3(1.08, 0.46, -0.8), Vector3(0.04, 0.04, 1.6), MB.rgb("e9d2b0"))
	return b.commit()

# ---- after the end: ruins, wrecks, and life pushing back through

static func _glow_buds(b: MB, spots: Array) -> void:
	var cols := ["8ff5ff", "ff8fd8", "fff07a", "a8ff9e", "c9a8ff"]
	for i in spots.size():
		var s: Vector3 = spots[i]
		b.cyl(s + Vector3(0, -0.06, 0), 0.012, 0.12, p(P.TUFT), 3, Basis(), -1.0, false)
		b.sphere(s + Vector3(0, 0.03, 0), 0.065, MB.glow(cols[(i * 3 + int(s.x * 10.0)) % cols.size()]), 6, 4)

static func _m_wreck_car() -> ArrayMesh:
	# an abandoned rusted car, flat tyres, ivy over the roof and a sapling through the bonnet
	var b := MB.new()
	for x in [-0.42, 0.42]:
		for z in [-0.56, 0.6]:
			b.cyl(Vector3(x, 0.12, z), 0.17, 0.13, MB.rgb("34302f"), 8, Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.RIGHT, 0.0), -1.0, true, false)
	b.cbox(Vector3(0, 0.36, 0), Vector3(0.95, 0.32, 1.8), 0.06, p(P.RUST), Basis(Vector3.BACK, 0.05))
	b.cbox(Vector3(0, 0.64, 0.08), Vector3(0.82, 0.3, 0.92), 0.05, p(P.RUST), Basis(Vector3.BACK, 0.05))
	b.box(Vector3(0.49, 0.38, -0.25), Vector3(0.02, 0.18, 0.62), MB.rgb("7b97ad"))
	b.box(Vector3(-0.47, 0.36, 0.4), Vector3(0.02, 0.14, 0.5), MB.rgb("7b97ad"))
	b.box(Vector3(0, 0.66, -0.39), Vector3(0.7, 0.22, 0.02), MB.rgb("2b2735"))
	b.box(Vector3(0.425, 0.66, 0.08), Vector3(0.02, 0.2, 0.7), MB.rgb("2b2735"))
	b.box(Vector3(-0.405, 0.66, 0.08), Vector3(0.02, 0.2, 0.7), MB.rgb("2b2735"))
	b.cbox(Vector3(0.08, 0.81, 0.12), Vector3(0.62, 0.05, 0.72), 0.02, p(P.IVY))
	b.cbox(Vector3(-0.12, 0.54, -0.68), Vector3(0.52, 0.04, 0.36), 0.02, p(P.IVY))
	b.box(Vector3(-0.46, 0.42, 0.2), Vector3(0.04, 0.3, 0.6), p(P.IVY))
	b.cyl(Vector3(0.2, 0.78, -0.58), 0.025, 0.55, p(P.TRUNK), 5)
	b.sphere(Vector3(0.2, 1.1, -0.58), 0.22, p(P.LEAF_A), 8, 5)
	b.sphere(Vector3(0.32, 1.02, -0.45), 0.14, p(P.BLOSSOM), 7, 4)
	_glow_buds(b, [Vector3(0.2, 0.88, 0.0), Vector3(-0.12, 0.88, 0.32), Vector3(-0.2, 0.6, -0.75), Vector3(0.36, 0.86, 0.3)])
	for g in [Vector3(0.55, 0.06, 0.0), Vector3(-0.5, 0.06, -0.6), Vector3(0.3, 0.06, 0.95)]:
		b.cyl(g, 0.02, 0.18, p(P.TUFT), 3, Basis(Vector3.BACK, 0.3), 0.0, false)
	return b.commit()

static func _house_ruin(wall: int, roof: int, flip: float) -> ArrayMesh:
	# a cottage shell: broken walls, a collapsed roof slab, and a tree growing up through it
	var b := MB.new()
	b.cbox(Vector3(0, 0.08, 0), Vector3(2.5, 0.16, 2.1), 0.04, p(P.CONCRETE))
	b.cbox(Vector3(0, 0.72, -0.92), Vector3(2.2, 1.2, 0.16), 0.03, p(wall))
	b.cbox(Vector3(-0.62 * flip, 1.42, -0.92), Vector3(0.9, 0.34, 0.16), 0.03, p(wall))
	b.cbox(Vector3(-1.02 * flip, 0.76, 0.0), Vector3(0.16, 1.3, 1.84), 0.03, p(wall))
	b.cbox(Vector3(1.02 * flip, 0.4, 0.3), Vector3(0.16, 0.56, 1.24), 0.03, p(wall))
	b.cbox(Vector3(-0.66 * flip, 0.6, 0.92), Vector3(0.7, 0.96, 0.16), 0.03, p(wall))
	b.cbox(Vector3(0.75 * flip, 0.34, 0.92), Vector3(0.5, 0.44, 0.16), 0.03, p(wall))
	b.box(Vector3(0.4 * flip, 0.86, -0.83), Vector3(0.36, 0.34, 0.02), MB.rgb("3a3342"))
	b.box(Vector3(-1.11 * flip, 0.86, -0.3), Vector3(0.02, 0.34, 0.36), MB.rgb("3a3342"))
	b.cbox(Vector3(-0.3 * flip, 1.2, -0.25), Vector3(1.35, 0.1, 1.35), 0.03, p(roof), Basis(Vector3.BACK, 0.5 * flip) * Basis(Vector3.RIGHT, 0.22))
	for r in [[0.6, 0.12, 0.45, 0.2], [0.85, 0.1, -0.25, 0.16], [-0.25, 0.1, 0.55, 0.13], [0.2, 0.08, 0.2, 0.1]]:
		b.cbox(Vector3(r[0] * flip, r[1] + 0.08, r[2]), Vector3(r[3] * 2.2, r[3] * 1.4, r[3] * 1.8), 0.03, p(P.CONCRETE), Basis(Vector3.UP, r[0] * 3.0))
	b.cyl(Vector3(0.45 * flip, 1.05, -0.1), 0.08, 2.0, p(P.TRUNK), 7)
	b.sphere(Vector3(0.45 * flip, 2.15, -0.1), 0.66, p(P.LEAF_A), 9, 6)
	b.sphere(Vector3(0.82 * flip, 1.88, 0.22), 0.42, p(P.LEAF_B), 8, 5)
	b.sphere(Vector3(0.12 * flip, 1.95, 0.18), 0.36, p(P.LEAF_A), 8, 5)
	b.box(Vector3(-1.115 * flip, 0.62, 0.42), Vector3(0.03, 0.95, 0.55), p(P.IVY))
	b.box(Vector3(-0.2 * flip, 0.55, -1.005), Vector3(0.85, 0.75, 0.03), p(P.IVY))
	b.box(Vector3(0.2 * flip, 0.2, 1.0), Vector3(1.6, 0.08, 0.12), p(P.IVY))
	_glow_buds(b, [Vector3(-0.9 * flip, 0.25, 0.75), Vector3(0.95 * flip, 0.72, 0.5), Vector3(-0.4 * flip, 1.62, -0.92), Vector3(0.1, 0.25, 1.05), Vector3(0.6 * flip, 0.25, -0.6)])
	return b.commit()

static func _m_house_ruin() -> ArrayMesh:
	return _house_ruin(P.WALL, P.ROOF_RED, 1.0)

static func _m_house_ruin_b() -> ArrayMesh:
	return _house_ruin(P.WALL_BLUE, P.ROOF_BLUE, -1.0)

static func _m_house_ruin_c() -> ArrayMesh:
	return _house_ruin(P.WALL_PINK, P.ROOF_GREEN, 1.0)

static func _m_wall_ruin() -> ArrayMesh:
	# a broken concrete wall with rebar, ivy and flowers at its feet
	var b := MB.new()
	b.cbox(Vector3(0, 0.45, 0), Vector3(1.5, 0.9, 0.2), 0.03, p(P.CONCRETE))
	b.cbox(Vector3(-0.38, 1.02, 0), Vector3(0.66, 0.26, 0.2), 0.03, p(P.CONCRETE))
	b.cbox(Vector3(0.5, 0.98, 0), Vector3(0.28, 0.16, 0.2), 0.03, p(P.CONCRETE))
	for x in [-0.05, 0.12, 0.3]:
		b.cyl(Vector3(x, 1.02, 0.0), 0.015, 0.34, p(P.RUST), 4, Basis(Vector3.BACK, x * 1.5))
	b.box(Vector3(-0.3, 0.55, 0.115), Vector3(0.7, 0.8, 0.03), p(P.IVY))
	b.box(Vector3(-0.5, 0.95, 0.115), Vector3(0.3, 0.3, 0.03), p(P.IVY))
	b.cbox(Vector3(0.55, 0.12, 0.35), Vector3(0.3, 0.2, 0.26), 0.03, p(P.CONCRETE), Basis(Vector3.UP, 0.6))
	for g in [Vector3(-0.6, 0.07, 0.25), Vector3(0.1, 0.07, 0.3), Vector3(0.7, 0.07, -0.25), Vector3(-0.2, 0.07, -0.3)]:
		b.cyl(g, 0.022, 0.2, p(P.TUFT), 3, Basis(Vector3.BACK, 0.35), 0.0, false)
	_glow_buds(b, [Vector3(-0.45, 0.16, 0.3), Vector3(0.25, 0.16, 0.28), Vector3(-0.1, 0.16, -0.3), Vector3(0.62, 0.3, 0.38)])
	return b.commit()

static func _m_rubble() -> ArrayMesh:
	# a heap of broken concrete with a wild tuft and a flower poking out
	var b := MB.new()
	var chunks := [[0.0, 0.14, 0.0, 0.42, 0.26, 0.36, 0.3], [0.24, 0.1, 0.18, 0.3, 0.2, 0.26, 1.1], [-0.22, 0.09, 0.15, 0.26, 0.18, 0.24, 2.0],
		[0.12, 0.3, -0.05, 0.26, 0.16, 0.24, 0.8], [-0.15, 0.08, -0.22, 0.28, 0.16, 0.22, 2.6]]
	for c in chunks:
		b.cbox(Vector3(c[0], c[1], c[2]), Vector3(c[3], c[4], c[5]), 0.03, p(P.CONCRETE), Basis(Vector3.UP, c[6]) * Basis(Vector3.RIGHT, c[6] * 0.2))
	b.cyl(Vector3(0.05, 0.42, 0.0), 0.014, 0.3, p(P.RUST), 4, Basis(Vector3.BACK, 0.5))
	b.cyl(Vector3(-0.3, 0.12, -0.05), 0.022, 0.24, p(P.TUFT), 3, Basis(Vector3.BACK, -0.3), 0.0, false)
	b.cyl(Vector3(0.32, 0.12, -0.12), 0.022, 0.22, p(P.TUFT), 3, Basis(Vector3.BACK, 0.3), 0.0, false)
	_glow_buds(b, [Vector3(-0.28, 0.27, -0.06), Vector3(0.3, 0.28, -0.12)])
	return b.commit()

static func _m_sign_rust() -> ArrayMesh:
	# a leaning rusty road sign, its face long faded, vines climbing the post
	var b := MB.new()
	var lean := Basis(Vector3.BACK, 0.22) * Basis(Vector3.RIGHT, -0.08)
	b.cyl(lean * Vector3(0, 0.6, 0), 0.035, 1.2, p(P.RUST), 6, lean)
	b.cbox(lean * Vector3(0, 1.2, 0), Vector3(0.62, 0.42, 0.04), 0.02, p(P.RUST), lean)
	b.box(lean * Vector3(0, 1.2, 0.025), Vector3(0.48, 0.28, 0.01), MB.rgb("c9c0a8"), lean)
	b.box(lean * Vector3(0.05, 0.5, 0.04), Vector3(0.08, 0.8, 0.04), p(P.IVY), lean)
	_glow_buds(b, [Vector3(-0.12, 0.1, 0.1), Vector3(0.14, 0.1, -0.08)])
	return b.commit()

static func _m_barrel_rust() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.3, 0), 0.24, 0.6, p(P.RUST), 10)
	for y in [0.12, 0.48]:
		b.cyl(Vector3(0, y, 0), 0.255, 0.04, MB.rgb("6e4a36"), 10)
	b.cyl(Vector3(0, 0.61, 0), 0.2, 0.03, p(P.MOSS), 10)
	b.cyl(Vector3(0.05, 0.72, 0.02), 0.016, 0.22, p(P.TUFT), 3, Basis(Vector3.BACK, 0.2), 0.0, false)
	_glow_buds(b, [Vector3(0.05, 0.85, 0.02)])
	return b.commit()

static func _m_bud_glow() -> ArrayMesh:
	# a little clump of glowing seed-buds and leaves pushing up through the ground
	var b := MB.new()
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		var r := 0.08 + 0.06 * float(i % 2)
		var hgt := 0.18 + 0.1 * float((i * 7) % 3)
		b.cyl(Vector3(cos(a) * r, hgt * 0.5, sin(a) * r), 0.012, hgt, p(P.TUFT), 3, Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.18), -1.0, false)
		b.box(Vector3(cos(a) * r * 1.6, 0.04, sin(a) * r * 1.6), Vector3(0.1, 0.012, 0.05), p(P.IVY), Basis(Vector3.UP, -a))
	_glow_buds(b, [Vector3(0.1, 0.27, 0.04), Vector3(-0.06, 0.37, 0.08), Vector3(0.02, 0.24, -0.11), Vector3(-0.1, 0.22, -0.04), Vector3(0.07, 0.33, -0.05)])
	return b.commit()

static func _m_pole_down() -> ArrayMesh:
	# a toppled utility pole across the grass, its wire trailing, ivy taking it over
	var b := MB.new()
	var lie := Basis(Vector3.BACK, PI * 0.5 - 0.12)
	b.cyl(Vector3(0.0, 0.14, 0), 0.07, 2.4, p(P.WOOD_DARK), 7, lie)
	b.box(Vector3(1.0, 0.24, 0), Vector3(0.08, 0.08, 0.7), p(P.WOOD_DARK))
	b.box(Vector3(0.3, 0.2, 0.0), Vector3(1.4, 0.04, 0.17), p(P.IVY))
	b.cyl(Vector3(0.9, 0.1, 0.42), 0.01, 0.8, MB.rgb("2e2a2a"), 3, Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.BACK, 0.4))
	_glow_buds(b, [Vector3(-0.5, 0.26, 0.05), Vector3(0.2, 0.26, -0.04), Vector3(0.7, 0.26, 0.06)])
	return b.commit()

static func _m_road_bits() -> ArrayMesh:
	# cracks through old asphalt, with grass and a flower finding the gap
	var b := MB.new()
	var pts := [Vector3(-0.6, 0, -0.3), Vector3(-0.25, 0, -0.1), Vector3(0.05, 0, -0.25), Vector3(0.35, 0, 0.05), Vector3(0.6, 0, 0.0)]
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		var mid := (a + c) * 0.5
		var d := c - a
		b.box(mid + Vector3(0, 0.004, 0), Vector3(d.length() + 0.03, 0.01, 0.035), p(P.ASPHALT_DK), Basis(Vector3.UP, -atan2(d.z, d.x)))
	b.box(Vector3(0.05, 0.004, 0.1), Vector3(0.3, 0.01, 0.03), p(P.ASPHALT_DK), Basis(Vector3.UP, 1.2))
	for g in [Vector3(-0.25, 0.06, -0.1), Vector3(-0.2, 0.06, -0.08), Vector3(0.35, 0.06, 0.05)]:
		b.cyl(g, 0.018, 0.13, p(P.TUFT), 3, Basis(Vector3.BACK, 0.4 * signf(g.x)), 0.0, false)
	b.sphere(Vector3(0.37, 0.12, 0.06), 0.035, p(P.BLOSSOM), 5, 3)
	return b.commit()

# ---- grind rails

static func _m_rail_piece() -> ArrayMesh:
	# 1 m of steel grind pipe along -Z (scaled per piece), centre at y = 0, with a rusty band
	var b := MB.new()
	var along := Basis(Vector3.RIGHT, PI * 0.5)
	b.cyl(Vector3(0, 0, -0.5), 0.075, 1.02, MB.rgb("d4d9e0"), 8, along)
	b.cyl(Vector3(0, 0, -0.2), 0.08, 0.14, p(P.RUST), 8, along)
	b.cyl(Vector3(0, -0.02, -0.75), 0.079, 0.05, MB.glow("8ff5ff"), 8, along)
	return b.commit()

static func _m_rail_post() -> ArrayMesh:
	# a support post down into the abyss, ivy and a glowing bud on the bracket
	var b := MB.new()
	b.cyl(Vector3(0, -3.4, 0), 0.06, 6.8, p(P.RUST), 6)
	b.box(Vector3(0, -0.12, 0), Vector3(0.36, 0.06, 0.08), p(P.RUST))
	b.box(Vector3(0.03, -0.9, 0.0), Vector3(0.05, 1.1, 0.13), p(P.IVY))
	_glow_buds(b, [Vector3(0.16, -0.08, 0.04)])
	return b.commit()

# ---- offroad

## A rounded hump, radius 1 and height 1 (scaled per instance), profile (1 - d^2)^n to match the
## physics in world.bump_at. strata: banded sandstone colours instead of the instance's top colour.
static func _dome(n_exp: float, strata: bool, slope_k: float, rings := 7, segs := 16) -> ArrayMesh:
	var b := MB.new()
	var bands := [MB.rgb("c06a42"), MB.rgb("d07c4d"), MB.rgb("dc8e5b"), MB.rgb("e69f69"), MB.rgb("eeb07b"), MB.rgb("f3c190")]
	var xs := []
	for i in rings + 1:
		var t := float(i) / rings
		xs.append(sin(t * PI * 0.5) if n_exp < 1.0 else t)
	var pt := func(x: float, a: float) -> Vector3:
		return Vector3(cos(a) * x, pow(maxf(1.0 - x * x, 0.0), n_exp) - (0.03 if x > 0.999 else 0.0), sin(a) * x)
	var nm := func(x: float, a: float) -> Vector3:
		var g := minf(2.0 * n_exp * x * pow(maxf(1.0 - x * x, 0.02), n_exp - 1.0), 6.0) * slope_k
		return Vector3(cos(a) * g, 1.0, sin(a) * g).normalized()
	for i in rings:
		var x0: float = xs[i]
		var x1: float = xs[i + 1]
		var y_mid := pow(maxf(1.0 - ((x0 + x1) * 0.5) * ((x0 + x1) * 0.5), 0.0), n_exp)
		var col: Color = MB.TOP
		if strata:
			col = bands[clampi(int(y_mid * 5.99 + 0.15 * sin(float(i) * 2.3)), 0, 5)]
		for j in segs:
			var a0 := TAU * j / segs
			var a1 := TAU * (j + 1) / segs
			if i == 0:
				b.tri(pt.call(x0, a0), pt.call(x1, a1), pt.call(x1, a0), nm.call(x0, a0), nm.call(x1, a1), nm.call(x1, a0), col)
			else:
				b.tri(pt.call(x0, a0), pt.call(x0, a1), pt.call(x1, a1), nm.call(x0, a0), nm.call(x0, a1), nm.call(x1, a1), col)
				b.tri(pt.call(x0, a0), pt.call(x1, a1), pt.call(x1, a0), nm.call(x0, a0), nm.call(x1, a1), nm.call(x1, a0), col)
	return b.commit()

static func _m_mound() -> ArrayMesh:
	return _dome(2.0, false, 0.45, 6, 14)

static func _m_slick_dome() -> ArrayMesh:
	return _dome(1.4, true, 0.5)

static func _m_slick_pillow() -> ArrayMesh:
	return _dome(0.55, true, 0.9, 8, 16)

static func _m_mud() -> ArrayMesh:
	# a flat glossy puddle, radius 1
	var b := MB.new()
	b.cyl(Vector3(0, 0.012, 0), 1.0, 0.02, MB.rgb("9a7050"), 14)
	b.cyl(Vector3(0.1, 0.026, -0.05), 0.74, 0.012, MB.rgb("a97d5a"), 12)
	b.cyl(Vector3(-0.3, 0.034, 0.2), 0.22, 0.01, MB.rgb("d2b494"), 8)
	b.cyl(Vector3(0.35, 0.034, -0.25), 0.12, 0.01, MB.rgb("d2b494"), 8)
	return b.commit()

# ---- deck challenge pieces: 1 m long along -Z (scaled to length per piece), top at y = 0

static func _m_deck_plank() -> ArrayMesh:
	# a narrow plank walkway section, 1.9 wide
	var b := MB.new()
	var cols := [p(P.PLANK), p(P.PLANK), p(P.WOOD_DARK), p(P.PLANK)]
	for i in 4:
		var z := -0.125 - i * 0.25
		b.cbox(Vector3([0.02, -0.03, 0.0, 0.03][i], -0.05, z), Vector3(1.9 + [0.0, 0.07, -0.05, 0.04][i], 0.1, 0.22), 0.02, cols[i])
	for sgn in [-1.0, 1.0]:
		b.box(Vector3(sgn * 0.74, -0.16, -0.5), Vector3(0.1, 0.12, 1.02), p(P.WOOD_DARK))
	return b.commit()

static func _m_deck_stilt() -> ArrayMesh:
	# tall stilts down into the haze, a cross brace, and two little lantern posts at the edges
	var b := MB.new()
	for sgn in [-1.0, 1.0]:
		b.box(Vector3(sgn * 0.7, -3.7, -0.1), Vector3(0.13, 7.2, 0.13), p(P.WOOD_DARK))
		b.box(Vector3(sgn * 1.03, 0.12, -0.1), Vector3(0.09, 0.42, 0.09), p(P.WOOD_DARK))
		b.box(Vector3(sgn * 1.03, 0.38, -0.1), Vector3(0.13, 0.11, 0.13), MB.glow("ffd27a"))
	b.box(Vector3(0, -1.2, -0.1), Vector3(1.9, 0.08, 0.08), p(P.WOOD_DARK), Basis(Vector3.BACK, 0.62))
	b.box(Vector3(0, -2.9, -0.1), Vector3(1.9, 0.08, 0.08), p(P.WOOD_DARK), Basis(Vector3.BACK, -0.62))
	b.box(Vector3(0, -0.28, -0.1), Vector3(1.6, 0.1, 0.14), p(P.WOOD_DARK))
	return b.commit()

static func _track(red: bool) -> ArrayMesh:
	# a toy race-track section, 2.4 wide: slate deck, candy kerbs, dashed centre line
	var b := MB.new()
	b.box(Vector3(0, -0.07, -0.5), Vector3(2.4, 0.14, 1.02), MB.rgb("56607a"))
	b.box(Vector3(0, -0.24, -0.5), Vector3(2.24, 0.2, 1.0), MB.rgb("3d455a"))
	var kc := MB.rgb("ef5b4c") if red else MB.rgb("f7f3ea")
	for sgn in [-1.0, 1.0]:
		b.box(Vector3(sgn * 1.08, 0.015, -0.5), Vector3(0.24, 0.06, 1.02), kc)
		b.box(Vector3(sgn * 1.22, -0.06, -0.5), Vector3(0.05, 0.2, 1.02), MB.rgb("ffcf4d"))
	if red:
		b.box(Vector3(0, 0.005, -0.5), Vector3(0.1, 0.02, 0.55), MB.rgb("f7f3ea"))
	return b.commit()

static func _m_deck_track_a() -> ArrayMesh:
	return _track(true)

static func _m_deck_track_b() -> ArrayMesh:
	return _track(false)

static func _m_deck_stand() -> ArrayMesh:
	# a chunky toy track stand under the deck
	var b := MB.new()
	b.box(Vector3(0, -0.4, -0.1), Vector3(1.9, 0.14, 0.26), MB.rgb("ff9a3d"))
	b.cyl(Vector3(0, -3.6, -0.1), 0.17, 6.4, MB.rgb("ffcf4d"), 10)
	b.cyl(Vector3(0, -0.62, -0.1), 0.26, 0.3, MB.rgb("ff9a3d"), 10)
	return b.commit()

static func _m_station() -> ArrayMesh:
	# a little roadside gas stop beside the pad; origin = pad center, building on +X
	var b := MB.new()
	# pad
	b.cbox(Vector3(0, 0.02, 0), Vector3(4.6, 0.06, 4.0), 0.03, p(P.STONE))
	b.box(Vector3(0, 0.06, -1.6), Vector3(4.2, 0.02, 0.12), MB.glow("ffe08a"))
	b.box(Vector3(0, 0.06, 1.6), Vector3(4.2, 0.02, 0.12), MB.glow("ffe08a"))
	# shop
	b.cbox(Vector3(3.6, 0.8, 0.3), Vector3(2.0, 1.6, 2.4), 0.06, p(P.WALL))
	b.cbox(Vector3(3.6, 1.72, 0.3), Vector3(2.3, 0.26, 2.7), 0.06, p(P.ROOF_RED))
	b.box(Vector3(2.59, 0.7, 0.3), Vector3(0.04, 0.8, 1.4), MB.glow("ffe3a3"))
	b.box(Vector3(2.59, 0.38, -0.7), Vector3(0.04, 0.76, 0.5), MB.rgb("6b4a3a"))
	# canopy over the pump island (beside the lane, so the car stays visible)
	b.cbox(Vector3(2.3, 2.1, -1.0), Vector3(1.4, 0.16, 2.2), 0.04, MB.rgb("ffffff"))
	b.box(Vector3(2.3, 2.0, -1.0), Vector3(1.42, 0.06, 2.22), MB.rgb("ef5b4c"))
	b.cyl(Vector3(2.3, 1.0, -1.9), 0.08, 2.0, MB.rgb("f2f2f2"), 8)
	# pumps
	for z in [-1.4, -0.5]:
		b.cbox(Vector3(2.3, 0.45, z), Vector3(0.38, 0.9, 0.3), 0.05, MB.rgb("ef5b4c"))
		b.box(Vector3(2.1, 0.62, z), Vector3(0.02, 0.2, 0.2), MB.glow("bff3ff"))
		b.cyl(Vector3(2.3, 0.95, z), 0.06, 0.1, MB.rgb("ffffff"), 8)
	# sign
	b.cyl(Vector3(-2.7, 1.3, 1.6), 0.07, 2.6, MB.rgb("dfe4ea"), 8)
	b.cbox(Vector3(-2.7, 2.7, 1.6), Vector3(0.9, 0.7, 0.16), 0.08, MB.glow("ffcf4d"))
	b.cbox(Vector3(-2.7, 2.7, 1.6), Vector3(0.7, 0.5, 0.18), 0.05, MB.rgb("ef5b4c"))
	return b.commit()

static func _m_arch() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(-3.2, 1.3, 0), Vector3(0.32, 2.6, 0.32), 0.06, MB.rgb("ffffff"))
	b.cbox(Vector3(3.2, 1.3, 0), Vector3(0.32, 2.6, 0.32), 0.06, MB.rgb("ffffff"))
	for i in 10:
		var x := -2.9 + i * 0.645
		b.box(Vector3(x, 2.55, 0), Vector3(0.645, 0.24, 0.08), MB.rgb("3a3a44" if i % 2 == 0 else "fafafa"))
		b.box(Vector3(x, 2.31, 0), Vector3(0.645, 0.24, 0.08), MB.rgb("fafafa" if i % 2 == 0 else "3a3a44"))
	b.sphere(Vector3(-3.2, 2.75, 0), 0.22, MB.glow("ffd166"), 10, 6)
	b.sphere(Vector3(3.2, 2.75, 0), 0.22, MB.glow("ffd166"), 10, 6)
	return b.commit()

static func _m_marker() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.45, 0), 0.05, 0.9, MB.rgb("8a5a35"), 6)
	b.cbox(Vector3(0, 0.9, 0), Vector3(0.9, 0.42, 0.08), 0.05, MB.rgb("fff3dd"))
	b.cbox(Vector3(0, 0.9, 0), Vector3(0.98, 0.5, 0.06), 0.05, MB.rgb("3f8f6b"))
	return b.commit()

static func _m_lamp() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.8, 0), 0.05, 1.6, MB.rgb("4c4a52"), 6)
	b.cbox(Vector3(0, 1.72, 0), Vector3(0.26, 0.3, 0.26), 0.05, MB.rgb("4c4a52"))
	b.cbox(Vector3(0, 1.72, 0), Vector3(0.2, 0.22, 0.28), 0.04, MB.glow("ffd98a"))
	b.cbox(Vector3(0, 1.72, 0), Vector3(0.28, 0.22, 0.2), 0.04, MB.glow("ffd98a"))
	return b.commit()

# ---------------------------------------------------------------- countryside

static func _m_tree_round() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.45, 0), 0.11, 0.9, p(P.TRUNK), 7)
	b.sphere(Vector3(0, 1.25, 0), 0.62, p(P.LEAF_A), 12, 8, Vector3(1, 0.92, 1))
	b.sphere(Vector3(0.32, 1.0, 0.2), 0.36, p(P.LEAF_A), 10, 6)
	b.sphere(Vector3(-0.3, 1.05, -0.18), 0.34, p(P.LEAF_A), 10, 6)
	return b.commit()

static func _m_tree_blossom() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.4, 0), 0.1, 0.8, p(P.TRUNK), 7)
	b.cyl(Vector3(0.12, 0.85, 0), 0.06, 0.4, p(P.TRUNK), 6, Basis(Vector3.BACK, -0.5))
	b.sphere(Vector3(0, 1.2, 0), 0.55, p(P.LEAF_B), 12, 8, Vector3(1.1, 0.85, 1.1))
	b.sphere(Vector3(0.38, 1.02, 0.1), 0.32, p(P.LEAF_B), 10, 6)
	b.sphere(Vector3(-0.25, 1.4, 0.15), 0.3, p(P.LEAF_B), 10, 6)
	return b.commit()

static func _m_bush() -> ArrayMesh:
	var b := MB.new()
	b.sphere(Vector3(0, 0.28, 0), 0.36, p(P.BUSH), 10, 6, Vector3(1.1, 0.8, 1))
	b.sphere(Vector3(0.28, 0.22, 0.1), 0.24, p(P.BUSH), 9, 5)
	b.sphere(Vector3(-0.22, 0.2, -0.12), 0.22, p(P.BUSH), 9, 5)
	b.sphere(Vector3(0.05, 0.5, 0.18), 0.07, p(P.FLOWER_A), 6, 4)
	b.sphere(Vector3(-0.15, 0.45, 0.25), 0.06, p(P.FLOWER_B), 6, 4)
	return b.commit()

static func _m_flowers() -> ArrayMesh:
	var b := MB.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.05, 0.42)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		var h := rng.randf_range(0.16, 0.3)
		b.cyl(pos + Vector3(0, h * 0.5, 0), 0.015, h, p(P.TUFT), 4, Basis(), -1.0, false)
		b.sphere(pos + Vector3(0, h, 0), 0.07, p(P.FLOWER_A if i % 2 == 0 else P.FLOWER_B), 7, 4, Vector3(1, 0.6, 1))
	return b.commit()

static func _m_tuft() -> ArrayMesh:
	var b := MB.new()
	for i in 5:
		var a := TAU * i / 5.0
		var bs := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.35)
		b.cyl(Vector3(cos(a) * 0.07, 0.14, sin(a) * 0.07), 0.05, 0.3, p(P.TUFT), 4, bs, 0.0, false)
	return b.commit()

static func _m_hay() -> ArrayMesh:
	var b := MB.new()
	var rot := Basis(Vector3.BACK, PI * 0.5)
	b.cyl(Vector3(0, 0.36, 0), 0.36, 0.7, p(P.HAY), 14, rot)
	b.cyl(Vector3(0, 0.36, 0), 0.25, 0.72, MB.rgb("e0b64e"), 14, rot)
	b.cyl(Vector3(0.18, 0.36, 0), 0.37, 0.04, MB.rgb("c9944a"), 14, rot)
	b.cyl(Vector3(-0.18, 0.36, 0), 0.37, 0.04, MB.rgb("c9944a"), 14, rot)
	return b.commit()

static func _m_fence() -> ArrayMesh:
	var b := MB.new()
	for i in 4:
		var x := -0.6 + i * 0.4
		b.cbox(Vector3(x, 0.3, 0), Vector3(0.12, 0.6, 0.06), 0.02, p(P.FENCE))
		b.box(Vector3(x, 0.62, 0), Vector3(0.08, 0.08, 0.05), p(P.FENCE), Basis(Vector3.BACK, PI * 0.25))
	b.box(Vector3(0, 0.42, -0.05), Vector3(1.6, 0.08, 0.04), p(P.FENCE))
	b.box(Vector3(0, 0.2, -0.05), Vector3(1.6, 0.08, 0.04), p(P.FENCE))
	return b.commit()

static func _m_rock() -> ArrayMesh:
	var b := MB.new()
	b.sphere(Vector3(0, 0.2, 0), 0.34, p(P.STONE), 7, 5, Vector3(1.2, 0.75, 1.0))
	b.sphere(Vector3(0.28, 0.12, 0.12), 0.18, p(P.ROCK_DARK), 6, 4)
	return b.commit()

static func _m_barn() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, 0.75, 0), Vector3(2.2, 1.5, 2.6), 0.06, MB.rgb("d9534a"))
	# gable roof
	var r1 := Basis(Vector3.BACK, 0.62)
	var r2 := Basis(Vector3.BACK, -0.62)
	b.cbox(Vector3(-0.58, 1.85, 0), Vector3(1.5, 0.14, 2.8), 0.04, p(P.ROOF_RED), r1)
	b.cbox(Vector3(0.58, 1.85, 0), Vector3(1.5, 0.14, 2.8), 0.04, p(P.ROOF_RED), r2)
	b.wedge(Vector3(0, 1.5, 1.3), Vector3(2.0, 0.75, 0.01), MB.rgb("d9534a"), Basis(Vector3.RIGHT, PI * 0.5))
	b.box(Vector3(0, 0.6, 1.31), Vector3(0.9, 1.1, 0.04), MB.rgb("ffffff"))
	b.box(Vector3(0, 0.6, 1.33), Vector3(0.72, 0.92, 0.04), MB.rgb("b94339"))
	b.box(Vector3(0, 0.6, 1.36), Vector3(0.9, 0.08, 0.02), MB.rgb("ffffff"), Basis(Vector3.BACK, 0.9))
	b.box(Vector3(0, 0.6, 1.36), Vector3(0.9, 0.08, 0.02), MB.rgb("ffffff"), Basis(Vector3.BACK, -0.9))
	b.box(Vector3(0, 1.55, 1.32), Vector3(0.36, 0.3, 0.04), MB.glow("ffe08a"))
	return b.commit()

static func _m_windmill() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 1.3, 0), 0.75, 2.6, p(P.WALL), 12, Basis(), 0.5)
	b.cyl(Vector3(0, 2.85, 0), 0.6, 0.6, p(P.ROOF_BLUE), 12, Basis(), 0.0)
	b.box(Vector3(0, 0.4, 0.72), Vector3(0.4, 0.7, 0.06), MB.rgb("8a5a35"))
	b.box(Vector3(0, 1.6, 0.62), Vector3(0.3, 0.32, 0.06), MB.glow("ffe08a"))
	return b.commit()

static func _m_windmill_blades() -> ArrayMesh:
	var b := MB.new()
	for i in 4:
		var bs := Basis(Vector3.BACK, PI * 0.5 * i)
		b.box(bs * Vector3(0, 0.75, 0), Vector3(0.08, 1.5, 0.04), MB.rgb("8a5a35"), bs)
		b.box(bs * Vector3(0.14, 0.85, 0.02), Vector3(0.26, 1.1, 0.02), MB.rgb("fff7ea"), bs)
	b.sphere(Vector3.ZERO, 0.12, MB.rgb("8a5a35"), 8, 5)
	return b.commit()

static func _m_sunflower() -> ArrayMesh:
	var b := MB.new()
	for k in 3:
		var o := Vector3([-0.18, 0.12, 0.0][k], 0, [0.1, -0.12, 0.2][k])
		var h := [0.8, 0.95, 0.7][k] as float
		b.cyl(o + Vector3(0, h * 0.5, 0), 0.025, h, p(P.TUFT), 5, Basis(), -1.0, false)
		b.cyl(o + Vector3(0, h, 0.02), 0.16, 0.04, p(P.FLOWER_B), 10, Basis(Vector3.RIGHT, 1.2))
		b.cyl(o + Vector3(0, h, 0.045), 0.07, 0.05, MB.rgb("6b4224"), 8, Basis(Vector3.RIGHT, 1.2))
	return b.commit()

# ---------------------------------------------------------------- seaside

static func _m_umbrella() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.6, 0), 0.03, 1.2, MB.rgb("ffffff"), 6)
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		var col := MB.rgb("ff7b6b" if i % 2 == 0 else "fff6e8")
		var top := Vector3(0, 1.35, 0)
		var p0 := Vector3(cos(a0) * 0.75, 1.05, sin(a0) * 0.75)
		var p1 := Vector3(cos(a1) * 0.75, 1.05, sin(a1) * 0.75)
		var nm := (p0 - top).cross(p1 - top).normalized()
		if nm.y < 0: nm = -nm
		b.tri(top, p0, p1, nm, nm, nm, col)
		b.tri(top, p1, p0, -nm, -nm, -nm, col)
	b.cbox(Vector3(0.5, 0.06, 0.3), Vector3(0.5, 0.04, 0.9), 0.02, MB.rgb("6fc7d6"), Basis(Vector3.UP, 0.4))
	return b.commit()

static func _m_hut() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, 0.6, 0), Vector3(1.4, 1.2, 1.3), 0.05, MB.rgb("fff1df"))
	for i in 5:
		b.box(Vector3(-0.56 + i * 0.28, 0.6, 0.66), Vector3(0.14, 1.18, 0.02), MB.rgb("6fc0d8"))
	b.cbox(Vector3(0, 1.32, 0), Vector3(1.7, 0.22, 1.6), 0.06, p(P.ROOF_BLUE))
	b.box(Vector3(0, 0.5, 0.68), Vector3(0.4, 0.8, 0.03), MB.rgb("e67a5a"))
	b.box(Vector3(0.45, 0.85, 0.68), Vector3(0.26, 0.24, 0.03), MB.glow("ffe08a"))
	return b.commit()

static func _m_lighthouse() -> ArrayMesh:
	var b := MB.new()
	for i in 4:
		var y := 0.45 + i * 0.9
		var r0 := 0.75 - i * 0.1
		b.cyl(Vector3(0, y, 0), r0, 0.9, MB.rgb("ffffff" if i % 2 == 0 else "ef5b4c"), 14, Basis(), r0 - 0.1, false)
	b.cyl(Vector3(0, 3.65, 0), 0.5, 0.1, MB.rgb("3a3a44"), 14)
	b.cyl(Vector3(0, 3.95, 0), 0.3, 0.5, MB.glow("fff2b0"), 12)
	b.cyl(Vector3(0, 4.35, 0), 0.4, 0.35, MB.rgb("ef5b4c"), 12, Basis(), 0.0)
	b.cbox(Vector3(0, 0.08, 0), Vector3(1.8, 0.16, 1.8), 0.05, p(P.STONE))
	return b.commit()

static func _m_beach_rock() -> ArrayMesh:
	var b := MB.new()
	b.sphere(Vector3(0, 0.15, 0), 0.32, p(P.SAND_SIDE), 7, 5, Vector3(1.3, 0.7, 1.0))
	b.sphere(Vector3(0.22, 0.24, -0.1), 0.18, p(P.STONE), 6, 4)
	b.sphere(Vector3(-0.1, 0.3, 0.15), 0.06, p(P.CORAL), 6, 4)
	return b.commit()

static func _m_dune_grass() -> ArrayMesh:
	var b := MB.new()
	for i in 6:
		var a := TAU * i / 6.0
		var bs := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.45)
		b.cyl(Vector3(cos(a) * 0.08, 0.2, sin(a) * 0.08), 0.04, 0.42, MB.rgb("c9c56c"), 4, bs, 0.0, false)
	return b.commit()

static func _m_sandcastle() -> ArrayMesh:
	var b := MB.new()
	var sc := p(P.SAND)
	b.cbox(Vector3(0, 0.15, 0), Vector3(0.8, 0.3, 0.8), 0.06, sc)
	for k in 4:
		var o := Vector3(0.32 * (1 if k % 2 == 0 else -1), 0, 0.32 * (1 if k < 2 else -1))
		b.cyl(o + Vector3(0, 0.4, 0), 0.12, 0.5, sc, 8)
	b.cyl(Vector3(0, 0.55, 0), 0.18, 0.5, sc, 8)
	b.cyl(Vector3(0, 0.95, 0), 0.015, 0.3, MB.rgb("ffffff"), 4)
	b.box(Vector3(0.08, 1.04, 0), Vector3(0.16, 0.1, 0.01), MB.rgb("ff6f61"))
	return b.commit()

static func _m_crate() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, 0.3, 0), Vector3(0.6, 0.6, 0.6), 0.05, p(P.PLANK))
	b.box(Vector3(0, 0.3, 0.305), Vector3(0.62, 0.1, 0.02), MB.rgb("a8703f"), Basis(Vector3.BACK, 0.78))
	b.box(Vector3(0.305, 0.3, 0), Vector3(0.02, 0.1, 0.62), MB.rgb("a8703f"), Basis(Vector3.RIGHT, 0.78))
	return b.commit()

static func _m_deck_chair() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, 0.18, 0.1), Vector3(0.5, 0.06, 0.7), 0.02, MB.rgb("ffd166"), Basis(Vector3.RIGHT, -0.15))
	b.cbox(Vector3(0, 0.42, -0.35), Vector3(0.5, 0.06, 0.6), 0.02, MB.rgb("ffd166"), Basis(Vector3.RIGHT, 0.9))
	b.box(Vector3(-0.24, 0.12, 0), Vector3(0.04, 0.24, 0.8), MB.rgb("ffffff"))
	b.box(Vector3(0.24, 0.12, 0), Vector3(0.04, 0.24, 0.8), MB.rgb("ffffff"))
	return b.commit()

static func _m_buoy() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.2, 0), 0.24, 0.4, MB.rgb("ff6f61"), 10, Basis(), 0.18)
	b.cyl(Vector3(0, 0.25, 0), 0.245, 0.1, MB.rgb("ffffff"), 10)
	b.cyl(Vector3(0, 0.55, 0), 0.04, 0.3, MB.rgb("ffffff"), 6)
	b.sphere(Vector3(0, 0.72, 0), 0.07, MB.glow("fff0a0"), 6, 4)
	return b.commit()

# ---------------------------------------------------------------- forest

static func _m_pine() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.25, 0), 0.1, 0.5, p(P.TRUNK), 6)
	for k in 3:
		var y := 0.45 + k * 0.45
		var r := 0.68 - k * 0.17
		b.cyl(Vector3(0, y + 0.3, 0), r, 0.6, p(P.PINE), 8, Basis(), 0.0, true)
		b.cyl(Vector3(0, y + 0.52, 0), r * 0.42, 0.16, p(P.PINE_CAP), 8, Basis(), 0.0, false)
	return b.commit()

static func _m_pine_tall() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.3, 0), 0.11, 0.6, p(P.TRUNK), 6)
	for k in 4:
		var y := 0.55 + k * 0.48
		var r := 0.72 - k * 0.15
		b.cyl(Vector3(0, y + 0.3, 0), r, 0.62, p(P.PINE), 8, Basis(), 0.0, true)
		b.cyl(Vector3(0, y + 0.53, 0), r * 0.42, 0.16, p(P.PINE_CAP), 8, Basis(), 0.0, false)
	return b.commit()

static func _m_log() -> ArrayMesh:
	var b := MB.new()
	var rot := Basis(Vector3.BACK, PI * 0.5)
	b.cyl(Vector3(0, 0.2, 0), 0.2, 1.2, p(P.TRUNK), 9, rot)
	b.cyl(Vector3(0.61, 0.2, 0), 0.16, 0.02, MB.rgb("e3b27a"), 9, rot)
	b.cyl(Vector3(-0.61, 0.2, 0), 0.16, 0.02, MB.rgb("e3b27a"), 9, rot)
	b.sphere(Vector3(0.2, 0.42, 0.05), 0.07, p(P.TUFT), 6, 4)
	return b.commit()

static func _m_stump() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.18, 0), 0.26, 0.36, p(P.TRUNK), 9, Basis(), 0.22)
	b.cyl(Vector3(0, 0.37, 0), 0.2, 0.02, MB.rgb("e3b27a"), 9)
	return b.commit()

static func _m_mushroom() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.16, 0), 0.07, 0.32, MB.rgb("fff3e3"), 8)
	b.sphere(Vector3(0, 0.34, 0), 0.22, MB.rgb("e8473f"), 10, 6, Vector3(1, 0.6, 1))
	for k in 5:
		var a := TAU * k / 5.0
		b.sphere(Vector3(cos(a) * 0.13, 0.42, sin(a) * 0.13), 0.035, MB.rgb("ffffff"), 6, 3)
	b.cyl(Vector3(0.2, 0.08, 0.12), 0.04, 0.16, MB.rgb("fff3e3"), 6)
	b.sphere(Vector3(0.2, 0.17, 0.12), 0.1, MB.rgb("e8473f"), 8, 5, Vector3(1, 0.6, 1))
	return b.commit()

static func _m_cabin() -> ArrayMesh:
	var b := MB.new()
	for i in 6:
		b.cyl(Vector3(0, 0.12 + i * 0.2, 0), 0.1, 2.0, p(P.TRUNK), 7, Basis(Vector3.BACK, PI * 0.5))
	b.box(Vector3(0, 0.6, 0), Vector3(1.8, 1.2, 1.5), MB.rgb("a8703f"))
	b.cbox(Vector3(-0.5, 1.62, 0), Vector3(1.25, 0.12, 1.8), 0.04, p(P.ROOF_RED), Basis(Vector3.BACK, 0.6))
	b.cbox(Vector3(0.5, 1.62, 0), Vector3(1.25, 0.12, 1.8), 0.04, p(P.ROOF_RED), Basis(Vector3.BACK, -0.6))
	b.box(Vector3(0, 0.55, 0.76), Vector3(0.5, 0.36, 0.03), MB.glow("ffd98a"))
	b.cbox(Vector3(0.55, 1.9, -0.3), Vector3(0.26, 0.6, 0.26), 0.03, p(P.STONE))
	return b.commit()

static func _m_fern() -> ArrayMesh:
	var b := MB.new()
	for i in 6:
		var a := TAU * i / 6.0
		var dir := Vector3(cos(a), 0, sin(a))
		var bs := Basis(dir.cross(Vector3.UP).normalized(), 0.9)
		b.cbox(dir * 0.18 + Vector3(0, 0.12, 0), Vector3(0.1, 0.36, 0.03), 0.01, p(P.BUSH), bs)
	return b.commit()

# ---------------------------------------------------------------- sky islands

static func _m_cloud_puff() -> ArrayMesh:
	var b := MB.new()
	b.sphere(Vector3(0, 0.3, 0), 0.38, p(P.CLOUD), 10, 6)
	b.sphere(Vector3(0.32, 0.24, 0.05), 0.26, p(P.CLOUD), 9, 5)
	b.sphere(Vector3(-0.3, 0.22, -0.05), 0.28, p(P.CLOUD), 9, 5)
	b.sphere(Vector3(0.05, 0.5, -0.1), 0.24, p(P.CLOUD), 9, 5)
	return b.commit()

static func _m_crystal() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.35, 0), 0.14, 0.7, MB.glow("b9a6ff"), 6, Basis(), 0.0, true, false)
	b.cyl(Vector3(0.16, 0.22, 0.05), 0.09, 0.44, MB.glow("8fe3ff"), 6, Basis(Vector3.BACK, -0.3), 0.0, true, false)
	b.cyl(Vector3(-0.14, 0.2, -0.04), 0.08, 0.4, MB.glow("ffb3e0"), 6, Basis(Vector3.BACK, 0.35), 0.0, true, false)
	b.sphere(Vector3(0, 0.04, 0), 0.22, p(P.STONE_SIDE), 7, 4, Vector3(1, 0.4, 1))
	return b.commit()

static func _m_pillar() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, 0.08, 0), Vector3(0.6, 0.16, 0.6), 0.04, p(P.STONE))
	b.cyl(Vector3(0, 0.75, 0), 0.2, 1.2, p(P.STONE), 10)
	b.cbox(Vector3(0, 1.4, 0), Vector3(0.56, 0.14, 0.56), 0.04, p(P.STONE))
	b.sphere(Vector3(0, 1.6, 0), 0.16, MB.glow("ffe9a8"), 8, 5)
	return b.commit()

static func _m_tree_puff() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.5, 0), 0.08, 1.0, MB.rgb("c9a2d6"), 6)
	b.sphere(Vector3(0, 1.2, 0), 0.48, p(P.LEAF_B), 12, 7)
	b.sphere(Vector3(0.18, 1.55, 0.05), 0.28, p(P.LEAF_B), 10, 6)
	return b.commit()

static func _m_balloon() -> ArrayMesh:
	var b := MB.new()
	for k in 8:
		var a0 := TAU * k / 8.0
		var col := MB.rgb(["ff7b6b", "ffd166", "6ec6ff", "fff6e8"][k % 4])
		var bs := Basis(Vector3.UP, a0)
		b.sphere(Vector3.ZERO, 1.0, col, 3, 8, Vector3(1, 1.15, 1), bs)
	b.cyl(Vector3(0, -1.45, 0), 0.22, 0.3, MB.rgb("a8703f"), 8)
	b.box(Vector3(0.16, -1.15, 0), Vector3(0.02, 0.5, 0.02), MB.rgb("6b4a3a"))
	b.box(Vector3(-0.16, -1.15, 0), Vector3(0.02, 0.5, 0.02), MB.rgb("6b4a3a"))
	return b.commit()

static func _m_far_cloud() -> ArrayMesh:
	var b := MB.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 7:
		var x := rng.randf_range(-2.5, 2.5)
		var z := rng.randf_range(-1.0, 1.0)
		var r := rng.randf_range(0.8, 1.6)
		b.sphere(Vector3(x, 0, z), r, MB.rgb("ffffff"), 10, 6, Vector3(1, 0.55, 1))
	return b.commit()

static func _m_far_island() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0, 0), 2.2, 0.5, p(P.GRASS), 10)
	b.cyl(Vector3(0, -1.0, 0), 2.0, 1.5, p(P.DIRT), 10, Basis(), 0.5)
	b.cyl(Vector3(0, -2.3, 0), 0.5, 1.1, p(P.DIRT_DARK), 8, Basis(), 0.0)
	b.sphere(Vector3(0.5, 0.9, 0.2), 0.6, p(P.LEAF_A), 10, 6)
	b.sphere(Vector3(-0.8, 0.6, -0.3), 0.4, p(P.LEAF_A), 10, 6)
	return b.commit()

# ---------------------------------------------------------------- effects

static func _m_puff() -> ArrayMesh:
	var b := MB.new()
	b.sphere(Vector3.ZERO, 0.5, MB.rgb("ffffff"), 8, 5)
	return b.commit()

static func _m_skid() -> ArrayMesh:
	var b := MB.new()
	b.quad(Vector3(-0.08, 0.012, -0.12), Vector3(0.08, 0.012, -0.12), Vector3(0.08, 0.012, 0.12), Vector3(-0.08, 0.012, 0.12), Vector3.UP, MB.rgb("5a4a42"))
	return b.commit()

static func _m_shard() -> ArrayMesh:
	var b := MB.new()
	b.box(Vector3.ZERO, Vector3(0.3, 0.3, 0.3), MB.SIDE)
	return b.commit()

# ---------------------------------------------------------------- cars

const WIN := "4d6890"
const BUMPER := "c9cfd8"
const DARK := "3a3540"

## Builds a car: returns {body, wheel_f, wheel_r, wheels: [Vector3 x4], r_f, r_r, length, width, height}
static var _car_meta := {}

## A car from the Tiny Car Pack, baked by tools/cars (assets/cars): body, left/right wheel meshes, wheel spots.
const CAR_SCALE := 2.6   # the pack's cars, baked at toy size, grown to real size (about 4.2 m long)

static func _pack_car(def: Dictionary) -> Dictionary:
	if _car_meta.is_empty():
		var f := FileAccess.open("res://assets/cars/cars_meta.json", FileAccess.READ)
		_car_meta = JSON.parse_string(f.get_as_text())
	var k := String(def["model"])
	var meta: Dictionary = _car_meta[k]
	var sc := CAR_SCALE
	var wl: Mesh = scaled(load("res://assets/cars/%s_wl.res" % k), sc)
	var wr: Mesh = scaled(load("res://assets/cars/%s_wr.res" % k), sc)
	var spots := []
	for w in meta["wheels"]:
		spots.append(Vector3(w[0], w[1], w[2]) * sc)
	var ab: Array = meta["aabb"]
	return {"body": scaled(load("res://assets/cars/%s_body.res" % k), sc), "wheel_f": wl, "wheel_r": wl, "wheel_fr": wr, "wheel_rr": wr,
		"wheels": spots, "r_f": float(meta["r"]) * sc, "r_r": float(meta["r"]) * sc, "ride": 0.0,
		"top": (float(ab[1]) + float(ab[4])) * sc, "front": float(ab[2]) * sc, "back": (float(ab[2]) + float(ab[5])) * sc,
		"width": float(ab[3]) * sc, "length": float(ab[5]) * sc, "height": float(ab[4]) * sc}

# ---------------------------------------------------------------- paint jobs
static var _paint_meta := {}

## The paint jobs a car can wear: [{v (the pack livery), swatch (hex)}], the factory paint first.
static func paints(def: Dictionary) -> Array:
	if _paint_meta.is_empty() and FileAccess.file_exists("res://assets/cars/paints_meta.json"):
		_paint_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cars/paints_meta.json"))
	return _paint_meta.get(String(def.get("model", "")), [])

## The car's body in paint job idx (0: as it came from the factory). Each paint is a row of per-vertex
## colours baked for this body (tools/cars/export_paints.gd); the lamps keep glowing.
static func painted_body(def: Dictionary, idx: int) -> Mesh:
	var info := car(def)
	if idx <= 0 or not def.has("model"):
		return info["body"]
	var key := "paint_%s_%d" % [def["id"], idx]
	if _cache.has(key):
		return _cache[key]
	var path := "res://assets/cars/%s_paints.res" % def["model"]
	if not ResourceLoader.exists(path):
		return info["body"]
	var img: Image = load(path)
	var src: Mesh = info["body"]
	var a := src.surface_get_arrays(0)
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
	if img == null or idx - 1 >= img.get_height() or img.get_width() != cols.size():
		return info["body"]
	for i in cols.size():
		var c := img.get_pixel(i, idx - 1)
		cols[i] = Color(c.r, c.g, c.b, cols[i].a)
	a[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	_cache[key] = m
	return m

## A copy of a mesh grown by s (every surface).
static func scaled(src: Mesh, s: float) -> ArrayMesh:
	var m := ArrayMesh.new()
	for si in src.get_surface_count():
		var a := src.surface_get_arrays(si)
		var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for k in vv.size():
			vv[k] *= s
		a[Mesh.ARRAY_VERTEX] = vv
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		var mat := src.surface_get_material(si)
		if mat:
			m.surface_set_material(si, mat)
	return m

static func car(def: Dictionary) -> Dictionary:
	var key := "car_" + String(def["id"])
	if _cache.has(key):
		return _cache[key]
	if def.has("model"):
		_cache[key] = _pack_car(def)
		return _cache[key]
	var b := MB.new()
	var body := Color(def["body"])
	var acc := Color(def.get("accent", "ffffff"))
	var shape := String(def["shape"])
	var w := 0.86
	var rf := 0.2
	var rr := 0.2
	var wz := 0.5
	var wx := 0.42
	var ride := 0.12   # chassis bottom height above wheel center
	match shape:
		"round":
			rf = 0.19; rr = 0.19; wz = 0.46
			b.sphere(Vector3(0, 0.42, 0), 0.5, MB.rgb(body), 14, 8, Vector3(0.86, 0.6, 1.5))
			b.sphere(Vector3(0, 0.66, 0.06), 0.36, MB.rgb(body), 12, 7, Vector3(0.95, 0.85, 1.15))
			b.sphere(Vector3(0, 0.7, -0.08), 0.34, MB.rgb(WIN), 12, 6, Vector3(0.92, 0.72, 1.0))
			b.sphere(Vector3(0, 0.68, 0.12), 0.33, MB.rgb(body), 12, 6, Vector3(0.97, 0.86, 0.85))
			for s in [-1.0, 1.0]:
				b.sphere(Vector3(s * 0.36, 0.3, -0.46), 0.2, MB.rgb(body), 10, 6, Vector3(0.8, 0.9, 1.1))
				b.sphere(Vector3(s * 0.36, 0.3, 0.46), 0.2, MB.rgb(body), 10, 6, Vector3(0.8, 0.9, 1.1))
				b.sphere(Vector3(s * 0.25, 0.44, -0.7), 0.08, MB.glow("fff6c8"), 8, 5)
				b.sphere(Vector3(s * 0.25, 0.44, 0.73), 0.06, MB.glow("ff6a5a"), 8, 5)
			b.cbox(Vector3(0, 0.22, -0.76), Vector3(0.7, 0.07, 0.07), 0.03, MB.rgb(BUMPER))
			b.cbox(Vector3(0, 0.22, 0.77), Vector3(0.7, 0.07, 0.07), 0.03, MB.rgb(BUMPER))
		"van":
			rf = 0.2; rr = 0.2; wz = 0.52
			b.cbox(Vector3(0, 0.42, 0), Vector3(w, 0.42, 1.6), 0.1, MB.rgb(body))
			b.cbox(Vector3(0, 0.84, 0.02), Vector3(w * 0.98, 0.46, 1.54), 0.12, MB.rgb(acc))
			b.cbox(Vector3(0, 0.62, -0.62), Vector3(0.9, 0.18, 0.4), 0.08, MB.rgb(body))
			b.box(Vector3(0, 0.86, -0.78), Vector3(0.7, 0.28, 0.03), MB.rgb(WIN))
			for s in [-1.0, 1.0]:
				for k in 3:
					b.box(Vector3(s * 0.432, 0.88, -0.38 + k * 0.42), Vector3(0.02, 0.24, 0.32), MB.rgb(WIN))
				b.sphere(Vector3(s * 0.28, 0.48, -0.79), 0.08, MB.glow("fff6c8"), 8, 5)
				b.box(Vector3(s * 0.3, 0.5, 0.805), Vector3(0.12, 0.12, 0.02), MB.glow("ff6a5a"))
			b.sphere(Vector3(0, 0.62, -0.83), 0.08, MB.rgb("ffffff"), 8, 5, Vector3(1, 1, 0.4))
			b.cbox(Vector3(0, 0.26, -0.82), Vector3(0.9, 0.08, 0.08), 0.03, MB.rgb(BUMPER))
			b.cbox(Vector3(0, 0.26, 0.82), Vector3(0.9, 0.08, 0.08), 0.03, MB.rgb(BUMPER))
			b.cbox(Vector3(0, 1.1, 0.25), Vector3(0.6, 0.06, 0.8), 0.02, MB.rgb(acc).darkened(0.08))
		"pickup", "monster":
			if shape == "monster":
				rf = 0.36; rr = 0.36; wz = 0.55; wx = 0.5; ride = 0.18
			else:
				rf = 0.2; rr = 0.2; wz = 0.52
			var lift := 0.0 if shape == "pickup" else 0.32
			b.cbox(Vector3(0, 0.38 + lift, 0), Vector3(w, 0.34, 1.62), 0.08, MB.rgb(body))
			b.cbox(Vector3(0, 0.72 + lift, -0.12), Vector3(w * 0.94, 0.38, 0.62), 0.1, MB.rgb(body))
			b.box(Vector3(0, 0.76 + lift, -0.43), Vector3(0.68, 0.22, 0.03), MB.rgb(WIN))
			for s in [-1.0, 1.0]:
				b.box(Vector3(s * 0.408, 0.76 + lift, -0.12), Vector3(0.02, 0.2, 0.42), MB.rgb(WIN))
				b.cbox(Vector3(s * 0.4, 0.66 + lift, 0.5), Vector3(0.07, 0.22, 0.62), 0.02, MB.rgb(body))
				b.sphere(Vector3(s * 0.28, 0.44 + lift, -0.81), 0.075, MB.glow("fff6c8"), 8, 5)
				b.box(Vector3(s * 0.32, 0.46 + lift, 0.815), Vector3(0.12, 0.1, 0.02), MB.glow("ff6a5a"))
			b.cbox(Vector3(0, 0.66 + lift, 0.8), Vector3(0.86, 0.22, 0.06), 0.02, MB.rgb(body))
			b.box(Vector3(0, 0.56 + lift, 0.5), Vector3(0.74, 0.02, 0.6), MB.rgb(acc))
			b.cbox(Vector3(0, 0.24 + lift, -0.83), Vector3(0.9, 0.08, 0.08), 0.03, MB.rgb(BUMPER))
			if shape == "monster":
				b.box(Vector3(0, 0.3, 0), Vector3(0.3, 0.12, 1.2), MB.rgb(DARK))
				b.box(Vector3(0, 0.96 + lift, -0.12), Vector3(0.5, 0.06, 0.1), MB.glow("fff0a0"))
		"jeep":
			rf = 0.23; rr = 0.23; wz = 0.5; ride = 0.14
			b.cbox(Vector3(0, 0.46, 0), Vector3(w, 0.38, 1.48), 0.05, MB.rgb(body))
			b.cbox(Vector3(0, 0.6, -0.55), Vector3(w * 0.96, 0.12, 0.38), 0.04, MB.rgb(body))
			b.box(Vector3(0, 0.84, -0.3), Vector3(0.78, 0.3, 0.04), MB.rgb(WIN), Basis(Vector3.RIGHT, -0.2))
			b.cbox(Vector3(0, 0.84, -0.3), Vector3(0.84, 0.36, 0.05), 0.02, MB.rgb(DARK), Basis(Vector3.RIGHT, -0.2))
			b.box(Vector3(0, 0.84, -0.29), Vector3(0.74, 0.28, 0.06), MB.rgb(WIN), Basis(Vector3.RIGHT, -0.2))
			for s in [-1.0, 1.0]:
				b.cyl(Vector3(s * 0.36, 0.86, 0.25), 0.035, 0.5, MB.rgb(DARK), 6)
				b.sphere(Vector3(s * 0.25, 0.56, -0.75), 0.08, MB.glow("fff6c8"), 8, 5)
				b.cbox(Vector3(s * 0.43, 0.58, -0.2), Vector3(0.06, 0.06, 0.9), 0.02, MB.rgb(body).darkened(0.15))
			b.box(Vector3(0, 1.1, 0.25), Vector3(0.76, 0.05, 0.05), MB.rgb(DARK))
			b.box(Vector3(0, 0.6, 0.2), Vector3(0.7, 0.04, 0.6), MB.rgb("6b4a3a"))
			b.cyl(Vector3(0, 0.6, 0.8), 0.2, 0.14, MB.rgb(DARK), 12, Basis(Vector3.RIGHT, PI * 0.5))
			b.cbox(Vector3(0, 0.28, -0.76), Vector3(0.92, 0.09, 0.08), 0.02, MB.rgb(DARK))
		"sedan", "taxi", "police", "wagon":
			rf = 0.19; rr = 0.19; wz = 0.5
			var long_roof := shape == "wagon"
			b.cbox(Vector3(0, 0.38, 0), Vector3(w, 0.3, 1.66), 0.09, MB.rgb(body))
			var rz := 0.12 if long_roof else 0.06
			var rl := 0.98 if long_roof else 0.76
			b.cbox(Vector3(0, 0.66, rz), Vector3(w * 0.9, 0.32, rl), 0.1, MB.rgb(acc if shape == "police" else body))
			b.box(Vector3(0, 0.67, rz - rl * 0.5 - 0.005), Vector3(0.64, 0.2, 0.02), MB.rgb(WIN))
			b.box(Vector3(0, 0.67, rz + rl * 0.5 + 0.005), Vector3(0.6, 0.18, 0.02), MB.rgb(WIN))
			for s in [-1.0, 1.0]:
				b.box(Vector3(s * w * 0.452, 0.68, rz), Vector3(0.02, 0.18, rl * 0.8), MB.rgb(WIN))
				b.sphere(Vector3(s * 0.28, 0.42, -0.83), 0.075, MB.glow("fff6c8"), 8, 5)
				b.box(Vector3(s * 0.3, 0.44, 0.835), Vector3(0.14, 0.08, 0.02), MB.glow("ff6a5a"))
				if shape == "wagon":
					b.box(Vector3(s * 0.432, 0.38, 0.08), Vector3(0.02, 0.18, 1.3), MB.rgb("b77b46"))
					b.box(Vector3(s * 0.435, 0.38, 0.08), Vector3(0.02, 0.2, 0.04), MB.rgb("f3dfc3"))
				if shape == "police":
					b.box(Vector3(s * 0.432, 0.4, 0.0), Vector3(0.02, 0.2, 0.7), MB.rgb("ffffff"))
			b.cbox(Vector3(0, 0.24, -0.84), Vector3(0.9, 0.08, 0.08), 0.03, MB.rgb(BUMPER))
			b.cbox(Vector3(0, 0.24, 0.84), Vector3(0.9, 0.08, 0.08), 0.03, MB.rgb(BUMPER))
			if shape == "taxi":
				b.cbox(Vector3(0, 0.88, 0.06), Vector3(0.34, 0.12, 0.16), 0.03, MB.glow("fff0a0"))
				for k in 6:
					b.box(Vector3(-0.432, 0.42, -0.5 + k * 0.2), Vector3(0.025, 0.08, 0.1), MB.rgb("3a3540" if k % 2 == 0 else "ffffff"))
					b.box(Vector3(0.432, 0.42, -0.5 + k * 0.2), Vector3(0.025, 0.08, 0.1), MB.rgb("3a3540" if k % 2 == 0 else "ffffff"))
			if shape == "police":
				b.cbox(Vector3(-0.14, 0.86, 0.06), Vector3(0.24, 0.1, 0.16), 0.03, MB.glow("ff4d4d"))
				b.cbox(Vector3(0.14, 0.86, 0.06), Vector3(0.24, 0.1, 0.16), 0.03, MB.glow("4d8dff"))
			if long_roof:
				b.box(Vector3(-0.25, 0.86, 0.12), Vector3(0.04, 0.04, 0.9), MB.rgb(DARK))
				b.box(Vector3(0.25, 0.86, 0.12), Vector3(0.04, 0.04, 0.9), MB.rgb(DARK))
				b.cbox(Vector3(0, 0.92, 0.12), Vector3(0.3, 0.06, 1.1), 0.03, MB.rgb("ff8a5c"))
		"mini":
			rf = 0.17; rr = 0.17; wz = 0.42; w = 0.8
			b.cbox(Vector3(0, 0.36, 0), Vector3(w, 0.32, 1.3), 0.1, MB.rgb(body))
			b.cbox(Vector3(0, 0.64, 0.08), Vector3(w * 0.92, 0.3, 0.82), 0.08, MB.rgb(body))
			b.cbox(Vector3(0, 0.8, 0.08), Vector3(w * 0.95, 0.06, 0.86), 0.03, MB.rgb(acc))
			b.box(Vector3(0, 0.64, -0.335), Vector3(0.6, 0.2, 0.02), MB.rgb(WIN))
			for s in [-1.0, 1.0]:
				b.box(Vector3(s * 0.37, 0.65, 0.08), Vector3(0.02, 0.18, 0.66), MB.rgb(WIN))
				b.sphere(Vector3(s * 0.25, 0.42, -0.65), 0.08, MB.glow("fff6c8"), 8, 5)
				b.box(Vector3(s * 0.27, 0.42, 0.655), Vector3(0.1, 0.1, 0.02), MB.glow("ff6a5a"))
				b.box(Vector3(s * 0.18, 0.524, -0.3), Vector3(0.1, 0.01, 0.6), MB.rgb(acc))
			b.cbox(Vector3(0, 0.22, -0.66), Vector3(0.82, 0.07, 0.07), 0.03, MB.rgb(BUMPER))
		"roadster", "racer", "hotrod":
			rf = 0.18; rr = 0.2; wz = 0.52; ride = 0.08
			if shape == "hotrod":
				rf = 0.16; rr = 0.27
			b.cbox(Vector3(0, 0.34, 0.02), Vector3(w * 0.92, 0.26, 1.7), 0.1, MB.rgb(body))
			if shape == "racer":
				b.cbox(Vector3(0, 0.4, -0.5), Vector3(0.5, 0.16, 0.7), 0.06, MB.rgb(body))
				b.cyl(Vector3(-0.0, 0.48, 0.05), 0.22, 0.04, MB.rgb("ffffff"), 14)
				b.cbox(Vector3(0, 0.7, 0.76), Vector3(0.86, 0.06, 0.24), 0.02, MB.rgb(acc))
				b.box(Vector3(-0.3, 0.58, 0.76), Vector3(0.04, 0.2, 0.06), MB.rgb(DARK))
				b.box(Vector3(0.3, 0.58, 0.76), Vector3(0.04, 0.2, 0.06), MB.rgb(DARK))
				b.box(Vector3(0, 0.475, -0.2), Vector3(0.14, 0.02, 1.6), MB.rgb(acc))
				b.sphere(Vector3(0, 0.58, 0.3), 0.16, MB.rgb("ffffff"), 10, 6)
			else:
				b.box(Vector3(0, 0.62, -0.25), Vector3(0.7, 0.2, 0.03), MB.rgb("bfe6ff"), Basis(Vector3.RIGHT, -0.35))
				b.cbox(Vector3(0, 0.5, 0.2), Vector3(0.62, 0.1, 0.5), 0.04, MB.rgb(acc))
				b.cbox(Vector3(0, 0.62, 0.42), Vector3(0.6, 0.22, 0.08), 0.04, MB.rgb(acc))
			if shape == "hotrod":
				b.cbox(Vector3(0, 0.56, -0.48), Vector3(0.36, 0.22, 0.46), 0.04, MB.rgb(BUMPER))
				for s in [-1.0, 1.0]:
					b.cyl(Vector3(s * 0.12, 0.72, -0.48), 0.04, 0.2, MB.rgb(BUMPER), 6)
					b.cyl(Vector3(s * 0.5, 0.32, 0.0), 0.04, 0.8, MB.rgb(BUMPER), 6, Basis(Vector3.RIGHT, PI * 0.5))
				for k in 3:
					b.box(Vector3(-0.42, 0.36, -0.6 + k * 0.18), Vector3(0.02, 0.1, 0.16), MB.rgb(["ffd166", "ff8a3d", "ff4d3d"][k]), Basis(Vector3.RIGHT, 0.4))
					b.box(Vector3(0.42, 0.36, -0.6 + k * 0.18), Vector3(0.02, 0.1, 0.16), MB.rgb(["ffd166", "ff8a3d", "ff4d3d"][k]), Basis(Vector3.RIGHT, 0.4))
			for s in [-1.0, 1.0]:
				b.sphere(Vector3(s * 0.26, 0.38, -0.86), 0.07, MB.glow("fff6c8"), 8, 5)
				b.box(Vector3(s * 0.28, 0.4, 0.875), Vector3(0.12, 0.08, 0.02), MB.glow("ff6a5a"))
		"bus", "firetruck", "icecream", "mail", "dump":
			rf = 0.21; rr = 0.21; wz = 0.6
			var L := 1.9 if shape == "bus" else 1.75
			if shape == "mail":
				L = 1.5; wz = 0.48
			if shape == "bus" or shape == "icecream" or shape == "mail":
				b.cbox(Vector3(0, 0.62, 0), Vector3(w, 0.82, L), 0.1, MB.rgb(body))
				var wins := 4 if shape == "bus" else 2
				for s in [-1.0, 1.0]:
					for k in wins:
						var zz := -L * 0.35 + k * (L * 0.7 / maxf(1.0, wins - 1))
						if shape == "icecream" and k == 1:
							b.box(Vector3(s * 0.435, 0.72, zz - 0.3), Vector3(0.02, 0.28, 0.5), MB.glow("fff0c4"))
						else:
							b.box(Vector3(s * 0.435, 0.8, zz), Vector3(0.02, 0.22, 0.26), MB.rgb(WIN))
					b.box(Vector3(s * 0.436, 0.5, 0), Vector3(0.02, 0.06, L * 0.9), MB.rgb(acc))
					b.sphere(Vector3(s * 0.28, 0.4, -L * 0.5 - 0.01), 0.075, MB.glow("fff6c8"), 8, 5)
					b.box(Vector3(s * 0.3, 0.45, L * 0.5 + 0.01), Vector3(0.12, 0.1, 0.02), MB.glow("ff6a5a"))
				b.box(Vector3(0, 0.82, -L * 0.5 - 0.005), Vector3(0.7, 0.3, 0.02), MB.rgb(WIN))
				if shape == "icecream":
					b.cyl(Vector3(0, 1.22, 0.1), 0.14, 0.32, MB.rgb("e8b46a"), 10, Basis(Vector3.RIGHT, PI), 0.0)
					b.sphere(Vector3(0, 1.44, 0.1), 0.18, MB.rgb("ffc2d6"), 10, 6)
					b.sphere(Vector3(0, 1.58, 0.1), 0.05, MB.rgb("e8473f"), 6, 4)
				if shape == "bus":
					b.box(Vector3(0, 1.04, 0), Vector3(0.7, 0.02, L * 0.8), MB.rgb(acc))
				if shape == "mail":
					b.cbox(Vector3(0, 0.42, -0.86), Vector3(0.8, 0.12, 0.1), 0.03, MB.rgb(acc))
			else:
				# cab + rear unit
				b.cbox(Vector3(0, 0.34, 0.05), Vector3(w * 0.9, 0.22, L), 0.05, MB.rgb(DARK))
				b.cbox(Vector3(0, 0.66, -0.58), Vector3(w, 0.62, 0.56), 0.1, MB.rgb(body))
				b.box(Vector3(0, 0.78, -0.865), Vector3(0.68, 0.24, 0.02), MB.rgb(WIN))
				for s in [-1.0, 1.0]:
					b.box(Vector3(s * 0.435, 0.8, -0.6), Vector3(0.02, 0.22, 0.32), MB.rgb(WIN))
					b.sphere(Vector3(s * 0.28, 0.48, -0.87), 0.07, MB.glow("fff6c8"), 8, 5)
				if shape == "firetruck":
					b.cbox(Vector3(0, 0.62, 0.32), Vector3(w, 0.52, 1.1), 0.08, MB.rgb(body))
					b.box(Vector3(0, 0.9, 0.3), Vector3(0.12, 0.06, 1.3), MB.rgb(BUMPER), Basis(Vector3.RIGHT, 0.05))
					for k in 8:
						b.box(Vector3(0, 0.94, -0.3 + k * 0.16), Vector3(0.36, 0.03, 0.03), MB.rgb(BUMPER))
					b.box(Vector3(-0.15, 0.94, 0.3), Vector3(0.03, 0.04, 1.3), MB.rgb(BUMPER))
					b.box(Vector3(0.15, 0.94, 0.3), Vector3(0.03, 0.04, 1.3), MB.rgb(BUMPER))
					b.cbox(Vector3(0, 1.0, -0.62), Vector3(0.4, 0.08, 0.14), 0.03, MB.glow("ff4d4d"))
					b.box(Vector3(-0.44, 0.5, 0.3), Vector3(0.02, 0.06, 1.0), MB.rgb("ffffff"))
					b.box(Vector3(0.44, 0.5, 0.3), Vector3(0.02, 0.06, 1.0), MB.rgb("ffffff"))
				else:
					b.cbox(Vector3(0, 0.66, 0.36), Vector3(w * 0.96, 0.5, 1.0), 0.06, MB.rgb(acc), Basis(Vector3.RIGHT, -0.12))
					b.box(Vector3(0, 0.92, 0.38), Vector3(0.66, 0.03, 0.9), MB.rgb("8f7a66"), Basis(Vector3.RIGHT, -0.12))
					b.sphere(Vector3(0.05, 0.98, 0.45), 0.28, MB.rgb("b48a5e"), 8, 5, Vector3(1.1, 0.4, 1.3))
			b.cbox(Vector3(0, 0.26, -L * 0.5 - 0.03), Vector3(0.9, 0.08, 0.08), 0.03, MB.rgb(BUMPER))
		"tractor":
			rf = 0.18; rr = 0.33; wz = 0.45; wx = 0.4
			b.cbox(Vector3(0, 0.48, -0.25), Vector3(0.5, 0.36, 0.9), 0.08, MB.rgb(body))
			b.cyl(Vector3(-0.12, 0.85, -0.5), 0.04, 0.36, MB.rgb(DARK), 6)
			b.cbox(Vector3(0, 0.42, 0.36), Vector3(0.6, 0.3, 0.6), 0.06, MB.rgb(body))
			b.cbox(Vector3(0, 0.72, 0.36), Vector3(0.36, 0.06, 0.32), 0.02, MB.rgb(DARK))
			for s in [-1.0, 1.0]:
				b.cyl(Vector3(s * 0.26, 1.0, 0.18), 0.03, 0.56, MB.rgb(DARK), 6)
				b.cyl(Vector3(s * 0.26, 1.0, 0.6), 0.03, 0.56, MB.rgb(DARK), 6)
				b.sphere(Vector3(s * 0.16, 0.52, -0.71), 0.06, MB.glow("fff6c8"), 8, 5)
				b.cbox(Vector3(s * 0.4, 0.5, 0.45), Vector3(0.12, 0.08, 0.6), 0.03, MB.rgb(acc))
			b.cbox(Vector3(0, 1.3, 0.4), Vector3(0.7, 0.06, 0.62), 0.03, MB.rgb(acc))
			b.box(Vector3(0, 0.5, -0.705), Vector3(0.3, 0.2, 0.02), MB.rgb(DARK))
	var wheel_f := _wheel(rf, 0.16 if shape != "monster" else 0.26, def)
	var wheel_r := _wheel(rr, 0.16 if shape != "monster" else 0.26, def) if rr != rf else wheel_f
	var res := {
		"body": b.commit(),
		"wheel_f": wheel_f,
		"wheel_r": wheel_r,
		"wheels": [Vector3(-wx, rf, -wz), Vector3(wx, rf, -wz), Vector3(-wx, rr, wz), Vector3(wx, rr, wz)],
		"r_f": rf, "r_r": rr, "ride": ride,
	}
	_cache[key] = res
	return res

## The mesh for wheel i (0 front-left, 1 front-right, 2 rear-left, 3 rear-right).
static func wheel_mesh(c: Dictionary, i: int) -> Mesh:
	var right := i == 1 or i == 3
	if i < 2:
		return c.get("wheel_fr", c["wheel_f"]) if right else c["wheel_f"]
	return c.get("wheel_rr", c["wheel_r"]) if right else c["wheel_r"]

static func _wheel(r: float, width: float, def: Dictionary) -> ArrayMesh:
	var key := "wheel_%.2f_%.2f_%s" % [r, width, String(def.get("hub", "e9e2d6"))]
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var rot := Basis(Vector3.BACK, PI * 0.5)
	b.cyl(Vector3.ZERO, r, width, MB.rgb("3a3540"), 14, rot)
	b.cyl(Vector3.ZERO, r * 0.82, width * 0.7, MB.rgb("4a4450"), 14, rot)
	b.cyl(Vector3.ZERO, r * 0.48, width + 0.02, MB.rgb(def.get("hub", "e9e2d6")), 10, rot)
	b.box(Vector3.ZERO, Vector3(width + 0.03, r * 0.16, r * 0.8), MB.rgb(def.get("hub", "e9e2d6")).darkened(0.15))
	var m := b.commit()
	_cache[key] = m
	return m

# ================================================================ places (richer environments)

# ---------------------------------------------------------------- special ground tiles

static func _m_tile_field() -> ArrayMesh:
	# ploughed rows with crops; crop colour follows the season
	var b := MB.new()
	b.cbox(Vector3(0, -0.15, 0), Vector3(T, 0.22, T), 0.04, MB.SIDE, Basis(), p(P.SOIL))
	b.box(Vector3(0, -0.7, 0), Vector3(T * 0.97, 0.9, T * 0.97), MB.SIDE)
	for k in 4:
		var x := -0.6 + k * 0.4
		b.cbox(Vector3(x, -0.02, 0), Vector3(0.2, 0.1, T * 0.96), 0.04, p(P.SOIL).darkened(0.0))
		for j in 5:
			var z := -0.64 + j * 0.32
			b.sphere(Vector3(x, 0.08, z), 0.1, p(P.CROP), 6, 4, Vector3(1.0, 1.3, 1.0))
	return b.commit()

static func _m_tile_cobble() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, -0.15, 0), Vector3(T, 0.26, T), 0.04, MB.SIDE, Basis(), p(P.ROCK_DARK))
	b.box(Vector3(0, -0.7, 0), Vector3(T * 0.97, 0.9, T * 0.97), MB.SIDE)
	for i in 4:
		for j in 4:
			var off := 0.1 if j % 2 == 0 else -0.1
			var c := Vector3(-0.6 + i * 0.4 + off, -0.0, -0.6 + j * 0.4)
			b.cbox(c, Vector3(0.34, 0.06, 0.34), 0.05, p(P.COBBLE if (i + j) % 3 != 0 else P.PEBBLE))
	return b.commit()

static func _m_tile_plank() -> ArrayMesh:
	# boardwalk / pier decking
	var b := MB.new()
	b.box(Vector3(0, -0.6, 0), Vector3(T * 0.9, 1.0, T * 0.9), MB.SIDE)
	for k in 5:
		var x := -0.64 + k * 0.32
		b.cbox(Vector3(x, -0.07, 0), Vector3(0.29, 0.12, T), 0.03, p(P.PLANK))
	b.box(Vector3(0, -0.17, -0.55), Vector3(T, 0.08, 0.1), p(P.WOOD_DARK))
	b.box(Vector3(0, -0.17, 0.55), Vector3(T, 0.08, 0.1), p(P.WOOD_DARK))
	return b.commit()

static func _m_tile_pier() -> ArrayMesh:
	# decking on stilts over water
	var b := MB.new()
	for k in 5:
		var x := -0.64 + k * 0.32
		b.cbox(Vector3(x, -0.07, 0), Vector3(0.29, 0.12, T), 0.03, p(P.PLANK))
	for x in [-0.65, 0.65]:
		for z in [-0.65, 0.65]:
			b.cyl(Vector3(x, -0.75, z), 0.08, 1.4, p(P.WOOD_DARK), 6)
	return b.commit()

static func _m_tile_rock() -> ArrayMesh:
	# a craggy block for mountain terraces (scaled taller per instance); unit height 1
	var b := MB.new()
	b.cbox(Vector3(0, 0.5, 0), Vector3(T, 1.0, T), 0.12, MB.SIDE, Basis(), MB.TOP)
	b.cbox(Vector3(0.25, 1.04, 0.2), Vector3(0.7, 0.14, 0.6), 0.06, p(P.ROCK))
	b.cbox(Vector3(-0.3, 1.02, -0.25), Vector3(0.5, 0.1, 0.5), 0.05, p(P.PEBBLE))
	b.box(Vector3(0, -0.5, 0), Vector3(T * 0.95, 1.0, T * 0.95), MB.SIDE)
	return b.commit()

static func _m_ground_bits() -> ArrayMesh:
	# tiny scatter for ordinary tiles: a few blades, a pebble and a flower
	var b := MB.new()
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		var bs := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.4)
		b.cyl(Vector3(cos(a) * 0.05, 0.07, sin(a) * 0.05), 0.025, 0.15, p(P.TUFT), 4, bs, 0.0, false)
	b.sphere(Vector3(0.25, 0.02, 0.12), 0.06, p(P.PEBBLE), 6, 3, Vector3(1.3, 0.6, 1.0))
	b.sphere(Vector3(-0.2, 0.08, 0.2), 0.045, p(P.BLOSSOM), 6, 3)
	b.cyl(Vector3(-0.2, 0.04, 0.2), 0.01, 0.08, p(P.TUFT), 3, Basis(), -1.0, false)
	return b.commit()

# ---------------------------------------------------------------- village

static func _cottage(wall: int, roof: int, w: float, d: float, h: float) -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, 0.08, 0), Vector3(w + 0.2, 0.16, d + 0.2), 0.04, p(P.STONE))
	b.cbox(Vector3(0, h * 0.5 + 0.12, 0), Vector3(w, h, d), 0.05, p(wall))
	var r1 := Basis(Vector3.BACK, 0.62)
	var r2 := Basis(Vector3.BACK, -0.62)
	var span := w * 0.62
	b.cbox(Vector3(-w * 0.26, h + 0.12 + w * 0.19, 0), Vector3(span, 0.12, d + 0.3), 0.04, p(roof), r1)
	b.cbox(Vector3(w * 0.26, h + 0.12 + w * 0.19, 0), Vector3(span, 0.12, d + 0.3), 0.04, p(roof), r2)
	b.wedge(Vector3(0, h + 0.12, d * 0.5 - 0.005), Vector3(w * 0.98, w * 0.36, 0.01), p(wall), Basis(Vector3.RIGHT, PI * 0.5))
	b.wedge(Vector3(0, h + 0.12, -d * 0.5 + 0.005), Vector3(w * 0.98, w * 0.36, 0.01), p(wall), Basis(Vector3.RIGHT, PI * 0.5))
	b.cbox(Vector3(w * 0.28, h + 0.5, -d * 0.2), Vector3(0.22, 0.6, 0.22), 0.03, p(P.ROCK_DARK))
	# door, windows (glow at night), flower box
	b.box(Vector3(0, 0.45, d * 0.5 + 0.02), Vector3(0.3, 0.6, 0.03), MB.rgb("8a5a35"))
	b.sphere(Vector3(0.08, 0.45, d * 0.5 + 0.04), 0.025, MB.rgb("ffd166"), 5, 3)
	for x in [-w * 0.3, w * 0.3]:
		b.box(Vector3(x, h * 0.62 + 0.1, d * 0.5 + 0.02), Vector3(0.26, 0.26, 0.03), MB.glow("ffe3a3"))
		b.box(Vector3(x, h * 0.62 + 0.1, d * 0.5 + 0.035), Vector3(0.28, 0.03, 0.02), MB.rgb("ffffff"))
		b.cbox(Vector3(x, h * 0.62 - 0.08, d * 0.5 + 0.07), Vector3(0.32, 0.08, 0.1), 0.02, MB.rgb("8a5a35"))
		for k in 3:
			b.sphere(Vector3(x - 0.1 + k * 0.1, h * 0.62 - 0.02, d * 0.5 + 0.08), 0.045, p(P.BLOSSOM if k != 1 else P.FLOWER_A), 5, 3)
	for z in [-d * 0.22, d * 0.22]:
		b.box(Vector3(w * 0.5 + 0.02, h * 0.62 + 0.1, z), Vector3(0.03, 0.24, 0.24), MB.glow("ffe3a3"))
		b.box(Vector3(-w * 0.5 - 0.02, h * 0.62 + 0.1, z), Vector3(0.03, 0.24, 0.24), MB.glow("ffe3a3"))
	return b.commit()

static func _m_cottage_a() -> ArrayMesh:
	return _cottage(P.WALL, P.ROOF_RED, 1.5, 1.3, 1.0)

static func _m_cottage_b() -> ArrayMesh:
	return _cottage(P.WALL_PINK, P.ROOF_BLUE, 1.3, 1.2, 0.95)

static func _m_cottage_c() -> ArrayMesh:
	return _cottage(P.WALL_BLUE, P.ROOF_GREEN, 1.4, 1.4, 1.05)

static func _m_well() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.22, 0), 0.38, 0.44, p(P.COBBLE), 12)
	b.cyl(Vector3(0, 0.45, 0), 0.3, 0.02, p(P.WATER), 12)
	for x in [-0.32, 0.32]:
		b.cbox(Vector3(x, 0.75, 0), Vector3(0.07, 0.65, 0.07), 0.02, p(P.WOOD_DARK))
	b.cbox(Vector3(0, 1.12, 0), Vector3(0.95, 0.08, 0.62), 0.03, p(P.ROOF_RED), Basis(Vector3.RIGHT, 0.0))
	b.cyl(Vector3(0, 0.88, 0), 0.04, 0.6, p(P.WOOD_DARK), 6, Basis(Vector3.BACK, PI * 0.5))
	b.cyl(Vector3(0.05, 0.62, 0), 0.09, 0.14, p(P.PLANK), 8)
	return b.commit()

static func _m_bench() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, 0.3, 0), Vector3(1.0, 0.06, 0.3), 0.02, p(P.PLANK))
	b.cbox(Vector3(0, 0.55, 0.13), Vector3(1.0, 0.24, 0.05), 0.02, p(P.PLANK))
	for x in [-0.42, 0.42]:
		b.box(Vector3(x, 0.15, 0), Vector3(0.05, 0.3, 0.28), MB.rgb("4c4a52"))
	return b.commit()

static func _m_mailbox() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.35, 0), 0.03, 0.7, p(P.WOOD_DARK), 6)
	b.cbox(Vector3(0, 0.76, 0), Vector3(0.18, 0.16, 0.3), 0.06, MB.rgb("5b8fd6"))
	b.box(Vector3(0.1, 0.84, 0.05), Vector3(0.02, 0.12, 0.04), MB.rgb("ef5b4c"))
	return b.commit()

static func _m_flower_bed() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, 0.08, 0), Vector3(1.2, 0.16, 0.5), 0.04, p(P.PLANK))
	b.cbox(Vector3(0, 0.15, 0), Vector3(1.1, 0.04, 0.42), 0.02, p(P.SOIL))
	for k in 7:
		var x := -0.45 + k * 0.15
		b.cyl(Vector3(x, 0.24, (k % 2) * 0.1 - 0.05), 0.012, 0.16, p(P.TUFT), 3, Basis(), -1.0, false)
		b.sphere(Vector3(x, 0.33, (k % 2) * 0.1 - 0.05), 0.06, p([P.FLOWER_A, P.FLOWER_B, P.BLOSSOM][k % 3]), 6, 3)
	return b.commit()

# ---------------------------------------------------------------- farm & pond

static func _m_silo() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 1.1, 0), 0.6, 2.2, MB.rgb("d7dde3"), 14)
	for k in 4:
		b.cyl(Vector3(0, 0.3 + k * 0.5, 0), 0.62, 0.05, MB.rgb("b8c0c9"), 14)
	b.sphere(Vector3(0, 2.2, 0), 0.6, p(P.ROOF_RED), 14, 6, Vector3(1, 0.55, 1))
	return b.commit()

static func _m_scarecrow() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.6, 0), 0.04, 1.2, p(P.WOOD_DARK), 6)
	b.cyl(Vector3(0, 0.85, 0), 0.03, 0.9, p(P.WOOD_DARK), 6, Basis(Vector3.BACK, PI * 0.5))
	b.cbox(Vector3(0, 0.78, 0), Vector3(0.36, 0.4, 0.2), 0.05, MB.rgb("6b8fd6"))
	b.sphere(Vector3(0, 1.12, 0), 0.15, p(P.HAY), 8, 5)
	b.cyl(Vector3(0, 1.24, 0), 0.24, 0.03, MB.rgb("c9944a"), 10)
	b.cyl(Vector3(0, 1.3, 0), 0.12, 0.12, MB.rgb("c9944a"), 10)
	for x in [-0.42, 0.42]:
		b.sphere(Vector3(x, 0.85, 0), 0.06, p(P.HAY), 6, 3)
	return b.commit()

static func _m_lily() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0, 0), 0.22, 0.02, p(P.LILY), 10)
	b.cyl(Vector3(0.15, 0, 0.18), 0.15, 0.02, p(P.LILY), 9)
	b.sphere(Vector3(0.02, 0.04, 0.0), 0.06, p(P.BLOSSOM), 6, 3, Vector3(1, 0.6, 1))
	return b.commit()

static func _m_reeds() -> ArrayMesh:
	var b := MB.new()
	for i in 7:
		var a := TAU * i / 7.0
		var h := 0.5 + (i % 3) * 0.15
		var bs := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.12)
		b.cyl(Vector3(cos(a) * 0.12, h * 0.5, sin(a) * 0.12), 0.02, h, p(P.REED), 4, bs, -1.0, false)
		if i % 2 == 0:
			b.cyl(Vector3(cos(a) * 0.12, h + 0.04, sin(a) * 0.12), 0.035, 0.12, MB.rgb("7a5236"), 5, bs)
	return b.commit()

static func _m_duck() -> ArrayMesh:
	var b := MB.new()
	b.sphere(Vector3(0, 0.08, 0), 0.12, MB.rgb("fff6e8"), 8, 5, Vector3(0.8, 0.7, 1.2))
	b.sphere(Vector3(0, 0.2, -0.1), 0.07, MB.rgb("fff6e8"), 8, 5)
	b.cbox(Vector3(0, 0.19, -0.18), Vector3(0.05, 0.02, 0.07), 0.01, MB.rgb("ff9f3d"))
	b.sphere(Vector3(0.035, 0.23, -0.14), 0.012, MB.rgb("2b2b33"), 4, 2)
	b.sphere(Vector3(-0.035, 0.23, -0.14), 0.012, MB.rgb("2b2b33"), 4, 2)
	return b.commit()

static func _m_apple_tree() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.4, 0), 0.1, 0.8, p(P.TRUNK), 7)
	b.sphere(Vector3(0, 1.1, 0), 0.55, p(P.LEAF_A), 12, 7, Vector3(1.05, 0.85, 1.05))
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for k in 9:
		var a := rng.randf() * TAU
		var e := rng.randf_range(-0.2, 0.6)
		var dir := Vector3(cos(a) * cos(e), sin(e) * 0.85, sin(a) * cos(e))
		b.sphere(Vector3(0, 1.1, 0) + dir * 0.52, 0.06, p(P.FRUIT), 6, 3)
	return b.commit()

static func _m_apple_crate() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, 0.15, 0), Vector3(0.5, 0.3, 0.4), 0.03, p(P.PLANK))
	for i in 3:
		for j in 2:
			b.sphere(Vector3(-0.14 + i * 0.14, 0.32, -0.08 + j * 0.16), 0.07, MB.rgb("e8473f"), 6, 3)
	return b.commit()

# ---------------------------------------------------------------- seaside

static func _m_towel() -> ArrayMesh:
	# built white so each instance can be tinted
	var b := MB.new()
	b.cbox(Vector3(0, 0.015, 0), Vector3(0.7, 0.03, 1.3), 0.01, MB.rgb("ffffff"))
	for k in 3:
		b.box(Vector3(0, 0.032, -0.4 + k * 0.4), Vector3(0.7, 0.005, 0.1), MB.rgb("e6e6e6"))
	return b.commit()

static func _m_surfboard() -> ArrayMesh:
	var b := MB.new()
	b.sphere(Vector3(0, 0.75, 0), 0.5, MB.rgb("ffffff"), 10, 6, Vector3(0.35, 1.6, 0.08))
	b.box(Vector3(0, 0.75, 0.045), Vector3(0.04, 1.4, 0.01), MB.rgb("e8e8e8"))
	return b.commit()

static func _m_beach_ball() -> ArrayMesh:
	var b := MB.new()
	for k in 6:
		var col := MB.rgb(["ff6f61", "ffffff", "ffd166", "ffffff", "6ec6ff", "ffffff"][k])
		b.sphere(Vector3(0, 0.18, 0), 0.18, col, 2, 7, Vector3.ONE, Basis(Vector3.UP, TAU * k / 6.0))
	return b.commit()

static func _m_lifeguard() -> ArrayMesh:
	var b := MB.new()
	for x in [-0.4, 0.4]:
		for z in [-0.4, 0.4]:
			b.cyl(Vector3(x * 0.9, 0.75, z * 0.9), 0.05, 1.5, MB.rgb("ffffff"), 6, Basis(Vector3(z, 0, -x).normalized(), 0.08))
	b.cbox(Vector3(0, 1.55, 0), Vector3(1.0, 0.1, 1.0), 0.03, p(P.PLANK))
	b.cbox(Vector3(0, 1.85, 0.4), Vector3(1.0, 0.5, 0.06), 0.03, MB.rgb("ef5b4c"))
	b.cbox(Vector3(0, 2.4, 0), Vector3(1.2, 0.08, 1.2), 0.03, MB.rgb("ffffff"))
	for x in [-0.5, 0.5]:
		b.cyl(Vector3(x, 2.0, -0.4), 0.03, 0.8, MB.rgb("ffffff"), 5)
	b.cbox(Vector3(0, 1.88, 0.44), Vector3(0.5, 0.18, 0.02), 0.01, MB.rgb("ffffff"))
	return b.commit()

static func _m_boat() -> ArrayMesh:
	var b := MB.new()
	b.sphere(Vector3(0, 0.12, 0), 0.5, MB.rgb("ffffff"), 12, 6, Vector3(0.55, 0.42, 1.25))
	b.cbox(Vector3(0, 0.22, 0), Vector3(0.48, 0.06, 1.05), 0.03, MB.rgb("c38757"))
	b.box(Vector3(0, 0.16, 0), Vector3(0.58, 0.05, 1.2), MB.rgb("5b8fd6"))
	b.cyl(Vector3(0, 0.9, 0.05), 0.03, 1.4, MB.rgb("8a5a35"), 6)
	var top := Vector3(0, 1.55, 0.05)
	var a := Vector3(0, 0.35, -0.5)
	var c := Vector3(0, 0.35, 0.05)
	b.tri(top, a, c, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, MB.rgb("fff6e8"))
	b.tri(top, c, a, Vector3.LEFT, Vector3.LEFT, Vector3.LEFT, MB.rgb("fff6e8"))
	return b.commit()

static func _m_kiosk() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, 0.5, 0), Vector3(1.2, 1.0, 0.9), 0.05, MB.rgb("fff6ee"))
	b.box(Vector3(0, 0.62, 0.46), Vector3(0.9, 0.4, 0.02), MB.glow("ffe3a3"))
	b.cbox(Vector3(0, 1.0, 0.55), Vector3(1.3, 0.06, 0.4), 0.02, MB.rgb("ff9fbf"), Basis(Vector3.RIGHT, -0.3))
	for k in 6:
		b.box(Vector3(-0.55 + k * 0.22, 0.98, 0.6), Vector3(0.11, 0.05, 0.4), MB.rgb("ffffff"), Basis(Vector3.RIGHT, -0.3))
	b.cyl(Vector3(0, 1.35, 0), 0.16, 0.36, MB.rgb("e8b46a"), 10, Basis(Vector3.RIGHT, PI), 0.0)
	b.sphere(Vector3(0, 1.58, 0), 0.2, MB.rgb("ffc2d6"), 10, 6)
	return b.commit()

static func _m_cafe_table() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.35, 0), 0.03, 0.7, MB.rgb("ffffff"), 6)
	b.cyl(Vector3(0, 0.7, 0), 0.32, 0.04, MB.rgb("ffffff"), 12)
	b.cyl(Vector3(0, 1.0, 0), 0.02, 0.7, MB.rgb("ffffff"), 5)
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		var col := MB.rgb("6ec6ff" if i % 2 == 0 else "ffffff")
		var tp := Vector3(0, 1.5, 0)
		var p0 := Vector3(cos(a0) * 0.6, 1.25, sin(a0) * 0.6)
		var p1 := Vector3(cos(a1) * 0.6, 1.25, sin(a1) * 0.6)
		var nm := (p0 - tp).cross(p1 - tp).normalized()
		if nm.y < 0: nm = -nm
		b.tri(tp, p0, p1, nm, nm, nm, col)
		b.tri(tp, p1, p0, -nm, -nm, -nm, col)
	return b.commit()

# ---------------------------------------------------------------- forest & mountains

static func _m_tent() -> ArrayMesh:
	# white canvas for instance tinting
	var b := MB.new()
	var h := 0.9
	var w := 0.8
	var d := 1.2
	var A := Vector3(-w, 0, -d * 0.5); var B := Vector3(w, 0, -d * 0.5)
	var C := Vector3(w, 0, d * 0.5); var D := Vector3(-w, 0, d * 0.5)
	var E := Vector3(0, h, -d * 0.5); var F := Vector3(0, h, d * 0.5)
	var nl := Vector3(-h, w, 0).normalized(); var nr := Vector3(h, w, 0).normalized()
	b.quad(A, D, F, E, nl, MB.rgb("ffffff"))
	b.quad(B, C, F, E, nr, MB.rgb("ffffff"))
	b.tri(A, B, E, Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD, MB.rgb("e8e8e8"))
	b.tri(D, C, F, Vector3.BACK, Vector3.BACK, Vector3.BACK, MB.rgb("e8e8e8"))
	b.tri(Vector3(-0.22, 0, d * 0.5 + 0.01), Vector3(0.22, 0, d * 0.5 + 0.01), Vector3(0, 0.55, d * 0.5 + 0.01), Vector3.BACK, Vector3.BACK, Vector3.BACK, MB.rgb("6a5c58"))
	b.cyl(Vector3(0, h * 0.5, d * 0.5 + 0.05), 0.02, h + 0.1, MB.rgb("8a5a35"), 4)
	return b.commit()

static func _m_campfire() -> ArrayMesh:
	var b := MB.new()
	for i in 8:
		var a := TAU * i / 8.0
		b.sphere(Vector3(cos(a) * 0.32, 0.05, sin(a) * 0.32), 0.09, p(P.ROCK), 6, 3, Vector3(1.2, 0.7, 1.0))
	for i in 3:
		var a := TAU * i / 3.0
		b.cyl(Vector3(cos(a) * 0.1, 0.12, sin(a) * 0.1), 0.045, 0.45, p(P.TRUNK), 6, Basis(Vector3(-sin(a), 0, cos(a)), 1.1))
	b.sphere(Vector3(0, 0.06, 0), 0.14, MB.glow("ff8a3d"), 6, 3, Vector3(1, 0.4, 1))
	return b.commit()

static func _m_flame() -> ArrayMesh:
	var b := MB.new()
	b.sphere(Vector3(0, 0.2, 0), 0.16, MB.rgb("ff8a3d"), 8, 5, Vector3(1, 1.7, 1))
	b.sphere(Vector3(0, 0.18, 0), 0.1, MB.rgb("ffd166"), 8, 5, Vector3(1, 1.6, 1))
	return b.commit()

static func _m_canoe() -> ArrayMesh:
	var b := MB.new()
	b.sphere(Vector3(0, 0.1, 0), 0.5, MB.rgb("ffffff"), 12, 6, Vector3(0.38, 0.32, 1.7))
	b.cbox(Vector3(0, 0.2, 0), Vector3(0.28, 0.03, 1.2), 0.01, MB.rgb("c38757"))
	b.cyl(Vector3(0.3, 0.12, 0.2), 0.02, 1.0, MB.rgb("c38757"), 5, Basis(Vector3.RIGHT, PI * 0.5))
	return b.commit()

static func _m_woodpile() -> ArrayMesh:
	var b := MB.new()
	var rot := Basis(Vector3.BACK, PI * 0.5)
	for r in 3:
		for k in 4 - r:
			b.cyl(Vector3(-0.3 + k * 0.2 + r * 0.1, 0.09 + r * 0.16, 0), 0.085, 0.6, p(P.TRUNK), 7, Basis(Vector3.RIGHT, PI * 0.5))
			b.cyl(Vector3(-0.3 + k * 0.2 + r * 0.1, 0.09 + r * 0.16, 0.301), 0.07, 0.01, MB.rgb("e3b27a"), 7, Basis(Vector3.RIGHT, PI * 0.5))
	return b.commit()

static func _m_lookout() -> ArrayMesh:
	var b := MB.new()
	for x in [-0.45, 0.45]:
		for z in [-0.45, 0.45]:
			b.cyl(Vector3(x, 1.2, z), 0.06, 2.4, p(P.WOOD_DARK), 6)
	b.cbox(Vector3(0, 2.4, 0), Vector3(1.3, 0.1, 1.3), 0.03, p(P.PLANK))
	for z in [-0.6, 0.6]:
		b.box(Vector3(0, 2.62, z), Vector3(1.3, 0.06, 0.05), p(P.WOOD_DARK))
	b.cbox(Vector3(0, 3.2, 0), Vector3(1.5, 0.12, 1.5), 0.04, p(P.ROOF_GREEN))
	for x in [-0.6, 0.6]:
		b.cyl(Vector3(x, 2.8, 0.6), 0.04, 0.8, p(P.WOOD_DARK), 5)
		b.cyl(Vector3(x, 2.8, -0.6), 0.04, 0.8, p(P.WOOD_DARK), 5)
	for k in 5:
		b.box(Vector3(0, 0.3 + k * 0.45, 0.5), Vector3(0.5, 0.05, 0.08), p(P.WOOD_DARK))
	return b.commit()

static func _m_peak() -> ArrayMesh:
	# a tall craggy mountain spire with a snowy top (sits beside the road, solid)
	var b := MB.new()
	b.cyl(Vector3(0, 1.4, 0), 1.3, 2.8, p(P.ROCK), 7, Basis(), 0.85, true, false)
	b.cyl(Vector3(0.1, 3.3, 0.05), 0.85, 1.2, p(P.ROCK), 7, Basis(), 0.45, true, false)
	b.cyl(Vector3(0.12, 4.15, 0.06), 0.47, 0.6, p(P.SNOWCAP), 7, Basis(), 0.05, true, false)
	b.cyl(Vector3(0.1, 3.75, 0.05), 0.62, 0.22, p(P.SNOWCAP), 7, Basis(), 0.47, false, false)
	b.cbox(Vector3(-0.8, 0.5, 0.6), Vector3(0.9, 1.0, 0.9), 0.15, p(P.ROCK))
	b.cbox(Vector3(0.9, 0.4, -0.5), Vector3(0.7, 0.8, 0.8), 0.12, p(P.PEBBLE))
	return b.commit()

# ---------------------------------------------------------------- sky ruins & balloon port

static func _m_ruin_arch() -> ArrayMesh:
	var b := MB.new()
	for x in [-0.9, 0.9]:
		b.cbox(Vector3(x, 0.08, 0), Vector3(0.5, 0.16, 0.5), 0.03, p(P.COBBLE))
		b.cyl(Vector3(x, 0.95, 0), 0.17, 1.6, p(P.STONE), 10)
		b.cbox(Vector3(x, 1.8, 0), Vector3(0.46, 0.12, 0.46), 0.03, p(P.STONE))
	b.cbox(Vector3(0, 1.96, 0), Vector3(2.4, 0.22, 0.5), 0.05, p(P.STONE))
	b.sphere(Vector3(0, 2.15, 0), 0.14, MB.glow("bfe9ff"), 8, 5)
	for k in 5:
		b.sphere(Vector3(-0.8 + k * 0.4, 2.08, 0.26), 0.07, p(P.MOSS), 6, 3)
	return b.commit()

static func _m_column_broken() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, 0.08, 0), Vector3(0.5, 0.16, 0.5), 0.03, p(P.COBBLE))
	b.cyl(Vector3(0, 0.5, 0), 0.17, 0.7, p(P.STONE), 10)
	b.cyl(Vector3(0.45, 0.12, 0.2), 0.17, 0.6, p(P.STONE), 10, Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.UP, 0.4))
	b.sphere(Vector3(0, 0.88, 0), 0.12, p(P.MOSS), 6, 3, Vector3(1.3, 0.5, 1.3))
	return b.commit()

static func _m_tether() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, 0.1, 0), Vector3(0.6, 0.2, 0.6), 0.04, p(P.PLANK))
	b.cyl(Vector3(0, 0.35, 0), 0.06, 0.4, p(P.WOOD_DARK), 6)
	return b.commit()

static func _m_rope() -> ArrayMesh:
	var b := MB.new()
	b.cyl(Vector3(0, 0.5, 0), 0.012, 1.0, MB.rgb("e9d2b0"), 4)
	return b.commit()

# ---------------------------------------------------------------- parked toy cars (static, from the garage set)

static func parked(def: Dictionary) -> ArrayMesh:
	var key := "parked_" + String(def["id"])
	if _cache.has(key):
		return _cache[key]
	var c := car(def)
	var st := SurfaceTool.new()
	st.append_from(c["body"], 0, Transform3D(Basis(), Vector3(0, c["ride"], 0)))
	for i in 4:
		st.append_from(wheel_mesh(c, i), 0, Transform3D(Basis(), c["wheels"][i]))
	var m := st.commit()
	_cache[key] = m
	return m

# ---------------------------------------------------------------- Kenney kits (CC0, kenney.nl)
# Baked by tools/kenney/bake_kenney.gd into assets/kenney/k_<pack>_<model>.res, facing -Z, painted colours kept.
# Each kit has its own scale; these bring them in line with the toy world (tile 1.6 m, people about 1 m tall).

const K_PACK_SCALE := {"sub": 7.5, "com": 10.0, "mod": 5.0, "retro": 4.6, "arena": 4.0, "car": 1.75, "skate": 4.0, "surv": 3.8,
	"forest": 5.5, "castle": 8.0, "holi": 1.6, "chars": 2.3}
const K_SCALE := {
	"k_surv_tree": 6.4, "k_surv_tree-tall": 6.4, "k_surv_tree-autumn": 6.4, "k_surv_tree-autumn-tall": 6.4, "k_surv_tree-trunk": 5.0,
	"k_surv_tent": 4.4, "k_surv_tent-canvas": 4.4, "k_surv_campfire-pit": 4.0, "k_surv_patch-grass": 5.0,
	"k_forest_tent": 2.6, "k_forest_flag": 4.0, "k_forest_plant": 3.0, "k_forest_target": 3.0,
	"k_castle_tree-large": 5.0, "k_castle_tree-small": 5.0, "k_castle_rocks-large": 6.0, "k_castle_rocks-small": 6.0,
	"k_castle_siege-catapult": 4.0, "k_castle_siege-trebuchet": 4.0, "k_castle_flag": 6.0, "k_castle_flag-pennant": 6.0,
	"k_castle_flag-banner-long": 5.0,
	"k_skate_skateboard": 1.2, "k_skate_scooter": 1.3, "k_skate_bench": 3.0, "k_skate_benches": 3.0,
	"k_retro_detail-bench": 3.0, "k_retro_detail-barrier-type-a": 3.0, "k_retro_detail-barrier-type-b": 3.0,
	"k_retro_detail-barrier-strong-type-a": 3.0, "k_retro_detail-dumpster-closed": 3.0, "k_retro_pallet": 1.3,
	"k_retro_truck-green": 4.0, "k_retro_truck-grey": 4.0, "k_retro_truck-flat": 4.0,
	"k_com_detail-parasol-a": 5.5, "k_com_detail-parasol-b": 5.5,
	"k_car_cone": 1.25, "k_car_cone-flat": 1.25, "k_car_box": 1.4,
	"k_holi_tree-decorated": 2.2, "k_holi_lantern": 2.0, "k_holi_lantern-hanging": 2.0, "k_holi_present-a-cube": 1.1,
	"k_holi_present-b-round": 1.1, "k_holi_present-a-rectangle": 1.1, "k_holi_candy-cane-red": 2.6, "k_holi_reindeer": 1.4,
	"k_holi_lights-colored": 3.0, "k_holi_nutcracker": 1.9, "k_holi_sled": 1.4, "k_holi_bench": 2.2,
	"k_arena_statue": 3.0, "k_arena_trophy": 3.0, "k_arena_column": 5.0, "k_arena_tree": 5.0,
	"k_sub_tree-large": 7.5, "k_sub_tree-small": 7.5,
	"k_pirate_barrel": 0.7, "k_pirate_crate": 0.85, "k_pirate_crate-bottles": 0.85, "k_pirate_chest": 0.8, "k_pirate_cannon": 1.2,
	"k_pirate_palm-straight": 2.2, "k_pirate_palm-bend": 2.2, "k_pirate_palm-detailed-straight": 2.2, "k_pirate_palm-detailed-bend": 2.2,
	"k_pirate_rocks-sand-a": 1.0, "k_pirate_rocks-sand-b": 1.0, "k_pirate_rocks-sand-c": 1.0, "k_pirate_boat-row-large": 1.4,
	"k_pirate_boat-row-small": 1.4, "k_pirate_tower-watch": 1.8, "k_pirate_structure": 2.2, "k_pirate_structure-roof": 2.2,
	"k_pirate_flag-high-pennant": 2.0,
}
# pets: heights in metres
const K_PET_H := {"cow": 1.6, "elephant": 2.4, "giraffe": 3.0, "deer": 1.4, "bee": 0.3, "chick": 0.35, "crab": 0.35,
	"caterpillar": 0.3, "fish": 0.4, "parrot": 0.5, "penguin": 0.7, "bunny": 0.45, "hog": 1.0, "pig": 0.9, "polar": 1.3,
	"lion": 1.1, "tiger": 1.0, "panda": 1.1, "dog": 0.6, "cat": 0.4, "fox": 0.6, "beaver": 0.55, "koala": 0.6, "monkey": 0.7}
static var _kmeta := {}

static func kmeta() -> Dictionary:
	if _kmeta.is_empty():
		_kmeta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/kenney/kenney_meta.json"))
	return _kmeta

static func kscale(name: String) -> float:
	if K_SCALE.has(name):
		return K_SCALE[name]
	var pack := name.get_slice("_", 1)
	if pack == "pets":
		var a: Array = kmeta().get(name, [0, 0, 0, 1, 1, 1])
		return float(K_PET_H.get(name.trim_prefix("k_pets_animal-"), 0.5)) / float(a[4])
	return K_PACK_SCALE.get(pack, 1.0)

## Size of a Kenney model as the game shows it.
static func ksize(name: String) -> Vector3:
	var a: Array = kmeta().get(name, [0, 0, 0, 1, 1, 1])
	return Vector3(a[3], a[4], a[5]) * kscale(name)

static func _k_mesh(name: String) -> ArrayMesh:
	var src: ArrayMesh = load("res://assets/kenney/%s.res" % name)
	var key := name
	if name.begins_with("k_chars_"):
		key = "k_chars_" + name.get_slice("_", 2)
	var sc := kscale(key)
	if is_equal_approx(sc, 1.0):
		return src
	return scaled(src, sc)

# ---------------------------------------------------------------- toy people (Kenney mini characters)
# Each has a body and two loose arms (pivots at the shoulders) for standing and for sitting.

const CHARS := ["character-female-b", "character-female-c", "character-female-d", "character-female-e", "character-female-f",
	"character-male-a", "character-male-b", "character-male-c", "character-male-d", "character-male-e", "character-male-f",
	"character-male-g", "character-worker"]

## pose "stand" / "sit"; part "" body, "al" / "ar" arms
static func kperson(v: int, pose: String, part := "") -> ArrayMesh:
	var nm := "k_chars_%s_%s" % [CHARS[v % CHARS.size()], pose]
	return get_mesh(nm if part == "" else nm + "_" + part)

## Shoulder positions [left, right] for a character's pose.
static func kshoulders(v: int, pose: String) -> Array:
	var a: Array = kmeta()["k_chars_%s_%s_pivots" % [CHARS[v % CHARS.size()], pose]]
	var sc: float = K_PACK_SCALE["chars"]
	return [Vector3(a[0], a[1], a[2]) * sc, Vector3(a[3], a[4], a[5]) * sc]

# ---------------------------------------------------------------- stunt yard

## A loop-the-loop you can drive: the track climbs, goes over upside down and comes back down a lane to
## the side (a corkscrew), so the way out never runs into the way in. Like a real one it bends gently at
## first (a clothoid) and tightest over the top, so a car's nose doesn't dig in. In the stunt kit's colours.
## Travel is toward -Z; you drive in on the left lane (x = -LOOP_SHIFT/2) and out on the right.
const LOOP_R := 7.0          # tightest radius, over the top
const LOOP_EASE := 11.0      # how long the bend takes to tighten up, in and out (m)
const LOOP_W := 6.0          # track width
const LOOP_SHIFT := 7.2      # how far the way out sits to the side of the way in
static var _loop_frames: Array = []

## Samples along the loop: [point, along, side, up (into the track's middle)], start to finish.
static func loop_frames() -> Array:
	if not _loop_frames.is_empty():
		return _loop_frames
	var kmax := 1.0 / LOOP_R
	var total := LOOP_EASE * 2.0 + (TAU - kmax * LOOP_EASE) / kmax
	var n := 180
	var sub := 10
	var h := total / (n * sub)
	var f := 0.0
	var y := 0.0
	var phi := 0.0
	var raw := []
	for i in n + 1:
		var u := float(i) / n
		var x := -LOOP_SHIFT * 0.5 + LOOP_SHIFT * (u - sin(TAU * u) / TAU)
		raw.append([Vector3(x, y, -f), phi])
		if i == n:
			break
		for k in sub:
			var sm := (i * sub + k + 0.5) * h
			var kap := kmax * minf(1.0, minf(sm, total - sm) / LOOP_EASE)
			var pm := phi + kap * h * 0.5
			f += cos(pm) * h
			y += sin(pm) * h
			phi += kap * h
	for i in raw.size():
		var p: Vector3 = raw[i][0]
		var ph: float = raw[i][1]
		var a: Vector3 = raw[maxi(i - 1, 0)][0]
		var b: Vector3 = raw[mini(i + 1, raw.size() - 1)][0]
		var tg := (b - a).normalized()
		var side := (Vector3.RIGHT - tg * tg.x).normalized()
		var up := side.cross(tg).normalized()
		if up.dot(Vector3(0, cos(ph), sin(ph))) < 0.0:
			up = -up
		_loop_frames.append([p, tg, side, up])
	return _loop_frames

## The top of the loop (model coords).
static func loop_top() -> Vector3:
	var fr := loop_frames()
	return fr[fr.size() / 2][0]

static func _m_stunt_loop() -> ArrayMesh:
	var b := MB.new()
	var deck := MB.rgb("5c5853")
	var stripe := MB.rgb("f2c230")
	var red := MB.rgb("b03a2c")
	var under := MB.rgb("7e2a21")
	var th_k := 0.3            # deck thickness
	var rail_h := 0.45
	var rail_w := 0.2
	var hw := LOOP_W * 0.5
	var frames: Array = []
	for fr in loop_frames():
		frames.append([fr[0], fr[2], fr[3]])
	var steps := frames.size() - 1
	for i in steps:
		var f0: Array = frames[i]
		var f1: Array = frames[i + 1]
		var p0: Vector3 = f0[0]; var s0: Vector3 = f0[1]; var u0: Vector3 = f0[2]
		var p1: Vector3 = f1[0]; var s1: Vector3 = f1[1]; var u1: Vector3 = f1[2]
		# the deck: a yellow edge stripe each side, dark in the middle
		var cuts := [-hw, -hw + 0.3, hw - 0.3, hw]
		for k in 3:
			var a0 := p0 + s0 * float(cuts[k]); var a1 := p1 + s1 * float(cuts[k])
			var b0 := p0 + s0 * float(cuts[k + 1]); var b1 := p1 + s1 * float(cuts[k + 1])
			var col: Color = deck if k == 1 else stripe
			b.tri(a0, b0, b1, u0, u0, u1, col)
			b.tri(a0, b1, a1, u0, u1, u1, col)
		# the underside
		var l0 := p0 - s0 * (hw + rail_w) - u0 * th_k; var l1 := p1 - s1 * (hw + rail_w) - u1 * th_k
		var r0 := p0 + s0 * (hw + rail_w) - u0 * th_k; var r1 := p1 + s1 * (hw + rail_w) - u1 * th_k
		b.tri(l0, r1, r0, -u0, -u1, -u0, under)
		b.tri(l0, l1, r1, -u0, -u1, -u1, under)
		# a rail along each edge (red), standing up from the deck
		for sd in [-1.0, 1.0]:
			var in0: Vector3 = p0 + s0 * hw * sd; var in1: Vector3 = p1 + s1 * hw * sd
			var out0: Vector3 = p0 + s0 * (hw + rail_w) * sd; var out1: Vector3 = p1 + s1 * (hw + rail_w) * sd
			var n_in: Vector3 = -s0 * sd
			# inner face
			b.tri(in0, in1 + u1 * rail_h, in1, n_in, n_in, n_in, red)
			b.tri(in0, in0 + u0 * rail_h, in1 + u1 * rail_h, n_in, n_in, n_in, red)
			# top
			b.tri(in0 + u0 * rail_h, out1 + u1 * rail_h, in1 + u1 * rail_h, u0, u1, u1, red)
			b.tri(in0 + u0 * rail_h, out0 + u0 * rail_h, out1 + u1 * rail_h, u0, u0, u1, red)
			# outer face, down past the deck to the underside
			b.tri(out0 - u0 * th_k, out1 + u1 * rail_h, out0 + u0 * rail_h, -n_in, -n_in, -n_in, red)
			b.tri(out0 - u0 * th_k, out1 - u1 * th_k, out1 + u1 * rail_h, -n_in, -n_in, -n_in, red)
	# legs: a frame each side holding the loop up where its track stands upright
	var fr2 := loop_frames()
	var half := fr2.size() / 2
	for span in [[0, half], [half, fr2.size()]]:
		var best: int = span[0]
		for i in range(span[0], span[1]):
			if absf((fr2[i][1] as Vector3).y) > absf((fr2[best][1] as Vector3).y):
				best = i
		var p: Vector3 = fr2[best][0]
		var outz := 1.0 if (fr2[best][3] as Vector3).z < 0.0 else -1.0
		var zo := p.z + outz * (th_k + 0.25)
		for sx in [-1.0, 1.0]:
			var x: float = p.x + float(sx) * (hw - 0.6)
			b.cbox(Vector3(x, (p.y + 0.8) * 0.5, zo), Vector3(0.36, p.y + 0.8, 0.36), 0.04, red)
			b.cbox(Vector3(x, 0.08, zo), Vector3(0.9, 0.16, 0.9), 0.03, MB.rgb("3c3a38"))
			# a diagonal brace out to a foot further along
			var foot := Vector3(x, 0.0, zo + outz * 3.0)
			var top := Vector3(x, p.y * 0.62, zo)
			var bs := Basis.looking_at(top - foot, Vector3.RIGHT)
			b.cbox((foot + top) * 0.5, Vector3(0.26, 0.26, (top - foot).length()), 0.03, red, bs)
			b.cbox(foot + Vector3(0, 0.08, 0), Vector3(0.7, 0.16, 0.7), 0.03, MB.rgb("3c3a38"))
		b.cbox(Vector3(p.x, p.y * 0.55, zo), Vector3(LOOP_W - 0.9, 0.3, 0.3), 0.03, red)
	return b.commit()

## A lead-in for the end of a half-pipe (at 1.5x, sunk 0.1 m): its top rises from the ground to meet the
## pipe's curved floor at z = 0, so you can roll in off-centre. Outward is +Z.
static func _m_hp_lip() -> ArrayMesh:
	var b := MB.new()
	var deck := MB.rgb("5c5853")
	var red := MB.rgb("b03a2c")
	var xs := [0.0, 0.9, 1.65, 2.55, 3.3, 4.2]
	var hs := [0.02, 0.08, 0.25, 0.52, 0.95, 1.54]
	var ln := 2.6
	for sd in [-1.0, 1.0]:
		for i in xs.size() - 1:
			var x0: float = float(xs[i]) * sd
			var x1: float = float(xs[i + 1]) * sd
			var h0: float = hs[i]
			var h1: float = hs[i + 1]
			var a0 := Vector3(x0, h0, 0.0)
			var a1 := Vector3(x1, h1, 0.0)
			var e0 := Vector3(x0, 0.0, ln)
			var e1 := Vector3(x1, 0.0, ln * (1.0 + h1 * 0.6))
			var nm := (a1 - a0).cross(e0 - a0).normalized()
			if nm.y < 0.0:
				nm = -nm
			b.tri(a0, a1, e1, nm, nm, nm, deck)
			b.tri(a0, e1, e0, nm, nm, nm, deck)
		# the open side at the outer end of the lip
		var xo: float = float(xs[xs.size() - 1]) * sd
		var ho: float = hs[hs.size() - 1]
		var outn := Vector3(sd, 0, 0)
		b.tri(Vector3(xo, 0, 0), Vector3(xo, ho, 0), Vector3(xo, 0, ln * (1.0 + ho * 0.6)), outn, outn, outn, red)
	return b.commit()

static func _m_rainbow() -> ArrayMesh:
	var b := MB.new()
	var cols := ["ff7a6b", "ffb85c", "ffe27a", "8fd19e", "6ec6ff", "a998f2"]
	for k in cols.size():
		var r := 2.6 - k * 0.16
		for i in 18:
			var a0 := PI * i / 18.0
			var a1 := PI * (i + 1) / 18.0
			var p0 := Vector3(cos(a0) * r, sin(a0) * r, 0)
			var p1 := Vector3(cos(a1) * r, sin(a1) * r, 0)
			var mid := (p0 + p1) * 0.5
			var len := p0.distance_to(p1)
			var bs := Basis(Vector3.BACK, (a0 + a1) * 0.5)
			b.box(mid, Vector3(0.17, len + 0.02, 0.16), MB.glow(cols[k]), bs)
	for x in [-2.35, 2.35]:
		b.sphere(Vector3(x, 0.15, 0), 0.45, p(P.CLOUD), 10, 6, Vector3(1.2, 0.7, 1))
	return b.commit()
