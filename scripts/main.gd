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
const Police := preload("res://scripts/game/police.gd")
const K := preload("res://scripts/ui/kit.gd")
const Ach := preload("res://scripts/game/achievements.gd")

enum { TITLE, RUN, DYING, OVER, GARAGE, PAUSED }

const CAM_SIZE := 14.0   # visible width in metres (taller phones see more road ahead)
const CAM_PITCH := -37.0
const CAM_YAW := 45.0

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
var police: Police
var chase := {}            # the chase in progress (from world.chases)
var chase_state := ""      # "", parked, on, over
var chase_siren_k := 0.0
var chase_over_t := 0.0

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
var honk_cd := 0.0

# input
var touches := {}         # touch index -> -1 (left arrow) or 1 (right arrow)
var title_touch := -1
var hold_l := 0.0
var hold_r := 0.0

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
	# trophies came in an update: seed the run bests from what the save already knows
	var st: Dictionary = save.data["stats"]
	if not st.has("max_dist"):
		st["max_dist"] = int(save.data["best_dist"])
		st["max_score"] = int(save.data["best"])
	missions = Missions.new(save)
	missions.ensure()
	ads = Ads.new()
	toon = ShaderMaterial.new()
	toon.shader = load("res://shaders/toon.gdshader")
	toon.set_shader_parameter("palette", PAL.make_texture())
	toon.set_shader_parameter("decay", 0.0)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = CAM_SIZE
	cam.near = 1.0
	cam.far = 420.0
	cam.rotation_degrees = Vector3(CAM_PITCH, CAM_YAW, 0)
	add_child(cam)
	world = World.new()
	add_child(world)
	world.setup(self, toon, K.font(650))
	fx = Fx.new()
	add_child(fx)
	fx.setup(toon)
	world.fx = fx
	car = Car.new()
	add_child(car)
	car.setup(world, self, toon)
	atmos = Atmos.new()
	add_child(atmos)
	atmos.setup(world, self, cam, toon)
	for m in world.mat_sway.values():
		atmos.add_material(m)
	atmos.add_material(fx.puffs.material_override)
	if fx.puffs.material_override is ShaderMaterial:
		(fx.puffs.material_override as ShaderMaterial).set_shader_parameter("decay", 0.0)
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
	police = Police.new()
	add_child(police)
	police.setup(toon)
	police.world = world
	atmos.add_material(police.paint)
	_apply_settings()
	car_changed()
	_new_world(_random_seed(), false)
	if args.has("garage"):
		open_garage(true)
		if String(args["garage"]) == "up":
			ui._garage_tab(false)
	elif args.has("run") or args.has("auto"):
		autopilot = args.has("auto")
		_start_run()
	else:
		state = TITLE
		ui.show_title()
		# unlock anything an existing save already earned (cars, upgrades, past runs)
		get_tree().create_timer(1.2).timeout.connect(func():
			if state == TITLE:
				ach_check()
				ui.refresh_title())
	if args.has("warp"):
		if String(args["warp"]) == "kind" and world.forced_v > 0.0:
			_warp(world.forced_v + 2.0)
		elif String(args["warp"]).begins_with("deck") and not world.decks.is_empty():
			_warp(float(world.decks[0]["va"]) + float(String(args["warp"]).trim_prefix("deck") if String(args["warp"]) != "deck" else "8"))
		else:
			_warp(float(args["warp"]))
	if args.has("chase"):
		world._plan_until(1600.0)
		if not world.chases.is_empty():
			_warp(float(world.chases[0]["v_start"]) - 30.0)
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
	world.force_deck = String(args.get("deck", ""))
	world.force_kind = String(args.get("kind", ""))
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
	police.reset()
	chase = {}
	chase_state = ""
	chase_siren_k = 0.0
	ui.chase_show(false)
	sound.mute_loops(false)

