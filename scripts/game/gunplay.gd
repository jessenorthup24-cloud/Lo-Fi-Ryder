extends Node3D
## Guns on foot. Holding FIRE (or the AIM toggle) puts you in aim: the camera comes in over your right
## shoulder, a reticle sits in the middle of the screen, and it locks on to the nearest person or officer
## near it (a red ring round them, the camera drifting onto them). Every gun is held in two hands and points
## where you're aiming. Shots land where the reticle is (or on the one you're locked on to): hit markers,
## blood, sparks, bullet holes; people and officers fall as ragdolls. Cars take damage, smoke, catch fire and
## blow up. Reloads lower the gun and swap the magazine. Officers get out and fight when you're wanted on foot.

const Weapons := preload("res://scripts/game/weapons.gd")
const Avatar := preload("res://scripts/game/avatar.gd")
const MAX_HP := 100.0
const REGEN := 2.0              # health back a second, out of a fight
const OFFICER_HP := 100.0
const PERSON_HP := 100.0
const OFFICER_SHOT := 9.0       # what one of their bullets does to you
const OFFICERS_MAX := 6
const OFFICER_V := 7            # the police officer, in the people's characters (models.gd CHARS)
const CAR_HP := 450.0           # damage to blow a car up (a rifle: about 15 shots)
const LOCK_ANG := 0.32          # how far off the reticle a target can be and still lock (rad)
const BLAST_R := 8.0

var game: Node
var hp := MAX_HP
var weapon: Dictionary = {}
var look := 0
var ammo := {}                  # weapon id -> rounds left in the magazine
var cool := -1.0                # till the next shot
var reload_t := 0.0             # reloading (s left)
var hurt_t := 0.0               # since you last took a hit (no regen in a fight)
var gun_node: MeshInstance3D
var officers: Array = []        # {node: CharacterBody3D, av: Avatar, hp, cool, unit, dead}
var flash: OmniLight3D
var aiming := false             # in aim (the shoulder camera, the reticle)
var aim_k := 0.0                # eased 0..1 for the camera
var shot_t := 0.0               # a few seconds after you last fired (the police shoot it out rather than cuff you)
var lock: Variant = null        # what's locked on: an officer dict, a person dict, or null
var lock_pos := Vector3.INF     # where on them
var aim_point := Vector3.INF    # where a shot would land
var kills := {"people": 0, "police": 0, "cars": 0}
var car_hp := {}                # instance id of a car body -> hp left
var burning: Array = []         # {node, t}
var holes: Array = []           # bullet holes (oldest first)
var _hole_mat: StandardMaterial3D
var _trace_mat: StandardMaterial3D
var _burnt_mat: StandardMaterial3D
var _recoil := 0.0
var _mag_swapped := false
var dying := false              # you're down (a ragdoll), WASTED on its way
var holstered := false          # the gun's put away (the swap button cycles to it; FIRE or AIM draws again)
var manual_t := 0.0             # you're steering the aim with the FIRE finger: lock-on doesn't drag the view

func setup(g: Node) -> void:
	game = g
	flash = OmniLight3D.new()
	flash.light_color = Color(1.0, 0.75, 0.4)
	flash.omni_range = 6.0
	flash.light_energy = 0.0
	add_child(flash)
	_hole_mat = StandardMaterial3D.new()
	_hole_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hole_mat.albedo_color = Color(0.06, 0.05, 0.05)
	_trace_mat = StandardMaterial3D.new()
	_trace_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trace_mat.albedo_color = Color(1.0, 0.9, 0.55)
	_trace_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_burnt_mat = StandardMaterial3D.new()
	_burnt_mat.albedo_color = Color(0.09, 0.085, 0.08)
	_burnt_mat.roughness = 1.0

# ------------------------------------------------------------------ the gun in your hands

## The gun you've picked (save: "gun", its look in "gun_look"), in your character's right hand.
func equip() -> void:
	var s: Dictionary = game.save.data
	var gid := String(s.get("gun", "pistol"))
	if not (gid in s.get("guns", ["pistol"])):
		gid = "pistol"
	weapon = Weapons.loadout(game.save, gid)          # (as you've built it: its parts change how it shoots)
	if not ammo.has(weapon["id"]) or int(ammo[weapon["id"]]) > int(weapon["mag"]):
		ammo[weapon["id"]] = int(weapon["mag"])
	reload_t = 0.0
	gun_node = null
	var av: Avatar = game.foot.avatar if game.foot else null
	if av == null or av.skel == null:
		return
	if holstered:
		av.hold({}, game.toon)
		return
	av.hold(weapon, game.toon)
	gun_node = av.gun

## A gun off the weapon wheel ("": put it away).
func select(id: String) -> void:
	if id == "":
		if holstered:
			return
		holstered = true
	else:
		if not holstered and id == String(weapon.get("id", "")):
			return
		holstered = false
		game.save.data["gun"] = id
	reload_t = 0.0
	equip()
	game.ui.popup_text("Holstered" if holstered else String(weapon["name"]))
	game.sfx("mag_in", -8.0, 1.2 if not holstered else 0.8)

