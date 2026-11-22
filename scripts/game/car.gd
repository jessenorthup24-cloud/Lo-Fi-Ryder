extends Node3D
## The toy car. Arcade physics on the world's height field: steady cruise, slidey drifts, ramp air,
## thumb-steered air spins, and a springy toy body on top.

const M := preload("res://scripts/core/models.gd")
const NO_GROUND := -1000.0

const CRUISE := 9.0
const GRAVITY := 17.0
const TURN := 2.45
const AIR_TURN := 6.8
const RADIUS := 0.55

var world: Node
var game: Node
var def: Dictionary

# physics state
var vel := Vector3.ZERO
var yaw := 0.0
var grounded := true
var steer := 0.0          # -1 (left) .. 1 (right), from the thumb
var steer_smooth := 0.0
var coyote := 0.0
var on_ramp: Dictionary = {}
var air_time := 0.0
var spin_acc := 0.0
var spin_dir := 0.0
var drift := 0.0           # current drift angle (signed, radians)
var drifting := false
var drift_time := 0.0
var drift_side := 0
var drift_chain := 0
var recover := 0.0
var fuel := 1.0
var dead := false
var falling := false
var splashed := false
var active := false        # false on the title screen: the car idles
var slow := 1.0            # brief slow-down after knocking things over
var boost_t := 0.0         # seconds of boost-pad speed left
var surface := "ground"

# tuning from upgrades / weather
var grip_mul := 1.0
var wind_resist := 0.0
var weather_grip := 1.0
var wind := Vector3.ZERO

# visuals
var pivot: Node3D
var body: MeshInstance3D
var wheels: Array = []
var wheel_spin := 0.0
var susp := 0.0
var susp_v := 0.0
var squash := 0.0
var squash_v := 0.0
var roll := 0.0
var pitch := 0.0
var lights: SpotLight3D
var tumble := Vector3.ZERO
var tumble_v := Vector3.ZERO
var idle_t := 0.0
var mat: Material
var outline_mat: ShaderMaterial

func setup(w: Node, g: Node, material: Material) -> void:
	world = w
	game = g
	mat = material
	pivot = Node3D.new()
	add_child(pivot)
	body = MeshInstance3D.new()
	pivot.add_child(body)
	outline_mat = ShaderMaterial.new()
	outline_mat.shader = load("res://shaders/outline.gdshader")
	outline_mat.set_shader_parameter("width", 0.03)
	lights = SpotLight3D.new()
	lights.spot_range = 7.5
	lights.spot_angle = 38.0
	lights.light_energy = 0.0
	lights.light_color = Color("ffe2a8")
	lights.shadow_enabled = false
	lights.position = Vector3(0, 0.55, -0.7)
	lights.rotation_degrees = Vector3(-14, 0, 0)
	pivot.add_child(lights)

func set_car(d: Dictionary) -> void:
	def = d
	var c := M.car(d)
	body.mesh = c["body"]
	var m: ShaderMaterial = (mat as ShaderMaterial).duplicate()
	m.next_pass = outline_mat
	body.material_override = m
	body.position.y = c["ride"]
	for wn in wheels:
		wn.queue_free()
	wheels.clear()
	for i in 4:
		var hold := Node3D.new()
		hold.position = c["wheels"][i]
		pivot.add_child(hold)
		var wm := MeshInstance3D.new()
		wm.mesh = c["wheel_f"] if i < 2 else c["wheel_r"]
		wm.material_override = mat
		hold.add_child(wm)
		wheels.append(hold)

func body_material() -> ShaderMaterial:
	return body.material_override

## 0..1 strength of the current boost (eases out over its last second).
func boost_k() -> float:
	return smoothstep(0.0, 1.0, boost_t)

## Drove over a boost pad: a kick of speed that fades over ~1.8 s.
func boost() -> void:
	boost_t = 1.8
	slow = 1.0
	if grounded:
		var f := forward()
		var vf := vel.dot(f)
		vel += f * maxf(0.0, CRUISE * 1.45 - vf)

func place(p: Vector3, heading: float) -> void:
	boost_t = 0.0
	position = p
	yaw = heading
	vel = Vector3.ZERO
	grounded = true
	dead = false
	falling = false
	splashed = false
	air_time = 0.0
	spin_acc = 0.0
	drift = 0.0
	drifting = false
	drift_time = 0.0
	drift_chain = 0
	fuel = 1.0
	recover = 0.0
	slow = 1.0
	tumble = Vector3.ZERO
	tumble_v = Vector3.ZERO
	on_ramp = {}
	rotation = Vector3(0, yaw, 0)
	pivot.rotation = Vector3.ZERO
	pivot.position = Vector3.ZERO
	pivot.scale = Vector3.ONE

