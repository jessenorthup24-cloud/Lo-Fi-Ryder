extends Node
## Story mode: runs the missions in campaign_data.gd one after another. Each one starts one of three ways (it
## follows straight on, the giver rings you, or there's a gold beacon to drive or walk into), plays its scene,
## then puts its objectives on the HUD one at a time, with the GPS pointed at wherever you need to be. Done:
## the pay, the texts, and the next one lines up. The story opens the island as it goes (OPENS: races, shops,
## fights, heists, property); free roam between missions, and the lot's open once it's over.
##
## Save "camp": {m (the mission you're on), st ("wait" for its start, "on" once it's going), s (its step),
## b (counts taken when the step started), legacy (an old save: nothing's locked), ch_seen}.
## Off (on: false) for the test bots and a straight --drive: then the old way (story.gd) runs instead.

const Data := preload("res://scripts/game/campaign_data.gd")
const Districts := preload("res://scripts/game/districts.gd")
const K := preload("res://scripts/ui/kit.gd")

const CALL_WAIT := 9.0          # after a mission, how long before the next giver rings
const BEACON_R := 16.0          # how close starts a beacon's mission

var game: Node
var on := false
var legacy := false
var m := 0                      # the mission (index into Data.MISSIONS)
var st := "wait"
var s := 0                      # its step
var b := {}                     # baselines for the step
var _t := 0.0
var _call_t := 0.0
var _busy := false              # (a scene's playing for us)
var _escaped := false
var _race_res := {}             # the last race you finished: {id, place}
var _gone_t := 0.0              # (busted or wrecked mid-escape: a moment, then they come again)
var beacon: Node3D
var _resumed := false           # (loaded mid-mission: the step's started again, once, without losing its counts)

func setup(g: Node) -> void:
	game = g
	var a: Dictionary = game.args
	on = not game.autopilot and not a.has("drive") and (not a.has("play") or String(a["play"]).begins_with("story"))
	for k in a:
		if String(k).ends_with("test"):
			on = false
	var sv: Dictionary = game.save.data
	if not sv.has("camp"):
		# someone who's played already: the story's there to play, but nothing gets locked away from them
		legacy = int(sv.get("story", 0)) > 0
		# (they still get the opening scene: the coach is skipped, they've done it)
		sv["camp"] = {"m": 0, "st": "wait", "s": 0, "b": {}, "legacy": legacy, "ch_seen": 0}
	var c: Dictionary = sv["camp"]
	m = int(c.get("m", 0))
	st = String(c.get("st", "wait"))
	s = int(c.get("s", 0))
	b = c.get("b", {})
	legacy = bool(c.get("legacy", false))
	_call_t = 4.0
	beacon = _make_beacon()
	add_child(beacon)
	beacon.visible = false

func _save() -> void:
	var c: Dictionary = game.save.data["camp"]
	c["m"] = m
	c["st"] = st
	c["s"] = s
	c["b"] = b
	game.save.save()

# ------------------------------------------------------------------ what's open

func finished() -> bool:
	return m >= Data.MISSIONS.size()

func chapter() -> int:
	return 8 if finished() else int(Data.MISSIONS[m]["ch"])

func mission() -> Dictionary:
	return {} if finished() else Data.MISSIONS[m]

## Is the story locking things away right now?
func gated() -> bool:
	return on and not legacy and not finished()

## The chapter that opens something (0: it's not the story's to open).
static func opens_at(key: String) -> int:
	for ch in Data.OPENS:
		if (Data.OPENS[ch] as Array).has(key):
			return int(ch)
	return 0

## Is it open? `otherwise`: the old rule, for when the story's off.
func allows(key: String, otherwise := true) -> bool:
	if not on:
		return otherwise
	if not gated():
		return true
	return chapter() >= opens_at(key)

## The chapter something's waiting on (0 if it's open).
func lock_ch(key: String) -> int:
	return 0 if allows(key) else opens_at(key)

## A beacon (a race, a zone, a trial): is it up?
func marker_open(kind: String, id: String) -> bool:
	match kind:
		"race":
			return allows("race:" + id)
		"trial":
			return allows("trials")
		"zone":
			return allows("zones")
	return true

func fight_open(id: String) -> bool:
	return allows("fights:%d" % int(Data.FIGHT_TIER.get(id, 1)))

