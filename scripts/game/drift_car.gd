extends RigidBody3D
## The player's car: a rigid body riding on four raycast springs, with a simple tyre model (grip builds
## with slip angle, then falls off a little once it slides, inside a friction circle). Rear-wheel drive
## with an automatic gearbox, brakes, and a handbrake that locks the rear and lets it swing out.
## Touch controls are on/off buttons, so steering eases in, the front wheels follow the slide when you
## let go (counter-steer), and a light hand keeps a drift from becoming a spin.
## Two ways of driving: normally it grips like a race car (planted rear, traction control, a stability
## system that catches a slide); pull the handbrake and it's in drift mode (loose tail, drift help) until
## you've straightened up again. Linked drifts (swinging from one side to the other) stay in drift mode.

const M := preload("res://scripts/core/models.gd")
const Dents := preload("res://scripts/game/dents.gd")
const MB := preload("res://scripts/core/mesh_builder.gd")

signal shifted(gear: int)
signal bumped(strength: float)
## You hit a traffic car: the push it gets (an impulse, N·s) and where.
signal rammed(body: Node3D, its_velocity: Vector3, impulse: Vector3, at: Vector3)

# ---- inputs, set every frame by main
var throttle := 0.0
var brake := 0.0
var handbrake := 0.0
var steer_in := 0.0          # -1 left .. 1 right
var assist := 1.0            # 0 = raw, 1 = full drift help

# ---- tuning (cars and upgrades change these)
var engine_force := 7600.0   # N at the wheels, low down
var power_speed := 13.0      # m/s where the engine stops pulling its hardest
var top_speed := 46.0
var mu := 1.12               # tyre grip
var rear_grip := 0.96        # rear grip relative to the front (less: looser tail)
var steer_lock := deg_to_rad(36.0)
var brake_force := 11000.0
var spring_k := 42000.0
var damper_c := 3600.0
var drag := 0.62

# ---- state you can read
var speed := 0.0             # forward speed, m/s (negative backwards)
var slip := 0.0              # radians between where the car points and where it's going
var drift := 0.0             # 0..1, how sideways (and fast) it is
var grounded := 0            # wheels on the ground
var air_t := 0.0
var gear := 1
var rpm := 0.0               # 0..1 within the gear
var surface := 1             # what the rear wheels are on (island.S_*)
var wheelspin := 0.0
var steer := 0.0             # current front wheel angle
var info: Dictionary         # the model's sizes
var island: Node

var wheels: Array = []
var wheel_nodes: Array = []
var body_node: MeshInstance3D
var _last_v := Vector3.ZERO
var _slide := 0.0
var _hb_t := 0.0
var _last_slip := 0.0
var _gear_cd := 0.0
var _rev_t := 0.0            # how long the brake has been held at a standstill
var vis_steer := 0.0
var wall_t := 0.0            # just touched a wall (counts down)
var wall_pos := Vector3.ZERO  # where it last touched one
var hit := {}                # the last knock: {"t", "pos", "n" (into the car), "kind": wall/car}
var damage := 0.0            # 0..100, from knocks; gas stations fix it (for coins)
var power_k := 1.0           # 1 normally; low when the tank's empty
var dent_data := {}
var _vh: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]   # the last few velocities, for knocks
var _ram_cd := 0.0
var _clock := 0.0
var drift_mode := false      # pulled the handbrake: drifting physics until you straighten up
# ---- the garage tuning: camber 0..1, ride -1 (slammed) .. 1 (lifted). More camber and lower: drifts
# easier, grips less on the road, worse off it. Less camber and higher: harder to drift, more grip, better
# off-road.
var camber := 0.0
var ride := 0.0
var ride_off := 0.0          # metres the springs sit longer (+) or shorter (-)
var grip_k := 1.0            # race grip, from the tuning
var drift_k := 0.0           # how much easier drifting is (-0.3 .. 0.9)
var nitro := 0.0             # nitrous going (0..1; main sets it while there's some in the bottle)
var neon_node: Node3D
const NEON := ["", "ff3fd0", "35e7ff", "9b5cff", "4dff7a", "ff8a2a", "ffffff", "ff3344", "3a6bff"]
const OFFROAD := [0, 3, 4, 6, 8]   # (island surfaces: grass, dirt, sand, field, forest)
const CAMBER_MAX := 10.0     # degrees
var _straight_t := 0.0
var _swing_dir := 0.0        # the side the last drift went (+1 right), for swinging into the next one
var _swing_t := 0.0         # what the front wheels show (they point into the slide when drifting)
const GRIP_MU := 1.15        # grip mode holds the road this much harder than drift mode
const DRIFT_PACE := 19.0     # m/s (about 68 km/h): a held drift settles around here
# in the air: how fast each control turns the car (rad/s) and how hard it gets there (rad/s²)
const AIR_PITCH := 3.4
const AIR_YAW := 2.8
const AIR_ROLL := 3.6
const AIR_ACC := 9.0
var on_stunt := 0            # wheels on a stunt piece (ramps, the loop, half-pipes)
var roof_t := 0.0            # lying on its roof or side, touching the ground (counts down)
# in the air, a button only does a trick once it's been pressed up there: the gas you were holding when
# you left the ramp doesn't tip the nose down (press it again for that)
var _air_free := {"gas": false, "brake": false, "steer": false}
const GEARS := [0.0, 8.5, 15.0, 22.0, 29.5, 37.0, 46.0, 60.0]
const TRAVEL := 0.28
const REST := 0.32           # ray starts this far above the wheel centre

