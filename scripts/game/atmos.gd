extends Node3D
## Time of day, seasons, weather, lighting, the sky backdrop and the far parallax layer.

const M := preload("res://scripts/core/models.gd")
const P := preload("res://scripts/core/palette.gd")

const DAY_LENGTH := 200.0       # seconds for a full day
const SEASON_LENGTH := 85.0     # seconds per season

# hour -> [sun color, sun energy, ambient color, ambient energy, sky top, sky bottom, night]
const KEYS := [
	[0.0, "9fb6ff", 0.24, "56609c", 0.51, "1b2350", "394077", 1.0],
	[4.5, "9fb6ff", 0.22, "5a62a0", 0.51, "222b5c", "4a4c86", 1.0],
	[6.0, "ffb59a", 0.41, "b393c6", 0.45, "7c86d8", "ffc2a6", 0.55],
	[7.5, "ffd2a0", 0.72, "a6b4e6", 0.43, "8cc8ff", "ffe0c4", 0.0],
	[12.0, "fff0d6", 0.80, "a9bbe8", 0.41, "88cfff", "fde8cc", 0.0],
	[16.5, "ffd29e", 0.76, "b0b4e2", 0.41, "8cc4ff", "ffdcbc", 0.0],
	[18.5, "ff9a58", 0.6, "c79cc8", 0.43, "7a7fd2", "ffb38e", 0.2],
	[20.0, "c7a0ff", 0.30, "6e6aac", 0.48, "3a3f86", "a477b0", 0.75],
	[21.5, "9fb6ff", 0.24, "56609c", 0.51, "1b2350", "394077", 1.0],
	[24.0, "9fb6ff", 0.24, "56609c", 0.51, "1b2350", "394077", 1.0],
]

# the abyss below: nebula aura colours per region [aura a, aura b, aura c]
const AURAS := {
	"countryside": ["3df2a6", "8a5cff", "ff9a6b"],
	"seaside": ["38d6ff", "ff5ab8", "9dffe6"],
	"forest": ["35e672", "6b3cf0", "ffb347"],
	"sky": ["ffcc55", "f04aa8", "b39bff"],
}

var world: Node
var game: Node
var aura := [Color("3df2a6"), Color("8a5cff"), Color("ff9a6b")]
var env: Environment
var sun: DirectionalLight3D
var sky_quad: MeshInstance3D
var sky_mat: ShaderMaterial
var cam: Camera3D
var mats: Array = []          # every toon material that needs season/night/fog params

var hour := 8.0
var day := 1
var season := 0.0
var season_idx := 0
var night := 0.0

# weather
var weather := "clear"
var weather_t := 0.0
var weather_dur := 30.0
var wint := 0.0                  # current intensity 0..1
var wtarget := 0.0
var rain := 0.0
var fog := 0.0
var snow := 0.0
var windy := 0.0
var gust := 0.0
var gust_t := 0.0
var gust_dir := 1.0
var wind_vec := Vector3.ZERO
var weather_enabled := false
var rng := RandomNumberGenerator.new()

var rain_p: CPUParticles3D
var snow_p: CPUParticles3D
var streak_p: CPUParticles3D
var leaf_p: CPUParticles3D
var mote_p: CPUParticles3D       # golden dust motes drifting in the light
var spore_p: CPUParticles3D      # pollen and seed fluff rising off the plants
var fly_p: CPUParticles3D        # fireflies at night
var petal_p: CPUParticles3D      # petals in spring
var wisp_p: CPUParticles3D       # glowing wisps rising out of the abyss
var glow_tex: GradientTexture2D
var vignette: ColorRect
var vig_mat: ShaderMaterial
var particle_root: Node3D
var far_root: Node3D
var leaf_mat: StandardMaterial3D
var far_mat: ShaderMaterial
var ground_mat: ShaderMaterial
var ground_plane: MeshInstance3D
var biome_w := Vector4(1, 0, 0, 0)
var far_items: Array = []
var last_target := Vector3.ZERO

