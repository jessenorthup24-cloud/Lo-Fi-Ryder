extends SceneTree
## Handling report: runs a list of scenarios with on/off inputs (the way the phone pads work) on a flat
## test pad with a wall, a kerb and a ramp, and prints one line of numbers per scenario.
##   godot --headless --path . -s res://tools/test/handling.gd -- [car_id,car_id...] [scenario,scenario...]
const Car := preload("res://scripts/game/drift_car.gd")
const CARS := preload("res://scripts/game/cars.gd")

const ALL := ["accel", "brake", "grip_turn", "power_turn", "hb_drift", "hb_release", "drift_exit", "lift_off",
	"transition", "long_hold", "brake_drift", "uturn", "reverse", "wall_head", "wall_glance", "kerb", "jump", "tap_steer", "wall_drift", "hb_fast", "hb_slow",
	"skid40", "skid60", "skid80", "power_exit"]

var car: RigidBody3D
var cars: Array = []
var scen: Array = []
var ci := 0
var si := 0
var t := 0.0
var m := {}            # metrics for the scenario running
var log := false

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	cars = Array((a[0] if a.size() > 0 else "bug").split(","))
	scen = ALL.duplicate() if a.size() < 2 or a[1] == "all" else Array(a[1].split(","))
	log = a.size() > 2 and a[2] == "log"
	_pad()
	_start()

func _box(pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	sb.add_child(cs)
	sb.position = pos
	sb.rotation = rot
	get_root().add_child(sb)

func _pad() -> void:
	_box(Vector3(0, -1, 0), Vector3(6000, 2, 6000))
	# a wall across the far end of a lane at x = 2000
	_box(Vector3(2000, 2, -150), Vector3(80, 4, 2))
	_box(Vector3(2410, 2, -200), Vector3(2, 4, 400))
	# a kerb 0.18 m high running along z at x = 3000 (cross it at an angle)
	_box(Vector3(3000 + 30, 0.09, -100), Vector3(60, 0.18, 400))
	# a ramp at x = -2000: 2.2 m tall over 9 m (about 14 degrees)
	_box(Vector3(-2000, 0.0, -120), Vector3(8, 2.2, 9.2), Vector3(deg_to_rad(14.0), 0, 0))

func _start() -> void:
	if ci >= cars.size():
		quit()
		return
	if si >= scen.size():
		ci += 1
		si = 0
		if ci >= cars.size():
			quit()
			return
	if car:
		car.queue_free()
	car = Car.new()
	get_root().add_child(car)
	car.setup(CARS.by_id(cars[ci]), StandardMaterial3D.new(), null)
	var name: String = scen[si]
	var x := 0.0
	var yaw := 0.0
	match name:
		"wall_head":
			x = 2000.0
		"wall_glance":
			x = 2390.0
			yaw = deg_to_rad(-15.0)
		"wall_drift":
			x = 2392.0
		"kerb":
			x = 2985.0
			yaw = deg_to_rad(-35.0)
		"jump":
			x = -2000.0
		_:
			x = float(si) * 120.0 - 1000.0
	car.place(Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0.75, 0)))
	t = 0.0
	m = {"name": name, "maxv": 0.0, "max_slip": 0.0, "spun": false, "flipped": false, "slips": [], "min_up": 1.0, "marks": {}}

## speed to set at t = 0.4 (after the springs settle), m/s
func _launch(v0: float) -> void:
	var fwd := -car.global_transform.basis.z
	car.linear_velocity = fwd * v0

func _mark(key: String) -> void:
	if not m["marks"].has(key):
		m["marks"][key] = t

