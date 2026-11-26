extends Node
## Fists. Out of a car, a shop or a job your hands are empty (a gun has to be picked off the wheel), and
## FIRE throws a punch: it locks on to whoever's nearest in front (the way you're pushing the stick first),
## turns you to them and steps you in. Tap again as one lands and it chains: a cross, a body jab, an elbow
## and uppercut, a roundhouse that knocks them flat; sprinting in, a front kick. Each hit stops the world for a
## blink, shakes the view and thuds; they reel (the head snaps, they double over), knocked back a step.
## In a fight the BLOCK button comes up: a tap guards (their punch thuds off your arms and leaves them open),
## held it's a dodge, a quick step aside. People you square up to stand their ground and swing back.
## Near someone you can greet them (a wave back) or taunt them: some take you on, some run off and call the
## police, some just shrug.

const Avatar := preload("res://scripts/game/avatar.gd")

## A strike: the clip, the stretch of it played (from, to) and when it lands (hit), in the clip's seconds,
## played at speed; damage, how they reel (react), how far it knocks them, how close it reaches.
const COMBO := [
	{"clip": "fight_cross_punch", "from": 0.80, "hit": 1.12, "to": 1.50, "speed": 1.6, "dmg": 14.0, "react": "head", "push": 0.5, "reach": 1.4, "snd": "punch"},
	{"clip": "fight_body_jab_cross", "from": 0.30, "hit": 0.58, "to": 0.92, "speed": 1.5, "dmg": 12.0, "react": "body", "push": 0.45, "reach": 1.35, "snd": "punch"},
	{"clip": "fight_elbow_uppercut_combo", "from": 0.62, "hit": 0.95, "to": 1.28, "speed": 1.5, "dmg": 18.0, "react": "head", "push": 0.6, "reach": 1.25, "snd": "punch"},
	{"clip": "fight_roundhouse_kick", "from": 0.42, "hit": 0.90, "to": 1.50, "speed": 1.45, "dmg": 30.0, "react": "ko", "push": 1.4, "reach": 1.6, "snd": "kick_hit", "finisher": true},
]
const KICK := {"clip": "fight_kicking", "from": 0.80, "hit": 1.20, "to": 1.65, "speed": 1.55, "dmg": 24.0, "react": "body", "push": 1.6, "reach": 1.7, "snd": "kick_hit"}
## What people throw back at you.
const FOE_ATK := [
	{"clip": "fight_cross_punch", "from": 0.70, "hit": 1.12, "to": 1.50, "speed": 1.25, "dmg": 9.0},
	{"clip": "fight_body_jab_cross", "from": 0.22, "hit": 0.58, "to": 0.95, "speed": 1.2, "dmg": 8.0},
	{"clip": "fight_kicking", "from": 0.75, "hit": 1.20, "to": 1.65, "speed": 1.3, "dmg": 12.0},
]
const REACT := {
	"head": ["fight_big_hit_to_head", 0.05, 0.85, 1.4],
	"body": ["fight_hit_to_body", 0.05, 0.85, 1.35],
	"light": ["fight_hit_reaction", 0.05, 0.75, 1.4],
}
const LOCK_R := 6.5           # who you'll swing at
const CHAIN := 0.5            # seconds after a swing ends that the next press still carries the combo on
const PERSON_HP := 60.0       # punches to put someone down: about five, or a combo
const BLOCK_T := 0.55
const DODGE_AT := 0.22        # held this long, the guard turns into a dodge

var game: Node
var target := {}              # who you're squared up to: {kind: "ped" | "cop", ref, av}
var atk := {}                 # the swing you're in: {def, t, landed, queued, tgt}
var combo := 0
var since := 9.0              # since the last swing ended
var fight_t := 0.0            # in a fight (stance, BLOCK up) for this long yet
var block_t := 0.0
var dodge_t := 0.0
var _held_t := -1.0           # how long BLOCK's been held (-1: not down)
var _dodged := false
var foes: Array = []          # people fighting you: {pr, cool, atk, stun, block_t}
var calls: Array = []         # people off to call the police: {t, pos}
var social := {}              # the person near enough to greet or taunt
var _stop_k := 0.0
var _social_cd := 0.0         # (a moment after a greet or a taunt before the prompt comes back)

