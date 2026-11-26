extends Node
## A scripted player: plays a run of the game the way someone would, checking things as it goes, and prints
## PASS / FAIL lines (and a summary). Five players, each leaning on different parts of the game:
##   racer      the story's start, races (and the level locks), restarting with the police on you, rewinding
##   shopper    Lo-Fi Customs, the Armory (every gun, every part, every build), Lo-Fi Threads, Dez
##   fighter    on foot: guns, crouch and slide, swapping, reloading, the police, dying, getting busted
##   heister    level 10, a crew, a big heist (three bags, the drill burning out), your crew fighting, the cut
##   builder    levelling up, the story's steps, the garage and mansion built up, your cars, saving and loading
## godot --headless --path . --fixed-fps 60 -- --fresh --play=racer

const Weapons := preload("res://scripts/game/weapons.gd")
const Progress := preload("res://scripts/game/progress.gd")
const Avatar := preload("res://scripts/game/avatar.gd")
const CARS := preload("res://scripts/game/cars.gd")

var game: Node
var who := ""
var passes := 0
var fails: Array = []
var notes: Array = []

func check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
		print("PASS ", what)
	else:
		fails.append(what)
		print("FAIL ", what)

func note(s: String) -> void:
	notes.append(s)
	print("NOTE ", s)

var god := false               # (the heister: kept on its feet, to get through the whole heist)

func wait(t: float) -> void:
	var left := t
	while left > 0.0:
		var step := minf(left, 0.25)
		await get_tree().create_timer(step, true, false, false).timeout
		left -= step
		if god and game.gunplay:
			game.gunplay.hp = game.gunplay.MAX_HP

func wait_until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		if cond.call():
			return true
		await get_tree().create_timer(0.25, true, false, false).timeout
		t += 0.25
	return cond.call()

func _ready() -> void:
	who = String(game.args.get("play", "racer"))
	_run.call_deferred()

func _run() -> void:
	await wait(1.0)
	print("PLAY start ", who)
	match who:
		"racer":
			await _racer()
		"shopper":
			await _shopper()
		"fighter":
			await _fighter()
		"heister":
			await _heister()
		"builder":
			await _builder()
	print("PLAY done %s: %d passed, %d failed" % [who, passes, fails.size()])
	for f in fails:
		print("PLAY failed: ", f)
	get_tree().quit()

## XP the quick way: as if you'd done this many races (it's all worked out from your stats).
func _give_level(lv: int) -> void:
	var s = game.save
	var n := 0
	while Progress.level(s) < lv and n < 4000:
		s.data["stats"]["races"] = s.stat("races") + 5
		n += 1
	game.ach_check()

# ------------------------------------------------------------------ the racer

