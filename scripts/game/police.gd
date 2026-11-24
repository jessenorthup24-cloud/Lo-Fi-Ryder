extends Node3D
## The police. Patrol cars drive about in the traffic: go past one well over the limit, or hit one, and
## they're after you. Wanted stars, sirens, and more cars the longer it goes on (and the more of them you
## hit). To lose them, get out of sight and stay out of sight till the stars stop flashing; let them box you
## in and stop you and you're busted (a fine). Half the street races draw them too: then they're after
## everyone in it, and it isn't over at the finish line.
##
## Police cars are real cars (the same physics as yours). They find their way to you along the roads
## (the GPS's road map), go straight for you once you're close with nothing in between, smash through
## traffic, back up when they're stuck, and new ones turn up out of sight as the heat rises.

const Car := preload("res://scripts/game/drift_car.gd")
const CARS := preload("res://scripts/game/cars.gd")

const LAYER := 16
## Speed limits (km/h) by the kind of road.
const LIMIT := {"ring": 80, "main": 50, "road": 70, "street": 50, "lane": 40, "mountain": 60, "dirt": 50}
const TOLERANCE := 10.0     # km/h over the limit they let go
const NOTICE_R := 32.0      # a patrol car sees you speeding this close
const SPOT_R := 95.0        # a car that's after you keeps you in sight this far (with nothing in between)
const CLOSE_R := 24.0       # ...and this close, it doesn't need to see you
const UNITS := [0, 1, 2, 3, 3, 4]               # police cars after you at each heat
const EVADE := [0.0, 7.0, 9.0, 11.0, 13.0, 15.0]  # seconds out of sight it takes to lose them, by heat
const BUST_T := 3.0         # stopped with a police car right there this long: busted
const HEAT_T := 40.0        # a star more for every this long they've had you in sight
const CALM_T := 25.0        # after a chase: a breather before they notice you again

var game: Node
var island: Node
var traffic: Node
var heat := 0               # wanted stars (0: nobody's after you)
var heat_pts := 0.0
var chase_t := 0.0
var seen := false
var unseen := 0.0           # out of sight of all of them this long
var last_seen := Vector3.ZERO
var bust := 0.0             # 0..1: how nearly they've got you
var units: Array = []       # {car, target, state ("chase", "leave", "wreck"), path, pi, ...}
var calm := 0.0
var limit := 0              # the limit where you are, km/h (0: off the roads)
var patrol_near := false    # a patrol car's about (the limit sign comes up)
var race_chase := false     # they're onto a street race: the racers too
var siren_k := 0.0          # 0..1 for the sound: how near the nearest siren is
var held := false
var stats := {"spawned": 0, "busted_racers": 0, "wrecked": 0, "notices": 0}
var _sighted := false       # a police car's had eyes on you this chase (till then, the radio tells them where you are)
var _race_id := 0
var _race_at := -1.0
var _ram_cd := 0.0
var _spawn_cd := 0.0
var _scan := 0.0
var _last_hit := -1.0
var _n := 0
var _mats := {}
var _blip_mat: StandardMaterial3D
var _force := -1             # tools: --cops=1 always at races, --cops=0 never

func setup(g: Node, isl: Node, tr: Node) -> void:
	game = g
	island = isl
	traffic = tr
	for side in [["r", Color(1.0, 0.1, 0.14), 0.0], ["b", Color(0.12, 0.32, 1.0), 0.5]]:
		for glow in [false, true]:
			var m := ShaderMaterial.new()
			m.shader = preload("res://shaders/police_light.gdshader")
			m.set_shader_parameter("col", side[1])
			m.set_shader_parameter("phase", side[2])
			m.set_shader_parameter("glow", glow)
			_mats[String(side[0]) + ("g" if glow else "")] = m
			if glow:
				game.atmos.add_material(m)      # (the haze round the lights grows after dark)
	_blip_mat = StandardMaterial3D.new()
	_blip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blip_mat.albedo_color = Color(1.0, 0.15, 0.2)
	game.car.collision_mask = game.car.collision_mask | LAYER
	if game.args.has("cops"):
		_force = int(game.args["cops"])