func setup(g: Node) -> void:
	game = g

## Each frame on foot with nothing in your hands (gunplay's put-away branch calls it).
func tick(dt: float, fire_tap: bool, block_held: bool) -> void:
	var foot: CharacterBody3D = game.foot
	if foot == null:
		return
	var av: Avatar = foot.avatar
	since += dt
	fight_t = maxf(0.0, fight_t - dt)
	block_t = maxf(0.0, block_t - dt)
	dodge_t = maxf(0.0, dodge_t - dt)
	var busy: bool = foot.down_t > 0.0 or foot.scripted or game.gunplay.dying
	# BLOCK: a tap guards, held it's a dodge
	if block_held and not busy:
		if _held_t < 0.0:
			_held_t = 0.0
			_dodged = false
			_block(av)
		else:
			_held_t += dt
			if _held_t >= DODGE_AT and not _dodged:
				_dodged = true
				_dodge(foot, av)
	else:
		_held_t = -1.0
	if fire_tap and not busy:
		_press(foot, av)
	_swing_tick(dt, foot, av)
	_foes_tick(dt, foot)
	_calls_tick(dt)
	# squared up: turned to them, the guard stance (and a step slower)
	var near := _nearest(foot, 4.5)
	if not foes.is_empty() or not atk.is_empty():
		fight_t = maxf(fight_t, 3.0)
	if fight_t > 0.0 and not near.is_empty() and atk.is_empty() and dodge_t <= 0.0:
		var to: Vector3 = _pos(near) - foot.global_position
		foot.facing = lerp_angle(foot.facing, atan2(-to.x, -to.z), 1.0 - exp(-dt * 8.0))
		foot.aiming = 0.15
	av.fight = fight_t > 0.0
	foot.move_scale = 0.35 if not atk.is_empty() else (0.75 if fight_t > 0.0 else 1.0)
	_social_cd = maxf(0.0, _social_cd - dt)
	social = {} if (fight_t > 0.0 or _social_cd > 0.0) else _social_pick(foot)

## Out of the fight at once (into a car, a gun drawn, a shop).
func stand_down() -> void:
	atk = {}
	fight_t = 0.0
	block_t = 0.0
	dodge_t = 0.0
	if game.foot:
		game.foot.move_scale = 1.0
		(game.foot.avatar as Avatar).fight = false

func in_fight() -> bool:
	return fight_t > 0.0

## Where the camera should drift to: whoever you're squared up to (INF: no one).
func focus() -> Vector3:
	if fight_t <= 0.0 or game.foot == null:
		return Vector3.INF
	var t := target if not target.is_empty() and _alive(target) else _nearest(game.foot, 4.5)
	if t.is_empty() or _pos(t).distance_to(game.foot.global_position) > 6.0:
		return Vector3.INF
	return _pos(t)

# ------------------------------------------------------------------ throwing them

func _press(foot: CharacterBody3D, av: Avatar) -> void:
	if not atk.is_empty():
		# mid swing: the next one's queued (it goes as this one lands)
		atk["queued"] = true
		return
	_start(foot, av)

func _start(foot: CharacterBody3D, av: Avatar) -> void:
	var hv := Vector3(foot.velocity.x, 0, foot.velocity.z)
	var def: Dictionary
	if hv.length() > 5.0 and foot.sprint:
		def = KICK
		combo = 0
	else:
		if since > CHAIN:
			combo = 0
		def = COMBO[combo % COMBO.size()]
		combo += 1
	var tgt := _acquire(foot)
	target = tgt
	if not tgt.is_empty():
		var to: Vector3 = _pos(tgt) - foot.global_position
		to.y = 0.0
		foot.facing = atan2(-to.x, -to.z)
		foot.aiming = 0.4
		# stepped in: closing the gap over the wind-up, to arm's length
		var gap := to.length() - float(def["reach"]) * 0.8
		var wind := (float(def["hit"]) - float(def["from"])) / float(def["speed"])
		if gap > 0.05:
			foot.shove = to.normalized() * minf(gap, 2.6) / maxf(wind, 0.12) * 1.3
		if tgt["kind"] == "cop":
			_provoked_by_swing(tgt)
	var dur := (float(def["to"]) - float(def["from"])) / float(def["speed"])
	av.play_once(String(def["clip"]), float(def["from"]), dur, float(def["speed"]), true, 0.06)
	atk = {"def": def, "t": 0.0, "landed": false, "queued": false, "tgt": tgt, "swished": false}
	fight_t = 4.0

