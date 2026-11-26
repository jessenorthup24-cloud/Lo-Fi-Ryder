extends SceneTree
## Bakes the heist props (glTF: the safe, the core drill, the money duffle, a bundle of cash) into game meshes:
## assets/props/<key>.res, and for each pivot node (the safe's DoorPivot, the drill's BitPivot) a mesh of
## what hangs off it, <key>_<pivot>.res, in the pivot's own space; props_meta.json has where each pivot sits.
## Flat materials become vertex colours (alpha 0.7: the toon shader draws them as painted); textured ones
## (the printed dollar, the strap) keep their UVs as a second surface with their own textured material.
##   GLB_DIR=/path/to/glbs godot --headless --path . -s tools/props/bake_props.gd
## (files: *safe*.glb -> safe, *drill*.glb -> drill, *tool*duffle*.glb -> tool_duffle (the drill's bag),
## *duffle*.glb -> duffle (the cash bag), *cash*.glb -> cash; what's already in props_meta.json is kept)

const OUT := "res://assets/props/"
const KEYS := [["tool", "tool_duffle"], ["safe", "safe"], ["drill", "drill"], ["duffle", "duffle"], ["cash", "cash"]]

var meta := {}

func _init() -> void:
	var dir := OS.get_environment("GLB_DIR")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if FileAccess.file_exists(OUT + "props_meta.json"):
		var old = JSON.parse_string(FileAccess.get_file_as_string(OUT + "props_meta.json"))
		if old is Dictionary:
			meta = old
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".glb"):
			continue
		var key := ""
		for k in KEYS:
			if f.to_lower().contains(k[0]):
				key = k[1]
				break
		if key == "":
			continue
		_bake_file(dir.path_join(f), key)
	var fa := FileAccess.open(OUT + "props_meta.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(meta, "\t"))
	fa.close()
	print("PROPS done ", meta.keys())
	quit()

func _bake_file(path: String, key: String) -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		push_error("can't read " + path)
		return
	var root: Node3D = doc.generate_scene(st)
	# parts: "" (the body) or the pivot's name -> [[MeshInstance3D, xf in that part's space]]
	var parts := {"": []}
	var pivots := {}
	_walk(root, Transform3D(), "", Transform3D(), parts, pivots)
	var m := {"pivots": {}}
	for pk in parts:
		var mesh := _bake(parts[pk])
		var nm: String = key if pk == "" else key + "_" + String(pk).to_lower()
		ResourceSaver.save(mesh, OUT + nm + ".res", ResourceSaver.FLAG_COMPRESS)
		if pk == "":
			var ab := mesh.get_aabb()
			m["aabb"] = [ab.position.x, ab.position.y, ab.position.z, ab.size.x, ab.size.y, ab.size.z]
		else:
			var o: Vector3 = (pivots[pk] as Transform3D).origin
			m["pivots"][String(pk).to_lower()] = [o.x, o.y, o.z]
		print("PROPS ", nm, " surfaces=", mesh.get_surface_count(), " aabb=", mesh.get_aabb())
	meta[key] = m
	root.free()

func _walk(n: Node, xf: Transform3D, part: String, part_xf: Transform3D, parts: Dictionary, pivots: Dictionary) -> void:
	var here := xf * ((n as Node3D).transform if n is Node3D else Transform3D())
	var p := part
	var pxf := part_xf
	if n.name.ends_with("Pivot"):
		p = String(n.name)
		pxf = here
		pivots[p] = here
		parts[p] = []
	if n is MeshInstance3D:
		(parts[p] as Array).append([n, pxf.affine_inverse() * here])
	for c in n.get_children():
		_walk(c, here, p, pxf, parts, pivots)

## Every surface into one flat-coloured surface (vertex colours), plus one for the textured ones.
func _bake(list: Array) -> ArrayMesh:
	var flat := SurfaceTool.new()
	flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tex_st := SurfaceTool.new()
	tex_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tex: Texture2D = null
	var any_tex := false
	var no_normals := false
	for e in list:
		var mi: MeshInstance3D = e[0]
		var x: Transform3D = e[1]
		var mesh := mi.mesh
		for si in mesh.get_surface_count():
			var mat := mi.get_active_material(si) as BaseMaterial3D
			var col := mat.albedo_color if mat else Color.WHITE
			var t: Texture2D = mat.albedo_texture if mat else null
			var arr := mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms := PackedVector3Array()
			if arr[Mesh.ARRAY_NORMAL] != null:
				norms = arr[Mesh.ARRAY_NORMAL]
			else:
				no_normals = true
			var uvs = arr[Mesh.ARRAY_TEX_UV]
			var idx = arr[Mesh.ARRAY_INDEX]
			var order: Array = []
			if idx != null and (idx as PackedInt32Array).size() > 0:
				order = Array(idx)
			else:
				order = range(verts.size())
			var st := tex_st if t != null else flat
			if t != null:
				any_tex = true
				tex = t
			var nb := x.basis.inverse().transposed()
			for i in order:
				st.set_normal((nb * norms[i]).normalized() if norms.size() > i else Vector3.UP)
				if t != null and uvs != null:
					st.set_uv((uvs as PackedVector2Array)[i])
					st.set_color(Color(col.r, col.g, col.b, 1.0))
				else:
					st.set_color(Color(col.r, col.g, col.b, 0.7))
				st.add_vertex(x * verts[i])
	var out := flat.commit()
	if no_normals and out.get_surface_count() > 0:
		# (a model saved without normals: made from its faces)
		var st2 := SurfaceTool.new()
		st2.create_from(out, 0)
		st2.generate_normals()
		out = st2.commit()
	if any_tex:
		tex_st.commit(out)
		var tm := StandardMaterial3D.new()
		tm.albedo_texture = tex
		tm.vertex_color_use_as_albedo = false
		tm.roughness = 0.9
		out.surface_set_material(out.get_surface_count() - 1, tm)
	return out
