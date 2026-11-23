extends RefCounted
## Crash damage you can see: pushes a mesh's vertices in around the point of an impact (on a private copy
## of the mesh), and recomputes its normals so the crumple catches the light.

## A copy of mesh that can be bent, with its vertex arrays kept to hand.
static func own(mesh: Mesh) -> Dictionary:
	var m := ArrayMesh.new()
	var surfs := []
	var orig := []
	for i in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(i)
		surfs.append(arr)
		orig.append((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate())
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := mesh.surface_get_material(i)
		if mat:
			m.surface_set_material(i, mat)
	return {"mesh": m, "surfs": surfs, "orig": orig, "src": mesh}

## Push in around p (mesh space) against the outward normal n: radius and depth in metres. A vertex never
## moves further than max_push from where it started, so nothing turns inside out.
static func dent(d: Dictionary, p: Vector3, n: Vector3, radius: float, depth: float, max_push := 0.35) -> void:
	var m: ArrayMesh = d["mesh"]
	var src: Mesh = d["src"]
	m.clear_surfaces()
	var r2 := radius * radius
	for si in d["surfs"].size():
		var arr: Array = d["surfs"][si]
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var orig: PackedVector3Array = d["orig"][si]
		var moved := false
		var touched := PackedByteArray()
		touched.resize(vs.size())
		for i in vs.size():
			var dd := vs[i].distance_squared_to(p)
			if dd >= r2:
				continue
			var f := 1.0 - sqrt(dd) / radius
			# mostly straight in, a little crumple so it isn't a smooth dish
			var wob := sin(vs[i].x * 23.0 + vs[i].z * 17.0) * 0.25
			var nv := vs[i] - n * depth * f * f * (1.0 + wob)
			var off := nv - orig[i]
			if off.length() > max_push:
				nv = orig[i] + off.normalized() * max_push
			vs[i] = nv
			touched[i] = 1
			moved = true
		arr[Mesh.ARRAY_VERTEX] = vs
		if moved:
			_normals(arr, touched)
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := src.surface_get_material(si)
		if mat:
			m.surface_set_material(si, mat)

## Back as it came from the factory.
static func repair(d: Dictionary) -> void:
	var m: ArrayMesh = d["mesh"]
	var src: Mesh = d["src"]
	m.clear_surfaces()
	for si in d["surfs"].size():
		var arr := src.surface_get_arrays(si)
		d["surfs"][si] = arr
		d["orig"][si] = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := src.surface_get_material(si)
		if mat:
			m.surface_set_material(si, mat)

static func _normals(arr: Array, touched: PackedByteArray) -> void:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns := PackedVector3Array()
	ns.resize(vs.size())
	var idx = arr[Mesh.ARRAY_INDEX]
	if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
		var ii: PackedInt32Array = idx
		for t in range(0, ii.size() - 2, 3):
			var a := ii[t]
			var b := ii[t + 1]
			var c := ii[t + 2]
			var fn := (vs[b] - vs[a]).cross(vs[c] - vs[a])
			ns[a] += fn
			ns[b] += fn
			ns[c] += fn
	else:
		for t in range(0, vs.size() - 2, 3):
			var fn := (vs[t + 1] - vs[t]).cross(vs[t + 2] - vs[t])
			ns[t] = fn
			ns[t + 1] = fn
			ns[t + 2] = fn
	var old: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] is PackedVector3Array else PackedVector3Array()
	for i in ns.size():
		if touched[i] == 0 and i < old.size():
			ns[i] = old[i]
			continue
		var nn := ns[i]
		if nn.length_squared() < 1e-12:
			ns[i] = old[i] if i < old.size() else Vector3.UP
			continue
		nn = nn.normalized()
		# keep the winding the mesh came with
		if i < old.size() and nn.dot(old[i]) < 0.0:
			nn = -nn
		ns[i] = nn
	arr[Mesh.ARRAY_NORMAL] = ns
