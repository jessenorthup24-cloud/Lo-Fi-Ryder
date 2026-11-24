extends Node3D
## People knocked down by a car. Each becomes a ragdoll: the upper body (with the head), the legs (jointed at
## the hips, so it folds) and the two arms (jointed at the shoulders, so they flail), weighing about 70 kg in
## all: heavy enough to thud off the bonnet and roll, light enough to go flying. It bleeds where it hits the
## road and leaves a pool where it stops; after a while (or once you're well away) it's taken away.
## The car's own physics treats these parts as nothing it crashed into (meta "ped").

const M := preload("res://scripts/core/models.gd")

const MAX := 6               # ragdolls at once (the oldest goes)
const LAYER := 32            # what they are, for collisions
const MASS := {"upper": 36.0, "legs": 24.0, "arm": 4.5}
const STAY := 28.0           # seconds one lies there before it's cleared
const HIP_K := 0.33          # the hips: this far up the body (the belt line on these characters)

var mat: Material
var fx: Node
var island: Node
var sound: Callable          # (name, db) -> plays a sound
var dolls: Array = []        # {root, parts: {upper, legs, al, ar}, t, still, pooled: bool, last_splat, landed}
static var _split := {}      # body mesh key -> {"upper": ArrayMesh, "legs": ArrayMesh, "hip": float, "ab": AABB}

func setup(m: Material, f: Node, isl: Node, snd: Callable) -> void:
	mat = m
	fx = f
	island = isl
	sound = snd

## Someone hit: their pose (body mesh key, arms, shoulders), where they stood, the car's velocity and the
## car itself (they don't collide with it for an instant, so the knock doesn't start inside the bonnet).
func spawn(v: int, xf: Transform3D, shoulders: Array, car_vel: Vector3, car: PhysicsBody3D) -> void:
	if dolls.size() >= MAX:
		_clear(dolls[0])
	var body_mesh: Mesh = M.kperson(v, "stand", "")
	var sp := _split_mesh(body_mesh, "%d" % v)
	var root := Node3D.new()
	root.name = "Ragdoll"
	add_child(root)
	var parts := {}
	var ab: AABB = sp["ab"]
	var hip: float = sp["hip"]
	var up_ab := AABB(Vector3(ab.position.x, hip, ab.position.z), Vector3(ab.size.x, ab.end.y - hip, ab.size.z))
	var lo_ab := AABB(ab.position, Vector3(ab.size.x, hip - ab.position.y, ab.size.z))
	parts["upper"] = _part(root, sp["upper"], xf, Transform3D(), up_ab, MASS["upper"], 0.8)
	parts["legs"] = _part(root, sp["legs"], xf, Transform3D(), lo_ab, MASS["legs"], 0.6)
	for i in 2:
		var am: Mesh = M.kperson(v, "stand", "al" if i == 0 else "ar")
		var sh: Vector3 = shoulders[i]
		parts["al" if i == 0 else "ar"] = _part(root, am, xf, Transform3D(Basis(), sh), am.get_aabb(), MASS["arm"], 0.7)
	# the hips: a cone that lets it fold forward and back, and twist a little
	var hj := ConeTwistJoint3D.new()
	root.add_child(hj)
	hj.global_transform = xf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, hip, 0))
	hj.node_a = parts["upper"].get_path()
	hj.node_b = parts["legs"].get_path()
	hj.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(65.0))
	hj.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(25.0))
	for i in 2:
		var sj := PinJoint3D.new()
		root.add_child(sj)
		sj.global_position = xf * (shoulders[i] as Vector3)
		sj.node_a = parts["upper"].get_path()
		sj.node_b = parts["al" if i == 0 else "ar"].get_path()
	# the knock: everything goes the car's way and up, the legs swept from under (so it pitches back over
	# the bonnet), spinning a little either way
	var vh := Vector3(car_vel.x, 0.0, car_vel.z)
	var s := vh.length()
	var dir := vh.normalized() if s > 0.1 else -xf.basis.z
	var lift := clampf(1.4 + s * 0.11, 1.4, 5.5)
	var spin := dir.cross(Vector3.UP).normalized() * clampf(s * 0.32, 2.0, 9.0)
	spin += Vector3.UP * randf_range(-1.0, 1.0) * clampf(s * 0.1, 0.5, 3.0)
	for k in parts:
		var rb: RigidBody3D = parts[k]
		var f := 1.08 if k == "legs" else (0.85 if k == "upper" else 0.95)
		rb.linear_velocity = vh * f + Vector3.UP * lift * (0.8 if k == "legs" else 1.0) + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
		rb.angular_velocity = spin
		if car:
			rb.add_collision_exception_with(car)
	var d := {"root": root, "parts": parts, "t": 0.0, "still": 0.0, "pooled": false, "last_splat": 0.0, "car": car, "landed": 0.0}
	dolls.append(d)

