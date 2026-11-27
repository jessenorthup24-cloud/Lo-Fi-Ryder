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

## A screenshot of this moment (with --snap=<dir>, run with a display: xvfb-run).
var _snap_n := 0
func snap(what: String) -> void:
	if not game.args.has("snap") or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_snap_n += 1
	var path := "%s/%s_%02d_%s.png" % [String(game.args["snap"]), who, _snap_n, what]
	get_viewport().get_texture().get_image().save_png(path)
	print("SNAP ", path)

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
		"tutor":
			await _tutor()
		"brawler":
			await _brawler()
		"brawlseq":
			await _brawlseq()
		"kotest":
			await _kotest()
		"street":
			await _street()
		"campaign":
			await _campaign()
		"fightsim":
			await _fightsim()
		"notices":
			await _notices()
		"places":
			for pl in game.island.places:
				print("PLACE %s %s r%.0f" % [pl["name"], pl["pos"], float(pl.get("r", 0))])
		"bank":
			await _bank()
		"dispatch":
			await _dispatch()
		"atms":
			await _atms()
		"mapper":
			await _mapper()
		"ram":
			await _ram()
		"ram2":
			await _ram2()
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
	await wait(2.0)
	await snap("title")
	game.start_drive()
	await wait(1.4)
	await snap("intro_card")
	await wait(2.0)
	check(game.on_foot, "fresh game: you start on foot by the car")
	check(game.story.step == 0 and game.story.goal() != "", "story: first goal shown (%s)" % game.story.goal())
	await wait(1.6)
	await snap("jay_text_on_foot")
	await wait(3.4)
	game.toggle_foot()
	await wait(1.0)
	await snap("driving_hud")
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
	await snap("race_intro")
	check(game.race != null, "race %s started" % rid)
	# the police turn up mid race: rewinding still works, and so does restarting
	await wait_until(func(): return game.race != null and game.race.state == 1, 20.0)
	await wait(6.0)
	await snap("race_mid")
	game.police.start(2.0, "A test")
	await wait(0.5)
	check(game.rewind_ok(), "rewind allowed in a race with the police on you")
	var rw0: int = int(game.race.rewinds) if game.race else 0
	var buf0: int = game.rw_buf.size()
	game.held["rewind"] = true
	await wait(0.5)
	await snap("rewinding")
	await wait(0.3)
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
	await snap("race_result")
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
		await snap("zone")
		check(game.challenge_on(), "drift zone runs")
		game.quit_challenge()
		await wait(1.0)
	if not game.island.trials.is_empty():
		game.start_challenge_now("trial", String(game.island.trials[0]["id"]))
		await wait(6.0)
		await snap("trial")
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
	await snap("customs_door")
	check(game.shops.near == "customs", "pulled up at Lo-Fi Customs: the door prompt")
	game.shops.enter()
	await wait(0.5)
	check(game.state == game.GARAGE and game.ui.g_mode == "customs", "inside Lo-Fi Customs")
	var buy_id := "racer"
	game.ui.g_index = CARS.index_of(buy_id)
	game.ui._garage_refresh()
	await snap("customs_cars")
	game.ui._garage_action()
	await wait(0.3)
	await snap("customs_bought")
	check(game.save.owns(buy_id) and String(game.save.data["car"]) == buy_id, "bought the Quicksilver")
	for tb in ["paint", "tune", "up"]:
		game.ui.g_tab = tb
		game.ui._garage_refresh()
		await wait(0.3)
		await snap("customs_" + tb)
	game.close_garage(game.DRIVE)
	await wait(1.0)
	await snap("customs_out_front")
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
	await wait(0.3)
	await snap("armory_carbine")
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
	await wait(0.3)
	await snap("armory_built")
	game.ui.g_slot = "optic"
	game.ui._garage_refresh()
	await wait(0.3)
	await snap("armory_optic_picker")
	game.ui.g_slot = ""
	game.close_garage(game.DRIVE)
	await wait(0.5)
	s["gun"] = "carbine"
	game.toggle_foot()
	await wait(1.0)
	game.gunplay.holstered = false
	game.gunplay.equip()
	var av = game.foot.avatar
	await wait(0.5)
	await snap("carbine_on_foot")
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
	await wait(0.4)
	await snap("threads_try_on")
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
	game.ui.toggle_phone()
	game.ui.phone._mode = "dez"
	game.ui.phone._sig = ""
	game.ui.phone.refresh()
	await wait(0.6)
	await snap("phone_dez")
	game.ui.toggle_phone()
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
	await snap("on_foot")
	var f = game.foot
	# crouch, stand, slide out of a sprint
	f.toggle_crouch()
	await wait(0.6)
	await snap("crouched")
	check(f.crouch and f.avatar.crouch, "crouched")
	f.toggle_crouch()
	await wait(0.4)
	check(not f.crouch, "stood back up")
	game.held["sprint"] = true
	game.stick = Vector2(0, 1)
	await wait(2.0)
	await snap("sprinting")
	f.toggle_crouch()
	await wait(0.25)
	await snap("sliding")
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
		await wait(0.3)
		await snap("firing_" + String(gid))
		await wait(0.3)
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
		if k % 10 == 5:
			await snap("shootout")
	var downs: int = int(game.gunplay.kills["police"])
	note("officers down in 15 s: %d, your hp %.0f" % [downs, float(game.gunplay.hp)])
	game.args.erase("guntest")
	# shot dead: WASTED, then back up
	if not game.on_foot:
		game.toggle_foot()
		await wait(1.0)
	game.gunplay.hurt(500.0, game.foot.global_position + Vector3(5, 1, 0))
	await wait(0.8)
	await snap("wasted")
	check(game.gunplay.dying, "down")
	await wait(4.5)
	check(not game.gunplay.dying and float(game.gunplay.hp) > 0.0 and not game.police.wanted(), "back up after WASTED, the police gone")
	# busted
	game.police.start(2.0, "A test")
	await wait(1.0)
	if game.has_method("_busted_scene"):
		game.police._busted()
		await wait(1.5)
		await snap("busted")
		await wait(5.5)
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
	await snap("safe_start")
	check(not game.heist.near.is_empty(), "by the safe: START HEIST shows")
	game.heist.start()
	check(game.heist.active() and game.heist.crew_in.size() == 2, "heist on, crew in: %s" % str(game.heist.crew_in))
	check(game.heist.bags_total == 3, "tier 4: three bags")
	await wait(1.0)
	await snap("heist_fetch")
	# the tool bag, back to the safe
	game.foot.place(game.heist.drill.global_position + Vector3(1.0, 0.5, 0), 0.0)
	await wait(1.0)
	check(game.heist.carrying == "tool_duffle", "got the tool bag")
	game.foot.place(front, float(hs["yaw"]))
	await wait(1.5)
	await snap("heist_drilling")
	check(game.heist.state == game.heist.DEFEND, "drill on the safe")
	# your crew get out and fight
	game.police.start(3.0, "A test")
	var out := await wait_until(func(): return game.allies.list.size() > 0, 20.0)
	check(out, "your crew got out to fight (%d)" % game.allies.list.size())
	await wait(5.0)
	await snap("crew_fighting")
	await wait(5.0)
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
			if k == 0:
				await snap("bag_on_back")
			check(game.heist.state == game.heist.STASH, "bag %d: take it to the car (state %d, left %d, duffle d %.1f)" % [k + 1, game.heist.state, game.heist.bags_left, game.heist.duffle.global_position.distance_to(game.foot.global_position) if game.heist.duffle else -1.0])
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
	await snap("heist_complete")
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

