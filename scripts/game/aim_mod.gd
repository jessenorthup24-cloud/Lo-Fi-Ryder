extends SkeletonModifier3D
## Points a character's gun at what they're shooting at, on top of whatever animation is playing (the
## Quaternius rig). The upper body turns toward the target and both arms come up, each a two-bone reach (the
## elbow bending out and down): the right fist to a grip point out in front of the chest on the line to the
## target, the left to the gun's fore-end along the same line. A long gun's shouldered: the right fist out
## from the right shoulder, the body side-on (the holder turns it). The gun itself is turned to face the
## target by the avatar holding it. Also: a flinch (the upper body knocked back for a moment by a hit).
## Everything here's in the skeleton's own space (its units, whatever the rig's scale).

var target := Vector3.INF      # world position to aim at (INF: not aiming)
var target_local := Vector3.INF  # or a point in the skeleton's own space (follows the body round: the garage)
var weight := 0.0              # eased in and out by the avatar
var fore := 0.0                # how far along the gun the left hand goes (skeleton units; 0: both on the grip)
var shoulder := false
var facing := Vector3.INF      # where the character faces (world; the avatar sets it)
var hands_up := 0.0            # 0..1: both hands up by the head (busted)
var flinch := 0.0              # 0..1, a hit knocking the upper body back
var flinch_axis := Vector3.RIGHT

var _b := {}                   # bone name -> index
var _up_len := 0.0             # upper arm, forearm (to the middle of the fist)
var _lo_len := 0.0

func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	# (our names for the parts, the Mixamo skeleton's bones)
	var names := {"Torso": "Spine2", "Head": "Head", "Neck": "Neck", "UpperArm.R": "RightArm", "LowerArm.R": "RightForeArm",
		"Fist.R": "RightHand", "Fist.R_end": "RightHandMiddle1", "UpperArm.L": "LeftArm", "LowerArm.L": "LeftForeArm",
		"Fist.L": "LeftHand", "Fist.L_end": "LeftHandMiddle1"}
	for n in names:
		_b[n] = sk.find_bone(names[n])
	if int(_b["LowerArm.R"]) >= 0:
		_up_len = sk.get_bone_rest(int(_b["LowerArm.R"])).origin.length()
		_lo_len = sk.get_bone_rest(int(_b["Fist.R"])).origin.length() + sk.get_bone_rest(int(_b["Fist.R_end"])).origin.length() * 0.55

func aim_point_local(sk: Skeleton3D) -> Vector3:
	if target_local != Vector3.INF:
		return target_local
	if target != Vector3.INF:
		return sk.global_transform.affine_inverse() * target
	return Vector3.INF

## The skeleton's up (the rig's Y may not be the world's): the world up in skeleton space.
func _up(sk: Skeleton3D) -> Vector3:
	return (sk.global_transform.basis.inverse() * Vector3.UP).normalized()

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _b.is_empty():
		return
	var t := aim_point_local(sk)
	if hands_up > 0.001:
		_hands_up(sk)
	elif weight > 0.001 and t != Vector3.INF:
		_aim(sk, t)
	if flinch > 0.001:
		var ax := (sk.global_transform.basis.inverse() * flinch_axis).normalized()
		for n in [["Torso", 0.7], ["Head", 0.5]]:
			var bi := int(_b[n[0]])
			if bi >= 0:
				_turn_global(sk, bi, Quaternion(ax, flinch * float(n[1])), 1.0)

