extends SceneTree
## Drives the car on a flat test pad with scripted inputs and prints what it does.
##   godot --headless --path . -s res://tools/test/drive_test.gd -- [car_id] [script]
const Car := preload("res://scripts/game/drift_car.gd")
const CARS := preload("res://scripts/game/cars.gd")

var car: RigidBody3D
var t := 0.0
var plan := "accel"
var log_t := 0.0
var maxv := 0.0
var max_slip := 0.0

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var id := a[0] if a.size() > 0 else "bug"
	plan = a[1] if a.size() > 1 else "accel"
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(4000, 2, 4000)
	cs.shape = b
	cs.position.y = -1
	ground.add_child(cs)
	get_root().add_child(ground)
	car = Car.new()
	get_root().add_child(car)
	car.setup(CARS.by_id(id), StandardMaterial3D.new(), null)
	car.place(Transform3D(Basis(), Vector3(0, 1.0, 0)))

func _physics_process(dt: float) -> bool:
	t += dt
	car.throttle = 0.0
	car.brake = 0.0
	car.handbrake = 0.0
	car.steer_in = 0.0
	match plan:
		"accel":
			car.throttle = 1.0 if t < 14.0 else 0.0
			car.brake = 1.0 if t > 14.0 else 0.0
		"turn":
			car.throttle = 1.0 if t < 4.0 else 0.6
			car.steer_in = 1.0 if t > 4.0 and t < 10.0 else 0.0
		"drift":
			# get going, flick + handbrake, then hold throttle and steer into it
			car.throttle = 1.0 if t < 4.0 or t > 4.5 else 0.0
			car.steer_in = 1.0 if t > 4.0 and t < 9.0 else 0.0
			car.handbrake = 1.0 if t > 4.0 and t < 4.5 else 0.0
		"drift_hold":
			car.throttle = 1.0
			car.steer_in = 1.0 if t > 4.0 and t < 7.0 else (-0.0)
			car.handbrake = 1.0 if t > 4.0 and t < 4.4 else 0.0
		"drift_tap":
			car.throttle = 1.0
			car.steer_in = 1.0 if t > 4.0 and t < 8.0 else 0.0
			car.handbrake = 1.0 if t > 4.0 and t < 4.25 else 0.0
		"slalom":
			car.throttle = 1.0
			car.steer_in = (1.0 if int(t / 1.5) % 2 == 0 else -1.0) if t > 4.0 and t < 12.0 else 0.0
			car.handbrake = 1.0 if t > 4.0 and t < 4.25 else 0.0
		"drift_exit":
			car.throttle = 1.0
			car.steer_in = 1.0 if t > 4.0 and t < 6.0 else (0.0 if t < 9.0 else (-1.0 if t < 10.5 else 0.0))
			car.handbrake = 1.0 if t > 4.0 and t < 4.25 else 0.0
		"brake":
			car.throttle = 1.0 if t < 5.0 else 0.0
			car.brake = 1.0 if t > 5.0 else 0.0
	maxv = maxf(maxv, absf(car.speed))
	max_slip = maxf(max_slip, absf(rad_to_deg(car.slip)))
	log_t += dt
	if log_t >= 0.5:
		log_t = 0.0
		var p := car.global_position
		var up := car.global_transform.basis.y
		print("t=%4.1f v=%5.1f km/h gear=%d rpm=%.2f slip=%5.1f drift=%.2f steer=%5.1f yawrate=%5.2f y=%.2f up=%.2f grounded=%d spin=%.2f" % [
			t, car.speed * 3.6, car.gear, car.rpm, rad_to_deg(car.slip), car.drift, rad_to_deg(car.steer),
			car.angular_velocity.y, p.y, up.y, car.grounded, car.wheelspin])
	if t > 16.0:
		print("max speed %.1f km/h, max slip %.1f" % [maxv * 3.6, max_slip])
		quit()
	return false
