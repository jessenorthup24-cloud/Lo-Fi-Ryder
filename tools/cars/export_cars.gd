extends SceneTree
## Bakes chosen cars from the pack into game meshes: scaled to toy size, turned to face -Z, texture colours
## baked into vertex colours (head and tail lights tagged to glow), wheels split out left and right.
const S := 0.46
const OUT := "/home/claude/lo-fi-ryder/assets/cars/"
var tex: Image

func _init():
	tex = Image.load_from_file("res://tinycarpack_0.png")
	var keys: PackedStringArray = OS.get_environment("CARS").split(",")
	var root: Node3D = (load("res://tinycarpack.fbx") as PackedScene).instantiate()
	var meta := {}
	for c in root.get_children():
		var nm := String(c.name).trim_prefix("Car")
		if not keys.has(nm):
			continue
		meta[nm] = _export_car(c, nm)
	var f := FileAccess.open(OUT + "cars_meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	print("done ", meta.keys())
	quit()

func _col(uv: Vector2) -> Color:
	var x := clampi(int(fposmod(uv.x, 1.0) * tex.get_width()), 0, tex.get_width() - 1)
	var y := clampi(int(fposmod(uv.y, 1.0) * tex.get_height()), 0, tex.get_height() - 1)
	return tex.get_pixel(x, y)

func _bake(mi: MeshInstance3D, xf: Transform3D, glow_rule: Callable) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var m: Mesh = mi.mesh
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var uu: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var ii = a[Mesh.ARRAY_INDEX]
		var base := verts.size()
		for k in vv.size():
			var p: Vector3 = xf * vv[k]
			verts.append(p)
			norms.append((xf.basis * nn[k]).normalized())
			cols.append(_col(uu[k]) if uu.size() > k else Color.WHITE)
		if ii == null or (ii as PackedInt32Array).is_empty():
			for k in vv.size():
				idx.append(base + k)
		else:
			for k in (ii as PackedInt32Array):
				idx.append(base + k)
	# lights: bright faces at the very front, red at the very back
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in verts:
		lo = lo.min(p)
		hi = hi.max(p)
	for k in verts.size():
		var c: Color = cols[k]
		var g: bool = glow_rule.call(verts[k], c, lo, hi)
		cols[k] = Color(c.r, c.g, c.b, 0.5 if g else 1.0)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out

func _export_car(car: Node3D, nm: String) -> Dictionary:
	var body: MeshInstance3D = null
	var wheel_nodes := []
	for k in car.get_children():
		if k is MeshInstance3D:
			body = k
		elif k is Node3D and k.get_child_count() > 0:
			wheel_nodes.append(k)
	var wmesh: MeshInstance3D = wheel_nodes[0].get_child(0)
	var wr: float = wmesh.mesh.get_aabb().size.y * 0.5
	var wy: float = (wheel_nodes[0] as Node3D).position.y
	var lift := wr - wy
	# pack cars face +Z: turn them round, sit the tyres on y = 0, shrink to toy size
	var turn := Basis(Vector3.UP, PI)
	var to_game := Transform3D(turn.scaled(Vector3.ONE * S), Vector3.ZERO) * Transform3D(Basis(), Vector3(0, lift, 0))
	var no_glow := func(_p: Vector3, _c: Color, _lo: Vector3, _hi: Vector3) -> bool: return false
	var lights := func(p: Vector3, c: Color, lo: Vector3, hi: Vector3) -> bool:
		var L := hi.z - lo.z
		var H := hi.y - lo.y
		var h := (p.y - lo.y) / H
		var front := p.z < lo.z + L * 0.07
		var back := p.z > hi.z - L * 0.06
		var lum := c.r * 0.3 + c.g * 0.55 + c.b * 0.15
		var red := c.r > 0.7 and c.g < 0.4 and c.b < 0.4
		return (front and h > 0.15 and h < 0.62 and lum > 0.78) or (back and h > 0.2 and h < 0.75 and red)
	var bm := _bake(body, to_game * body.transform, lights)
	ResourceSaver.save(bm, OUT + nm + "_body.res", ResourceSaver.FLAG_COMPRESS)
	# wheels: game left = pack +x
	var info := {"wheels": [], "r": wr * S}
	var left: Node3D = null
	var right: Node3D = null
	for w in wheel_nodes:
		var wp: Vector3 = (w as Node3D).position
		if wp.z > 0.0 and wp.x > 0.0: left = w
		if wp.z > 0.0 and wp.x < 0.0: right = w
	for pair in [[left, "_wl"], [right, "_wr"]]:
		var wn: Node3D = pair[0]
		var mi: MeshInstance3D = wn.get_child(0)
		var wxf := Transform3D(turn.scaled(Vector3.ONE * S), Vector3.ZERO) * mi.transform
		ResourceSaver.save(_bake(mi, wxf, no_glow), OUT + nm + String(pair[1]) + ".res", ResourceSaver.FLAG_COMPRESS)
	# wheel centres in game order: front-left, front-right, rear-left, rear-right
	var order := [[1.0, 1.0], [-1.0, 1.0], [1.0, -1.0], [-1.0, -1.0]]
	for o in order:
		for w in wheel_nodes:
			var wp: Vector3 = (w as Node3D).position
			if signf(wp.x) == o[0] and signf(wp.z) == o[1]:
				var g: Vector3 = to_game * wp
				info["wheels"].append([snappedf(g.x, 0.001), snappedf(g.y, 0.001), snappedf(g.z, 0.001)])
	var ab := bm.get_aabb()
	info["aabb"] = [snappedf(ab.position.x, 0.001), snappedf(ab.position.y, 0.001), snappedf(ab.position.z, 0.001), snappedf(ab.size.x, 0.001), snappedf(ab.size.y, 0.001), snappedf(ab.size.z, 0.001)]
	info["verts"] = bm.surface_get_array_len(0)
	return info
