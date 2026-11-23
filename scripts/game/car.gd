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
var wall_cd := 0.0         # cooldown between wall-bump sounds
var stuck_t := 0.0         # how long we've been crawling while trying to drive
var wall_t := 0.0          # >0 just after touching a wall
var wall_dir := Vector3.ZERO  # the glancing direction off that wall
var surface := "ground"
var pace := 1.0            # cruise multiplier: the run speeds up the farther you get
var air_bump := false      # this air time came from cresting a bump (steering stays gentle)
var yaw_rate := 0.0        # rad/s: the car has rotational weight, steering eases it in and out
var acc_lat := 0.0         # sideways and fore-aft accel the tyres are making (for body roll and squat)
var acc_lon := 0.0
const GRIP_ACC := 24.0     # how hard the tyres can push sideways (m/s^2) before they slide
var grinding := false      # locked onto a grind rail
var rail: Dictionary = {}
var rail_s := 0.0
var grind_t := 0.0
var grind_speed := 0.0
var wheel_drop := [0.0, 0.0, 0.0, 0.0]   # visual suspension travel per wheel
var wheel_h := [0.0, 0.0, 0.0, 0.0]

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
	m.set_shader_parameter("decay", 0.0)
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
		wm.mesh = M.wheel_mesh(c, i)
		wm.material_override = mat
		hold.add_child(wm)
		wheels.append(hold)

func body_material() -> ShaderMaterial:
	return body.material_override

## 0..1 strength of the current boost (eases out over its last second).
func boost_k() -> float:
	return smoothstep(0.0, 1.0, boost_t)

