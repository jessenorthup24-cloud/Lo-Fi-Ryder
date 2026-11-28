extends RefCounted
## Everything there is to do and everywhere worth going, in one list: the map's markers and legend and the
## phone's Things to do app both read it. Each point: {kind, id, name, sub (one line), info (a few lines), pos,
## xf (where Go puts you), start (a Callable for a challenge, or not valid)}.

const K := preload("res://scripts/ui/kit.gd")

## The kinds, in the legend's order: colour, the glyph on its pin, the legend's name, the icon.
const CATS := [
	{"id": "story", "name": "Story mission", "col": Color("ffd34d"), "glyph": "!", "icon": "flag"},
	{"id": "drop", "name": "Your dropped cash", "col": Color("3dff7a"), "glyph": "$", "icon": "coin"},
	{"id": "race", "name": "Races", "col": Color("ff5c7a"), "glyph": "R", "icon": "flag"},
	{"id": "fight", "name": "Street fights", "col": Color("ffb020"), "glyph": "F", "icon": "target"},
	{"id": "heist", "name": "Safes (heists)", "col": Color("ff8c42"), "glyph": "H", "icon": "lock"},
	{"id": "zone", "name": "Drift zones", "col": Color("ff8a5c"), "glyph": "D", "icon": "tire"},
	{"id": "trial", "name": "Time trials", "col": Color("5cc8ff"), "glyph": "T", "icon": "gauge"},
	{"id": "bank", "name": "Banks", "col": Color("2fbf5f"), "glyph": "B", "icon": "home"},
	{"id": "atm", "name": "ATMs", "col": Color("7be495"), "glyph": "$", "icon": "coin"},
	{"id": "shop", "name": "Shops", "col": Color("c38bff"), "glyph": "S", "icon": "car"},
	{"id": "home", "name": "Your property", "col": Color("f2d16b"), "glyph": "P", "icon": "home"},
	{"id": "gas", "name": "Gas stations", "col": Color("4fb3a5"), "glyph": "G", "icon": "fuel"},
]

static func cat(id: String) -> Dictionary:
	for c in CATS:
		if c["id"] == id:
			return c
	return CATS[0]

