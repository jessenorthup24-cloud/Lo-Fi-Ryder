extends Node3D
## The little people (Kenney mini characters) who live in the places beside the road. They turn to watch
## you, wave as you pass, cheer at stunts nearby, and hop out of the way so you can never hit them. When
## the ground crumbles under them they pop away in a puff (they're fine).

const M := preload("res://scripts/core/models.gd")
const Pool := preload("res://scripts/game/pool.gd")
const POSES := ["stand", "sit"]
const SIT_LIFT := 0.06   # a sitter's seat is this far below its origin

var world: Node
var mat: ShaderMaterial
var pools := {}      # "v_pose" -> Pool, "v_pose_al" / "v_pose_ar" -> arm Pools
var shoulders := {}  # "v_pose" -> [left, right]
var list: Array = []
var cheer_t := 0.0
var cheer_pos := Vector3.ZERO

func setup(w: Node, material: ShaderMaterial) -> void:
	world = w
	mat = material
	for v in M.CHARS.size():
		for pose in POSES:
			var key := "%d_%s" % [v, pose]
			var cap := 20 if pose == "stand" else 8
			for part in ["", "al", "ar"]:
				var p: Pool = Pool.new()
				p.setup(M.kperson(v, pose, part), cap, mat, false, part == "")
				p.name = "person_" + key + part
				add_child(p)
				pools[key if part == "" else key + "_" + part] = p
			shoulders[key] = M.kshoulders(v, pose)

func clear() -> void:
	for p in pools.values():
		p.clear_all()
	list.clear()

## pose: "stand", "sit" (pos.y = the seat's height) or "lie" (sunbathing on a towel)
func spawn(v: int, pose: String, pos: Vector3, yaw: float, s: int) -> Dictionary:
	var mp := "sit" if pose == "sit" else "stand"
	var n: int = M.CHARS.size()
	# that one's busy? someone else comes along
	for k in n:
		var vv := (v + k) % n
		var key := "%d_%s" % [vv, mp]
		var slot: int = pools[key].alloc()
		if slot < 0:
			continue
		if pose == "sit":
			pos.y += SIT_LIFT
		var pr := {"v": vv, "pose": pose, "key": key, "slot": slot, "al": pools[key + "_al"].alloc(), "ar": pools[key + "_ar"].alloc(),
			"pos": pos, "home": pos, "yaw": yaw, "face": yaw, "y": 0.0, "vy": 0.0, "wave": 0.0, "hop": Vector3.ZERO, "s": s,
			"phase": randf() * TAU, "gone": false}
		list.append(pr)
		_place(pr, 0.0)
		return pr
	return {}

## Someone out for a walk: back and forth along a path (a pavement), swinging their arms.
func spawn_walker(v: int, path: PackedVector3Array, speed: float) -> Dictionary:
	var pr := spawn(v, "stand", path[0], 0.0, 0)
	if pr.is_empty():
		return pr
	var cum := PackedFloat32Array([0.0])
	for k in range(1, path.size()):
		cum.append(cum[k - 1] + path[k].distance_to(path[k - 1]))
	pr["path"] = path
	pr["cum"] = cum
	pr["d"] = randf() * cum[cum.size() - 1]
	pr["wdir"] = 1.0 if randf() < 0.5 else -1.0
	pr["speed"] = speed
	return pr

func _walk(pr: Dictionary, dt: float) -> void:
	var cum: PackedFloat32Array = pr["cum"]
	var total: float = cum[cum.size() - 1]
	var d: float = pr["d"] + float(pr["wdir"]) * float(pr["speed"]) * dt
	if d > total or d < 0.0:
		pr["wdir"] = -float(pr["wdir"])
		d = clampf(d, 0.0, total)
	pr["d"] = d
	var path: PackedVector3Array = pr["path"]
	var k := 0
	while k < cum.size() - 2 and cum[k + 1] < d:
		k += 1
	var seg := maxf(cum[k + 1] - cum[k], 0.001)
	var a := path[k]
	var b := path[k + 1]
	var p := a.lerp(b, (d - cum[k]) / seg)
	var dir := (b - a) * float(pr["wdir"])
	pr["pos"] = p
	pr["home"] = p
	pr["face"] = lerp_angle(pr["face"], atan2(-dir.x, -dir.z), 1.0 - exp(-dt * 6.0))

func cheer(at: Vector3) -> void:
	cheer_t = 1.2
	cheer_pos = at