func _swing_tick(dt: float, foot: CharacterBody3D, av: Avatar) -> void:
	if atk.is_empty():
		return
	var def: Dictionary = atk["def"]
	atk["t"] = float(atk["t"]) + dt
	var t_hit := (float(def["hit"]) - float(def["from"])) / float(def["speed"])
	var t_end := (float(def["to"]) - float(def["from"])) / float(def["speed"])
	var tgt: Dictionary = atk["tgt"]
	if not tgt.is_empty() and float(atk["t"]) < t_hit:
		# (still turning onto them as they move)
		var to: Vector3 = _pos(tgt) - foot.global_position
		foot.facing = lerp_angle(foot.facing, atan2(-to.x, -to.z), 1.0 - exp(-dt * 14.0))
		foot.aiming = 0.3
	if not atk["swished"] and float(atk["t"]) > t_hit - 0.09:
		atk["swished"] = true
		game.sfx("swish_%d" % randi_range(1, 2), -9.0, randf_range(0.9, 1.15))
	if not atk["landed"] and float(atk["t"]) >= t_hit:
		atk["landed"] = true
		_land(foot, def, tgt)
	# chained: once it's landed the next one can cut in
	var can_cut: bool = atk["landed"] and float(atk["t"]) > t_hit + 0.08
	if (can_cut and atk["queued"]) or float(atk["t"]) >= t_end:
		var q: bool = atk["queued"]
		atk = {}
		since = 0.0
		av.lock_t = 0.0
		if q and def != KICK and not bool(def.get("finisher", false)):
			_start(foot, av)

## The moment it lands (or doesn't).
func _land(foot: CharacterBody3D, def: Dictionary, tgt: Dictionary) -> void:
	if tgt.is_empty() or not _alive(tgt):
		return
	var me := foot.global_position
	var to: Vector3 = _pos(tgt) - me
	to.y = 0.0
	var fwd := Vector3(-sin(foot.facing), 0, -cos(foot.facing))
	if to.length() > float(def["reach"]) + 0.35 or (to.length() > 0.3 and fwd.dot(to.normalized()) < 0.2):
		return           # (a miss: just the swish)
	var d := to.normalized() if to.length() > 0.05 else fwd
	var at: Vector3 = _pos(tgt) + Vector3(0, 1.45 if def["react"] != "body" else 1.1, 0) - d * 0.25
	# a foe with their guard up: it thuds off their arms
	var f := _foe_of(tgt)
	if not f.is_empty() and float(f["block_t"]) > 0.0 and not bool(def.get("finisher", false)):
		game.sfx("block", -4.0, randf_range(0.9, 1.05))
		_hitstop(0.04)
		game.shake = maxf(game.shake, 0.1)
		f["block_t"] = 0.0
		f["cool"] = maxf(float(f["cool"]), 0.4)
		_knock(tgt, d * 0.3)
		return
	var dmg: float = float(def["dmg"]) * randf_range(0.9, 1.1)
	var heavy := bool(def.get("finisher", false)) or def == KICK
	game.sfx(("punch_heavy" if heavy else "punch_%d" % randi_range(1, 3)) if def["snd"] == "punch" else "kick_hit", -1.0 if heavy else -3.0, randf_range(0.92, 1.08))
	_hitstop(0.085 if heavy else 0.05)
	game.shake = maxf(game.shake, 0.38 if heavy else 0.2)
	game.buzz(60 if heavy else 35, 0.9 if heavy else 0.6)
	if def["react"] != "body" and randf() < (0.8 if heavy else 0.3):
		game.fx.blood(at, d, 6 if heavy else 3, 3.0)
	var hp := _hurt(tgt, dmg)
	var av: Avatar = tgt["av"]
	if hp <= 0.0 or def["react"] == "ko" and hp < PERSON_HP * 0.45:
		_ko(tgt, d * (8.5 if heavy else 5.5) + Vector3(0, 2.2 if heavy else 1.2, 0))
		return
	if av and is_instance_valid(av):
		var r: Array = REACT.get(String(def["react"]), REACT["light"])
		if def["react"] == "ko":
			r = REACT["head"]
		av.play_once(String(r[0]), float(r[1]), (float(r[2]) - float(r[1])) / float(r[3]), float(r[3]), true, 0.05)
		av.hit(at, d, 1.5 if heavy else 1.1)
	if not f.is_empty():
		f["stun"] = 0.55 if heavy else 0.4
		f["atk"] = {}
		f["cool"] = maxf(float(f["cool"]), 0.6)
	_knock(tgt, d * float(def["push"]))
	fight_t = 4.0
	if tgt["kind"] == "ped":
		_provoked_by_swing(tgt)