# ------------------------------------------------------------------ where things are

func anchor(key: String) -> Vector3:
	var isl = game.island
	var p := Vector3.ZERO
	var kind := key.get_slice(":", 0)
	var id := key.get_slice(":", 1) if ":" in key else ""
	match kind:
		"you":
			return game.you().global_position
		"place":
			for pl in isl.places:
				if String(pl["name"]) == id:
					p = pl["pos"]
		"race":
			for rc in isl.races:
				if String(rc["id"]) == id:
					p = rc["pos"]
		"zone":
			for z in isl.zones:
				if String(z["id"]) == id:
					p = z["start"]
		"trial":
			for t in isl.trials:
				if String(t["id"]) == id:
					p = (t["gates"][0] as Transform3D).origin
		"fight":
			p = game.fights.spots.get(id, Vector3.ZERO)
		"door":
			p = game.shops.door_of(id)
		"bank":
			for bk in game.bank.banks:
				if String(bk["id"]) == id:
					p = bk["door"]
		"plot":
			if Districts.PLOTS.has(id):
				var c: Vector2 = Districts.PLOTS[id]["c"]
				p = Vector3(c.x, 0, c.y)
		"station":
			for sn in Districts.STATIONS:
				if String(sn["name"]) == id:
					var pd: Vector2 = sn["pad"]
					p = Vector3(pd.x, 0, pd.y)
		"safehouse":
			p = game.heist.safehouse.get("pos", Vector3.ZERO)
		"xyz":
			var q := id.split(",")
			p = Vector3(float(q[0]), float(q[1]), float(q[2]))
	p.y = isl.height_at(p.x, p.z)
	return p

# ------------------------------------------------------------------ the run of it

## The very first time: the island, the ferry, Jay. (Then the first ride's coach.)
func intro() -> void:
	if finished() or m != 0:
		return
	st = "wait"
	_call_t = 0.6               # (tick starts it, a moment after you're stood by the car)
	_save()

func tick(dt: float) -> void:
	if not on or finished() or _busy or game.cutscene.active:
		_beacon_tick(false)
		return
	_t -= dt
	var md := mission()
	if st == "wait":
		var start := String(md["start"])
		if start == "auto":
			if _free():
				_call_t -= dt
				if _call_t <= 0.0:
					_start_mission()
		elif start == "call":
			_beacon_tick(false)
			if _free():
				_call_t -= dt
				if _call_t <= 0.0:
					_ring()
		else:
			_beacon_tick(true)
			var me: Vector3 = game.you().global_position
			if _free(true) and anchor(start).distance_to(me) < BEACON_R:
				_start_mission()
		return
	_beacon_tick(false)
	if not _resumed:
		if not _free():
			return
		_resumed = true
		if _resume_step():
			return
	if _t > 0.0:
		return
	_t = 0.25
	_step_tick()

## Back in a game you'd quit mid-mission: whatever the step had going (the coach, the police after you, a
## scene) going again. True if it's taken over (a scene).
func _resume_step() -> bool:
	var sp := _step()
	if sp.is_empty():
		return false
	match String(sp[0]):
		"tutorial":
			if not bool(game.save.data.get("tut", false)) and not game.tutorial.active:
				game.tutorial.start()
		"wanted", "escape":
			if game.police.heat == 0:
				game.police.start(float(sp[1]), "They're still after you")
		"scene":
			_begin_step()
			return true
	_show_goal()
	return false

## Nothing else going on: not racing, no police, no fight, no heist, no menu.
func _free(foot_ok := true) -> bool:
	if game.state != game.DRIVE or game.challenge_on() or game.police.heat > 0 or game.police.report.size() > 0:
		return false
	if game.fights.active() or game.heist.active() or game.tutorial.active or float(game.ui._cine_t) > 0.0:
		return false
	return foot_ok or not game.on_foot

## The giver rings: the phone buzzes, then the call (a scene, over your shoulder).
func _ring() -> void:
	var md := mission()
	_busy = true
	game.buzz(120, 0.7)
	game.sfx("phone_ring", -4.0)
	game.ui.toast("%s is calling" % String(md["giver"]), "phone", Color("3fd26b"), Color.WHITE, 1.8)
	get_tree().create_timer(1.6, false).timeout.connect(func():
		_busy = false
		if game.state == game.DRIVE:
			_start_mission()
		else:
			_call_t = 3.0)

