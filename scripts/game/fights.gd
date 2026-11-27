extends Node
## Street fights for money, at your own pace (like the races and the heists): eight fighters round town,
## gold beacons on the map, each tougher than the last up to King Lo. Walk (or drive) up to one: who they
## are and why they want you, and your bet (a quarter, half, or all of their purse); the odds pay more the
## harder they are, and the first time you beat someone there's their purse on top. START: a ring of people
## round you, their name up in lights, 3-2-1, the camera locked on them. Fists only (a gun out and the
## fight's off, your bet with it); run off and you've walked away. Knocked down: you lost your bet (a beating,
## not WASTED). Save "fights": {id: true} for the ones you've beaten (they're there for a rematch).

const Avatar := preload("res://scripts/game/avatar.gd")
const K := preload("res://scripts/ui/kit.gd")
const Progress := preload("res://scripts/game/progress.gd")
const FIXER := "Mo"
const RING := 15.0            # leave this far from the middle: you've walked away
const UNLOCK := 2             # Mo gets in touch at this level

## What you can bet against someone: a quarter, half, or all of their purse.
static func bets(d: Dictionary) -> Array:
	var p := int(d["purse"])
	return [p / 4, p / 2, p]

## Who you fight. stats: hp, spd (how quick), cool (how long between combos), block, slip, combo (most
## punches at once), dmg, range (where they circle), recover (how fast they shake off a hit), moves (which
## of melee's FOE_ATK they throw: 0 cross, 1 body jab, 2 front kick; repeats weight them).
const FIGHTERS := [
	{"id": "dre", "name": "Dre Collins", "nick": "Paper Hands", "who": "male_hoodie", "place": "Town Square", "lvl": 2, "purse": 400,
		"stats": {"hp": 125.0, "spd": 1.1, "cool": [0.7, 1.25], "block": 0.35, "slip": 0.12, "combo": 2, "dmg": 1.6, "range": 1.8, "recover": 0.6, "armor": 0.35, "counter": 0.45, "moves": [0, 1, 0]},
		"story": "Dre owes Mo money, and Mo's letting him fight it off. He talks big and swings wild, but a man with debts fights like he's got nothing to lose.", "odds": 1.6,
		"line": "\"I need this more than you, man\"", "beaten": "Dre: \"Tell Mo I'll have the rest next week...\"", "won": "Dre: \"Ha! Debt's paid. Kind of\""},
	{"id": "tuna", "name": "Tony Baptiste", "nick": "Big Tuna", "who": "male_constructor", "place": "Old Harbour", "lvl": 3, "purse": 700,
		"stats": {"hp": 200.0, "spd": 0.9, "cool": [0.8, 1.3], "block": 0.2, "slip": 0.0, "combo": 2, "dmg": 1.9, "range": 1.6, "recover": 0.7, "armor": 0.65, "counter": 0.35, "moves": [0, 0, 1]},
		"story": "Thirty years on the docks, then the cranes started driving themselves. Now Big Tuna fights anyone who'll stand still at the Old Harbour. Slow. Hits like a truck.", "odds": 1.8,
		"line": "\"Thirty years on these docks. You're nothing\"", "beaten": "Tuna: \"...Back in the day you'd have been fish food\"", "won": "Tuna: \"Waterfront's still mine\""},
	{"id": "kiko", "name": "Kiko Reyes", "nick": "Viral", "who": "women_fitness", "place": "Skate Park", "lvl": 4, "purse": 1000,
		"stats": {"hp": 160.0, "spd": 1.35, "cool": [0.45, 0.85], "block": 0.15, "slip": 0.5, "combo": 3, "dmg": 1.35, "range": 1.8, "recover": 0.5, "armor": 0.0, "counter": 0.7, "moves": [0, 1, 2]},
		"story": "Kiko films every fight for her channel and needs one big win to go viral. She's picked you. Quick, and she slips everything: don't swing wild.", "odds": 2.0,
		"line": "\"Smile for the camera, this one's going up tonight\"", "beaten": "Kiko: \"...Okay. Deleting that one\"", "won": "Kiko: \"Two million views, easy\""},
	{"id": "deacon", "name": "Elias Grant", "nick": "The Deacon", "who": "businessman_suit", "place": "Old Hill Cemetery", "lvl": 5, "purse": 1400,
		"stats": {"hp": 200.0, "spd": 1.05, "cool": [0.7, 1.2], "block": 0.65, "slip": 0.1, "combo": 2, "dmg": 1.4, "range": 1.6, "recover": 0.5, "armor": 0.35, "counter": 0.85, "moves": [0, 1]},
		"story": "The Deacon runs the soup kitchen up by the cemetery and fights to keep its lights on. He turtles up and waits for you to tire. Hit him when he swings.", "odds": 2.1,
		"line": "\"I'll pray for you after, child\"", "beaten": "Deacon: \"The Lord tests us all. Today He tested me\"", "won": "Deacon: \"Go in peace. And ice that\""},
	{"id": "marco", "name": "Marco Bellini", "nick": "Two Times", "who": "male_jacket", "place": "Palmer Street", "lvl": 6, "purse": 1900,
		"stats": {"hp": 210.0, "spd": 1.2, "cool": [0.35, 0.7], "block": 0.35, "slip": 0.25, "combo": 4, "dmg": 1.45, "range": 1.6, "recover": 0.45, "armor": 0.4, "counter": 0.55, "moves": [0, 1, 1]},
		"story": "Marco says nobody beats him twice, and Dre's his little brother. He throws combos for days: block them, then make him pay.", "odds": 2.3,
		"line": "\"You put my brother on the floor. My turn\"", "beaten": "Marco: \"...Once. That was once\"", "won": "Marco: \"That's for Dre\""},
	{"id": "sasha", "name": "Sasha Volk", "nick": "The Wall", "who": "women_coat", "place": "Sycamore Heights", "lvl": 7, "purse": 2600,
		"stats": {"hp": 225.0, "spd": 1.2, "cool": [0.45, 0.85], "block": 0.4, "slip": 0.3, "combo": 3, "dmg": 1.8, "range": 2.0, "recover": 0.4, "armor": 0.45, "counter": 0.6, "moves": [2, 2, 0]},
		"story": "Sasha guarded rich folk up in Sycamore Heights till a client got robbed on her watch. Says the guy looked like you. She kicks from way out: get inside.", "odds": 2.5,
		"line": "\"I never forget a face. Yours was there that night\"", "beaten": "Sasha: \"...Fine. Wasn't you. Probably\"", "won": "Sasha: \"Case closed\""},
	{"id": "hammer", "name": "Hamid Saleh", "nick": "The Hammer", "who": "man_fitness", "place": "The Courts", "lvl": 8, "purse": 3400,
		"stats": {"hp": 285.0, "spd": 1.1, "cool": [0.5, 1.0], "block": 0.4, "slip": 0.15, "combo": 3, "dmg": 2.4, "range": 1.6, "recover": 0.4, "armor": 0.6, "counter": 0.5, "moves": [0, 1, 2]},
		"story": "The Hammer ran these fights before Mo. Retired, till developers bought his gym out from under him. He's back, and angry. Biggest punch in town. Don't trade with him.", "odds": 2.8,
		"line": "\"Nothing personal. I just need to hit something\"", "beaten": "Hammer: \"Good. The gym's in good hands. Somewhere\"", "won": "Hammer: \"Still got it\""},
	{"id": "king", "name": "Lo Fischer", "nick": "King Lo", "who": "businessman_shirt", "place": "Downtown", "lvl": 10, "purse": 5000,
		"stats": {"hp": 230.0, "spd": 1.35, "cool": [0.4, 0.75], "block": 0.4, "slip": 0.4, "combo": 4, "dmg": 1.5, "range": 1.55, "recover": 0.35, "armor": 0.5, "counter": 0.7, "moves": [0, 1, 2]},
		"story": "King Lo, Mo's partner. Never lost. Owns half of Downtown and the fights with it. Beat him and you're the king of these streets.", "odds": 3.2,
		"line": "\"Mo says you're good. Mo's said that before\"", "beaten": "King Lo: \"...Long live the king, then\"", "won": "King Lo: \"Come back when you're ready. You're not\""},
]

