extends RefCounted
## The phone's Things to do app: everything there is in the game, one tab at a time: how it works, and every
## place it's at (from scripts/game/guide.gd), each with Set as destination. Opens over the game, paused.

const K := preload("res://scripts/ui/kit.gd")
const Guide := preload("res://scripts/game/guide.gd")
const CARS := preload("res://scripts/game/cars.gd")

const TABS := [
	["story", "Story"], ["start", "Start here"], ["race", "Races"], ["fight", "Fights"], ["heist", "Heists"], ["money", "Money"],
	["drift", "Drifting"], ["cars", "Cars & property"],
]

static func open(ui: Node, tab := "") -> void:
	var game: Node = ui.game
	if tab == "":
		tab = "story" if game.campaign.on else "start"
	if game.state == game.DRIVE:
		game.pause(false)
	var vb: VBoxContainer = await ui._sheet("Things to do", "flag", Color("ff8a5c"), 1160.0)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1120, minf(430.0, ui._vs().y - 300.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	ui._drag_scroll(sc)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	sc.add_child(body)
	var show := [Callable()]          # (in an array: a lambda captures locals by value, so it can't call itself)
	show[0] = func(id: String):
		for c in tabs.get_children():
			tabs.remove_child(c)          # (now, so the new ones can take their names)
			c.queue_free()
		for t in TABS:
			if t[0] == "story" and not game.campaign.on:
				continue
			var on: bool = t[0] == id
			var b := K.button(String(t[1]), K.CORAL if on else K.PAPER, K.CORAL_DK if on else K.LINE, 18, 0, 50)
			b.name = "Tab_" + String(t[0])
			var tid: String = t[0]
			ui._tap(b, func(): (show[0] as Callable).call(tid))
			tabs.add_child(b)
		for c in body.get_children():
			body.remove_child(c)
			c.queue_free()
		sc.scroll_vertical = 0
		_fill(ui, body, id)
	(show[0] as Callable).call(tab)
	var ok := K.button("Done", K.PAPER, K.LINE, 26, 0, 64)
	ui._tap(ok, func():
		ui.close_sheet()
		if game.state == game.PAUSED:
			game.resume())
	vb.add_child(ok)

static func _para(body: VBoxContainer, t: String, big := false) -> void:
	var l := K.label(t, 22 if big else 18, K.INK if big else K.INK_SOFT, 750 if big else 600, HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1080, 0)
	body.add_child(l)

static func _fill(ui: Node, body: VBoxContainer, id: String) -> void:
	var game: Node = ui.game
	var s: Dictionary = game.save.data
	var pts: Array = Guide.points(game)
	var lvl: int = game.Progress.level(game.save)
	match id:
		"story":
			_story(ui, body, pts)
		"start":
			_para(body, "You're level %d with %s on you and %s in the bank." % [lvl, K.money(game.bank.cash()), K.money(game.bank.banked())], true)
			_para(body, "Nothing's routed for you: pick anything here or on the map and tap Set as destination, and the GPS takes you there.")
			var sug := _suggest(game, pts)
			if not sug.is_empty():
				_para(body, "Suggested next", true)
				for p in sug:
					body.add_child(_row(ui, p))
			_para(body, "The map (pause, then Map) shows everything at once, with a legend you can filter.")
		"race":
			_para(body, "Street races and circuit races. Drive up to a pink beacon and tap START. Win for cash and XP; set the difficulty in Settings (harder pays more). Bronze, silver and gold for your best times.")
			_rows(ui, body, pts, ["race"])
		"fight":
			_para(body, "Mo runs street fights from level 2: eight fighters, each tougher than the last. Walk up to one, hear their story, and bet a quarter, half or all of their purse. Win: your bet back times their odds, plus the purse the first time you beat them. Lose and the bet's gone.")
			_para(body, "FIRE throws punches (time the next press as one lands for a combo). Hold BLOCK to keep your guard up. Everything costs stamina: running, swinging, and most of all taking hits on your guard. Run out and you're slow and weak, and a blow breaks your guard, till you back off and get your breath back. Walk away, pull a gun or bring the police and you forfeit.")
			if not bool(s.get("fights_intro", false)):
				_para(body, "Mo hasn't been in touch yet: reach level 2.", true)
			_rows(ui, body, pts, ["fight"])
		"heist":
			_para(body, "Safes are hidden all over the island (the phone's Safe radar points at the nearest). Walk up and tap START HEIST: find the drill somewhere in the ring, bring it back, hold off the police while it drills, then get the cash to your safehouse (your mansion, once it's built). Call friends from your phone first: they help, and take a cut.")
			_rows(ui, body, pts, ["heist"])
		"money":
			_para(body, "Everything you earn is cash on you: the big number at the top of the screen. Bank it at an ATM or one of the three banks (tap BANK when you're at one). Shops take your cash first, then the bank.", true)
			_para(body, "Die with cash on you and you drop all of it where you fell: it's on the map. You get one chance to go back for it. Die again before you've picked it up and it's gone for good.")
			_rows(ui, body, pts, ["drop", "bank", "atm"])
		"drift":
			_para(body, "Drift zones score your slides inside the zone; time trials and drift runs take you through gates against the clock. Medals for each.")
			_rows(ui, body, pts, ["zone", "trial"])
		"cars":
			var owned: int = (s["owned"] as Array).size()
			_para(body, "You own %d of %d cars." % [owned, CARS.LIST.size()], true)
			var next := {}
			for c in CARS.LIST:
				if not (s["owned"] as Array).has(c["id"]) and (next.is_empty() or int(c["price"]) < int(next["price"])):
					next = c
			if not next.is_empty():
				_para(body, "Next up: the %s for %s. Lo-Fi Customs sells cars, paint, tuning and upgrades (engine, turbo, tyres, nitrous)." % [next["name"], K.money(int(next["price"]))])
			_para(body, "Build your own place: stand on the lot and put money in, stage by stage. The Nightline Garage shows off every car you own; the Nightline Mansion is your safehouse for heists. From level 3, Dez brings any car you own to you (phone).")
			_rows(ui, body, pts, ["shop", "home", "gas"])

## What to do next, by where you're at: a couple of things to aim for.
static func _suggest(game: Node, pts: Array) -> Array:
	var out: Array = []
	var me: Vector3 = game.you().global_position
	var nearest := func(kind: String, ok: Callable = Callable()) -> Dictionary:
		var best := {}
		var bd := INF
		for p in pts:
			if p["kind"] == kind and (not ok.is_valid() or ok.call(p)):
				var d := (p["pos"] as Vector3).distance_to(me)
				if d < bd:
					bd = d
					best = p
		return best
	if not game.bank.drop.is_empty():
		out.append(nearest.call("drop"))
	if game.bank.cash() >= 1500:
		out.append(nearest.call("atm"))
	# the next fight in Mo's line-up (in order: the first you've not beaten)
	for fd in game.Fights.FIGHTERS:
		if not game.fights.won(String(fd["id"])):
			for p in pts:
				if p["kind"] == "fight" and p["id"] == fd["id"]:
					out.append(p)
			break
	var r: Dictionary = nearest.call("race", func(p): return int(p.get("medal", 0)) < 3)
	if not r.is_empty():
		out.append(r)
	if out.size() < 3:
		var h: Dictionary = nearest.call("heist", func(p): return not p.get("dim", false))
		if not h.is_empty():
			out.append(h)
	var clean: Array = []
	for p in out:
		if not p.is_empty():
			clean.append(p)
	return clean.slice(0, 4)

static func _rows(ui: Node, body: VBoxContainer, pts: Array, kinds: Array) -> void:
	var me: Vector3 = ui.game.you().global_position
	var sel: Array = []
	for p in pts:
		if p["kind"] in kinds:
			sel.append(p)
	sel.sort_custom(func(a, b): return (a["pos"] as Vector3).distance_to(me) < (b["pos"] as Vector3).distance_to(me))
	for p in sel:
		body.add_child(_row(ui, p))

static func _row(ui: Node, p: Dictionary) -> Control:
	var game: Node = ui.game
	var ct := Guide.cat(p["kind"])
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", K.box(K.CREAM, 20, 0, Color.TRANSPARENT, 10))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	pc.add_child(hb)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(22, 22)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", K.box(ct["col"], 11, 0, Color.TRANSPARENT, 0))
	hb.add_child(dot)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", -2)
	hb.add_child(vb)
	var me: Vector3 = game.you().global_position
	var d: float = (p["pos"] as Vector3).distance_to(me)
	vb.add_child(K.label(String(p["name"]), 22, K.INK, 750, HORIZONTAL_ALIGNMENT_LEFT))
	vb.add_child(K.label("%s · %s · %s" % [p["sub"], _near(game, p["pos"]), ("%.1f km" % (d / 1000.0)) if d >= 1000.0 else ("%d m" % int(round(d / 10.0) * 10.0))], 16, K.INK_SOFT, 600, HORIZONTAL_ALIGNMENT_LEFT))
	for l in vb.get_children():
		(l as Label).clip_text = true
		(l as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		(l as Label).custom_minimum_size.x = 60
	var is_dest: bool = not game.route_pick.is_empty() and (game.route_pick["pos"] as Vector3).distance_to(p["pos"]) < 2.0
	var b := K.button("✓  On your GPS" if is_dest else "Set as destination", K.PAPER if is_dest else K.SKY, K.LINE if is_dest else K.SKY_DK, 18, 230, 52, "flag")
	b.name = "Dest"
	ui._tap(b, func():
		game.set_route_pick(p["pos"], String(p["name"]))
		ui.close_sheet()
		if game.state == game.PAUSED:
			game.resume()
		ui.toast("Destination set: %s" % p["name"], "flag", Color("4aa8ff"), Color.WHITE, 2.0))
	hb.add_child(b)
	return pc

static func _near(game: Node, wp: Vector3) -> String:
	var best := "out of town"
	var bd := INF
	for pl in game.island.places:
		var d := Vector2(wp.x - pl["pos"].x, wp.z - pl["pos"].z).length()
		if d < bd:
			bd = d
			best = String(pl["name"])
	return ("near " + best) if bd < 260.0 else "out of town"

## The story: the chapter, the mission and what to do now, and how far through you are.
static func _story(ui: Node, body: VBoxContainer, pts: Array) -> void:
	var c = ui.game.campaign
	var D = c.Data
	if c.finished():
		_para(body, "The story's done. The island's yours, and everything's open.", true)
		return
	var md: Dictionary = c.mission()
	var ch: int = c.chapter()
	_para(body, "Chapter %d: %s" % [ch, D.CHAPTERS[ch - 1][0]], true)
	_para(body, String(D.CHAPTERS[ch - 1][1]))
	_para(body, "%s  (from %s)" % [md["title"], md["giver"]], true)
	var g: String = c.goal()
	if g == "":
		g = "%s will be in touch." % md["giver"] if String(md["start"]) == "call" else "It's starting."
	_para(body, g)
	for p in pts:
		if p["kind"] == "story":
			body.add_child(_row(ui, p))
	# how far through: a line per chapter
	var done_in := {}
	var all_in := {}
	for i in D.MISSIONS.size():
		var k := int(D.MISSIONS[i]["ch"])
		all_in[k] = int(all_in.get(k, 0)) + 1
		if i < c.m:
			done_in[k] = int(done_in.get(k, 0)) + 1
	_para(body, "Progress", true)
	for k in range(1, D.CHAPTERS.size() + 1):
		var mark := "✓" if int(done_in.get(k, 0)) >= int(all_in.get(k, 0)) else ("▸" if k == ch else "·")
		_para(body, "%s  %d. %s   %d/%d" % [mark, k, D.CHAPTERS[k - 1][0] if k <= ch else "???", int(done_in.get(k, 0)), int(all_in.get(k, 0))])
	_para(body, "Between missions the island's yours: races, drifting, fights and the rest all pay. The story opens more of it as you go.")