func _start_mission() -> void:
	if _busy or game.cutscene.active or st != "wait":
		return
	var md := mission()
	beacon.visible = false
	_chapter_card()
	_busy = true
	var go := func():
		_busy = false
		st = "on"
		s = 0
		_resumed = true
		_begin_step()
	var sc: Dictionary = md.get("intro", {})
	if sc.is_empty():
		go.call()
	else:
		game.cutscene.play(sc, go)

## A new chapter: its card (once).
func _chapter_card() -> void:
	var c: Dictionary = game.save.data["camp"]
	var ch := chapter()
	if ch <= int(c.get("ch_seen", 0)) or ch > Data.CHAPTERS.size():
		return
	c["ch_seen"] = ch
	var cd: Array = Data.CHAPTERS[ch - 1]
	if ch > 1:
		game.ui.intro_card("CHAPTER %d · %s" % [ch, String(cd[0]).to_upper()], String(cd[1]))
		var opened: Array = []
		for k in Data.OPENS.get(ch, []):
			opened.append(_open_name(String(k)))
		if not opened.is_empty() and not legacy:
			var txt := "Now open: " + ", ".join(opened)
			get_tree().create_timer(4.2, false).timeout.connect(func(): game.ui.toast(txt, "flag", Color("ffd34d"), K.INK, 3.6))

static func _open_name(k: String) -> String:
	var names := {"race:downtown": "the Downtown Loop", "race:northloop": "the Northern Loop", "race:beachloop": "the Beach Loop",
		"race:raceway": "the Raceway", "race:ringroad": "the Ring Road Classic", "race:cliffside": "Cliffside Circuit",
		"race:eastpoint": "Eastpoint Speedway", "race:southshore": "Southshore Circuit", "shop:customs": "Lo-Fi Customs",
		"shop:threads": "Lo-Fi Threads", "shop:armory": "the Armory", "zones": "drift zones", "trials": "time trials",
		"heists": "heists", "property:garage": "the garage lot", "property:mansion": "the mansion plot", "dez": "Dez's deliveries",
		"fights:1": "Mo's first fights", "fights:2": "more fights", "fights:3": "the heavy hitters", "fights:4": "King Lo"}
	return String(names.get(k, k))

func _step() -> Array:
	var steps: Array = mission()["steps"]
	return steps[s] if s < steps.size() else []

## A step's starting: count where things are, set the HUD, anything it kicks off.
func _begin_step() -> void:
	var steps: Array = mission()["steps"]
	if s >= steps.size():
		_complete()
		return
	var sp := _step()
	var sv = game.save
	var up := 0
	for k in sv.data["up"]:
		up += int(sv.data["up"][k])
	b = {"heists": sv.stat("heists"), "banked": sv.stat("banked"), "up": up, "owned": (sv.data["owned"] as Array).size(),
		"guns": (sv.data.get("guns", ["pistol"]) as Array).size(), "escapes": sv.stat("escapes")}
	_escaped = false
	_race_res = {}
	match String(sp[0]):
		"tutorial":
			if not bool(sv.data.get("tut", false)) and not game.tutorial.active:
				game.tutorial.start()
		"wanted":
			game.police.start(float(sp[1]), "%s put out a call on you" % String(mission()["giver"]))
		"escape":
			if game.police.heat == 0:
				game.police.start(float(sp[1]), "Every unit's after you")
		"scene":
			_busy = true
			game.cutscene.play(Data.SCENES.get(String(sp[1]), {}), func():
				_busy = false
				_next_step())
			return
	_save()
	_show_goal()          # (the goal line under the top bar says it: no toast on top)

## What the HUD's goal line says.
func goal() -> String:
	if not on or finished():
		return ""
	var md := mission()
	if st == "wait":
		var start := String(md["start"])
		if start == "call" or start == "auto":
			return ""
		return "%s: meet %s (gold marker)" % [String(md["title"]), String(md["giver"])]
	var sp := _step()
	if sp.is_empty() or String(sp[0]) == "tutorial" or String(sp[0]) == "scene":
		return ""
	return String(sp[sp.size() - 1])

func _show_goal() -> void:
	if game.tutorial.active:
		return
	game.ui.story_goal(goal())

func _next_step() -> void:
	s += 1
	_begin_step()