## One piece: a rigid body at the person's place (so the mesh lines up as it stood), its box round `box`
## (in the mesh's own space), placed `local` from the person's origin.
func _part(root: Node3D, mesh: Mesh, xf: Transform3D, local: Transform3D, box: AABB, mass: float, shrink: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.set_meta("ped", true)
	rb.mass = mass
	rb.collision_layer = LAYER
	rb.collision_mask = 1 | 2 | 4 | 16
	rb.linear_damp = 0.05
	rb.angular_damp = 0.6
	rb.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.15
	rb.physics_material_override = pm
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(maxf(box.size.x * shrink, 0.08), maxf(box.size.y * 0.92, 0.08), maxf(box.size.z * shrink, 0.08))
	cs.shape = bx
	cs.position = box.get_center()
	rb.add_child(cs)
	rb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	rb.center_of_mass = box.get_center()
	rb.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	root.add_child(rb)
	rb.global_transform = xf * local
	rb.reset_physics_interpolation()
	return rb

## A character's body cut at the hips into the upper body (with the head) and the legs (each triangle goes
## by where its middle is). Made once per character.
static func _split_mesh(m: Mesh, key: String) -> Dictionary:
	if _split.has(key):
		return _split[key]
	var ab := m.get_aabb()
	var hip := ab.position.y + ab.size.y * HIP_K
	var out := {"hip": hip, "ab": ab}
	var upper := ArrayMesh.new()
	var legs := ArrayMesh.new()
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		var tri_idx := PackedInt32Array()
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			tri_idx = idx
		else:
			tri_idx.resize(vs.size())
			for i in vs.size():
				tri_idx[i] = i
		var iu := PackedInt32Array()
		var il := PackedInt32Array()
		for t in range(0, tri_idx.size() - 2, 3):
			var cy := (vs[tri_idx[t]].y + vs[tri_idx[t + 1]].y + vs[tri_idx[t + 2]].y) / 3.0
			var dst := iu if cy >= hip else il
			dst.append(tri_idx[t])
			dst.append(tri_idx[t + 1])
			dst.append(tri_idx[t + 2])
		for pair in [[upper, iu], [legs, il]]:
			if (pair[1] as PackedInt32Array).is_empty():
				continue
			var a2 := arr.duplicate()
			a2[Mesh.ARRAY_INDEX] = pair[1]
			(pair[0] as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
	out["upper"] = upper
	out["legs"] = legs
	_split[key] = out
	return out

func tick(dt: float, car_pos: Vector3) -> void:
	var done := []
	for d in dolls:
		d["t"] = float(d["t"]) + dt
		var up: RigidBody3D = d["parts"]["upper"]
		if not is_instance_valid(up):
			done.append(d)
			continue
		# (it may touch the car again once it's clear of the bonnet it started in)
		if float(d["t"]) > 0.12 and d.get("car") != null:
			var car = d["car"]
			if is_instance_valid(car):
				for k in d["parts"]:
					(d["parts"][k] as RigidBody3D).remove_collision_exception_with(car)
			d["car"] = null
		var p := up.to_global(up.center_of_mass)
		var gy: float = island.height_at(p.x, p.z)
		var v := up.linear_velocity.length()
		var low := p.y - gy < 0.6
		# coming down on the road: a thud, and a splash of blood
		if low and float(d["landed"]) <= 0.0 and float(d["t"]) > 0.25:
			d["landed"] = 1.0
			if sound.is_valid():
				sound.call("body_land", -6.0)
			fx.blood(p, Vector3(up.linear_velocity.x, 0, up.linear_velocity.z).normalized(), 8, 2.5)
			fx.splat(p, 0.9)
		# sliding along: a smear behind it
		if low and v > 2.5 and float(d["t"]) - float(d["last_splat"]) > 0.11:
			d["last_splat"] = d["t"]
			fx.splat(p, clampf(0.35 + v * 0.04, 0.35, 0.8))
		# come to rest: a pool spreads under it
		if v < 0.35 and up.angular_velocity.length() < 0.5:
			d["still"] = float(d["still"]) + dt
			if float(d["still"]) > 0.8 and not d["pooled"]:
				d["pooled"] = true
				fx.splat(p, 1.6)
				fx.splat(p + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)), 1.1)
		else:
			d["still"] = 0.0
		if float(d["t"]) > STAY or p.distance_to(car_pos) > 170.0 or p.y < -30.0:
			done.append(d)
	for d in done:
		_clear(d)

func _clear(d: Dictionary) -> void:
	var r: Node = d["root"]
	if is_instance_valid(r):
		r.queue_free()
	dolls.erase(d)

func clear_all() -> void:
	for d in dolls.duplicate():
		_clear(d)