## Let go of a long drift: a little kick of speed (the longer the drift, the bigger).
func drift_boost(t: float) -> void:
	if not grounded or dead:
		return
	boost_t = maxf(boost_t, clampf(0.35 + t * 0.25, 0.45, 1.0))
	var f := forward()
	vel += f * clampf(1.2 + t * 0.8, 1.2, 3.2)

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
	yaw_rate = 0.0
	acc_lat = 0.0
	acc_lon = 0.0
	grinding = false
	rail = {}
	wall_cd = 0.0
	stuck_t = 0.0
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
	if grinding:
		_grind(dt)
		return
	if not grounded and active and vel.y < 1.6:
		var hit: Dictionary = world.rail_catch(position, 1.9)
		if not hit.is_empty():
			grinding = true
			rail = hit["rail"]
			rail_s = hit["s"]
			grind_t = 0.0
			grind_speed = maxf(speed(), CRUISE * pace * 0.9)
			spin_acc = 0.0
			game.car_event("grind_start", {"pos": position})
			_grind(dt)
			return
	var f := forward()
	var r := right()
	boost_t = maxf(0.0, boost_t - dt)
	var target := CRUISE * pace * slow * (1.0 + 0.6 * boost_k()) if fuel > 0.0 else 0.0
	if surface == "slick":
		target *= 0.72   # rock crawling: easy does it
	if not active:
		target = 0.0
	slow = move_toward(slow, 1.0, dt * 0.8)
	var turned := 0.0
	if grounded:
		var spd := speed()
		var accel := 2.4 if fuel > 0.0 else 0.9
		var drift_def := float(def.get("drift", 1.0))
		# how hard the arrow is held: a tap carves, holding it lets the rear step out
		var hold := smoothstep(0.25, 0.9, absf(steer_smooth))
		# steering asks for a rate of turn; the car has some rotational weight, so it eases in and out,
		# and a big slide pulls the nose back toward where you're going (catchable, no endless spins)
		var turn_scale := clampf(spd / 3.5, 0.4 if active else 0.0, 1.0)
		var want_rate := -steer_smooth * TURN * (0.85 + 0.15 * pace) * turn_scale * (1.0 + hold * 0.5 * drift_def)
		want_rate -= clampf(drift, -1.2, 1.2) * 2.2 * clampf(spd / 6.0, 0.0, 1.0)
		yaw_rate = lerpf(yaw_rate, want_rate, 1.0 - exp(-dt * 9.0))
		turned = -yaw_rate * dt
		# never stay pinned: crawling while trying to drive swings the nose back toward the road,
		# overriding the thumb (the velocity turns with the car, so it can pull away)
		if active and fuel > 0.0 and spd < 1.6:
			stuck_t += dt
		else:
			stuck_t = maxf(0.0, stuck_t - dt * 2.0)
		wall_t -= dt
		if stuck_t > 0.45:
			var to := wall_dir if wall_t > 0.0 else _to_road()
			turned = angle_difference(atan2(-to.x, -to.z), yaw) * (1.0 - exp(-dt * 6.0))
			yaw_rate = -turned / dt
			vel = vel.rotated(Vector3.UP, -turned)
		yaw -= turned
		var icy := surface == "ice"
		var dirt := surface == "dirt"
		var vf := vel.dot(forward())
		var vl := vel.dot(right())
		var vf0 := vf
		vf += (target - vf) * accel * dt
		# climbing slows you, rolling down a slickrock face speeds you up
		if world.uneven_at(position):
			var fw := forward()
			var gf: float = world.ground_at(position + fw * 0.5)
			var gb: float = world.ground_at(position - fw * 0.5)
			if gf > NO_GROUND + 1.0 and gb > NO_GROUND + 1.0:
				var sl := gf - gb
				vf -= GRAVITY * 0.75 * sl / sqrt(1.0 + sl * sl) * dt
		if stuck_t > 1.5:
			# still wedged: a little toy hop back toward the road
			stuck_t = 0.0
			var to := _to_road()
			yaw = atan2(-to.x, -to.z)
			yaw_rate = 0.0
			vf = 4.5
			vl = 0.0
			vel.y = 6.0
			grounded = false
			air_bump = true
			air_time = 0.0
			spin_acc = 0.0
			game.car_event("hop", {"pos": position})
		# recover from a sideways landing: swing the nose round to where we're going
		if recover > 0.0:
			recover -= dt
			if spd > 1.0:
				var vdir := atan2(-vel.x, -vel.z)
				yaw = lerp_angle(yaw, vdir, 1.0 - exp(-dt * 5.0))
		# tyres: they can only push sideways so hard (grip, surface, weather); hold the arrow and the
		# rear lets go a little, so the car slides, and a slide carries its momentum forward
		var mu := GRIP_ACC * grip_mul * float(def.get("grip", 1.0)) * weather_grip
		if icy:
			mu *= 0.3
		elif dirt:
			mu *= 0.7
		elif surface == "slick":
			mu *= 0.85
		mu *= 1.0 - 0.5 * clampf(hold * drift_def, 0.0, 1.0)
		var dv := clampf(-vl, -mu * dt, mu * dt)
		vl += dv
		if fuel > 0.0 and active:
			vf += absf(dv) * 0.35 * hold
		acc_lat = lerpf(acc_lat, dv / dt, 1.0 - exp(-dt * 10.0))
		acc_lon = lerpf(acc_lon, (vf - vf0) / dt, 1.0 - exp(-dt * 8.0))
		var nf := forward()
		var nr := right()
		vel = nf * vf + nr * vl + Vector3(0, vel.y, 0)
		vel += wind * (1.0 - wind_resist) * dt * (0.3 if surface == "deck" else 0.85)
		drift = atan2(vel.dot(nr), maxf(0.1, vel.dot(nf)))
	else:
		vel.y -= GRAVITY * dt
		turned = steer_smooth * (TURN * 1.1 if air_bump else AIR_TURN) * dt
		yaw_rate = -turned / dt
		acc_lat = lerpf(acc_lat, 0.0, 1.0 - exp(-dt * 6.0))
		acc_lon = lerpf(acc_lon, 0.0, 1.0 - exp(-dt * 6.0))
		yaw -= turned
		spin_acc += absf(turned)
		if absf(turned) > 0.0001:
			spin_dir = signf(-turned)
		air_time += dt
		vel += wind * (1.0 - wind_resist) * dt * 1.2
	_move(dt)
	_drift_logic(dt)

## Something taller than a curb at p (rocks, ledges, a kicker's side): we slide along it, never climb it.
func _wall(p: Vector3, mv: Vector3, y: float) -> bool:
	var flat := Vector3(mv.x, 0, mv.z)
	if flat.length_squared() > 0.000001:
		p += flat.normalized() * 0.3
	var g: float = world.ground_at(p)
	return g != NO_GROUND and g > y + 0.45