func setup(def: Dictionary, mat: Material, isl: Node, paint := 0) -> void:
	island = isl
	info = M.car(def)
	for c in get_children():
		c.queue_free()
	neon_node = null
	wheels.clear()
	wheel_nodes.clear()
	body_node = MeshInstance3D.new()
	dent_data = Dents.own(M.painted_body(def, paint))
	body_node.mesh = dent_data["mesh"]
	damage = 0.0
	body_node.material_override = mat
	body_node.name = "Body"
	add_child(body_node)
	var spots: Array = info["wheels"]
	for i in 4:
		var wn := MeshInstance3D.new()
		wn.mesh = M.wheel_mesh(info, i)
		wn.material_override = mat
		add_child(wn)
		wheel_nodes.append(wn)
		var sp: Vector3 = spots[i]
		wheels.append({"mount": Vector3(sp.x, sp.y + REST, sp.z), "home": sp, "r": float(info["r_f"] if i < 2 else info["r_r"]),
			"front": i < 2, "left": sp.x < 0.0, "len": REST, "last": REST, "contact": false, "spin": 0.0, "load": 0.0,
			"slip": 0.0, "surf": 1})
	# a box for the body, sitting above the wheels so the springs do the work
	var w: float = info["width"]
	var l: float = info["length"]
	var h: float = info["height"]
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	var bottom: float = float(info["r_f"]) * 0.9
	bx.size = Vector3(w * 0.86, maxf(h - bottom - 0.1, 0.6), l * 0.94)
	cs.shape = bx
	cs.position = Vector3(0, bottom + bx.size.y * 0.5, (float(info["front"]) + float(info["back"])) * 0.5)
	add_child(cs)
	mass = 1250.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, bottom + 0.25, 0.12)
	inertia = Vector3(1500, 2300, 1100)
	gravity_scale = 1.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.4
	can_sleep = false
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.08          # slide along walls rather than being yanked round by them
	pm.bounce = 0.05
	physics_material_override = pm
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = 4
	collision_mask = 1 | 2
	tune(def, {})

## Car personality and garage upgrades. up: {engine, turbo, tyres, steering} levels 0..5;
## tun: the garage tuning {camber 0..5, height -2..2, neon 0 off / colour index}.
func tune(def: Dictionary, up: Dictionary, tun := {}) -> void:
	camber = clampf(float(tun.get("camber", 0)) / 5.0, 0.0, 1.0)
	ride = clampf(float(tun.get("height", 0)) / 2.0, -1.0, 1.0)
	ride_off = ride * (0.08 if ride < 0.0 else 0.1)
	grip_k = 1.0 - 0.09 * camber + 0.04 * ride
	drift_k = clampf(0.6 * camber - 0.3 * ride, -0.3, 0.9)
	if neon_node:
		neon_node.queue_free()
		neon_node = null
	var ni := int(tun.get("neon", 0))
	if ni > 0 and ni < NEON.size() and not info.is_empty():
		neon_node = make_neon(info, NEON[ni], body_node.material_override if body_node else null)
		add_child(neon_node)
		var pl: MeshInstance3D = neon_node.get_meta("pool")
		pl.top_level = true            # (it goes on the ground, not with the car's tilt)
		pl.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var pw: float = def.get("power", 1.0) * (1.0 + 0.08 * int(up.get("engine", 0)))
	engine_force = 7600.0 * pw
	power_speed = 13.0 * (1.0 + 0.05 * int(up.get("turbo", 0)))
	top_speed = 46.0 * def.get("speed", 1.0) * (1.0 + 0.035 * int(up.get("turbo", 0)))
	drag = engine_force * power_speed / pow(top_speed, 3.0)
	mu = 1.12 * def.get("grip", 1.0) * (1.0 + 0.035 * int(up.get("tyres", 0)))
	rear_grip = 0.97 - (def.get("drift", 1.0) - 1.0) * 0.25
	steer_lock = deg_to_rad(34.0 + 2.5 * int(up.get("steering", 0)))

