extends Node3D
## The police. Patrol cars drive about in the traffic, and they see in a cone ahead of them (and anything
## right beside them). Speed past one well over the limit, hit one, or crash into someone in front of one,
## and they're after you: wanted stars under the minimap, sirens you hear go by, and more of them the
## longer it goes on and the more of them you hit or wreck.
##
## Each police car's sight is a cone (drawn on the minimap while they're after you). Get out of every cone
## and stay out till the stars stop flashing and you've lost them; let them box you in and stop you and
## you're busted (a fine). They follow you along the roads, some head you off where you're going, they
## weave round the traffic (which pulls over for their sirens), get on your tail and try to spin you out
## with a PIT, and pen you in when you stop. At three stars they set up roadblocks ahead of you; at four a
## helicopter joins in, with a searchlight after dark. When it's over they switch off their lights and
## drive off. Half the street races get a visit too: then they're after everyone in it, and it isn't over
## at the finish line.
##
## Police cars are real cars (the same physics as yours), the same model as the patrol cars in the traffic,
## so one that sees you just pulls out after you.

const Car := preload("res://scripts/game/drift_car.gd")
const CARS := preload("res://scripts/game/cars.gd")
const MB := preload("res://scripts/core/mesh_builder.gd")
const Heli := preload("res://scripts/game/heli.gd")

const LAYER := 16
## Speed limits (km/h) by the kind of road.
const LIMIT := {"ring": 80, "main": 50, "road": 70, "street": 50, "lane": 40, "mountain": 60, "dirt": 50}
const TOLERANCE := 15.0     # km/h over the limit they let go
const SEE_R := 50.0         # a patrol car sees this far ahead...
const SEE_ANG := 1.05       # ...this far either side of straight ahead (radians)...
const NEAR_R := 13.0        # ...and anything this close, whichever way it's facing
const SPOT_R := 90.0        # a car that's after you: its cone (the one on the minimap)
const SPOT_ANG := 0.95
const CLOSE_R := 22.0
const UNITS := [0, 2, 3, 4, 4, 5]                 # police cars after you at each heat
const EVADE := [0.0, 8.0, 10.0, 12.0, 14.0, 16.0]   # seconds out of sight it takes to lose them, by heat
const BUST_T := 3.5         # stopped with a police car right there this long: busted
const HEAT_T := 60.0        # a star more for every this long they've had you in sight
const CALM_T := 20.0        # after a chase: a breather before they notice you again
const BLOCK_CD := 24.0      # seconds between roadblocks
const ROLES := ["chase", "cut", "chase", "cut", "chase"]

