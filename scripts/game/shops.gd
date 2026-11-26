extends Node3D
## The shops in town, on Main Street (Districts.SHOP_PLOTS): Lo-Fi Customs (cars: buy, paint, tune, upgrade),
## the Armory (guns and their attachments) and Lo-Fi Threads (who you are). Pull up or walk up to the front
## door and go in: the shop's screen opens (ui.gd's garage screen, showing that shop's counters).

const Districts := preload("res://scripts/game/districts.gd")

const LIST := [
	{"id": "customs", "name": "Lo-Fi Customs", "glb": "res://assets/shops/customs.glb", "col": Color("5cc8ff"), "icon": "car",
		"tag": "Cars, paint, tuning and upgrades"},
	{"id": "armory", "name": "The Armory", "glb": "res://assets/shops/armory.glb", "col": Color("ff6b5c"), "icon": "star",
		"tag": "Guns and attachments"},
	{"id": "threads", "name": "Lo-Fi Threads", "glb": "res://assets/shops/threads.glb", "col": Color("c38bff"), "icon": "group",
		"tag": "Characters and looks"},
]

var game: Node
var shops := {}           # id -> {def, node, door (world), front (unit, out of the door)}
var near := ""            # the shop whose door you're at

func build(g: Node) -> void:
	game = g
	for d in LIST:
		var id: String = d["id"]
		var pl: Dictionary = Districts.SHOP_PLOTS[id]
		var c: Vector2 = pl["c"]
		var yaw: float = pl["yaw"]
		var model: Node3D = (load(String(d["glb"])) as PackedScene).instantiate()
		model.name = "Shop_" + id
		add_child(model)
		model.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, game.island.height_at(c.x, c.y) + 0.02, c.y))
		# the building itself (not its trees, lamps and planters): the big pieces, made solid
		var body := AABB()
		var first := true
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			m.visibility_range_end = 380.0
			var ab := _local(model, m) * m.get_aabb()
			if ab.size.y > 2.5 and (ab.size.x > 6.0 or ab.size.z > 6.0):
				body = ab if first else body.merge(ab)
				first = false
		if first:
			body = AABB(Vector3(-8, 0, -6), Vector3(16, 5, 12))
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(body.size.x, maxf(body.size.y, 4.0), body.size.z - 0.3)
		cs.shape = bx
		cs.position = body.get_center() - Vector3(0, 0, 0.15)
		sb.add_child(cs)
		model.add_child(sb)
		var bs := Basis(Vector3.UP, yaw)
		var door: Vector3 = model.global_transform * Vector3(body.get_center().x, 0, body.end.z + 1.6)
		door.y = game.island.height_at(door.x, door.z)
		shops[id] = {"def": d, "node": model, "door": door, "front": bs * Vector3(0, 0, 1)}
		game.island.map_marker(door, d["col"], 10.0)
		# (lit a little at night: a lamp over the door)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.85, 0.6)
		lamp.omni_range = 9.0
		lamp.light_energy = 0.0
		lamp.position = Vector3(body.get_center().x, 3.6, body.end.z + 1.0)
		model.add_child(lamp)
		shops[id]["lamp"] = lamp

func _local(root: Node3D, n: Node3D) -> Transform3D:
	var x := Transform3D()
	var p: Node = n
	while p != null and p != root:
		if p is Node3D:
			x = (p as Node3D).transform * x
		p = p.get_parent()
	return x

## At a door (on foot by it, or pulled up in front of it, slow): show the way in.
func tick(_dt: float) -> void:
	near = ""
	if game.state != game.DRIVE or game.challenge_on() or game.heist.active():
		game.ui.shop_prompt("")
		return
	var you: Node3D = game.you()
	var p := you.global_position
	for id in shops:
		var s: Dictionary = shops[id]
		var d: float = Vector2(p.x - s["door"].x, p.z - s["door"].z).length()
		var ok: bool = d < 3.2 if game.on_foot else (d < 9.0 and absf(game.car.speed) < 3.0)
		if ok:
			near = id
	game.ui.shop_prompt("" if near == "" else "ENTER  " + String(shops[near]["def"]["name"]).to_upper())

func enter() -> void:
	if near != "":
		game.open_shop(near)

func door_of(id: String) -> Vector3:
	return shops[id]["door"] if shops.has(id) else Vector3.ZERO

## Where to put you back out: just in front of the door, facing away from it.
func out_spot(id: String) -> Transform3D:
	var s: Dictionary = shops[id]
	var f: Vector3 = s["front"]
	var p: Vector3 = (s["door"] as Vector3) + f * 2.0
	return Transform3D(Basis(Vector3.UP, atan2(f.x, f.z)), p)
