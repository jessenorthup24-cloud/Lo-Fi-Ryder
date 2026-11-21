extends Node3D
## Lo-Fi Ryder: wires everything together and runs the game loop.

const PAL := preload("res://scripts/core/palette.gd")
const M := preload("res://scripts/core/models.gd")
const World := preload("res://scripts/game/world.gd")
const Car := preload("res://scripts/game/car.gd")
const Fx := preload("res://scripts/game/fx.gd")
const Atmos := preload("res://scripts/game/atmos.gd")
const Sound := preload("res://scripts/game/sound.gd")
const SaveData := preload("res://scripts/game/save.gd")
const Missions := preload("res://scripts/game/missions.gd")
const Ads := preload("res://scripts/game/ads.gd")
const CARS := preload("res://scripts/game/cars.gd")
const UI := preload("res://scripts/ui/ui.gd")
const K := preload("res://scripts/ui/kit.gd")

enum { TITLE, RUN, DYING, OVER, GARAGE, PAUSED }

const CAM_SIZE := 21.0
const CAM_PITCH := -37.0
const CAM_YAW := 45.0
const STEER_RANGE := 105.0

var save: SaveData
var missions: Missions
var ads: Ads
var toon: ShaderMaterial
var world: World
var car: Car
var fx: Fx
var atmos: Atmos
var sound: Sound
var ui: UI
var cam: Camera3D
var ghost: Node3D
var ghost_mat: ShaderMaterial
var best_line: Node3D

var state := TITLE
var seed_value := 1
var daily := false
var run_t := 0.0
var max_v := 0.0
var style := 0
var run_coins := 0
var run := {}
var biomes_seen := {}
var chain := 0
var chain_t := 0.0
var edge_cd := 0.0
var dying_t := 0.0
var death := ""
var fuel_cap := 30.0
var stopped_t := 0.0
var coin_streak := 0
var coin_streak_t := 0.0
var low_fuel_warned := false
var ghost_rec: Array = []
var ghost_rec_t := 0.0
var ghost_play: Array = []
var ghost_on := false
var best_target := 0
var best_v := 0.0
var cam_focus := Vector3.ZERO
var cam_size := CAM_SIZE
var shake := 0.0
var crumble_delay := 0.0
var drift_tick := 0.0
var skid_t := 0.0
var dust_t := 0.0
var time := 0.0
var rumble_t := 0.0

# input
var touch_id := -1
var anchor_x := 0.0
var tap_start := Vector2.ZERO
var tap_moved := false
var key_steer := 0.0

# test harness
var args := {}
var frames := 0
var autopilot := false