func _start_run() -> void:
	state = RUN
	_clear_touches()
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
	car.pace = 1.0
	next_gear = 1.1
	ach_run = []
	ach_run_coins = 0
	ach_t = 0.0
	run = {"dist": 0, "coins": 0, "drift": 0.0, "near": 0, "clean": 0, "spins": 0, "spin720": 0, "stations": 0,
		"knocks": 0, "jumps": 0, "night": 0.0, "regions": 0, "weather": 0.0, "air_max": 0.0, "chases": 0, "boosts": 0,
		"decks": 0, "grind": 0.0, "hops": 0, "planks": 0, "tracks": 0, "gauntlets": 0, "police_fell": 0}
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
	sound.mute_loops(false)
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
	sound.set_engine(String(car.def.get("engine", "small")), float(car.def.get("pitch", 1.0)))
	_build_ghost()

func pause() -> void:
	if state != RUN:
		return
	state = PAUSED
	_clear_touches()
	sound.set_muffle(0.8)
	sound.mute_loops(true)
	ui.open_pause()

func resume() -> void:
	if state == PAUSED:
		state = RUN
		sound.set_muffle(0.0)
		sound.mute_loops(false)

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
	world.people.cheer(pos)
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
			var impact: float = d["impact"]
			if d.get("bump", false) and int(d["spins"]) == 0:
				# a hop over a hump: thump, dust, a little haptic kick
				if air > 0.08:
					var dc := _dust_color()
					for i in 3:
						fx.puff(car.position + Vector3(randf_range(-0.4, 0.4), 0.08, randf_range(-0.4, 0.4)), dc, 0.32, Vector3(randf_range(-1.2, 1.2), 0.3, randf_range(-1.2, 1.2)), 0.5, 0.5)
					sfx("bump", -7.0 + minf(impact, 8.0) * 0.6, randf_range(0.9, 1.1))
					buzz(int(clampf(impact * 7.0, 15.0, 45.0)), clampf(0.25 + impact * 0.07, 0.3, 0.75))
					shake = maxf(shake, clampf(impact * 0.015, 0.02, 0.1))
				if air >= 0.5:
					run["hops"] = int(run.get("hops", 0)) + 1
					_style(int(air * 40.0), "Hop!", car.position, K.LEAF, "%.1fs" % air)
				return
			run["air_max"] = maxf(float(run["air_max"]), air)
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
				_style(int(t * 12.0 * (1.0 + c * 0.25)), "Drift" if c == 0 else "Drift chain x%d" % (c + 1), car.position, K.SUN, "%.1fs" % t)
				run["drift_max"] = maxf(float(run.get("drift_max", 0.0)), t)
				run["max_chain"] = maxi(int(run.get("max_chain", 0)), c + 1)
			if t > 0.8 and state == RUN:
				car.drift_boost(t)
				sfx("boost", -10.0 + minf(t, 3.0) * 1.5, 1.25)
				buzz(30, 0.5)
				fx.puff(car.position - car.forward() * 0.8 + Vector3(0, 0.2, 0), Color("ffd37a"), 0.45, -car.forward() * 2.0, 0.4)
				fx.puff(car.position - car.forward() * 0.8 + Vector3(0, 0.2, 0), Color("ff9a5a"), 0.35, -car.forward() * 2.5, 0.35)
		"wall":
			var hit: float = d["impact"]
			wall_hits += 1
			sfx("bonk", -9.0 + minf(hit, 9.0) * 0.5, randf_range(0.92, 1.08))
			buzz(22, clampf(0.25 + hit * 0.05, 0.25, 0.6))
			fx.puff(d["pos"], Color("fff4e0"), 0.4, Vector3(0, 1.2, 0), 0.4)
		"grind_start":
			if args.has("auto"):
				print("GRIND START v=", int(world.v_of(car.position)), " y=", snappedf(car.position.y, 0.01))
			sfx("knock_metal", -2.0, 1.3)
			buzz(50, 0.8)
			shake = maxf(shake, 0.12)
			grind_fx_t = 0.0
			ui.popup("Grind!", car.position + Vector3(0, 1.3, 0), Color("8ff5ff"), 40)
		"grind_end":
			if args.has("auto"):
				print("GRIND END v=", int(world.v_of(car.position)), " len=", int(d["len"]))
			var gl: float = d["len"]
			run["grind"] = float(run.get("grind", 0.0)) + gl
			_style(int(gl * 7.0), "Rail grind!", car.position, Color("8ff5ff"), "%dm" % int(gl))
			sfx("launch", -3.0, 1.15)
			buzz(40, 0.7)
		"hop":
			if args.has("auto"):
				print("HOP at v=", snappedf(world.v_of(car.position), 0.1), " u=", snappedf(world.u_of(car.position) - world.center(world.v_of(car.position)), 0.1))
			sfx("launch", -4.0, 1.25)
			buzz(30, 0.5)
			fx.puff(d["pos"], Color("fff4e0"), 0.5, Vector3(0, 1.0, 0), 0.5)
		"off_edge":
			pass
		"dead":
			if chase_state == "on":
				police.stop()
				chase_state = "over"
				ui.chase_show(false)
			death = String(d["why"])
			if args.has("auto"):
				var sg: Dictionary = world.segment_at(world.v_of(car.position))
				print("DEATH ", death, " v=", int(world.v_of(car.position)), " seg=", sg["type"], "/", sg.get("kind", ""), " u=", snappedf(world.u_of(car.position) - world.center(world.v_of(car.position)), 0.1), " spd=", snappedf(car.speed(), 0.1), " pace=", snappedf(car.pace, 0.01), " drift=", snappedf(car.drift, 0.01))
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
			sound.mute_loops(true)

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
	sound.tick(dt, {"speed": car.speed(), "grounded": car.grounded, "active": running and car.active and not car.dead,
		"drift": drift_amt, "air_t": car.air_time, "boost": car.boost_k(), "empty": car.fuel <= 0.0 and running,
		"roll": world.roll_at(car.position, atmos.season_idx == 3), "windy": atmos.windy, "rainy": atmos.rain,
		"siren": chase_siren(), "siren_close": chase_closeness(), "pace": car.pace, "grind": car.grinding and state == RUN})
	if state == RUN:
		ui.hud_update(dt, int(max_v), car.fuel, run_coins, best_target, 1.0 + minf(chain - 1, 8) * 0.25 if chain > 1 else 1.0)
	_harness()