func wanted() -> bool:
	return heat > 0

## For the HUD.
func hud() -> Dictionary:
	return {"heat": heat, "seen": seen, "evade": unseen / maxf(EVADE[heat], 0.1) if heat > 0 else 0.0, "bust": bust,
		"limit": limit, "patrol": patrol_near}

# ------------------------------------------------------------------ every frame

func tick(dt: float) -> void:
	if held:
		return
	var you: Car = game.car
	var cp := you.global_position
	_ram_cd -= dt
	_spawn_cd -= dt
	calm -= dt
	_scan -= dt
	if _scan <= 0.0:
		_scan = 0.2
		_look_around(cp)
	_hits()
	_race_watch()
	if heat > 0:
		_chase(dt, cp)
	var near := INF
	for u in units.duplicate():
		_drive(u, dt)
		if u["state"] == "chase" and is_instance_valid(u["car"]):
			near = minf(near, (u["car"] as Node3D).global_position.distance_to(cp))
	siren_k = clampf(1.0 - near / 160.0, 0.0, 1.0) if heat > 0 else 0.0
	if game.args.has("copslog") and int(game.time * 2.0) != int((game.time - dt) * 2.0):
		var line := "COPS t=%.1f heat=%d pts=%.2f seen=%s unseen=%.1f bust=%.2f you=%.0fkmh lim=%d near=%s" % [game.time, heat, heat_pts, seen, unseen, bust, absf(you.speed) * 3.6, limit, patrol_near]
		for u in units:
			if is_instance_valid(u["car"]):
				var uc: Car = u["car"]
				line += " | %s d=%.0f v=%.0f %s%s path=%d%s" % [String(u["state"]), uc.global_position.distance_to(cp), uc.linear_velocity.length() * 3.6,
					"sees " if u["sees"] else "", "you" if u["target"] == you else "racer", (u["path"] as PackedVector3Array).size(),
					(" REV" if float(u["rev"]) > 0.0 else "") + (" stuck%d" % int(u["stucks"]) if int(u["stucks"]) > 0 else "")]
		print(line)
	_tidy_up(cp)
	# the minimap: police cars are red and blue dots, flashing
	_blip_mat.albedo_color = Color(1.0, 0.15, 0.2) if fmod(Time.get_ticks_msec() * 0.001, 0.5) < 0.25 else Color(0.2, 0.4, 1.0)
	for u in units:
		if is_instance_valid(u["car"]):
			var p: Vector3 = (u["car"] as Node3D).global_position
			(u["blip"] as Node3D).global_position = Vector3(p.x, 300.8, p.z)

## The limit where you are, which patrol cars are about, and whether one has just seen you speeding past.
func _look_around(cp: Vector3) -> void:
	var me: Array = game.router.nearest_near(Vector2(cp.x, cp.z), 20.0)
	limit = 0
	if int(me[0]) >= 0:
		var r: Dictionary = island.roads[int(me[0])]
		if float(me[2]) < float(r["w"]) * 0.5 + 3.0:
			limit = int(LIMIT.get(r["kind"], 0))
	var kmh := absf(game.car.speed) * 3.6
	patrol_near = false
	for c in traffic.cars:
		if String(c["model"]) != "k_car_police" or int(c["mode"]) >= 2:
			continue
		var b: Node3D = c["body"]
		var d := b.global_position.distance_to(cp)
		if d < 90.0:
			patrol_near = true
		if d > NOTICE_R or not game.chase_ok() or not _sees(b.global_position, cp):
			continue
		if heat == 0 and calm <= 0.0 and limit > 0 and kmh > limit + TOLERANCE:
			stats["notices"] += 1
			start(1.0, "Speeding · %d in a %d" % [int(kmh), limit])
			_join(c)
			return
		if heat > 0 and not seen:
			# they're looking for you, and this one's spotted you: back on, and it joins in
			_spotted(cp)
			if _active() < UNITS[heat] + 1:
				_join(c)
			return

