extends Node3D
## The police cruiser for chases. It waits parked beside the road, then pulls out and follows the
## path you drove (your breadcrumb trail), so it takes the same ramps and bridges you did. It is not a
## great driver: it weaves, runs wide on bends, lurches now and then and gets nervous on bridges. If its
## wheels leave the ground where you were still on the ground, it goes over the edge.

const M := preload("res://scripts/core/models.gd")
const CARS := preload("res://scripts/game/cars.gd")

const BASE_SPEED := 10.0     # you cruise at 9: it gains about 1 m/s unless you boost
var pace := 1.0              # matches the car's speed-up over the run
const CATCH_GAP := 1.4
const LOST_GAP := 42.0

var body: Node3D
var wheels: Array = []
var beacon_r: MeshInstance3D
var beacon_b: MeshInstance3D
var light_r: OmniLight3D
var light_b: OmniLight3D
var mat_on_r: StandardMaterial3D
var mat_on_b: StandardMaterial3D
var mat_off: StandardMaterial3D

var state := "hidden"    # hidden, parked, chasing, stopping
var trail: Array = []    # [{p: Vector3, yaw: float, s: float}]
var trail_s := 0.0       # distance the player has driven (along the trail)
var s := 0.0             # distance the cruiser has driven along the trail
var speed := 0.0
var blend := 0.0
var parked_pos := Vector3.ZERO
var parked_yaw := 0.0
var t := 0.0
var wheel_spin := 0.0
var stop_vel := Vector3.ZERO
var world: Node                 # for ground checks
var paint: ShaderMaterial       # its own material: no weathering on the cruiser
var lat := 0.0                  # sideways offset from your line (m, + = to its right)
var lat_v := 0.0                # lurch speed
var lat_prev := 0.0
var swerve_t := 3.0
var phase_a := 0.0
var phase_b := 0.0
var nerves := 0.0               # 0..1, rises on narrow decks
var fall_vel := Vector3.ZERO
var tumble := Vector3.ZERO
var tumble_v := Vector3.ZERO
var fell := false               # went over an edge this chase

func setup(toon: ShaderMaterial) -> void:
	var def := CARS.by_id("police")
	var c := M.car(def)
	body = Node3D.new()
	add_child(body)
	var bm := MeshInstance3D.new()
	bm.mesh = c["body"]
	paint = toon.duplicate()
	paint.set_shader_parameter("decay", 0.0)
	bm.material_override = paint
	bm.position.y = c["ride"]
	body.add_child(bm)
	for i in 4:
		var w := MeshInstance3D.new()
		w.mesh = M.wheel_mesh(c, i)
		w.material_override = toon
		w.position = c["wheels"][i]
		body.add_child(w)
		wheels.append(w)
	mat_on_r = _mat(Color(1.0, 0.25, 0.25))
	mat_on_b = _mat(Color(0.3, 0.5, 1.0))
	mat_off = _mat(Color(0.35, 0.33, 0.38))
	var bx := BoxMesh.new()
	bx.size = Vector3(0.26, 0.12, 0.18)
	beacon_r = MeshInstance3D.new()
	beacon_r.mesh = bx
	var roof: float = c.get("top", 0.9) + 0.03
	beacon_r.position = Vector3(-0.14, roof + c["ride"], 0.06)
	body.add_child(beacon_r)
	beacon_b = MeshInstance3D.new()
	beacon_b.mesh = bx
	beacon_b.position = Vector3(0.14, roof + c["ride"], 0.06)
	body.add_child(beacon_b)
	light_r = _light(Color(1.0, 0.2, 0.2), Vector3(-0.3, 1.2, 0))
	light_b = _light(Color(0.25, 0.45, 1.0), Vector3(0.3, 1.2, 0))
	visible = false

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return m

func _light(col: Color, p: Vector3) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.omni_range = 4.0
	l.light_energy = 0.0
	l.shadow_enabled = false
	l.position = p
	body.add_child(l)
	return l

func reset() -> void:
	state = "hidden"
	visible = false
	trail.clear()
	trail_s = 0.0
	s = 0.0
	speed = 0.0
	fell = false
	body.rotation = Vector3.ZERO

## Remember where the player has been (call every frame during a run).
func record(p: Vector3, yaw: float, grounded := true) -> void:
	if trail.is_empty():
		trail.append({"p": p, "yaw": yaw, "s": 0.0, "gr": grounded})
		return
	var last: Dictionary = trail[trail.size() - 1]
	var d := Vector2(p.x - last["p"].x, p.z - last["p"].z).length()
	if d < 0.3:
		return
	trail_s += d
	trail.append({"p": p, "yaw": yaw, "s": trail_s, "gr": grounded})
	# keep the last ~120 m (the cruiser never falls further behind than that)
	while trail.size() > 2 and trail_s - float(trail[1]["s"]) > 120.0:
		trail.pop_front()

func park(p: Vector3, yaw: float) -> void:
	parked_pos = p
	parked_yaw = yaw
	position = p
	rotation = Vector3(0, yaw, 0)
	state = "parked"
	visible = true
	blend = 0.0
	fell = false
	body.rotation = Vector3.ZERO
	body.position = Vector3.ZERO

func start_chase() -> void:
	state = "chasing"
	s = maxf(trail_s - 12.0, float(trail[0]["s"]) if not trail.is_empty() else 0.0)
	speed = 4.0
	blend = 0.0
	lat = 0.0
	lat_v = 0.0
	lat_prev = 0.0
	swerve_t = randf_range(2.0, 4.0)
	phase_a = randf() * TAU
	phase_b = randf() * TAU
	nerves = 0.0

func gap() -> float:
	return trail_s - s