func _sim(dt: float) -> void:
	if state == RUN:
		run_t += dt
		car.steer = _steer_input(dt)
		crumble_delay -= dt
	elif state == TITLE:
		car.steer = 0.0
	if state == RUN:
		ach_t += dt
		if ach_t > 0.5:
			ach_t = 0.0
			_ach_announce(Ach.check(save.data, _ach_live()))
		var want_pace: float = world.pace_at(max_v)
		car.pace = move_toward(car.pace, want_pace, dt * 0.05)
		if want_pace >= next_gear:
			next_gear += 0.1
			if max_v > 50.0:
				ui.toast("Faster!  %d km/h" % int(Car.CRUISE * want_pace * 3.6), "wind", K.SUN, K.INK, 1.4)
				sfx("boost", -9.0, 0.8)
				buzz(25, 0.4)
	police.pace = car.pace
	car.step(dt)
	var cv := world.v_of(car.position)
	var crumble_on := state == RUN and crumble_delay <= 0.0
	var gap := cv - world.crumble_v
	var cspeed := lerpf(6.0, 7.4, world.difficulty) * lerpf(1.0, car.pace, 0.9) + clampf((gap - 32.0) * 0.3, 0.0, 6.0)
	world.tick(dt, maxf(cv, max_v), cspeed, crumble_on, time, car.position, car.vel)
	honk_cd -= dt
	if world.honk_pending:
		world.honk_pending = false
		if state == RUN and honk_cd <= 0.0 and not car.dead:
			honk_cd = 3.5
			sound.horn()
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
	if car.grinding:
		grind_fx_t -= dt
		if grind_fx_t <= 0.0:
			grind_fx_t = 0.05
			fx.burst(car.position + Vector3(0, -0.05, 0) - car.forward() * 0.4, ["ffd27a", "ff9a3d", "fff3b0"], 3, 2.5, 3.0, 0.35)
			buzz(8, 0.35)
	for gt in world.gauntlets:
		if gt["done"]:
			continue
		if not gt["warned"] and cv > float(gt["va"]) - 6.0:
			gt["warned"] = true
			ui.toast("Gauntlet! Ramp · rail · bridge · canyon", "flag", K.CORAL, Color.WHITE, 2.2)
		if max_v > float(gt["vb"]) and car.grounded and not car.dead:
			gt["done"] = true
			run["gauntlets"] = int(run.get("gauntlets", 0)) + 1
			_style(500, "Gauntlet cleared!", car.position, K.CORAL, "")
			sfx("record", -4.0)
			buzz(90, 0.9)
			fx.burst(car.position + Vector3(0, 0.8, 0), ["ff7a6b", "ffc94d", "8ff5ff", "a998f2"], 26, 5.0, 6.0)
	# red rock canyon heads-up
	var sg_now: Dictionary = world.segment_at(cv + 8.0)
	if sg_now.get("kind", "") == "rough" and canyon_seg != sg_now:
		canyon_seg = sg_now
		ui.toast("Red rock canyon · crawl it", "map", Color("e0915c"), Color.WHITE, 1.8)
	# deck challenges: a heads-up as one comes into view, a reward for making it across
	for dk in world.decks:
		if dk["done"]:
			continue
		var plank: bool = dk["style"] == "plank"
		if not dk.get("warned", false) and cv > float(dk["va"]) - 26.0:
			dk["warned"] = true
			ui.toast("Tightrope bridge ahead!" if plank else "Race track ahead!", "flag", K.SUN if plank else K.CORAL, K.INK if plank else Color.WHITE, 1.8)
		if max_v > float(dk["vb"]) + 1.0 and car.grounded and not car.dead:
			dk["done"] = true
			var length: float = float(dk["vb"]) - float(dk["va"])
			run["decks"] = int(run.get("decks", 0)) + 1
			run["planks" if plank else "tracks"] = int(run.get("planks" if plank else "tracks", 0)) + 1
			_style(int(length * (3.0 if plank else 2.4)), "Tightrope!" if plank else "Track run!", car.position, K.SUN if plank else K.CORAL, "%dm" % int(length))
			sfx("spin", -2.0, 1.1)
			buzz(50, 0.7)
			fx.burst(car.position + Vector3(0, 0.6, 0), ["ffc94d", "ff7a6b", "fff3b0"] if plank else ["ef5b4c", "f7f3ea", "ffcf4d"], 12, 3.5, 4.0)
			if args.has("auto"):
				print("DECK CROSSED ", dk["style"], " len=", int(length), " at v=", int(cv))
	# fuel
	if car.active and car.speed() > 0.5:
		var before := car.fuel
		car.fuel = maxf(0.0, car.fuel - dt * (1.0 + (car.pace - 1.0) * 0.5) / fuel_cap)
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
			sound.mute_loops(true)
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
	solid_cd -= dt
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
				var hit := car.push_solid(e["normal"], e["depth"], dt)
				if hit > 1.5 and solid_cd <= 0.0:
					solid_cd = 0.4
					sfx("bonk", -3.0 + minf(hit, 9.0) * 0.3)
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
			"boost":
				car.boost()
				run["boosts"] += 1
				sfx("boost", -2.0)
				sound.rev(1.25)
				buzz(45, 0.85)
				shake = maxf(shake, 0.18)
				ui.popup("Boost!", e["pos"] + Vector3(0, 1.0, 0), Color("ffb84d"), 40)
				for i in 6:
					fx.puff(car.position - car.forward() * 0.8 + Vector3(randf_range(-0.4, 0.4), 0.2, randf_range(-0.4, 0.4)), Color("ffd9a0"), 0.4, -car.forward() * 4.0, 0.45, 0.4)
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
			var dirt := car.surface == "dirt"
			dust_t = 0.05 if dirt else 0.12
			fx.puff(car.position - car.forward() * 0.75 + Vector3(randf_range(-0.3, 0.3), 0.08, randf_range(-0.2, 0.2)), _dust_color(), 0.34 if dirt else 0.22,
				-car.vel * (0.12 if dirt else 0.0) + Vector3(0, 0.4 if dirt else 0.0, 0), 0.7 if dirt else 0.45, 0.5 if dirt else 0.3)
	# mud puddles: a brown splash, a little drag and a slip
	var md := world.mud_at(car.position) if car.grounded else {}
	if not md.is_empty():
		car.slow = minf(car.slow, 0.86)
		if not in_mud:
			sfx("splash", -9.0, 1.5)
			buzz(30, 0.5)
		if randf() < dt * 30.0:
			fx.puff(car.position + Vector3(randf_range(-0.4, 0.4), 0.15, randf_range(-0.4, 0.4)), Color("7a5638"), 0.3,
				Vector3(randf_range(-2.5, 2.5), 2.2, randf_range(-2.5, 2.5)) - car.vel * 0.1, 0.5, 0.1)
	in_mud = not md.is_empty()
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
	_chase_tick(dt, cv)
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

