extends PanelContainer
## The phone (GTA style): your contacts, the drivers you've swapped numbers with. Call one and they come
## and drive with you (up to three); call one of your crew again to send them off. It sits to the left
## of the screen, above the steering wheel, so you can keep driving while it's up.

const K := preload("res://scripts/ui/kit.gd")
const Icon := preload("res://scripts/ui/icon.gd")

const BODY := Color("0c0b10")
const SCREEN := Color("17151f")         # (a dark screen, like the rest of the UI)
const GO := Color("54b87a")
const GO_DK := Color("3e9460")
const STYLE_COL := {"drift": Color("ff8a5c"), "grip": Color("5cc8ff"), "wild": Color("c38bff")}
const STYLE_TXT := {"drift": "drifter", "grip": "grip", "wild": "wild"}

var ui: Node
var game: Node
var list: VBoxContainer
var crew_lbl: Label
var clock_lbl: Label
var hint_lbl: Label
var _sig := ""
var _rows := {}          # who -> {dist: Label, state: Label}
var _t := 0.0
var radar_btn: Button
var dez_btn: Button
var _mode := "contacts"        # or "dez": your cars, to have one brought

func setup(u: Node, g: Node) -> void:
	ui = u
	game = g
	var sb := K.box(BODY, 34, 0, Color.TRANSPARENT, 10)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 16
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 6)
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(290, 318)
	var screen := PanelContainer.new()
	var ssb := K.box(SCREEN, 24, 0, Color.TRANSPARENT, 12)
	ssb.content_margin_top = 8
	ssb.content_margin_bottom = 10
	screen.add_theme_stylebox_override("panel", ssb)
	add_child(screen)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	screen.add_child(vb)
	# the status bar: the time, and how many are with you; the close button
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	vb.add_child(bar)
	clock_lbl = K.label("12:00", 17, K.INK_SOFT, 650, HORIZONTAL_ALIGNMENT_LEFT)
	clock_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(clock_lbl)
	crew_lbl = K.label("Crew 0/3", 17, K.INK_SOFT, 650, HORIZONTAL_ALIGNMENT_RIGHT)
	bar.add_child(crew_lbl)
	var x := K.round_button("back", K.PAPER, K.LINE, 40)
	x.pressed.connect(func():
		game.ui_tap()
		ui.toggle_phone())
	bar.add_child(x)
	# apps: the safe radar (it goes on the HUD: a pulse pointing roughly at the nearest safe)
	var apps := HBoxContainer.new()
	apps.add_theme_constant_override("separation", 8)
	vb.add_child(apps)
	radar_btn = K.button("Safe radar", Color("2c6e49"), Color("1f5036"), 17, 0, 46, "eye")
	radar_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radar_btn.pressed.connect(func():
		game.ui_tap()
		ui.radar_on = not ui.radar_on
		ui.toast("Safe radar on: follow the pulse" if ui.radar_on else "Safe radar off", "eye", Color("3fd26b"), Color.WHITE, 1.8)
		_radar_label()
		ui.toggle_phone())
	apps.add_child(radar_btn)
	# Dez: brings any car you own to wherever you are, for a fee (from level 3)
	dez_btn = K.button("Dez", Color("2f5f8a"), Color("1f4466"), 17, 0, 46, "car")
	dez_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dez_btn.pressed.connect(func():
		game.ui_tap()
		if game.Progress.level(game.save) < game.Progress.DELIVERY_LEVEL:
			ui.toast("Dez picks up at level %d" % game.Progress.DELIVERY_LEVEL, "lock", K.PAPER, K.INK, 2.0)
			return
		_mode = "contacts" if _mode == "dez" else "dez"
		_sig = ""
		refresh())
	apps.add_child(dez_btn)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	var hi := Icon.new("phone", K.INK, 24)
	hi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hi)
	head.add_child(K.label("Contacts", 22, K.INK, 750, HORIZONTAL_ALIGNMENT_LEFT))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 186)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	ui._drag_scroll(sc)
	hint_lbl = K.label("Get close to a driver to swap numbers", 13, K.INK_SOFT, 600)
	hint_lbl.clip_text = true
	vb.add_child(hint_lbl)

func _radar_label() -> void:
	K.set_text(radar_btn, "Radar: on" if ui.radar_on else "Safe radar")

func open() -> void:
	_mode = "contacts"
	_radar_label()
	_sig = ""
	refresh()

func tick(dt: float) -> void:
	_t -= dt
	if _t <= 0.0:
		_t = 0.25
		refresh()

func refresh() -> void:
	var crew: Node = game.crew
	if crew == null:
		return
	if _mode == "dez":
		var h0: float = game.atmos.hour
		clock_lbl.text = "%02d:%02d" % [int(h0) % 24, int(fmod(h0, 1.0) * 60.0)]
		var sig0 := "dez|%s|%d" % [String(game.save.data["car"]), int(game.save.data["coins"]) / 50]
		if sig0 != _sig:
			_sig = sig0
			_dez_list()
		hint_lbl.text = "Dez brings it to you, wherever you are"
		return
	var h: float = game.atmos.hour
	clock_lbl.text = "%02d:%02d" % [int(h) % 24, int(fmod(h, 1.0) * 60.0)]
	var n: int = crew.crew_count()
	crew_lbl.text = "Crew %d/%d" % [n, crew.CREW_MAX]
	var cs: Array = crew.contacts()
	var busy: bool = game.challenge_on()
	var sig := "%d|%s|" % [n, busy]
	for e in cs:
		sig += "%d:%s," % [int(e["who"]), String(e["state"])]
	if sig != _sig:
		_sig = sig
		_rebuild(cs, n, busy)
	for e in cs:
		var r: Dictionary = _rows.get(int(e["who"]), {})
		if r.is_empty():
			continue
		(r["dist"] as Label).text = _dist_txt(e)
	hint_lbl.text = "No calls during a challenge" if busy else "Get close to a driver to swap numbers"