## Park out in front of a plot, looking at it.
func _look_at_plot(id: String) -> void:
	var pl: Dictionary = game.property.props[id]["plot"]
	var c: Vector2 = pl["c"]
	var f := Vector2(sin(float(pl["yaw"])), cos(float(pl["yaw"])))
	var at := c + f * (Vector2(pl["hs"]).y + 26.0)
	var y: float = game.island.height_at(at.x, at.y) + 0.8
	game.car.place(Transform3D(Basis(Vector3.UP, atan2(f.x, f.y)), Vector3(at.x, y, at.y)))
	game._snap_cam()

func _builder() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait_until(func(): return int(game.save.data.get("level_seen", 0)) > 0, 5.0)
	var c0 := int(game.save.data["coins"])
	var lv0 := Progress.level(game.save)
	_give_level(8)
	await wait(0.7)
	await snap("level_up")
	check(Progress.level(game.save) == 8 and int(game.save.data.get("level_seen", 0)) == 8, "levelled 1 -> 8")
	var expect := 0
	for l in range(lv0 + 1, 9):
		expect += Progress.cash_for(l)
	check(int(game.save.data["coins"]) - c0 == expect, "level cash paid ($%d)" % expect)
	check(game.Cards.packs(game.save) >= 7, "card packs waiting (%d)" % game.Cards.packs(game.save))
	# build the garage all the way up
	game.save.data["coins"] = 2000000
	_look_at_plot("garage")
	var g: Node = game.property.props["garage"]["node"]
	var tg: Array = game.property.props["garage"]["def"]["targets"]
	var stages := 0
	while int(g.get("built_count")) < tg.size() and stages < 20:
		var need: int = int(tg[int(g.get("built_count"))]) - int(g.get("invested"))
		var took: int = int(g.call("deposit", maxi(need, 1)))
		game.save.data["coins"] = int(game.save.data["coins"]) - took
		stages += 1
		await wait(2.0)
	await snap("garage_built")
	check(game.property.finished("garage"), "garage built (%d stages)" % stages)
	check(game.property.garage_open(), "its bays are up")
	game.save.data["owned"] = ["bug", "roadster", "taxi", "racer"]
	game.open_garage("own")
	await wait(0.5)
	await snap("your_cars")
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
	_look_at_plot("mansion")
	await wait(1.0)
	var m: Node = game.property.props["mansion"]["node"]
	var tm: Array = game.property.props["mansion"]["def"]["targets"]
	stages = 0
	while int(m.get("built_count")) < tm.size() and stages < 20:
		var need2: int = int(tm[int(m.get("built_count"))]) - int(m.get("invested"))
		m.call("deposit", maxi(need2, 1))
		stages += 1
		await wait(2.0)
	await snap("mansion_built")
	check(game.property.finished("mansion"), "mansion built (%d stages)" % stages)
	game.pause()
	await wait(0.6)
	await snap("pause_menu")
	game.resume()
	await wait(0.3)
	game.pause(false)
	game.ui.open_map()
	await wait(1.0)
	await snap("map")
	game.ui._map_close()
	await wait(0.5)
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

# ------------------------------------------------------------------ the ram test (the police car made on top of you)

func _ram() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait(2.0)
	for trial in 5:
		game.car.damage = 0.0
		game.car.engine_dmg = 0.0
		var xf: Transform3D = game.car.global_transform
		var p0: Vector3 = xf.origin
		# a police car right where you are (a patrol car you touched, turning on its lights), coming at you
		# (the last two: its nose wedged under yours, driving in hard)
		var off: Vector3 = [xf.basis.x * 0.6, xf.basis.x * 1.2, Vector3.ZERO, -xf.basis.z * 3.4 - Vector3(0, 0.25, 0), xf.basis.x * 2.6 - Vector3(0, 0.3, 0)][trial]
		var pxf := Transform3D(xf.basis.rotated(Vector3.UP, [0.0, 1.2, 3.0, PI, PI * 0.5][trial]), p0 + off + Vector3(0, 0.3, 0))
		var u: Dictionary = game.police._unit(pxf, -pxf.basis.z * [14.0, 14.0, 14.0, 25.0, 25.0][trial], game.you())
		game.police.units.append(u)
		var top := 0.0
		var far := 0.0
		for k in 20:
			await wait(0.1)
			top = maxf(top, game.car.linear_velocity.length())
			far = maxf(far, game.car.global_position.distance_to(p0))
		check(top < 25.0 and far < 25.0 and game.car.damage < 60.0, "police car made on top of you (%d): top speed %.0f m/s, moved %.0f m, damage %.0f" % [trial, top, far, game.car.damage])
		game.police.clear()
		game.car.place(xf)
		await wait(1.0)

var _bumps: Array = []

func _bump_log(st: float) -> void:
	_bumps.append(st)