## Walls and cars push you about, but never roll you over or send you spinning like a top. Traffic cars
## don't stop you dead like a wall would: the two of you share the knock by weight.
func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	var wall := false
	var com := st.transform * st.center_of_mass_local
	var stunt_rid: RID = island.stunt_body if island else RID()
	var upw := st.transform.basis.y
	for i in st.get_contact_count():
		var n := st.get_contact_local_normal(i)
		# lying on its roof: the ground underneath pushes up into it (hanging upside down at the top of the
		# loop, the track above pushes down instead)
		var n_in := n if (com - st.get_contact_local_position(i)).dot(n) >= 0.0 else -n
		if upw.y < 0.35 and n_in.y > 0.6:
			roof_t = 0.15

		if stunt_rid.is_valid() and st.get_contact_collider(i) == stunt_rid:
			# a stunt piece: riding its deck or walls (whichever way up) isn't a knock; only its sides
			# square on to the car are, and even those don't hold the car flat (it may be mid-loop)
			var upc := st.transform.basis.y
			if absf(n.dot(upc)) >= 0.6:
				continue
			var cps := st.get_contact_local_position(i)
			if (com - cps).dot(n) < 0.0:
				n = -n
			if hit.is_empty() or _clock - float(hit["t"]) > 0.25:
				hit = {"t": _clock, "pos": cps, "n": n, "kind": "wall"}
			continue
		if absf(n.y) >= 0.6:
			continue
		wall = true
		var cp := st.get_contact_local_position(i)
		wall_pos = cp
		if (com - cp).dot(n) < 0.0:
			n = -n                       # into the car
		var col := st.get_contact_collider_object(i)
		var kind := "car" if col is Node and ((col as Node).has_meta("traffic_id") or (col as Node).has_meta("wreck") or (col as Node).has_meta("racer")) else "wall"
		if hit.is_empty() or _clock - float(hit["t"]) > 0.25:
			hit = {"t": _clock, "pos": cp, "n": n, "kind": kind}
		if kind == "car" and col is AnimatableBody3D and _ram_cd <= 0.0:
			var vt := st.get_contact_collider_velocity_at_position(i)
			var vb: Vector3 = _vh[0]
			for q in _vh:
				if ((q as Vector3) - vt).dot(n) < (vb - vt).dot(n):
					vb = q
			var closing: float = (vb - vt).dot(n)
			if closing < -2.5:
				var mt: float = float((col as Node).get_meta("mass", 1150.0))
				var j: float = -(1.0 + 0.25) * closing / (1.0 / mass + 1.0 / mt)
				st.linear_velocity = vb + n * j / mass
				_ram_cd = 0.4
				rammed.emit(col, vt, -n * j, cp)
	if wall:
		wall_t = 0.3
		# scraping along costs a little speed
		st.linear_velocity *= 0.994
	if wall_t <= 0.0:
		return
	# for a moment after a knock the car won't tip: rolling and pitching are held right down
	var upv := st.transform.basis.y
	var av := st.angular_velocity
	var yaw_part := upv * av.dot(upv)
	var tip := av - yaw_part
	tip = tip * (0.4 if wall else 0.8)
	if tip.length() > 0.7:
		tip = tip.normalized() * 0.7
	st.angular_velocity = yaw_part * (0.97 if wall else 1.0) + tip

func place(xf: Transform3D) -> void:
	global_transform = xf
	reset_physics_interpolation()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_last_v = Vector3.ZERO
	for wd in wheels:
		wd["len"] = REST
		wd["last"] = REST
	gear = 1