## Bumped a wall with normal n: lose the speed going into it and turn to run along it, away from it.
func _hit_wall(n: Vector3, dt: float, notify := true) -> void:
	var into := -Vector3(vel.x, 0, vel.z).dot(n)
	if into > 0.0:
		vel += n * into * 1.12
	if grounded:
		var t := Vector3(-n.z, 0, n.x)
		var road := _to_road()
		if t.dot(forward()) + t.dot(road) * 0.6 < 0.0:
			t = -t
		var d := (t + n * 0.45).normalized()
		wall_dir = d
		wall_t = 0.2
		if stuck_t <= 0.45:
			yaw = lerp_angle(yaw, atan2(-d.x, -d.z), 1.0 - exp(-dt * 9.0))
		drift *= 0.5
	if notify and wall_cd <= 0.0 and into > 1.5:
		wall_cd = 0.4
		game.car_event("wall", {"pos": position - n * 0.4, "impact": into})

## Flat unit vector from the car toward the road a little way ahead.
func _to_road() -> Vector3:
	var to: Vector3 = world.pos_at(world.v_of(position) + 5.0, 0.0) - position
	to.y = 0.0
	return to.normalized() if to.length() > 0.3 else forward()

## Pressed against a solid prop (normal n, overlap depth): pop out and glance off it.
## Returns how hard we were driving into it.
func push_solid(n: Vector3, depth: float, dt: float) -> float:
	position += n * depth
	var into := -Vector3(vel.x, 0, vel.z).dot(n)
	_hit_wall(n, dt, false)
	return into

## Locked on a rail: slide along it (no steering needed), sparks fly, and pop off the far end.
func _grind(dt: float) -> void:
	if rail.get("falling", false):
		grinding = false
		grounded = false
		return
	grind_t += dt
	grind_speed = move_toward(grind_speed, CRUISE * pace * 1.12, dt * 2.0)
	rail_s += grind_speed * dt
	var at: Dictionary = world.rail_at(rail, rail_s)
	var dir: Vector3 = at["dir"]
	var target: Vector3 = at["p"] + Vector3(0, 0.1, 0)
	position = position.lerp(target, 1.0 - exp(-dt * 30.0)) if grind_t < 0.2 else target
	yaw = lerp_angle(yaw, atan2(-dir.x, -dir.z), 1.0 - exp(-dt * 12.0))
	vel = dir * grind_speed
	yaw_rate = 0.0
	drift = 0.0
	air_time = 0.0
	if rail_s >= float(rail["len"]) - 0.05:
		grinding = false
		grounded = false
		air_bump = false
		vel = dir * grind_speed + Vector3(0, 1.2, 0)
		spin_acc = 0.0
		game.car_event("grind_end", {"pos": position, "len": float(rail["len"]), "time": grind_t})
		rail = {}

