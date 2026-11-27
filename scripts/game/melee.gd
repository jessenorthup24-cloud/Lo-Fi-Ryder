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
	{"clip": "fight_cross_punch", "from": 0.80, "hit": 1.08, "to": 1.46, "speed": 1.55, "dmg": 14.0, "react": "head", "push": 0.5, "reach": 1.4, "snd": "punch"},
	{"clip": "fight_body_jab_cross", "from": 0.20, "hit": 0.44, "to": 0.64, "speed": 1.35, "dmg": 12.0, "react": "body", "push": 0.45, "reach": 1.35, "snd": "punch"},
	{"clip": "fight_elbow_uppercut_combo", "from": 0.62, "hit": 0.95, "to": 1.28, "speed": 1.5, "dmg": 18.0, "react": "head", "push": 0.6, "reach": 1.25, "snd": "punch"},
	{"clip": "fight_roundhouse_kick", "from": 0.42, "hit": 0.94, "to": 1.50, "speed": 1.45, "dmg": 30.0, "react": "ko", "push": 1.4, "reach": 1.6, "snd": "kick_hit", "finisher": true},
]
const KICK := {"clip": "fight_kicking", "from": 0.82, "hit": 1.21, "to": 1.65, "speed": 1.55, "dmg": 24.0, "react": "body", "push": 1.6, "reach": 1.7, "snd": "kick_hit"}
## What people throw back at you.
const FOE_ATK := [
	{"clip": "fight_cross_punch", "from": 0.66, "hit": 1.08, "to": 1.46, "speed": 1.1, "dmg": 9.0},
	{"clip": "fight_body_jab_cross", "from": 0.05, "hit": 0.44, "to": 0.64, "speed": 1.0, "dmg": 8.0},
	{"clip": "fight_kicking", "from": 0.72, "hit": 1.21, "to": 1.65, "speed": 1.15, "dmg": 12.0},
]
const REACT := {
	"head": ["fight_big_hit_to_head", 0.05, 0.85, 1.4],
	"body": ["fight_hit_to_body", 0.05, 0.85, 1.35],
	"light": ["fight_hit_reaction", 0.1, 0.95, 1.45],
}
const LOCK_R := 6.5           # who you'll swing at
const CHAIN := 0.5            # seconds after a swing ends that the next press still carries the combo on
const PERSON_HP := 60.0       # punches to put someone down: about five, or a combo
const BLOCK_T := 0.42
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
var solos: Array = []         # fighters not of the crowd (a street fight's opponent): ped-like, placed by us
var calls: Array = []         # people off to call the police: {t, pos}
var social := {}              # the person near enough to greet or taunt
var _stop_k := 0.0
var _social_cd := 0.0
var recoil_t := 0.0           # thrown off by their guard (or overreached past a slip): no punching a moment
var stats := {"swings": 0, "landed": 0, "blocked": 0, "slipped": 0, "heavy": 0, "knockdowns": 0, "their_hits": 0, "you_blocked": 0}         # (a moment after a greet or a taunt before the prompt comes back)

func setup(g: Node) -> void:
	game = g

## Each frame on foot with nothing in your hands (gunplay's put-away branch calls it).
func tick(dt: float, fire_tap: bool, block_held: bool) -> void:
	var foot: CharacterBody3D = game.foot
	if foot == null:
		return
	var av: Avatar = foot.avatar
	since += dt
	recoil_t = maxf(0.0, recoil_t - dt)
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
	if fire_tap and not busy and recoil_t <= 0.0:
		_press(foot, av)
	_swing_tick(dt, foot, av)
	# squared up: turned to them, the guard stance (and a step slower)
	var near := _nearest(foot, 4.5)
	if not foes.is_empty() or not atk.is_empty():
		fight_t = maxf(fight_t, 3.0)
	if fight_t > 0.0 and not near.is_empty() and atk.is_empty() and dodge_t <= 0.0:
		var to: Vector3 = _pos(near) - foot.global_position
		foot.facing = lerp_angle(foot.facing, atan2(-to.x, -to.z), 1.0 - exp(-dt * 8.0))
		foot.aiming = 0.15
	av.fight = fight_t > 0.0
	foot.move_scale = 0.0 if (not atk.is_empty() or dodge_t > 0.0) else (0.75 if fight_t > 0.0 else 1.0)
	_social_cd = maxf(0.0, _social_cd - dt)
	social = {} if (fight_t > 0.0 or _social_cd > 0.0) else _social_pick(foot)

