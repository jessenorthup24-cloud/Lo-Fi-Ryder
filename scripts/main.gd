extends Node3D
## Lo-Fi Dryfter: an open-world drift game on a little island. This node runs the game: the camera, the
## controls, drift scoring, the challenges (drift zones, trials, hidden coins), places to find, saving.

const PAL := preload("res://scripts/core/palette.gd")
const M := preload("res://scripts/core/models.gd")
const MB := preload("res://scripts/core/mesh_builder.gd")
const Island := preload("res://scripts/game/island.gd")
const Car := preload("res://scripts/game/drift_car.gd")
const Fx := preload("res://scripts/game/fx.gd")
const Atmos := preload("res://scripts/game/atmos.gd")
const Sound := preload("res://scripts/game/sound.gd")
const SaveData := preload("res://scripts/game/save.gd")
const CARS := preload("res://scripts/game/cars.gd")
const UI := preload("res://scripts/ui/ui.gd")
const K := preload("res://scripts/ui/kit.gd")
const Ach := preload("res://scripts/game/achievements.gd")
const Pool := preload("res://scripts/game/pool.gd")
const Traffic := preload("res://scripts/game/traffic.gd")
const Route := preload("res://scripts/game/route.gd")
const Race := preload("res://scripts/game/race.gd")
const Police := preload("res://scripts/game/police.gd")
const Boats := preload("res://scripts/game/boats.gd")

enum { LOADING, TITLE, DRIVE, PAUSED, GARAGE }

const MEDAL_PAY := [0, 150, 350, 700]
const FUEL_PRICE := 1.0        # coins per percent of a tank
const REPAIR_PRICE := 2.0      # coins per percent of damage
const COIN_PICKUP := 25

var save: SaveData
var toon: ShaderMaterial
var island: Island
var car: Car
var fx: Fx
var traffic: Traffic
var atmos: Atmos
var sound: Sound
var ui: UI
var cam: Camera3D
var state := LOADING
var args := {}
var frames := 0
var autopilot := false
var time := 0.0

# controls
var touches := {}          # touch index -> control name
var held := {}             # control name -> true (touch or keyboard)
var keys := {}
# camera
var cam_yaw := 0.0
var cam_look := Vector3.ZERO   # which way the camera aims along the car (eased every frame: see _cam)
var cam_pos := Vector3.ZERO
var cam_mode := 0           # 0 near, 1 far, 2 close and low
# looking round: drag a finger anywhere off the buttons to swing the camera round the car, pinch to zoom
var look_yaw := 0.0
var look_pitch := 0.0
var wheel_idx := -1         # the finger on the steering wheel (-1: none)
var wheel_angle := 0.0      # how far it's turned (radians, + right)
var wheel_grab := 0.0       # (where on the rim the finger took hold)
const WHEEL_MAX := 1.35     # turned this far: full lock (about 77°: quick, but still fine-grained near the middle)
var look_yaw_t := 0.0       # where the finger has asked the view to go (the view eases there each frame,
var look_pitch_t := 0.0     # so touches arriving unevenly don't make it judder)
var look_t := 9.0           # since the last look drag
var cam_zoom := 1.0
var look_touches := {}      # touch index -> position
var shake := 0.0
var cam_kick := Vector3.ZERO      # the camera jolted by a knock (springs back)
var cam_kick_v := Vector3.ZERO
var fov_kick := 0.0
var fov_base := 62.0
var fire_t := 0.0
var _slow_until := 0
var title_t := 0.0
# drifting
var drift_on := false
var drift_pts := 0.0
var drift_off_t := 0.0
var drift_len := 0.0
var combo := 1
var combo_t := 0.0
var coin_frac := 0.0
var close := INF            # how near a wall or car the drift is running (m)
var close_t := 0.0
var close_shown := false
var prox_t := 0.0
var skid_acc := {}
var smoke_t := 0.0
# challenges
var zone := {}             # the attempt in progress
var zone_t := 0.0
var zone_pts := 0.0
var zone_out := 0.0
var trial := {}
var trial_t := 0.0
var trial_gate := 0
var trial_pts := 0.0
var markers := []          # {kind, id, pos, node, label}
var gate_nodes: Array = []
var coin_pool: Pool
var coins_live: Array = []
# the rest
var place_now := ""
var place_t := 0.0
var flip_t := 0.0
var stuck_t := 0.0
var save_t := 0.0
var ach_t := 0.0
var last_pos := Vector3.ZERO
var road_hint := Vector3.ZERO
var bump_cd := 0.0
var auto := {}
var auto_stuck := 0.0
var damage_told := false
var was_air := 0.0
var was_flipped := false
var hb_was := false
var auto_back := 0.0
# stunts
var jump := {}              # the jump in the air right now: {t, from, pitch, yaw, roll, hoops}
var boost_cd := 0.0
var loop_on := -1           # the loop you're going round (island.stunt.loops), -1: none
var loop_last := 0
var loop_flip := false      # been over the top of it yet
var loop_cam := 0.0         # how far the camera has moved out to watch the loop from the side
var last_sp := Vector3.INF  # where the car was last frame (for flying through hoops)
# fuel, gas stations and the GPS
var fuel := 100.0
var fuel_told := 0          # 1: told it's low, 2: told it's empty
var at_station := {}        # the station you're stopped at
var router: Route
var police: Police
var boats: Boats
var route := {}             # where the GPS is taking you: {pos, name, kind}
var route_pick := {}        # a place you picked on the map
var route_pts := PackedVector3Array()
var route_t := 0.0
var race: Race = null       # the street race on now
var in_marker := {}         # the beacon you're sitting in (its start card is up)
var nos_left := 3.0         # seconds of nitrous in the bottle
# ---- rewind: the last few seconds, kept so you can hold REWIND and take them back
var rw_buf: Array = []      # snapshots, oldest first
var rw_t := 0.0
var rewinding := false
var rw_pos := 0.0           # (where in the buffer the rewind is: fractional, so it plays back smoothly)
var rw_ghost := 0.0         # just after a rewind: the traffic can't hit you for a moment
const RW_SECS := 10.0
const RW_HZ := 20.0
var nos_on := false
var nos_fx_t := 0.0
var intro := {}             # a challenge getting going: {kind, id, t, said}: the title, then 3-2-1-GO
const INTRO_T := 2.4        # (how long the title shows before the countdown)
const KIND_INFO := {"zone": ["DRIFT ZONE", "ff8a5c"], "time": ["TIME TRIAL", "5cc8ff"], "drift": ["DRIFT RUN", "c38bff"],
	"race": ["STREET RACE", "ff5c7a"]}
var race_end_t := 0.0

func _ready() -> void:
	_parse_args()
	# landscape, laid out for 1280x720 whatever the installed app was built with
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if FileAccess.file_exists("user://content_pending"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://content_pending"))
	save = SaveData.new()
	if not args.has("fresh"):
		save.load_data()
	toon = ShaderMaterial.new()
	toon.shader = load("res://shaders/toon.gdshader")
	toon.set_shader_parameter("palette", PAL.make_texture())
	cam = Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # follows the car every frame
	cam.fov = 64.0
	cam.near = 0.25
	cam.far = 1400.0
	cam.cull_mask = 0xFFFFF & ~Island.MAP_LAYER
	cam.position = Vector3(-240, 30, 120)
	add_child(cam)
	cam.make_current()
	atmos = Atmos.new()
	add_child(atmos)
	atmos.setup(self, toon)
	if args.has("season"):
		atmos.set_season(int(args["season"]))
	if args.has("hour"):
		atmos.hour = float(args["hour"])
	sound = Sound.new()
	add_child(sound)
	sound.setup()
	ui = UI.new()
	add_child(ui)
	ui.setup(self)
	ui.show_loading()
	_apply_settings()

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"

## The island takes a moment to build; the loading card shows first.
func _build_world() -> void:
	var t0 := Time.get_ticks_msec()
	island = Island.new()
	island.name = "Island"
	add_child(island)
	island.build(toon, atmos.season)
	atmos.sea = island.water_mat
	atmos.add_material(island.road_mat)        # (roads: night, the lamps' light, the season)

	Ach.coin_total = island.coin_spots.size()
	fx = Fx.new()
	add_child(fx)
	fx.setup(toon)
	fx.ground = func(x: float, z: float) -> float: return island.height_at(x, z)
	atmos.add_material(fx.smoke_mat)
	traffic = Traffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(island, toon)
	boats = Boats.new()
	boats.name = "Boats"
	add_child(boats)
	boats.setup(island, toon, atmos)
	car = Car.new()
	car.name = "Car"
	# the car moves in physics steps (60 a second) but the screen may show more frames than that:
	# it's drawn smoothly in between. Everything else here moves every frame already.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	car.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(car)
	car.bumped.connect(_on_bump)
	car.rolled.connect(_on_roll)
	car.misfired.connect(_on_misfire)
	car.shifted.connect(func(_g): sound.rev(0.82); sound.shift())
	car.rammed.connect(func(b, v, j, at): traffic.knock(b, v, j, at))
	car_changed()
	fuel = clampf(float(save.data.get("fuel", 100.0)), 0.0, 100.0)
	nos_left = nos_cap()
	car.damage = clampf(float(save.data.get("damage", 0.0)), 0.0, 100.0)
	car.engine_dmg = clampf(float(save.data.get("engine", 0.0)), 0.0, 100.0)
	car.batter(hash(String(save.data["car"])))      # (it comes back looking as battered as it was)
	router = Route.new()
	router.build(island)
	police = Police.new()
	police.name = "Police"
	add_child(police)
	police.setup(self, island, traffic)
	car.rammed.connect(func(b, _v, _j, _at): police.rammed(b))
	for st in island.stations:
		island.map_marker(st["pos"], Color("4fb3a5"), 7.0)
	_build_markers()
	_build_coins()
	var sp := island.spawn
	var p: Array = save.data.get("pos", [])
	if p.size() == 4 and not args.has("fresh") and not args.has("at"):
		sp = Transform3D(Basis(Vector3.UP, float(p[3])), Vector3(p[0], p[1] + 1.0, p[2]))
	if args.has("at"):
		sp = _at_spot(String(args["at"]))
	if args.has("put"):
		# a test: exactly here (x,z,yaw degrees), off the road
		var q := String(args["put"]).split(",")
		var qx := float(q[0])
		var qz := float(q[1])
		sp = Transform3D(Basis(Vector3.UP, deg_to_rad(float(q[2]) if q.size() > 2 else 0.0)), Vector3(qx, island.height_at(qx, qz) + 0.9, qz))
	car.place(sp)
	if args.has("route"):
		var rq := String(args["route"]).split(",")
		route_pick = {"pos": Vector3(float(rq[0]), 0, float(rq[1])), "name": rq[2] if rq.size() > 2 else "Test", "kind": "pick"}
	if args.has("fuel"):
		fuel = float(args["fuel"])
	if args.has("damage"):
		car.damage = float(args["damage"])
		car.batter(7)
	if args.has("engine"):
		car.engine_dmg = float(args["engine"])
	if args.has("cam"):
		cam_mode = int(args["cam"])
	last_pos = sp.origin
	cam_yaw = sp.basis.get_euler().y
	_snap_cam()
	print("world ready in %d ms %s" % [Time.get_ticks_msec() - t0, str(island.timings)])
	ui.world_ready(island)
	if args.has("crashtest"):
		_crash_setup(String(args["crashtest"]), float(args.get("crashv", "18")))
	if args.has("ram"):
		# a test: park a traffic car on the road ahead to drive into
		var p2 := Vector2(sp.origin.x, sp.origin.z)
		var best := []
		for ri in island.roads.size():
			var rn: Array = island.road_nearest(ri, p2)
			if best.is_empty() or float(rn[0]) < float(best[0]):
				best = [rn[0], ri, rn[1]]
		var tc: Dictionary = traffic.cars[0]
		var f3 := -sp.basis.z
		var tt: Vector2 = traffic._lane(best[1], best[2], 1)[1]
		var dirn := 1 if tt.dot(Vector2(f3.x, f3.z)) >= 0.0 else -1
		tc["r"] = best[1]
		tc["s"] = float(best[2]) + dirn * float(args["ram"]) / island.CELL
		tc["dir"] = -dirn if args.has("headon") else dirn
		tc["mode"] = 0
		tc["hit"] = 9999.0
		traffic._put(tc)
		# line up behind it (or facing it)
		var np: Vector3 = (tc["body"] as Node3D).global_position
		var off := Vector3(np.x - sp.origin.x, 0, np.z - sp.origin.z)
		var side := Vector3(-f3.z, 0, f3.x)
		car.place(Transform3D(sp.basis, sp.origin + side * off.dot(side) + Vector3(0, 0.3, 0)))
	if args.has("tunetest"):
		# a test: this tuning on the car you drive (camber,height,neon), with the neon kit
		var tq := String(args["tunetest"]).split(",")
		save.data["neon_kit"] = true
		save.data["tune"][String(save.data["car"])] = {"camber": int(tq[0]), "height": int(tq[1]), "neon": int(tq[2])}
		car_changed()
	if args.has("aim"):
		# a test: lined up 22 m from a tree, a street lamp or a traffic light, with a clear run at it
		var want := String(args["aim"])
		var cands := []
		if want == "lamp":
			for bk in island.breakables:
				if String(bk["pool"]).contains("light-single"):
					cands.append(bk["home"])
		else:
			for tr in island.topples:
				if (tr["kind"] == "tree") == (want == "tree"):
					cands.append(tr["pos"])
		var c0 := Vector3(-150, 0, 100) if want != "tree" else Vector3(150, 0, 120)
		cands.sort_custom(func(a1, b1): return (a1 as Vector3).distance_to(c0) < (b1 as Vector3).distance_to(c0))
		var space := get_world_3d().direct_space_state
		var done := false
		for tp in cands.slice(0, 60):
			for k in 12:
				var d := Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0))
				var st := (tp as Vector3) + d * 22.0
				st.y = island.height_at(st.x, st.z)
				if absf(st.y - (tp as Vector3).y) > 1.0 or island.is_blocked(st.x, st.z) and want == "tree":
					continue
				var q := PhysicsRayQueryParameters3D.create(st + Vector3(0, 0.8, 0), (tp as Vector3) + Vector3(0, 0.8, 0) + d * 1.2, 1 | 2)
				var q2 := PhysicsRayQueryParameters3D.create(st + Vector3(0, 0.8, 0) + d.cross(Vector3.UP) * 1.0, (tp as Vector3) + Vector3(0, 0.8, 0) + d * 1.2 + d.cross(Vector3.UP) * 1.0, 1 | 2)
				var q3 := PhysicsRayQueryParameters3D.create(st + Vector3(0, 0.8, 0) - d.cross(Vector3.UP) * 1.0, (tp as Vector3) + Vector3(0, 0.8, 0) + d * 1.2 - d.cross(Vector3.UP) * 1.0, 1 | 2)
				if space.intersect_ray(q).is_empty() and space.intersect_ray(q2).is_empty() and space.intersect_ray(q3).is_empty():
					car.place(Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), st + Vector3(0, 0.9, 0)))
					print("AIM %s at (%.1f, %.1f) from (%.1f, %.1f)" % [want, tp.x, tp.z, st.x, st.z])
					done = true
					break
			if done:
				break
	if args.has("sheet"):
		# a test: open a screen for a screenshot (settings, help)
		save.data["seen_help"] = true
		start_drive()
		match String(args["sheet"]):
			"settings":
				ui.open_settings()
			"help":
				ui.show_help()
			"map":
				ui.open_map()
	elif args.has("garage"):
		open_garage()
		if String(args["garage"]) in ["up", "paint", "tune"]:
			ui.g_tab = String(args["garage"])
			ui.g_paint = int(args.get("paintprev", "-1"))
			ui._garage_refresh()
	elif args.has("auto") or args.has("drive"):
		autopilot = args.has("auto")
		start_drive()
		if args.has("race"):
			# a test: straight into a street race (--raceauto: and the CPU drives your car too)
			_start_race(String(args["race"]))
		if args.has("resulttest"):
			# a test: the results card with this medal (0-3)
			get_tree().create_timer(0.5).timeout.connect(func(): ui.challenge_result("Main Street Sprint", "24.31 s", int(args["resulttest"]), 400, true))
		if args.has("begin"):
			# a test: as if START was pressed (kind:id, e.g. race:downtown, zone:bowl, trial:coast)
			var bq := String(args["begin"]).split(":")
			start_challenge_now(bq[0], bq[1])
		if args.has("wanted"):
			# a test: the police are after you from the start (at this heat)
			police.start(float(args["wanted"]), "A test")
	else:
		state = TITLE
		ui.show_title()
	if save.data.get("migrated", false):
		save.data.erase("migrated")
		get_tree().create_timer(1.5).timeout.connect(func(): ui.toast("Welcome to the island! Your old upgrades were refunded as coins.", "coin", K.SUN))
	sound.start_music()
	get_tree().create_timer(2.0).timeout.connect(ach_check)

