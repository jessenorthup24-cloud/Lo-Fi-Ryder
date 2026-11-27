extends Node3D
## Property you build up as you play: the mansion (by the sea off Bowl Exit) and the luxury garage (south of
## town, off South Street). Each starts as a bare dirt lot; stand on it and pay for the next stage, and it
## goes up stage by stage (the kits' own controllers, scripts/game/property/, grow each stage in). What you've
## put in is saved. The finished garage's bays fill with the cars you own; its door rolls up as you come.
## The finished mansion is your safehouse for heists.

const K := preload("res://scripts/ui/kit.gd")
const CARS := preload("res://scripts/game/cars.gd")
const Models := preload("res://scripts/core/models.gd")

## The plots (districts.gd reserves them and runs a driveway to the road: Districts.PLOTS).
const LIST := [
	{"id": "garage", "name": "Nightline Garage", "glb": "res://assets/property/garage.glb", "ctl": "res://scripts/game/property/garage_construction.gd",
		"targets": [0, 1500, 6000, 12000, 22000, 35000, 46000, 53000, 62000, 71000, 76000, 85000],
		"stages": ["Dirt lot", "Site work", "Foundation", "Steel frame", "Marble floor", "Walls", "Roof and skylights", "Roll-up door",
			"West bays", "East bays", "Landscaping", "Luxury details"]},
	{"id": "mansion", "name": "Nightline Mansion", "glb": "res://assets/property/mansion.glb", "ctl": "res://scripts/game/property/mansion_construction.gd",
		"targets": [0, 6000, 11000, 18000, 26000, 42000, 56000, 70000, 88000, 106000, 136000, 166000, 196000, 224000, 250000],
		"stages": ["Dirt lot", "Foundation", "Scaffolding", "Ground framing", "Ground structure", "Ground facade", "Upper framing",
			"Upper structure", "Upper facade", "Roof", "Ground interiors", "Upper interiors", "Pool and terrace", "Landscaping", "Luxury details"]},
]

var game: Node
var props := {}          # id -> {def, node (the controller), plot}
var _panel: PanelContainer
var _title: Label
var _sub: Label
var _bar: ProgressBar
var _btn: Button
var _near := ""
var _parked: Array = []
var _parked_n := -1

func build(g: Node) -> void:
	game = g
	var Districts = preload("res://scripts/game/districts.gd")
	for d in LIST:
		var plot: Dictionary = Districts.PLOTS[d["id"]]
		var c: Vector2 = plot["c"]
		var wrap := Node3D.new()
		wrap.name = "Property_" + String(d["id"])
		wrap.set_script(load(String(d["ctl"])))
		var model: Node3D = (load(String(d["glb"])) as PackedScene).instantiate()
		wrap.add_child(model)
		wrap.set("model", model)
		var tg: Array[int] = []
		for t in d["targets"]:
			tg.append(int(t))
		wrap.set("funding_targets", tg)
		wrap.set("generate_collisions", true)
		wrap.set("build_seconds", 1.6)
		add_child(wrap)
		wrap.global_transform = Transform3D(Basis(Vector3.UP, float(plot["yaw"])), Vector3(c.x, game.island.height_at(c.x, c.y) + 0.06, c.y))
		# far off it isn't drawn (it's a lot of pieces)
		for mi in model.find_children("*", "GeometryInstance3D", true, false):
			(mi as GeometryInstance3D).visibility_range_end = 420.0
		var saved: int = int((game.save.data.get("property", {}) as Dictionary).get(String(d["id"]), 0))
		if game.args.has("invest"):
			# a test: --invest=garage:85000,mansion:9000
			for kv in String(game.args["invest"]).split(","):
				if kv.begins_with(String(d["id"]) + ":"):
					saved = int(kv.split(":")[1])
		wrap.call("restore_investment", saved)
		props[d["id"]] = {"def": d, "node": wrap, "plot": plot}
	_build_panel()
	_build_hq()

