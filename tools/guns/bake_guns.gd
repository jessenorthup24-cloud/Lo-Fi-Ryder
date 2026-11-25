extends SceneTree
## Bakes PIXEL ARSENAL guns (a paid pack: the source and the baked meshes live only in the private
## lo-fi-assets-private repo, never in this public one) into game meshes: every part merged, each
## triangle coloured from its pixel-art texture (alpha 0.7: the toon shader's "as painted"), turned to point
## down -Z with the grip at the origin. Writes <OUT>/<preset>.res and guns_meta.json (length, muzzle).
##   SRC=/path/PixelArsenal_Mega_v1.0/GLB OUT=/path/lo-fi-assets-private/guns godot --headless --path . -s tools/guns/bake_guns.gd

const FAMILIES := ["Pistol", "Revolver", "SMG", "Pump_Shotgun", "AK_Rifle", "Sniper_Rifle"]

func _init() -> void:
	var src := OS.get_environment("SRC")
	var out := OS.get_environment("OUT")
	DirAccess.make_dir_recursive_absolute(out)
	var meta := {}
	for fam: String in FAMILIES:
		var dir := src + "/" + fam + "/Presets"
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".glb"):
				continue
			var doc := GLTFDocument.new()
			var st := GLTFState.new()
			if doc.append_from_file(dir + "/" + f, st) != OK:
				continue
			var root: Node3D = doc.generate_scene(st)
			var m := _merge(root)
			root.free()
			if m == null:
				continue
			var key := f.get_basename()
			ResourceSaver.save(m, out + "/" + key + ".res", ResourceSaver.FLAG_COMPRESS)
			var ab := m.get_aabb()
			meta[key] = {"family": fam, "len": snappedf(ab.size.z, 0.001), "muzzle": [0.0, snappedf(ab.get_center().y, 0.001), snappedf(ab.position.z, 0.001)], "tris": m.surface_get_array_len(0) / 3}
			print("BAKED ", key, " ", meta[key])
	var fh := FileAccess.open(out + "/guns_meta.json", FileAccess.WRITE)
	fh.store_string(JSON.stringify(meta, "\t"))
	fh.close()
	quit()

func _merge(root: Node3D) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = (mi as Node3D).global_transform if (mi as Node3D).is_inside_tree() else _xf_of(mi as Node3D, root)
		var m: Mesh = (mi as MeshInstance3D).mesh
		for si in m.get_surface_count():
			var a := m.surface_get_arrays(si)
			var mat := (mi as MeshInstance3D).get_active_material(si)
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
	# point it down -Z (the packs' barrels run along +Z), the middle of the grip end at the origin
	var ab := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		ab = ab.expand(v)
	var turn := Basis(Vector3.UP, PI)
	var off := Vector3(ab.get_center().x, ab.get_center().y, ab.position.z + ab.size.z * 0.22)
	for k in verts.size():
		verts[k] = turn * (verts[k] - off)
		norms[k] = turn * norms[k]
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out

func _xf_of(n: Node3D, root: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