func _place(pr: Dictionary, t: float) -> void:
	var key: String = pr["key"]
	var sh: Array = shoulders[key]
	var base: Vector3 = pr["pos"] + Vector3(0, pr["y"], 0)
	if pr["pose"] == "lie":
		var lb := Basis(Vector3.UP, pr["yaw"]) * Basis(Vector3.RIGHT, PI * 0.5)
		var lo := base + Vector3(0, 0.16, 0) + lb * Vector3(0, -0.5, 0)
		pools[key].put(pr["slot"], Transform3D(lb, lo))
		for i in 2:
			var sg := signf((sh[i] as Vector3).x)
			pools[key + ("_al" if i == 0 else "_ar")].put(pr["al"] if i == 0 else pr["ar"],
				Transform3D(lb * Basis(Vector3.BACK, sg * 0.25), lo + lb * (sh[i] as Vector3)))
		return
	var b := Basis(Vector3.UP, pr["face"])
	var bob := Vector3(0, sin(t * 2.0 + pr["phase"]) * 0.008, 0)
	var swing := 0.0
	if pr.has("path"):
		var step: float = float(pr["d"]) * 3.4
		swing = sin(step) * 0.55
		bob = Vector3(0, absf(sin(step)) * 0.06, 0)
		b = b * Basis(Vector3.BACK, sin(step) * 0.04)
	# a little sway while waving
	var w: float = pr["wave"]
	var bb := b * Basis(Vector3.BACK, sin(t * 6.0 + pr["phase"]) * 0.06 * w)
	pools[key].put(pr["slot"], Transform3D(bb, base + bob))
	for i in 2:
		var sg := signf((sh[i] as Vector3).x)
		# arms hang at rest; the right arm waves (both when cheering)
		var lift: float = pr.get("arms", 0.0)
		if sg > 0.0 or (cheer_t > 0.0 and pr.get("cheering", false)):
			lift = lerpf(lift, 2.5 + sin(t * 12.0 + pr["phase"] + i) * 0.4, w)
		var ab := bb * Basis(Vector3.BACK, sg * lift)
		if swing != 0.0 and lift < 0.3:
			ab = bb * Basis(Vector3.RIGHT, swing * (1.0 if i == 0 else -1.0))
		pools[key + ("_al" if i == 0 else "_ar")].put(pr["al"] if i == 0 else pr["ar"], Transform3D(ab, base + bob + bb * (sh[i] as Vector3)))

## Returns true when someone near the road starts waving (the car can honk back).
func tick(dt: float, car_pos: Vector3, car_vel: Vector3, t: float) -> bool:
	cheer_t = maxf(0.0, cheer_t - dt)
	var honk := false
	for pr in list:
		if pr["gone"]:
			continue
		if pr.has("ride"):
			# moved along by its place (the skater)
			_place(pr, t)
			continue
		var walking: bool = pr.has("path")
		if walking and pr["y"] == 0.0:
			_walk(pr, dt)
		var d: Vector3 = car_pos - pr["pos"]
		d.y = 0
		var dist := d.length()
		if dist > 60.0:
			if walking and dist < 160.0:
				_place(pr, t)
			continue
		if pr["pose"] != "lie":
			# watch the car go by
			if dist < 26.0 and not walking:
				pr["face"] = lerp_angle(pr["face"], atan2(-d.x, -d.z), 1.0 - exp(-dt * 4.0))
			var want_wave := 1.0 if dist < 18.0 else 0.0
			if cheer_t > 0.0 and cheer_pos.distance_to(pr["pos"]) < 30.0:
				want_wave = 1.0
				pr["cheering"] = true
				if pr["vy"] == 0.0 and pr["y"] == 0.0 and randf() < dt * 3.0:
					pr["vy"] = 2.6
			else:
				pr["cheering"] = false
			if want_wave > 0.5 and pr["wave"] < 0.1 and dist < 14.0:
				honk = true
			pr["wave"] = move_toward(pr["wave"], want_wave, dt * 3.0)
			# hop out of the way: where will the car pass in the next half second?
			var rel: Vector3 = pr["pos"] - car_pos
			rel.y = 0.0
			var v2 := Vector3(car_vel.x, 0, car_vel.z)
			var tc := clampf(rel.dot(v2) / maxf(v2.length_squared(), 0.01), 0.0, 0.55)
			var miss := rel - v2 * tc
			if miss.length() < 3.2 and pr["y"] == 0.0 and (dist < 4.0 or v2.length() > 3.0):
				pr["vy"] = 5.5
				var side := Vector3(v2.z, 0, -v2.x).normalized() if v2.length() > 0.5 else -d.normalized()
				if side.dot(miss) < 0.0:
					side = -side
				pr["hop"] = side * 4.5
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
	var key: String = pr["key"]
	pools[key].release(pr["slot"])
	pools[key + "_al"].release(pr["al"])
	pools[key + "_ar"].release(pr["ar"])
	list.erase(pr)

func tick_visibility() -> void:
	for p in pools.values():
		p.visible = p.used() > 0