func _ready() -> void:
	_parse_args()
	if FileAccess.file_exists("user://content_pending"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://content_pending"))
	save = SaveData.new()
	if not args.has("fresh"):
		save.load_data()
	missions = Missions.new(save)
	missions.ensure()
	ads = Ads.new()
	toon = ShaderMaterial.new()
	toon.shader = load("res://shaders/toon.gdshader")
	toon.set_shader_parameter("palette", PAL.make_texture())
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_SIZE
	cam.near = 1.0
	cam.far = 140.0
	cam.rotation_degrees = Vector3(CAM_PITCH, CAM_YAW, 0)
	add_child(cam)
	world = World.new()
	add_child(world)
	world.setup(self, toon, K.font(650))
	fx = Fx.new()
	add_child(fx)
	fx.setup(toon)
	car = Car.new()
	add_child(car)
	car.setup(world, self, toon)
	atmos = Atmos.new()
	add_child(atmos)
	atmos.setup(world, self, cam, toon)
	for m in world.mat_sway.values():
		atmos.add_material(m)
	atmos.add_material(fx.puffs.material_override)
	sound = Sound.new()
	add_child(sound)
	sound.setup()
	ui = UI.new()
	add_child(ui)
	ui.setup(self)
	ghost_mat = ShaderMaterial.new()
	ghost_mat.shader = load("res://shaders/ghost.gdshader")
	ghost = Node3D.new()
	add_child(ghost)
	ghost.visible = false
	best_line = _make_best_line()
	add_child(best_line)
	_apply_settings()
	car_changed()
	_new_world(_random_seed(), false)
	if args.has("garage"):
		open_garage(true)
	elif args.has("run") or args.has("auto"):
		autopilot = args.has("auto")
		_start_run()
	else:
		state = TITLE
		ui.show_title()
	sound.start_music()

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"

func _random_seed() -> int:
	if args.has("seed"):
		return int(args["seed"])
	return randi() % 1000000 + 1

func today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

func _daily_seed() -> int:
	return int(today().replace("-", "")) * 7 + 13

func build_label() -> String:
	var v = JSON.parse_string(FileAccess.get_file_as_string("res://version.json")) if FileAccess.file_exists("res://version.json") else null
	return String(v.get("label", "dev")) if v is Dictionary else "dev"

# ------------------------------------------------------------------ world / run lifecycle

func _new_world(s: int, is_daily: bool) -> void:
	seed_value = s
	daily = is_daily
	world.reset(s, String(args.get("biome", "")))
	fx.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var start_season := rng.randi_range(0, 3)
	if args.has("season"):
		start_season = int(args["season"])
	atmos.reset(s, start_season)
	if args.has("hour"):
		atmos.hour = float(args["hour"])
	if args.has("weather"):
		atmos.force_weather(String(args["weather"]))
	var p := world.pos_at(0.0, 0.0)
	var t := world.tangent(0.0)
	car.place(p, atan2(-t.x, -t.z))
	car.active = false
	cam_focus = p + world.F * 3.0
	_cam_update(1.0, true)
	ghost.visible = false
	best_line.visible = false
	biomes_seen.clear()

func _start_run() -> void:
	state = RUN
	run_t = 0.0
	max_v = 0.0
	style = 0
	run_coins = 0
	chain = 0
	chain_t = 0.0
	stopped_t = 0.0
	dying_t = 0.0
	death = ""
	low_fuel_warned = false
	coin_streak = 0
	run = {"dist": 0, "coins": 0, "drift": 0.0, "near": 0, "clean": 0, "spins": 0, "spin720": 0, "stations": 0,
		"knocks": 0, "jumps": 0, "night": 0.0, "regions": 0, "weather": 0.0, "air_max": 0.0}
	biomes_seen.clear()
	_apply_upgrades()
	car.active = true
	car.fuel = 1.0
	crumble_delay = 2.2
	world.start_crumble(-16.0)
	ghost_rec.clear()
	ghost_rec_t = 0.0
	ghost_play = save.data["daily_ghost"] if daily else save.data["ghost"]
	if daily and String(save.data["daily"]["date"]) != today():
		ghost_play = []
	ghost_on = ghost_play.size() > 4
	_build_ghost()
	best_target = int(save.data["daily"]["best"]) if daily and String(save.data["daily"]["date"]) == today() else int(save.data["best"])
	if daily and String(save.data["daily"]["date"]) != today():
		best_target = 0
	best_v = float(save.data["daily"]["best_dist"]) if daily and String(save.data["daily"]["date"]) == today() else float(save.data["best_dist"])
	best_line.visible = false
	ui.hide_title()
	ui.show_hud()
	sound.set_muffle(0.0)
	sfx("start")
	buzz(40, 0.6)
	if daily:
		ui.toast("Daily run · %s" % today(), "calendar", K.SUN, Color.WHITE)
	var b := world.biome_at(0.0)
	biomes_seen[b] = true
	ui.toast(World.BIOME_NAMES[b], "map", K.PAPER, K.INK, 1.6)

func _apply_upgrades() -> void:
	fuel_cap = 30.0 * (1.0 + 0.18 * save.level("tank"))
	car.grip_mul = 1.0 + 0.09 * save.level("grip")
	car.wind_resist = 0.15 * save.level("wind")

func _magnet() -> float:
	return 1.0 + 0.55 * save.level("magnet")

func restart(is_daily: bool) -> void:
	ui.transition(func():
		ui.hide_over()
		_new_world(_daily_seed() if is_daily else _random_seed(), is_daily)
		_start_run())

func start_daily() -> void:
	ui.transition(func():
		_new_world(_daily_seed(), true)
		_start_run())

func go_home() -> void:
	ui.transition(func():
		ui.hide_over()
		ui.hide_garage()
		_new_world(_random_seed(), false)
		state = TITLE
		ui.show_title()
		sound.set_muffle(0.0))

func open_garage(instant := false) -> void:
	var f := func():
		ui.hide_over()
		ui.close_sheet()
		ui.show_garage()
		state = GARAGE
		sound.set_muffle(0.35)
	if instant:
		f.call()
	else:
		ui.transition(f)

func close_garage() -> void:
	go_home()

func car_changed() -> void:
	var old := car.body.material_override as ShaderMaterial
	if old:
		atmos.remove_material(old)
	car.set_car(CARS.by_id(String(save.data["car"])))
	atmos.add_material(car.body_material())
	_build_ghost()

func pause() -> void:
	if state != RUN:
		return
	state = PAUSED
	sound.set_muffle(0.8)
	sound.silence_loops()
	ui.open_pause()

func resume() -> void:
	if state == PAUSED:
		state = RUN
		sound.set_muffle(0.0)

func end_run_from_pause() -> void:
	state = RUN
	_finish_run("quit")

func reset_progress() -> void:
	save.reset()
	missions.ensure()
	save.save()
	car_changed()
	_apply_settings()
	ui.refresh_title()

func set_setting(k: String, v) -> void:
	save.data["settings"][k] = v
	save.save()
	_apply_settings()

func _apply_settings() -> void:
	var st = save.data["settings"]
	sound.set_volumes(float(st["music"]), float(st["sfx"]))
	atmos.sun.shadow_enabled = bool(st["shadows"])

# ------------------------------------------------------------------ feedback helpers

func sfx(n: String, vol := 0.0, pitch := 1.0) -> void:
	sound.play(n, vol, pitch)

func ui_tap() -> void:
	sound.play("tap", -4.0, 1.0, 0.08)
	buzz(10, 0.3)

func buzz(ms: int, amp: float) -> void:
	if not bool(save.data["settings"]["haptics"]):
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, clampf(amp, 0.0, 1.0))