var game: Node
var spots := {}               # id -> Vector3: where each fight is
var cur := {}                 # the fight on: {def, pr, av, crowd, center, state, t}
var _mo_t := 0.0

func setup(g: Node) -> void:
	game = g

func def_of(id: String) -> Dictionary:
	for d in FIGHTERS:
		if d["id"] == id:
			return d
	return {}

func won(id: String) -> bool:
	return bool((game.save.data.get("fights", {}) as Dictionary).get(id, false))

## The one you can fight now: the first you haven't beaten ("" once you've beaten them all).
func next_id() -> String:
	for d in FIGHTERS:
		if not won(String(d["id"])):
			return String(d["id"])
	return ""

func active() -> bool:
	return not cur.is_empty()

## Where the camera locks on: your opponent, from the moment it starts till it's done (INF: no fight).
func focus() -> Vector3:
	if cur.is_empty() or cur["state"] == "done":
		return Vector3.INF
	return (cur["pr"] as Dictionary)["pos"]

## Their beacon's up: they're next, and Mo's told you about them.
func showing(_id: String) -> bool:
	return bool(game.save.data.get("fights_intro", false)) and cur.is_empty()

# ------------------------------------------------------------------ where

## Each fight in the open near its place: off the road on the pavement side, on the level.
func build_spots() -> void:
	for d in FIGHTERS:
		var c := Vector3.ZERO
		for pl in game.island.places:
			if pl["name"] == d["place"]:
				c = pl["pos"]
		spots[d["id"]] = _open_spot(c)