## Testing: start at a named place or "x,z".
func _at_spot(s: String) -> Transform3D:
	var pos := Vector3.ZERO
	var yaw := 0.0
	if "," in s:
		var xz := s.split(",")
		pos = Vector3(float(xz[0]), 0, float(xz[1]))
		if xz.size() > 2:
			yaw = deg_to_rad(float(xz[2]))
	else:
		for z in island.zones:
			if z["id"] == s:
				pos = z["start"]
		for t in island.trials:
			if t["id"] == s:
				return (t["gates"][0] as Transform3D).translated(Vector3(0, 1.0, 0)).translated_local(Vector3(0, 0, 14))
		for pl in island.places:
			if String(pl["name"]).to_lower().begins_with(s.to_lower()):
				pos = pl["pos"]
	return _road_spot(pos, yaw)

## The nearest bit of road to p, pointing along it (the way closest to yaw).
func _road_spot(p: Vector3, yaw: float) -> Transform3D:
	var best := Vector2.ZERO
	var bt := Vector2(0, -1)
	var bd := 1e18
	for r in island.roads:
		var pts: PackedVector2Array = r["pts"]
		for k in range(0, pts.size(), 2):
			var d := pts[k].distance_squared_to(Vector2(p.x, p.z))
			if d < bd:
				bd = d
				best = pts[k]
				bt = island._tangent(pts, k, r["closed"])
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	if bt.dot(fwd) < 0.0:
		bt = -bt
	var y := island.height_at(best.x, best.y) + 0.9
	return Transform3D(Basis(Vector3.UP, atan2(-bt.x, -bt.y)), Vector3(best.x, y, best.y))

# ------------------------------------------------------------------ states

func start_drive() -> void:
	if state == TITLE:
		sound.start_engine()
	state = DRIVE
	ui.show_hud()
	car.freeze = false
	if not bool(save.data.get("seen_help", false)) and not autopilot and not args.has("drive"):
		save.data["seen_help"] = true
		ui.show_help()

func go_title() -> void:
	_save_now()
	state = TITLE
	_end_challenges()
	police.clear()
	ui.show_title()

func pause() -> void:
	if state != DRIVE:
		return
	state = PAUSED
	get_tree().paused = false
	car.freeze = true
	if race != null:
		race.hold(true)
	police.hold(true)
	sound.mute_loops(true)
	if island.rail:
		island.rail.quiet(true)
	ui.open_pause()
	_save_now()

func resume() -> void:
	if state != PAUSED:
		return
	state = DRIVE
	car.freeze = false
	if race != null:
		race.hold(false)
	police.hold(false)
	sound.mute_loops(false)
	if island.rail:
		island.rail.quiet(false)
	ui.close_sheet()
	ui.show_hud()

func open_garage() -> void:
	if police.wanted():
		ui.toast("Lose the police first", "eye", Color("ff5c7a"), Color.WHITE)
		return
	_save_now()
	var from := state
	state = GARAGE
	car.freeze = true
	if race != null:
		race.hold(true)
	police.hold(true)
	sound.mute_loops(true)
	ui.show_garage(from)

func close_garage(back_to: int) -> void:
	ui.hide_garage()
	sound.mute_loops(false)
	if back_to == DRIVE or back_to == PAUSED:
		state = DRIVE
		car.freeze = false
		if race != null:
			race.hold(false)
		police.hold(false)
		ui.show_hud()
	else:
		state = TITLE
		ui.show_title()

func car_changed() -> void:
	var d := CARS.by_id(String(save.data["car"]))
	var xf := car.global_transform if car.is_inside_tree() and car.wheels.size() > 0 else Transform3D()
	var dmg := car.damage
	var edmg := car.engine_dmg
	var bnt := car.bent
	car.setup(d, toon, island, int(save.data["paint"].get(String(d["id"]), 0)))
	car.damage = dmg          # (a different car doesn't mean a repaired one)
	car.engine_dmg = edmg
	car.bent = bnt
	car.batter(hash(String(d["id"])))
	car.tune(d, save.data["up"], save.data["tune"].get(String(d["id"]), {}))
	car.assist = 1.0 if bool(save.setting("assist")) else 0.35
	if xf != Transform3D():
		car.place(Transform3D(Basis(Vector3.UP, xf.basis.get_euler().y), xf.origin + Vector3(0, 0.6, 0)))
	sound.set_engine(String(d["engine"]), float(d["pitch"]))
	sound.turbo = int(save.data["up"].get("turbo", 0))

func reset_car() -> void:
	rw_buf.clear()
	if race != null and race.state == 1:
		# in a race: back to the last checkpoint
		var lc := int(race.you["last_cp"])
		race.you["s"] = (float(lc / race.cps.size()) * race.length + float(race.cps[lc % race.cps.size()])) if lc >= 0 else -9.0
		race._respawn(race.you, 0.0)
		_snap_cam()
		return
	var p := car.global_position
	var xf := _road_spot(p, car.global_rotation.y)
	# in the stunt yard: back to the start of the nearest run
	if (island.stunt["rect"] as Rect2).grow(10.0).has_point(Vector2(p.x, p.z)):
		var best := 1e9
		for r in island.stunt["resets"]:
			var d := ((r as Transform3D).origin - p).length()
			if d < best:
				best = d
				xf = r
	jump = {}
	loop_on = -1
	car.place(xf)
	_break_drift(false)
	flip_t = 0.0
	stuck_t = 0.0
	_snap_cam()
	fx.puff(xf.origin, Color(1, 1, 1), 2.5, Vector3.ZERO, 0.6, 1.0)
	if state == PAUSED:
		resume()

## Fast travel from the map.
func travel_to(xf: Transform3D) -> void:
	if police.wanted():
		ui.toast("Lose the police first", "eye", Color("ff5c7a"), Color.WHITE)
		if state == PAUSED:
			resume()
		return
	rw_buf.clear()
	_end_challenges()
	jump = {}
	loop_on = -1
	car.place(xf)
	_break_drift(false)
	_snap_cam()
	if state == PAUSED:
		resume()
	elif state == TITLE:
		start_drive()

func reset_progress() -> void:
	save.reset()
	for c in coins_live:
		c["taken"] = false
	_refresh_coins()
	car_changed()
	ui.close_sheet()
	ui.toast("Progress reset", "home", K.PAPER)

func set_setting(k: String, v) -> void:
	save.data["settings"][k] = v
	save.save()
	_apply_settings()

func _apply_settings() -> void:
	var st = save.data["settings"]
	sound.set_volumes(float(st["music"]), float(st["sfx"]))
	atmos.sun.shadow_enabled = bool(st["shadows"])
	atmos.env.glow_enabled = bool(st.get("bloom", true))
	Engine.max_fps = 60 if bool(st.get("fps60", false)) else 0
	cam_mode = clampi(int(st.get("cam", 0)), 0, 2)
	cam_zoom = clampf(float(st.get("zoom", 1.0)), 0.55, 1.7)
	if car:
		car.assist = 1.0 if bool(st.get("assist", true)) else 0.35

func _save_now() -> void:
	if car and car.is_inside_tree():
		var p := car.global_position
		save.data["pos"] = [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1), snappedf(car.global_rotation.y, 0.01)]
		save.data["fuel"] = snappedf(fuel, 0.1)
		save.data["damage"] = snappedf(car.damage, 0.1)
		save.data["engine"] = snappedf(car.engine_dmg, 0.1)
	save.save()

# ------------------------------------------------------------------ feedback

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

func ach_check() -> void:
	var got := Ach.check(save.data)
	for a in got:
		ui.toast("Trophy: %s  +%d" % [a["name"], int(a["reward"])], a["icon"], K.SUN)
		sfx("mission")
	if not got.is_empty():
		save.save()

# ------------------------------------------------------------------ every frame

func _process(dt: float) -> void:
	frames += 1
	if args.has("interp") and state == DRIVE and time > 4.0 and time < 4.2:
		# testing: is the car drawn smoothly between physics steps? (run with --fixed-fps 120)
		var xi := car.get_global_transform_interpolated().origin
		print("INTERP f=%d frac=%.2f drawn=(%.3f,%.3f) physics=(%.3f,%.3f) cam=(%.3f,%.3f) mesh=(%.3f,%.3f)" % [frames, Engine.get_physics_interpolation_fraction(),
			xi.x, xi.z, car.global_position.x, car.global_position.z, cam.global_position.x, cam.global_position.z,
			car.body_node.get_global_transform_interpolated().origin.x, car.body_node.get_global_transform_interpolated().origin.z])
	if args.has("hitch") and state == DRIVE:
		# testing: report frames that took far longer than the rest (stutters you'd feel)
		var pt := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var ph := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		if pt > 6.0 or ph > 6.0:
			print("HITCH t=%.2f process=%.1f ms physics=%.1f ms save_t=%.1f ach_t=%.1f route_t=%.1f" % [time, pt, ph, save_t, ach_t, route_t])
	if state == LOADING:
		if frames == 3:
			_build_world()
		return
	dt = minf(dt, 0.05)
	time += dt
	atmos.tick(dt)
	if state == DRIVE or state == TITLE:
		atmos.motes_tick(cam.global_position, -cam.global_transform.basis.z, bool(save.setting("motes")))
	if island and state != LOADING:
		_lamp_lights(dt)
	if car and car.neon_node:
		(car.neon_node.get_meta("pool_mat") as ShaderMaterial).set_shader_parameter("night", atmos.night)
		car.neon_tick(car.get_global_transform_interpolated())
	var cp := car.global_position
	boats.tick(dt)
	if island.rail and (state == DRIVE or state == TITLE):
		island.rail.tick(dt, cam.global_position)
	island.tick(dt, cp, car.linear_velocity)
	traffic.tick(dt, cp, car.linear_velocity, -cam.global_transform.basis.z)
	if traffic.honk != Vector3.INF and state == DRIVE:
		var hd: float = traffic.honk.distance_to(cp)
		sfx(traffic.honk_kind, clampf(-4.0 - hd * 0.3, -16.0, -4.0), randf_range(0.95, 1.08))
	fx.tick(dt)
	_coins_tick(dt)
	_markers_tick(dt)
	match state:
		TITLE:
			_controls_off()
			car.handbrake = 1.0
			_title_cam(dt)
		DRIVE:
			_controls(dt)
			_intro_tick(dt)
			_rewind_tick(dt)
			# (the camera first: the HUD works out where the car is on screen from it, this frame's view)
			_cam(dt)
			if not rewinding:
				_drive(dt)
			else:
				ui.hud_update_light()
			police.tick(dt)
		PAUSED, GARAGE:
			_controls_off()
	_sound(dt)
	ui.tick(dt)
	if args.has("ram") and frames % 10 == 0 and traffic:
		var tc2: Dictionary = traffic.cars[maxi(traffic.last_knock, 0)]
		var tb: Node3D = tc2["body"]
		print("ram t=%.2f v=%.0f dmg=%.0f | npc mode=%d pos=(%.1f,%.1f,%.1f) up=%.2f v=%.1f" % [time, car.speed * 3.6, car.damage, tc2["mode"],
			tb.global_position.x, tb.global_position.y, tb.global_position.z, tb.global_transform.basis.y.y, (tb as RigidBody3D).linear_velocity.length() if tb is RigidBody3D else float(tc2["v"])])
	if args.has("trafficdebug") and frames % 60 == 0 and traffic:
		var near := 0
		var moving := 0
		for c in traffic.cars:
			var d: float = (c["body"] as Node3D).global_position.distance_to(cp)
			if d < 120.0:
				near += 1
			if float(c["v"]) > 1.0:
				moving += 1
		print("traffic near=%d moving=%d first=%s" % [near, moving, str((traffic.cars[0]["body"] as Node3D).global_position)])
	if args.has("buytest") and state == DRIVE and frames == 150:
		# a test: what a fill-up and a repair cost and do
		save.data["coins"] = int(args["buytest"])
		print("BUY before: fuel %.0f damage %.0f coins %d at %s" % [fuel, car.damage, int(save.data["coins"]), str(at_station.get("name", "-"))])
		buy_fuel()
		buy_repair()
		print("BUY after: fuel %.0f damage %.0f coins %d" % [fuel, car.damage, int(save.data["coins"])])
	if args.has("looktest") and state == DRIVE:
		# a test: a finger dragged across the empty middle of the screen (and, with =pinch, a second one)
		var f0 := int(args.get("shot_at", "200")) - 40
		if frames == f0:
			var ev := InputEventScreenTouch.new()
			ev.index = 7
			ev.position = Vector2(640, 300)
			ev.pressed = true
			Input.parse_input_event(ev)
		elif frames > f0 and frames < f0 + 30:
			var ev2 := InputEventScreenDrag.new()
			ev2.index = 7
			ev2.position = Vector2(640 + (frames - f0) * 14, 300 + (frames - f0) * 3)
			Input.parse_input_event(ev2)
	if args.has("shot") and frames == int(args.get("shot_at", "200")):
		get_viewport().get_texture().get_image().save_png(String(args["shot"]))
	if args.has("shot_t") and not has_meta("shot_done") and time >= float(String(args["shot_t"]).split(":")[0]):
		# a test: a screenshot at a game time (shot_t=seconds:file)
		set_meta("shot_done", true)
		get_viewport().get_texture().get_image().save_png(String(args["shot_t"]).split(":")[1])
	if args.has("quit_after") and (time > float(args["quit_after"]) or (args.has("shot") and frames > int(args.get("shot_at", "200")) + 2)):
		print("RESULT t=%.1f dist=%.0f drift=%.0f coins=%d max_kmh=%.0f knocks=%.0f state=%d tris=%d draws=%d" % [time, save.stat("distance"),
			save.stat("drift_points"), int(save.data["coins"]), save.stat("max_kmh"), save.stat("knocks"), state,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		get_tree().quit()

func _controls_off() -> void:
	car.throttle = 0.0
	car.brake = 0.0
	car.steer_in = 0.0
	car.handbrake = 0.0

func _controls(dt: float) -> void:
	if args.has("crashtest"):
		_crash_controls()
		return
	if autopilot:
		_autopilot(dt)
		return
	if args.has("stunt"):
		_stunt_test()
		return
	if args.has("demo"):
		# a scripted drift for screenshots: get going, flick it, hold it
		var dt2 := time - float(auto.get("demo0", time))
		auto["demo0"] = float(auto.get("demo0", time))
		var go := float(args.get("demo", "1"))
		if go < 2.0:
			go = 2.6
		car.throttle = 1.0
		car.steer_in = 1.0 if dt2 > go else 0.0
		car.handbrake = 1.0 if dt2 > go and dt2 < go + 0.3 else 0.0
		car.brake = 0.0
		if args.has("autodebug") and frames % 15 == 0:
			print("demo t=%.2f v=%.0f slip=%.0f drift=%.2f on=%s pts=%.0f x%d close=%.1f" % [dt2, car.speed * 3.6, rad_to_deg(car.slip), car.drift, drift_on, drift_pts, combo, close])
		return
	var l := 1.0 if held.get("left", false) else 0.0
	var r := 1.0 if held.get("right", false) else 0.0
	if wheel_idx >= 0:
		car.steer_in = clampf(wheel_angle / WHEEL_MAX, -1.0, 1.0)      # (the wheel: as far as you've turned it)
	else:
		# let go: the wheel springs back to the middle (keys and buttons steer as before)
		wheel_angle = move_toward(wheel_angle, (r - l) * WHEEL_MAX, get_process_delta_time() * 11.0)
		car.steer_in = r - l if (l > 0.0 or r > 0.0) else clampf(wheel_angle / WHEEL_MAX, -1.0, 1.0)
	car.throttle = 1.0 if held.get("gas", false) else 0.0
	car.brake = 1.0 if held.get("brake", false) else 0.0
	car.handbrake = 1.0 if held.get("hand", false) else 0.0
	ui.pressed_controls(held)

## Tests: crashes on the Raceway's main straight (flat and open, a wall along its north side), logged:
##   --crashtest=tbone   a car driven into your side at --crashv m/s (you sit still)
##   --crashtest=wall    you, sliding sideways into the wall at --crashv
##   --crashtest=front   you, nose first into the wall at --crashv (gas held: engine damage, misfires, fire)
##   --crashtest=swipe   you at --crashv alongside a car going slower, steering into it for a second
##                       (swipe0: the same without it there, for comparison)
func _crash_setup(kind: String, v: float) -> void:
	var y := island.height_at(470.0, 372.0) + 0.75
	auto["crash"] = kind
	auto["crash_t0"] = time
	match kind:
		"tbone":
			car.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(470, y, 372)))
			auto["bullet"] = _crash_car(Transform3D(Basis(), Vector3(470, y, 389)), Vector3(0, 0, -v))
		"wall":
			car.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(470, y, 369)))
			car.linear_velocity = Vector3(0, 0, -v)
		"front":
			car.place(Transform3D(Basis(), Vector3(470, y, 389)))
			car.linear_velocity = Vector3(0, 0, -v)
		"swipe", "swipe0":
			car.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(400, y, 370.2)))
			car.linear_velocity = Vector3(v, 0, 0)
			if kind == "swipe":
				auto["bullet"] = _crash_car(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(412, y, 374.0)), Vector3(v * 0.55, 0, 0))
	car._last_v = car.linear_velocity          # (setting off at speed isn't a knock)
	car.reset_physics_interpolation()
	_snap_cam()