## Rammed for real: police cars driving into you head-on, side-on and from behind, and a patrol car you hit.
func _ram2() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait(2.0)
	game.car.bumped.connect(_bump_log)
	var setups := [["head-on", PI, Vector3(0, 0, -14), 28.0], ["T-bone", PI * 0.5, Vector3(9, 0, -9), 28.0], ["rear", 0.0, Vector3(0, 0, 10), 30.0], ["T-bone fast", PI * 0.5, Vector3(9, 0, -12), 40.0]]
	for su in setups:
		game.car.damage = 0.0
		game.car.engine_dmg = 0.0
		_bumps.clear()
		var xf: Transform3D = game.car.global_transform
		var off: Vector3 = xf.basis * (su[2] as Vector3)
		var pb := xf.basis.rotated(Vector3.UP, float(su[1]))
		var pxf := Transform3D(pb, xf.origin + off + Vector3(0, 0.2, 0))
		var tgt: Vector3 = xf.origin
		var dir: Vector3 = (tgt - pxf.origin)
		dir.y = 0
		pxf.basis = Basis(Vector3.UP, atan2(-dir.x, -dir.z))
		var u: Dictionary = game.police._unit(pxf, dir.normalized() * float(su[3]), game.you())
		game.police.units.append(u)
		var p0: Vector3 = xf.origin
		var top := 0.0
		var up := 0.0
		var dmin := 99.0
		for k in 30:
			dmin = minf(dmin, (u["car"] as Node3D).global_position.distance_to(game.car.global_position)) if is_instance_valid(u["car"]) else dmin
			await wait(0.05)
			top = maxf(top, game.car.linear_velocity.length())
			up = maxf(up, game.car.global_position.y - p0.y)
		var mb := 0.0
		for b in _bumps:
			mb = maxf(mb, b)
		check(game.car.damage < 60.0 and up < 6.0, "rammed %s: closest %.1f m, top %.0f m/s, up %.1f m, bump %.0f, damage %.0f" % [su[0], dmin, top, up, mb, game.car.damage])
		game.police.clear()
		game.car.place(xf)
		await wait(1.5)
	# a patrol car in the traffic you drive into
	for k in 2:
		game.car.damage = 0.0
		_bumps.clear()
		var xf: Transform3D = game.car.global_transform
		var c: Dictionary = {}
		for tc in game.traffic.cars:
			if int(tc["mode"]) < game.traffic.KNOCKED:
				c = tc
				break
		if c.is_empty():
			note("no traffic car to use")
			break
		var b: Node3D = c["body"]
		b.global_transform = Transform3D(xf.basis, xf.origin - xf.basis.z * (4.6 - k * 0.6))
		game.police.patrol_hit(c, -xf.basis.z * 18000.0, b.global_position)
		var p0: Vector3 = xf.origin
		var top := 0.0
		var up := 0.0
		for i in 30:
			await wait(0.05)
			top = maxf(top, game.car.linear_velocity.length())
			up = maxf(up, game.car.global_position.y - p0.y)
		var mb := 0.0
		for bb in _bumps:
			mb = maxf(mb, bb)
		check(game.car.damage < 60.0 and up < 6.0, "patrol car hit (%d): top %.0f m/s, up %.1f m, bump %.0f, damage %.0f" % [k, top, up, mb, game.car.damage])
		game.police.clear()
		game.car.place(xf)
		await wait(1.5)

# ------------------------------------------------------------------ the first ride's coach

func _coach_title() -> String:
	var c = game.ui.coach_ui
	return c.title.text if c != null and c.box.visible else ""

func _tutor() -> void:
	await wait(2.0)
	game.start_drive()
	await wait(4.5)
	await snap("tut_car")
	check(game.tutorial.active and game.tutorial.step_id() == "car", "coach on: get in the car (%s)" % _coach_title())
	check(game.route.is_empty(), "no GPS set unless you ask for it")
	check(game.ui.goal_lbl == null or not game.ui.goal_lbl.visible, "no goal line under the coach")
	game.foot.global_position = game.car.global_position + game.car.global_transform.basis.x * 2.2
	await wait(0.5)
	game.toggle_foot()
	await wait(1.6)
	await snap("tut_gas")
	check(game.tutorial.step_id() == "gas", "coach: gas (%s)" % _coach_title())
	game.held["gas"] = true
	await wait_until(func(): return game.tutorial.step_id() == "steer", 10.0)
	await wait(0.8)
	await snap("tut_steer")
	check(game.tutorial.step_id() == "steer", "coach: steer")
	game.held["left"] = true
	await wait_until(func(): return game.tutorial.step_id() == "drift", 10.0)
	game.held["left"] = false
	await wait(0.8)
	await snap("tut_drift")
	check(game.tutorial.step_id() == "drift", "coach: drift")
	game.held["right"] = true
	game.held["hand"] = true
	await wait_until(func(): return game.tutorial.step_id() == "go_race", 28.0)
	game.held["right"] = false
	game.held["hand"] = false
	game.held["gas"] = false
	await wait(1.0)
	# (the drift may have run someone down: the coach says lose the police first; then they're called off)
	if game.police.wanted():
		await wait(1.0)
		await snap("tut_police")
		check(game.ui.coach_ui.title.text.begins_with("Lose the police"), "coach: lose the police first (%s)" % game.ui.coach_ui.title.text)
		game.police.clear()
		await wait(1.0)
	await snap("tut_go_race")
	check(game.tutorial.step_id() == "go_race" and game.route.is_empty(), "coach: off to the first race, nothing routed yet")
	await wait(0.6)
	check(game.ui.coach_ui.dest_btn.visible, "coach: a Set as destination button")
	game.ui.coach_ui.dest_btn.pressed.emit()
	await wait(2.0)
	check(String(game.route.get("name", "")) == "First race", "tapped it: GPS on the first race (%s)" % game.route.get("name", ""))
	await snap("tut_dest")
	# (driving there takes a while: put the car at the beacon)
	var m: Dictionary = game.tutorial._race_marker()
	game.car.place(game.on_ground(Transform3D(Basis(), (m["pos"] as Vector3) + Vector3(0, 0.5, 0))))
	await wait_until(func(): return game.tutorial.step_id() == "start", 6.0)
	await wait(0.8)
	await snap("tut_start")
	check(game.tutorial.step_id() == "start", "coach: tap START (step %s, in %s, wanted %s, dist %.1f, intro %s)" % [game.tutorial.step_id(), game.in_marker.get("kind", "-"), game.police.wanted(), game.car.global_position.distance_to(m["pos"]), not game.intro.is_empty()])
	game.args["raceauto"] = true
	game.start_challenge_now("race", String(game.in_marker["id"]))
	await wait(1.0)
	check(game.tutorial.step_id() == "racing" and not game.ui.coach_ui.box.visible, "coach quiet during the race")
	await wait_until(func(): return game.race != null and game.race.state == 2, 420.0)
	game.args.erase("raceauto")
	await wait_until(func(): return game.race == null, 30.0)
	await wait_until(func(): return game.tutorial.step_id() == "shop", 15.0)
	await wait(1.0)
	await snap("tut_shop")
	check(game.tutorial.step_id() == "shop", "coach: to Lo-Fi Customs (step %s)" % game.tutorial.step_id())
	check(game.story.step >= 2 and game.ui._nq.is_empty() and (game.ui._ncur.is_empty() or String(game.ui._ncur.get("key", "")).begins_with("toast:")), "story moved on quietly, no texts (step %d)" % game.story.step)
	game.police.clear()
	game.open_shop("customs")
	await wait(1.5)
	game.close_garage(game.DRIVE)
	await wait(2.0)
	await snap("tut_phone")
	check(game.tutorial.step_id() == "phone", "coach: your phone (step %s, state %d, shop_in '%s')" % [game.tutorial.step_id(), game.state, game._shop_in])
	game.ui.toggle_phone()
	await wait(1.0)
	game.ui.toggle_phone()
	await wait(1.2)
	await snap("tut_done")
	check(game.tutorial.step_id() == "done", "coach: you're set")
	await wait(5.0)
	check(not game.tutorial.active and bool(game.save.data.get("tut", false)), "tutorial over and saved")
	check(game.ui.goal_lbl != null and game.ui.goal_lbl.visible, "Jay's goal line back (%s)" % game.story.goal())

# ------------------------------------------------------------------ fists

