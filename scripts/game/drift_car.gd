extends RigidBody3D
## The player's car: a rigid body riding on four raycast springs, with a simple tyre model (grip builds
## with slip angle, then falls off a little once it slides, inside a friction circle). Rear-wheel drive
## with an automatic gearbox, brakes, and a handbrake that locks the rear and lets it swing out.
## Touch controls are on/off buttons, so steering eases in, the front wheels follow the slide when you
## let go (counter-steer), and a light hand keeps a drift from becoming a spin.

const M := preload("res://scripts/core/models.gd")

signal shifted(gear: int)
signal bumped(strength: float)

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
const GEARS := [0.0, 8.5, 15.0, 22.0, 29.5, 37.0, 46.0, 60.0]
const TRAVEL := 0.28
const REST := 0.32           # ray starts this far above the wheel centre

func setup(def: Dictionary, mat: Material, isl: Node) -> void:
	island = isl
	info = M.car(def)
	for c in get_children():
		c.queue_free()
	wheels.clear()
	wheel_nodes.clear()
	body_node = MeshInstance3D.new()
	body_node.mesh = info["body"]
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
	pm.friction = 0.35
	pm.bounce = 0.05
	physics_material_override = pm
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = 4
	collision_mask = 1 | 2
	tune(def, {})

## Car personality and garage upgrades. up: {engine, turbo, tyres, steering} levels 0..5
func tune(def: Dictionary, up: Dictionary) -> void:
	var pw: float = def.get("power", 1.0) * (1.0 + 0.08 * int(up.get("engine", 0)))
	engine_force = 7600.0 * pw
	power_speed = 13.0 * (1.0 + 0.05 * int(up.get("turbo", 0)))
	top_speed = 46.0 * def.get("speed", 1.0) * (1.0 + 0.035 * int(up.get("turbo", 0)))
	drag = engine_force * power_speed / pow(top_speed, 3.0)
	mu = 1.12 * def.get("grip", 1.0) * (1.0 + 0.035 * int(up.get("tyres", 0)))
	rear_grip = 0.97 - (def.get("drift", 1.0) - 1.0) * 0.25
	steer_lock = deg_to_rad(34.0 + 2.5 * int(up.get("steering", 0)))

func place(xf: Transform3D) -> void:
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_last_v = Vector3.ZERO
	for wd in wheels:
		wd["len"] = REST
		wd["last"] = REST
	gear = 1