func _aim(sk: Skeleton3D, t: Vector3) -> void:
	var up := _up(sk)
	# the torso turns (about the vertical only) toward it, up to a point
	var ti := int(_b["Torso"])
	if ti >= 0:
		var tg := sk.get_bone_global_pose(ti)
		var to := t - tg.origin
		to -= up * to.dot(up)
		# (forward: square to the line through the shoulders; a long gun's clips are side-on already, the gun
		# ahead of where the character faces: so for those, where it faces)
		var rgt := sk.get_bone_global_pose(int(_b["UpperArm.R"])).origin - sk.get_bone_global_pose(int(_b["UpperArm.L"])).origin
		var fwd := up.cross(rgt)
		if shoulder and facing != Vector3.INF:
			fwd = sk.global_transform.basis.inverse() * facing
		fwd -= up * fwd.dot(up)
		if to.length() > 0.0001 and fwd.length() > 0.0001:
			var ang := clampf(fwd.signed_angle_to(to, up), -1.0, 1.0) * (0.9 if shoulder else 0.75)
			_turn_global(sk, ti, Quaternion(up, ang), weight)
	var rs := sk.get_bone_global_pose(int(_b["UpperArm.R"])).origin
	var ls := sk.get_bone_global_pose(int(_b["UpperArm.L"])).origin
	var reach := (_up_len + _lo_len) * 0.92
	var grip: Vector3
	var dir: Vector3
	if shoulder:
		dir = (t - rs).normalized()
		grip = rs + dir * reach * 0.45
	else:
		var mid := (rs + ls) * 0.5
		dir = (t - mid).normalized()
		var half := rs.distance_to(ls) * 0.5
		grip = mid + dir * sqrt(maxf(reach * reach - half * half, reach * reach * 0.2))
	var side := dir.cross(up).normalized()          # (to the right, along the aim)
	if shoulder and int(_b["Head"]) >= 0:
		# (the clips stand side-on, the right shoulder behind the head: the line from it to the target would go
		# through the face. Out to the right cheek instead, the stock in the shoulder's pocket, the head beside it)
		var hd := sk.get_bone_global_pose(int(_b["Head"])).origin
		var lat := (rs - hd).dot(side)
		var want := _up_len * 0.36
		if lat < want:
			grip += side * (want - lat)
	_reach(sk, "R", grip, -up + side * 0.6)
	_reach(sk, "L", grip + dir * maxf(fore, 0.0), -up - side * 0.6)

## Hands up: each fist up beside the head, elbows out.
func _hands_up(sk: Skeleton3D) -> void:
	var up := _up(sk)
	var rs := sk.get_bone_global_pose(int(_b["UpperArm.R"])).origin
	var ls := sk.get_bone_global_pose(int(_b["UpperArm.L"])).origin
	var out := (rs - ls).normalized()
	var reach := (_up_len + _lo_len)
	var w0 := weight
	weight = hands_up
	_reach(sk, "R", rs + up * reach * 0.75 + out * reach * 0.25, out - up * 0.2)
	_reach(sk, "L", ls + up * reach * 0.75 - out * reach * 0.25, -out - up * 0.2)
	weight = w0

## A two-bone reach: the upper arm and forearm bent so the fist's middle lands on goal, the elbow toward pole.
func _reach(sk: Skeleton3D, s: String, goal: Vector3, pole: Vector3) -> void:
	var ui := int(_b["UpperArm." + s])
	var li := int(_b["LowerArm." + s])
	var fi := int(_b["Fist." + s])
	var fe := int(_b["Fist.%s_end" % s])
	if ui < 0 or li < 0 or fi < 0:
		return
	var a := sk.get_bone_global_pose(ui).origin
	var to := goal - a
	var d := clampf(to.length(), absf(_up_len - _lo_len) + 0.0001, (_up_len + _lo_len) * 0.999)
	var dn := to.normalized()
	# the elbow: on the circle where the two lengths meet, toward the pole
	var x := (d * d + _up_len * _up_len - _lo_len * _lo_len) / (2.0 * d)
	var h := sqrt(maxf(_up_len * _up_len - x * x, 0.0))
	var pn := (pole - dn * pole.dot(dn)).normalized()
	var elbow := a + dn * x + pn * h
	_point_child(sk, ui, li, elbow)
	var hand_mid := (sk.get_bone_global_pose(fi).origin + sk.get_bone_global_pose(fe).origin) * 0.5 if fe >= 0 else sk.get_bone_global_pose(fi).origin
	_point_at(sk, li, hand_mid, a + dn * d)

## Turn bone bi so its child's origin heads for `want` (skeleton space).
func _point_child(sk: Skeleton3D, bi: int, child: int, want: Vector3) -> void:
	_point_at(sk, bi, sk.get_bone_global_pose(child).origin, want)

func _point_at(sk: Skeleton3D, bi: int, cur_tip: Vector3, want: Vector3) -> void:
	var o := sk.get_bone_global_pose(bi).origin
	var cur := (cur_tip - o).normalized()
	var wnt := (want - o).normalized()
	if cur.length() < 0.5 or wnt.length() < 0.5 or cur.dot(wnt) > 0.99999:
		return
	_turn_global(sk, bi, Quaternion(cur, wnt), weight)

## Turn a bone by q (a rotation in skeleton space), blended in by w, keeping the rest of its pose.
func _turn_global(sk: Skeleton3D, bi: int, q: Quaternion, w: float) -> void:
	var gp := sk.get_bone_global_pose(bi)
	var new_global := Basis(q) * gp.basis
	var parent := sk.get_bone_parent(bi)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var local := (pg.basis.orthonormalized().inverse() * new_global.orthonormalized()).get_rotation_quaternion()
	var q0 := sk.get_bone_pose_rotation(bi)
	sk.set_bone_pose_rotation(bi, q0.slerp(local, w))