## The people fighting you and the calls to the police carry on whatever's in your hands (a gun out, in the
## car: they give up when you drive off).
func _process(dt: float) -> void:
	if game == null or game.state != game.DRIVE:
		return
	if game.on_foot and game.foot != null:
		_foes_tick(dt, game.foot)
	else:
		for f in foes:
			(f["pr"] as Dictionary).erase("fight")
			var fav = f["pr"].get("live")
			if fav != null and is_instance_valid(fav):
				(fav as Avatar).fight = false
		foes.clear()
		fight_t = 0.0
	_calls_tick(dt)

## Out of the fight at once (into a car, a gun drawn, a shop).
func stand_down() -> void:
	atk = {}
	fight_t = 0.0
	block_t = 0.0
	dodge_t = 0.0
	if game.foot:
		game.foot.move_scale = 1.0
		(game.foot.avatar as Avatar).fight = false

## A street fight's opponent squares up: their own stats (fights.gd).
func add_foe(pr: Dictionary, stats: Dictionary) -> void:
	pr["fight"] = true
	pr["fist_hp"] = float(stats["hp"])
	pr["fist_max"] = float(stats["hp"])
	foes.append({"pr": pr, "prof": stats, "cool": randf_range(0.6, 1.0), "atk": {}, "stun": 0.0, "block_t": 0.0,
		"phase": "circle", "side": 1.0 if randf() < 0.5 else -1.0, "side_t": randf_range(1.0, 2.5), "left": 0,
		"slip_t": 0.0, "slip_v": Vector3.ZERO, "hits": 0, "hit_t": 9.0, "down_t": 0.0})
	fight_t = 4.0

func drop_solo(pr: Dictionary) -> void:
	solos.erase(pr)
	for f in foes.duplicate():
		if f["pr"] == pr:
			foes.erase(f)
	pr.erase("fight")

func in_fight() -> bool:
	return fight_t > 0.0

## How much fight's left in whoever you're squared up to (0..1; -1: not someone fighting you).
func focus_hp() -> float:
	var t := target if not target.is_empty() and _alive(target) else ({} if game.foot == null else _nearest(game.foot, 4.5))
	var f := _foe_of(t)
	if f.is_empty():
		return -1.0
	var pr: Dictionary = f["pr"]
	return clampf(float(pr.get("fist_hp", PERSON_HP)) / float(pr.get("fist_max", PERSON_HP)), 0.0, 1.0)

