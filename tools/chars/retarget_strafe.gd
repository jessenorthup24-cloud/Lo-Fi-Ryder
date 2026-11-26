extends SceneTree
## The fight shuffle: the locomotion pack's sidestep clips were made on another rig (the low-poly
## "CharacterArmature" one, its legs as IK), so they're carried over by where the feet go, not by bone
## rotations: each frame the source's knee and ankle, relative to its hip and its stride's ground and in
## units of its leg length, are reached for with the target's own legs (two-bone, the knee bending the way
## the source's did), standing on the guard stance's hips. The upper body is the guard (fight_fight_idle).
## Saved into the library as fight_shuffle_<left|right>[_run].
##   godot --headless --path . -s tools/chars/retarget_strafe.gd -- "/tmp/loco/left strafe walking.fbx=fight_shuffle_left" ...

const OUT := "res://assets/chars/bp_anims.res"
const Avatar := preload("res://scripts/game/avatar.gd")
const FPS := 30.0
const LEGS := [["UpperLeg.L", "LowerLeg.L", "LowerLeg.L_end", "LeftUpLeg", "LeftLeg", "LeftFoot"],
	["UpperLeg.R", "LowerLeg.R", "LowerLeg.R_end", "RightUpLeg", "RightLeg", "RightFoot"]]

var jobs: Array = []
var job := -1
var src_root: Node
var src_ap: AnimationPlayer
var src_sk: Skeleton3D
var src_anim: Animation
var src_ground := 0.0
var src_len := 1.0
var av: Node3D
var f := 0
var k := 0
var nframes := 0
var keys := {}                # target bone -> [rotations per frame]
var lib: AnimationLibrary
var waiting := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		jobs.append([a.get_slice("=", 0), a.get_slice("=", 1)])
	lib = load(OUT)
	av = Avatar.new()
	root.add_child(av)
	av.setup("male_casual1", "", null)
	av.legs.active = false
	av.aim.active = false
	av.skel.skeleton_updated.connect(_upd)

func _next_job() -> bool:
	if src_root:
		src_root.queue_free()
		src_root = null
	job += 1
	if job >= jobs.size():
		return false
	var doc := FBXDocument.new()
	var st := FBXState.new()
	doc.append_from_file(String(jobs[job][0]), st)
	src_root = doc.generate_scene(st)
	root.add_child(src_root)
	src_ap = src_root.find_children("*", "AnimationPlayer", true, false)[0]
	src_sk = src_root.find_children("*", "Skeleton3D", true, false)[0]
	src_anim = src_ap.get_animation("mixamo_com")
	src_len = src_anim.length
	src_ap.play("mixamo_com")
	src_ap.pause()
	# its ground: the lowest the ankles get over the stride
	src_ground = INF
	for i in 24:
		_seek_src(src_len * i / 24.0)
		for lg in LEGS:
			src_ground = minf(src_ground, _sg(String(lg[2])).y)
	nframes = int(round(src_len * FPS))
	keys = {}
	k = 0
	return true

func _seek_src(t: float) -> void:
	src_ap.seek(t, true)
	src_sk.force_update_all_bone_transforms()

func _sg(n: String) -> Vector3:
	return src_sk.global_transform * src_sk.get_bone_global_pose(src_sk.find_bone(n)).origin

func _process(_dt: float) -> bool:
	f += 1
	if f < 10:
		return false
	if job < 0 or k >= nframes:
		if job >= 0:
			_save_job()
		if not _next_job():
			ResourceSaver.save(lib, OUT, ResourceSaver.FLAG_COMPRESS)
			print("RETARGET done")
			return true
	if not waiting:
		# the guard stance at this moment, on the target (read back once it's posed)
		var t := float(k) / FPS
		av._act_in("fight_fight_idle", 0.001, fmod(t, 2.0), 0.0)
		av.lock_t = 99.0
		waiting = true
	return false

