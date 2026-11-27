extends SceneTree
## Bakes a car made as a glTF (one with its wheels as their own nodes, like the Haywire) into the same
## shape as the Tiny Car Pack cars (tools/cars/export_cars.gd): <key>_body.res, <key>_wl.res, <key>_wr.res
## and an entry in cars_meta.json, at toy size, facing -Z, tyres on y = 0.
## Flat materials become vertex colours; textured ones (livery, lettering) keep their UVs, moved into one
## atlas (assets/cars/<key>_detail.png) that the toon shader reads through the car_detail global, and are
## tagged with vertex alpha 0.9. Lamps ("light" front, "red" back) are tagged to glow.
##   GLB=/path/car.glb KEY=hoon LEN=4.25 ONE_SIDED=1 KEEP=0.35 COARSE=1 godot --headless --path . -s tools/cars/bake_glb_car.gd
##   (the Mountain Ghost: KEY=ae86 LEN=4.2 NOTEX=1, the rest the same: only one car can use the texture atlas)
##   An FBX works too, coloured from its swatch sheet (the Designersoup cars):
##   GLB=/path/car.fbx PALETTE=/path/palette.png KEY=wedge LEN=4.2 godot --headless --path . -s tools/cars/bake_glb_car.gd
## Expects the glTF's front along -X, its left along +Z, wheel nodes named Wheel_Front_L and so on.
## FRONT_Z=1: a car facing -Z already, its wheels as Spin_FL / Spin_FR / Spin_RL / Spin_RR (under Travel_ and
## Steer_ nodes), with solid axles (Axle_Front, Axle_Rear) and coil-overs (Spring_FL ...) as their own parts:
## those are baked separately (<key>_axle_f.res, <key>_axle_r.res, <key>_spring.res) for the game to move
## (the Lo-Fi Crawler: GLB=/path/crawler.glb KEY=crawler LEN=4.8 FRONT_Z=1 NOTEX=1 ...)

const OUT := "res://assets/cars/"
const GAME_SCALE := 2.6       # models.gd CAR_SCALE: the game grows the toy-size meta by this
const PAD := 8

var key := ""
var front_z := false
var extras := {}               # FRONT_Z: axle and spring parts by name -> [MeshInstance3D, Transform3D in the car's space]
var to_game := Transform3D()    # glTF metres -> toy size, facing -Z
var atlas_rects := {}           # Texture2D rid -> Rect2 (in atlas pixels)
var atlas: Image

