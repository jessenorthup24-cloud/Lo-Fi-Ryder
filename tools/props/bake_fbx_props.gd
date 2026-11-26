extends SceneTree
## Bakes small FBX props coloured from a swatch sheet (Designersoup's "extras": tyre stacks, cones, oil drums,
## a windsock, spare wheels, an air gun; CC0) into one mesh each: assets/props/ds_<name>.res, vertex colours
## (alpha 0.7: the toon shader draws them as painted), standing on y = 0, centred, in metres.
##   FBX_DIR=/path/to/extras PALETTE=/path/to/palette.png godot --headless --path . -s tools/props/bake_fbx_props.gd

const OUT := "res://assets/props/"

var palette: Image

func _init() -> void:
	var dir := OS.get_environment("FBX_DIR")
	palette = Image.load_from_file(OS.get_environment("PALETTE"))
	var meta := {}
	for f in DirAccess.get_files_at(dir):
		if not f.to_lower().ends_with(".fbx"):
			continue
		var doc := FBXDocument.new()
		var st := FBXState.new()
		if doc.append_from_file(dir.path_join(f), st) != OK:
			push_error("can't read " + f)
			continue
		var root: Node3D = doc.generate_scene(st)
		var parts := []
		_walk(root, Transform3D(), parts)
		var m := _bake(parts)
		var key := "ds_" + f.get_basename().to_snake_case()
		ResourceSaver.save(m, OUT + key + ".res", ResourceSaver.FLAG_COMPRESS)
		var ab := m.get_aabb()
		meta[key] = [snappedf(ab.size.x, 0.01), snappedf(ab.size.y, 0.01), snappedf(ab.size.z, 0.01)]
		print("PROP ", key, " ", meta[key], " verts ", m.surface_get_array_len(0))
		root.free()
	quit()

func _walk(n: Node, xf: Transform3D, out: Array) -> void:
	for c in n.get_children():
		var cx := xf * (c as Node3D).transform if c is Node3D else xf
		if c is MeshInstance3D:
			out.append([c, cx])
		_walk(c, cx, out)

func _bake(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for bp in parts:
		var mi: MeshInstance3D = bp[0]
		var xf: Transform3D = bp[1]
		for si in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(si)
			var mat := mi.get_active_material(si)
			var base := Color.WHITE
			var tex := false
			if mat is BaseMaterial3D:
				base = (mat as BaseMaterial3D).albedo_color
				tex = (mat as BaseMaterial3D).albedo_texture != null
			var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var uu = a[Mesh.ARRAY_TEX_UV]
			var ii = a[Mesh.ARRAY_INDEX]
			var tri := PackedInt32Array()
			if ii == null or (ii as PackedInt32Array).is_empty():
				for k in vv.size():
					tri.append(k)
			else:
				tri = ii
			for q in range(0, tri.size(), 3):
				var p0 := xf * vv[tri[q]]
				var p1 := xf * vv[tri[q + 1]]
				var p2 := xf * vv[tri[q + 2]]
				var fn := (p2 - p0).cross(p1 - p0)
				fn = fn.normalized() if fn.length() > 1e-12 else Vector3.UP
				for e in 3:
					var vi: int = tri[q + e]
					verts.append(xf * vv[vi])
					norms.append(fn)
					var c := base
					if tex and uu != null and (uu as PackedVector2Array).size() > vi:
						var uv: Vector2 = uu[vi]
						c = palette.get_pixel(clampi(int(fposmod(uv.x, 1.0) * palette.get_width()), 0, palette.get_width() - 1),
							clampi(int(fposmod(uv.y, 1.0) * palette.get_height()), 0, palette.get_height() - 1))
					cols.append(Color(c.r, c.g, c.b, 0.7))
	# stood on the ground, centred
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in verts:
		lo = lo.min(p)
		hi = hi.max(p)
	var off := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)
	for k in verts.size():
		verts[k] -= off
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out
