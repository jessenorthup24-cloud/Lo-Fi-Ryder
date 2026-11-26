extends SceneTree
## Bakes the whole PIXEL ARSENAL Mega Pack into a gun kit for the Armory: every base receiver and every loose
## part as its own game mesh (each triangle coloured from its pixel-art texture, alpha 0.7: the toon shader's
## "as painted"), kept in the pack's own frame (barrels along +Z, a part's origin its mount point), plus
## kit.json: each part's family, category, the sockets it mounts to and the ones it provides (their
## transforms), its hand-hold marks, and each preset as a base plus a part on each socket (worked out by
## matching the preset's pieces against the loose parts). Also copies the pack's inventory icons.
## The pack is licensed: the source and everything baked from it go only to the private
## lo-fi-assets-private repo, never into this public one.
##   SRC=/path/PixelArsenal_Mega_v1.0 OUT=/path/lo-fi-assets-private/guns godot --headless --path . -s tools/guns/bake_kit.gd

var src := ""
var out := ""
var kit := {"families": {}, "parts": {}}

func _init() -> void:
	src = OS.get_environment("SRC")
	out = OS.get_environment("OUT")
	DirAccess.make_dir_recursive_absolute(out + "/kit")
	DirAccess.make_dir_recursive_absolute(out + "/icons")
	var only := OS.get_environment("ONLY")
	var csv := _csv(src + "/CONTENTS.csv")
	for fam in DirAccess.get_directories_at(src + "/GLB"):
		if only != "" and fam != only:
			continue
		kit["families"][fam] = {"bases": [], "presets": {}}
		var sig := {}           # part name -> its mesh node names (to match presets)
		var pdir := src + "/GLB/" + fam + "/Parts"
		for cat in DirAccess.get_directories_at(pdir):
			for f in DirAccess.get_files_at(pdir + "/" + cat):
				if not f.ends_with(".glb"):
					continue
				var nm := f.get_basename()
				var info := _part(pdir + "/" + cat + "/" + f, nm)
				if info.is_empty():
					continue
				var row: Dictionary = csv.get(nm, {})
				info["family"] = fam
				info["cat"] = cat
				info["mounts"] = String(row.get("mounts_to", "")).split(" ", false)
				info["finish"] = String(row.get("finish", ""))
				kit["parts"][nm] = info
				sig[nm] = info["sig"]
				if cat == "Base":
					(kit["families"][fam]["bases"] as Array).append(nm)
				_icon(fam, "Parts/" + cat, nm)
		var prd := src + "/GLB/" + fam + "/Presets"
		for f in DirAccess.get_files_at(prd):
			if f.ends_with(".glb"):
				var nm2 := f.get_basename()
				kit["families"][fam]["presets"][nm2] = _preset(prd + "/" + f, fam, sig)
				_icon(fam, "Presets", nm2)
		print("KIT ", fam, " parts=", sig.size(), " presets=", kit["families"][fam]["presets"].size())
	for nm in kit["parts"]:
		kit["parts"][nm].erase("sig")
	var fh := FileAccess.open(out + "/kit.json", FileAccess.WRITE)
	fh.store_string(JSON.stringify(kit))
	fh.close()
	quit()

func _csv(path: String) -> Dictionary:
	var d := {}
	var f := FileAccess.open(path, FileAccess.READ)
	var head := f.get_csv_line()
	while not f.eof_reached():
		var l := f.get_csv_line()
		if l.size() < head.size():
			continue
		var row := {}
		for i in head.size():
			row[head[i]] = l[i]
		d[row["name"]] = row
	return d

func _icon(fam: String, sub: String, nm: String) -> void:
	var p := src + "/Icons/" + fam + "/" + sub + "/" + nm + ".png"
	if FileAccess.file_exists(p):
		DirAccess.copy_absolute(p, out + "/icons/" + nm + ".png")