## A blink of stillness on the hit (the world stops, then carries on): what makes it land.
func _hitstop(t: float) -> void:
	if Engine.time_scale < 0.99:
		return
	Engine.time_scale = 0.06
	_stop_k += 1.0
	var k := _stop_k
	get_tree().create_timer(t, true, false, true).timeout.connect(func():
		if _stop_k == k and Engine.time_scale < 0.1:
			Engine.time_scale = 1.0)

# ------------------------------------------------------------------ guarding

func _block(av: Avatar) -> void:
	block_t = BLOCK_T
	fight_t = maxf(fight_t, 3.0)
	if atk.is_empty():
		av.play_once("fight_center_block", 0.15, 0.5, 1.25, true, 0.05)

func _dodge(foot: CharacterBody3D, av: Avatar) -> void:
	block_t = 0.0
	dodge_t = 0.5
	atk = {}
	var away := Vector3(sin(foot.facing), 0, cos(foot.facing))          # (back from where you face)
	var side := Vector3(-cos(foot.facing), 0, sin(foot.facing))
	if foot.move.length() > 0.3:
		var m: Vector2 = foot.move
		var f := Vector3(-sin(foot.cam_yaw), 0, -cos(foot.cam_yaw))
		var r := Vector3(cos(foot.cam_yaw), 0, -sin(foot.cam_yaw))
		side = (f * m.y + r * m.x).normalized()
	else:
		side = (side * (1.0 if randf() < 0.5 else -1.0) + away * 0.6).normalized()
	foot.shove = side * 5.5
	av.play_once("fight_dodging_1", 0.35, 0.65, 1.45, true, 0.05)
	game.sfx("swish_2", -12.0, 0.8)

# ------------------------------------------------------------------ the people you fight

## Who's in reach to swing at: the one nearest in front (the way the stick's pushed, if it is).
func _acquire(foot: CharacterBody3D) -> Dictionary:
	var me := foot.global_position
	var dir := Vector3(-sin(foot.facing), 0, -cos(foot.facing))
	if foot.move.length() > 0.3:
		var m: Vector2 = foot.move
		dir = (Vector3(-sin(foot.cam_yaw), 0, -cos(foot.cam_yaw)) * m.y + Vector3(cos(foot.cam_yaw), 0, -sin(foot.cam_yaw)) * m.x).normalized()
	var best := {}
	var bs := INF
	for c in _candidates():
		var to: Vector3 = _pos(c) - me
		to.y = 0.0
		var d := to.length()
		if d > LOCK_R:
			continue
		var ang := 1.0 - dir.dot(to.normalized()) if d > 0.2 else 0.0
		var sc := d + ang * 2.2 - (1.5 if not _foe_of(c).is_empty() else 0.0)
		if sc < bs:
			bs = sc
			best = c
	return best