## You (or a police car) hit something: a patrol car in the traffic, or one of the cars after you.
func rammed(body: Node) -> void:
	var c: Dictionary = traffic._car_of(body)
	if c.is_empty() or String(c["model"]) != "k_car_police" or not game.chase_ok_or_chase():
		return
	if _ram_cd > 0.0:
		return
	_ram_cd = 2.5
	if heat == 0:
		start(2.0, "Hit a police car")
	else:
		heat_pts += 0.5
		_spotted(game.car.global_position)

func _hits() -> void:
	var h: Dictionary = game.car.hit
	if h.is_empty() or float(h["t"]) == _last_hit:
		return
	_last_hit = float(h["t"])
	var who = h.get("who")
	if who == null or not is_instance_valid(who) or not (who is Node) or not (who as Node).has_meta("police"):
		return
	var rel: float = (game.car.linear_velocity - (who as RigidBody3D).linear_velocity).length()
	if rel < 6.0 or _ram_cd > 0.0:
		return
	_ram_cd = 2.5
	if heat == 0:
		if game.chase_ok_or_chase():
			start(2.0, "Rammed a police car")
	else:
		heat_pts += 0.35

## They're after you (or after you harder): pts is the heat it starts at.
func start(pts: float, why: String) -> void:
	var was := heat
	heat_pts = maxf(heat_pts, pts)
	heat = clampi(int(heat_pts), 1, 5)
	_spotted(game.car.global_position)
	if was == 0:
		chase_t = 0.0
		bust = 0.0
		_sighted = false
		game.police_started(why)

func _spotted(cp: Vector3) -> void:
	seen = true
	unseen = 0.0
	last_seen = cp

func _active() -> int:
	var n := 0
	for u in units:
		if u["state"] == "chase":
			n += 1
	return n

func _chase(dt: float, cp: Vector3) -> void:
	chase_t += dt
	# who's got eyes on you (checked a few times a second each)
	var any := false
	var nearest := INF
	for u in units:
		if u["state"] != "chase" or not is_instance_valid(u["car"]):
			continue
		var c: Car = u["car"]
		var d := c.global_position.distance_to(cp)
		nearest = minf(nearest, d)
		u["eye_t"] = float(u["eye_t"]) - dt
		if float(u["eye_t"]) <= 0.0:
			u["eye_t"] = 0.25
			u["sees"] = d < CLOSE_R or (d < SPOT_R and _sees(c.global_position, cp))
		if u["sees"] and u["target"] == game.car:
			any = true
			_sighted = true
	if not _sighted and chase_t < 15.0:
		any = true            # (on their way: they know where you are)
	if race_chase and game.race != null and game.race.state == 1:
		any = true            # (a race: they know where it goes. Losing them starts once you're over the line)
	if any:
		if not seen:
			game.ui.popup_text("Spotted!", Color("ff5c7a"))
		_spotted(cp)
		heat_pts += dt / HEAT_T
	else:
		if seen:
			# lost you: they head for where you were last seen and look round there
			seen = false
			for u in units:
				u["search"] = last_seen
		unseen += dt
		if unseen >= EVADE[heat]:
			_escaped()
			return
	var was := heat
	heat = clampi(int(heat_pts), 1, 5)
	if heat > was:
		game.ui.popup_text("Wanted level %d" % heat, Color("ffd34d"))
		game.sfx("checkpoint", -4.0, 0.7)
	game.save.max_stat("max_heat", heat)
	# boxed in and stopped
	var boxed := absf(game.car.speed) < 2.5 and nearest < 7.5
	bust = clampf(bust + (dt / BUST_T if boxed else -dt / BUST_T * 0.7), 0.0, 1.0)
	if bust >= 1.0:
		_busted()
		return
	# more of them as it heats up (they turn up out of sight: where you are, or where they last saw you)
	var want: int = UNITS[heat] + (1 if race_chase and game.race != null else 0)
	if _active() < want and _spawn_cd <= 0.0:
		_spawn_cd = 3.0
		_spawn_near(cp if seen else last_seen, game.car, seen)

