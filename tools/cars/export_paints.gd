extends SceneTree
## Paint jobs: the pack has each car body in five or so liveries. Rather than ship a mesh for every one, this
## takes each car the game uses and, for every other livery of the same body, works out the colour each of
## its vertices would have (from the nearest vertex of that livery, facing the same way), and saves the lot
## as one image per car: a row of colours per paint job (assets/cars/<model>_paints.res), plus
## paints_meta.json listing each car's paints with a swatch colour.
## Run from the scratch project with the pack (tinycarpack.fbx and its texture):
##   CARS=13_4,10_1,... godot --headless --path <scratch> -s export_paints.gd
const S := 0.46
const GAME := "/home/claude/lo-fi-ryder/assets/cars/"
const CELL := 0.03
var tex: Image

func _init():
	tex = Image.load_from_file("res://tinycarpack_0.png")
	var keys: PackedStringArray = OS.get_environment("CARS").split(",")
	var root: Node3D = (load("res://tinycarpack.fbx") as PackedScene).instantiate()
	var by := {}
	for c in root.get_children():
		by[String(c.name).trim_prefix("Car")] = c
	var meta := {}
	for key in keys:
		var body_n := key.get_slice("_", 0)
		var own := key.get_slice("_", 1)
		var base: ArrayMesh = load(GAME + key + "_body.res")
		var ba := base.surface_get_arrays(0)
		var bp: PackedVector3Array = ba[Mesh.ARRAY_VERTEX]
		var bn: PackedVector3Array = ba[Mesh.ARRAY_NORMAL]
		var bc: PackedColorArray = ba[Mesh.ARRAY_COLOR]
		var main := _main_paint(bc)
		var rows := []
		var list := [{"v": key, "swatch": _swatch(bc, main).to_html(false)}]
		for v in range(1, 7):
			var vk := "%s_%d" % [body_n, v]
			if vk == key or not by.has(vk):
				continue
			var got: Array = _variant(by[vk])
			var cols := _map(bp, bn, got[0], got[1], got[2], bc)
			rows.append(cols)
			list.append({"v": vk, "swatch": _swatch(cols, main).to_html(false)})
		var img := Image.create(bp.size(), rows.size(), false, Image.FORMAT_RGB8)
		for r in rows.size():
			var cols: PackedColorArray = rows[r]
			for i in bp.size():
				img.set_pixel(i, r, cols[i])
		ResourceSaver.save(img, GAME + key + "_paints.res", ResourceSaver.FLAG_COMPRESS)
		meta[key] = list
		print(key, ": ", list.map(func(e): return e["v"] + " " + e["swatch"]))
	var f := FileAccess.open(GAME + "paints_meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	quit()

func _col(uv: Vector2) -> Color:
	var x := clampi(int(fposmod(uv.x, 1.0) * tex.get_width()), 0, tex.get_width() - 1)
	var y := clampi(int(fposmod(uv.y, 1.0) * tex.get_height()), 0, tex.get_height() - 1)
	return tex.get_pixel(x, y)

## A livery's body in game space: [positions, normals, colours] (as export_cars.gd bakes it).
func _variant(car: Node3D) -> Array:
	var body: MeshInstance3D = null
	var wheel_nodes := []
	for k in car.get_children():
		if k is MeshInstance3D:
			body = k
		elif k is Node3D and k.get_child_count() > 0:
			wheel_nodes.append(k)
	var wmesh: MeshInstance3D = wheel_nodes[0].get_child(0)
	var lift: float = wmesh.mesh.get_aabb().size.y * 0.5 - (wheel_nodes[0] as Node3D).position.y
	var turn := Basis(Vector3.UP, PI)
	var xf := Transform3D(turn.scaled(Vector3.ONE * S), Vector3.ZERO) * Transform3D(Basis(), Vector3(0, lift, 0)) * body.transform
	var ps := PackedVector3Array()
	var ns := PackedVector3Array()
	var cs := PackedColorArray()
	var m: Mesh = body.mesh
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var uu: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		for k in vv.size():
			ps.append(xf * vv[k])
			ns.append((xf.basis * nn[k]).normalized())
			cs.append(_col(uu[k]) if uu.size() > k else Color.WHITE)
	return [ps, ns, cs]

## For each vertex of the base car, the colour at the nearest vertex of the livery that faces the same way.
func _map(bp: PackedVector3Array, bn: PackedVector3Array, qp: PackedVector3Array, qn: PackedVector3Array, qc: PackedColorArray, fallback: PackedColorArray) -> PackedColorArray:
	var grid := {}
	for i in qp.size():
		var key := Vector3i((qp[i] / CELL).floor())
		if not grid.has(key):
			grid[key] = []          # (an Array: a packed array would be copied, not added to)
		(grid[key] as Array).append(i)
	var out := PackedColorArray()
	out.resize(bp.size())
	for i in bp.size():
		var c0 := Vector3i((bp[i] / CELL).floor())
		var best := -1
		var bd := INF
		var best_any := -1
		var bd_any := INF
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var cell = grid.get(c0 + Vector3i(dx, dy, dz))
					if cell == null:
						continue
					for j in (cell as Array):
						var d := bp[i].distance_squared_to(qp[j])
						if d < bd_any:
							bd_any = d
							best_any = j
						if bn[i].dot(qn[j]) > 0.5 and d < bd:
							bd = d
							best = j
		if best < 0:
			best = best_any
		out[i] = qc[best] if best >= 0 else fallback[i]
	return out

## The car's main paint: the commonest colour on it (ignoring dark trim, glass and chrome greys).
func _main_paint(cols: PackedColorArray) -> Dictionary:
	var count := {}
	for c in cols:
		if c.s < 0.15 and (c.v < 0.35 or c.v > 0.8):
			continue
		var k := Color(snappedf(c.r, 0.1), snappedf(c.g, 0.1), snappedf(c.b, 0.1))
		count[k] = int(count.get(k, 0)) + 1
	var best := Color(0.5, 0.5, 0.5)
	var bn := -1
	for k in count:
		if int(count[k]) > bn:
			bn = count[k]
			best = k
	return {"col": best}

## The swatch for a paint job: its average over the vertices where the factory car wears its main colour.
func _swatch(cols: PackedColorArray, main: Dictionary) -> Color:
	var key: Color = main["col"]
	if not main.has("mask"):
		var mask := PackedByteArray()
		mask.resize(cols.size())
		for i in cols.size():
			var c := cols[i]
			mask[i] = 1 if Color(snappedf(c.r, 0.1), snappedf(c.g, 0.1), snappedf(c.b, 0.1)) == key else 0
		main["mask"] = mask
	var m: PackedByteArray = main["mask"]
	var sum := Color(0, 0, 0)
	var n := 0
	for i in mini(cols.size(), m.size()):
		if m[i] == 1:
			sum += cols[i]
			n += 1
	return Color(sum.r / maxf(n, 1), sum.g / maxf(n, 1), sum.b / maxf(n, 1))
