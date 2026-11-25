extends Node3D
## Guns on foot: your gun in your hand, firing (hitscan, auto-aimed at the nearest person or officer in
## front of you, or straight down the camera if there's no one), reloading; your health; the police getting
## out of their cars to come at you on foot when you're wanted and not in a car; WASTED.
## main.gd owns one and calls tick() while you're on foot.

const Weapons := preload("res://scripts/game/weapons.gd")
const Avatar := preload("res://scripts/game/avatar.gd")
const MAX_HP := 100.0
const REGEN := 2.0              # health back a second, out of a fight
const OFFICER_HP := 60.0
const OFFICER_SHOT := 9.0       # what one of their bullets does to you
const OFFICERS_MAX := 6
# (the Kenney rig's arms are straight out sideways at rest, the right one along its bone's -X, and posed by
# turning at the shoulder: the fist is at the far end, the barrel carries on the way the arm points)
const HAND_AT := Vector3(-0.29, -0.01, 0.0)
const HAND_YAW := PI * 0.5

var game: Node
var hp := MAX_HP
var weapon: Dictionary = {}
var look := 0
var ammo := {}                  # weapon id -> rounds left in the magazine
var cool := 0.0                 # till the next shot
var reload_t := 0.0             # reloading (s left)
var hurt_t := 0.0               # since you last took a hit (no regen in a fight)
var gun_node: MeshInstance3D
var officers: Array = []        # {node: CharacterBody3D, av: Avatar, hp, cool, unit, dead_t}
var flash: OmniLight3D
var target: Node3D = null       # what the auto-aim's on (for the HUD marker)
var target_pos := Vector3.INF
var kills := {"people": 0, "police": 0}

func setup(g: Node) -> void:
	game = g
	flash = OmniLight3D.new()
	flash.light_color = Color(1.0, 0.75, 0.4)
	flash.omni_range = 5.0
	flash.light_energy = 0.0
	flash.shadow_enabled = false
	add_child(flash)

## The gun you've picked (save: "gun", its look in "gun_look"), in your character's hand.
func equip() -> void:
	var s: Dictionary = game.save.data
	weapon = Weapons.by_id(String(s.get("gun", "pistol")))
	if not (weapon["id"] in s.get("guns", ["pistol"])):
		weapon = Weapons.LIST[0]
	look = int((s.get("gun_look", {}) as Dictionary).get(String(weapon["id"]), 0))
	if not ammo.has(weapon["id"]):
		ammo[weapon["id"]] = int(weapon["mag"])
	reload_t = 0.0
	if gun_node and is_instance_valid(gun_node):
		gun_node.queue_free()
	gun_node = null
	var av: Avatar = game.foot.avatar if game.foot else null
	if av == null or av.skel == null:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = "arm-right"
	av.skel.add_child(ba)
	gun_node = MeshInstance3D.new()
	gun_node.mesh = Weapons.mesh(weapon, look)
	gun_node.material_override = game.toon
	gun_node.transform = hand_xf(weapon)
	ba.add_child(gun_node)

## Where a gun sits on the right arm bone (in the model's own units: the avatar's scaled 2.3x). Tuned by eye
## in the garage's Guns tab: grip in the fist, barrel out along the arm.
static func hand_xf(w: Dictionary) -> Transform3D:
	var k: float = float(w["scale"]) / Avatar.SCALE
	return Transform3D(Basis(Vector3.UP, HAND_YAW).scaled(Vector3.ONE * k), HAND_AT)

## Next gun you own (the swap button).
func cycle() -> void:
	var s: Dictionary = game.save.data
	var owned: Array = s.get("guns", ["pistol"])
	var ids: Array = []
	for w in Weapons.LIST:
		if w["id"] in owned:
			ids.append(w["id"])
	var i := ids.find(String(weapon.get("id", "pistol")))
	s["gun"] = ids[(i + 1) % ids.size()]
	equip()
	game.ui.popup_text(String(weapon["name"]))
	game.sfx("reload", -10.0, 1.3)

func ammo_text() -> String:
	if weapon.is_empty():
		return ""
	if reload_t > 0.0:
		return "reloading"
	return "%d / %d" % [int(ammo.get(weapon["id"], 0)), int(weapon["mag"])]