func _move(dt: float) -> void:
	wall_cd -= dt
	var old := position
	var mv := vel * dt
	var np := old + mv
	# walls: slide along whichever axis is free (tiles are axis-aligned squares)
	var gold: float = world.ground_at(old)
	var inside := gold != NO_GROUND and gold > old.y + 0.45
	if not inside and _wall(np, mv, old.y):
		var mx := Vector3(mv.x, mv.y, 0)
		var mz := Vector3(0, mv.y, mv.z)
		var ok_x := absf(mv.x) > 0.0001 and not _wall(old + mx, mx, old.y)
		var ok_z := absf(mv.z) > 0.0001 and not _wall(old + mz, mz, old.y)
		if ok_x and (not ok_z or absf(mv.x) >= absf(mv.z)):
			np = old + mx
			_hit_wall(Vector3(0, 0, -signf(mv.z)), dt)
		elif ok_z:
			np = old + mz
			_hit_wall(Vector3(-signf(mv.x), 0, 0), dt)
		else:
			np = Vector3(old.x, old.y + mv.y, old.z)
			var back := -Vector3(mv.x, 0, mv.z)
			_hit_wall(back.normalized() if back.length_squared() > 0.000001 else -forward(), dt)
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
			air_bump = false
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
				# carry vertical speed over rises and dips and get light off the crests: when the ground
				# drops away faster than you'd fall, you're airborne (crests, ledges, the end of a slope)
				var bumpy: bool = world.uneven_at(np) or world.uneven_at(old)
				var ballistic := old.y + vel.y * dt - GRAVITY * 1.15 * dt * dt   # (springs keep it planted a touch)
				var drops := g < old.y - 0.07
				if speed() > 3.0 and g < ballistic - 0.006 and (vel.y > 0.6 or drops):
					grounded = false
					air_bump = true
					air_time = 0.0
					spin_acc = 0.0
					vel.y -= GRAVITY * dt
					np.y = old.y + vel.y * dt
				else:
					var vy := (g - old.y) / dt
					susp_v -= maxf(0.0, vy - vel.y) * (0.045 if bumpy else 0.025) * float(def.get("bounce", 1.0))
					vel.y = clampf(vy, -7.0, 9.0)
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
				air_bump = false
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
	if ang > 1.2 and not air_bump:
		recover = 0.35
		vel *= 0.82
	susp_v -= impact * 0.11 * float(def.get("bounce", 1.0))
	squash_v -= impact * 0.07
	game.car_event("land", {"air": air_time, "spins": spins, "spin_deg": rad_to_deg(spin_acc), "clean": clean, "impact": impact, "pos": position, "bump": air_bump})
	air_bump = false
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
	var target_roll := clampf(acc_lat * 0.0065, -0.15, 0.15) - drift * 0.06
	var target_pitch := clampf(acc_lon * 0.012, -0.08, 0.08)
	# terrain under each wheel: the body pitches and rolls with it, each wheel reaches for the ground
	var wb := Basis(Vector3.UP, yaw)
	var gh := [0.0, 0.0, 0.0, 0.0]
	var on_bumps: bool = grounded and world.uneven_at(position)
	if on_bumps:
		for i in 4:
			var g: float = world.ground_at(position + wb * Vector3(c["wheels"][i].x, 0, c["wheels"][i].z))
			gh[i] = (g - position.y) if g > NO_GROUND + 1.0 else -0.3
		var base_len := absf(float(c["wheels"][0].z) - float(c["wheels"][2].z))
		var track := absf(float(c["wheels"][0].x) - float(c["wheels"][1].x))
		var front: float = (gh[0] + gh[1]) * 0.5
		var rear: float = (gh[2] + gh[3]) * 0.5
		var lft: float = (gh[0] + gh[2]) * 0.5 if float(c["wheels"][0].x) < 0.0 else (gh[1] + gh[3]) * 0.5
		var rgt: float = (gh[1] + gh[3]) * 0.5 if float(c["wheels"][0].x) < 0.0 else (gh[0] + gh[2]) * 0.5
		wheel_h = gh
		target_pitch = clampf(atan2(front - rear, maxf(base_len, 0.3)), -0.6, 0.6)
		target_roll = clampf(atan2(rgt - lft, maxf(track, 0.3)), -0.5, 0.5) - drift * 0.06
	elif not grounded:
		target_roll = 0.0
		target_pitch = clampf(vel.y * 0.035, -0.25, 0.25)
	roll = lerpf(roll, target_roll, 1.0 - exp(-dt * (14.0 if on_bumps else 8.0)))
	pitch = lerpf(pitch, target_pitch, 1.0 - exp(-dt * (14.0 if on_bumps else 6.0)))
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
		# suspension travel: how far this wheel sits from the tilted body's plane
		var travel := 0.0
		if on_bumps:
			var wl: Vector3 = c["wheels"][i]
			var plane := -wl.z * sin(pitch) + wl.x * sin(roll)
			travel = clampf(float(wheel_h[i]) - plane, -0.16, 0.16)
		wheel_drop[i] = lerpf(float(wheel_drop[i]), travel, 1.0 - exp(-dt * 16.0))
		wh.position = c["wheels"][i] + Vector3(0, float(wheel_drop[i]) - susp, 0)
		var wmesh: MeshInstance3D = wh.get_child(0)
		var rr: float = c["r_f"] if i < 2 else c["r_r"]
		wmesh.rotation.x = wheel_spin * float(c["r_r"]) / rr
	lights.light_energy = smoothstep(0.35, 0.8, night) * 1.3