func _physics_process(dt: float) -> void:
	if is_physics_interpolated_and_enabled():
		# drawn between physics steps: the wheels move with the steps too, so they stay smooth with the body
		_wheel_vis(dt)
	if wheels.is_empty() or freeze:
		return
	var xf := global_transform
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var com := xf * center_of_mass
	var v := linear_velocity
	speed = v.dot(fwd)
	var vflat := v - up * v.dot(up)
	var vs := vflat.length()
	# how sideways are we?
	if vs > 1.0:
		slip = atan2(vflat.dot(xf.basis.x), maxf(absf(vflat.dot(fwd)), 0.01) * signf(speed + 0.001))
		if speed < 0.0:
			slip = 0.0
	else:
		slip = 0.0
	# drift mode: in with a pull of the handbrake, out once it's been running straight for a moment
	if handbrake > 0.5 and vs > 6.0:
		drift_mode = true
		_straight_t = 0.0
	elif drift_mode:
		var straight := absf(slip) < deg_to_rad(5.0) and absf(angular_velocity.dot(up)) < 0.45
		_straight_t = _straight_t + dt if straight else 0.0
		if _straight_t > 0.35 or vs < 3.0:
			drift_mode = false
	drift = clampf((absf(slip) - deg_to_rad(9.0)) / deg_to_rad(25.0), 0.0, 1.0) * clampf((vs - 4.0) / 6.0, 0.0, 1.0)
	if not drift_mode:
		drift = 0.0          # (a slide in grip mode isn't a drift: it doesn't score)
	if handbrake > 0.5 and vs > 6.0:
		_hb_t = 0.45
	else:
		_hb_t = maxf(0.0, _hb_t - dt)
	_slide = move_toward(_slide, smoothstep(deg_to_rad(7.0), deg_to_rad(18.0), absf(slip)) * clampf((vs - 5.0) / 5.0, 0.0, 1.0), dt * 3.0)
	# ---- steering: eases toward the button, smaller at speed, front wheels follow the slide
	# as much lock as the tyres can use at this speed (a bit more, so you can still provoke a slide)
	var wb := absf(float((wheels[0]["home"] as Vector3).z - (wheels[2]["home"] as Vector3).z))
	var lock_v := minf(steer_lock, atan(wb * 1.5 * mu * 9.8 / maxf(vs * vs, 1.0)) + deg_to_rad(4.0))
	var want := steer_in * lock_v
	if absf(slip) > deg_to_rad(4.0) and speed > 2.0:
		var counter := clampf(slip, -steer_lock, steer_lock) * 0.92 * assist
		want = clampf(want + counter * (1.0 - absf(steer_in) * 0.35), -steer_lock * 1.1, steer_lock * 1.1)
		if absf(steer_in) > 0.1:
			# pushing into the drift opens the angle up
			want += steer_in * deg_to_rad(10.0) * drift
	var rate := (4.2 if absf(want) > absf(steer) else 6.5) if drift_mode else (5.5 if absf(want) > absf(steer) else 8.0)
	steer = move_toward(steer, want, rate * dt)
	# ---- engine and gearbox
	_gear_cd = maxf(0.0, _gear_cd - dt)
	var gv := absf(speed)
	if _gear_cd <= 0.0:
		if gear < GEARS.size() - 2 and gv > GEARS[gear] * 0.97 and throttle > 0.1:
			gear += 1
			_gear_cd = 0.35
			shifted.emit(gear)
		elif gear > 1 and gv < GEARS[gear - 1] * 0.72:
			gear -= 1
			_gear_cd = 0.25
	var g_lo: float = GEARS[gear - 1] * 0.55
	var g_hi: float = GEARS[gear]
	var rpm_target := clampf((gv - g_lo) / maxf(g_hi - g_lo, 1.0), 0.0, 1.0)
	if grounded == 0 or wheelspin > 0.3:
		rpm_target = minf(1.0, rpm_target + throttle * 0.5)
	rpm = lerpf(rpm, maxf(rpm_target, throttle * 0.25), 1.0 - exp(-dt * 10.0))
	# holding the brake at a standstill backs up, after a beat (so braking to a stop doesn't reverse)
	if brake > 0.1 and speed < 0.8 and throttle < 0.1:
		_rev_t += dt
	else:
		_rev_t = 0.0
	var reverse := _rev_t > 0.45 or (brake > 0.1 and speed < -0.5 and throttle < 0.1)
	var drive := 0.0
	if throttle > 0.0:
		drive = throttle * minf(engine_force, engine_force * power_speed / maxf(gv, 1.0))
		drive *= 1.0 - damage * 0.0012     # a battered car pulls a little less
		drive *= power_k                   # (and with an empty tank, hardly at all)
		# sideways, most of the power goes into wheelspin and smoke
		drive *= lerpf(1.0, 0.5, drift * clampf((vs - DRIFT_PACE + 6.0) / 6.0, 0.0, 1.0))
		if _gear_cd > 0.2:
			drive *= 0.35
	elif reverse:
		drive = -brake * engine_force * 0.45 * clampf(1.0 - (-speed) / 9.0, 0.0, 1.0)
	var braking := 0.0 if reverse else brake
	if throttle > 0.1 and speed < -1.0:
		braking = maxf(braking, throttle)   # gas while rolling backwards stops you first
	# ---- each wheel
	var space := get_world_3d().direct_space_state
	grounded = 0
	on_stunt = 0
	wheelspin = 0.0
	var rear_surf := -1
	var stunt_rid: RID = island.stunt_body if island else RID()
	for i in 4:
		var wd: Dictionary = wheels[i]
		var r: float = wd["r"]
		var origin: Vector3 = xf * (wd["mount"] as Vector3)
		var q := PhysicsRayQueryParameters3D.create(origin, origin - up * (REST + TRAVEL + r), 1 | 2)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		wd["last"] = wd["len"]
		if hit.is_empty():
			wd["contact"] = false
			wd["len"] = move_toward(float(wd["len"]), REST + TRAVEL, dt * 3.0)
			wd["load"] = 0.0
			continue
		grounded += 1
		if stunt_rid.is_valid() and hit.get("rid") == stunt_rid:
			on_stunt += 1
		wd["contact"] = true
		var hp: Vector3 = hit["position"]
		var n: Vector3 = hit["normal"]
		var length := maxf((origin - hp).dot(up) - r, 0.0)
		wd["len"] = length
		var comp := REST + 0.1 + ride_off - length     # (the ride height sets where the springs sit)
		var comp_v: float = (float(wd["last"]) - length) / dt
		var fz := maxf(0.0, spring_k * comp + damper_c * comp_v)
		if length < 0.02:
			fz += (0.02 - length) * spring_k * 6.0   # bump stop
		var on_piece: bool = stunt_rid.is_valid() and hit.get("rid") == stunt_rid
		if on_piece and length < 0.12:
			# round the loop the load runs to several g: a firm stop keeps the body off the track
			fz += (0.12 - length) * spring_k * 6.0
		fz = minf(fz, mass * 9.8 * (3.2 if on_piece else 2.5))
		wd["load"] = fz
		apply_force(up * fz, hp - com)
		# anti-roll bar: share the load across the axle
		var other: Dictionary = wheels[i ^ 1]
		if other["contact"] or i % 2 == 1:
			var arb: float = (float(other["len"]) - length) * 26000.0
			apply_force(up * arb, hp - com)
		# what's under the tyre
		var s := 1
		var g := 1.0
		if island:
			s = island.surface_at(hp.x, hp.z)
			g = island.GRIP[s]
			if hit.get("collider") != island.body or absf(hp.y - island.height_at(hp.x, hp.z)) > 0.3:
				s = 1
				g = 1.0
		var offroad := s in OFFROAD
		if offroad:
			g *= 1.0 + 0.12 * ride - 0.08 * camber     # lifted bites in the dirt; slammed with camber slips
		wd["surf"] = s
		if not wd["front"]:
			rear_surf = s
		# tyre frame on the ground
		var wf := fwd
		if wd["front"]:
			wf = Basis(up, -steer) * fwd
		wf = (wf - n * wf.dot(n)).normalized()
		var wr := wf.cross(n)
		var pv := v + angular_velocity.cross(hp - com)
		var vx := pv.dot(wr)
		var vz := pv.dot(wf)
		# (gripping, the rear holds on a little better than the front: it turns in, it doesn't spin)
		var fz_g := minf(fz, mass * 9.8 * 0.45)
		if wd["front"] and not drift_mode and drive > 0.0:
			# gripping on the gas: give the nose back the load accelerating takes off it (so it doesn't go light
			# and push wide), and you can turn while you accelerate
			# (only while the tail's following: once it starts to slide, the nose doesn't get the help)
			var follow := clampf(1.0 - (absf(slip) - deg_to_rad(2.5)) / deg_to_rad(3.0), 0.0, 1.0)
			fz_g = minf(fz_g + minf(drive * 0.5 * 0.21, mass * 9.8 * 0.055) * follow, mass * 9.8 * 0.45)
		var cap := mu * g * fz_g * (1.0 if wd["front"] else (rear_grip if drift_mode else maxf(rear_grip, 1.04)))
		if not drift_mode:
			cap *= GRIP_MU * grip_k        # race tyres, as it were (less with camber): drifting keeps its own feel
		elif not wd["front"]:
			cap *= 1.0 - 0.08 * drift_k    # (camber and a low car: the tail lets go more easily)
		# handbrake: rear wheels lock and let go sideways
		if not wd["front"] and handbrake > 0.0:
			cap *= lerpf(1.0, 0.45, handbrake)
		# once it's sideways, keeping your foot in keeps the tail light (lift off and it grips again);
		# and just after a handbrake tap the rear stays loose for a moment
		if not wd["front"] and drift_mode:
			cap *= 1.0 - 0.3 * _slide * throttle
			cap *= lerpf(1.0, 0.6, clampf(_hb_t / 0.45, 0.0, 1.0))
		# lateral force from the slip angle (peaks, then eases off as it slides)
		var alpha := atan2(vx, absf(vz) + 1.2)
		var aa := absf(alpha)
		var peak := deg_to_rad(7.5)
		var f := aa / peak if aa < peak else lerpf(1.0, 0.78 if drift_mode else 0.93, clampf((aa - peak) / deg_to_rad(35.0), 0.0, 1.0))
		var fy := -signf(alpha) * f * cap
		if pv.length() < 1.5:
			fy = clampf(-vx * fz * 0.6, -cap, cap)
		# longitudinal
		var fx := 0.0
		if not wd["front"]:
			fx += drive * 0.5 * (1.0 - handbrake)   # (the clutch goes in with the handbrake)
		var bk := braking * brake_force * (0.3 if wd["front"] else 0.2)
		if not wd["front"] and handbrake > 0.0:
			bk += handbrake * cap * 0.9
		if absf(vz) > 0.05:
			fx -= signf(vz) * minf(bk, absf(vz) * mass * 0.25 / dt)
		elif bk > 0.0 and absf(drive) < 1.0:
			fx -= vz * mass * 0.2
		fx -= vz * 4.0
		if offroad:
			fx -= vz * (8.0 + 30.0 * maxf(-ride, 0.0))   # rough ground drags, a low car more
		# gripping: traction control keeps the drive wheels just short of spinning up, and cornering comes
		# first: the engine only gets the grip the tyre isn't already using to turn
		if not wd["front"] and not drift_mode and fx > 0.0:
			var spare := sqrt(maxf(cap * cap - fy * fy, cap * cap * 0.05))
			fx = minf(fx, minf(cap * 0.8, spare * 0.92))
		# friction circle: the drive wheels spinning up steal sideways grip
		if absf(fx) > cap:
			if not wd["front"] and drive > 0.0:
				wheelspin = maxf(wheelspin, clampf((absf(fx) - cap) / cap, 0.0, 1.0))
			fx = signf(fx) * cap
		var room := sqrt(maxf(cap * cap - fx * fx, cap * cap * 0.08))
		fy = clampf(fy, -room, room)
		wd["slip"] = alpha
		# push at the tyre, a little raised so the body doesn't trip over itself
		var at := hp + up * ((com - hp).dot(up) * 0.75) - com
		apply_force(wf * fx + wr * fy, at)
		wd["spin"] += vz / r * dt
	if rear_surf >= 0:
		surface = rear_surf
	# ---- drift help: once you're sideways with your foot down, the angle follows the buttons:
	# steering into the slide deepens it, nothing holds it, steering out straightens up.
	var aslip := absf(slip)
	var slip_rate := (aslip - _last_slip) / dt
	_last_slip = aslip
	if grounded >= 2 and vs > 5.0 and not drift_mode:
		# gripping: a stability system catches any slide before it gets going
		# (a few degrees is just how a tyre corners at the limit: it only steps in past that)
		if aslip > deg_to_rad(6.0) and speed > 3.0:
			var d0 := -signf(slip)
			apply_torque(-up * d0 * (-(aslip - deg_to_rad(6.0)) * 15000.0 - slip_rate * 4500.0))
		var yr0 := angular_velocity.dot(up)
		if absf(steer_in) < 0.1:
			apply_torque(-up * yr0 * (2600.0 if brake > 0.1 else 900.0))
	elif grounded >= 2 and vs > 5.0:
		# a handbrake flick with some steering swings the tail out
		if _hb_t > 0.0 and absf(steer_in) > 0.2 and aslip < deg_to_rad(28.0):
			apply_torque(up * -steer_in * 3600.0 * (1.0 + 0.3 * drift_k) * clampf(_hb_t / 0.45, 0.0, 1.0) * clampf(vs / 12.0, 0.3, 1.0))
		var holding := (drift > 0.15 or aslip > deg_to_rad(14.0)) and throttle > 0.15 and speed > 3.0
		# a transition: steer the other way with your foot down and, as the car swings through
		# straight, the tail lets go again so it carries on into a drift the other way
		var yaw_to := -angular_velocity.dot(up) * steer_in
		if _swing_t > 0.0 and throttle > 0.5 and steer_in * _swing_dir < -0.5 and yaw_to > 0.35 \
				and (aslip < deg_to_rad(4.0) or -signf(slip) == -_swing_dir):
			_hb_t = 0.35
			_swing_t = 0.0
		_swing_t = maxf(0.0, _swing_t - dt)
		if holding:
			var dir := -signf(slip)                 # +1: sliding round to the right
			_swing_dir = dir
			_swing_t = 0.9
			var press := steer_in * dir             # +1 into the drift, -1 out of it
			var target := deg_to_rad(10.0) + maxf(press, 0.0) * deg_to_rad(34.0)   # hands off: it eases out
			if press < -0.5:
				target = deg_to_rad(4.0)
			var err := target - aslip
			apply_torque(-up * dir * (err * 16000.0 - slip_rate * 5200.0) * assist * (1.0 + 0.35 * drift_k))
		elif aslip > deg_to_rad(8.0) and speed > 3.0 and (throttle < 0.15 or brake > 0.1):
			# off the gas or on the brakes: the tyres bite again and it straightens up
			var dir2 := -signf(slip)
			apply_torque(-up * dir2 * ((deg_to_rad(1.0) - aslip) * 10000.0 - slip_rate * 4200.0) * assist * (1.0 - 0.25 * drift_k))
		if aslip > deg_to_rad(58.0) and speed > 2.0:
			apply_torque(-up * signf(slip) * (aslip - deg_to_rad(58.0)) * 30000.0 * assist)
		# a drift with your foot down doesn't bleed all its speed (but settles at a pace that fits
		# round a street corner instead of building up forever)
		if drift > 0.1 and throttle > 0.2 and speed > 0.0:
			var keep := clampf((DRIFT_PACE - vs) / 7.0, 0.0, 1.0)
			apply_central_force(vflat.normalized() * mass * 3.4 * drift * throttle * assist * keep)
		# calm the yaw a touch when nothing is pressed
		var yr := angular_velocity.dot(up)
		if absf(steer_in) < 0.1 and drift < 0.2:
			apply_torque(-up * yr * (2600.0 if brake > 0.1 else 900.0) * assist)
	# ---- in the air, GTA style: gas tips the nose down and brake pulls it up (hold either to flip),
	# steering spins the car round, and with the handbrake held steering barrel-rolls it instead. Hands off,
	# the spin eases and, if it's roughly upright, the car settles level for the landing.
	if grounded == 0:
		air_t += dt
		if throttle < 0.1:
			_air_free["gas"] = true
		if brake < 0.1:
			_air_free["brake"] = true
		if absf(steer_in) < 0.1:
			_air_free["steer"] = true
		var gas_a := throttle if _air_free["gas"] else 0.0
		var brake_a := brake if _air_free["brake"] else 0.0
		var steer_a := steer_in if _air_free["steer"] else 0.0
		var ctl := clampf((air_t - 0.12) / 0.2, 0.0, 1.0)     # (a hop over a crest isn't a flip)
		if ctl > 0.0:
			var bs := xf.basis
			var wl := bs.inverse() * angular_velocity       # x: nose up, y: turning left, z: rolling left
			var rolling := handbrake > 0.5
			var ask := Vector3(brake_a - gas_a, 0.0 if rolling else -steer_a, -steer_a if rolling else 0.0)
			var rates := Vector3(AIR_PITCH, AIR_YAW, AIR_ROLL)
			var acc := Vector3.ZERO
			for a in 3:
				if absf(ask[a]) > 0.1:
					acc[a] = clampf((ask[a] * rates[a] - wl[a]) * 8.0, -AIR_ACC, AIR_ACC)
				else:
					acc[a] = clampf(-wl[a] * 2.0, -4.0, 4.0)
			apply_torque(bs * (acc * inertia) * ctl)
			if absf(steer_a) < 0.1 and gas_a < 0.1 and brake_a < 0.1 and up.y > 0.3:
				apply_torque(up.cross(Vector3.UP) * 4500.0 * ctl)
	else:
		air_t = 0.0
		for k in _air_free:
			_air_free[k] = false
	# ---- on a stunt piece (the loop, a half-pipe wall) the tyres hold on, as long as you keep some pace
	if on_stunt >= 2 and up.y < 0.9:
		# (only needed at a crawl: going fast, the bend itself holds the car on)
		var hold := clampf((vs - 4.0) / 6.0, 0.0, 1.0) * clampf((22.0 - vs) / 8.0, 0.0, 1.0)
		apply_central_force(-up * mass * 9.8 * clampf(1.0 - up.y, 0.0, 2.0) * 0.75 * hold)
	# ---- on its roof (or side), the bodywork scrapes along the ground and soon stops
	roof_t = maxf(0.0, roof_t - dt)
	if roof_t > 0.0 and grounded == 0:
		var vh := Vector3(v.x, 0.0, v.z)
		if vh.length() > 0.3:
			apply_central_force(-vh.normalized() * mass * 9.8 * 0.55 - vh * mass * 0.6)
		apply_torque(-angular_velocity * 900.0)
	# ---- nitrous: a hard shove along the nose while it lasts (the drag lets it run a good deal faster)
	if nitro > 0.0 and grounded >= 2 and speed > -1.0:
		var nf := Vector3(fwd.x, 0.0, fwd.z).normalized()
		apply_central_force(nf * engine_force * 0.55 * nitro)
	# ---- air resistance and a bit of downforce
	apply_central_force(-v * v.length() * drag)
	if grounded > 0:
		apply_central_force(-up * vs * vs * 0.55)
	# a stopped car stays stopped
	if vs < 0.4 and throttle < 0.05 and not reverse and grounded >= 3:
		linear_velocity = linear_velocity.lerp(Vector3.ZERO, 0.2)
		angular_velocity = angular_velocity.lerp(Vector3.ZERO, 0.2)
	_clock += dt
	_ram_cd = maxf(0.0, _ram_cd - dt)
	_vh.push_front(linear_velocity)
	_vh.resize(3)
	# bumps: sudden changes in velocity
	var dv := (linear_velocity - _last_v).length()
	if dv > 4.5:
		bumped.emit(dv)
	_last_v = linear_velocity
	wall_t = maxf(0.0, wall_t - dt)
	# just after a knock, keep the wheels down: lean back toward upright if it's tipping
	if wall_t > 0.0:
		var tilt2 := up.cross(Vector3.UP)
		if tilt2.length() > 0.12 and grounded > 0:
			apply_torque(tilt2 * 14000.0)