func _dist_txt(e: Dictionary) -> String:
	match String(e["state"]):
		"crew":
			return "With you"
		"calling":
			return "Calling..."
		"cops":
			return "Police on them!"
		"busted":
			return "Busted"
		"near":
			return "%d m away" % int(e["dist"])
	return "Out of town"

func _rebuild(cs: Array, n: int, busy: bool) -> void:
	for ch in list.get_children():
		ch.queue_free()
	_rows.clear()
	if cs.is_empty():
		list.add_child(K.label("No numbers yet", 18, K.INK_SOFT, 600))
		return
	var crew: Node = game.crew
	for e in cs:
		var who := int(e["who"])
		var st := String(e["state"])
		var row := PanelContainer.new()
		var rsb := K.box(Color(1, 1, 1, 0.06) if st != "crew" else Color(0.33, 0.72, 0.48, 0.22), 18, 0, Color.TRANSPARENT, 8)
		rsb.content_margin_top = 6
		rsb.content_margin_bottom = 6
		row.add_theme_stylebox_override("panel", rsb)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		list.add_child(row)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		row.add_child(hb)
		# a round face: their initial on their style's colour
		var face := PanelContainer.new()
		face.custom_minimum_size = Vector2(42, 42)
		face.add_theme_stylebox_override("panel", K.box(STYLE_COL.get(String(e["style"]), K.SKY), 21, 0, Color.TRANSPARENT, 0))
		face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		face.add_child(K.label(String(e["name"]).substr(0, 1), 24, Color.WHITE, 750))
		hb.add_child(face)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", -5)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(info)
		info.add_child(K.label(String(e["name"]), 21, K.INK, 700, HORIZONTAL_ALIGNMENT_LEFT))
		info.add_child(K.label("%s · %s" % [String(e["car"]), STYLE_TXT.get(String(e["style"]), "")], 13, K.INK_SOFT, 600, HORIZONTAL_ALIGNMENT_LEFT))
		var dl := K.label(_dist_txt(e), 13, Color("ef6a55") if st in ["cops", "busted"] else (GO_DK if st == "crew" else K.INK_SOFT), 650, HORIZONTAL_ALIGNMENT_LEFT)
		info.add_child(dl)
		_rows[who] = {"dist": dl}
		var b: Button
		if st == "crew":
			b = K.button("Send off", K.LILAC, K.LILAC_DK, 16, 84, 44)
			b.pressed.connect(func():
				game.ui_tap()
				crew.dismiss(who)
				refresh())
		else:
			b = K.button("Call", GO, GO_DK, 18, 72, 44)
			b.disabled = busy or st == "calling" or n >= crew.CREW_MAX
			b.pressed.connect(func():
				if ui._drag_dist > 18.0:
					return
				game.ui_tap()
				crew.call_driver(who)
				refresh())
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(b)
	ui._pass_touches.call_deferred(list)

## Dez's list: every car you own (not the one you're in), each with what it costs to have it brought.
func _dez_list() -> void:
	for ch in list.get_children():
		ch.queue_free()
	_rows.clear()
	var CARS = preload("res://scripts/game/cars.gd")
	if game.Progress.level(game.save) < game.Progress.DELIVERY_LEVEL:
		list.add_child(K.label("Dez picks up from level %d.\nTill then: Lo-Fi Customs, or your garage" % game.Progress.DELIVERY_LEVEL, 16, K.INK_SOFT, 600))
		return
	var fee: int = game.delivery_fee()
	list.add_child(K.label("Dez: delivery · %s a car" % K.money(fee), 17, Color("5cc8ff"), 700, HORIZONTAL_ALIGNMENT_LEFT))
	var any := false
	for d in CARS.LIST:
		var id := String(d["id"])
		if not game.save.owns(id) or id == String(game.save.data["car"]):
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)
		var nm := K.label(String(d["name"]), 19, K.INK, 650, HORIZONTAL_ALIGNMENT_LEFT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		row.add_child(nm)
		var b := K.button("Bring it", GO, GO_DK, 16, 90, 42)
		b.disabled = int(game.save.data["coins"]) < fee or game.challenge_on()
		b.pressed.connect(func():
			if ui._drag_dist > 18.0:
				return
			game.ui_tap()
			game.deliver_car(id)
			_mode = "contacts"
			ui.toggle_phone())
		row.add_child(b)
	if not any:
		list.add_child(K.label("Buy more cars at Lo-Fi Customs", 16, K.INK_SOFT, 600))
	ui._pass_touches.call_deferred(list)