func _open_spot(c: Vector3) -> Vector3:
	var isl = game.island
	var best := Vector3(c.x, isl.height_at(c.x, c.z), c.z)
	var bs := INF
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	for ring in [0.0, 8.0, 16.0, 26.0, 38.0]:
		var n := 1 if ring == 0.0 else 10
		for k in n:
			var a := TAU * k / n
			var p: Vector3 = c + Vector3(cos(a), 0, sin(a)) * ring
			var h: float = isl.height_at(p.x, p.z)
			# clear of buildings (nothing over it) and level all round, a fight's width
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, h + 40.0, p.z), Vector3(p.x, h - 1.0, p.z), 1)
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and (hit["position"] as Vector3).y > h + 0.4:
				continue
			var flat := 0.0
			for o in [Vector3(4, 0, 0), Vector3(-4, 0, 0), Vector3(0, 0, 4), Vector3(0, 0, -4)]:
				flat = maxf(flat, absf(isl.height_at(p.x + o.x, p.z + o.z) - h))
			var walls := 0
			for o in [Vector3(5, 0, 0), Vector3(-5, 0, 0), Vector3(0, 0, 5), Vector3(0, 0, -5)]:
				var q2 := PhysicsRayQueryParameters3D.create(Vector3(p.x, h + 1.0, p.z), Vector3(p.x, h + 1.0, p.z) + o, 1)
				if not space.intersect_ray(q2).is_empty():
					walls += 1
			var road := 0.0
			var loc: Array = game.router.nearest_near(Vector2(p.x, p.z), 6.0)
			if int(loc[0]) >= 0:
				road = 6.0          # (on a road: the traffic'd run through it)
			var sc: float = flat * 20.0 + walls * 3.0 + road + ring * 0.05
			if sc < bs:
				bs = sc
				best = Vector3(p.x, h, p.z)
	return best

# ------------------------------------------------------------------ Mo, and the beacon's card

func tick(dt: float) -> void:
	_mo_t -= dt
	if _mo_t <= 0.0:
		_mo_t = 1.0
		if not bool(game.save.data.get("fights_intro", false)) and Progress.level(game.save) >= UNLOCK \
				and game.state == game.DRIVE and not game.tutorial.active and not game.challenge_on():
			game.save.data["fights_intro"] = true
			game.save.save()
			game.ui.text_msg(FIXER, "Heard you can handle yourself. I run fights for money round town, if you want in")
			game.ui.text_msg(FIXER, "Eight fighters, the gold fists on your map. Walk up, hear them out, put your money down. Beat them all and you're the king")
	if not cur.is_empty():
		_fight_tick(dt)