func stop() -> void:
	if state == "chasing":
		state = "stopping"
		var a := _at(s)
		var b := _at(s + 0.6)
		stop_vel = (b["p"] - a["p"]).normalized() * speed

func _at(dist: float) -> Dictionary:
	if trail.is_empty():
		return {"p": position, "yaw": rotation.y}
	if dist <= float(trail[0]["s"]):
		return trail[0]
	var lo := 0
	var hi := trail.size() - 1
	if dist >= float(trail[hi]["s"]):
		return trail[hi]
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if float(trail[mid]["s"]) < dist:
			lo = mid
		else:
			hi = mid
	var a: Dictionary = trail[lo]
	var b: Dictionary = trail[hi]
	var k := (dist - float(a["s"])) / maxf(0.001, float(b["s"]) - float(a["s"]))
	return {"p": (a["p"] as Vector3).lerp(b["p"], k), "yaw": lerp_angle(a["yaw"], b["yaw"], k), "gr": bool(a.get("gr", true)) and bool(b.get("gr", true))}

## Off the road: keep the momentum, tumble away into the drop.
func _go_over(fwd: Vector3, side: Vector3) -> void:
	state = "falling"
	fell = true
	fall_vel = fwd * speed * 0.9 + side * (lat - lat_prev) * 30.0 + Vector3(0, 1.0, 0)
	tumble = Vector3.ZERO
	tumble_v = Vector3(randf_range(-2.5, 2.5), randf_range(-1.5, 1.5), signf(lat + 0.001) * -randf_range(2.0, 3.5))

func tick(dt: float, night: float) -> void:
	t += dt
	if state == "hidden":
		return
	var flashing := state == "chasing" or (state == "stopping" and t < 2.0) or state == "parked" or state == "falling"
	var phase := int(t * 6.0) % 2 == 0
	beacon_r.material_override = mat_on_r if flashing and phase else mat_off
	beacon_b.material_override = mat_on_b if flashing and not phase else mat_off
	var le := (1.2 + night * 1.5) if state != "parked" else 0.4
	light_r.light_energy = le if flashing and phase else 0.0
	light_b.light_energy = le if flashing and not phase else 0.0
	match state:
		"parked":
			body.position.y = sin(t * 20.0) * 0.004
		"chasing":
			var g := gap()
			var at := _at(s)
			var ahead := _at(s + 3.5)
			var bend := angle_difference(float(at["yaw"]), float(ahead["yaw"]))   # + = bending left
			# it brakes a bit for bends (badly), and floors it on the straights
			var want := (BASE_SPEED * pace + (1.2 if g > 24.0 else 0.0)) * (1.0 - minf(absf(bend) * 0.5, 0.28))
			speed = move_toward(speed, want, dt * 5.0)
			s = minf(s + speed * dt, trail_s)
			at = _at(s)
			# sloppy line: a lazy weave, running wide on bends, a lurch every few seconds, and the
			# jitters on narrow decks
			var on_deck: bool = world != null and not (world.deck_at(at["p"]) as Dictionary).is_empty()
			nerves = move_toward(nerves, 1.0 if on_deck else 0.0, dt * (1.5 if on_deck else 0.6))
			var weave := (sin(t * 1.9 + phase_a) * 0.3 + sin(t * 0.73 + phase_b) * 0.24) * (1.0 + nerves * 1.1)
			var wide := clampf(bend * speed * 0.07, -1.2, 1.2)
			swerve_t -= dt
			if swerve_t <= 0.0:
				swerve_t = randf_range(2.0, 4.5) * (0.6 if on_deck else 1.0)
				lat_v += randf_range(0.9, 1.9) * (1.0 if randf() < 0.5 else -1.0) * (1.0 + nerves * 0.6)
			lat_v *= exp(-dt * 2.2)
			lat_prev = lat
			lat += ((weave + wide) - lat) * (1.0 - exp(-dt * 2.0)) + lat_v * dt
			blend = minf(1.0, blend + dt / 1.2)
			var k := smoothstep(0.0, 1.0, blend)
			var yaw: float = at["yaw"]
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			var side := Vector3(cos(yaw), 0, -sin(yaw))
			var off := side * lat * k
			position = parked_pos.lerp(at["p"], k) + off
			var slip := atan2((lat - lat_prev) / maxf(dt, 0.001), maxf(speed, 1.0))
			rotation.y = lerp_angle(parked_yaw, yaw - slip * 1.4, k)
			wheel_spin -= speed * dt / 0.19
			body.position.y = sin(t * 18.0) * 0.01
			body.rotation.z = lerpf(body.rotation.z, -clampf(lat_v * 0.05, -0.12, 0.12), 1.0 - exp(-dt * 6.0))
			# where you had wheels on the ground, it needs ground too
			if k > 0.98 and bool(at["gr"]) and world != null:
				# (only when all of it is over nothing, and your own line still had ground there)
				var none := func(q: Vector3) -> bool: return float(world.ground_at(q)) < -999.0
				if none.call(position) and none.call(position + fwd * 0.45) and none.call(position - fwd * 0.45) \
						and not none.call(at["p"]):
					_go_over(fwd, side)
		"falling":
			fall_vel.y -= 17.0 * dt
			fall_vel.x *= 1.0 - dt * 0.3
			fall_vel.z *= 1.0 - dt * 0.3
			position += fall_vel * dt
			tumble += tumble_v * dt
			body.rotation = tumble
			wheel_spin -= 30.0 * dt
			if position.y < -30.0:
				state = "hidden"
				visible = false
		"stopping":
			stop_vel = stop_vel.move_toward(Vector3.ZERO, dt * 8.0)
			position += stop_vel * dt
			wheel_spin -= stop_vel.length() * dt / 0.19
	for w in wheels:
		w.rotation.x = wheel_spin
