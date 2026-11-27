extends Node
## People against cars, whoever's driving: a police car tearing through a crowd, the traffic, a racer, a
## street driver; and the officers on foot and you. Bumped by a car at a crawl and they're shoved; hit
## at more than a walking pace and they're knocked off their feet (a ragdoll), getting up dazed and limping
## off a few seconds later; hit hard and it can kill them (the harder, the likelier: flat out, always).
## Your own car's hits on the crowd stay in main.gd (_ped_hit: those are your doing, with the police and
## the stats); here it's everyone else's car, and anyone's car against officers and you.

const Avatar := preload("res://scripts/game/avatar.gd")
const KNOCK := 3.2          # m/s: off their feet from here
const DEADLY := 7.5         # m/s: from here a hit can kill (always by about 14 m/s, 50 km/h)

var game: Node
var _last := {}             # car id -> [position, time] (the traffic is moved, not simulated: its speed's measured)
var _cool := {}             # who's just been hit (no second hit from the same car the next frame)
var dazed: Array = []       # people knocked down who'll get up: {av, t, pos, face, state}
var stats := {"knocked": 0, "killed": 0, "officers": 0, "you": 0}

func setup(g: Node) -> void:
	game = g

func tick(dt: float) -> void:
	var now: float = game.time
	var me: Vector3 = game.you().global_position
	for k in _cool.keys():
		if float(_cool[k]) < now:
			_cool.erase(k)
	for c in _cars():
		var body: Node3D = c[0]
		if not is_instance_valid(body) or body.global_position.distance_to(me) > 140.0:
			continue
		var vel := _vel(body, now)
		if Vector2(vel.x, vel.z).length() < 2.0:
			continue
		var half: Vector3 = c[1]
		var zc: float = c[2]
		var mine: bool = body == game.car
		if not mine:
			for pr in game.island.people.hits(body.global_transform, half, zc, vel):
				hit_person(pr, vel, body)
		for o in game.gunplay.officers:
			if not o["dead"] and is_instance_valid(o["node"]) and _inside(body, half, zc, (o["node"] as Node3D).global_position):
				_hit_officer(o, vel, body, mine)
		if game.on_foot and not mine and _inside(body, half, zc, game.foot.global_position):
			_hit_you(vel, body)
	_dazed_tick(dt)

## Every car on the road that could hit someone: [body, half size, middle along its length].
func _cars() -> Array:
	var out: Array = []
	if game.car and is_instance_valid(game.car):
		out.append([game.car, _half_of(game.car), _zc_of(game.car)])
	for u in game.police.units:
		if is_instance_valid(u["car"]):
			out.append([u["car"], _half_of(u["car"]), _zc_of(u["car"])])
	for tc in game.traffic.cars:
		var b: Node3D = tc["body"]
		if is_instance_valid(b):
			out.append([b, Vector3(float(tc["w"]) * 0.5, 0.8, float(tc["len"]) * 0.5), 0.0])
	if game.race != null:
		for r in game.race.racers:
			if is_instance_valid(r["car"]):
				out.append([r["car"], _half_of(r["car"]), _zc_of(r["car"])])
	if game.crew != null:
		for d in game.crew.drivers:
			if d.get("car") != null and is_instance_valid(d["car"]):
				out.append([d["car"], _half_of(d["car"]), _zc_of(d["car"])])
	return out

func _half_of(car: Node) -> Vector3:
	var info = car.get("info")
	if info is Dictionary and info.has("width"):
		return Vector3(float(info["width"]) * 0.5, float(info.get("height", 1.4)) * 0.5, float(info["length"]) * 0.5)
	return Vector3(0.95, 0.7, 2.2)

func _zc_of(car: Node) -> float:
	var info = car.get("info")
	if info is Dictionary and info.has("front"):
		return (float(info["front"]) + float(info["back"])) * 0.5
	return 0.0

