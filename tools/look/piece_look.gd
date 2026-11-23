extends SceneTree
## Photographs one baked model from above, the side, the front and at an angle, on a grid of 1 m squares
## with a car for scale:
##   xvfb-run -a godot --path . -s res://tools/look/piece_look.gd -- out_prefix k_klyo_half_pipe [scale]
const PAL := preload("res://scripts/core/palette.gd")
const M := preload("res://scripts/core/models.gd")
const CARS := preload("res://scripts/game/cars.gd")
var frames := 0
var prefix := "/tmp/piece"
var cam: Camera3D
var shots := ["top", "side", "front", "iso"]
var ab: AABB

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	prefix = a[0]
	var sc := float(a[2]) if a.size() > 2 else 1.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon.gdshader")
	mat.set_shader_parameter("palette", PAL.make_texture())
	mat.set_shader_parameter("haze", 0.0)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("cfe3f0")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c8c8d0")
	e.ambient_light_energy = 0.5
	env.environment = e
	get_root().add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	get_root().add_child(sun)
	var mi := MeshInstance3D.new()
	mi.mesh = load("res://assets/kenney/%s.res" % a[1])
	mi.material_override = mat
	mi.scale = Vector3.ONE * sc
	get_root().add_child(mi)
	ab = mi.mesh.get_aabb()
	ab = AABB(ab.position * sc, ab.size * sc)
	# a 1 m grid (every 5th line darker) and axis marks: red +x, blue +z
	var g := ImmediateMesh.new()
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.vertex_color_use_as_albedo = true
	g.surface_begin(Mesh.PRIMITIVE_LINES, gm)
	for k in range(-30, 31):
		var c := Color(0.3, 0.3, 0.35) if k % 5 == 0 else Color(0.7, 0.72, 0.76)
		g.surface_set_color(c); g.surface_add_vertex(Vector3(k, 0.005, -30)); g.surface_set_color(c); g.surface_add_vertex(Vector3(k, 0.005, 30))
		g.surface_set_color(c); g.surface_add_vertex(Vector3(-30, 0.005, k)); g.surface_set_color(c); g.surface_add_vertex(Vector3(30, 0.005, k))
	g.surface_set_color(Color.RED); g.surface_add_vertex(Vector3(0, 0.02, 0)); g.surface_set_color(Color.RED); g.surface_add_vertex(Vector3(30, 0.02, 0))
	g.surface_set_color(Color.BLUE); g.surface_add_vertex(Vector3(0, 0.02, 0)); g.surface_set_color(Color.BLUE); g.surface_add_vertex(Vector3(0, 0.02, 30))
	g.surface_end()
	var gi := MeshInstance3D.new()
	gi.mesh = g
	get_root().add_child(gi)
	# a car beside it, nose to -z
	var info: Dictionary = M.car(CARS.LIST[0])
	var car := MeshInstance3D.new()
	car.mesh = info["body"]
	car.material_override = mat
	car.position = Vector3(ab.end.x + 3.0, 0, 0)
	get_root().add_child(car)
	cam = Camera3D.new()
	cam.far = 500.0
	get_root().add_child(cam)
	cam.make_current()
	print("aabb ", ab)

func _aim(v: String) -> void:
	var c := ab.get_center()
	var r := ab.size.length() * 0.75 + 3.0
	match v:
		"top":
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = maxf(ab.size.x, ab.size.z) * 1.3 + 4.0
			cam.position = c + Vector3(0, 60, 0.001)
			cam.look_at(c, Vector3(0, 0, -1))
		"side":
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = maxf(ab.size.y, ab.size.z) * 1.3 + 2.0
			cam.position = c + Vector3(60, 0, 0)
			cam.look_at(c, Vector3.UP)
		"front":
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = maxf(ab.size.y, ab.size.x) * 1.3 + 2.0
			cam.position = c + Vector3(0, 0, 60)
			cam.look_at(c, Vector3.UP)
		"iso":
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 55.0
			cam.position = c + Vector3(r * 0.8, r * 0.6, r * 0.8)
			cam.look_at(c, Vector3.UP)

func _process(_dt: float) -> bool:
	frames += 1
	if frames == 1:
		_aim(shots[0])
	if frames % 4 == 0:
		get_root().get_texture().get_image().save_png("%s_%s.png" % [prefix, shots[0]])
		shots.pop_front()
		if shots.is_empty():
			return true
		_aim(shots[0])
	return false