func _escaped() -> void:
	var bounty := 40 * heat + int(chase_t) * 2
	var h := heat
	_end()
	game.police_escaped(bounty, h)

func _busted() -> void:
	var fine := mini(int(game.save.data["coins"]), 50 + 75 * (heat - 1))
	_end()
	game.police_busted(fine)

## The chase is over: they pull up where they are, lights off (and go once you can't see them).
func _end() -> void:
	heat = 0
	heat_pts = 0.0
	seen = false
	bust = 0.0
	unseen = 0.0
	race_chase = false
	calm = CALM_T
	for u in units:
		if u["state"] == "chase":
			_leave(u)

func _leave(u: Dictionary) -> void:
	u["state"] = "leave"
	u["leave_t"] = 0.0
	var c: Car = u["car"]
	(c.get_node("LightBar") as Node3D).visible = false
	u["path"] = PackedVector3Array()

## Paused, or in the garage: they wait where they are.
func hold(on: bool) -> void:
	held = on
	for u in units:
		var c: RigidBody3D = u["car"]
		if not is_instance_valid(c):
			continue
		if on and not c.freeze:
			u["held"] = [c.linear_velocity, c.angular_velocity]
			c.freeze = true
		elif not on and u.has("held"):
			c.freeze = false
			c.linear_velocity = u["held"][0]
			c.angular_velocity = u["held"][1]
			u.erase("held")

## Everything gone at once (back to the title, or fast travel's been allowed after all).
func clear() -> void:
	for u in units:
		if is_instance_valid(u["car"]):
			(u["car"] as Node).queue_free()
		if is_instance_valid(u["blip"]):
			(u["blip"] as Node).queue_free()
	units.clear()
	heat = 0
	heat_pts = 0.0
	seen = false
	bust = 0.0
	race_chase = false

# ------------------------------------------------------------------ street races

## Half the races (decided when one starts) get a visit: some way into it, police cars turn up after
## everyone in it, and the chase goes on after the finish.
func _race_watch() -> void:
	var r = game.race
	if r == null:
		_race_at = -1.0
		_race_id = 0
		return
	if r.get_instance_id() != _race_id:
		_race_id = r.get_instance_id()
		var go := randf() < 0.5 if _force < 0 else _force == 1
		_race_at = randf_range(18.0, 45.0) if go else -1.0
		if go and game.args.has("copsat"):
			_race_at = float(game.args["copsat"])
	if _race_at > 0.0 and r.state == 1 and r.t >= _race_at:
		_race_at = -1.0
		race_chase = true
		start(2.0, "They're onto the race!")
		# they come in from round about: one after you, the rest after whoever's nearest them
		for i in 3:
			_spawn_near(game.car.global_position, game.car, true)
		_spawn_cd = 4.0

func _pick_target(u: Dictionary, i: int) -> void:
	u["target"] = game.car
	var r = game.race
	if not race_chase or r == null or r.state != 1 or i % 2 == 0:
		return
	var c: Node3D = u["car"]
	var best := 180.0
	for rr in r.racers:
		if not rr["ai"] or rr.get("busted", false):
			continue
		var rc: Node3D = rr["car"]
		var d := rc.global_position.distance_to(c.global_position)
		if d < best:
			best = d
			u["target"] = rc

# ------------------------------------------------------------------ police cars