## Someone stood about near the road, made into a real character by you, and you right in front of them.
func _walk_up_to_someone() -> Dictionary:
	var people = game.island.people
	var me: Vector3 = game.foot.global_position
	var best := {}
	var bd := INF
	for pr in people.list:
		if pr["gone"] or pr.get("down", false) or pr["pose"] != "stand" or pr.has("path") or pr.has("ride") or pr.has("fight"):
			continue
		var d := (pr["pos"] as Vector3).distance_to(me)
		if d < bd:
			bd = d
			best = pr
	if best.is_empty():
		return {}
	var p: Vector3 = best["pos"]
	var face := float(best["face"])
	var front := Vector3(-sin(face), 0, -cos(face))
	game.foot.place(p + front * 1.5, atan2(front.x, front.z))
	await wait(1.0)
	return best

func _brawler() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait(1.0)
	game.save.data["guns"] = ["pistol", "rifle"]
	game.gunplay.holstered = false
	game.toggle_foot()
	await wait(1.0)
	check(game.on_foot and game.gunplay.holstered, "out of the car with empty hands")
	var ui = game.ui
	check(ui.ctl["swap"].get_global_rect().position.y < 400.0, "weapon wheel up by the minimap (y %.0f)" % ui.ctl["swap"].get_global_rect().position.y)
	check(ui.ctl["door"].visible, "ENTER showing by the car")
	game.foot.global_position += Vector3(14, 0, 0)
	await wait(1.0)
	check(not ui.ctl["door"].visible, "ENTER gone away from the car")
	check(bool(ui.ctl["fire"].get_meta("fist", false)) and not ui.ctl["reload"].visible, "PUNCH instead of FIRE, no reload")
	# up to someone: they stay put (no jogging off), the greet/taunt prompt comes up
	var pr := await _walk_up_to_someone()
	check(not pr.is_empty(), "found someone")
	if pr.is_empty():
		return
	var p0: Vector3 = pr["pos"]
	await wait(1.5)
	check((pr["pos"] as Vector3).distance_to(p0) < 0.3, "they didn't run off when you walked up")
	check(pr.has("live") and not game.melee.social.is_empty() and ui.social_box.visible, "GREET / TAUNT up by them")
	await snap("social")
	game.melee.greet()
	await wait(1.2)
	await snap("greet")
	check(game.foot.avatar.current() != "", "waved")
	# a punch: they reel; keep going and it's a fight or they run
	pr["grit"] = 1.0          # (this one fights)
	pr["style"] = "scrapper"
	game.held["fire"] = true
	await wait(0.05)
	game.held["fire"] = false
	await wait(0.12)
	await snap("punch_windup")
	await wait(0.2)
	await snap("punch_land")
	await wait(0.4)
	check(float(pr.get("fist_hp", 60.0)) < float(pr.get("fist_max", 60.0)), "the punch landed (hp %.0f of %.0f), not a knock-out" % [float(pr.get("fist_hp", 60.0)), float(pr.get("fist_max", 60.0))])
	check(game.melee.foes.size() == 1 and pr.has("fight"), "they're fighting back")
	var bp: Control = ui.ctl["block"]
	check(bp.visible and bp.modulate.a > 0.9 and bp.scale.x > 0.9 and bp.is_visible_in_tree(), "BLOCK up in the fight (at %s, a %.2f, scale %.2f, in tree %s, parent %s)" % [bp.get_global_rect(), bp.modulate.a, bp.scale.x, bp.is_visible_in_tree(), bp.get_parent().name])
	check(game.foot.avatar.fight, "squared up (guard stance)")
	await snap("fight_stance")
	# they swing: block it
	var f: Dictionary = game.melee.foes[0]
	f["cool"] = 0.0
	var hp0: float = game.gunplay.hp
	var blocked := false
	for k in 60:
		await wait(0.05)
		if not f["atk"].is_empty() and not f["atk"]["landed"]:
			var a: Dictionary = f["atk"]
			var t_hit: float = (float(a["def"]["hit"]) - float(a["def"]["from"])) / float(a["def"]["speed"])
			if t_hit - float(a["t"]) < 0.3:
				game.held["block"] = true
				await wait(0.1)
				game.held["block"] = false
				blocked = true
				break
	await wait(0.6)
	check(blocked and game.gunplay.hp >= hp0 - 0.1, "blocked their punch (hp %.0f -> %.0f)" % [hp0, game.gunplay.hp])
	# they swing again: take it
	f["cool"] = 0.0
	f["stun"] = 0.0
	hp0 = game.gunplay.hp
	await wait(2.2)
	await snap("got_hit")
	check(game.gunplay.hp < hp0, "took a punch when not guarding (hp %.0f -> %.0f)" % [hp0, game.gunplay.hp])
	# held: the guard stays up (no dodge), and it costs stamina; spent, there's no guard
	f["cool"] = 9.0
	var st0: float = float(game.foot.sta["v"])
	game.held["block"] = true
	await wait(1.0)
	check(game.melee.block_t > 0.0 and float(game.foot.sta["v"]) < st0 - 2.0, "holding BLOCK: guard up, stamina going (%.0f -> %.0f)" % [st0, float(game.foot.sta["v"])])
	await snap("guard")
	game.held["block"] = false
	game.foot.sta["v"] = 0.0
	game.foot.sta["spent"] = true
	await wait(0.3)
	game.held["block"] = true
	await wait(0.4)
	check(game.melee.block_t <= 0.0, "spent: no guard")
	game.held["block"] = false
	var hp_s: float = game.gunplay.hp
	await wait(4.0)
	check(not game.foot.sta["spent"], "stood still: breath back (%.0f)" % float(game.foot.sta["v"]))
	f["cool"] = 0.0
	# the combo till they're down
	game.gunplay.hp = game.gunplay.MAX_HP
	var downed := false
	for k in 30:
		if pr.get("down", false):
			downed = true
			break
		game.held["fire"] = true
		await wait(0.05)
		game.held["fire"] = false
		await wait(0.18)
		if k == 6:
			await snap("combo")
	await wait(0.6)
	await snap("knocked_out")
	check(downed or pr.get("down", false), "knocked them out")
	check(game.melee.foes.is_empty(), "the fight's over")
	game.police.clear()
	# a taunt: someone else reacts (fights, runs to call it in, or shrugs)
	await wait(4.0)
	var pr2 := await _walk_up_to_someone()
	if not pr2.is_empty():
		pr2["grit"] = 0.0          # (this one runs)
		pr2["react"] = 0.1
		await wait(0.6)
		note("taunt: social is pr2 %s, fight_t %.1f, social empty %s" % [game.melee.social == pr2, game.melee.fight_t, game.melee.social.is_empty()])
		game.melee.taunt()
		await wait(0.4)
		await snap("taunt")
		await wait(1.0)
		check(pr2.get("fled", false), "taunted: they ran off")
		await wait(5.0)
		check(game.police.wanted() or not game.police.report.is_empty(), "and called the police")
	game.police.clear()
	# a gun only off the wheel
	game.gunplay.select("pistol")
	await wait(0.4)
	check(not game.gunplay.holstered and not ui.ctl["block"].visible and ui.ctl["reload"].visible, "gun out from the wheel: FIRE, reload, no BLOCK")
	game.foot.global_position = game.car.global_position - game.car.global_transform.basis.x * 2.0
	await wait(0.3)
	game.toggle_foot()
	await wait(0.6)
	check(not game.on_foot, "back in the car")
	game.toggle_foot()
	await wait(0.8)
	check(game.gunplay.holstered, "out of the car again: hands empty")