func _init() -> void:
	var path := OS.get_environment("GLB")
	key = OS.get_environment("KEY")
	front_z = OS.get_environment("FRONT_Z") != ""
	var want_len := float(OS.get_environment("LEN")) if OS.get_environment("LEN") != "" else 4.2
	print("BAKE start ", path)
	var fbx := path.get_extension().to_lower() == "fbx"
	var doc: GLTFDocument = FBXDocument.new() if fbx else GLTFDocument.new()
	var st: GLTFState = FBXState.new() if fbx else GLTFState.new()
	if OS.get_environment("PALETTE") != "":
		palette = Image.load_from_file(OS.get_environment("PALETTE"))
		notex = true
	two_sided = OS.get_environment("ONE_SIDED") == ""
	notex = OS.get_environment("NOTEX") != "" or palette != null
	if OS.get_environment("KEEP") != "":
		keep = float(OS.get_environment("KEEP"))
	if OS.get_environment("KEEP_WHEEL") != "":
		keep_wheel = float(OS.get_environment("KEEP_WHEEL"))
	if doc.append_from_file(path, st) != OK:
		push_error("can't read " + path)
		quit(1)
		return
	print("BAKE read")
	var root: Node3D = doc.generate_scene(st)
	print("BAKE scene")
	var wheel_groups := {}      # "Front_L" -> Node3D
	var body_parts := []        # [MeshInstance3D, Transform3D in the car's space]
	if fbx:
		_walk_fbx(root, Transform3D(), wheel_groups, body_parts)
		# DROP=0.28: the body lowered onto its wheels (a car modelled hovering, wheels folded under)
		var drop := float(OS.get_environment("DROP")) if OS.get_environment("DROP") != "" else 0.0
		for bp in body_parts:
			bp[1] = Transform3D(Basis(), Vector3(0, -drop, 0)) * (bp[1] as Transform3D)
	else:
		_walk(root, Transform3D(), wheel_groups, body_parts)
	# size: as long as want_len (bumper to bumper) once the game grows it
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for bp in body_parts:
		var ab: AABB = (bp[1] as Transform3D) * (bp[0] as MeshInstance3D).mesh.get_aabb()
		lo = lo.min(ab.position)
		hi = hi.max(ab.end)
	var s := want_len / ((hi.z - lo.z) if front_z else (hi.x - lo.x)) / GAME_SCALE
	to_game = Transform3D((Basis() if front_z else Basis(Vector3.UP, -PI * 0.5)).scaled(Vector3.ONE * s), Vector3.ZERO)
	if not notex:
		_build_atlas(body_parts)
	# the body
	var bm := _bake(body_parts, true)
	ResourceSaver.save(bm, OUT + key + "_body.res", ResourceSaver.FLAG_COMPRESS)
	# the wheels: game left is the glTF's +Z side
	var wr := 0.0
	for side in [["Front_L", "_wl"], ["Front_R", "_wr"]]:
		var g: Node3D = wheel_groups[side[0]]
		var parts := []
		if g is MeshInstance3D:
			parts.append([g, Transform3D()])        # (FRONT_Z: the wheel node is its own mesh)
		for c in g.get_children():
			if c is MeshInstance3D:
				parts.append([c, (c as MeshInstance3D).transform])
		var wm := _bake(parts, false, true)
		wr = maxf(wr, wm.get_aabb().size.y * 0.5)
		ResourceSaver.save(wm, OUT + key + String(side[1]) + ".res", ResourceSaver.FLAG_COMPRESS)
	if atlas != null:
		atlas.save_png(ProjectSettings.globalize_path(OUT + key + "_detail.png"))
	# wheel spots in game order: front-left, front-right, rear-left, rear-right
	var info := {"wheels": [], "r": snappedf(wr, 0.0001)}
	for nm in ["Front_L", "Front_R", "Rear_L", "Rear_R"]:
		var gp: Vector3 = to_game * (wheel_groups[nm] as Node3D).get_meta("at")
		gp.y = wr       # (tyres on the ground)
		info["wheels"].append([snappedf(gp.x, 0.001), snappedf(gp.y, 0.001), snappedf(gp.z, 0.001)])
	var lift: float = wr - float((to_game * (wheel_groups["Front_L"] as Node3D).get_meta("at")).y)
	if absf(lift) > 0.001:
		push_warning("wheel centres not at tyre radius: lift %.3f (not applied)" % lift)
	# FRONT_Z: the axles and a coil-over, each round its own pivot (the node's origin), and where they sit
	if not extras.is_empty():
		var rig := {}
		for pr in [["Axle_Front", "_axle_f", "axle_f"], ["Axle_Rear", "_axle_r", "axle_r"], ["Spring_FL", "_spring", "spring"]]:
			if not extras.has(pr[0]):
				continue
			var e: Array = extras[pr[0]]
			var em := _bake([[e[0], Transform3D()]], false, true)
			ResourceSaver.save(em, OUT + key + String(pr[1]) + ".res", ResourceSaver.FLAG_COMPRESS)
			var at3: Vector3 = to_game * (e[1] as Transform3D).origin
			rig[pr[2]] = [snappedf(at3.x, 0.001), snappedf(at3.y, 0.001), snappedf(at3.z, 0.001)]
		var tops := []
		for nm2 in ["Spring_FL", "Spring_FR", "Spring_RL", "Spring_RR"]:
			if extras.has(nm2):
				var t3: Vector3 = to_game * ((extras[nm2] as Array)[1] as Transform3D).origin
				tops.append([snappedf(t3.x, 0.001), snappedf(t3.y, 0.001), snappedf(t3.z, 0.001)])
		rig["spring_tops"] = tops
		if extras.has("Spring_FL"):
			var sab: AABB = ((extras["Spring_FL"] as Array)[0] as MeshInstance3D).mesh.get_aabb()
			rig["spring_len"] = snappedf(sab.size.y * to_game.basis.get_scale().y, 0.0001)
		info["rig"] = rig
	var bab := bm.get_aabb()
	info["aabb"] = [snappedf(bab.position.x, 0.001), snappedf(bab.position.y, 0.001), snappedf(bab.position.z, 0.001), snappedf(bab.size.x, 0.001), snappedf(bab.size.y, 0.001), snappedf(bab.size.z, 0.001)]
	info["verts"] = bm.surface_get_array_len(0)
	info["detail"] = atlas != null
	var mp := ProjectSettings.globalize_path(OUT + "cars_meta.json")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(mp))
	meta[key] = info
	var f := FileAccess.open(mp, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	print("BAKED ", key, " ", info, " real length %.2f m" % (bab.size.z * GAME_SCALE))
	quit()

func _walk(n: Node, xf: Transform3D, wheels: Dictionary, body: Array) -> void:
	for c in n.get_children():
		var cx := xf * (c as Node3D).transform if c is Node3D else xf
		var nm := String(c.name)
		if front_z and nm.begins_with("Spin_"):
			var corner := {"FL": "Front_L", "FR": "Front_R", "RL": "Rear_L", "RR": "Rear_R"}
			(c as Node3D).set_meta("at", cx.origin)
			wheels[corner[nm.trim_prefix("Spin_")]] = c
			continue
		if front_z and (nm.begins_with("Axle_") or nm.begins_with("Spring_")):
			extras[nm] = [c, cx]
			continue
		if front_z and nm.begins_with("Steer_"):
			_walk(c, cx, wheels, body)
			continue
		if nm.begins_with("Wheel_") and c.get_child_count() > 0:
			var k := nm.trim_prefix("Wheel_")
			(c as Node3D).set_meta("at", cx.origin)
			wheels[k] = c
			continue
		if nm.begins_with("Steer_") and not "_detail" in nm:
			_walk(c, cx, wheels, [])     # (a steering knuckle's own bits are left off)
			continue
		if c is MeshInstance3D:
			body.append([c, cx])
		_walk(c, cx, wheels, body)

## An FBX car (the Designersoup pack): its wheels are meshes named something with "wheel" in it, the
## names not to be trusted for the corner (they're copied and renamed), so each goes to the corner it
## sits at. A wheel modelled lying flat (a car in its flying pose) is stood back up on its tyre.
func _walk_fbx(n: Node, xf: Transform3D, wheels: Dictionary, body: Array) -> void:
	var found := []
	_collect_fbx(n, xf, found, body)
	var mid := Vector3.ZERO
	for w in found:
		mid += (w[1] as Transform3D) * (w[0] as MeshInstance3D).mesh.get_aabb().get_center()
	mid /= maxf(1.0, found.size())
	for w in found:
		var mi: MeshInstance3D = w[0]
		var wx: Transform3D = w[1]
		var ab: AABB = wx * mi.mesh.get_aabb()
		var c := ab.get_center()
		var up := Basis()
		if ab.size.y < minf(ab.size.x, ab.size.z) * 0.6:
			up = Basis(Vector3.RIGHT, PI * 0.5)       # (axis up the way: tip it so the axle runs across)
			c.y = maxf(ab.size.x, ab.size.z) * 0.5
		var k := ("Front_" if c.x < mid.x else "Rear_") + ("L" if c.z > mid.z else "R")
		var g := Node3D.new()
		g.set_meta("at", c)
		var part := MeshInstance3D.new()
		part.mesh = mi.mesh
		for si in mi.mesh.get_surface_count():
			part.set_surface_override_material(si, mi.get_active_material(si))
		var local := Transform3D(Basis(), -ab.get_center()) * wx
		part.transform = Transform3D(up, Vector3.ZERO) * local
		g.add_child(part)
		wheels[k] = g

func _collect_fbx(n: Node, xf: Transform3D, found: Array, body: Array) -> void:
	for c in n.get_children():
		var cx := xf * (c as Node3D).transform if c is Node3D else xf
		if c is MeshInstance3D:
			if "wheel" in String(c.name).to_lower():
				found.append([c, cx])
				continue
			body.append([c, cx])
		_collect_fbx(c, cx, found, body)

func _tex_of(mat: Material) -> Texture2D:
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).albedo_texture
	return null