## Next gun you own (the swap key on a keyboard).
func cycle() -> void:
	var s: Dictionary = game.save.data
	var owned: Array = s.get("guns", ["pistol"])
	var ids: Array = []
	for w in Weapons.LIST:
		if w["id"] in owned:
			ids.append(w["id"])
	var i := ids.find(String(weapon.get("id", "pistol")))
	# your guns in turn, then put away, then the first again
	if holstered:
		holstered = false
		s["gun"] = ids[0]
	elif i >= ids.size() - 1:
		holstered = true
	else:
		s["gun"] = ids[i + 1]
	reload_t = 0.0
	equip()
	game.ui.popup_text("Holstered" if holstered else String(weapon["name"]))
	game.sfx("mag_in", -8.0, 1.2 if not holstered else 0.8)

func ammo_text() -> String:
	if weapon.is_empty():
		return ""
	if holstered:
		return "put away"
	if reload_t > 0.0:
		return "reloading"
	return "%d / %d" % [int(ammo.get(weapon["id"], 0)), int(weapon["mag"])]

# ------------------------------------------------------------------ every frame

## fire_tap: the trigger's just pulled this frame; fire_held: it's down (an automatic fires as fast as it
## goes; the rest fire on each tap, or held, a bit slower); aim_on: the AIM toggle; reload: the reload key.
func tick(dt: float, fire_tap: bool, fire_held: bool, aim_on: bool, reload: bool) -> void:
	var you: CharacterBody3D = game.foot
	if dying:
		aim_k = move_toward(aim_k, 0.0, dt * 4.0)      # (the camera pulls back to watch you fall)
		lock_pos = Vector3.INF
		return
	manual_t = maxf(0.0, manual_t - dt)
	shot_t = maxf(0.0, shot_t - dt)
	if holstered:
		# put away: hands free, walking about like anyone. FIRE or AIM draws it (a moment before it'll fire)
		aiming = false
		aim_k = move_toward(aim_k, 0.0, dt * 6.0)
		lock_pos = Vector3.INF
		if fire_tap or (aim_on and not aiming):
			holstered = false
			equip()
			cool = 0.3
			game.sfx("mag_in", -6.0, 1.3)
		else:
			(you.avatar as Avatar).aim_at(Vector3.INF, true, dt)
			_officers_tick(dt, you)
			_burn_tick(dt)
			return
	var semi_wait: float = 0.55 / float(weapon["rate"])
	var fire: bool = fire_held if bool(weapon.get("auto", false)) else (fire_tap or (fire_held and cool <= -semi_wait))
	cool -= dt
	hurt_t += dt
	flash.light_energy = maxf(0.0, flash.light_energy - dt * 30.0)
	_recoil = move_toward(_recoil, 0.0, dt * (9.0 if bool(weapon.get("auto", false)) else 5.0))
	if hurt_t > 5.0:
		hp = minf(MAX_HP, hp + REGEN * dt)
	aiming = aim_on or fire_held or cool > -0.5
	aim_k = move_toward(aim_k, (0.35 if reload_t > 0.0 else 1.0) if aiming else 0.0, dt * 6.0)      # (reloading: back a bit, the gun out of your face)
	_find_aim(you)
	# reloading: the gun comes down, the magazine out (half way) and back in, the gun back up
	if reload_t > 0.0:
		reload_t -= dt
		var r: float = 1.0 - reload_t / float(weapon["reload"])
		if r > 0.45 and not _mag_swapped:
			_mag_swapped = true
			game.sfx("mag_out", -6.0)
		if reload_t <= 0.0:
			ammo[weapon["id"]] = int(weapon["mag"])
			game.sfx("mag_in", -4.0)
	elif reload and int(ammo.get(weapon["id"], 0)) < int(weapon["mag"]):
		_reload()
	if fire and reload_t <= 0.0 and cool <= 0.0:
		if int(ammo.get(weapon["id"], 0)) <= 0:
			game.sfx("dry_fire", -6.0)
			cool = 0.25
			_reload()
		else:
			_fire(you)
	_pose(you, dt)
	_officers_tick(dt, you)
	_burn_tick(dt)

func _reload() -> void:
	if reload_t > 0.0:
		return
	reload_t = float(weapon["reload"])
	_mag_swapped = false
	game.sfx("reload", -10.0, 1.1)