## The name of whoever you're squared up to, if they've one (a street fight's opponent).
func focus_name() -> String:
	var t := target if not target.is_empty() and _alive(target) else ({} if game.foot == null else _nearest(game.foot, 4.5))
	if t.is_empty() or t["kind"] != "ped":
		return ""
	return String((t["ref"] as Dictionary).get("name", ""))

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
		# mid swing: the next one's queued (it goes as this one lands) - pressed in time, as it lands, not
		# mashed through the wind-up (that's just a wasted press)
		var def: Dictionary = atk["def"]
		var t_hit := (float(def["hit"]) - float(def["from"])) / float(def["speed"])
		if float(atk["t"]) >= t_hit - 0.14:
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
		if gap > 0.05:
			# (the shove fades at 9 m/s each second: this much carries you just the gap, no further)
			foot.shove = to.normalized() * minf(sqrt(2.0 * 9.0 * minf(gap, 2.2)), 6.5)
		if tgt["kind"] == "cop":
			_provoked_by_swing(tgt)
	var dur := (float(def["to"]) - float(def["from"])) / float(def["speed"])
	av.play_once(String(def["clip"]), float(def["from"]), dur, float(def["speed"]), true, 0.09)
	atk = {"def": def, "t": 0.0, "landed": false, "queued": false, "tgt": tgt, "swished": false}
	stats["swings"] += 1
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
		if atk.is_empty():
			return          # (bounced off their guard: thrown off, the swing's over)
	# chained: once it's landed the next one can cut in
	# (the punch follows through before the next one comes: about two and a half a second, flat out)
	var can_cut: bool = atk["landed"] and float(atk["t"]) > t_hit + 0.2
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
	var f := _foe_of(tgt)
	# (down on the ground, or slipped out of the way: nothing there to hit)
	if not f.is_empty() and (float(f["down_t"]) > 0.0 or float(f["slip_t"]) > 0.0):
		if float(f["slip_t"]) > 0.0:
			stats["slipped"] += 1
			_recoil(foot, Vector3.ZERO, 0.35)          # (overreached into thin air)
			_counter(f)
		return
	# a foe with their guard up: it thuds off their arms
	if not f.is_empty() and float(f["block_t"]) > 0.0 and not bool(def.get("finisher", false)):
		game.sfx("block", -4.0, randf_range(0.9, 1.05))
		stats["blocked"] += 1
		_hitstop(0.04)
		game.shake = maxf(game.shake, 0.1)
		f["block_t"] = 0.0
		_knock(tgt, d * 0.3)
		# your fist bounces off their guard: thrown off a beat (that's when they come back at you)
		_recoil(foot, d, 0.45)
		_counter(f)
		return
	var dmg: float = float(def["dmg"]) * randf_range(0.9, 1.1)
	var heavy := bool(def.get("finisher", false)) or def == KICK
	stats["landed"] += 1
	if heavy:
		stats["heavy"] += 1
	game.sfx(("punch_heavy" if heavy else "punch_%d" % randi_range(1, 3)) if def["snd"] == "punch" else "kick_hit", -1.0 if heavy else -3.0, randf_range(0.92, 1.08))
	_hitstop(0.085 if heavy else 0.05)
	game.shake = maxf(game.shake, 0.38 if heavy else 0.2)
	game.buzz(60 if heavy else 35, 0.9 if heavy else 0.6)
	if def["react"] != "body" and randf() < (0.8 if heavy else 0.3):
		game.fx.blood(at, d, 6 if heavy else 3, 3.0)
	game.fx.puff(at, Color(1, 1, 1, 0.8), 0.12 if not heavy else 0.2, d * 2.0, 0.18, 0.0)
	if tgt["kind"] == "ped" and not tgt["ref"].has("solo") and not game.police.wanted() and game.chase_ok() and game.police._witnessed(me):
		game.police.start(1.0, "Assault in front of the police")
	if tgt["kind"] == "ped" and f.is_empty():
		_provoked_by_swing(tgt)          # (hit out of nowhere: they fight back, or run)
		f = _foe_of(tgt)
	var hp := _hurt(tgt, dmg)
	var av: Avatar = tgt["av"]
	if hp <= 0.0:
		_ko(tgt, d * (8.5 if heavy else 5.0) + Vector3(0, 2.2 if heavy else 1.0, 0))
		return
	# a big one may put them on the ground (the tough ones keep their feet more)
	if heavy and not f.is_empty() and randf() < (0.3 if f["prof"] == PROFILES["boxer"] else 0.6):
		_knockdown(f, d * 6.0 + Vector3(0, 1.6, 0))
		stats["knockdowns"] += 1
		fight_t = 4.0
		return
	# mid-swing, the heavy ones walk through a light punch and keep coming (you trade)
	# (a street fight's opponent most of all: they've come to trade)
	var armor := float(f["prof"].get("armor", 0.0)) if not f.is_empty() else 0.0
	if not f.is_empty() and (f["pr"] as Dictionary).has("solo"):
		armor = maxf(armor, 0.55)
	if not f.is_empty() and not f["atk"].is_empty() and not heavy and randf() < armor:
		stats["armored"] = int(stats.get("armored", 0)) + 1
		if av and is_instance_valid(av):
			av.hit(at, d, 0.6)
		fight_t = 4.0
		return
	if av and is_instance_valid(av):
		var r: Array = REACT.get(String(def["react"]), REACT["light"])
		if def["react"] == "ko":
			r = REACT["head"]
		av.play_once(String(r[0]), float(r[1]), (float(r[2]) - float(r[1])) / float(r[3]), float(r[3]), true, 0.05)
		av.hit(at, d, 1.5 if heavy else 1.1)
	var push := float(def["push"])
	if not f.is_empty():
		var prof: Dictionary = f["prof"]
		# hit again and again: rocked (reeling longer, knocked further back) - or, the good ones, they cover
		# up and come back at you
		f["hits"] = int(f["hits"]) + 1
		f["hit_t"] = 0.0
		var rocked := int(f["hits"]) >= 3
		f["atk"] = {}
		f["left"] = 0
		var solo := (f["pr"] as Dictionary).has("solo")
		if not solo:
			f["phase"] = "circle"
			f["cool"] = maxf(float(f["cool"]), 0.7 * float(prof["recover"]))
		else:
			# (a street fighter shakes it off and keeps coming: they're here to fight)
			f["phase"] = "press"
			f["left"] = randi_range(1, int(prof["combo"]))
		# (the good ones fire straight back as soon as they've shaken it off)
		if randf() < float(prof.get("counter", 0.2)) * 0.5:
			f["cool"] = 0.0
			f["phase"] = "press"
			f["left"] = randi_range(1, int(prof["combo"]))
		if rocked and float(prof["recover"]) <= 0.6:
			f["stun"] = 0.15
			f["block_t"] = 0.9
			f["hits"] = 0
			if av and is_instance_valid(av):
				av.play_once("fight_center_block", 0.15, 0.5, 1.3, true, 0.05)
		else:
			f["stun"] = (1.0 if rocked else (0.55 if heavy else 0.4)) * float(prof["recover"]) * (0.6 if solo else 1.0)
			if rocked:
				push *= 1.8
				f["hits"] = 0
	_knock(tgt, d * push)
	fight_t = 4.0

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
	for pr in solos:
		if pr.has("fight") and not pr.get("down", false) and is_instance_valid(pr["live"]):
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