var game: Node
var island: Node
var traffic: Node
var heat := 0               # wanted stars (0: nobody's after you)
var heat_pts := 0.0
var chase_t := 0.0
var seen := false
var unseen := 0.0           # out of everyone's sight this long
var last_seen := Vector3.ZERO
var bust := 0.0             # 0..1: how nearly they've got you
var units: Array = []       # {car, role, target, state ("chase", "block", "patrol", "wreck"), path, pi, ...}
var heli: Heli
var calm := 0.0
var _witness_t := 0.0        # someone saw you knock a person down: they call it in when this runs out
var _witness_at := Vector3.ZERO
var limit := 0              # the limit where you are, km/h (0: off the roads)
var patrol_near := false    # a patrol car's about (the limit sign comes up)
var race_chase := false     # they're onto a street race: the racers too
var siren_k := 0.0          # (the sirens are 3D now, one on each car: this stays 0)
var held := false
var stats := {"spawned": 0, "busted_racers": 0, "wrecked": 0, "notices": 0, "blocks": 0, "pits": 0}
var _sighted := false
var _race_id := 0
var _race_at := -1.0
var _ram_cd := 0.0
var _spawn_cd := 0.0
var _block_cd := 8.0
var _scan := 0.0
var _last_hit := -1.0
var _n := 0
var _mats := {}
var _blip_mat: StandardMaterial3D
var _cone_mat: StandardMaterial3D
var _cone_mesh: ArrayMesh
var _siren: AudioStream
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
	# the sight cones on the minimap: a fan, see-through
	_cone_mat = StandardMaterial3D.new()
	_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cone_mat.albedo_color = Color(1.0, 0.35, 0.4, 0.28)
	_cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var fan := MB.new()
	var segs := 14
	for k in segs:
		var a0 := -SPOT_ANG + 2.0 * SPOT_ANG * k / segs
		var a1 := -SPOT_ANG + 2.0 * SPOT_ANG * (k + 1) / segs
		var p0 := Vector3(sin(a0), 0, -cos(a0)) * SPOT_R
		var p1 := Vector3(sin(a1), 0, -cos(a1)) * SPOT_R
		fan.tri(Vector3.ZERO, p0, p1, Vector3.UP, Vector3.UP, Vector3.UP, Color.WHITE)
	_cone_mesh = fan.commit()
	_siren = game.sound.siren.stream if game.sound.siren else load("res://assets/audio/sfx/siren.wav")
	game.car.collision_mask = game.car.collision_mask | LAYER
	game.cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_IDLE_STEP
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
	_block_cd -= dt
	calm -= dt
	if _witness_t > 0.0:
		_witness_t -= dt
		if _witness_t <= 0.0 and heat == 0 and game.chase_ok():
			start(1.0, "A witness called the police")
	_scan -= dt
	if _scan <= 0.0:
		_scan = 0.2
		_look_around(cp)
	_hits()
	_race_watch()
	if heat > 0:
		_chase(dt, cp)
	if heat > 0:
		_roadblocks()
	_heli_tick(dt, cp)
	for u in units.duplicate():
		_drive(u, dt)
	# the traffic pulls over for the sirens
	var sirens := []
	for u in units:
		if u["state"] == "chase" and is_instance_valid(u["car"]):
			var uc: RigidBody3D = u["car"]
			if uc.linear_velocity.length() > 4.0:
				sirens.append([uc.global_position, -uc.global_transform.basis.z])
	traffic.sirens = sirens
	_tidy_up(cp)
	# the minimap: police cars are red and blue dots, flashing, with their sight cones
	var blink := fmod(Time.get_ticks_msec() * 0.001, 0.5) < 0.25
	_blip_mat.albedo_color = Color(1.0, 0.15, 0.2) if blink else Color(0.2, 0.4, 1.0)
	_cone_mat.albedo_color = Color(1.0, 0.35, 0.4, 0.26) if seen else Color(0.9, 0.92, 1.0, 0.3)
	for u in units:
		if not is_instance_valid(u["car"]):
			continue
		var uc2: Node3D = u["car"]
		var p := uc2.global_position
		var on: bool = u["state"] == "chase" or u["state"] == "block"
		(u["blip"] as Node3D).visible = on
		(u["blip"] as Node3D).global_position = Vector3(p.x, 300.8, p.z)
		(u["cone"] as Node3D).visible = on and heat > 0
		var f := -uc2.global_transform.basis.z
		(u["cone"] as Node3D).global_transform = Transform3D(Basis(Vector3.UP, atan2(-f.x, -f.z)), Vector3(p.x, 300.6, p.z))
	if game.args.has("copslog") and int(game.time * 2.0) != int((game.time - dt) * 2.0):
		var pulled := 0
		for tc in traffic.cars:
			if float(tc.get("pull", 0.0)) > 0.5:
				pulled += 1
		var line := "COPS t=%.1f heat=%d pts=%.2f seen=%s unseen=%.1f bust=%.2f you=%.0fkmh lim=%d heli=%s pulled=%d pits=%d" % [game.time, heat, heat_pts, seen, unseen, bust,
			absf(you.speed) * 3.6, limit, "sees" if heli and heli.sees(cp) else ("yes" if heli else "no"), pulled, int(stats["pits"])]
		for u in units:
			if is_instance_valid(u["car"]):
				var uc3: Car = u["car"]
				line += " | %s/%s d=%.0f v=%.0f %s%s%s" % [String(u["state"]), String(u["role"]), uc3.global_position.distance_to(cp),
					uc3.linear_velocity.length() * 3.6, "sees " if u["sees"] else "", "you" if u["target"] == you else "racer",
					(" REV" if float(u["rev"]) > 0.0 else "") + " " + String(u["mode"])]
		print(line)

