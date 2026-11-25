extends SkeletonModifier3D
## Points a character's gun at what they're shooting at, on top of whatever animation is playing. The upper
## body turns toward the target, and both arms come up to meet at a grip point out in front of the chest, on
## the line to the target (a two-handed hold: the Kenney rig has no elbows, so the fists meet where two
## straight arms can reach). The gun itself is turned to face the target by whoever holds it (gunplay).
## (The Kenney rig's arms run along their bones' X axis: the right arm down -X, the left down +X.)

const ARM := 0.29              # shoulder to the middle of the fist, in the rig's units

var target := Vector3.INF      # world position to aim at (INF: not aiming)
var both := true               # both hands on the gun (false: just the right arm points)
var weight := 0.0              # eased in and out by the avatar
var grip := Vector3.INF        # (out) where the hands met, in world space, last update

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or weight <= 0.001 or target == Vector3.INF:
		grip = Vector3.INF
		return
	var inv := sk.global_transform.affine_inverse()
	var t := inv * target                       # the target, in the skeleton's own space
	# the torso turns (about the vertical only) toward it, up to a point
	var ti := sk.find_bone("torso")
	if ti >= 0:
		var tg := sk.get_bone_global_pose(ti)
		var to := t - tg.origin
		var yaw := clampf(atan2(to.x, to.z), -1.0, 1.0)
		var q0 := sk.get_bone_pose_rotation(ti)
		sk.set_bone_pose_rotation(ti, q0.slerp(Quaternion(Vector3.UP, yaw) * q0, weight * 0.75))
	var ri := sk.find_bone("arm-right")
	var li := sk.find_bone("arm-left")
	if ri < 0:
		return
	var rs := sk.get_bone_global_pose(ri).origin
	if not both or li < 0:
		_point(sk, ri, Vector3(-1, 0, 0), t)
		grip = sk.global_transform * (rs + (t - rs).normalized() * ARM)
		return
	var ls := sk.get_bone_global_pose(li).origin
	var mid := (rs + ls) * 0.5
	var half := rs.distance_to(ls) * 0.5
	var dir := (t - mid).normalized()
	# the point both fists can reach: out along the aim line from between the shoulders
	var reach := sqrt(maxf(ARM * ARM - half * half, 0.0)) if ARM > half else 0.05
	var p := mid + dir * reach
	_point(sk, ri, Vector3(-1, 0, 0), p)
	_point(sk, li, Vector3(1, 0, 0), p)
	grip = sk.global_transform * p

## Turn a bone so its local `axis` points at t (skeleton space), keeping its animated pose otherwise.
func _point(sk: Skeleton3D, bi: int, axis: Vector3, t: Vector3) -> void:
	var gp := sk.get_bone_global_pose(bi)
	var cur := (gp.basis * axis).normalized()
	var want := (t - gp.origin).normalized()
	if cur.dot(want) > 0.9999:
		return
	var turn := Quaternion(cur, want)
	var new_global := Basis(turn) * gp.basis
	var parent := sk.get_bone_parent(bi)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var local := (pg.basis.inverse() * new_global).get_rotation_quaternion()
	var q0 := sk.get_bone_pose_rotation(bi)
	sk.set_bone_pose_rotation(bi, q0.slerp(local, weight))