## Out cold. Thrown by a big blow, or on uneven ground: limp (their own body, a ragdoll that settles on
## whatever's under it). Dropped by a lesser one on the flat: they fall back and lie there fitting a while.
## The body's cleared away a good while later (they're back on their feet somewhere else by then).
func _ko(c: Dictionary, vel: Vector3) -> void:
	_drop_foe(c)
	if c["kind"] == "cop":
		game.gunplay._officer_down(c["ref"], vel)
		game.save.add_stat("cops_down", 1)
		game.police.heat_pts += 0.4
		return
	var pr: Dictionary = c["ref"]
	var av = pr.get("live")
	var at: Vector3 = pr["pos"]
	pr.erase("fight")
	if pr.has("solo"):
		# a street fight's won: out cold (no police, no dropped cash: that's the purse)
		pr["down"] = true
		if av != null and is_instance_valid(av):
			(av as Avatar).fight = false
			(av as Avatar).go_limp(game, vel, vel * 0.3 + Vector3(0, 0.6, 0))
		game.save.add_stat("knockouts", 1)
		return
	# (the body's ours now: the crowd lets go of it without freeing it, and counts them down)
	if av != null and is_instance_valid(av):
		pr.erase("live")
		game.island.people._live.erase(pr)
	var info: Dictionary = game.island.people.knock_down(pr)
	if av == null or not is_instance_valid(av):
		if not info.is_empty():
			game.ragdolls.spawn(int(info["v"]), info["xf"], info["shoulders"], vel, game.foot)
	else:
		var a2: Avatar = av
		a2.fight = false
		var flat := _flat(at)
		if flat and (vel.length() < 7.0 and (randf() < 0.4 or game.args.has("kodrop"))):
			# fall back, fit, then still
			var dl: float = a2.anim.get_animation("fight_dying_backwards").length
			a2.play_once("fight_dying_backwards", 0.25, (dl - 0.25) / 1.2, 1.2, true, 0.06)
			var fit := "fight_tonic_seizure" if randf() < 0.5 else "fight_laying_seizure"
			var tw := a2.create_tween()
			tw.tween_interval((dl - 0.25) / 1.2 - 0.2)
			tw.tween_callback(func():
				a2.lock_t = 0.0
				a2.play(fit, 1.0, 0.35))
			tw.tween_interval(randf_range(4.0, 7.0))
			tw.tween_callback(func():
				a2._act_in("fight_dying_backwards", 0.8, dl - 0.02, 0.0)
				a2.lock_t = 99.0)
		else:
			a2.go_limp(game, vel, vel * 0.25 + Vector3(0, 0.5, 0))
		get_tree().create_timer(35.0, false).timeout.connect(func():
			if is_instance_valid(a2):
				a2.queue_free())
	game.save.add_stat("knockouts", 1)
	game.police.ped_hit(at)
	if randf() < 0.5:
		game.heist.drop_cash(at + Vector3(vel.x, 0, vel.z).normalized() * 0.8, randi_range(2, 8) * 5)
	game.island.people.panic(at, 10.0)