func _mat(mi: MeshInstance3D, si: int) -> Material:
	var m := mi.get_active_material(si)
	return m

## One atlas for every texture the car uses, stacked, with a gap so mipmaps don't bleed.
func _build_atlas(parts: Array) -> void:
	var texs := []
	for bp in parts:
		var mi: MeshInstance3D = bp[0]
		for si in mi.mesh.get_surface_count():
			var t := _tex_of(_mat(mi, si))
			if t and not texs.has(t):
				texs.append(t)
	if texs.is_empty():
		return
	var w := 0
	var h := 0
	for t in texs:
		w = maxi(w, t.get_width())
		h += t.get_height() + PAD
	atlas = Image.create(w, h, false, Image.FORMAT_RGB8)
	atlas.fill(Color.WHITE)
	var y := 0
	for t in texs:
		var im: Image = (t as Texture2D).get_image()
		im.decompress()
		im.convert(Image.FORMAT_RGB8)
		atlas.blit_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(0, y))
		# smear the edge rows into the gap
		for k in PAD:
			atlas.blit_rect(im, Rect2i(0, im.get_height() - 1, im.get_width(), 1), Vector2i(0, y + im.get_height() + k))
		atlas_rects[t.get_rid()] = Rect2(0, y, im.get_width(), im.get_height())
		y += im.get_height() + PAD

