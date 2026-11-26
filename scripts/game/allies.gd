extends Node3D
## Your crew on foot. When you're out of the car with the police on you or a heist on, the friends driving
## with you pull up, get out (each with their own look and gun) and fight beside you: they keep close, take
## cover a few metres off you and shoot the police officers that come at you. They can get hurt and go down
## (back up and in their car when you drive off). Back in your car, they get back in theirs and drive with you
## again.

const Avatar := preload("res://scripts/game/avatar.gd")
const Weapons := preload("res://scripts/game/weapons.gd")

const LAYER := 512
const HP := 160.0
const SHOT_DMG := {"pistol": 26.0, "smg": 17.0, "rifle": 32.0, "carbine": 30.0, "shotgun": 45.0}
## Who looks like who, and what they carry (by their place in crew.gd's roster).
const LOOKS := ["male_hoodie", "women_casual2", "male_jacket", "woman_casual3", "male_constructor", "women_coat",
	"male_t_shirt", "women_fitness", "male_beach", "businesswoman", "male_casual2", "women_beach"]
const GUNS := ["smg", "rifle", "shotgun", "carbine", "rifle", "pistol", "carbine", "smg", "shotgun", "rifle", "pistol", "smg"]

var game: Node
var list: Array = []          # {who, node: CharacterBody3D, av, hp, cool, car (their Car), down, slot}

func setup(g: Node) -> void:
	game = g

func alive() -> Array:
	var out: Array = []
	for a in list:
		if not a["down"] and is_instance_valid(a["node"]):
			out.append(a)
	return out

func tick(dt: float) -> void:
	var want: bool = game.on_foot and game.foot != null and (game.police.wanted() or game.heist.active()) and not game.gunplay.dying
	if not want:
		if not list.is_empty() and not game.on_foot:
			_all_back()
		return
	var you: Node3D = game.foot
	var yp: Vector3 = you.global_position
	# out of the car: each of your crew parked up near you gets out
	for d in game.crew.drivers:
		if String(d["mode"]) != "crew" or not is_instance_valid(d["car"]):
			continue
		var c: Node3D = d["car"]
		if _of(int(d["who"])).is_empty() and c.global_position.distance_to(yp) < 70.0 and (c as RigidBody3D).linear_velocity.length() < 3.0:
			_out(d)
	var officers: Array = game.gunplay.officers
	var i := 0
	for a in list.duplicate():
		var n: CharacterBody3D = a["node"]
		if not is_instance_valid(n):
			list.erase(a)
			continue
		var av: Avatar = a["av"]
		if a["down"]:
			continue
		i += 1
		# the nearest officer up and about, in range
		var tgt: Dictionary = {}
		var td := 34.0
		for o in officers:
			if o["dead"] or not is_instance_valid(o["node"]):
				continue
			var dd := (o["node"] as Node3D).global_position.distance_to(n.global_position)
			if dd < td:
				td = dd
				tgt = o
		# where to be: off your shoulder (each their own side), a few metres out
		var ang: float = float(a["slot"]) * 2.1 + 0.6
		var spot := yp + Vector3(cos(ang), 0, sin(ang)) * (4.5 if tgt.is_empty() else 6.0)
		var to := spot - n.global_position
		to.y = 0.0
		var vel := Vector3.ZERO
		if to.length() > 1.5:
			vel = to.normalized() * clampf(to.length() * 1.6, 1.5, 6.0)
		n.velocity.x = lerpf(n.velocity.x, vel.x, 1.0 - exp(-dt * 6.0))
		n.velocity.z = lerpf(n.velocity.z, vel.z, 1.0 - exp(-dt * 6.0))
		n.velocity.y = 0.0 if n.is_on_floor() else n.velocity.y - 16.0 * dt
		n.move_and_slide()
		var face_to: Vector3 = (tgt["node"] as Node3D).global_position - n.global_position if not tgt.is_empty() else (vel if vel.length() > 0.5 else Vector3.ZERO)
		if face_to.length() > 0.1:
			av.rotation.y = lerp_angle(av.rotation.y, atan2(-face_to.x, -face_to.z) + PI, 1.0 - exp(-dt * 10.0))
		var fwd := Vector3(-sin(av.rotation.y - PI), 0, -cos(av.rotation.y - PI))
		var left := Vector3(-cos(av.rotation.y - PI), 0, sin(av.rotation.y - PI))
		var hv := Vector3(n.velocity.x, 0, n.velocity.z)
		av.locomote(Vector2(hv.dot(left), hv.dot(fwd)))
		if tgt.is_empty():
			av.aim_at(Vector3.INF, true, dt)
			continue
		var tp: Vector3 = (tgt["node"] as Node3D).global_position + Vector3(0, 1.1, 0)
		av.aim_at(tp, true, dt)
		av.play("holding-both", 1.0)
		a["cool"] = float(a["cool"]) - dt
		if float(a["cool"]) <= 0.0:
			var gid := String(GUNS[int(a["who"]) % GUNS.size()])
			var auto := gid in ["smg", "rifle", "carbine"]
			a["cool"] = randf_range(0.12, 0.2) if auto and randf() < 0.75 else randf_range(0.7, 1.3)
			var from := n.global_position + Vector3(0, 1.3, 0)
			game.sfx(String(Weapons.by_id(gid)["sound"]), clampf(-6.0 - n.global_position.distance_to(yp) * 0.3, -16.0, -6.0), randf_range(0.95, 1.05))
			game.fx.spark_burst(from + (tp - from).normalized() * 0.7, (tp - from).normalized(), 2, 4.0)
			if game.gunplay._clear(from, tp) and randf() < clampf(0.6 - td * 0.012, 0.18, 0.6):
				game.gunplay._tracer(from, tp)
				game.gunplay._hit_officer(tgt, float(SHOT_DMG.get(gid, 22.0)) * randf_range(0.8, 1.15), (tp - from).normalized(), tp)
			else:
				game.gunplay._tracer(from, tp + Vector3(randf_range(-1.2, 1.2), randf_range(-0.3, 0.8), randf_range(-1.2, 1.2)))

