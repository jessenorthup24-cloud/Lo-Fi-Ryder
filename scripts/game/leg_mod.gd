extends SkeletonModifier3D
## Standing tall: the clips were made on a rig with longer legs, so on these characters they stand and walk
## knees bent, sunk a few centimetres, a little hunched. This lifts the hips (as far as the legs allow, never
## past a slight bend) and bends each leg back down with a two-bone reach so the feet stay exactly where the
## clip put them, flat as they were. Off when crouched, ragdolled or playing a one-off move.

var on := 1.0                 # eased by the avatar (1: standing/walking, 0: crouched, a move, seated)
const BEND := 13.0            # degrees: the least the knee's left bent
const LIFT_MAX := 0.075       # of the leg's length (about 6 cm)
const LEAN_BACK := 0.07       # radians: the spine eased back up out of the slouch

var _b := {}
var _lift := 0.0

func _ready() -> void:
	var sk := get_skeleton()
	for n in ["Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot", "Spine1", "Spine2"]:
		_b[n] = sk.find_bone(n)

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or on <= 0.01 or int(_b.get("Hips", -1)) < 0:
		return
	var hi: int = _b["Hips"]
	var up := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	var legs := []
	for s in ["Left", "Right"]:
		var ui: int = _b[s + "UpLeg"]
		var li: int = _b[s + "Leg"]
		var fi: int = _b[s + "Foot"]
		if ui < 0 or li < 0 or fi < 0:
			return
		var u := sk.get_bone_global_pose(ui).origin
		var k := sk.get_bone_global_pose(li).origin
		var f := sk.get_bone_global_pose(fi)
		legs.append([ui, li, fi, u, k, f, (k - u).length(), (f.origin - k).length()])
	# how far the hips can come up: the most-stretched leg mustn't go past BEND
	var lift := INF
	for lg in legs:
		var l1: float = lg[6]
		var l2: float = lg[7]
		var d_t := sqrt(l1 * l1 + l2 * l2 + 2.0 * l1 * l2 * cos(deg_to_rad(BEND)))
		var dv: Vector3 = (lg[5] as Transform3D).origin - (lg[3] as Vector3)
		var b := dv.dot(up)
		var disc := b * b - dv.length_squared() + d_t * d_t
		var h := b + sqrt(disc) if disc > 0.0 else 0.0
		lift = minf(lift, h)
	lift = clampf(lift, 0.0, LIFT_MAX * (float(legs[0][6]) + float(legs[0][7]))) * on
	# (down at once, so a foot's never pulled off the ground; up gently, so it doesn't add a bob to the walk)
	_lift = lift if lift < _lift else lerpf(_lift, lift, 0.12)
	lift = _lift
	if lift < 0.0005:
		return
	# the hips up
	var hg := sk.get_bone_global_pose(hi)
	var hp := sk.get_bone_parent(hi)
	var new_o := hg.origin + up * lift
	var local_o := new_o if hp < 0 else sk.get_bone_global_pose(hp).affine_inverse() * new_o
	sk.set_bone_pose_position(hi, local_o)
	# each leg back down to its foot, the knee bending the way it was, the foot as it was
	for lg in legs:
		var ui: int = lg[0]
		var li: int = lg[1]
		var fi: int = lg[2]
		var foot0: Transform3D = lg[5]
		var u := sk.get_bone_global_pose(ui).origin
		var l1: float = lg[6]
		var l2: float = lg[7]
		var to := foot0.origin - u
		var d := clampf(to.length(), absf(l1 - l2) + 0.0001, (l1 + l2) * 0.9995)
		var dn := to.normalized()
		var pole: Vector3 = (lg[4] as Vector3) - (lg[3] as Vector3)        # (the knee's old way)
		var pn := (pole - dn * pole.dot(dn))
		if pn.length() < 0.0001:
			continue
		pn = pn.normalized()
		var x := (d * d + l1 * l1 - l2 * l2) / (2.0 * d)
		var hh := sqrt(maxf(l1 * l1 - x * x, 0.0))
		var knee := u + dn * x + pn * hh
		_point_at(sk, ui, sk.get_bone_global_pose(li).origin, knee)
		_point_at(sk, li, sk.get_bone_global_pose(fi).origin, foot0.origin)
		_set_global_basis(sk, fi, foot0.basis)
	# and the back eased up a touch out of the slouch
	for n in ["Spine1", "Spine2"]:
		var si: int = _b[n]
		if si < 0:
			continue
		var g := sk.get_bone_global_pose(si)
		var side := g.basis.x.normalized()
		var q := Quaternion(side, -LEAN_BACK * 0.5 * on)
		_turn_global(sk, si, q)

func _point_at(sk: Skeleton3D, bi: int, cur_tip: Vector3, want: Vector3) -> void:
	var o := sk.get_bone_global_pose(bi).origin
	var cur := (cur_tip - o).normalized()
	var wnt := (want - o).normalized()
	if cur.length() < 0.5 or wnt.length() < 0.5 or cur.dot(wnt) > 0.999999:
		return
	_turn_global(sk, bi, Quaternion(cur, wnt))

func _turn_global(sk: Skeleton3D, bi: int, q: Quaternion) -> void:
	var gp := sk.get_bone_global_pose(bi)
	_set_global_basis(sk, bi, Basis(q) * gp.basis)

func _set_global_basis(sk: Skeleton3D, bi: int, b: Basis) -> void:
	var parent := sk.get_bone_parent(bi)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	sk.set_bone_pose_rotation(bi, (pg.basis.orthonormalized().inverse() * b.orthonormalized()).get_rotation_quaternion())