## Does a police car at `from` facing `fwd` see p (in its cone of r and ang, or within near, with nothing
## solid in between)?
func _cone(from: Vector3, fwd: Vector3, p: Vector3, r: float, ang: float, near: float) -> bool:
	var to := p - from
	to.y = 0.0
	var d := to.length()
	if d > r:
		return false
	if d > near:
		var f := Vector3(fwd.x, 0, fwd.z).normalized()
		if f.angle_to(to) > ang:
			return false
	return _sees(from, p)

## The limit where you are, which patrol cars are about, and whether one of them has seen you speeding.
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
		if d > SEE_R or not game.chase_ok_or_chase():
			continue
		if not _cone(b.global_position, -b.global_transform.basis.z, cp, SEE_R, SEE_ANG, NEAR_R):
			continue
		if heat == 0 and calm <= 0.0 and game.chase_ok() and limit > 0 and kmh > limit + TOLERANCE:
			stats["notices"] += 1
			start(1.0, "Speeding · %d in a %d" % [int(kmh), limit])
			_join(c)
			return
		if heat > 0 and not seen:
			# they're looking for you and this one's spotted you: back on, and it pulls out after you
			_spotted(cp)
			if _active() < UNITS[heat] + 1:
				_join(c)
			return

## Is a police car (a patrol, or one about the place) looking at you right now?
func _witnessed(cp: Vector3) -> bool:
	for c in traffic.cars:
		if String(c["model"]) == "k_car_police" and int(c["mode"]) < 2:
			var b: Node3D = c["body"]
			if _cone(b.global_position, -b.global_transform.basis.z, cp, SEE_R, SEE_ANG, NEAR_R):
				return true
	for u in units:
		if is_instance_valid(u["car"]) and u["state"] != "wreck":
			var uc: Node3D = u["car"]
			if _cone(uc.global_position, -uc.global_transform.basis.z, cp, SEE_R, SEE_ANG, NEAR_R):
				return true
	return false

## You hit a car in the traffic: a patrol car's a crime; so is anyone else's, if the police saw it.
func rammed(body: Node) -> void:
	var c: Dictionary = traffic._car_of(body)
	if c.is_empty() or _ram_cd > 0.0:
		return
	var cp: Vector3 = game.car.global_position
	if String(c["model"]) == "k_car_police":
		if not game.chase_ok_or_chase():
			return
		_ram_cd = 2.5
		if heat == 0:
			start(2.0 if absf(game.car.speed) > 11.0 else 1.0, "Hit a police car")
		else:
			heat_pts += 0.4
			_spotted(cp)
	elif heat == 0 and calm <= 0.0 and game.chase_ok() and _witnessed(cp):
		_ram_cd = 2.5
		start(1.0, "Crashed in front of the police")
	elif heat > 0:
		heat_pts += 0.08

func _hits() -> void:
	var h: Dictionary = game.car.hit
	if h.is_empty() or float(h["t"]) == _last_hit:
		return
	_last_hit = float(h["t"])
	var who = h.get("who")
	if who == null or not is_instance_valid(who) or not (who is Node) or not (who as Node).has_meta("police"):
		return
	var rel: float = (game.car.linear_velocity - (who as RigidBody3D).linear_velocity).length()
	if rel < 5.0 or _ram_cd > 0.0:
		return
	_ram_cd = 2.5
	if heat == 0:
		if game.chase_ok_or_chase():
			start(2.0, "Rammed a police car")
	else:
		heat_pts += 0.3