func _nearest(foot: CharacterBody3D, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for c in _candidates():
		var d := _pos(c).distance_to(foot.global_position)
		if d < bd:
			bd = d
			best = c
	return best

func _candidates() -> Array:
	var out: Array = []
	var people = game.island.people
	for pr in people._live:
		if pr["gone"] or pr.get("down", false) or not pr.has("live") or not is_instance_valid(pr["live"]):
			continue
		out.append({"kind": "ped", "ref": pr, "av": pr["live"]})
	for o in game.gunplay.officers:
		if not o["dead"] and is_instance_valid(o["node"]):
			out.append({"kind": "cop", "ref": o, "av": o["av"]})
	return out

func _pos(c: Dictionary) -> Vector3:
	if c["kind"] == "ped":
		var pr: Dictionary = c["ref"]
		return (pr["pos"] as Vector3) + Vector3(0, float(pr.get("y", 0.0)), 0)
	return ((c["ref"] as Dictionary)["node"] as Node3D).global_position

func _alive(c: Dictionary) -> bool:
	if c["kind"] == "ped":
		var pr: Dictionary = c["ref"]
		return not pr["gone"] and not pr.get("down", false)
	var o: Dictionary = c["ref"]
	return not o["dead"] and is_instance_valid(o["node"])

func _hurt(c: Dictionary, dmg: float) -> float:
	if c["kind"] == "ped":
		var pr: Dictionary = c["ref"]
		pr["fist_hp"] = float(pr.get("fist_hp", PERSON_HP)) - dmg
		return float(pr["fist_hp"])
	var o: Dictionary = c["ref"]
	o["hp"] = float(o["hp"]) - dmg * 0.8
	o["stagger"] = 0.6
	o["cool"] = maxf(float(o["cool"]), 1.0)
	return float(o["hp"])

## Knocked back a step (or a couple).
func _knock(c: Dictionary, v: Vector3) -> void:
	if c["kind"] == "ped":
		var pr: Dictionary = c["ref"]
		pr["fist_v"] = v * 4.0
	else:
		var n: CharacterBody3D = (c["ref"] as Dictionary)["node"]
		n.velocity += v * 5.0

## Out cold: limp, thrown the way the blow went.
func _ko(c: Dictionary, vel: Vector3) -> void:
	_drop_foe(c)
	if c["kind"] == "cop":
		game.gunplay._officer_down(c["ref"], vel)
		game.save.add_stat("cops_down", 1)
		game.police.heat_pts += 0.4
		return
	var pr: Dictionary = c["ref"]
	var face := float(pr["face"])
	var info: Dictionary = game.island.people.knock_down(pr)
	if info.is_empty():
		return
	pr.erase("fight")
	var xf: Transform3D = info["xf"]
	if vel.length() < 7.0 and randf() < 0.6:
		_ko_drop(int(info["v"]), xf.origin, face)        # (dropped where they stood: out cold, fitting)
	else:
		game.ragdolls.spawn(int(info["v"]), xf, info["shoulders"], vel, game.foot)
	game.save.add_stat("knockouts", 1)
	game.police.ped_hit(xf.origin)
	if randf() < 0.5:
		game.heist.drop_cash(xf.origin + Vector3(vel.x, 0, vel.z).normalized() * 0.8, randi_range(2, 8) * 5)
	game.island.people.panic(xf.origin, 10.0)

## Out cold where they stand: they crumple, and lie there fitting a while (the seizure clips), then still;
## the body's cleared away a good while later (they're back on their feet somewhere else by then).
func _ko_drop(v: int, at: Vector3, face: float) -> void:
	const M := preload("res://scripts/core/models.gd")
	var av := Avatar.new()
	game.add_child(av)
	av.setup(String(M.CHARS[v % M.CHARS.size()]), "", game.island.people.mat)
	av.global_position = at
	av.rotation.y = face + PI
	var ko_len: float = av.anim.get_animation("fight_knockedout_death").length if av.anim else 3.7
	av.play_once("fight_knockedout_death", 0.35, (ko_len - 0.35) / 1.15, 1.15, true, 0.06)
	var fit := "fight_tonic_seizure" if randf() < 0.5 else "fight_laying_seizure"
	var fit_t := randf_range(4.0, 7.0)
	var tw := av.create_tween()
	tw.tween_interval((ko_len - 0.35) / 1.15 - 0.15)
	tw.tween_callback(func():
		av.lock_t = 0.0
		av.play(fit, 1.0, 0.4))
	tw.tween_interval(fit_t)
	tw.tween_callback(func():
		# (then still: the end of the fall held)
		av._act_in("fight_knockedout_death", 0.6, ko_len - 0.02, 0.0)
		av.lock_t = 99.0)
	tw.tween_interval(30.0)
	tw.tween_callback(av.queue_free)

## Hit (or swung at) someone who wasn't fighting: they fight back, or run and call it in. A police officer:
## that's assault, and they're onto you.
func _provoked_by_swing(c: Dictionary) -> void:
	if c["kind"] == "cop":
		if not game.police.wanted() and game.chase_ok_or_chase():
			game.police.start(1.0, "Assaulted an officer")
		return
	var pr: Dictionary = c["ref"]
	if not _foe_of(c).is_empty() or pr.get("fled", false):
		return
	if randf() < float(pr.get("grit", _grit(pr))):
		_provoke(pr)
	else:
		_flee_and_call(pr)

## How likely they are to fight (fixed per person).
func _grit(pr: Dictionary) -> float:
	if not pr.has("grit"):
		pr["grit"] = randf_range(0.2, 0.75)
	return float(pr["grit"])

func _provoke(pr: Dictionary) -> void:
	if pr.get("down", false) or pr["gone"]:
		return
	game.island.people.make_live(pr)
	pr["fight"] = true
	pr["flee"] = 0.0
	for f in foes:
		if f["pr"] == pr:
			return
	foes.append({"pr": pr, "cool": randf_range(0.5, 1.0), "atk": {}, "stun": 0.0, "block_t": 0.0})
	fight_t = 4.0

func _flee_and_call(pr: Dictionary) -> void:
	pr["fled"] = true
	game.island.people.panic(pr["pos"], 2.0)
	calls.append({"t": randf_range(3.0, 5.0), "pos": pr["pos"], "pr": pr})

func _calls_tick(dt: float) -> void:
	for c in calls.duplicate():
		c["t"] = float(c["t"]) - dt
		if float(c["t"]) > 0.0:
			continue
		calls.erase(c)
		var pr: Dictionary = c["pr"]
		if pr["gone"] or pr.get("down", false):
			continue          # (knocked out before they got the call made)
		if not game.police.wanted() and game.chase_ok_or_chase():
			game.police.start(1.0, "Someone called the police")
		elif game.police.wanted():
			game.police.heat_pts += 0.15

func _foe_of(c: Dictionary) -> Dictionary:
	if c.is_empty() or c["kind"] != "ped":
		return {}
	for f in foes:
		if f["pr"] == c["ref"]:
			return f
	return {}

func _drop_foe(c: Dictionary) -> void:
	var f := _foe_of(c)
	if not f.is_empty():
		foes.erase(f)

## The people fighting you: they square up, close in and swing (a wind-up you can see coming: block it,
## dodge it, or hit them first and it's broken off).
func _foes_tick(dt: float, foot: CharacterBody3D) -> void:
	# (and anyone knocked back by a blow slides off a step)
	for pr in game.island.people._live:
		if pr.has("fist_v"):
			var v: Vector3 = pr["fist_v"]
			pr["pos"] = (pr["pos"] as Vector3) + v * dt
			v = v.move_toward(Vector3.ZERO, dt * 12.0)
			if v.length() < 0.05:
				pr.erase("fist_v")
			else:
				pr["fist_v"] = v
	var me := foot.global_position
	for f in foes.duplicate():
		var pr: Dictionary = f["pr"]
		if pr["gone"] or pr.get("down", false) or not pr.has("live") or not is_instance_valid(pr["live"]):
			foes.erase(f)
			pr.erase("fight")
			continue
		var av: Avatar = pr["live"]
		av.fight = true
		var to: Vector3 = me - (pr["pos"] as Vector3)
		to.y = 0.0
		var dist := to.length()
		if dist > 30.0 or game.gunplay.dying or not game.on_foot:
			# (you've gone: they give up)
			foes.erase(f)
			pr.erase("fight")
			av.fight = false
			continue
		pr["face"] = lerp_angle(float(pr["face"]), atan2(-to.x, -to.z), 1.0 - exp(-dt * 7.0))
		f["block_t"] = maxf(0.0, float(f["block_t"]) - dt)
		if float(f["stun"]) > 0.0:
			f["stun"] = float(f["stun"]) - dt
			continue
		# winding up on you: they might get their guard up (more often the more they've been hit)
		if not atk.is_empty() and f["atk"].is_empty() and float(f["block_t"]) <= 0.0 and atk["tgt"].get("ref") == pr and not atk["landed"] and float(atk["t"]) < 0.05:
			if randf() < 0.22:
				f["block_t"] = 0.6
				av.play_once("fight_center_block", 0.15, 0.5, 1.3, true, 0.05)
		if not f["atk"].is_empty():
			_foe_swing(dt, f, av, foot, dist, to)
			continue
		if dist > 1.25:
			var sp := minf(2.8, (dist - 1.1) * 3.0)
			var np: Vector3 = (pr["pos"] as Vector3) + to.normalized() * sp * dt
			np.y = game.island.height_at(np.x, np.z)
			pr["pos"] = np
			av.locomote(Vector2(0, sp))
		else:
			av.locomote(Vector2.ZERO)
			f["cool"] = float(f["cool"]) - dt
			if float(f["cool"]) <= 0.0 and foot.down_t <= 0.0:
				var def: Dictionary = FOE_ATK[randi() % FOE_ATK.size()]
				f["atk"] = {"def": def, "t": 0.0, "landed": false}
				f["cool"] = randf_range(1.0, 1.9)
				av.play_once(String(def["clip"]), float(def["from"]), (float(def["to"]) - float(def["from"])) / float(def["speed"]), float(def["speed"]), true, 0.06)
		# beaten: some give up and run
		if float(pr.get("fist_hp", PERSON_HP)) < PERSON_HP * 0.25 and randf() < dt * 0.4:
			foes.erase(f)
			pr.erase("fight")
			av.fight = false
			_flee_and_call(pr)

func _foe_swing(dt: float, f: Dictionary, av: Avatar, foot: CharacterBody3D, dist: float, to: Vector3) -> void:
	var a: Dictionary = f["atk"]
	var def: Dictionary = a["def"]
	a["t"] = float(a["t"]) + dt
	var t_hit := (float(def["hit"]) - float(def["from"])) / float(def["speed"])
	var t_end := (float(def["to"]) - float(def["from"])) / float(def["speed"])
	if not a["landed"] and float(a["t"]) > t_hit - 0.09 and not a.get("sw", false):
		a["sw"] = true
		game.sfx("swish_1", -12.0, randf_range(0.85, 1.0))
	if not a["landed"] and float(a["t"]) >= t_hit:
		a["landed"] = true
		if dist < 1.7:
			var from: Vector3 = f["pr"]["pos"]
			if dodge_t > 0.0:
				pass          # (stepped clean out of it)
			elif block_t > 0.0:
				game.sfx("block", -3.0, randf_range(0.9, 1.05))
				game.shake = maxf(game.shake, 0.12)
				_hitstop(0.04)
				f["stun"] = 0.7         # (thrown off: your opening)
				f["atk"] = {}
				return
			else:
				hurt_you(float(def["dmg"]) * randf_range(0.9, 1.15), from, String(def["clip"]).contains("kick"))
	if float(a["t"]) >= t_end:
		f["atk"] = {}
		av.lock_t = 0.0

## You take a blow: you reel, the view jolts, it thuds. (Out of health it's lights out like any other way.)
func hurt_you(dmg: float, from: Vector3, heavy := false) -> void:
	var gp = game.gunplay
	var foot: CharacterBody3D = game.foot
	if gp.hp <= 0.0 or foot == null:
		return
	var d := foot.global_position - from
	d.y = 0.0
	d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	game.sfx("kick_hit" if heavy else "punch_%d" % randi_range(1, 3), -2.0, randf_range(0.85, 0.95))
	_hitstop(0.05)
	if gp.hp - dmg > 0.0:
		gp.hp -= dmg
		gp.hurt_t = 0.0
		game.buzz(50, 0.9)
		game.ui.impact_flash(0.25)
		game.shake = maxf(game.shake, 0.3 if heavy else 0.22)
		var av: Avatar = foot.avatar
		atk = {}
		var r: Array = REACT["body"] if heavy else REACT["head" if randf() < 0.5 else "light"]
		av.play_once(String(r[0]), float(r[1]), (float(r[2]) - float(r[1])) / float(r[3]) * 0.8, float(r[3]) * 1.15, true, 0.05)
		av.hit(foot.global_position + Vector3(0, 1.4, 0), d, 1.1)
		foot.shove = d * (3.5 if heavy else 2.2)
		fight_t = 4.0
	else:
		gp.hurt(dmg, from)

# ------------------------------------------------------------------ saying hello (or otherwise)

func _social_pick(foot: CharacterBody3D) -> Dictionary:
	if game.gunplay.dying or foot.down_t > 0.0 or not game.gunplay.holstered:
		return {}
	var me := foot.global_position
	var fwd := Vector3(-sin(foot.facing), 0, -cos(foot.facing))
	var best := {}
	var bd := 3.4
	for pr in game.island.people._live:
		if pr["gone"] or pr.get("down", false) or pr.has("fight") or float(pr.get("flee", 0.0)) > 0.0 or pr["pose"] == "sit":
			continue
		var to: Vector3 = (pr["pos"] as Vector3) - me
		to.y = 0.0
		var d := to.length()
		if d < bd and (d < 1.2 or fwd.dot(to.normalized()) > -0.2):
			bd = d
			best = pr
	return best

func greet() -> void:
	var pr: Dictionary = social
	if pr.is_empty() or game.foot == null:
		return
	var foot: CharacterBody3D = game.foot
	var to: Vector3 = (pr["pos"] as Vector3) - foot.global_position
	foot.facing = atan2(-to.x, -to.z)
	foot.aiming = 0.5
	(foot.avatar as Avatar).play_once("wave", 0.0, 1.3, 1.0, false, 0.12)
	_social_cd = 2.5
	pr["face"] = atan2(to.x, to.z)
	pr["talk_to"] = true
	var av = pr.get("live")
	get_tree().create_timer(0.45, false).timeout.connect(func():
		if av == null or not is_instance_valid(av) or pr.get("down", false):
			return
		if randf() < 0.8:
			pr["friendly"] = true
			pr["wave"] = 1.0
			(av as Avatar).play_once("wave", 0.0, 1.4, 1.0, false, 0.12)
		else:
			(av as Avatar).play_once("shrug", 0.0, 1.6, 1.0, false, 0.15))

func taunt() -> void:
	var pr: Dictionary = social
	if pr.is_empty() or game.foot == null:
		return
	var foot: CharacterBody3D = game.foot
	var to: Vector3 = (pr["pos"] as Vector3) - foot.global_position
	foot.facing = atan2(-to.x, -to.z)
	foot.aiming = 0.6
	(foot.avatar as Avatar).play_once("fight_taunt", 0.15, 1.1, 1.25, true, 0.1)
	_social_cd = 3.0
	pr["face"] = atan2(to.x, to.z)
	var av = pr.get("live")
	social = {}
	get_tree().create_timer(0.9, false).timeout.connect(func():
		if pr["gone"] or pr.get("down", false) or pr.has("fight"):
			return
		var roll := randf()
		var grit := _grit(pr)
		# (the bold square up; most of the rest run off to call it in; a few just shrug you off)
		var fight_p := grit * 0.9
		var run_p := fight_p + (1.0 - fight_p) * 0.6
		if pr.has("react"):
			roll = float(pr["react"])
		if roll < fight_p:
			if av != null and is_instance_valid(av):
				(av as Avatar).play_once("fight_taunt", 0.15, 1.0, 1.3, true, 0.1)
			get_tree().create_timer(0.7, false).timeout.connect(func(): _provoke(pr))
			game.ui.toast("They want to go", "", Color("ff5c7a"), Color.WHITE, 1.4)
		elif roll < run_p:
			_flee_and_call(pr)
			game.ui.toast("They're running off to call the police", "eye", Color("ff5c7a"), Color.WHITE, 2.0)
		else:
			if av != null and is_instance_valid(av):
				(av as Avatar).play_once("shrug", 0.0, 1.6, 1.0, false, 0.15))