## The body: facing where you aim, both hands on the gun and the gun pointing at it; lowered, tipped over
## and the magazine swapped while reloading; carried at the low ready otherwise.
func _pose(you: CharacterBody3D, dt: float) -> void:
	var av: Avatar = you.avatar
	if av.lock_t > 0.0 or you.get("down_t") > 0.0 or you.get("scripted"):
		# (a one-off move playing, or knocked flat: the arms are the animation's)
		av.aim_at(Vector3.INF, true, dt * 4.0)
		return
	var moving := Vector3(you.velocity.x, 0, you.velocity.z).length() > 0.5
	var y: float = you.facing
	var ahead := Vector3(-sin(y), 0, -cos(y))
	var right := Vector3(cos(y), 0, -sin(y))
	var at := Vector3.INF          # where the arms (and the gun) point
	var extra := Basis()           # recoil, the reload tip
	if reload_t > 0.0:
		# down and across the chest, tipped over on its side while the magazine's swapped
		at = you.global_position + Vector3(0, 0.6, 0) + ahead * 1.5 - right * 0.5
		var r: float = 1.0 - reload_t / float(weapon["reload"])
		var tip := sin(clampf(r, 0.0, 1.0) * PI)
		extra = Basis(Vector3.FORWARD, tip * 1.2) * Basis(Vector3.RIGHT, -tip * 0.3)
	elif aiming and aim_point != Vector3.INF:
		var to := aim_point - you.global_position
		# a long gun's shouldered: the body side-on (left shoulder toward them), the stock at the right shoulder
		var blade := 0.0            # (the long gun clips stand side-on themselves)
		you.facing = lerp_angle(you.facing, atan2(-to.x, -to.z) + blade, 1.0 - exp(-dt * 20.0))
		you.aiming = 0.3
		at = aim_point
		extra = Basis(Vector3.RIGHT, _recoil * (0.18 if bool(weapon.get("auto", false)) else 0.4))
	# (not aiming, stood or moving: the clips carry the gun themselves; the arms are theirs)
	av.aim_at(at, true, dt)
	if not moving:
		av.play("holding-both" if aiming else "idle", 1.0, 0.2)
	# (the avatar turns the gun onto where the arms point; this is on top: the kick, the reload's tip)
	av.gun_extra = extra
	av.gun_nudge = Vector3(_recoil * 0.06, 0, 0)

## Where you're aiming: locked on to whoever's nearest the reticle (and in sight), or wherever the reticle's
## ray from the camera lands.
func _find_aim(you: CharacterBody3D) -> void:
	var cam: Camera3D = game.cam
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var head := you.global_position + Vector3(0, 0.85 if you.get("crouch") else 1.3, 0)
	var rng: float = weapon.get("range", 60.0)
	lock = null
	lock_pos = Vector3.INF
	var best := LOCK_ANG
	if aiming:
		var cands: Array = []
		for o in officers:
			if not o["dead"]:
				cands.append([(o["node"] as Node3D).global_position + Vector3(0, 1.0, 0), o, true])
		for pr in game.island.people.list:
			if not pr["gone"] and not pr.get("down", false):
				cands.append([(pr["pos"] as Vector3) + Vector3(0, 0.85, 0), pr, false])
		for c in cands:
			var p: Vector3 = c[0]
			if p.distance_to(head) > rng:
				continue
			var ang := fwd.angle_to(p - from)
			# officers win ties: they're the ones shooting back
			var score := ang * (0.6 if c[2] else 1.0)
			if score < best and _clear(head, p):
				best = score
				lock = c[1]
				lock_pos = p
	if lock_pos != Vector3.INF:
		aim_point = lock_pos
		return
	# free aim: down the middle of the screen, from the camera, to whatever it meets (or far off)
	var q := PhysicsRayQueryParameters3D.create(from + fwd * 2.0, from + fwd * rng, 1 | 2 | 16 | 256)
	q.exclude = [you.get_rid(), game.car.get_rid()]
	var h: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	aim_point = h["position"] if not h.is_empty() else from + fwd * rng

func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return game.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

# ------------------------------------------------------------------ firing

func _fire(you: CharacterBody3D) -> void:
	shot_t = 6.0
	cool = 1.0 / float(weapon["rate"])
	ammo[weapon["id"]] = int(ammo[weapon["id"]]) - 1
	var muzzle: Vector3 = you.global_position + Vector3(0, 0.85 if you.get("crouch") else 1.3, 0)
	if gun_node and is_instance_valid(gun_node):
		muzzle = gun_node.global_transform * (gun_node.get_meta("muzzle", Vector3.ZERO) as Vector3)
	# the shot goes from your chest (clear of your feet and the ground) to the aim point
	var chest := you.global_position + Vector3(0, 1.25, 0)
	var aim_dir := (aim_point - chest).normalized()
	var quiet: bool = weapon.get("quiet", false)
	# (suppressed: a cough, not a crack, and no flash to speak of)
	game.sfx(String(weapon["sound"]), -12.0 if quiet else -1.0, randf_range(1.25, 1.35) if quiet else randf_range(0.95, 1.05))
	flash.global_position = muzzle
	flash.light_energy = 0.6 if quiet else 4.0
	if not quiet:
		_muzzle_flash(muzzle, aim_dir)
	# the kick: a sharp one for the single shots, a small steady one for an automatic (it'd bounce about)
	var auto: bool = weapon.get("auto", false)
	var rk: float = float(weapon.get("recoil", 1.0))      # (a brake, a stock, a foregrip: less kick)
	_recoil = minf(1.0, _recoil + (0.35 if auto else 1.0) * rk)
	var punch: float = float(weapon["dmg"]) * float(weapon["pellets"])
	var kick: float = (clampf(punch / 2400.0, 0.004, 0.02) if auto else clampf(punch / 900.0, 0.012, 0.11)) * rk
	game.aim_kick = minf(game.aim_kick + kick, 0.09 if auto else 0.2)
	game.shake = maxf(game.shake, 0.015 if auto else 0.04 + kick * 0.5)
	# a buzz in the hands with every shot: a tap for the SMG, a thump for the shotgun and the sniper
	game.buzz(int(clampf(8.0 + punch * 0.4, 10.0, 55.0)), clampf(0.25 + punch / 140.0, 0.3, 1.0))
	var hit_any := false
	var killed := false
	for k in int(weapon["pellets"]):
		var sp: float = float(weapon["spread"]) * (0.5 if lock != null else 1.0) * (float(weapon.get("hip", 1.0)) if aim_k < 0.5 else 1.0)
		var d := (aim_dir + Vector3(randf_range(-sp, sp), randf_range(-sp, sp) * 0.6, randf_range(-sp, sp))).normalized()
		var r: int = _ray(chest, d, float(weapon["range"]), float(weapon["dmg"]) * randf_range(0.85, 1.15), you, muzzle)
		hit_any = hit_any or r > 0
		killed = killed or r > 1
	if hit_any:
		# (no marker on the screen: the blood and the body tell you)
		game.sfx("kill_ding" if killed else "hit_tick", -10.0 if killed else -14.0)
	# shots fired where anyone can hear: people scatter, and the police get a call (suppressed: only those
	# close by notice, and the police mostly don't hear about it)
	game.island.people.panic(you.global_position, 12.0 if quiet else 40.0)
	if not game.police.wanted() and (not quiet or randf() < 0.08):
		game.police.start(1.0, "Shots fired")
	else:
		game.police.heat_pts += 0.02

