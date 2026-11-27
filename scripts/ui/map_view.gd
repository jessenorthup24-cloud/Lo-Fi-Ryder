extends Control
## The big map: the island from above, every place worth going on it (scripts/game/guide.gd), the parts of
## town named across it in big letters (and the streets, zoomed in), a legend down the right that's also a
## filter, and the nearest things in a list. Tap a marker (or a row) for what it is, with Set as destination
## (the GPS only ever goes where you pick), Go (fast travel) and, for a race, Start. Tap open ground to drop a
## pin. Nothing's routed till you ask.

const K := preload("res://scripts/ui/kit.gd")
const Guide := preload("res://scripts/game/guide.gd")
const Icon := preload("res://scripts/ui/icon.gd")
const PANEL_W := 470.0
const SPAN := 1200.0

var ui: Node
var game: Node
var mc: Camera3D
var focus := Vector3.ZERO
var zoom := 0.3
var touches := {}
var moved := 0.0
var pts: Array = []
var off_kinds := {}
var sel := {}                  # the point the card's about ({} none)
var card: PanelContainer
var list: VBoxContainer
var legend: GridContainer
var dest_pill: PanelContainer
var _t := 0.0
var _font: Font
var _font_b: Font

func _init(u: Node) -> void:
	ui = u
	game = u.game
	mc = game.cam
	_font = K.font(650)
	_font_b = K.font(800)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	off_kinds = (game.save.data.get("map_hide", {}) as Dictionary).duplicate()
	pts = Guide.points(game)
	var yp: Vector3 = game.you().global_position
	focus = Vector3(yp.x, 0, yp.z)
	_place_cam()
	_build()

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

func _place_cam() -> void:
	var h := lerpf(120.0, 900.0, zoom)
	var off := Vector3(PANEL_W * 0.21 * (h / 500.0), 0, 0)     # (shifted: the panel covers the right)
	mc.global_transform = Transform3D(Basis(), focus + off + Vector3(0, h, h * 0.62))
	mc.look_at(focus + off, Vector3.UP)

func _scr(p: Vector3) -> Vector2:
	return mc.unproject_position(p)

func _ground_at(sp: Vector2) -> Vector3:
	var o := mc.project_ray_origin(sp)
	var dd := mc.project_ray_normal(sp)
	var q := PhysicsRayQueryParameters3D.create(o, o + dd * 3000.0, 1)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"]
	var t := -o.y / minf(dd.y, -0.01)
	return o + dd * t

# ------------------------------------------------------------------ the panels

func _build() -> void:
	var back := K.round_button("back", K.PAPER, K.LINE, 64)
	back.position = Vector2(28, 22)
	ui._tap(back, func(): ui._map_close())
	add_child(back)
	var title := K.outlined(K.label("Island map", 34, Color.WHITE, 800), K.SHADE, 8)
	title.position = Vector2(110, 30)
	add_child(title)
	var hint := K.outlined(K.label("Tap a marker for info · drag to move · pinch to zoom · tap the ground for a pin", 16, Color.WHITE, 650), K.SHADE, 6)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(30, -44)
	add_child(hint)
	# the destination you've set, top middle, with a clear
	dest_pill = PanelContainer.new()
	dest_pill.add_theme_stylebox_override("panel", K.box(Color(0.06, 0.055, 0.09, 0.85), 24, 0, Color.TRANSPARENT, 10))
	add_child(dest_pill)
	_dest_refresh()
	# the legend and the list, down the right
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", K.box(Color(0.06, 0.055, 0.09, 0.84), 24, 0, Color.TRANSPARENT, 16))
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -PANEL_W - 20
	panel.offset_right = -20
	panel.offset_top = 20
	panel.offset_bottom = -20
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	vb.add_child(K.label("LEGEND  ·  tap to show or hide", 15, Color(1, 1, 1, 0.55), 800, HORIZONTAL_ALIGNMENT_LEFT))
	legend = GridContainer.new()
	legend.columns = 2
	legend.add_theme_constant_override("h_separation", 6)
	legend.add_theme_constant_override("v_separation", 6)
	vb.add_child(legend)
	_legend_refresh()
	var found: int = game.save.data["places"].size()
	vb.add_child(K.label("NEARBY  ·  places found %d/%d" % [found, game.island.places.size()], 15, Color(1, 1, 1, 0.55), 800, HORIZONTAL_ALIGNMENT_LEFT))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	ui._drag_scroll(sc)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	_list_refresh()