## Frames of a fight in sequence (for checking it flows): a combo, their swing blocked, a dodge, the finisher.
func _brawlseq() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait(1.0)
	game.toggle_foot()
	await wait(1.0)
	var pr := await _walk_up_to_someone()
	if pr.is_empty():
		return
	game.melee._provoke(pr)
	pr["fist_hp"] = 200.0
	await wait(2.5)
	var f: Dictionary = game.melee.foes[0]
	f["cool"] = 99.0
	var n := 0
	# the combo: four presses, a beat apart
	for k in 4:
		game.held["fire"] = true
		await wait(0.04)
		game.held["fire"] = false
		for j in 3:
			await wait(0.1)
			n += 1
			await snap("c%02d" % n)
	await wait(0.6)
	# their swing: blocked
	f["cool"] = 0.0
	f["stun"] = 0.0
	for j in 12:
		await wait(0.08)
		if not f["atk"].is_empty() and not f["atk"]["landed"]:
			var a: Dictionary = f["atk"]
			var t_hit: float = (float(a["def"]["hit"]) - float(a["def"]["from"])) / float(a["def"]["speed"])
			if t_hit - float(a["t"]) < 0.3:
				game.held["block"] = true
		n += 1
		await snap("b%02d" % n)
	game.held["block"] = false
	await wait(0.5)
	# a dodge
	game.held["block"] = true
	for j in 6:
		await wait(0.08)
		n += 1
		await snap("d%02d" % n)
	game.held["block"] = false
	f["cool"] = 99.0
	pr["fist_hp"] = 20.0
	await wait(0.6)
	game.melee.combo = 3
	game.melee.since = 0.0
	game.held["fire"] = true
	await wait(0.04)
	game.held["fire"] = false
	for j in 10:
		await wait(0.1)
		n += 1
		await snap("k%02d" % n)

## Knock-outs as they look: thrown limp (the ragdoll), and dropped where they stood (fall, fit, still).
func _kotest() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait(1.0)
	game.toggle_foot()
	await wait(1.0)
	for mode in ["ragdoll", "drop"]:
		var pr := await _walk_up_to_someone()
		if pr.is_empty():
			return
		await wait(1.5)
		var d: Vector3 = (pr["pos"] as Vector3) - game.foot.global_position
		d.y = 0.0
		d = d.normalized()
		var c := {"kind": "ped", "ref": pr, "av": pr["live"]}
		if mode == "ragdoll":
			game.melee._ko(c, d * 8.5 + Vector3(0, 2.2, 0))
		else:
			game.melee._ko(c, d * 3.0 + Vector3(0, 1.0, 0))
		for k in 4:
			await wait(0.6 if k < 2 else 2.0)
			await snap("%s_%d" % [mode, k])
		game.police.clear()
		await wait(1.0)

func _punch() -> void:
	game.held["fire"] = true
	await wait(0.05)
	game.held["fire"] = false

## Street fights of every sort: they fight back, circle you, take a few to put down (more the better they
## are), get knocked down and up again.
func _street() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait(1.0)
	game.toggle_foot()
	await wait(1.0)
	for style in ["scrapper", "brawler", "boxer"]:
		game.police.clear()
		game.gunplay.hp = game.gunplay.MAX_HP
		var pr := await _walk_up_to_someone()
		if pr.is_empty():
			note("nobody about for the %s" % style)
			continue
		pr["style"] = style
		pr["grit"] = 1.0
		game.melee._provoke(pr)
		var f: Dictionary = game.melee.foes[0]
		check(float(pr["fist_hp"]) == float(game.melee.PROFILES[style]["hp"]), "%s squares up (hp %.0f)" % [style, float(pr["fist_hp"])])
		# they come at you: circling first, then a combo
		var p0: Vector3 = pr["pos"]
		var hp0: float = game.gunplay.hp
		var circled := 0.0
		for k in 50:
			await wait(0.1)
			if f["phase"] == "circle":
				circled += (pr["pos"] as Vector3).distance_to(p0)
			p0 = pr["pos"]
			game.gunplay.hp = maxf(game.gunplay.hp, 30.0)
		check(circled > 0.8, "%s circled you (%.1f m)" % [style, circled])
		check(game.gunplay.hp < hp0 or game.gunplay.hp <= 30.0, "%s fought back: landed punches (hp %.0f -> %.0f)" % [style, hp0, game.gunplay.hp])
		# put them down: count the presses (keep standing up to it)
		var presses := 0
		var downs := 0
		var was_down := false
		var got_up := false
		for k in 120:
			if pr.get("down", false):
				break
			game.gunplay.hp = game.gunplay.MAX_HP
			if float(f.get("down_t", 0.0)) > 0.0:
				if not was_down:
					downs += 1
				was_down = true
				await wait(0.2)
				continue
			if was_down:
				got_up = true
				was_down = false
			# (in reach: walk up to them)
			var to: Vector3 = (pr["pos"] as Vector3) - game.foot.global_position
			to.y = 0.0
			if to.length() > 1.6:
				game.foot.global_position += to.normalized() * (to.length() - 1.2)
			await _punch()
			presses += 1
			await wait(0.22)
		check(pr.get("down", false), "%s knocked out" % style)
		note("%s: %d punches to knock out, knocked down %d times, got up %s; melee %s" % [style, presses, downs, got_up, game.melee.stats])
		for kk in game.melee.stats:
			game.melee.stats[kk] = 0
		check(presses >= {"scrapper": 3, "brawler": 5, "boxer": 7}[style], "%s took a few (%d punches)" % [style, presses])
		if downs > 0:
			check(got_up, "%s got back up after a knock-down" % style)
		await wait(1.5)

