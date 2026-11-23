extends SceneTree
## Bakes chosen Kenney (CC0) models into game meshes: all mesh parts merged, the colormap texture baked
## into vertex colours (alpha 0.7 = "as authored" colour band in toon.gdshader), turned to face -Z like the
## game's own models, saved as assets/kenney/k_<pack>_<name>.res at the pack's native scale (models.gd scales
## them on load). The little people are posed (standing, sitting) and split into a body and two arms that
## hang from their shoulders, so they can still wave. Run from a scratch project whose res://packs/<pack>/
## holds the pack's "GLB format" folder:  godot --headless --path <scratch> -s bake_kenney.gd
const OUT := "/home/claude/lo-fi-ryder/assets/kenney/"
const PICK := {
	"sub": ["building-type-a", "building-type-b", "building-type-c", "building-type-d", "building-type-e", "building-type-f",
		"building-type-g", "building-type-h", "building-type-i", "building-type-j", "building-type-k", "building-type-l",
		"building-type-m", "building-type-n", "building-type-o", "building-type-p", "building-type-q", "building-type-r",
		"building-type-s", "building-type-t", "building-type-u", "fence-1x2", "fence-low", "planter", "tree-large", "tree-small"],
	"com": ["building-a", "building-b", "building-c", "building-d", "building-e", "building-f", "building-g", "building-h",
		"detail-parasol-a", "detail-parasol-b", "detail-awning"],
	"skate": ["half-pipe", "half-pipe-low", "ramp", "ramp-rail", "rail-high", "rail-low", "rail-slope", "obstacle-box",
		"obstacle-box-grind", "bench", "fence", "steps-rail", "structure-platform", "skateboard", "scooter", "bowl-side"],
	"surv": ["tent", "tent-canvas", "campfire-pit", "barrel", "box", "box-large", "bedroll", "signpost", "tree", "tree-tall",
		"tree-autumn", "tree-autumn-tall", "tree-log", "rock-a", "rock-b", "rock-c", "rock-flat-grass", "resource-wood",
		"workbench", "chest", "bucket"],
	"forest": ["tree", "tree-high", "rocks-high", "rocks-low", "plant", "stones", "flag", "tent"],
	"pets": ["animal-beaver", "animal-bee", "animal-bunny", "animal-cat", "animal-caterpillar", "animal-chick", "animal-cow",
		"animal-crab", "animal-deer", "animal-dog", "animal-elephant", "animal-fish", "animal-fox", "animal-giraffe", "animal-hog",
		"animal-koala", "animal-lion", "animal-monkey", "animal-panda", "animal-parrot", "animal-penguin", "animal-pig",
		"animal-polar", "animal-tiger"],
	"castle": ["tower-square-base", "tower-square-mid", "tower-square-top-roof", "tower-hexagon-base", "tower-hexagon-mid",
		"tower-hexagon-roof", "wall", "wall-corner", "gate", "flag", "flag-pennant", "bridge-straight", "tree-large"],
	"holi": ["snowman", "snowman-hat", "present-a-cube", "present-b-round", "present-a-rectangle", "tree-decorated", "lantern",
		"candy-cane-red", "sled", "reindeer", "gingerbread-man", "lights-colored"],
	"mod": ["building-sample-house-a", "building-sample-house-b", "building-sample-house-c", "building-sample-tower-a",
		"building-sample-tower-b"],
	"retro": ["detail-bench", "detail-light-single"],
	"arena": ["banner", "statue", "trophy"],
	"chars": ["character-female-a", "character-female-b", "character-female-c", "character-female-d", "character-female-e",
		"character-female-f", "character-male-a", "character-male-b", "character-male-c", "character-male-d", "character-male-e",
		"character-male-f", "character-male-g", "character-worker"],
}
var images := {}
const TURN := Basis(Vector3.UP, PI)   # Kenney models face +Z; the game's face -Z

