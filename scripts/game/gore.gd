extends Node3D
## What a bullet does to a person. Where it hits matters: the head (deadly), the body, an arm (they clutch it
## and run), a leg (they limp off). Hard enough (a heavy round, a close shotgun blast) a limb comes off: it
## goes tumbling, there's a raw stump, and it bleeds. Lose a leg and they go down and crawl away in agony,
## bleeding out, till they lie still (or you finish it). Killed, they go limp, thrown by the shot (the part
## that was hit kicked hardest), or now and then fall and fit before they're still. Each kind of hit has its
## own kick in your hand (the phone's vibration) and its own mark on the crosshair.
## The people about the island (people.gd) and the police on foot (gunplay.gd) both come through here.

const Avatar := preload("res://scripts/game/avatar.gd")

const MULT := {"head": 2.6, "torso": 1.0, "larm": 0.55, "rarm": 0.55, "lleg": 0.75, "rleg": 0.75, "lshin": 0.6, "rshin": 0.6}
const MAX_GIBS := 10
const CRAWL_SPEED := 0.42          # m/s, dragging themselves along (the crawl clip's own pace)

var game: Node
var gibs: Array = []               # {rb, t}
var crawlers: Array = []           # {av, pr, pos, face, t, life, hp, bleed_t, splat_d, bone, state}
var shot_n := 0                    # which trigger pull it is (the pellets of one blast add up)
var stats := {"hits": 0, "head": 0, "limbs": 0, "severed": 0, "crawlers": 0, "seizures": 0, "kills": 0}

func setup(g: Node) -> void:
	game = g

## A new pull of the trigger (gunplay calls it once per shot, before the pellets).
func new_shot() -> void:
	shot_n += 1

# ------------------------------------------------------------------ a person shot

## A person in the crowd shot at `at` going `d`. Returns 0 nothing, 1 hurt, 2 killed. raw: the round's damage.
func shoot_person(pr: Dictionary, d: Vector3, raw: float, at: Vector3) -> int:
	var av: Avatar = pr.get("live") if pr.has("live") and is_instance_valid(pr["live"]) else null
	if av == null or av.skel == null:
		return -1          # (not near enough to be a full character: the old way)
	var hb: Array = av._hit_bone(at, d)
	var limb := av.limb_of(int(hb[0]))
	var dmg: float = raw * float(MULT.get(limb, 1.0))
	stats["hits"] += 1
	pr["hp"] = float(pr.get("hp", 100.0)) - dmg
	var spot: Vector3 = hb[2]
	game.fx.blood(spot, d, 18 if limb == "head" else 12, 5.5)
	game.sfx("body_hit_%d" % randi_range(1, 3), -5.0, randf_range(1.0, 1.15))
	var dead := float(pr["hp"]) <= 0.0
	var off := _sever_roll(pr, limb, raw, dead)
	if dead:
		_kill_person(pr, av, d, raw, int(hb[0]), limb, off)
		return 2
	av.wound(spot, d)
	av.hit(spot, d, clampf(raw / 25.0, 0.7, 1.6))
	game.island.people.flinch(pr, d)
	if off != "":
		_sever(av, off, d, raw)
	match limb:
		"head":
			stats["head"] += 1
			game.buzz(70, 1.0)
			game.ui.hitmark("head")
		"lleg", "rleg", "lshin", "rshin":
			stats["limbs"] += 1
			pr["hurt"] = true            # (a limp from here on)
			game.buzz(35, 0.7)
			game.ui.hitmark("hit")
		_:
			game.buzz(30, 0.65)
			game.ui.hitmark("hit")
	# a leg gone: down, and crawling
	if off.ends_with("leg") or off.ends_with("shin"):
		_to_crawler(pr, av, d, int(hb[0]))
	else:
		game.island.people.panic(pr["pos"], 3.0)
	game.police.heat_pts += 0.1
	return 1