func _process(dt: float) -> void:
	if not is_physics_interpolated_and_enabled():
		_wheel_vis(dt)

func _wheel_vis(dt: float) -> void:
	if wheels.is_empty():
		return
	# in a drift the front wheels visibly point the way the car is going
	var vis_want := lerpf(steer, clampf(slip * 0.85, -steer_lock * 1.15, steer_lock * 1.15), clampf(drift * 1.2, 0.0, 1.0) * 0.7)
	vis_steer = lerpf(vis_steer, vis_want, 1.0 - exp(-dt * 12.0))
	for i in 4:
		var wd: Dictionary = wheels[i]
		var wn: MeshInstance3D = wheel_nodes[i]
		var home: Vector3 = wd["home"]
		var drop: float = clampf(float(wd["len"]) - REST, -0.2, TRAVEL)
		var b := Basis()
		if wd["front"]:
			b = Basis(Vector3.UP, -vis_steer)
		b = b * camber_basis(bool(wd["left"]), camber) * Basis(Vector3.RIGHT, -float(wd["spin"]))
		wn.transform = Transform3D(b, home - Vector3(0, drop, 0))


## A wheel leaning in at the top by camber (0..1 of CAMBER_MAX).
static func camber_basis(left: bool, cam: float) -> Basis:
	return Basis(Vector3(0, 0, 1), deg_to_rad(CAMBER_MAX) * cam * (-1.0 if left else 1.0))