var bet_k := 1               # which bet you've picked on the card (a quarter, half, all of their purse)

func start_info(id: String) -> Dictionary:
	var d := def_of(id)
	var bs := bets(d)
	var bet: int = bs[clampi(bet_k, 0, bs.size() - 1)]
	var win := int(round(float(bet) * float(d["odds"])))
	var first := not won(id)
	var info := "Bet %s: win %s (%sx)%s · fists only" % [_money(bet), _money(win), str(d["odds"]), ("  +  %s for beating them the first time" % _money(int(d["purse"]))) if first else ""]
	var chips: Array = []
	for b in bs:
		chips.append(_money(int(b)))
	var out := {"kind_label": "STREET FIGHT" + ("" if first else "  ·  REMATCH"), "name": "%s \"%s\"" % [d["name"], d["nick"]], "col": Color("ffb020"), "medal": 3 if not first else 0,
		"story": String(d["story"]), "info": info, "chips": chips, "chip": clampi(bet_k, 0, bs.size() - 1),
		"set_chip": func(k: int):
			bet_k = k
			game.ui.start_card_show(start_info(id), false),
		"start": func(): begin(id)}
	if not first:
		out["medal"] = 3
	if Progress.level(game.save) < int(d["lvl"]):
		out["warn"] = "They won't fight anyone under level %d" % int(d["lvl"])
	elif game.police.wanted():
		out["warn"] = "Not with the police on you"
	elif int(game.save.data["coins"]) < bet:
		out["warn"] = "You need %s for that bet" % _money(bet)
	return out

func _money(n: int) -> String:
	return K.money(n)

# ------------------------------------------------------------------ the fight

func begin(id: String) -> void:
	var d := def_of(id)
	if d.is_empty() or not cur.is_empty():
		return
	if Progress.level(game.save) < int(d["lvl"]):
		game.ui.toast("Level %d for this one" % int(d["lvl"]), "lock", K.PAPER, K.INK, 2.0)
		return
	if game.police.wanted():
		game.ui.toast("Lose the police first", "eye", Color("ff5c7a"), Color.WHITE)
		return
	var bs := bets(d)
	var st: int = bs[clampi(bet_k, 0, bs.size() - 1)]
	if int(game.save.data["coins"]) < st:
		game.ui.toast("You need %s for that bet" % _money(st), "coin", Color("ff5c7a"), Color.WHITE, 2.4)
		return
	# your money's down
	game.save.data["coins"] = int(game.save.data["coins"]) - st
	game.save.save()
	game.sfx("cash", -6.0, 0.8)
	game.ui.start_card_hide()
	game.in_marker = {}
	var c: Vector3 = spots[id]
	if not game.on_foot:
		game.toggle_foot()
	if game.foot == null:
		return
	# (your car parked off to the side, out of the ring)
	var car: Node3D = game.car
	if car and Vector2(car.global_position.x - c.x, car.global_position.z - c.z).length() < RING * 0.7:
		var away: Vector3 = car.global_position - c
		away.y = 0.0
		away = away.normalized() if away.length() > 0.5 else Vector3(1, 0, 0)
		var park: Vector3 = c + away * 10.0
		park.y = game.island.height_at(park.x, park.z) + 0.6
		car.place(game.on_ground(Transform3D(Basis(Vector3.UP, atan2(away.x, away.z)), park)))
	# you, at the edge of the ring; them across it
	game.gunplay.holstered = true
	game.gunplay.equip()
	game.gunplay.hp = game.gunplay.MAX_HP
	var you_at := c + Vector3(0, 0, 2.2)
	you_at.y = game.island.height_at(you_at.x, you_at.z) + 0.05
	game.foot.place(you_at, 0.0)
	var av := Avatar.new()
	game.add_child(av)
	av.setup(String(d["who"]), "", game.toon)
	var them := c - Vector3(0, 0, 2.2)
	them.y = game.island.height_at(them.x, them.z)
	av.global_position = them
	av.rotation.y = PI + PI        # (facing you: +Z)
	av.fight = true
	var pr := {"pos": them, "face": PI, "live": av, "gone": false, "down": false, "pose": "stand", "y": 0.0, "solo": true,
		"grit": 1.0, "style": "custom", "name": String(d["nick"])}
	cur = {"def": d, "pr": pr, "av": av, "center": c, "state": "intro", "t": 0.0, "crowd": _crowd(c), "stake": st}
	game.melee.solos.append(pr)
	game.ui.intro_card(String(d["nick"]).to_upper(), String(d["line"]) + "      ·      %s bet" % _money(st))
	game.sfx("mission", -4.0)
	game.police.calm = maxf(game.police.calm, 9999.0)      # (nobody calls the police on a fight like this)