func _legend_refresh() -> void:
	for c in legend.get_children():
		c.queue_free()
	for ct in Guide.CATS:
		var n := 0
		for p in pts:
			if p["kind"] == ct["id"]:
				n += 1
		if n == 0:
			continue
		var off: bool = off_kinds.get(ct["id"], false)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2((PANEL_W - 38) * 0.5, 44)
		b.add_theme_stylebox_override("normal", K.box(Color(1, 1, 1, 0.04 if off else 0.1), 14, 0, Color.TRANSPARENT, 6))
		b.add_theme_stylebox_override("hover", K.box(Color(1, 1, 1, 0.14), 14, 0, Color.TRANSPARENT, 6))
		b.add_theme_stylebox_override("pressed", K.box(Color(1, 1, 1, 0.2), 14, 0, Color.TRANSPARENT, 6))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 8
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hb)
		var pin := Control.new()
		pin.custom_minimum_size = Vector2(28, 28)
		pin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col: Color = ct["col"]
		var gl: String = ct["glyph"]
		pin.draw.connect(func(): _pin(pin, Vector2(14, 14), 12.0, col if not off else Color(col, 0.3), gl))
		hb.add_child(pin)
		var l := K.label("%s  %d" % [ct["name"], n], 16, Color(1, 1, 1, 0.35 if off else 0.92), 700, HORIZONTAL_ALIGNMENT_LEFT)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 40
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(l)
		var id: String = ct["id"]
		b.pressed.connect(func():
			game.ui_tap()
			if off_kinds.get(id, false):
				off_kinds.erase(id)
			else:
				off_kinds[id] = true
			game.save.data["map_hide"] = off_kinds.duplicate()
			if not sel.is_empty() and off_kinds.get(String(sel.get("kind", "")), false):
				_select({})
			_legend_refresh()
			_list_refresh())
		legend.add_child(b)

func _list_refresh() -> void:
	for c in list.get_children():
		c.queue_free()
	var me: Vector3 = game.you().global_position
	var show: Array = []
	for p in pts:
		if not off_kinds.get(p["kind"], false):
			show.append(p)
	show.sort_custom(func(a, b): return (a["pos"] as Vector3).distance_to(me) < (b["pos"] as Vector3).distance_to(me))
	for p in show.slice(0, 40):
		list.add_child(_row(p, me))

func _row(p: Dictionary, me: Vector3) -> Control:
	var ct := Guide.cat(p["kind"])
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 62)
	var on: bool = not sel.is_empty() and sel.get("id") == p["id"] and sel.get("kind") == p["kind"]
	b.add_theme_stylebox_override("normal", K.box(K.CREAM if not on else Color("fff2c4"), 18, 0, Color.TRANSPARENT, 8))
	b.add_theme_stylebox_override("hover", K.box(K.CREAM, 18, 0, Color.TRANSPARENT, 8))
	b.add_theme_stylebox_override("pressed", K.box(Color("fff2c4"), 18, 0, Color.TRANSPARENT, 8))
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 10
	hb.offset_right = -12
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var pin := Control.new()
	pin.custom_minimum_size = Vector2(32, 32)
	pin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: Color = ct["col"]
	var gl: String = ct["glyph"]
	pin.draw.connect(func(): _pin(pin, Vector2(16, 16), 14.0, col, gl))
	hb.add_child(pin)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", -3)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	for t in [[p["name"], 20, K.INK, 750], [p["sub"], 15, K.INK_SOFT, 600]]:
		var l := K.label(String(t[0]), int(t[1]), t[2], int(t[3]), HORIZONTAL_ALIGNMENT_LEFT)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size.x = 60
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(l)
	var dl := K.label(_dist((p["pos"] as Vector3).distance_to(me)), 16, K.INK_SOFT, 700)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(dl)
	b.pressed.connect(func():
		game.ui_tap()
		_select(p, true))
	return b

static func _dist(d: float) -> String:
	return ("%.1f km" % (d / 1000.0)) if d >= 1000.0 else ("%d m" % int(round(d / 10.0) * 10.0))

func _dest_refresh() -> void:
	for c in dest_pill.get_children():
		c.queue_free()
	dest_pill.visible = not game.route_pick.is_empty()
	if not dest_pill.visible:
		return
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	dest_pill.add_child(hb)
	hb.add_child(Icon.new("flag", Color("4aa8ff"), 26))
	hb.add_child(K.label("Destination: %s" % game.route_pick["name"], 19, Color.WHITE, 750))
	var clr := K.button("Clear", K.PAPER, K.LINE, 17, 90, 40)
	ui._tap(clr, func():
		game.set_route_pick(Vector3.ZERO, "")
		_dest_refresh()
		if not sel.is_empty():
			_select(sel))
	hb.add_child(clr)
	dest_pill.reset_size()
	var vw := get_viewport_rect().size.x
	dest_pill.position = Vector2(maxf((vw - PANEL_W - 40 - dest_pill.size.x) * 0.5 + 60.0, 330.0), 24)