func _crash_car(xf: Transform3D, vel: Vector3) -> Car:
	var d := CARS.by_id("police")
	var c: Car = Car.new()
	c.set_meta("racer", true)
	c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(c)
	c.setup(d, toon, island, 0)
	c.tune(d, save.data["up"])
	c.collision_layer = 16                   # (as a police car is: it meets yours)
	c.collision_mask = 1 | 2 | 4 | 16
	c.place(xf)
	c.linear_velocity = vel
	c._last_v = vel
	c.reset_physics_interpolation()
	return c

func _crash_controls() -> void:
	var kind: String = auto.get("crash", "")
	var t: float = time - float(auto.get("crash_t0", 0.0))
	car.brake = 0.0
	car.handbrake = 0.0
	car.steer_in = 0.0
	car.throttle = 1.0 if kind in ["front", "swipe", "swipe0"] else 0.0
	if kind == "front" and t > 4.0:
		car.steer_in = sin(t * 0.7) * 0.6           # (driving about on what's left of the engine)
	if kind in ["swipe", "swipe0"] and t > 0.3 and t < 1.3:
		car.steer_in = float(args.get("swipesteer", "0.35"))   # (in towards the other car)
	if auto.has("bullet"):
		var b: Car = auto["bullet"]
		b.throttle = 0.6 if kind == "swipe" else 0.0
		b.steer_in = 0.0
	if frames % 6 == 0:
		var hv := Vector3(car.linear_velocity.x, 0, car.linear_velocity.z).length()
		print("CRASH %s t=%.2f v=%.1f up=%.2f dmg=%.0f eng=%.0f bent=%.2f roll=%.1f righting=%s misfire=%s pos=(%.1f,%.1f,%.1f)" % [kind, t, hv * 3.6,
			car.global_transform.basis.y.y, car.damage, car.engine_dmg, car.bent, car.roll_t, car.righting(), car.misfiring(),
			car.global_position.x, car.global_position.y, car.global_position.z]
			+ (" | other (%.1f,%.1f,%.1f) v=%.1f up=%.2f" % [(auto["bullet"] as Node3D).global_position.x, (auto["bullet"] as Node3D).global_position.y,
				(auto["bullet"] as Node3D).global_position.z, (auto["bullet"] as RigidBody3D).linear_velocity.length() * 3.6, (auto["bullet"] as Node3D).global_transform.basis.y.y] if auto.has("bullet") else ""))

## A test: hold the gas along the line the car started on, then do a trick in the air:
## --stunt=straight|backflip|frontflip|spin|roll|level  (logs every few frames)
func _stunt_test() -> void:
	if not auto.has("line"):
		auto["line"] = car.global_transform
	var o: Transform3D = auto["line"]
	var dir := -o.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var xf := car.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	var off := (car.global_position - o.origin).dot(dir.cross(Vector3.UP))
	var herr := atan2(dir.cross(fwd.normalized()).y, dir.dot(fwd.normalized()))
	car.throttle = 1.0
	car.brake = 0.0
	car.handbrake = 0.0
	car.steer_in = 0.0
	if car.grounded >= 2 and loop_on < 0:
		car.steer_in = clampf(-off * 0.25 + herr * 1.4, -1.0, 1.0)
	var air := car.grounded == 0 and car.air_t > 0.2
	if car.grounded == 0 and not air:
		car.throttle = 0.0      # (off the gas at the lip, so pressing it again in the air counts)
	# (let go once the trick's round, and let it settle for the landing)
	var done := not jump.is_empty() and maxf(absf(float(jump["pitch"])), maxf(absf(float(jump["roll"])), absf(float(jump["yaw"])))) > float(args.get("turn", "5.0"))
	if air and done:
		car.throttle = 0.0
	elif air:
		match String(args["stunt"]):
			"backflip":
				car.throttle = 0.0
				car.brake = 1.0
			"spin":
				car.throttle = 0.0
				car.steer_in = 1.0
			"roll":
				car.throttle = 0.0
				car.handbrake = 1.0
				car.steer_in = 1.0
			"level":
				car.throttle = 0.0
	if frames % 6 == 0:
		var p := car.global_position
		print("st t=%.2f p=(%.1f,%.1f,%.1f) v=%.1f up=%.2f gr=%d on=%d air=%.2f loop=%d/%s jump=%s pts=%.0f" % [time, p.x, p.y, p.z,
			car.linear_velocity.length(), xf.basis.y.y, car.grounded, car.on_stunt, car.air_t, loop_on, str(loop_flip),
			"" if jump.is_empty() else "t%.1f p%.1f y%.1f r%.1f" % [jump["t"], jump["pitch"], jump["yaw"], jump["roll"]], save.stat("stunt_points")])

func _drive(dt: float) -> void:
	var p := car.global_position
	var v := car.linear_velocity
	# (flipping in the air, the speed along the nose means nothing: show how fast it's flying)
	var kmh := (car.linear_velocity.length() if car.grounded == 0 else absf(car.speed)) * 3.6
	# distance and records
	var step := Vector2(p.x - last_pos.x, p.z - last_pos.z).length()
	if step < 5.0:
		save.add_stat("distance", step)
		if atmos.is_night():
			save.add_stat("night", step)
	last_pos = p
	if car.grounded > 0:
		save.max_stat("max_kmh", kmh)   # (on the road: a long fall doesn't count)
	if car.air_t > 0.0:
		save.max_stat("max_air", car.air_t)
	_drift(dt)
	_nitrous(dt)
	_fuel(dt)
	_stations_tick()
	_route_tick(dt)
	_stunts(dt)
	_effects(dt)
	_impacts(dt)
	_breakables()
	_zone_tick(dt)
	_trial_tick(dt)
	_race_tick(dt)
	_places(dt)
	_recover(dt)
	bump_cd = maxf(0.0, bump_cd - dt)
	save_t += dt
	if save_t > 20.0:
		save_t = 0.0
		_save_now()
	ach_t += dt
	if ach_t > 2.0:
		ach_t = 0.0
		ach_check()
	ui.hud_update({"kmh": kmh, "gear": car.gear, "rpm": car.rpm, "drift": drift_pts, "combo": combo, "combo_t": combo_t,
		"drifting": drift_on, "coins": int(save.data["coins"]), "place": place_now, "clock": atmos.clock_text(),
		"zone": zone, "zone_t": zone_t, "zone_pts": zone_pts, "trial": trial, "trial_t": trial_t, "trial_gate": trial_gate,
		"trial_pts": trial_pts, "race": {} if race == null else race.hud(), "car_pos": car.get_global_transform_interpolated().origin, "car_yaw": car.global_rotation.y, "angle": rad_to_deg(absf(car.slip)),
		"close": drift_on and close < 1.6 and car.drift > 0.2, "damage": car.damage, "engine": car.engine_dmg, "fuel": fuel,
		"nos": nos_left / nos_cap(), "nos_on": car.nitro, "wheel": wheel_angle / WHEEL_MAX, "police": police.hud()})

# ------------------------------------------------------------------ drifting

func _drift(dt: float) -> void:
	var sideways := car.drift > 0.2 and car.grounded >= 2 and car.speed > 6.0
	if sideways:
		if not drift_on:
			drift_on = true
			drift_pts = 0.0
			drift_len = 0.0
			close_t = 0.0
			close_shown = false
			if combo_t > 0.0:
				combo = mini(combo + 1, 10)
		drift_off_t = 0.0
		drift_len += dt
		# skimming a wall, a parked car or the traffic: half as much again
		prox_t -= dt
		if prox_t <= 0.0:
			prox_t = 0.08
			close = _proximity()
		var near := close < 1.6 and car.drift > 0.2
		if near:
			close_t += dt
			if close_t > 0.3 and not close_shown:
				close_shown = true
				ui.popup_text("Close!", K.SUN)
				sfx("near", -4.0)
				save.add_stat("close_calls", 1)
		var ang := rad_to_deg(absf(car.slip))
		# held in the sweet spot (not too shallow, not too sideways): worth more
		var sweet: bool = ang >= Car.SWEET[0] and ang <= Car.SWEET[1]
		drift_pts += dt * ang * 0.65 * maxf(car.speed, 0.0) * (1.5 if near else 1.0) * (1.4 if sweet else 1.0)
		# hold it long enough and the multiplier ticks up too
		if drift_len > 3.0:
			drift_len -= 3.0
			combo = mini(combo + 1, 10)
			ui.combo_bump(combo)
		combo_t = 2.2
	elif drift_on:
		drift_off_t += dt
		if drift_off_t > 0.55:
			_bank()
	elif car.grounded > 0:
		# (it keeps while you're in the air, so a jump can carry a combo on)
		combo_t = maxf(0.0, combo_t - dt)
		if combo_t <= 0.0:
			combo = 1

func _bank() -> void:
	drift_on = false
	var total := int(drift_pts * combo)
	if total < 50:
		return
	save.add_stat("drift_points", total)
	save.add_stat("drifts", 1)
	save.max_stat("max_drift", total)
	save.max_stat("max_combo", combo)
	coin_frac += total / 120.0
	var c := int(coin_frac)
	coin_frac -= c
	save.data["coins"] = int(save.data["coins"]) + c
	if not zone.is_empty() and _in_zone():
		zone_pts += total
	if not trial.is_empty() and trial["kind"] == "drift":
		trial_pts += total
	ui.banked(total, c)
	if total > 1500:
		island.people.cheer(car.global_position)
		sfx("near", -2.0)
	sfx("coin", -6.0, 1.0 + minf(total / 20000.0, 0.5))

## How close the car's sides and tail run to a wall or another car (m), out to 2 m; INF if nothing.
func _proximity() -> float:
	var xf := car.global_transform
	var w: float = float(car.info["width"]) * 0.5
	var l: float = float(car.info["length"]) * 0.5
	var space := get_world_3d().direct_space_state
	var o := xf.origin + xf.basis.y * 0.8
	var best := INF
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0.6, 0, 0.8), Vector3(-0.6, 0, 0.8)]:
		var dir: Vector3 = xf.basis * d
		var ext: float = absf(d.x) * w + absf(d.z) * l
		ext = minf(ext, w / maxf(absf(d.x), 0.01)) if d.z != 0.0 and d.x != 0.0 else ext
		var q := PhysicsRayQueryParameters3D.create(o, o + dir * (ext + 2.0), 1 | 2)
		q.exclude = [car.get_rid()]
		var h := space.intersect_ray(q)
		if not h.is_empty() and (h["normal"] as Vector3).y < 0.6:
			best = minf(best, o.distance_to(h["position"]) - ext)
	return best

## A crash loses the drift in progress.
func _break_drift(show := true) -> void:
	if drift_on and drift_pts * combo > 200 and show:
		ui.drift_lost()
		sfx("bonk")
	drift_on = false
	drift_pts = 0.0
	combo = 1
	combo_t = 0.0

