extends CanvasLayer
## Every screen, built in code, laid out for landscape (1280x720 and wider): loading, title, the
## driving HUD (steering, pedals, speedo, drift meter, minimap), challenge cards, the map, pause,
## settings, trophies and the garage (cars and upgrades).

const K := preload("res://scripts/ui/kit.gd")
const Icon := preload("res://scripts/ui/icon.gd")
const CARS := preload("res://scripts/game/cars.gd")
const M := preload("res://scripts/core/models.gd")
const PAL := preload("res://scripts/core/palette.gd")
const MB := preload("res://scripts/core/mesh_builder.gd")
const Ach := preload("res://scripts/game/achievements.gd")
const SaveData := preload("res://scripts/game/save.gd")
const CarScript := preload("res://scripts/game/drift_car.gd")
const Phone := preload("res://scripts/ui/phone.gd")

var game: Node
var island: Node
var root: Control
var loading: Control
var title: Control
var hud: Control
var garage: Control
var overlay: Control
var popups: Control
var toasts: VBoxContainer
var wipe: ColorRect
var wipe_mat: ShaderMaterial

# hud
var ctl := {}                 # left, right, gas, brake, hand -> Control
var speed_lbl: Label
var gear_lbl: Label
var rpm_bar: ProgressBar
var drift_card: PanelContainer
var drift_lbl: Label
var combo_lbl: Label
var combo_bar: ProgressBar
var angle_lbl: Label
var coins_pill: PanelContainer
var place_lbl: Label
var clock_lbl: Label
var chal_card: PanelContainer
var chal_name: Label
var chal_main: Label
var chal_sub: Label
var mini_vp: SubViewport
var mini_cam: Camera3D
var mini_wrap: Control
var reset_hint: Button
var _drift_show := 0.0
var _bank_t := 0.0
var _pop_n := 0
var fuel_g: Control          # the fuel and condition gauges by the speedo
var cond_g: Control
var route_box: Control       # the GPS arrow, top middle
var route_lbl: Label
var _route_ang := 0.0
var _route_on := false
var station_card: PanelContainer
var station_lbl: Label
var st_fuel_lbl: Label
var st_cond_lbl: Label
var st_fuel_btn: Button
var st_cond_btn: Button
var _last_coins := -1
var _hint_t := 0.0
var _hud_data := {}
var title_logo: Control
var title_coins: PanelContainer

# garage
var g_view: SubViewport
var g_root3d: Node3D
var g_car: Node3D
var g_turn: Node3D
var g_mat: ShaderMaterial
var g_index := 0
var g_from := 1
var g_panel: VBoxContainer
var g_coins: PanelContainer
var g_tab := "cars"
var g_paint := -1            # the paint job being tried on in the showroom (-1: the one it wears)
const PAINT_PRICE := 250
var g_spin := 0.0
var g_drag := 0.0
var g_neon: Node3D = null       # the underglow on the car on show (lit as light, by _garage_neon)
var g_neon_y := 0.0
var speed_fx: ColorRect          # streaks at the screen edges when you're flying along
var count_lbl: Label             # the race countdown, big in the middle
var sweet_meter: Control         # the drift angle, with the sweet spot marked
var wheel: Control               # the steering wheel (top half), bottom left
var _fps_t := 0.0
var _fps_worst := 0.0
var _fps_txt := ""
var count_ring: Control          # (and the burst of colour behind each number)
var start_card: PanelContainer   # a challenge's card, up while you sit in its beacon
var _start_cb := Callable()
var speed_k := 0.0
var wanted_box: HBoxContainer    # the police: wanted stars, under the minimap
var wanted_stars: Array = []
var limit_sign: PanelContainer   # the speed limit, by the speedo while a patrol car's about
var limit_lbl: Label
var phone: Phone                 # the phone: your contacts (the drivers), to call them to drive with you
var phone_btn: Button

func setup(g: Node) -> void:
	game = g
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	speed_fx = ColorRect.new()
	speed_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	speed_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/speed.gdshader")
	speed_fx.material = sm
	speed_fx.visible = false
	popups = _full(Control.MOUSE_FILTER_IGNORE)
	_build_hud()
	hud.add_child(speed_fx)          # under everything on the HUD, and hidden with it
	hud.move_child(speed_fx, 0)
	_build_title()
	_build_garage()
	overlay = _full(Control.MOUSE_FILTER_STOP)
	overlay.visible = false
	toasts = VBoxContainer.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toasts.position = Vector2(-330, 150)
	toasts.custom_minimum_size = Vector2(660, 0)
	toasts.size = Vector2(660, 0)
	toasts.add_theme_constant_override("separation", 10)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)
	_build_loading()
	wipe = ColorRect.new()
	wipe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wipe_mat = ShaderMaterial.new()
	wipe_mat.shader = load("res://shaders/wipe.gdshader")
	wipe.material = wipe_mat
	root.add_child(wipe)
	_set_wipe(0.0)

func _full(filter: int) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = filter
	root.add_child(c)
	return c

func _tap(b: BaseButton, f: Callable) -> void:
	b.pressed.connect(func():
		if _drag_dist > 18.0:
			return          # (that was a finger scrolling a list, not a tap)
		game.ui_tap()
		f.call())

## How far the finger has moved since it touched down (so scrolling a list doesn't press what it started on).
var _drag_dist := 0.0

func _input(e: InputEvent) -> void:
	if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		_drag_dist = 0.0
	elif e is InputEventScreenDrag:
		_drag_dist += (e as InputEventScreenDrag).relative.length()
	elif e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and not DisplayServer.is_touchscreen_available():
		_drag_dist += (e as InputEventMouseMotion).relative.length()

## A list you scroll by dragging anywhere on it (rows and buttons included), with a bar you can grab too.
func _drag_scroll(sc: ScrollContainer) -> void:
	sc.scroll_deadzone = 100000          # (our own dragging below, the same on every phone)
	var bar := sc.get_v_scroll_bar()
	bar.custom_minimum_size.x = 16
	bar.add_theme_stylebox_override("scroll", K.box(Color(0, 0, 0, 0.06), 8, 0, Color.TRANSPARENT, 0))
	bar.add_theme_stylebox_override("grabber", K.box(Color(0, 0, 0, 0.28), 8, 0, Color.TRANSPARENT, 0))
	bar.add_theme_stylebox_override("grabber_highlight", K.box(Color(0, 0, 0, 0.36), 8, 0, Color.TRANSPARENT, 0))
	bar.add_theme_stylebox_override("grabber_pressed", K.box(Color(0, 0, 0, 0.42), 8, 0, Color.TRANSPARENT, 0))
	sc.gui_input.connect(func(e: InputEvent):
		var rel := Vector2.ZERO
		if e is InputEventScreenDrag:
			rel = (e as InputEventScreenDrag).relative
		elif e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and not DisplayServer.is_touchscreen_available():
			rel = (e as InputEventMouseMotion).relative
		if rel.y != 0.0:
			sc.scroll_vertical -= int(round(rel.y)))
	_pass_touches.call_deferred(sc)

func _pass_touches(n: Node) -> void:
	for c in n.get_children():
		if c is ScrollBar:
			continue
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_PASS
		_pass_touches(c)

func _vs() -> Vector2:
	return root.get_viewport_rect().size

func _set_wipe(p: float) -> void:
	wipe_mat.set_shader_parameter("progress", p)
	var vs := _vs()
	wipe_mat.set_shader_parameter("aspect", Vector2(vs.x / maxf(vs.y, 1.0), 1.0))
	wipe.visible = p > 0.001
	wipe.mouse_filter = Control.MOUSE_FILTER_STOP if p > 0.5 else Control.MOUSE_FILTER_IGNORE

