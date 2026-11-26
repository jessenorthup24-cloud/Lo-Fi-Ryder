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
var _vis_t := 0.0
const SEEN := 170.0          # people further than this aren't drawn (too small to make out anyway)
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
	for pr in _live.duplicate():
		_unlive(pr)
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
	var run := 3.2 if float(pr.get("flee", 0.0)) > 0.0 else 1.0
	var d: float = pr["d"] + float(pr["wdir"]) * float(pr["speed"]) * run * dt
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
	if pr.has("live"):
		_place_live(pr, base, t)
		return
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
	# shot: a flinch, the body jerked back away from it for a moment
	var fl: float = pr.get("flinch", 0.0)
	if fl > 0.0:
		b = Basis(pr["flinch_ax"], fl * 0.55) * b
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
		var lift: float = pr.get("arms", 0.0) + fl * 2.2         # (hands up, flinching)
		if sg > 0.0 or (cheer_t > 0.0 and pr.get("cheering", false)):
			lift = lerpf(lift, 2.5 + sin(t * 12.0 + pr["phase"] + i) * 0.4, w)
		var ab := bb * Basis(Vector3.BACK, sg * lift)
		if swing != 0.0 and lift < 0.3:
			ab = bb * Basis(Vector3.RIGHT, swing * (1.0 if i == 0 else -1.0))
		pools[key + ("_al" if i == 0 else "_ar")].put(pr["al"] if i == 0 else pr["ar"], Transform3D(ab, base + bob + bb * (sh[i] as Vector3)))

# ---------------------------------------------------------------- the few nearest, fully animated
# The people nearest you (a handful) swap their still pieces for the real character, doing something: on the
# phone, texting, talking, leaning, waving, dancing by the sea; walking, running from trouble, sitting.
# Further off they're the still pieces again (cheap: dozens of them).
const Avatar := preload("res://scripts/game/avatar.gd")
const LIVE_N := 5
const LIVE_R := 24.0
const ACTS := ["talk", "text", "phone", "lean", "idle", "wave", "talk"]
var _live_t := 0.0
var _live: Array = []

func _live_tick(dt: float, you: Vector3) -> void:
	_live_t -= dt
	if _live_t > 0.0:
		return
	_live_t = 0.4
	# let go of any that have gone off (too far, knocked down, gone)
	for pr in _live.duplicate():
		var far: bool = Vector2(pr["pos"].x - you.x, pr["pos"].z - you.z).length() > LIVE_R * 1.3
		if far or pr["gone"] or pr.get("down", false) or pr.has("ride"):
			_unlive(pr)
	if _live.size() >= LIVE_N:
		return
	var best: Array = []
	for pr in list:
		if pr["gone"] or pr.get("down", false) or pr.has("ride") or pr.has("live") or pr["pose"] == "lie":
			continue
		var d := Vector2(pr["pos"].x - you.x, pr["pos"].z - you.z).length()
		if d < LIVE_R:
			best.append([d, pr])
	best.sort_custom(func(a, b): return a[0] < b[0])
	for e in best:
		if _live.size() >= LIVE_N:
			break
		_make_live(e[1])

func _make_live(pr: Dictionary) -> void:
	var av := Avatar.new()
	add_child(av)
	av.setup(String(M.CHARS[int(pr["v"]) % M.CHARS.size()]), "", mat)
	pr["live"] = av
	var p: Vector3 = pr["pos"]
	pr["act"] = "sit" if pr["pose"] == "sit" else ("dance" if p.z > 300.0 and randf() < 0.35 else ACTS[randi() % ACTS.size()])
	_live.append(pr)
	# the still pieces out of sight
	var hide := Transform3D(Basis().scaled(Vector3.ONE * 0.001), p + Vector3(0, -60, 0))
	pools[pr["key"]].put(pr["slot"], hide)
	pools[pr["key"] + "_al"].put(pr["al"], hide)
	pools[pr["key"] + "_ar"].put(pr["ar"], hide)

func _unlive(pr: Dictionary) -> void:
	var av: Node = pr.get("live")
	pr.erase("live")
	_live.erase(pr)
	if av and is_instance_valid(av):
		av.queue_free()