## You knocked someone down. In front of the police (or with them after you already) it's straight on;
## otherwise, more often than not, somebody who saw it calls it in a few seconds later.
func ped_hit(at: Vector3) -> void:
	if not game.chase_ok_or_chase():
		return
	var cp: Vector3 = game.car.global_position
	if heat > 0:
		heat_pts += 0.7
		_spotted(cp)
		if int(heat_pts) > heat:
			start(heat_pts, "Ran someone down")
		return
	if _witnessed(cp):
		start(2.0, "Ran someone down in front of the police")
	elif _witness_t <= 0.0 and randf() < 0.75:
		_witness_t = randf_range(2.5, 5.0)
		_witness_at = at

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
		_block_cd = 10.0
		game.police_started(why)
	elif heat > was:
		game.police_heat_up(heat)

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
	# who's got eyes on you (each checks a few times a second): the cars' cones, the helicopter's circle
	var any := false
	var nearest := INF
	for u in units:
		if (u["state"] != "chase" and u["state"] != "block") or not is_instance_valid(u["car"]):
			continue
		var c: Car = u["car"]
		var d := c.global_position.distance_to(cp)
		nearest = minf(nearest, d)
		u["eye_t"] = float(u["eye_t"]) - dt
		if float(u["eye_t"]) <= 0.0:
			u["eye_t"] = 0.2
			u["sees"] = _cone(c.global_position, -c.global_transform.basis.z, cp, SPOT_R, SPOT_ANG, CLOSE_R)
		if u["sees"] and u["target"] == game.car:
			any = true
			_sighted = true
	if heli and heli.sees(cp):
		any = true
		_sighted = true
	if not _sighted and chase_t < 15.0:
		any = true            # (on their way: the radio tells them where you are)
	if race_chase and game.race != null and game.race.state == 1:
		any = true            # (a race: they know where it goes. Losing them starts once you're over the line)
	if any:
		if not seen:
			game.police_reacquired()
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
		game.police_heat_up(heat)
	game.save.max_stat("max_heat", heat)
	# boxed in and stopped
	var boxed := absf(game.car.speed) < 2.0 and nearest < 7.0 and seen
	bust = clampf(bust + (dt / BUST_T if boxed else -dt / BUST_T * 0.7), 0.0, 1.0)
	if bust >= 1.0:
		_busted()
		return
	# more of them as it heats up (they turn up out of sight: round you, or where they last saw you)
	var want: int = UNITS[heat] + (1 if race_chase and game.race != null else 0)
	if _active() < want and _spawn_cd <= 0.0:
		_spawn_cd = 3.5
		_spawn_near(cp if seen else last_seen, game.car, seen)

func _escaped() -> void:
	var bounty := 40 * heat + int(chase_t) * 2
	var h := heat
	_end(false)
	game.police_escaped(bounty, h)

func _busted() -> void:
	var fine := mini(int(game.save.data["coins"]), 50 + 75 * (heat - 1))
	_end(true)
	game.police_busted(fine)

## The chase is over: lights and sirens off, and they drive off (once they've seen you on your way, if
## they've just booked you), and go once you can't see them.
func _end(booked: bool) -> void:
	heat = 0
	heat_pts = 0.0
	seen = false
	bust = 0.0
	unseen = 0.0
	race_chase = false
	calm = CALM_T
	for u in units:
		if u["state"] == "chase" or u["state"] == "block":
			_leave(u, 3.5 if booked else 0.0)
	if heli:
		heli.leaving = true

func _leave(u: Dictionary, wait: float) -> void:
	u["state"] = "patrol"
	u["wait"] = wait
	u["leave_t"] = 0.0
	var c: Car = u["car"]
	(c.get_node("LightBar") as Node3D).visible = false
	(u["siren"] as AudioStreamPlayer3D).stop()
	u["path"] = PackedVector3Array()
	u["away"] = _somewhere_away(c.global_position)

## A spot on a road well away from you (where a police car that's done drives off to).
func _somewhere_away(from: Vector3) -> Vector3:
	var you: Vector3 = game.car.global_position
	var out := Vector3(from.x - you.x, 0, from.z - you.z)
	if out.length() < 1.0:
		out = Vector3(1, 0, 0)
	out = out.normalized()
	for tries in 10:
		var q := Vector2(from.x, from.z) + Vector2(out.x, out.z).rotated(randf_range(-0.9, 0.9)) * randf_range(250.0, 400.0)
		var loc: Array = game.router.nearest_near(q, 20.0)
		if int(loc[0]) >= 0:
			var pt: Vector2 = game.router.road_at(int(loc[0]), float(loc[1]))
			return Vector3(pt.x, 0, pt.y)
	return from + out * 300.0

## Paused, or in the garage: they wait where they are (and go quiet).
func hold(on: bool) -> void:
	held = on
	for u in units:
		var c: RigidBody3D = u["car"]
		if not is_instance_valid(c):
			continue
		(u["siren"] as AudioStreamPlayer3D).stream_paused = on
		if on and not c.freeze:
			u["held"] = [c.linear_velocity, c.angular_velocity]
			c.freeze = true
		elif not on and u.has("held"):
			c.freeze = false
			c.linear_velocity = u["held"][0]
			c.angular_velocity = u["held"][1]
			u.erase("held")
	if heli:
		heli.quiet(on)