## Every frame on foot: firing (fire held), aiming, officers, health.
func tick(dt: float, fire: bool, reload: bool) -> void:
	var you: CharacterBody3D = game.foot
	cool -= dt
	hurt_t += dt
	flash.light_energy = maxf(0.0, flash.light_energy - dt * 30.0)
	if hurt_t > 5.0:
		hp = minf(MAX_HP, hp + REGEN * dt)
	_pick_target(you)
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			ammo[weapon["id"]] = int(weapon["mag"])
	elif reload and int(ammo.get(weapon["id"], 0)) < int(weapon["mag"]):
		_reload()
	if fire and reload_t <= 0.0 and cool <= 0.0:
		if int(ammo.get(weapon["id"], 0)) <= 0:
			_reload()
		else:
			_fire(you)
	# the avatar: gun up (two hands for the long ones), and turned to what you're shooting at
	var av: Avatar = you.avatar
	var moving := Vector3(you.velocity.x, 0, you.velocity.z).length() > 0.5
	if fire or cool > -0.6:
		if target_pos != Vector3.INF:
			var to := target_pos - you.global_position
			you.facing = lerp_angle(you.facing, atan2(-to.x, -to.z), 1.0 - exp(-dt * 18.0))
		else:
			you.facing = lerp_angle(you.facing, game.foot_yaw + game.look_yaw, 1.0 - exp(-dt * 18.0))
		you.aiming = 0.35
		if not moving:
			av.play("holding-both-shoot" if weapon["both"] else "holding-right-shoot", 1.0, 0.08)
	_officers_tick(dt, you)

func _reload() -> void:
	if reload_t > 0.0:
		return
	reload_t = float(weapon["reload"])
	game.sfx("reload", -6.0)

## The nearest person or officer in front (a cone along where you'd fire), in range and in sight.
func _pick_target(you: CharacterBody3D) -> void:
	target = null
	target_pos = Vector3.INF
	var from := you.global_position + Vector3(0, 1.2, 0)
	var aim_yaw: float = game.foot_yaw + game.look_yaw
	var fwd := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
	var rng: float = weapon.get("range", 60.0)
	var best := INF
	var cands: Array = []
	for o in officers:
		if float(o["hp"]) > 0.0:
			cands.append([(o["node"] as Node3D).global_position + Vector3(0, 1.0, 0), o["node"], 0.7])
	for pr in game.island.people.list:
		if pr["gone"] or pr.get("down", false):
			continue
		cands.append([(pr["pos"] as Vector3) + Vector3(0, 0.9, 0), pr, 1.0])
	for c in cands:
		var p: Vector3 = c[0]
		var to := p - from
		var d := to.length()
		if d > rng or d < 0.5:
			continue
		var ang := fwd.angle_to(Vector3(to.x, 0, to.z))
		if ang > 0.6:
			continue
		var score := d * float(c[2]) * (1.0 + ang * 2.5)
		if score < best and _clear(from, p):
			best = score
			target_pos = p
			target = c[1] if c[1] is Node3D else null
			if not (c[1] is Node3D):
				target_pos = p

func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return game.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _fire(you: CharacterBody3D) -> void:
	cool = 1.0 / float(weapon["rate"])
	ammo[weapon["id"]] = int(ammo[weapon["id"]]) - 1
	# the shot goes from your chest (clear of the ground and anything at your feet); the flash and the
	# tracer start at the muzzle
	var muzzle: Vector3 = gun_node.global_transform * Vector3(0, 0.03, -0.3) if gun_node else you.global_position + Vector3(0, 1.3, 0)
	var y0: float = you.facing
	var chest := you.global_position + Vector3(0, 1.25, 0) + Vector3(-sin(y0), 0, -cos(y0)) * 0.45
	var aim_dir: Vector3
	if target_pos != Vector3.INF:
		aim_dir = (target_pos - chest).normalized()
	else:
		var y: float = game.foot_yaw + game.look_yaw
		aim_dir = Vector3(-sin(y), -0.03, -cos(y)).normalized()
	game.sfx(String(weapon["sound"]), -2.0, randf_range(0.95, 1.05))
	flash.global_position = muzzle
	flash.light_energy = 3.0
	game.fx.spark_burst(muzzle, aim_dir, 4, 3.0)
	game.shake = maxf(game.shake, 0.08 if not weapon["both"] else 0.12)
	for k in int(weapon["pellets"]):
		var sp: float = weapon["spread"]
		var d := (aim_dir + Vector3(randf_range(-sp, sp), randf_range(-sp, sp) * 0.6, randf_range(-sp, sp))).normalized()
		_ray(chest, d, float(weapon["range"]), float(weapon["dmg"]), you, muzzle)
	# shots fired where anyone can hear: people scatter, and the police get a call
	game.island.people.panic(you.global_position, 40.0)
	if not game.police.wanted():
		game.police.start(1.0, "Shots fired")
	else:
		game.police.heat_pts += 0.02