# ------------------------------------------------------------------ police chases

func _chase_tick(dt: float, cv: float) -> void:
	police.record(car.position, car.yaw, car.grounded)
	match chase_state:
		"":
			for c in world.chases:
				if not c["done"] and cv > c["v_start"] - 45.0 and cv < c["v_start"]:
					chase = c
					chase_state = "parked"
					police.park(c["parked"], c["yaw"])
					break
		"parked":
			if cv >= chase["v_start"]:
				chase_state = "on"
				police.start_chase()
				if args.has("auto"):
					print("CHASE START v=", cv, " end=", chase["v_end"], " gap=", police.gap())
				chase_siren_k = 1.0
				ui.chase_show(true)
				ui.toast("Police chase! Hit the boost pads", "flag", Color("4b6bd6"), Color.WHITE, 2.4)
				sfx("lowfuel", -4.0, 0.8)
				buzz(80, 0.8)
			elif cv > chase["v_start"] + 5.0:
				chase_state = ""
		"on":
			var g := police.gap()
			var left := maxf(0.0, float(chase["v_end"]) - cv)
			ui.chase_update(dt, int(left), clampf(1.0 - (g - CATCH_SAFE) / 18.0, 0.0, 1.0))
			if police.state == "falling":
				_chase_end(true, true)
			elif g < Police.CATCH_GAP:
				_chase_end(false)
			elif left <= 0.0 or g > Police.LOST_GAP:
				_chase_end(true)
		"over":
			chase_over_t += dt
			chase_siren_k = maxf(0.0, chase_siren_k - dt * 0.5)
			if chase_over_t > 3.0 and police.position.distance_to(car.position) > 26.0:
				police.state = "hidden"
				police.visible = false
				chase_state = ""
	police.tick(dt, atmos.night)