## Normals for each triangle corner (the glTF has none): the face's own, smoothed with the neighbours
## that meet it at under SMOOTH degrees (so tyres and curves come out round, edges stay crisp).
## Godot's front faces wind clockwise.
const SMOOTH := 38.0
var two_sided := true

func _corner_normals(vv: PackedVector3Array, tri: PackedInt32Array) -> PackedVector3Array:
	var fn := PackedVector3Array()
	var by_v := {}
	for q in range(0, tri.size(), 3):
		var a: Vector3 = vv[tri[q]]
		var n := (vv[tri[q + 2]] - a).cross(vv[tri[q + 1]] - a)
		fn.append(n.normalized() if n.length() > 1e-12 else Vector3.UP)
		for e in 3:
			var p: Vector3 = vv[tri[q + e]]
			var pk := Vector3i(roundi(p.x * 1e4), roundi(p.y * 1e4), roundi(p.z * 1e4))
			if not by_v.has(pk):
				by_v[pk] = PackedInt32Array()
			(by_v[pk] as PackedInt32Array).append(q / 3)
	var out := PackedVector3Array()
	out.resize(tri.size())
	var lim := cos(deg_to_rad(SMOOTH))
	for q in range(0, tri.size(), 3):
		var f: Vector3 = fn[q / 3]
		for e in 3:
			var p: Vector3 = vv[tri[q + e]]
			var pk := Vector3i(roundi(p.x * 1e4), roundi(p.y * 1e4), roundi(p.z * 1e4))
			var acc := Vector3.ZERO
			for o in (by_v[pk] as PackedInt32Array):
				var g: Vector3 = fn[o]
				if g.dot(f) >= lim:
					acc += g
			out[q + e] = acc.normalized() if acc.length() > 1e-9 else f
	return out

