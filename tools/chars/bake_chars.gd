extends SceneTree
## Bakes the Kenney Mini Characters 2.0 (CC0) into ready-to-use scenes: assets/chars/<name>.scn, each the
## rigged character with its animations (idle, walk, sprint, jump, fall, drive, die, holding-*-shoot...)
## and its colours baked into the vertices (the colormap texture sampled at each vertex, as the other Kenney
## models are: vertex alpha 0.7, the toon shader's "as painted" colours). The looping ones are set to loop.
## Accessories (glasses, sunglasses, mask) bake to plain meshes: assets/chars/acc_<name>.res.
##   SRC="/path/Models/GLB format" godot --headless --path . -s tools/chars/bake_chars.gd

const OUT := "res://assets/chars/"
const CHARS := ["character-male-a", "character-male-b", "character-male-c", "character-male-d", "character-male-e",
	"character-male-f", "character-male-g", "character-female-a", "character-female-b", "character-female-c",
	"character-female-d", "character-female-e", "character-female-f", "character-soldier", "character-worker",
	"character-raider", "character-robot", "character-alien", "character-knight", "character-zombie"]
const ACC := ["aid-glasses", "aid-sunglasses"]
const LOOPS := ["idle", "walk", "sprint", "drive", "fall", "crouch", "sit", "holding-right", "holding-left", "holding-both"]

var img: Image

func _init() -> void:
	var src := OS.get_environment("SRC")
	img = Image.load_from_file(src + "/Textures/colormap.png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for nm: String in CHARS:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(src + "/" + nm + ".glb", st) != OK:
			push_error("can't read " + nm)
			continue
		var root: Node = doc.generate_scene(st)
		_bake_meshes(root)
		for ap in root.find_children("*", "AnimationPlayer", true, false):
			var lib: AnimationLibrary = (ap as AnimationPlayer).get_animation_library("")
			for an in lib.get_animation_list():
				var a: Animation = lib.get_animation(an)
				a.loop_mode = Animation.LOOP_LINEAR if an in LOOPS else Animation.LOOP_NONE
		_own(root, root)
		var ps := PackedScene.new()
		ps.pack(root)
		var key: String = String(nm).trim_prefix("character-")
		ResourceSaver.save(ps, OUT + key + ".scn", ResourceSaver.FLAG_COMPRESS)
		print("BAKED ", key)
		root.free()
	for nm: String in ACC:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(src + "/" + nm + ".glb", st) != OK:
			continue
		var root: Node = doc.generate_scene(st)
		_bake_meshes(root)
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			ResourceSaver.save((mi as MeshInstance3D).mesh, OUT + "acc_" + nm.trim_prefix("aid-") + ".res", ResourceSaver.FLAG_COMPRESS)
			print("BAKED acc ", nm)
			break
		root.free()
	quit()

## (everything in the scene owned by its root, or packing leaves it out)
func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)

func _bake_meshes(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		var out := ArrayMesh.new()
		for si in m.get_surface_count():
			var a := m.surface_get_arrays(si)
			var uu = a[Mesh.ARRAY_TEX_UV]
			var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var cols := PackedColorArray()
			for k in vv.size():
				var c := Color.WHITE
				if uu != null and (uu as PackedVector2Array).size() > k:
					var uv: Vector2 = uu[k]
					c = img.get_pixel(clampi(int(fposmod(uv.x, 1.0) * img.get_width()), 0, img.get_width() - 1),
						clampi(int(fposmod(uv.y, 1.0) * img.get_height()), 0, img.get_height() - 1))
				cols.append(Color(c.r, c.g, c.b, 0.7))
			a[Mesh.ARRAY_COLOR] = cols
			a[Mesh.ARRAY_TEX_UV] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, m.surface_get_format(si) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS))
		(mi as MeshInstance3D).mesh = out
		(mi as MeshInstance3D).material_override = null
		for si in out.get_surface_count():
			(mi as MeshInstance3D).set_surface_override_material(si, null)
