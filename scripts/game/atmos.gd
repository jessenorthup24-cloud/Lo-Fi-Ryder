extends Node
## Sky, sun and time of day for the island. A day lasts 14 minutes; the season follows your calendar
## (and December brings the holiday decorations). Street lamps and windows light up after dusk.

const P := preload("res://scripts/core/palette.gd")

const DAY_LENGTH := 840.0     # seconds for 24 hours
const SUN_STEPS := 60.0        # the sun's direction changes this many times a game hour
# time of day keys: hour, sky top, horizon, sun colour, sun energy, ambient colour, ambient energy
const KEYS := [
	[0.0, "0b1433", "26365f", "9fb4ff", 0.18, "5a6aa8", 0.55],
	[5.0, "15204a", "3b4a7a", "9fb4ff", 0.2, "6070aa", 0.55],
	[6.5, "6d8fd6", "ffbf96", "ffc08a", 0.62, "c2a8c8", 0.5],
	[8.5, "5d9fe8", "d4e2f2", "fff0d8", 0.98, "cfd6e2", 0.5],
	[12.0, "5599e8", "d8e6f6", "fffaf0", 1.02, "d2d9e4", 0.5],
	[16.5, "5f9ce0", "dae3f2", "fff0da", 0.96, "d0d4e0", 0.5],
	[18.5, "6a70c9", "ffa37f", "ffae78", 0.62, "c9a2b4", 0.5],
	[19.6, "3a3f88", "c47a8e", "c0a0ff", 0.3, "7f74a8", 0.52],
	[21.0, "121a40", "2e3b6b", "9fb4ff", 0.18, "5a6aa8", 0.55],
	[24.0, "0b1433", "26365f", "9fb4ff", 0.18, "5a6aa8", 0.55],
]

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var hour := 9.5
var running := true
var season := 1
var night := 0.0
var mats: Array = []
var sea: ShaderMaterial

func setup(parent: Node, toon: ShaderMaterial) -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 18.0
	sky_mat.sky_curve = 0.12
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_density = 0.00105
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# bloom: bright things (lit windows, lamps, the sun on white walls, neon) bleed a soft glow
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.82
	env.glow_hdr_scale = 1.4
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for lv in 7:
		env.set_glow_level(lv, lv in [1, 2, 3, 4])
	we.environment = env
	parent.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 110.0     # (fading out at the far end, not stopping on a line)
	sun.directional_shadow_blend_splits = true      # (no line where the near, sharper shadows hand over)
	sun.shadow_blur = 0.8
	# enough bias that a surface never shadows itself (the speckled "acne" on a car's bonnet with the sun
	# low), not so much that shadows lift off the ground
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.2
	parent.add_child(sun)
	mats.append(toon)
	set_season(season_now())
	_apply()

## The island's season from the real date: Dec-Feb winter, Mar-May spring, Jun-Aug summer, Sep-Nov autumn.
static func season_now() -> int:
	var m := int(Time.get_date_dict_from_system()["month"])
	if m == 12 or m <= 2:
		return 3
	if m <= 5:
		return 0
	if m <= 8:
		return 1
	return 2

func set_season(s: int) -> void:
	season = s
	for m in mats:
		m.set_shader_parameter("season", float(s) + 0.5)

# ---- a few things in the air round the camera: pollen by day, leaves in autumn, snow in winter, fireflies at night
var motes: CPUParticles3D
var mote_mode := ""

func _make_motes(mode: String) -> void:
	if motes:
		motes.queue_free()
	mote_mode = mode
	motes = CPUParticles3D.new()
	motes.name = "Motes"
	motes.local_coords = false
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.disable_receive_shadows = true
	var q := QuadMesh.new()
	var ramp := Gradient.new()
	match mode:
		"pollen":
			motes.amount = 70
			motes.lifetime = 8.0
			motes.emission_box_extents = Vector3(26, 5, 26)
			motes.direction = Vector3(1, 0.2, 0.3)
			motes.spread = 180.0
			motes.gravity = Vector3(0, 0.02, 0)
			motes.initial_velocity_min = 0.1
			motes.initial_velocity_max = 0.5
			q.size = Vector2(0.06, 0.06)
			motes.color = Color(1.0, 0.97, 0.85)
			ramp.set_color(0, Color(1, 1, 1, 0))
			ramp.add_point(0.2, Color(1, 1, 1, 0.75))
			ramp.add_point(0.8, Color(1, 1, 1, 0.75))
			ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
		"leaves":
			motes.amount = 50
			motes.lifetime = 7.0
			motes.emission_box_extents = Vector3(26, 2, 26)
			motes.direction = Vector3(0.4, -1, 0.2)
			motes.spread = 25.0
			motes.gravity = Vector3(0.3, -0.25, 0.1)
			motes.initial_velocity_min = 0.6
			motes.initial_velocity_max = 1.2
			motes.angular_velocity_min = -160.0
			motes.angular_velocity_max = 160.0
			motes.angle_max = 360.0
			q.size = Vector2(0.2, 0.13)
			var cr := Gradient.new()
			cr.set_color(0, Color("e8742c"))
			cr.add_point(0.5, Color("d84a2a"))
			cr.set_color(cr.get_point_count() - 1, Color("e6b13a"))
			motes.color_initial_ramp = cr
			ramp.set_color(0, Color(1, 1, 1, 0))
			ramp.add_point(0.1, Color(1, 1, 1, 1))
			ramp.add_point(0.85, Color(1, 1, 1, 1))
			ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
		"snow":
			motes.amount = 160
			motes.lifetime = 5.0
			motes.emission_box_extents = Vector3(24, 1, 24)
			motes.direction = Vector3(0.2, -1, 0.1)
			motes.spread = 12.0
			motes.gravity = Vector3(0, -0.4, 0)
			motes.initial_velocity_min = 1.0
			motes.initial_velocity_max = 1.8
			q.size = Vector2(0.08, 0.08)
			motes.color = Color(1, 1, 1)
			ramp.set_color(0, Color(1, 1, 1, 0))
			ramp.add_point(0.1, Color(1, 1, 1, 0.9))
			ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.9))
		"fireflies":
			motes.amount = 60
			motes.lifetime = 6.0
			motes.emission_box_extents = Vector3(24, 1.2, 24)
			motes.direction = Vector3(0, 1, 0)
			motes.spread = 180.0
			motes.gravity = Vector3.ZERO
			motes.initial_velocity_min = 0.1
			motes.initial_velocity_max = 0.4
			q.size = Vector2(0.15, 0.15)
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			motes.color = Color(0.85, 1.0, 0.45)
			# (blinking on and off as they drift)
			ramp.set_color(0, Color(1, 1, 1, 0))
			for k in range(1, 6):
				ramp.add_point(k / 6.0 - 0.06, Color(1, 1, 1, 0.05))
				ramp.add_point(k / 6.0, Color(1, 1, 1, 1))
			ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	motes.color_ramp = ramp
	q.material = m
	motes.mesh = q
	motes.preprocess = motes.lifetime
	add_child(motes)

