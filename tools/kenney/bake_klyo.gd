extends SceneTree
## Bakes the Klyo Games stunt arena kits (CC BY 4.0) into game meshes, like bake_kenney.gd: parts merged,
## each material's colour (its texture averaged) baked into vertex colours (alpha 0.7: "as authored" in
## toon.gdshader), saved as assets/kenney/k_klyo_<name>.res, plus k_klyo_<name>_col.res from the kit's
## simple collision meshes where the game uses them (the drivable pieces; island.add_stunt_collider picks
## them up). Models stay as authored, in metres; ramps rise towards -Z, the gap jump is driven towards -Z.
## Run from a scratch project whose res://packs/klyo/ holds the kits' *_lod1.glb and *_collision.glb files:
##   godot --headless --path <scratch> -s bake_klyo.gd
## The kit's vertical loop isn't used: it's a closed ring (no way in or out), so the game builds its own.
## JSON.stringify writes every number as a float, so merge the new kenney_meta.json lines in by hand
## rather than keeping the rewritten file.
const OUT := "/home/claude/lo-fi-ryder/assets/kenney/"
const PICK := ["ramp_low", "ramp_kicker", "platform", "gold_hoop", "container", "jersey_barrier", "steel_drum", "floodlight",
	"half_pipe", "industrial_tunnel", "gap_jump_pair", "boost_pad", "checkpoint_gate"]
const COL := ["ramp_low", "ramp_kicker", "platform"]
var avg := {}

func _init():
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT + "kenney_meta.json"))
	for nm in PICK:
		for kind in ["", "_col"]:
			var path := "res://packs/klyo/%s%s.glb" % [nm, "_lod1" if kind == "" else "_collision"]
			if not ResourceLoader.exists(path) or (kind == "_col" and not nm in COL):
				continue
			var root: Node = (load(path) as PackedScene).instantiate()
			var m := _bake(root)
			root.free()
			var key := "k_klyo_%s%s" % [nm, kind]
			ResourceSaver.save(m, OUT + key + ".res", ResourceSaver.FLAG_COMPRESS)
			var ab := m.get_aabb()
			meta[key] = [snappedf(ab.position.x, 0.001), snappedf(ab.position.y, 0.001), snappedf(ab.position.z, 0.001),
				snappedf(ab.size.x, 0.001), snappedf(ab.size.y, 0.001), snappedf(ab.size.z, 0.001), m.surface_get_array_len(0)]
			print("%s %s tris %d" % [key, str(ab.size), m.surface_get_array_len(0) / 3])
	var f := FileAccess.open(OUT + "kenney_meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	quit()

func _avg(tex: Texture2D) -> Color:
	if avg.has(tex):
		return avg[tex]
	var im := tex.get_image()
	if im.is_compressed():
		im.decompress()
	# the mean over a grid of samples (a 1x1 resize only looks at a few pixels)
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in 48:
		for x in 48:
			sum += im.get_pixel(int((x + 0.5) / 48.0 * im.get_width()), int((y + 0.5) / 48.0 * im.get_height()))
			n += 1
	avg[tex] = Color(sum.r / n, sum.g / n, sum.b / n)
	print("  ", tex.resource_path.get_file(), " -> ", avg[tex].to_html(false))
	return avg[tex]

func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([n, here])
	for c in n.get_children():
		_collect(c, here, out)

func _bake(root: Node) -> ArrayMesh:
	var parts := []
	_collect(root, Transform3D(), parts)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for pt in parts:
		var mi: MeshInstance3D = pt[0]
		var xf: Transform3D = pt[1]
		var m: Mesh = mi.mesh
		for si in m.get_surface_count():
			var a := m.surface_get_arrays(si)
			var mat = mi.get_active_material(si)
			var c := Color(0.7, 0.7, 0.7)
			if mat is BaseMaterial3D:
				c = (mat as BaseMaterial3D).albedo_color
				if (mat as BaseMaterial3D).albedo_texture:
					c = c * _avg((mat as BaseMaterial3D).albedo_texture)
				# lamps and indicator strips glow at night
			var glowy := mat != null and (String(mat.resource_name).contains("Lamp") or String(mat.resource_name).contains("Indicator"))
			var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var ii = a[Mesh.ARRAY_INDEX]
			var base := verts.size()
			for k in vv.size():
				verts.append(xf * vv[k])
				norms.append((xf.basis * nn[k]).normalized() if nn.size() > k else Vector3.UP)
				cols.append(Color(c.r, c.g, c.b, 0.5 if glowy else 0.7))
			if ii == null or (ii as PackedInt32Array).is_empty():
				for k in vv.size():
					idx.append(base + k)
			else:
				for k in (ii as PackedInt32Array):
					idx.append(base + k)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out
