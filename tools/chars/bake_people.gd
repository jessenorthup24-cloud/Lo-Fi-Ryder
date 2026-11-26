extends SceneTree
## The people about the island, from the Quaternius character: for each outfit (avatar.gd CHARS) and pose
## (standing: the idle clip; sitting: the Sitting Idle clip) a still body and its two arms, split off at the
## shoulders so they can swing and wave (people.gd puts them in pools). The skinning's done here, once:
## the meshes are plain (no rig), in metres, feet on y = 0, facing +Z, painted, and thinned a little.
##   godot --headless --path . -s tools/chars/bake_people.gd
## -> assets/chars/qp_<outfit index>_<pose>[_al|_ar].res and assets/chars/qp_meta.json (the shoulders)

const Avatar := preload("res://scripts/game/avatar.gd")
const M := preload("res://scripts/core/models.gd")
const OUT := "res://assets/chars/"
const POSES := {"stand": ["act_idle", 0.0], "sit": ["x_sitting", 0.5]}
const KEEP := 0.45

var meta := {}

var _done := false

## (baked on the first frame, not in _init: before the tree's running, the animation players don't pose anything)
func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	_bake_all()
	return true

func _bake_all() -> void:
	for v in M.CHARS.size():
		for pose in POSES:
			_bake(v, pose)
	var f := FileAccess.open(OUT + "qp_meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	print("PEOPLE baked ", meta.size())
	quit()

func _bake(v: int, pose: String) -> void:
	var av = Avatar.new()
	root.add_child(av)
	av.setup(String(M.CHARS[v]), "", null)
	var sk: Skeleton3D = av.skel
	var ap: AnimationPlayer = av.anim
	ap.play(String(POSES[pose][0]))
	ap.seek(float(POSES[pose][1]), true)
	sk.force_update_all_bone_transforms()      # (headless, the bones' world poses don't follow the clip by themselves)
	var to_me: Transform3D = av._skel_xf()
	var mi: MeshInstance3D = av.model.find_children("*", "MeshInstance3D", true, false)[0]
	var skin: Skin = mi.skin
	var bind_xf := []
	var bind_bone := []
	for i in skin.get_bind_count():
		var bi := skin.get_bind_bone(i)
		if String(skin.get_bind_name(i)) != "":
			bi = sk.find_bone(skin.get_bind_name(i))
		bind_bone.append(sk.get_bone_name(bi))
		bind_xf.append(to_me * sk.get_bone_global_pose(bi) * skin.get_bind_pose(i))
	var parts := {"": [], "al": [], "ar": []}       # [verts, norms, cols] per triangle corner
	for k in parts:
		parts[k] = [[], [], []]      # (plain arrays: a packed one read out of an Array is a copy)
	var m: Mesh = mi.mesh
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var cc: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var bb: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var ww: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var per := bb.size() / vv.size()
		var pv := PackedVector3Array()
		var pn := PackedVector3Array()
		var side := PackedStringArray()
		pv.resize(vv.size())
		pn.resize(vv.size())
		side.resize(vv.size())
		for i in vv.size():
			var p := Vector3.ZERO
			var n := Vector3.ZERO
			var best := -1.0
			var bname := ""
			for k in per:
				var w := ww[i * per + k]
				if w <= 0.0:
					continue
				var xf: Transform3D = bind_xf[bb[i * per + k]]
				p += (xf * vv[i]) * w
				n += (xf.basis * nn[i]) * w
				if w > best:
					best = w
					bname = bind_bone[bb[i * per + k]]
			pv[i] = p
			pn[i] = n.normalized()
			side[i] = "al" if (bname == "LeftArm" or bname == "LeftForeArm" or bname.begins_with("LeftHand")) else \
				("ar" if (bname == "RightArm" or bname == "RightForeArm" or bname.begins_with("RightHand")) else "")
		var idx := PackedInt32Array()
		if a[Mesh.ARRAY_INDEX] != null and (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
			idx = a[Mesh.ARRAY_INDEX]
		else:
			for i in vv.size():
				idx.append(i)
		for q in range(0, idx.size(), 3):
			# a triangle goes with the part most of its corners are on
			var s0 := side[idx[q]]
			var s1 := side[idx[q + 1]]
			var s2 := side[idx[q + 2]]
			var part := s0 if (s0 == s1 or s0 == s2) else s1
			var arr: Array = parts[part]
			for e in 3:
				var vi := idx[q + e]
				(arr[0] as Array).append(pv[vi])
				(arr[1] as Array).append(pn[vi])
				(arr[2] as Array).append(cc[vi])
	# the shoulders: where each arm turns
	var sh := []
	for s in ["Left", "Right"]:
		sh.append((to_me * sk.get_bone_global_pose(sk.find_bone(s + "Arm"))).origin)
	meta["%d_%s" % [v, pose]] = [sh[0].x, sh[0].y, sh[0].z, sh[1].x, sh[1].y, sh[1].z]
	for k in parts:
		var arr: Array = parts[k]
		var off: Vector3 = Vector3.ZERO if k == "" else (sh[0] if k == "al" else sh[1])
		var verts := PackedVector3Array(arr[0])
		for i in verts.size():
			verts[i] -= off
		if verts.is_empty():
			push_warning("empty part %d %s %s" % [v, pose, k])
			continue
		var mesh := _mesh(verts, PackedVector3Array(arr[1]), PackedColorArray(arr[2]), k == "")
		ResourceSaver.save(mesh, OUT + "qp_%d_%s%s.res" % [v, pose, "" if k == "" else "_" + k], ResourceSaver.FLAG_COMPRESS)
	av.queue_free()

## Corners welded (same place, normal and colour), the body thinned down to about KEEP of its triangles.
func _mesh(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, thin: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in verts.size():
		st.set_color(cols[i])
		st.set_normal(norms[i])
		st.add_vertex(verts[i])
	st.index()
	var arrays := st.commit_to_arrays()
	if thin and arrays[Mesh.ARRAY_INDEX] != null:
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
		im.generate_lods(25.0, 60.0, [])
		var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var best := full
		for li in im.get_surface_lod_count(0):
			var ii := im.get_surface_lod_indices(0, li)
			if ii.size() >= full.size() * KEEP and ii.size() < best.size():
				best = ii
		arrays[Mesh.ARRAY_INDEX] = best
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out