func _style(points: int, text: String, pos: Vector3, col := Color.WHITE, sub := "") -> void:
	chain += 1
	chain_t = 2.6
	var mult := 1.0 + minf(chain - 1, 6) * 0.25
	var pts := int(round(points * mult))
	style += pts
	var s := "+%d" % pts
	if mult > 1.01:
		s += "  x%.2f" % mult if fmod(mult * 4.0, 2.0) != 0.0 else "  x%.1f" % mult
	ui.popup(text, pos + Vector3(0, 1.2, 0), col, 40, s if sub == "" else sub + "  " + s)

# ------------------------------------------------------------------ events from the world, car and sky

func car_event(kind: String, d: Dictionary) -> void:
	match kind:
		"launch":
			run["jumps"] += 1
			sfx("launch")
			buzz(30, 0.7)
			shake = maxf(shake, 0.15)
			fx.puff(car.position, Color("fff4e0"), 0.5, -car.vel * 0.1, 0.5)
		"land":
			var air: float = d["air"]
			run["air_max"] = maxf(float(run["air_max"]), air)
			var impact: float = d["impact"]
			if air > 0.12:
				var dust := _dust_color()
				for i in 6:
					fx.puff(car.position + Vector3(randf_range(-0.5, 0.5), 0.1, randf_range(-0.5, 0.5)), dust, 0.45, Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), 0.6, 0.8)
				sfx("land", -2.0 + minf(impact, 10.0) * 0.4)
				buzz(int(clampf(impact * 6.0, 20.0, 70.0)), clampf(impact * 0.09, 0.4, 1.0))
				shake = maxf(shake, clampf(impact * 0.03, 0.05, 0.3))
			if air >= 0.4:
				var spins: int = d["spins"]
				if spins >= 1:
					run["spins"] += 1
					if spins >= 2:
						run["spin720"] += 1
					var names := {1: "360!", 2: "720!!", 3: "1080!!!"}
					var pts := {1: 90, 2: 220, 3: 450}
					_style(pts.get(spins, 700), names.get(spins, "%d°!!!" % (spins * 360)), car.position, K.LILAC, "")
					sfx("spin")
					fx.burst(car.position + Vector3(0, 0.6, 0), ["ff7a6b", "ffc94d", "3db5a6", "a998f2"], 14, 4.0, 5.0)
				elif air >= 0.55:
					_style(int(air * 60.0), "Big air", car.position, K.SKY, "%.1fs" % air)
				if d["clean"]:
					run["clean"] += 1
					_style(35 if spins == 0 else 60, "Clean landing", car.position + Vector3(0, -0.5, 0), K.LEAF)
					sfx("land_clean")
					fx.sparkle(car.position + Vector3(0, 0.3, 0), Color("fff3b0"), 8)
				elif d["spins"] == 0 and air > 0.6:
					pass
		"drift_end":
			var t: float = d["time"]
			if t > 0.45:
				var c: int = d["chain"]
				_style(int(t * 20.0 * (1.0 + c * 0.25)), "Drift" if c == 0 else "Drift chain x%d" % (c + 1), car.position, K.SUN, "%.1fs" % t)
		"off_edge":
			pass
		"dead":
			death = String(d["why"])
			state = DYING
			dying_t = 0.0
			if death == "splash":
				sfx("splash")
				for i in 10:
					fx.puff(car.position + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)), Color("bfe8ff"), 0.5, Vector3(randf_range(-2, 2), 3.0, randf_range(-2, 2)), 0.8, 2.0)
				buzz(120, 0.8)
			else:
				sfx("fall")
				buzz(180, 0.7)
			sound.silence_loops()