func _vel(body: Node3D, now: float) -> Vector3:
	if body is RigidBody3D and not (body as RigidBody3D).freeze:
		return (body as RigidBody3D).linear_velocity
	var id := body.get_instance_id()
	var p := body.global_position
	var v := Vector3.ZERO
	if _last.has(id):
		var l: Array = _last[id]
		var dtt := now - float(l[1])
		if dtt > 0.0001:
			v = (p - (l[0] as Vector3)) / dtt
			if v.length() > 60.0:
				v = Vector3.ZERO          # (put somewhere)
		else:
			v = l[2]
	_last[id] = [p, now, v]
	return v

func _inside(body: Node3D, half: Vector3, zc: float, p: Vector3) -> bool:
	if absf(p.x - body.global_position.x) > 6.0 or absf(p.z - body.global_position.z) > 6.0:
		return false
	var lp := body.global_transform.affine_inverse() * (p + Vector3(0, 0.5, 0))
	return absf(lp.x) < half.x + 0.35 and absf(lp.z - zc) < half.z + 0.4 and lp.y > -0.8 and lp.y < half.y * 2.0 + 0.5

## How hard it hit them: the car's speed toward them (a car sliding past sideways hits as hard as its slide).
static func _speed(vel: Vector3) -> float:
	return Vector2(vel.x, vel.z).length()

# ------------------------------------------------------------------ the crowd

func hit_person(pr: Dictionary, vel: Vector3, car: Node3D) -> void:
	if float(pr.get("car_hit_t", -9.0)) > game.time - 1.0:
		return
	pr["car_hit_t"] = game.time
	var s := _speed(vel)
	var dir := Vector3(vel.x, 0, vel.z).normalized()
	var lethal: bool = s >= DEADLY and randf() < clampf((s - DEADLY) / (14.0 - DEADLY), 0.25, 1.0)
	var av: Avatar = pr.get("live") if pr.has("live") and is_instance_valid(pr["live"]) else null
	var at: Vector3 = (pr["pos"] as Vector3) + Vector3(0, 0.9, 0)
	game.fx.blood(at, dir, int(clampf(6.0 + s * 1.2, 6.0, 30.0)), clampf(2.0 + s * 0.25, 2.0, 8.0))
	game.sfx("body_hit_%d" % randi_range(1, 3), clampf(-10.0 + s * 0.5, -10.0, 2.0), randf_range(0.9, 1.05))
	if av != null:
		var body: Avatar = game.gore._take(pr, av)
		if body == null:
			return
		var throw := vel * clampf(0.55 + s * 0.02, 0.55, 0.95) + Vector3(0, clampf(s * 0.18, 0.8, 3.5), 0)
		body.go_limp(game.gore, throw, dir * clampf(s * 0.3, 1.0, 4.0) + Vector3(0, 0.8, 0))
		if lethal:
			stats["killed"] += 1
			game.fx.splat(Vector3(at.x, game.island.height_at(at.x, at.z), at.z) + dir * 1.5, randf_range(0.9, 1.3), 2.5)
			get_tree().create_timer(40.0, false).timeout.connect(func():
				if is_instance_valid(body):
					body.queue_free())
		else:
			stats["knocked"] += 1
			dazed.append({"av": body, "t": 0.0, "up_at": randf_range(2.8, 4.2), "state": "down"})
	else:
		# (further off, one of the crowd: the crowd's own ragdoll, up again later on)
		var info: Dictionary = game.island.people.knock_down(pr)
		if not info.is_empty():
			game.ragdolls.spawn(int(info["v"]), info["xf"], info["shoulders"], vel, car as PhysicsBody3D if car is PhysicsBody3D else null)
			stats["killed" if lethal else "knocked"] += 1
	game.island.people.panic(pr["pos"], 14.0)

