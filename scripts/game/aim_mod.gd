extends SkeletonModifier3D
## Points a character's gun at what they're shooting at, on top of whatever animation is playing. The upper
## body turns toward the target and both arms come up: the right fist to a grip point out in front of the
## chest on the line to the target, the left reaching to the gun's fore-end along the same line (the Kenney
## rig has no elbows, so the fists go where two straight arms can reach). The gun itself is turned to face
## the target by the avatar holding it. Also: a flinch (the upper body knocked back for a moment by a hit).
## (The Kenney rig's arms run along their bones' X axis: the right arm down -X, the left down +X.)

const ARM := 0.28              # shoulder to the middle of the fist, in the rig's units

var target := Vector3.INF      # world position to aim at (INF: not aiming)
var target_local := Vector3.INF  # or a point in the skeleton's own space (follows the body round: the garage)
var weight := 0.0              # eased in and out by the avatar
var fore := 0.0                # how far along the gun the left hand goes (rig units; 0: both on the grip)
var flinch := 0.0              # 0..1, a hit knocking the upper body back
var flinch_axis := Vector3.RIGHT

func aim_point_local(sk: Skeleton3D) -> Vector3:
	if target_local != Vector3.INF:
		return target_local
	if target != Vector3.INF:
		return sk.global_transform.affine_inverse() * target
	return Vector3.INF

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var t := aim_point_local(sk)
	if weight > 0.001 and t != Vector3.INF:
		_aim(sk, t)
	if flinch > 0.001:
		var ti := sk.find_bone("torso")
		if ti >= 0:
			var q0 := sk.get_bone_pose_rotation(ti)
			sk.set_bone_pose_rotation(ti, Quaternion(flinch_axis, flinch * 0.45) * q0)

func _aim(sk: Skeleton3D, t: Vector3) -> void:
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
	if ri < 0 or li < 0:
		return
	var rs := sk.get_bone_global_pose(ri).origin
	var ls := sk.get_bone_global_pose(li).origin
	var mid := (rs + ls) * 0.5
	var half := rs.distance_to(ls) * 0.5
	var dir := (t - mid).normalized()
	# the grip: out along the aim line from between the shoulders, where the right fist can reach
	var reach := sqrt(maxf(ARM * ARM - half * half, 0.0)) if ARM > half else 0.05
	var g := mid + dir * reach
	_point(sk, ri, Vector3(-1, 0, 0), g)
	_point(sk, li, Vector3(1, 0, 0), g + dir * fore)

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