func world_event(kind: String, d: Dictionary) -> void:
	match kind:
		"crumble":
			if state == RUN and d["pos"].distance_to(car.position) < 14.0:
				rumble_t = 0.2

func atmos_event(kind: String, d: Dictionary) -> void:
	if state != RUN:
		return
	match kind:
		"season":
			var s: int = d["season"]
			var icons := ["leaf", "sun", "leaf", "snow"]
			var cols := [Color("9ad96b"), K.SUN, Color("f08b3a"), K.SKY]
			ui.toast(PAL.SEASON_NAMES[s], icons[s], cols[s], Color.WHITE, 2.4)
			sfx("season")
		"day":
			ui.toast("Day %d" % d["day"], "sun", K.SUN, Color.WHITE, 1.8)
		"weather":
			var w: String = d["weather"]
			var msg := {"rain": ["Rain rolling in · slippery!", "rain"], "fog": ["Fog ahead", "fog"], "snow": ["Snowfall · watch for ice", "snow"],
				"wind": ["Windy · gusts push you", "wind"], "clear": ["Skies clearing", "sun"]}
			ui.toast(msg[w][0], msg[w][1], K.PAPER, K.INK, 2.2)
		"gust":
			sfx("gust", -4.0)
			buzz(60, 0.35)

# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	time += delta
	frames += 1
	var dt := minf(delta, 1.0 / 30.0)
	ui.title_tick(time)
	ui.garage_tick(dt)
	if state == PAUSED or state == GARAGE:
		_harness()
		return
	var steps := int(ceil(dt / (1.0 / 60.0)))
	var h := dt / steps
	for i in steps:
		_sim(h)
	car.render(dt, atmos.night)
	fx.tick(dt)
	_cam_update(dt, false)
	_ghost_tick()
	_best_line_tick()
	var running := state == RUN
	atmos.tick(dt, cam_focus, running)
	car.weather_grip = 1.0 - atmos.rain * 0.3 - atmos.snow * 0.15
	car.wind = atmos.wind_vec if running else Vector3.ZERO
	var drift_amt := clampf((absf(car.drift) - 0.2) * 2.5, 0.0, 1.0) if car.drifting else 0.0
	sound.tick(dt, car.speed(), car.steer_smooth, car.grounded, running and car.active and not car.dead, drift_amt, atmos.windy, atmos.rain, car.fuel < 0.2)
	if state == RUN:
		ui.hud_update(dt, int(max_v), car.fuel, run_coins, best_target, 1.0 + minf(chain - 1, 8) * 0.25 if chain > 1 else 1.0)
	_harness()