## One bullet: what it hits first. Returns 0 (nothing alive), 1 (hit someone or a car), 2 (killed).
func _ray(from: Vector3, d: Vector3, rng: float, dmg: float, you: Node3D, muzzle: Vector3) -> int:
	var to := from + d * rng
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 16 | 32 | 256)
	q.exclude = [you.get_rid(), game.car.get_rid()]       # (not your own car, parked behind you)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = hit["position"] if not hit.is_empty() else to
	# people aren't physics bodies: the nearest one along the shot, before whatever it hit
	var best_pr := {}
	var best_t := from.distance_to(end)
	for pr in game.island.people.list:
		if pr["gone"] or pr.get("down", false):
			continue
		var c: Vector3 = (pr["pos"] as Vector3) + Vector3(0, 0.85, 0)
		var t := (c - from).dot(d)
		if t < 0.3 or t > best_t:
			continue
		if (from + d * t).distance_to(c) < 0.6:
			best_t = t
			best_pr = pr
	# the police helicopter (no body to hit: near enough the line counts)
	var hl = game.police.heli
	if best_pr.is_empty() and hl != null and is_instance_valid(hl) and not hl.downed:
		var hc: Vector3 = hl.global_position
		var ht := (hc - from).dot(d)
		if ht > 0.0 and ht < rng and ht <= from.distance_to(end) + 4.0 and (from + d * ht).distance_to(hc) < 4.5:
			_tracer(muzzle, from + d * ht)
			game.fx.spark_burst(from + d * ht, -d, 6, 6.0)
			var down: bool = hl.hit(dmg)
			if down:
				game.ui.popup_text("Helicopter down!")
				game.police.heat_pts += 0.6
				game.save.add_stat("helis_down", 1)
			return 2 if down else 1
	if not best_pr.is_empty():
		_tracer(muzzle, from + d * best_t)
		return _hit_person(best_pr, d, dmg, from + d * best_t)
	_tracer(muzzle, end)
	if hit.is_empty():
		return 0
	var col: Object = hit["collider"]
	var hp_: Vector3 = hit["position"]
	var nrm: Vector3 = hit["normal"]
	for o in officers:
		if o["node"] == col and not o["dead"]:
			return _hit_officer(o, dmg, d, hp_)
	var car_node := _car_of(col)
	if car_node != null:
		game.fx.spark_burst(hp_, nrm, 8, 5.0)
		game.sfx("bullet_metal", -10.0, randf_range(0.9, 1.15))
		_hole(hp_, nrm, col as Node3D)
		_damage_car(car_node, dmg)
		if col is RigidBody3D and not (col as RigidBody3D).freeze:
			(col as RigidBody3D).apply_impulse(d * dmg * 4.0, hp_ - (col as Node3D).global_position)
		return 1
	# the world: a puff of dust, a chip, a hole
	game.fx.puff(hp_, Color(0.78, 0.76, 0.7), 0.22, nrm * 0.9, 0.5, 0.3)
	game.fx.spark_burst(hp_, nrm, 3, 2.5)
	_hole(hp_, nrm, null)
	if randf() < 0.2:
		game.sfx("ricochet", -14.0, randf_range(0.9, 1.2))
	return 0

## A bullet hole on a surface (stuck to a car if it hit one); forty at most, the oldest go first.
func _hole(p: Vector3, n: Vector3, on: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.14, 0.14)
	mi.mesh = qm
	mi.material_override = _hole_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD
	var parent: Node3D = on if on != null and is_instance_valid(on) else self
	parent.add_child(mi)
	mi.global_transform = Transform3D(Basis.looking_at(-n, up), p + n * 0.012)
	holes.append(mi)
	if holes.size() > 40:
		var old: Variant = holes.pop_front()      # (it may have gone with the car it was on)
		if is_instance_valid(old):
			(old as Node).queue_free()

func _muzzle_flash(p: Vector3, d: Vector3) -> void:
	for k in 2:
		game.fx.puff(p + d * (0.1 + k * 0.12), Color(1.0, 0.85, 0.45) if k == 0 else Color(1.0, 0.6, 0.25), 0.16 - k * 0.04, d * 2.0, 0.07, 0.0)
	game.fx.spark_burst(p, d, 3, 6.0)

