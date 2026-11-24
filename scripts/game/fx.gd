extends Node3D
## Pooled little effects: dust and drift smoke, skid marks, sparkles, confetti, splashes; and for crashes,
## sparks, bits of bodywork and glass that tumble and bounce along the ground, and engine fire.

const M := preload("res://scripts/core/models.gd")
const MB := preload("res://scripts/core/mesh_builder.gd")
const Pool := preload("res://scripts/game/pool.gd")

var puffs: Pool
var skids: Pool
var bits: Pool
var live_puffs: Array = []
var live_skids: Array = []
var live_bits: Array = []
var chunks: Pool
var sparks: Pool
var flames: Pool
var live_chunks: Array = []
var live_sparks: Array = []
var live_flames: Array = []
var ground: Callable            # (x, z) -> the height of the ground there, for bits to land on
var splats: Pool                # blood on the ground (flat blots that stay a while)
var live_splats: Array = []
var live_drops: Array = []      # blood in the air (each leaves a blot where it lands)
const BLOOD := Color(0.74, 0.05, 0.06)     # (sRGB: the shader darkens it toward a deep red)

var smoke_mat: ShaderMaterial

func setup(mat: ShaderMaterial) -> void:
	# smoke: soft camera-facing puffs that fade (not little solid balls)
	smoke_mat = ShaderMaterial.new()
	smoke_mat.shader = load("res://shaders/smoke.gdshader")
	var qm := QuadMesh.new()
	qm.size = Vector2(1.7, 1.7)
	puffs = Pool.new()
	puffs.setup(qm, 220, smoke_mat, false, false)
	add_child(puffs)
	var marks: ShaderMaterial = mat.duplicate()
	marks.set_shader_parameter("depth_bias", 0.0009)
	marks.set_shader_parameter("rim_strength", 0.0)
	skids = Pool.new()
	skids.setup(M.get_mesh("skid"), 1200, marks, false, false)
	add_child(skids)
	var b := MB.new()
	b.cbox(Vector3.ZERO, Vector3(0.14, 0.14, 0.03), 0.02, MB.rgb("ffffff"))
	bits = Pool.new()
	bits.setup(b.commit(), 160, mat, false, false)
	add_child(bits)
	# crash bits: a bent scrap of panel (painted per instance), sparks (thin glowing streaks), flames
	var cb := MB.new()
	cb.cbox(Vector3(0, 0, 0), Vector3(0.36, 0.045, 0.24), 0.015, MB.rgb("ffffff"))
	cb.cbox(Vector3(0.15, 0.03, 0.02), Vector3(0.12, 0.04, 0.2), 0.01, MB.rgb("ffffff"), Basis(Vector3(0, 0, 1), 0.5))
	chunks = Pool.new()
	chunks.setup(cb.commit(), 120, mat, false, false)
	add_child(chunks)
	var sb := MB.new()
	sb.cbox(Vector3.ZERO, Vector3(0.07, 0.07, 0.34), 0.0, MB.rgb("ffffff"))
	sparks = Pool.new()
	sparks.setup(sb.commit(), 200, mat, false, false)
	add_child(sparks)
	# a blot: an uneven round splash, flat (it lies on the ground like a skid mark)
	var bm := MB.new()
	var rr := RandomNumberGenerator.new()
	rr.seed = 7
	var ring := PackedVector3Array()
	for i in 14:
		var a := TAU * i / 14.0
		var r := rr.randf_range(0.65, 1.0) if i % 3 != 0 else rr.randf_range(1.0, 1.35)
		ring.append(Vector3(cos(a) * r, 0, sin(a) * r) * 0.5)
	for i in 14:
		# (both ways round: it shows whichever way it's wound)
		bm.tri(Vector3.ZERO, ring[(i + 1) % 14], ring[i], Vector3.UP, Vector3.UP, Vector3.UP, MB.rgb("ffffff"))
		bm.tri(Vector3.ZERO, ring[i], ring[(i + 1) % 14], Vector3.UP, Vector3.UP, Vector3.UP, MB.rgb("ffffff"))
	splats = Pool.new()
	splats.setup(bm.commit(), 160, marks, false, false)
	add_child(splats)
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/flame.gdshader")
	var fq := QuadMesh.new()
	fq.size = Vector2(1.0, 1.3)
	flames = Pool.new()
	flames.setup(fq, 48, fm, false, false)
	add_child(flames)