## A new police car on a road some way from p, out of sight, facing your way (behind: coming up from
## behind you, while they've got you in sight).
func _spawn_near(p: Vector3, target: Node3D, behind := false) -> void:
	var cam: Camera3D = game.cam
	var you: Vector3 = game.car.global_position
	var back := Vector2(cam.global_transform.basis.z.x, cam.global_transform.basis.z.z).normalized()
	for tries in 36:
		var dirn := Vector2.from_angle(randf() * TAU)
		if behind and tries < 24:
			dirn = back.rotated(randf_range(-1.1, 1.1))
		var q := Vector2(p.x, p.z) + dirn * (randf_range(50.0, 100.0) if behind else randf_range(80.0, 150.0))
		var loc: Array = game.router.nearest_near(q, 20.0)
		if int(loc[0]) < 0 or not LIMIT.has(island.roads[int(loc[0])]["kind"]):
			continue
		var ri := int(loc[0])
		var s := float(loc[1])
		var pt: Vector2 = game.router.road_at(ri, s)
		var pos := Vector3(pt.x, island.height_at(pt.x, pt.y) + 0.7, pt.y)
		if pos.distance_to(you) < (45.0 if behind else 65.0):
			continue
		# (in plain view: no)
		if cam.is_position_in_frustum(pos) and pos.distance_to(cam.global_position) < 220.0 and _sees(cam.global_position, pos + Vector3(0, 0.6, 0)):
			continue
		var clear := true
		for u in units:
			if is_instance_valid(u["car"]) and (u["car"] as Node3D).global_position.distance_to(pos) < 12.0:
				clear = false
		for c in traffic.cars:
			if (c["body"] as Node3D).global_position.distance_to(pos) < 10.0:
				clear = false
		if not clear:
			continue
		var t: Vector2 = (game.router.road_at(ri, s + 1.0) - game.router.road_at(ri, s - 1.0)).normalized()
		if t.dot(Vector2(p.x, p.z) - pt) < 0.0:
			t = -t
		var xf: Transform3D = game.on_ground(Transform3D(Basis(Vector3.UP, atan2(-t.x, -t.y)), pos))
		_unit(xf, Vector3(t.x, 0, t.y) * 12.0, target)
		return

## A patrol car in the traffic that's seen you: it becomes a police car after you (and the traffic gets a
## new car somewhere out of sight in its place).
func _join(c: Dictionary) -> void:
	var b: Node3D = c["body"]
	var f := -b.global_transform.basis.z
	var p := b.global_position
	var xf: Transform3D = game.on_ground(Transform3D(Basis(Vector3.UP, atan2(-f.x, -f.z)), p + Vector3(0, 0.7, 0)))
	_unit(xf, Vector3(f.x, 0, f.z) * float(c["v"]), game.car)
	game.fx.puff(p + Vector3(0, 0.4, 0), Color(0.9, 0.9, 0.92), 1.2, Vector3.ZERO, 0.6, 0.6)
	traffic._place_random(c, game.car.global_position, 160.0, 260.0, -game.cam.global_transform.basis.z)

func _unit(xf: Transform3D, vel: Vector3, target: Node3D) -> Dictionary:
	var d := CARS.by_id("police")
	var c: Car = Car.new()
	_n += 1
	c.name = "Police_%d" % _n
	c.set_meta("police", true)
	c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON     # drawn smoothly, like yours
	game.add_child(c)
	c.setup(d, game.toon, island, 0)
	c.tune(d, game.save.data["up"])
	c.assist = 1.0
	c.collision_layer = LAYER
	c.collision_mask = 1 | 2 | 4 | 8 | LAYER
	c.place(xf)
	c.linear_velocity = vel
	c.reset_physics_interpolation()
	c.rammed.connect(func(b, v, j, at): traffic.knock(b, v, j, at))     # (they plough through the traffic)
	_light_bar(c)
	var blip := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 5.0
	cyl.bottom_radius = 5.0
	cyl.height = 0.2
	cyl.radial_segments = 14
	blip.mesh = cyl
	blip.material_override = _blip_mat
	blip.layers = island.MAP_LAYER
	blip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blip.top_level = true
	blip.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	c.add_child(blip)
	var u := {"car": c, "target": target, "state": "chase", "path": PackedVector3Array(), "pi": 0, "replan": 0.0,
		"eye_t": 0.0, "sees": false, "look": 0.0, "clear": false, "stuck": 0.0, "rev": 0.0, "stucks": 0, "flip": 0.0,
		"search": last_seen, "bust": 0.0, "retarget": 0.0, "blip": blip, "leave_t": 0.0}
	units.append(u)
	_pick_target(u, units.size() - 1)
	stats["spawned"] += 1
	return u