## The police station (Districts.PLOTS police_hq): a plain two-storey block at the back of its yard, a
## POLICE sign out front, two patrol cars parked. Busted, you're let go on its drive (hq_spot).
func _build_hq() -> void:
	var Districts = preload("res://scripts/game/districts.gd")
	var pl: Dictionary = Districts.PLOTS["police_hq"]
	var c: Vector2 = pl["c"]
	var hs: Vector2 = pl["hs"]
	var yaw: float = pl["yaw"]
	var root := Node3D.new()
	root.name = "PoliceHQ"
	add_child(root)
	root.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, game.island.height_at(c.x, c.y), c.y))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	root.add_child(body)
	var size := Vector3(hs.x * 1.6, 7.0, hs.y * 0.8)
	var at := Vector3(0, size.y * 0.5, -hs.y + size.z * 0.5 + 0.5)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("2c3e66")
	mat.roughness = 0.9
	mi.material_override = mat
	mi.position = at
	root.add_child(mi)
	# a pale band of windows along the front
	var band := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(size.x * 0.9, 1.2, 0.1)
	band.mesh = bb
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("a8c8ff")
	wm.emission_enabled = true
	wm.emission = Color("4a6fb0")
	band.material_override = wm
	band.position = at + Vector3(0, 1.2, size.z * 0.5 + 0.05)
	root.add_child(band)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.position = at
	body.add_child(cs)
	var sign := Label3D.new()
	sign.text = "POLICE"
	sign.font_size = 160
	sign.outline_size = 24
	sign.modulate = Color.WHITE
	sign.outline_modulate = Color("1a2a55")
	sign.position = at + Vector3(0, size.y * 0.5 + 1.0, size.z * 0.5)
	sign.pixel_size = 0.012
	root.add_child(sign)
	# two patrol cars, nosed in by the building
	var pdef: Dictionary = CARS.by_id("police")
	var info: Dictionary = Models.car(pdef)
	for k in 2:
		var cr := Node3D.new()
		root.add_child(cr)
		cr.position = Vector3(-6.0 + k * 4.0, 0.0, at.z + size.z * 0.5 + 4.5)
		cr.rotation.y = 0.0
		var b := MeshInstance3D.new()
		b.mesh = info["body"]
		b.material_override = game.toon
		cr.add_child(b)
		var ws: Array = info["wheels"]
		for i in ws.size():
			var w := MeshInstance3D.new()
			w.mesh = info["wheel_f" if i % 2 == 0 else "wheel_fr"]
			w.material_override = game.toon
			w.position = ws[i]
			cr.add_child(w)

## Where you're let go after being busted: on the station's drive, facing the road.
func hq_spot() -> Transform3D:
	var Districts = preload("res://scripts/game/districts.gd")
	var pl: Dictionary = Districts.PLOTS["police_hq"]
	var c: Vector2 = pl["c"]
	var f := Vector2(sin(float(pl["yaw"])), cos(float(pl["yaw"])))
	var p := c + f * (Vector2(pl["hs"]).y + float(pl["back"]) * 0.45)
	return Transform3D(Basis(Vector3.UP, atan2(-f.x, -f.y)), Vector3(p.x, game.island.height_at(p.x, p.y) + 0.6, p.y))

## The garage's bays are up: cars you buy are kept there.
func garage_open() -> bool:
	return props.has("garage") and int(props["garage"]["node"].get("built_count")) >= 9

func invested(id: String) -> int:
	return int(props[id]["node"].get("invested")) if props.has(id) else 0

func finished(id: String) -> bool:
	return props.has(id) and int(props[id]["node"].get("built_count")) >= (props[id]["def"]["targets"] as Array).size()

## Where the mansion's front door is (the safehouse, once it's built).
func mansion_door() -> Vector3:
	var pl: Dictionary = props["mansion"]["plot"]
	var c: Vector2 = pl["c"]
	var f := Vector2(sin(float(pl["yaw"])), cos(float(pl["yaw"]))) * (Vector2(pl["hs"]).y + 4.0)
	return Vector3(c.x + f.x, game.island.height_at(c.x + f.x, c.y + f.y), c.y + f.y)

func tick(dt: float) -> void:
	if game.state != game.DRIVE:
		_panel.visible = false
		return
	var you: Vector3 = game.you().global_position
	_near = ""
	for id in props:
		var pl: Dictionary = props[id]["plot"]
		var local := Basis(Vector3.UP, float(pl["yaw"])).inverse() * (you - Vector3(Vector2(pl["c"]).x, you.y, Vector2(pl["c"]).y))
		var hs: Vector2 = pl["hs"]
		if absf(local.x) < hs.x + 6.0 and absf(local.z) < hs.y + 14.0:
			_near = id
	_show(_near)
	_garage_tick(you)