func setup(w: Node, g: Node, camera: Camera3D, toon_mat: ShaderMaterial) -> void:
	world = w
	game = g
	cam = camera
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("fde8cc")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# soft bloom on glowing buds, lanterns, stars and auras
	env.glow_enabled = false   # (the compatibility renderer is LDR: bloom would wash out anything white)
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.8
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.4)
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 55.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	add_child(sun)
	# backdrop quad, parented to the camera far away
	sky_quad = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(80, 80)
	sky_quad.mesh = q
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_quad.material_override = sky_mat
	sky_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_quad.position = Vector3(0, 0, -cam.far + 4.0)
	cam.add_child(sky_quad)
	# particles follow the car
	particle_root = Node3D.new()
	add_child(particle_root)
	rain_p = _particles(480, _streak_mesh(Vector3(0.025, 0.55, 0.025), Color(0.82, 0.9, 1.0, 0.75)), Vector3(18, 0.5, 18), Vector3(0, -1, 0), 22.0, 26.0, 1.0, 0.0)
	snow_p = _particles(320, _flake_mesh(), Vector3(18, 0.5, 18), Vector3(0, -1, 0), 1.6, 2.4, 6.0, 0.6)
	streak_p = _particles(40, _streak_mesh(Vector3(1.6, 0.025, 0.025), Color(1, 1, 1, 0.55)), Vector3(16, 3, 16), Vector3(1, 0, 0), 9.0, 13.0, 1.4, 0.0)
	leaf_p = _particles(40, _leaf_mesh(), Vector3(16, 3, 16), Vector3(1, 0, 0), 4.0, 6.0, 2.6, 0.4)
	# a soft vignette tinted by the abyss
	var vl := CanvasLayer.new()
	vl.layer = -1
	add_child(vl)
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = "shader_type canvas_item;\nuniform vec4 edge : source_color = vec4(0.1, 0.05, 0.2, 0.5);\nvoid fragment() {\n\tvec2 d = (UV - 0.5) * vec2(1.0, 1.25);\n\tfloat k = smoothstep(0.38, 0.85, length(d));\n\tCOLOR = vec4(edge.rgb, edge.a * k);\n}\n"
	vig_mat = ShaderMaterial.new()
	vig_mat.shader = vs
	vignette.material = vig_mat
	vl.add_child(vignette)
	# ambient life: motes, spores, fireflies, petals and abyss wisps
	glow_tex = GradientTexture2D.new()
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(0.5, 0.0)
	glow_tex.width = 64
	glow_tex.height = 64
	var gg := Gradient.new()
	gg.set_color(0, Color(1, 1, 1, 1))
	gg.set_color(1, Color(1, 1, 1, 0))
	gg.add_point(0.25, Color(1, 1, 1, 0.75))
	glow_tex.gradient = gg
	mote_p = _glow_particles(70, 0.16, Vector3(13, 2.5, 13), Vector3(0.3, 0.25, 0.1), 0.15, 0.45, 7.0,
		[Color(1, 0.9, 0.6, 0.0), Color(1, 0.88, 0.55, 0.9), Color(1, 0.85, 0.5, 0.0)])
	mote_p.position.y = 2.2
	spore_p = _glow_particles(45, 0.12, Vector3(13, 0.6, 13), Vector3(0.1, 1.0, 0.0), 0.25, 0.6, 6.0,
		[Color(0.9, 1, 0.85, 0.0), Color(0.92, 1, 0.8, 0.95), Color(0.9, 1, 0.9, 0.0)])
	spore_p.position.y = 0.4
	fly_p = _glow_particles(50, 0.26, Vector3(12, 1.2, 12), Vector3(0.0, 0.3, 0.0), 0.1, 0.5, 5.0,
		[Color(0.8, 1, 0.4, 0.0), Color(0.85, 1, 0.45, 1.0), Color(0.8, 1, 0.4, 0.1), Color(0.85, 1, 0.45, 1.0), Color(0.8, 1, 0.4, 0.0)])
	fly_p.position.y = 0.9
	fly_p.angular_velocity_min = 0.0
	fly_p.angular_velocity_max = 0.0
	fly_p.gravity = Vector3(0, 0.05, 0)
	fly_p.spread = 180.0
	petal_p = _glow_particles(26, 0.16, Vector3(14, 3, 14), Vector3(0.6, -0.3, 0.2), 0.4, 0.8, 7.0,
		[Color(1, 0.75, 0.85, 0.0), Color(1, 0.72, 0.82, 0.95), Color(1, 0.8, 0.9, 0.0)])
	petal_p.position.y = 3.0
	wisp_p = _glow_particles(18, 0.9, Vector3(20, 1.0, 20), Vector3(0, 1, 0), 1.2, 2.0, 9.0,
		[Color(0.6, 0.8, 1, 0.0), Color(0.7, 0.85, 1, 0.55), Color(0.8, 0.7, 1, 0.0)])
	wisp_p.position.y = -14.0
	rain_p.position.y = 13.0
	snow_p.position.y = 11.0
	streak_p.position.y = 1.6
	leaf_p.position.y = 2.0
	# far layer
	far_root = Node3D.new()
	add_child(far_root)
	ground_plane = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	ground_plane.mesh = pm
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = load("res://shaders/far_ground.gdshader")
	ground_mat.set_shader_parameter("palette", toon_mat.get_shader_parameter("palette"))
	ground_plane.material_override = ground_mat
	ground_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground_plane)
	far_mat = ShaderMaterial.new()
	far_mat.shader = load("res://shaders/far.gdshader")
	far_mat.set_shader_parameter("palette", toon_mat.get_shader_parameter("palette"))
	for i in 5:
		var mi := MeshInstance3D.new()
		var kind := "far_island"
		mi.mesh = M.get_mesh(kind)
		mi.material_override = far_mat if kind != "balloon" else toon_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far_root.add_child(mi)
		far_items.append({"node": mi, "kind": kind, "depth": 0.0})
	mats.append(toon_mat)