## Level enough to lie on (a fall and a fit look wrong across a slope or a kerb).
func _flat(p: Vector3) -> bool:
	var isl = game.island
	var h0: float = isl.height_at(p.x, p.z)
	for o in [Vector3(0.9, 0, 0), Vector3(-0.9, 0, 0), Vector3(0, 0, 0.9), Vector3(0, 0, -0.9)]:
		if absf(isl.height_at(p.x + o.x, p.z + o.z) - h0) > 0.06:
			return false
	return absf(p.y - h0) < 0.15

## Hit (or swung at) someone who wasn't fighting: in the street most swing back; the rest run and call it
## in. A police officer: that's assault, and they're onto you.
func _provoked_by_swing(c: Dictionary) -> void:
	if c["kind"] == "cop":
		if not game.police.wanted() and game.chase_ok_or_chase():
			game.police.start(1.0, "Assaulted an officer")
		return
	var pr: Dictionary = c["ref"]
	if not _foe_of(c).is_empty() or pr.get("fled", false):
		return
	if randf() < 0.55 + _grit(pr) * 0.45:
		_provoke(pr)
	else:
		_flee_and_call(pr)

## How likely they are to fight, and how good they are at it (fixed per person).
func _grit(pr: Dictionary) -> float:
	if not pr.has("grit"):
		pr["grit"] = randf()
	return float(pr["grit"])

## What sort of fighter: a scrapper goes down easy and swings wild and slow; a brawler can take a few and
## throws two at a time; a boxer's quick, blocks and slips your punches, throws threes, and takes a lot.
const PROFILES := {
	"scrapper": {"hp": 45.0, "spd": 0.95, "cool": [1.3, 2.3], "block": 0.08, "slip": 0.05, "combo": 1, "dmg": 0.8, "range": 1.9, "recover": 1.2},
	"brawler": {"hp": 75.0, "spd": 1.05, "cool": [0.9, 1.6], "block": 0.25, "slip": 0.12, "combo": 2, "dmg": 1.0, "range": 1.7, "recover": 0.7},
	"boxer": {"hp": 115.0, "spd": 1.2, "cool": [0.55, 1.1], "block": 0.4, "slip": 0.25, "combo": 3, "dmg": 1.25, "range": 1.55, "recover": 0.5},
}

func _profile(pr: Dictionary) -> String:
	if not pr.has("style"):
		var g := _grit(pr)
		pr["style"] = "boxer" if g > 0.78 or randf() < 0.1 else ("brawler" if g > 0.38 else "scrapper")
	return String(pr["style"])

func _provoke(pr: Dictionary) -> void:
	if pr.get("down", false) or pr["gone"]:
		return
	game.island.people.make_live(pr)
	pr["fight"] = true
	pr["flee"] = 0.0
	for f in foes:
		if f["pr"] == pr:
			return
	var st := _profile(pr)
	var prof: Dictionary = PROFILES[st]
	# (their health as that sort of fighter: what you've already done to them still counts)
	var taken := PERSON_HP - float(pr.get("fist_hp", PERSON_HP))
	pr["fist_hp"] = float(prof["hp"]) - taken
	pr["fist_max"] = float(prof["hp"])
	foes.append({"pr": pr, "prof": prof, "cool": randf_range(0.4, 0.9), "atk": {}, "stun": 0.0, "block_t": 0.0,
		"phase": "circle", "side": 1.0 if randf() < 0.5 else -1.0, "side_t": randf_range(1.0, 2.5), "left": 0,
		"slip_t": 0.0, "slip_v": Vector3.ZERO, "hits": 0, "hit_t": 9.0, "down_t": 0.0})
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

