extends Node3D
## The weather: clear, cloudy, rain, storms (rain, wind, lightning and thunder) and fog, with the season
## having its say (wetter in spring and autumn, misty mornings; in winter it snows instead of raining). It
## changes every few minutes and blends over half a minute or so. Rain darkens the sky, dims the sun and
## its shadows, thickens the air, falls as streaks round the camera, wets the roads (darker, and every car's
## tyres grip a little less while they're wet; they dry off after) and you hear it. Settings → Weather off
## keeps it fine.
##
## atmos.gd reads cloud, fog and flash each frame when it lights the sky (weather_mods).

const Car := preload("res://scripts/game/drift_car.gd")

## state -> [cloud, rain, fog, wind]
const STATES := {
	"clear": [0.0, 0.0, 0.0, 0.1],
	"cloudy": [0.65, 0.0, 0.1, 0.3],
	"rain": [0.85, 0.75, 0.25, 0.45],
	"storm": [1.0, 1.0, 0.35, 0.9],
	"fog": [0.45, 0.0, 1.0, 0.0],
}
## how likely each is, by season (spring, summer, autumn, winter)
const ODDS := [
	{"clear": 0.4, "cloudy": 0.25, "rain": 0.22, "storm": 0.05, "fog": 0.08},
	{"clear": 0.6, "cloudy": 0.2, "rain": 0.1, "storm": 0.07, "fog": 0.03},
	{"clear": 0.3, "cloudy": 0.27, "rain": 0.23, "storm": 0.08, "fog": 0.12},
	{"clear": 0.35, "cloudy": 0.3, "rain": 0.25, "storm": 0.02, "fog": 0.08},
]
const NAMES := {"clear": "", "cloudy": "Cloudy", "rain": "Rain", "storm": "Storm", "fog": "Fog"}

var game: Node
var state := "clear"
var cloud := 0.0
var rain := 0.0
var fog := 0.0
var wind := 0.0
var wet := 0.0               # the roads: 0 dry .. 1 soaked
var flash := 0.0             # lightning
var enabled := true
var _next := 200.0           # seconds till it changes
var _bolt := 8.0
var _thunder := -1.0
var _drops: CPUParticles3D
var _drop_mat: StandardMaterial3D
var _snowing := false
var _rain_snd: AudioStreamPlayer
var _wind_snd: AudioStreamPlayer
var _forced := false

func setup(g: Node) -> void:
	game = g
	_drops = CPUParticles3D.new()
	_drops.name = "Rain"
	_drops.local_coords = false
	_drops.emitting = false
	_drops.amount = 1100
	_drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drops.emission_box_extents = Vector3(24, 0.5, 24)
	_drop_mat = StandardMaterial3D.new()
	_drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_drop_mat.billboard_keep_scale = true
	_drop_mat.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.material = _drop_mat
	_drops.mesh = q
	add_child(_drops)
	_style_drops(false)
	_rain_snd = _loop("rain")
	_wind_snd = _loop("wind")
	if game.args.has("weather"):
		_forced = true
		set_now(String(game.args["weather"]))
	else:
		state = _pick()
		var w: Array = STATES[state]
		cloud = w[0]
		rain = w[1] * 0.6
		fog = w[2]
		wind = w[3]
		wet = rain
		_next = randf_range(150.0, 300.0)