func add_material(m: ShaderMaterial) -> void:
	if not mats.has(m):
		mats.append(m)

func remove_material(m: ShaderMaterial) -> void:
	mats.erase(m)

func _particles(amount: int, mesh: Mesh, box: Vector3, dir: Vector3, vmin: float, vmax: float, life: float, spread_rot: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.mesh = mesh
	p.lifetime = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.direction = dir
	p.spread = 4.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if spread_rot > 0.0:
		p.angular_velocity_min = -180.0
		p.angular_velocity_max = 180.0
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.particle_flag_rotate_y = true
	particle_root.add_child(p)
	return p

## Soft glowing billboard particles that fade in and out over their life (colors: the ramp).
func _glow_particles(amount: int, size: float, box: Vector3, dir: Vector3, vmin: float, vmax: float, life: float, ramp: Array) -> CPUParticles3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = glow_tex
	m.no_depth_test = false
	m.disable_receive_shadows = true
	q.material = m
	var p := _particles(amount, q, box, dir, vmin, vmax, life, 0.0)
	p.spread = 35.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, ramp[0])
	g.set_color(1, ramp[ramp.size() - 1])
	for i in range(1, ramp.size() - 1):
		g.add_point(float(i) / float(ramp.size() - 1), ramp[i])
	p.color_ramp = g
	p.preprocess = life
	return p