func _on_bump(strength: float) -> void:
	if state != DRIVE or bump_cd > 0.0:
		return
	bump_cd = 0.4
	shake = minf(1.0, strength / 12.0)
	buzz(int(clampf(strength * 6.0, 20.0, 90.0)), clampf(strength / 12.0, 0.2, 1.0))
	# what did we hit, and where?
	var h: Dictionary = car.hit
	var fresh: bool = not h.is_empty() and car._clock - float(h["t"]) < 0.3
	var kind: String = h["kind"] if fresh else "ground"
	var at: Vector3 = h["pos"] if fresh else car.global_position
	var vol := clampf(-12.0 + strength * 0.8, -12.0, 0.0)
	if kind == "car":
		sfx("crash_heavy" if strength > 13.0 else ("crash_car" if strength > 6.0 else "fender"), vol)
	elif kind == "wall":
		sfx("crash_heavy" if strength > 14.0 else ("crash_wall" if strength > 7.0 else ("fender" if strength > 3.5 else "bump")), vol)
	else:
		sfx("bump", clampf(-10.0 + strength, -10.0, 2.0))
	if strength > 7.0:
		_break_drift()
	if strength > 3.0 and kind != "car":
		traffic.hit(car.global_position)
	# crash damage: a dent where it hit, bits flying, and the car slowly getting more battered
	if fresh and kind != "ground" and strength > 3.0:
		var hn: Vector3 = h["n"]
		car.dent(at, hn, strength)
		var was := car.damage
		var ewas := car.engine_dmg
		car.damage = minf(100.0, car.damage + strength * 1.4)
		# the engine's in the front: a knock there hurts it most (a roll shakes it about a bit too)
		var lp := car.to_local(at)
		var half_l: float = float(car.info["length"]) * 0.5
		var zc: float = (float(car.info["front"]) + float(car.info["back"])) * 0.5
		var nose := clampf((zc - lp.z) / maxf(half_l, 0.1), -1.0, 1.0)       # (+1: right at the front)
		var e_k := 0.4 if kind == "roll" else 0.3 + 1.5 * smoothstep(0.2, 0.8, nose)
		car.engine_dmg = minf(100.0, car.engine_dmg + strength * e_k)
		# a hard knock on a front corner bends that wheel
		if strength > 9.0 and nose > 0.4 and absf(lp.x) > float(car.info["width"]) * 0.2 and kind != "roll":
			car.bent = clampf(car.bent + signf(lp.x) * strength * 0.035, -1.0, 1.0)
		# sparks, bits of the bodywork, dust off a big one
		fx.spark_burst(at, hn, int(clampf(strength * 1.6, 6.0, 40.0)), clampf(4.0 + strength * 0.35, 4.0, 12.0))
		if strength > 6.0:
			fx.debris(at, hn, [car.paint_col, car.paint_col, Color("2a2a2e"), Color("c9ccd2")],
				int(clampf((strength - 4.0) * 0.6, 2.0, 12.0)), clampf(2.0 + strength * 0.2, 2.0, 7.0))
		if strength > 10.0:
			for k in int(clampf(strength * 0.3, 3.0, 10.0)):
				fx.puff(at + Vector3(randf_range(-0.6, 0.6), randf_range(0.1, 0.9), randf_range(-0.6, 0.6)), Color(0.74, 0.73, 0.72),
					randf_range(0.9, 1.6), hn * randf_range(1.0, 3.0) + Vector3(randf_range(-1, 1), randf_range(0.3, 1.2), randf_range(-1, 1)), 1.3, 0.7)
		if strength > 16.0 and (nose > 0.5 or kind == "roll") and randf() < 0.7:
			fx.glass(at + Vector3(0, 0.5, 0), hn, 12)
		if strength > 11.0:
			sfx("debris", vol - 4.0)
		if was < 35.0 and car.damage >= 35.0:
			sfx("headlight", -6.0)
			fx.glass(at, hn, 6)
		if was < 70.0 and car.damage >= 70.0:
			sfx("glass", -4.0)
			sfx("hubcap", -8.0)
			fx.glass(car.global_position + Vector3(0, 1.0, 0), hn, 18)
			fx.debris(car.global_position + Vector3(0, 0.3, 0), hn, [Color("d6d9de")], 1, 5.0, 1.2)     # (the hubcap)
		if was < 50.0 and car.damage >= 50.0 and not damage_told:
			damage_told = true
			ui.toast("Battered! Any gas station fixes you up: follow the arrow", "gear", K.PAPER, K.INK, 3.0)
		if ewas < 60.0 and car.engine_dmg >= 60.0 and car.engine_dmg < 99.5:
			ui.toast("The engine's hurt: it's losing power", "gear", Color("f2b84b"), K.INK, 2.6)
		if ewas < 99.5 and car.engine_dmg >= 99.5:
			ui.toast("Engine's gone! Limp to a gas station", "gear", Color("ef6a55"), Color.WHITE, 3.2)
			sfx("backfire", 0.0, 0.8)
			for k in 6:
				fx.flame(car.to_global(Vector3(randf_range(-0.5, 0.5), float(car.info["height"]) * 0.7, float(car.info["front"]) + half_l * 0.3)),
					randf_range(0.8, 1.3), Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1)), randf_range(0.4, 0.7))
		save.add_stat("crashes", 1)
		# the camera takes the knock too
		cam_kick_v += hn * clampf(strength * 0.06, 0.0, 1.4)
		fov_kick = maxf(fov_kick, clampf((strength - 6.0) * 0.45, 0.0, 7.0))
		if strength > 16.0:
			ui.impact_flash((strength - 14.0) / 16.0)
	# a big hit lands with a moment of slow motion
	if strength > 15.0 and kind != "ground":
		slowmo(0.4, 0.14)

## You've rolled it: a heavy crunch, a beat of slow motion, and the drift's gone.
func _on_roll(sev: float) -> void:
	if state != DRIVE:
		return
	sfx("rollover", -2.0)
	sfx("crash_heavy", -4.0)
	_break_drift()
	save.add_stat("rollovers", 1)
	shake = maxf(shake, 0.8)
	buzz(140, 1.0)
	slowmo(0.35, clampf(0.3 + sev * 0.015, 0.35, 0.6))
	ui.popup_text("Rolled it!", K.CORAL)

## The engine coughs: a bang from the exhaust, a puff of dark smoke and a flick of flame.
func _on_misfire() -> void:
	if state != DRIVE:
		return
	sfx("backfire", -6.0, randf_range(0.8, 1.05))
	var tail := car.to_global(Vector3(float(car.info["width"]) * 0.22, 0.4, float(car.info["back"]) - 0.05))
	var back := car.global_transform.basis.z
	fx.puff(tail, Color(0.22, 0.22, 0.24), 0.45, back * 2.0 + car.linear_velocity * 0.8, 0.8, 0.4)
	fx.flame(tail, 0.4, back * 3.0 + car.linear_velocity, 0.1)
	shake = maxf(shake, 0.06)

## A moment of slow motion (real time); overlapping ones run to the end of the longest.
func slowmo(scale: float, dur: float) -> void:
	if autopilot:
		return
	Engine.time_scale = minf(Engine.time_scale, scale)
	_slow_until = maxi(_slow_until, Time.get_ticks_msec() + int(dur * 1000.0))
	get_tree().create_timer(dur, true, false, true).timeout.connect(func():
		if Time.get_ticks_msec() >= _slow_until - 5:
			Engine.time_scale = 1.0)

# ------------------------------------------------------------------ landings, damage smoke, repairs

func _impacts(dt: float) -> void:
	# landings
	if car.grounded > 0 and was_air > 0.35:
		sfx("land", clampf(-14.0 + was_air * 8.0, -14.0, 0.0))
		if was_air > 1.1:
			sfx("land_hard", -6.0)
	was_air = car.air_t if car.grounded == 0 else 0.0
	# over on the roof
	var flipped := car.is_upside_down()
	if flipped and not was_flipped and car.linear_velocity.length() > 3.0:
		sfx("rollover", -3.0)
	was_flipped = flipped
	# a chirp from the tyres as the handbrake goes on at speed
	var hb := car.handbrake > 0.5
	if hb and not hb_was and absf(car.speed) > 8.0:
		sfx("chirp", -12.0)
	hb_was = hb
	# a hurt engine smokes from under the bonnet: wisps of steam, then grey, then thick black with flames
	# when it's nearly gone (rising and drifting back, never a cloud in your face)
	var ed := car.engine_dmg
	var smoke_k := maxf(clampf((ed - 20.0) / 80.0, 0.0, 1.0), clampf((car.damage - 60.0) / 100.0, 0.0, 0.3))
	var half_l: float = float(car.info["length"]) * 0.5
	if smoke_k > 0.0 and randf() < 0.15 + smoke_k * 0.5:
		var front := car.to_global(Vector3(randf_range(-0.35, 0.35), float(car.info["height"]) * 0.72, float(car.info["front"]) + half_l * 0.35))
		var col := Color(0.93, 0.93, 0.95).lerp(Color(0.52, 0.52, 0.54), smoothstep(0.3, 0.65, smoke_k)).lerp(Color(0.15, 0.15, 0.17), smoothstep(0.7, 1.0, smoke_k))
		fx.puff(front, col, randf_range(0.3, 0.5) + smoke_k * 0.7, Vector3(randf_range(-0.3, 0.3), 1.5 + smoke_k * 1.2, randf_range(-0.3, 0.3)) + car.linear_velocity * 0.6,
			0.8 + smoke_k * 1.0, 0.6)
	if ed > 85.0:
		fire_t -= dt
		if fire_t <= 0.0:
			fire_t = randf_range(0.05, 0.1) * (1.0 if ed >= 99.5 else 1.8)
			var fp := car.to_global(Vector3(randf_range(-0.45, 0.45), float(car.info["height"]) * 0.68, float(car.info["front"]) + half_l * 0.3))
			fx.flame(fp, randf_range(0.45, 0.85) * (1.35 if ed >= 99.5 else 1.0), car.linear_velocity * 0.85, randf_range(0.28, 0.5))

# ------------------------------------------------------------------ smoke, marks, knock-overs

func _effects(dt: float) -> void:
	smoke_t += dt
	for i in car.wheels.size():
		var wd: Dictionary = car.wheels[i]
		if not wd["contact"]:
			skid_acc.erase(i)
			continue
		var sl := absf(float(wd["slip"]))
		var marking: bool = (sl > deg_to_rad(10.0) and car.linear_velocity.length() > 4.0) or (not wd["front"] and (car.wheelspin > 0.3 or car.handbrake > 0.5) and car.linear_velocity.length() > 3.0)
		var wp: Vector3 = car.to_global(wd["home"] - Vector3(0, float(wd["len"]) - car.REST + float(wd["r"]), 0))
		if marking:
			var last: Vector3 = skid_acc.get(i, wp)
			var d := wp.distance_to(last)
			if d > 0.35 or not skid_acc.has(i):
				if skid_acc.has(i) and d < 3.0:
					var mid := (wp + last) * 0.5
					var dir := wp - last
					var surf: int = wd["surf"]
					if surf in [island.S_ASPHALT, island.S_CONCRETE, island.S_COBBLE, island.S_WOOD]:
						fx.skid(mid + Vector3(0, island.ROAD_LIFT, 0), atan2(-dir.x, -dir.z), d + 0.05, 0.32)
				skid_acc[i] = wp
			if not wd["front"] and smoke_t > 0.05:
				var surf2: int = wd["surf"]
				var col := Color(0.96, 0.96, 0.98)
				if surf2 in [island.S_DIRT, island.S_FIELD]:
					col = Color("c9a27e")
				elif surf2 == island.S_SAND:
					col = Color("f1dfb4")
				elif surf2 in [island.S_GRASS, island.S_FOREST]:
					col = Color("b9d79a")
				fx.puff(wp + Vector3(0, 0.3, 0), col, randf_range(1.2, 2.0) * (0.6 + car.drift * 0.6), -car.linear_velocity * 0.15 + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), 1.4, 1.0)
		else:
			skid_acc.erase(i)
	# scraping a wall throws sparks, and so does sliding along on the roof
	if car.wall_t > 0.15 and car.linear_velocity.length() > 5.0 and smoke_t > 0.04:
		fx.spark_burst(car.wall_pos + Vector3(0, randf_range(0.1, 0.5), 0), -car.linear_velocity.normalized() * 0.6 + Vector3.UP * 0.4, 4, 5.0)
	if car.roof_t > 0.0 and car.linear_velocity.length() > 3.0 and smoke_t > 0.04:
		var rh: Dictionary = car.hit
		var rp: Vector3 = rh["pos"] if not rh.is_empty() and rh.get("kind", "") == "roll" and car._clock - float(rh["t"]) < 1.0 else car.global_position
		fx.spark_burst(rp, -car.linear_velocity.normalized() * 0.5 + Vector3.UP * 0.5, 5, 6.0)
	if smoke_t > 0.05:
		smoke_t = 0.0

func _breakables() -> void:
	var p := car.global_position + car.linear_velocity * 0.03
	# trees and traffic lights: hit them fast enough and over they go (a little ahead, so the trunk or the
	# post is out of the way before the car gets there)
	for tr in island.hit_topples(car.global_position + car.linear_velocity * 0.07, car.linear_velocity, 2.1):
		var tree: bool = tr["kind"] == "tree"
		save.add_stat("knocks", 1)
		sfx("knock_wood" if tree else "crash_wall", -1.0, randf_range(0.85, 1.0))
		if tree:
			for k in 6:
				fx.puff((tr["pos"] as Vector3) + Vector3(randf_range(-1, 1), randf_range(2.0, 4.5), randf_range(-1, 1)), Color(0.45, 0.72, 0.38),
					randf_range(0.5, 1.0), Vector3(randf_range(-2, 2), randf_range(0.5, 2.0), randf_range(-2, 2)), 1.2, 0.2)
		fx.puff((tr["pos"] as Vector3) + Vector3(0, 0.6, 0), Color(0.85, 0.8, 0.72), 1.6, Vector3(0, 1, 0), 0.7, 0.8)
		car.linear_velocity *= 0.8 if tree else 0.88
		car.damage = minf(100.0, car.damage + (4.0 if tree else 2.5))
		shake = maxf(shake, 0.45 if tree else 0.3)
		_break_drift(true)
	var hits := island.hit_breakables(p, car.linear_velocity, 1.9)
	for b in hits:
		save.add_stat("knocks", 1)
		var cone: bool = String(b["pool"]).contains("cone")
		sfx("knock_soft" if cone else "knock_wood", -6.0 if cone else -2.0, randf_range(0.9, 1.15))
		fx.puff(b["pos"] + Vector3(0, 0.6, 0), Color(1, 1, 1), 1.4, Vector3(0, 1, 0), 0.5, 0.8)
		if not cone:
			car.linear_velocity *= 0.93
			shake = maxf(shake, 0.25)
		if not zone.is_empty() and cone:
			zone_pts = maxf(0.0, zone_pts - 250.0)
			ui.popup_text("Cone! -250", K.CORAL)

# ------------------------------------------------------------------ flips, water, getting stuck

func _recover(dt: float) -> void:
	var p := car.global_position
	if p.y < island.sea_y - 0.9 or p.y < -20.0:
		sfx("splash")
		ui.toast("Splash! Back to the road.", "rain", K.SKY, K.PAPER, 1.5)
		reset_car()
		return
	var over := car.is_upside_down() and car.linear_velocity.length() < 4.0 and car.on_stunt < 2
	var hung := car.grounded == 0 and car.linear_velocity.length() < 0.5
	if over or hung or car.righting():
		flip_t += dt
		if flip_t > 0.5:
			_bail()
		# come to rest on its roof or side: after a beat it's set back on its wheels, right where it is
		if over and flip_t > 1.2 and not car.righting():
			car.right_up()
			sfx("land", -8.0)
		if flip_t > (5.0 if over or car.righting() else 2.2):
			reset_car()
	else:
		flip_t = 0.0
	if car.throttle > 0.5 and car.linear_velocity.length() < 0.6:
		stuck_t += dt
		if stuck_t > 5.0:
			ui.show_reset_hint()
	else:
		stuck_t = 0.0

# ------------------------------------------------------------------ places

func _places(dt: float) -> void:
	place_t -= dt
	if place_t > 0.0:
		return
	place_t = 0.5
	var p := car.global_position
	var now := ""
	var best := 1e9
	for pl in island.places:
		var d := Vector2(p.x - pl["pos"].x, p.z - pl["pos"].z).length()
		if d < float(pl["r"]) and d < best:
			best = d
			now = pl["name"]
	if now != place_now:
		place_now = now
		if now != "" and not save.data["places"].has(now):
			save.data["places"].append(now)
			ui.discovered(now)
			sfx("mission", -4.0)
			ach_check()

# ------------------------------------------------------------------ challenges: markers

func _ring_mesh(r: float, col: Color, w := 1.2) -> ArrayMesh:
	var b := MB.new()
	var n := 40
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		b.quad(o0 * (r - w) + Vector3(0, 0.08, 0), o1 * (r - w) + Vector3(0, 0.08, 0), o1 * r + Vector3(0, 0.08, 0), o0 * r + Vector3(0, 0.08, 0), Vector3.UP, MB.glow(col))
	return b.commit()

func _build_markers() -> void:
	for z in island.zones:
		var st := _zone_start(z)
		z["start"] = st
		_marker("zone", z["id"], st, Color("ff8a5c"), z["name"], 7.0)
		island.map_marker(z["pos"], Color("ff8a5c"), 11.0)
	for t in island.trials:
		var g0: Transform3D = t["gates"][0]
		_marker("trial", t["id"], g0.origin, Color("5cc8ff") if t["kind"] == "time" else Color("c38bff"), t["name"], 6.0)
		island.map_marker(g0.origin, Color("5cc8ff") if t["kind"] == "time" else Color("c38bff"), 10.0)
	for rc in island.races:
		var sp: Vector2 = rc["start"]
		var p3 := Vector3(sp.x, island.height_at(sp.x, sp.y), sp.y)
		rc["pos"] = p3
		_marker("race", rc["id"], p3, Color("ff5c7a"), String(rc.get("label", "Street race: ")) + String(rc["name"]), 7.0)
		island.map_marker(p3, Color("ff5c7a"), 11.0)