## Mo's street fights: the first text, the beacon, a fight won for the purse, one lost (a beating, not
## WASTED), a gun drawn (forfeit), then on to the next.
func _campaign() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait(1.0)
	game.save.data["tut"] = true
	_give_level(10)
	await wait(1.0)
	var got_mo := await wait_until(func(): return bool(game.save.data.get("fights_intro", false)), 8.0)
	check(got_mo, "Mo got in touch at level %d" % game.fights.UNLOCK)
	var all_up := true
	for d in game.fights.FIGHTERS:
		all_up = all_up and game.fights.showing(String(d["id"]))
		note("fight %s at %s (%s)" % [d["id"], game.fights.spots[d["id"]], d["place"]])
	check(all_up, "every fighter's beacon is up (at your own pace)")
	# the beacon: drive into it, the card comes up
	var sp0: Vector3 = game.fights.spots["dre"]
	game.car.place(game.on_ground(Transform3D(Basis(), sp0 + Vector3(0, 0.6, 0))))
	var card := await wait_until(func(): return String(game.in_marker.get("kind", "")) == "fight", 5.0)
	check(card, "the fight's beacon brings up its card")
	var info: Dictionary = game.fights.start_info("dre")
	check(String(info.get("story", "")) != "" and (info.get("chips", []) as Array).size() == 3, "the card: their story and three bets (%s)" % str(info.get("chips", [])))
	await snap("fight_card")
	game.fights.begin("dre")
	await wait(1.0)
	await snap("fight_intro")
	check(game.on_foot and game.fights.active() and game.fights.cur["crowd"].size() >= 4, "out of the car, a crowd round the ring (%d)" % game.fights.cur["crowd"].size())
	await wait(3.2)
	await snap("fight_count")
	await wait(2.6)
	check(game.melee.foes.size() == 1, "FIGHT: Dre's on you")
	await snap("fight_on")
	var c0 := int(game.save.data["coins"])
	var pr: Dictionary = game.fights.cur["pr"]
	for k in 160:
		if pr.get("down", false):
			break
		game.gunplay.hp = game.gunplay.MAX_HP
		var to: Vector3 = (pr["pos"] as Vector3) - game.foot.global_position
		to.y = 0.0
		if to.length() > 1.6:
			game.foot.global_position += to.normalized() * (to.length() - 1.2)
		await _punch()
		await wait(0.22)
	await wait(0.5)
	await snap("fight_won")
	var want := 200 + int(round(200.0 * 1.6)) + 400
	check(game.fights.won("dre") and int(game.save.data["coins"]) - c0 == want, "beat Dre: bet back, the odds and the first-win purse (+$%d, want $%d)" % [int(game.save.data["coins"]) - c0, want])
	await wait(8.0)
	# Big Tuna: stand there and take it
	game.fights.begin("tuna")
	await wait(6.0)
	check(game.melee.foes.size() == 1, "Big Tuna's on you")
	game.gunplay.hp = 20.0
	var lost := await wait_until(func(): return not game.fights.active() or game.fights.cur.get("state", "") == "done", 30.0)
	await wait(0.3)
	await snap("fight_lost")
	check(lost and not game.fights.won("tuna") and not game.gunplay.dying and game.gunplay.hp > 0.0, "lost to Big Tuna: knocked down, not WASTED (hp %.0f)" % game.gunplay.hp)
	await wait(8.0)
	# a gun: the fight's off
	game.fights.begin("tuna")
	await wait(6.0)
	game.gunplay.select("pistol")
	await wait(0.5)
	check(game.fights.cur.get("state", "") == "done" or not game.fights.active(), "a gun out: fight called off")
	check(not game.fights.won("tuna"), "and no purse")

## How hard the street fights are: a decent player (blocks two thirds of what's thrown at them, a fifth of
## those as dodges; punches when they're open, now and then into a guard) against each fighter, bout after
## bout. --sims=n bouts each, --only=id for one fighter.
func _bout(id: String) -> Dictionary:
	var fw: Dictionary = game.save.data.get("fights", {})
	fw.erase(id)
	game.save.data["coins"] = 99999
	if not game.on_foot:
		game.toggle_foot()
		await wait(0.5)
	game.fights.begin(id)
	await wait(5.8)
	var pr: Dictionary = game.fights.cur.get("pr", {})
	if pr.is_empty() or game.melee.foes.is_empty():
		note("no start %s: active %s wanted %s on_foot %s down %.1f cur %s" % [id, game.fights.active(), game.police.wanted(), game.on_foot, game.foot.down_t if game.foot else -1.0, game.fights.cur.get("state", "-")])
		game.police.clear()
		if game.fights.active():
			game.fights._clear()
		await wait(2.0)
		return {"res": "nostart"}
	var f: Dictionary = game.melee.foes[0]
	var reacted := {}
	var t := 0.0
	var res := "timeout"
	var punches := 0
	while t < 120.0:
		await wait(0.05)
		t += 0.05
		if pr.get("down", false):
			res = "win"
			break
		if not game.fights.active() or game.fights.cur.get("state", "") != "fight":
			res = "loss(%s)" % game.fights.cur.get("why", "?")
			break
		var foot = game.foot
		var to: Vector3 = (pr["pos"] as Vector3) - foot.global_position
		to.y = 0.0
		var dist := to.length()
		var a: Dictionary = f["atk"]
		if not a.is_empty() and not a["landed"]:
			var key: int = int(a.get("id", 0))
			var t_hit: float = (float(a["def"]["hit"]) - float(a["def"]["from"])) / float(a["sp"])
			var left: float = t_hit - float(a["t"])
			if not reacted.has(key):
				reacted[key] = randf_range(0.12, 0.5)      # (when this player reacts: sometimes early, sometimes late)
			if left < float(reacted[key]) and left > 0.0 and float(reacted[key]) > 0.0:
				reacted[key] = -1.0
				if randf() < 0.62:
					game.held["block"] = true
					await wait(0.08 if randf() < 0.8 else 0.32)
					game.held["block"] = false
					t += 0.1
				continue
		if dist > 1.6:
			if float(f["down_t"]) <= 0.0:
				foot.global_position += to.normalized() * minf(3.2 * 0.05, dist - 1.3)
			continue
		var open: bool = float(f["stun"]) > 0.0 or (a.is_empty() and float(f["block_t"]) <= 0.0)
		if game.args.get("style", "") == "smart":
			# (a counter-puncher: hits them when they're reeling or thrown off, otherwise waits on their move)
			open = float(f["stun"]) > 0.0 or (a.is_empty() and float(f["block_t"]) <= 0.0 and f["phase"] == "circle" and randf() < 0.12)
		if open or (randf() < 0.15 and game.args.get("style", "") != "smart"):
			await _punch()
			punches += 1
			t += 0.05
	var hp_left: float = game.gunplay.hp if res != "loss" else 0.0
	var ms: Dictionary = game.melee.stats.duplicate()
	for kk in game.melee.stats:
		game.melee.stats[kk] = 0
	var their: float = float(pr.get("fist_hp", 0.0))
	game.held["block"] = false
	if game.fights.active():
		if game.fights.cur.get("state", "") == "fight":
			game.fights._end(false, "", true)
		game.fights._clear()
	await wait(4.0)        # (a moment to get up, if you went down)
	game.gunplay.hp = game.gunplay.MAX_HP
	return {"res": res, "t": t, "hp": hp_left, "their": their, "punches": punches, "ms": "L%d B%d S%d A%d th%d yb%d wh%d" % [int(ms.get("landed", 0)), int(ms.get("blocked", 0)), int(ms.get("slipped", 0)), int(ms.get("armored", 0)), int(ms.get("their_hits", 0)), int(ms.get("you_blocked", 0)), int(ms.get("their_whiffs", 0))]}