func _place_live(pr: Dictionary, base: Vector3, _t: float) -> void:
	var av: Avatar = pr["live"]
	if not is_instance_valid(av):
		pr.erase("live")
		return
	av.global_position = base - Vector3(0, SIT_LIFT if pr["pose"] == "sit" else 0.0, 0)
	av.rotation.y = float(pr["face"])
	if float(pr.get("flinch", 0.0)) > 0.9 and pr.has("flinch_ax"):
		av.flinch(Vector3(pr["flinch_ax"]).cross(Vector3.UP))
	if float(pr.get("flee", 0.0)) > 0.0:
		av.play("sprint" if pr.has("path") else "terrified")
	elif pr.has("path"):
		av.play("walk", 0.9)
	elif float(pr["wave"]) > 0.4 or (cheer_t > 0.0 and pr.get("cheering", false)):
		av.play("wave")
	else:
		av.play(String(pr.get("act", "idle")))

## Returns true when someone near the road starts waving (the car can honk back).
func tick(dt: float, car_pos: Vector3, car_vel: Vector3, t: float) -> bool:
	cheer_t = maxf(0.0, cheer_t - dt)
	_live_tick(dt, car_pos)
	var honk := false
	for pr in list:
		if pr["gone"]:
			continue
		if pr.get("flinch", 0.0) > 0.0:
			pr["flinch"] = maxf(0.0, float(pr["flinch"]) - dt * 3.0)
		if pr.get("down", false):
			# knocked down: back on their feet where they were, a good while later, once you're well away
			pr["down_t"] = float(pr["down_t"]) + dt
			if float(pr["down_t"]) > 45.0 and Vector2(pr["home"].x - car_pos.x, pr["home"].z - car_pos.z).length() > 130.0:
				_stand_up(pr, t)
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
			# (at a crawl anyone steps out of the way; going at a lick, only the quick ones get clear)
			if not pr.has("quick") or randf() < dt * 0.15:
				pr["quick"] = randf() < 0.3
			var can_dodge: bool = v2.length() < 8.0 or pr["quick"]
			if can_dodge and miss.length() < 3.2 and pr["y"] == 0.0 and (dist < 4.0 or v2.length() > 3.0):
				pr["vy"] = 5.5
				var side := Vector3(v2.z, 0, -v2.x).normalized() if v2.length() > 0.5 else -d.normalized()
				if side.dot(miss) < 0.0:
					side = -side
				pr["hop"] = side * 4.5
		if float(pr.get("flee", 0.0)) > 0.0:
			pr["flee"] = float(pr["flee"]) - dt
			if not walking and pr["pose"] == "stand":
				var fv: Vector3 = pr["flee_v"]
				pr["pos"] += fv * dt * clampf(float(pr["flee"]), 0.0, 1.0)
				pr["face"] = lerp_angle(pr["face"], atan2(-fv.x, -fv.z), 1.0 - exp(-dt * 8.0))
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

## Who the car is hitting right now: its box (half extents across, up, along; the middle `zc` along it)
## grown a little, at its transform xf, going at vel. Only at a decent pace (a nudge at a crawl is nothing).
func hits(xf: Transform3D, half: Vector3, zc: float, vel: Vector3) -> Array:
	var out := []
	if Vector2(vel.x, vel.z).length() < 3.5:
		return out
	var inv := xf.affine_inverse()
	for pr in list:
		if pr["gone"] or pr.get("down", false) or pr.has("ride"):
			continue
		var p: Vector3 = pr["pos"] + Vector3(0, float(pr["y"]) + 0.5, 0)
		if absf(p.x - xf.origin.x) > 7.0 or absf(p.z - xf.origin.z) > 7.0:
			continue
		var lp := inv * p
		if absf(lp.x) < half.x + 0.3 and absf(lp.z - zc) < half.z + 0.35 and lp.y > -0.6 and lp.y < half.y * 2.0 + 0.4:
			out.append(pr)
	return out