## Out of their car: a body of their own beside it, their gun in hand.
func _out(d: Dictionary) -> void:
	var c: Node3D = d["car"]
	var who := int(d["who"])
	var n := CharacterBody3D.new()
	n.collision_layer = LAYER
	n.collision_mask = 1 | 2 | 4 | 16
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	n.add_child(cs)
	var av := Avatar.new()
	n.add_child(av)
	av.setup(String(LOOKS[who % LOOKS.size()]), "", game.toon)
	av.hold(Weapons.by_id(String(GUNS[who % GUNS.size()])), game.toon)
	add_child(n)
	var side: Vector3 = -c.global_transform.basis.x * 1.8
	var p: Vector3 = c.global_position + side
	n.global_position = Vector3(p.x, game.island.height_at(p.x, p.z) + 0.1, p.z)
	# (they hold up here: the car waits, parked)
	d["parked_for_fight"] = true
	list.append({"who": who, "node": n, "av": av, "hp": HP, "cool": randf_range(0.4, 1.0), "car": c, "down": false, "slot": list.size()})

func _of(who: int) -> Dictionary:
	for a in list:
		if int(a["who"]) == who:
			return a
	return {}

## An officer's shot lands on one of them.
func hurt(a: Dictionary, dmg: float, from: Vector3) -> void:
	if a["down"]:
		return
	a["hp"] = float(a["hp"]) - dmg
	var n: Node3D = a["node"]
	var d: Vector3 = (n.global_position - from)
	d.y = 0.0
	d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	var chest := n.global_position + Vector3(0, 1.1, 0)
	game.fx.blood(chest, d, 14, 5.0)
	(a["av"] as Avatar).wound(chest, d)
	(a["av"] as Avatar).hit(chest, d, 1.0)
	if float(a["hp"]) <= 0.0:
		a["down"] = true
		(a["av"] as Avatar).go_limp(self, Vector3.ZERO, d * 3.0 + Vector3(0, 0.5, 0))
		game.ui.toast("%s is down!" % String(game.crew.ROSTER[int(a["who"])]["name"]), "heart", Color("ff4f6b"), Color.WHITE, 2.0)

## Back in your car: they get back in theirs (the ones who went down too: patched up) and drive on.
func _all_back() -> void:
	for a in list:
		if is_instance_valid(a["node"]):
			(a["node"] as Node).queue_free()
	list.clear()
	for d in game.crew.drivers:
		d.erase("parked_for_fight")

func clear() -> void:
	_all_back()