func _fightsim() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait(1.0)
	game.save.data["tut"] = true
	game.save.data["fights_intro"] = true
	_give_level(12)
	await wait(1.0)
	var n := int(game.args.get("sims", "2"))
	var only := String(game.args.get("only", ""))
	for d in game.fights.FIGHTERS:
		var id := String(d["id"])
		if only != "" and id != only:
			continue
		var wins := 0
		var rows := []
		for k in n:
			var r: Dictionary = await _bout(id)
			game.police.clear()
			if r["res"] == "win":
				wins += 1
			rows.append("%s %.0fs you%.0f them%.0f p%d %s" % [r["res"], float(r.get("t", 0)), float(r.get("hp", 0)), float(r.get("their", 0)), int(r.get("punches", 0)), r.get("ms", "")])
		print("SIM %s: %d/%d wins | %s" % [id, wins, n, " ; ".join(rows)])

## Pop-ups take turns: a pile of them at once shows one at a time; a tap dismisses the one that's up.
func _up_count() -> int:
	var n := 0
	for c in game.ui.get_children():
		if c is Control and (c as Control).visible and (c.has_meta("out") or c == game.ui._ncur.get("node")):
			n += 1
	for c in game.ui.hud.get_children():
		if c is Control and c.has_meta("out") and not c.has_meta("going"):
			n += 1
	return n

func _notices() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait(2.0)
	var ui = game.ui
	ui.text_msg("Jay", "First text")
	ui.text_msg("Mo", "Second text")
	ui.toast("A toast", "coin")
	ui.level_up(5, 1000, [["car", "Something"]])
	ui.heist_done(5000)
	ui.toast("A toast", "coin")          # (the same again: not twice)
	await wait(0.5)
	check(ui._nq.size() == 4, "five pop-ups at once: one up, four waiting (%d waiting)" % ui._nq.size())
	var most := 0
	for k in 20:
		most = maxi(most, _up_count())
		await wait(0.25)
	check(most <= 1, "never more than one on screen (most %d)" % most)
	# a tap dismisses the one that's up
	var cur: Control = ui._ncur.get("node")
	var before: int = ui._nq.size()
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	cur.gui_input.emit(ev)
	await wait(0.6)
	check(not is_instance_valid(cur) or cur.has_meta("going"), "tapped: it's dismissed")
	check(ui._nq.size() < before, "and the next one comes up (%d -> %d waiting)" % [before, ui._nq.size()])
	await snap("notice")
	var cleared := await wait_until(func(): return ui._nq.is_empty() and ui._ncur.is_empty(), 30.0)
	check(cleared, "all shown in turn and gone")
	# a challenge's card up: they wait
	game.pause()
	ui.text_msg("Jay", "While paused")
	await wait(1.5)
	check(ui._ncur.is_empty() and ui._nq.size() == 1, "paused: the text waits")
	game.resume()
	await wait(1.0)
	check(not ui._ncur.is_empty(), "back in: it comes up")


## Banking: what you earn is cash on you; an ATM banks it; die and it's dropped (one chance to get it back).
func _bank() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait(1.5)
	var b = game.bank
	var s: Dictionary = game.save.data
	note("%d banks, %d ATMs" % [b.banks.size(), b.atms.size()])
	for bk in b.banks:
		note("BANK %s door %s" % [bk["name"], bk["door"]])
	for a in b.atms:
		note("ATM %s at %s" % [a["name"], (a["pos"] as Vector3).snapped(Vector3.ONE)])
	check(b.banks.size() == 3, "three banks")
	check(b.atms.size() >= 10 and b.atms.size() <= 12, "ATMs round town (%d)" % b.atms.size())
	# nobody walks into a wall: a step at the bank's front wall stops short of it
	var door: Vector3 = b.banks[0]["door"]
	var mv: Vector3 = game.island.people.wall_move(door, door + Vector3(0, 0, 5.0))
	check(mv.z < 77.0 and mv.z > door.z - 0.01, "a step into the bank's wall stops at it (z %.2f)" % mv.z)
	var mv2: Vector3 = game.island.people.wall_move(door, door + Vector3(3.0, 0, 3.0))
	check(mv2.x > door.x + 1.0 and mv2.z < 77.0, "and slides along it (%.1f, %.2f)" % [mv2.x, mv2.z])
	var c0: int = b.cash()
	s["coins"] = int(s["coins"]) + 3000
	await wait(0.5)
	check(b.cash() == c0 + 3000, "earned 3000: it's cash on you (%d)" % b.cash())
	s["coins"] = int(s["coins"]) - 500
	await wait(0.5)
	check(b.cash() == c0 + 2500, "spent 500: off the cash first (%d)" % b.cash())
	# walk up to an ATM
	game.toggle_foot()
	await wait(1.0)
	var a0: Dictionary = b.atms[b.atms.size() - 1]
	var fr: Vector3 = a0["front"]
	game.foot.place((a0["pos"] as Vector3) + fr * 1.2 + Vector3(0, 0.3, 0), atan2(-fr.x, -fr.z))
	await wait(1.0)
	check(not b.near.is_empty(), "at the ATM: in range")
	check(game.ui.atm_btn.visible, "the BANK button's up (%s)" % game.ui.atm_btn.get_meta("t", ""))
	await snap("atm")
	b.deposit()
	await wait(0.5)
	check(b.cash() == 0 and b.banked() == int(s["coins"]), "banked it all (bank %d)" % b.banked())
	var bank0: int = b.banked()
	# earn some, then die with it
	s["coins"] = int(s["coins"]) + 2000
	await wait(0.5)
	game.foot.place((a0["pos"] as Vector3) + fr * 8.0 + Vector3(0, 0.3, 0), 0.0)
	await wait(0.5)
	game.wasted()
	await wait(4.0)
	check(not b.drop.is_empty() and int(b.drop["amount"]) == 2000, "died: 2000 dropped (%s)" % str(b.drop.get("amount", 0)))
	check(b.cash() < 200, "nothing much on you now (%d)" % b.cash())
	check(b.banked() < bank0 and b.banked() > 0, "hospital bill from the bank (%d -> %d)" % [bank0, b.banked()])
	check(game.you().global_position.distance_to(b.drop["pos"]) > 20.0, "came round away from it (%.0f m)" % game.you().global_position.distance_to(b.drop["pos"]))
	await snap("drop")
	# get it back
	if not game.on_foot:
		game.toggle_foot()
		await wait(1.0)
	game.foot.place((b.drop["pos"] as Vector3) + Vector3(0, 0.3, 0), 0.0)
	await wait(1.0)
	check(b.drop.is_empty() and b.cash() >= 2000, "picked it back up (cash %d)" % b.cash())
	# die twice: gone
	game.wasted()
	await wait(4.0)
	check(int(b.drop.get("amount", 0)) >= 2000, "dropped again")
	var tot: int = int(s["coins"])
	game.wasted()
	await wait(4.0)
	check(b.drop.is_empty(), "died again before getting it: gone for good")
	check(int(s["coins"]) <= tot, "and not back in the total")
	check(not s.has("drop"), "and off the save")


