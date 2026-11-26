extends SkeletonModifier3D
## The Quaternius rig's feet hang off the root (made for IK), and the Mixamo clips retargeted onto it carry no
## foot tracks at all: left alone the feet stay where they were and the shins stretch to them. So every frame
## each foot is put back on the end of its shin, turned with it as it was at rest. (Added last: after the
## aim and the ragdoll have moved the legs.)

var _sides: Array = []      # [foot bone, shin-end bone, the foot from the shin end at rest]

func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for s in ["L", "R"]:
		var f := sk.find_bone("Foot." + s)
		var e := sk.find_bone("LowerLeg.%s_end" % s)
		if f < 0 or e < 0:
			continue
		var rel := _rest_global(sk, e).affine_inverse() * _rest_global(sk, f)
		_sides.append([f, e, rel])

static func _rest_global(sk: Skeleton3D, b: int) -> Transform3D:
	var t := sk.get_bone_rest(b)
	var p := sk.get_bone_parent(b)
	while p >= 0:
		t = sk.get_bone_rest(p) * t
		p = sk.get_bone_parent(p)
	return t

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for s in _sides:
		var g := sk.get_bone_global_pose(int(s[1])) * (s[2] as Transform3D)
		sk.set_bone_global_pose(int(s[0]), Transform3D(g.basis.orthonormalized(), g.origin))
