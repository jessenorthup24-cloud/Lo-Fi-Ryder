extends SceneTree
## Renders a contact sheet of baked Kenney meshes, each scaled to fit its cell, seen from the front:
##   xvfb-run -a godot --path . -s res://tools/look/kgrid.gd -- out.png k_sub_building-type-a,k_pets_animal-cow,...
## People ("k_chars_<name>_stand") get their arms; KARM=<radians> in the environment raises them.
const PAL := preload("res://scripts/core/palette.gd")
var frames := 0
var out := "/tmp/kgrid.png"
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	var names: PackedStringArray = a[1].split(",")
	var vp := get_root()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon.gdshader")
	mat.set_shader_parameter("palette", PAL.make_texture())
	mat.set_shader_parameter("haze", 0.0)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("cfc6f0")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b8b0e0")
	e.ambient_light_energy = 0.45
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 25, 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	vp.add_child(sun)
	var n := names.size()
	var cols := int(ceil(sqrt(n)))
	var sp := 1.6
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = load("res://assets/kenney/%s.res" % names[i])
		mi.material_override = mat
		var ab: AABB = mi.mesh.get_aabb()
		var s := 1.2 / maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
		mi.scale = Vector3.ONE * s
		mi.position = Vector3((i % cols) * sp, -ab.position.y * s - (i / cols) * 1.9, 0)
		vp.add_child(mi)
		if names[i].begins_with("k_chars_"):
			var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/kenney/kenney_meta.json"))
			var pv: Array = meta[names[i] + "_pivots"]
			for k in 2:
				var am := MeshInstance3D.new()
				am.mesh = load("res://assets/kenney/%s_%s.res" % [names[i], "al" if k == 0 else "ar"])
				am.material_override = mat
				am.position = Vector3(pv[k * 3], pv[k * 3 + 1], pv[k * 3 + 2])
				am.rotation.z = float(OS.get_environment("KARM")) * (1.0 if pv[k * 3] > 0 else -1.0) if OS.get_environment("KARM") != "" else 0.0
				mi.add_child(am)
		var l := Label3D.new()
		l.text = names[i].trim_prefix("k_")
		l.font_size = 22
		l.pixel_size = 0.004
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = Color.BLACK
		l.outline_size = 0
		l.position = mi.position + Vector3(0, -0.12, 0.5)
		vp.add_child(l)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = cols * sp * 1.05
	var c := Vector3((cols - 1) * sp * 0.5, 0.6 - (ceil(float(n) / cols) - 1) * 0.95, 0)
	cam.rotation_degrees = Vector3(-12, 200, 0)
	cam.position = c + cam.basis.z * 30.0
	vp.add_child(cam)
	cam.make_current()

func _process(_d: float) -> bool:
	frames += 1
	if frames == 6:
		get_root().get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false