func _sim(dt: float) -> void:
	if state == RUN:
		run_t += dt
		car.steer = _steer_input()
		crumble_delay -= dt
	elif state == TITLE:
		car.steer = 0.0
	car.step(dt)
	var cv := world.v_of(car.position)
	var crumble_on := state == RUN and crumble_delay <= 0.0
	var gap := cv - world.crumble_v
	var cspeed := lerpf(6.0, 7.4, world.difficulty) + clampf((gap - 40.0) * 0.25, 0.0, 6.0)
	world.tick(dt, maxf(cv, max_v), cspeed, crumble_on, time)
	if state == DYING:
		dying_t += dt
		if dying_t > (0.8 if death == "fuel" else 1.5):
			_finish_run(death)
		return
	if state != RUN:
		return
	# progress
	if cv > max_v:
		var add := cv - max_v
		max_v = cv
		if atmos.is_night():
			run["night"] += add
		if atmos.weather != "clear" and atmos.wint > 0.4:
			run["weather"] += add
		run["dist"] = int(max_v)
		if best_target > 0 and style + int(max_v) + run_coins * 5 > best_target:
			ui.passed_best()
	# fuel
	if car.active and car.speed() > 0.5:
		var before := car.fuel
		car.fuel = maxf(0.0, car.fuel - dt / fuel_cap)
		if before > 0.2 and car.fuel <= 0.2 and not low_fuel_warned:
			low_fuel_warned = true
			ui.toast("Low fuel!", "fuel", K.CORAL, Color.WHITE, 1.6)
			sfx("lowfuel")
			buzz(80, 0.6)
		if before > 0.0 and car.fuel <= 0.0:
			sfx("sputter")
			ui.toast("Out of fuel… coast to a can!", "fuel", K.CORAL, Color.WHITE, 2.0)
	if car.fuel <= 0.0 and car.out_of_fuel_stopped():
		stopped_t += dt
		if stopped_t > 0.7:
			death = "fuel"
			state = DYING
			dying_t = 0.0
			sound.silence_loops()
	else:
		stopped_t = 0.0
	# combo window
	if chain_t > 0.0:
		chain_t -= dt
		if chain_t <= 0.0:
			chain = 0
	if car.dead:
		return
	# scenery
	for e in world.collide(car.position, Car.RADIUS, car.vel, car.forward()):
		match e["type"]:
			"knock":
				run["knocks"] += 1
				car.slow = 0.72
				var kind: String = e["kind"]
				sfx("knock_" + kind if kind in ["wood", "soft", "rock", "cloud", "sand", "crystal", "metal"] else "knock_wood")
				buzz(35, 0.75)
				shake = maxf(shake, 0.12)
				var col: Color = {"cloud": Color.WHITE, "sand": Color("f4dca2"), "crystal": Color("d9ccff"), "soft": Color("b6e39a")}.get(kind, _dust_color())
				for i in (8 if kind in ["cloud", "sand"] else 4):
					fx.puff(e["pos"] + Vector3(randf_range(-0.3, 0.3), 0.4, randf_range(-0.3, 0.3)), col, 0.5, Vector3(randf_range(-1.5, 1.5), 1.0, randf_range(-1.5, 1.5)), 0.7)
				if kind == "crystal":
					fx.burst(e["pos"] + Vector3(0, 0.4, 0), ["b9a6ff", "8fe3ff", "ffb3e0"], 10, 3.0, 4.0)
				if randf() < 0.35:
					ui.popup(["Bonk!", "Oops!", "Boop!", "Whoops!"][randi() % 4], e["pos"] + Vector3(0, 1.0, 0), Color.WHITE, 30)
			"solid":
				var n: Vector3 = e["normal"]
				car.position += n * e["depth"]
				var vn := car.vel.dot(n)
				if vn < 0.0:
					car.vel -= n * vn * 1.4
					car.vel *= 0.8
					sfx("bonk")
					buzz(40, 0.8)
					shake = maxf(shake, 0.2)
			"near":
				run["near"] += 1
				_style(15, "Close call!", e["pos"], Color.WHITE)
				sfx("near", -3.0)
				buzz(15, 0.45)
	# edge skims
	edge_cd -= dt
	if car.grounded and car.speed() > 5.0 and edge_cd <= 0.0 and world.edge_skim(car.position, car.right()):
		edge_cd = 1.1
		run["near"] += 1
		_style(12, "Edge skim!", car.position, Color("ffe2a8"))
		sfx("near", -5.0, 1.2)
		buzz(15, 0.4)
	# pickups
	coin_streak_t -= dt
	if coin_streak_t <= 0.0:
		coin_streak = 0
	for e in world.collect(car.position, _magnet(), dt):
		match e["type"]:
			"coin":
				run_coins += 1
				run["coins"] = run_coins
				coin_streak = mini(coin_streak + 1, 12)
				coin_streak_t = 0.9
				sfx("coin", -3.0, 1.0 + coin_streak * 0.045)
				buzz(8, 0.35)
				fx.sparkle(e["pos"], Color("ffe27a"), 5)
			"fuel":
				var add := 9.0 / fuel_cap
				car.fuel = minf(1.0, car.fuel + add)
				low_fuel_warned = car.fuel <= 0.2
				sfx("fuel")
				buzz(30, 0.6)
				ui.popup("Fuel +", e["pos"] + Vector3(0, 1.0, 0), Color("ff8a5c"), 36)
				fx.burst(e["pos"] + Vector3(0, 0.4, 0), ["ec4b3f", "ffd36b", "ffffff"], 8, 2.5, 3.0, 0.7)
			"station":
				car.fuel = 1.0
				low_fuel_warned = false
				run["stations"] += 1
				sfx("station")
				buzz(25, 0.7)
				ui.popup("Refueled!", e["pos"] + Vector3(0, 1.6, 0), Color("8fd19e"), 44)
				fx.burst(e["pos"] + Vector3(0, 0.6, 0), ["ff7a6b", "ffc94d", "ffffff"], 16, 3.5, 5.0)
	# drifting: dust, skids, haptic ticks, counter
	if car.drifting:
		run["drift"] += dt
		skid_t -= dt
		if skid_t <= 0.0:
			skid_t = 0.04
			for wi in [2, 3]:
				var wp: Vector3 = car.position + car.right() * (0.42 if wi == 3 else -0.42) - car.forward() * 0.5
				fx.skid(Vector3(wp.x, world.ground_at(wp) + 0.0, wp.z), car.yaw)
			fx.puff(car.position - car.forward() * 0.7 + Vector3(0, 0.15, 0), Color("fffaf2"), 0.38, -car.vel * 0.15, 0.55, 0.5)
		drift_tick -= dt
		if drift_tick <= 0.0:
			drift_tick = 0.14
			buzz(6, 0.25)
	elif car.grounded and car.speed() > 4.0:
		dust_t -= dt
		if dust_t <= 0.0:
			dust_t = 0.12
			fx.puff(car.position - car.forward() * 0.75 + Vector3(randf_range(-0.2, 0.2), 0.08, 0), _dust_color(), 0.22, Vector3.ZERO, 0.45, 0.3)
	# near the crumbling edge
	if cv - world.crumble_v < 7.0 and car.grounded:
		rumble_t = maxf(rumble_t, 0.05)
	if rumble_t > 0.0:
		rumble_t -= dt
		shake = maxf(shake, 0.05)
		if randf() < dt * 6.0:
			buzz(20, 0.35)
	# regions
	var nb := world.biome_changed(cv)
	if nb != "" and run_t > 0.5:
		if not biomes_seen.has(nb):
			biomes_seen[nb] = true
		run["regions"] = biomes_seen.size()
		ui.toast(World.BIOME_NAMES[nb], "map", K.PAPER, K.INK, 2.0)
	run["regions"] = maxi(int(run["regions"]), biomes_seen.size())
	# weather starts after a calm opening
	atmos.weather_enabled = run_t > 18.0 or args.has("weather")
	# missions
	for m in missions.check(run):
		ui.toast("Mission done! +%d" % int(m["reward"]), "check", K.TEAL, Color.WHITE, 2.4)
		sfx("mission")
		buzz(50, 0.7)
	# ghost recording (10 per second): [t, v, u relative to the center line, y, yaw relative to the road]
	ghost_rec_t -= dt
	if ghost_rec_t <= 0.0:
		ghost_rec_t = 0.1
		var tv := cv
		var tt := world.tangent(tv)
		ghost_rec.append([snappedf(run_t, 0.01), snappedf(tv, 0.01), snappedf(world.u_of(car.position) - world.center(tv), 0.01),
			snappedf(car.position.y, 0.01), snappedf(angle_difference(atan2(-tt.x, -tt.z), car.yaw), 0.001)])