func transition(mid: Callable) -> void:
	var t := create_tween()
	t.tween_method(_set_wipe, 0.0, 1.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(mid)
	t.tween_interval(0.1)
	t.tween_method(_set_wipe, 1.0, 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# ------------------------------------------------------------------ loading

func _build_loading() -> void:
	loading = _full(Control.MOUSE_FILTER_STOP)
	var bg := ColorRect.new()
	bg.color = Color("d8d3cb")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vb.position = Vector2(-300, -110)
	vb.size = Vector2(600, 220)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	loading.add_child(vb)
	vb.add_child(K.outlined(K.label("Lo-Fi Dryfter", 84, K.PAPER, 700), K.INK, 16))
	var l := K.outlined(K.label("Building the island...", 32, Color.WHITE, 650), K.INK, 10)
	l.name = "Msg"
	vb.add_child(l)
	loading.visible = false

func show_loading() -> void:
	loading.visible = true
	title.visible = false
	hud.visible = false

func world_ready(isl: Node) -> void:
	island = isl
	_setup_minimap()
	var t := create_tween()
	t.tween_property(loading, "modulate:a", 0.0, 0.5)
	t.tween_callback(func(): loading.visible = false)

# ------------------------------------------------------------------ title

func _build_title() -> void:
	title = _full(Control.MOUSE_FILTER_IGNORE)
	title.visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.08, 0.2, 0.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(shade)
	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 64
	left.offset_right = 640
	left.offset_top = 70
	left.offset_bottom = -50
	left.add_theme_constant_override("separation", 16)
	title.add_child(left)
	title_logo = Control.new()
	title_logo.custom_minimum_size = Vector2(560, 120)
	left.add_child(title_logo)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	title_logo.add_child(row)
	var i := 0
	for ch in "Lo-Fi Dryfter":
		var l := K.outlined(K.label(ch, 100, K.PAPER, 700), K.INK, 16)
		l.set_meta("i", i)
		row.add_child(l)
		i += 1
	left.add_child(K.outlined(K.label("drift the streets of a little island town", 34, Color.WHITE, 650, HORIZONTAL_ALIGNMENT_LEFT), K.INK, 10))
	left.add_child(K.spacer(26))
	var go := K.button("Drive", K.CORAL, K.CORAL_DK, 50, 360, 112, "play")
	_tap(go, func(): transition(func(): game.start_drive()))
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(go)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	left.add_child(row2)
	for b in [["car", "Garage", K.TEAL, K.TEAL_DK, func(): game.open_garage()], ["map", "Map", K.SUN, K.SUN_DK, func(): open_map()],
			["trophy", "Trophies", K.SKY, K.SKY_DK, func(): open_achievements()], ["gear", "", K.LILAC, K.LILAC_DK, func(): open_settings()]]:
		var bt := K.button(b[1], b[2], b[3], 30, 84 if b[1] == "" else 170, 84, b[0])
		_tap(bt, b[4])
		row2.add_child(bt)
	title_coins = K.pill("coin", "0")
	title_coins.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	title_coins.position = Vector2(-260, 36)
	title.add_child(title_coins)
	var bl := K.outlined(K.label("", 22, Color.WHITE, 600, HORIZONTAL_ALIGNMENT_LEFT), K.INK, 6)
	bl.name = "Build"
	bl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bl.position = Vector2(24, -44)
	title.add_child(bl)

func show_title() -> void:
	title.visible = true
	hud.visible = false
	garage.visible = false
	close_sheet()
	title.modulate.a = 1.0
	title_coins.get_meta("label").text = K.fmt(int(game.save.data["coins"]))
	(title.get_node("Build") as Label).text = "Lo-Fi Dryfter · %s · %d/%d trophies" % [build_label(), Ach.count(game.save.data), Ach.LIST.size()]

static func build_label() -> String:
	var v = JSON.parse_string(FileAccess.get_file_as_string("res://version.json")) if FileAccess.file_exists("res://version.json") else null
	return String(v.get("label", "dev")) if v is Dictionary else "dev"

func _title_tick(t: float) -> void:
	var row: HBoxContainer = title_logo.get_child(0)
	for ch in row.get_children():
		var i: int = ch.get_meta("i")
		ch.position.y = sin(t * 2.2 + i * 0.55) * 7.0
		ch.rotation = sin(t * 1.6 + i * 0.8) * 0.04

# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	hud = _full(Control.MOUSE_FILTER_IGNORE)
	hud.visible = false
	# top left: pause, where you are, the time
	var tl := HBoxContainer.new()
	tl.position = Vector2(26, 22)
	tl.add_theme_constant_override("separation", 14)
	hud.add_child(tl)
	var pb := K.round_button("pause", K.PAPER, K.LINE, 72)
	_tap(pb, func(): game.pause())
	tl.add_child(pb)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", -4)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(info)
	place_lbl = K.outlined(K.label("", 30, Color.WHITE, 700, HORIZONTAL_ALIGNMENT_LEFT), K.INK, 10)
	info.add_child(place_lbl)
	clock_lbl = K.outlined(K.label("", 24, Color.WHITE, 600, HORIZONTAL_ALIGNMENT_LEFT), K.INK, 8)
	info.add_child(clock_lbl)
	# top right: coins, minimap, camera and map buttons
	coins_pill = K.pill("coin", "0")
	coins_pill.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	coins_pill.position = Vector2(-250, 22)
	hud.add_child(coins_pill)
	mini_wrap = Panel.new()
	mini_wrap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mini_wrap.size = Vector2(196, 196)
	mini_wrap.position = Vector2(-222, 90)
	mini_wrap.add_theme_stylebox_override("panel", K.box(Color.WHITE, 98, 0, Color.TRANSPARENT, 0))
	mini_wrap.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	mini_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	mini_wrap.gui_input.connect(func(e):
		if e is InputEventScreenTouch and not e.pressed or (e is InputEventMouseButton and not e.pressed):
			game.ui_tap()
			game.pause()
			open_map())
	hud.add_child(mini_wrap)
	var ring := Panel.new()
	ring.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	ring.size = Vector2(204, 204)
	ring.position = Vector2(-226, 86)
	var rsb := K.box(Color.TRANSPARENT, 102, 0, Color.TRANSPARENT, 0)
	rsb.border_color = K.PAPER
	rsb.set_border_width_all(6)
	ring.add_theme_stylebox_override("panel", rsb)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(ring)
	mini_ring = ring
	var camb := K.round_button("eye", K.PAPER, K.LINE, 64)
	camb.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	camb.position = Vector2(-300, 230)
	_tap(camb, func(): game.toggle_cam())
	hud.add_child(camb)
	# the phone: call the drivers you know
	phone_btn = K.round_button("phone", K.PAPER, K.LINE, 64)
	phone_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	phone_btn.position = Vector2(-300, 152)
	_tap(phone_btn, func(): toggle_phone())
	hud.add_child(phone_btn)
	phone = Phone.new()
	phone.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	phone.position = Vector2(26, 204)
	phone.size = Vector2(290, 318)
	phone.visible = false
	hud.add_child(phone)
	phone.setup(self, game)
	# REWIND: hold it to take the last few seconds back
	var rw := PanelContainer.new()
	rw.add_theme_stylebox_override("panel", K.box(Color(K.PAPER, 0.7), 30, 6, Color(K.LINE_DK, 0.7), 0))
	rw.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	rw.position = Vector2(-432, 226)
	rw.size = Vector2(118, 70)
	rw.custom_minimum_size = rw.size
	rw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rw.pivot_offset = rw.size * 0.5
	var rwh := HBoxContainer.new()
	rwh.alignment = BoxContainer.ALIGNMENT_CENTER
	rwh.add_theme_constant_override("separation", 4)
	rwh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rw.add_child(rwh)
	var rwi := Icon.new("back", K.INK, 30)
	rwi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rwh.add_child(rwi)
	rwh.add_child(K.label("REWIND", 17, K.INK, 750))
	hud.add_child(rw)
	ctl["rewind"] = rw
	_build_wanted()
	# the challenge card, top middle
	chal_card = K.card(K.PAPER, 22)
	chal_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	chal_card.custom_minimum_size = Vector2(300, 0)
	chal_card.position = Vector2(-150, 14)
	var csb: StyleBoxFlat = (chal_card.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	csb.content_margin_top = 6
	csb.content_margin_bottom = 8
	csb.content_margin_left = 18
	csb.content_margin_right = 18
	chal_card.add_theme_stylebox_override("panel", csb)
	chal_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(chal_card)
	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", -2)
	chal_card.add_child(cvb)
	chal_name = K.label("", 18, K.INK_SOFT, 650)
	cvb.add_child(chal_name)
	chal_main = K.label("", 32, K.INK, 700)
	cvb.add_child(chal_main)
	chal_sub = K.label("", 16, K.INK_SOFT, 600)
	cvb.add_child(chal_sub)
	chal_card.visible = false
	# the drift meter: a slim readout up in the top left, under the place name, out of the way of the road
	drift_card = PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.08, 0.08, 0.09, 0.34)
	dsb.set_corner_radius_all(10)
	dsb.border_color = Color("e8dcc4")
	dsb.border_width_left = 4
	dsb.content_margin_left = 12
	dsb.content_margin_right = 12
	dsb.content_margin_top = 2
	dsb.content_margin_bottom = 6
	drift_card.add_theme_stylebox_override("panel", dsb)
	drift_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	drift_card.custom_minimum_size = Vector2(196, 0)
	drift_card.position = Vector2(28, 108)
	drift_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(drift_card)
	var dvb := VBoxContainer.new()
	dvb.add_theme_constant_override("separation", -2)
	drift_card.add_child(dvb)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 8)
	dvb.add_child(dh)
	drift_lbl = K.outlined(K.label("0", 32, Color.WHITE, 700, HORIZONTAL_ALIGNMENT_LEFT), K.INK, 7)
	dh.add_child(drift_lbl)
	combo_lbl = K.outlined(K.label("x1", 22, Color("e8dcc4"), 700, HORIZONTAL_ALIGNMENT_LEFT), K.INK, 6)
	combo_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	dh.add_child(combo_lbl)
	angle_lbl = K.label("DRIFT", 15, Color(1, 1, 1, 0.85), 650, HORIZONTAL_ALIGNMENT_LEFT)
	dvb.add_child(angle_lbl)
	# the drift angle on a little scale, 0-60°, with the sweet spot marked
	sweet_meter = Control.new()
	sweet_meter.custom_minimum_size = Vector2(172, 12)
	sweet_meter.set_meta("a", 0.0)
	sweet_meter.draw.connect(func():
		var w := sweet_meter.size.x
		var a: float = sweet_meter.get_meta("a")
		sweet_meter.draw_rect(Rect2(0, 4, w, 4), Color(1, 1, 1, 0.22))
		var s0: float = CarScript.SWEET[0] / 60.0 * w
		var s1: float = CarScript.SWEET[1] / 60.0 * w
		var inside := a >= CarScript.SWEET[0] and a <= CarScript.SWEET[1]
		sweet_meter.draw_rect(Rect2(s0, 3, s1 - s0, 6), Color("54e08a") if inside else Color(0.33, 0.88, 0.54, 0.55))
		var x := clampf(a / 60.0, 0.0, 1.0) * w
		sweet_meter.draw_rect(Rect2(x - 2, 0, 4, 12), Color.WHITE))
	dvb.add_child(sweet_meter)
	combo_bar = K.bar(172, 4, Color("e8dcc4"), Color(1, 1, 1, 0.22))
	dvb.add_child(combo_bar)
	drift_card.modulate.a = 0.0
	_build_route_and_station()
	# speedo, bottom middle
	var sp := VBoxContainer.new()
	sp.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	sp.position = Vector2(-120, -150)
	sp.size = Vector2(240, 130)
	sp.add_theme_constant_override("separation", -10)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(sp)
	speed_lbl = K.outlined(K.label("0", 76, Color.WHITE, 700), K.INK, 14)
	sp.add_child(speed_lbl)
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 12)
	sp.add_child(srow)
	srow.add_child(K.outlined(K.label("km/h", 24, Color.WHITE, 650), K.INK, 8))
	gear_lbl = K.outlined(K.label("1", 28, Color("e8dcc4"), 700), K.INK, 8)
	srow.add_child(gear_lbl)
	sp.add_child(K.spacer(14))
	rpm_bar = K.bar(200, 10, K.PAPER, Color(0, 0, 0, 0.25))
	rpm_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sp.add_child(rpm_bar)
	# fuel (left of the speedo) and condition (right): slim upright bars
	fuel_g = _gauge("fuel", Vector2(-176, -146))
	cond_g = _gauge("gear", Vector2(142, -146))
	# steering, bottom left
	ctl["left"] = _pad("left", Vector2(40, -210), Vector2(170, 170), true, K.PAPER)
	ctl["right"] = _pad("right", Vector2(230, -210), Vector2(170, 170), true, K.PAPER)
	_build_wheel()
	# pedals, bottom right
	ctl["brake"] = _pad("brake", Vector2(-420, -210), Vector2(130, 170), false, K.PAPER)
	ctl["gas"] = _pad("gas", Vector2(-270, -250), Vector2(150, 210), false, K.PAPER)
	ctl["hand"] = _pad("hand", Vector2(-420, -360), Vector2(130, 120), false, K.PAPER)
	ctl["nos"] = _pad("nos", Vector2(-270, -380), Vector2(150, 116), false, Color("cfe9ff"))
	reset_hint = K.button("Stuck? Reset car", K.SUN, K.SUN_DK, 28, 0, 72, "home")
	reset_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reset_hint.position = Vector2(-160, 60)
	_tap(reset_hint, func():
		reset_hint.visible = false
		game.reset_car())
	reset_hint.visible = false
	hud.add_child(reset_hint)