func _racer() -> void:
	game.start_drive()
	await wait(1.0)
	check(game.on_foot, "fresh game: you start on foot by the car")
	check(game.story.step == 0 and game.story.goal() != "", "story: first goal shown (%s)" % game.story.goal())
	await wait(5.0)
	game.toggle_foot()
	await wait(1.0)
	check(not game.on_foot, "into Jay's car")
	await wait_until(func(): return game.story.step >= 1, 4.0)
	check(game.story.step == 1, "story: on to 'win some cash'")
	# the level locks on race difficulty
	game.save.data["settings"]["race_diff"] = 2
	check(game.race_diff() == 0, "level 1: hard races locked (falls back to easy)")
	game.save.data["settings"]["race_diff"] = 0
	# a race, the CPU driving
	var rid: String = String(game.island.races[0]["id"])
	var coins0 := int(game.save.data["coins"])
	game.args["raceauto"] = true
	game.start_challenge_now("race", rid)
	await wait(2.0)
	check(game.race != null, "race %s started" % rid)
	# the police turn up mid race: rewinding still works, and so does restarting
	await wait_until(func(): return game.race != null and game.race.state == 1, 20.0)
	await wait(6.0)
	game.police.start(2.0, "A test")
	await wait(0.5)
	check(game.rewind_ok(), "rewind allowed in a race with the police on you")
	var rw0: int = int(game.race.rewinds) if game.race else 0
	var buf0: int = game.rw_buf.size()
	game.held["rewind"] = true
	await wait(0.8)
	var rewound: bool = game.rewinding or (game.race != null and int(game.race.rewinds) > rw0)
	game.held["rewind"] = false
	await wait(0.5)
	check(rewound, "rewinding happened (buffer %d)" % buf0)
	game.restart_challenge()
	await wait(1.5)
	check(not game.police.wanted(), "restart called the police off")
	check(game.race != null, "race running again after the restart")
	# let it run to the end
	var finished := await wait_until(func(): return game.race != null and game.race.state == 2, 420.0)
	check(finished, "the race finished (CPU driving)")
	await wait(1.0)
	var earned := int(game.save.data["coins"]) - coins0
	check(earned > 0, "the race paid out ($%d)" % earned)
	await wait_until(func(): return game.story.step >= 2, 6.0)
	check(game.story.step >= 2, "story: on to the shops after the first race")
	# a second run of the same race pays again (repeat pay)
	var c1 := int(game.save.data["coins"])
	await wait(5.0)
	game.start_challenge_now("race", rid)
	var fin2 := await wait_until(func(): return game.race != null and game.race.state == 2, 420.0)
	await wait(1.0)
	check(fin2 and int(game.save.data["coins"]) > c1, "a repeat run pays too")
	game.args.erase("raceauto")
	game.quit_challenge()
	await wait(1.0)
	check(not game.challenge_on(), "left the race")
	# a zone and a trial start and stop cleanly
	if not game.island.zones.is_empty():
		game.start_challenge_now("zone", String(game.island.zones[0]["id"]))
		await wait(6.0)
		check(game.challenge_on(), "drift zone runs")
		game.quit_challenge()
		await wait(1.0)
	if not game.island.trials.is_empty():
		game.start_challenge_now("trial", String(game.island.trials[0]["id"]))
		await wait(6.0)
		check(game.challenge_on(), "trial runs")
		game.quit_challenge()
		await wait(1.0)

# ------------------------------------------------------------------ the shopper