func _dust_color() -> Color:
	var b := world.biome_at(world.v_of(car.position))
	var slot: int = World.BIOME_TOP.get(b, PAL.GRASS)
	if car.surface == "ice":
		slot = PAL.ICE
	return PAL.color(slot, atmos.season).lightened(0.35)

func _finish_run(why: String) -> void:
	if state == OVER:
		return
	state = OVER
	car.active = false
	sound.silence_loops()
	sound.set_muffle(0.6)
	ui.hide_hud()
	var dist := int(max_v)
	var score := dist + style + run_coins * 5
	var s = save.data
	s["coins"] = int(s["coins"]) + run_coins
	s["runs"] = int(s["runs"]) + 1
	s["stats"]["distance"] = float(s["stats"]["distance"]) + dist
	s["stats"]["coins"] = int(s["stats"]["coins"]) + run_coins
	var record := false
	if daily:
		var d = s["daily"]
		if String(d["date"]) != today():
			d["date"] = today()
			d["best"] = 0
			d["best_dist"] = 0
			s["daily_ghost"] = []
		d["runs"] = int(d["runs"]) + 1
		if score > int(d["best"]):
			record = true
			d["best"] = score
			d["best_dist"] = dist
			s["daily_ghost"] = ghost_rec.duplicate()
	if score > int(s["best"]) and not daily:
		record = true
		s["best"] = score
		s["best_dist"] = dist
		s["ghost"] = ghost_rec.duplicate()
	var shown_missions: Array = s["missions"].duplicate(true)
	var mc := missions.settle()
	s["coins"] = int(s["coins"]) + mc
	save.save()
	if record:
		sfx("record")
		buzz(120, 1.0)
		fx.burst(car.position + Vector3(0, 1.0, 0), ["ff7a6b", "ffc94d", "3db5a6", "a998f2", "6ec6ff"], 40, 6.0, 8.0, 1.6)
	var result := {"why": why, "dist": dist, "style": style, "coins": run_coins, "score": score, "record": record,
		"best": int(s["daily"]["best"]) if daily else int(s["best"]), "mission_coins": mc, "missions": shown_missions,
		"run": run.duplicate(), "daily": daily, "date": today()}
	await get_tree().create_timer(0.35).timeout
	ui.show_over(result)