## A tracer: a thin bright streak along the shot, gone in a blink.
func _tracer(a: Vector3, b: Vector3) -> void:
	var len := a.distance_to(b)
	if len < 0.3:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.035, len)
	mi.mesh = bm
	var m := _trace_mat.duplicate() as StandardMaterial3D
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.FORWARD
	mi.global_transform = Transform3D(Basis.looking_at(b - a, up), (a + b) * 0.5)
	var tw := create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.09)
	tw.tween_callback(mi.queue_free)

# ------------------------------------------------------------------ people and officers

## A person shot: blood, and they run; out of health, they go down.
func _hit_person(pr: Dictionary, d: Vector3, dmg: float, at: Vector3) -> int:
	pr["hp"] = float(pr.get("hp", PERSON_HP)) - dmg
	if float(pr["hp"]) <= 0.0:
		_kill_person(pr, d, dmg)
		return 2
	game.fx.blood(at, d, 16, 5.5)
	game.sfx("body_hit_%d" % randi_range(1, 3), -6.0, randf_range(1.0, 1.15))
	game.island.people.flinch(pr, d)
	var pav = pr.get("live")
	if pav != null and is_instance_valid(pav):
		(pav as Avatar).wound(at, d)
		(pav as Avatar).hit(at, d, 1.0)
	game.island.people.panic(pr["pos"], 3.0)
	game.police.heat_pts += 0.1
	return 1

## A person goes down: a ragdoll knocked the way the bullet went.
func _kill_person(pr: Dictionary, d: Vector3, dmg: float) -> void:
	var info: Dictionary = game.island.people.knock_down(pr)
	if info.is_empty():
		return
	var xf: Transform3D = info["xf"]
	game.ragdolls.spawn(int(info["v"]), xf, info["shoulders"], d * clampf(dmg * 0.12, 3.0, 9.0), game.foot)
	_blood(xf.origin + Vector3(0, 0.9, 0), d)
	game.save.add_stat("people_hit", 1)
	kills["people"] += 1
	if randf() < 0.75:
		game.heist.drop_cash(xf.origin + d * 0.8, randi_range(3, 12) * 5)
	game.police.heat_pts += 0.35
	game.police.ped_hit(xf.origin)

func _blood(p: Vector3, d: Vector3) -> void:
	game.fx.blood(p, d, 26, 6.0)
	# a pool spreading out slowly under where they fell
	game.fx.splat(Vector3(p.x, game.island.height_at(p.x, p.z), p.z) + d * 0.7, randf_range(1.1, 1.5), 5.0)
	game.sfx("body_hit_%d" % randi_range(1, 3), -6.0, randf_range(0.95, 1.1))

func _hit_officer(o: Dictionary, dmg: float, d: Vector3, at: Vector3) -> int:
	o["hp"] = float(o["hp"]) - dmg
	var n: CharacterBody3D = o["node"]
	game.fx.blood(at, d, 16, 5.5)
	game.sfx("body_hit_%d" % randi_range(1, 3), -6.0, randf_range(0.95, 1.1))
	(o["av"] as Avatar).wound(at, d)
	if float(o["hp"]) > 0.0:
		# hit: knocked back a step or two, the part that's hit snapping away from the shot, off their aim
		# for a moment (they stagger, then come back up shooting)
		n.velocity += d * 4.5 + Vector3(0, 0.6, 0)
		(o["av"] as Avatar).hit(at, d, clampf(dmg / 30.0, 0.6, 1.4))
		o["cool"] = maxf(float(o["cool"]), 0.85)
		o["stagger"] = 0.45
		return 1
	_officer_down(o, d * clampf(dmg * 0.12, 3.5, 8.0) + Vector3(0, 0.8, 0))
	game.save.add_stat("cops_down", 1)
	kills["police"] += 1
	game.police.heat_pts += 0.6
	return 2

## An officer goes down: limp (a ragdoll of their own character), thrown the way the shot went; cleared
## away after a while.
func _officer_down(o: Dictionary, push: Vector3) -> void:
	o["dead"] = true
	if not is_instance_valid(o["node"]):
		return
	var n: CharacterBody3D = o["node"]
	_blood(n.global_position + Vector3(0, 1.0, 0), push.normalized())
	n.collision_layer = 0
	n.collision_mask = 0
	n.set_meta("down", true)
	game.heist.drop_cash(n.global_position + push.normalized() * 0.8, randi_range(8, 24) * 5)
	(o["av"] as Avatar).go_limp(self, n.velocity * 0.5, push)
	get_tree().create_timer(14.0).timeout.connect(func():
		if is_instance_valid(n):
			n.queue_free())

## You take a hit (from a point: the way it knocks you). Blood, a flinch, the screen flashes; out of
## health, you go limp (a ragdoll) and it's WASTED.
func hurt(dmg: float, from: Vector3) -> void:
	if hp <= 0.0 or game.foot == null:
		return
	hp -= dmg
	hurt_t = 0.0
	game.buzz(45, 0.85)
	var you: CharacterBody3D = game.foot
	var chest := you.global_position + Vector3(0, 1.1, 0)
	var d := (chest - from)
	d.y = 0.0
	d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	game.fx.blood(chest, d, 14, 4.0)
	game.sfx("body_hit_%d" % randi_range(1, 3), -5.0, randf_range(0.9, 1.0))
	(you.avatar as Avatar).flinch(d)
	game.ui.impact_flash(0.35)
	game.shake = maxf(game.shake, 0.18)
	if hp <= 0.0:
		hp = 0.0
		dying = true
		aiming = false
		reload_t = 0.0
		(you.avatar as Avatar).go_limp(self, you.velocity, d * clampf(dmg * 0.04, 1.5, 4.0) + Vector3(0, 0.6, 0))
		game.fx.splat(Vector3(chest.x, game.island.height_at(chest.x, chest.z), chest.z) + d * 0.8, 0.7)
		game.wasted()