## Everything gone at once (back to the title).
func clear() -> void:
	_witness_t = 0.0
	for u in units:
		if is_instance_valid(u["car"]):
			(u["car"] as Node).queue_free()
	units.clear()
	if heli:
		heli.queue_free()
		heli = null
	heat = 0
	heat_pts = 0.0
	seen = false
	bust = 0.0
	race_chase = false
	traffic.sirens = []

# ------------------------------------------------------------------ roadblocks and the helicopter

## Three stars and up: now and then two police cars are parked across the road a little way ahead of
## where you're going (put there out of your sight). Get through or round them; when you're close they
## join in.
func _roadblocks() -> void:
	if heat < 3 or not seen or _block_cd > 0.0 or absf(game.car.speed) < 12.0 or game.race != null:
		return
	for u in units:
		if u["state"] == "block":
			return
	_block_cd = BLOCK_CD
	var you: Car = game.car
	var cp := you.global_position
	var dirv := Vector3(you.linear_velocity.x, 0, you.linear_velocity.z).normalized()
	var path: PackedVector3Array = game.router.find(cp, cp + dirv * 280.0, true)
	if path.size() < 3:
		return
	var walked := 0.0
	var want := clampf(absf(you.speed) * 5.5, 130.0, 210.0)
	for k in range(1, path.size()):
		var seg := Vector2(path[k].x - path[k - 1].x, path[k].z - path[k - 1].z).length()
		walked += seg
		if walked < want:
			continue
		var p2 := Vector2(path[k].x, path[k].z)
		var loc: Array = game.router.nearest_near(p2, 8.0)
		if int(loc[0]) < 0 or not LIMIT.has(island.roads[int(loc[0])]["kind"]):
			return
		var ri := int(loc[0])
		var s := float(loc[1])
		var pt: Vector2 = game.router.road_at(ri, s)
		var pos := Vector3(pt.x, island.height_at(pt.x, pt.y) + 0.7, pt.y)
		var cam: Camera3D = game.cam
		if cam.is_position_in_frustum(pos) and pos.distance_to(cam.global_position) < 160.0 and _sees(cam.global_position, pos + Vector3(0, 0.6, 0)):
			return          # (in plain view: not this time)
		for c in traffic.cars:
			if (c["body"] as Node3D).global_position.distance_to(pos) < 14.0:
				return
		var t: Vector2 = (game.router.road_at(ri, s + 1.0) - game.router.road_at(ri, s - 1.0)).normalized()
		var rt := Vector2(-t.y, t.x)
		var road_yaw := atan2(-t.x, -t.y)
		for sd0 in [-1.0, 1.0]:
			var sd: float = sd0
			var q: Vector2 = pt + rt * 2.5 * sd
			var yaw: float = road_yaw + (PI * 0.5 - 0.4) * sd
			var xf: Transform3D = game.on_ground(Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, pos.y, q.y)))
			var u := _unit(xf, Vector3.ZERO, you)
			u["state"] = "block"
			(u["siren"] as AudioStreamPlayer3D).stop()
		stats["blocks"] += 1
		return

## Four stars and up: the helicopter. It watches you while they've got you, and searches round where you
## were last seen when they haven't.
func _heli_tick(dt: float, cp: Vector3) -> void:
	if heat >= 4 and heli == null:
		heli = Heli.new()
		heli.name = "PoliceHeli"
		game.add_child(heli)
		heli.build(island, game.toon, game.atmos)
		var a := randf() * TAU
		heli.global_position = cp + Vector3(cos(a), 0, sin(a)) * 220.0 + Vector3(0, 55.0, 0)
		heli.look = cp
	if heli == null:
		return
	var focus: Vector3 = cp + (game.car as RigidBody3D).linear_velocity * 0.8 if seen else last_seen + Vector3(cos(chase_t * 0.3), 0, sin(chase_t * 0.3)) * 45.0
	var aim: Vector3 = cp if seen else focus
	heli.tick(dt, focus, aim, game.atmos.night)
	if heli.gone:
		heli.queue_free()
		heli = null