## Up again: on their feet where the body ended up, dazed, limping off; gone once they're out of sight.
func _dazed_tick(dt: float) -> void:
	for d in dazed.duplicate():
		var av: Avatar = d["av"]
		if not is_instance_valid(av):
			dazed.erase(d)
			continue
		d["t"] = float(d["t"]) + dt
		match String(d["state"]):
			"down":
				if float(d["t"]) >= float(d["up_at"]):
					var tp: Vector3 = av.limp.torso_pos() if av.limp else av.global_position
					var p := Vector3(tp.x, game.island.height_at(tp.x, tp.z), tp.z)
					av.recover()
					av.global_position = p
					av.hurt = true
					av.play_once("get_up", 0.0, 1.1, 1.2)
					var away: Vector3 = p - game.you().global_position
					d["face"] = atan2(-away.x, -away.z) + randf_range(-0.6, 0.6)
					d["pos"] = p
					d["state"] = "up"
					d["t"] = 0.0
			"up":
				if float(d["t"]) < 1.0:
					continue
				var fwd := Vector3(-sin(float(d["face"])), 0, -cos(float(d["face"])))
				var np: Vector3 = game.island.people.wall_move(d["pos"], (d["pos"] as Vector3) + fwd * 1.1 * dt)
				d["pos"] = np
				av.global_position = np
				av.rotation.y = float(d["face"]) + PI
				av.locomote(Vector2(0, 1.1), 0.25)
				if float(d["t"]) > 25.0 or np.distance_to(game.you().global_position) > 90.0:
					av.queue_free()
					dazed.erase(d)

# ------------------------------------------------------------------ officers and you

func _hit_officer(o: Dictionary, vel: Vector3, car: Node3D, mine: bool) -> void:
	var key := "o%d" % (o["node"] as Node).get_instance_id()
	if _cool.has(key) or float(o.get("down_t", 0.0)) > 0.0:
		return
	var s := _speed(vel)
	if s < KNOCK:
		return
	_cool[key] = game.time + 1.2
	stats["officers"] += 1
	var n: CharacterBody3D = o["node"]
	var dir := Vector3(vel.x, 0, vel.z).normalized()
	game.fx.blood(n.global_position + Vector3(0, 1.0, 0), dir, int(clampf(6.0 + s, 6.0, 26.0)), 4.0)
	game.sfx("body_hit_%d" % randi_range(1, 3), clampf(-8.0 + s * 0.5, -8.0, 2.0))
	o["hp"] = float(o["hp"]) - (s - KNOCK + 1.0) * 13.0
	var throw := vel * 0.7 + Vector3(0, clampf(s * 0.18, 0.8, 3.0), 0)
	if float(o["hp"]) <= 0.0:
		game.gunplay._officer_down(o, throw)
		if mine:
			game.save.add_stat("cops_down", 1)
			game.gunplay.kills["police"] += 1
			game.police.heat_pts += 0.6
		return
	# knocked flat: down a few seconds, then up and at it again
	o["down_t"] = randf_range(2.6, 3.6)
	(o["av"] as Avatar).go_limp(game.gunplay, throw, dir * 2.0 + Vector3(0, 0.6, 0))
	if mine:
		game.police.heat_pts += 0.3

func _hit_you(vel: Vector3, car: Node3D) -> void:
	var foot: CharacterBody3D = game.foot
	if _cool.has("you") or foot.down_t > 0.0 or game.gunplay.dying:
		return
	var s := _speed(vel)
	if s < KNOCK:
		return
	_cool["you"] = game.time + 1.5
	stats["you"] += 1
	var dmg := (s - KNOCK + 1.0) * 11.0
	var gp = game.gunplay
	game.buzz(int(clampf(40.0 + s * 4.0, 50.0, 120.0)), 1.0)
	game.shake = maxf(game.shake, clampf(s * 0.03, 0.2, 0.6))
	if gp.hp - dmg <= 0.0:
		gp.hurt(dmg, car.global_position)          # (out of health: limp, and it's WASTED)
		return
	gp.hp -= dmg
	gp.hurt_t = 0.0
	game.fx.blood(foot.global_position + Vector3(0, 1.0, 0), Vector3(vel.x, 0, vel.z).normalized(), 12, 4.0)
	game.sfx("body_hit_%d" % randi_range(1, 3), -2.0, 0.9)
	game.ui.impact_flash(0.4)
	foot.knock_down(game, vel * 0.7 + Vector3(0, clampf(s * 0.15, 0.8, 3.0), 0), clampf(1.6 + s * 0.12, 1.8, 3.2))