func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))

func right() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))

func speed() -> float:
	return Vector2(vel.x, vel.z).length()

func step(dt: float) -> void:
	if dead:
		_step_dead(dt)
		return
	steer_smooth = move_toward(steer_smooth, steer, dt * 7.0)
	var f := forward()
	var r := right()
	boost_t = maxf(0.0, boost_t - dt)
	var target := CRUISE * slow * (1.0 + 0.6 * boost_k()) if fuel > 0.0 else 0.0
	if not active:
		target = 0.0
	slow = move_toward(slow, 1.0, dt * 0.8)
	var turned := 0.0
	if grounded:
		var spd := speed()
		var vf := vel.dot(f)
		var vl := vel.dot(r)
		var accel := 2.4 if fuel > 0.0 else 0.9
		vf += (target - vf) * accel * dt
		# steering: faster turns while sliding; very little when nearly stopped
		var turn_scale := clampf(spd / 4.0, 0.0, 1.0)
		var drift_amt := smoothstep(0.45, 1.0, absf(steer_smooth)) * float(def.get("drift", 1.0))
		turned = steer_smooth * TURN * turn_scale * (1.0 + drift_amt * 0.35) * dt
		yaw -= turned
		# recover from a sideways landing: swing the nose round to where we're going
		if recover > 0.0:
			recover -= dt
			if spd > 1.0:
				var vdir := atan2(-vel.x, -vel.z)
				yaw = lerp_angle(yaw, vdir, 1.0 - exp(-dt * 7.0))
		var grip := lerpf(7.6, 1.7, clampf(drift_amt, 0.0, 1.0)) * grip_mul * float(def.get("grip", 1.0)) * weather_grip
		if surface == "ice":
			grip *= 0.28
		vl *= exp(-grip * dt)
		var nf := forward()
		var nr := right()
		vel = nf * vf + nr * vl + Vector3(0, vel.y, 0)
		vel += wind * (1.0 - wind_resist) * dt * 0.85
		drift = atan2(vel.dot(nr), maxf(0.1, vel.dot(nf)))
	else:
		vel.y -= GRAVITY * dt
		turned = steer_smooth * AIR_TURN * dt
		yaw -= turned
		spin_acc += absf(turned)
		if absf(turned) > 0.0001:
			spin_dir = signf(-turned)
		air_time += dt
		vel += wind * (1.0 - wind_resist) * dt * 1.2
	_move(dt)
	_drift_logic(dt)

func _move(dt: float) -> void:
	var old := position
	var np := position + vel * dt
	var ramp_before: Dictionary = world.ramp_at(position) if grounded else {}
	var g: float = world.ground_at(np)
	surface = world.surface_at(np)
	if grounded:
		var lip: bool = not ramp_before.is_empty() and world.ramp_at(np).is_empty()
		if lip:
			# only a launch if we left over the top edge, not off the side
			var rel: Vector3 = np - ramp_before["origin"]
			var along: float = rel.x * ramp_before["fwd"].x + rel.z * ramp_before["fwd"].z
			lip = along >= float(ramp_before["len"]) - 0.1
		if lip:
			# off the end of a kicker: launch
			var sp := speed()
			vel.y = float(ramp_before["launch"])
			vel.x *= 1.06
			vel.z *= 1.06
			grounded = false
			air_time = 0.0
			spin_acc = 0.0
			game.car_event("launch", {"pos": np, "speed": sp})
			np.y = maxf(np.y, position.y)
		elif g != NO_GROUND and g > np.y - 0.42:
			if g > np.y + 0.45:
				# a wall-high step up: bump instead of climbing
				np = Vector3(old.x, np.y, old.z)
				vel.x *= -0.2
				vel.z *= -0.2
			else:
				np.y = g
			coyote = 0.0
		else:
			# no ground under the middle: hang on for a moment if a wheel is still on something
			coyote += dt
			var held := false
			if coyote < 0.12:
				var f := forward() * 0.45
				var r := right() * 0.32
				for o in [f + r, f - r, -f + r, -f - r]:
					var gw: float = world.ground_at(np + o)
					if gw != NO_GROUND and gw > np.y - 0.3:
						held = true
						np.y = gw
						break
			if not held:
				grounded = false
				air_time = 0.0
				spin_acc = 0.0
				vel.y = maxf(vel.y, 0.0)
				if g == NO_GROUND or g < np.y - 1.0:
					game.car_event("off_edge", {"pos": np})
	else:
		if g != NO_GROUND and np.y <= g and position.y >= g - 0.45:
			np.y = g
			_land(-vel.y)
	position = np
	# death checks
	if not grounded and position.y < -2.4:
		_die("fall")
	elif world.water_at(position) and position.y < -0.12 and not grounded:
		_die("splash")