## Where the camera looks while you're down: your body.
func dead_focus() -> Vector3:
	if game.foot == null:
		return Vector3.INF
	var av: Avatar = game.foot.avatar
	return av.limp.torso_pos() if av.limp else Vector3.INF

# ------------------------------------------------------------------ cars

## The car a collider belongs to (a traffic car, a police car, a parked car); null if it's not a car. A
## traffic car is always its own entry's "anim" body (it swaps to a loose rigid body when it's knocked).
func _car_of(col: Object) -> Node3D:
	if not (col is Node3D):
		return null
	var n: Node3D = col
	if n == game.car:
		return null
	for c in game.traffic.cars:
		if c["body"] == n or c["anim"] == n:
			return c["anim"]
	if n.has_meta("police"):
		return n
	for pk in game.parked:
		if pk["node"] == n:
			return n
	return null

func _traffic_of(n: Node3D) -> Dictionary:
	for c in game.traffic.cars:
		if c["anim"] == n:
			return c
	return {}

## Where a car is now (a knocked traffic car's moved on with its loose body).
func _car_body(n: Node3D) -> Node3D:
	var c := _traffic_of(n)
	return c["body"] if not c.is_empty() else n

func _damage_car(n: Node3D, dmg: float) -> void:
	var id := n.get_instance_id()
	if not car_hp.has(id):
		car_hp[id] = CAR_HP
	if float(car_hp[id]) <= 0.0:
		# a burnt-out traffic car comes back as a fresh one when traffic recycles it (its paint back on)
		var tc := _traffic_of(n)
		if tc.is_empty() or tc.has("mat0"):
			return
		car_hp[id] = CAR_HP
	car_hp[id] = float(car_hp[id]) - dmg
	var left: float = car_hp[id]
	var on_fire := false
	for b in burning:
		if b["node"] == n:
			on_fire = true
	if left <= 0.0:
		explode(n)
	elif left < CAR_HP * 0.35 and not on_fire:
		# on fire: it goes up a few seconds later, if nobody finishes it
		burning.append({"node": n, "t": 0.0})
		game.sfx("fire_loop", -10.0)
	elif left < CAR_HP * 0.7 and randf() < 0.3:
		game.fx.puff(_car_body(n).global_position + Vector3(0, 1.0, 0), Color(0.3, 0.3, 0.3), 0.5, Vector3(0, 1.5, 0), 1.2, 1.0)

func _burn_tick(dt: float) -> void:
	for b in burning.duplicate():
		if not is_instance_valid(b["node"]):
			burning.erase(b)
			continue
		var n: Node3D = b["node"]
		b["t"] = float(b["t"]) + dt
		var p := _car_body(n).global_position + Vector3(0, 1.0, 0)
		if randf() < dt * 14.0:
			game.fx.puff(p + Vector3(randf_range(-0.4, 0.4), 0.2, randf_range(-0.6, 0.6)), Color(1.0, 0.5, 0.15), 0.35, Vector3(0, 1.4, 0), 0.5, 1.2)
		if randf() < dt * 8.0:
			game.fx.puff(p + Vector3(0, 0.6, 0), Color(0.12, 0.11, 0.1), 0.6, Vector3(0, 2.0, 0), 1.6, 1.5)
		if b.get("shell", false):
			if float(b["t"]) > 9.0:
				burning.erase(b)      # (the wreck smoulders a while)
		elif float(b["t"]) > 5.0:
			burning.erase(b)
			explode(n)

## Boom: a fireball, a shove for everything near, people and officers down, you hurt if you're close;
## the car's left a burnt-out shell, thrown up in the air.
## A blast with nothing under it (the helicopter coming down): fire, smoke, the bang; anyone near is hurt.
func boom(p: Vector3) -> void:
	game.sfx("explosion", 3.0, randf_range(0.8, 0.95))
	flash.global_position = p
	flash.light_energy = 18.0
	for k in 18:
		var dv := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized()
		game.fx.puff(p + dv * 0.8, Color(1.0, randf_range(0.45, 0.7), 0.15), randf_range(1.4, 2.4), dv * randf_range(4.0, 9.0), randf_range(0.7, 1.1), 0.8)
	for k in 12:
		var dv2 := Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)).normalized()
		game.fx.puff(p + dv2, Color(0.1, 0.09, 0.09), randf_range(1.4, 2.4), dv2 * randf_range(1.5, 3.5), 3.0, 1.8)
	game.fx.spark_burst(p, Vector3.UP, 40, 14.0)
	var you: Vector3 = game.you().global_position
	game.shake = maxf(game.shake, 0.6 if you.distance_to(p) < 30.0 else 0.2)
	game.ui.impact_flash(0.45)
	if game.on_foot and you.distance_to(p) < BLAST_R * 1.3:
		hurt(80.0 * (1.0 - you.distance_to(p) / (BLAST_R * 1.3)), p)