func _shopper() -> void:
	game.args["drive"] = true
	game.start_drive()
	game.save.data["coins"] = 400000
	_give_level(30)
	await wait(1.0)
	check(Progress.level(game.save) == 30, "levelled to 30")
	# ---- Lo-Fi Customs: buy a car, come out in it
	var sp: Vector3 = game.shops.door_of("customs")
	game.car.place(Transform3D(Basis(), sp + game.shops.shops["customs"]["front"] * 6.0 + Vector3(0, 0.6, 0)))
	await wait(1.5)
	game.shops.tick(0.1)
	check(game.shops.near == "customs", "pulled up at Lo-Fi Customs: the door prompt")
	game.shops.enter()
	await wait(0.5)
	check(game.state == game.GARAGE and game.ui.g_mode == "customs", "inside Lo-Fi Customs")
	var buy_id := "racer"
	game.ui.g_index = CARS.index_of(buy_id)
	game.ui._garage_refresh()
	game.ui._garage_action()
	check(game.save.owns(buy_id) and String(game.save.data["car"]) == buy_id, "bought the Quicksilver")
	game.ui.g_tab = "paint"
	game.ui._garage_refresh()
	game.ui.g_tab = "tune"
	game.ui._garage_refresh()
	game.ui.g_tab = "up"
	game.ui._garage_refresh()
	game.close_garage(game.DRIVE)
	await wait(1.0)
	check(game.state == game.DRIVE and game.car.global_position.distance_to(sp) < 25.0, "out front of the shop in it")
	# ---- the Armory: every gun, every preset, every part
	var bad: Array = []
	var tried := 0
	for w in Weapons.LIST:
		var ps: Array = Weapons.presets(w)
		if ps.is_empty():
			bad.append("%s: no presets" % w["id"])
			continue
		for pn in ps:
			var b := Weapons.preset_build(w, String(pn))
			var a := Weapons.assemble(w, b)
			var lw := Weapons.with_build(w, b)
			tried += 1
			if (a["mesh"] as Mesh).get_surface_count() == 0:
				bad.append("%s %s: no mesh" % [w["id"], pn])
			if int(lw["mag"]) <= 0:
				bad.append("%s %s: mag %d" % [w["id"], pn, int(lw["mag"])])
			if bool(w["both"]) and a["support"] == Vector3.INF:
				bad.append("%s %s: no hold for the left hand" % [w["id"], pn])
			if float(a["len"]) < 0.12 or float(a["len"]) > 1.9:
				bad.append("%s %s: length %.2f m" % [w["id"], pn, float(a["len"])])
		# every part on its socket, on the first preset
		var b0 := Weapons.default_build(w)
		for sk in game.ui._gun_sockets(w, b0):
			for pn2 in Weapons.parts_for(w, sk):
				var nb := {"base": b0["base"], "parts": (b0["parts"] as Dictionary).duplicate()}
				nb["parts"][sk] = pn2
				var a2 := Weapons.assemble(w, nb)
				tried += 1
				if (a2["mesh"] as Mesh).get_surface_count() == 0:
					bad.append("%s +%s: no mesh" % [w["id"], pn2])
				if Weapons.part_price(w, pn2) <= 0:
					bad.append("%s %s: free" % [w["id"], pn2])
				if Weapons.describe(pn2) == "":
					bad.append("%s %s: no description" % [w["id"], pn2])
	check(bad.is_empty(), "every gun, preset and part assembles (%d builds)%s" % [tried, "" if bad.is_empty() else ": " + ", ".join(bad.slice(0, 8))])
	# buy a carbine, put a scope and a suppressor on it, carry it
	game.open_shop("armory")
	await wait(0.5)
	check(game.state == game.GARAGE and game.ui.g_mode == "armory", "inside the Armory")
	var s = game.save.data
	var w := Weapons.by_id("carbine")
	s["coins"] = int(s["coins"]) - int(w["price"])
	if not s.has("guns"):
		s["guns"] = ["pistol"]
	(s["guns"] as Array).append("carbine")
	game.ui.g_gun = "carbine"
	game.ui._garage_refresh()
	var b1: Dictionary = Weapons.build_of(game.save, "carbine")
	var nb1 := {"base": b1["base"], "parts": (b1["parts"] as Dictionary).duplicate()}
	var optic := ""
	for pn3 in Weapons.parts_for(w, "optic"):
		if "Scope" in pn3 or "4x" in pn3 or "Prism" in pn3:
			optic = pn3
	var muz := ""
	for pn4 in Weapons.parts_for(w, "muzzle"):
		if "Suppressor" in pn4:
			muz = pn4
	if optic != "":
		nb1["parts"]["optic"] = optic
	if muz != "":
		nb1["parts"]["muzzle"] = muz
	var c0 := int(s["coins"])
	game.ui._buy_build(w, nb1)
	var lw2: Dictionary = Weapons.loadout(game.save, "carbine")
	check(int(s["coins"]) < c0, "paid for the parts")
	check(optic == "" or float(lw2["zoom"]) > 1.2, "the optic zooms (%.2f)" % float(lw2["zoom"]))
	check(muz == "" or bool(lw2["quiet"]), "the suppressor quiets it")
	# the picker for a socket draws
	game.ui.g_slot = "optic"
	game.ui._garage_refresh()
	game.ui.g_slot = ""
	game.close_garage(game.DRIVE)
	await wait(0.5)
	s["gun"] = "carbine"
	game.toggle_foot()
	await wait(1.0)
	game.gunplay.holstered = false
	game.gunplay.equip()
	var av = game.foot.avatar
	check(av.gun != null and av.aim.fore_pt != Vector3.INF, "carrying the carbine, left hand on its hold")
	check(int(game.gunplay.ammo.get("carbine", 0)) == int(lw2["mag"]), "the magazine matches the build (%d)" % int(lw2["mag"]))
	game.toggle_foot()
	await wait(1.0)
	# ---- Lo-Fi Threads: try one on, buy it
	game.open_shop("threads")
	await wait(0.5)
	var ci := 20
	var cid: String = Avatar.CHARS[ci][0]
	game.ui.g_char_try = cid
	game.ui._garage_refresh()
	s["coins"] = int(s["coins"]) - Progress.char_price(ci)
	var ho: Array = s.get("chars_owned", [])
	ho.append(cid)
	s["chars_owned"] = ho
	s["avatar"] = cid
	game.ui.g_char_try = ""
	game.ui._garage_refresh()
	game.close_garage(game.DRIVE)
	await wait(0.5)
	game.toggle_foot()
	await wait(1.0)
	check(game.foot != null and game.foot.avatar.skel != null, "on foot as %s" % Avatar.CHARS[ci][1])
	game.toggle_foot()
	await wait(1.0)
	# ---- Dez brings the Bug
	var here: Vector3 = game.car.global_position
	game.deliver_car("bug")
	await wait(7.5)
	check(String(game.save.data["car"]) == "bug", "Dez delivered the Bug")
	check(game.car.global_position.distance_to(here) < 40.0, "delivered near you (%.0f m)" % game.car.global_position.distance_to(here))