## Red and blue lights over the bar on the roof (the bulbs, and a haze round each that shows from afar).
func _light_bar(c: Car) -> void:
	var bar := Node3D.new()
	bar.name = "LightBar"
	var top := float(c.info["top"])
	c.add_child(bar)
	for side in [["r", -0.26], ["b", 0.3]]:
		var bulb := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.17, 0.47)
		bulb.mesh = bm
		bulb.material_override = _mats[side[0]]
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bulb.position = Vector3(float(side[1]), top - 0.07, 0.1)
		bar.add_child(bulb)
		var halo := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(2.6, 2.6)
		halo.mesh = qm
		halo.material_override = _mats[String(side[0]) + "g"]
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		halo.position = Vector3(float(side[1]), top + 0.05, 0.1)
		bar.add_child(halo)

## Drive one police car: along the roads towards its target (or where you were last seen), straight at it
## when it's close with nothing in between, backing up when it's stuck.
func _drive(u: Dictionary, dt: float) -> void:
	var c: Car = u["car"]
	if not is_instance_valid(c):
		units.erase(u)
		return
	if c.freeze:
		return
	var pos := c.global_position
	var v := c.linear_velocity.length()
	var fwd := -c.global_transform.basis.z
	if u["state"] == "wreck" or u["state"] == "leave":
		c.throttle = 0.0
		c.brake = 0.4 if u["state"] == "wreck" else 1.0
		c.steer_in = 0.0
		return
	# who it's after
	u["retarget"] = float(u["retarget"]) - dt
	if float(u["retarget"]) <= 0.0 or not is_instance_valid(u["target"]):
		u["retarget"] = 3.0
		_pick_target(u, units.find(u))
	var tgt: Node3D = u["target"]
	var after_you: bool = tgt == game.car
	var know := true
	var goal: Vector3
	var tv := Vector3.ZERO
	if after_you and not seen:
		goal = u["search"]
		know = false
		if Vector2(pos.x, pos.z).distance_to(Vector2(goal.x, goal.z)) < 16.0:
			u["search"] = _search_spot()
			goal = u["search"]
			u["replan"] = 0.0         # (a new way there, now)
	else:
		goal = tgt.global_position
		tv = (tgt as RigidBody3D).linear_velocity
	var d := Vector2(pos.x, pos.z).distance_to(Vector2(goal.x, goal.z))
	u["look"] = float(u["look"]) - dt
	if float(u["look"]) <= 0.0:
		u["look"] = 0.3
		u["clear"] = know and d < 40.0 and _sees(pos, goal)
	var aim: Vector2
	var vt := 44.0
	if know and d < 34.0 and bool(u["clear"]):
		# right there: for the car itself, where it'll be in a moment
		var lead := clampf(d / maxf(v, 10.0), 0.0, 0.9)
		var pp := goal + tv * lead
		aim = Vector2(pp.x, pp.z)
		vt = tv.length() + clampf(d - 8.0, -3.0, 11.0) + 1.5
		if d < 9.0:
			# on your bumper: hang on to you (and stop when you do, to box you in), not shove you along
			vt = maxf(tv.length() - 1.5, 0.0) if tv.length() > 4.0 else 0.0
		u["path"] = PackedVector3Array()
	else:
		u["replan"] = float(u["replan"]) - dt
		var path: PackedVector3Array = u["path"]
		if float(u["replan"]) <= 0.0 or path.size() < 2:
			path = game.router.find(pos, goal, true)
			u["path"] = path
			u["pi"] = 0
			u["replan"] = randf_range(0.9, 1.5)
		if path.size() < 2:
			aim = Vector2(goal.x, goal.z)
		else:
			var p2 := Vector2(pos.x, pos.z)
			var pi: int = u["pi"]
			while pi < path.size() - 1:
				var a := Vector2(path[pi].x, path[pi].z)
				var b := Vector2(path[pi + 1].x, path[pi + 1].z)
				var ab := b - a
				var t := (p2 - a).dot(ab) / maxf(ab.length_squared(), 0.01)
				if t > 1.0 or a.distance_to(p2) < 3.0:
					pi += 1
				else:
					break
			u["pi"] = pi
			aim = _ahead(path, pi, p2, 6.0 + v * 0.45)
			vt = _corner_speed(path, pi, p2)
		if not know:
			vt = minf(vt, 24.0)       # (looking for you: not flat out)
	# another police car just ahead, going the same way: stay behind it (they'd only pile into each other)
	for o in units:
		if o == u or o["state"] != "chase" or not is_instance_valid(o["car"]):
			continue
		var oc: RigidBody3D = o["car"]
		var rel := oc.global_position - pos
		if rel.length() < 11.0 and rel.normalized().dot(fwd) > 0.75:
			vt = minf(vt, oc.linear_velocity.length() + (rel.length() - 7.0) * 0.6)
	var to := Vector3(aim.x - pos.x, 0, aim.y - pos.z)
	var ang := atan2(fwd.z * to.x - fwd.x * to.z, fwd.x * to.x + fwd.z * to.z)
	var steer := clampf(-ang * 2.4, -1.0, 1.0)
	c.handbrake = 0.0
	if absf(ang) > 0.5 and v > 8.0:
		vt = minf(vt, v - 3.0)
	if v < vt - 0.6:
		c.throttle = 1.0
		c.brake = 0.0
	elif v > vt + 1.2:
		c.throttle = 0.0
		c.brake = clampf((v - vt) / 4.0, 0.3, 1.0)
	else:
		c.throttle = 0.4
		c.brake = 0.0
	c.steer_in = steer
	# stuck (against a wall, or another car): back up a moment, turned the other way
	if float(u["rev"]) > 0.0:
		u["rev"] = float(u["rev"]) - dt
		c.throttle = 0.0
		c.brake = 1.0
		c.steer_in = -steer
	elif v < 1.5 and c.throttle > 0.5:
		u["stuck"] = float(u["stuck"]) + dt
		if float(u["stuck"]) > 1.4:
			u["stuck"] = 0.0
			u["rev"] = 1.6
			u["stucks"] = int(u["stucks"]) + 1
	else:
		u["stuck"] = maxf(0.0, float(u["stuck"]) - dt)
		if v > 8.0:
			u["stucks"] = 0
	# on its roof: out of it (and it doesn't count any more)
	u["flip"] = float(u["flip"]) + dt if c.global_transform.basis.y.y < 0.3 else 0.0
	if float(u["flip"]) > 2.0 and u["state"] == "chase":
		u["state"] = "wreck"
		u["leave_t"] = 0.0
		(c.get_node("LightBar") as Node3D).visible = false
		stats["wrecked"] += 1
		if heat > 0:
			heat_pts += 0.6
			game.ui.popup_text("Police car wrecked!", Color("ffd34d"))
	# a racer it's after: boxed in and stopped, they're out of the race
	if not after_you and u["state"] == "chase" and game.race != null:
		var tr: RigidBody3D = tgt as RigidBody3D
		if tr.linear_velocity.length() < 2.5 and pos.distance_to(tgt.global_position) < 7.5:
			u["bust"] = float(u["bust"]) + dt
			if float(u["bust"]) > BUST_T:
				u["bust"] = 0.0
				stats["busted_racers"] += 1
				game.race.bust(tgt)
				u["retarget"] = 0.0
		else:
			u["bust"] = maxf(0.0, float(u["bust"]) - dt)