func clear() -> void:
	puffs.clear_all(); skids.clear_all(); bits.clear_all(); chunks.clear_all(); sparks.clear_all(); flames.clear_all(); splats.clear_all()
	live_puffs.clear(); live_skids.clear(); live_bits.clear(); live_chunks.clear(); live_sparks.clear(); live_flames.clear()
	live_splats.clear(); live_drops.clear()

func puff(p: Vector3, col: Color, size := 0.35, v := Vector3.ZERO, life := 0.7, rise := 0.6) -> void:
	var s := puffs.alloc()
	if s < 0:
		return
	puffs.multimesh.set_instance_color(s, col)
	live_puffs.append({"s": s, "p": p, "v": v + Vector3(0, rise, 0), "t": 0.0, "life": life, "size": size, "c": col})

## A tyre mark: len along yaw, w wide (metres), lying on a surface with normal n.
func skid(p: Vector3, yaw: float, len := 0.24, w := 0.16, n := Vector3.UP) -> void:
	var s := skids.alloc()
	if s < 0:
		var old = live_skids.pop_front()
		skids.release(old["s"])
		s = skids.alloc()
	var b := Basis(Vector3.UP, yaw)
	if n.dot(Vector3.UP) < 0.999:
		b = Basis(Quaternion(Vector3.UP, n.normalized())) * b
	b = b.scaled(Vector3(w / 0.16, 1.0, len / 0.24))
	live_skids.append({"s": s, "b": b, "p": p, "t": 0.0})
	skids.put(s, Transform3D(b, p))

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

## Sparks off a scrape or a knock: hot streaks flying out along n (and every which way), falling fast.
func spark_burst(p: Vector3, n: Vector3, count := 12, speed := 7.0) -> void:
	for i in count:
		var s := sparks.alloc()
		if s < 0:
			return
		var hot := randf()
		# (alpha in the shader's glow band: they shine)
		sparks.multimesh.set_instance_color(s, Color(1.0, lerpf(0.55, 0.95, hot), lerpf(0.15, 0.7, hot), 0.55))
		var dir := (n * randf_range(0.3, 1.0) + Vector3(randf_range(-1, 1), randf_range(0.1, 1.0), randf_range(-1, 1)).normalized() * 0.9).normalized()
		live_sparks.append({"s": s, "p": p, "v": dir * speed * randf_range(0.5, 1.3), "t": 0.0, "life": randf_range(0.22, 0.5)})

## Bits of bodywork knocked off: they fly out along n, tumble, bounce and skid along the ground, lie there a
## few seconds and go. cols: the colours to pick from (the paint, black trim, chrome).
func debris(p: Vector3, n: Vector3, cols: Array, count := 6, speed := 5.0, size := 1.0) -> void:
	for i in count:
		var s := chunks.alloc()
		if s < 0:
			return
		chunks.multimesh.set_instance_color(s, Color(cols[i % cols.size()]))
		var v := n * speed * randf_range(0.4, 1.1) + Vector3(randf_range(-2.5, 2.5), randf_range(2.0, 5.5), randf_range(-2.5, 2.5))
		live_chunks.append({"s": s, "p": p + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.4), randf_range(-0.3, 0.3)), "v": v,
			"r": Vector3(randf() * TAU, randf() * TAU, randf() * TAU), "rv": Vector3(randf_range(-14, 14), randf_range(-10, 10), randf_range(-14, 14)),
			"t": 0.0, "life": randf_range(5.0, 7.5), "sz": size * randf_range(0.6, 1.35), "rest": false})

