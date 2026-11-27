extends Node3D
## Your money: cash on you, and what's in the bank. Everything you earn comes to you as cash; bank it at an
## ATM (all over town) or one of the three banks, or risk it. Die with cash on you and it's dropped where you
## fell (a bag of it, lit up on the map): one chance to get back to it. Die again before you've picked it up
## and it's gone for good. Spending takes your cash first, then the bank.
## Save: "coins" is everything you have (all the shops and prices work off it, as before); "cash" is how much
## of it is on you, unbanked; "drop" is the bag you dropped ({pos: [x, y, z], amount}).

const K := preload("res://scripts/ui/kit.gd")
const Districts := preload("res://scripts/game/districts.gd")

## The banks: each on a city block off Main Street (paved by districts.gd, from SHOP_PLOTS).
const BANKS := [
	{"id": "bank_main", "name": "Lo-Fi Bank: Main Street"},
	{"id": "bank_west", "name": "Lo-Fi Bank: Harbor Avenue"},
	{"id": "bank_east", "name": "Lo-Fi Bank: Bay Avenue"},
]
## Where the ATMs go: by these places, the shops, the gas stations and the banks' doors.
const ATM_PLACES := ["Downtown", "Skate Park", "Old Harbour", "Sunny Bay", "Maple Hills", "Sycamore Heights"]
const ATM_STATIONS := ["Coast Road", "Main Street East"]

var game: Node
var banks: Array = []          # {id, name, door, node}
var atms: Array = []           # {pos, name, node}
var drop := {}                 # the bag you dropped: {pos, amount, node}
var near := {}                 # the ATM or bank you're at
var _last := -1
var _pulse := 0.0
var _atm_scene: PackedScene

func build(g: Node) -> void:
	game = g
	var s: Dictionary = game.save.data
	if not s.has("cash"):
		s["cash"] = 0          # (an old save: what you had is all in the bank)
	_last = int(s["coins"])
	_atm_scene = load("res://assets/bank/atm.glb")
	var bank_scene: PackedScene = load("res://assets/bank/bank.glb")
	for b in BANKS:
		var pl: Dictionary = Districts.SHOP_PLOTS[b["id"]]
		var c: Vector2 = pl["c"]
		var yaw: float = pl["yaw"]
		var model: Node3D = bank_scene.instantiate()
		model.name = "Bank_" + String(b["id"])
		add_child(model)
		model.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, game.island.height_at(c.x, c.y) + 0.02, c.y))
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visibility_range_end = 380.0
		# solid: the building's box (its front steps left open)
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(18.4, 5.0, 13.6)
		cs.shape = bx
		cs.position = Vector3(0, 2.5, -0.1)
		sb.add_child(cs)
		model.add_child(sb)
		var door: Vector3 = model.global_transform * Vector3(0, 0, 9.0)
		door.y = game.island.height_at(door.x, door.z)
		banks.append({"id": b["id"], "name": b["name"], "door": door, "node": model})
		game.island.map_marker(door, Color("2fbf5f"), 10.0)
	# ATMs by the shops' doors and the gas stations' shops
	for id in game.shops.shops:
		var sh: Dictionary = game.shops.shops[id]
		var fr: Vector3 = sh["front"]
		var side := Vector3(fr.z, 0, -fr.x)
		_atm((sh["door"] as Vector3) + side * 5.5 - fr * 0.6, atan2(fr.x, fr.z), String(sh["def"]["name"]))
	for st in game.island.stations:
		if not String(st["name"]) in ATM_STATIONS:
			continue
		var sp: Vector3 = st["pos"]
		var spot: Vector3 = game.fights._open_spot(sp + Vector3(6, 0, 6))
		_atm(spot, 0.0, "%s gas station" % st["name"])
	for nm in ATM_PLACES:
		for pl2 in game.island.places:
			if pl2["name"] == nm:
				var spot2: Vector3 = game.fights._open_spot((pl2["pos"] as Vector3) + Vector3(5, 0, -5))
				_atm(spot2, randf() * TAU, String(nm))
	# a bag you'd dropped, still out there
	var dd: Dictionary = s.get("drop", {})
	if not dd.is_empty():
		var ap: Array = dd["pos"]
		_make_drop(Vector3(float(ap[0]), float(ap[1]), float(ap[2])), int(dd["amount"]))

func _atm(p: Vector3, yaw: float, by: String) -> void:
	var n: Node3D = _atm_scene.instantiate()
	add_child(n)
	p.y = game.island.height_at(p.x, p.z)
	n.global_transform = Transform3D(Basis(Vector3.UP, yaw), p)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 160.0
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.95, 1.9, 0.8)
	cs.shape = bx
	cs.position = Vector3(0, 0.95, 0)
	sb.add_child(cs)
	n.add_child(sb)
	game.island.map_marker(p, Color("7be495"), 5.0)
	atms.append({"pos": p, "name": "ATM · " + by, "node": n, "front": Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)})

# ------------------------------------------------------------------ the money

func cash() -> int:
	return int(game.save.data.get("cash", 0))

func banked() -> int:
	return maxi(0, int(game.save.data["coins"]) - cash())

## What you earn is cash; what you spend comes off your cash first (the coins total tells us which).
func _track() -> void:
	var s: Dictionary = game.save.data
	var c := int(s["coins"])
	if _last < 0:
		_last = c
	var d := c - _last
	if d > 0:
		s["cash"] = int(s["cash"]) + d
	elif d < 0:
		s["cash"] = maxi(0, int(s["cash"]) + d)
	s["cash"] = mini(int(s["cash"]), c)
	_last = c