func _unshaded(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if col.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	return m

func _streak_mesh(size: Vector3, col: Color) -> Mesh:
	var b := BoxMesh.new()
	b.size = size
	b.material = _unshaded(col)
	return b

func _flake_mesh() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 0.07
	s.height = 0.14
	s.radial_segments = 6
	s.rings = 3
	s.material = _unshaded(Color(1, 1, 1, 0.95))
	return s

func _leaf_mesh() -> Mesh:
	var b := BoxMesh.new()
	b.size = Vector3(0.18, 0.02, 0.12)
	leaf_mat = _unshaded(Color("f08b3a"))
	b.material = leaf_mat
	return b

func reset(seed_in: int, start_season: int) -> void:
	rng.seed = seed_in + 77
	hour = 8.0
	day = 1
	season = float(start_season)
	season_idx = start_season
	weather = "clear"
	weather_t = 0.0
	weather_dur = rng.randf_range(24.0, 34.0)
	wint = 0.0
	wtarget = 0.0
	rain = 0.0; fog = 0.0; snow = 0.0; windy = 0.0; gust = 0.0
	wind_vec = Vector3.ZERO
	weather_enabled = false
	world.winter_ice = false
	for p in [rain_p, snow_p, streak_p, leaf_p]:
		p.emitting = false
	for p in [mote_p, spore_p, wisp_p]:
		p.emitting = true
	_place_far(Vector3.ZERO, true)
	apply(Vector3.ZERO, 0.0)

func _place_far(target: Vector3, all: bool) -> void:
	for it in far_items:
		var n: MeshInstance3D = it["node"]
		if all or it["depth"] == 0.0:
			var ahead := rng.randf_range(-28.0, 40.0) if all else rng.randf_range(34.0, 46.0)
			it["depth"] = rng.randf_range(18.0, 34.0) if it["kind"] != "balloon" else rng.randf_range(2.0, 7.0)
			var lat := rng.randf_range(-22.0, 22.0)
			n.position = target + world.F * ahead + world.S * lat + Vector3(0, -it["depth"], 0)
			var sc := rng.randf_range(0.9, 1.8)
			if it["kind"] == "balloon":
				sc = rng.randf_range(0.5, 0.7)
				n.position.y = rng.randf_range(4.0, 9.0)
				n.position += world.S * signf(lat) * 6.0
			n.scale = Vector3.ONE * sc
			n.rotation.y = rng.randf() * TAU

## Advance time and weather. `running` is false on menus (time still drifts, slower).
func tick(dt: float, target: Vector3, running: bool) -> void:
	var rate := 1.0 if running else 0.25
	var prev_hour := hour
	hour = fposmod(hour + dt * rate * 24.0 / DAY_LENGTH, 24.0)
	if prev_hour < 6.0 and hour >= 6.0:
		day += 1
		if running:
			game.atmos_event("day", {"day": day})
	if running:
		season += dt / SEASON_LENGTH
		var si := int(floor(fposmod(season + 0.2, 4.0)))
		if si != season_idx:
			season_idx = si
			game.atmos_event("season", {"season": si})
		_weather(dt)
	else:
		wtarget = 0.0
		wint = move_toward(wint, 0.0, dt * 0.5)
	# far layer drifts with the camera at 80% speed: depth without perspective
	var delta := target - last_target
	if delta.length() > 30.0:
		_place_far(target, true)
		delta = Vector3.ZERO
	last_target = target
	for it in far_items:
		var n: MeshInstance3D = it["node"]
		var k := 0.8 if it["kind"] != "balloon" else 0.0
		n.position += Vector3(delta.x, 0, delta.z) * k
		n.position += world.S * dt * 0.25
		if it["kind"] == "balloon":
			n.position.y += sin(Time.get_ticks_msec() * 0.0005 + n.position.x) * dt * 0.2
		var rel := n.position - target
		var along: float = rel.x * world.F.x + rel.z * world.F.z
		if along < -30.0 or absf(rel.x * world.S.x + rel.z * world.S.z) > 34.0:
			it["depth"] = 0.0
	_place_far(target, false)
	particle_root.position = target
	apply(target, dt)

func _weather(dt: float) -> void:
	weather_t += dt
	if not weather_enabled:
		weather_t = 0.0
		return
	if weather_t > weather_dur:
		weather_t = 0.0
		if weather == "clear":
			weather = _pick_weather()
			weather_dur = rng.randf_range(18.0, 30.0)
			wtarget = rng.randf_range(0.7, 1.0)
			gust_dir = 1.0 if rng.randf() < 0.5 else -1.0
			game.atmos_event("weather", {"weather": weather})
		else:
			weather = "clear"
			weather_dur = rng.randf_range(24.0, 44.0) * (1.3 if season_idx == 1 else 1.0)
			wtarget = 0.0
			game.atmos_event("weather", {"weather": "clear"})
	# ease in and out; the event's type holds while it fades
	if weather != "clear":
		wint = move_toward(wint, wtarget, dt * 0.25)
	else:
		wint = move_toward(wint, 0.0, dt * 0.2)
	var want := {"rain": 0.0, "fog": 0.0, "snow": 0.0, "wind": 0.0}
	if weather != "clear":
		want[weather] = wint
	rain = move_toward(rain, want["rain"], dt * 0.3)
	fog = move_toward(fog, want["fog"], dt * 0.25)
	snow = move_toward(snow, want["snow"], dt * 0.3)
	windy = move_toward(windy, want["wind"], dt * 0.35)
	# gusts
	gust_t -= dt
	if gust_t <= 0.0:
		gust_t = rng.randf_range(2.6, 4.6)
		if windy > 0.3:
			game.atmos_event("gust", {"dir": gust_dir})
	var phase := 1.0 - gust_t / 3.6
	gust = smoothstep(0.0, 0.25, phase) * (1.0 - smoothstep(0.55, 0.9, phase))
	world.winter_ice = snow > 0.3

func _pick_weather() -> String:
	var table: Dictionary
	match season_idx:
		0: table = {"rain": 0.5, "wind": 0.25, "fog": 0.25}
		1: table = {"wind": 0.5, "rain": 0.3, "fog": 0.2}
		2: table = {"wind": 0.4, "fog": 0.35, "rain": 0.25}
		_: table = {"snow": 0.65, "fog": 0.2, "wind": 0.15}
	var r := rng.randf()
	for k in table:
		r -= table[k]
		if r <= 0.0:
			return k
	return table.keys()[0]

func _key_at(h: float) -> Array:
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if h >= a[0] and h <= b[0]:
			var t := smoothstep(0.0, 1.0, (h - a[0]) / maxf(0.001, b[0] - a[0]))
			return [Color(a[1]).lerp(Color(b[1]), t), lerpf(a[2], b[2], t), Color(a[3]).lerp(Color(b[3]), t), lerpf(a[4], b[4], t),
				Color(a[5]).lerp(Color(b[5]), t), Color(a[6]).lerp(Color(b[6]), t), lerpf(a[7], b[7], t)]
	var k: Array = KEYS[0]
	return [Color(k[1]), k[2], Color(k[3]), k[4], Color(k[5]), Color(k[6]), k[7]]

func apply(target: Vector3, dt: float) -> void:
	var k := _key_at(hour)
	var sun_col: Color = k[0]
	var sun_e: float = k[1]
	var amb: Color = k[2]
	var amb_e: float = k[3]
	var top: Color = k[4]
	var bot: Color = k[5]
	night = k[6]
	var grey := Color("a9b1bf").lerp(Color("3c4260"), night)
	var wet := maxf(rain, fog * 0.8)
	sun_e *= 1.0 - rain * 0.45 - fog * 0.3 - snow * 0.15
	amb = amb.lerp(Color("c4cad6").lerp(Color("56609c"), night), maxf(rain * 0.5, snow * 0.4))
	amb_e += (snow * 0.12 + fog * 0.1) * (1.0 - night * 0.7)
	top = top.lerp(grey, wet * 0.75).lerp(Color("dfe6f0").lerp(Color("5a6078"), night), snow * 0.5)
	bot = bot.lerp(grey.lightened(0.15), wet * 0.7).lerp(Color("f2f5fa").lerp(Color("6a7090"), night), snow * 0.5)
	# the sun swings across the sky; the moon takes over at night
	var day_k := clampf((hour - 5.5) / 15.0, 0.0, 1.0)
	var elev := 30.0 + sin(day_k * PI) * 32.0
	var az := lerpf(70.0, -10.0, day_k)
	if night > 0.6:
		elev = 48.0
		az = 20.0
	sun.rotation_degrees = Vector3(-elev, az, 0)
	sun.light_color = sun_col
	sun.light_energy = sun_e
	sun.shadow_opacity = clampf(0.85 - wet * 0.5 - night * 0.3, 0.2, 0.85)
	# the galaxy abyss: region auras drift in, the void deepens at night
	var prog: float = target.x * world.F.x + target.z * world.F.z
	var b: String = world.biome_at(prog)
	var want_aura: Array = AURAS.get(b, AURAS["countryside"])
	var ak := clampf(dt * 0.5, 0.0, 1.0) if dt > 0.0 else 1.0
	for i in 3:
		aura[i] = (aura[i] as Color).lerp(Color(want_aura[i]), ak)
	var deep := Color("1d1246").lerp(Color("0a0618"), night).lerp(Color("2a2a3a"), wet * 0.4)
	var aura_amt := lerpf(0.9, 1.25, night) * (1.0 - wet * 0.45)
	var star_amt := lerpf(0.45, 1.1, night) * (1.0 - wet * 0.7)
	for m2 in [sky_mat, ground_mat]:
		m2.set_shader_parameter("deep_color", deep)
		m2.set_shader_parameter("aura_a", aura[0])
		m2.set_shader_parameter("aura_b", aura[1])
		m2.set_shader_parameter("aura_c", aura[2])
		m2.set_shader_parameter("aura_amount", aura_amt)
		m2.set_shader_parameter("star_amount", star_amt)
	sky_mat.set_shader_parameter("scroll", Vector2(0, -prog * 0.004))
	sky_mat.set_shader_parameter("sun_glow", sun_col)
	sky_mat.set_shader_parameter("sun_amount", (1.0 - night) * (1.0 - wet * 0.8))
	var abyss := deep.lerp(aura[1], 0.18)
	# a touch of the aura in the shadows
	amb = amb.lerp((aura[1] as Color).lerp(aura[0], 0.3), 0.22)
	env.ambient_light_color = amb
	env.ambient_light_energy = amb_e
	env.background_color = deep
	var fog_col := Color("b9b0d8").lerp(Color("3a3560"), night).lerp(abyss.lightened(0.3), 0.3)
	var rim_col := (aura[0] as Color).lerp(aura[1], 0.4)
	var ve := deep.lerp(aura[1], 0.35)
	vig_mat.set_shader_parameter("edge", Color(ve.r, ve.g, ve.b, lerpf(0.38, 0.6, night)))
	wind_vec = world.S * gust_dir * windy * (0.35 + gust * 0.65) * 6.5
	for m in mats:
		m.set_shader_parameter("season", season)
		m.set_shader_parameter("night", night)
		m.set_shader_parameter("fog_color", fog_col)
		m.set_shader_parameter("fog_amount", fog * 0.92 + snow * 0.25 + rain * 0.2)
		m.set_shader_parameter("fog_origin", target)
		m.set_shader_parameter("fog_start", lerpf(14.0, 2.0, fog))
		m.set_shader_parameter("fog_len", lerpf(22.0, 12.0, fog))
		m.set_shader_parameter("wind", Vector2(wind_vec.x, wind_vec.z) * 0.06)
		m.set_shader_parameter("abyss_color", abyss)
		m.set_shader_parameter("moss_color", P.color(P.MOSS, season).darkened(0.08))
		m.set_shader_parameter("rim_color", rim_col)
	far_mat.set_shader_parameter("season", season)
	far_mat.set_shader_parameter("night", night)
	far_mat.set_shader_parameter("haze_color", abyss)
	far_mat.set_shader_parameter("haze", 0.62 + wet * 0.2)
	# the abyss plane follows the camera; its layers slide slower (depth without perspective)
	ground_plane.position = Vector3(target.x, -38.0, target.z)
	ground_mat.set_shader_parameter("cam_xz", Vector2(target.x, target.z))
	_particles_update()

func _particles_update() -> void:
	var dry := rain < 0.3 and snow < 0.3
	mote_p.emitting = night < 0.5 and dry
	spore_p.emitting = dry and season_idx != 3
	fly_p.emitting = night > 0.5 and dry and season_idx != 3
	petal_p.emitting = season_idx == 0 and dry
	wisp_p.emitting = true
	if wisp_p.color_ramp != null:
		var c0: Color = (aura[0] as Color).lerp(aura[2], 0.5)
		wisp_p.color_ramp.set_color(1, Color(c0.r, c0.g, c0.b, 0.5))
	rain_p.emitting = rain > 0.05
	snow_p.emitting = snow > 0.05
	var wdir: Vector3 = world.S * gust_dir
	snow_p.direction = (Vector3(0, -1, 0) + wdir * windy * 0.6).normalized()
	streak_p.emitting = windy > 0.15
	streak_p.direction = wdir
	leaf_p.emitting = windy > 0.2 and (season_idx == 2 or season_idx == 0)
	leaf_p.direction = (wdir + Vector3(0, 0.15, 0)).normalized()
	var leaf_col := Color("f08b3a") if season_idx == 2 else Color("f7b9cb")
	leaf_mat.albedo_color = leaf_col

## Testing: start with a weather event already at full strength.
func force_weather(w: String) -> void:
	weather = w
	weather_dur = 999.0
	wtarget = 1.0
	wint = 1.0
	weather_enabled = true
	match w:
		"rain": rain = 1.0
		"fog": fog = 1.0
		"snow": snow = 1.0
		"wind": windy = 1.0
	world.winter_ice = snow > 0.3

func season_name() -> String:
	return P.SEASON_NAMES[season_idx]

func is_night() -> bool:
	return night > 0.6