func explode(n: Node3D) -> void:
	if not is_instance_valid(n):
		return
	car_hp[n.get_instance_id()] = -1.0
	for b in burning.duplicate():
		if b["node"] == n:
			burning.erase(b)
	var p := _car_body(n).global_position + Vector3(0, 0.8, 0)
	game.sfx("explosion", 2.0, randf_range(0.9, 1.05))
	flash.global_position = p
	flash.light_energy = 16.0
	for k in 14:
		var dv := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized()
		game.fx.puff(p + dv * 0.6, Color(1.0, randf_range(0.45, 0.7), 0.15), randf_range(1.0, 1.9), dv * randf_range(3.0, 7.0), randf_range(0.7, 1.1), 0.8)
	for k in 10:
		var dv2 := Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)).normalized()
		game.fx.puff(p + dv2, Color(0.1, 0.09, 0.09), randf_range(1.0, 1.8), dv2 * randf_range(1.5, 3.5), 2.4, 1.6)
	game.fx.spark_burst(p, Vector3.UP, 30, 12.0)
	var you_near: bool = game.on_foot and game.foot != null and game.foot.global_position.distance_to(p) < 25.0
	game.shake = maxf(game.shake, 0.6 if you_near else 0.25)
	game.ui.impact_flash(0.5)
	_shell(n)
	burning.append({"node": n, "t": 0.0, "shell": true})
	kills["cars"] += 1
	game.save.add_stat("cars_blown", 1)
	if game.police.wanted():
		game.police.heat_pts += 0.4
	else:
		game.police.start(1.0, "Explosion")
	# the blast: people and officers down, you hurt, other cars knocked about and damaged (so they go up too)
	for pr in game.island.people.list:
		if pr["gone"] or pr.get("down", false):
			continue
		if (pr["pos"] as Vector3).distance_to(p) < BLAST_R:
			_kill_person(pr, ((pr["pos"] as Vector3) - p + Vector3(0, 1.0, 0)).normalized(), 90.0)
	for o in officers.duplicate():
		if not o["dead"] and is_instance_valid(o["node"]) and (o["node"] as Node3D).global_position.distance_to(p) < BLAST_R:
			_officer_down(o, ((o["node"] as Node3D).global_position - p + Vector3(0, 1.5, 0)).normalized() * 10.0)
			kills["police"] += 1
	if game.on_foot and game.foot:
		var dy: float = game.foot.global_position.distance_to(p)
		if dy < BLAST_R:
			game.foot.velocity += (game.foot.global_position - p + Vector3(0, 2.0, 0)).normalized() * (10.0 - dy)
			hurt(90.0 * (1.0 - dy / BLAST_R), p)
	for c in game.traffic.cars:
		var cb: Node3D = c["body"]
		var dc := cb.global_position.distance_to(p)
		if c["anim"] != n and dc < BLAST_R:
			_damage_car(c["anim"], 120.0 * (1.0 - dc / BLAST_R))
			if int(c["mode"]) < game.traffic.KNOCKED:
				game.traffic.knock(cb, Vector3.ZERO, ((cb.global_position - p).normalized() + Vector3.UP) * 6000.0 * (1.0 - dc / BLAST_R), p)
	for u in game.police.units:
		var uc = u["car"]
		if is_instance_valid(uc) and uc != n and uc.global_position.distance_to(p) < BLAST_R:
			_damage_car(uc, 100.0)
			(uc as RigidBody3D).apply_central_impulse(((uc.global_position - p).normalized() + Vector3.UP) * 5000.0)
	if game.car != n and game.car.global_position.distance_to(p) < BLAST_R:
		# your car: knocked about and dented, more the nearer it is (not thrown across town)
		var near_k: float = 1.0 - game.car.global_position.distance_to(p) / BLAST_R
		var away: Vector3 = (game.car.global_position - p)
		away.y = 0.0
		game.car.apply_central_impulse((away.normalized() * 0.8 + Vector3.UP * 0.35) * game.car.mass * 3.5 * near_k)
		game.car.damage = minf(100.0, game.car.damage + 28.0 * near_k)
		game.car.dent(p, (game.car.global_position - p).normalized(), 0.6 * near_k)

## What's left after a car blows: blackened, thrown up and over.
func _shell(n: Node3D) -> void:
	var up := Vector3(randf_range(-1.5, 1.5), 9.0, randf_range(-1.5, 1.5))
	var c := _traffic_of(n)
	if not c.is_empty():
		if int(c["mode"]) < game.traffic.KNOCKED:
			game.traffic.knock(n, Vector3.ZERO, up * 1150.0, n.global_position + Vector3(0.6, 0, 0.3))
		elif c["body"] is RigidBody3D:
			(c["body"] as RigidBody3D).apply_impulse(up * 1150.0, Vector3(0.6, 0, 0.3))
		var mi: MeshInstance3D = c["mi"]
		if not c.has("mat0"):
			c["mat0"] = mi.material_override
		mi.material_override = _burnt_mat
		return
	for u in game.police.units:
		if u["car"] == n:
			_tint(n)
			(n as RigidBody3D).apply_impulse(up * (n as RigidBody3D).mass, Vector3(0.5, 0, 0.3))
			u["state"] = "wreck"
			u["leave_t"] = 0.0
			return
	_tint(n)
	if n is RigidBody3D:
		(n as RigidBody3D).apply_impulse(up * (n as RigidBody3D).mass, Vector3(0.5, 0, 0.3))