## Underglow for a car: a pool of light on the ground and neon tubes under the floor (seen only from
## underneath). The pool is its child "pool" (meta); in the game it's laid on the ground by neon_tick.
static func make_neon(car_info: Dictionary, col: String, _mat: Material) -> Node3D:
	var root := Node3D.new()
	root.name = "Neon"
	var w: float = car_info["width"]
	var l: float = car_info["length"]
	var zc: float = (float(car_info["front"]) + float(car_info["back"])) * 0.5
	var pool := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w * 2.7, l * 1.75)
	pool.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/neon.gdshader")
	sm.set_shader_parameter("col", Color(col))
	pool.material_override = sm
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.position = Vector3(0, 0.03, zc)
	root.add_child(pool)
	# the tubes: tucked under the floor, inside the outline of the body
	var tubes := MeshInstance3D.new()
	var mb := MB.new()
	var fy: float = float(car_info["r_f"]) * 0.9 - 0.04
	for sd in [-1.0, 1.0]:
		mb.box(Vector3(sd * w * 0.32, fy, zc), Vector3(0.05, 0.03, l * 0.56), MB.rgb("ffffff"))
	for e in [-1.0, 1.0]:
		mb.box(Vector3(0, fy, zc + e * l * 0.3), Vector3(w * 0.6, 0.03, 0.05), MB.rgb("ffffff"))
	tubes.mesh = mb.commit()
	var tm := ShaderMaterial.new()
	tm.shader = load("res://shaders/neon_tube.gdshader")
	tm.set_shader_parameter("col", Color(col))
	tubes.material_override = tm
	tubes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tubes.name = "Tubes"
	root.add_child(tubes)
	root.set_meta("pool_mat", sm)
	root.set_meta("pool", pool)
	root.set_meta("zc", zc)
	return root