func _loop(n: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	var s = game.sound._looped(n)
	p.stream = s
	p.volume_db = -80.0
	add_child(p)
	if s:
		p.play()
	return p

## Straight to this weather (tests: --weather=rain / storm / fog / cloudy / clear / snow).
func set_now(st: String) -> void:
	if st == "snow":
		st = "rain"
		game.atmos.set_season(3)
	if not STATES.has(st):
		st = "clear"
	state = st
	var w: Array = STATES[st]
	cloud = w[0]
	rain = w[1]
	fog = w[2]
	wind = w[3]
	wet = 1.0 if rain > 0.0 else 0.0

func _pick() -> String:
	var odds: Dictionary = ODDS[clampi(int(game.atmos.season), 0, 3)].duplicate()
	var h: float = game.atmos.hour
	if h > 4.5 and h < 9.0:
		odds["fog"] = float(odds["fog"]) * 3.0           # misty mornings
	var tot := 0.0
	for k in odds:
		tot += float(odds[k])
	var r := randf() * tot
	for k in odds:
		r -= float(odds[k])
		if r <= 0.0:
			return k
	return "clear"

## The name for the HUD ("" when it's fine).
func label() -> String:
	if not enabled or rain < 0.15 and fog < 0.5 and cloud < 0.4:
		return ""
	if rain > 0.15 and game.atmos.season == 3:
		return "Snow"
	return NAMES.get(state, "")

func tick(dt: float, cam: Camera3D) -> void:
	enabled = bool(game.save.setting("weather")) if game.save.data["settings"].has("weather") else true
	var target: Array = STATES[state] if enabled else STATES["clear"]
	if not _forced:
		_next -= dt
		if _next <= 0.0:
			_next = randf_range(180.0, 360.0)
			state = _pick()
	var k := 1.0 - exp(-dt / 12.0)          # (about half a minute to change over)
	cloud = lerpf(cloud, float(target[0]), k)
	rain = lerpf(rain, float(target[1]), k)
	fog = lerpf(fog, float(target[2]), k)
	wind = lerpf(wind, float(target[3]), k)
	# the roads get wet while it rains, and dry off (slower) after
	wet = move_toward(wet, 1.0 if rain > 0.3 else 0.0, dt / (40.0 if rain > 0.3 else 150.0))
	var snow: bool = game.atmos.season == 3
	Car.wet_k = 1.0 - (0.06 if snow else 0.14) * wet       # (every car's tyres)
	# lightning in a storm: a flash, and the thunder a moment after
	flash = maxf(0.0, flash - dt * 3.5)
	if state == "storm" and rain > 0.7 and enabled and not snow:
		_bolt -= dt
		if _bolt <= 0.0:
			_bolt = randf_range(6.0, 16.0)
			flash = 1.0
			_thunder = randf_range(0.6, 2.4)
	if _thunder > 0.0:
		_thunder -= dt
		if _thunder <= 0.0:
			game.sfx("crumble", -3.0, randf_range(0.35, 0.45))
			game.sfx("crash_heavy", -14.0, 0.4)
	# the rain (or snow) round the camera
	var falling := rain > 0.08 and bool(game.save.setting("motes") if game.save.data["settings"].has("motes") else true)
	if snow != _snowing:
		_style_drops(snow)
	_drops.emitting = falling
	# wet roads go darker (in winter the snow just settles a little)
	var rm: ShaderMaterial = game.island.road_mat if game.island else null
	if rm:
		rm.set_shader_parameter("tint", Color.WHITE.lerp(Color(0.95, 0.96, 1.0) if snow else Color(0.7, 0.72, 0.78), wet))
	if falling:
		_drop_mat.albedo_color.a = (0.85 if snow else 0.58) * clampf(rain * 1.3, 0.15, 1.0)
		var f := -cam.global_transform.basis.z
		var c := cam.global_position + Vector3(f.x, 0, f.z).normalized() * 10.0
		_drops.global_position = c + Vector3(0, 14.0 if not snow else 12.0, 0)
		_drops.direction = Vector3(wind * 0.25, -1.0, wind * 0.1).normalized()
	# and the sound of it
	var quiet: bool = game.state != game.DRIVE
	_rain_snd.volume_db = -80.0 if (quiet or snow or rain < 0.05) else lerpf(-26.0, -8.0, rain)
	_wind_snd.volume_db = -80.0 if (quiet or wind < 0.35) else lerpf(-30.0, -12.0, (wind - 0.35) / 0.65)

func _style_drops(snow: bool) -> void:
	_snowing = snow
	var q: QuadMesh = _drops.mesh
	if snow:
		q.size = Vector2(0.09, 0.09)
		_drop_mat.albedo_color = Color(1, 1, 1, 0.85)
		_drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_drops.lifetime = 4.0
		_drops.initial_velocity_min = 2.0
		_drops.initial_velocity_max = 3.2
		_drops.spread = 25.0
		_drops.gravity = Vector3.ZERO
	else:
		q.size = Vector2(0.025, 0.75)
		_drop_mat.albedo_color = Color(0.78, 0.84, 0.95, 0.42)
		_drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		_drops.lifetime = 0.75
		_drops.initial_velocity_min = 19.0
		_drops.initial_velocity_max = 23.0
		_drops.spread = 3.0
		_drops.gravity = Vector3.ZERO

## Pause, garage: the rain stops where it is, and goes quiet.
func hold(on: bool) -> void:
	_drops.speed_scale = 0.0 if on else 1.0
