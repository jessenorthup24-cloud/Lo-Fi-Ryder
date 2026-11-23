extends Node
## Sky, sun and time of day for the island. A day lasts 14 minutes; the season follows your calendar
## (and December brings the holiday decorations). Street lamps and windows light up after dusk.

const P := preload("res://scripts/core/palette.gd")

const DAY_LENGTH := 840.0     # seconds for 24 hours
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
	we.environment = env
	parent.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_blur = 0.6
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.4
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
	# the sun goes round once a day (the moon takes over at night, from the other side)
	var day := hour >= 5.5 and hour <= 19.8
	var t := (hour - 6.0) / 12.0
	var elev := sin(clampf(t, 0.0, 1.0) * PI) * 62.0 + 8.0
	var az := lerpf(-70.0, 250.0, clampf(t, 0.0, 1.0))
	if not day:
		var nt := fposmod(hour - 19.8, 24.0) / 9.7
		elev = sin(nt * PI) * 45.0 + 12.0
		az = lerpf(-60.0, 240.0, nt)
	sun.rotation_degrees = Vector3(-elev, az, 0)
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