## One bullet: what it hits first (an officer, a person, a car, the world).
func _ray(from: Vector3, d: Vector3, rng: float, dmg: float, you: Node3D, muzzle: Vector3) -> void:
	var to := from + d * rng
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 16 | 32 | 256)
	q.exclude = [you.get_rid(), game.car.get_rid()]       # (not your own car, parked behind you)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = hit["position"] if not hit.is_empty() else to
	var seg := end - from
	# people aren't physics bodies: the nearest one along the shot, before whatever it hit
	var best_pr := {}
	var best_t := seg.length()
	for pr in game.island.people.list:
		if pr["gone"] or pr.get("down", false):
			continue
		var c: Vector3 = (pr["pos"] as Vector3) + Vector3(0, 0.85, 0)
		var t := (c - from).dot(d)
		if t < 0.3 or t > best_t:
			continue
		if (from + d * t).distance_to(c) < 0.55:
			best_t = t
			best_pr = pr
	if not best_pr.is_empty():
		_hit_person(best_pr, d)
		_tracer(muzzle, from + d * best_t)
		return
	_tracer(muzzle, end)
	if hit.is_empty():
		return
	var col: Object = hit["collider"]
	if game.args.has("gundebug"):
		print("RAY hit ", (col as Node).name if col is Node else col, " layer ", (col as CollisionObject3D).collision_layer if col is CollisionObject3D else -1, " d=%.1f" % from.distance_to(end), " officers ", officers.map(func(o): return (o["node"] as Node).name))
	for o in officers:
		if o["node"] == col and float(o["hp"]) > 0.0:
			_hit_officer(o, dmg, d)
			return
	if col is RigidBody3D or col is AnimatableBody3D:
		game.fx.spark_burst(hit["position"], hit["normal"], 6, 4.0)
		game.sfx("knock_metal", -12.0, randf_range(1.2, 1.5))
		if col is RigidBody3D and col.has_method("apply_impulse"):
			(col as RigidBody3D).apply_impulse(d * dmg * 6.0, (hit["position"] as Vector3) - (col as Node3D).global_position)
	else:
		game.fx.puff(hit["position"], Color(0.8, 0.78, 0.72), 0.18, (hit["normal"] as Vector3) * 0.6, 0.4, 0.2)
		if randf() < 0.25:
			game.sfx("ricochet", -14.0, randf_range(0.9, 1.2))

