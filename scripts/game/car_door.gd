extends RefCounted
## A car's driver door opening (getting in or out). The cars are each one solid body, so the door's cut out of
## it for the moment: the triangles on the left flank facing out, between about a third and three fifths of
## the way back from the nose, from the sill to the roof line, become a door of their own hinged at its front
## edge, with a dark panel behind where it was (else you'd see straight through the car). Closed again, the
## car's own body goes back. Works on any car body (the player's, a parked one, one off the road).
##   var d := CarDoor.open(body_meshinstance, material); CarDoor.swing(d, 0..1); CarDoor.close(d)

const OPEN_ANGLE := 1.15       # radians, the door at its widest

static func open(body: MeshInstance3D, mat: Material) -> Dictionary:
	if body == null or body.mesh == null:
		return {}
	var src: Mesh = body.mesh
	var ab := src.get_aabb()
	var ln := ab.size.z
	var z0 := ab.position.z + ln * 0.30          # (the nose is -Z: the front edge of the door)
	var z1 := ab.position.z + ln * 0.62
	var y0 := ab.position.y + ab.size.y * 0.18
	var y1 := ab.position.y + ab.size.y * 0.86
	var xs := ab.position.x + ab.size.x * 0.3    # (the left flank: -X)
	var keep := ArrayMesh.new()
	var door_tris := []               # [verts, normals, colours, uvs]
	var dv := PackedVector3Array()
	var dn := PackedVector3Array()
	var dc := PackedColorArray()
	var du := PackedVector2Array()
	var side_x := 1e9
	for si in src.get_surface_count():
		var a := src.surface_get_arrays(si)
		var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nn = a[Mesh.ARRAY_NORMAL]
		var cc = a[Mesh.ARRAY_COLOR]
		var uu = a[Mesh.ARRAY_TEX_UV]
		var idx := PackedInt32Array()
		if a[Mesh.ARRAY_INDEX] != null and (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
			idx = a[Mesh.ARRAY_INDEX]
		else:
			for i in vv.size():
				idx.append(i)
		var kept := PackedInt32Array()
		for q in range(0, idx.size(), 3):
			var p0 := vv[idx[q]]
			var p1 := vv[idx[q + 1]]
			var p2 := vv[idx[q + 2]]
			var c := (p0 + p1 + p2) / 3.0
			var fn := (p1 - p0).cross(p2 - p0)
			fn = fn.normalized() if fn.length() > 1e-9 else Vector3.UP
			var on_door := c.x < xs and c.z > z0 and c.z < z1 and c.y > y0 and c.y < y1 and absf(fn.x) > 0.45
			if not on_door:
				kept.append_array([idx[q], idx[q + 1], idx[q + 2]])
				continue
			for e in 3:
				var vi := idx[q + e]
				dv.append(vv[vi])
				dn.append((nn as PackedVector3Array)[vi] if nn != null else fn)
				dc.append((cc as PackedColorArray)[vi] if cc != null else Color.WHITE)
				du.append((uu as PackedVector2Array)[vi] if uu != null else Vector2.ZERO)
				side_x = minf(side_x, vv[vi].x)
		if kept.size() > 0:
			a[Mesh.ARRAY_INDEX] = kept
			keep.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	if dv.size() < 9:
		return {}          # (nothing door-shaped there)
	# the door, about its hinge (the front edge, on the flank)
	var hinge := Vector3(side_x, (y0 + y1) * 0.5, z0)
	for i in dv.size():
		dv[i] -= hinge
	var da := []
	da.resize(Mesh.ARRAY_MAX)
	da[Mesh.ARRAY_VERTEX] = dv
	da[Mesh.ARRAY_NORMAL] = dn
	da[Mesh.ARRAY_COLOR] = dc
	da[Mesh.ARRAY_TEX_UV] = du
	var dm := ArrayMesh.new()
	dm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, da)
	var pivot := Node3D.new()
	pivot.name = "Door"
	body.add_child(pivot)
	pivot.position = hinge
	var door := MeshInstance3D.new()
	door.mesh = dm
	door.material_override = mat
	pivot.add_child(door)
	# the cabin behind it: dark
	var fill := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(ab.size.x * 0.08, (y1 - y0) * 0.85, (z1 - z0) * 0.95)
	fill.mesh = bm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.06, 0.06, 0.08)
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill.material_override = fm
	fill.position = Vector3(side_x + ab.size.x * 0.12, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	body.add_child(fill)
	var orig := body.mesh
	body.mesh = keep
	return {"body": body, "orig": orig, "pivot": pivot, "fill": fill, "k": 0.0}

## How far open (0 shut, 1 wide).
static func swing(d: Dictionary, k: float) -> void:
	if d.is_empty() or not is_instance_valid(d["pivot"]):
		return
	d["k"] = clampf(k, 0.0, 1.0)
	(d["pivot"] as Node3D).rotation.y = -OPEN_ANGLE * (1.0 - pow(1.0 - float(d["k"]), 2.0))

## Shut: the car's own body back, the door and the panel gone.
static func close(d: Dictionary) -> void:
	if d.is_empty():
		return
	if is_instance_valid(d["body"]):
		(d["body"] as MeshInstance3D).mesh = d["orig"]
	for k in ["pivot", "fill"]:
		if is_instance_valid(d[k]):
			(d[k] as Node).queue_free()
	d.clear()