func _physics_process(dt: float) -> bool:
	if not car or not car.is_inside_tree():
		return false
	t += dt
	car.throttle = 0.0
	car.brake = 0.0
	car.handbrake = 0.0
	car.steer_in = 0.0
	var name: String = m["name"]
	var kmh: float = car.speed * 3.6
	var slip_d := rad_to_deg(car.slip)
	var aslip := absf(slip_d)
	var dur := 8.0
	var settled := t > 0.4
	match name:
		"accel":
			dur = 22.0
			car.throttle = 1.0
			if kmh >= 60.0: _mark("t60")
			if kmh >= 100.0: _mark("t100")
		"brake":
			if t < 0.4: pass
			elif t < 0.45: _launch(100.0 / 3.6)
			else:
				car.brake = 1.0
				if not m.has("x0"): m["x0"] = car.global_position
				if absf(car.speed) < 0.3: _mark("stop")
			dur = 6.0
		"grip_turn":
			if t < 0.45 and settled: _launch(50.0 / 3.6)
			car.throttle = 0.45
			car.steer_in = 1.0 if t > 1.0 else 0.0
		"power_turn":
			if t < 0.45 and settled: _launch(50.0 / 3.6)
			car.throttle = 1.0
			car.steer_in = 1.0 if t > 1.0 else 0.0
		"hb_drift", "hb_release", "drift_exit", "lift_off", "transition", "long_hold", "brake_drift", "hb_fast", "hb_slow":
			if t < 0.45 and settled: _launch((95.0 if name == "hb_fast" else (35.0 if name == "hb_slow" else 62.0)) / 3.6)
			car.throttle = 1.0
			# the entry: steer in, a short handbrake tap
			car.steer_in = 1.0 if t > 1.0 else 0.0
			car.handbrake = 1.0 if t > 1.0 and t < 1.3 else 0.0
			match name:
				"hb_release":   # steer in only for the entry, then hands off with the foot down
					if t > 2.2: car.steer_in = 0.0
				"drift_exit":   # hold it, then let go of steering to straighten up
					if t > 4.5: car.steer_in = 0.0
				"lift_off":
					if t > 4.5: car.throttle = 0.0
				"transition":   # swing it the other way
					if t > 3.5: car.steer_in = -1.0
				"long_hold":
					dur = 14.0
				"brake_drift":
					if t > 4.0:
						car.throttle = 0.0
						car.brake = 1.0
			if name == "transition" and t > 3.5 and car.slip > deg_to_rad(12.0): _mark("swapped")
			if t > 2.0 and t < (4.5 if name != "long_hold" else 14.0) and name != "transition":
				m["slips"].append(aslip)
			if name in ["drift_exit", "lift_off", "brake_drift"] and t > 4.6 and aslip < 6.0: _mark("straight")
			if aslip >= 15.0 and t > 1.0: _mark("t15")
		"wall_drift":   # drift sideways into a wall
			if t < 0.45 and settled: _launch(62.0 / 3.6)
			car.throttle = 1.0
			car.steer_in = 1.0 if t > 1.0 else 0.0
			car.handbrake = 1.0 if t > 1.0 and t < 1.3 else 0.0
		"uturn":
			if t < 0.45 and settled: _launch(15.0 / 3.6)
			car.throttle = 0.35
			car.steer_in = 1.0
			if t > 2.0:
				var p: Vector3 = car.global_position
				m["minx"] = minf(m.get("minx", 1e9), p.x); m["maxx"] = maxf(m.get("maxx", -1e9), p.x)
		"reverse":
			car.brake = 1.0 if t < 4.0 else 0.0
			car.throttle = 1.0 if t > 4.5 else 0.0
			if kmh < -5.0: _mark("rev5")
			m["minv"] = minf(m.get("minv", 0.0), kmh)
			if t > 4.5 and kmh > 5.0: _mark("fwd5")
		"wall_head":
			if t < 0.45 and settled: _launch(60.0 / 3.6)
			car.throttle = 1.0 if t < 2.0 else 0.0
			car.brake = 1.0 if t > 4.0 else 0.0   # back away
			if t > 3.0: m["after_v"] = kmh
		"wall_glance":
			if t < 0.45 and settled: _launch(70.0 / 3.6)
			car.throttle = 1.0
			if t > 2.5 and not m.has("exit_v"):
				m["exit_v"] = kmh
		"kerb":
			if t < 0.45 and settled: _launch(50.0 / 3.6)
			car.throttle = 0.6
			dur = 5.0
		"jump":
			if t < 0.45 and settled: _launch(80.0 / 3.6)
			car.throttle = 1.0
			if car.grounded == 0 and t > 1.0: m["air"] = m.get("air", 0.0) + dt
			dur = 7.0
		"skid40", "skid60", "skid80":   # a steady circle at this speed, full lock: how much sideways grip
			var v0 := float(name.substr(4)) / 3.6
			if t < 0.45 and settled: _launch(v0)
			car.steer_in = 1.0 if t > 1.0 else 0.0
			car.throttle = clampf((v0 - car.linear_velocity.length()) * 0.6 + 0.35, 0.0, 1.0)
			car.brake = clampf((car.linear_velocity.length() - v0 - 1.5) * 0.3, 0.0, 1.0)
			if t > 3.0:
				var yr := absf(car.angular_velocity.y)
				m["lat"] = float(m.get("lat", 0.0)) + car.linear_velocity.length() * yr
				m["vsum"] = float(m.get("vsum", 0.0)) + car.linear_velocity.length()
				m["n"] = int(m.get("n", 0)) + 1
		"power_exit":   # full lock and full throttle out of a slow corner: does the tail step out?
			if t < 0.45 and settled: _launch(30.0 / 3.6)
			car.steer_in = 1.0 if t > 1.0 else 0.0
			car.throttle = 1.0 if t > 1.0 else 0.3
		"tap_steer":   # quick taps at speed, the way you'd nudge through a curve
			if t < 0.45 and settled: _launch(90.0 / 3.6)
			car.throttle = 1.0
			var ph := fmod(t, 1.2)
			car.steer_in = 1.0 if t > 1.0 and ph < 0.18 else 0.0
	if settled:
		m["maxv"] = maxf(m["maxv"], kmh)
		if t > 1.0:
			m["max_slip"] = maxf(m["max_slip"], aslip)
		if aslip > 95.0 and absf(car.speed) > 0.0: m["spun"] = true
		var up: float = car.global_transform.basis.y.y
		m["min_up"] = minf(m["min_up"], up)
		if up < 0.2: m["flipped"] = true
	if log and fmod(t, 0.25) < dt:
		print("  t=%4.2f x=%7.1f z=%7.1f v=%5.1f slip=%6.1f steer=%5.1f yaw=%5.2f gr=%d up=%.2f drift=%.2f" % [t, car.global_position.x, car.global_position.z, kmh, slip_d, rad_to_deg(car.steer),
			car.angular_velocity.y, car.grounded, car.global_transform.basis.y.y, car.drift])
	if t >= dur:
		_report()
		si += 1
		_start()
	return false