## A windscreen going: little glinting bits of glass.
func glass(p: Vector3, n: Vector3, count := 14) -> void:
	debris(p, n, ["cfeefa", "a9dcef", "f4fbff"], count, 4.0, 0.32)

## Blood thrown out from p along dir: drops that fly, fall and leave a blot where each lands.
func blood(p: Vector3, dir: Vector3, count := 14, speed := 5.0) -> void:
	for i in count:
		var s := bits.alloc()
		if s < 0:
			return
		bits.multimesh.set_instance_color(s, BLOOD.lerp(Color(0.55, 0.02, 0.04), randf() * 0.6))
		var v := dir * speed * randf_range(0.3, 1.1) + Vector3(randf_range(-1.6, 1.6), randf_range(0.8, 3.5), randf_range(-1.6, 1.6))
		live_drops.append({"s": s, "p": p + Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.3), randf_range(-0.2, 0.2)), "v": v,
			"t": 0.0, "sz": randf_range(0.5, 1.1)})

## A blot of blood on the ground at p (size: across, metres). It stays half a minute, then shrinks away.
func splat(p: Vector3, size := 0.5) -> void:
	var s := splats.alloc()
	if s < 0:
		var old = live_splats.pop_front()
		splats.release(old["s"])
		s = splats.alloc()
	splats.multimesh.set_instance_color(s, BLOOD.lerp(Color(0.56, 0.02, 0.04), randf() * 0.5))
	var gy: float = ground.call(p.x, p.z) if ground.is_valid() else p.y
	var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(size * randf_range(0.8, 1.25), 1.0, size * randf_range(0.8, 1.25)))
	var at := Vector3(p.x, gy + 0.05, p.z)
	live_splats.append({"s": s, "b": b, "p": at, "t": 0.0})
	splats.put(s, Transform3D(b.scaled(Vector3(0.3, 1, 0.3)), at))

## Fire from a wrecked engine: a lick of flame rising from p.
func flame(p: Vector3, size := 0.8, v := Vector3.ZERO, life := 0.45) -> void:
	var s := flames.alloc()
	if s < 0:
		return
	live_flames.append({"s": s, "p": p, "v": v + Vector3(0, 1.6, 0), "t": 0.0, "life": life, "size": size})

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
		var sz: float = q["size"] * (0.6 + k * 1.4)       # (it spreads as it thins out)
		puffs.put(q["s"], Transform3D(Basis().scaled(Vector3.ONE * maxf(sz, 0.001)), q["p"]))
		var c0: Color = q["c"]
		puffs.multimesh.set_instance_color(q["s"], Color(c0.r, c0.g, c0.b, (1.0 - k) * (1.0 - k) * minf(k * 8.0, 1.0)))
	for q in done:
		live_puffs.erase(q)
	done.clear()
	for q in live_skids:
		q["t"] += dt
		if q["t"] > 18.0:
			skids.release(q["s"])
			done.append(q)
			continue
		if q["t"] > 14.0:
			var k := 1.0 - smoothstep(14.0, 18.0, q["t"])
			skids.put(q["s"], Transform3D((q["b"] as Basis).scaled(Vector3(k, 1, 1)), q["p"]))
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
	_crash_tick(dt)

