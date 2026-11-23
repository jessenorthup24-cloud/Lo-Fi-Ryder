extends SceneTree
## Builds the island and photographs it from a few spots:
##   xvfb-run -a godot --path . -s res://tools/look/island_look.gd -- out_prefix [season] [view,view...]
## Views: top (whole map), town, square, suburbs, castle, lake, farm, bowl, beach, harbour, skate, spawn

const PAL := preload("res://scripts/core/palette.gd")
const Island := preload("res://scripts/game/island.gd")

const VIEWS := {
	"top": [Vector3(0, 900, 0.1), Vector3(0, 0, 0), 75.0],
	"town": [Vector3(-20, 70, 150), Vector3(-110, 5, 30), 55.0],
	"square": [Vector3(-60, 18, 70), Vector3(-95, 3, 20), 60.0],
	"street": [Vector3(-235, 3.2, 61), Vector3(-150, 3, 60), 65.0],
	"suburbs": [Vector3(-130, 45, -40), Vector3(-200, 2, -130), 60.0],
	"castle": [Vector3(60, 55, -200), Vector3(-30, 30, -362), 55.0],
	"lake": [Vector3(200, 45, -160), Vector3(285, 2, -255), 60.0],
	"farm": [Vector3(180, 40, -80), Vector3(260, 2, 0), 60.0],
	"bowl": [Vector3(100, 45, 120), Vector3(175, 2, 205), 60.0],
	"beach": [Vector3(-60, 30, 300), Vector3(-60, 0, 410), 65.0],
	"harbour": [Vector3(-330, 30, 110), Vector3(-420, 1, 165), 60.0],
	"skate": [Vector3(85, 20, 80), Vector3(60, 1, 110), 60.0],
	"spawn": [Vector3(-262, 60, 20), Vector3(-262, 0, 61), 60.0],
	"carpark": [Vector3(-230, 40, 70), Vector3(-230, 0, 30), 55.0],
	"harbourtop": [Vector3(-420, 130, 162.1), Vector3(-420, 0, 162), 60.0],
	"bowltop": [Vector3(175, 150, 205.1), Vector3(175, 0, 205), 60.0],
	"j4": [Vector3(-140, 38, 0.1), Vector3(-140, 0, 0), 60.0],
	"jmain": [Vector3(-140, 38, 60.1), Vector3(-140, 0, 60), 60.0],
	"jt": [Vector3(-260, 38, 0.1), Vector3(-260, 0, 0), 60.0],
	"jring": [Vector3(-303, 45, 61.1), Vector3(-303, 0, 61), 60.0],
	"jcastle": [Vector3(-80, 45, -132.1), Vector3(-80, 0, -132), 60.0],
	"jmaple": [Vector3(-288, 45, -150.1), Vector3(-288, 0, -150), 60.0],
	"jstreet": [Vector3(-170, 9, 12), Vector3(-140, 0, 0), 60.0],
	"spawntop": [Vector3(-262, 140, 61.1), Vector3(-262, 0, 61), 60.0],
	"stunttop": [Vector3(-170, 170, 262.1), Vector3(-170, 0, 262), 60.0],
	"stunt": [Vector3(-110, 40, 190), Vector3(-175, 2, 265), 60.0],
	"stunt2": [Vector3(-235, 30, 330), Vector3(-170, 2, 250), 60.0],
	"stuntgate": [Vector3(-104, 6, 196), Vector3(-118, 4, 250), 60.0],
	"stuntloop": [Vector3(-146, 8, 262), Vector3(-114, 7, 256), 60.0],
	"stuntplat": [Vector3(-186, 9, 246), Vector3(-205, 3, 224), 62.0],
	"stuntpipe": [Vector3(-216, 7, 296), Vector3(-234, 1.5, 262), 60.0],
	"stuntair": [Vector3(-120, 7, 300), Vector3(-160, 6, 284), 60.0],
	"farmtrack": [Vector3(318, 6, 262), Vector3(298, 1, 236), 60.0],
	"fields": [Vector3(372, 10, 236), Vector3(320, 1, 190), 60.0],
	"fields2": [Vector3(220, 12, 130), Vector3(260, 1, 92), 60.0],
	"fieldnear": [Vector3(300, 4, 160), Vector3(320, 1, 185), 62.0],
	"wheat": [Vector3(232, 4, 60), Vector3(250, 1, 85), 62.0],
	"cabbage": [Vector3(312, 4, 60), Vector3(330, 1, 85), 62.0],
	"corn": [Vector3(240, 5, 150), Vector3(266, 1, 180), 62.0],
	"potato": [Vector3(366, 5, -78), Vector3(340, 1, -55), 62.0],
}

var frames := 0
var shots: Array = []
var prefix := "/tmp/isl"
var cam: Camera3D

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		prefix = a[0]
	var season := 1
	if a.size() > 1:
		season = int(a[1])
	var views: Array = VIEWS.keys()
	if a.size() > 2:
		views = Array(a[2].split(","))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon.gdshader")
	mat.set_shader_parameter("palette", PAL.make_texture())
	mat.set_shader_parameter("season", float(season) + 0.5)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("6fb6ff")
	sm.sky_horizon_color = Color("cfe8ff")
	sm.ground_horizon_color = Color("cfe8ff")
	sm.ground_bottom_color = Color("8fb0d0")
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c8d8ff")
	e.ambient_light_energy = 0.55
	e.fog_enabled = true
	e.fog_light_color = Color("cfe8ff")
	e.fog_density = 0.0016
	e.fog_sky_affect = 0.0
	env.environment = e
	get_root().add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	get_root().add_child(sun)
	var t0 := Time.get_ticks_msec()
	var isl: Node3D = Island.new()
	get_root().add_child(isl)
	isl.build(mat, season)
	print("island built in %d ms; children %d, breakables %d, anims %d, people %d" % [Time.get_ticks_msec() - t0,
		isl.get_child_count(), isl.breakables.size(), isl.anims.size(), isl.people.list.size()])
	var verts := 0
	for c in isl.get_children():
		if c is MeshInstance3D and c.mesh is ArrayMesh:
			for si in c.mesh.get_surface_count():
				verts += c.mesh.surface_get_array_len(si)
	print("static verts %d" % verts)
	cam = Camera3D.new()
	cam.far = 2500.0
	cam.near = 0.3
	cam.cull_mask = 0xFFFFF & ~Island.MAP_LAYER
	get_root().add_child(cam)
	cam.make_current()
	shots = views

func _aim(v: String) -> void:
	var d: Array = VIEWS[v]
	cam.position = d[0]
	cam.fov = d[2]
	cam.look_at(d[1], Vector3.UP if v != "top" else Vector3(0, 0, -1))

func _process(_dt: float) -> bool:
	frames += 1
	if shots.is_empty() or frames > 400:
		return true
	if frames == 1:
		_aim(shots[0])
	if frames % 4 == 0:
		var v: String = shots[0]
		get_root().get_texture().get_image().save_png("%s_%s.png" % [prefix, v])
		print("saved ", v)
		shots.pop_front()
		if shots.is_empty():
			return true
		_aim(shots[0])
	return false