## People round the ring: shouting, waving it on.
func _crowd(c: Vector3) -> Array:
	const M := preload("res://scripts/core/models.gd")
	var out: Array = []
	var n := 7
	for k in n:
		var a := TAU * (k + 0.5) / n + randf_range(-0.15, 0.15)
		var r := randf_range(5.0, 6.2)
		var p := c + Vector3(cos(a), 0, sin(a)) * r
		p.y = game.island.height_at(p.x, p.z)
		if absf(p.y - c.y) > 0.6:
			continue
		var av := Avatar.new()
		game.add_child(av)
		av.setup(String(M.CHARS[randi() % M.CHARS.size()]), "", game.island.people.mat)
		av.global_position = p
		var to := c - p
		av.rotation.y = atan2(-to.x, -to.z) + PI
		out.append({"av": av, "t": randf_range(0.0, 1.5)})
	return out

func _crowd_tick(dt: float, hot: bool) -> void:
	for cw in cur.get("crowd", []):
		var av: Avatar = cw["av"]
		if not is_instance_valid(av):
			continue
		cw["t"] = float(cw["t"]) - dt
		if float(cw["t"]) <= 0.0:
			cw["t"] = randf_range(1.2, 2.8)
			var acts := ["wave", "fight_taunt", "talk", "idle"] if hot else ["talk", "idle", "wave"]
			var a: String = acts[randi() % acts.size()]
			if a == "fight_taunt":
				av.play_once(a, 0.15, 1.1, 1.2, false, 0.2)
			else:
				av.play(a, randf_range(0.9, 1.15), 0.3)

func _fight_tick(dt: float) -> void:
	cur["t"] = float(cur["t"]) + dt
	var pr: Dictionary = cur["pr"]
	var d: Dictionary = cur["def"]
	_crowd_tick(dt, cur["state"] == "fight")
	match String(cur["state"]):
		"intro":
			# the name up in lights, then 3-2-1
			if float(cur["t"]) > 3.0:
				cur["state"] = "count"
				cur["t"] = 0.0
				game.ui.fight_count()
		"count":
			if float(cur["t"]) > 2.6:
				cur["state"] = "fight"
				cur["t"] = 0.0
				game.melee.add_foe(pr, d["stats"])
				# (straight at you from the bell)
				var f0: Dictionary = game.melee.foes[game.melee.foes.size() - 1]
				f0["phase"] = "press"
				f0["left"] = 2
		"fight":
			if pr.get("down", false):
				_end(true)
				return
			var foot = game.foot
			if not game.on_foot or foot == null:
				_end(false, "You walked away")
				return
			if not game.gunplay.holstered:
				_end(false, "A gun? The fight's off, and so's the purse")
				return
			# (a fight moves about: walking away is running off from them, or right out of the area)
			var from_them := Vector2(foot.global_position.x - pr["pos"].x, foot.global_position.z - pr["pos"].z).length()
			cur["away_t"] = float(cur.get("away_t", 0.0)) + dt if from_them > RING * 0.75 else 0.0
			if float(cur["away_t"]) > 2.0 or Vector2(foot.global_position.x - cur["center"].x, foot.global_position.z - cur["center"].z).length() > RING * 2.0:
				_end(false, "You walked away")
				return
			if game.police.wanted():
				_end(false, "Police! Everybody scatters", true)
				return
		"done":
			if float(cur["t"]) > 6.0:
				_clear()