func _load(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		return null
	return doc.generate_scene(st)

## The model's own root: the node named after the file (inside the scene's wrapper).
func _root(scene: Node, nm: String) -> Node3D:
	var r := scene.find_child(nm, true, false)
	return r as Node3D if r else scene as Node3D

func _rel(n: Node, root: Node) -> Transform3D:
	var x := Transform3D()
	var p: Node = n
	while p != null and p != root:
		if p is Node3D:
			x = (p as Node3D).transform * x
		p = p.get_parent()
	return x

func _xf_arr(x: Transform3D) -> Array:
	return [x.basis.x.x, x.basis.x.y, x.basis.x.z, x.basis.y.x, x.basis.y.y, x.basis.y.z, x.basis.z.x, x.basis.z.y, x.basis.z.z,
		x.origin.x, x.origin.y, x.origin.z]

## A loose part (or a base): its mesh baked, its sockets and hand marks.
func _part(path: String, nm: String) -> Dictionary:
	var scene := _load(path)
	if scene == null:
		return {}
	var root := _root(scene, nm)
	var sockets := {}
	var hands := {}
	var meshes: Array = []
	var names: Array = []
	_walk(root, root, sockets, hands, meshes, names)
	var m := _bake(meshes)
	scene.free()
	if m == null:
		return {}
	ResourceSaver.save(m, out + "/kit/" + nm + ".res", ResourceSaver.FLAG_COMPRESS)
	var ab := m.get_aabb()
	names.sort()
	return {"sockets": sockets, "hands": hands, "sig": names, "tris": m.surface_get_array_len(0) / 3,
		"aabb": [ab.position.x, ab.position.y, ab.position.z, ab.size.x, ab.size.y, ab.size.z]}

func _walk(n: Node, root: Node, sockets: Dictionary, hands: Dictionary, meshes: Array, names: Array) -> void:
	for c in n.get_children():
		var cn := String(c.name)
		if cn.begins_with("socket_hand_"):
			hands[cn.trim_prefix("socket_")] = _xf_arr(_rel(c, root))
			continue
		if cn.begins_with("socket_"):
			sockets[cn.trim_prefix("socket_")] = _xf_arr(_rel(c, root))
			continue              # (in a loose part a socket's empty; in a preset what's under it is another part)
		if c is MeshInstance3D:
			meshes.append([c, _rel(c, root)])
			names.append(cn.get_slice("#", 0))
		_walk(c, root, sockets, hands, meshes, names)

## A preset: which base, and which part on each socket (by its pieces' names: the closest loose part that
## mounts there).
func _preset(path: String, fam: String, sig: Dictionary) -> Dictionary:
	var nm := path.get_file().get_basename()
	var scene := _load(path)
	var root := _root(scene, nm)
	var base_names: Array = []
	for c in root.get_children():
		if c is MeshInstance3D:
			base_names.append(String(c.name).get_slice("#", 0))
	var base := _best(base_names, sig, func(p: String): return String(kit["parts"][p]["cat"]) == "Base")
	var parts := {}
	_preset_sockets(root, sig, parts)
	scene.free()
	return {"base": base, "parts": parts}

func _preset_sockets(n: Node, sig: Dictionary, parts: Dictionary) -> void:
	for c in n.get_children():
		var cn := String(c.name)
		if cn.begins_with("socket_hand_"):
			continue
		if not cn.begins_with("socket_"):
			# (a pivot, a hinge: sockets can sit under those too)
			if not (c is MeshInstance3D):
				_preset_sockets(c, sig, parts)
			continue
		var sk := cn.trim_prefix("socket_")
		var names: Array = []
		for m in c.get_children():
			if m is MeshInstance3D:
				names.append(String(m.name).get_slice("#", 0))
		if names.is_empty():
			continue
		var p := _best(names, sig, func(q: String): return (kit["parts"][q]["mounts"] as Array).has(sk))
		if p != "":
			parts[sk] = p
		_preset_sockets(c, sig, parts)       # (a part's own sockets: a barrel's muzzle, a scope's top)

func _best(names: Array, sig: Dictionary, ok: Callable) -> String:
	var best := ""
	var bs := 0.0
	var mine := {}
	for x in names:
		mine[x] = int(mine.get(x, 0)) + 1
	for p in sig:
		if not ok.call(p):
			continue
		var theirs := {}
		for x in sig[p]:
			theirs[x] = int(theirs.get(x, 0)) + 1
		var inter := 0
		var uni := 0
		for k in mine:
			inter += mini(int(mine[k]), int(theirs.get(k, 0)))
			uni += maxi(int(mine[k]), int(theirs.get(k, 0)))
		for k in theirs:
			if not mine.has(k):
				uni += int(theirs[k])
		var sc := float(inter) / float(maxi(uni, 1))
		if sc > bs:
			bs = sc
			best = p
	return best if bs > 0.05 else ""

func _bake(list: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for e in list:
		var mi: MeshInstance3D = e[0]
		var xf: Transform3D = e[1]
		var m: Mesh = mi.mesh
		for si in m.get_surface_count():
			var a := m.surface_get_arrays(si)
			var mat := mi.get_active_material(si)
			var img: Image = null
			var base := Color.WHITE
			if mat is BaseMaterial3D:
				base = (mat as BaseMaterial3D).albedo_color
				if (mat as BaseMaterial3D).albedo_texture:
					img = (mat as BaseMaterial3D).albedo_texture.get_image()
					if img and img.is_compressed():
						img.decompress()
			var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var uu = a[Mesh.ARRAY_TEX_UV]
			var ii = a[Mesh.ARRAY_INDEX]
			var idx := PackedInt32Array()
			if ii == null:
				for k in vv.size():
					idx.append(k)
			else:
				idx = ii
			for q in range(0, idx.size(), 3):
				var p0 := xf * vv[idx[q]]
				var p1 := xf * vv[idx[q + 1]]
				var p2 := xf * vv[idx[q + 2]]
				var n := (p2 - p0).cross(p1 - p0).normalized()
				var c := base
				if img and uu != null:
					var uv: Vector2 = ((uu[idx[q]] as Vector2) + (uu[idx[q + 1]] as Vector2) + (uu[idx[q + 2]] as Vector2)) / 3.0
					c = c * img.get_pixel(clampi(int(fposmod(uv.x, 1.0) * img.get_width()), 0, img.get_width() - 1), clampi(int(fposmod(uv.y, 1.0) * img.get_height()), 0, img.get_height() - 1))
				for p in [p0, p1, p2]:
					verts.append(p)
					norms.append(n)
					cols.append(Color(c.r, c.g, c.b, 0.7))
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	var outm := ArrayMesh.new()
	outm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return outm