func deposit() -> void:
	var amt := cash()
	if amt <= 0:
		return
	game.save.data["cash"] = 0
	game.save.add_stat("banked", amt)
	game.save.save()
	game.sfx("cash", -2.0, 1.1)
	game.buzz(40, 0.6)
	game.ui.toast("Banked %s  ·  %s in the bank" % [K.money(amt), K.money(banked())], "coin", Color("3fd26b"), Color.WHITE, 2.6)

## You're down: the cash on you goes on the ground where you fell (and any you'd dropped before is lost).
func on_death(at: Vector3) -> void:
	_track()
	var s: Dictionary = game.save.data
	if not drop.is_empty():
		var lost := int(drop["amount"])
		_clear_drop()
		get_tree().create_timer(2.6, false).timeout.connect(func():
			game.ui.toast("The %s you dropped before is gone for good" % K.money(lost), "coin", Color("ff5c7a"), Color.WHITE, 3.2))
	var amt := cash()
	if amt > 0:
		s["coins"] = int(s["coins"]) - amt
		s["cash"] = 0
		_last = int(s["coins"])
		_make_drop(at, amt)
		get_tree().create_timer(3.0, false).timeout.connect(func():
			game.ui.toast("You dropped %s where you fell. One chance: get back to it (it's on the map)" % K.money(amt), "coin", Color("ffb020"), Color.WHITE, 4.0))
	game.save.save()

func _make_drop(at: Vector3, amt: int) -> void:
	at.y = game.island.height_at(at.x, at.z)
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	# a fat roll of notes, glowing, with a column of light to find it by
	var bag := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.32, 0.38)
	bag.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("3fae4a")
	mat.emission_enabled = true
	mat.emission = Color("3fd26b")
	mat.emission_energy_multiplier = 0.6
	bag.material_override = mat
	bag.position = Vector3(0, 0.3, 0)
	n.add_child(bag)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 40.0
	beam.mesh = cm
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(0.25, 1.0, 0.45, 0.22)
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3(0, 20.0, 0)
	n.add_child(beam)
	var mk: MeshInstance3D = game.island.map_marker(at, Color("3dff7a"), 12.0)
	drop = {"pos": at, "amount": amt, "node": n, "bag": bag, "t": 0.0, "mk": mk}
	game.save.data["drop"] = {"pos": [at.x, at.y, at.z], "amount": amt}

func _clear_drop() -> void:
	if not drop.is_empty() and is_instance_valid(drop["node"]):
		(drop["node"] as Node).queue_free()
	if not drop.is_empty() and drop.get("mk") != null and is_instance_valid(drop["mk"]):
		(drop["mk"] as Node).queue_free()
	drop = {}
	game.save.data.erase("drop")

func _pick_up() -> void:
	var amt := int(drop["amount"])
	_clear_drop()
	game.save.data["coins"] = int(game.save.data["coins"]) + amt       # (back as cash: bank it)
	_track()
	game.save.save()
	game.sfx("cash", 0.0, 0.9)
	game.buzz(60, 0.9)
	game.ui.toast("Got your %s back: bank it before anything else happens" % K.money(amt), "coin", Color("3fd26b"), Color.WHITE, 3.0)

# ------------------------------------------------------------------ every frame

func tick(dt: float) -> void:
	_track()
	_pulse += dt
	if not drop.is_empty() and is_instance_valid(drop["bag"]):
		(drop["bag"] as Node3D).rotation.y += dt * 1.5
		(drop["bag"] as Node3D).position.y = 0.3 + sin(_pulse * 3.0) * 0.08
		if drop.get("mk") != null and is_instance_valid(drop["mk"]):
			(drop["mk"] as Node3D).scale = Vector3.ONE * (1.0 + 0.35 * (0.5 + 0.5 * sin(_pulse * 5.0)))
	near = {}
	if game.state != game.DRIVE or game.challenge_on() or game.fights.active():
		game.ui.atm_prompt("")
		return
	var p: Vector3 = game.you().global_position
	if not drop.is_empty():
		drop["t"] = float(drop["t"]) + dt
	if not drop.is_empty() and float(drop["t"]) > 4.0 and Vector2(p.x - drop["pos"].x, p.z - drop["pos"].z).length() < (2.2 if game.on_foot else 4.0) \
			and not game.gunplay.dying:
		_pick_up()
	if game.on_foot:
		for a in atms:
			if p.distance_to(a["pos"] + (a["front"] as Vector3) * 0.8) < 2.0:
				near = a
	for b in banks:
		var d: float = Vector2(p.x - b["door"].x, p.z - b["door"].z).length()
		if d < (3.5 if game.on_foot else 9.0) and (game.on_foot or absf(game.car.speed) < 3.0):
			near = b
	var c := cash()
	game.ui.atm_prompt("" if near.is_empty() else ("BANK  " + K.money(c) if c > 0 else "Nothing on you to bank"))

## Every place to bank, for the map and the phone: [{pos, name, kind}].
func points() -> Array:
	var out: Array = []
	for b in banks:
		out.append({"pos": b["door"], "name": b["name"], "kind": "bank"})
	for a in atms:
		out.append({"pos": a["pos"], "name": a["name"], "kind": "atm"})
	return out