## You're out on your feet: a beating, not a death.
func lost_by_ko(from: Vector3) -> void:
	if cur.is_empty() or cur["state"] != "fight":
		return
	var foot = game.foot
	var d: Vector3 = foot.global_position - from
	d.y = 0.0
	foot.knock_down(game, d.normalized() * 4.0 + Vector3(0, 1.5, 0), 3.0)
	game.gunplay.hp = 30.0
	_end(false, "")

func _end(win: bool, why := "", no_fault := false) -> void:
	var d: Dictionary = cur["def"]
	var pr: Dictionary = cur["pr"]
	cur["state"] = "done"
	cur["t"] = 0.0
	cur["why"] = "win" if win else (why if why != "" else "knocked out")
	game.melee.drop_solo(pr)
	game.police.calm = 0.0
	var st := int(cur.get("stake", 0))
	if win:
		# your bet back, what it won at their odds, and their purse the first time you beat them
		var first := not won(String(d["id"]))
		var purse := int(round(float(st) * float(d["odds"]))) + (int(d["purse"]) if first else 0)
		game.save.data["coins"] = int(game.save.data["coins"]) + purse + st
		var fw: Dictionary = game.save.data.get("fights", {})
		fw[d["id"]] = true
		game.save.data["fights"] = fw
		game.save.add_stat("fights_won", 1)
		game.save.save()
		game.sfx("mission", 0.0)
		game.sfx("cash", -2.0)
		game.ui.intro_card("YOU WIN", "+" + _money(purse) + "   ·   " + String(d["nick"]) + " is out cold")
		get_tree().create_timer(3.4, false).timeout.connect(func(): game.ui.text_msg(String(d["nick"]), String(d["beaten"]).get_slice(": ", 1)))
		var left := 0
		for fd in FIGHTERS:
			if not won(String(fd["id"])):
				left += 1
		if left == 0 and first:
			get_tree().create_timer(6.0, false).timeout.connect(func():
				game.ui.text_msg(FIXER, "That's all eight. King of the streets. Every fighter in town knows your name now")
				game.ui.text_msg(FIXER, "They'll still take your money for a rematch. Don't fight the cops"))
		game.ach_check()
	else:
		if no_fault:
			game.save.data["coins"] = int(game.save.data["coins"]) + st       # (nobody won: the stake back)
			game.save.save()
		if why != "":
			game.ui.toast(why + ("" if no_fault else "   ·   -%s" % _money(st)), "", Color("ff5c7a"), Color.WHITE, 2.6)
		if not no_fault:
			game.ui.intro_card("YOU LOST", "-%s   ·   " % _money(st) + String(d["won"]).get_slice(": ", 1))
			get_tree().create_timer(4.0, false).timeout.connect(func():
				game.ui.text_msg(FIXER, "Shake it off. %s will be there when you want your money back" % String(d["nick"])))
		# (they walk off: a beaten fighter's gone, a winner stands about a moment)
		var av = cur["av"]
		if is_instance_valid(av) and not pr.get("down", false):
			(av as Avatar).fight = false
			(av as Avatar).play("talk", 1.0, 0.3)

func _clear() -> void:
	for cw in cur.get("crowd", []):
		if is_instance_valid(cw["av"]):
			(cw["av"] as Node).queue_free()
	var av = cur.get("av")
	var pr: Dictionary = cur.get("pr", {})
	if av != null and is_instance_valid(av) and not pr.get("down", false):
		(av as Node).queue_free()
	elif av != null and is_instance_valid(av):
		get_tree().create_timer(25.0, false).timeout.connect(func():
			if is_instance_valid(av):
				(av as Node).queue_free())
	cur = {}