## A big touch pad. It isn't a Button: main reads touches on it directly, so several work at once.
func _pad(name: String, pos: Vector2, size: Vector2, left_side: bool, col: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", K.box(Color(col, 0.62), 34 if name != "hand" else 40, 8, Color(K.LINE_DK, 0.7), 0))
	if left_side:
		p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	else:
		p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	p.position = pos
	p.size = size
	p.custom_minimum_size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.pivot_offset = size * 0.5
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(vb)
	match name:
		"left", "right":
			var ic := Icon.new(name, K.INK, 92)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			vb.add_child(ic)
		"gas":
			vb.add_child(K.label("GAS", 34, K.INK, 700))
			var ic2 := Icon.new("play", K.INK, 56)
			ic2.rotation = -PI * 0.5
			ic2.pivot_offset = Vector2(28, 28)
			ic2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			vb.add_child(ic2)
		"brake":
			vb.add_child(K.label("BRAKE", 26, K.INK, 700))
			vb.add_child(K.label("hold: reverse", 15, K.INK_SOFT, 600))
		"hand":
			vb.add_child(K.label("DRIFT", 26, K.INK, 700))
			vb.add_child(K.label("handbrake", 16, K.INK_SOFT, 600))
		"nos":
			vb.add_child(K.label("NOS", 30, Color("1f4f7a"), 800))
			# how much is in the bottle
			var fill := Control.new()
			fill.custom_minimum_size = Vector2(104, 12)
			fill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fill.set_meta("v", 1.0)
			fill.draw.connect(func():
				var v: float = fill.get_meta("v")
				fill.draw_rect(Rect2(Vector2.ZERO, fill.size), Color(0.1, 0.2, 0.3, 0.35))
				fill.draw_rect(Rect2(Vector2.ZERO, Vector2(fill.size.x * clampf(v, 0.0, 1.0), fill.size.y)), Color("3aa0ff") if v > 0.2 else Color("ef6a55")))
			vb.add_child(fill)
			p.set_meta("fill", fill)
	hud.add_child(p)
	return p

## The police, the way GTA does it: five stars under the minimap (none lit, none shown, till they're
## after you). The lit ones flash while they've lost sight of you and turn red as they box you in, and the
## minimap's rim flashes red and blue while they've got you. A line under the stars says what for, for a
## few seconds. No banners. And a speed limit sign by the speedo whenever a patrol car's about.
var wanted_why: Label
var _wanted_fade := 0.0      # (fading the stars out after you've lost them)
var _wanted_shown := 0       # (stars lit last frame)
var _why_t := 0.0
var mini_ring: Panel
func _build_wanted() -> void:
	var box := HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.position = Vector2(-214, 294)
	box.size = Vector2(180, 34)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = false
	hud.add_child(box)
	wanted_box = box
	for i in 5:
		var st := Icon.new("star", Color("f4efe2"), 32)
		st.pivot_offset = Vector2(16, 16)
		box.add_child(st)
		wanted_stars.append(st)
	wanted_why = K.outlined(K.label("", 16, Color.WHITE, 700), K.INK, 6)
	wanted_why.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	wanted_why.position = Vector2(-304, 330)
	wanted_why.size = Vector2(360, 24)
	wanted_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wanted_why.visible = false
	hud.add_child(wanted_why)
	limit_sign = PanelContainer.new()
	var lsb := K.box(Color.WHITE, 40, 0, Color.TRANSPARENT, 0)
	lsb.border_color = Color("e0303e")
	lsb.set_border_width_all(9)
	limit_sign.add_theme_stylebox_override("panel", lsb)
	limit_sign.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	limit_sign.position = Vector2(132, -150)
	limit_sign.size = Vector2(80, 80)
	limit_sign.custom_minimum_size = limit_sign.size
	limit_sign.pivot_offset = limit_sign.size * 0.5
	limit_sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	limit_sign.visible = false
	limit_lbl = K.label("50", 30, K.INK, 800)
	limit_sign.add_child(limit_lbl)
	hud.add_child(limit_sign)

## They're after you: the stars come up (a quick pop), and what for underneath.
func wanted_start(why: String) -> void:
	_wanted_fade = 0.0
	wanted_box.visible = true
	wanted_box.modulate = Color.WHITE
	for st in wanted_stars:
		var tw := create_tween()
		(st as Control).scale = Vector2.ONE * 1.6
		tw.tween_property(st, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	wanted_why.text = why
	wanted_why.visible = true
	wanted_why.modulate.a = 1.0
	_why_t = 3.5

## A star more: it pops.
func wanted_up(h: int) -> void:
	if h >= 1 and h <= 5:
		var st: Control = wanted_stars[h - 1]
		st.scale = Vector2.ONE * 1.8
		create_tween().tween_property(st, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Lost them: the stars fade away, and a quiet note of the bounty.
func wanted_lost(bounty: int, _heat: int) -> void:
	_wanted_fade = 1.2
	toast("Lost the police  ·  +%d" % bounty, "coin", Color(0.12, 0.13, 0.16, 0.85), Color.WHITE, 2.4)

## A big knock: the screen flashes pale for an instant (k: 0..1, how hard), whatever the time scale.
var _flash: ColorRect
func impact_flash(k: float) -> void:
	if _flash == null:
		_flash = ColorRect.new()
		_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(_flash)
		hud.move_child(_flash, 0)            # (under the gauges and buttons)
	_flash.color = Color(1.0, 0.96, 0.9, clampf(k, 0.0, 1.0) * 0.4)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(_flash, "color:a", 0.0, 0.25)

## Busted: the picture drains of colour, BUSTED across it, the fine under it; then it all fades back.
func busted_fx(fine: int) -> void:
	var lay := Control.new()
	lay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(lay)
	var grey := ColorRect.new()
	grey.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/busted.gdshader")
	sm.set_shader_parameter("k", 0.0)
	grey.material = sm
	lay.add_child(grey)
	var big := K.outlined(K.label("BUSTED", 104, Color("eef0f3"), 800), Color(0.05, 0.06, 0.1), 16)
	big.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	big.position = Vector2(-400, -110)
	big.size = Vector2(800, 140)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.pivot_offset = big.size * 0.5
	lay.add_child(big)
	var sub := K.outlined(K.label(("Fined %d coins" % fine) if fine > 0 else "Let off with a warning", 26, Color.WHITE, 700), Color(0.05, 0.06, 0.1), 8)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sub.position = Vector2(-300, 34)
	sub.size = Vector2(600, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lay.add_child(sub)
	lay.modulate.a = 0.0
	big.scale = Vector2.ONE * 1.15
	var tw := create_tween().set_ignore_time_scale(true)
	tw.set_parallel(true)
	tw.tween_property(lay, "modulate:a", 1.0, 0.45)
	tw.tween_method(func(v: float): sm.set_shader_parameter("k", v), 0.0, 1.0, 0.6)
	tw.tween_property(big, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(2.0)
	tw.tween_property(lay, "modulate:a", 0.0, 0.8)
	tw.tween_callback(lay.queue_free)
	wanted_box.visible = false
	_wanted_fade = 0.0

func _wanted_update(pd: Dictionary, kmh: float) -> void:
	var heat := int(pd.get("heat", 0))
	var now := Time.get_ticks_msec() * 0.001
	var dt := get_process_delta_time()
	if heat > 0:
		_wanted_shown = heat
		wanted_box.visible = true
		wanted_box.modulate.a = 1.0
		var flash := not bool(pd["seen"]) and fmod(now, 0.6) < 0.3
		var b := float(pd["bust"])
		for i in 5:
			var st: Control = wanted_stars[i]
			if i < heat:
				var lit := Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.25, 0.25), clampf(b * 1.3, 0.0, 1.0))
				st.modulate = Color(0.55, 0.55, 0.58, 0.6) if flash else lit
			else:
				st.modulate = Color(0.1, 0.1, 0.12, 0.35)
		# the minimap's rim: red and blue while they've got you; grey and white while they're looking
		var phase := fmod(now, 0.5) < 0.25
		if bool(pd["seen"]):
			_ring_col(Color("ff3044") if phase else Color("3a6bff"))
		else:
			_ring_col(Color("c9ccd4") if fmod(now, 0.9) < 0.45 else K.PAPER)
	elif _wanted_fade > 0.0:
		_wanted_fade -= dt
		wanted_box.modulate.a = clampf(_wanted_fade / 1.2, 0.0, 1.0)
		if _wanted_fade <= 0.0:
			wanted_box.visible = false
		_ring_col(K.PAPER)
	else:
		wanted_box.visible = false
		_ring_col(K.PAPER)
	if _why_t > 0.0:
		_why_t -= dt
		wanted_why.modulate.a = clampf(_why_t / 0.6, 0.0, 1.0)
		if _why_t <= 0.0 or heat == 0:
			wanted_why.visible = false
			_why_t = 0.0
	var lim := int(pd.get("limit", 0))
	limit_sign.visible = heat == 0 and bool(pd.get("patrol", false)) and lim > 0
	if limit_sign.visible:
		limit_lbl.text = str(lim)
		var over := kmh > lim + 10.0
		limit_sign.scale = Vector2.ONE * ((1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.02)) if over else 1.0)
		limit_lbl.add_theme_color_override("font_color", Color("e0303e") if over else K.INK)

func _ring_col(col: Color) -> void:
	if mini_ring:
		var sb: StyleBoxFlat = mini_ring.get_theme_stylebox("panel")
		if sb.border_color != col:
			sb.border_color = col

## Rewinding: the picture goes blue and a REWIND banner pulses at the top.
var _rw_fx: Control
func rewind_fx(on: bool) -> void:
	if _rw_fx == null:
		_rw_fx = Control.new()
		_rw_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_rw_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tint := ColorRect.new()
		tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tint.color = Color(0.25, 0.45, 0.95, 0.2)
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rw_fx.add_child(tint)
		var lb := K.outlined(K.label("◀◀  REWIND", 44, Color.WHITE, 800), K.INK, 10)
		lb.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		lb.position = Vector2(-160, 120)
		lb.size = Vector2(320, 60)
		lb.name = "Label"
		_rw_fx.add_child(lb)
		hud.add_child(_rw_fx)
		hud.move_child(_rw_fx, 1)
	_rw_fx.visible = on

## While rewinding, only what moves with the picture (the minimap) keeps up.
func hud_update_light() -> void:
	if _rw_fx and _rw_fx.visible:
		(_rw_fx.get_node("Label") as Control).modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
	_minimap_tick(game.car.get_global_transform_interpolated().origin, game.car.global_rotation.y)

## The steering wheel: the top half of a wheel at the bottom left. Put a thumb on it and turn it.
func _build_wheel() -> void:
	wheel = Control.new()
	wheel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	wheel.position = Vector2(26, -262)
	wheel.size = Vector2(400, 262)
	wheel.custom_minimum_size = wheel.size
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel.set_meta("a", 0.0)
	wheel.set_meta("on", false)
	wheel.draw.connect(func():
		var a: float = wheel.get_meta("a")
		var on: bool = wheel.get_meta("on")
		var c := _wheel_hub()
		var r := 176.0
		var rim := Color(K.PAPER, 0.8 if on else 0.62)
		var edge := Color(K.INK, 0.55)
		# the rim (the top half, turned)
		wheel.draw_arc(c, r, PI + a - 0.15, TAU + a + 0.15, 48, edge, 40.0, true)
		wheel.draw_arc(c, r, PI + a - 0.13, TAU + a + 0.13, 48, rim, 34.0, true)
		# spokes and the hub
		for sp_a in [a - 0.38, a + PI + 0.38]:      # (two spokes, angled up a little so they show)
			var dirv := Vector2.from_angle(sp_a)
			wheel.draw_line(c + dirv * 40.0, c + dirv * (r - 14.0), edge, 22.0, true)
			wheel.draw_line(c + dirv * 40.0, c + dirv * (r - 14.0), rim, 16.0, true)
		wheel.draw_circle(c, 52.0, edge)
		wheel.draw_circle(c, 46.0, rim)
		# the mark at the top, so you can see how far it's turned
		var top := c + Vector2.from_angle(-PI * 0.5 + a) * r
		wheel.draw_circle(top, 13.0, Color("ff5c7a")))
	hud.add_child(wheel)

func _wheel_hub() -> Vector2:
	return Vector2(wheel.size.x * 0.5, wheel.size.y + 4.0)

## The angle (radians, 0 straight up, + clockwise) of a point round the middle of the wheel.
func wheel_angle_at(pos: Vector2) -> float:
	var c := wheel.get_global_rect().position + _wheel_hub()
	var d := pos - c
	return atan2(d.x, -d.y)

func wheel_mode() -> bool:
	return bool(game.save.setting("wheel"))

## Which control (if any) a touch at pos lands on. Pads have generous edges.
func control_at(pos: Vector2) -> String:
	if not hud.visible or overlay.visible:
		return ""
	if wheel_mode() and wheel.get_global_rect().grow(16).has_point(pos):
		var hub := wheel.get_global_rect().position + _wheel_hub()
		if pos.distance_to(hub) < 250.0:
			return "wheel"
	for k in ["rewind", "nos", "hand", "gas", "brake", "left", "right"]:
		var c: Control = ctl[k]
		if not c.visible:
			continue
		if c.get_global_rect().grow(14 if k == "nos" else 22).has_point(pos):
			return k
	return ""

func pressed_controls(held: Dictionary) -> void:
	for k in ctl:
		var c: Control = ctl[k]
		var on: bool = held.get(k, false)
		c.scale = c.scale.lerp(Vector2.ONE * (0.93 if on else 1.0), 0.5)
		c.modulate = Color(1.15, 1.15, 1.15, 1.0) if on else Color(1, 1, 1, 0.9)

func _gauge(icon: String, at: Vector2) -> Control:
	var g := Control.new()
	g.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	g.position = at
	g.size = Vector2(34, 120)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.set_meta("v", 1.0)
	g.draw.connect(func():
		var v: float = g.get_meta("v")
		var bar := Rect2(Vector2(11, 0), Vector2(12, 84))
		g.draw_rect(bar.grow(3), Color(0.08, 0.08, 0.09, 0.42))
		var col := K.PAPER if v > 0.35 else (Color("f2b84b") if v > 0.15 else Color("ef6a55"))
		var h := bar.size.y * clampf(v, 0.0, 1.0)
		g.draw_rect(Rect2(bar.position + Vector2(0, bar.size.y - h), Vector2(bar.size.x, h)), col)
		for k in range(1, 4):
			var y := bar.position.y + bar.size.y * k / 4.0
			g.draw_line(Vector2(bar.position.x, y), Vector2(bar.end.x, y), Color(0, 0, 0, 0.25), 1.0))
	var ic := Icon.new(icon, K.PAPER, 30)
	ic.position = Vector2(2, 88)
	g.add_child(ic)
	hud.add_child(g)
	return g

## Show (or hide) the GPS arrow: angle from straight ahead (radians, + to the right), metres to go.
func route_arrow(on: bool, angle := 0.0, dist := 0.0, name := "") -> void:
	_route_on = on
	route_box.visible = on
	if not on:
		return
	_route_ang = lerp_angle(_route_ang, angle, 0.25)
	route_box.queue_redraw()
	var dtxt := ("%d m" % int(round(dist / 10.0) * 10.0)) if dist < 1000.0 else ("%.1f km" % (dist / 1000.0))
	route_lbl.text = "%s · %s" % [dtxt, name]
	route_box.position.y = 112.0 if chal_card.visible else ((start_card.size.y + 26.0) if start_card != null and start_card.visible else 10.0)

func station_open(name: String) -> void:
	station_lbl.text = "%s gas station" % name
	station_card.visible = true
	station_card.modulate.a = 0.0
	create_tween().tween_property(station_card, "modulate:a", 1.0, 0.2)

func station_close() -> void:
	station_card.visible = false

func station_update(fuel: float, damage: float, fuel_cost: int, repair_cost: int, coins: int) -> void:
	st_fuel_lbl.text = "Fuel %d%%" % int(round(fuel))
	st_cond_lbl.text = "Condition %d%%" % int(round(100.0 - damage))
	var full := fuel > 99.5
	st_fuel_btn.text = "Full" if full else ("Fill up · %s coins" % K.fmt(fuel_cost))
	st_fuel_btn.disabled = full
	var fixed := damage < 0.5
	st_cond_btn.text = "Like new" if fixed else ("Repair · %s coins" % K.fmt(repair_cost))
	st_cond_btn.disabled = fixed
	st_fuel_btn.modulate.a = 0.55 if full else 1.0
	st_cond_btn.modulate.a = 0.55 if fixed else 1.0

func _build_route_and_station() -> void:
	# the GPS arrow
	route_box = Control.new()
	route_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	route_box.size = Vector2(300, 84)
	route_box.position = Vector2(-150, 10)
	route_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	route_box.visible = false
	route_box.draw.connect(func():
		var c := Vector2(150, 28)
		var f := Vector2(sin(_route_ang), -cos(_route_ang))
		var r := Vector2(-f.y, f.x)
		var pts := PackedVector2Array([c + f * 22.0, c - f * 14.0 + r * 18.0, c - f * 6.0, c - f * 14.0 - r * 18.0])
		route_box.draw_colored_polygon(pts, Color("4aa8ff"))
		route_box.draw_polyline(pts + PackedVector2Array([pts[0]]), K.INK, 4.0, true)
		route_box.draw_polyline(pts + PackedVector2Array([pts[0]]), Color.WHITE, 1.6, true))
	hud.add_child(route_box)
	route_lbl = K.outlined(K.label("", 18, Color.WHITE, 700), K.INK, 6)
	route_lbl.position = Vector2(0, 56)
	route_lbl.size = Vector2(300, 26)
	route_box.add_child(route_lbl)
	# the station card: what you can buy here
	station_card = K.card(K.PAPER, 22)
	var ssb: StyleBoxFlat = (station_card.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	ssb.content_margin_top = 10
	ssb.content_margin_bottom = 12
	ssb.content_margin_left = 18
	ssb.content_margin_right = 18
	station_card.add_theme_stylebox_override("panel", ssb)
	station_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	station_card.position = Vector2(-230, -250)
	station_card.custom_minimum_size = Vector2(460, 0)
	station_card.visible = false
	hud.add_child(station_card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	station_card.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(Icon.new("fuel", K.INK, 30))
	station_lbl = K.label("", 24, K.INK, 700, HORIZONTAL_ALIGNMENT_LEFT)
	head.add_child(station_lbl)
	vb.add_child(head)
	for row in 2:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		var l := K.label("", 20, K.INK_SOFT, 650, HORIZONTAL_ALIGNMENT_LEFT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
		var b := K.button("", K.TEAL if row == 0 else K.SUN, K.TEAL_DK if row == 0 else K.SUN_DK, 20, 210, 52)
		hb.add_child(b)
		vb.add_child(hb)
		if row == 0:
			st_fuel_lbl = l
			st_fuel_btn = b
			_tap(b, func(): game.buy_fuel())
		else:
			st_cond_lbl = l
			st_cond_btn = b
			_tap(b, func(): game.buy_repair())

func show_hud() -> void:
	title.visible = false
	garage.visible = false
	hud.visible = true

func hud_update(d: Dictionary) -> void:
	_hud_data = d
	speed_lbl.text = str(int(round(d["kmh"])))
	var wm := wheel_mode()
	wheel.visible = wm
	ctl["left"].visible = not wm
	ctl["right"].visible = not wm
	if wm:
		wheel.set_meta("a", float(d.get("wheel", 0.0)) * game.WHEEL_MAX)     # (turned with the finger)
		wheel.set_meta("on", game.wheel_idx >= 0)
		wheel.queue_redraw()
	_wanted_update(d.get("police", {}), float(d["kmh"]))
	var nf: Control = ctl["nos"].get_meta("fill")
	nf.set_meta("v", float(d.get("nos", 1.0)))
	nf.queue_redraw()
	# a sense of speed: the edges of the screen blur a little (never your car or the way ahead) and streaks
	# rush past, from about 120 km/h, building to 240
	var want := clampf((float(d["kmh"]) - 120.0) / 120.0 + float(d.get("nos_on", 0.0)) * 0.25, 0.0, 1.0) if bool(game.save.setting("speedfx")) else 0.0
	if game.args.has("speedfx"):
		want = float(game.args["speedfx"])      # test: show them at this strength
	speed_k = move_toward(speed_k, want, get_process_delta_time() * 1.5)
	speed_fx.visible = speed_k > 0.01
	if speed_fx.visible:
		var vs := get_viewport().get_visible_rect().size
		var sm2 := speed_fx.material as ShaderMaterial
		sm2.set_shader_parameter("amount", speed_k)
		sm2.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
		# where the car is on screen (kept sharp) and where the road runs off to (everything rushes out from there)
		var cam3: Camera3D = game.cam
		var cpos: Vector3 = d["car_pos"]
		if not cam3.is_position_behind(cpos):
			var cs := cam3.unproject_position(cpos + Vector3(0, 0.6, 0)) / vs
			sm2.set_shader_parameter("car_uv", cs)
			var dist := maxf(cam3.global_position.distance_to(cpos), 2.0)
			sm2.set_shader_parameter("car_size", Vector2(1.35 / dist * 1.2, 1.1 / dist * 1.5 * vs.x / vs.y * 0.5))
		var ahead: Vector3 = cpos - cam3.global_transform.basis.z * 60.0
		if not cam3.is_position_behind(ahead):
			sm2.set_shader_parameter("center", cam3.unproject_position(ahead) / vs)
	gear_lbl.text = "R" if game.car.speed < -0.5 and game.car.grounded > 0 else str(int(d["gear"]))
	rpm_bar.value = d["rpm"]
	clock_lbl.text = d["clock"] if bool(game.save.setting("clock")) else ""
	if bool(game.save.setting("fps")):
		# (for tracking down stutters: frames a second, and the slowest frame in the last second)
		_fps_worst = maxf(_fps_worst, get_process_delta_time())
		_fps_t += get_process_delta_time()
		if _fps_t > 1.0:
			_fps_txt = "%d fps · worst %d ms" % [Engine.get_frames_per_second(), int(_fps_worst * 1000.0)]
			_fps_t = 0.0
			_fps_worst = 0.0
		clock_lbl.text += ("   " if clock_lbl.text != "" else "") + _fps_txt
	var fv := float(d.get("fuel", 100.0)) / 100.0
	var cv := 1.0 - maxf(float(d.get("damage", 0.0)), float(d.get("engine", 0.0))) / 100.0
	if absf(float(fuel_g.get_meta("v")) - fv) > 0.002:
		fuel_g.set_meta("v", fv)
		fuel_g.queue_redraw()
	if absf(float(cond_g.get_meta("v")) - cv) > 0.002:
		cond_g.set_meta("v", cv)
		cond_g.queue_redraw()
	place_lbl.text = d["place"]
	if int(d["coins"]) != _last_coins:
		_last_coins = int(d["coins"])
		coins_pill.get_meta("label").text = K.fmt(_last_coins)
	# drift meter
	var pts: float = d["drift"]
	var combo: int = d["combo"]
	if d["drifting"]:
		_drift_show = 1.0
		drift_lbl.text = K.fmt(int(pts * combo))
		combo_lbl.text = "x%d" % combo
		var ang := int(d["angle"])
		var sweet: bool = ang >= CarScript.SWEET[0] and ang <= CarScript.SWEET[1]
		angle_lbl.text = "%d°%s%s" % [ang, "  ·  SWEET SPOT ×1.4" if sweet else "", "  ·  close ×1.5" if d.get("close", false) else ""]
		angle_lbl.add_theme_color_override("font_color", Color("7dffae") if sweet else Color(1, 1, 1, 0.85))
		sweet_meter.set_meta("a", float(ang))
		sweet_meter.queue_redraw()
		combo_bar.value = 1.0
	elif _bank_t <= 0.0:
		combo_bar.value = clampf(float(d["combo_t"]) / 2.2, 0.0, 1.0)
		combo_lbl.text = "x%d" % combo
		if float(d["combo_t"]) <= 0.0:
			_drift_show = maxf(0.0, _drift_show - get_process_delta_time() * 2.0)
	drift_card.modulate.a = lerpf(drift_card.modulate.a, _drift_show, 0.25)
	# the challenge in progress
	var z: Dictionary = d["zone"]
	var t: Dictionary = d["trial"]
	var rc: Dictionary = d.get("race", {})
	chal_card.visible = not z.is_empty() or not t.is_empty() or not rc.is_empty()
	if not rc.is_empty():
		chal_name.text = "%s · Lap %d/%d" % [rc["name"], int(rc["lap"]), int(rc["laps"])]
		var pl := int(rc["place"])
		chal_main.text = "Get ready" if rc["counting"] else ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th"][clampi(pl - 1, 0, 7)]
		var rt := float(rc["t"])
		chal_sub.text = "of %d · %d:%04.1f" % [int(rc["of"]), int(rt) / 60, fmod(rt, 60.0)]
	elif not z.is_empty():
		chal_name.text = z["name"]
		chal_main.text = K.fmt(int(d["zone_pts"]))
		var m: Array = z["medals"]
		var next := "Gold!"
		for i in 3:
			if float(d["zone_pts"]) < float(m[i]):
				next = "%s at %s" % [["Bronze", "Silver", "Gold"][i], K.fmt(int(m[i]))]
				break
		chal_sub.text = "%d s left · %s" % [int(ceil(float(d["zone_t"]))), next]
	elif not t.is_empty():
		chal_name.text = t["name"]
		if t["kind"] == "time":
			chal_main.text = "%.1f s" % float(d["trial_t"])
			chal_sub.text = "Gate %d of %d · gold %.0f s" % [int(d["trial_gate"]), (t["gates"] as Array).size() - 1, float(t["medals"][0])]
		else:
			chal_main.text = K.fmt(int(d["trial_pts"]))
			chal_sub.text = "Gate %d of %d · gold %s" % [int(d["trial_gate"]), (t["gates"] as Array).size() - 1, K.fmt(int(t["medals"][2]))]
	_minimap_tick(d["car_pos"], d["car_yaw"])

func combo_bump(c: int) -> void:
	combo_lbl.pivot_offset = combo_lbl.size * 0.5
	combo_lbl.scale = Vector2(1.5, 1.5)
	create_tween().tween_property(combo_lbl, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func banked(total: int, coins: int) -> void:
	_bank_t = 1.1
	_drift_show = 1.0
	drift_lbl.text = "+" + K.fmt(total)
	angle_lbl.text = ("+%d coins" % coins) if coins > 0 else "nice!"
	drift_card.pivot_offset = Vector2(0, drift_card.size.y * 0.5)
	drift_card.scale = Vector2(1.08, 1.08)
	create_tween().tween_property(drift_card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func drift_lost() -> void:
	_bank_t = 0.9
	drift_lbl.text = "Crashed!"
	angle_lbl.text = "drift lost"
	_drift_show = 1.0

## A short call-out ("Close!", a stunt's name), small, beside the drift meter; a few stack up.
func popup_text(text: String, col := Color.WHITE) -> void:
	var l := K.outlined(K.label(text, 24, col, 700, HORIZONTAL_ALIGNMENT_LEFT), K.INK, 7)
	popups.add_child(l)
	var slot := _pop_n % 3
	_pop_n += 1
	l.position = Vector2(30, 186 + slot * 30)
	l.pivot_offset = Vector2(0, 14)
	l.scale = Vector2(0.6, 0.6)
	var t := create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "position:x", l.position.x + 10, 1.1)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.9)
	t.tween_callback(l.queue_free)

func toast(text: String, icon := "", col := K.PAPER, icol := K.INK, hold := 2.2) -> void:
	var p := PanelContainer.new()
	var sb := K.box(col, 36, 6, col.darkened(0.12), 20)
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(hb)
	if icon != "":
		hb.add_child(Icon.new(icon, icol, 34))
	hb.add_child(K.label(text, 26, icol, 650))
	toasts.add_child(p)
	p.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(p, "modulate:a", 1.0, 0.25)
	t.tween_interval(hold)
	t.tween_property(p, "modulate:a", 0.0, 0.4)
	t.tween_callback(p.queue_free)

func discovered(name: String) -> void:
	var n: int = game.save.data["places"].size()
	toast("Found %s  (%d/%d)" % [name, n, island.places.size()], "map", K.TEAL, Color.WHITE, 2.6)

func found_coin(n: int, total: int, pay: int) -> void:
	toast("Hidden coin %d/%d  +%d" % [n, total, pay], "coin", K.SUN, K.INK, 1.8)

func show_reset_hint() -> void:
	if not reset_hint.visible:
		reset_hint.visible = true
		_hint_t = 6.0

func challenge_start(name: String, desc: String, medals: Array, timed: bool) -> void:
	var m := ""
	if timed:
		m = "Gold %.0f s · Silver %.0f s · Bronze %.0f s" % [medals[0], medals[1], medals[2]]
	else:
		m = "Bronze %s · Silver %s · Gold %s" % [K.fmt(int(medals[0])), K.fmt(int(medals[1])), K.fmt(int(medals[2]))]
	toast(name + "!  " + desc, "flag", K.CORAL, Color.WHITE, 2.4)
	toast(m, "trophy", K.PAPER, K.INK, 2.4)

## A street race begins: what it is, and how the medals go.
func race_start(name: String, laps: int, cars: int) -> void:
	toast("%s!  %d laps, %d cars. Follow the line on the road" % [name, laps, cars], "flag", K.CORAL, Color.WHITE, 3.0)
	toast("Gold for 1st · Silver for 2nd · Bronze for 3rd", "trophy", K.PAPER, K.INK, 3.0)

## The countdown (3, 2, 1, GO!), big in the middle of the screen, each with a ring of colour bursting out.
func big_count(text: String) -> void:
	if count_lbl == null:
		count_ring = Control.new()
		count_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		count_ring.set_meta("k", 1.0)
		count_ring.set_meta("col", Color.WHITE)
		count_ring.draw.connect(func():
			var k: float = count_ring.get_meta("k")
			var cc: Color = count_ring.get_meta("col")
			var ctr := _vs() * Vector2(0.5, 0.5) - Vector2(0, 90)
			count_ring.draw_arc(ctr, 70.0 + k * 170.0, 0.0, TAU, 64, Color(cc, 0.8 * (1.0 - k)), 14.0 * (1.0 - k) + 2.0, true)
			count_ring.draw_circle(ctr, 64.0 + k * 20.0, Color(cc, 0.22 * (1.0 - k))))
		hud.add_child(count_ring)
		count_lbl = K.label("", 140, Color.WHITE, 800)
		count_lbl.add_theme_color_override("font_outline_color", K.INK)
		count_lbl.add_theme_constant_override("outline_size", 22)
		count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(count_lbl)
	var col: Color = {"3": Color("ff5a4e"), "2": Color("ffb84a"), "1": Color("ffe066"), "GO!": Color("54e08a")}.get(text, Color.WHITE)
	count_lbl.text = text
	count_lbl.add_theme_color_override("font_color", col)
	count_lbl.reset_size()
	count_lbl.position = (_vs() - count_lbl.size) * 0.5 - Vector2(0, 90)
	count_lbl.pivot_offset = count_lbl.size * 0.5
	count_lbl.visible = true
	count_lbl.modulate.a = 1.0
	count_lbl.scale = Vector2(1.8, 1.8)
	count_ring.set_meta("col", col)
	count_ring.visible = true
	var tw := create_tween()
	tw.tween_property(count_lbl, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.4 if text != "GO!" else 0.6)
	tw.tween_property(count_lbl, "modulate:a", 0.0, 0.25)
	var tr := create_tween()
	tr.tween_method(func(k: float):
		count_ring.set_meta("k", k)
		count_ring.queue_redraw(), 0.0, 1.0, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	game.buzz(40 if text != "GO!" else 90, 0.5)

## The start card: what the challenge is, your best, and START. A race's card also has the difficulty to
## pick (Easy, Medium, Hard): picking one redraws the card where it is, with that difficulty's best and medal.
func start_card_show(info: Dictionary, animate := true) -> void:
	if not animate and start_card != null:
		start_card.queue_free()
		start_card = null
	start_card_hide()
	_start_cb = info["start"]
	var col: Color = info["col"]
	start_card = PanelContainer.new()
	var sb := K.box(K.PAPER, 26, 8, K.LINE_DK, 0)
	sb.shadow_color = Color(0.1, 0.1, 0.1, 0.25)
	sb.shadow_size = 14
	start_card.add_theme_stylebox_override("panel", sb)
	start_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hud.add_child(start_card)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	start_card.add_child(hb)
	# a slab of the challenge's colour down the left
	var slab := PanelContainer.new()
	var ss := K.box(col, 26, 0, Color.TRANSPARENT, 0)
	ss.corner_radius_top_right = 0
	ss.corner_radius_bottom_right = 0
	slab.add_theme_stylebox_override("panel", ss)
	slab.custom_minimum_size = Vector2(18, 0)
	hb.add_child(slab)
	var mid := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mid.add_theme_constant_override("margin_" + side, {"left": 18, "right": 14, "top": 12, "bottom": 14}[side])
	hb.add_child(mid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	mid.add_child(row)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	row.add_child(vb)
	var kl := K.label(" ".join(Array(String(info["kind_label"]).split(""))), 15, col.darkened(0.25), 800, HORIZONTAL_ALIGNMENT_LEFT)
	vb.add_child(kl)
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 8)
	nr.add_child(K.label(info["name"], 32, K.INK, 750, HORIZONTAL_ALIGNMENT_LEFT))
	if int(info["medal"]) > 0:
		nr.add_child(Icon.new("trophy", [K.LINE, Color("b98b62"), Color("b3b8bd"), Color("d4b25c")][int(info["medal"])], 28))
	vb.add_child(nr)
	vb.add_child(K.label(info["info"], 17, K.INK_SOFT, 600, HORIZONTAL_ALIGNMENT_LEFT))
	if String(info.get("warn", "")) != "":
		vb.add_child(K.label(info["warn"], 17, Color("d0503a"), 700, HORIZONTAL_ALIGNMENT_LEFT))
	if info.has("diff"):
		var dr := HBoxContainer.new()
		dr.add_theme_constant_override("separation", 8)
		var dsp := Control.new()
		dsp.custom_minimum_size = Vector2(0, 8)
		vb.add_child(dsp)
		vb.add_child(dr)
		for k in 3:
			var on: bool = int(info["diff"]) == k
			var dcol: Color = [Color("6cc28a"), Color("f2b84b"), Color("ef6a55")][k]
			var chip := K.button(["Easy", "Medium", "Hard"][k], dcol if on else K.CREAM, dcol.darkened(0.3) if on else K.LINE_DK, 19, 104, 46)
			if not on:
				chip.add_theme_color_override("font_color", K.INK_SOFT)
			var kk := k
			var setter: Callable = info["set_diff"]
			_tap(chip, func():
				if kk != int(info["diff"]):
					game.sfx("select", -8.0, 1.1 + kk * 0.1)
					setter.call(kk))
			dr.add_child(chip)
	var go := K.button("START", col.darkened(0.08), col.darkened(0.35), 30, 150, 70)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tap(go, func():
		var cb := _start_cb
		start_card_hide()
		cb.call())
	row.add_child(go)
	if not animate:
		await get_tree().process_frame
		if start_card != null:
			start_card.position = Vector2((_vs().x - start_card.size.x) * 0.5, 14.0)
		return
	start_card.modulate.a = 0.0
	await get_tree().process_frame
	if start_card == null:
		return
	start_card.position = Vector2((_vs().x - start_card.size.x) * 0.5, -start_card.size.y)
	var tw := create_tween()
	tw.tween_property(start_card, "position:y", 14.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(start_card, "modulate:a", 1.0, 0.2)
	game.sfx("select", -10.0, 1.3)

func start_card_hide() -> void:
	if start_card != null:
		var c := start_card
		start_card = null
		var tw := create_tween()
		tw.tween_property(c, "modulate:a", 0.0, 0.15)
		tw.tween_callback(c.queue_free)

## A challenge's title: a slanted band slides across with what it is, its name and what to do.
func intro_banner(kind_label: String, name: String, sub: String, col: Color) -> void:
	var vs := _vs()
	var band := Control.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.size = Vector2(vs.x + 240.0, 200.0)
	band.position = Vector2(-vs.x - 240.0, vs.y * 0.2)
	band.draw.connect(func():
		var w := band.size.x
		var h := band.size.y
		band.draw_colored_polygon(PackedVector2Array([Vector2(60, 0), Vector2(w, 0), Vector2(w - 60, h), Vector2(0, h)]), Color(K.INK, 0.9))
		band.draw_colored_polygon(PackedVector2Array([Vector2(60, 0), Vector2(w, 0), Vector2(w - 4, 14), Vector2(56, 14)]), col)
		band.draw_colored_polygon(PackedVector2Array([Vector2(4, h - 14), Vector2(w - 56, h - 14), Vector2(w - 60, h), Vector2(0, h)]), col)
		for k in 5:
			var x0 := 120.0 + k * 34.0
			band.draw_colored_polygon(PackedVector2Array([Vector2(x0 + 30, 30), Vector2(x0 + 48, 30), Vector2(x0 + 18, h - 30), Vector2(x0, h - 30)]), Color(col, 0.18 + k * 0.05)))
	hud.add_child(band)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -4)
	vb.position = Vector2(340, 26)
	band.add_child(vb)
	vb.add_child(K.label(" ".join(Array(kind_label.split(""))), 22, col, 800, HORIZONTAL_ALIGNMENT_LEFT))
	var nl := K.label(name.to_upper(), 66, Color.WHITE, 800, HORIZONTAL_ALIGNMENT_LEFT)
	vb.add_child(nl)
	vb.add_child(K.label(sub, 20, Color(1, 1, 1, 0.8), 600, HORIZONTAL_ALIGNMENT_LEFT))
	var tw := create_tween()
	tw.tween_property(band, "position:x", -120.0, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.25)
	tw.tween_property(band, "position:x", vs.x + 60.0, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_callback(band.queue_free)
	var tv := create_tween()          # (the words drift a little against the band: a touch of motion)
	tv.tween_property(vb, "position:x", 300.0, 2.1).from(400.0)
	game.sfx("blowoff", -8.0)

## A burst of confetti from the top of the screen (in the medal's colour and a few others).
func _confetti(col: Color, n: int) -> void:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popups.add_child(layer)
	var vs := _vs()
	var bits := []
	var pal := [col, col.lightened(0.3), Color("ff5c7a"), Color("5cc8ff"), Color("ffe066"), Color("54e08a")]
	for i in n:
		bits.append({"p": Vector2(randf_range(0.15, 0.85) * vs.x, randf_range(-60.0, 0.0)),
			"v": Vector2(randf_range(-160.0, 160.0), randf_range(-420.0, -120.0)), "a": randf() * TAU,
			"w": randf_range(-9.0, 9.0), "c": pal[i % pal.size()], "s": randf_range(7.0, 13.0)})
	layer.draw.connect(func():
		for b in bits:
			var xf := Transform2D(float(b["a"]), b["p"])
			layer.draw_set_transform_matrix(xf)
			layer.draw_rect(Rect2(-float(b["s"]) * 0.5, -float(b["s"]) * 0.3, float(b["s"]), float(b["s"]) * 0.6), b["c"]))
	var last := [0.0]
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var st := clampf(t - float(last[0]), 0.0, 0.05)
		last[0] = t
		for b in bits:
			b["v"] = (b["v"] as Vector2) + Vector2(0, 900.0) * st
			b["v"] = (b["v"] as Vector2) * pow(0.4, st)
			b["p"] = (b["p"] as Vector2) + (b["v"] as Vector2) * st
			b["a"] = float(b["a"]) + float(b["w"]) * st
		layer.modulate.a = clampf((2.6 - t) / 0.6, 0.0, 1.0)
		layer.queue_redraw(), 0.0, 2.6, 2.6)
	tw.tween_callback(layer.queue_free)

func challenge_end() -> void:
	chal_card.visible = false

func challenge_result(name: String, score: String, medal: int, pay: int, record: bool, again := Callable()) -> void:
	var cols := [Color("c9c3bb"), Color("b98b62"), Color("b3b8bd"), Color("d4b25c")]
	var names := ["No medal", "Bronze", "Silver", "Gold"]
	var p := K.card(K.PAPER, 36)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	var head := PanelContainer.new()
	var hs := K.box(cols[medal], 16, 0, Color.TRANSPARENT, 0)
	head.add_theme_stylebox_override("panel", hs)
	head.custom_minimum_size = Vector2(0, 10)
	vb.add_child(head)
	vb.add_child(K.label(name, 30, K.INK_SOFT, 650))
	vb.add_child(K.label(score, 56, K.INK, 700))
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", K.box(cols[medal], 30, 0, Color.TRANSPARENT, 12))
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 8)
	badge.add_child(bh)
	bh.add_child(Icon.new("trophy" if medal > 0 else "flag", Color.WHITE, 34))
	bh.add_child(K.label(names[medal], 30, Color.WHITE, 700))
	vb.add_child(badge)
	# the medal stamps down a beat after the card
	badge.pivot_offset = Vector2(90, 30)
	badge.scale = Vector2(2.4, 2.4)
	badge.modulate.a = 0.0
	var tb := create_tween()
	tb.tween_interval(0.35)
	tb.tween_property(badge, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tb.parallel().tween_property(badge, "modulate:a", 1.0, 0.12)
	if medal > 0:
		tb.tween_callback(func(): _confetti(cols[medal], 24 + medal * 18))
	if pay > 0:
		vb.add_child(K.label("+%d coins" % pay, 30, K.INK, 700))
	if record:
		vb.add_child(K.label("New personal best!", 26, K.INK_SOFT, 700))
	# a quick way to have another go (the card stays up a little longer for it)
	var stay := 3.2
	if again.is_valid():
		stay = 5.5
		var ab := K.button("Try again", K.CORAL, K.CORAL_DK, 26, 240, 60, "play")
		ab.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ab.mouse_filter = Control.MOUSE_FILTER_STOP
		_tap(ab, func():
			p.queue_free()
			again.call())
		vb.add_child(ab)
		if game.args.has("againtest"):
			# a test: Try again pressed a moment after the card comes up
			get_tree().create_timer(1.2).timeout.connect(func():
				print("AGAIN pressed")
				if is_instance_valid(ab):
					ab.pressed.emit())
	popups.add_child(p)
	await get_tree().process_frame
	p.position = (_vs() - p.size) * 0.5 - Vector2(0, 60)
	p.pivot_offset = p.size * 0.5
	p.scale = Vector2(0.6, 0.6)
	var t := create_tween()
	t.tween_property(p, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(stay)
	t.tween_property(p, "modulate:a", 0.0, 0.4)
	t.tween_callback(p.queue_free)
	game.sfx("finish", -3.0)
	if record:
		game.sfx("record", -2.0)
	elif medal > 0:
		game.sfx("medal", -2.0)
	if medal > 0:
		game.buzz(80, 0.8)

## The phone up (sliding in from below), or away.
func toggle_phone() -> void:
	if phone.visible:
		var t := create_tween()
		t.tween_property(phone, "modulate:a", 0.0, 0.12)
		t.tween_callback(func(): phone.visible = false)
		return
	phone.visible = true
	phone.open()
	phone.modulate.a = 0.0
	var y := phone.position.y
	phone.position.y = y + 40.0
	var t2 := create_tween().set_parallel()
	t2.tween_property(phone, "modulate:a", 1.0, 0.16)
	t2.tween_property(phone, "position:y", y, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func tick(dt: float) -> void:
	if phone and phone.visible and hud.visible:
		phone.tick(dt)
	if title.visible:
		_title_tick(Time.get_ticks_msec() / 1000.0)
	if garage.visible:
		g_spin += dt * 0.35
		g_turn.rotation.y = g_spin
		# the underglow's light turns with the car
		if g_neon and is_instance_valid(g_neon):
			var zc: float = g_neon.get_meta("zc")
			CarScript.neon_light(g_neon, g_turn.global_transform * Vector3(0, g_neon_y + 0.02, zc), g_turn.global_transform.basis.z, 0.95)
		else:
			CarScript.neon_light(null, Vector3.ZERO, Vector3.ZERO, 0.0)
	_bank_t = maxf(0.0, _bank_t - dt)
	if _hint_t > 0.0:
		_hint_t -= dt
		if _hint_t <= 0.0:
			reset_hint.visible = false

# ------------------------------------------------------------------ minimap

func _setup_minimap() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_wrap.add_child(svc)
	mini_vp = SubViewport.new()
	mini_vp.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # (everything in it moves every frame)
	mini_vp.size = Vector2i(196, 196)
	mini_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(mini_vp)
	mini_cam = Camera3D.new()
	mini_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved every frame by hand
	mini_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	mini_cam.size = 260.0
	mini_cam.near = 1.0
	mini_cam.far = 900.0
	mini_cam.cull_mask = island.MAP_LAYER
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("6fc3e8")
	mini_cam.environment = env
	mini_vp.add_child(mini_cam)
	var arrow := Control.new()
	arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.draw.connect(func():
		var c := arrow.size * 0.5
		var pts := PackedVector2Array([c + Vector2(0, -15), c + Vector2(11, 12), c + Vector2(0, 6), c + Vector2(-11, 12)])
		arrow.draw_colored_polygon(pts, K.PAPER)
		arrow.draw_polyline(pts + PackedVector2Array([pts[0]]), K.INK, 3.0))
	mini_wrap.add_child(arrow)

func _minimap_tick(p: Vector3, yaw: float) -> void:
	if mini_cam == null:
		return
	# heading up: the camera looks straight down, turned with the car
	mini_cam.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5), Vector3(p.x, 700.0, p.z))

# ------------------------------------------------------------------ sheets

func _sheet(title_text: String, icon: String, col: Color, width := 640.0) -> VBoxContainer:
	for c in overlay.get_children():
		c.queue_free()
	overlay.visible = true
	var dim := ColorRect.new()
	dim.color = K.DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var card := K.card()
	card.custom_minimum_size = Vector2(width, 0)
	overlay.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", K.box(col, 26, 0, Color.TRANSPARENT, 10))
	badge.add_child(Icon.new(icon, Color.WHITE, 38))
	head.add_child(badge)
	var tl := K.label(title_text, 40, K.INK, 700, HORIZONTAL_ALIGNMENT_LEFT)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	vb.add_child(head)
	card.modulate.a = 0.0
	card.resized.connect(func():
		card.position = (_vs() - card.size) * 0.5
		card.pivot_offset = card.size * 0.5)
	await get_tree().process_frame
	card.position = (_vs() - card.size) * 0.5
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(0.9, 0.9)
	var t := create_tween()
	t.tween_property(card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(card, "modulate:a", 1.0, 0.18)
	return vb

func close_sheet() -> void:
	overlay.visible = false
	for c in overlay.get_children():
		c.queue_free()

func _row_buttons(vb: VBoxContainer, items: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	for it in items:
		var b := K.button(it[0], it[2], it[3], 30, 300, 78, it[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tap(b, it[4])
		grid.add_child(b)

func open_pause() -> void:
	var vb: VBoxContainer = await _sheet("Paused", "pause", K.CORAL, 680.0)
	_row_buttons(vb, [
		["Keep driving", "play", K.CORAL, K.CORAL_DK, func(): game.resume()],
		["Reset car", "home", K.SUN, K.SUN_DK, func(): game.reset_car()],
		["Map", "map", K.TEAL, K.TEAL_DK, func(): open_map()],
		["Garage", "car", K.SKY, K.SKY_DK, func():
			close_sheet()
			game.open_garage()],
		["Trophies", "trophy", K.LILAC, K.LILAC_DK, func(): open_achievements(true)],
		["Settings", "gear", K.PAPER, K.LINE, func(): open_settings(true)],
	])
	if game.challenge_on():
		var is_race: bool = game.race != null
		_row_buttons(vb, [
			["Restart race" if is_race else "Restart", "back", K.CORAL, K.CORAL_DK, func(): game.restart_challenge()],
			["Leave race" if is_race else "Stop challenge", "flag", K.PAPER, K.LINE, func(): game.quit_challenge()],
		])
	var q := K.button("Title screen", K.PAPER, K.LINE, 26, 0, 64)
	_tap(q, func():
		close_sheet()
		transition(func(): game.go_title()))
	vb.add_child(q)

func _back_from(from_pause: bool) -> void:
	if from_pause:
		open_pause()
	else:
		close_sheet()

func open_settings(from_pause := false) -> void:
	var vb: VBoxContainer = await _sheet("Settings", "gear", K.LILAC, 1160.0)
	var st = game.save.data["settings"]
	# (everything between the title and Done scrolls, so Done is always on screen, however short the screen)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	_drag_scroll(sc)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 26)        # (clear of the scroll bar)
	sc.add_child(pad)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(inner)
	var sl := HBoxContainer.new()
	sl.add_theme_constant_override("separation", 40)
	inner.add_child(sl)
	var ms := _setting_slider("music", "Music", st["music"], func(v): game.set_setting("music", v))
	var ss := _setting_slider("sound", "Sounds", st["sfx"], func(v): game.set_setting("sfx", v))
	for x in [ms, ss]:
		x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.add_child(x)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 26)
	g.add_theme_constant_override("v_separation", 8)
	inner.add_child(g)
	g.add_child(_setting_toggle("tire", "Drift help", st["assist"], func(v): game.set_setting("assist", v)))
	g.add_child(_setting_toggle("car", "Steering wheel", st.get("wheel", true), func(v): game.set_setting("wheel", v)))
	g.add_child(_setting_toggle("vibe", "Vibration", st["haptics"], func(v): game.set_setting("haptics", v)))
	g.add_child(_setting_toggle("shadow", "Shadows", st["shadows"], func(v): game.set_setting("shadows", v)))
	g.add_child(_setting_toggle("sun", "Bloom", st.get("bloom", true), func(v): game.set_setting("bloom", v)))
	g.add_child(_setting_toggle("wind", "Speed blur", st.get("speedfx", true), func(v): game.set_setting("speedfx", v)))
	g.add_child(_setting_toggle("leaf", "Ambient particles", st.get("motes", true), func(v): game.set_setting("motes", v)))
	g.add_child(_setting_toggle("calendar", "Show clock", st["clock"], func(v): game.set_setting("clock", v)))
	g.add_child(_setting_toggle("eye", "Show FPS", st.get("fps", false), func(v): game.set_setting("fps", v)))
	g.add_child(_setting_toggle("gear", "Cap at 60 fps", st.get("fps60", false), func(v): game.set_setting("fps60", v)))
	var reset := K.button("Reset progress", K.PAPER, K.LINE, 24, 0, 60)
	reset.add_theme_color_override("font_color", K.CORAL_DK)
	var armed := [false]
	reset.pressed.connect(func():
		game.ui_tap()
		if not armed[0]:
			armed[0] = true
			reset.text = "Tap again to erase everything"
		else:
			game.reset_progress())
	inner.add_child(reset)
	var credit: String = game.sound.credit_line()
	var cl := K.label(("Music by %s (CC0) · " % credit if credit != "" else "") + "Models: Kenney (CC0), Tiny Car Pack, stunt ramps by Klyo Games (CC BY 4.0) · " + build_label(), 18, K.INK_SOFT, 500)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(cl)
	var kl := K.label("Stunt Yard: \"Stunt arena 3D models: ramps, hoop, barriers (GLB)\" and \"Stunt arena 3D expansion: loop, half-pipe, tunnel, obstacles\" by Klyo Games (https://games.klyo.pl/free-game-assets/), CC BY 4.0 (creativecommons.org/licenses/by/4.0), recoloured for the game.", 15, K.INK_SOFT, 500)
	kl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(kl)
	var done := K.button("Done", K.LILAC, K.LILAC_DK, 32, 0, 76)
	_tap(done, func(): _back_from(from_pause))
	vb.add_child(done)
	# as tall as what's in it, or as the screen leaves room for
	sc.custom_minimum_size = Vector2(0, minf(560.0, _vs().y - 250.0))
	await get_tree().process_frame
	if is_instance_valid(sc) and is_instance_valid(pad):
		sc.custom_minimum_size.y = minf(pad.size.y, _vs().y - 250.0)

func _setting_slider(icon: String, text: String, value: float, cb: Callable) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	hb.add_child(Icon.new(icon, K.INK, 38))
	var l := K.label(text, 28, K.INK, 600, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(130, 0)
	hb.add_child(l)
	var s := K.slider(value)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(cb)
	hb.add_child(s)
	return hb

func _setting_toggle(icon: String, text: String, value: bool, cb: Callable) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.custom_minimum_size = Vector2(320, 0)
	hb.add_child(Icon.new(icon, K.INK, 36))
	var l := K.label(text, 26, K.INK, 600, HORIZONTAL_ALIGNMENT_LEFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	var b := K.button("On" if value else "Off", K.TEAL if value else Color("c9c3bb"), K.TEAL_DK if value else Color("aba59d"), 24, 96, 56)
	var state := [value]
	b.pressed.connect(func():
		game.ui_tap()
		state[0] = not state[0]
		b.text = "On" if state[0] else "Off"
		var col: Color = K.TEAL if state[0] else Color("c9c3bb")
		var dk: Color = K.TEAL_DK if state[0] else Color("aba59d")
		for sname in ["normal", "hover"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(sname).duplicate()
			sb.bg_color = col
			sb.border_color = dk
			b.add_theme_stylebox_override(sname, sb)
		cb.call(state[0]))
	hb.add_child(b)
	return hb

func open_achievements(from_pause := false) -> void:
	var data: Dictionary = game.save.data
	var vb: VBoxContainer = await _sheet("Trophies  %d/%d" % [Ach.count(data), Ach.LIST.size()], "trophy", K.SKY, 820.0)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(780, minf(440.0, _vs().y - 260.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	_drag_scroll(sc)
	var list := GridContainer.new()
	list.columns = 2
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("h_separation", 10)
	list.add_theme_constant_override("v_separation", 10)
	sc.add_child(list)
	var rows := []
	for a in Ach.LIST:
		var got := Ach.unlocked(data, a["id"])
		var prog := clampf(Ach.value(a, data) / Ach.target(a), 0.0, 1.0)
		rows.append([a, got, prog])
	rows.sort_custom(func(x, y): return (1 if x[1] else 0) > (1 if y[1] else 0) or (x[1] == y[1] and x[2] > y[2]))
	for r in rows:
		list.add_child(_ach_row(r[0], r[1], r[2]))
	var ok := K.button("Done", K.SKY, K.SKY_DK, 30, 0, 72)
	_tap(ok, func(): _back_from(from_pause))
	vb.add_child(ok)

func _ach_row(a: Dictionary, got: bool, prog: float) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", K.box(Color("ece4d3") if got else K.CREAM, 20, 0, Color.TRANSPARENT, 10))
	p.custom_minimum_size = Vector2(380, 0)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(hb)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", K.box(K.SUN if got else K.LINE, 22, 0, Color.TRANSPARENT, 6))
	badge.add_child(Icon.new(a["icon"] if got else "lock", Color.WHITE if got else K.INK_SOFT, 30))
	badge.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(badge)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(vb)
	vb.add_child(K.label(a["name"], 22, K.INK, 700, HORIZONTAL_ALIGNMENT_LEFT))
	var dl := K.label(a["desc"], 17, K.INK_SOFT, 500, HORIZONTAL_ALIGNMENT_LEFT)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(dl)
	if not got and Ach.target(a) > 1.0:
		var b := K.bar(200, 8, K.SKY)
		b.value = prog
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(b)
	var rw := HBoxContainer.new()
	rw.add_theme_constant_override("separation", 4)
	rw.mouse_filter = Control.MOUSE_FILTER_PASS
	if got:
		rw.add_child(Icon.new("check", K.TEAL, 28))
	else:
		rw.add_child(Icon.new("coin", K.INK, 22))
		rw.add_child(K.label(str(a["reward"]), 20, K.INK, 650))
	hb.add_child(rw)
	return p

func show_help() -> void:
	var vb: VBoxContainer = await _sheet("How to drive", "car", K.TEAL, 1040.0)
	for line in [
		["left", "Steer with the wheel on the left (or arrow buttons: turn the wheel off in Settings). Drag anywhere else on the screen to look around the car, pinch to zoom."],
		["play", "GAS and BRAKE on the right. Hold BRAKE when stopped to reverse."],
		["tire", "Tap DRIFT (the handbrake) while steering to swing the tail out. Keep the gas down and hold the steering into the turn to hold the slide."],
		["right", "Steer the other way with the gas down to swing into a drift the other way. Let go of steering, or ease off the gas, to straighten up."],
		["star", "Drifts score points and coins. Chain them for a bigger multiplier, and skim walls and cars for a close bonus. Don't crash mid-drift!"],
		["wind", "In the air, GAS tips the nose down and BRAKE lifts it (hold to flip), steering spins you round, and DRIFT + steering barrel-rolls. Land on your wheels! The Stunt Yard is just south of town."],
		["flag", "Orange rings are drift zones, blue time trials, purple drift runs and red ones races. Open the map to set a route to any of them (or a gas station: fuel runs down, and they fix dents too)."],
	]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		hb.add_child(Icon.new(line[0], K.INK, 38))
		var l := K.label(line[1], 22, K.INK, 600, HORIZONTAL_ALIGNMENT_LEFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(920, 0)
		hb.add_child(l)
		vb.add_child(hb)
	var ok := K.button("Let's go", K.TEAL, K.TEAL_DK, 32, 0, 76, "play")
	_tap(ok, close_sheet)
	vb.add_child(ok)

# ------------------------------------------------------------------ the map

const MAP_SPAN := 1200.0     # metres across the big map (the island and the circuits off its coasts)

func open_map() -> void:
	var vb: VBoxContainer = await _sheet("Island map", "map", K.TEAL, 1120.0)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	var sz := minf(470.0, _vs().y - 220.0)
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(sz, sz)
	holder.add_theme_stylebox_override("panel", K.box(Color("6fc3e8"), 24, 0, Color.TRANSPARENT, 0))
	holder.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	hb.add_child(holder)
	var svc := SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	holder.add_child(svc)
	var vp := SubViewport.new()
	vp.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # (everything in it moves every frame)
	vp.size = Vector2i(int(sz), int(sz))
	svc.add_child(vp)
	var mc := Camera3D.new()
	mc.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved every frame by hand
	mc.projection = Camera3D.PROJECTION_ORTHOGONAL
	mc.size = MAP_SPAN
	mc.near = 1.0
	mc.far = 900.0
	mc.cull_mask = island.MAP_LAYER
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("6fc3e8")
	mc.environment = env
	vp.add_child(mc)
	mc.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 700, 0))
	# you are here
	var me := Control.new()
	me.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	me.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cp: Vector3 = game.car.global_position
	var cy: float = game.car.global_rotation.y
	me.draw.connect(func():
		var c := Vector2((cp.x / MAP_SPAN + 0.5) * sz, (cp.z / MAP_SPAN + 0.5) * sz)
		var f := Vector2(-sin(cy), -cos(cy))
		var r := Vector2(-f.y, f.x)
		var pts := PackedVector2Array([c + f * 14.0, c - f * 9.0 + r * 9.0, c - f * 4.0, c - f * 9.0 - r * 9.0])
		me.draw_colored_polygon(pts, K.PAPER)
		me.draw_polyline(pts + PackedVector2Array([pts[0]]), K.INK, 2.5))
	holder.add_child(me)
	# the challenges, with your medals and a quick way there
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(right)
	var found: int = game.save.data["places"].size()
	right.add_child(K.label("Places found %d/%d · Hidden coins %d/%d" % [found, island.places.size(), game.save.data["coins_taken"].size(), island.coin_spots.size()], 22, K.INK_SOFT, 600, HORIZONTAL_ALIGNMENT_LEFT))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(560, sz - 40.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sc)
	_drag_scroll(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	sc.add_child(list)
	if not game.route_pick.is_empty():
		var clr := K.button("Clear route to %s" % game.route_pick["name"], K.PAPER, K.LINE, 20, 0, 50)
		_tap(clr, func():
			game.set_route_pick(Vector3.ZERO, "")
			open_map())
		list.add_child(clr)
	for z in island.zones:
		var best := int(game.save.data["zones"].get(z["id"], 0))
		list.add_child(_chal_row(z["name"], "Drift zone · best %s" % K.fmt(best) if best > 0 else "Drift zone", int(game.save.data["medals"].get(z["id"], 0)), Color("ff8a5c"),
			game._road_spot(z["start"], 0.0), z["start"]))
	for t in island.trials:
		var best2: float = float(game.save.data["trials"].get(t["id"], 0.0))
		var info := "Time trial" if t["kind"] == "time" else "Drift run"
		if best2 > 0.0:
			info += (" · best %.2f s" % best2) if t["kind"] == "time" else (" · best %s" % K.fmt(int(best2)))
		var g0: Transform3D = t["gates"][0]
		list.add_child(_chal_row(t["name"], info, int(game.save.data["medals"].get(t["id"], 0)), Color("5cc8ff") if t["kind"] == "time" else Color("c38bff"),
			Transform3D(g0.basis, g0.origin + Vector3(0, 1.0, 0)).translated_local(Vector3(0, 0, 16)), g0.origin))
	for rc in island.races:
		var dk: String = game.race_key(String(rc["id"]), game.race_diff())
		var rbest: float = float(game.save.data["races"].get(dk, 0.0))
		var rinfo := "%s · %d laps · %s" % ["Circuit race" if rc.get("track", false) else "Street race", int(rc["laps"]),
			String(game.Race.DIFF[game.race_diff()]["name"])]
		if rbest > 0.0:
			rinfo += " · best %d:%05.2f" % [int(rbest) / 60, fmod(rbest, 60.0)]
		var rid: String = rc["id"]
		list.add_child(_chal_row(rc["name"], rinfo, int(game.save.data["medals"].get("race_" + dk, 0)), Color("ff5c7a"),
			Transform3D(Basis(), (rc["pos"] as Vector3) + Vector3(0, 1.0, 0)), rc["pos"], func(): game.start_challenge_now("race", rid)))
	for st in island.stations:
		var sp: Vector3 = st["pos"]
		var d := int(round(sp.distance_to(game.car.global_position) / 10.0) * 10.0)
		list.add_child(_chal_row("%s gas station" % st["name"], "Fuel and repairs · %d m away" % d, -1, Color("4fb3a5"),
			game._road_spot(sp, 0.0), sp))
	var back := K.button("Back", K.PAPER, K.LINE, 28, 0, 68)
	_tap(back, func():
		if game.state == game.PAUSED:
			open_pause()
		else:
			close_sheet())
	vb.add_child(back)

func _chal_row(name: String, info: String, medal: int, col: Color, xf: Transform3D, where := Vector3.INF, start := Callable()) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", K.box(K.CREAM, 20, 0, Color.TRANSPARENT, 10))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(22, 22)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", K.box(col, 11, 0, Color.TRANSPARENT, 0))
	hb.add_child(dot)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", -2)
	hb.add_child(vb)
	vb.add_child(K.label(name, 24, K.INK, 700, HORIZONTAL_ALIGNMENT_LEFT))
	vb.add_child(K.label(info, 18, K.INK_SOFT, 600, HORIZONTAL_ALIGNMENT_LEFT))
	if medal >= 0:
		var mcol: Color = [K.LINE, Color("b98b62"), Color("b3b8bd"), Color("d4b25c")][medal]
		hb.add_child(Icon.new("trophy", mcol, 34))
	else:
		hb.add_child(Icon.new("fuel", K.INK_SOFT, 34))
	if where != Vector3.INF:
		# set the GPS: a line on the map and the arrow up top
		var rt := K.button("Route", K.SKY, K.SKY_DK, 20, 92, 54)
		_tap(rt, func():
			game.set_route_pick(where, name)
			close_sheet()
			if game.state == game.PAUSED:
				game.resume())
		hb.add_child(rt)
	var go := K.button("Race" if start.is_valid() else "Go", K.TEAL, K.TEAL_DK, 22, 76 if not start.is_valid() else 84, 54)
	_tap(go, func():
		close_sheet()
		transition(func():
			game.travel_to(xf)        # (out of the pause menu or the title, and to the spot)
			if start.is_valid():
				start.call()))
	hb.add_child(go)
	return p

# ------------------------------------------------------------------ garage

func _build_garage() -> void:
	garage = _full(Control.MOUSE_FILTER_STOP)
	garage.visible = false
	var bg := ColorRect.new()
	bg.color = Color("e4e0d9")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	garage.add_child(bg)
	# the showroom (left side)
	var svc := SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	svc.anchor_right = 0.56
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_PASS
	svc.gui_input.connect(_garage_input)
	garage.add_child(svc)
	g_view = SubViewport.new()
	g_view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # (everything in it moves every frame)
	g_view.own_world_3d = true
	g_view.transparent_bg = true
	g_view.msaa_3d = Viewport.MSAA_4X
	g_view.size = Vector2i(720, 720)
	svc.add_child(g_view)
	g_root3d = Node3D.new()
	g_view.add_child(g_root3d)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d8d6d2")
	env.ambient_light_energy = 0.5
	we.environment = env
	g_root3d.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_color = Color("fff3e0")
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	g_root3d.add_child(sun)
	var cam := Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved every frame by hand
	cam.fov = 34
	cam.position = Vector3(0, 3.6, 12.5)
	cam.rotation_degrees = Vector3(-13, 0, 0)
	g_root3d.add_child(cam)
	g_mat = ShaderMaterial.new()
	g_mat.shader = load("res://shaders/toon.gdshader")
	g_mat.set_shader_parameter("palette", PAL.make_texture())
	g_mat.set_shader_parameter("season", 1.5)
	g_turn = Node3D.new()
	g_root3d.add_child(g_turn)
	var plat := MeshInstance3D.new()
	var mb := MB.new()
	mb.cyl(Vector3(0, -0.15, 0), 3.6, 0.3, MB.rgb("b9b3aa"), 48)
	mb.cyl(Vector3(0, -0.42, 0), 3.75, 0.26, MB.rgb("8f8981"), 48)
	plat.mesh = mb.commit()
	plat.material_override = g_mat
	g_turn.add_child(plat)
	g_car = Node3D.new()
	g_turn.add_child(g_car)
	# top bar
	var tb := HBoxContainer.new()
	tb.position = Vector2(26, 22)
	tb.add_theme_constant_override("separation", 16)
	garage.add_child(tb)
	var back := K.round_button("back", K.PAPER, K.LINE, 72)
	_tap(back, func(): game.close_garage(g_from))
	tb.add_child(back)
	tb.add_child(K.label("Garage", 46, K.INK, 700, HORIZONTAL_ALIGNMENT_LEFT))
	g_coins = K.pill("coin", "0")
	g_coins.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	g_coins.position = Vector2(-250, 22)
	garage.add_child(g_coins)
	# the panel (right side)
	var card := K.card(K.PAPER, 36)
	card.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	card.anchor_left = 0.56
	card.offset_left = 0
	card.offset_right = -24
	card.offset_top = 96
	card.offset_bottom = -24
	garage.add_child(card)
	g_panel = VBoxContainer.new()
	g_panel.add_theme_constant_override("separation", 12)
	card.add_child(g_panel)

func show_garage(from: int) -> void:
	g_from = from
	title.visible = false
	hud.visible = false
	close_sheet()
	garage.visible = true
	g_index = CARS.index_of(String(game.save.data["car"]))
	g_tab = "cars"
	g_paint = -1
	_garage_refresh()

func hide_garage() -> void:
	garage.visible = false

func _garage_refresh() -> void:
	var s = game.save.data
	g_coins.get_meta("label").text = K.fmt(int(s["coins"]))
	for c in g_panel.get_children():
		c.queue_free()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	g_panel.add_child(tabs)
	for tdef in [["cars", "Cars", "car"], ["paint", "Paint", "star"], ["tune", "Tune", "tire"], ["up", "Upgrades", "gear"]]:
		var on: bool = g_tab == tdef[0]
		var b := K.button(tdef[1], K.CORAL if on else K.CREAM, K.CORAL_DK if on else K.LINE_DK, 18, 0, 62, tdef[2])
		if not on:
			b.add_theme_color_override("font_color", K.INK)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = float(String(tdef[1]).length()) + 4.0     # (a longer name, a wider tab)
		var id: String = tdef[0]
		_tap(b, func():
			g_tab = id
			g_paint = -1
			_garage_refresh())
		tabs.add_child(b)
	_show_car(CARS.LIST[g_index])
	if g_tab == "cars":
		_cars_tab()
	elif g_tab == "paint":
		_paint_tab()
	elif g_tab == "tune":
		_tune_tab()
	else:
		_upgrades_tab()

## The paint job a car wears (0: factory).
func _worn_paint(id: String) -> int:
	return int(game.save.data["paint"].get(id, 0))

func _owns_paint(id: String, idx: int) -> bool:
	return idx == 0 or (game.save.data["paints"].get(id, []) as Array).has(idx)

func _paint_tab() -> void:
	var s = game.save.data
	var d: Dictionary = CARS.LIST[g_index]
	var id: String = d["id"]
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	g_panel.add_child(nav)
	var prev := K.round_button("left", K.PAPER, K.LINE, 64)
	_tap(prev, func(): _garage_step(-1))
	nav.add_child(prev)
	var nm := K.label(d["name"], 32, K.INK, 700)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(nm)
	var nxt := K.round_button("right", K.PAPER, K.LINE, 64)
	_tap(nxt, func(): _garage_step(1))
	nav.add_child(nxt)
	var list := M.paints(d)
	if list.size() < 2:
		g_panel.add_child(K.label("No other paint jobs for this one.", 22, K.INK_SOFT, 600))
		return
	g_panel.add_child(K.label("Tap a colour to try it on. %s coins each." % K.fmt(PAINT_PRICE), 20, K.INK_SOFT, 600))
	var shown := _worn_paint(id) if g_paint < 0 else g_paint
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	g_panel.add_child(row)
	for i in list.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(78, 78)
		var col := Color(String(list[i]["swatch"]))
		var sb := K.box(col, 39, 0, Color.TRANSPARENT, 0)
		sb.set_border_width_all(6 if i == shown else 3)
		sb.border_color = K.INK if i == shown else Color(1, 1, 1, 0.8)
		for st in ["normal", "hover", "pressed", "focus"]:
			sw.add_theme_stylebox_override(st, sb)
		if not _owns_paint(id, i):
			sw.add_child(Icon.new("lock", Color(1, 1, 1, 0.85), 30))
			(sw.get_child(0) as Control).position = Vector2(24, 24)
		elif i == _worn_paint(id):
			sw.add_child(Icon.new("check", Color.WHITE, 30))
			(sw.get_child(0) as Control).position = Vector2(24, 24)
		var ii := i
		_tap(sw, func():
			g_paint = ii
			game.sfx("select", -8.0)
			_garage_refresh())
		row.add_child(sw)
	g_panel.add_child(K.label("Factory paint" if shown == 0 else "Paint job %d" % shown, 22, K.INK, 650))
	var act: Button
	if not game.save.owns(id):
		act = K.button("Buy the car first", Color("c9c3bb"), Color("aba59d"), 28, 0, 80, "lock")
		act.disabled = true
	elif shown == _worn_paint(id):
		act = K.button("Wearing this paint", Color("c9c3bb"), Color("aba59d"), 28, 0, 80, "check")
		act.disabled = true
	elif _owns_paint(id, shown):
		act = K.button("Use this paint", K.TEAL, K.TEAL_DK, 30, 0, 80, "play")
	elif int(s["coins"]) >= PAINT_PRICE:
		act = K.button("Buy paint · %s" % K.fmt(PAINT_PRICE), K.CORAL, K.CORAL_DK, 30, 0, 80, "coin")
	else:
		act = K.button("%s coins" % K.fmt(PAINT_PRICE), Color("c9c3bb"), Color("aba59d"), 28, 0, 80, "lock")
		act.disabled = true
	var pick := shown
	_tap(act, func(): _paint_action(id, pick))
	g_panel.add_child(act)

func _paint_action(id: String, idx: int) -> void:
	var s = game.save.data
	if not _owns_paint(id, idx):
		if int(s["coins"]) < PAINT_PRICE:
			return
		s["coins"] = int(s["coins"]) - PAINT_PRICE
		var got: Array = s["paints"].get(id, [])
		got.append(idx)
		s["paints"][id] = got
		game.sfx("purchase")
		game.buzz(60, 0.9)
	else:
		game.sfx("select")
	s["paint"][id] = idx
	game.save.save()
	if String(s["car"]) == id:
		game.car_changed()
	g_paint = -1
	_garage_refresh()

func _show_car(d: Dictionary) -> void:
	for c in g_car.get_children():
		c.queue_free()
	var c := M.car(d)
	var tn: Dictionary = game.save.data["tune"].get(String(d["id"]), {})
	var cam_k := clampf(float(tn.get("camber", 0)) / 5.0, 0.0, 1.0)
	var rh := clampf(float(tn.get("height", 0)) / 2.0, -1.0, 1.0)
	var body := MeshInstance3D.new()
	body.mesh = M.painted_body(d, (_worn_paint(d["id"]) if g_paint < 0 else g_paint) if g_tab == "paint" else _worn_paint(d["id"]))
	body.material_override = g_mat
	body.position.y = rh * (0.08 if rh < 0.0 else 0.1)       # (the ride height: the body up or down over its wheels)
	g_car.add_child(body)
	var low := 1e9
	for i in 4:
		var w := MeshInstance3D.new()
		w.mesh = M.wheel_mesh(c, i)
		w.material_override = g_mat
		w.position = c["wheels"][i]
		w.basis = CarScript.camber_basis((c["wheels"][i] as Vector3).x < 0.0, cam_k)
		g_car.add_child(w)
		low = minf(low, (c["wheels"][i] as Vector3).y - float(c["r_f"] if i < 2 else c["r_r"]))
	var ni := int(tn.get("neon", 0))
	g_neon = null
	g_neon_y = low
	if ni > 0 and ni < CarScript.NEON.size():
		var nn := CarScript.make_neon(c, CarScript.NEON[ni], g_mat)
		g_car.add_child(nn)
		g_neon = nn

func _cars_tab() -> void:
	var s = game.save.data
	var d: Dictionary = CARS.LIST[g_index]
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	g_panel.add_child(nav)
	var prev := K.round_button("left", K.PAPER, K.LINE, 70)
	_tap(prev, func(): _garage_step(-1))
	nav.add_child(prev)
	var nm := K.label(d["name"], 36, K.INK, 700)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(nm)
	var nxt := K.round_button("right", K.PAPER, K.LINE, 70)
	_tap(nxt, func(): _garage_step(1))
	nav.add_child(nxt)
	g_panel.add_child(K.label("%d of %d" % [g_index + 1, CARS.LIST.size()], 20, K.INK_SOFT, 600))
	for st in [["Power", d["power"], 0.95, 1.6], ["Top speed", d["speed"], 0.95, 1.25], ["Grip", d["grip"], 0.95, 1.16], ["Drift", d["drift"], 1.0, 1.4]]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		var l := K.label(st[0], 24, K.INK_SOFT, 600, HORIZONTAL_ALIGNMENT_LEFT)
		l.custom_minimum_size = Vector2(140, 0)
		hb.add_child(l)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 6)
		var n := 1 + int(round(clampf((float(st[1]) - st[2]) / (st[3] - st[2]), 0.0, 1.0) * 5.0))
		for k in 6:
			var pip := Panel.new()
			pip.custom_minimum_size = Vector2(38, 16)
			pip.add_theme_stylebox_override("panel", K.box(K.TEAL if k < n else K.LINE, 8, 0, Color.TRANSPARENT, 0))
			pips.add_child(pip)
		hb.add_child(pips)
		g_panel.add_child(hb)
	var owned: bool = game.save.owns(d["id"])
	var selected: bool = String(s["car"]) == d["id"]
	var price: int = d["price"]
	var act: Button
	if selected:
		act = K.button("Driving this one", Color("c9c3bb"), Color("aba59d"), 30, 0, 84, "check")
		act.disabled = true
	elif owned:
		act = K.button("Drive this one", K.TEAL, K.TEAL_DK, 32, 0, 84, "play")
	elif int(s["coins"]) >= price:
		act = K.button("Buy · %s" % K.fmt(price), K.CORAL, K.CORAL_DK, 32, 0, 84, "coin")
	else:
		act = K.button("%s coins" % K.fmt(price), Color("c9c3bb"), Color("aba59d"), 30, 0, 84, "lock")
		act.disabled = true
	_tap(act, _garage_action)
	g_panel.add_child(act)

func _garage_step(dlt: int) -> void:
	g_index = posmod(g_index + dlt, CARS.LIST.size())
	g_paint = -1
	_garage_refresh()
	g_car.scale = Vector3(0.75, 0.75, 0.75)
	create_tween().tween_property(g_car, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _garage_action() -> void:
	var d: Dictionary = CARS.LIST[g_index]
	var s = game.save.data
	if game.save.owns(d["id"]):
		s["car"] = d["id"]
		game.save.save()
		game.car_changed()
		game.sfx("select")
	elif int(s["coins"]) >= int(d["price"]):
		s["coins"] = int(s["coins"]) - int(d["price"])
		s["owned"].append(d["id"])
		s["car"] = d["id"]
		game.save.save()
		game.car_changed()
		game.sfx("purchase")
		game.buzz(60, 0.9)
		game.ach_check()
	_garage_refresh()

## Tuning for the car on show: camber, ride height, and neon underglow. They change how it handles.
func _tune_tab() -> void:
	var s = game.save
	var d: Dictionary = CARS.LIST[g_index]
	var id := String(d["id"])
	g_panel.add_child(K.label(d["name"], 30, K.INK, 700))
	if not s.owns(id):
		g_panel.add_child(K.label("Buy this car to tune it.", 22, K.INK_SOFT, 600))
		return
	var tn: Dictionary = s.data["tune"].get(id, {})
	var set_tn := func(k: String, v):
		var t2: Dictionary = (s.data["tune"].get(id, {}) as Dictionary).duplicate()
		t2[k] = v
		s.data["tune"][id] = t2
		s.save()
		if String(s.data["car"]) == id:
			game.car_changed()
		game.sfx("upgrade", -6.0, 1.2)
		_garage_refresh()
	var cam := int(tn.get("camber", 0))
	var hgt := int(tn.get("height", 0))
	g_panel.add_child(_tune_row("Camber", "%d°" % (cam * 2), cam, 0, 5, K.LILAC, func(v): set_tn.call("camber", v)))
	g_panel.add_child(_tune_row("Ride height", ["Slammed", "Low", "Stock", "High", "Lifted"][hgt + 2], hgt, -2, 2, K.SKY, func(v): set_tn.call("height", v)))
	# what that does to the handling
	var ck := cam / 5.0
	var rk := hgt / 2.0
	var grip := 1.0 - 0.09 * ck + 0.04 * rk
	var ease := clampf(0.6 * ck - 0.3 * rk, -0.3, 0.9)
	var off := 1.0 + 0.12 * rk - 0.08 * ck - 0.1 * maxf(-rk, 0.0)
	var eg := GridContainer.new()
	eg.columns = 2
	eg.add_theme_constant_override("h_separation", 12)
	eg.add_theme_constant_override("v_separation", 4)
	g_panel.add_child(eg)
	for e in [["Race grip", (grip - 0.87) / 0.17], ["Drift ease", (ease + 0.3) / 1.2], ["Off-road", (off - 0.82) / 0.3]]:
		eg.add_child(K.label(e[0], 18, K.INK_SOFT, 600, HORIZONTAL_ALIGNMENT_LEFT))
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(250, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fv := clampf(float(e[1]), 0.05, 1.0)
		bar.draw.connect(func():
			bar.draw_rect(Rect2(Vector2.ZERO, bar.size), K.LINE)
			bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * fv, bar.size.y)), K.TEAL_DK))
		eg.add_child(bar)
	# neon
	if not bool(s.data.get("neon_kit", false)):
		var nb := K.button("Neon underglow kit · %s" % K.fmt(SaveData.NEON_KIT), K.CORAL, K.CORAL_DK, 22, 0, 58, "coin")
		nb.disabled = int(s.data["coins"]) < SaveData.NEON_KIT
		_tap(nb, func():
			if int(s.data["coins"]) < SaveData.NEON_KIT:
				return
			s.data["coins"] = int(s.data["coins"]) - SaveData.NEON_KIT
			s.data["neon_kit"] = true
			s.save()
			game.sfx("upgrade")
			_garage_refresh())
		g_panel.add_child(nb)
	else:
		var nr := HBoxContainer.new()
		nr.add_theme_constant_override("separation", 6)
		nr.add_child(K.label("Neon", 20, K.INK_SOFT, 650))
		var cur := int(tn.get("neon", 0))
		for ni in CarScript.NEON.size():
			var sw := Button.new()
			sw.focus_mode = Control.FOCUS_NONE
			sw.custom_minimum_size = Vector2(40, 40)
			var sc: Color = K.LINE if ni == 0 else Color(CarScript.NEON[ni])
			var sb := K.box(sc, 20, 0, Color.TRANSPARENT, 0)
			if ni == cur:
				sb.border_color = K.INK
				sb.set_border_width_all(4)
			for st in ["normal", "hover", "pressed", "hover_pressed"]:
				sw.add_theme_stylebox_override(st, sb)
			if ni == 0:
				sw.text = "off"
				sw.add_theme_font_size_override("font_size", 13)
				sw.add_theme_color_override("font_color", K.INK)
			var nv := ni
			_tap(sw, func(): set_tn.call("neon", nv))
			nr.add_child(sw)
		g_panel.add_child(nr)

## A tuning setting with - and + either side of where it's set.
func _tune_row(label: String, value: String, v: int, lo: int, hi: int, col: Color, on_set: Callable) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", K.box(K.CREAM, 22, 0, Color.TRANSPARENT, 10))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)
	vb.add_child(K.label("%s  ·  %s" % [label, value], 22, K.INK, 700, HORIZONTAL_ALIGNMENT_LEFT))
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 5)
	for k in range(lo, hi + 1):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(30, 12)
		pip.add_theme_stylebox_override("panel", K.box(col if k <= v else K.LINE, 6, 0, Color.TRANSPARENT, 0))
		pips.add_child(pip)
	vb.add_child(pips)
	var minus := K.round_button("left", K.PAPER, K.LINE, 56)
	minus.disabled = v <= lo
	_tap(minus, func(): on_set.call(v - 1))
	hb.add_child(minus)
	var plus := K.round_button("right", K.PAPER, K.LINE, 56)
	plus.disabled = v >= hi
	_tap(plus, func(): on_set.call(v + 1))
	hb.add_child(plus)
	return p

func _upgrades_tab() -> void:
	var s = game.save
	g_panel.add_child(K.label("Upgrades work on every car you own.", 20, K.INK_SOFT, 600))
	var cols := {"engine": K.CORAL, "turbo": K.SKY, "tyres": K.TEAL, "steering": K.LILAC, "nitrous": Color("3aa0ff")}
	for u in SaveData.UPGRADES:
		var info: Dictionary = SaveData.UPGRADE_INFO[u]
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", K.box(K.CREAM, 22, 0, Color.TRANSPARENT, 10))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		p.add_child(hb)
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", K.box(cols[u], 22, 0, Color.TRANSPARENT, 8))
		badge.add_child(Icon.new(info["icon"], Color.WHITE, 38))
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(badge)
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 2)
		hb.add_child(vb)
		vb.add_child(K.label(info["name"], 24, K.INK, 700, HORIZONTAL_ALIGNMENT_LEFT))
		vb.add_child(K.label(info["desc"], 17, K.INK_SOFT, 500, HORIZONTAL_ALIGNMENT_LEFT))
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 5)
		var lvl: int = s.level(u)
		for k in SaveData.MAX_LEVEL:
			var pip := Panel.new()
			pip.custom_minimum_size = Vector2(30, 12)
			pip.add_theme_stylebox_override("panel", K.box(cols[u] if k < lvl else K.LINE, 6, 0, Color.TRANSPARENT, 0))
			pips.add_child(pip)
		vb.add_child(pips)
		var cost: int = s.upgrade_cost(u)
		var b: Button
		if cost < 0:
			b = K.button("Max", Color("c9c3bb"), Color("aba59d"), 24, 120, 60)
			b.disabled = true
		else:
			b = K.button(K.fmt(cost), cols[u], (cols[u] as Color).darkened(0.2), 24, 120, 60, "coin")
			b.disabled = int(s.data["coins"]) < cost
			var uu: String = u
			_tap(b, func(): _buy_upgrade(uu))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(b)
		g_panel.add_child(p)

func _buy_upgrade(u: String) -> void:
	var s = game.save
	var cost: int = s.upgrade_cost(u)
	if cost < 0 or int(s.data["coins"]) < cost:
		return
	s.data["coins"] = int(s.data["coins"]) - cost
	s.data["up"][u] = s.level(u) + 1
	s.save()
	game.car_changed()
	game.sfx("upgrade")
	game.buzz(50, 0.8)
	game.ach_check()
	_garage_refresh()

func _garage_input(e: InputEvent) -> void:
	if e is InputEventScreenDrag:
		g_drag += e.relative.x
		g_spin += e.relative.x * 0.01
	elif e is InputEventScreenTouch and not e.pressed:
		g_drag = 0.0          # (a swipe only turns the car: the arrows change it)