## Every frame (xf: where the car's drawn): the underglow lies on the ground under the car, and fades as
## the car lifts off or tips over.
func neon_tick(xf: Transform3D) -> void:
	if neon_node == null:
		return
	var pool: MeshInstance3D = neon_node.get_meta("pool")
	var mat: ShaderMaterial = neon_node.get_meta("pool_mat")
	var up := xf.basis.y
	var c := xf * Vector3(0, 0.3, float(neon_node.get_meta("zc")))
	var q := PhysicsRayQueryParameters3D.create(c + Vector3(0, 0.8, 0), c - Vector3(0, 3.0, 0), 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		pool.visible = false
		return
	var hp: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	var k := clampf(1.0 - (c.y - 0.3 - hp.y - 0.4) / 1.0, 0.0, 1.0) * clampf((up.dot(n) - 0.55) / 0.3, 0.0, 1.0)
	pool.visible = k > 0.02
	if not pool.visible:
		return
	var f := xf.basis.z
	f = (f - n * f.dot(n)).normalized()
	pool.global_transform = Transform3D(Basis(n.cross(f).normalized(), n, f), hp + n * 0.05)
	mat.set_shader_parameter("k", k)

## A dent where you hit (global point and the direction into the car), sized by how hard.
func dent(at: Vector3, into: Vector3, strength: float) -> void:
	if dent_data.is_empty():
		return
	var inv := body_node.global_transform.affine_inverse()
	var lp := inv * at
	var out := -(inv.basis * into).normalized()
	# the box we collide with sits a little inside the bodywork: reach out to it
	lp += out * 0.15
	var rad := clampf(0.55 + strength * 0.045, 0.55, 1.35)
	var depth := clampf(strength * 0.02, 0.04, 0.32)
	Dents.dent(dent_data, lp, out, rad, depth, 0.38)

func repair() -> void:
	if not dent_data.is_empty():
		Dents.repair(dent_data)
	damage = 0.0

func is_upside_down() -> bool:
	return global_transform.basis.y.y < 0.25