const CATCH_SAFE := 2.0
var wall_hits := 0
var perf_acc := 0.0
var perf_n := 0
var perf_max := 0.0
var grind_fx_t := 0.0
var canyon_seg: Dictionary = {}
var gauntlet_msg_t := 0.0
var in_mud := false
var ach_t := 0.0
var next_gear := 1.1
var solid_cd := 0.0
var slow_t := 0.0
var slow_max := 0.0

func _chase_end(escaped: bool, fell := false) -> void:
	if args.has("auto"):
		var pv := world.v_of(police.position)
		var psg: Dictionary = world.segment_at(pv)
		print("CHASE END escaped=", escaped, " fell=", fell, " gap=", int(police.gap()), " v=", int(world.v_of(car.position)), " police_at=", psg["type"], "/", psg.get("kind", ""), " lat=", snappedf(police.lat, 0.01), " water=", world.water_at(police.position), " boosts=", run["boosts"])
	chase["done"] = true
	chase_state = "over"
	chase_over_t = 0.0
	police.stop()
	ui.chase_show(false)
	if escaped:
		run["chases"] += 1
		run_coins += 40
		run["coins"] = run_coins
		if fell:
			run["police_fell"] = int(run.get("police_fell", 0)) + 1
			_style(350, "Cop went over!", car.position, K.SKY, "+40 coins")
			ui.toast("The cruiser went over the edge!", "flag", Color("4b6bd6"), Color.WHITE, 2.0)
		else:
			_style(250, "Got away!", car.position, K.SKY, "+40 coins")
		sfx("mission")
		buzz(90, 0.9)
		fx.burst(car.position + Vector3(0, 0.8, 0), ["4b6bd6", "ff5a5a", "ffffff", "ffc94d"], 22, 5.0, 6.0)
	else:
		car.fuel = maxf(0.0, car.fuel - 0.3)
		ui.popup("Busted!", car.position + Vector3(0, 1.4, 0), Color("ff5a5a"), 52, "-30% fuel")
		sfx("bonk")
		sfx("lowfuel", -2.0, 0.7)
		buzz(160, 1.0)
		shake = maxf(shake, 0.35)
		car.slow = 0.5