## Does this one take a limb off? A heavy enough hit (the pellets of one blast counted together), or a limb
## hit again and again. Returns the part ("" none).
func _sever_roll(pr: Dictionary, limb: String, raw: float, dead: bool) -> String:
	if limb == "torso":
		return ""
	var acc: Dictionary = pr.get("limb_acc", {})
	if int(pr.get("shot_n", -1)) != shot_n:
		pr["shot_n"] = shot_n
		pr["shot_raw"] = {}
	var sr: Dictionary = pr["shot_raw"]
	sr[limb] = float(sr.get(limb, 0.0)) + raw
	acc[limb] = float(acc.get(limb, 0.0)) + raw
	pr["limb_acc"] = acc
	var blast: float = sr[limb]
	if limb == "head":
		return "head" if dead and blast >= 40.0 and randf() < clampf((blast - 30.0) / 60.0, 0.25, 0.8) else ""
	var p := clampf((blast - 24.0) / 45.0, 0.0, 0.85)
	if float(acc[limb]) >= (110.0 if limb.ends_with("arm") else 130.0):
		p = 1.0
	if pr.get("severed_" + limb, false) or randf() >= p:
		return ""
	pr["severed_" + limb] = true
	return limb

func _sever(av: Avatar, part: String, d: Vector3, raw: float) -> void:
	var bn: String = Avatar.SEVER_AT.get(part, "")
	if bn == "" or av.severed.has(bn):
		return
	var bi := av.skel.find_bone(bn)
	var at: Vector3 = av.skel.global_transform * av.skel.get_bone_global_pose(bi).origin if bi >= 0 else av.global_position
	var gib := av.make_gib(self, bn, d * clampf(raw * 0.12, 2.5, 7.0))
	av.sever(part)
	if gib:
		gibs.append({"rb": gib, "t": 0.0})
		while gibs.size() > MAX_GIBS:
			var old: Dictionary = gibs.pop_front()
			if is_instance_valid(old["rb"]):
				(old["rb"] as Node).queue_free()
	game.fx.blood(at, d, 30, 6.5)
	game.fx.blood(at, -d + Vector3.UP, 14, 3.0)
	game.fx.splat(Vector3(at.x, game.island.height_at(at.x, at.z), at.z), randf_range(0.9, 1.3), 1.6)
	game.sfx("body_hit_%d" % randi_range(1, 3), -2.0, 0.8)
	game.buzz(120, 1.0)
	game.ui.hitmark("sever")
	stats["severed"] += 1
	game.save.add_stat("limbs_off", 1)
	# (it keeps bleeding, from the stump: a few spurts)
	for k in 6:
		get_tree().create_timer(0.25 + k * 0.35, false).timeout.connect(func():
			if is_instance_valid(av) and av.skel and bi >= 0:
				var par := av.skel.get_bone_parent(bi)
				var sp: Vector3 = av.skel.global_transform * av.skel.get_bone_global_pose(par if par >= 0 else bi).origin
				game.fx.blood(sp, Vector3(randf_range(-1, 1), 0.6, randf_range(-1, 1)), 5, 2.2))

