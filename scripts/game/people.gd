extends Node3D
## Little peg-figure people who live in the places beside the road. They turn to watch you, wave as
## you pass, cheer at stunts nearby, and hop out of the way so you can never hit them. When the
## ground crumbles under them they pop away in a puff (they're fine).

const M := preload("res://scripts/core/models.gd")
const Pool := preload("res://scripts/game/pool.gd")

var world: Node
var mat: ShaderMaterial
var bodies := {}     # "v_pose" -> Pool
var arms := {}       # v -> Pool
var list: Array = []
var cheer_t := 0.0
var cheer_pos := Vector3.ZERO

func setup(w: Node, material: ShaderMaterial) -> void:
	world = w
	mat = material
	for v in M.PEOPLE.size():
		for sit in [false, true]:
			var p: Pool = Pool.new()
			p.setup(M.person(v, sit), 40, mat, false, true)
			add_child(p)
			bodies["%d_%s" % [v, "sit" if sit else "stand"]] = p
		var a: Pool = Pool.new()
		a.setup(M.arm(v), 160, mat, false, false)
		add_child(a)
		arms[v] = a

func clear() -> void:
	for p in bodies.values():
		p.clear_all()
	for a in arms.values():
		a.clear_all()
	list.clear()

## pose: "stand", "sit" or "lie" (sunbathing on a towel)
func spawn(v: int, pose: String, pos: Vector3, yaw: float, s: int) -> Dictionary:
	v = v % M.PEOPLE.size()
	var key := "%d_%s" % [v, "sit" if pose == "sit" else "stand"]
	var bp: Pool = bodies[key]
	var slot := bp.alloc()
	if slot < 0:
		return {}
	var al: int = arms[v].alloc()
	var ar: int = arms[v].alloc()
	var pr := {"v": v, "pose": pose, "key": key, "slot": slot, "al": al, "ar": ar, "pos": pos, "home": pos, "yaw": yaw,
		"face": yaw, "y": 0.0, "vy": 0.0, "wave": 0.0, "hop": Vector3.ZERO, "s": s, "phase": randf() * TAU, "gone": false}
	list.append(pr)
	_place(pr, 0.0)
	return pr

func cheer(at: Vector3) -> void:
	cheer_t = 1.2
	cheer_pos = at

func _place(pr: Dictionary, t: float) -> void:
	var b := Basis(Vector3.UP, pr["face"])
	var base: Vector3 = pr["pos"] + Vector3(0, pr["y"], 0)
	var shoulder_y := 0.7 if pr["pose"] != "sit" else 0.48
	if pr["pose"] == "lie":
		var lb := Basis(Vector3.UP, pr["yaw"]) * Basis(Vector3.RIGHT, -PI * 0.5)
		bodies[pr["key"]].put(pr["slot"], Transform3D(lb, base + Vector3(0, 0.2, 0) + lb * Vector3(0, -0.5, 0)))
		for side in [-1.0, 1.0]:
			var sl: int = pr["al"] if side < 0 else pr["ar"]
			var ab := lb * Basis(Vector3.BACK, side * 0.15)
			arms[pr["v"]].put(sl, Transform3D(ab, base + Vector3(0, 0.2, 0) + lb * Vector3(side * 0.2, 0.2, 0)))
		return
	var bob := sin(t * 2.0 + pr["phase"]) * 0.01
	bodies[pr["key"]].put(pr["slot"], Transform3D(b, base + Vector3(0, bob, 0)))
	var w: float = pr["wave"]
	for side in [-1.0, 1.0]:
		var sl: int = pr["al"] if side < 0 else pr["ar"]
		# arms hang at rest; the right arm waves (both when cheering)
		var lift := 0.12
		var waving: bool = side > 0 or (cheer_t > 0.0 and pr.get("cheering", false))
		if waving:
			lift = lerpf(0.12, 2.6 + sin(t * 12.0 + pr["phase"]) * 0.35, w)
		var ab := b * Basis(Vector3.BACK, side * lift)
		arms[pr["v"]].put(sl, Transform3D(ab, base + Vector3(0, shoulder_y + bob, 0) + b * Vector3(side * 0.19, 0, 0)))

## Returns true when someone near the road starts waving (the car can honk back).
func tick(dt: float, car_pos: Vector3, car_vel: Vector3, t: float) -> bool:
	cheer_t = maxf(0.0, cheer_t - dt)
	var honk := false
	for pr in list:
		if pr["gone"]:
			continue
		var d: Vector3 = car_pos - pr["pos"]
		d.y = 0
		var dist := d.length()
		if dist > 34.0:
			continue
		if pr["pose"] != "lie":
			# watch the car go by
			if dist < 12.0:
				pr["face"] = lerp_angle(pr["face"], atan2(-d.x, -d.z) + PI, 1.0 - exp(-dt * 4.0))
			var want_wave := 1.0 if dist < 8.0 else 0.0
			if cheer_t > 0.0 and cheer_pos.distance_to(pr["pos"]) < 14.0:
				want_wave = 1.0
				pr["cheering"] = true
				if pr["vy"] == 0.0 and pr["y"] == 0.0 and randf() < dt * 3.0:
					pr["vy"] = 2.6
			else:
				pr["cheering"] = false
			if want_wave > 0.5 and pr["wave"] < 0.1 and dist < 7.0:
				honk = true
			pr["wave"] = move_toward(pr["wave"], want_wave, dt * 3.0)
			# hop out of the way
			if dist < 1.25 and pr["y"] == 0.0:
				pr["vy"] = 4.2
				var away := -d.normalized() if dist > 0.01 else Vector3.RIGHT
				var side := Vector3(car_vel.z, 0, -car_vel.x).normalized()
				if side.dot(away) < 0.0:
					side = -side
				pr["hop"] = side * 2.4
		if pr["vy"] != 0.0 or pr["y"] > 0.0:
			pr["vy"] -= 14.0 * dt
			pr["y"] += pr["vy"] * dt
			pr["pos"] += pr["hop"] * dt
			if pr["y"] <= 0.0:
				pr["y"] = 0.0
				pr["vy"] = 0.0
				pr["hop"] = Vector3.ZERO
		_place(pr, t)
	return honk

## The ground is going: pop away in a puff.
func vanish(pr: Dictionary, fx: Node) -> void:
	if pr.is_empty() or pr["gone"]:
		return
	pr["gone"] = true
	if fx:
		fx.puff(pr["pos"] + Vector3(0, 0.5, 0), Color(1, 1, 1), 0.6, Vector3(0, 1, 0), 0.6, 1.0)
	bodies[pr["key"]].release(pr["slot"])
	arms[pr["v"]].release(pr["al"])
	arms[pr["v"]].release(pr["ar"])
	list.erase(pr)

func tick_visibility() -> void:
	for p in bodies.values():
		p.visible = p.used() > 0
	for a in arms.values():
		a.visible = a.used() > 0