func _zone_start(z: Dictionary) -> Vector3:
	var c: Vector3 = z["pos"]
	var starts := {"bowl": Vector3(175, 0, 178), "square": Vector3(-110, 0, 0), "harbour": Vector3(-362, 0, 163),
		"farmyard": Vector3(235, 0, 2), "beach": Vector3(60, 0, 378), "skate": Vector3(70, 0, 120), "stunt": Vector3(-110, 0, 199)}
	var p: Vector3 = starts.get(z["id"], c)
	p.y = island.height_at(p.x, p.z)
	return p

func _marker(kind: String, id: String, pos: Vector3, col: Color, name: String, r: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh(r, col)
	mi.material_override = toon
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	add_child(mi)
	# a column of light, so you can see it from down the street
	var pil := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.62
	cm.bottom_radius = r * 0.7
	cm.height = 16.0
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 32
	cm.rings = 1
	pil.mesh = cm
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/beacon.gdshader")
	bm.set_shader_parameter("col", col)
	pil.material_override = bm
	pil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pil.position = Vector3(0, 8.0, 0)
	mi.add_child(pil)
	var lb := Label3D.new()
	lb.text = name
	lb.font = K.font(700)
	lb.font_size = 96
	lb.outline_size = 22
	lb.outline_modulate = K.INK
	lb.modulate = col.lightened(0.3)
	lb.pixel_size = 0.012
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = false
	lb.position = pos + Vector3(0, 4.0, 0)
	add_child(lb)
	markers.append({"kind": kind, "id": id, "pos": pos, "node": mi, "label": lb, "r": r})

func _markers_tick(_dt: float) -> void:
	var p := car.global_position
	var busy := not zone.is_empty() or not trial.is_empty() or race != null or not intro.is_empty() or police.wanted()
	var inside := {}
	for m in markers:
		var d := (m["pos"] as Vector3).distance_to(p)
		var show := d < 220.0 and not busy
		(m["node"] as Node3D).visible = show
		(m["label"] as Node3D).visible = show and d < 120.0 and d > float(m["r"]) + 6.0
		# (the column of light thins out as you drive into it, so you're not sitting in a pink fog)
		var pil: MeshInstance3D = (m["node"] as Node3D).get_child(0)
		(pil.material_override as ShaderMaterial).set_shader_parameter("fade", clampf((d - float(m["r"])) / 14.0, 0.08, 1.0))
		if show:
			(m["node"] as Node3D).rotation.y += 0.3 * get_process_delta_time()
			(m["label"] as Node3D).position.y = (m["pos"] as Vector3).y + 4.0 + sin(time * 2.0) * 0.3
		# inside a beacon: its start card comes up (nothing starts until you press START)
		if state == DRIVE and not busy and d < float(m["r"]) + 1.0:
			inside = m
	if String(inside.get("id", "")) + String(inside.get("kind", "")) != String(in_marker.get("id", "")) + String(in_marker.get("kind", "")):
		in_marker = inside
		if inside.is_empty():
			ui.start_card_hide()
		else:
			ui.start_card_show(_start_info(inside["kind"], inside["id"]))

## What a challenge's start card says: {kind_label, name, info, col, medal, start}.
func _start_info(kind: String, id: String) -> Dictionary:
	var out := {"kind_label": "", "name": "", "info": "", "col": Color.WHITE, "medal": 0, "start": func(): begin_challenge(kind, id)}
	match kind:
		"zone":
			for z in island.zones:
				if z["id"] == id:
					var best := int(save.data["zones"].get(id, 0))
					out["kind_label"] = KIND_INFO["zone"][0]
					out["col"] = Color(KIND_INFO["zone"][1])
					out["name"] = z["name"]
					out["info"] = "%d seconds · gold %s pts%s" % [int(z["time"]), K.fmt(int(z["medals"][2])), (" · best %s" % K.fmt(best)) if best > 0 else ""]
					out["medal"] = int(save.data["medals"].get(id, 0))
		"trial":
			for t in island.trials:
				if t["id"] == id:
					var kk := "time" if t["kind"] == "time" else "drift"
					var best2 := float(save.data["trials"].get(id, 0.0))
					out["kind_label"] = KIND_INFO[kk][0]
					out["col"] = Color(KIND_INFO[kk][1])
					out["name"] = t["name"]
					if kk == "time":
						out["info"] = "%d gates · gold %.0f s%s" % [(t["gates"] as Array).size() - 1, float(t["medals"][0]), (" · best %.2f s" % best2) if best2 > 0.0 else ""]
					else:
						out["info"] = "%d gates · gold %s pts%s" % [(t["gates"] as Array).size() - 1, K.fmt(int(t["medals"][2])), (" · best %s" % K.fmt(int(best2))) if best2 > 0.0 else ""]
					out["medal"] = int(save.data["medals"].get(id, 0))
		"race":
			for rc in island.races:
				if rc["id"] == id:
					var rb := float(save.data["races"].get(id, 0.0))
					out["kind_label"] = KIND_INFO["race"][0]
					out["col"] = Color(KIND_INFO["race"][1])
					out["name"] = rc["name"]
					out["info"] = "%d laps · 8 cars%s" % [int(rc["laps"]), (" · best %d:%05.2f" % [int(rb) / 60, fmod(rb, 60.0)]) if rb > 0.0 else ""]
					out["medal"] = int(save.data["medals"].get("race_" + id, 0))
	return out

## xf moved down to just above the ground under it (so a car put there settles, rather than drops).
func on_ground(xf: Transform3D) -> Transform3D:
	var q := PhysicsRayQueryParameters3D.create(xf.origin + Vector3(0, 2.0, 0), xf.origin - Vector3(0, 6.0, 0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return xf
	return Transform3D(xf.basis, (hit["position"] as Vector3) + Vector3(0, 0.12, 0))

## START pressed: a wipe, then you're lined up for it, the title, the countdown and away.
func begin_challenge(kind: String, id: String) -> void:
	ui.start_card_hide()
	in_marker = {}
	ui.transition(func(): start_challenge_now(kind, id))

func start_challenge_now(kind: String, id: String) -> void:
	_end_challenges()
	jump = {}
	loop_on = -1
	_break_drift(false)
	var info := _start_info(kind, id)
	var sub := ""
	match kind:
		"zone":
			for z in island.zones:
				if z["id"] == id:
					var dz: Vector3 = (z["pos"] as Vector3) - (z["start"] as Vector3)
					car.place(_road_spot(z["start"], atan2(-dz.x, -dz.z)))
					sub = "Jumps, flips, the loop and drifts all count" if id == "stunt" else "Drift inside the zone before the clock runs out"
			_start_zone(id)
		"trial":
			for t in island.trials:
				if t["id"] == id:
					car.place((t["gates"][0] as Transform3D).translated(Vector3(0, 1.0, 0)).translated_local(Vector3(0, 0, 14)))
					sub = "Through every gate, fast as you can" if t["kind"] == "time" else "Drift all the way through. Points count"
			_start_trial(id)
		"race":
			_start_race(id)
			race.count = 3.0 + INTRO_T + 0.05      # (its own 3-2-1 waits for the title)
			sub = "Follow the line. Beat seven drivers to the flag"
	if kind != "race":
		car.place(on_ground(car.global_transform))     # (just above the road: it settles onto its wheels)
	car.hold = true
	_snap_cam()
	intro = {"kind": kind, "id": id, "t": 0.0, "said": 4}
	ui.intro_banner(info["kind_label"], info["name"], sub + "  ·  " + info["info"], info["col"])
	sfx("checkpoint", -5.0, 0.7)

## The title, then 3, 2, 1, GO (a race counts itself down).
func _intro_tick(dt: float) -> void:
	if intro.is_empty():
		return
	intro["t"] = float(intro["t"]) + dt
	var t: float = intro["t"]
	if intro["kind"] == "race":
		if race == null or race.state >= 1:
			intro = {}
		return
	car.hold = true
	var n := 3 - int(floor(t - INTRO_T))      # 3, 2, 1, then 0 = GO
	if t >= INTRO_T and n < int(intro["said"]):
		intro["said"] = n
		if n > 0:
			ui.big_count(str(n))
			sfx("checkpoint", -4.0, 0.8)
		else:
			ui.big_count("GO!")
			sfx("go", 0.0)
			car.hold = false
			intro = {}

# ------------------------------------------------------------------ drift zones

func _start_zone(id: String) -> void:
	for z in island.zones:
		if z["id"] == id:
			zone = z
	zone_t = float(zone["time"])
	zone_pts = 0.0
	zone_out = 0.0
	_break_drift(false)
	var how := "Jumps, flips, the loop and drifts all count. %d seconds!" if zone["id"] == "stunt" else "Drift inside the zone. %d seconds!"
	ui.chal_card.visible = true

func _in_zone() -> bool:
	if zone.is_empty():
		return false
	var c: Vector3 = zone["pos"]
	var p := car.global_position
	if zone.has("rect"):
		return (zone["rect"] as Rect2).grow(6.0).has_point(Vector2(p.x, p.z))
	return Vector2(p.x - c.x, p.z - c.z).length() < float(zone["r"])

func _zone_tick(dt: float) -> void:
	if zone.is_empty() or not intro.is_empty():
		return
	zone_t -= dt
	if not _in_zone():
		zone_out += dt
		if zone_out > 4.0:
			ui.toast("Left the zone", "flag", K.PAPER, K.INK, 1.6)
			_finish_zone()
			return
	else:
		zone_out = 0.0
	if zone_t <= 0.0:
		if drift_on:
			_bank()
		_finish_zone()

func _finish_zone() -> void:
	var z := zone
	zone = {}
	var score := int(zone_pts)
	var medal := _medal(score, z["medals"], false)
	var best := int(save.data["zones"].get(z["id"], 0))
	var old_medal := int(save.data["medals"].get(z["id"], 0))
	var pay := 0
	if score > best:
		save.data["zones"][z["id"]] = score
	if medal > old_medal:
		pay = MEDAL_PAY[medal] - MEDAL_PAY[old_medal]
		save.data["medals"][z["id"]] = medal
		save.data["coins"] = int(save.data["coins"]) + pay
	_medal_stats()
	ui.challenge_result(z["name"], "%s pts" % K.fmt(score), medal, pay, score > best and best > 0)
	_save_now()
	ach_check()

## Medal for a score: times list [gold, silver, bronze] (lower is better), points [bronze, silver, gold].
func _medal(score: float, medals: Array, lower_better: bool) -> int:
	if lower_better:
		for i in 3:
			if score <= float(medals[i]):
				return 3 - i
		return 0
	for i in range(2, -1, -1):
		if score >= float(medals[i]):
			return i + 1
	return 0

func _medal_stats() -> void:
	var zm := 0
	var zg := 0
	for z in island.zones:
		var md := int(save.data["medals"].get(z["id"], 0))
		zm += 1 if md > 0 else 0
		zg += 1 if md == 3 else 0
	var tm := 0
	var tg := 0
	for t in island.trials:
		var md2 := int(save.data["medals"].get(t["id"], 0))
		tm += 1 if md2 > 0 else 0
		tg += 1 if md2 == 3 else 0
	save.data["stats"]["zone_medals"] = zm
	save.data["stats"]["zone_golds"] = zg
	save.data["stats"]["trial_medals"] = tm
	save.data["stats"]["trial_golds"] = tg

# ------------------------------------------------------------------ trials and drift runs

func _start_trial(id: String) -> void:
	for t in island.trials:
		if t["id"] == id:
			trial = t
	trial_t = 0.0
	trial_gate = 1
	trial_pts = 0.0
	_break_drift(false)
	for g in gate_nodes:
		g.queue_free()
	gate_nodes.clear()
	var gates: Array = trial["gates"]
	for i in range(1, gates.size()):
		var gx: Transform3D = gates[i]
		var arch := MeshInstance3D.new()
		var am := M.get_mesh("arch")
		arch.mesh = am
		arch.material_override = toon
		var w: float = float(trial["w"]) + 4.0
		var s: float = w / maxf(am.get_aabb().size.x, 0.1)
		arch.transform = Transform3D(gx.basis.scaled(Vector3.ONE * s), gx.origin)
		add_child(arch)
		gate_nodes.append(arch)
	var desc := "Through every gate, fast as you can!" if trial["kind"] == "time" else "Drift all the way up. Points count!"
	ui.chal_card.visible = true

func _trial_tick(dt: float) -> void:
	if trial.is_empty() or not intro.is_empty():
		return
	trial_t += dt
	var gates: Array = trial["gates"]
	for i in gate_nodes.size():
		(gate_nodes[i] as Node3D).visible = i + 1 >= trial_gate and i + 1 <= trial_gate + 1
	var g: Transform3D = gates[trial_gate]
	var p := car.global_position
	var d := Vector2(p.x - g.origin.x, p.z - g.origin.z).length()
	if d < float(trial["w"]) * 0.5 + 4.0:
		trial_gate += 1
		sfx("checkpoint", -3.0)
		fx.sparkle(g.origin + Vector3(0, 3, 0), Color("5cc8ff"), 10)
		if trial_gate >= gates.size():
			if drift_on:
				_bank()
			_finish_trial()
			return
		ui.popup_text("Checkpoint %d/%d" % [trial_gate - 1, gates.size() - 1], K.SKY)
	var limit: float = (float(trial["medals"][2]) * 2.0) if trial["kind"] == "time" else 150.0
	if trial_t > limit:
		ui.toast("Out of time", "flag", K.PAPER, K.INK, 1.6)
		_end_challenges()

func _finish_trial() -> void:
	var t := trial
	_end_challenges()
	var timed: bool = t["kind"] == "time"
	var score: float = trial_t if timed else trial_pts
	var medal := _medal(score, t["medals"], timed)
	var best: float = float(save.data["trials"].get(t["id"], 0.0))
	var better: bool = best <= 0.0 or (score < best if timed else score > best)
	if better:
		save.data["trials"][t["id"]] = snappedf(score, 0.01)
	var old_medal := int(save.data["medals"].get(t["id"], 0))
	var pay := 0
	if medal > old_medal:
		pay = MEDAL_PAY[medal] - MEDAL_PAY[old_medal]
		save.data["medals"][t["id"]] = medal
		save.data["coins"] = int(save.data["coins"]) + pay
	_medal_stats()
	var txt := ("%.2f s" % score) if timed else ("%s pts" % K.fmt(int(score)))
	ui.challenge_result(t["name"], txt, medal, pay, better and best > 0.0)
	_save_now()
	ach_check()

func _end_challenges() -> void:
	zone = {}
	trial = {}
	rw_buf.clear()           # (nothing to rewind back into)
	if not intro.is_empty():
		intro = {}
	car.hold = false
	if race != null:
		race.cleanup()
		race.queue_free()
		race = null
		traffic.keep_out = Rect2()
		car.freeze = false
		car.collision_mask = car.collision_mask & ~Race.AI_LAYER
		route = {}
	for g in gate_nodes:
		g.queue_free()
	gate_nodes.clear()
	ui.challenge_end()

# ------------------------------------------------------------------ hidden coins

func _build_coins() -> void:
	coin_pool = Pool.new()
	coin_pool.setup(M.get_mesh("coin"), island.coin_spots.size() + 4, toon, false, true)
	add_child(coin_pool)
	for c in island.coin_spots:
		var slot := coin_pool.alloc()
		coins_live.append({"id": c["id"], "pos": c["pos"], "slot": slot, "taken": save.data["coins_taken"].has(c["id"])})
	_refresh_coins()

func _refresh_coins() -> void:
	for c in coins_live:
		c["taken"] = save.data["coins_taken"].has(c["id"])
		if c["taken"]:
			coin_pool.put(c["slot"], Transform3D(Basis().scaled(Vector3.ONE * 0.001), c["pos"]))

func _coins_tick(_dt: float) -> void:
	var p := car.global_position + Vector3(0, 0.8, 0)
	var b := Basis(Vector3.UP, time * 2.2).scaled(Vector3.ONE * 2.6)
	for c in coins_live:
		if c["taken"]:
			continue
		var cp: Vector3 = c["pos"]
		var d := cp.distance_to(p)
		if d > 180.0:
			continue
		coin_pool.put(c["slot"], Transform3D(b, cp + Vector3(0, sin(time * 2.0 + cp.x) * 0.25, 0)))
		if d < 3.2 and state == DRIVE:
			c["taken"] = true
			save.data["coins_taken"].append(c["id"])
			save.data["coins"] = int(save.data["coins"]) + COIN_PICKUP
			coin_pool.put(c["slot"], Transform3D(Basis().scaled(Vector3.ONE * 0.001), cp))
			fx.sparkle(cp, Color("ffd34d"), 12)
			sfx("coin", 0.0, 1.2)
			buzz(30, 0.6)
			ui.found_coin(save.data["coins_taken"].size(), coins_live.size(), COIN_PICKUP)
			ach_check()

# ------------------------------------------------------------------ fuel and gas stations

## After dark: your headlights and the street lamps nearest the camera light up what's round them (the toon
## shader adds their light). Lamps a little further off fade out first, so swapping them in and out doesn't pop.
var _lamp_t := 0.0
var _lamp_buf := PackedVector4Array()

## Lamps lighting things up after dark: your headlights (moved every frame, with the car as it's drawn)
## and the nearest street lamps. Which lamps are picked is worked out a few times a second; each one
## eases in and out, so one joining or leaving the few that are lit never flickers on or off.
var _lamp_want := {}        # lamp -> how lit it should be
var _lamp_w := {}           # lamp -> how lit it is
func _lamp_lights(dt: float) -> void:
	_lamp_buf.resize(16)
	_lamp_buf.fill(Vector4.ZERO)
	if atmos.night <= 0.02:
		if not _lamp_w.is_empty():
			_lamp_w.clear()
			_lamp_want.clear()
		for m in [toon, island.road_mat]:
			(m as ShaderMaterial).set_shader_parameter("lamps", _lamp_buf)
		return
	_lamp_t -= dt
	if _lamp_t <= 0.0:
		_lamp_t = 0.1
		var cp := cam.global_position
		var near := []
		for i in island.lamp_src.size():
			if island.lamp_on[i] == 0:
				continue
			var lp: Vector3 = island.lamp_src[i]
			var d2 := Vector2(lp.x - cp.x, lp.z - cp.z).length_squared()
			if d2 < 75.0 * 75.0:
				near.append([d2, i])
		near.sort_custom(func(a, b): return a[0] < b[0])
		_lamp_want.clear()
		for k in mini(near.size(), 14):
			_lamp_want[int(near[k][1])] = clampf((75.0 - sqrt(float(near[k][0]))) / 25.0, 0.0, 1.0)
	for i in _lamp_want:
		if not _lamp_w.has(i):
			_lamp_w[i] = 0.0
	var lit := []
	for i in _lamp_w.keys():
		var w := move_toward(float(_lamp_w[i]), float(_lamp_want.get(i, 0.0)), dt * 2.5)
		if w <= 0.0 and not _lamp_want.has(i):
			_lamp_w.erase(i)
			continue
		_lamp_w[i] = w
		lit.append([w, i])
	if lit.size() > 15:
		lit.sort_custom(func(a, b): return a[0] > b[0])
	# your headlights: a pool of light on the road ahead
	var hx := car.get_global_transform_interpolated()
	var ahead := hx.origin - hx.basis.z * 7.0 + Vector3(0, 1.2, 0)
	_lamp_buf[0] = Vector4(ahead.x, ahead.y, ahead.z, -11.0)
	for k in mini(lit.size(), 15):
		var lp2: Vector3 = island.lamp_src[lit[k][1]]
		_lamp_buf[k + 1] = Vector4(lp2.x, lp2.y, lp2.z, 13.0 * float(lit[k][0]))
	for m in [toon, island.road_mat]:
		(m as ShaderMaterial).set_shader_parameter("lamps", _lamp_buf)

# ------------------------------------------------------------------ rewind

# ------------------------------------------------------------------ the police

## Whether the police take notice of you right now (not in the middle of a challenge, or rewinding).
func chase_ok() -> bool:
	return state == DRIVE and intro.is_empty() and zone.is_empty() and trial.is_empty() and race == null and not rewinding

## (hitting one: that counts in a chase that's on already, or a race they've come to)
func chase_ok_or_chase() -> bool:
	return chase_ok() or police.wanted()

## They're after you: no fanfare, the stars come up under the minimap with a crackle of police radio,
## and a line saying what for.
func police_started(why: String) -> void:
	ui.wanted_start(why)
	sfx("radio_chirp", -6.0)
	ui.start_card_hide()
	in_marker = {}
	rw_buf.clear()
	route = {}

func police_heat_up(h: int) -> void:
	ui.wanted_up(h)
	sfx("radio_chirp", -7.0, 0.95)

## (they'd lost you, and someone's seen you again)
func police_reacquired() -> void:
	sfx("radio_chirp", -9.0, 1.05)

## Busted: the picture slows and drains of colour, BUSTED across it, and the fine.
func police_busted(fine: int) -> void:
	save.data["coins"] = maxi(int(save.data["coins"]) - fine, 0)
	save.add_stat("busts", 1)
	ui.busted_fx(fine)
	sfx("radio_chirp", -4.0, 0.85)
	if args.has("shot_busted"):
		get_tree().create_timer(1.9, true, false, true).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(String(args["shot_busted"])))
	Engine.time_scale = 0.35
	get_tree().create_timer(1.3, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)
	if race != null and race.state == 1:
		# busted in a race: you're out of it
		race.state = 2
		race_end_t = 3.0
	_save_now()

## Lost them: the stars fade, and the bounty.
func police_escaped(bounty: int, heat: int) -> void:
	save.data["coins"] = int(save.data["coins"]) + bounty
	save.add_stat("escapes", 1)
	ui.wanted_lost(bounty, heat)
	sfx("radio_chirp", -9.0, 0.9)
	_save_now()
	ach_check()

## Rewinding's not on during a countdown, after you've finished a race (or with the police after you).
func rewind_ok() -> bool:
	return intro.is_empty() and (race == null or race.state == 1) and state == DRIVE and not police.wanted()

func _rw_snap() -> Dictionary:
	var sn := {"xf": car.global_transform, "v": car.linear_velocity, "w": car.angular_velocity, "fuel": fuel, "nos": nos_left, "dmg": car.damage, "eng": car.engine_dmg,
		"drift": [drift_on, drift_pts, combo, combo_t, drift_len], "zone": [zone_t, zone_pts], "trial": [trial_t, trial_gate, trial_pts]}
	if race != null:
		sn["race"] = race.snapshot()
	return sn

func _rewind_tick(dt: float) -> void:
	if args.has("rwtest"):
		# tools: hold REWIND from 6 s to 7.5 s, report where the car is
		var at := float(args.get("rwtest", "6"))
		if at < 1.0:
			at = 6.0
		held["rewind"] = time > at and time < at + 1.5
		if frames % 10 == 0 and time > at - 2.0 and time < at + 4.0:
			var cp0 := car.global_position
			print("rw t=%.2f on=%s pos=(%.1f,%.1f,%.1f) v=%.0f buf=%d at=%.1f%s" % [time, rewinding, cp0.x, cp0.y, cp0.z, car.speed * 3.6, rw_buf.size(), rw_pos,
				(" race s=%.0f t=%.1f" % [race.racers[0]["s"], race.t]) if race != null else ""])
	var want: bool = held.get("rewind", false) and rewind_ok() and rw_buf.size() > 3
	if want and not rewinding:
		rewinding = true
		rw_pos = float(rw_buf.size() - 1)
		car.freeze = true
		_break_drift(false)
		if race != null:
			race.rw_hold(true)
		ui.rewind_fx(true)
		sfx("blowoff", -6.0, 0.6)
	elif rewinding and not want:
		_rewind_end()
	elif not rewinding and rewind_ok():
		# keep recording
		rw_t += dt
		if rw_t >= 1.0 / RW_HZ:
			rw_t = 0.0
			rw_buf.append(_rw_snap())
			if rw_buf.size() > int(RW_SECS * RW_HZ):
				rw_buf.pop_front()
	if rw_ghost > 0.0:
		rw_ghost -= dt
		if rw_ghost <= 0.0:
			car.collision_mask = car.collision_mask | 2

## (moved in the physics steps, so the frozen car is drawn smoothly between them)
func _physics_process(dt: float) -> void:
	if not rewinding:
		return
	rw_pos = maxf(0.0, rw_pos - dt * RW_HZ * 2.0)        # (twice as fast as it happened)
	var i := int(floor(rw_pos))
	var f := rw_pos - float(i)
	var a: Dictionary = rw_buf[i]
	var b: Dictionary = rw_buf[mini(i + 1, rw_buf.size() - 1)]
	var xa: Transform3D = a["xf"]
	var xb: Transform3D = b["xf"]
	car.global_transform = xa.interpolate_with(xb, f)
	if race != null and a.has("race"):
		race.rw_apply(a["race"], true)
	if rw_pos <= 0.0:
		_rewind_end()

## Let go of REWIND: back to that moment, at the speed you had then.
func _rewind_end() -> void:
	rewinding = false
	var i := clampi(int(round(rw_pos)), 0, rw_buf.size() - 1)
	var sn: Dictionary = rw_buf[i]
	rw_buf.resize(i + 1)
	car.global_transform = sn["xf"]
	car.freeze = false
	car.linear_velocity = sn["v"]
	car.angular_velocity = sn["w"]
	fuel = float(sn["fuel"])
	nos_left = float(sn["nos"])
	car.damage = float(sn["dmg"])
	car.engine_dmg = float(sn.get("eng", car.engine_dmg))
	var dr: Array = sn["drift"]
	drift_on = dr[0]
	drift_pts = dr[1]
	combo = dr[2]
	combo_t = dr[3]
	drift_len = dr[4]
	zone_t = float(sn["zone"][0])
	zone_pts = float(sn["zone"][1])
	trial_t = float(sn["trial"][0])
	trial_gate = int(sn["trial"][1])
	trial_pts = float(sn["trial"][2])
	if race != null and sn.has("race"):
		race.rw_hold(false)          # (unfrozen first: a frozen body drops the speeds it's given)
		race.rw_apply(sn["race"], false)
	# a moment where the traffic can't hit you (it didn't rewind)
	rw_ghost = 1.2
	car.collision_mask = car.collision_mask & ~2
	ui.rewind_fx(false)

## Seconds of nitrous a full bottle holds (the Nitrous Tank upgrade makes it bigger).
func nos_cap() -> float:
	return 3.0 + 1.2 * save.level("nitrous")

## Hold NOS: a shove and a higher top speed while the bottle lasts. It fills back up slowly as you drive,
## quicker when you're drifting or in the air.
func _nitrous(dt: float) -> void:
	var cap := nos_cap()
	var want: bool = held.get("nos", false) and nos_left > 0.05 and car.grounded >= 2 and car.speed > 2.0 \
		and intro.is_empty() and not car.freeze and not car.hold
	if args.has("nos") and car.speed > 8.0 and nos_left > 0.05:
		want = true          # (a test: fire it as soon as you're moving)
	car.nitro = move_toward(car.nitro, 1.0 if want else 0.0, dt * 6.0)
	if want:
		nos_left = maxf(0.0, nos_left - dt)
		if not nos_on:
			sfx("blowoff", -4.0, 0.8)
			sound.rev(1.0)
			buzz(30, 0.5)
		# blue flames out of the back
		nos_fx_t += dt
		if nos_fx_t > 0.03:
			nos_fx_t = 0.0
			var back := car.global_transform.basis.z
			for sd in [-1.0, 1.0]:
				var ep := car.to_global(Vector3(sd * 0.3, float(car.info["height"]) * 0.22, float(car.info["back"]) + 0.15))
				fx.puff(ep, Color(0.45, 0.7, 1.0).lerp(Color(1, 1, 1), randf() * 0.4), randf_range(0.22, 0.38),
					back * randf_range(5.0, 8.0) + car.linear_velocity * 0.9, 0.18, 0.0)
	else:
		var fill := 0.12
		if car.drift > 0.3:
			fill += 0.5
		if car.grounded == 0 and car.air_t > 0.3:
			fill += 0.4
		nos_left = minf(cap, nos_left + fill * dt)
	nos_on = want

func _fuel(dt: float) -> void:
	if race != null:
		return          # (a race doesn't use up your tank: nobody wants to run dry on the last lap)
	var burn := 0.004 + car.throttle * 0.075 * (0.45 + car.rpm)
	if car.linear_velocity.length() < 0.5 and car.throttle < 0.05:
		burn = 0.002
	fuel = maxf(0.0, fuel - burn * dt)
	# running on fumes: a quarter of the power, enough to limp to a station
	car.power_k = 1.0 if fuel > 0.0 else 0.25
	if fuel <= 0.0 and car.throttle > 0.5 and randf() < dt * 1.2:
		sfx("backfire", -10.0, 0.8)
	if fuel < 15.0 and fuel_told < 1:
		fuel_told = 1
		ui.toast("Low on fuel! The arrow points to the nearest gas station", "fuel", K.PAPER, K.INK, 3.0)
	elif fuel <= 0.0 and fuel_told < 2:
		fuel_told = 2
		ui.toast("Out of fuel! Limping on fumes to the nearest station", "fuel", K.CORAL, Color.WHITE, 3.0)

func fuel_cost() -> int:
	return int(ceil((100.0 - fuel) * FUEL_PRICE))

func repair_cost() -> int:
	return int(ceil(maxf(car.damage, car.engine_dmg) * REPAIR_PRICE))

func _stations_tick() -> void:
	var p := car.global_position
	var here := {}
	if car.linear_velocity.length() < 1.6 and car.grounded >= 3:
		for st in island.stations:
			if (st["pos"] as Vector3).distance_to(p) < 6.5:
				here = st
	if here.get("name", "") != at_station.get("name", ""):
		at_station = here
		if here.is_empty():
			ui.station_close()
		else:
			ui.station_open(String(here["name"]))
	if not at_station.is_empty():
		ui.station_update(fuel, car.damage, fuel_cost(), repair_cost(), int(save.data["coins"]))

## Fill the tank (as far as your coins go; an empty tank and an empty wallet gets a free splash).
func buy_fuel() -> void:
	var need := 100.0 - fuel
	if need < 0.5:
		return
	var coins := int(save.data["coins"])
	var buy := minf(need, float(coins) / FUEL_PRICE)
	if buy < 1.0:
		if fuel < 15.0:
			fuel = 15.0
			ui.toast("On the house: enough to get you home", "fuel", K.PAPER, K.INK, 2.2)
			sfx("fuel", -2.0)
		return
	fuel += buy
	save.data["coins"] = coins - int(ceil(buy * FUEL_PRICE))
	save.add_stat("fuel_bought", buy)
	fuel_told = 0
	sfx("fuel", -2.0)
	sfx("coin", -8.0, 0.9)
	_save_now()

## Mend the car (all of it if you can pay; otherwise as much as you can).
func buy_repair() -> void:
	var worst := maxf(car.damage, car.engine_dmg)
	if worst < 0.5:
		return
	var coins := int(save.data["coins"])
	var fix := minf(worst, float(coins) / REPAIR_PRICE)
	if fix < 1.0:
		ui.toast("Not enough coins for repairs", "coin", K.PAPER, K.INK, 1.8)
		return
	save.data["coins"] = coins - int(ceil(fix * REPAIR_PRICE))
	if fix >= worst - 0.5:
		car.repair()
		damage_told = false
		ui.toast("All fixed up!", "gear", K.PAPER, K.INK, 2.0)
	else:
		car.damage = maxf(0.0, car.damage - fix)
		car.engine_dmg = maxf(0.0, car.engine_dmg - fix)
		ui.toast("Patched up a bit", "gear", K.PAPER, K.INK, 2.0)
	sfx("upgrade", -2.0)
	_save_now()

# ------------------------------------------------------------------ street races

func _start_race(id: String) -> void:
	var d := {}
	for rc in island.races:
		if rc["id"] == id:
			d = rc
	if d.is_empty():
		return
	_end_challenges()
	_break_drift(false)
	race = Race.new()
	add_child(race)
	race.setup(self, island, d)
	race.grid(car)
	car.collision_mask = car.collision_mask | Race.AI_LAYER     # bump into the other racers
	_snap_cam()
	# the streets the race runs on are closed to traffic
	var bb := Rect2(race.pts[0], Vector2.ZERO)
	for q in race.pts:
		bb = bb.expand(q)
	traffic.keep_out = bb.grow(14.0)
	race_end_t = 0.0

func _race_tick(dt: float) -> void:
	if race == null:
		return
	race.tick(dt)
	if race_end_t > 0.0:
		race_end_t -= dt
		if race_end_t <= 0.0:
			_end_challenges()

## You crossed the line: where you came, and your time.
func race_done(place: int, t: float) -> void:
	var d: Dictionary = race.def
	var id := String(d["id"])
	var mkey := "race_" + id
	var medal := 3 if place == 1 else (2 if place == 2 else (1 if place == 3 else 0))
	var best := float(save.data["races"].get(id, 0.0))
	var better := best <= 0.0 or t < best
	if better:
		save.data["races"][id] = snappedf(t, 0.01)
	var old_medal := int(save.data["medals"].get(mkey, 0))
	var pay := 0
	if medal > old_medal:
		pay = MEDAL_PAY[medal] - MEDAL_PAY[old_medal]
		save.data["medals"][mkey] = medal
		save.data["coins"] = int(save.data["coins"]) + pay
	if place == 1:
		save.add_stat("race_wins", 1)
	save.add_stat("races", 1)
	var nth: String = ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th"][clampi(place - 1, 0, 7)]
	var mins := int(t) / 60
	ui.challenge_result(String(d["name"]), "%s · %d:%05.2f" % [nth, mins, t - mins * 60.0], medal, pay, better and best > 0.0)
	sfx("finish", -2.0)
	race_end_t = 4.0
	_save_now()
	ach_check()

# ------------------------------------------------------------------ the GPS

## Set (or clear) a place to go, from the map.
func set_route_pick(pos: Vector3, name: String) -> void:
	route_pick = {} if name == "" else {"pos": pos, "name": name, "kind": "pick"}
	route_t = 0.0
	route = {}

func nearest_station() -> Dictionary:
	var best := {}
	var bd := INF
	for st in island.stations:
		var d := (st["pos"] as Vector3).distance_to(car.global_position)
		if d < bd:
			bd = d
			best = st
	return best

## Where the GPS should take you right now: the next gate, back into the zone, a station when you're low
## on fuel or battered, or the place you picked.
func _route_target() -> Dictionary:
	var p := car.global_position
	if not trial.is_empty():
		var gates: Array = trial["gates"]
		if trial_gate < gates.size():
			return {"pos": (gates[trial_gate] as Transform3D).origin, "name": "Gate %d" % trial_gate, "kind": "trial"}
	if not zone.is_empty():
		return {} if _in_zone() else {"pos": zone["pos"], "name": zone["name"], "kind": "zone"}
	if (fuel < 15.0 or car.damage >= 50.0) and at_station.is_empty():
		var st := nearest_station()
		if not st.is_empty():
			return {"pos": st["pos"], "name": "Gas station", "kind": "station"}
	if not route_pick.is_empty():
		if (route_pick["pos"] as Vector3).distance_to(p) < 18.0:
			ui.toast("You've arrived: %s" % route_pick["name"], "flag", K.PAPER, K.INK, 2.0)
			route_pick = {}
			return {}
		return route_pick
	return {}

func _route_tick(dt: float) -> void:
	if race != null:
		# racing: the arrow follows the course to the next checkpoint (the course is already on the map)
		var g: Array = race.guide()
		var cb0 := cam.global_transform.basis
		var f0 := Vector3(-cb0.z.x, 0, -cb0.z.z).normalized()
		var r0 := Vector3(cb0.x.x, 0, cb0.x.z).normalized()
		var to0 := (g[0] as Vector3) - Vector3(car.global_position.x, 0, car.global_position.z)
		ui.route_arrow(true, atan2(to0.dot(r0), to0.dot(f0)), float(g[1]), String(g[2]))
		return
	var want := _route_target()
	route_t -= dt
	var changed: bool = want.get("name", "") != route.get("name", "") or (want.get("pos", Vector3.ZERO) as Vector3).distance_to(route.get("pos", Vector3.ZERO)) > 1.0
	if changed or (not want.is_empty() and route_t <= 0.0):
		route = want
		route_t = 1.5
		route_pts = PackedVector3Array() if want.is_empty() else router.find(car.global_position, want["pos"])
		island.route_line(route_pts, Color("ffd34d") if want.get("kind", "") == "trial" else Color("4aa8ff"))
	if route.is_empty() or route_pts.is_empty():
		ui.route_arrow(false)
		return
	# the arrow points at the road some way ahead along the route (so it shows the turn coming up)
	var p := car.global_position
	var bi := 0
	var bd := INF
	for i in route_pts.size():
		var d := Vector2(route_pts[i].x - p.x, route_pts[i].z - p.z).length_squared()
		if d < bd:
			bd = d
			bi = i
	var aim := route_pts[route_pts.size() - 1]
	var acc := 0.0
	for i in range(bi + 1, route_pts.size()):
		acc += route_pts[i].distance_to(route_pts[i - 1])
		if acc > 30.0:
			aim = route_pts[i]
			break
	var left := 0.0
	for i in range(bi + 1, route_pts.size()):
		left += route_pts[i].distance_to(route_pts[i - 1])
	left += sqrt(bd)
	var cb := cam.global_transform.basis
	var fwd := Vector3(-cb.z.x, 0, -cb.z.z).normalized()
	var rgt := Vector3(cb.x.x, 0, cb.x.z).normalized()
	var to := Vector3(aim.x - p.x, 0, aim.z - p.z)
	ui.route_arrow(true, atan2(to.dot(rgt), to.dot(fwd)), left, String(route["name"]))

# ------------------------------------------------------------------ stunts

func _stunts(dt: float) -> void:
	var p := car.global_position
	var xf := car.global_transform
	var st: Dictionary = island.stunt
	# boost pads: a shove forward as you drive over one
	boost_cd = maxf(0.0, boost_cd - dt)
	if boost_cd <= 0.0 and car.grounded >= 2:
		for pad in st["pads"]:
			var d: Vector3 = p - (pad["pos"] as Vector3)
			var dir: Vector3 = pad["dir"]
			var hs: Vector2 = pad["hs"]
			if absf(d.y) > 2.0 or absf(d.dot(dir)) > hs.y or absf(d.dot(Vector3(-dir.z, 0, dir.x))) > hs.x:
				continue
			var v := car.linear_velocity
			var va := v.dot(dir)
			if va < 3.0:
				continue
			var to := clampf(maxf(va + 7.0, 25.0), va, 34.0)
			car.linear_velocity = v + dir * (to - va)
			boost_cd = 1.0
			sfx("boost", -1.0)
			ui.popup_text("Boost!", K.SKY)
			shake = maxf(shake, 0.35)
			buzz(60, 0.7)
			for k in 10:
				fx.puff(p + Vector3(randf_range(-1.2, 1.2), 0.3, randf_range(-1.2, 1.2)), Color("8fe3ff"), randf_range(0.6, 1.1),
					-dir * randf_range(4.0, 9.0) + Vector3(0, randf_range(0.5, 2.0), 0), 0.6, 0.6)
			save.add_stat("boosts", 1)
			break
	# flying through a hoop
	if last_sp != Vector3.INF:
		for h in st["hoops"]:
			var c: Vector3 = h["pos"]
			var n: Vector3 = h["n"]
			var a := (last_sp - c).dot(n)
			var b := (p - c).dot(n)
			if (a < 0.0) != (b < 0.0):
				var q := last_sp.lerp(p, a / (a - b))
				if q.distance_to(c) < float(h["r"]):
					sfx("checkpoint", -2.0)
					ui.popup_text("Through the hoop!", K.SUN)
					fx.sparkle(q, Color("ffd34d"), 24)
					save.add_stat("hoops", 1)
					if jump.is_empty():
						_stunt_bank(800.0, "Hoop!")
					else:
						jump["hoops"] = int(jump["hoops"]) + 1
	last_sp = p
	# round the loop
	if loop_on < 0 and car.on_stunt >= 2 and xf.basis.y.y < 0.3:
		for i in st["loops"].size():
			var lc: Vector3 = st["loops"][i]["pos"]
			if Vector2(p.x - lc.x, p.z - lc.z).length() < 16.0:
				loop_on = i
				loop_last = i
				loop_flip = false
	if loop_on >= 0:
		if xf.basis.y.y < -0.6 and car.on_stunt >= 2:
			loop_flip = true
		if car.grounded == 0 and car.air_t > 0.3:
			loop_on = -1          # fell off
		elif xf.basis.y.y > 0.85 and car.grounded >= 2:
			if loop_flip:
				save.add_stat("loops", 1)
				_stunt_bank(1500.0, "Loop the loop!")
			loop_on = -1
	# jumps: add up the turns in the air, score them when the wheels are back down
	if car.grounded == 0 and not car.freeze:
		if jump.is_empty():
			jump = {"t": 0.0, "from": p, "pitch": 0.0, "yaw": 0.0, "roll": 0.0, "hoops": 0}
		jump["t"] = float(jump["t"]) + dt
		# (from how the car's turned since last frame, so a slow frame doesn't lose any of it)
		var bn := xf.basis.orthonormalized()
		if jump.has("b"):
			var dq := Quaternion((jump["b"] as Basis).inverse() * bn)
			var ang := dq.get_angle()
			if ang > PI:
				ang -= TAU
			var rv := dq.get_axis() * ang if absf(ang) > 0.00001 else Vector3.ZERO
			jump["pitch"] = float(jump["pitch"]) + rv.x
			jump["yaw"] = float(jump["yaw"]) + rv.y
			jump["roll"] = float(jump["roll"]) + rv.z
		jump["b"] = bn
	elif not jump.is_empty() and car.grounded >= 2:
		_landed()
		jump = {}

func _landed() -> void:
	var t: float = jump["t"]
	var hoops: int = jump["hoops"]
	if t < 0.7 and hoops == 0:
		return
	var p := car.global_position
	var from: Vector3 = jump["from"]
	var dist := Vector2(p.x - from.x, p.z - from.z).length()
	var pitch: float = jump["pitch"]
	var flips := int((absf(pitch) + 0.6) / TAU)
	var rolls := int((absf(float(jump["roll"])) + 0.6) / TAU)
	var halves := int((absf(float(jump["yaw"])) + 0.45) / PI)
	var parts := PackedStringArray()
	if flips > 0:
		parts.append(("Backflip" if pitch > 0.0 else "Frontflip") + (" x%d" % flips if flips > 1 else ""))
	if rolls > 0:
		parts.append("Barrel roll" + (" x%d" % rolls if rolls > 1 else ""))
	if halves > 0:
		parts.append(str(halves * 180))
	if hoops > 0:
		parts.append("hoop")
	var tricks := flips + rolls + halves
	var pts := t * 160.0 + dist * 5.0 + flips * 1200.0 + rolls * 1000.0 + halves * 350.0 + hoops * 800.0
	if tricks > 0 and car.global_transform.basis.y.y > 0.8:
		pts *= 1.5
		parts.append("clean!")
	if tricks == 0:
		parts.insert(0, "Big air %.1f s" % t if t >= 1.5 else "Air %.1f s" % t)
	save.add_stat("jumps", 1)
	save.add_stat("flips", flips + rolls)
	save.max_stat("max_flips", flips + rolls)
	save.max_stat("max_jump", dist)
	_stunt_bank(pts, " · ".join(parts))

## Scores a stunt like a banked drift: the combo multiplies it, and it keeps the combo going.
func _stunt_bank(pts: float, text: String) -> void:
	if combo_t > 0.0:
		combo = mini(combo + 1, 10)
		ui.combo_bump(combo)
	combo_t = 2.6
	var total := int(pts * combo)
	if args.has("stunt"):
		print("STUNT %s  %d x%d = %d" % [text, int(pts), combo, total])
	save.add_stat("stunt_points", total)
	save.max_stat("max_stunt", total)
	coin_frac += total / 120.0
	var c := int(coin_frac)
	coin_frac -= c
	save.data["coins"] = int(save.data["coins"]) + c
	if not zone.is_empty() and _in_zone():
		zone_pts += total
	ui.popup_text(text, K.SUN)
	ui.banked(total, c)
	sfx("near", -2.0)
	sfx("coin", -6.0, 1.0 + minf(total / 20000.0, 0.5))
	if total > 2500:
		island.people.cheer(car.global_position)

## Came down on the roof: the jump in progress scores nothing.
func _bail() -> void:
	if jump.is_empty():
		return
	var t: float = jump["t"]
	jump = {}
	if t > 0.7:
		ui.popup_text("Bailed!", K.CORAL)
		combo = 1
		combo_t = 0.0

# ------------------------------------------------------------------ camera

func _snap_cam() -> void:
	cam_yaw = car.global_rotation.y
	_cam(1.0, true)

func _cam(dt: float, snap := false) -> void:
	var xf := car.get_global_transform_interpolated()   # where the car is drawn this frame
	if not intro.is_empty() and float(intro["t"]) < INTRO_T:
		# the title's up: the camera swings round from the front of the car to behind it
		var it: float = intro["t"]
		var cy := car.global_rotation.y
		var a := cy + (INTRO_T - it) * 0.95
		var c := xf.origin + Vector3(0, 1.0, 0)
		var cp2 := c + Vector3(sin(a), 0, cos(a)) * (6.5 + it * 0.6) + Vector3(0, 1.4 + it * 0.45, 0)
		cp2.y = maxf(cp2.y, island.height_at(cp2.x, cp2.z) + 1.0)
		cam.position = cp2
		cam.look_at(c, Vector3.UP)
		cam_pos = cp2
		cam_yaw = cy
		cam.fov = 58.0
		return
	var fwd := -xf.basis.z
	fwd.y = 0.0
	var v := car.linear_velocity
	v.y = 0.0
	var flying := car.grounded == 0 and car.air_t > 0.15
	if flying or xf.basis.y.y < 0.35 or fwd.length() < 0.3:
		# flipping in the air or up a wall: follow where it's going, not which way it points
		fwd = v if v.length() > 2.0 else Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	fwd = fwd.normalized()
	var dirv := fwd
	if v.length() > 3.0 and car.speed > 0.0 and not flying:
		# look along where the car is going, so a drift shows off its side
		dirv = fwd.slerp(v.normalized(), clampf(car.drift * 0.7 + 0.25, 0.0, 0.8))
	# (the car's velocity only changes on physics steps, 60 a second: on a 120 Hz screen aiming straight
	# along it makes the view step every other frame. Eased every frame instead, it glides.)
	cam_look = dirv if snap or cam_look.length() < 0.5 else cam_look.slerp(dirv, 1.0 - exp(-dt * 12.0)).normalized()
	dirv = cam_look
	var want := atan2(-dirv.x, -dirv.z)
	var rate := 3.2 + clampf(v.length() / 10.0, 0.0, 3.0)
	if loop_on < 0:
		cam_yaw = want if snap else lerp_angle(cam_yaw, want, 1.0 - exp(-dt * rate))
	else:
		# round the loop: hold the heading you came in on (it comes out the same way)
		dirv = Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var dist: float = [7.6, 11.0, 5.0][cam_mode] + clampf(v.length() * 0.05, 0.0, 2.0) * (0.5 if cam_mode == 2 else 1.0)
	var height: float = [2.7, 4.4, 1.3][cam_mode]
	var target := xf.origin + Vector3(0, 0.95 if cam_mode == 2 else 1.3, 0)
	# looking round: after a moment without a finger on it, the view swings back behind the car
	look_t += dt
	if look_touches.is_empty() and look_t > 1.2:
		look_yaw_t = lerp_angle(look_yaw_t, 0.0, 1.0 - exp(-dt * 2.5))
		look_pitch_t = lerpf(look_pitch_t, 0.0, 1.0 - exp(-dt * 2.5))
	look_yaw = lerp_angle(look_yaw, look_yaw_t, 1.0 - exp(-dt * 16.0))
	look_pitch = lerpf(look_pitch, look_pitch_t, 1.0 - exp(-dt * 16.0))
	dist *= cam_zoom
	var looking := absf(look_yaw) > 0.05 or absf(look_pitch) > 0.05
	var yaw_v := cam_yaw + look_yaw
	var back := Vector3(sin(yaw_v), 0, cos(yaw_v))
	var lift := height + dist * sin(look_pitch) * 1.2
	var desired := target + back * dist * cos(look_pitch * 0.6) + Vector3(0, lift, 0)
	# don't sink into the hillside or walk through walls
	var gy := island.height_at(desired.x, desired.z) + (0.8 if cam_mode == 2 else 1.2)
	desired.y = maxf(desired.y, gy)
	var q := PhysicsRayQueryParameters3D.create(target, desired, 1)   # (the world only, not cars)
	q.exclude = [car.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		desired = (hit["position"] as Vector3) + (target - (hit["position"] as Vector3)).normalized() * 0.6
	cam_pos = desired if snap else cam_pos.lerp(desired, 1.0 - exp(-dt * (14.0 if looking else 9.0)))
	cam.position = cam_pos
	var look := target + dirv * (5.0 if cam_mode == 2 else 3.0) + Vector3(0, -0.2, 0)
	if looking:
		# swung round: keep the car in the middle of the picture
		look = look.lerp(target, clampf(maxf(absf(look_yaw) * 1.5, absf(look_pitch) * 2.0), 0.0, 1.0))
	# going round a loop, the camera stands off to the side to watch
	loop_cam = 0.0 if snap else move_toward(loop_cam, 1.0 if loop_on >= 0 else 0.0, dt * (4.0 if loop_on >= 0 else 2.2))
	if loop_cam > 0.0:
		var lp: Dictionary = island.stunt["loops"][loop_last]
		var side_pos: Vector3 = (lp["pos"] as Vector3) + (lp["side"] as Vector3) * 24.0 + Vector3(0, M.LOOP_R + 1.0, 0)
		var k := smoothstep(0.0, 1.0, loop_cam)
		cam.position = cam_pos.lerp(side_pos, k)
		look = look.lerp(xf.origin, k)
	if shake > 0.0:
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.18
		shake = maxf(0.0, shake - dt * 2.5)
	# a knock jolts the camera the way the car was shoved, and it springs back
	cam_kick_v += (-cam_kick * 90.0 - cam_kick_v * 12.0) * dt
	cam_kick += cam_kick_v * dt
	cam.position += cam_kick
	cam.look_at(look, Vector3.UP)
	if args.has("patrolcam") and traffic:
		# a test: beside the first patrol car in the traffic
		for pc in traffic.cars:
			if String(pc["model"]) == "k_car_police":
				var px: Transform3D = (pc["body"] as Node3D).global_transform
				cam.position = px.origin + px.basis.x * 7.0 - px.basis.z * 3.0 + Vector3(0, 2.2, 0)
				cam.look_at(px.origin + Vector3(0, 0.8, 0), Vector3.UP)
				cam.fov = 50.0
				return
	if args.has("traincam") and island.rail:
		# a test: beside train i, a little ahead, looking back along it
		var tb: Node3D = island.rail.trains[int(args["traincam"])]["cars"][0]["body"]
		var tx := tb.global_transform
		cam.position = tx.origin - tx.basis.z * 14.0 + tx.basis.x * 12.0 + Vector3(0, 4.0, 0)
		cam.look_at(tx.origin + tx.basis.z * 10.0, Vector3.UP)
		cam.far = 3000.0
		cam.fov = 55.0
		return
	if args.has("boatcam") and boats:
		# a test: alongside boat i, looking at it
		var bmi: Node3D = boats.boats[int(args["boatcam"])]["mi"]
		var bx := bmi.global_transform
		cam.position = bx.origin + bx.basis.x.normalized() * 22.0 + bx.basis.z.normalized() * 14.0 + Vector3(0, 7.0, 0)
		cam.look_at(bx.origin + Vector3(0, 1.0, 0), Vector3.UP)
		cam.far = 3000.0
		cam.fov = 50.0
		return
	if args.has("lookcam"):
		# a test: the camera here, looking there (x,y,z,tx,ty,tz)
		var lq := String(args["lookcam"]).split(",")
		cam.position = Vector3(float(lq[0]), float(lq[1]), float(lq[2]))
		cam.look_at(Vector3(float(lq[3]), float(lq[4]), float(lq[5])), Vector3.UP)
		cam.far = 3000.0
		cam.fov = 60.0
		return
	if args.has("topcam"):
		# a test: straight down from x,z,height
		var tq := String(args["topcam"]).split(",")
		cam.position = Vector3(float(tq[0]), float(tq[2]), float(tq[1]))
		cam.look_at(Vector3(float(tq[0]), 0, float(tq[1]) - 0.01), Vector3.UP)
		cam.far = 2000.0
		cam.fov = 60.0
		return
	fov_base = lerpf(fov_base, 62.0 + clampf(absf(car.speed) * 3.6 * 0.09, 0.0, 16.0) + car.nitro * 9.0, 1.0 - exp(-dt * 3.0))
	cam.fov = fov_base + fov_kick
	fov_kick = maxf(0.0, fov_kick - dt * 30.0)

func _title_cam(dt: float) -> void:
	title_t += dt
	var c := car.global_position + Vector3(0, 1.2, 0)
	var a := title_t * 0.12 + car.global_rotation.y + 2.4
	var pos := c + Vector3(sin(a) * 10.5, 3.4 + sin(title_t * 0.3) * 0.6, cos(a) * 10.5)
	pos.y = maxf(pos.y, island.height_at(pos.x, pos.z) + 1.5)
	cam.position = cam.position.lerp(pos, 1.0 - exp(-dt * 2.0))
	cam.look_at(c, Vector3.UP)
	cam.fov = 58.0
	cam_yaw = car.global_rotation.y
	cam_pos = cam.position

func toggle_cam() -> void:
	cam_mode = (cam_mode + 1) % 3
	save.data["settings"]["cam"] = cam_mode
	ui.popup_text(["Near camera", "Far camera", "Low camera"][cam_mode])

# ------------------------------------------------------------------ sound

func _sound(dt: float) -> void:
	var active := state == DRIVE
	var roll: String = island.ROLL[car.surface] if car.surface < island.ROLL.size() else "road"
	var skid := 0.0
	for wd in car.wheels:
		if wd["contact"]:
			skid = maxf(skid, clampf((absf(float(wd["slip"])) - deg_to_rad(6.0)) / deg_to_rad(20.0), 0.0, 1.0))
	if car.linear_velocity.length() < 3.0:
		skid *= car.linear_velocity.length() / 3.0
	sound.tick(dt, {"speed": absf(car.speed), "active": active, "grounded": car.grounded > 0, "drift": maxf(skid, car.wheelspin),
		"air_t": car.air_t, "rpm_k": car.rpm, "throttle": car.throttle, "roll": roll, "pace": 2.6,
		"grind": active and (car.wall_t > 0.12 or car.roof_t > 0.0) and car.linear_velocity.length() > 3.0,
		"eng_dmg": car.engine_dmg, "misfire": car.misfiring(),
		"siren": 0.0, "siren_close": 0.0})          # (each police car has its own siren now, heard from where it is)

# ------------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and not e.echo:
		var on: bool = e.pressed
		match e.keycode:
			KEY_LEFT, KEY_A:
				held["left"] = on
			KEY_RIGHT, KEY_D:
				held["right"] = on
			KEY_UP, KEY_W:
				held["gas"] = on
			KEY_DOWN, KEY_S:
				held["brake"] = on
			KEY_SPACE, KEY_SHIFT:
				held["hand"] = on
			KEY_N, KEY_E:
				held["nos"] = on
			KEY_BACKSPACE, KEY_Z:
				held["rewind"] = on
			KEY_R:
				if on and state == DRIVE:
					reset_car()
			KEY_C:
				if on:
					toggle_cam()
			KEY_ESCAPE, KEY_P:
				if on:
					if state == DRIVE:
						pause()
					elif state == PAUSED:
						resume()
	if e is InputEventScreenTouch:
		if e.pressed:
			var c := ui.control_at(e.position)
			if c == "wheel":
				# took hold of the steering wheel: it turns with the finger round its middle
				touches[e.index] = c
				wheel_idx = e.index
				wheel_grab = ui.wheel_angle_at(e.position) - wheel_angle
			elif c != "":
				touches[e.index] = c
			elif state == DRIVE:
				look_touches[e.index] = e.position
		else:
			touches.erase(e.index)
			if e.index == wheel_idx:
				wheel_idx = -1
			if look_touches.has(e.index):
				look_touches.erase(e.index)
				if look_touches.is_empty():
					save.data["settings"]["zoom"] = cam_zoom
		_touch_held()
	elif e is InputEventScreenDrag:
		if e.index == wheel_idx:
			wheel_angle = clampf(wrapf(ui.wheel_angle_at(e.position) - wheel_grab, -PI, PI), -WHEEL_MAX, WHEEL_MAX)
		# slide a thumb from one button to its neighbour
		elif touches.has(e.index):
			var c2 := ui.control_at(e.position)
			if c2 != "":
				touches[e.index] = c2
			_touch_held()
		elif look_touches.has(e.index):
			_look_drag(e.index, e.position)

## A finger dragging off the buttons: one swings the camera round the car, two pinch to zoom.
func _look_drag(idx: int, pos: Vector2) -> void:
	var old: Vector2 = look_touches[idx]
	if look_touches.size() >= 2:
		var other := Vector2.ZERO
		for k in look_touches:
			if k != idx:
				other = look_touches[k]
		var d0 := old.distance_to(other)
		var d1 := pos.distance_to(other)
		if d0 > 20.0:
			cam_zoom = clampf(cam_zoom * d0 / maxf(d1, 1.0), 0.55, 1.7)
	else:
		var dlt := pos - old
		look_yaw_t = wrapf(look_yaw_t - dlt.x * 0.005, -PI, PI)
		look_pitch_t = clampf(look_pitch_t + dlt.y * 0.004, -0.25, 1.0)
	look_touches[idx] = pos
	look_t = 0.0

func _touch_held() -> void:
	for k in ["left", "right", "gas", "brake", "hand", "nos", "rewind"]:
		var on := false
		for t in touches.values():
			if t == k:
				on = true
		held[k] = on or keys.get(k, false)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if ui.overlay.visible:
				ui.close_sheet()
				if state == PAUSED:
					resume()
			elif state == DRIVE:
				pause()
			elif state == GARAGE:
				close_garage(TITLE)
			elif state == TITLE:
				_save_now()
				get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			touches.clear()
			held.clear()
			if state == DRIVE:
				pause()
			elif state != LOADING:
				_save_now()
		NOTIFICATION_WM_CLOSE_REQUEST:
			if state != LOADING:
				_save_now()

# ------------------------------------------------------------------ autopilot (testing)

## Follows the roads: aims at a point ahead on the nearest road, lifts for bends, now and then drifts.
func _autopilot(dt: float) -> void:
	var p := car.global_position
	var fwd := -car.global_transform.basis.z
	if auto.is_empty() or frames % 20 == 0:
		var bd := 1e18
		for ri in island.roads.size():
			var r: Dictionary = island.roads[ri]
			if (r["kind"] == "dirt" and ri % 2 == 0) or r["kind"] == "yard":
				continue
			var pts: PackedVector2Array = r["pts"]
			for k in range(0, pts.size(), 2):
				var d := pts[k].distance_squared_to(Vector2(p.x, p.z))
				if d < bd:
					bd = d
					auto = {"r": ri, "k": k}
	var r2: Dictionary = island.roads[auto["r"]]
	var pts2: PackedVector2Array = r2["pts"]
	var n := pts2.size()
	var t: Vector2 = island._tangent(pts2, auto["k"], r2["closed"])
	var dirn := 1 if t.dot(Vector2(fwd.x, fwd.z)) >= 0.0 else -1
	var look := int(clampf(car.speed * 0.7, 6.0, 16.0))
	var k2: int = auto["k"] + dirn * look
	if r2["closed"]:
		k2 = posmod(k2, n)
	k2 = clampi(k2, 0, n - 1)
	if not r2["closed"] and (k2 == 0 or k2 == n - 1) and Vector2(p.x, p.z).distance_to(pts2[k2]) < 12.0:
		# end of the road: turn around on the spot (well, three points)
		auto["k"] = clampi(auto["k"] - dirn * 4, 0, n - 1)
	var aim := pts2[k2]
	var to := Vector3(aim.x - p.x, 0, aim.y - p.z)
	var ang := fwd.signed_angle_to(to.normalized(), Vector3.UP)
	car.steer_in = clampf(-ang * 2.2, -1.0, 1.0)
	var ahead: int = posmod(auto["k"] + dirn * 24, n) if r2["closed"] else clampi(auto["k"] + dirn * 24, 0, n - 1)
	var t2: Vector2 = island._tangent(pts2, ahead, r2["closed"])
	var bend := absf(t.angle_to(t2))
	var vmax := lerpf(30.0, 11.0, clampf(bend / 1.2, 0.0, 1.0))
	car.throttle = 1.0 if car.speed < vmax else 0.0
	car.brake = 1.0 if car.speed > vmax + 5.0 else 0.0
	car.handbrake = 1.0 if (bend > 0.6 and car.speed > 14.0 and int(time) % 7 < 3) else 0.0
	# wedged against something: back out of it
	if absf(car.speed) < 1.0 and car.throttle > 0.5:
		auto_stuck += dt
	elif auto_back <= 0.0:
		auto_stuck = 0.0
	if auto_stuck > 1.5:
		auto_stuck = 0.0
		auto_back = 1.6
	if auto_back > 0.0:
		auto_back -= dt
		car.throttle = 0.0
		car.brake = 1.0
		car.handbrake = 0.0
		car.steer_in = -car.steer_in
	if args.has("autodebug") and frames % 60 == 0:
		print("auto t=%.0f p=(%.0f,%.0f) v=%.0f slip=%.0f road=%s steer=%.2f thr=%.0f br=%.0f hb=%.0f gr=%d" % [time, p.x, p.z, car.speed * 3.6,
			rad_to_deg(car.slip), r2["name"], car.steer_in, car.throttle, car.brake, car.handbrake, car.grounded])