# ------------------------------------------------------------------ the fighter

func _fighter() -> void:
	game.args["drive"] = true
	game.start_drive()
	game.save.data["guns"] = ["pistol", "smg", "rifle", "shotgun", "sniper", "lmg"]
	await wait(1.0)
	game.toggle_foot()
	await wait(1.0)
	check(game.on_foot, "out on foot")
	var f = game.foot
	# crouch, stand, slide out of a sprint
	f.toggle_crouch()
	await wait(0.6)
	check(f.crouch and f.avatar.crouch, "crouched")
	f.toggle_crouch()
	await wait(0.4)
	check(not f.crouch, "stood back up")
	game.held["sprint"] = true
	game.stick = Vector2(0, 1)
	await wait(2.0)
	f.toggle_crouch()
	await wait(0.1)
	check(f.slide_t > 0.0 and f.crouch, "slid into a crouch from a sprint")
	await wait(1.2)
	check(f.crouch and f.slide_t <= 0.0, "crouched after the slide")
	game.held["sprint"] = false
	game.stick = Vector2.ZERO
	await wait(0.5)
	f.toggle_crouch()
	await wait(0.5)
	# every gun out in turn, fired, reloaded
	for gid in game.save.data["guns"]:
		game.police.clear()          # (the shots bring the police: not yet, this is the range)
		game.gunplay.hp = game.gunplay.MAX_HP
		game.gunplay.select(String(gid))
		await wait(0.4)
		check(String(game.gunplay.weapon.get("id", "")) == String(gid) and f.avatar.gun != null, "%s in hand" % gid)
		game.gunplay.ammo[gid] = 1
		game.held["fire"] = true
		await wait(0.6)
		game.held["fire"] = false
		await wait(0.2)
		game.held["reload"] = true
		await wait(0.2)
		game.held["reload"] = false
		await wait(float(game.gunplay.weapon["reload"]) + 0.5)
		check(int(game.gunplay.ammo.get(gid, 0)) == int(game.gunplay.weapon["mag"]), "%s reloaded to %d (has %d, reload %.1f s, reloading %.1f)" % [gid, int(game.gunplay.weapon["mag"]), int(game.gunplay.ammo.get(gid, 0)), float(game.gunplay.weapon["reload"]), float(game.gunplay.reload_t)])
	game.gunplay.select("rifle")
	game.police.clear()
	await wait(1.0)
	if not game.on_foot:
		game.toggle_foot()
		await wait(1.0)
	# the police come; shoot it out (the test aimer: whoever's in front)
	game.police.start(3.0, "A test")
	game.args["guntest"] = "rifle"
	game.set_meta("gt_out", true)
	var got_officers := await wait_until(func(): return game.gunplay.officers.size() > 0, 40.0)
	check(got_officers, "officers came out at you")
	for k in 30:
		game.gunplay.hp = maxf(game.gunplay.hp, 60.0)      # (staying up long enough to see it)
		await wait(0.5)
	var downs: int = int(game.gunplay.kills["police"])
	note("officers down in 15 s: %d, your hp %.0f" % [downs, float(game.gunplay.hp)])
	game.args.erase("guntest")
	# shot dead: WASTED, then back up
	if not game.on_foot:
		game.toggle_foot()
		await wait(1.0)
	game.gunplay.hurt(500.0, game.foot.global_position + Vector3(5, 1, 0))
	await wait(0.5)
	check(game.gunplay.dying, "down")
	await wait(4.5)
	check(not game.gunplay.dying and float(game.gunplay.hp) > 0.0 and not game.police.wanted(), "back up after WASTED, the police gone")
	# busted
	game.police.start(2.0, "A test")
	await wait(1.0)
	if game.has_method("_busted_scene"):
		game.police._busted()
		await wait(7.0)
		check(game.busted_t <= 0.0 and game.state == game.DRIVE, "let go after being busted")

