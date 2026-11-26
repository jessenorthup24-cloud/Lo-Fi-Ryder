extends SkeletonModifier3D
## A rigged character gone limp (the Quaternius rig): a rigid body for each part (the trunk, the head, upper
## and lower arms and legs), each joined to the one above it, thrown by whatever killed them; every frame the
## skeleton's bones are put where the bodies are, so the character's own skinned mesh falls and tumbles.
## Each part's box runs from its bone to the next one down the limb, sized from the rig itself. (The bodies
## live outside the character, unscaled, in the world: physics doesn't take kindly to scaled bodies.)
## Used for you and the officers (the people about the island have their own ragdolls: ragdoll.gd).

const LAYER := 32
# part: [bone, the bone its box reaches to, thickness (of its length), mass, joint ("cone"/"pin"), parent part bone]
const PARTS := [
	["Hips", "Neck", 0.55, 30.0, "", ""],
	["Head", "Head_end", 0.85, 6.0, "cone", "Hips"],
	["UpperArm.L", "LowerArm.L", 0.32, 2.5, "pin", "Hips"],
	["UpperArm.R", "LowerArm.R", 0.32, 2.5, "pin", "Hips"],
	["LowerArm.L", "Fist.L_end", 0.26, 2.0, "pin", "UpperArm.L"],
	["LowerArm.R", "Fist.R_end", 0.26, 2.0, "pin", "UpperArm.R"],
	["UpperLeg.L", "LowerLeg.L", 0.3, 7.0, "cone", "Hips"],
	["UpperLeg.R", "LowerLeg.R", 0.3, 7.0, "cone", "Hips"],
	["LowerLeg.L", "LowerLeg.L_end", 0.26, 5.0, "pin", "UpperLeg.L"],
	["LowerLeg.R", "LowerLeg.R_end", 0.26, 5.0, "pin", "UpperLeg.R"],
]

var bodies := {}               # bone index -> RigidBody3D
var offs := {}                 # bone index -> the bone's world pose, from its body's
var root_i := -1
var torso_i := -1
var root_rel := Transform3D()  # the root bone, from the trunk (skeleton space)
var holder: Node3D

## Go limp: bodies made in `world` (an unscaled node), all moving at `vel`, with `push` on the trunk.
func start(sk: Skeleton3D, world: Node3D, vel: Vector3, push: Vector3) -> void:
	holder = Node3D.new()
	holder.name = "LimpBody"
	world.add_child(holder)
	var sg := sk.global_transform
	root_i = sk.find_bone("Body")
	torso_i = sk.find_bone("Hips")
	if root_i >= 0 and torso_i >= 0:
		root_rel = sk.get_bone_global_pose(torso_i).affine_inverse() * sk.get_bone_global_pose(root_i)
	var by_name := {}
	var list: Array = []
	for p in PARTS:
		var bi := sk.find_bone(String(p[0]))
		var ti := sk.find_bone(String(p[1]))
		if bi < 0 or ti < 0:
			continue
		var bw: Transform3D = sg * sk.get_bone_global_pose(bi)        # the bone in the world (scaled)
		var a := bw.origin
		var b := (sg * sk.get_bone_global_pose(ti)).origin
		var seg := b - a
		var ln := maxf(seg.length(), 0.05)
		# the box: its Y down the part, centred halfway along
		var yv := seg.normalized() if seg.length() > 0.001 else Vector3.UP
		var xv := yv.cross(Vector3.FORWARD if absf(yv.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var zv := xv.cross(yv).normalized()
		var b0 := Transform3D(Basis(xv, yv, zv), (a + b) * 0.5)
		var rb := RigidBody3D.new()
		rb.collision_layer = LAYER
		rb.collision_mask = 1 | 2
		rb.mass = p[3]
		rb.linear_damp = 0.15
		rb.angular_damp = 1.2
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		var th: float = ln * float(p[2])
		bx.size = Vector3(th, ln, th * (0.7 if String(p[0]) == "Hips" else 1.0))
		cs.shape = bx
		rb.add_child(cs)
		holder.add_child(rb)
		rb.global_transform = b0
		rb.linear_velocity = vel + Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.8), randf_range(-0.6, 0.6))
		bodies[bi] = rb
		offs[bi] = b0.affine_inverse() * Transform3D(bw.basis.orthonormalized(), bw.origin)
		by_name[String(p[0])] = [rb, a]
		list.append(rb)
	for x in list:
		for y in list:
			if x != y:
				(x as RigidBody3D).add_collision_exception_with(y)
	var torso: RigidBody3D = bodies.get(torso_i)
	if torso == null:
		return
	torso.apply_central_impulse(push * torso.mass)
	torso.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 6.0)
	# the joints: each part onto the one above it, at its own bone
	for p in PARTS:
		if String(p[5]) == "" or not by_name.has(p[0]) or not by_name.has(p[5]):
			continue
		var me: RigidBody3D = by_name[p[0]][0]
		var at: Vector3 = by_name[p[0]][1]
		var up: RigidBody3D = by_name[p[5]][0]
		var j: Joint3D
		if String(p[4]) == "cone":
			var cj := ConeTwistJoint3D.new()
			cj.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(35.0 if String(p[0]) == "Head" else 75.0))
			cj.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(20.0))
			j = cj
			holder.add_child(j)
			# (the twist axis, the joint's X, along the part)
			var yv2: Vector3 = (me.global_transform.basis.y).normalized()
			var xv2 := yv2
			var zv2 := xv2.cross(Vector3.UP if absf(xv2.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
			j.global_transform = Transform3D(Basis(xv2, zv2.cross(xv2), zv2), at)
		else:
			j = PinJoint3D.new()
			holder.add_child(j)
			j.global_transform = Transform3D(Basis(), at)
		j.node_a = up.get_path()
		j.node_b = me.get_path()
	# (the skinned meshes wander far from where the character stood: don't let them be culled)
	for mi in sk.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).extra_cull_margin = 16.0
	for mi in sk.get_parent().find_children("*", "MeshInstance3D", true, false):
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
	# (down the tree, so each part's set after the one it hangs from)
	for p in PARTS:
		var bi := sk.find_bone(String(p[0]))
		var rb: RigidBody3D = bodies.get(bi)
		if rb == null or not is_instance_valid(rb):
			continue
		var g := inv * rb.global_transform * (offs[bi] as Transform3D)
		g.basis = g.basis.orthonormalized()
		sk.set_bone_global_pose(bi, g)

func _exit_tree() -> void:
	if holder and is_instance_valid(holder):
		holder.queue_free()
