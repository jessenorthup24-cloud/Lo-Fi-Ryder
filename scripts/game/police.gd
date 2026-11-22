extends Node3D
## The police cruiser for chases. It waits parked beside the road, then pulls out and follows the
## exact path you drove (your breadcrumb trail), so it takes the same ramps and bridges you did.

const M := preload("res://scripts/core/models.gd")
const CARS := preload("res://scripts/game/cars.gd")

const BASE_SPEED := 10.0     # you cruise at 9: it gains about 1 m/s unless you boost
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

func setup(toon: ShaderMaterial) -> void:
	var def := CARS.by_id("police")
	var c := M.car(def)
	body = Node3D.new()
	add_child(body)
	var bm := MeshInstance3D.new()
	bm.mesh = c["body"]
	bm.material_override = toon
	bm.position.y = c["ride"]
	body.add_child(bm)
	for i in 4:
		var w := MeshInstance3D.new()
		w.mesh = c["wheel_f"] if i < 2 else c["wheel_r"]
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
	beacon_r.position = Vector3(-0.14, 0.9 + c["ride"], 0.06)
	body.add_child(beacon_r)
	beacon_b = MeshInstance3D.new()
	beacon_b.mesh = bx
	beacon_b.position = Vector3(0.14, 0.9 + c["ride"], 0.06)
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

## Remember where the player has been (call every frame during a run).
func record(p: Vector3, yaw: float) -> void:
	if trail.is_empty():
		trail.append({"p": p, "yaw": yaw, "s": 0.0})
		return
	var last: Dictionary = trail[trail.size() - 1]
	var d := Vector2(p.x - last["p"].x, p.z - last["p"].z).length()
	if d < 0.3:
		return
	trail_s += d
	trail.append({"p": p, "yaw": yaw, "s": trail_s})
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

func start_chase() -> void:
	state = "chasing"
	s = maxf(trail_s - 12.0, float(trail[0]["s"]) if not trail.is_empty() else 0.0)
	speed = 4.0
	blend = 0.0

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
	return {"p": (a["p"] as Vector3).lerp(b["p"], k), "yaw": lerp_angle(a["yaw"], b["yaw"], k)}

func tick(dt: float, night: float) -> void:
	t += dt
	if state == "hidden":
		return
	var flashing := state == "chasing" or (state == "stopping" and t < 2.0) or state == "parked"
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
			var want := BASE_SPEED + (1.2 if g > 24.0 else 0.0)
			speed = move_toward(speed, want, dt * 5.0)
			s = minf(s + speed * dt, trail_s)
			var at := _at(s)
			blend = minf(1.0, blend + dt / 1.2)
			var k := smoothstep(0.0, 1.0, blend)
			position = parked_pos.lerp(at["p"], k)
			rotation.y = lerp_angle(parked_yaw, at["yaw"], k)
			wheel_spin -= speed * dt / 0.19
			body.position.y = sin(t * 18.0) * 0.01
		"stopping":
			stop_vel = stop_vel.move_toward(Vector3.ZERO, dt * 8.0)
			position += stop_vel * dt
			wheel_spin -= stop_vel.length() * dt / 0.19
	for w in wheels:
		w.rotation.x = wheel_spin