static func points(game: Node) -> Array:
	var out: Array = []
	var s: Dictionary = game.save.data
	var isl = game.island
	# the story: where the next mission is (or the step you're on)
	var sp: Dictionary = game.campaign.map_point() if game.campaign else {}
	if not sp.is_empty():
		out.append(sp)
	# the cash you dropped
	var dr: Dictionary = game.bank.drop
	if not dr.is_empty():
		out.append({"kind": "drop", "id": "drop", "name": "Your dropped cash", "sub": K.money(int(dr["amount"])) + " on the ground",
			"info": "Where you went down. Get back to it and pick it up, then bank it. Die again before you do and it's gone for good.",
			"pos": dr["pos"], "xf": null})
	# races
	for rc in isl.races:
		var dk: String = game.race_key(String(rc["id"]), game.race_diff())
		var rbest: float = float(s["races"].get(dk, 0.0))
		var sub := "%s · %d laps" % ["Circuit race" if rc.get("track", false) else "Street race", int(rc["laps"])]
		if rbest > 0.0:
			sub += " · best %d:%05.2f" % [int(rbest) / 60, fmod(rbest, 60.0)]
		var rid: String = rc["id"]
		out.append({"kind": "race", "id": rid, "name": rc["name"], "sub": sub,
			"info": "Pull up to the beacon and tap START. Beat the field for cash and XP; harder difficulty (in Settings) pays more. Medals for your times.",
			"pos": rc["pos"], "xf": Transform3D(Basis(), (rc["pos"] as Vector3) + Vector3(0, 1.0, 0)),
			"start": func(): game.start_challenge_now("race", rid), "medal": int(s["medals"].get("race_" + dk, 0))})
		var lc: int = game.campaign.lock_ch("race:" + rid)
		if lc > 0:
			out[-1]["sub"] = "Opens in chapter %d of the story" % lc
			out[-1]["dim"] = true
			out[-1].erase("start")
	# street fights (once Mo's told you about them)
	for fd in game.Fights.FIGHTERS:
		var fid: String = fd["id"]
		if not game.fights.showing(fid) or not game.fights.spots.has(fid):
			continue
		var won: bool = game.fights.won(fid)
		var fsub := "%s \"%s\" · level %d · purse %s%s" % [fd["name"], fd["nick"], int(fd["lvl"]), K.money(int(fd["purse"])), " · beaten" if won else ""]
		out.append({"kind": "fight", "id": fid, "name": "Street fight: " + String(fd["nick"]), "sub": fsub,
			"info": String(fd["story"]) + " Bet on yourself: win and you take %.1fx your bet." % float(fd["odds"]),
			"pos": game.fights.spots[fid], "xf": game._road_spot(game.fights.spots[fid], 0.0)})
	# safes
	for sf in game.heist.safes:
		var cracked: bool = game.heist._cracked(sf)
		out.append({"kind": "heist", "id": String(sf["id"]), "name": "Safe", "sub": "Cracked lately: back later" if cracked else "Ready: $7,500 to $12,500 inside",
			"info": "Walk up and tap START HEIST. Find the drill in the ring, bring it back, hold off the police while it drills, then get the cash to your safehouse.",
			"pos": sf["pos"], "xf": game._road_spot(sf["pos"], 0.0), "dim": cracked})
	# drift zones and trials
	for z in isl.zones:
		var best := int(s["zones"].get(z["id"], 0))
		out.append({"kind": "zone", "id": String(z["id"]), "name": z["name"], "sub": "Drift zone" + (" · best %s" % K.fmt(best) if best > 0 else ""),
			"info": "Drift inside the zone to rack up points. Long, clean slides multiply; hit a wall and you lose the combo.",
			"pos": z["start"], "xf": game._road_spot(z["start"], 0.0), "medal": int(s["medals"].get(z["id"], 0))})
	for t in isl.trials:
		var g0: Transform3D = t["gates"][0]
		var tb: float = float(s["trials"].get(t["id"], 0.0))
		var tk: String = String(t["kind"])
		var tsub: String = {"time": "Time trial", "crawl": "Rock crawl (crawlers only)"}.get(tk, "Drift run")
		if tb > 0.0:
			tsub += (" · best %.2f s" % tb) if tk != "drift" else (" · best %s" % K.fmt(int(tb)))
		out.append({"kind": "trial", "id": String(t["id"]), "name": t["name"], "sub": tsub,
			"info": "Through the gates in order, against the clock" + (" (or for drift points)" if t["kind"] != "time" else "") + ". Drive through the first gate to start.",
			"pos": g0.origin, "xf": Transform3D(g0.basis, g0.origin + Vector3(0, 1.0, 0)).translated_local(Vector3(0, 0, 16)),
			"medal": int(s["medals"].get(t["id"], 0))})
	# money
	for b in game.bank.banks:
		out.append({"kind": "bank", "id": String(b["id"]), "name": b["name"], "sub": "Bank your cash",
			"info": "Pull up out front or walk to the doors and tap BANK. Cash you're carrying is lost if you die; banked money is safe.",
			"pos": b["door"], "xf": game._road_spot(b["door"], 0.0)})
	for i in game.bank.atms.size():
		var a: Dictionary = game.bank.atms[i]
		out.append({"kind": "atm", "id": "atm%d" % i, "name": a["name"], "sub": "Walk up and tap BANK",
			"info": "Bank the cash on you. Anything you're carrying when you die is dropped where you fell.",
			"pos": a["pos"], "xf": game._road_spot(a["pos"], 0.0)})
	# shops, property, gas
	for id in game.shops.shops:
		var sh: Dictionary = game.shops.shops[id]
		out.append({"kind": "shop", "id": String(id), "name": sh["def"]["name"], "sub": sh["def"]["tag"],
			"info": {"customs": "Buy new cars, paint them, tune them and upgrade the engine, turbo, tyres and nitrous.",
				"armory": "Buy guns and attachments. Pick one off the weapon wheel by the minimap to draw it.",
				"threads": "New characters and looks for when you're on foot."}.get(String(id), ""),
			"pos": sh["door"], "xf": game._road_spot(sh["door"], 0.0)})
	for id in game.property.props:
		var pr: Dictionary = game.property.props[id]
		var d: Dictionary = pr["def"]
		var built := int(pr["node"].get("built_count"))
		var n := (d["targets"] as Array).size()
		var pl: Dictionary = pr["plot"]
		var c: Vector2 = pl["c"]
		var pp := Vector3(c.x, isl.height_at(c.x, c.y), c.y)
		out.append({"kind": "home", "id": String(id), "name": d["name"], "sub": ("Finished" if built >= n else "Stage %d of %d" % [built, n]),
			"info": ("Stand on the lot and put money in: it goes up stage by stage. " +
				("The finished garage shows off every car you own." if id == "garage" else "The finished mansion is your safehouse for heists.")),
			"pos": pp, "xf": game._road_spot(pp, 0.0)})
	for st in isl.stations:
		out.append({"kind": "gas", "id": String(st["name"]), "name": "%s gas station" % st["name"], "sub": "Fuel and repairs",
			"info": "Pull in to fill up and get the car fixed.", "pos": st["pos"], "xf": game._road_spot(st["pos"], 0.0)})
	return out