func _tint(n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _burnt_mat

# ------------------------------------------------------------------ the police on foot

## While you're wanted and on foot, police cars that get near you stop and the officers get out and open
## fire, pushing in if you're far off.
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
		if o["dead"] or not is_instance_valid(o["node"]):
			officers.erase(o)
			continue
		var n: CharacterBody3D = o["node"]
		var av: Avatar = o["av"]
		if not police.wanted() or not game.on_foot:
			officers.erase(o)
			n.queue_free()
			continue
		var to := yp - n.global_position
		to.y = 0.0
		var d := to.length()
		if av.lock_t > 0.0:
			# (still climbing out of the car)
			av.aim_at(Vector3.INF, true, dt)
			continue
		var want := Vector3.ZERO
		if float(o.get("stagger", 0.0)) > 0.0:
			# (staggering from a hit: carried back by it, the gun down, no shooting)
			o["stagger"] = float(o["stagger"]) - dt
			av.aim_at(Vector3.INF, true, dt * 3.0)
			n.velocity.x = lerpf(n.velocity.x, 0.0, 1.0 - exp(-dt * 3.0))
			n.velocity.z = lerpf(n.velocity.z, 0.0, 1.0 - exp(-dt * 3.0))
			n.velocity.y = 0.0 if n.is_on_floor() else n.velocity.y - 16.0 * dt
			n.move_and_slide()
			o["cool"] = maxf(float(o["cool"]), 0.3)
			continue
		if d > 11.0:
			want = to.normalized() * 4.6
			av.play("sprint", 1.0)
			av.aim_at(Vector3.INF, true, dt)
		else:
			av.play("holding-both", 1.0)
			av.aim_at(yp + Vector3(0, 1.0, 0), true, dt)
		n.velocity.x = lerpf(n.velocity.x, want.x, 1.0 - exp(-dt * 8.0))
		n.velocity.z = lerpf(n.velocity.z, want.z, 1.0 - exp(-dt * 8.0))
		n.velocity.y = 0.0 if n.is_on_floor() else n.velocity.y - 16.0 * dt
		n.move_and_slide()
		av.rotation.y = atan2(-to.x, -to.z) + PI
		o["cool"] = float(o["cool"]) - dt
		if d < 32.0 and float(o["cool"]) <= 0.0:
			o["cool"] = randf_range(0.9, 1.6)
			var from := n.global_position + Vector3(0, 1.3, 0)
			# who they shoot at: you, or one of your crew if they're nearer
			var ally: Dictionary = {}
			var ad := d - 3.0
			if game.allies:
				for a in game.allies.alive():
					var da: float = (a["node"] as Node3D).global_position.distance_to(n.global_position)
					if da < ad:
						ad = da
						ally = a
			var aim := (yp if ally.is_empty() else (ally["node"] as Node3D).global_position) + Vector3(0, 1.0, 0)
			var ato := aim - from
			game.sfx("shot_pistol", clampf(-4.0 - d * 0.25, -14.0, -4.0), randf_range(0.9, 1.0))
			game.fx.spark_burst(from + ato.normalized() * 0.6, ato.normalized(), 3, 5.0)
			if _clear(from, aim):
				var moving := Vector3(you.velocity.x, 0, you.velocity.z).length() > 4.0 and ally.is_empty()
				var dd := d if ally.is_empty() else ad
				var chance := clampf(0.55 - dd * 0.018 - (0.18 if moving else 0.0), 0.1, 0.55)
				if randf() < chance:
					_tracer(from, aim)
					if ally.is_empty():
						hurt(OFFICER_SHOT, from)
					else:
						game.allies.hurt(ally, OFFICER_SHOT, from)
				else:
					_tracer(from, aim + Vector3(randf_range(-1.4, 1.4), randf_range(-0.4, 0.8), randf_range(-1.4, 1.4)))

func _officer_out(u: Dictionary, k: int) -> void:
	var uc: Node3D = u["car"]
	var side: Vector3 = uc.global_transform.basis.x * (1.7 if k == 0 else -1.7)
	var n := CharacterBody3D.new()
	n.collision_layer = 256
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
	av.setup("cop", "", game.toon)        # (the police uniform)
	av.hold(Weapons.LIST[0], game.toon)
	add_child(n)
	var p := uc.global_position + side
	n.global_position = Vector3(p.x, game.island.height_at(p.x, p.z) + 0.1, p.z)
	av.rotation.y = atan2(side.x, side.z)
	officers.append({"node": n, "av": av, "hp": OFFICER_HP, "cool": randf_range(0.8, 1.6) + 0.4, "unit": u, "dead": false})

## Officers gone (you're back in a car, or it's over); the cars they came in pick up the chase again.
func clear_officers() -> void:
	for o in officers:
		if is_instance_valid(o["node"]):
			(o["node"] as Node).queue_free()
	officers.clear()
	aiming = false
	aim_k = 0.0