## Dead: limp and thrown (the hit part kicked hardest), or (now and then, hit in the body) a fall and a fit.
func _kill_person(pr: Dictionary, av: Avatar, d: Vector3, raw: float, bone: int, limb: String, off: String) -> void:
	var at: Vector3 = pr["pos"]
	var body := _take(pr, av)
	if body == null:
		return
	stats["kills"] += 1
	if off != "":
		_sever(av, off, d, raw)
	var push := d * clampf(raw * 0.11, 2.5, 9.0)
	var seize: bool = limb != "head" and raw < 45.0 and off == "" and randf() < 0.28 and game.melee._flat(at)
	if seize:
		stats["seizures"] += 1
		var dl: float = av.anim.get_animation("fight_dying_backwards").length if av.anim.has_animation("fight_dying_backwards") else 1.5
		av.play_once("fight_dying_backwards", 0.25, (dl - 0.25) / 1.2, 1.2, true, 0.06)
		var fit := "fight_tonic_seizure" if randf() < 0.5 else "fight_laying_seizure"
		var tw := av.create_tween()
		tw.tween_interval((dl - 0.25) / 1.2 - 0.2)
		tw.tween_callback(func():
			av.lock_t = 0.0
			av.play(fit, 1.0, 0.35))
		tw.tween_interval(randf_range(3.0, 6.0))
		tw.tween_callback(func():
			av._act_in("fight_dying_backwards", 0.8, dl - 0.02, 0.0)
			av.lock_t = 99.0)
	else:
		av.go_limp(self, d * 1.5, push * 0.45 + Vector3(0, 0.5, 0), bone, push * (1.4 if limb == "head" else 1.0))
	game.fx.blood(at + Vector3(0, 0.9, 0), d, 26, 6.0)
	game.fx.splat(Vector3(at.x, game.island.height_at(at.x, at.z), at.z) + d * 0.7, randf_range(1.1, 1.5), 5.0)
	game.sfx("kill_ding", -10.0)
	game.buzz(90 if limb != "head" else 110, 1.0)
	game.ui.hitmark("kill")
	if limb == "head":
		game.melee._hitstop(0.05)
	_after_kill(at, d)
	get_tree().create_timer(40.0, false).timeout.connect(func():
		if is_instance_valid(av):
			av.queue_free())

func _after_kill(at: Vector3, d: Vector3) -> void:
	game.save.add_stat("people_hit", 1)
	game.gunplay.kills["people"] += 1
	if randf() < 0.75:
		game.heist.drop_cash(at + d * 0.8, randi_range(3, 12) * 5)
	game.police.heat_pts += 0.35
	game.police.ped_hit(at)

## The body's ours now: out of the crowd (its slot freed, counted down), the character left where it is.
func _take(pr: Dictionary, av: Avatar) -> Avatar:
	if not is_instance_valid(av):
		return null
	pr.erase("live")
	game.island.people._live.erase(pr)
	pr.erase("fight")
	game.island.people.knock_down(pr)
	av.fight = false
	av.hurt = false
	# (re-parented under us, so the crowd's clean-up doesn't take it)
	var xf := av.global_transform
	av.get_parent().remove_child(av)
	add_child(av)
	av.global_transform = xf
	return av

# ------------------------------------------------------------------ crawling away

func _to_crawler(pr: Dictionary, av: Avatar, d: Vector3, bone: int) -> void:
	var body := _take(pr, av)
	if body == null:
		return
	stats["crawlers"] += 1
	var face := atan2(-d.x, -d.z)          # (away from you, the way the shot went)
	var c := {"av": av, "pos": av.global_position, "face": face, "t": 0.0, "life": randf_range(14.0, 24.0),
		"hp": 40.0, "bleed_t": 0.0, "splat_d": 0.0, "state": "fall", "clip": "hurt_zombie_crawl"}
	crawlers.append(c)
	# down they go (a fall back), then the crawl
	av.lock_t = 0.0
	av.play_once("fight_dying_backwards", 0.25, 0.7, 1.4, true, 0.05)
	game.island.people.panic(c["pos"], 8.0)