# ------------------------------------------------------------------ the heister

func _heister() -> void:
	god = true
	game.args["drive"] = true
	game.start_drive()
	_give_level(12)
	game.save.data["guns"] = ["pistol", "rifle"]
	game.save.data["gun"] = "rifle"
	await wait(1.0)
	check(Progress.level(game.save) >= 10, "level %d: heists open" % Progress.level(game.save))
	# a crew of two
	for nm in ["Kai", "Nova"]:
		var w2: int = game.crew._who(nm)
		(game.save.data["contacts"] as Array).append(nm)
		game.crew._make_room()
		var d: Dictionary = game.crew._spawn(w2, true)
		if not d.is_empty():
			game.crew._join_crew(d)
	await wait(6.0)
	check(game.crew.crew_count() == 2, "two friends driving with you")
	# out at a safe; start it (a big one: three bags, maybe the drill burns out)
	game.args["heisttier"] = 4
	var hs: Dictionary = game.heist.safes[0]
	var front: Vector3 = (hs["node"] as Node3D).global_transform * Vector3(0, 0.5, 3.0)
	game.car.place(Transform3D(Basis(), front + Vector3(6, 0.6, 6)))
	await wait(4.0)
	game.toggle_foot()
	game.foot.place(front, float(hs["yaw"]))
	await wait(1.0)
	game.heist.tick(0.1)
	check(not game.heist.near.is_empty(), "by the safe: START HEIST shows")
	game.heist.start()
	check(game.heist.active() and game.heist.crew_in.size() == 2, "heist on, crew in: %s" % str(game.heist.crew_in))
	check(game.heist.bags_total == 3, "tier 4: three bags")
	# the tool bag, back to the safe
	game.foot.place(game.heist.drill.global_position + Vector3(1.0, 0.5, 0), 0.0)
	await wait(1.0)
	check(game.heist.carrying == "tool_duffle", "got the tool bag")
	game.foot.place(front, float(hs["yaw"]))
	await wait(1.5)
	check(game.heist.state == game.heist.DEFEND, "drill on the safe")
	# your crew get out and fight
	game.police.start(3.0, "A test")
	var out := await wait_until(func(): return game.allies.list.size() > 0, 20.0)
	check(out, "your crew got out to fight (%d)" % game.allies.list.size())
	await wait(10.0)
	note("officers out %d, down %d, crew up %d" % [game.gunplay.officers.size(), int(game.gunplay.kills["police"]), game.allies.alive().size()])
	# skip the drilling (through a breakdown if there is one)
	var guard := 0
	while game.heist.state != game.heist.CRACKED and guard < 6:
		guard += 1
		if game.heist.state == game.heist.DEFEND:
			game.heist.drill_t = maxf(game.heist.drill_t, game.heist.defend_t - 0.5) if game.heist.break_at < 0.0 else game.heist.break_at + 0.1
			await wait(1.0)
		elif game.heist.state == game.heist.FETCH:
			note("the drill burnt out: fetching another")
			game.foot.place(game.heist.drill.global_position + Vector3(1.0, 0.5, 0), 0.0)
			await wait(1.0)
			game.foot.place(front, float(hs["yaw"]))
			await wait(1.5)
		else:
			await wait(1.0)
	check(game.heist.state == game.heist.CRACKED, "the safe's open")
	# three bags: two trips to the car, the last one carried off
	var safe_in: Vector3 = (hs["node"] as Node3D).global_transform * Vector3(0, 0.5, 1.6)
	for k in 3:
		await wait(1.5)
		game.foot.place(safe_in, float(hs["yaw"]))
		await wait(1.0)
		if k < 2:
			check(game.heist.state == game.heist.STASH, "bag %d: take it to the car" % (k + 1))
			game.foot.place(game.car.global_position + Vector3(2.2, 0.5, 0), 0.0)
			await wait(1.0)
			check(game.heist.state == game.heist.CRACKED, "bag %d stashed" % (k + 1))
	check(game.heist.state == game.heist.ESCAPE, "last bag: get away")
	game.police.clear()
	await wait(1.0)
	var pay: int = game.heist.pay
	var c0 := int(game.save.data["coins"])
	game.foot.place(game.heist._drop_at() + Vector3(0, 0.5, 0), 0.0)
	await wait(1.5)
	var got := int(game.save.data["coins"]) - c0
	check(game.heist.state == game.heist.IDLE and got == pay - int(float(pay) * 0.15) * 2, "heist done: $%d of $%d after the crew's cut" % [got, pay])
	await wait(1.0)
	check(game.allies.list.size() > 0, "crew still out with you on foot after the heist")
	game.foot.place(game.car.global_position + Vector3(2.0, 0.5, 0), 0.0)
	await wait(0.5)
	game.toggle_foot()
	await wait(1.0)
	check(not game.on_foot and game.allies.list.is_empty(), "crew back in their cars when you drove off")

