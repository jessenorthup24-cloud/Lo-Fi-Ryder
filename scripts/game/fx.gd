extends Node3D
## Pooled little effects: dust and drift smoke, skid marks, sparkles, confetti, splashes.

const M := preload("res://scripts/core/models.gd")
const MB := preload("res://scripts/core/mesh_builder.gd")
const Pool := preload("res://scripts/game/pool.gd")

var puffs: Pool
var skids: Pool
var bits: Pool
var live_puffs: Array = []
var live_skids: Array = []
var live_bits: Array = []

func setup(mat: ShaderMaterial) -> void:
	var soft: ShaderMaterial = mat.duplicate()
	soft.set_shader_parameter("rim_strength", 0.0)
	puffs = Pool.new()
	puffs.setup(M.get_mesh("puff"), 220, soft, false, false)
	add_child(puffs)
	skids = Pool.new()
	skids.setup(M.get_mesh("skid"), 260, mat, false, false)
	add_child(skids)
	var b := MB.new()
	b.cbox(Vector3.ZERO, Vector3(0.14, 0.14, 0.03), 0.02, MB.rgb("ffffff"))
	bits = Pool.new()
	bits.setup(b.commit(), 160, mat, false, false)
	add_child(bits)

func clear() -> void:
	puffs.clear_all(); skids.clear_all(); bits.clear_all()
	live_puffs.clear(); live_skids.clear(); live_bits.clear()

func puff(p: Vector3, col: Color, size := 0.35, v := Vector3.ZERO, life := 0.7, rise := 0.6) -> void:
	var s := puffs.alloc()
	if s < 0:
		return
	puffs.multimesh.set_instance_color(s, col)
	live_puffs.append({"s": s, "p": p, "v": v + Vector3(0, rise, 0), "t": 0.0, "life": life, "size": size})

func skid(p: Vector3, yaw: float) -> void:
	var s := skids.alloc()
	if s < 0:
		var old = live_skids.pop_front()
		skids.release(old["s"])
		s = skids.alloc()
	live_skids.append({"s": s, "p": p, "yaw": yaw, "t": 0.0})
	skids.put(s, Transform3D(Basis(Vector3.UP, yaw), p))

func burst(p: Vector3, cols: Array, n := 10, speed := 4.0, up := 4.0, life := 1.1) -> void:
	for i in n:
		var s := bits.alloc()
		if s < 0:
			return
		bits.multimesh.set_instance_color(s, Color(cols[i % cols.size()]))
		var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		live_bits.append({"s": s, "p": p, "v": dir * randf_range(0.4, 1.0) * speed + Vector3(0, up * randf_range(0.6, 1.2), 0),
			"r": Vector3(randf() * TAU, randf() * TAU, 0), "rv": Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)),
			"t": 0.0, "life": life * randf_range(0.7, 1.2), "g": 9.0})

func sparkle(p: Vector3, col: Color, n := 6) -> void:
	for i in n:
		var s := bits.alloc()
		if s < 0:
			return
		bits.multimesh.set_instance_color(s, col)
		var a := TAU * i / n
		live_bits.append({"s": s, "p": p, "v": Vector3(cos(a), 1.2, sin(a)) * 2.2, "r": Vector3(0, a, 0.78), "rv": Vector3(0, 6, 0),
			"t": 0.0, "life": 0.45, "g": 2.0})

func tick(dt: float) -> void:
	var done := []
	for q in live_puffs:
		q["t"] += dt
		var k: float = q["t"] / q["life"]
		if k >= 1.0:
			puffs.release(q["s"])
			done.append(q)
			continue
		q["v"] *= 1.0 - dt * 2.5
		q["p"] += q["v"] * dt
		var sz: float = q["size"] * (0.5 + k * 0.9) * (1.0 - k * k)
		puffs.put(q["s"], Transform3D(Basis().scaled(Vector3.ONE * maxf(sz, 0.001)), q["p"]))
	for q in done:
		live_puffs.erase(q)
	done.clear()
	for q in live_skids:
		q["t"] += dt
		if q["t"] > 2.6:
			skids.release(q["s"])
			done.append(q)
			continue
		var k := 1.0 - smoothstep(1.6, 2.6, q["t"])
		skids.put(q["s"], Transform3D(Basis(Vector3.UP, q["yaw"]).scaled(Vector3(k, 1, 1)), q["p"]))
	for q in done:
		live_skids.erase(q)
	done.clear()
	for q in live_bits:
		q["t"] += dt
		if q["t"] >= q["life"]:
			bits.release(q["s"])
			done.append(q)
			continue
		q["v"].y -= q["g"] * dt
		q["v"] *= 1.0 - dt * 0.8
		q["p"] += q["v"] * dt
		q["r"] += q["rv"] * dt
		var k: float = 1.0 - smoothstep(0.7, 1.0, q["t"] / q["life"])
		bits.put(q["s"], Transform3D(Basis.from_euler(q["r"]).scaled(Vector3.ONE * maxf(k, 0.001)), q["p"]))
	for q in done:
		live_bits.erase(q)