func _crawl_tick(dt: float) -> void:
	for c in crawlers.duplicate():
		var av: Avatar = c["av"]
		if not is_instance_valid(av):
			crawlers.erase(c)
			continue
		c["t"] = float(c["t"]) + dt
		match String(c["state"]):
			"fall":
				if float(c["t"]) > 0.75:
					c["state"] = "crawl"
					av.lock_t = 0.0
					av.play(String(c["clip"]), 1.0, 0.3)
			"crawl":
				# dragging themselves along, away, leaving a trail; slower as they bleed out
				var k := clampf(1.0 - float(c["t"]) / float(c["life"]), 0.25, 1.0)
				var fwd := Vector3(-sin(float(c["face"])), 0, -cos(float(c["face"])))
				var np: Vector3 = game.island.people.wall_move(c["pos"], (c["pos"] as Vector3) + fwd * CRAWL_SPEED * k * dt)
				if np.distance_to(c["pos"] as Vector3 + fwd * CRAWL_SPEED * k * dt) > 0.02:
					c["face"] = float(c["face"]) + randf_range(0.6, 1.2) * (1.0 if randf() < 0.5 else -1.0)      # (a wall: turn off it)
				c["splat_d"] = float(c["splat_d"]) + (np - (c["pos"] as Vector3)).length()
				c["pos"] = np
				av.global_position = np
				av.rotation.y = float(c["face"]) + PI
				av.play(String(c["clip"]), k)
				c["bleed_t"] = float(c["bleed_t"]) - dt
				if float(c["bleed_t"]) <= 0.0:
					c["bleed_t"] = randf_range(0.25, 0.5)
					game.fx.blood(np + Vector3(0, 0.25, 0), fwd * -1.0 + Vector3(0, 0.4, 0), 3, 1.5)
				if float(c["splat_d"]) > 0.7:
					c["splat_d"] = 0.0
					game.fx.splat(np - fwd * 0.4, randf_range(0.45, 0.7), 0.2)
				if float(c["t"]) >= float(c["life"]):
					# bled out: a last fit, then still
					c["state"] = "fit"
					c["t"] = 0.0
					av.play("fight_laying_seizure", 1.0, 0.4)
			"fit":
				if float(c["t"]) > 3.5:
					c["state"] = "still"
					av.lock_t = 99.0
					get_tree().create_timer(30.0, false).timeout.connect(func():
						if is_instance_valid(av):
							av.queue_free())
			"still":
				crawlers.erase(c)

## Someone crawling, shot again: finished.
func shoot_crawler(c: Dictionary, d: Vector3, raw: float, at: Vector3) -> int:
	var av: Avatar = c["av"]
	c["hp"] = float(c["hp"]) - raw
	game.fx.blood(at, d, 14, 4.5)
	game.sfx("body_hit_%d" % randi_range(1, 3), -5.0)
	game.buzz(40, 0.8)
	if float(c["hp"]) > 0.0:
		game.ui.hitmark("hit")
		av.hit(at, d, 1.0)
		return 1
	crawlers.erase(c)
	var hb: Array = av._hit_bone(at, d)
	av.lock_t = 0.0
	av.go_limp(self, d, d * clampf(raw * 0.08, 2.0, 6.0), int(hb[0]), d * 4.0)
	game.ui.hitmark("kill")
	game.sfx("kill_ding", -10.0)
	game.buzz(90, 1.0)
	stats["kills"] += 1
	_after_kill(c["pos"], d)
	get_tree().create_timer(40.0, false).timeout.connect(func():
		if is_instance_valid(av):
			av.queue_free())
	return 2

## The nearest crawler along a shot (they're low: lying on the ground), before `max_t`: [crawler, t] or [].
func crawler_on(from: Vector3, d: Vector3, max_t: float) -> Array:
	var best: Array = []
	var bt := max_t
	for c in crawlers:
		if not is_instance_valid(c["av"]) or c["state"] == "still":
			continue
		var p: Vector3 = (c["pos"] as Vector3) + Vector3(0, 0.25, 0)
		var t := (p - from).dot(d)
		if t < 0.3 or t > bt:
			continue
		if (from + d * t).distance_to(p) < 0.55:
			bt = t
			best = [c, t]
	return best

# ------------------------------------------------------------------ every frame

func _process(dt: float) -> void:
	if game == null:
		return
	_crawl_tick(dt)
	for g in gibs.duplicate():
		g["t"] = float(g["t"]) + dt
		var rb: RigidBody3D = g["rb"]
		if not is_instance_valid(rb):
			gibs.erase(g)
			continue
		if float(g["t"]) < 1.5 and randf() < dt * 10.0:
			game.fx.blood(rb.global_position, rb.linear_velocity.normalized() * -1.0, 2, 1.5)
		if float(g["t"]) > 30.0:
			rb.queue_free()
			gibs.erase(g)
