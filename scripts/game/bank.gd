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
const ATM_PLACES := ["Downtown", "Town Square", "Palmer Street", "Old Harbour", "Sunny Bay"]

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
	# ATMs where an ATM goes: backed onto a shop front beside the door, on the wall of each gas station's
	# shop, and on a building front by the street in the busy parts of town
	for id in game.shops.shops:
		var sh: Dictionary = game.shops.shops[id]
		_atm_wall(sh["door"], 14.0, String(sh["def"]["name"]), 3.5)
	for st in game.island.stations:
		_atm_wall(st["pos"], 30.0, "%s gas station" % st["name"], 0.0, true)
	for nm in ATM_PLACES:
		for pl2 in game.island.places:
			if pl2["name"] == nm:
				_atm_wall(pl2["pos"], 70.0, String(nm))
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

## An ATM against a wall near `anchor` (within r): a real building's wall (tall, and wide enough: not a
## post, a pump or a cone), facing out onto the pavement by a street, with room in front of it, clear of
## doors and of the other ATMs. min_d: not right on the anchor (a shop's door). Nothing that fits: none.
func _atm_wall(anchor: Vector3, r: float, by: String, min_d := 0.0, any_side := false) -> bool:
	var space := get_world_3d().direct_space_state
	var best := {}
	var bs := INF
	var dirs: Array = []
	for k in 8:
		dirs.append(Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 8.0))
	var step := 3.0
	var ring := 0.0
	while ring <= r:
		var n_pts := maxi(1, int(TAU * ring / step))
		for i in n_pts:
			var q: Vector3 = anchor + Vector3.FORWARD.rotated(Vector3.UP, i * TAU / n_pts) * ring
			q.y = game.island.height_at(q.x, q.z)
			for d in dirs:
				var hit := _ray(space, q + Vector3(0, 1.0, 0), d, 7.0)
				if hit.is_empty():
					continue
				var nrm: Vector3 = hit["normal"]
				if absf(nrm.y) > 0.15:
					continue
				nrm.y = 0.0
				nrm = nrm.normalized()
				var c := _atm_fit(space, hit["position"], nrm, min_d, anchor, any_side)
				if c.is_empty():
					continue
				var sc: float = (c["pos"] as Vector3).distance_to(anchor) + float(c["pen"])
				if sc < bs:
					bs = sc
					best = c
		if not best.is_empty() and ring > 6.0:
			break          # (the nearest wall that fits: good enough)
		ring += step
	if best.is_empty():
		return false
	_atm(best["pos"], atan2(best["n"].x, best["n"].z), by)
	return true

func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, d: Vector3, len: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + d * len, 1)
	return space.intersect_ray(q)

## Does an ATM fit on the wall hit at w (facing n)? Returns {pos, n, pen} or {}.
func _atm_fit(space: PhysicsDirectSpaceState3D, w: Vector3, n: Vector3, min_d: float, anchor: Vector3, any_side: bool) -> Dictionary:
	var isl = game.island
	var t := Vector3(n.z, 0, -n.x)
	var base := Vector3(w.x, 0, w.z) + n * 0.42
	base.y = isl.height_at(base.x, base.z)
	if Vector2(base.x - anchor.x, base.z - anchor.z).length() < min_d:
		return {}
	# a wall: tall and wide (1.2 m either side), flat (all at the same depth)
	# (3.4 m up: a building, not a ramp or a fence)
	for o in [Vector3(0, 3.4, 0), t * 1.2 + Vector3(0, 1.0, 0), -t * 1.2 + Vector3(0, 1.0, 0), t * 1.2 + Vector3(0, 3.0, 0), -t * 1.2 + Vector3(0, 3.0, 0)]:
		var h := _ray(space, base + n * 0.6 + (o as Vector3), -n, 1.6)
		if h.is_empty() or absf((h["normal"] as Vector3).dot(n)) < 0.92:
			return {}
	# flat, level ground where it stands and in front of it
	for o in [Vector3.ZERO, n * 1.5, t * 0.6, -t * 0.6]:
		var pp: Vector3 = base + (o as Vector3)
		if absf(isl.height_at(pp.x, pp.z) - base.y) > 0.25:
			return {}
	# room: nothing in front (1.8 m) or to the sides (0.9 m)
	for d in [n * 1.8, t * 0.9, -t * 0.9, n * 1.2 + t * 0.8, n * 1.2 - t * 0.8]:
		if not _ray(space, base + Vector3(0, 0.9, 0), d, 1.0).is_empty():
			return {}
	# facing the street: a road within reach in front, but not standing on it
	var pen := 0.0
	var me: Array = game.router.nearest_near(Vector2(base.x, base.z), 24.0)
	if int(me[0]) < 0:
		if not any_side:
			return {}
		pen += 15.0
	else:
		var rw: float = float(game.island.roads[int(me[0])]["w"]) * 0.5
		if float(me[2]) < rw + 1.0:
			return {}
		var rp: Vector2 = game.router.road_at(int(me[0]), float(me[1]))
		var to_road := Vector3(rp.x - base.x, 0, rp.y - base.z).normalized()
		if to_road.dot(n) < 0.2 and not any_side:
			return {}          # (round the back, away from the street)
		pen += maxf(0.0, float(me[2]) - rw - 4.0) * 0.5
	# clear of doors (the shops', the banks') and of the other ATMs
	for id in game.shops.shops:
		if base.distance_to(game.shops.shops[id]["door"]) < 3.2:
			return {}
	for b in banks:
		if base.distance_to(b["door"]) < 5.0:
			return {}
	for a in atms:
		if base.distance_to(a["pos"]) < 40.0:
			return {}
	return {"pos": base, "n": n, "pen": pen}

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