func chase_siren() -> float:
	return chase_siren_k if chase_state in ["on", "over"] else 0.0

func chase_closeness() -> float:
	if chase_state != "on":
		return 0.0
	return clampf(1.0 - police.gap() / 20.0, 0.0, 1.0)

func _dust_color() -> Color:
	var b := world.biome_at(world.v_of(car.position))
	var slot: int = World.BIOME_TOP.get(b, PAL.GRASS)
	if car.surface == "ice":
		slot = PAL.ICE
	elif car.surface == "dirt":
		slot = World.ROUGH_TOP.get(b, PAL.PATH)
		return PAL.color(slot, atmos.season).lightened(0.12)
	elif car.surface == "slick":
		return Color("f0b88c")
	return PAL.color(slot, atmos.season).lightened(0.35)

func _finish_run(why: String) -> void:
	if state == OVER:
		return
	state = OVER
	_clear_touches()
	car.active = false
	sound.mute_loops(true)
	sound.set_muffle(0.6)
	ui.hide_hud()
	var dist := int(max_v)
	var score := dist + style + run_coins * 5
	var s = save.data
	s["coins"] = int(s["coins"]) + run_coins
	s["runs"] = int(s["runs"]) + 1
	var live := _ach_live()
	if daily:
		live["daily_runs"] = 1
	var ach_before := int(s["coins"])
	Ach.fold(s, live)
	var ach_late := Ach.check(s, {})
	var ach_coins := int(s["coins"]) - ach_before + ach_run_coins
	var ach_new: Array = ach_run.duplicate() + ach_late
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
		"run": run.duplicate(), "daily": daily, "date": today(), "ach": ach_new, "ach_coins": ach_coins}
	await get_tree().create_timer(0.35).timeout
	ui.show_over(result)
	_ach_announce(ach_late)

# ------------------------------------------------------------------ achievements

var ach_run: Array = []     # unlocked during the current run (already paid)
var ach_run_coins := 0

## The current run's counters, keyed like the lifetime stats.
func _ach_live() -> Dictionary:
	return {"distance": max_v, "max_dist": max_v, "max_kmh": Car.CRUISE * car.pace * 3.6 + 0.01,
		"coins": run_coins, "max_coins_run": run_coins,
		"drift": run["drift"], "max_drift": run.get("drift_max", 0.0), "max_chain": run.get("max_chain", 0),
		"jumps": run["jumps"], "spin720": run["spin720"], "spins": run["spins"], "clean": run["clean"],
		"near": run["near"], "knocks": run["knocks"], "planks": run.get("planks", 0), "tracks": run.get("tracks", 0),
		"grind": run.get("grind", 0.0), "gauntlets": run.get("gauntlets", 0), "police_fell": run.get("police_fell", 0),
		"decks": run.get("decks", 0), "chases": run["chases"], "max_regions": run["regions"], "stations": run["stations"],
		"night": run["night"], "weather": run["weather"], "max_score": int(max_v) + style + run_coins * 5}