## Police cars that are done (driven off, wrecked, stuck for good or left far behind) go once you can't
## see them; ones that have fallen right behind come back in nearer by.
func _tidy_up(cp: Vector3) -> void:
	var cam: Camera3D = game.cam
	for u in units.duplicate():
		var c: Car = u["car"]
		if not is_instance_valid(c):
			units.erase(u)
			continue
		var p := c.global_position
		var d := p.distance_to(cp)
		var in_view := cam.is_position_in_frustum(p) and d < 200.0
		u["leave_t"] = float(u["leave_t"]) + get_process_delta_time()
		var go := false
		match String(u["state"]):
			"leave":
				go = not in_view and (d > 40.0 or float(u["leave_t"]) > 20.0)
			"wreck":
				go = (not in_view and float(u["leave_t"]) > 3.0) or float(u["leave_t"]) > 12.0
			_:
				go = (int(u["stucks"]) >= 4 or (d > 300.0 and seen)) and not in_view
		if go:
			c.queue_free()
			units.erase(u)

## Somewhere on a road round where you were last seen (where they look for you).
func _search_spot() -> Vector3:
	for tries in 8:
		var q := Vector2(last_seen.x, last_seen.z) + Vector2.from_angle(randf() * TAU) * randf_range(30.0, 110.0)
		var loc: Array = game.router.nearest_near(q, 20.0)
		if int(loc[0]) >= 0:
			var pt: Vector2 = game.router.road_at(int(loc[0]), float(loc[1]))
			return Vector3(pt.x, 0, pt.y)
	return last_seen

