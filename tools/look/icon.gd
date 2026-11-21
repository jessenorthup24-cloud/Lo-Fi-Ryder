extends SceneTree
## Renders the app icon layers: xvfb-run godot --path . -s res://tools/look/icon.gd -- out_dir
const M := preload("res://scripts/core/models.gd")
const PAL := preload("res://scripts/core/palette.gd")
const CARS := preload("res://scripts/game/cars.gd")
const MB := preload("res://scripts/core/mesh_builder.gd")
var frames := 0
var out := "/tmp"
var vp: SubViewport
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	vp = SubViewport.new()
	vp.size = Vector2i(864, 864)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon.gdshader")
	mat.set_shader_parameter("palette", PAL.make_texture())
	mat.set_shader_parameter("haze", 0.0)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b8b0e0")
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 25, 0)
	sun.light_energy = 0.7
	sun.light_color = Color("fff1dc")
	sun.shadow_enabled = true
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.6
	cam.rotation_degrees = Vector3(-32, 40, 0)
	cam.position = Vector3(0, 0.45, 0) + cam.basis.z * 20.0
	vp.add_child(cam)
	# little floating island
	var b := MB.new()
	b.cbox(Vector3(0, -0.15, 0), Vector3(2.9, 0.3, 2.9), 0.08, MB.pal(PAL.DIRT), Basis(), MB.pal(PAL.GRASS))
	b.cbox(Vector3(0, -0.6, 0), Vector3(2.5, 0.6, 2.5), 0.1, MB.pal(PAL.DIRT))
	b.cyl(Vector3(0, -1.25, 0), 1.0, 0.9, MB.pal(PAL.DIRT_DARK), 8, Basis(), 0.0, false, false)
	b.box(Vector3(0.0, 0.005, 0.0), Vector3(0.9, 0.02, 2.9), MB.pal(PAL.PATH))
	var isl := MeshInstance3D.new()
	isl.mesh = b.commit()
	isl.material_override = mat
	vp.add_child(isl)
	for p in [[Vector3(-0.95, 0, -0.95), "tree_round"], [Vector3(0.95, 0, -1.0), "pine"], [Vector3(-1.05, 0, 0.95), "flowers"], [Vector3(1.05, 0, 0.6), "bush"]]:
		var mi := MeshInstance3D.new()
		mi.mesh = M.get_mesh(p[1])
		mi.material_override = mat
		mi.position = p[0]
		mi.scale = Vector3.ONE * 0.8
		vp.add_child(mi)
	var c := M.car(CARS.LIST[1])
	var car := Node3D.new()
	car.rotation.y = deg_to_rad(40.0 + 180.0 - 38.0)
	car.scale = Vector3.ONE * 1.25
	var body := MeshInstance3D.new()
	body.mesh = c["body"]
	var bm: ShaderMaterial = mat.duplicate()
	var om := ShaderMaterial.new()
	om.shader = load("res://shaders/outline.gdshader")
	om.set_shader_parameter("width", 0.025)
	bm.next_pass = om
	body.material_override = bm
	body.position.y = c["ride"]
	car.add_child(body)
	for i in 4:
		var w := MeshInstance3D.new()
		w.mesh = c["wheel_f"] if i < 2 else c["wheel_r"]
		w.material_override = mat
		w.position = c["wheels"][i]
		car.add_child(w)
	vp.add_child(car)
func _process(_d: float) -> bool:
	frames += 1
	if frames == 10:
		var img := vp.get_texture().get_image()
		img.save_png(out + "/icon_fg_raw.png")
		print("icon saved")
		quit()
	return false