func _ach_announce(list: Array) -> void:
	if list.is_empty():
		return
	for a in list:
		ui.toast("%s  +%d" % [a["name"], int(a["reward"])], "trophy", K.SUN, K.INK, 2.6)
		if state == RUN:
			ach_run.append(a)
			ach_run_coins += int(a["reward"])
	sfx("mission", -2.0, 1.12)
	buzz(70, 0.8)
	save.save()

## Garage and upgrade achievements (called by the UI after buying).
func ach_check() -> void:
	_ach_announce(Ach.check(save.data, {}))

# ------------------------------------------------------------------ camera

func _cam_update(dt: float, snap: bool) -> void:
	var target := car.position
	if car.dead and car.falling:
		target = Vector3(car.position.x, maxf(car.position.y, -1.5), car.position.z)
	var lead := world.F * ((4.4 if chase_state != "on" else 1.6) + (car.pace - 1.0) * 3.0) + Vector3(car.vel.x, 0, car.vel.z) * 0.16
	if state == TITLE or state == GARAGE:
		lead = world.F * 2.0
	var want := Vector3(target.x, maxf(target.y * 0.6, -1.0), target.z) + lead
	if snap:
		cam_focus = want
	else:
		cam_focus = cam_focus.lerp(want, 1.0 - exp(-dt * 4.0))
	var want_size := CAM_SIZE + (1.0 if not car.grounded and not car.dead else 0.0) + (1.2 if chase_state == "on" else 0.0) + (car.pace - 1.0) * 2.2
	if state == TITLE:
		want_size = CAM_SIZE - 1.8
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

## Arrow steering: a quick tap is a gentle turn; holding winds up to full lock (and a drift).
func _steer_input(dt: float) -> float:
	if autopilot:
		return _auto_steer()
	var left := Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)
	var right := Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)
	for side in touches.values():
		if side < 0:
			left = true
		else:
			right = true
	hold_l = hold_l + dt if left else 0.0
	hold_r = hold_r + dt if right else 0.0
	var l := lerpf(0.5, 1.0, smoothstep(0.0, 0.35, hold_l)) if left else 0.0
	var r := lerpf(0.5, 1.0, smoothstep(0.0, 0.35, hold_r)) if right else 0.0
	ui.arrows_pressed(left, right)
	return clampf(r - l, -1.0, 1.0)

## Which arrow a touch belongs to: the left or right half of the screen below the top bar.
func _arrow_side(p: Vector2) -> int:
	var vs := get_viewport().get_visible_rect().size
	if p.y < vs.y * 0.3:
		return 0
	return -1 if p.x < vs.x * 0.5 else 1

func _clear_touches() -> void:
	touches.clear()
	title_touch = -1
	hold_l = 0.0
	hold_r = 0.0
	ui.arrows_pressed(false, false)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			if ui.blocks(e.position):
				return
			if state == TITLE:
				title_touch = e.index
			elif state == RUN:
				var side := _arrow_side(e.position)
				if side != 0:
					touches[e.index] = side
		else:
			touches.erase(e.index)
			if state == TITLE and e.index == title_touch:
				title_touch = -1
				_start_run()
	elif e is InputEventScreenDrag and touches.has(e.index):
		# sliding a thumb across to the other side switches arrows
		var side := _arrow_side(e.position)
		if side != 0:
			touches[e.index] = side
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
	var aim := float(args.get("hug", "0"))
	var offs := [0.0, -1.2, 1.2, -2.4, 2.4]
	if args.has("hug"):
		offs = [aim, aim * 0.85, aim * 0.7, aim * 0.5, 0.0]
	for off in offs:
		var sc := 0.0
		for k in [3.0, 5.5, 8.0]:
			var q := world.pos_at(v + k, off)
			if world.ground_at(q) == World.NO_GROUND and world.ramp_at(q).is_empty():
				sc -= 3.0
		sc -= absf(off - aim) * 0.3
		if sc > best_score:
			best_score = sc
			best_off = off
	var tgt := world.pos_at(v + 5.0, best_off)
	var d := tgt - car.position
	var desired := atan2(-d.x, -d.z)
	var err := angle_difference(car.yaw, desired)
	var s := clampf(-err * 2.0 + car.yaw_rate * 0.3, -0.85, 0.85)
	if args.has("wiggle"):
		s = clampf(s + sin(run_t * 1.3) * 0.7, -1.0, 1.0)
	if args.has("drifttest") and run_t > 3.0 and run_t < 5.0:
		s = 1.0
		if frames % 8 == 0:
			print("DT t=%.2f drift=%.0f spd=%.2f yr=%.2f gr=%s" % [run_t, rad_to_deg(car.drift), car.speed(), car.yaw_rate, car.grounded])
	return s