## The map: every kind on it, a tap on a marker opens its card, Set as destination routes there (nothing before).
func _mapper() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait(2.0)
	game.save.data["fights_intro"] = true
	check(game.route.is_empty() and game.route_pick.is_empty(), "nothing routed on its own")
	game.fuel = 5.0
	await wait(2.0)
	check(game.route.is_empty(), "low on fuel: still no auto-route")
	game.fuel = 80.0
	game.ui.open_map()
	await wait(1.0)
	var mv = game.ui.map_layer
	var kinds := {}
	for p in mv.pts:
		kinds[p["kind"]] = int(kinds.get(p["kind"], 0)) + 1
	note("map kinds %s" % str(kinds))
	for k in ["race", "fight", "heist", "zone", "trial", "bank", "atm", "shop", "home", "gas"]:
		check(kinds.has(k), "on the map: %s" % k)
	check(mv.legend.get_child_count() >= 10, "legend rows (%d)" % mv.legend.get_child_count())
	await snap("map")
	# tap a bank
	var bk: Dictionary = {}
	for p in mv.pts:
		if p["kind"] == "bank":
			bk = p
	mv._select(bk, true)
	await wait(0.5)
	mv.tap_at(mv._scr(bk["pos"]))
	await wait(0.6)
	check(mv.card != null and mv.sel.get("id") == bk["id"], "tapped the bank: its card")
	await snap("map_card")
	var db: Button = mv.card.find_child("Dest", true, false)
	db.pressed.emit()
	await wait(0.4)
	check(String(game.route_pick.get("name", "")) == String(bk["name"]), "Set as destination: routed (%s)" % game.route_pick.get("name", ""))
	# hide ATMs
	var before: int = mv.list.get_child_count()
	mv.off_kinds["atm"] = true
	mv._list_refresh()
	await wait(0.2)
	check(mv.list.get_child_count() <= before, "legend filter: ATMs hidden")
	mv.zoom = 0.1
	mv._place_cam()
	await wait(0.4)
	await snap("map_zoom")
	game.ui._map_close()
	await wait(2.0)
	check(String(game.route.get("name", "")) == String(bk["name"]), "back in: the GPS goes to the bank")
	# the phone's Things to do
	game.ui.toggle_phone()
	await wait(0.6)
	game.ui.phone.todo_btn.pressed.emit()
	await wait(1.2)
	check(game.ui.overlay.visible, "Things to do: open")
	await snap("todo_start")
	for t in ["race", "fight", "heist", "money", "drift", "cars"]:
		var tb: Button = game.ui.overlay.find_child("Tab_" + t, true, false)
		check(tb != null, "tab %s" % t)
		if tb:
			tb.pressed.emit()
			await wait(0.5)
	var owns := false
	for l in game.ui.overlay.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("You own"):
			owns = true
	check(owns, "the Cars & property tab shows (you own x of y)")
	await snap("todo_cars")
	var mt: Button = game.ui.overlay.find_child("Tab_race", true, false)
	mt.pressed.emit()
	await wait(0.5)
	var dbt: Button = game.ui.overlay.find_child("Dest", true, false)
	check(dbt != null, "a race with Set as destination")
	dbt.pressed.emit()
	await wait(1.5)
	check(not game.ui.overlay.visible and game.state == game.DRIVE, "set: back driving")
	check(String(game.route_pick.get("name", "")) != String(bk["name"]), "and the GPS on the race (%s)" % game.route_pick.get("name", ""))
	game.save.data["map_hide"] = {}


## The police: speeding's nothing; a crime nobody from the police saw gets called in (a blinking star), a
## unit comes 15-20 s later and looks round; there: a chase; gone: called off.
func _dispatch() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait(2.0)
	var pol = game.police
	# no patrol cars about to see it (so it's a call, not on the spot)
	for c in game.traffic.cars:
		if String(c["model"]) == "k_car_police":
			c["model"] = "k_car_sedan"
	game.car.linear_velocity = -game.car.global_transform.basis.z * 40.0
	await wait(3.0)
	check(not pol.wanted(), "speeding: nobody cares")
	game.car.linear_velocity = Vector3.ZERO
	await wait(1.0)
	pol.crime(1.0, "Crashed into someone")
	await wait(0.5)
	check(not pol.wanted() and pol.report.get("phase", "") == "call", "a crime unseen: someone's calling it in")
	check(game.ui.wanted_box.visible and pol.hud()["report"] == "call", "the star blinks")
	await snap("calling")
	await wait(14.0)
	check(not pol.wanted() and pol.report.get("phase", "") == "call", "still on the phone at 14 s")
	await wait(7.0)
	check(pol.report.get("phase", "") == "search", "dispatched by 21 s")
	var resp := 0
	for u in pol.units:
		if u.get("respond", false):
			resp += 1
	check(resp >= 1, "a unit on its way (%d)" % resp)
	# stay put: they find you
	var t := 0.0
	while not pol.wanted() and t < 60.0:
		await wait(1.0)
		t += 1.0
	check(pol.wanted(), "stayed at the scene: found, chase on (%.0f s after dispatch)" % t)
	await snap("found")
	pol.clear()
	pol._end(false)
	await wait(2.0)
	pol.calm = 0.0
	# again, and leave
	pol.crime(1.0, "Shots fired")
	await wait(0.5)
	var far: Vector3 = game.car.global_position + Vector3(500, 0, 0)
	game.travel_to(game._road_spot(far, 0.0))
	await wait(1.0)
	note("moved %.0f m from the scene" % game.car.global_position.distance_to(pol.report.get("at", Vector3.ZERO)))
	t = 0.0
	while not pol.report.is_empty() and t < 120.0:
		await wait(1.0)
		t += 1.0
	check(pol.report.is_empty() and not pol.wanted(), "left the area: they looked round and called it off (%.0f s)" % t)


## A look at every ATM where it stands (for the eye: snaps).
func _atms() -> void:
	game.args["drive"] = true
	game.start_drive()
	await wait(1.5)
	game.toggle_foot()
	await wait(1.0)
	var i := 0
	for a in game.bank.atms:
		var fr: Vector3 = a["front"]
		var side := Vector3(fr.z, 0, -fr.x)
		game.foot.place((a["pos"] as Vector3) + fr * 4.5 + side * 2.0 + Vector3(0, 0.3, 0), atan2(-fr.x, -fr.z))
		await wait(1.2)
		i += 1
		await snap("atm_%02d" % i)