func _report() -> void:
	var name: String = m["name"]
	var mk: Dictionary = m["marks"]
	var s := "%-8s %-11s " % [cars[ci], name]
	var kmh: float = car.speed * 3.6
	match name:
		"accel":
			s += "0-60 %.1fs  0-100 %s  top %.0f km/h (22s)" % [mk.get("t60", 99.0), ("%.1fs" % mk["t100"]) if mk.has("t100") else "-", m["maxv"]]
		"brake":
			var d: float = (car.global_position - (m["x0"] as Vector3)).length()
			s += "100-0 in %.1f m, %.2fs  yaw drift %.1f" % [d, mk.get("stop", 99.0) - 0.45, absf(rad_to_deg(car.global_rotation.y))]
		"uturn":
			s += "turning circle %.1f m" % [m.get("maxx", 0.0) - m.get("minx", 0.0)]
		"reverse":
			s += "reverse to -5 at %.1fs, max %.0f km/h, forward 5 at %s" % [mk.get("rev5", 99.0), m.get("minv", 0.0), ("%.1fs" % mk["fwd5"]) if mk.has("fwd5") else "never"]
		"wall_head":
			s += "after hit %.1f km/h" % m.get("after_v", 0.0)
		"wall_glance":
			s += "exit %.0f km/h" % m.get("exit_v", 0.0)
		"jump":
			s += "air %.2fs" % m.get("air", 0.0)
		"skid40", "skid60", "skid80":
			var nn: int = maxi(int(m.get("n", 0)), 1)
			var lat: float = float(m.get("lat", 0.0)) / nn
			var vv: float = float(m.get("vsum", 0.0)) / nn
			s += "lat %.1f m/s² at %.0f km/h, radius %.0f m " % [lat, vv * 3.6, vv * vv / maxf(lat, 0.1)]
		_:
			pass
	var sl: Array = m["slips"]
	if sl.size() > 0:
		var mean := 0.0
		for v in sl: mean += v
		mean /= sl.size()
		var sd := 0.0
		for v in sl: sd += (v - mean) * (v - mean)
		sd = sqrt(sd / sl.size())
		s += "angle %.0f±%.0f " % [mean, sd]
	for k in mk:
		if k in ["t15", "straight", "swapped"]:
			s += "%s@%.2f " % [k, mk[k]]
	s += " max_slip %.0f end %.0f km/h min_up %.2f%s%s" % [m["max_slip"], kmh, m["min_up"], " SPUN" if m["spun"] else "", " FLIPPED" if m["flipped"] else ""]
	print(s)