## Testing: jump the car (and the crumble) ahead along the road.
func _warp(v: float) -> void:
	world.gen_s = int(floor((v - 24.0) / World.D))
	world._plan_until(v + 120.0)
	world.update_gen(v)
	var p := world.pos_at(v, 0.0)
	p.y = maxf(0.0, world.ground_at(p))
	var t := world.tangent(v)
	car.place(p, atan2(-t.x, -t.z))
	car.active = state == RUN
	world.crumble_v = v - 30.0
	world.crumble_s = int(floor(world.crumble_v / World.D))
	_cam_update(1.0, true)

func _harness() -> void:
	if args.has("perf") and state == RUN:
		perf_acc += Performance.get_monitor(Performance.TIME_PROCESS)
		perf_n += 1
		perf_max = maxf(perf_max, Performance.get_monitor(Performance.TIME_PROCESS))
		if perf_n >= 300:
			print("PERF v=%d avg=%.2fms max=%.2fms seg=%s" % [int(max_v), perf_acc / perf_n * 1000.0, perf_max * 1000.0, world.segment_at(world.v_of(car.position)).get("kind", "")])
			perf_acc = 0.0
			perf_n = 0
			perf_max = 0.0
	if args.has("trace") and frames == 5:
		var segs := []
		for sg in world.segments:
			segs.append("%s/%s@%d-%d" % [sg["type"], sg.get("kind", ""), int(sg["v0"]), int(sg["v1"])])
		print("SEGS ", segs, " forced=", world.forced_v, " mounds=", world.pools["mound"].used(), " cells=", world.bump_cells.size())
	if args.has("trace") and state == RUN and frames % 6 == 0:
		var cv := world.v_of(car.position)
		print("TR t=%.2f v=%.1f u=%.2f spd=%.2f yaw=%.2f drift=%.2f gr=%s steer=%.2f g=%.2f stuck=%.2f" % [run_t, cv, world.u_of(car.position) - world.center(cv), car.speed(), car.yaw, car.drift, car.grounded, car.steer, world.ground_at(car.position), car.stuck_t])
	if args.has("auto") and state == RUN and car.fuel > 0.0:
		slow_t = slow_t + get_process_delta_time() if car.speed() < 2.0 else 0.0
		slow_max = maxf(slow_max, slow_t)
	if args.has("shot"):
		var at := int(args.get("frames", "90"))
		if frames == at:
			var img := get_viewport().get_texture().get_image()
			img.save_png(String(args["shot"]))
			print("shot saved ", args["shot"], " hour=", atmos.hour, " night=", atmos.night, " state=", state, " v=", world.v_of(car.position), " tiles=", world.tiles.size(), " fuel=", car.fuel)
			if not args.has("keep"):
				get_tree().quit()
	if args.has("quit_after") and (run_t > float(args["quit_after"]) or (state == OVER and ui.over.visible)):
		print("RESULT t=%.1f dist=%d style=%d coins=%d dead=%s why=%s state=%d tiles=%d walls=%d stuck=%.2f" % [run_t, int(max_v), style, run_coins, car.dead, death, state, world.tiles.size(), wall_hits, slow_max])
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
			"trophies":
				for id in ["first_run", "d500", "plank1", "drift3", "coins500"]:
					save.data["ach"][id] = true
				save.data["stats"]["max_dist"] = 812
				save.data["stats"]["distance"] = 6400
				save.data["stats"]["chases"] = 2
				ui.open_achievements()
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
