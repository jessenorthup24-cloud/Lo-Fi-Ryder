extends SceneTree
## Photographs a car before and after some knocks, to check how crash damage looks.
##   xvfb-run -a godot --path . -s res://tools/look/dent_look.gd -- out.png [car_id]
const PAL := preload("res://scripts/core/palette.gd")
const Car := preload("res://scripts/game/drift_car.gd")
const CARS := preload("res://scripts/game/cars.gd")
var frames := 0
var out := "/tmp/dent.png"
var cars: Array = []
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	var id := a[1] if a.size() > 1 else "bug"
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon.gdshader")
	mat.set_shader_parameter("palette", PAL.make_texture())
	var vp := get_root()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("d8d4cc")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("d0d4dc")
	e.ambient_light_energy = 0.5
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	vp.add_child(sun)
	for k in 2:
		var c: RigidBody3D = Car.new()
		vp.add_child(c)
		c.setup(CARS.by_id(id), mat, null)
		c.freeze = true
		c.position = Vector3(k * 6.0 - 3.0, 0, 0)
		c.rotation.y = 0.7
		cars.append(c)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.fov = 50
	cam.look_at_from_position(Vector3(0, 4.5, 9.5), Vector3(0, 0.8, 0))
func _process(_d: float) -> bool:
	frames += 1
	if frames == 1:
		get_root().get_camera_3d().look_at_from_position(Vector3(0, 4.5, 9.5), Vector3(0, 0.8, 0))
	if frames == 3:
		# the second car: a front corner hit, a side swipe and a rear knock
		var c: Node3D = cars[1]
		var xf := c.global_transform
		var l: float = c.info["length"]
		var w: float = c.info["width"]
		c.dent(xf * Vector3(-w * 0.4, 0.6, -l * 0.47), xf.basis * Vector3(0.3, 0, 1).normalized(), 14.0)
		c.dent(xf * Vector3(-w * 0.45, 0.7, 0.0), xf.basis * Vector3(1, 0, 0), 9.0)
		c.dent(xf * Vector3(w * 0.1, 0.6, l * 0.47), xf.basis * Vector3(0, 0, -1), 10.0)
	if frames == 8:
		get_root().get_texture().get_image().save_png(out)
		quit()
	return false