# ------------------------------------------------------------------ the card

func _select(p: Dictionary, fly := false) -> void:
	sel = p
	if card != null:
		card.queue_free()
		card = null
	_list_refresh()
	if p.is_empty():
		return
	if fly:
		focus = Vector3((p["pos"] as Vector3).x, 0, (p["pos"] as Vector3).z)
		zoom = minf(zoom, 0.3)
		_place_cam()
	var ct := Guide.cat(p["kind"])
	card = PanelContainer.new()
	var sb := K.box(Color(0.06, 0.055, 0.09, 0.94), 24, 0, Color.TRANSPARENT, 18)
	sb.border_color = Color(ct["col"], 0.7)
	sb.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(560, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vb.add_child(top)
	var pin := Control.new()
	pin.custom_minimum_size = Vector2(30, 30)
	var col: Color = ct["col"]
	var gl: String = ct["glyph"]
	pin.draw.connect(func(): _pin(pin, Vector2(15, 15), 13.0, col, gl))
	top.add_child(pin)
	var kl := K.label(String(ct["name"]).to_upper(), 15, col, 800, HORIZONTAL_ALIGNMENT_LEFT)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(kl)
	var me: Vector3 = game.you().global_position
	top.add_child(K.label(_dist((p["pos"] as Vector3).distance_to(me)) + " away", 16, Color(1, 1, 1, 0.6), 700))
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.focus_mode = Control.FOCUS_NONE
	x.add_theme_font_size_override("font_size", 22)
	x.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	x.pressed.connect(func(): _select({}))
	top.add_child(x)
	vb.add_child(K.label(String(p["name"]), 30, Color.WHITE, 800, HORIZONTAL_ALIGNMENT_LEFT))
	vb.add_child(K.label(String(p["sub"]), 18, Color(1, 1, 1, 0.8), 650, HORIZONTAL_ALIGNMENT_LEFT))
	if String(p.get("info", "")) != "":
		var il := K.label(String(p["info"]), 16, Color(1, 1, 1, 0.62), 550, HORIZONTAL_ALIGNMENT_LEFT)
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		il.custom_minimum_size = Vector2(520, 0)
		vb.add_child(il)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var is_dest: bool = not game.route_pick.is_empty() and String(game.route_pick["name"]) == String(p["name"]) \
		and (game.route_pick["pos"] as Vector3).distance_to(p["pos"]) < 2.0
	if true:
		var db := K.button("✓  Destination set" if is_dest else "Set as destination", Color("4aa8ff") if not is_dest else K.PAPER,
			Color("2b78c2") if not is_dest else K.LINE, 20, 250, 54, "flag")
		db.name = "Dest"
		ui._tap(db, func():
			if is_dest:
				game.set_route_pick(Vector3.ZERO, "")
			else:
				game.set_route_pick(p["pos"], String(p["name"]))
			_dest_refresh()
			_select(sel))
		row.add_child(db)
	var xf: Variant = p.get("xf")
	if xf is Transform3D:
		var near_drop: bool = not game.bank.drop.is_empty() and p["kind"] != "drop" \
			and (game.bank.drop["pos"] as Vector3).distance_to(p["pos"]) < 150.0
		var go := K.button("Go", K.TEAL, K.TEAL_DK, 20, 90, 54)
		go.name = "Go"
		if near_drop:
			go.disabled = true
			go.modulate.a = 0.5
			go.tooltip_text = "Too close to your dropped cash: drive there"
		var st: Callable = p.get("start", Callable())
		ui._tap(go, func():
			if go.disabled:
				return
			ui.close_sheet()
			ui.transition(func():
				game.travel_to(xf)))
		row.add_child(go)
		if st.is_valid():
			var sbt := K.button("Race", K.CORAL, K.CORAL.darkened(0.3), 20, 100, 54)
			ui._tap(sbt, func():
				ui.close_sheet()
				ui.transition(func():
					game.travel_to(xf)
					st.call()))
			row.add_child(sbt)
	card.reset_size()
	card.position = Vector2(28, get_viewport_rect().size.y - card.size.y - 80)
	card.modulate.a = 0.0
	card.position.y += 20
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.18)
	tw.tween_property(card, "position:y", card.position.y - 20, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ------------------------------------------------------------------ input

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and e.pressed:
		zoom = clampf(zoom + (-0.06 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 0.06), 0.0, 1.0)
		_place_cam()
		return
	var idx := -1
	var pressed := false
	var is_press := false
	if e is InputEventScreenTouch:
		idx = e.index
		pressed = e.pressed
		is_press = true
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
		idx = 100
		pressed = e.pressed
		is_press = true
	if is_press:
		if pressed:
			touches[idx] = e.position
			if touches.size() == 1:
				moved = 0.0
		else:
			if touches.size() == 1 and moved < 14.0 and touches.has(idx):
				tap_at(e.position)
			touches.erase(idx)
		return
	var di := -1
	if e is InputEventScreenDrag:
		di = e.index
	elif e is InputEventMouseMotion and touches.has(100):
		di = 100
	if di < 0 or not touches.has(di):
		return
	var old: Vector2 = touches[di]
	if touches.size() >= 2:
		var other := Vector2.ZERO
		for k in touches:
			if k != di:
				other = touches[k]
		var d0 := old.distance_to(other)
		var d1 := (e.position as Vector2).distance_to(other)
		if d0 > 10.0:
			zoom = clampf(zoom * d0 / maxf(d1, 1.0), 0.0, 1.0)
	else:
		var dl: Vector2 = (e.position as Vector2) - old
		moved += dl.length()
		var k := lerpf(120.0, 900.0, zoom) * 2.0 / get_viewport_rect().size.y
		focus += Vector3(-dl.x, 0, -dl.y) * k
		focus = Vector3(clampf(focus.x, -SPAN * 0.5, SPAN * 0.5), 0, clampf(focus.z, -SPAN * 0.5, SPAN * 0.5))
	touches[di] = e.position
	_place_cam()

## A tap on the map: the nearest marker under it (its card), or a pin on the ground there.
func tap_at(sp: Vector2) -> void:
	var best := {}
	var bd := 30.0
	for p in pts:
		if off_kinds.get(p["kind"], false) or mc.is_position_behind(p["pos"]):
			continue
		var d := _scr(p["pos"]).distance_to(sp)
		if d < bd:
			bd = d
			best = p
	game.ui_tap()
	if not best.is_empty():
		_select(best)
		return
	var wp := _ground_at(sp)
	_select({"kind": "pin", "id": "pin", "name": "Dropped pin", "sub": _place_name(wp), "info": "", "pos": wp, "xf": null})

func _place_name(wp: Vector3) -> String:
	var best := "Out of town"
	var bd := INF
	for pl in game.island.places:
		var d := Vector2(wp.x - pl["pos"].x, wp.z - pl["pos"].z).length()
		if d < float(pl.get("r", 40.0)) * 1.3 and d < bd:
			bd = d
			best = "Near " + String(pl["name"])
	return best

# ------------------------------------------------------------------ drawing

func _pin(c: CanvasItem, at: Vector2, r: float, col: Color, glyph: String) -> void:
	c.draw_circle(at, r + 2.5, Color(0.05, 0.04, 0.07, col.a))
	c.draw_circle(at, r, col)
	var fs := int(r * 1.25)
	var w := _font_b.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(_font_b, at + Vector2(-w * 0.5, fs * 0.36), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.08, 0.06, 0.1, col.a))