# ------------------------------------------------------------------ the builder

func _builder() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait_until(func(): return int(game.save.data.get("level_seen", 0)) > 0, 5.0)
	var c0 := int(game.save.data["coins"])
	var lv0 := Progress.level(game.save)
	_give_level(8)
	await wait(0.5)
	check(Progress.level(game.save) == 8 and int(game.save.data.get("level_seen", 0)) == 8, "levelled 1 -> 8")
	var expect := 0
	for l in range(lv0 + 1, 9):
		expect += Progress.cash_for(l)
	check(int(game.save.data["coins"]) - c0 == expect, "level cash paid ($%d)" % expect)
	check(game.Cards.packs(game.save) >= 7, "card packs waiting (%d)" % game.Cards.packs(game.save))
	# build the garage all the way up
	game.save.data["coins"] = 2000000
	var g: Node = game.property.props["garage"]["node"]
	var tg: Array = game.property.props["garage"]["def"]["targets"]
	var stages := 0
	while int(g.get("built_count")) < tg.size() and stages < 20:
		var need: int = int(tg[int(g.get("built_count"))]) - int(g.get("invested"))
		var took: int = int(g.call("deposit", maxi(need, 1)))
		game.save.data["coins"] = int(game.save.data["coins"]) - took
		stages += 1
		await wait(2.0)
	check(game.property.finished("garage"), "garage built (%d stages)" % stages)
	check(game.property.garage_open(), "its bays are up")
	game.save.data["owned"] = ["bug", "roadster", "taxi", "racer"]
	game.open_garage("own")
	await wait(0.5)
	var seen := {}
	for k in 6:
		game.ui._garage_step(1)
		seen[String(CARS.LIST[game.ui.g_index]["id"])] = true
	var only_owned := true
	for id in seen:
		if not game.save.owns(String(id)):
			only_owned = false
	check(only_owned, "your garage shows only your cars (%s)" % str(seen.keys()))
	game.close_garage(game.DRIVE)
	await wait(0.5)
	# the mansion
	var m: Node = game.property.props["mansion"]["node"]
	var tm: Array = game.property.props["mansion"]["def"]["targets"]
	stages = 0
	while int(m.get("built_count")) < tm.size() and stages < 20:
		var need2: int = int(tm[int(m.get("built_count"))]) - int(m.get("invested"))
		m.call("deposit", maxi(need2, 1))
		stages += 1
		await wait(2.0)
	check(game.property.finished("mansion"), "mansion built (%d stages)" % stages)
	# the story all the way through
	game.story.step = 3
	_give_level(10)
	game.save.data["stats"]["heists"] = 1
	game.save.data["property"] = {"garage": 85000, "mansion": 250000}
	var reached := await wait_until(func(): return game.story.step >= game.story.STEPS.size() - 1, 12.0)
	check(reached, "story to the end (step %d)" % game.story.step)
	# saving and loading
	game._save_now()
	var SaveData = preload("res://scripts/game/save.gd")
	var s2 = SaveData.new()
	s2.load_data()
	check(int(s2.data["coins"]) == int(game.save.data["coins"]) and int(s2.data.get("story", -1)) == game.story.step, "saved and loaded back")
	check((s2.data.get("owned", []) as Array).size() == 4, "owned cars kept")
