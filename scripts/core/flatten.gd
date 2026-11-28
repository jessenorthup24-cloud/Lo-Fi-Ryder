extends RefCounted
## A model made of many parts (an imported building or machine: a door, a sign, a frame, a pane, each its own
## mesh), made into one mesh with one surface per material. Each part was a draw call of its own (twice with
## shadows); now each material is one. Looks the same: same triangles, same materials, in the same places.
## Skinned or animated parts are left alone.

## Flattens everything under `root` into one MeshInstance3D child of root. Returns the parts merged.
static func flatten(root: Node3D, range_end := 0.0) -> int:
	var r := build(root)
	if r.is_empty():
		return 0
	for mi: MeshInstance3D in r[1]:
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	var one := MeshInstance3D.new()
	one.name = "Flat"
	one.mesh = r[0]
	one.cast_shadow = r[2]
	if range_end > 0.0:
		one.visibility_range_end = range_end
	root.add_child(one)
	return (r[1] as Array).size()

## The merged mesh of everything under root (in root's own space; root needn't be in the scene), the parts
## it was made of, and whether any cast shadows: [mesh, parts, cast_shadow]. Empty if not worth it.
static func build(root: Node3D) -> Array:
	var parts: Array = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.skin != null or not mi.visible:
			continue
		if mi.get_child_count() > 0:
			continue          # (something hangs off it: leave it be)
		parts.append(mi)
	if parts.size() < 2:
		return []
	var by_mat := {}          # material -> SurfaceTool
	var order: Array = []
	var shadows := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi: MeshInstance3D in parts:
		var xf := _rel(root, mi)
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				return []          # (lines or points: not worth the trouble, leave the lot)
			var mat: Material = mi.material_override
			if mat == null:
				mat = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			var key: Variant = mat if mat else "none"
			if not by_mat.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[key] = st
				order.append(key)
			(by_mat[key] as SurfaceTool).append_from(mi.mesh, s, xf)
	var out := ArrayMesh.new()
	for key in order:
		var st: SurfaceTool = by_mat[key]
		st.commit(out)
		if key is Material:
			out.surface_set_material(out.get_surface_count() - 1, key)
	return [out, parts, shadows]

static func _rel(root: Node, n: Node) -> Transform3D:
	var t := Transform3D()
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
