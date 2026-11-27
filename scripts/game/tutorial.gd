extends Node
## The first ride: a coach that walks you through it, one thing at a time, pointing at the button to press
## and with the GPS arrow showing where to go. Into Jay's car, gas, steer, brake, out to your first race,
## START, then Lo-Fi Customs on Main Street, then your phone. Each step's done when you've done it (or
## already had); skip any time. Jay's texts wait till it's over. Save "tut": true once done.

const STEPS := [
	# [id, title, how, the control it points at ("" for none)]
	["car", "Get in Jay's car", "Walk over with the stick, then tap ENTER", "door"],
	["gas", "Hold GAS to drive", "Keep it held to pick up speed", "gas"],
	["steer", "Steer", "Hold left or right to turn", "steer"],
	["brake", "Brake for corners", "Cars have real weight: slow down with BRAKE before you turn in", "brake"],
	["go_race", "Your first race", "Tap Set as destination, then follow the arrow to the pink beacon", "dest"],
	["start", "Tap START", "Easy races pay cash and XP every time you win", "start"],
	["racing", "", "", ""],
	["shop", "Lo-Fi Customs", "Upgrades and new cars, on Main Street: set it as your destination", "dest"],
	["phone", "Your phone", "Tap it: your crew, Dez's deliveries and the safe radar", "phone"],
	["done", "You're set", "Jay will text you what's next. This town's yours", ""],
]

var game: Node
var active := false
var i := 0
var _t := 0.0           # time on this step
var _acc := 0.0         # whatever this step adds up (turning, sliding)
var _shown := -1
var _shown_v := ""
var _wait := 0.0        # a moment before the first card (the title card's up)      # which version of the card's up (the police on you changes what it says)

func setup(g: Node) -> void:
	game = g

func start() -> void:
	if bool(game.save.data.get("tut", false)):
		return
	active = true
	i = 0
	_shown = -1
	_t = 0.0
	_wait = 3.2

func skip() -> void:
	_finish()

func step_id() -> String:
	return String(STEPS[i][0]) if active else ""

## Where the GPS should take you for this step ({} for nowhere).
func route() -> Dictionary:
	if not active:
		return {}
	match step_id():
		"car":
			if game.on_foot and game.car:
				return {"pos": game.car.global_position, "name": "Jay's car", "kind": "tut"}
		"go_race":
			var m := _race_marker()
			if not m.is_empty():
				return {"pos": m["pos"], "name": "First race", "kind": "tut"}
		"shop":
			return {"pos": game.shops.door_of("customs"), "name": "Lo-Fi Customs", "kind": "tut"}
	return {}

func _race_marker() -> Dictionary:
	var best := {}
	var bd := INF
	var p: Vector3 = game.you().global_position
	for m in game.markers:
		if m["kind"] == "race":
			var d := (m["pos"] as Vector3).distance_to(p)
			if d < bd:
				bd = d
				best = m
	return best

func tick(dt: float) -> void:
	if not active:
		return
	var busy: bool = game.state != game.DRIVE
	if busy:
		if _shown >= 0 and step_id() != "racing":
			game.ui.coach_hide()
			_shown = -1
		# (a shop's counters open: that's this step done, whatever comes next)
		if step_id() == "shop" and (game._shop_in != "" or game.story._flag_shop):
			_next()
		elif step_id() == "phone" and game.ui.phone_layer != null and game.ui.phone_layer.visible:
			_next()
		return
	if _wait > 0.0:
		_wait -= dt
		return
	_t += dt
	if _done(dt):
		_next()
		return
	var st: Array = STEPS[i]
	var v := ""
	if game.police.wanted() and step_id() in ["go_race", "start", "shop"]:
		v = "police"
		st = [st[0], "Lose the police first", "Races and shops wait till the stars are gone: get out of sight", ""]
	if _shown != i or _shown_v != v:
		_shown = i
		_shown_v = v
		if String(st[1]) == "":
			game.ui.coach_hide()
		else:
			var n := STEPS.size() - 2         # (the race itself and the last card aren't counted)
			var shown_i := i + 1 - (1 if i > 6 else 0)
			game.ui.coach(String(st[1]), String(st[2]), _target(String(st[3])), mini(shown_i, n), n, step_id() == "done")

## The thing on screen to point at.
func _target(k: String) -> Variant:
	var ui = game.ui
	match k:
		"":
			return null
		"steer":
			return ui.wheel if ui.wheel_mode() else [ui.ctl["left"], ui.ctl["right"]]
		"route":
			return ui.route_box
		"dest":
			# (the button till you've tapped it, then the arrow it gave you)
			return func(): return ui.route_box if ui.route_box.visible else ui.coach_ui.dest_btn
		"start":
			return func(): return ui.start_card
		"phone":
			return ui.phone_btn
	return ui.ctl.get(k)

func _done(dt: float) -> bool:
	var car = game.car
	var spd: float = car.linear_velocity.length() if car else 0.0
	match step_id():
		"car":
			return not game.on_foot
		"gas":
			return not game.on_foot and spd > 9.0
		"steer":
			if not game.on_foot and spd > 4.0:
				_acc += absf(car.angular_velocity.y) * dt
			return _acc > 1.4
		"brake":
			if not game.on_foot and spd > 6.0 and car.brake > 0.5:
				_acc += dt
			return _acc > 0.4 or _t > 25.0        # (not got it yet? it comes: on to the race)
		"go_race":
			return game.in_marker.get("kind", "") == "race" or game.race != null or _raced()
		"start":
			if game.race != null:
				return true
			if game.in_marker.get("kind", "") != "race" and not _raced():
				i -= 1           # (drove back out of the beacon: back to finding it)
				_shown = -1
				return false
			return _raced()
		"racing":
			return game.race == null
		"shop":
			return game.story._flag_shop      # (been in one: see open_shop)
		"phone":
			return game.ui.phone_layer != null and game.ui.phone_layer.visible
		"done":
			return _t > 4.0
	return true

func _raced() -> bool:
	return game.save.stat("races") > 0

func _next() -> void:
	_acc = 0.0
	_t = 0.0
	if step_id() != "racing" and step_id() != "done" and _shown == i:
		game.ui.coach_done()
		game.buzz(30, 0.4)
	i += 1
	# (skip on past what you've already done: a race run before, say)
	while i < STEPS.size() - 1 and _already(step_id()):
		i += 1
	if i >= STEPS.size():
		_finish()

func _already(id: String) -> bool:
	match id:
		"go_race", "start", "racing":
			return _raced() and game.race == null
	return false

func _finish() -> void:
	if not active:
		return
	active = false
	game.ui.coach_hide()
	game.save.data["tut"] = true
	game.save.save()
	game.story.tutorial_over()