func _init():
	var meta := {}
	for pack in PICK:
		if pack == "chars":
			continue
		for nm in PICK[pack]:
			var path := "res://packs/%s/%s.glb" % [pack, nm]
			if not ResourceLoader.exists(path):
				print("MISSING ", path)
				continue
			var root: Node = (load(path) as PackedScene).instantiate()
			var m := _bake(root, "", Vector3.ZERO, pack in ["sub", "com", "mod"], nm in ["lantern", "lights-colored", "detail-light-single"])
			root.free()
			var key := "k_%s_%s" % [pack, nm]
			ResourceSaver.save(m, OUT + key + ".res", ResourceSaver.FLAG_COMPRESS)
			var ab := m.get_aabb()
			meta[key] = [snappedf(ab.position.x, 0.001), snappedf(ab.position.y, 0.001), snappedf(ab.position.z, 0.001),
				snappedf(ab.size.x, 0.001), snappedf(ab.size.y, 0.001), snappedf(ab.size.z, 0.001), m.surface_get_array_len(0)]
	# the little people, posed, with loose arms
	for nm in PICK["chars"]:
		for pose in [["idle", 0.3, "stand"], ["sit", 0.1, "sit"]]:
			var root: Node = (load("res://packs/chars/%s.glb" % nm) as PackedScene).instantiate()
			get_root().add_child(root)
			var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
			ap.play(pose[0])
			ap.seek(pose[1], true)
			var sk: Skeleton3D = root.find_child("Skeleton3D", true, false)
			var key := "k_chars_%s_%s" % [nm, pose[2]]
			var piv := []
			for part in ["body", "arm-left", "arm-right"]:
				var off := Vector3.ZERO
				if part != "body":
					off = TURN * (_xf_to_root(sk) * sk.get_bone_global_pose(sk.find_bone(part))).origin
					piv.append_array([snappedf(off.x, 0.001), snappedf(off.y, 0.001), snappedf(off.z, 0.001)])
				var m := _bake(root, part, off)
				if part != "body":
					# let the arm hang by the side (or rest forward on the lap when sitting)
					var sx := 1.0 if off.x > 0.0 else -1.0
					m = _hang(m, Vector3(sx * 0.16, -1.0, 0.0) if pose[2] == "stand" else Vector3(sx * 0.12, -0.75, -0.65))
				var k2 := key if part == "body" else key + ("_al" if part == "arm-left" else "_ar")
				ResourceSaver.save(m, OUT + k2 + ".res", ResourceSaver.FLAG_COMPRESS)
				var ab := m.get_aabb()
				meta[k2] = [snappedf(ab.position.x, 0.001), snappedf(ab.position.y, 0.001), snappedf(ab.position.z, 0.001),
					snappedf(ab.size.x, 0.001), snappedf(ab.size.y, 0.001), snappedf(ab.size.z, 0.001), m.surface_get_array_len(0)]
			meta[key + "_pivots"] = piv
			root.queue_free()
	var f := FileAccess.open(OUT + "kenney_meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	print("baked ", meta.size())
	quit()

## Turns a loose arm (origin at the shoulder) so it points along `dir`.
func _hang(m: ArrayMesh, dir: Vector3) -> ArrayMesh:
	var a := m.surface_get_arrays(0)
	var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var c := Vector3.ZERO
	for v in vv:
		c += v
	c /= maxf(1.0, vv.size())
	var q := Quaternion(c.normalized(), dir.normalized())
	for k in vv.size():
		vv[k] = q * vv[k]
		nn[k] = q * nn[k]
	a[Mesh.ARRAY_VERTEX] = vv
	a[Mesh.ARRAY_NORMAL] = nn
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return out

func _img(tex: Texture2D) -> Image:
	if images.has(tex):
		return images[tex]
	var im := tex.get_image()
	if im.is_compressed():
		im.decompress()
	images[tex] = im
	return im

func _xf_to_root(n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != null and cur is Node3D and cur.get_parent() != null and not (cur.get_parent() is Window):
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([n, here])
	for c in n.get_children():
		_collect(c, here, out)

## part: "" everything; for skinned models "body" (all but the arms) or a bone name ("arm-left"), moved so
## `off` (the shoulder) is the origin.
func _bake(root: Node, part: String, off: Vector3, lit_glass := false, lit_bulbs := false) -> ArrayMesh:
	var parts := []
	_collect(root, Transform3D(), parts)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for pt in parts:
		var mi: MeshInstance3D = pt[0]
		var xf: Transform3D = pt[1]
		var m: Mesh = mi.mesh
		for si in m.get_surface_count():
			var a := m.surface_get_arrays(si)
			var mat = mi.get_active_material(si)
			var tint := Color.WHITE
			var im: Image = null
			if mat is BaseMaterial3D:
				tint = (mat as BaseMaterial3D).albedo_color
				if (mat as BaseMaterial3D).albedo_texture:
					im = _img((mat as BaseMaterial3D).albedo_texture)
			var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var keep := PackedByteArray()
			# skinned (the characters): pose every vertex by its bones, on the CPU
			var skel: Skeleton3D = mi.get_node_or_null(mi.skeleton) as Skeleton3D if mi.skin != null else null
			if skel != null:
				var sxf := _xf_to_root(skel)
				var mats := []
				for bi in mi.skin.get_bind_count():
					var bone := mi.skin.get_bind_bone(bi)
					if bone < 0:
						bone = skel.find_bone(mi.skin.get_bind_name(bi))
					mats.append(sxf * skel.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bi))
				var bones = a[Mesh.ARRAY_BONES]
				var weights = a[Mesh.ARRAY_WEIGHTS]
				var per := (bones as PackedInt32Array).size() / vv.size()
				# which part each vertex belongs to: its heaviest bone
				keep = PackedByteArray()
				keep.resize(vv.size())
				for k in vv.size():
					var bw := -1.0
					var bb := 0
					for j in per:
						if weights[k * per + j] > bw:
							bw = weights[k * per + j]
							bb = bones[k * per + j]
					var bone := mi.skin.get_bind_bone(bb)
					var bname := skel.get_bone_name(bone) if bone >= 0 else String(mi.skin.get_bind_name(bb))
					var is_arm := bname.begins_with("arm-")
					keep[k] = 1 if part == "" or (part == "body" and not is_arm) or bname == part else 0
				var pv := PackedVector3Array()
				var pn := PackedVector3Array()
				for k in vv.size():
					var p := Vector3.ZERO
					var q := Vector3.ZERO
					for j in per:
						var w: float = weights[k * per + j]
						if w > 0.0:
							var mm: Transform3D = mats[bones[k * per + j]]
							p += (mm * vv[k]) * w
							q += (mm.basis * nn[k]) * w
					pv.append(p)
					pn.append(q.normalized())
				vv = pv
				nn = pn
				xf = Transform3D()
			var uu = a[Mesh.ARRAY_TEX_UV]
			var cc = a[Mesh.ARRAY_COLOR]
			var ii = a[Mesh.ARRAY_INDEX]
			var remap := PackedInt32Array()
			remap.resize(vv.size())
			for k in vv.size():
				remap[k] = -1
				if not keep.is_empty() and keep[k] == 0:
					continue
				remap[k] = verts.size()
				verts.append(TURN * (xf * vv[k]) - off)
				norms.append((TURN * (xf.basis * nn[k])).normalized())
				var c := tint
				if im != null and uu != null and (uu as PackedVector2Array).size() > k:
					var uv: Vector2 = uu[k]
					c = c * im.get_pixel(clampi(int(fposmod(uv.x, 1.0) * im.get_width()), 0, im.get_width() - 1),
						clampi(int(fposmod(uv.y, 1.0) * im.get_height()), 0, im.get_height() - 1))
				elif cc != null and (cc as PackedColorArray).size() > k:
					c = c * (cc as PackedColorArray)[k]
				# house windows light up at night
				var glass := lit_glass and c.b > c.r + 0.25 and c.b > c.g + 0.1 and c.r > 0.35
				if lit_bulbs and c.s > 0.45 and c.v > 0.75:
					glass = true
				cols.append(Color(c.r, c.g, c.b, 0.45 if glass else 0.7))
			var tri := PackedInt32Array()
			if ii == null or (ii as PackedInt32Array).is_empty():
				for k in vv.size():
					tri.append(k)
			else:
				tri = ii
			for t in range(0, tri.size(), 3):
				var r0 := remap[tri[t]]
				var r1 := remap[tri[t + 1]]
				var r2 := remap[tri[t + 2]]
				if r0 < 0 or r1 < 0 or r2 < 0:
					continue
				idx.append(r0)
				idx.append(r1)
				idx.append(r2)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out