# ------------------------------------------------------------------ camera

func _cam_update(dt: float, snap: bool) -> void:
	var target := car.position
	if car.dead and car.falling:
		target = Vector3(car.position.x, maxf(car.position.y, -1.5), car.position.z)
	var lead := world.F * 3.2 + Vector3(car.vel.x, 0, car.vel.z) * 0.18
	if state == TITLE or state == GARAGE:
		lead = world.F * 2.0
	var want := Vector3(target.x, maxf(target.y * 0.6, -1.0), target.z) + lead
	if snap:
		cam_focus = want
	else:
		cam_focus = cam_focus.lerp(want, 1.0 - exp(-dt * 4.0))
	var want_size := CAM_SIZE + (1.6 if not car.grounded and not car.dead else 0.0)
	if state == TITLE:
		want_size = CAM_SIZE - 3.0
	cam_size = want_size if snap else lerpf(cam_size, want_size, 1.0 - exp(-dt * 2.0))
	cam.size = cam_size
	var fwd := cam.global_transform.basis.z
	shake = maxf(0.0, shake - dt * 0.9)
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.6 if shake > 0.0 else Vector3.ZERO
	cam.position = cam_focus + fwd * 60.0 + cam.global_transform.basis * sh

# ------------------------------------------------------------------ ghost of the best run

func _build_ghost() -> void:
	for c in ghost.get_children():
		c.queue_free()
	var c := M.car(CARS.by_id(String(save.data["car"])))
	var b := MeshInstance3D.new()
	b.mesh = c["body"]
	b.material_override = ghost_mat
	b.position.y = c["ride"]
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.add_child(b)
	for i in 4:
		var w := MeshInstance3D.new()
		w.mesh = c["wheel_f"] if i < 2 else c["wheel_r"]
		w.material_override = ghost_mat
		w.position = c["wheels"][i]
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(w)

func _ghost_tick() -> void:
	if not ghost_on or state != RUN:
		ghost.visible = false
		return
	var n := ghost_play.size()
	var last: Array = ghost_play[n - 1]
	if run_t > float(last[0]) + 1.0:
		ghost.visible = false
		return
	var i := clampi(int(run_t * 10.0), 0, n - 2)
	while i < n - 2 and float(ghost_play[i + 1][0]) < run_t:
		i += 1
	while i > 0 and float(ghost_play[i][0]) > run_t:
		i -= 1
	var a: Array = ghost_play[i]
	var b: Array = ghost_play[i + 1]
	var k := clampf((run_t - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0])), 0.0, 1.0)
	var v := lerpf(a[1], b[1], k)
	var u := lerpf(a[2], b[2], k)
	var y := lerpf(a[3], b[3], k)
	var tt := world.tangent(v)
	var ryaw := lerp_angle(float(a[4]), float(b[4]), k)
	var p := world.pos_at(v, u)
	p.y = maxf(y, -6.0)
	ghost.position = p
	ghost.rotation = Vector3(0, atan2(-tt.x, -tt.z) + ryaw, 0)
	ghost.visible = true
	var fade := 1.0 - clampf(run_t - float(last[0]), 0.0, 1.0)
	ghost_mat.set_shader_parameter("alpha", 0.38 * fade)

func _make_best_line() -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var mb := preload("res://scripts/core/mesh_builder.gd").new()
	for i in 9:
		var x := -4.0 + i
		mb.cyl(Vector3(x, 0.45, 0), 0.035, 0.9, mb.rgb("ffffff"), 6)
		mb.box(Vector3(x + 0.22, 0.78, 0), Vector3(0.42, 0.26, 0.02), mb.glow("ffc94d" if i % 2 == 0 else "ff7a6b"))
	mb.box(Vector3(0, 0.02, 0), Vector3(9.0, 0.03, 0.18), mb.glow("fff3b0"))
	mi.mesh = mb.commit()
	mi.material_override = toon
	n.add_child(mi)
	var l := Label3D.new()
	l.text = "BEST"
	l.font = K.font(700)
	l.font_size = 96
	l.pixel_size = 0.008
	l.outline_size = 18
	l.outline_modulate = Color("4a3a33")
	l.modulate = Color("ffc94d")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, 1.6, 0)
	n.add_child(l)
	return n

func _best_line_tick() -> void:
	if state != RUN or best_v < 40.0:
		best_line.visible = false
		return
	var v := best_v
	if world.gen_s * World.D < v + 2.0 or world.crumble_v > v:
		best_line.visible = false
		return
	var t := world.tangent(v)
	best_line.position = world.pos_at(v, 0.0)
	best_line.rotation = Vector3(0, atan2(-t.x, -t.z), 0)
	best_line.visible = world.ground_at(best_line.position) != World.NO_GROUND or max_v > v