func _bake(parts: Array, lamps: bool, centred := false) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var basis_only := Transform3D(to_game.basis, Vector3.ZERO)
	for bp in parts:
		var mi: MeshInstance3D = bp[0]
		var xf: Transform3D = (basis_only if centred else to_game) * (bp[1] as Transform3D)
		var m: Mesh = mi.mesh
		for si in m.get_surface_count():
			var a := m.surface_get_arrays(si)
			var mat := _mat(mi, si)
			var base_col := Color.WHITE
			if mat is BaseMaterial3D:
				base_col = (mat as BaseMaterial3D).albedo_color
			var mname := String(mat.resource_name) if mat else ""
			var t := _tex_of(mat)
			var pal := palette != null and t != null
			if pal:
				t = null
			elif t and notex:
				# (no atlas for this one: a small texture, a number plate, say, as its average colour)
				var im: Image = t.get_image()
				im.decompress()
				im.resize(1, 1, Image.INTERPOLATE_BILINEAR)
				base_col = base_col * im.get_pixel(0, 0)
				t = null
			var rect: Rect2 = atlas_rects.get(t.get_rid(), Rect2()) if t else Rect2()
			var glow := lamps and (mname in ["light", "red", "Warm headlight lens"] or mname.begins_with("gradientEmmisive"))
			var v0 := verts.size()
			var i0 := idx.size()
			if OS.get_environment("DEBUG") != "":
				print("PART ", mi.name, " mat '", mname, "' tex ", t != null, " glow ", glow, " verts ", (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			var src: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			if mname == "spring" and keep < 1.0:
				continue     # (coil springs, thousands of triangles, up inside the arches where you can't see them)
			if mname == "Grille mesh" and keep < 1.0:
				# a perforated grille, thousands of tiny holes: drawn as its dark backing panel
				var ab := AABB(xf * src[0], Vector3.ZERO)
				for q in src:
					ab = ab.expand(xf * q)
				var gb := verts.size()
				var gc := base_col.darkened(0.3)
				var gn := Vector3(0, 0, -1)
				for cn in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
					verts.append(Vector3(ab.position.x + cn.x * ab.size.x, ab.position.y + cn.y * ab.size.y, ab.position.z + ab.size.z * 0.5))
					norms.append(gn)
					cols.append(Color(gc.r, gc.g, gc.b, 1.0))
					uvs.append(Vector2.ZERO)
				for q in [0, 2, 1, 0, 3, 2]:
					idx.append(gb + q)
				continue
			var vv := PackedVector3Array()
			for k in src.size():
				vv.append(xf * src[k])
			var uu = a[Mesh.ARRAY_TEX_UV]
			var ii = a[Mesh.ARRAY_INDEX]
			var tri := PackedInt32Array()
			if ii == null or (ii as PackedInt32Array).is_empty():
				for k in vv.size():
					tri.append(k)
			else:
				tri = ii
			var sides := [1]
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED and two_sided:
				sides = [1, -1]
			var corner_n := _corner_normals(vv, tri)
			for sd in sides:
				var seen := {}
				for k in tri.size():
					var vi: int = tri[k]
					var n: Vector3 = corner_n[k] * sd
					var kk := Vector4i(vi, roundi(n.x * 50.0), roundi(n.y * 50.0), roundi(n.z * 50.0))
					var at: int = seen.get(kk, -1)
					if at < 0:
						at = verts.size()
						seen[kk] = at
						verts.append(vv[vi])
						norms.append(n)
						var c := base_col
						if t and uu != null and (uu as PackedVector2Array).size() > vi:
							var uv: Vector2 = uu[vi]
							uv = Vector2(clampf(uv.x, 0.0, 1.0), clampf(uv.y, 0.0, 1.0))
							uvs.append(Vector2((rect.position.x + uv.x * rect.size.x) / atlas.get_width(), (rect.position.y + uv.y * rect.size.y) / atlas.get_height()))
							cols.append(Color(c.r, c.g, c.b, 0.9))
						else:
							if pal and uu != null and (uu as PackedVector2Array).size() > vi:
								var puv: Vector2 = uu[vi]
								c = palette.get_pixel(clampi(int(fposmod(puv.x, 1.0) * palette.get_width()), 0, palette.get_width() - 1),
									clampi(int(fposmod(puv.y, 1.0) * palette.get_height()), 0, palette.get_height() - 1))
							uvs.append(Vector2.ZERO)
							cols.append(Color(c.r, c.g, c.b, 0.5 if glow else 1.0))
					idx.append(at)
				if sd < 0:
					# the back faces: wound the other way
					var n0 := idx.size() - tri.size()
					for q in range(n0, idx.size(), 3):
						var tmp := idx[q + 1]
						idx[q + 1] = idx[q + 2]
						idx[q + 2] = tmp
			# a big plain part (the shell, the grille, the blower): fewer triangles. Lamps, glass and the
			# livery stay as they are (simplified, small bits like those just vanish).
			var k := keep_wheel if centred else keep
			if k < 1.0 and t == null and not glow and idx.size() - i0 > 3000:
				var part := []
				part.resize(Mesh.ARRAY_MAX)
				part[Mesh.ARRAY_VERTEX] = verts.slice(v0)
				part[Mesh.ARRAY_NORMAL] = norms.slice(v0)
				part[Mesh.ARRAY_COLOR] = cols.slice(v0)
				part[Mesh.ARRAY_TEX_UV] = uvs.slice(v0)
				var pi := idx.slice(i0)
				for q in pi.size():
					pi[q] -= v0
				part[Mesh.ARRAY_INDEX] = pi
				if OS.get_environment("DEBUG") != "":
					print("SIMPL PART ", mi.name, " ", mname)
				part = _simplify(part, k)
				verts.resize(v0); norms.resize(v0); cols.resize(v0); uvs.resize(v0); idx.resize(i0)
				verts.append_array(part[Mesh.ARRAY_VERTEX])
				norms.append_array(part[Mesh.ARRAY_NORMAL])
				cols.append_array(part[Mesh.ARRAY_COLOR])
				uvs.append_array(part[Mesh.ARRAY_TEX_UV])
				for q in (part[Mesh.ARRAY_INDEX] as PackedInt32Array):
					idx.append(q + v0)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out

## Fewer triangles (Godot's LOD maker, meshoptimizer underneath): the coarsest LOD that still keeps about
## `keep` of them, then the vertices nothing uses any more dropped. Dents and the GPU both pay per vertex.
var keep := 1.0
var keep_wheel := 1.0
var palette: Image     # PALETTE=/path.png: the car's textures are a colour swatch sheet: each vertex takes its swatch
var notex := false     # NOTEX=1: no texture atlas (the toon shader has one, the Hoon's): textures as flat colour

func _simplify(arr: Array, want: float) -> Array:
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(25.0, 60.0, [])
	var full: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var best := full
	var sizes := []
	for li in im.get_surface_lod_count(0):
		var ii := im.get_surface_lod_indices(0, li)
		sizes.append(ii.size() / 3)
		if ii.size() >= full.size() * want and ii.size() < best.size():
			best = ii
	if best == full and sizes.size() > 0 and OS.get_environment("COARSE") != "":
		best = im.get_surface_lod_indices(0, 0)     # (no level near the target: the finest one there is)
	var remap := {}
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var vv := PackedVector3Array()
	var nn := PackedVector3Array()
	var cc := PackedColorArray()
	var uu := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in best:
		if not remap.has(i):
			remap[i] = vv.size()
			vv.append(arr[Mesh.ARRAY_VERTEX][i])
			nn.append(arr[Mesh.ARRAY_NORMAL][i])
			cc.append(arr[Mesh.ARRAY_COLOR][i])
			uu.append(arr[Mesh.ARRAY_TEX_UV][i])
		idx.append(remap[i])
	out[Mesh.ARRAY_VERTEX] = vv
	out[Mesh.ARRAY_NORMAL] = nn
	out[Mesh.ARRAY_COLOR] = cc
	out[Mesh.ARRAY_TEX_UV] = uu
	out[Mesh.ARRAY_INDEX] = idx
	print("SIMPLIFY tris %d -> %d, verts %d -> %d" % [full.size() / 3, idx.size() / 3, (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), vv.size()])
	return out