## Knocked down: gone from the crowd (their places in the pools freed) until they get up again.
## Returns what the ragdoll needs: {v (the character), xf (the body as it stood), shoulders}.
func knock_down(pr: Dictionary) -> Dictionary:
	if pr["gone"] or pr.get("down", false):
		return {}
	if pr.has("live"):
		_unlive(pr)
	var key: String = pr["key"]
	# the body as it stands now (seated: they come off the seat as they'd stand; lying: as they lie)
	var xf := Transform3D(Basis(Vector3.UP, pr["face"]), pr["pos"] + Vector3(0, float(pr["y"]), 0))
	if pr["pose"] == "sit":
		xf.origin.y -= SIT_LIFT
	elif pr["pose"] == "lie":
		var lb := Basis(Vector3.UP, pr["yaw"]) * Basis(Vector3.RIGHT, PI * 0.5)
		xf = Transform3D(lb, pr["pos"] + Vector3(0, 0.16, 0) + lb * Vector3(0, -0.5, 0))
	var info := {"v": int(pr["v"]), "xf": xf, "shoulders": shoulders["%d_stand" % int(pr["v"])]}
	pools[key].release(pr["slot"])
	pools[key + "_al"].release(pr["al"])
	pools[key + "_ar"].release(pr["ar"])
	pr["down"] = true
	pr["down_t"] = 0.0
	pr["y"] = 0.0
	pr["vy"] = 0.0
	pr["hop"] = Vector3.ZERO
	return info

func _stand_up(pr: Dictionary, t: float) -> void:
	var key: String = pr["key"]
	var slot: int = pools[key].alloc()
	if slot < 0:
		return
	pr["slot"] = slot
	pr["al"] = pools[key + "_al"].alloc()
	pr["ar"] = pools[key + "_ar"].alloc()
	pr["down"] = false
	pr["flee"] = 0.0
	pr["pos"] = pr["home"]
	_place(pr, t)

## Shot (not down): a flinch away from the bullet's direction d.
func flinch(pr: Dictionary, d: Vector3) -> void:
	var ax := Vector3.UP.cross(Vector3(d.x, 0, d.z).normalized())
	if ax.length() < 0.01:
		return
	pr["flinch_ax"] = ax.normalized()
	pr["flinch"] = 1.0

## Something awful just happened at `at`: everyone within r runs off (walkers hurry away along their way;
## people standing about run a few metres away from it).
func panic(at: Vector3, r: float) -> void:
	for pr in list:
		if pr["gone"] or pr.get("down", false) or pr.has("ride") or pr["pose"] == "lie":
			continue
		var d: Vector3 = pr["pos"] - at
		d.y = 0.0
		if d.length() > r:
			continue
		pr["flee"] = randf_range(2.5, 4.5)
		pr["wave"] = 0.0
		var away := d.normalized() if d.length() > 0.1 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		pr["flee_v"] = away * randf_range(3.5, 5.0)
		if pr.has("path"):
			# (along their way, whichever direction takes them off from it)
			var path: PackedVector3Array = pr["path"]
			var k := 0
			var cum: PackedFloat32Array = pr["cum"]
			while k < cum.size() - 2 and cum[k + 1] < float(pr["d"]):
				k += 1
			var along := (path[k + 1] - path[k]).normalized()
			pr["wdir"] = 1.0 if along.dot(away) >= 0.0 else -1.0

## The ground is going: pop away in a puff.
func vanish(pr: Dictionary, fx: Node) -> void:
	if pr.is_empty() or pr["gone"]:
		return
	if pr.has("live"):
		_unlive(pr)
	pr["gone"] = true
	if fx:
		fx.puff(pr["pos"] + Vector3(0, 0.5, 0), Color(1, 1, 1), 0.6, Vector3(0, 1, 0), 0.6, 1.0)
	var key: String = pr["key"]
	if not pr.get("down", false):
		pools[key].release(pr["slot"])
		pools[key + "_al"].release(pr["al"])
		pools[key + "_ar"].release(pr["ar"])
	list.erase(pr)

## Each pool (a character in a pose) is drawn only while someone in it is near enough to see: the pools
## span the whole island, so without this every one of them is a draw call from anywhere, even from the
## far side where nobody's in sight.
func tick_visibility(dt: float, car_pos: Vector3) -> void:
	_vis_t -= dt
	if _vis_t > 0.0:
		return
	_vis_t = 0.25
	var near := {}
	for pr in list:
		if pr["gone"] or pr.get("down", false):
			continue
		var p: Vector3 = pr["pos"]
		if Vector2(p.x - car_pos.x, p.z - car_pos.z).length_squared() < SEEN * SEEN:
			near[pr["key"]] = true
	for k: String in pools:
		var base := k.trim_suffix("_al").trim_suffix("_ar")
		pools[k].visible = pools[k].used() > 0 and near.has(base)
