extends RefCounted
## Every model in the game, built from code. Meshes are cached by name.

const MB := preload("res://scripts/core/mesh_builder.gd")
const P := preload("res://scripts/core/palette.gd")

const T := 1.6   # tile size (world units = meters)

static var _cache := {}

static func get_mesh(name: String) -> ArrayMesh:
	if _cache.has(name):
		return _cache[name]
	var m: ArrayMesh = load("res://scripts/core/models.gd").call("_m_" + name)
	_cache[name] = m
	return m

static func p(i: int) -> Color:
	return MB.pal(i)

# ---------------------------------------------------------------- terrain

static func _m_tile() -> ArrayMesh:
	var b := MB.new()
	b.cbox(Vector3(0, -0.13, 0), Vector3(T, 0.26, T), 0.05, MB.SIDE, Basis(), MB.TOP)
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
			var bs := Basis(Vector3.UP, sgn * 0.75)
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
static func car(def: Dictionary) -> Dictionary:
	var key := "car_" + String(def["id"])
	if _cache.has(key):
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
		st.append_from(c["wheel_f"] if i < 2 else c["wheel_r"], 0, Transform3D(Basis(), c["wheels"][i]))
	var m := st.commit()
	_cache[key] = m
	return m

# ---------------------------------------------------------------- toy people (peg figures)

# skin, hair, shirt, pants, hat ("" none / "cap" / "sunhat" / "beanie"), hat colour
const PEOPLE := [
	["f1c7a5", "4a3226", "ff7a6b", "4a6fa5", "", ""],
	["c98e66", "2b1d16", "3db5a6", "e8d9b5", "cap", "ffc94d"],
	["8d5a3b", "1d1512", "ffc94d", "3a3f4a", "", ""],
	["ffdcc0", "d9a441", "a998f2", "4a6fa5", "sunhat", "f3e1b0"],
	["e0ac82", "6b3e26", "6ec6ff", "8a5a35", "beanie", "ef5b4c"],
	["a86b47", "2b1d16", "ffffff", "3db5a6", "cap", "ff7a6b"],
]

static func person(v: int, sit: bool) -> ArrayMesh:
	var key := "person_%d_%s" % [v, "sit" if sit else "stand"]
	if _cache.has(key):
		return _cache[key]
	var d: Array = PEOPLE[v]
	var skin := MB.rgb(d[0]); var hair := MB.rgb(d[1]); var shirt := MB.rgb(d[2]); var pants := MB.rgb(d[3])
	var b := MB.new()
	var lift := 0.0 if not sit else -0.22
	for x in [-0.08, 0.08]:
		if sit:
			b.cyl(Vector3(x, 0.2, -0.12), 0.07, 0.3, pants, 7, Basis(Vector3.RIGHT, PI * 0.5))
			b.cyl(Vector3(x, 0.08, -0.27), 0.065, 0.2, pants, 7)
			b.cbox(Vector3(x, 0.02, -0.3), Vector3(0.1, 0.05, 0.16), 0.02, MB.rgb("3a3540"))
		else:
			b.cyl(Vector3(x, 0.19, 0), 0.07, 0.34, pants, 7)
			b.cbox(Vector3(x, 0.03, -0.03), Vector3(0.1, 0.06, 0.17), 0.02, MB.rgb("3a3540"))
	b.cyl(Vector3(0, 0.54 + lift, 0), 0.165, 0.38, shirt, 12)
	b.sphere(Vector3(0, 0.72 + lift, 0), 0.165, shirt, 12, 6, Vector3(1, 0.45, 1))
	b.sphere(Vector3(0, 0.36 + lift, 0), 0.165, pants, 12, 6, Vector3(1, 0.35, 1))
	var hy := 0.93 + lift
	b.sphere(Vector3(0, hy, 0), 0.155, skin, 12, 7)
	b.sphere(Vector3(0, hy + 0.03, 0.02), 0.162, hair, 12, 6, Vector3(1, 0.75, 1))
	b.sphere(Vector3(-0.05, hy + 0.0, -0.145), 0.018, MB.rgb("2b2530"), 5, 3)
	b.sphere(Vector3(0.05, hy + 0.0, -0.145), 0.018, MB.rgb("2b2530"), 5, 3)
	b.sphere(Vector3(0, hy - 0.05, -0.15), 0.014, MB.rgb("e87a7a"), 5, 3, Vector3(1.6, 0.6, 1))
	match String(d[4]):
		"cap":
			b.sphere(Vector3(0, hy + 0.07, 0.0), 0.165, MB.rgb(d[5]), 12, 6, Vector3(1, 0.6, 1))
			b.cbox(Vector3(0, hy + 0.06, -0.18), Vector3(0.2, 0.025, 0.14), 0.01, MB.rgb(d[5]))
		"sunhat":
			b.cyl(Vector3(0, hy + 0.08, 0), 0.3, 0.02, MB.rgb(d[5]), 14)
			b.cyl(Vector3(0, hy + 0.14, 0), 0.14, 0.12, MB.rgb(d[5]), 12)
			b.cyl(Vector3(0, hy + 0.1, 0), 0.145, 0.03, MB.rgb("ef8a8a"), 12)
		"beanie":
			b.sphere(Vector3(0, hy + 0.06, 0.0), 0.168, MB.rgb(d[5]), 12, 6, Vector3(1, 0.72, 1))
			b.sphere(Vector3(0, hy + 0.2, 0.0), 0.05, MB.rgb("ffffff"), 6, 3)
	var m := b.commit()
	_cache[key] = m
	return m

## One arm, hanging down from the shoulder (origin). Rotate it to wave.
static func arm(v: int) -> ArrayMesh:
	var key := "arm_%d" % v
	if _cache.has(key):
		return _cache[key]
	var d: Array = PEOPLE[v]
	var b := MB.new()
	b.cyl(Vector3(0, -0.13, 0), 0.05, 0.26, MB.rgb(d[2]), 6)
	b.sphere(Vector3(0, -0.3, 0), 0.055, MB.rgb(d[0]), 6, 4)
	var m := b.commit()
	_cache[key] = m
	return m

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