func _physics_process(dt: float) -> void:
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
	drift = clampf((absf(slip) - deg_to_rad(9.0)) / deg_to_rad(25.0), 0.0, 1.0) * clampf((vs - 4.0) / 6.0, 0.0, 1.0)
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
	var rate := 4.2 if absf(want) > absf(steer) else 6.5
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
	var reverse := brake > 0.1 and speed < 0.8 and throttle < 0.1
	var drive := 0.0
	if throttle > 0.0:
		drive = throttle * minf(engine_force, engine_force * power_speed / maxf(gv, 1.0))
		if _gear_cd > 0.2:
			drive *= 0.35
	elif reverse:
		drive = -brake * engine_force * 0.45 * clampf(1.0 - (-speed) / 9.0, 0.0, 1.0)
	var braking := 0.0 if reverse else brake
	# ---- each wheel
	var space := get_world_3d().direct_space_state
	grounded = 0
	wheelspin = 0.0
	var rear_surf := -1
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
		wd["contact"] = true
		var hp: Vector3 = hit["position"]
		var n: Vector3 = hit["normal"]
		var length := maxf((origin - hp).dot(up) - r, 0.0)
		wd["len"] = length
		var comp := REST + 0.1 - length
		var comp_v: float = (float(wd["last"]) - length) / dt
		var fz := maxf(0.0, spring_k * comp + damper_c * comp_v)
		if length < 0.02:
			fz += (0.02 - length) * spring_k * 6.0   # bump stop
		fz = minf(fz, mass * 9.8 * 2.5)
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
		var cap := mu * g * minf(fz, mass * 9.8 * 0.45) * (1.0 if wd["front"] else rear_grip)
		# handbrake: rear wheels lock and let go sideways
		if not wd["front"] and handbrake > 0.0:
			cap *= lerpf(1.0, 0.45, handbrake)
		# once it's sideways, keeping your foot in keeps the tail light (lift off and it grips again);
		# and just after a handbrake tap the rear stays loose for a moment
		if not wd["front"]:
			cap *= 1.0 - 0.3 * _slide * throttle
			cap *= lerpf(1.0, 0.6, clampf(_hb_t / 0.45, 0.0, 1.0))
		# lateral force from the slip angle (peaks, then eases off as it slides)
		var alpha := atan2(vx, absf(vz) + 1.2)
		var aa := absf(alpha)
		var peak := deg_to_rad(7.5)
		var f := aa / peak if aa < peak else lerpf(1.0, 0.78, clampf((aa - peak) / deg_to_rad(35.0), 0.0, 1.0))
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
	if grounded >= 2 and vs > 5.0:
		# a handbrake flick with some steering swings the tail out
		if _hb_t > 0.0 and absf(steer_in) > 0.2 and aslip < deg_to_rad(28.0):
			apply_torque(up * -steer_in * 3600.0 * clampf(_hb_t / 0.45, 0.0, 1.0) * clampf(vs / 12.0, 0.3, 1.0))
		var holding := (drift > 0.15 or aslip > deg_to_rad(14.0)) and throttle > 0.15 and speed > 3.0
		if holding:
			var dir := -signf(slip)                 # +1: sliding round to the right
			var press := steer_in * dir             # +1 into the drift, -1 out of it
			var target := deg_to_rad(28.0) + press * deg_to_rad(16.0)
			if press < -0.5:
				target = deg_to_rad(4.0)
			var err := target - aslip
			apply_torque(-up * dir * (err * 16000.0 - slip_rate * 5200.0) * assist)
		elif aslip > deg_to_rad(50.0):
			apply_torque(-up * signf(slip) * (aslip - deg_to_rad(50.0)) * 30000.0 * assist)
		# a drift with your foot down doesn't bleed all its speed
		if drift > 0.1 and throttle > 0.2 and speed > 0.0:
			apply_central_force(vflat.normalized() * mass * 3.4 * drift * throttle * assist)
		# calm the yaw a touch when nothing is pressed
		var yr := angular_velocity.dot(up)
		if absf(steer_in) < 0.1 and drift < 0.2:
			apply_torque(-up * yr * 900.0 * assist)
	# ---- air: a little spin control, and level out gently
	if grounded == 0:
		air_t += dt
		apply_torque(up * -steer_in * 2200.0)
		var tilt := up.cross(Vector3.UP)
		apply_torque(tilt * 3000.0)
	else:
		air_t = 0.0
	# ---- air resistance and a bit of downforce
	apply_central_force(-v * v.length() * drag)
	if grounded > 0:
		apply_central_force(-up * vs * vs * 0.55)
	# a stopped car stays stopped
	if vs < 0.4 and throttle < 0.05 and not reverse and grounded >= 3:
		linear_velocity = linear_velocity.lerp(Vector3.ZERO, 0.2)
		angular_velocity = angular_velocity.lerp(Vector3.ZERO, 0.2)
	# bumps: sudden changes in velocity
	var dv := (linear_velocity - _last_v).length()
	if dv > 4.5:
		bumped.emit(dv)
	_last_v = linear_velocity

func _process(_dt: float) -> void:
	if wheels.is_empty():
		return
	for i in 4:
		var wd: Dictionary = wheels[i]
		var wn: MeshInstance3D = wheel_nodes[i]
		var home: Vector3 = wd["home"]
		var drop: float = clampf(float(wd["len"]) - REST, -0.2, TRAVEL)
		var b := Basis()
		if wd["front"]:
			b = Basis(Vector3.UP, -steer)
		b = b * Basis(Vector3.RIGHT, -float(wd["spin"]))
		wn.transform = Transform3D(b, home - Vector3(0, drop, 0))

func is_upside_down() -> bool:
	return global_transform.basis.y.y < 0.25