func _upd() -> void:
	if not waiting or job < 0 or k >= nframes or f < 12:
		return
	waiting = false
	var t := float(k) / FPS
	_seek_src(t)
	var sk: Skeleton3D = av.skel
	for lg in LEGS:
		var su := _sg(String(lg[0]))
		var sknee := _sg(String(lg[1]))
		var sa := _sg(String(lg[2]))
		var sl := su.distance_to(sknee) + sknee.distance_to(sa)
		var ui := sk.find_bone(String(lg[3]))
		var li := sk.find_bone(String(lg[4]))
		var fi := sk.find_bone(String(lg[5]))
		var w := sk.global_transform
		var u := w * sk.get_bone_global_pose(ui).origin
		var kn := w * sk.get_bone_global_pose(li).origin
		var foot0 := sk.get_bone_global_pose(fi)
		var fw := w * foot0.origin
		var l1 := u.distance_to(kn)
		var l2 := kn.distance_to(fw)
		var tl := l1 + l2
		var ground_t := fw.y          # (the guard's ankles stand on its ground)
		var off := (sa - su) / sl * tl
		var ankle := Vector3(u.x + off.x, ground_t + (sa.y - src_ground) / sl * tl, u.z + off.z)
		var to := ankle - u
		var d := clampf(to.length(), absf(l1 - l2) + 0.001, tl * 0.999)
		var dn := to.normalized()
		var pole := (sknee - su) - (sa - su).normalized() * (sknee - su).dot((sa - su).normalized())
		var pn := pole - dn * pole.dot(dn)
		pn = pn.normalized() if pn.length() > 0.0001 else Vector3(0, 0, 1)
		var x := (d * d + l1 * l1 - l2 * l2) / (2.0 * d)
		var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
		var knee := u + dn * x + pn * h
		var wi := w.affine_inverse()
		_point_at(sk, ui, sk.get_bone_global_pose(li).origin, wi * knee)
		_point_at(sk, li, sk.get_bone_global_pose(fi).origin, wi * (u + dn * d))
		_set_global_basis(sk, fi, foot0.basis)
		for bi in [ui, li, fi]:
			var bn := sk.get_bone_name(bi)
			if not keys.has(bn):
				keys[bn] = []
			keys[bn].append(sk.get_bone_pose_rotation(bi))
	k += 1

func _save_job() -> void:
	var name := String(jobs[job][1])
	var base: Animation = lib.get_animation("fight_fight_idle")
	var a := Animation.new()
	a.length = src_len
	a.loop_mode = Animation.LOOP_LINEAR
	for t in base.get_track_count():
		var bone := String(base.track_get_path(t)).get_slice(":", 1)
		if keys.has(bone) and base.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			continue
		var nt := a.add_track(base.track_get_type(t))
		a.track_set_path(nt, base.track_get_path(t))
		a.track_set_interpolation_type(nt, base.track_get_interpolation_type(t))
		var first = null
		for kk in base.track_get_key_count(t):
			var kt := base.track_get_key_time(t, kk)
			if kt >= src_len:
				break
			if first == null:
				first = base.track_get_key_value(t, kk)
			a.track_insert_key(nt, kt, base.track_get_key_value(t, kk))
		if first != null:
			a.track_insert_key(nt, src_len, first)
	for bone in keys:
		var nt := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(nt, NodePath("Skeleton3D:" + String(bone)))
		var arr: Array = keys[bone]
		for i in arr.size():
			a.rotation_track_insert_key(nt, float(i) / FPS, arr[i])
		a.rotation_track_insert_key(nt, src_len, arr[0])
	if lib.has_animation(name):
		lib.remove_animation(name)
	lib.add_animation(name, a)
	print("RETARGET %s: %d frames, %.2fs" % [name, nframes, src_len])

func _point_at(sk: Skeleton3D, bi: int, cur_tip: Vector3, want: Vector3) -> void:
	var o := sk.get_bone_global_pose(bi).origin
	var cur := (cur_tip - o).normalized()
	var wnt := (want - o).normalized()
	if cur.dot(wnt) > 0.999999:
		return
	var gp := sk.get_bone_global_pose(bi)
	_set_global_basis(sk, bi, Basis(Quaternion(cur, wnt)) * gp.basis)

func _set_global_basis(sk: Skeleton3D, bi: int, b: Basis) -> void:
	var parent := sk.get_bone_parent(bi)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	sk.set_bone_pose_rotation(bi, (pg.basis.orthonormalized().inverse() * b.orthonormalized()).get_rotation_quaternion())