func _text(p: Vector2, t: String, fs: int, col: Color, outline: int, rot := 0.0) -> void:
	var w := _font_b.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_set_transform(p, rot, Vector2.ONE)
	draw_string_outline(_font_b, Vector2(-w * 0.5, fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(0.05, 0.04, 0.08, 0.85 * col.a))
	draw_string(_font_b, Vector2(-w * 0.5, fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw() -> void:
	var vs := get_viewport_rect().size
	vs.x -= PANEL_W + 30.0        # (nothing drawn under the panel)
	# streets, zoomed in: their names along them
	if zoom < 0.22:
		var a := clampf((0.22 - zoom) / 0.08, 0.0, 1.0)
		var done := {}
		for r in game.island.roads:
			var nm: String = r["name"]
			if nm == "" or done.has(nm) or not (String(r["kind"]) in ["street", "main", "ring", "road"]):
				continue
			var rp: PackedVector2Array = r["pts"]
			if rp.size() < 2:
				continue
			# the point of it nearest the middle of the view
			var cen: Vector3 = focus
			var bi := 0
			var bdd := INF
			for k in range(0, rp.size(), 4):
				var dd := rp[k].distance_to(Vector2(cen.x, cen.z))
				if dd < bdd:
					bdd = dd
					bi = k
			if bdd > 260.0:
				continue
			var k0 := clampi(bi, 0, rp.size() - 2)
			var p0 := _scr(Vector3(rp[k0].x, 0, rp[k0].y))
			var p1 := _scr(Vector3(rp[k0 + 1].x, 0, rp[k0 + 1].y))
			var ang := (p1 - p0).angle()
			if ang > PI * 0.5:
				ang -= PI
			elif ang < -PI * 0.5:
				ang += PI
			if p0.x > vs.x - 80.0:
				continue
			done[nm] = true
			_text(p0, nm, 15, Color(1, 1, 1, 0.85 * a), 5, ang)
	# the parts of town, big
	for pl in game.island.places:
		var r := float(pl.get("r", 40.0))
		var big := r >= 50.0
		if not big and zoom > 0.55:
			continue
		var pp: Vector3 = pl["pos"]
		pp.y = game.island.height_at(pp.x, pp.z)
		if mc.is_position_behind(pp):
			continue
		var s := _scr(pp)
		var half := _font_b.get_string_size(String(pl["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x * 0.5
		if s.x + half > vs.x:
			continue
		if s.x < -200 or s.y < -100 or s.y > vs.y + 100:
			continue
		var fs := int(lerpf(42.0, 28.0, zoom)) if big else int(lerpf(26.0, 19.0, zoom))
		_text(s, String(pl["name"]).to_upper(), fs, Color(1, 1, 1, 0.92) if big else Color(1, 0.95, 0.85, 0.85), 8)
	# the markers (fights and your dropped cash pulse, so they stand out)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var r0 := lerpf(15.0, 10.0, zoom)
	for p in pts:
		if off_kinds.get(p["kind"], false):
			continue
		var wp: Vector3 = p["pos"]
		if mc.is_position_behind(wp):
			continue
		var s2 := _scr(wp)
		if s2.x < -30 or s2.x > vs.x or s2.y < -30 or s2.y > vs.y + 30:
			continue
		var ct := Guide.cat(p["kind"])
		var col: Color = ct["col"]
		if p.get("dim", false):
			col = Color(col.lerp(Color(0.6, 0.6, 0.6), 0.6), 0.75)
		var rr := r0 * (1.25 if p["kind"] in ["drop", "fight", "bank"] else (0.75 if p["kind"] == "atm" else (0.8 if p["kind"] == "heist" else 1.0)))
		if p["kind"] in ["drop", "fight"]:
			draw_arc(s2, rr + 6.0 + pulse * 8.0, 0.0, TAU, 40, Color(col, 0.75 - pulse * 0.5), 3.0, true)
		if not sel.is_empty() and sel.get("id") == p["id"] and sel.get("kind") == p["kind"]:
			draw_arc(s2, rr + 8.0, 0.0, TAU, 40, Color.WHITE, 4.0, true)
		_pin(self, s2, rr, col, String(ct["glyph"]))
	# a dropped pin, the destination, a heist's target
	if not sel.is_empty() and sel["kind"] == "pin":
		_flag(sel["pos"], Color.WHITE)
	if not game.route_pick.is_empty():
		_flag(game.route_pick["pos"], Color("4aa8ff"))
	var ht: Dictionary = game.heist.route()
	if not ht.is_empty():
		_flag(ht["pos"], Color("ffb347"))
	# you
	var cp3: Vector3 = game.you().global_position
	if not mc.is_position_behind(cp3):
		var cy: float = game.you().global_rotation.y if not game.on_foot else float(game.foot.facing)
		var c := _scr(cp3)
		var f := Vector2(-sin(cy), -cos(cy))
		var rt := Vector2(-f.y, f.x)
		var poly := PackedVector2Array([c + f * 18.0, c - f * 11.0 + rt * 11.0, c - f * 4.0, c - f * 11.0 - rt * 11.0])
		draw_colored_polygon(poly, Color.WHITE)
		draw_polyline(poly + PackedVector2Array([poly[0]]), K.SHADE, 3.0)

func _flag(wp: Vector3, col: Color) -> void:
	if mc.is_position_behind(wp):
		return
	var w := _scr(wp)
	draw_line(w, w - Vector2(0, 30), K.SHADE, 4.0)
	draw_circle(w - Vector2(0, 34), 11.0, K.SHADE)
	draw_circle(w - Vector2(0, 34), 8.0, col)
	draw_circle(w, 4.0, K.SHADE)