func _recoil(foot: CharacterBody3D, d: Vector3, t: float) -> void:
	recoil_t = t
	atk = {}
	since = 9.0          # (and the combo's broken)
	var av: Avatar = foot.avatar
	av.lock_t = 0.0
	if d != Vector3.ZERO:
		av.hit(foot.global_position + Vector3(0, 1.3, 0), -d, 0.7)
		foot.shove = -d * 1.4
	av.play_once(String(REACT["light"][0]), 0.15, t, 1.6, true, 0.05)

## They blocked or slipped you: the good ones make you pay, straight back with a combo of their own.
func _counter(f: Dictionary) -> void:
	if randf() < float(f["prof"].get("counter", 0.2)):
		f["cool"] = 0.0
		f["stun"] = 0.0
		f["phase"] = "press"
		f["left"] = randi_range(1, int(f["prof"]["combo"]))
	else:
		f["cool"] = maxf(float(f["cool"]), 0.4)

## Knocked off their feet (not out): limp a moment, then up again and back at you, angrier.
func _knockdown(f: Dictionary, vel: Vector3) -> void:
	var pr: Dictionary = f["pr"]
	var av = pr.get("live")
	if av == null or not is_instance_valid(av):
		return
	f["down_t"] = randf_range(1.8, 2.6)
	f["atk"] = {}
	f["stun"] = 0.0
	(av as Avatar).fight = false
	(av as Avatar).go_limp(game, vel, vel * 0.2 + Vector3(0, 0.4, 0))
	game.sfx("body_land", -4.0, randf_range(0.9, 1.05))

func _get_up(f: Dictionary, av: Avatar) -> void:
	var pr: Dictionary = f["pr"]
	var tp: Vector3 = av.limp.torso_pos() if av.limp else (pr["pos"] as Vector3)
	var p := Vector3(tp.x, game.island.height_at(tp.x, tp.z), tp.z)
	pr["pos"] = p
	av.recover()
	av.global_position = p
	av.play_once("get_up", 0.0, 1.0, 1.25, true, 0.1)
	f["stun"] = 1.0
	f["cool"] = float(f["prof"]["cool"][0])       # (up and straight back at you)
	f["phase"] = "circle"