func _step_tick() -> void:
	var sp := _step()
	if sp.is_empty():
		_complete()
		return
	if _done(sp):
		game.sfx("checkpoint", -4.0)
		_next_step()

## Has the step been done?
func _done(sp: Array) -> bool:
	var sv = game.save
	var me: Vector3 = game.you().global_position
	match String(sp[0]):
		"tutorial":
			return bool(sv.data.get("tut", false)) and not game.tutorial.active
		"goto":
			return anchor(String(sp[1])).distance_to(me) < float(sp[2])
		"race":
			if _race_res.is_empty():
				return false
			var ok: bool = String(_race_res["id"]) == String(sp[1]) and int(_race_res["place"]) <= int(sp[2])
			if not ok and String(_race_res["id"]) == String(sp[1]):
				b["fails"] = int(b.get("fails", 0)) + 1
				if int(b["fails"]) >= 2:
					game.ui.toast("Struggling? Easy races are kinder (Settings), and the rewind button undoes a mistake", "gear", Color("ffd34d"), K.INK, 4.0)
				else:
					game.ui.toast("Not good enough this time. Line up and run it again", "flag", Color("ff5c7a"), Color.WHITE, 3.0)
			_race_res = {}
			return ok
		"zone":
			return int(sv.data["zones"].get(String(sp[1]), 0)) >= int(sp[2])
		"trial":
			return int(sv.data["medals"].get(String(sp[1]), 0)) >= int(sp[2])
		"fight":
			return game.fights.won(String(sp[1]))
		"heist":
			return sv.stat("heists") - float(b.get("heists", 0)) >= float(sp[1])
		"bank":
			return sv.stat("banked") - float(b.get("banked", 0)) >= float(sp[1])
		"upgrade":
			var up := 0
			for k in sv.data["up"]:
				up += int(sv.data["up"][k])
			return up - int(b.get("up", 0)) >= int(sp[1])
		"buy_car":
			return (sv.data["owned"] as Array).size() > int(b.get("owned", 1))
		"buy_gun":
			return (sv.data.get("guns", ["pistol"]) as Array).size() > int(b.get("guns", 1))
		"property":
			var tg: Array = game.property.props[String(sp[1])]["def"]["targets"] if game.property.props.has(String(sp[1])) else [0]
			var need := int(tg[clampi(int(sp[2]), 0, tg.size() - 1)])
			return int((sv.data.get("property", {}) as Dictionary).get(String(sp[1]), 0)) >= need
		"cash":
			return int(sv.data["coins"]) >= int(sp[1])
		"pay":
			if anchor(String(sp[2])).distance_to(me) > 30.0 or game.state != game.DRIVE:
				return false
			var amt := int(sp[1])
			if int(sv.data["coins"]) < amt:
				if not b.has("told"):
					b["told"] = true
					game.ui.toast("You need %s. Go make some and come back" % K.money(amt), "coin", Color("ff5c7a"), Color.WHITE, 3.0)
				return false
			var from_pocket := mini(amt, game.bank.cash())
			sv.data["coins"] = int(sv.data["coins"]) - amt
			sv.data["cash"] = maxi(int(sv.data.get("cash", 0)) - from_pocket, 0)
			game.sfx("cash", -2.0, 0.8)
			game.ui.toast("Paid %s" % K.money(amt), "coin", K.PAPER, K.INK, 2.0)
			return true
		"wanted":
			if game.police.heat == 0 and game.state == game.DRIVE:
				_gone_t += 0.25
				if _gone_t >= 5.0:
					_gone_t = 0.0
					game.police.start(float(sp[1]), "They're still after you")
			return game.police.heat >= int(sp[1])
		"escape":
			if _escaped:
				return true
			# busted or wrecked before you got away: they come again
			if game.police.heat > 0 or game.state != game.DRIVE:
				_gone_t = 0.0
			else:
				_gone_t += 0.25
				if _gone_t >= 5.0:
					_gone_t = 0.0
					game.police.start(float(sp[1]), "They're still after you")
			return false
	return false

