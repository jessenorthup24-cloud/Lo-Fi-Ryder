extends SkeletonModifier3D
## A rigged character gone limp: a rigid body for each part (torso, head, arms, legs) joined at the hips,
## shoulders and neck, thrown by whatever killed them; every frame the skeleton's bones are put where the
## bodies are, so the character's own skinned mesh falls and tumbles. (The bodies live outside the character,
## unscaled, in the world: physics doesn't take kindly to the characters' 2.3x scale.)
## Used for you and the officers (the people about the island have their own ragdolls: ragdoll.gd).

const LAYER := 32
# part: [bone, middle of the part from its bone (rig units), size (rig units), mass]
const PARTS := {
	"torso": ["torso", Vector3(0, 0.085, 0), Vector3(0.22, 0.17, 0.16), 30.0],
	"head": ["head", Vector3(0, 0.16, 0), Vector3(0.42, 0.31, 0.32), 8.0],
	"arm-left": ["arm-left", Vector3(0.14, -0.01, 0), Vector3(0.28, 0.075, 0.075), 4.0],
	"arm-right": ["arm-right", Vector3(-0.14, -0.01, 0), Vector3(0.28, 0.075, 0.075), 4.0],
	"leg-left": ["leg-left", Vector3(0, -0.088, 0), Vector3(0.085, 0.176, 0.1), 10.0],
	"leg-right": ["leg-right", Vector3(0, -0.088, 0), Vector3(0.085, 0.176, 0.1), 10.0],
}

var bodies := {}               # bone index -> RigidBody3D
var offs := {}                 # bone index -> the bone's world pose, from its body's
var root_i := -1
var torso_i := -1
var root_rel := Transform3D()  # the root bone, from the torso (skeleton space)
var holder: Node3D

## Go limp: bodies made in `world` (an unscaled node), all moving at `vel`, with `push` on the torso.
func start(sk: Skeleton3D, world: Node3D, vel: Vector3, push: Vector3) -> void:
	holder = Node3D.new()
	holder.name = "LimpBody"
	world.add_child(holder)
	var sg := sk.global_transform
	var sc := sg.basis.get_scale().x
	root_i = sk.find_bone("root")
	torso_i = sk.find_bone("torso")
	if root_i >= 0 and torso_i >= 0:
		root_rel = sk.get_bone_global_pose(torso_i).affine_inverse() * sk.get_bone_global_pose(root_i)
	var list: Array = []
	for k in PARTS:
		var p: Array = PARTS[k]
		var bi := sk.find_bone(String(p[0]))
		if bi < 0:
			continue
		var bw: Transform3D = sg * sk.get_bone_global_pose(bi)        # the bone in the world (scaled)
		var b0 := Transform3D(bw.basis.orthonormalized(), bw * (p[1] as Vector3))
		var rb := RigidBody3D.new()
		rb.collision_layer = LAYER
		rb.collision_mask = 1 | 2
		rb.mass = p[3]
		rb.linear_damp = 0.15
		rb.angular_damp = 1.2
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = (p[2] as Vector3) * sc
		cs.shape = bx
		rb.add_child(cs)
		holder.add_child(rb)
		rb.global_transform = b0
		rb.linear_velocity = vel + Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.8), randf_range(-0.6, 0.6))
		bodies[bi] = rb
		offs[bi] = b0.affine_inverse() * bw
		list.append(rb)
	for a in list:
		for b in list:
			if a != b:
				(a as RigidBody3D).add_collision_exception_with(b)
	# the joints: hips, shoulders and neck, all onto the torso
	var torso: RigidBody3D = bodies.get(torso_i)
	if torso == null:
		return
	torso.apply_central_impulse(push * torso.mass)
	torso.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 6.0)
	for bi in bodies:
		if bi == torso_i:
			continue
		var at: Vector3 = (sg * sk.get_bone_global_pose(bi)).origin
		var nm := sk.get_bone_name(bi)
		var j: Joint3D
		if nm.begins_with("leg") or nm == "head":
			var cj := ConeTwistJoint3D.new()
			cj.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(35.0 if nm == "head" else 75.0))
			cj.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(20.0))
			j = cj
			holder.add_child(j)
			# (the twist axis, the joint's X, along the limb: down a leg, up the neck)
			j.global_transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5 if nm == "head" else -PI * 0.5), at)
		else:
			j = PinJoint3D.new()
			holder.add_child(j)
			j.global_transform = Transform3D(Basis(), at)
		j.node_a = torso.get_path()
		j.node_b = (bodies[bi] as Node).get_path()
	# (the skinned meshes wander far from where the character stood: don't let them be culled)
	for mi in sk.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).extra_cull_margin = 16.0

func torso_pos() -> Vector3:
	var t: RigidBody3D = bodies.get(torso_i)
	return t.global_position if t != null and is_instance_valid(t) else Vector3.INF

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or bodies.is_empty():
		return
	var inv := sk.global_transform.affine_inverse()
	var torso: RigidBody3D = bodies.get(torso_i)
	if torso == null or not is_instance_valid(torso):
		return
	var tp := inv * torso.global_transform * (offs[torso_i] as Transform3D)
	tp.basis = tp.basis.orthonormalized()
	if root_i >= 0:
		var rp := tp * root_rel
		rp.basis = rp.basis.orthonormalized()
		sk.set_bone_global_pose(root_i, rp)
	sk.set_bone_global_pose(torso_i, tp)
	for bi in bodies:
		if bi == torso_i:
			continue
		var rb: RigidBody3D = bodies[bi]
		if not is_instance_valid(rb):
			continue
		var p := inv * rb.global_transform * (offs[bi] as Transform3D)
		p.basis = p.basis.orthonormalized()
		sk.set_bone_global_pose(bi, p)

func _exit_tree() -> void:
	if holder and is_instance_valid(holder):
		holder.queue_free()