# ------------------------------------------------------------------ input

func _steer_input() -> float:
	if autopilot:
		return _auto_steer()
	var s := key_steer
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		s -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		s += 1.0
	return clampf(s, -1.0, 1.0)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			if touch_id == -1:
				touch_id = e.index
				anchor_x = e.position.x
				tap_start = e.position
				tap_moved = false
		elif e.index == touch_id:
			touch_id = -1
			key_steer = 0.0
			if state == TITLE and not tap_moved:
				_start_run()
	elif e is InputEventScreenDrag and e.index == touch_id:
		if e.position.distance_to(tap_start) > 24.0:
			tap_moved = true
		var dx: float = e.position.x - anchor_x
		if absf(dx) > STEER_RANGE:
			anchor_x = e.position.x - signf(dx) * STEER_RANGE
			dx = signf(dx) * STEER_RANGE
		key_steer = dx / STEER_RANGE
	elif e is InputEventKey and e.pressed and not e.echo:
		if state == TITLE and e.keycode in [KEY_SPACE, KEY_ENTER, KEY_UP, KEY_W]:
			_start_run()
		elif e.keycode == KEY_ESCAPE:
			if state == RUN:
				pause()
			elif state == PAUSED:
				ui.close_sheet()
				resume()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if ui.overlay.visible:
				ui.close_sheet()
				if state == PAUSED:
					resume()
			elif state == RUN:
				pause()
			elif state == GARAGE:
				close_garage()
			elif state == OVER:
				go_home()
			elif state == TITLE:
				get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if state == RUN:
				pause()

# ------------------------------------------------------------------ autopilot and screenshots (testing)

func _auto_steer() -> float:
	var v := world.v_of(car.position)
	var best_off := 0.0
	var best_score := -999.0
	for off in [0.0, -1.2, 1.2, -2.4, 2.4]:
		var sc := 0.0
		for k in [3.0, 5.5, 8.0]:
			var q := world.pos_at(v + k, off)
			if world.ground_at(q) == World.NO_GROUND and world.ramp_at(q).is_empty():
				sc -= 3.0
		sc -= absf(off) * 0.3
		if sc > best_score:
			best_score = sc
			best_off = off
	var tgt := world.pos_at(v + 5.0, best_off)
	var d := tgt - car.position
	var desired := atan2(-d.x, -d.z)
	var err := angle_difference(car.yaw, desired)
	var s := clampf(-err * 2.4, -1.0, 1.0)
	if args.has("wiggle"):
		s = clampf(s + sin(run_t * 1.3) * 0.7, -1.0, 1.0)
	return s

func _harness() -> void:
	if args.has("shot"):
		var at := int(args.get("frames", "90"))
		if frames == at:
			var img := get_viewport().get_texture().get_image()
			img.save_png(String(args["shot"]))
			print("shot saved ", args["shot"], " hour=", atmos.hour, " night=", atmos.night, " state=", state, " v=", world.v_of(car.position), " tiles=", world.tiles.size(), " fuel=", car.fuel)
			if not args.has("keep"):
				get_tree().quit()
	if args.has("quit_after") and run_t > float(args["quit_after"]):
		print("RESULT t=%.1f dist=%d style=%d coins=%d dead=%s why=%s state=%d tiles=%d" % [run_t, int(max_v), style, run_coins, car.dead, death, state, world.tiles.size()])
		get_tree().quit()
	if args.has("over") and frames == 40 and state == RUN:
		max_v = 412.0
		style = 286
		run_coins = 23
		save.data["best"] = 600
		_finish_run(String(args["over"]))
	if args.has("coins") and frames == 2:
		save.data["coins"] = int(args["coins"])
		ui.refresh_title()
	if args.has("open") and frames == 3:
		match String(args["open"]):
			"missions": ui.open_missions()
			"settings": ui.open_settings()
			"daily": ui.open_daily()
			"pause":
				pause()
	if args.has("auto") and state == OVER and args.has("loops"):
		if frames % 60 == 0:
			var left := int(args["loops"]) - 1
			args["loops"] = str(left)
			print("RUN-END dist=%d style=%d coins=%d why=%s t=%.1f" % [int(max_v), style, run_coins, death, run_t])
			if left <= 0:
				get_tree().quit()
			else:
				ui.hide_over()
				_new_world(_random_seed() + frames, false)
				_start_run()