# ------------------------------------------------------------------ street races

## Half the street races (decided when one starts; never one on a circuit) get a visit: some way into it, police cars turn up after
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
		if bool((r.def as Dictionary).get("track", false)) and _force < 0:
			go = false        # (a race on a closed circuit is all above board: no visit)
		_race_at = randf_range(18.0, 45.0) if go else -1.0
		if go and game.args.has("copsat"):
			_race_at = float(game.args["copsat"])
	if _race_at > 0.0 and r.state == 1 and r.t >= _race_at:
		_race_at = -1.0
		race_chase = true
		start(2.0, "The police are onto the race")
		# they come in from round about: some after you, the rest after whoever's nearest them
		for i in 3:
			_spawn_near(game.car.global_position, game.car, true)
		_spawn_cd = 4.0

func _pick_target(u: Dictionary) -> void:
	u["target"] = game.car
	var r = game.race
	if not race_chase or r == null or r.state != 1 or int(u["idx"]) % 2 == 0:
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
		var q := Vector2(p.x, p.z) + dirn * (randf_range(55.0, 105.0) if behind else randf_range(80.0, 150.0))
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

## A patrol car in the traffic that's seen you: it becomes a police car after you, right where it is and
## going as it was (the same model, so it just pulls out after you), and the traffic gets a new car somewhere
## out of sight in its place.
func _join(c: Dictionary) -> void:
	var b: Node3D = c["body"]
	var f := -b.global_transform.basis.z
	var p := b.global_position
	var xf: Transform3D = game.on_ground(Transform3D(Basis(Vector3.UP, atan2(-f.x, -f.z)), p + Vector3(0, 0.7, 0)))
	_unit(xf, Vector3(f.x, 0, f.z) * float(c["v"]), game.car)
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
	c.rammed.connect(func(b, v, j, at): traffic.knock(b, v, j, at))     # (bumping the traffic it can't get round)
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
	var cone := MeshInstance3D.new()
	cone.mesh = _cone_mesh
	cone.material_override = _cone_mat
	cone.layers = island.MAP_LAYER
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.top_level = true
	cone.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	c.add_child(cone)
	# its siren: a sound of its own, from where it is (you hear it go by, pitch dropping as it passes)
	var sn := AudioStreamPlayer3D.new()
	var st = _siren
	if st is AudioStreamWAV:
		st = (st as AudioStreamWAV).duplicate()
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * st.mix_rate)
	sn.stream = st
	sn.bus = "SFX"
	sn.unit_size = 22.0
	sn.max_distance = 420.0
	sn.volume_db = -5.0
	sn.pitch_scale = randf_range(0.96, 1.04)
	sn.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	c.add_child(sn)
	sn.play(randf() * 1.5)
	var u := {"car": c, "target": target, "state": "chase", "role": ROLES[_n % ROLES.size()], "idx": _n,
		"path": PackedVector3Array(), "pi": 0, "replan": 0.0, "eye_t": 0.0, "sees": false, "look": 0.0, "clear": false,
		"stuck": 0.0, "rev": 0.0, "stucks": 0, "flip": 0.0, "search": last_seen, "bust": 0.0, "retarget": 0.0,
		"blip": blip, "cone": cone, "siren": sn, "leave_t": 0.0, "wait": 0.0, "away": Vector3.ZERO, "mode": "road", "vt": 0.0}
	units.append(u)
	_pick_target(u)
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

