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
	[7.5, "ffe1c0", 0.70, "a6b4e6", 0.43, "8cc8ff", "ffe0c4", 0.0],
	[12.0, "fff4e0", 0.80, "a9bbe8", 0.41, "88cfff", "fde8cc", 0.0],
	[16.5, "ffe6c4", 0.74, "b0b4e2", 0.41, "8cc4ff", "ffdcbc", 0.0],
	[18.5, "ffa86e", 0.55, "c79cc8", 0.43, "7a7fd2", "ffb38e", 0.2],
	[20.0, "c7a0ff", 0.30, "6e6aac", 0.48, "3a3f86", "a477b0", 0.75],
	[21.5, "9fb6ff", 0.24, "56609c", 0.51, "1b2350", "394077", 1.0],
	[24.0, "9fb6ff", 0.24, "56609c", 0.51, "1b2350", "394077", 1.0],
]

var world: Node
var game: Node
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
var particle_root: Node3D
var far_root: Node3D
var leaf_mat: StandardMaterial3D
var far_mat: ShaderMaterial
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
	rain_p.position.y = 13.0
	snow_p.position.y = 11.0
	streak_p.position.y = 1.6
	leaf_p.position.y = 2.0
	# far layer
	far_root = Node3D.new()
	add_child(far_root)
	far_mat = ShaderMaterial.new()
	far_mat.shader = load("res://shaders/far.gdshader")
	far_mat.set_shader_parameter("palette", toon_mat.get_shader_parameter("palette"))
	for i in 14:
		var mi := MeshInstance3D.new()
		var kind := "far_cloud" if i < 10 else ("far_island" if i < 13 else "balloon")
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
	env.ambient_light_color = amb
	env.ambient_light_energy = amb_e
	env.background_color = bot
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("bottom_color", bot)
	sky_mat.set_shader_parameter("haze_color", bot.lightened(0.2))
	sky_mat.set_shader_parameter("stars", night * (1.0 - wet))
	sky_mat.set_shader_parameter("cloud_amount", 0.4 + wet * 0.5)
	sky_mat.set_shader_parameter("cloud_color", Color(1, 1, 1).lerp(Color("8a90b0"), night))
	var prog: float = target.x * world.F.x + target.z * world.F.z
	sky_mat.set_shader_parameter("scroll", Vector2(0, -prog * 0.004))
	var fog_col := bot.lightened(0.25).lerp(Color("e8ecf2").lerp(Color("50567a"), night), fog)
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
	far_mat.set_shader_parameter("season", season)
	far_mat.set_shader_parameter("night", night)
	far_mat.set_shader_parameter("haze_color", bot.lerp(top, 0.35))
	far_mat.set_shader_parameter("haze", 0.5 + wet * 0.3)
	_particles_update()

func _particles_update() -> void:
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