## The mission's done: the pay, the texts, a card, and on to the next.
func _complete() -> void:
	var md := mission()
	var pay := int(md.get("pay", 0))
	game.save.data["coins"] = int(game.save.data["coins"]) + pay
	if game.bank.has_method("_track"):
		game.bank._track()
	game.sfx("mission", 0.0)
	game.buzz(60, 0.8)
	game.ui.intro_card("MISSION COMPLETE", "%s  ·  +%s" % [String(md["title"]).to_upper(), K.money(pay)])
	var d := 4.2
	for l in md.get("outro", []):
		var who := String(l[0])
		var line := String(l[1])
		get_tree().create_timer(d, false).timeout.connect(func():
			if who == "":
				game.ui.toast(line, "flag", Color("ffd34d"), K.INK, 5.0)
			else:
				game.ui.text_msg(who, line))
		d += 3.4
	m += 1
	st = "wait"
	s = 0
	b = {}
	_call_t = CALL_WAIT + d
	_save()
	game.ui.story_goal("")
	if finished():
		game.save.data["camp"]["done"] = true
		game.save.save()
		get_tree().create_timer(d + 1.0, false).timeout.connect(func():
			game.ui.toast("Story complete. The whole island's open", "trophy", Color("ffd34d"), K.INK, 4.0))
	else:
		get_tree().create_timer(d, false).timeout.connect(func(): _show_goal())

# ------------------------------------------------------------------ events from the game

func on_race(id: String, place: int) -> void:
	if on and st == "on" and not _step().is_empty() and String(_step()[0]) == "race":
		_race_res = {"id": id, "place": place}

func on_escape(_heat: int) -> void:
	if on and st == "on":
		_escaped = true

## The first ride's coach is over: the goal line's the story's from now.
func tutorial_over() -> void:
	_show_goal()

# ------------------------------------------------------------------ the GPS and the beacon

## Where the GPS should point for the story (nothing in a race or a challenge).
func route() -> Dictionary:
	if not on or finished() or _busy:
		return {}
	var md := mission()
	if st == "wait":
		var start := String(md["start"])
		if start == "call" or start == "auto":
			return {}
		return {"pos": anchor(start), "name": "%s: %s" % [String(md["giver"]), String(md["title"])], "kind": "story"}
	var sp := _step()
	if sp.is_empty():
		return {}
	var at := ""
	match String(sp[0]):
		"goto":
			at = String(sp[1])
		"race":
			at = "race:" + String(sp[1])
		"zone":
			at = "zone:" + String(sp[1])
		"trial":
			at = "trial:" + String(sp[1])
		"fight":
			at = "fight:" + String(sp[1])
		"pay":
			at = String(sp[2])
		"upgrade", "buy_car":
			at = "door:customs"
		"buy_gun":
			at = "door:armory"
		"property":
			at = "plot:" + String(sp[1])
	if at == "":
		return {}
	var p := anchor(at)
	if p.distance_to(game.you().global_position) < 14.0:
		return {}
	return {"pos": p, "name": String(sp[sp.size() - 1]), "kind": "story"}

## The map's story pin.
func map_point() -> Dictionary:
	var r := route()
	if r.is_empty():
		return {}
	var md := mission()
	var ch := chapter()
	return {"kind": "story", "id": "story", "name": "Story: " + String(md["title"]),
		"sub": "Chapter %d · %s" % [ch, String(Data.CHAPTERS[ch - 1][0])], "info": String(r["name"]),
		"pos": r["pos"], "xf": game._road_spot(r["pos"], 0.0)}

func _make_beacon() -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 2.4
	cy.bottom_radius = 2.4
	cy.height = 60.0
	cy.cap_top = false
	cy.cap_bottom = false
	mi.mesh = cy
	mi.position.y = 30.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.82, 0.25, 0.32)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	var lb := Label3D.new()
	lb.name = "Label"
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.fixed_size = true
	lb.pixel_size = 0.0018
	lb.font_size = 40
	lb.outline_size = 10
	lb.modulate = Color("ffd34d")
	lb.position.y = 4.5
	n.add_child(lb)
	return n

func _beacon_tick(show: bool) -> void:
	if not show or finished():
		beacon.visible = false
		return
	var md := mission()
	var p := anchor(String(md["start"]))
	var d := p.distance_to(game.you().global_position)
	beacon.visible = d < 400.0 and game.state == game.DRIVE
	beacon.global_position = p
	var lb: Label3D = beacon.get_node("Label")
	lb.text = "%s\n%s" % [String(md["giver"]).to_upper(), String(md["title"])]
	lb.visible = d > 10.0