## Drive one police car.
func _drive(u: Dictionary, dt: float) -> void:
	var c: Car = u["car"]
	if not is_instance_valid(c):
		units.erase(u)
		return
	if c.freeze:
		return
	var you: Car = game.car
	var pos := c.global_position
	var v := c.linear_velocity.length()
	var fwd := -c.global_transform.basis.z
	var rgt := c.global_transform.basis.x
	fwd.y = 0.0
	rgt.y = 0.0
	fwd = fwd.normalized()
	rgt = rgt.normalized()
	match String(u["state"]):
		"wreck":
			c.throttle = 0.0
			c.brake = 0.0
			c.handbrake = 1.0
			c.steer_in = 0.0
			return
		"block":
			# parked across the road: waiting for you (on the handbrake: the brake at a standstill reverses)
			c.throttle = 0.0
			c.brake = 0.0
			c.handbrake = 1.0
			c.steer_in = 0.0
			if pos.distance_to(you.global_position) < 30.0:
				u["state"] = "chase"
				c.handbrake = 0.0
				(u["siren"] as AudioStreamPlayer3D).play()
			return
	if float(u["wait"]) > 0.0:
		u["wait"] = float(u["wait"]) - dt
		c.throttle = 0.0
		c.brake = 1.0 if v > 1.0 else 0.0
		c.handbrake = 1.0
		c.steer_in = 0.0
		return
	var patrol: bool = u["state"] == "patrol"
	# who it's after
	u["retarget"] = float(u["retarget"]) - dt
	if not patrol and (float(u["retarget"]) <= 0.0 or not is_instance_valid(u["target"])):
		u["retarget"] = 3.0
		_pick_target(u)
	var tgt: Node3D = u["target"] if is_instance_valid(u["target"]) else you
	var after_you: bool = tgt == you
	var know := not patrol
	var goal: Vector3
	var tv := Vector3.ZERO
	if patrol:
		goal = u["away"]
	elif after_you and not seen:
		goal = u["search"]
		know = false
		if Vector2(pos.x, pos.z).distance_to(Vector2(goal.x, goal.z)) < 16.0:
			u["search"] = _search_spot()
			goal = u["search"]
			u["replan"] = 0.0
	else:
		goal = tgt.global_position
		tv = (tgt as RigidBody3D).linear_velocity
		# heading you off: some go for where you'll be in a few seconds, not where you are
		if u["role"] == "cut" and tv.length() > 12.0 and pos.distance_to(goal) > 45.0:
			goal += tv * clampf(pos.distance_to(goal) / 35.0, 1.5, 4.0)
	var tpos := tgt.global_position
	var d_t := Vector2(pos.x, pos.z).distance_to(Vector2(tpos.x, tpos.z))
	u["look"] = float(u["look"]) - dt
	if float(u["look"]) <= 0.0:
		u["look"] = 0.3
		u["clear"] = know and d_t < 40.0 and _sees(pos, tpos)
	var aim: Vector2
	var vt := 44.0
	var close := know and d_t < 34.0 and bool(u["clear"])
	if close:
		aim = _close_in(u, c, tgt, v)
		vt = float(u["vt"])
		u["path"] = PackedVector3Array()
	else:
		u["mode"] = "road"
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
		if patrol:
			vt = minf(vt, 13.0)
		elif not know:
			vt = minf(vt, 24.0)       # (looking for you: not flat out)
	# the traffic: steer round anything in the way (on the side with more room), slow for it if it's close
	var dodge := 0.0
	var look_d := 8.0 + v * 1.1
	for tc in traffic.cars:
		var tb: Node3D = tc["body"]
		var rel := tb.global_position - pos
		var ahead := rel.dot(fwd)
		if ahead < 1.5 or ahead > look_d:
			continue
		var lat := rel.dot(rgt)
		if absf(lat) < 2.8:
			var side := -signf(lat) if absf(lat) > 0.3 else -1.0
			var need := (3.0 - absf(lat)) * side
			if absf(need) > absf(dodge):
				dodge = need
			if ahead < 7.0 and absf(lat) < 1.6:
				vt = minf(vt, float(tc["v"]) + 3.0)
	if dodge != 0.0 and not (close and String(u["mode"]) == "pit"):
		aim += Vector2(rgt.x, rgt.z) * dodge * 1.4
	# another police car just ahead, going the same way: stay behind it (they'd only pile into each other)
	for o in units:
		if o == u or o["state"] != "chase" or not is_instance_valid(o["car"]):
			continue
		var oc: RigidBody3D = o["car"]
		var rel2 := oc.global_position - pos
		if rel2.length() < 11.0 and rel2.normalized().dot(fwd) > 0.75:
			vt = minf(vt, oc.linear_velocity.length() + (rel2.length() - 7.0) * 0.6)
	# and a patrol car that's done never drives into you
	if patrol:
		var ry := you.global_position - pos
		if ry.length() < 12.0 and ry.normalized().dot(fwd) > 0.5:
			vt = 0.0
	var to := Vector3(aim.x - pos.x, 0, aim.y - pos.z)
	var ang := atan2(fwd.z * to.x - fwd.x * to.z, fwd.x * to.x + fwd.z * to.z)
	var steer := clampf(-ang * 2.4, -1.0, 1.0)
	c.handbrake = 0.0
	if absf(ang) > 0.5 and v > 8.0:
		vt = minf(vt, v - 3.0)
	if vt <= 0.0 and v < 1.0:
		# (stopped where it wants to be: on the handbrake, or the brake would back it up)
		c.throttle = 0.0
		c.brake = 0.0
		c.handbrake = 1.0
	elif v < vt - 0.6:
		c.throttle = 1.0
		c.brake = 0.0
	elif v > vt + 1.2:
		c.throttle = 0.0
		c.brake = clampf((v - vt) / 4.0, 0.3, 1.0)
	else:
		c.throttle = 0.4
		c.brake = 0.0
	c.steer_in = steer
	# facing away from you and nearly stopped: back round (a reverse turn), not a slow loop forward
	if know and absf(ang) > 2.2 and v < 6.0 and float(u["rev"]) <= 0.0 and d_t < 60.0:
		u["rev"] = 1.3
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
		(u["siren"] as AudioStreamPlayer3D).stop()
		stats["wrecked"] += 1
		if heat > 0:
			heat_pts += 0.6
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