func _tracer(a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.5, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	tw.tween_callback(mi.queue_free)

func _hit_person(pr: Dictionary, d: Vector3) -> void:
	var info: Dictionary = game.island.people.knock_down(pr)
	if info.is_empty():
		return
	var xf: Transform3D = info["xf"]
	game.ragdolls.spawn(int(info["v"]), xf, info["shoulders"], d * 6.0, game.foot)
	game.fx.blood(xf.origin + Vector3(0, 0.9, 0), d, 14, 4.0)
	game.fx.splat(xf.origin, 0.5)
	game.sfx("body_hit_%d" % randi_range(1, 3), -6.0, randf_range(0.95, 1.1))
	game.save.add_stat("people_hit", 1)
	kills["people"] += 1
	game.police.heat_pts += 0.35
	game.police.ped_hit(xf.origin)

func _hit_officer(o: Dictionary, dmg: float, d: Vector3) -> void:
	o["hp"] = float(o["hp"]) - dmg
	var n: CharacterBody3D = o["node"]
	game.fx.blood(n.global_position + Vector3(0, 1.0, 0), d, 8, 3.0)
	game.sfx("body_hit_%d" % randi_range(1, 3), -8.0, randf_range(1.0, 1.15))
	if float(o["hp"]) <= 0.0:
		(o["av"] as Avatar).play("die", 1.0, 0.05)
		o["dead_t"] = 0.0
		n.collision_layer = 0
		kills["police"] += 1
		game.save.add_stat("cops_down", 1)
		game.police.heat_pts += 0.6

## You take a hit.
func hurt(dmg: float, from: Vector3) -> void:
	if hp <= 0.0:
		return
	hp -= dmg
	hurt_t = 0.0
	game.ui.impact_flash(0.35)
	game.shake = maxf(game.shake, 0.18)
	if hp <= 0.0:
		hp = 0.0
		game.wasted()

# ------------------------------------------------------------------ the police on foot

## While you're wanted and on foot, police cars that get near you stop and the officers get out, run up and
## open fire; they get back in their cars if you drive off, or once it's over.
func _officers_tick(dt: float, you: CharacterBody3D) -> void:
	var police: Node = game.police
	var yp := you.global_position
	if police.wanted() and officers.size() < OFFICERS_MAX:
		for u in police.units:
			if u.get("foot_out", false) or not is_instance_valid(u["car"]) or u["state"] != "chase":
				continue
			var uc: Node3D = u["car"]
			if uc.global_position.distance_to(yp) < 26.0 and (uc as RigidBody3D).linear_velocity.length() < 8.0:
				u["foot_out"] = true
				for k in 2:
					if officers.size() < OFFICERS_MAX:
						_officer_out(u, k)
	for o in officers.duplicate():
		var n: CharacterBody3D = o["node"]
		var av: Avatar = o["av"]
		if float(o["hp"]) <= 0.0:
			o["dead_t"] = float(o["dead_t"]) + dt
			if float(o["dead_t"]) > 12.0 or n.global_position.distance_to(yp) > 140.0:
				officers.erase(o)
				n.queue_free()
			continue
		if not police.wanted() or not game.on_foot:
			# it's over (or you drove off): back to the car and away
			officers.erase(o)
			n.queue_free()
			continue
		var to := yp - n.global_position
		to.y = 0.0
		var d := to.length()
		var want := Vector3.ZERO
		if d > 9.0:
			want = to.normalized() * 4.4
			av.play("sprint", 1.0)
		else:
			av.play("holding-right-shoot", 1.0)
		n.velocity.x = want.x
		n.velocity.z = want.z
		n.velocity.y = 0.0 if n.is_on_floor() else n.velocity.y - 16.0 * dt
		n.move_and_slide()
		av.rotation.y = atan2(-to.x, -to.z) + PI
		o["cool"] = float(o["cool"]) - dt
		if d < 30.0 and float(o["cool"]) <= 0.0:
			o["cool"] = randf_range(1.0, 1.7)
			var from := n.global_position + Vector3(0, 1.3, 0)
			var aim := yp + Vector3(0, 1.0, 0)
			game.sfx("shot_pistol", clampf(-4.0 - d * 0.25, -14.0, -4.0), randf_range(0.9, 1.0))
			if _clear(from, aim):
				var miss := aim + Vector3(randf_range(-1.2, 1.2), randf_range(-0.4, 0.6), randf_range(-1.2, 1.2))
				var chance := clampf(0.6 - d * 0.02 - (0.15 if Vector3(you.velocity.x, 0, you.velocity.z).length() > 4.0 else 0.0), 0.12, 0.6)
				if randf() < chance:
					_tracer(from, aim)
					hurt(OFFICER_SHOT, from)
				else:
					_tracer(from, miss)

func _officer_out(u: Dictionary, k: int) -> void:
	var uc: Node3D = u["car"]
	var side: Vector3 = uc.global_transform.basis.x * (1.6 if k == 0 else -1.6)
	var n := CharacterBody3D.new()
	n.collision_layer = 256
	n.collision_mask = 1 | 2 | 4 | 16
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	n.add_child(cs)
	var av := Avatar.new()
	n.add_child(av)
	av.setup("male-c", "", game.toon)        # (the one in the police uniform)
	# their pistol
	if av.skel:
		var ba := BoneAttachment3D.new()
		ba.bone_name = "arm-right"
		av.skel.add_child(ba)
		var g := MeshInstance3D.new()
		g.mesh = Weapons.mesh(Weapons.LIST[0], 0)
		g.material_override = game.toon
		g.transform = hand_xf(Weapons.LIST[0])
		ba.add_child(g)
	add_child(n)
	var p := uc.global_position + side
	n.global_position = Vector3(p.x, game.island.height_at(p.x, p.z) + 0.1, p.z)
	officers.append({"node": n, "av": av, "hp": OFFICER_HP, "cool": randf_range(0.8, 1.6), "unit": u, "dead_t": 0.0})

## Officers gone (you're back in a car, or it's over); the cars they came in pick up the chase again.
func clear_officers() -> void:
	for o in officers:
		(o["node"] as Node).queue_free()
	officers.clear()