## The people fighting you. They square up and circle you (the shuffle, one way then the other), sizing you
## up; then press in and throw a combo (as many punches as their sort throws), and back off again. Your
## wind-up, they may block or slip; hit, they reel; hit again and again, they're rocked; a big one may knock
## them down (they get up). Wind-ups you can read: block them, dodge them, or hit them first.
func _foes_tick(dt: float, foot: CharacterBody3D) -> void:
	# (anyone knocked back by a blow slides off a step)
	for pr in game.island.people._live + solos:
		if pr.has("fist_v"):
			var v: Vector3 = pr["fist_v"]
			var np: Vector3 = game.island.people.wall_move(pr["pos"], (pr["pos"] as Vector3) + v * dt)
			if np.distance_to(pr["pos"] as Vector3 + v * dt) > 0.05:
				v = Vector3.ZERO        # (into a wall: stopped dead)
			pr["pos"] = np
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
		var prof: Dictionary = f["prof"]
		if pr.has("solo") and not av.limp:
			av.global_position = pr["pos"]
			av.rotation.y = float(pr["face"]) + PI
		var to: Vector3 = me - (pr["pos"] as Vector3)
		to.y = 0.0
		var dist := to.length()
		if (dist > 30.0 and not pr.has("solo")) or game.gunplay.dying:
			foes.erase(f)
			pr.erase("fight")
			av.fight = false
			continue
		# down: limp, then up again
		if float(f["down_t"]) > 0.0:
			f["down_t"] = float(f["down_t"]) - dt
			if av.limp:
				var tp: Vector3 = av.limp.torso_pos()
				pr["pos"] = Vector3(tp.x, game.island.height_at(tp.x, tp.z), tp.z)
			if float(f["down_t"]) <= 0.0:
				_get_up(f, av)
			continue
		av.fight = true
		f["hit_t"] = float(f["hit_t"]) + dt
		if float(f["hit_t"]) > 2.0:
			f["hits"] = 0
		pr["face"] = lerp_angle(float(pr["face"]), atan2(-to.x, -to.z), 1.0 - exp(-dt * 8.0))
		# (no walking through you, or through each other)
		if dist < 0.85 and dist > 0.01:
			pr["pos"] = game.island.people.wall_move(pr["pos"], (pr["pos"] as Vector3) - to.normalized() * (0.85 - dist))
		for g in foes:
			if g != f:
				var gp2: Vector3 = (g["pr"] as Dictionary)["pos"]
				var sep: Vector3 = (pr["pos"] as Vector3) - gp2
				sep.y = 0.0
				if sep.length() < 0.9 and sep.length() > 0.01:
					pr["pos"] = game.island.people.wall_move(pr["pos"], (pr["pos"] as Vector3) + sep.normalized() * (0.9 - sep.length()) * 0.5)
		f["block_t"] = maxf(0.0, float(f["block_t"]) - dt)
		# slipping a punch: a quick step back and aside
		if float(f["slip_t"]) > 0.0:
			f["slip_t"] = float(f["slip_t"]) - dt
			_move(pr, f["slip_v"] as Vector3, dt)
			continue
		# (reeling from a hit: the good ones still get a guard up as you wind up the next)
		var reeling := float(f["stun"]) > 0.0
		if reeling:
			f["stun"] = float(f["stun"]) - dt
			if float(f["prof"]["recover"]) > 0.7 or float(f["stun"]) > 0.3:
				continue
		# you're winding up on them: guard up, or slip it
		if not atk.is_empty() and f["atk"].is_empty() and atk["tgt"].get("ref") == pr and not atk["landed"] and not atk.has("judged"):
			atk["judged"] = true
			var roll := randf()
			if roll < float(prof["slip"]):
				f["slip_t"] = 0.32
				var side := Vector3(-to.z, 0, to.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
				f["slip_v"] = (-to.normalized() * 2.6 + side * 2.0)
				av.play_once("fight_dodging_1", 0.35, 0.45, 1.6, true, 0.05)
				continue
			# (swing after swing at them, they read it and cover up more)
			var now: float = game.time
			f["read"] = minf(float(f.get("read", 0.0)) + 1.0, 4.0) if now - float(f.get("last_sw", -9.0)) < 0.9 else 0.0
			f["last_sw"] = now
			if roll >= float(prof["slip"]) and roll < float(prof["slip"]) + float(prof["block"]) + 0.12 * int(f["hits"]) + 0.08 * float(f["read"]):
				# (more likely the more you've just landed: they cover up)
				f["block_t"] = 0.6
				f["stun"] = 0.0
				av.play_once("fight_center_block", 0.15, 0.5, 1.3, true, 0.05)
		if reeling and float(f["stun"]) > 0.0:
			continue
		if not f["atk"].is_empty():
			_foe_swing(dt, f, av, foot, dist, to)
			continue
		f["cool"] = float(f["cool"]) - dt
		var spd := float(prof["spd"])
		if f["phase"] == "circle":
			# sizing you up: round you at their range, now and then switching which way
			f["side_t"] = float(f["side_t"]) - dt
			if float(f["side_t"]) <= 0.0:
				f["side"] = -float(f["side"])
				f["side_t"] = randf_range(1.0, 2.6)
			var want_r := float(prof["range"])
			var radial := clampf((dist - want_r) * 2.0, -1.6, 2.4)
			var lateral := 1.15 * spd * float(f["side"])
			var tn := to.normalized()
			var tang := Vector3(-tn.z, 0, tn.x)
			_move(pr, tn * radial + tang * lateral, dt)
			# (in their own frame for the shuffle: x to their left, y ahead)
			av.locomote(Vector2(lateral, radial))
			if float(f["cool"]) <= 0.0 and foot.down_t <= 0.0:
				f["phase"] = "press"
				f["left"] = randi_range(1, int(prof["combo"]))
		elif f["phase"] == "press":
			# in to arm's length, then the combo
			if dist > 1.2:
				var sp := minf(3.4 * spd, (dist - 1.05) * 4.0)
				_move(pr, to.normalized() * sp, dt)
				av.locomote(Vector2(0, sp))
			else:
				av.locomote(Vector2.ZERO)
				_foe_start(f, av)
		# beaten: some give up and run
		if not pr.has("solo") and float(pr.get("fist_hp", PERSON_HP)) < float(pr.get("fist_max", PERSON_HP)) * 0.2 and randf() < dt * 0.25:
			foes.erase(f)
			pr.erase("fight")
			av.fight = false
			_flee_and_call(pr)

func _move(pr: Dictionary, v: Vector3, dt: float) -> void:
	pr["pos"] = game.island.people.wall_move(pr["pos"], (pr["pos"] as Vector3) + v * dt)

func _foe_start(f: Dictionary, av: Avatar) -> void:
	var prof: Dictionary = f["prof"]
	var moves: Array = prof.get("moves", [0, 1, 2])
	var def: Dictionary = FOE_ATK[int(moves[randi() % moves.size()])]
	# (the quick ones throw them quicker)
	var sp := float(def["speed"]) * float(prof["spd"])
	f["atk"] = {"def": def, "t": 0.0, "landed": false, "sp": sp, "id": randi()}
	av.play_once(String(def["clip"]), float(def["from"]), (float(def["to"]) - float(def["from"])) / sp, sp, true, 0.08)

func _foe_swing(dt: float, f: Dictionary, av: Avatar, foot: CharacterBody3D, dist: float, to: Vector3) -> void:
	var a: Dictionary = f["atk"]
	var def: Dictionary = a["def"]
	var sp := float(a["sp"])
	a["t"] = float(a["t"]) + dt
	var t_hit := (float(def["hit"]) - float(def["from"])) / sp
	var t_end := (float(def["to"]) - float(def["from"])) / sp
	# (stepping into it as they throw: they mean to land it)
	if not a["landed"] and dist > 1.1:
		_move(f["pr"], to.normalized() * minf(3.0, (dist - 1.0) * 6.0), dt)
	if not a["landed"] and float(a["t"]) > t_hit - 0.09 and not a.get("sw", false):
		a["sw"] = true
		game.sfx("swish_1", -12.0, randf_range(0.85, 1.0))
	if not a["landed"] and float(a["t"]) >= t_hit:
		a["landed"] = true
		if dist >= 1.9:
			stats["their_whiffs"] = int(stats.get("their_whiffs", 0)) + 1
		if dist < 1.9:
			var from: Vector3 = f["pr"]["pos"]
			if dodge_t > 0.0:
				pass          # (stepped clean out of it)
			elif block_t > 0.0:
				stats["you_blocked"] += 1
				game.sfx("block", -3.0, randf_range(0.9, 1.05))
				game.shake = maxf(game.shake, 0.12)
				game.buzz(25, 0.5)
				_hitstop(0.04)
				# your arms take it (a jolt back), and they're thrown off balance: your opening
				var d2 := foot.global_position - from
				d2.y = 0.0
				d2 = d2.normalized() if d2.length() > 0.01 else Vector3.FORWARD
				(foot.avatar as Avatar).hit(foot.global_position + Vector3(0, 1.3, 0), d2, 0.6)
				foot.shove = d2 * 1.6
				f["stun"] = 0.75
				f["atk"] = {}
				f["left"] = 0
				f["phase"] = "circle"
				f["cool"] = randf_range(float(f["prof"]["cool"][0]), float(f["prof"]["cool"][1]))
				var r: Array = REACT["light"]
				av.play_once(String(r[0]), float(r[1]), 0.5, float(r[3]), true, 0.06)
				return
			else:
				stats["their_hits"] += 1
				hurt_you(float(def["dmg"]) * float(f["prof"]["dmg"]) * randf_range(0.9, 1.15), from, String(def["clip"]).contains("kick"))
	# combos: the next punch cuts in once this one's landed
	if a["landed"] and float(a["t"]) > t_hit + 0.1 and int(f["left"]) > 1:
		f["left"] = int(f["left"]) - 1
		f["atk"] = {}
		_foe_start(f, av)
		return
	if float(a["t"]) >= t_end:
		f["atk"] = {}
		av.lock_t = 0.0
		f["left"] = 0
		f["phase"] = "circle"
		f["cool"] = randf_range(float(f["prof"]["cool"][0]), float(f["prof"]["cool"][1]))

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
	elif game.fights and game.fights.active():
		game.fights.lost_by_ko(from)
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