## Keep the things in the air round the camera (and the right ones for the time and the season).
func motes_tick(cam_pos: Vector3, cam_fwd: Vector3, on: bool) -> void:
	var want := ""
	if on:
		if season == 3:
			want = "snow"
		elif night > 0.6:
			want = "fireflies"
		elif night < 0.3:
			want = "leaves" if season == 2 else "pollen"
		else:
			want = mote_mode if mote_mode != "" else "pollen"
	if want != mote_mode:
		if want == "":
			if motes:
				motes.queue_free()
				motes = null
			mote_mode = ""
		else:
			_make_motes(want)
	if motes:
		var c := cam_pos + Vector3(cam_fwd.x, 0, cam_fwd.z).normalized() * 14.0
		motes.global_position = c + Vector3(0, 2.5 if mote_mode != "snow" else 9.0, 0) - (Vector3(0, 1.3, 0) if mote_mode == "fireflies" else Vector3.ZERO)

func add_material(m: ShaderMaterial) -> void:
	mats.append(m)
	m.set_shader_parameter("season", float(season) + 0.5)

func tick(dt: float) -> void:
	if running:
		hour = fposmod(hour + dt * 24.0 / DAY_LENGTH, 24.0)
	_apply()

func _key(h: float) -> Array:
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if h >= a[0] and h <= b[0]:
			var t := smoothstep(0.0, 1.0, (h - a[0]) / maxf(b[0] - a[0], 0.001))
			return [Color(a[1]).lerp(Color(b[1]), t), Color(a[2]).lerp(Color(b[2]), t), Color(a[3]).lerp(Color(b[3]), t),
				lerpf(a[4], b[4], t), Color(a[5]).lerp(Color(b[5]), t), lerpf(a[6], b[6], t)]
	return [Color(KEYS[0][1]), Color(KEYS[0][2]), Color(KEYS[0][3]), KEYS[0][4], Color(KEYS[0][5]), KEYS[0][6]]

func _apply() -> void:
	var k := _key(hour)
	sky_mat.sky_top_color = k[0]
	sky_mat.sky_horizon_color = k[1]
	sky_mat.ground_horizon_color = k[1]
	sky_mat.ground_bottom_color = (k[1] as Color).darkened(0.3)
	sky_mat.sun_angle_max = 18.0
	env.fog_light_color = (k[1] as Color).lerp(k[0], 0.25)
	env.ambient_light_color = k[4]
	env.ambient_light_energy = k[5]
	# the sun goes round once a day (the moon takes over at night, from the other side). It moves in small steps
	# (a game minute, about every half second) rather than smoothly: a light that turns a little every frame
	# makes the shadow map re-sample every frame, and the edges of every building's shadow shimmer
	var hq := floorf(hour * SUN_STEPS) / SUN_STEPS
	var day := hq >= 5.5 and hq <= 19.8
	var t := (hq - 6.0) / 12.0
	var elev := sin(clampf(t, 0.0, 1.0) * PI) * 62.0 + 8.0
	var az := lerpf(-70.0, 250.0, clampf(t, 0.0, 1.0))
	if not day:
		var nt := fposmod(hq - 19.8, 24.0) / 9.7
		elev = sin(nt * PI) * 45.0 + 12.0
		az = lerpf(-60.0, 240.0, nt)
	sun.rotation_degrees = Vector3(-elev, az, 0)
	# with the sun (or the moon) low, shadows are long and grazing, and that's when they turn speckled and
	# patchy: they fade back as it gets low, rather than glitch
	sun.shadow_opacity = clampf((elev - 6.0) / 16.0, 0.35, 1.0)
	sun.light_color = k[2]
	sun.light_energy = k[3]
	night = clampf(1.0 - smoothstep(0.2, 0.55, float(k[3])), 0.0, 1.0)
	for m in mats:
		m.set_shader_parameter("night", night)
		m.set_shader_parameter("rim_color", (k[1] as Color).lerp(Color.WHITE, 0.3))
	if sea:
		sea.set_shader_parameter("night", night)

func is_night() -> bool:
	return night > 0.5

func clock_text() -> String:
	var h := int(hour)
	var m := int((hour - h) * 60.0)
	return "%d:%02d" % [h, m]