func _land(impact: float) -> void:
	grounded = true
	vel.y = 0.0
	var hv := Vector3(vel.x, 0, vel.z)
	var ang := 0.0
	if hv.length() > 0.5:
		ang = absf(angle_difference(yaw, atan2(-hv.x, -hv.z)))
	var spins := int(floor((spin_acc + 0.7) / TAU))
	var clean := ang < 0.5
	if ang > 1.0:
		recover = 0.45
		vel *= 0.65
	susp_v -= impact * 0.11 * float(def.get("bounce", 1.0))
	squash_v -= impact * 0.07
	game.car_event("land", {"air": air_time, "spins": spins, "spin_deg": rad_to_deg(spin_acc), "clean": clean, "impact": impact, "pos": position})
	air_time = 0.0
	spin_acc = 0.0

func _die(why: String) -> void:
	if dead:
		return
	dead = true
	falling = why == "fall"
	splashed = why == "splash"
	tumble_v = Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-3, 3))
	game.car_event("dead", {"why": why, "pos": position})

func _step_dead(dt: float) -> void:
	if splashed:
		vel = vel.lerp(Vector3(0, -0.6, 0), dt * 3.0)
		position += vel * dt
		tumble += Vector3(0.6, 0, 0.4) * dt
		pivot.rotation = tumble
		return
	vel.y -= GRAVITY * dt
	vel.x *= 1.0 - dt * 0.3
	vel.z *= 1.0 - dt * 0.3
	position += vel * dt
	tumble += tumble_v * dt
	pivot.rotation = tumble

func out_of_fuel_stopped() -> bool:
	return fuel <= 0.0 and grounded and speed() < 0.35

func _drift_logic(dt: float) -> void:
	var was := drifting
	drifting = grounded and speed() > 4.0 and absf(drift) > 0.26
	if drifting:
		var side := 1 if drift > 0.0 else -1
		if not was:
			if side != drift_side and drift_side != 0 and drift_time < 0.0:
				drift_chain += 1
			drift_time = 0.0
		drift_side = side
		drift_time += dt
	elif was:
		game.car_event("drift_end", {"time": drift_time, "chain": drift_chain})
		drift_time = -0.6   # a short window to chain the next drift
	else:
		if drift_time < 0.0:
			drift_time += dt
			if drift_time >= 0.0:
				drift_time = 0.0
				drift_chain = 0
				drift_side = 0

func render(dt: float, night: float) -> void:
	idle_t += dt
	if dead:
		rotation.y = yaw
		return
	rotation.y = yaw
	var c := M.car(def)
	var spd := speed()
	# springy suspension
	var bounce := float(def.get("bounce", 1.0))
	susp_v += (-susp * 120.0 - susp_v * 9.0 / bounce) * dt
	susp += susp_v * dt
	squash_v += (-squash * 160.0 - squash_v * 11.0) * dt
	squash += squash_v * dt
	if grounded and spd > 1.0 and randf() < dt * 3.0 * bounce:
		susp_v += randf_range(-0.6, 0.6)
	if not active:
		susp = sin(idle_t * 24.0) * 0.006
	var target_roll := -steer_smooth * 0.09 * clampf(spd / CRUISE, 0.0, 1.0) - drift * 0.12
	var target_pitch := 0.0
	if not grounded:
		target_roll = 0.0
		target_pitch = clampf(vel.y * 0.035, -0.25, 0.25)
	roll = lerpf(roll, target_roll, 1.0 - exp(-dt * 8.0))
	pitch = lerpf(pitch, target_pitch, 1.0 - exp(-dt * 6.0))
	pivot.position.y = susp
	pivot.rotation = Vector3(pitch, 0, roll)
	var sq := clampf(squash, -0.3, 0.3)
	pivot.scale = Vector3(1.0 - sq * 0.5, 1.0 + sq, 1.0 - sq * 0.5)
	# wheels
	wheel_spin -= spd * dt / float(c["r_r"])
	for i in wheels.size():
		var wh: Node3D = wheels[i]
		var st := (steer_smooth * 0.42 if grounded else 0.0) if i < 2 else 0.0
		wh.rotation = Vector3(0, -st, 0)
		var wmesh: MeshInstance3D = wh.get_child(0)
		var rr: float = c["r_f"] if i < 2 else c["r_r"]
		wmesh.rotation.x = wheel_spin * float(c["r_r"]) / rr
	lights.light_energy = smoothstep(0.35, 0.8, night) * 1.3