## The point la metres along the path ahead of from (from is near path[pi]).
func _ahead(path: PackedVector3Array, pi: int, from: Vector2, la: float) -> Vector2:
	var cur := from
	var left := la
	var k := pi
	while k < path.size():
		var nxt := Vector2(path[k].x, path[k].z)
		var l := cur.distance_to(nxt)
		if l >= left:
			return cur.lerp(nxt, left / maxf(l, 0.001))
		left -= l
		cur = nxt
		k += 1
	return Vector2(path[path.size() - 1].x, path[path.size() - 1].z)

## How fast it can go now and still make the bends coming up (braking in time for them).
func _corner_speed(path: PackedVector3Array, pi: int, from: Vector2) -> float:
	var vt := 44.0
	var acc := from.distance_to(Vector2(path[mini(pi, path.size() - 1)].x, path[mini(pi, path.size() - 1)].z))
	for k in range(pi, mini(pi + 14, path.size() - 2)):
		var d1 := Vector2(path[k + 1].x - path[k].x, path[k + 1].z - path[k].z)
		var d2 := Vector2(path[k + 2].x - path[k + 1].x, path[k + 2].z - path[k + 1].z)
		var l1 := d1.length()
		var l2 := d2.length()
		if l1 < 0.5 or l2 < 0.5:
			acc += l1
			continue
		var turn := absf(d1.angle_to(d2))
		if turn > 0.08:
			var rad := (l1 + l2) * 0.5 / turn
			var vc := clampf(sqrt(8.5 * rad), 8.0, 44.0)
			vt = minf(vt, sqrt(vc * vc + 2.0 * 6.5 * maxf(acc - 3.0, 0.0)))
		acc += l1
	return vt

## Nothing solid (buildings, hills, trees) between a and b, at about head height.
func _sees(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 1.3, 0), b + Vector3(0, 1.0, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()