func _crash_tick(dt: float) -> void:
	var done := []
	for q in live_sparks:
		q["t"] += dt
		if q["t"] >= q["life"]:
			sparks.release(q["s"])
			done.append(q)
			continue
		q["v"].y -= 14.0 * dt
		q["p"] += q["v"] * dt
		var v: Vector3 = q["v"]
		var k: float = 1.0 - float(q["t"]) / float(q["life"])
		var len := clampf(v.length() * 0.07, 0.5, 2.2) * k
		var b := Basis.looking_at(v.normalized() if v.length() > 0.01 else Vector3.FORWARD, Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.RIGHT)
		sparks.put(q["s"], Transform3D(b.scaled(Vector3(k, k, len)), q["p"]))
	for q in done:
		live_sparks.erase(q)
	done.clear()
	for q in live_chunks:
		q["t"] += dt
		if q["t"] >= q["life"]:
			chunks.release(q["s"])
			done.append(q)
			continue
		var p: Vector3 = q["p"]
		var v: Vector3 = q["v"]
		var gy: float = ground.call(p.x, p.z) + 0.03 if ground.is_valid() else -1000.0
		if not q["rest"]:
			v.y -= 9.8 * dt
			p += v * dt
			q["r"] += q["rv"] * dt
			if p.y < gy:
				p.y = gy
				if v.y < -1.2:
					# a bounce: up a bit, skidding on, spinning less
					v = Vector3(v.x * 0.55, -v.y * 0.32, v.z * 0.55)
					q["rv"] *= 0.5
				else:
					v.y = 0.0
					var h := Vector3(v.x, 0, v.z)
					h = h.move_toward(Vector3.ZERO, 7.0 * dt)
					v = h
					q["rv"] *= 1.0 - minf(dt * 6.0, 1.0)
					if h.length() < 0.1:
						q["rest"] = true
			q["p"] = p
			q["v"] = v
		if q["rest"]:
			# lying flat on the ground
			var r: Vector3 = q["r"]
			r.x = lerp_angle(r.x, round(r.x / PI) * PI, minf(dt * 8.0, 1.0))
			r.z = lerp_angle(r.z, round(r.z / PI) * PI, minf(dt * 8.0, 1.0))
			q["r"] = r
		var k := 1.0 - smoothstep(float(q["life"]) - 0.8, float(q["life"]), float(q["t"]))
		chunks.put(q["s"], Transform3D(Basis.from_euler(q["r"]).scaled(Vector3.ONE * float(q["sz"]) * maxf(k, 0.001)), q["p"]))
	for q in done:
		live_chunks.erase(q)
	done.clear()
	for q in live_flames:
		q["t"] += dt
		var k: float = q["t"] / q["life"]
		if k >= 1.0:
			flames.release(q["s"])
			done.append(q)
			continue
		q["v"] *= 1.0 - dt * 1.5
		q["p"] += q["v"] * dt
		var sz: float = q["size"] * (1.0 - k * 0.6)
		flames.put(q["s"], Transform3D(Basis().scaled(Vector3.ONE * maxf(sz, 0.001)), q["p"]))
		flames.multimesh.set_instance_color(q["s"], Color(1, 1, 1, (1.0 - k) * minf(k * 6.0, 1.0)))
	for q in done:
		live_flames.erase(q)
	done.clear()
	for q in live_drops:
		q["t"] += dt
		q["v"].y -= 12.0 * dt
		q["p"] += q["v"] * dt
		var p: Vector3 = q["p"]
		var gy: float = ground.call(p.x, p.z) if ground.is_valid() else -1000.0
		if p.y <= gy + 0.05 or q["t"] > 2.5:
			bits.release(q["s"])
			done.append(q)
			if p.y <= gy + 0.3:
				splat(p, 0.18 + float(q["sz"]) * 0.22)
			continue
		var v: Vector3 = q["v"]
		var b := Basis.looking_at(v.normalized() if v.length() > 0.05 else Vector3.DOWN, Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.RIGHT)
		bits.put(q["s"], Transform3D(b.scaled(Vector3(0.6, 0.6, 1.6) * float(q["sz"])), p))
	for q in done:
		live_drops.erase(q)
	done.clear()
	for q in live_splats:
		q["t"] += dt
		var t: float = q["t"]
		if t > 34.0:
			splats.release(q["s"])
			done.append(q)
			continue
		if t < 0.25 or t > 30.0:
			# (it spreads out as it lands, and shrinks away at the end)
			var k := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(30.0, 34.0, t))
			splats.put(q["s"], Transform3D((q["b"] as Basis).scaled(Vector3(0.3 + k * 0.7, 1, 0.3 + k * 0.7) * maxf(k, 0.01) if t > 30.0 else Vector3(0.3 + k * 0.7, 1, 0.3 + k * 0.7)), q["p"]))
	for q in done:
		live_splats.erase(q)