func _show(id: String) -> void:
	if id == "" or game.heist.active():
		_panel.visible = false
		return
	_panel.visible = true
	var p: Dictionary = props[id]
	var d: Dictionary = p["def"]
	var n: Node = p["node"]
	var tg: Array = d["targets"]
	var built: int = int(n.get("built_count"))
	var inv: int = int(n.get("invested"))
	_title.text = String(d["name"]).to_upper()
	if built >= tg.size() or (id == "garage" and garage_open()):
		if built >= tg.size():
			_sub.text = "Finished" + ("  ·  your safehouse" if id == "mansion" else "  ·  your cars live here")
			_bar.value = 1.0
		# (the garage, once its bays are up: swap into any car you own)
		_btn.visible = id == "garage" and not game.on_foot or (id == "garage" and built >= tg.size())
		if id == "garage":
			(_btn.get_meta("label") as Label).text = "YOUR CARS"
			_btn.set_meta("id", "open")
			_btn.modulate.a = 1.0
		if built >= tg.size():
			return
	var next: int = int(tg[built]) if built < tg.size() else int(tg.back())
	var cost := maxi(0, next - inv)
	_sub.text = "Stage %d of %d  ·  next: %s" % [built, tg.size() - 1, String(d["stages"][mini(built, tg.size() - 1)])]
	_bar.value = float(inv) / float(tg.back())
	_btn.visible = true
	var cash := int(game.save.data["coins"])
	var txt := ("BUILD  ·  " + K.money(cost)) if cash >= cost else ("NEED " + K.money(cost))
	var bl: Label = _btn.get_meta("label")
	if bl.text != txt:
		bl.text = txt
	_btn.set_meta("id", id)
	_btn.set_meta("cost", cost)
	_btn.modulate.a = 1.0 if cash >= cost else 0.55

func _pay() -> void:
	if String(_btn.get_meta("id", "")) == "open":
		game.open_garage("own")
		return
	var id := String(_btn.get_meta("id", ""))
	var cost := int(_btn.get_meta("cost", 0))
	if id != "" and not game.campaign.allows("property:" + id):
		game.ui.toast("This plot opens in chapter %d of the story" % game.campaign.lock_ch("property:" + id), "lock", K.PAPER, K.INK, 2.4)
		return
	if id == "" or cost <= 0:
		return
	if int(game.save.data["coins"]) < cost:
		game.ui.toast("Not enough cash yet", "coin", Color("ff5c7a"), Color.WHITE)
		return
	var took: int = int(props[id]["node"].call("deposit", cost))
	if took <= 0:
		return
	game.save.data["coins"] = int(game.save.data["coins"]) - took
	if not game.save.data.has("property"):
		game.save.data["property"] = {}
	game.save.data["property"][id] = int(props[id]["node"].get("invested"))
	game.save.save()
	game.sfx("cash", -2.0)
	game.buzz(30, 0.6)
	_parked_n = -1          # (new bays: park the cars again)

func _build_panel() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.055, 0.09, 0.78)
	sb.set_corner_radius_all(22)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel.position = Vector2(-230, 130)
	_panel.custom_minimum_size = Vector2(460, 0)
	_panel.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_panel.add_child(vb)
	_title = K.label("", 22, Color.WHITE, 800)
	vb.add_child(_title)
	_sub = K.label("", 16, Color(1, 1, 1, 0.75), 500)
	vb.add_child(_sub)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("ffd34d")
	fill.set_corner_radius_all(5)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	back.set_corner_radius_all(5)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	vb.add_child(_bar)
	_btn = K.button("BUILD", Color("ffb347"), Color("c77f1f"), 24, 416, 64, "coin")
	vb.add_child(_btn)
	_btn.pressed.connect(_pay)
	game.ui.hud.add_child(_panel)

## The garage: your cars in the finished bays (as models, not drivable), and the door up as you come near.
func _garage_tick(you: Vector3) -> void:
	if not props.has("garage"):
		return
	var g: Node3D = props["garage"]["node"]
	var built: int = int(g.get("built_count"))
	if built >= 8:
		var door: Vector3 = g.global_transform * Vector3(0, 0, 40.0)
		var open: bool = you.distance_to(door) < 28.0
		if open != bool(g.get_meta("door", false)):
			g.set_meta("door", open)
			g.call("set_door_open", open)
	var bays: Array = g.call("available_bays")
	if bays.size() == _parked_n:
		return
	_parked_n = bays.size()
	for n in _parked:
		n.queue_free()
	_parked.clear()
	var owned: Array = []
	for d in CARS.LIST:
		if game.save.owns(String(d["id"])) and String(d["id"]) != String(game.save.data["car"]):
			owned.append(d)
	for i in mini(bays.size(), owned.size()):
		var info: Dictionary = Models.car(owned[i])
		var xf: Transform3D = g.call("bay_transform", i + 1, true)
		var root := Node3D.new()
		add_child(root)
		root.global_transform = xf
		var body := MeshInstance3D.new()
		body.mesh = Models.painted_body(owned[i], int(game.save.data["paint"].get(String(owned[i]["id"]), 0)))
		body.material_override = game.toon
		root.add_child(body)
		var ws: Array = info["wheels"]
		for k in ws.size():
			var w := MeshInstance3D.new()
			w.mesh = info["wheel_f" if k % 2 == 0 else "wheel_fr"]
			w.material_override = game.toon
			w.position = ws[k]
			root.add_child(w)
		_parked.append(root)
