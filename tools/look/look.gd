extends SceneTree
## Renders a test diorama to a PNG: xvfb-run godot --path . -s res://tools/look/look.gd -- /tmp/look.png
const M := preload("res://scripts/core/models.gd")
const PAL := preload("res://scripts/core/palette.gd")
const CARS := preload("res://scripts/game/cars.gd")
var frames := 0
var out := "/tmp/look.png"
var mat: ShaderMaterial
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	var root3 := Node3D.new()
	get_root().add_child(root3)
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/toon.gdshader")
	mat.set_shader_parameter("palette", PAL.make_texture())
	mat.set_shader_parameter("season", float(a[1]) if a.size() > 1 else 0.0)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("bfe3ff")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b8b0e0")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.25
	sun.light_color = Color("fff1dc")
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60
	root3.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 18
	cam.rotation_degrees = Vector3(-38, 45, 0)
	cam.position = Vector3(30, 36, 30) * 0.9
	cam.far = 200
	root3.add_child(cam)
	# tiles via multimesh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = M.get_mesh("tile")
	mm.instance_count = 100
	var k := 0
	for i in 10:
		for j in 10:
			var t := Transform3D(Basis(), Vector3((i - 5) * M.T, randf_range(-0.02, 0.02), (j - 5) * M.T))
			mm.set_instance_transform(k, t)
			var top := PAL.GRASS if (i + j) % 7 != 0 else PAL.PATH
			mm.set_instance_color(k, Color(1, 1, 1, 1))
			mm.set_instance_custom_data(k, Color(top / 255.0, PAL.DIRT / 255.0, randf(), 0))
			k += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	root3.add_child(mmi)
	var props := ["tree_round", "tree_blossom", "pine", "bush", "hay", "fence", "rock", "flowers", "barn", "windmill", "mushroom", "station", "ramp", "fuel", "coin", "lamp", "umbrella", "sandcastle", "cloud_puff", "crystal"]
	var idx := 0
	for nm in props:
		var mi := MeshInstance3D.new()
		mi.mesh = M.get_mesh(nm)
		mi.material_override = mat
		var x := (idx % 5) * 2.8 - 6
		var z := (idx / 5) * 2.8 - 6
		mi.position = Vector3(x, 0, z)
		if nm == "station": mi.position = Vector3(8, 0, 4)
		root3.add_child(mi)
		idx += 1
	for ci in 5:
		var d: Dictionary = CARS.LIST[ci * 3 + (1 if a.size() > 2 else 0)]
		var c := M.car(d)
		var car := Node3D.new()
		var body := MeshInstance3D.new()
		body.mesh = c["body"]
		body.material_override = mat
		body.position.y = c["ride"]
		car.add_child(body)
		for wi in 4:
			var w := MeshInstance3D.new()
			w.mesh = c["wheel_f"] if wi < 2 else c["wheel_r"]
			w.material_override = mat
			w.position = c["wheels"][wi]
			car.add_child(w)
		car.position = Vector3(-6 + ci * 2.2, 0, 7.5)
		car.rotation.y = 0.6
		root3.add_child(car)
func _process(_d: float) -> bool:
	frames += 1
	if frames == 8:
		var img := get_root().get_texture().get_image()
		img.save_png(out)
		print("saved ", out)
		quit()
	return false