## Right there with nothing in between: what to do about it. Sets u["vt"] (speed to aim for) and u["mode"];
## returns the point to drive at.
func _close_in(u: Dictionary, c: Car, tgt: Node3D, v: float) -> Vector2:
	var pos := c.global_position
	var tp := tgt.global_position
	var tv := (tgt as RigidBody3D).linear_velocity
	var tf := -tgt.global_transform.basis.z
	var tr := tgt.global_transform.basis.x
	tf.y = 0.0
	tr.y = 0.0
	tf = tf.normalized()
	tr = tr.normalized()
	var rel := pos - tp
	var along := rel.dot(tf)          # (+: ahead of it)
	var side := rel.dot(tr)           # (+: off its right side)
	var sgn := signf(side) if absf(side) > 0.4 else (1.0 if int(u["idx"]) % 2 == 0 else -1.0)
	var tvl := tv.length()
	var aim3: Vector3
	if tvl < 4.0:
		# stopped (or nearly): pen it in, one across its nose, the next behind it
		var front := int(u["idx"]) % 2 == 0
		var spot := tp + tf * (6.0 if front else -6.0) + tr * sgn * 1.2
		var ds := pos.distance_to(spot)
		aim3 = spot
		u["vt"] = 0.0 if ds < 2.5 else clampf(ds * 0.9, 2.0, 14.0)
		u["mode"] = "box"
	elif heat >= 2 and along > -5.5 and along < 1.2 and absf(side) < 4.2 and tvl > 8.0:
		# alongside its back end: the PIT, turning in against its rear corner to spin it round
		aim3 = tp - tf * 2.2 + tr * sgn * 0.2
		u["vt"] = tvl + 2.5
		if u["mode"] != "pit":
			stats["pits"] += 1
		u["mode"] = "pit"
	else:
		# on its tail (from two stars, a little off to one side: lining up the PIT)
		var tail := tp - tf * (6.5 if heat < 2 else 3.2) + tr * sgn * (0.0 if heat < 2 else 2.3)
		var lead := clampf(pos.distance_to(tail) / maxf(v, 10.0), 0.0, 0.8)
		aim3 = tail + tv * lead
		var gap := pos.distance_to(tail)
		u["vt"] = tvl + clampf(gap * 0.6, -4.0, 12.0)
		u["mode"] = "tail"
	return Vector2(aim3.x, aim3.z)

## Police cars that are done (driven off, wrecked, stuck for good or left far behind) go once you can't
## see them.
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
			"patrol":
				var away: Vector3 = u["away"]
				go = not in_view and (d > 60.0 or float(u["leave_t"]) > 25.0 or Vector2(p.x - away.x, p.z - away.z).length() < 20.0)
			"wreck":
				go = (not in_view and float(u["leave_t"]) > 3.0) or float(u["leave_t"]) > 12.0
			"block":
				go = d > 320.0 and not in_view
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
