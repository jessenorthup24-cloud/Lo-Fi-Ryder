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
const Cards := preload("res://scripts/game/cards.gd")
const CARD_SHADER := preload("res://shaders/card.gdshader")
const SaveData := preload("res://scripts/game/save.gd")
const MapView := preload("res://scripts/ui/map_view.gd")
const CarScript := preload("res://scripts/game/drift_car.gd")
const Phone := preload("res://scripts/ui/phone.gd")
const Progress := preload("res://scripts/game/progress.gd")

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
var speedo: Control
var foot_mode := false
var hp_bar: ProgressBar      # (unused now: health is hp_g, top right)
var hp_g: Control
var sta_g: Control
var phone_layer: Control
var radar_on := false        # the phone's safe radar: a pulse on the HUD pointing roughly at the nearest safe
var radar: Control
var _radar_ang := 0.0
var _radar_d := 0.0
var _ping_t := 0.0
var _clock_dot: Label
var cruise_lbl: Label
var heist_btn: Button        # by a safe: START HEIST
var heist_box: PanelContainer   # a heist on: what to do, the clock, a bar
var _heist_title: Label
var _heist_sub: Label
var _heist_bar: ProgressBar
const FOOT_PADS := ["stick", "jump", "sprint", "fire", "swap", "reload", "crouch"]     # (no AIM: holding FIRE aims)
var reticle: Control        # on foot, aiming: the dot in the middle (red when it's locked on)
var _hit_t := 0.0            # a hit marker showing (s left)
var _hit_kill := false
var aim_mark: Control       # on foot: the stick, jump and sprint instead of the car's controls
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
var title_go: Button
var g_root3d: Node3D
var g_car: Node3D
const Avatar := preload("res://scripts/game/avatar.gd")
const Weapons := preload("res://scripts/game/weapons.gd")
const Gunplay := preload("res://scripts/game/gunplay.gd")
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
var wanted_back: Panel
var limit_sign: PanelContainer   # the speed limit, by the speedo while a patrol car's about
var limit_lbl: Label
var phone: Phone                 # the phone: your contacts (the drivers), to call them to drive with you
var phone_btn: Button
var group_btn: Button            # the group ride view (only there while you've a crew)

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
	if wheel_open():
		_wheel_input(e)
		return
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

func _pass_touches(n) -> void:
	if n == null or not is_instance_valid(n):
		return            # (gone by the time this ran: the list was rebuilt)
	for c in (n as Node).get_children():
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
	bg.color = Color("0b0a11")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vb.position = Vector2(-420, -110)
	vb.size = Vector2(840, 220)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	loading.add_child(vb)
	vb.add_child(K.wordmark(64, false, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(K.spacer(10))
	var l := K.label("building the island...", 24, K.INK_SOFT, 400)
	l.add_theme_font_override("font", K.font_spaced(400, 2))
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
	# a dark wash from the left (so the type reads over any scene) and thin letterbox bars: a film still
	var wash := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.035, 0.03, 0.06, 0.92))
	gr.set_color(1, Color(0.035, 0.03, 0.06, 0.0))
	gr.add_point(0.42, Color(0.035, 0.03, 0.06, 0.6))
	gt.gradient = gr
	gt.width = 256
	gt.height = 4
	gt.fill_to = Vector2(1, 0)
	wash.texture = gt
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	wash.anchor_right = 0.72
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(wash)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.02, 0.02, 0.035, 0.9)
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size = Vector2(0, 26)
		if top:
			bar.offset_bottom = 26
		else:
			bar.offset_top = -26
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.add_child(bar)
	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 88
	left.offset_right = 760
	left.offset_top = 0
	left.offset_bottom = 0
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 14)
	title.add_child(left)
	title_logo = K.wordmark(100, true)
	left.add_child(title_logo)
	var tag := K.label("drift the streets of a little island town", 26, K.INK_SOFT, 400, HORIZONTAL_ALIGNMENT_LEFT)
	tag.add_theme_font_override("font", K.font_spaced(400, 1))
	left.add_child(tag)
	left.add_child(K.spacer(30))
	var go := K.button("DRIVE", K.CORAL, K.CORAL_DK, 38, 340, 92, "play")
	(go.get_meta("label") as Label).add_theme_font_override("font", K.font_spaced(650, 8))
	_tap(go, func(): transition(func(): game.start_drive()))
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(go)
	title_go = go
	left.add_child(K.spacer(8))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 34)
	left.add_child(row2)
	for b in [["car", "Garage", func(): game.open_garage()], ["map", "Map", func(): open_map()],
			["star", "Cards", func(): open_cards()], ["trophy", "Trophies", func(): open_achievements()], ["gear", "Settings", func(): open_settings()]]:
		var lk := K.link(b[1], b[0], 24)
		_tap(lk, b[2])
		row2.add_child(lk)
	title_coins = K.pill("coin", "0")
	title_coins.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	title_coins.position = Vector2(-250, 48)
	title.add_child(title_coins)
	var bl := K.label("", 17, Color(1, 1, 1, 0.38), 500, HORIZONTAL_ALIGNMENT_LEFT)
	bl.add_theme_font_override("font", K.font_spaced(500, 2))
	bl.name = "Build"
	bl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bl.position = Vector2(88, -64)
	title.add_child(bl)

func show_title() -> void:
	title.visible = true
	hud.visible = false
	garage.visible = false
	close_sheet()
	title.modulate.a = 1.0
	title_coins.get_meta("label").text = K.money(int(game.save.data["coins"]))
	(title.get_node("Build") as Label).text = "%s   ·   %d / %d TROPHIES" % [build_label().to_upper(), Ach.count(game.save.data), Ach.LIST.size()]
	# (a gentle way in: the type rises and fades up)
	title.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(title, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)

static func build_label() -> String:
	var v = JSON.parse_string(FileAccess.get_file_as_string("res://version.json")) if FileAccess.file_exists("res://version.json") else null
	return String(v.get("label", "dev")) if v is Dictionary else "dev"

## The DRIVE button breathes: its glow swells and settles.
func _title_tick(t: float) -> void:
	if title_go == null:
		return
	var sb := title_go.get_theme_stylebox("normal") as StyleBoxFlat
	if sb:
		sb.shadow_size = int(10.0 + 8.0 * (0.5 + 0.5 * sin(t * 2.0)))

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
	K.set_art(pb, "pause")
	pb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN      # (a circle: not stretched down beside the goal lines)
	_tap(pb, func(): game.pause())
	tl.add_child(pb)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(info)
	# one pill: your cash · the time · the weather; the district you're in, small, under it
	coins_pill = K.pill("coin", "0", 28)
	coins_pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var phb: HBoxContainer = coins_pill.get_child(0)
	# what's in the bank, small, after the cash on you (the cash is what you'd lose)
	_bank_lbl = K.label("", 16, Color("8cf0a8"), 800)
	_bank_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	phb.add_child(_bank_lbl)
	phb.move_child(_bank_lbl, 3)
	# your level, first in the pill: the number in a ring that fills with XP
	lvl_badge = Control.new()
	lvl_badge.custom_minimum_size = Vector2(46, 46)
	lvl_badge.size = Vector2(46, 46)
	lvl_badge.pivot_offset = Vector2(23, 23)
	lvl_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lvl_badge.draw.connect(_draw_lvl_badge)
	phb.add_child(lvl_badge)
	phb.move_child(lvl_badge, 0)
	_clock_dot = K.label("·", 26, Color(K.INK, 0.45), 700)
	phb.add_child(_clock_dot)
	clock_lbl = K.label("", 24, K.INK_SOFT, 650, HORIZONTAL_ALIGNMENT_LEFT)
	phb.add_child(clock_lbl)
	info.add_child(coins_pill)
	place_lbl = K.outlined(K.label("", 20, Color.WHITE, 650, HORIZONTAL_ALIGNMENT_LEFT), K.INK, 6)
	info.add_child(place_lbl)
	# top right: fuel, the car's condition and your health, side by side; the minimap under them
	var bars := HBoxContainer.new()
	bars.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	bars.position = Vector2(-306, 30)
	bars.add_theme_constant_override("separation", 14)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bars)
	fuel_g = _gauge("fuel", bars)
	cond_g = _gauge("wrench", bars)
	hp_g = _gauge("heart", bars)
	sta_g = _gauge("wind", bars)        # (your stamina: on foot)
	sta_g.visible = false
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
	rsb.border_color = Color(1, 1, 1, 0.55)
	rsb.set_border_width_all(3)
	ring.add_theme_stylebox_override("panel", rsb)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(ring)
	mini_ring = ring
	# a tidy column left of the minimap, all the same round buttons: phone, camera, rewind (and the
	# group view beside the phone while you've a crew)
	var camb := K.round_button("eye", K.PAPER, K.LINE, 64)
	K.set_art(camb, "camera")
	camb.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	camb.position = Vector2(-300, 170)
	_tap(camb, func(): game.toggle_cam())
	hud.add_child(camb)
	# the phone: call the drivers you know
	phone_btn = K.round_button("phone", K.PAPER, K.LINE, 64)
	K.set_art(phone_btn, "phone")
	phone_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	phone_btn.position = Vector2(-300, 94)
	_tap(phone_btn, func(): toggle_phone())
	hud.add_child(phone_btn)
	group_btn = K.round_button("group", K.PAPER, K.LINE, 64)
	group_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	group_btn.position = Vector2(-376, 94)
	group_btn.visible = false
	_tap(group_btn, func(): game.toggle_group_cam())
	hud.add_child(group_btn)
	phone = Phone.new()
	phone.visible = false
	phone.setup(self, game)
	# REWIND: hold it to take the last few seconds back
	var rw := PanelContainer.new()
	rw.add_theme_stylebox_override("panel", K.box(Color(K.PAPER, 0.85), 32, 6, Color(K.LINE_DK, 0.7), 0))
	rw.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	rw.position = Vector2(-300, 246)
	rw.size = Vector2(64, 64)
	rw.custom_minimum_size = rw.size
	rw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rw.pivot_offset = rw.size * 0.5
	var rwh := HBoxContainer.new()
	rwh.alignment = BoxContainer.ALIGNMENT_CENTER
	rwh.add_theme_constant_override("separation", 4)
	rwh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rw.add_child(rwh)
	if K.art("rewind").is_empty():
		var rwi := Icon.new("rewind", K.INK, 30)
		rwi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rwh.add_child(rwi)
	else:
		rw.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		rw.draw.connect(func(): K.draw_art(rw, Rect2(Vector2.ZERO, rw.size), "rewind", rw.scale.x > 1.01 or bool(rw.get_meta("on", false))))
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
	speedo = sp
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
	# cruise on: what it's holding, under the speedo (tap the speedo to set it, again to let go)
	cruise_lbl = K.outlined(K.label("", 18, Color("9fe3ff"), 700), K.INK, 6)
	sp.add_child(cruise_lbl)
	# steering, bottom left
	ctl["left"] = _pad("left", Vector2(40, -210), Vector2(170, 170), true, K.PAPER)
	ctl["right"] = _pad("right", Vector2(230, -210), Vector2(170, 170), true, K.PAPER)
	_build_wheel()
	# pedals, bottom right
	ctl["gas"] = _pad("gas", Vector2(-176, -232), Vector2(146, 196), false, K.PAPER)
	ctl["brake"] = _pad("brake", Vector2(-330, -212), Vector2(146, 196), false, K.PAPER)
	ctl["hand"] = _pad("hand", Vector2(-330, -380), Vector2(150, 152), false, K.PAPER)
	ctl["nos"] = _pad("nos", Vector2(-172, -386), Vector2(136, 140), false, Color("cfe9ff"))
	ctl["cruise"] = _pad("cruise", Vector2(-528, -356), Vector2(92, 92), false, K.PAPER)
	ctl["cruise"].visible = false        # (cruise is a tap on the speedo now)
	# the door: out of the car, or into it (both ways, the same spot)
	ctl["door"] = _pad("door", Vector2(-528, -470), Vector2(92, 92), false, K.PAPER)       # (above cruise)
	_place(ctl["door"], Control.PRESET_TOP_RIGHT, Vector2(-404, 80))     # (you start in the car: EXIT up by the phone)
	# on foot: a stick on the left, jump and sprint on the right
	ctl["stick"] = _pad("stick", Vector2(60, -300), Vector2(240, 240), true, K.PAPER)
	# the right thumb's cluster: the main button (punch, or fire) in the corner, the rest on an arc round it
	ctl["fire"] = _pad("fire", _arc(0, 0, 150), Vector2(150, 150), false, K.PAPER)
	ctl["jump"] = _pad("jump", _arc(270, 132, 98), Vector2(98, 98), false, K.PAPER)
	ctl["sprint"] = _pad("sprint", _arc(180, 132, 98), Vector2(98, 98), false, K.PAPER)
	ctl["crouch"] = _pad("crouch", _arc(225, 140, 76), Vector2(76, 76), false, K.PAPER)
	ctl["swap"] = _pad("swap", Vector2(-566, -372), Vector2(96, 96), false, K.PAPER)       # (the weapon wheel)
	_place(ctl["swap"], Control.PRESET_TOP_RIGHT, Vector2(-316, 248))      # (up by the minimap, under the phone and camera)
	ctl["block"] = _pad("block", _arc(318, 134, 90), Vector2(90, 90), false, K.PAPER)     # (in a fight: hold for your guard)
	ctl["block"].visible = false
	ctl["reload"] = _pad("reload", _arc(318, 134, 80), Vector2(80, 80), false, K.PAPER)
	ctl["aim"] = _pad("aim", _arc(150, 250, 76), Vector2(76, 76), false, K.PAPER)
	for k in FOOT_PADS:
		ctl[k].visible = false
	ctl["aim"].visible = false
	# your health, on foot: a slim bar under the minimap
	hp_bar = K.bar(196, 10, Color("ff4f6b"), Color(0, 0, 0, 0.35))
	hp_bar.visible = false
	# locked on: a ring of four brackets round whoever you're locked on to
	aim_mark = Control.new()
	aim_mark.size = Vector2(72, 72)
	aim_mark.pivot_offset = Vector2(36, 36)
	aim_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aim_mark.visible = false
	aim_mark.draw.connect(func():
		var red := Color(1.0, 0.25, 0.35, 0.95)
		for k in 4:
			var a := TAU * k / 4.0 + PI * 0.25
			aim_mark.draw_arc(Vector2(36, 36), 26.0, a - 0.38, a + 0.38, 10, Color(0, 0, 0, 0.4), 6.0, true)
			aim_mark.draw_arc(Vector2(36, 36), 26.0, a - 0.38, a + 0.38, 10, red, 3.0, true))
	hud.add_child(aim_mark)
	# the reticle, in the middle of the screen; the hit marker on it
	reticle = Control.new()
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.size = Vector2(120, 120)
	reticle.position = Vector2(-60, -60)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.visible = false
	reticle.draw.connect(_draw_reticle)
	hud.add_child(reticle)
	# the safe radar (switched on from the phone): a disc on the left, a wedge pulsing toward the nearest safe
	radar = Control.new()
	radar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	radar.position = Vector2(30, 196)
	radar.size = Vector2(150, 176)
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar.visible = false
	radar.draw.connect(_draw_radar)
	hud.add_child(radar)
	# heists: the button by a safe, and the panel up top while one's on
	heist_btn = K.button("START HEIST", Color("ff4f6b"), Color("c23650"), 30, 300, 84, "lock")
	heist_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	heist_btn.position = Vector2(-150, -230)
	heist_btn.visible = false
	_tap(heist_btn, func(): game.heist.start())
	hud.add_child(heist_btn)
	shop_btn = K.button("ENTER", Color("5cc8ff"), Color("2f86b8"), 28, 380, 80, "home")
	shop_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	shop_btn.position = Vector2(-190, -230)
	shop_btn.visible = false
	_tap(shop_btn, func(): game.shops.enter())
	hud.add_child(shop_btn)
	atm_btn = K.button("BANK", Color("3fd26b"), Color("23934a"), 28, 380, 80, "coin")
	atm_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	atm_btn.position = Vector2(-190, -230)
	atm_btn.visible = false
	_tap(atm_btn, func(): game.bank.deposit())
	hud.add_child(atm_btn)
	heist_box = PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0.06, 0.055, 0.09, 0.72)
	hsb.set_corner_radius_all(22)
	hsb.border_color = Color(1, 1, 1, 0.18)
	hsb.set_border_width_all(1)
	hsb.content_margin_left = 22
	hsb.content_margin_right = 22
	hsb.content_margin_top = 10
	hsb.content_margin_bottom = 12
	heist_box.add_theme_stylebox_override("panel", hsb)
	heist_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	heist_box.position = Vector2(-190, 14)
	heist_box.custom_minimum_size = Vector2(380, 0)
	heist_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heist_box.visible = false
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 4)
	heist_box.add_child(hv)
	_heist_title = K.label("", 20, Color(1, 1, 1, 0.8), 650)
	hv.add_child(_heist_title)
	_heist_sub = K.label("", 34, Color.WHITE, 750)
	hv.add_child(_heist_sub)
	_heist_bar = K.bar(336, 8, Color("ffb347"), Color(1, 1, 1, 0.15))
	hv.add_child(_heist_bar)
	hud.add_child(heist_box)
	reset_hint = K.button("Stuck? Reset car", K.SUN, K.SUN_DK, 28, 0, 72, "home")
	reset_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reset_hint.position = Vector2(-160, 60)
	_tap(reset_hint, func():
		reset_hint.visible = false
		game.reset_car())
	reset_hint.visible = false
	hud.add_child(reset_hint)

## A big touch control. It isn't a Button: main reads touches on it directly, so several work at once.
## Each is drawn as what it is: see-through arrows to steer, a gas and a brake pedal, a handbrake lever,
## the nitrous canister (showing what's left in it) and the cruise control.
## The right thumb's cluster: the top-left (from the bottom right corner) of a button `size` across whose
## middle is `r` out from the main button's at `deg` (0 right, 90 down, 180 left, 270 up).
const CLUSTER := Vector2(-196, -186)
func _arc(deg: float, r: float, size: float) -> Vector2:
	return CLUSTER + Vector2.from_angle(deg_to_rad(deg)) * r - Vector2(size, size) * 0.5

func _pad(name: String, pos: Vector2, size: Vector2, left_side: bool, _col: Color) -> Control:
	var p := Control.new()
	if left_side:
		p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	else:
		p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	p.position = pos
	p.size = size
	p.custom_minimum_size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.pivot_offset = size * 0.5
	p.set_meta("on", false)
	p.set_meta("v", 1.0)
	p.draw.connect(func(): _draw_pad(p, name))
	hud.add_child(p)
	return p

## A fist, knuckles forward (empty hands: punching).
func _fist(c: Control, cc: Vector2, col: Color, k := 1.0) -> void:
	var r := Rect2(cc + Vector2(-17, -15) * k, Vector2(34, 26) * k)
	c.draw_rect(Rect2(r.position + Vector2(4, 0) * k, r.size - Vector2(8, 0) * k), col)
	c.draw_rect(Rect2(r.position + Vector2(0, 4) * k, r.size - Vector2(0, 8) * k), col)
	for i in 4:
		c.draw_circle(r.position + Vector2(4.5 + i * 8.3, 4.0) * k, 4.5 * k, col)
	# the fingers' creases and the thumb across the front
	var dk := Color(0.1, 0.08, 0.12, 0.55)
	for i in 3:
		var x := r.position.x + (8.5 + i * 8.3) * k
		c.draw_line(Vector2(x, r.position.y + 2.0 * k), Vector2(x, r.position.y + 12.0 * k), dk, 2.0 * k)
	c.draw_line(r.position + Vector2(3, 16) * k, r.position + Vector2(24, 16) * k, dk, 2.5 * k)
	c.draw_rect(Rect2(cc + Vector2(-10, 11) * k, Vector2(20, 9) * k), col)

## A pedal: a tall rounded slab of the smoked glass (the accent filling it while it's held).
func _pedal(c: Control, on: bool, accent: Color) -> Rect2:
	var r := Rect2(Vector2(4, 4), c.size - Vector2(8, 8))
	if on:
		r = r.grow(-3.0)
	var rad := minf(r.size.x, r.size.y) * 0.26
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0.2)
	sh.set_corner_radius_all(int(rad))
	sh.anti_aliasing = true
	c.draw_style_box(sh, Rect2(r.position + Vector2(0, 3), r.size))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent, 0.36) if on else Color(0.055, 0.05, 0.08, 0.5)
	sb.set_corner_radius_all(int(rad))
	sb.border_color = Color(accent, 0.95) if on else Color(1, 1, 1, 0.22)
	sb.set_border_width_all(2 if on else 1)
	sb.anti_aliasing = true
	c.draw_style_box(sb, r)
	c.draw_line(r.position + Vector2(rad, 6), Vector2(r.end.x - rad, r.position.y + 6), Color(1, 1, 1, 0.08), 3.0)
	return r

## A small caption in a pad (letter-spaced caps, quiet).
func _cap(c: Control, text: String, at: Vector2, col := Color(1, 1, 1, 0.72)) -> void:
	var f := K.font_spaced(700, 2)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	c.draw_string(f, at + Vector2(-w * 0.5, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

func _pad_text(c: Control, text: String, at: Vector2, size: int, col: Color) -> void:
	var f := K.font(750)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	c.draw_string_outline(f, at - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.35))
	c.draw_string(f, at - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _rrect(c: Control, r: Rect2, rad: float, fill: Color, border := Color.TRANSPARENT, bw := 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	c.draw_style_box(sb, r)

## A sticker: a shape with a thick ink outline and a soft offset shadow (the look of the whole HUD set).
func _sticker(c: Control, pts: PackedVector2Array, fill: Color, lift := 5.0, ink := 4.0) -> void:
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(q + Vector2(lift * 0.6, lift))
	c.draw_colored_polygon(sh, Color(0.05, 0.04, 0.03, 0.28))
	c.draw_colored_polygon(pts, fill)
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), K.STK_INK, ink, true)

## A rounded box as a polygon (so it can be a sticker).
func _rbox(r: Rect2, rad: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cs := [[r.position + Vector2(rad, rad), PI], [Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5],
		[r.end - Vector2(rad, rad), 0.0], [Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5]]
	for cc in cs:
		for k in 5:
			var a: float = float(cc[1]) + PI * 0.5 * k / 4.0
			out.append((cc[0] as Vector2) + Vector2(cos(a), sin(a)) * rad)
	return out

func _tag(c: Control, text: String, at: Vector2, size: int, bg: Color, fg := K.STK_INK) -> void:
	var f := K.font(750)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0
	_sticker(c, _rbox(Rect2(at - Vector2(w * 0.5, size * 0.75), Vector2(w, size * 1.3)), size * 0.45), bg, 3.0, 3.0)
	c.draw_string(f, at - Vector2(w * 0.5 - 8.0, -size * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fg)

## The on-foot controls and the door: discs of smoked glass with clean white line icons, no captions (the
## icons say it), the main one bigger with the accent round it (K.disc: the HUD's one button look).
func _draw_glass_disc(c: Control, r: float, on: bool, lit := true, accent := K.CORAL) -> Vector2:
	var cc := c.size * 0.5
	K.disc(c, cc, r, on, accent, lit)
	return cc

const _ICON_W := 3.2
func _chev(c: Control, at: Vector2, d: Vector2, w: float, h: float, col: Color, th := _ICON_W) -> void:
	var n := Vector2(-d.y, d.x)
	c.draw_polyline(PackedVector2Array([at - d * h * 0.5 + n * w * 0.5, at + d * h * 0.5, at - d * h * 0.5 - n * w * 0.5]), col, th, true)

func _draw_foot_pad(c: Control, name: String) -> void:
	var on: bool = c.get_meta("on")
	var w := Color(1, 1, 1, 0.94)
	var R := c.size.x * 0.46
	match name:
		"stick":
			var cc := c.size * 0.5
			var SR := c.size.x * 0.4
			c.draw_circle(cc, SR, Color(0.055, 0.05, 0.08, 0.26))
			c.draw_arc(cc, SR, 0, TAU, 72, Color(1, 1, 1, 0.16), 1.5, true)
			var kv: Vector2 = c.get_meta("knob", Vector2.ZERO)
			var kp := cc + Vector2(kv.x, -kv.y) * SR
			# (the way you're pushing: a lit arc on the rim)
			if kv.length() > 0.05:
				var ka := atan2(-kv.y, kv.x)
				c.draw_arc(cc, SR, ka - 0.5, ka + 0.5, 20, Color(K.CORAL, 0.9), 3.0, true)
			K.disc(c, kp, SR * 0.34, kv.length() > 0.05)
		"jump":
			var cc := _draw_glass_disc(c, R, on)
			_chev(c, cc + Vector2(0, -6), Vector2(0, -1), 28, 13, w)
			_chev(c, cc + Vector2(0, 8), Vector2(0, -1), 28, 13, Color(1, 1, 1, 0.45))
		"crouch":
			var lit: bool = c.get_meta("lit", false)
			var cc := _draw_glass_disc(c, R, on or lit)
			_chev(c, cc + Vector2(0, -6), Vector2(0, 1), 24, 11, w)
			c.draw_line(cc + Vector2(-13, 10), cc + Vector2(13, 10), w, _ICON_W, true)
		"sprint":
			var cc := _draw_glass_disc(c, R, on)
			_chev(c, cc + Vector2(-6, 0), Vector2(1, 0), 24, 11, w)
			_chev(c, cc + Vector2(7, 0), Vector2(1, 0), 24, 11, Color(1, 1, 1, 0.55))
		"fire":
			var cc := c.size * 0.5
			# the main button: bigger, a ring of the accent round it
			c.draw_arc(cc, R + 4.0, 0, TAU, 72, Color(K.CORAL, 0.55 if not on else 0.95), 3.0, true)
			K.disc(c, cc, R, on)
			if c.get_meta("fist", false):
				_fist(c, cc, w, 1.15)
			else:
				c.draw_arc(cc, 20.0, 0, TAU, 36, w, 3.0, true)
				for k in 4:
					var dv := Vector2.from_angle(TAU * k / 4.0)
					c.draw_line(cc + dv * 11.0, cc + dv * 30.0, w, 3.0, true)
				c.draw_circle(cc, 3.0, w)
		"block":
			# a shield; held: your guard's up
			var cc := _draw_glass_disc(c, R, on, true, Color("7fd6ff"))
			var sh := PackedVector2Array([cc + Vector2(0, -19), cc + Vector2(15, -13), cc + Vector2(14, 3), cc + Vector2(0, 19),
				cc + Vector2(-14, 3), cc + Vector2(-15, -13), cc + Vector2(0, -19)])
			c.draw_polyline(sh, w, _ICON_W, true)
			c.draw_line(cc + Vector2(0, -12), cc + Vector2(0, 12), Color(1, 1, 1, 0.45), 2.0, true)
		"swap":
			# the gun you've out (or a hand), its rounds under it; ticks round the rim: there's a wheel
			var cc := _draw_glass_disc(c, R, on)
			for k in 12:
				var dv := Vector2.from_angle(TAU * k / 12.0)
				c.draw_line(cc + dv * (R - 7.0), cc + dv * (R - 3.0), Color(1, 1, 1, 0.28), 2.0)
			var lines := String(c.get_meta("txt", "")).split("\n")
			var gid := String(c.get_meta("gid", "pistol"))
			if gid == "":
				_fist(c, cc + Vector2(0, -2), w, 0.8)
			else:
				gun_glyph(c, gid, cc + Vector2(0, -8), 22.0, w)
			if lines.size() > 1 and lines[1] != "":
				c.draw_string(K.font(650), cc + Vector2(-50, 24), lines[1], HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Color(1, 1, 1, 0.75))
		"aim":
			var lit: bool = c.get_meta("set", false)
			var cc := _draw_glass_disc(c, R, on or lit)
			for k in 4:
				var q := Vector2.from_angle(TAU * k / 4.0 + PI * 0.25) * 15.0
				var t := Vector2(-q.y, q.x).normalized()
				c.draw_polyline(PackedVector2Array([cc + q + t * 7.0, cc + q, cc + q - Vector2(q.x, 0).normalized() * 0.0 - t * 7.0]), w, 2.6, true)
			c.draw_circle(cc, 3.0, w)
		"reload":
			# round arrows; a ring fills while the new magazine goes in; it pulses when you're empty
			var empty: bool = c.get_meta("empty", false)
			var prog: float = c.get_meta("prog", 0.0)
			var cc := _draw_glass_disc(c, R, on)
			var rc := Color(1.0, 0.45, 0.6) if empty else w
			if empty:
				var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
				c.draw_arc(cc, R, 0, TAU, 48, Color(K.CORAL, 0.4 + 0.5 * pulse), 3.0, true)
			for half in 2:
				var a0 := -PI * 0.15 + half * PI
				c.draw_arc(cc, 14.0, a0, a0 + PI * 0.72, 16, rc, 2.8, true)
				var tip := a0 + PI * 0.72
				var tp := cc + Vector2(cos(tip), sin(tip)) * 14.0
				var tg := Vector2(-sin(tip), cos(tip))
				var nr := Vector2(cos(tip), sin(tip))
				c.draw_colored_polygon(PackedVector2Array([tp + tg * 6.0, tp + nr * 5.0, tp - nr * 5.0]), rc)
			if prog > 0.0:
				c.draw_arc(cc, R - 1.5, -PI * 0.5, -PI * 0.5 + TAU * prog, 48, K.CORAL, 4.0, true)
		"door":
			var foot: bool = c.get_meta("foot", false)
			var near: bool = c.get_meta("near", false)
			var steal: bool = c.get_meta("steal", false)
			var cc := _draw_glass_disc(c, R, on, not foot or near, Color("ff6b80") if steal else K.CORAL)
			# in the car: a door with an arrow out; on foot: a little car (and STEAL, if it isn't yours)
			if not foot:
				c.draw_rect(Rect2(cc + Vector2(-13, -15), Vector2(16, 30)), w, false, 2.8)
				c.draw_line(cc + Vector2(-1, 0), cc + Vector2(17, 0), w, 3.0, true)
				_chev(c, cc + Vector2(13, 0), Vector2(1, 0), 13, 7, w, 3.0)
			else:
				var cw := Color(1, 1, 1, 1.0 if near else 0.4)
				c.draw_rect(Rect2(cc + Vector2(-17, -1), Vector2(34, 11)), cw, false, 2.8)
				c.draw_polyline(PackedVector2Array([cc + Vector2(-10, -1), cc + Vector2(-5, -11), cc + Vector2(6, -11), cc + Vector2(11, -1)]), cw, 2.8, true)
				c.draw_circle(cc + Vector2(-9, 12), 3.5, cw)
				c.draw_circle(cc + Vector2(9, 12), 3.5, cw)
			if steal:
				_tag(c, "STEAL", cc + Vector2(0, R + 12), 12, Color("ff6b80"), Color.WHITE)

## Which piece of the button art a pad shows ("" none: the stick and the cruise button draw themselves).
func _pad_art(c: Control, name: String) -> String:
	match name:
		"fire":
			return "punch" if c.get_meta("fist", false) else "fire"
		"hand":
			return "drift"
		"door":
			return "enter" if c.get_meta("foot", false) else "exit"
		"stick", "cruise":
			return ""
	return name

func _draw_pad(c: Control, name: String) -> void:
	# the lo-fi hardware art (assets/ui/hud), and what it can't show on top: a reload filling, the NOS left,
	# the rounds in the gun, STEAL
	var an := _pad_art(c, name)
	var lit: bool = c.get_meta("on") or c.get_meta("lit", false) or c.get_meta("set", false)
	if an != "" and K.draw_art(c, Rect2(Vector2.ZERO, c.size), an, lit):
		var cc := c.size * 0.5
		var rr := minf(c.size.x, c.size.y) * 0.5
		match name:
			"reload":
				if c.get_meta("empty", false):
					var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
					c.draw_arc(cc, rr + 3.0, 0, TAU, 48, Color(K.CORAL, 0.35 + 0.5 * pulse), 3.0, true)
				var prog: float = c.get_meta("prog", 0.0)
				if prog > 0.0:
					c.draw_arc(cc, rr + 3.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 48, K.CORAL, 4.0, true)
			"nos":
				var v: float = c.get_meta("v")
				c.draw_arc(cc, rr + 3.0, 0, TAU, 64, Color(0, 0, 0, 0.35), 5.0, true)
				if v > 0.001:
					c.draw_arc(cc, rr + 3.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(v, 0.0, 1.0), 64, Color("4fb6ff"), 5.0, true)
			"swap":
				var lines := String(c.get_meta("txt", "")).split("\n")
				if lines.size() > 1 and lines[1] != "":
					_pad_text(c, lines[1], Vector2(cc.x, c.size.y + 14), 13, Color(1, 1, 1, 0.85))
			"door":
				if c.get_meta("steal", false):
					_tag(c, "STEAL", Vector2(cc.x, c.size.y + 10), 12, Color("ff6b80"), Color.WHITE)
				elif c.get_meta("foot", false) and not c.get_meta("near", false):
					pass
		return
	if name in FOOT_PADS or name == "door" or name == "block":
		_draw_foot_pad(c, name)
		return
	var s := c.size
	var on: bool = c.get_meta("on")
	match name:
		"left", "right":
			var d := -1.0 if name == "left" else 1.0
			var cc := s * 0.5
			K.disc(c, cc, minf(s.x, s.y) * 0.4, on)
			_chev(c, cc + Vector2(-5 * d, 0), Vector2(d, 0), 30, 14, Color(1, 1, 1, 0.94), 3.5)
			_chev(c, cc + Vector2(9 * d, 0), Vector2(d, 0), 30, 14, Color(1, 1, 1, 0.45), 3.5)
		"gas":
			var r := _pedal(c, on, Color("3fd26b"))
			for k in 3:
				_chev(c, r.get_center() + Vector2(0, 18 - k * 17), Vector2(0, -1), 34, 15, Color(1, 1, 1, 0.94 - k * 0.25), 3.6)
			_cap(c, "GAS", Vector2(r.get_center().x, r.end.y - 14))
		"brake":
			var r := _pedal(c, on, Color("ff5c7a"))
			c.draw_line(r.get_center() + Vector2(-18, -14), r.get_center() + Vector2(18, -14), Color(1, 1, 1, 0.94), 5.0, true)
			_chev(c, r.get_center() + Vector2(0, 4), Vector2(0, 1), 34, 15, Color(1, 1, 1, 0.94), 3.6)
			_chev(c, r.get_center() + Vector2(0, 20), Vector2(0, 1), 34, 15, Color(1, 1, 1, 0.5), 3.6)
			_cap(c, "BRAKE", Vector2(r.get_center().x, r.end.y - 14))
		"hand":
			# the handbrake: a slide (a sweeping arrow, its back end kicked out)
			var r := _pedal(c, on, Color("f2b84b"))
			var cc := r.get_center() + Vector2(0, -6)
			c.draw_arc(cc + Vector2(0, 10), 22.0, PI * 1.05, PI * 1.85, 18, Color(1, 1, 1, 0.94), 3.4, true)
			var tip := cc + Vector2(0, 10) + Vector2.from_angle(PI * 1.85) * 22.0
			_chev(c, tip + Vector2(2, 2), Vector2(0.6, 0.8).normalized(), 12, 7, Color(1, 1, 1, 0.94), 3.2)
			for k in 3:
				c.draw_line(cc + Vector2(-22 + k * 4, 14 + k * 5), cc + Vector2(-12 + k * 4, 14 + k * 5), Color(1, 1, 1, 0.4), 2.4, true)
			_cap(c, "DRIFT", Vector2(r.get_center().x, r.end.y - 12))
		"nos":
			# nitrous: a disc with what's left round its rim; armed, it glows blue
			var v: float = c.get_meta("v")
			var cc := s * 0.5
			var rr := minf(s.x, s.y) * 0.44
			var blue := Color("4fb6ff")
			if on:
				c.draw_circle(cc, rr + 10.0, Color(blue, 0.18))
			K.disc(c, cc, rr, on, blue)
			c.draw_arc(cc, rr + 5.0, PI * 0.5, PI * 0.5 + TAU, 64, Color(1, 1, 1, 0.12), 4.0, true)
			if v > 0.001:
				c.draw_arc(cc, rr + 5.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(v, 0.0, 1.0), 64, blue, 4.0, true)
			var f := K.font(800)
			var tw := f.get_string_size("NOS", HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			c.draw_string(f, cc + Vector2(-tw * 0.5, 4), "NOS", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.95))
			_cap(c, "ON" if on else "TAP", cc + Vector2(0, 22), Color(blue, 0.95) if on else Color(1, 1, 1, 0.45))
		"cruise":
			# a dash button with a little green LCD: the speed it's holding
			var r := minf(s.x, s.y) * 0.5 - 6
			var cc := s * 0.5
			var circ := PackedVector2Array()
			for k in 28:
				var a := TAU * k / 28.0
				circ.append(cc + Vector2(cos(a), sin(a)) * r)
			_sticker(c, circ, Color("e8dcc4") if on else K.STK_PAPER, 2.0 if on else 5.0)
			var lcd := Rect2(cc - Vector2(26, 16), Vector2(52, 26))
			_sticker(c, _rbox(lcd, 5), Color("1f3324"), 0.0, 3.0)
			var sv: float = c.get_meta("set", 0.0)
			var txt := str(int(sv)) if on else "SET"
			var f := K.font(800)
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			c.draw_string(f, Vector2(cc.x - tw * 0.5, cc.y + 3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("7dff9a") if on else Color("3f6b4a"))
			var f2 := K.font(750)
			var w2 := f2.get_string_size("CRUISE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			c.draw_string(f2, Vector2(cc.x - w2 * 0.5, cc.y + r - 8), "CRUISE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, K.STK_INK)

## The police, the way GTA does it: five stars under the minimap (none lit, none shown, till they're
## after you). The lit ones flash while they've lost sight of you and turn red as they box you in, and the
## minimap's rim flashes red and blue while they've got you. A line under the stars says what for, for a
## few seconds. No banners. And a speed limit sign by the speedo whenever a patrol car's about.
var wanted_why: Label
var _wanted_fade := 0.0      # (fading the stars out after you've lost them)
var _searching := false      # (the "searching" line's up)
var _wanted_shown := 0       # (stars lit last frame)
var _why_t := 0.0
var mini_ring: Panel
func _build_wanted() -> void:
	var box := HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.position = Vector2(-220, 296)
	box.size = Vector2(196, 40)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = false
	hud.add_child(box)
	wanted_box = box
	# (a dark pill behind them, so they read over a bright sky or the minimap)
	var back := Panel.new()
	back.add_theme_stylebox_override("panel", K.box(Color(0.08, 0.09, 0.12, 0.55), 20, 0, Color.TRANSPARENT, 0))
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.position = box.position
	back.size = box.size
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(back)
	hud.move_child(back, box.get_index())
	back.visible = false
	wanted_back = back
	for i in 5:
		var st := Icon.new("star", Color("ffd23f"), 34)
		st.pivot_offset = Vector2(17, 17)
		box.add_child(st)
		wanted_stars.append(st)
	wanted_why = K.outlined(K.label("", 16, Color.WHITE, 700), K.INK, 6)
	wanted_why.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	# (right-aligned under the stars and wrapping, so a long reason never runs off the edge)
	wanted_why.position = Vector2(-316, 338)
	wanted_why.size = Vector2(296, 24)
	wanted_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wanted_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wanted_why.visible = false
	hud.add_child(wanted_why)
	limit_sign = PanelContainer.new()
	var lsb := K.box(Color.WHITE, 40, 0, Color.TRANSPARENT, 0)
	lsb.border_color = Color("e0303e")
	lsb.set_border_width_all(9)
	limit_sign.add_theme_stylebox_override("panel", lsb)
	limit_sign.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	limit_sign.position = Vector2(118, -240)      # (above the condition bar, clear of it and of the pedals)
	limit_sign.size = Vector2(80, 80)
	limit_sign.custom_minimum_size = limit_sign.size
	limit_sign.pivot_offset = limit_sign.size * 0.5
	limit_sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	limit_sign.visible = false
	limit_lbl = K.label("50", 30, K.STK_INK, 800)
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

## Somebody's calling the police on you: the first star blinks, and a line says so.
func wanted_report(why: String) -> void:
	_wanted_fade = 0.0
	wanted_box.visible = true
	wanted_box.modulate = Color.WHITE
	var st: Control = wanted_stars[0]
	st.scale = Vector2.ONE * 1.6
	create_tween().tween_property(st, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	wanted_why.text = "Someone's calling the police"
	wanted_why.visible = true
	wanted_why.modulate.a = 1.0
	_why_t = 0.0

## A star more: it pops.
func wanted_up(h: int) -> void:
	if h >= 1 and h <= 5:
		var st: Control = wanted_stars[h - 1]
		st.scale = Vector2.ONE * 1.8
		create_tween().tween_property(st, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Lost them: the stars fade away, and a quiet note of the bounty.
func wanted_lost(bounty: int, _heat: int) -> void:
	_wanted_fade = 1.2
	toast("Lost the police  ·  +" + K.money(bounty), "coin", Color(0.12, 0.13, 0.16, 0.85), Color.WHITE, 2.4)

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
func _radar_tick(dt: float) -> void:
	var on: bool = radar_on and hud.visible and game.state == game.DRIVE and not game.heist.active()
	radar.visible = on
	if not on:
		return
	var yp: Vector3 = game.you().global_position
	var sf: Dictionary = game.heist.nearest_safe(yp)
	if sf.is_empty():
		radar.visible = false
		return
	var to: Vector3 = (sf["pos"] as Vector3) - yp
	_radar_d = Vector2(to.x, to.z).length()
	# its bearing, from the way the camera's looking (up on the disc: straight ahead)
	var cb: Basis = game.cam.global_transform.basis
	var f := Vector3(-cb.z.x, 0, -cb.z.z).normalized()
	var r := Vector3(cb.x.x, 0, cb.x.z).normalized()
	_radar_ang = lerp_angle(_radar_ang, atan2(to.dot(r), to.dot(f)), 1.0 - exp(-dt * 6.0))
	# a ping: slow when it's far, quick when it's close
	_ping_t -= dt
	if _ping_t <= 0.0:
		_ping_t = clampf(_radar_d / 160.0, 0.35, 2.4)
		radar.set_meta("ping", Time.get_ticks_msec() / 1000.0)
		game.sfx("hit_tick", -14.0 + clampf(1.0 - _radar_d / 300.0, 0.0, 1.0) * 6.0, 0.7)
	radar.queue_redraw()

func _draw_radar() -> void:
	var c := Vector2(75, 75)
	var R := 68.0
	radar.draw_circle(c, R, Color(0.06, 0.055, 0.09, 0.6))
	radar.draw_arc(c, R, 0, TAU, 48, Color(0.4, 1.0, 0.55, 0.35), 2.0, true)
	radar.draw_arc(c, R * 0.55, 0, TAU, 40, Color(0.4, 1.0, 0.55, 0.15), 1.5, true)
	# the pulse: a ring going out from the middle each ping
	var since: float = Time.get_ticks_msec() / 1000.0 - float(radar.get_meta("ping", 0.0))
	if since < 1.0:
		radar.draw_arc(c, R * since, 0, TAU, 40, Color(0.4, 1.0, 0.55, 0.6 * (1.0 - since)), 3.0, true)
	# the wedge: roughly that way (wide: it's a hint, not a pointer), brighter as you get closer
	var a := _radar_ang - PI * 0.5
	var spread := deg_to_rad(lerpf(32.0, 55.0, clampf(_radar_d / 400.0, 0.0, 1.0)))
	var k := clampf(1.0 - _radar_d / 400.0, 0.25, 1.0)
	var pts := PackedVector2Array([c])
	for i in 13:
		var t := a - spread + spread * 2.0 * i / 12.0
		pts.append(c + Vector2(cos(t), sin(t)) * R * 0.95)
	radar.draw_colored_polygon(pts, Color(0.4, 1.0, 0.55, (0.35 + 0.35 * maxf(1.0 - since, 0.0)) * k))
	radar.draw_circle(c, 5, Color.WHITE)
	var word := "Close" if _radar_d < 40.0 else ("Near" if _radar_d < 150.0 else "Far")
	var f := K.font(700)
	var tw := f.get_string_size("SAFE · " + word, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	radar.draw_string_outline(f, Vector2(75 - tw * 0.5, 168), "SAFE · " + word, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.5))
	radar.draw_string(f, Vector2(75 - tw * 0.5, 168), "SAFE · " + word, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("8ff0a4"))

## By a safe: the START HEIST button ("" hides it).
var shop_btn: Button          # at a shop's door: ENTER <the shop>
func shop_prompt(text: String) -> void:
	var on := text != "" and not overlay.visible
	if shop_btn.visible != on:
		shop_btn.visible = on
	if on and String(shop_btn.get_meta("t", "")) != text:
		shop_btn.set_meta("t", text)
		var l = shop_btn.get_meta("label") if shop_btn.has_meta("label") else null
		if l is Label:
			(l as Label).text = text
		else:
			shop_btn.text = text

var _bank_lbl: Label
var _bank_last := Vector2i(-1, -1)
## The pill: the cash on you, big (red-ish when there's a lot at risk), and BANK $x beside it.
func _bank_tick() -> void:
	if game.bank == null:
		return
	var k := Vector2i(game.bank.cash(), game.bank.banked())
	if k == _bank_last:
		return
	_bank_last = k
	coins_pill.get_meta("label").text = K.money(k.x)
	(coins_pill.get_meta("label") as Label).add_theme_color_override("font_color", Color("c0392b") if k.x >= 5000 else K.INK)
	_bank_lbl.text = "BANK\n" + K.money(k.y)

var atm_btn: Button           # at an ATM or a bank: BANK $<cash on you>
func atm_prompt(text: String) -> void:
	var on := text != "" and not overlay.visible and not shop_btn.visible
	if atm_btn.visible != on:
		atm_btn.visible = on
	if on and String(atm_btn.get_meta("t", "")) != text:
		atm_btn.set_meta("t", text)
		var l = atm_btn.get_meta("label") if atm_btn.has_meta("label") else null
		if l is Label:
			(l as Label).text = text
		else:
			atm_btn.text = text
	atm_btn.disabled = text.begins_with("Nothing")
	atm_btn.modulate.a = 0.6 if atm_btn.disabled else 1.0

func heist_prompt(text: String) -> void:
	heist_btn.visible = text != "" and not overlay.visible

## The heist panel: the step, the clock (or what's in the bag), a bar (frac < 0: none); red when it's urgent.
func heist_hud(title: String, sub: String, frac: float, alarm: bool) -> void:
	heist_box.visible = title != ""
	if title == "":
		return
	_heist_title.text = title.to_upper()
	_heist_sub.text = sub
	_heist_sub.add_theme_color_override("font_color", Color("ff6b80") if alarm else Color.WHITE)
	_heist_bar.visible = frac >= 0.0
	_heist_bar.value = clampf(frac, 0.0, 1.0)

## The money's home: HEIST COMPLETE, and the take.
func heist_done(amount: int) -> void:
	notice(func(): return _heist_card(amount), 3.2)

func _heist_card(amount: int) -> Dictionary:
	var lay := Control.new()
	lay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(lay)
	var big := K.outlined(K.label("HEIST COMPLETE", 88, Color("7be36b"), 800), Color(0.05, 0.06, 0.1), 16)
	big.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	big.position = Vector2(-500, -110)
	big.size = Vector2(1000, 120)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.pivot_offset = big.size * 0.5
	lay.add_child(big)
	var sub := K.outlined(K.label("+" + K.money(amount), 54, Color.WHITE, 800), Color(0.05, 0.06, 0.1), 10)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sub.position = Vector2(-300, 24)
	sub.size = Vector2(600, 70)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lay.add_child(sub)
	lay.modulate.a = 0.0
	big.scale = Vector2.ONE * 1.2
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lay, "modulate:a", 1.0, 0.35)
	tw.tween_property(big, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	lay.set_meta("out", func(t2: Tween):
		t2.tween_property(lay, "modulate:a", 0.0, 0.5))
	return {"node": lay, "tap": big}

func busted_fx(fine: int, word := "BUSTED", line := "") -> void:
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
	var big := K.outlined(K.label(word, 104, Color("eef0f3") if word == "BUSTED" else Color("ff4f6b"), 800), Color(0.05, 0.06, 0.1), 16)
	big.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	big.position = Vector2(-400, -110)
	big.size = Vector2(800, 140)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.pivot_offset = big.size * 0.5
	lay.add_child(big)
	var sub := K.outlined(K.label(line if line != "" else (("Fined " + K.money(fine)) if fine > 0 else "Let off with a warning"), 26, Color.WHITE, 700), Color(0.05, 0.06, 0.1), 8)
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
	_wanted_update2(pd, kmh)
	if wanted_back:
		wanted_back.visible = wanted_box.visible
		wanted_back.modulate = wanted_box.modulate

func _wanted_update2(pd: Dictionary, kmh: float) -> void:
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
				var lit := Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.3, 0.3), clampf(b * 1.3, 0.0, 1.0))
				st.modulate = Color(0.7, 0.7, 0.72, 0.55) if flash else lit
			else:
				st.modulate = Color(0.3, 0.3, 0.34, 0.6)
		# out of their sight: a line under the stars says they're searching, and how near you are to losing them
		if not bool(pd["seen"]) and _why_t <= 0.0:
			_searching = true
			wanted_why.visible = true
			wanted_why.modulate.a = 1.0
			wanted_why.text = "Out of sight · searching  %d%%" % int(clampf(float(pd.get("evade", 0.0)), 0.0, 1.0) * 100.0)
		elif _searching and bool(pd["seen"]):
			_searching = false
			wanted_why.visible = false
		# the minimap's rim: red and blue while they've got you; grey and white while they're looking
		var phase := fmod(now, 0.5) < 0.25
		if bool(pd["seen"]):
			_ring_col(Color("ff3044") if phase else Color("3a6bff"))
		else:
			_ring_col(Color("c9ccd4") if fmod(now, 0.9) < 0.45 else Color(1, 1, 1, 0.55))
	elif String(pd.get("report", "")) != "":
		# a call's been made (blinking: police on the way), or they're at the scene looking round
		var srch: bool = pd["report"] == "search"
		wanted_box.visible = true
		wanted_box.modulate.a = 1.0
		_wanted_fade = 1.2
		var on := fmod(now, 0.5 if srch else 0.9) < (0.25 if srch else 0.45)
		for i in 5:
			var st2: Control = wanted_stars[i]
			if i == 0:
				st2.modulate = (Color(1.0, 0.35, 0.35) if srch else Color.WHITE) if on else Color(0.5, 0.5, 0.55, 0.5)
			else:
				st2.modulate = Color(0.3, 0.3, 0.34, 0.6)
		_searching = true
		wanted_why.visible = true
		wanted_why.modulate.a = 1.0
		if srch:
			wanted_why.text = "Police are searching the area"
		else:
			wanted_why.text = "Someone's calling the police"
		if srch:
			_ring_col(Color("c9ccd4") if fmod(now, 0.9) < 0.45 else Color(1, 1, 1, 0.55))
	elif _wanted_fade > 0.0:
		if _searching:
			_searching = false
			wanted_why.visible = false
		_wanted_fade -= dt
		wanted_box.modulate.a = clampf(_wanted_fade / 1.2, 0.0, 1.0)
		if _wanted_fade <= 0.0:
			wanted_box.visible = false
		_ring_col(Color(1, 1, 1, 0.55))
	else:
		wanted_box.visible = false
		_ring_col(Color(1, 1, 1, 0.55))
	if _why_t > 0.0:
		_why_t -= dt
		wanted_why.modulate.a = clampf(_why_t / 0.6, 0.0, 1.0)
		if _why_t <= 0.0 or heat == 0:
			wanted_why.visible = false
			_why_t = 0.0
	var lim := int(pd.get("limit", 0))
	limit_sign.visible = false      # (the speedo turns red instead)
	if limit_sign.visible:
		limit_lbl.text = str(lim)
		var over := kmh > lim + 10.0
		limit_sign.scale = Vector2.ONE * ((1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.02)) if over else 1.0)
		limit_lbl.add_theme_color_override("font_color", Color("e0303e") if over else K.STK_INK)

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
		var r := 172.0
		# the art: a carbon-fibre sports wheel, turned with you (its middle down at the bottom of the screen)
		var wt: Array = K.art("wheel")
		if not wt.is_empty():
			var tex: Texture2D = wt[0]
			var dd := r / 0.45
			wheel.draw_set_transform(c, a, Vector2.ONE)
			wheel.draw_texture_rect(tex, Rect2(Vector2(-dd, -dd * tex.get_height() / tex.get_width()) * 0.5, Vector2(dd, dd * tex.get_height() / tex.get_width())), false)
			wheel.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if on:
				wheel.draw_arc(c, dd * 0.5 - 3.0, PI + a - 0.2, TAU + a + 0.2, 64, Color(K.CORAL, 0.55), 3.0, true)
			return
		var glass := Color(0.055, 0.05, 0.08, 0.62 if on else 0.5)
		var edge := Color(1, 1, 1, 0.3 if on else 0.2)
		# the rim (the top half, turned): a band of smoked glass with a hairline either side
		wheel.draw_arc(c, r, PI + a - 0.15, TAU + a + 0.15, 56, Color(0, 0, 0, 0.18), 30.0, true)
		wheel.draw_arc(c, r, PI + a - 0.13, TAU + a + 0.13, 56, glass, 26.0, true)
		wheel.draw_arc(c, r + 13.0, PI + a - 0.13, TAU + a + 0.13, 56, edge, 1.5, true)
		wheel.draw_arc(c, r - 13.0, PI + a - 0.13, TAU + a + 0.13, 56, edge, 1.5, true)
		# spokes and the hub
		for sp_a in [a - 0.38, a + PI + 0.38]:
			var dirv := Vector2.from_angle(sp_a)
			wheel.draw_line(c + dirv * 44.0, c + dirv * (r - 13.0), glass, 12.0, true)
		K.disc(wheel, c, 44.0, on)
		# the mark at the top, so you can see how far it's turned
		var top := c + Vector2.from_angle(-PI * 0.5 + a) * r
		wheel.draw_circle(top, 8.0, K.CORAL))
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
	# (only the wheel when you're driving: on foot it's hidden, and its patch of screen is the walk stick's)
	if wheel_mode() and not foot_mode and wheel.visible and wheel.get_global_rect().grow(16).has_point(pos):
		var hub := wheel.get_global_rect().position + _wheel_hub()
		if pos.distance_to(hub) < 250.0:
			return "wheel"
	if not foot_mode and speedo.visible and speedo.get_global_rect().grow(12).has_point(pos):
		return "cruise"         # (tap the speedo: cruise control)
	for k in (["door", "fire", "block", "reload", "swap", "jump", "sprint", "crouch", "stick"] if foot_mode else ["rewind", "door", "nos", "cruise", "hand", "gas", "brake", "left", "right"]):
		var c: Control = ctl[k]
		if not c.visible:
			continue
		if c.get_global_rect().grow(14 if k == "nos" else (60 if k == "stick" else 22)).has_point(pos):
			return k
	return ""

## On foot or back in the car: which controls are up.
func set_foot(on: bool) -> void:
	foot_mode = on
	for k in ["gas", "brake", "hand", "nos", "rewind", "left", "right"]:
		ctl[k].visible = not on
	ctl["cruise"].visible = false        # (never a button: tap the speedo)
	if on:
		wheel.visible = false
	else:
		wheel.visible = wheel_mode()
		ctl["left"].visible = not wheel_mode()
		ctl["right"].visible = not wheel_mode()
	for k in FOOT_PADS:
		ctl[k].visible = on
	aim_mark.visible = false
	reticle.visible = false
	speedo.visible = not on
	if on:
		limit_sign.visible = false
	ctl["door"].set_meta("foot", on)
	ctl["block"].visible = false
	ctl["block"].set_meta("want", false)
	if not on:
		if melee_mark:
			melee_mark.visible = false
		ctl["door"].set_meta("want", true)
		ctl["door"].visible = true
		ctl["door"].modulate.a = 1.0
		ctl["door"].scale = Vector2.ONE
		_social_prompt({})
	# in the car, EXIT sits up top by the phone; on foot ENTER's down by your thumb
	if on:
		_place(ctl["door"], Control.PRESET_BOTTOM_RIGHT, _arc(135, 152, 92))      # (on foot: down by your thumb, below-left of the main button)
	else:
		_place(ctl["door"], Control.PRESET_TOP_RIGHT, Vector2(-404, 80))
	group_btn.position = Vector2(-376, 94) if on else Vector2(-480, 94)
	ctl["door"].queue_redraw()

## A pad that comes and goes: it pops up when it's wanted, fades away when it's not.
func _pop(c: Control, want: bool) -> void:
	if bool(c.get_meta("want", c.visible)) == want:
		return
	c.set_meta("want", want)
	if c.has_meta("tw"):
		var old = c.get_meta("tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	c.set_meta("tw", tw)
	if want:
		c.visible = true
		c.modulate.a = 0.0
		c.scale = Vector2(0.6, 0.6)
		tw.set_parallel(true)
		tw.tween_property(c, "modulate:a", 1.0, 0.14)
		tw.tween_property(c, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tw.set_parallel(true)
		tw.tween_property(c, "modulate:a", 0.0, 0.16)
		tw.tween_property(c, "scale", Vector2(0.8, 0.8), 0.16)
		tw.chain().tween_callback(func(): c.visible = false)

## A street fight's count-in: 3, 2, 1, FIGHT! big in the middle, each one punching in.
func fight_count() -> void:
	var words := ["3", "2", "1", "FIGHT!"]
	for i in words.size():
		var w: String = words[i]
		get_tree().create_timer(0.62 * i, false).timeout.connect(func():
			var l := K.outlined(K.label(w, 120 if w.length() < 2 else 96, Color("ffd34d") if w.length() > 1 else Color.WHITE, 800), K.SHADE, 16)
			l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			l.size = Vector2(600, 160)
			l.position = _vs() * 0.5 - l.size * 0.5 - Vector2(0, 60)
			l.pivot_offset = l.size * 0.5
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			popups.add_child(l)
			l.scale = Vector2(1.8, 1.8)
			l.modulate.a = 0.0
			var tw := l.create_tween()
			tw.set_parallel(true)
			tw.tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(l, "modulate:a", 1.0, 0.1)
			tw.chain().tween_interval(0.25 if w.length() < 2 else 0.6)
			tw.chain().tween_property(l, "modulate:a", 0.0, 0.18)
			tw.chain().tween_callback(l.queue_free)
			game.sfx("punch_heavy" if w.length() > 1 else "bonk", -6.0 if w.length() > 1 else -10.0, 1.0 if w.length() > 1 else 1.3))

## Squared up to someone: a small red chevron over their head (who your punches go to).
var melee_mark: Control
func _melee_mark_tick() -> void:
	if melee_mark == null:
		melee_mark = Control.new()
		melee_mark.size = Vector2(60, 34)
		melee_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		melee_mark.draw.connect(func():
			# their fight left (someone fighting you), then the chevron
			var hpk: float = melee_mark.get_meta("hp", -1.0)
			var nm: String = melee_mark.get_meta("name", "")
			if nm != "":
				melee_mark.draw_string(K.font(700), Vector2(-70, -6), nm, HORIZONTAL_ALIGNMENT_CENTER, 200, 16, Color.WHITE)
			if hpk >= 0.0:
				melee_mark.draw_rect(Rect2(4, 0, 52, 7), Color(0.05, 0.04, 0.07, 0.75))
				melee_mark.draw_rect(Rect2(5, 1, 50.0 * hpk, 5), Color("ff4f6b").lerp(Color("ffd34d"), clampf(hpk * 1.3 - 0.3, 0.0, 1.0)))
				# their stamina under it (orange: spent, your opening)
				var sk: float = melee_mark.get_meta("sta", -1.0)
				if sk >= 0.0:
					melee_mark.draw_rect(Rect2(4, 7, 52, 5), Color(0.05, 0.04, 0.07, 0.75))
					melee_mark.draw_rect(Rect2(5, 8, 50.0 * sk, 3), Color("ff8c42") if melee_mark.get_meta("spent", false) else Color("7fd6ff"))
			var pts := PackedVector2Array([Vector2(18, 12), Vector2(42, 12), Vector2(30, 30)])
			melee_mark.draw_colored_polygon(pts, Color("ff4f6b"))
			melee_mark.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.1, 0.05, 0.08, 0.8), 2.0, true))
		hud.add_child(melee_mark)
	var p: Vector3 = game.melee.focus() if game.gunplay.holstered else Vector3.INF
	var cam: Camera3D = game.cam
	if p == Vector3.INF or cam.is_position_behind(p + Vector3(0, 2.1, 0)):
		melee_mark.visible = false
		return
	var sp := cam.unproject_position(p + Vector3(0, 2.15, 0))
	melee_mark.visible = true
	melee_mark.position = sp - Vector2(30, 32) + Vector2(0, sin(Time.get_ticks_msec() * 0.006) * 3.0)
	var hpk: float = game.melee.focus_hp()
	var nm: String = game.melee.focus_name()
	var stk: float = game.melee.focus_sta()
	var spk: bool = game.melee.focus_spent()
	if absf(float(melee_mark.get_meta("sta", -2.0)) - stk) > 0.01 or bool(melee_mark.get_meta("spent", false)) != spk:
		melee_mark.set_meta("sta", stk)
		melee_mark.set_meta("spent", spk)
		melee_mark.queue_redraw()
	if absf(float(melee_mark.get_meta("hp", -2.0)) - hpk) > 0.005 or String(melee_mark.get_meta("name", "")) != nm:
		melee_mark.set_meta("hp", hpk)
		melee_mark.set_meta("name", nm)
		melee_mark.queue_redraw()

## By someone you could talk to: GREET and TAUNT, low in the middle.
var social_box: HBoxContainer
func _social_prompt(pr: Dictionary) -> void:
	if social_box == null:
		social_box = HBoxContainer.new()
		social_box.add_theme_constant_override("separation", 14)
		social_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		social_box.position = Vector2(-150, -150)
		social_box.size = Vector2(300, 64)
		social_box.alignment = BoxContainer.ALIGNMENT_CENTER
		hud.add_child(social_box)
		var g := K.round_button("person", K.PAPER, K.LINE, 84)
		K.set_art(g, "greet")
		_tap(g, func(): game.melee.greet())
		social_box.add_child(g)
		var t := K.round_button("target", K.PAPER, K.LINE, 84)
		K.set_art(t, "taunt")
		_tap(t, func(): game.melee.taunt())
		social_box.add_child(t)
		social_box.visible = false
		social_box.set_meta("want", false)
	_pop(social_box, not pr.is_empty() and foot_mode)

## A control moved to `pos` from the corner `preset` names (its size kept).
func _place(c: Control, preset: int, pos: Vector2) -> void:
	var sz := c.size
	c.set_anchors_preset(preset)
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y

## Where a finger on the stick pushes it: x right, y forward, up to 1.
func stick_vec(pos: Vector2) -> Vector2:
	var r := (ctl["stick"] as Control).get_global_rect()
	var d := (pos - r.get_center()) / (r.size.x * 0.42)
	return Vector2(d.x, -d.y).limit_length(1.0)

## The HUD while you're on foot: the minimap round you, the clock, coins; the door lit when you're by the car.
func foot_hud(p: Vector3, yaw: float, clock: String, coins: int, near: bool) -> void:
	_minimap_tick(p, yaw)
	if bool(game.save.setting("clock")):
		clock_lbl.text = clock
	if coins != _last_coins:
		_last_coins = coins
		coins_pill.get_meta("label").text = K.money(coins)
	_bank_tick()
	var dc: Control = ctl["door"]
	var steal: bool = near and game.near_kind() == "steal"
	if bool(dc.get_meta("near", false)) != near or bool(dc.get_meta("steal", false)) != steal:
		dc.set_meta("near", near)
		dc.set_meta("steal", steal)
		dc.queue_redraw()
	# ENTER only comes up by a car (a pop in, a fade out); BLOCK only in a fight; RELOAD only with a gun out
	_pop(dc, near)
	var gp0 = game.gunplay
	_pop(ctl["block"], gp0.holstered and game.melee.in_fight() and not gp0.dying)
	ctl["reload"].visible = not gp0.holstered
	var fc: Control = ctl["fire"]
	if bool(fc.get_meta("fist", false)) != gp0.holstered:
		fc.set_meta("fist", gp0.holstered)
		fc.queue_redraw()
	_social_prompt(game.melee.social)
	_melee_mark_tick()
	(ctl["stick"] as Control).set_meta("knob", game.stick)
	ctl["stick"].queue_redraw()
	var gp = game.gunplay
	_gauge_set(hp_g, gp.hp / gp.MAX_HP)
	sta_g.visible = true
	cond_g.visible = false          # (on foot: your stamina where the car's condition was)
	var spent: bool = game.foot.sta["spent"]
	if bool(sta_g.get_meta("spent", false)) != spent:
		sta_g.set_meta("spent", spent)
		(sta_g.get_meta("bar") as Control).queue_redraw()
	_gauge_set(sta_g, float(game.foot.sta["v"]) / 100.0)
	var sw: Control = ctl["swap"]
	var gtxt: String = ("Hands" if gp.holstered else String(gp.weapon.get("name", ""))) + "\n" + ("" if gp.holstered else gp.ammo_text())
	if String(sw.get_meta("txt", "")) != gtxt:
		sw.set_meta("txt", gtxt)
		sw.set_meta("gid", "" if gp.holstered else String(gp.weapon.get("id", "pistol")))
		sw.queue_redraw()
	var rl: Control = ctl["reload"]
	var prog: float = 0.0
	if gp.reload_t > 0.0 and not gp.weapon.is_empty():
		prog = 1.0 - gp.reload_t / float(gp.weapon["reload"])
	var empty: bool = not gp.holstered and not gp.weapon.is_empty() and int(gp.ammo.get(gp.weapon["id"], 1)) <= 0 and gp.reload_t <= 0.0
	if prog != float(rl.get_meta("prog", 0.0)) or empty or bool(rl.get_meta("empty", false)) != empty:
		rl.set_meta("prog", prog)
		rl.set_meta("empty", empty)
		rl.queue_redraw()
	# (no ring round whoever you're locked on to: the soft lock still works, and the dot goes red)
	aim_mark.visible = false
	_hit_t = maxf(0.0, _hit_t - get_process_delta_time())
	reticle.visible = gp.aim_k > 0.05 or _hit_t > 0.0
	reticle.modulate.a = clampf(gp.aim_k * 1.4, 0.0, 1.0) if _hit_t <= 0.0 else 1.0
	reticle.queue_redraw()
	_wanted_update(game.police.hud(), 0.0)        # (the stars and the searching line, on foot too)
	pressed_controls(game.held)

## A shot landed: a mark on the crosshair. kind: hit (white), head (amber, a ring), kill (red, bigger),
## sever (red, a burst).
var _hit_kind := "hit"
const HIT_T := {"hit": 0.16, "head": 0.3, "kill": 0.36, "sever": 0.42}
func hitmark(kind: String) -> void:
	# (a kill or a limb outranks a plain hit landing in the same instant)
	if _hit_t > 0.0 and HIT_T.get(_hit_kind, 0.0) > HIT_T.get(kind, 0.0) and kind == "hit":
		return
	_hit_kind = kind
	_hit_t = HIT_T.get(kind, 0.2)
	_hit_kill = kind == "kill" or kind == "sever"

func hit_marker(kill: bool) -> void:
	hitmark("kill" if kill else "hit")

## The crosshair: three ticks round a dot (top, and either side below), spreading with the bloom (moving,
## firing, the kick) and drawing in as you steady; red when it's locked on someone.
func _draw_reticle() -> void:
	var gp = game.gunplay
	var c := Vector2(60, 60)
	var locked: bool = gp.lock_pos != Vector3.INF
	var col := Color(1.0, 0.3, 0.4, 0.95) if locked else Color(1, 1, 1, 0.94)
	var ink := Color(0, 0, 0, 0.5)
	var gap: float = 7.0 + gp.spread_k() * 26.0
	for k in 3:
		var a := -PI * 0.5 + TAU * k / 3.0
		var dv := Vector2(cos(a), sin(a))
		var p0 := c + dv * gap
		var p1 := c + dv * (gap + 11.0)
		reticle.draw_line(p0, p1, ink, 6.0, true)
		reticle.draw_line(p0, p1, col, 3.0, true)
	reticle.draw_circle(c, 3.2, ink)
	reticle.draw_circle(c, 2.0, col)
	if _hit_t > 0.0:
		var t: float = _hit_t / float(HIT_T.get(_hit_kind, 0.2))
		var hc := Color(1, 1, 1, t)
		match _hit_kind:
			"head":
				hc = Color(1.0, 0.72, 0.2, t)
				reticle.draw_arc(c, 18.0 + (1.0 - t) * 14.0, 0, TAU, 32, Color(1.0, 0.72, 0.2, t * 0.8), 2.5, true)
			"kill":
				hc = Color(1.0, 0.18, 0.25, t)
			"sever":
				hc = Color(1.0, 0.12, 0.2, t)
				for k in 8:
					var sa := TAU * k / 8.0
					var sv := Vector2(cos(sa), sin(sa))
					reticle.draw_circle(c + sv * (20.0 + (1.0 - t) * 22.0), 3.0 * t + 0.5, Color(0.85, 0.05, 0.1, t))
		var big := _hit_kind != "hit"
		var r0 := 8.0 + (1.0 - t) * 5.0
		var r1 := r0 + (15.0 if big else 9.0)
		for k in 4:
			var a := TAU * k / 4.0 + PI * 0.25
			var dv := Vector2(cos(a), sin(a))
			reticle.draw_line(c + dv * r0, c + dv * r1, Color(0, 0, 0, 0.5 * t), 6.5 if big else 5.5, true)
			reticle.draw_line(c + dv * r0, c + dv * r1, hc, 3.5 if big else 2.6, true)

func pressed_controls(held: Dictionary) -> void:
	for k in ctl:
		var c: Control = ctl[k]
		var on: bool = held.get(k, false)
		# (the nitrous and the cruise control show whether they're switched on, not your finger)
		if k == "nos":
			on = game.nos_toggle
		elif k == "cruise":
			on = game.cruise_on
			c.set_meta("set", game.cruise_v * 3.6)
		if k == "rewind":
			c.scale = c.scale.lerp(Vector2.ONE * (0.93 if on else 1.0), 0.5)
			c.modulate = Color(1.15, 1.15, 1.15, 1.0) if on else Color(1, 1, 1, 0.9)
		elif c.has_meta("on") and bool(c.get_meta("on")) != on:
			c.set_meta("on", on)
			c.queue_redraw()

## A slim level bar with its icon (fuel, condition, health), side by side up in the top right.
func _gauge(icon: String, row: HBoxContainer) -> Control:
	var g := HBoxContainer.new()
	g.add_theme_constant_override("separation", 4)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Icon.new(icon, Color.WHITE, 26)
	g.add_child(ic)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(52, 26)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(bar)
	g.set_meta("v", 1.0)
	g.set_meta("bar", bar)
	bar.draw.connect(func():
		var v: float = g.get_meta("v")
		var r := Rect2(Vector2(0, 9), Vector2(bar.size.x, 9))
		bar.draw_rect(r.grow(2), Color(0.06, 0.055, 0.09, 0.55))
		var col := (Color("ff6b80") if icon == "heart" else Color("eef0f3")) if v > 0.35 else (Color("f2b84b") if v > 0.15 else Color("ef4f55"))
		if icon == "wind":
			col = Color("ff8c42") if g.get_meta("spent", false) else Color("7fd6ff")
		bar.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(v, 0.0, 1.0), r.size.y)), col))
	row.add_child(g)
	return g

func _gauge_set(g: Control, v: float) -> void:
	if absf(float(g.get_meta("v")) - v) > 0.002:
		g.set_meta("v", v)
		(g.get_meta("bar") as Control).queue_redraw()

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
	st_fuel_btn.text = "Full" if full else ("Fill up · " + K.money(fuel_cost))
	st_fuel_btn.disabled = full
	var fixed := damage < 0.5
	st_cond_btn.text = "Like new" if fixed else ("Repair · " + K.money(repair_cost))
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
	var wm := wheel_mode() and not foot_mode
	wheel.visible = wm
	ctl["left"].visible = not wm and not foot_mode
	ctl["right"].visible = not wm and not foot_mode
	if wm:
		wheel.set_meta("a", float(d.get("wheel", 0.0)) * game.WHEEL_MAX)     # (turned with the finger)
		wheel.set_meta("on", game.wheel_idx >= 0)
		wheel.queue_redraw()
	_wanted_update(d.get("police", {}), float(d["kmh"]))
	var nc: Control = ctl["nos"]
	nc.visible = not foot_mode and bool(d.get("nos_has", true))      # (a car off the street has no nitrous)
	if absf(float(nc.get_meta("v")) - float(d.get("nos", 1.0))) > 0.01:
		nc.set_meta("v", float(d.get("nos", 1.0)))
		nc.queue_redraw()
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
	_gauge_set(fuel_g, fv)
	_gauge_set(cond_g, cv)
	_gauge_set(hp_g, game.gunplay.hp / game.gunplay.MAX_HP)
	sta_g.visible = false
	cond_g.visible = true
	_clock_dot.visible = clock_lbl.text != ""
	# over the limit: the speedo goes red (no separate sign)
	var lim: int = game.police.limit
	var kmh := absf(game.car.speed) * 3.6
	speed_lbl.add_theme_color_override("font_color", Color("ff4f5e") if lim > 0 and kmh > lim + 3 else Color.WHITE)
	cruise_lbl.text = ("CRUISE %d" % int(round(game.cruise_v * 3.6))) if game.cruise_on else ""
	place_lbl.text = d["place"]
	if int(d["coins"]) != _last_coins:
		_last_coins = int(d["coins"])
		coins_pill.get_meta("label").text = K.money(_last_coins)
	_bank_tick()
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
		if t["kind"] == "time" or t["kind"] == "crawl":
			chal_main.text = "%.1f s" % (float(d["trial_t"]) + (game.crawl_pen if t["kind"] == "crawl" else 0.0))
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
	angle_lbl.text = ("+" + K.money(coins)) if coins > 0 else "nice!"
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
	if popups.get_child_count() >= 2:
		return              # (two at a time is plenty)
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

# ------------------------------------------------------------------ your level

var lvl_badge: Control
var _lvl := -1                 # the level shown
var _lvl_k := 0.0              # the ring, eased toward how far into the level you are
var _lvl_want := 0.0
var _lvl_xp := -1              # total XP last looked at
var _lvl_t := 0.0
var _xp_pending := 0           # XP gained lately, shown as one "+N XP" once it settles
var _xp_pend_t := 0.0

func _process(dt: float) -> void:
	_cine_t = maxf(0.0, _cine_t - dt)
	if game == null or game.save == null or lvl_badge == null:
		return
	_lvl_t -= dt
	if _lvl_t <= 0.0:
		_lvl_t = 0.25
		var pr: Array = Progress.progress(game.save)
		var x: int = pr[3]
		if _lvl < 0:
			_lvl = int(pr[0])
			_lvl_xp = x
			_lvl_k = float(pr[1]) / float(pr[2])
		elif x > _lvl_xp:
			_xp_pending += x - _lvl_xp
			_xp_pend_t = 0.6
			_lvl_xp = x
		if int(pr[0]) != _lvl:
			_lvl = int(pr[0])
			_lvl_k = 0.0
		_lvl_want = float(pr[1]) / float(pr[2])
	if _xp_pend_t > 0.0:
		_xp_pend_t -= dt
		if _xp_pend_t <= 0.0 and _xp_pending >= 5 and hud.visible:
			_xp_pop(_xp_pending)
			_xp_pending = 0
	var k := move_toward(_lvl_k, _lvl_want, dt * 0.8)
	if absf(k - _lvl_k) > 0.0005:
		_lvl_k = k
		lvl_badge.queue_redraw()

func _draw_lvl_badge() -> void:
	var c := lvl_badge.size * 0.5
	var R := 21.0
	lvl_badge.draw_circle(c, R, Color(0, 0, 0, 0.45))
	lvl_badge.draw_arc(c, R - 2.5, 0, TAU, 48, Color(1, 1, 1, 0.16), 4.0, true)
	if _lvl_k > 0.002:
		lvl_badge.draw_arc(c, R - 2.5, -PI * 0.5, -PI * 0.5 + TAU * clampf(_lvl_k, 0.0, 1.0), 48, Color("ffd34d"), 4.5, true)
	var f := K.font(800)
	var txt := str(maxi(_lvl, 1))
	var fs := 22 if txt.length() < 2 else 19
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	lvl_badge.draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

## "+120 XP" floating up off the badge.
func _xp_pop(n: int) -> void:
	var l := K.outlined(K.label("+%s XP" % K.fmt(n), 20, Color("ffd34d"), 800, HORIZONTAL_ALIGNMENT_LEFT), K.SHADE, 6)
	hud.add_child(l)
	l.global_position = lvl_badge.global_position + Vector2(-4, 46)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 26.0, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.9)
	tw.chain().tween_callback(l.queue_free)

## Level up: a card in the middle of the screen. The level number bursts in, then what you got (the cash,
## a pack of car cards) and anything that's opened up with it.
func level_up(lv: int, cash: int, unlocks: Array) -> void:
	notice(func(): return _level_card(lv, cash, unlocks), 3.6 + 0.4 * mini(unlocks.size(), 4))

func _level_card(lv: int, cash: int, unlocks: Array) -> Dictionary:
	lvl_badge.scale = Vector2.ONE * 1.6
	var bt := lvl_badge.create_tween()
	bt.tween_property(lvl_badge, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", K.box(Color(0.06, 0.055, 0.09, 0.9), 30, 0, Color.TRANSPARENT, 26))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)
	vb.add_child(K.label("LEVEL UP", 22, Color("ffd34d"), 800))
	var big := K.label(str(lv), 96, Color.WHITE, 800)
	big.pivot_offset = Vector2(60, 60)
	vb.add_child(big)
	var rw := HBoxContainer.new()
	rw.alignment = BoxContainer.ALIGNMENT_CENTER
	rw.add_theme_constant_override("separation", 12)
	vb.add_child(rw)
	rw.add_child(_reward_chip("coin", "+" + K.money(cash), Color("3fd26b")))
	rw.add_child(_reward_chip("star", "Card pack", Color("ffb020")))
	var shown := 0
	for u in unlocks:
		if shown >= 4:
			vb.add_child(K.label("and %d more in the shops" % (unlocks.size() - shown), 17, Color(1, 1, 1, 0.6), 600))
			break
		var hb := HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", 8)
		hb.add_child(Icon.new(String(u[0]), Color("ffd34d"), 24))
		hb.add_child(K.label("Unlocked: " + String(u[1]), 19, Color.WHITE, 650))
		vb.add_child(hb)
		shown += 1
	card.reset_size()
	var vs := _vs()
	card.position = Vector2((vs.x - card.size.x) * 0.5, vs.y * 0.3)       # (below where friends' texts come in)
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2.ONE * 0.6
	card.modulate.a = 0.0
	big.pivot_offset = big.size * 0.5
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_notice_x(card)
	root.set_meta("out", func(t2: Tween):
		t2.tween_property(root, "modulate:a", 0.0, 0.3))
	big.scale = Vector2.ONE * 2.2
	var tb := big.create_tween()
	tb.tween_property(big, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT).set_delay(0.12)
	# a burst of confetti behind it
	for i in 36:
		var bit := ColorRect.new()
		bit.color = [Color("ffd34d"), Color("ff5c8a"), Color("5cc8ff"), Color("3fd26b"), Color.WHITE][i % 5]
		bit.size = Vector2(randf_range(6, 12), randf_range(10, 18))
		bit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bit)
		root.move_child(bit, 0)
		var from := Vector2(vs.x * 0.5, vs.y * 0.32)
		bit.position = from
		bit.pivot_offset = bit.size * 0.5
		var a := randf() * TAU
		var to := from + Vector2(cos(a), sin(a) * 0.7) * randf_range(180, 520) + Vector2(0, 140)
		var ct := bit.create_tween()
		ct.set_parallel(true)
		ct.tween_property(bit, "position", to, randf_range(1.0, 1.6)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ct.tween_property(bit, "rotation", randf_range(-8, 8), 1.6)
		ct.tween_property(bit, "modulate:a", 0.0, 0.6).set_delay(1.0)
	return {"node": root, "tap": card}

func _reward_chip(icon: String, text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", K.box(Color(col, 0.22), 20, 0, Color.TRANSPARENT, 10))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	p.add_child(hb)
	hb.add_child(Icon.new(icon, col, 24))
	hb.add_child(K.label(text, 20, Color.WHITE, 700))
	return p

# ------------------------------------------------------------------ the story

var goal_lbl: Label

## What you're meant to be doing: a line under where you are, top left.
# ------------------------------------------------------------------ the first ride's coach (tutorial.gd)

var coach_ui: Control

func coach(t: String, how: String, target: Variant, k: int, n: int, final := false) -> void:
	if coach_ui == null:
		coach_ui = preload("res://scripts/ui/coach.gd").new(self)
		add_child(coach_ui)
	if goal_lbl != null:
		goal_lbl.visible = false        # (the coach says what to do: no goal line as well)
	coach_ui.show_step(t, how, target, k, n, final)

func coach_done() -> void:
	if coach_ui != null:
		coach_ui.done_flash()

func coach_hide() -> void:
	if coach_ui != null:
		coach_ui.hide_all()

func story_goal(text: String) -> void:
	if goal_lbl == null:
		goal_lbl = K.outlined(K.label("", 18, Color("ffd34d"), 700, HORIZONTAL_ALIGNMENT_LEFT), K.SHADE, 6)
		goal_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goal_lbl.custom_minimum_size = Vector2(380, 0)
		place_lbl.get_parent().add_child(goal_lbl)
	goal_lbl.text = ("▸ " + text) if text != "" else ""
	goal_lbl.visible = text != ""
	if text != "":
		goal_lbl.modulate.a = 0.0
		goal_lbl.create_tween().tween_property(goal_lbl, "modulate:a", 1.0, 0.5)

# ------------------------------------------------------------------ notices: one at a time, tap to dismiss

## Everything that pops up over the game (a friend's text, a toast, a level-up, a heist done) waits its
## turn: one on screen at a time, gone after a while or the moment you tap it. They hold off while a menu,
## a challenge's card or a title card is up. A toast cuts in at the front of the line (it's about now).
var _nq: Array = []            # {build: Callable -> {node, tap}, hold, hud, key}
var _ncur: Dictionary = {}     # the one up: {node, tap, key, tw}
var _cine_t := 0.0             # a title card's up: nothing else for now
var _npump := false

var _seen_keys := {}           # notice key -> when it last went up (the same one again soon: left out)

func notice(build: Callable, hold: float, front := false, key := "", needs_hud := true) -> void:
	if key != "":
		if String(_ncur.get("key", "")) == key:
			return
		for e in _nq:
			if String(e["key"]) == key:
				return
		var now := Time.get_ticks_msec() / 1000.0
		if key.begins_with("toast:") and now - float(_seen_keys.get(key, -999.0)) < 30.0:
			return
		_seen_keys[key] = now
	# (driving: a quieter screen. Toasts are about now, so a stale one waiting its turn gets dropped;
	# no more than two waiting at once. Texts from people always wait their turn)
	if key.begins_with("toast:"):
		var waiting := 0
		for i in range(_nq.size() - 1, -1, -1):
			if String(_nq[i]["key"]).begins_with("toast:"):
				waiting += 1
				if waiting >= 2:
					_nq.remove_at(i)
		if game != null and game.state == game.DRIVE and not game.on_foot and game.car.linear_velocity.length() > 9.0:
			hold = minf(hold, 2.4)
	var e := {"build": build, "hold": hold, "hud": needs_hud, "key": key}
	if front:
		_nq.push_front(e)
	else:
		_nq.append(e)
	_notice_pump()

func _notice_blocked(e: Dictionary) -> bool:
	if _cine_t > 0.0:
		return true
	if not bool(e["hud"]):
		return false
	return game.state != game.DRIVE or overlay.visible or not hud.visible or (start_card != null and is_instance_valid(start_card)) \
		or (phone_layer != null and phone_layer.visible)

func _notice_pump() -> void:
	if not _ncur.is_empty() and is_instance_valid(_ncur["node"]):
		return
	_ncur = {}
	if _nq.is_empty():
		return
	if _notice_blocked(_nq[0]):
		if not _npump:
			_npump = true
			get_tree().create_timer(0.4, false).timeout.connect(func():
				_npump = false
				_notice_pump())
		return
	var e: Dictionary = _nq.pop_front()
	var made: Dictionary = (e["build"] as Callable).call()
	var node: Control = made["node"]
	var tap: Control = made.get("tap", node)
	tap.mouse_filter = Control.MOUSE_FILTER_STOP
	tap.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			_notice_dismiss(node))
	# (a long line waiting: each one's up a bit less)
	var hold := float(e["hold"]) * (0.65 if _nq.size() >= 3 else 1.0)
	_ncur = {"node": node, "key": e["key"]}
	var wr: WeakRef = weakref(node)      # (it may be gone by then: a title card clears it early)
	get_tree().create_timer(hold, false).timeout.connect(func(): _notice_dismiss(wr.get_ref()))

func _notice_dismiss(node: Control) -> void:
	if not is_instance_valid(node) or node.has_meta("going"):
		return
	node.set_meta("going", true)
	var out: Callable = node.get_meta("out") if node.has_meta("out") else Callable()
	var tw := node.create_tween()
	if out.is_valid():
		out.call(tw)
	else:
		tw.tween_property(node, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		node.queue_free()
		if _ncur.get("node") == node:
			_ncur = {}
		get_tree().create_timer(0.12, false).timeout.connect(_notice_pump))

## A small ✕ in the corner of a notice: tap it (or anywhere on it) to dismiss.
func _notice_x(parent: Control) -> void:
	var x := K.label("✕", 15, Color(1, 1, 1, 0.45), 700)
	x.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	x.position = Vector2(-26, 6)
	x.size = Vector2(20, 20)
	x.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(x)

## A text from a friend: a bubble that slides down from the top (one at a time), a buzz.
func text_msg(from: String, text: String) -> void:
	notice(func(): return _text_card(from, text), clampf(1.6 + text.length() * 0.045, 2.6, 5.5))

func _text_card(from: String, text: String) -> Dictionary:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", K.box(Color(0.07, 0.065, 0.1, 0.92), 22, 0, Color.TRANSPARENT, 14))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hb)
	var face := PanelContainer.new()
	face.custom_minimum_size = Vector2(46, 46)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_theme_stylebox_override("panel", K.box(Color("5cc8ff"), 23, 0, Color.TRANSPARENT, 0))
	face.add_child(K.label(from.substr(0, 1), 26, Color.WHITE, 800))
	hb.add_child(face)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	vb.add_child(K.label(from, 17, Color("5cc8ff"), 800, HORIZONTAL_ALIGNMENT_LEFT))
	var tl := K.label(text, 20, Color.WHITE, 600, HORIZONTAL_ALIGNMENT_LEFT)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size = Vector2(520, 0)
	vb.add_child(tl)
	add_child(card)
	_notice_x(card)
	card.reset_size()
	var vs := _vs()
	card.position = Vector2((vs.x - card.size.x) * 0.5, -card.size.y - 10.0)
	game.sfx("radio_chirp", -10.0, 1.4)
	game.buzz(25, 0.4)
	card.create_tween().tween_property(card, "position:y", 104.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	card.set_meta("out", func(tw: Tween):
		tw.tween_property(card, "position:y", -card.size.y - 10.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN))
	return {"node": card}

## The opening: letterbox bars, the title and a line, over the town.
func intro_card(title_txt: String, sub: String) -> void:
	_cine_t = 3.8
	if not _ncur.is_empty() and is_instance_valid(_ncur["node"]):
		_notice_dismiss(_ncur["node"])
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var vs := _vs()
	var top := ColorRect.new()
	top.color = Color.BLACK
	top.size = Vector2(vs.x, 0)
	root.add_child(top)
	var bot := ColorRect.new()
	bot.color = Color.BLACK
	bot.position = Vector2(0, vs.y)
	bot.size = Vector2(vs.x, 0)
	root.add_child(bot)
	var t1 := K.outlined(K.label(title_txt, 86, Color.WHITE, 800), K.SHADE, 14)
	t1.add_theme_font_override("font", K.font_spaced(800, 12))
	t1.size = Vector2(vs.x, 110)
	t1.position = Vector2(0, vs.y * 0.36)
	t1.modulate.a = 0.0
	root.add_child(t1)
	var t2 := K.outlined(K.label(sub, 30, Color("ffd34d"), 650), K.SHADE, 8)
	t2.size = Vector2(vs.x, 44)
	t2.position = Vector2(0, vs.y * 0.36 + 110)
	t2.modulate.a = 0.0
	root.add_child(t2)
	var bar := vs.y * 0.12
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(top, "size:y", bar, 0.6)
	tw.tween_property(bot, "size:y", bar, 0.6)
	tw.tween_property(bot, "position:y", vs.y - bar, 0.6)
	tw.tween_property(t1, "modulate:a", 1.0, 0.8).set_delay(0.4)
	tw.tween_property(t2, "modulate:a", 1.0, 0.8).set_delay(1.1)
	tw.chain().tween_interval(1.8)
	tw.chain().set_parallel(true)
	tw.tween_property(t1, "modulate:a", 0.0, 0.5)
	tw.tween_property(t2, "modulate:a", 0.0, 0.5)
	tw.tween_property(top, "size:y", 0.0, 0.6)
	tw.tween_property(bot, "size:y", 0.0, 0.6)
	tw.tween_property(bot, "position:y", vs.y, 0.6)
	tw.chain().tween_callback(root.queue_free)

func toast(text: String, icon := "", col := K.PAPER, icol := K.INK, hold := 2.2) -> void:
	if game != null and game.state == game.DRIVE and not overlay.visible:
		# out in the world: it takes its turn with the other notices (at the front: it's about now)
		notice(func(): return _toast_card(text, icon, col, icol), hold + 0.3, true, "toast:" + text)
		return
	# in a menu or a shop: straight up (feedback on what you just pressed), replacing any before it
	for c in toasts.get_children():
		if c.get_meta("text", "") == text and not c.is_queued_for_deletion():
			return
		c.queue_free()
	_toast_legacy(text, icon, col, icol, hold)

## A toast in the line of notices: the same dark pill, at the top in the middle.
func _toast_card(text: String, icon: String, col: Color, icol: Color) -> Dictionary:
	var p := _toast_pill(text, icon, col, icol)
	add_child(p)
	_notice_x(p)
	p.reset_size()
	var vs := _vs()
	p.position = Vector2((vs.x - p.size.x) * 0.5, 98.0)       # (up under the top bar, out of the view of the road)
	p.pivot_offset = p.size * 0.5
	p.modulate.a = 0.0
	p.scale = Vector2(0.78, 0.78)
	var t := p.create_tween()
	t.tween_property(p, "modulate:a", 1.0, 0.18)
	t.parallel().tween_property(p, "scale", Vector2(0.9, 0.9), 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	p.set_meta("out", func(tw: Tween):
		tw.tween_property(p, "modulate:a", 0.0, 0.22)
		tw.parallel().tween_property(p, "scale", Vector2(0.94, 0.94), 0.22))
	return {"node": p}

func _toast_pill(text: String, icon: String, col: Color, icol: Color) -> PanelContainer:
	var tinted := col.a > 0.95 and col.get_luminance() > 0.08 and col != K.PAPER
	var p := PanelContainer.new()
	var sb := K.box(Color(0.06, 0.055, 0.085, 0.86), 36, 0, Color.TRANSPARENT, 20)
	sb.set_border_width_all(1)
	sb.border_color = Color(col, 0.6) if tinted else Color(1, 1, 1, 0.14)
	icol = col if tinted else K.INK
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.content_margin_right = 34
	p.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(hb)
	if icon != "":
		hb.add_child(Icon.new(icon, icol, 34))
	hb.add_child(K.label(text, 24, K.INK, 600))
	return p

func _toast_legacy(text: String, icon := "", col := K.PAPER, icol := K.INK, hold := 2.2) -> void:
	# (always a dark glass pill: the toast's own colour goes to its icon and a faint edge)
	var tinted := col.a > 0.95 and col.get_luminance() > 0.08 and col != K.PAPER
	var p := PanelContainer.new()
	var sb := K.box(Color(0.06, 0.055, 0.085, 0.86), 36, 0, Color.TRANSPARENT, 20)
	sb.set_border_width_all(1)
	sb.border_color = Color(col, 0.6) if tinted else Color(1, 1, 1, 0.14)
	icol = col if tinted else K.INK
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
	hb.add_child(K.label(text, 24, K.INK, 600))
	p.set_meta("text", text)
	toasts.add_child(p)
	p.modulate.a = 0.0
	p.scale = Vector2(0.86, 0.86)
	# (a little pop in from its middle, a fade and a shrink away)
	p.resized.connect(func(): p.pivot_offset = p.size * 0.5)
	var t := p.create_tween()
	t.tween_property(p, "modulate:a", 1.0, 0.18)
	t.parallel().tween_property(p, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(hold)
	t.tween_property(p, "modulate:a", 0.0, 0.3)
	t.parallel().tween_property(p, "scale", Vector2(0.94, 0.94), 0.3).set_ease(Tween.EASE_IN)
	t.tween_callback(p.queue_free)

func discovered(name: String) -> void:
	var n: int = game.save.data["places"].size()
	toast("Found %s  (%d/%d)" % [name, n, island.places.size()], "map", K.TEAL, Color.WHITE, 2.6)

func found_coin(n: int, total: int, pay: int) -> void:
	toast("Hidden cash %d/%d  +%s" % [n, total, K.money(pay)], "coin", K.SUN, K.INK, 1.8)

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
	if String(info.get("story", "")) != "":
		# (who they are and why they want you: a street fight's opponent)
		var st := K.label(String(info["story"]), 17, K.INK, 550, HORIZONTAL_ALIGNMENT_LEFT)
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.custom_minimum_size = Vector2(500, 0)
		st.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 4)
		vb.add_child(gap)
		vb.add_child(st)
	vb.add_child(K.label(info["info"], 17, K.INK_SOFT, 600, HORIZONTAL_ALIGNMENT_LEFT))
	if info.has("chips"):
		# a choice along the bottom (a street fight's bet)
		var cr := HBoxContainer.new()
		cr.add_theme_constant_override("separation", 8)
		var csp := Control.new()
		csp.custom_minimum_size = Vector2(0, 8)
		vb.add_child(csp)
		vb.add_child(cr)
		var labels: Array = info["chips"]
		for k in labels.size():
			var on2: bool = int(info["chip"]) == k
			var ch := K.button(String(labels[k]), col if on2 else K.CREAM, col.darkened(0.3) if on2 else K.LINE_DK, 18, 0, 46)
			if not on2:
				ch.add_theme_color_override("font_color", K.INK_SOFT)
			var k2 := k
			var cset: Callable = info["set_chip"]
			_tap(ch, func():
				if k2 != int(info["chip"]):
					game.sfx("select", -8.0, 1.1 + k2 * 0.1)
					cset.call(k2))
			cr.add_child(ch)
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
			var open: bool = Progress.race_ok(game.save, k)
			var need: int = Progress.RACE_LEVEL[k]
			var chip := K.button(["Easy", "Medium", "Hard"][k] if open else "Lv %d" % need, dcol if on else K.CREAM, dcol.darkened(0.3) if on else K.LINE_DK, 19, 104, 46, "" if open else "lock")
			if not on:
				chip.add_theme_color_override("font_color", K.INK_SOFT)
			var kk := k
			var setter: Callable = info["set_diff"]
			_tap(chip, func():
				if not open:
					toast("%s races open up at level %d" % [["Easy", "Medium", "Hard"][kk], need], "lock", K.PAPER, K.INK, 2.0)
					return
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
		vb.add_child(K.label("+" + K.money(pay), 30, K.INK, 700))
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
## The phone pulls up over everything (like the map: the game waits, the screen dims behind it); tap
## outside it, or its back button, to put it away.
func toggle_phone() -> void:
	if phone_layer == null:
		phone_layer = Control.new()
		phone_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		phone_layer.mouse_filter = Control.MOUSE_FILTER_STOP
		phone_layer.visible = false
		add_child(phone_layer)
		var dim := ColorRect.new()
		dim.color = K.DIM
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		dim.gui_input.connect(func(e):
			if (e is InputEventScreenTouch or e is InputEventMouseButton) and not e.pressed and phone_layer.visible:
				game.ui_tap()
				toggle_phone())
		phone_layer.add_child(dim)
		phone.set_anchors_preset(Control.PRESET_TOP_LEFT)
		phone.size = Vector2(290, 318)
		phone.pivot_offset = phone.size * 0.5
		phone_layer.add_child(phone)
	if phone_layer.visible:
		var t := create_tween()
		t.tween_property(phone_layer, "modulate:a", 0.0, 0.14)
		t.tween_callback(func():
			phone_layer.visible = false
			phone.visible = false
			game.drop_touches()
			game.resume())
		return
	if game.state != game.DRIVE:
		return
	game.pause(false)
	phone_layer.visible = true
	phone.visible = true
	phone.open()
	phone_layer.modulate.a = 0.0
	phone.scale = Vector2.ONE * 1.55
	var sz: Vector2 = _vs()
	var at := (sz - phone.size) * 0.5
	phone.position = at + Vector2(0, sz.y * 0.6)
	var t2 := create_tween().set_parallel()
	t2.tween_property(phone_layer, "modulate:a", 1.0, 0.16)
	t2.tween_property(phone, "position", at, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func tick(dt: float) -> void:
	if phone and phone.visible:
		phone.tick(dt)
	_radar_tick(dt)
	if group_btn and hud.visible and game.crew:
		group_btn.visible = game.crew.crew_count() > 0 or game.group_cam
		group_btn.modulate = Color(0.75, 1.0, 0.82) if game.group_cam else Color.WHITE
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
	_map_ranges(false)
	for c in overlay.get_children():
		c.queue_free()
	overlay.visible = true
	if _hud_tw and _hud_tw.is_valid():
		_hud_tw.kill()
	hud.modulate.a = 0.0            # (the controls hide behind a menu: no pedals poking out round it)
	var dim := ColorRect.new()
	dim.color = K.DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	dim.modulate.a = 0.0
	dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.2)
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
	card.scale = Vector2(0.92, 0.92)
	var t := card.create_tween()
	t.tween_property(card, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(card, "modulate:a", 1.0, 0.2)
	# (its rows, added as it opens, come in one after another, a beat apart)
	var born := Time.get_ticks_msec()
	var cnt := [0]
	vb.child_entered_tree.connect(func(row: Node):
		if not (row is Control) or Time.get_ticks_msec() - born > 300:
			return
		(row as Control).modulate.a = 0.0
		var rt := (row as Control).create_tween()
		rt.tween_interval(0.05 + 0.04 * mini(cnt[0], 8))
		rt.tween_property(row, "modulate:a", 1.0, 0.18)
		cnt[0] += 1)
	return vb

## The 3D map sees the whole town from up high: the buildings stay drawn however far off while it's open.
func _map_ranges(open: bool) -> void:
	for mi in island.chunk_mi.values():
		(mi as GeometryInstance3D).visibility_range_end = 0.0 if open else 330.0

func close_sheet() -> void:
	_map_restore()
	_map_ranges(false)
	overlay.visible = false
	var kids := overlay.get_children()
	if kids.is_empty():
		hud.modulate.a = 1.0
		return
	# (it goes at once as far as the game's concerned; on screen it fades and sinks away, the HUD fading back)
	var ghost := Control.new()
	ghost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ghost)
	move_child(ghost, overlay.get_index() + 1)
	for c in kids:
		c.reparent(ghost, false)
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.18)
	tw.tween_property(ghost, "position:y", 14.0, 0.18).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ghost.queue_free)
	if _hud_tw and _hud_tw.is_valid():
		_hud_tw.kill()
	_hud_tw = create_tween()
	_hud_tw.tween_property(hud, "modulate:a", 1.0, 0.22)

var _hud_tw: Tween

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
		["Your cars", "car", K.SKY, K.SKY_DK, func():
			# (Dez brings any of them to you; the shops are on Main Street)
			game.resume()
			if not phone.visible:
				toggle_phone()
			phone._mode = "dez"
			phone._sig = ""
			phone.refresh()],
		["Trophies", "trophy", K.LILAC, K.LILAC_DK, func(): open_achievements(true)],
		["Car cards", "star", Color("ffb020"), Color("c98500"), func(): open_cards(true)],
		["Settings", "gear", K.PAPER, K.LINE, func(): open_settings(true)],
		["How to drive", "help", K.PAPER, K.LINE, func(): show_help(true)],
		["Call the crew", "phone", K.PAPER, K.LINE, func():
			game.resume()
			if not phone.visible:
				toggle_phone()],
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
	g.add_child(_setting_toggle("eye", "Aim blur", st.get("dof", true), func(v): game.set_setting("dof", v)))
	g.add_child(_setting_toggle("wind", "Speed blur", st.get("speedfx", true), func(v): game.set_setting("speedfx", v)))
	g.add_child(_setting_toggle("leaf", "Ambient particles", st.get("motes", true), func(v): game.set_setting("motes", v)))
	g.add_child(_setting_toggle("rain", "Weather", st.get("weather", true), func(v): game.set_setting("weather", v)))
	g.add_child(_setting_toggle("calendar", "Show clock", st["clock"], func(v): game.set_setting("clock", v)))
	g.add_child(_setting_toggle("gauge", "Show FPS", st.get("fps", false), func(v): game.set_setting("fps", v)))
	g.add_child(_setting_toggle("lock", "Cap at 60 fps", st.get("fps60", false), func(v): game.set_setting("fps60", v)))
	g.add_child(_setting_toggle("lock", "Cap at 30 fps (smoother on slower phones)", st.get("fps30", false), func(v): game.set_setting("fps30", v)))
	g.add_child(_setting_toggle("flag", "Event markers from afar (off: only up close, or where your GPS is going)", st.get("markers", true), func(v): game.set_setting("markers", v)))
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

# ------------------------------------------------------------------ car cards

## The card collection: your level (and how far to the next: each level's a pack), packs to open, and the
## fifty cards (the ones you've not got yet face down).
func open_cards(from_pause := false) -> void:
	var sv = game.save
	var x: int = Cards.xp(sv)
	var lv: Array = Cards.level_of(x)
	var vb: VBoxContainer = await _sheet("Car cards  %d/%d" % [Cards.owned(sv), Cards.LIST.size()], "star", Color("ffb020"), 1180.0)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	vb.add_child(top)
	var lvb := VBoxContainer.new()
	lvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lvb)
	lvb.add_child(K.label("Level %d" % int(lv[0]), 30, K.INK, 750, HORIZONTAL_ALIGNMENT_LEFT))
	var bar := K.bar(520, 12, Color("ffb020"), Color(1, 1, 1, 0.15))
	bar.value = float(lv[1]) / float(lv[2])
	lvb.add_child(bar)
	lvb.add_child(K.label("%s / %s XP to the next level (a new pack): drift, race, explore, pull heists" % [K.fmt(int(lv[1])), K.fmt(int(lv[2]))], 16, K.INK_SOFT, 600, HORIZONTAL_ALIGNMENT_LEFT))
	var n: int = Cards.packs(sv)
	var ob := K.button(("Open pack  (%d)" % n) if n > 0 else "No packs: level up", K.CORAL if n > 0 else K.PAPER, K.CORAL_DK if n > 0 else K.LINE, 26, 300, 76, "star")
	ob.disabled = n <= 0
	_tap(ob, func():
		if Cards.packs(game.save) > 0:
			_open_pack(from_pause))
	top.add_child(ob)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1140, minf(400.0, _vs().y - 330.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	_drag_scroll(sc)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	sc.add_child(grid)
	var got: Dictionary = sv.data.get("cards", {})
	for c in Cards.LIST:
		var have := int(got.get(c[0], 0))
		var cardc := _card(c, have > 0, Vector2(170, 238), have)
		if have > 0:
			_tap_card(cardc, c, from_pause)
		grid.add_child(cardc)
	var ok := K.button("Done", K.PAPER, K.LINE, 28, 0, 68)
	_tap(ok, func(): _back_from(from_pause))
	vb.add_child(ok)

func _tap_card(cardc: Control, c: Array, from_pause: bool) -> void:
	cardc.mouse_filter = Control.MOUSE_FILTER_PASS
	cardc.gui_input.connect(func(e):
		if ((e is InputEventScreenTouch or e is InputEventMouseButton) and not e.pressed) and _drag_dist < 18.0:
			game.ui_tap()
			_card_detail(c, from_pause))

## One card. Face up: a metal frame in its rarity's colour (foil and a holo sheen from Rare up, gold for
## Legendary), the car's photo, its name, year and origin, a line from its fact. Face down: the card back.
## info: the back with the fact written on it, and who took the photo.
func _card(c: Array, face: bool, sz: Vector2, count := 1, info := false) -> Control:
	var root := Control.new()
	root.custom_minimum_size = sz
	root.size = sz
	root.pivot_offset = sz * 0.5
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := ColorRect.new()
	art.size = sz
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = CARD_SHADER
	sm.set_shader_parameter("card_px", sz)
	sm.set_shader_parameter("mode", 0 if face else 1)
	sm.set_shader_parameter("show_ring", not info)
	var r: int = int(c[4]) if not c.is_empty() else 0
	sm.set_shader_parameter("rarity", r)
	sm.set_shader_parameter("rarity_col", Cards.RARITY[r]["col"])
	var tex := _card_photo(String(c[0])) if face and not c.is_empty() else null
	sm.set_shader_parameter("has_photo", tex != null)
	if tex:
		sm.set_shader_parameter("photo", tex)
		sm.set_shader_parameter("photo_aspect", float(tex.get_width()) / maxf(float(tex.get_height()), 1.0))
	art.material = sm
	root.add_child(art)
	var ov := Control.new()
	ov.size = sz
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.draw.connect(func(): _card_text(ov, c, face, sz, count, info, tex != null))
	root.add_child(ov)
	root.set_meta("mat", sm)
	return root

var _photo_cache := {}

func _card_photo(id: String) -> Texture2D:
	if _photo_cache.has(id):
		return _photo_cache[id]
	var t: Texture2D = null
	for ext in ["png", "jpg", "webp"]:
		var p := "res://assets/cards/%s.%s" % [id, ext]
		if ResourceLoader.exists(p):
			t = load(p)
			break
	_photo_cache[id] = t
	return t

## The largest size (up to `size`) that fits `text` in `w` pixels.
func _fit(f: Font, text: String, w: float, size: int) -> int:
	var s := size
	while s > 8 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > w:
		s -= 1
	return s

func _card_text(o: Control, c: Array, face: bool, sz: Vector2, count: int, info: bool, photo: bool) -> void:
	var k := sz.x / 250.0
	var bold := K.font(800)
	var mid := K.font(650)
	var thin := K.font(500)
	if not face and not info:
		# the back: the game's name in the ring
		var lt: Texture2D = load("res://assets/ui/wordmark.png") if ResourceLoader.exists("res://assets/ui/wordmark.png") else null
		if lt:
			var lw := sz.x * 0.74
			var lh := lw * lt.get_height() / lt.get_width()
			o.draw_texture_rect(lt, Rect2((sz.x - lw) * 0.5, sz.y * 0.47 - lh * 0.5, lw, lh), false)
		var t3 := "CAR CARDS"
		o.draw_string(mid, Vector2((sz.x - mid.get_string_size(t3, 0, -1, int(13 * k)).x) * 0.5, sz.y * 0.88), t3, HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * k), Color(1, 1, 1, 0.55))
		return
	var r: Dictionary = Cards.RARITY[int(c[4])]
	var rc: Color = r["col"]
	var num := Cards.LIST.find(c) + 1
	var pad := 20.0 * k
	if info:
		# the back, written on: the car, the fact, the photo credit
		var y := 46.0 * k
		var ns := _fit(bold, String(c[1]), sz.x - pad * 2, int(24 * k))
		o.draw_string(bold, Vector2(pad, y), String(c[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, ns, Color.WHITE)
		y += 26 * k
		o.draw_string(mid, Vector2(pad, y), "%d  ·  %s  ·  %s" % [int(c[2]), String(c[3]).to_upper(), String(r["name"]).to_upper()], HORIZONTAL_ALIGNMENT_LEFT, sz.x - pad * 2, int(13 * k), rc)
		y += 16 * k
		o.draw_line(Vector2(pad, y), Vector2(sz.x - pad, y), Color(rc, 0.6), 2.0 * k)
		y += 30 * k
		o.draw_multiline_string(thin, Vector2(pad, y), String(c[5]), HORIZONTAL_ALIGNMENT_LEFT, sz.x - pad * 2, int(18 * k), 9, Color(1, 1, 1, 0.92))
		o.draw_string(mid, Vector2(pad, sz.y - 16 * k), "No. %02d / %d" % [num, Cards.LIST.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * k), Color(1, 1, 1, 0.5))
		return
	# front: the name across the top, its rarity in gems at the right
	var gem_w := 12.0 * k * (int(c[4]) + 1)
	var ns2 := _fit(bold, String(c[1]), sz.x - pad * 2 - gem_w - 6 * k, int(20 * k))
	o.draw_string_outline(bold, Vector2(pad, sz.y * 0.085), String(c[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, ns2, int(4 * k), Color(0, 0, 0, 0.5))
	o.draw_string(bold, Vector2(pad, sz.y * 0.085), String(c[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, ns2, Color.WHITE)
	for g in int(c[4]) + 1:
		var gc := Vector2(sz.x - pad - 5 * k - g * 12 * k, sz.y * 0.068)
		var d := 5.0 * k
		o.draw_colored_polygon(PackedVector2Array([gc + Vector2(0, -d), gc + Vector2(d, 0), gc + Vector2(0, d), gc + Vector2(-d, 0)]), rc.lightened(0.2))
	if not photo:
		# (no photo yet: a car shape on the backdrop)
		var bc := Vector2(sz.x * 0.5, sz.y * 0.4)
		var body := Color(0.95, 0.96, 1.0, 0.9)
		_rrect(o, Rect2(bc + Vector2(-64, -6) * k, Vector2(128, 28) * k), 11 * k, body)
		_rrect(o, Rect2(bc + Vector2(-36, -28) * k, Vector2(68, 26) * k), 11 * k, body)
		o.draw_circle(bc + Vector2(-38, 22) * k, 14 * k, Color(0.08, 0.08, 0.1))
		o.draw_circle(bc + Vector2(38, 22) * k, 14 * k, Color(0.08, 0.08, 0.1))
	# under the photo: year and where from, the number
	var yy := sz.y * 0.67
	o.draw_string(mid, Vector2(pad, yy), "%d  ·  %s" % [int(c[2]), String(c[3]).to_upper()], HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * k), Color(1, 1, 1, 0.75))
	var ntxt := "%02d/%d" % [num, Cards.LIST.size()]
	o.draw_string(mid, Vector2(sz.x - pad - mid.get_string_size(ntxt, 0, -1, int(12 * k)).x, yy), ntxt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * k), Color(1, 1, 1, 0.45))
	# the rarity, and the start of the fact
	o.draw_string(bold, Vector2(pad, yy + 24 * k), String(r["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * k), rc.lightened(0.15))
	var fact := String(c[5])
	var first := fact.substr(0, fact.find(". ") + 1) if fact.find(". ") > 0 else fact
	o.draw_multiline_string(thin, Vector2(pad, yy + 44 * k), first, HORIZONTAL_ALIGNMENT_LEFT, sz.x - pad * 2, int(12 * k), 3, Color(1, 1, 1, 0.7))
	if count > 1:
		var xs := "x%d" % count
		o.draw_string(bold, Vector2(sz.x - pad - bold.get_string_size(xs, 0, -1, int(14 * k)).x, sz.y - 14 * k), xs, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * k), Color(1, 1, 1, 0.7))

## A foil pack (the wrapper you tear open).
func _pack(sz: Vector2) -> Control:
	var root := Control.new()
	root.custom_minimum_size = sz
	root.size = sz
	root.pivot_offset = sz * 0.5
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := ColorRect.new()
	art.size = sz
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = CARD_SHADER
	sm.set_shader_parameter("card_px", sz)
	sm.set_shader_parameter("mode", 2)
	sm.set_shader_parameter("rarity_col", Color(1.0, 0.33, 0.55))
	art.material = sm
	root.add_child(art)
	var ov := Control.new()
	ov.size = sz
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.draw.connect(func():
		var k := sz.x / 260.0
		var bold := K.font(800)
		var mid := K.font(650)
		var lines := [["LO-FI LIFE", mid, int(15 * k), Color(1, 1, 1, 0.85), sz.y * 0.2], ["CAR", bold, int(54 * k), Color.WHITE, sz.y * 0.47],
			["CARDS", bold, int(46 * k), Color("ffd34d"), sz.y * 0.59], ["3 CARDS  ·  SERIES 1", mid, int(14 * k), Color(1, 1, 1, 0.85), sz.y * 0.82]]
		for l in lines:
			var f: Font = l[1]
			var w := f.get_string_size(String(l[0]), 0, -1, int(l[2])).x
			ov.draw_string_outline(f, Vector2((sz.x - w) * 0.5, float(l[4])), String(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(l[2]), int(6 * k), Color(0, 0, 0, 0.45))
			ov.draw_string(f, Vector2((sz.x - w) * 0.5, float(l[4])), String(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(l[2]), l[3]))
	root.add_child(ov)
	root.set_meta("mat", sm)
	return root

## A card's detail: big, and tap it to turn it over (the fact's on the back).
func _card_detail(c: Array, from_pause: bool) -> void:
	var vb: VBoxContainer = await _sheet(String(c[1]), "star", Cards.RARITY[int(c[4])]["col"], 760.0)
	var h := minf(470.0, _vs().y - 250.0)
	var sz := Vector2(h * 0.714, h)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	var holder := Control.new()
	holder.custom_minimum_size = sz
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	hb.add_child(holder)
	var front := _card(c, true, sz)
	var back := _card(c, false, sz, 1, true)
	back.visible = false
	holder.add_child(front)
	holder.add_child(back)
	var flipping := [false]
	holder.gui_input.connect(func(e):
		if ((e is InputEventScreenTouch or e is InputEventMouseButton) and not e.pressed) and not flipping[0]:
			flipping[0] = true
			game.sfx("tap", -6.0, 1.3)
			var showing: Control = front if front.visible else back
			var other: Control = back if front.visible else front
			var tw := create_tween()
			tw.tween_property(showing, "scale:x", 0.0, 0.14).set_ease(Tween.EASE_IN)
			tw.tween_callback(func():
				showing.visible = false
				showing.scale.x = 1.0
				other.scale.x = 0.0
				other.visible = true)
			tw.tween_property(other, "scale:x", 1.0, 0.16).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func(): flipping[0] = false))
	vb.add_child(K.label("Tap the card to turn it over", 16, K.INK_SOFT, 600))
	var ok := K.button("Back to the cards", K.PAPER, K.LINE, 26, 0, 64)
	_tap(ok, func(): open_cards(from_pause))
	vb.add_child(ok)

## Opening a pack: the pack, tap it and it shakes and bursts open, three cards fly out face down and turn
## over one after another (a flash in their rarity's colour; NEW, or what a duplicate paid).
func _open_pack(from_pause: bool) -> void:
	var got: Array = Cards.open_pack(game.save)
	game._save_now()
	for ch in overlay.get_children():
		ch.queue_free()
	overlay.visible = true
	hud.modulate.a = 0.0
	var vs: Vector2 = _vs()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(stage)
	var ch_h := minf(vs.y * 0.56, 380.0)
	var csz := Vector2(ch_h * 0.714, ch_h)
	var psz := Vector2(ch_h * 0.74, ch_h * 1.08)
	var pk := _pack(psz)
	pk.position = (vs - psz) * 0.5
	pk.scale = Vector2(0.5, 0.5)
	pk.modulate.a = 0.0
	stage.add_child(pk)
	var hint := K.outlined(K.label("Tap to open", 22, Color.WHITE, 700), K.INK, 6)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-150, -70)
	hint.size = Vector2(300, 40)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(hint)
	var ti := create_tween()
	ti.set_parallel(true)
	ti.tween_property(pk, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ti.tween_property(pk, "modulate:a", 1.0, 0.25)
	# a gentle float while it waits
	var bob := create_tween().set_loops()
	bob.tween_property(pk, "rotation", 0.04, 0.9).set_trans(Tween.TRANS_SINE)
	bob.tween_property(pk, "rotation", -0.04, 0.9).set_trans(Tween.TRANS_SINE)
	var opened := [false]
	var open := func():
		if opened[0]:
			return
		opened[0] = true
		bob.kill()
		hint.visible = false
		game.sfx("mag_out", -2.0, 0.8)
		var pm: ShaderMaterial = pk.get_meta("mat")
		var t := create_tween()
		for k in 6:
			t.tween_property(pk, "rotation", 0.09 * (1.0 if k % 2 == 0 else -1.0), 0.05)
		t.tween_property(pk, "rotation", 0.0, 0.05)
		t.parallel().tween_method(func(v): pm.set_shader_parameter("glow", v), 0.0, 1.2, 0.3)
		t.tween_callback(func(): game.sfx("explosion", -14.0, 1.8))
		t.tween_property(pk, "scale", Vector2(1.25, 1.25), 0.18)
		t.parallel().tween_property(pk, "modulate:a", 0.0, 0.18)
		t.tween_callback(func():
			pk.queue_free()
			_deal(stage, got, csz, vs, from_pause))
	dim.gui_input.connect(func(e):
		if (e is InputEventScreenTouch or e is InputEventMouseButton) and not e.pressed:
			open.call())
	if String(game.args.get("cardtest", "")) == "pack":
		get_tree().create_timer(0.7).timeout.connect(open)

func _deal(stage: Control, got: Array, csz: Vector2, vs: Vector2, from_pause: bool) -> void:
	var gap := 34.0
	var x0 := vs.x * 0.5 - (csz.x * 1.5 + gap)
	var y := (vs.y - csz.y) * 0.5 - 24.0
	for i in got.size():
		var g: Array = got[i]
		var c: Array = g[0]
		var slot := Control.new()
		slot.position = Vector2(vs.x * 0.5 - csz.x * 0.5, vs.y * 0.5 - csz.y * 0.5)
		slot.size = csz
		slot.pivot_offset = csz * 0.5
		slot.scale = Vector2(0.4, 0.4)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(slot)
		var back := _card(c, false, csz)
		var front := _card(c, true, csz)
		front.visible = false
		slot.add_child(back)
		slot.add_child(front)
		var tag := K.outlined(K.label("NEW!" if g[1] else ("+" + K.money(int(g[2]))), 24, Color("ffd34d") if g[1] else Color(1, 1, 1, 0.8), 800), K.INK, 6)
		tag.position = Vector2(0, csz.y + 10)
		tag.size = Vector2(csz.x, 30)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.modulate.a = 0.0
		slot.add_child(tag)
		var to := Vector2(x0 + i * (csz.x + gap), y)
		var t := create_tween()
		t.tween_interval(i * 0.12)
		t.tween_property(slot, "position", to, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(slot, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(slot, "rotation", (i - 1) * 0.05, 0.35)
		# then turn over, one after another (the rarest last makes the best show, but it's the order they came)
		t.tween_interval(0.5 + i * 0.55)
		t.tween_property(slot, "scale:x", 0.0, 0.14).set_ease(Tween.EASE_IN)
		var r: int = int(c[4])
		t.tween_callback(func():
			back.visible = false
			front.visible = true
			var fm: ShaderMaterial = front.get_meta("mat")
			var gt := create_tween()
			gt.tween_method(func(v): fm.set_shader_parameter("glow", v), 0.4 + r * 0.25, 0.0, 0.7)
			_burst(stage, to + csz * 0.5, Cards.RARITY[r]["col"], csz.x * (0.6 + r * 0.25))
			game.sfx("cash" if r < 3 else "mission", -6.0 + r, 1.0 + r * 0.08))
		t.tween_property(slot, "scale:x", 1.0, 0.18).set_ease(Tween.EASE_OUT)
		t.tween_property(tag, "modulate:a", 1.0, 0.2)
	# then what next
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.position = Vector2(vs.x * 0.5 - 360, vs.y - 96)
	row.size = Vector2(720, 70)
	row.modulate.a = 0.0
	stage.add_child(row)
	var more: int = Cards.packs(game.save)
	if more > 0:
		var again := K.button("Open another  (%d)" % more, Color("ffb020"), Color("c98500"), 24, 0, 64, "star")
		again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tap(again, func(): _open_pack(from_pause))
		row.add_child(again)
	var see := K.button("See your cards", K.PAPER, K.LINE, 24, 0, 64)
	see.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tap(see, func(): open_cards(from_pause))
	row.add_child(see)
	var rt := create_tween()
	rt.tween_interval(0.9 + got.size() * 0.7)
	rt.tween_property(row, "modulate:a", 1.0, 0.3)

## A ring of light going out from a card as it turns over.
func _burst(stage: Control, at: Vector2, col: Color, r: float) -> void:
	var b := Control.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.position = at
	stage.add_child(b)
	stage.move_child(b, 0)
	b.set_meta("k", 0.0)
	b.draw.connect(func():
		var k: float = b.get_meta("k")
		for i in 3:
			var rr := r * (0.4 + k * (0.9 + i * 0.25))
			b.draw_arc(Vector2.ZERO, rr, 0, TAU, 64, Color(col, (1.0 - k) * (0.7 - i * 0.2)), 10.0 * (1.0 - k) + 2.0, true)
		b.draw_circle(Vector2.ZERO, r * 0.6 * (1.0 - k), Color(col.lightened(0.4), 0.25 * (1.0 - k))))
	var t := create_tween()
	t.tween_method(func(v):
		b.set_meta("k", v)
		b.queue_redraw(), 0.0, 1.0, 0.7)
	t.tween_callback(b.queue_free)

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
	p.add_theme_stylebox_override("panel", K.box(Color(1.0, 0.31, 0.55, 0.14) if got else K.CREAM, 20, 0, Color.TRANSPARENT, 10))
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
		rw.add_child(K.label(K.money(int(a["reward"])), 20, K.INK, 650))
	hb.add_child(rw)
	return p

## How to drive: four short pages (tabs along the top) rather than one wall of text. From the pause menu too.
const HELP_PAGES := [
	["Driving", "car", [
		["left", "Steer with the wheel, bottom left (or arrow buttons: Settings). Drag anywhere else to look round the car, pinch to zoom."],
		["play", "GAS and BRAKE, bottom right. Hold BRAKE when you've stopped to reverse."],
		["gauge", "Tap the speedometer to hold the speed you're doing (cruise): tap it again, or brake, to let go. It turns red when you're over the limit. The bars top right are fuel, the car's condition and your health: a gas station fills and fixes the car."],
		["rewind", "Crashed? Hold REWIND (by the minimap) to take the last few seconds back."],
	]],
	["Drifting", "tire", [
		["tire", "Tap DRIFT (the lever) while you steer to swing the tail out, then keep the gas down and steer into the turn to hold it."],
		["right", "Steer the other way with the gas down to flick into a drift the other way. Let go of steering, or ease off, to straighten up."],
		["star", "Drifts score points and cash. Chain them for a bigger multiplier, skim walls and cars for a close bonus, and don't crash mid-drift."],
		["tank", "NOS: tap the bottle to switch it on (and again to switch it off). It burns while you're on the gas."],
	]],
	["Tricks", "wind", [
		["wind", "In the air, GAS tips the nose down and BRAKE lifts it (hold to flip), steering spins you, and DRIFT + steering barrel-rolls. Land on your wheels!"],
		["flag", "Kickers, ramps and boost pads are dotted round the car parks, and the Stunt Yard is just south of town."],
	]],
	["Around town", "map", [
		["flag", "Orange rings are drift zones, blue time trials, purple drift runs and red ones races. The map sets a route to any of them, or to a gas station."],
		["phone", "The phone (by the minimap) calls the drivers you've met: they'll ride with you. The group button beside it pulls the camera out to fit you all in."],
		["star", "Speed past a patrol car or hit one and they'll come after you: stars show under the minimap. Get out of sight and stay out to lose them."],
		["car", "Cash buys cars, paint and upgrades in the garage. The legendary cars are the best drifters of all."],
	]],
]

func show_help(from_pause := false, page := 0) -> void:
	var vb: VBoxContainer = await _sheet("How to drive", "help", K.TEAL, 1040.0)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	vb.add_child(tabs)
	for i in HELP_PAGES.size():
		var pg: Array = HELP_PAGES[i]
		var on := i == page
		var tb := K.button(String(pg[0]), K.INK if on else K.PAPER, K.INK if on else K.LINE, 22, 0, 52, String(pg[1]))
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if on:
			tb.add_theme_color_override("font_color", Color.WHITE)
		var ii := i
		_tap(tb, func(): show_help(from_pause, ii))
		tabs.add_child(tb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(0, 300)
	vb.add_child(box)
	for line in HELP_PAGES[page][2]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		hb.add_child(Icon.new(line[0], K.INK, 38))
		var l := K.label(line[1], 23, K.INK, 600, HORIZONTAL_ALIGNMENT_LEFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(920, 0)
		hb.add_child(l)
		box.add_child(hb)
	var last := page == HELP_PAGES.size() - 1
	var ok := K.button("Let's go" if (last or from_pause) else "Next", K.TEAL, K.TEAL_DK, 32, 0, 76, "play")
	_tap(ok, func():
		if from_pause:
			_back_from(true)
		elif last:
			close_sheet()
		else:
			show_help(false, page + 1))
	vb.add_child(ok)

# ------------------------------------------------------------------ the map

const MAP_SPAN := 1200.0     # metres across the big map (the island and the circuits off its coasts)

## The island map, full screen: the game's own camera goes up over the island at a slant (no second view of
## the world to draw: phones choke on that), the game held while it's open. Drag to move about, pinch (or the
## wheel) to zoom, tap a spot for a waypoint (the GPS takes you to it). Your challenges down the right.
var map_layer: Control
var _map_saved := {}
func open_map() -> void:
	if map_layer != null:
		return
	var from_pause: bool = game.state == game.PAUSED and overlay.visible
	close_sheet()
	title.visible = false
	if game.state == game.DRIVE:
		game.pause(false)
	hud.modulate.a = 0.0
	var mc: Camera3D = game.cam
	_map_saved = {"xf": mc.global_transform, "fov": mc.fov, "far": mc.far, "env": mc.environment, "from_pause": from_pause}
	_map_ranges(true)
	var wenv: Environment = (game.atmos.env as Environment).duplicate()
	wenv.fog_enabled = false          # (from up here the haze would wash the whole town out)
	mc.environment = wenv
	mc.fov = 48.0
	mc.far = 2400.0
	map_layer = MapView.new(self)
	add_child(map_layer)

## The camera back where it was, the map gone (a Route or Go from its list closes it this way too).
func _map_restore() -> void:
	if map_layer == null:
		return
	map_layer.queue_free()
	map_layer = null
	_map_ranges(false)
	var mc: Camera3D = game.cam
	mc.global_transform = _map_saved["xf"]
	mc.fov = _map_saved["fov"]
	mc.far = _map_saved["far"]
	mc.environment = _map_saved["env"]
	hud.modulate.a = 1.0

## Out of the map: the camera back where it was, the game going again (or the pause menu, if that's where it was).
func _map_close() -> void:
	if map_layer == null:
		return
	_map_restore()
	if bool(_map_saved.get("from_pause", false)):
		open_pause()
	elif game.state == game.TITLE:
		show_title()
	else:
		hud.modulate.a = 1.0
		game.resume()

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
	for l in vb.get_children():
		# (a long name gets cut short with "…" rather than pushing the buttons off the edge)
		(l as Label).clip_text = true
		(l as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		(l as Label).custom_minimum_size.x = 60
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
	# a night studio: a soft violet pool of light behind the car, dark to the edges
	var bg := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color("2c2440"))
	gr.set_color(1, Color("0b0a11"))
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.3, 0.55)
	gt.fill_to = Vector2(0.95, 1.1)
	gt.width = 256
	gt.height = 256
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
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
	env.ambient_light_color = Color("b9b4d6")
	env.ambient_light_energy = 0.45
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
	mb.cyl(Vector3(0, -0.15, 0), 3.6, 0.3, MB.rgb("2b2833"), 48)
	mb.cyl(Vector3(0, -0.42, 0), 3.75, 0.26, MB.rgb("1b1a21"), 48)
	mb.cyl(Vector3(0, -0.29, 0), 3.66, 0.04, Color(1.0, 0.31, 0.55, 0.5), 64)      # (a neon rim: alpha 0.5 glows)
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
	var gl := K.label("GARAGE", 38, K.INK, 400, HORIZONTAL_ALIGNMENT_LEFT)
	gl.add_theme_font_override("font", K.font_spaced(400, 10))
	tb.add_child(gl)
	g_title = gl
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

## Which counters a shop has: Lo-Fi Customs (cars), the Armory (guns), Lo-Fi Threads (who you are); "own":
## your own cars only (the title screen, your garage), to pick one to drive.
const SHOP_TABS := {"customs": ["cars", "paint", "tune", "up"], "armory": ["guns"], "threads": ["driver"], "own": ["cars"]}
const SHOP_NAMES := {"customs": "LO-FI CUSTOMS", "armory": "THE ARMORY", "threads": "LO-FI THREADS", "own": "YOUR CARS"}
var g_mode := "own"
var g_char_try := ""          # a character on the turntable you haven't bought (Lo-Fi Threads)
var g_title: Label

func show_garage(from: int, mode := "own") -> void:
	g_from = from
	g_mode = mode
	g_char_try = ""
	g_gun = ""
	g_slot = ""
	g_try = {}
	title.visible = false
	hud.visible = false
	close_sheet()
	garage.visible = true
	g_index = CARS.index_of(String(game.save.data["car"]))
	g_tab = (SHOP_TABS.get(mode, ["cars"]) as Array)[0]
	g_paint = -1
	_garage_refresh()

func hide_garage() -> void:
	garage.visible = false

func _garage_refresh() -> void:
	var s = game.save.data
	g_coins.get_meta("label").text = K.money(int(s["coins"]))
	for c in g_panel.get_children():
		c.queue_free()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	g_panel.add_child(tabs)
	var allowed: Array = SHOP_TABS.get(g_mode, ["cars"])
	if g_title:
		g_title.text = String(SHOP_NAMES.get(g_mode, "GARAGE"))
	for tdef in [["cars", "Cars", "car"], ["paint", "Paint", "paint"], ["tune", "Tune", "tire"], ["up", "Upgrades", "gear"], ["driver", "Driver", "person"], ["guns", "Guns", "target"]]:
		if not allowed.has(tdef[0]):
			continue
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
	if g_tab == "guns":
		_show_gun()
	elif g_tab == "driver":
		_show_driver(false)
	else:
		_show_car(CARS.LIST[g_index])
	if g_tab == "driver":
		_driver_tab()
	elif g_tab == "guns":
		_guns_tab()
	elif g_tab == "cars":
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
	g_panel.add_child(K.label("Tap a colour to try it on. %s each." % K.money(PAINT_PRICE), 20, K.INK_SOFT, 600))
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
		act = K.button("Buy paint · " + K.money(PAINT_PRICE), K.CORAL, K.CORAL_DK, 30, 0, 80, "coin")
	else:
		act = K.button(K.money(PAINT_PRICE), Color("c9c3bb"), Color("aba59d"), 28, 0, 80, "lock")
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

## The Driver tab: who you are when you step out of the car. Everyone's free; the accessory rides on your head.
func _driver_tab() -> void:
	var s = game.save.data
	var now := String(s.get("avatar", "male-a"))
	var l := K.label(Avatar.name_of(now), 30, K.INK, 500)
	l.add_theme_font_override("font", K.font_spaced(500, 3))
	g_panel.add_child(l)
	g_panel.add_child(K.label("Who steps out when you get out of the car", 17, K.INK_SOFT, 500))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 250)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL     # (all the room the panel has: no empty space under it)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	g_panel.add_child(sc)
	_drag_scroll(sc)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(grid)
	# at Lo-Fi Threads: the first few free, the rest bought (and opened up by level). Tap one to try it on,
	# tap again to buy (or wear) it
	var lv: int = Progress.level(game.save)
	var have: Array = s.get("chars_owned", [])
	for i in Avatar.CHARS.size():
		var c: Array = Avatar.CHARS[i]
		var id: String = c[0]
		var on := id == now
		var trying := id == g_char_try and not on
		var owned_c: bool = Progress.char_price(i) == 0 or have.has(id) or on
		var need: int = Progress.char_level(i)
		var txt := String(c[1])
		var icon := ""
		if not owned_c:
			if lv < need:
				txt = "Lv %d" % need
				icon = "lock"
			else:
				txt = "%s  %s" % [String(c[1]), K.money(Progress.char_price(i))] if trying else K.money(Progress.char_price(i))
		var bg: Color = K.CORAL if on else (K.SKY if trying else K.CREAM)
		var b := K.button(txt, bg, K.CORAL_DK if on else (K.SKY_DK if trying else K.LINE_DK), 15 if trying else 17, 0, 50, icon)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ii := i
		_tap(b, func():
			if owned_c:
				g_char_try = ""
				game.save.data["avatar"] = id
				game.save.save()
			elif lv < need:
				toast("%s opens up at level %d" % [String(Avatar.CHARS[ii][1]), need], "lock", K.PAPER, K.INK, 2.0)
				g_char_try = id
			elif g_char_try != id:
				g_char_try = id           # (on the turntable: have a look first)
			elif int(game.save.data["coins"]) >= Progress.char_price(ii):
				game.save.data["coins"] = int(game.save.data["coins"]) - Progress.char_price(ii)
				var ho: Array = game.save.data.get("chars_owned", [])
				ho.append(id)
				game.save.data["chars_owned"] = ho
				game.save.data["avatar"] = id
				g_char_try = ""
				game.save.save()
				game.sfx("purchase")
				game.buzz(40, 0.7)
			else:
				toast("Not enough cash yet", "coin", Color("ff5c7a"), Color.WHITE)
			_garage_refresh())
		grid.add_child(b)
	var acc_now := String(s.get("acc", ""))
	if Avatar.ACCS.size() < 2:
		return              # (nothing to pick between: no lone "None" button)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	g_panel.add_child(row)
	for a in Avatar.ACCS:
		var aid: String = a[0]
		var on2 := aid == acc_now
		var ab := K.button(String(a[1]), K.CORAL if on2 else K.CREAM, K.CORAL_DK if on2 else K.LINE_DK, 17, 0, 50)
		ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tap(ab, func():
			game.save.data["acc"] = aid
			game.save.save()
			_garage_refresh())
		row.add_child(ab)

# ------------------------------------------------------------------ the Armory

var g_gun := ""               # the gun on show
var g_slot := ""              # the socket you're picking a part for ("": the list of slots)
var g_try := {}               # a build on show that isn't yours yet (a part you're looking at)
var g_try_part := ""

## Your parts: bought ones, plus whatever came on the guns you own (their starting build).
func _owns_part(nm: String) -> bool:
	var s = game.save.data
	if (s.get("parts_owned", []) as Array).has(nm):
		return true
	for gid in s.get("guns", ["pistol"]):
		var b: Dictionary = Weapons.default_build(Weapons.by_id(String(gid)))
		if String(b.get("base", "")) == nm or (b.get("parts", {}) as Dictionary).values().has(nm):
			return true
	return false

func _guns_tab() -> void:
	var s = game.save.data
	if not s.has("guns"):
		s["guns"] = ["pistol"]
	var owned: Array = s["guns"]
	if g_gun == "":
		g_gun = String(s.get("gun", "pistol"))
	var w0: Dictionary = Weapons.by_id(g_gun)
	var have: bool = g_gun in owned
	var mine: Dictionary = Weapons.build_of(game.save, g_gun)
	var shown: Dictionary = g_try if not g_try.is_empty() else mine
	var w: Dictionary = Weapons.with_build(w0, shown)
	var base_w: Dictionary = Weapons.with_build(w0, mine)
	var lv: int = Progress.level(game.save)
	# the gun: < name >
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	g_panel.add_child(nav)
	var prev := K.round_button("left", K.PAPER, K.LINE, 60)
	_tap(prev, func(): _gun_step(-1))
	nav.add_child(prev)
	var nm := K.label(String(w0["name"]), 30, K.INK, 700)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(nm)
	var nxt := K.round_button("right", K.PAPER, K.LINE, 60)
	_tap(nxt, func(): _gun_step(1))
	nav.add_child(nxt)
	# what it does (as built: green where a part on show would make it better, red where worse)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	g_panel.add_child(grid)
	var stat := func(w2: Dictionary) -> Array:
		return [float(w2["dmg"]) * float(w2["pellets"]) / 110.0, float(w2["rate"]) / 12.0, float(w2["range"]) / 300.0,
			1.0 - clampf(float(w2["spread"]) / 0.15, 0.0, 1.0), 1.0 - clampf(float(w2.get("recoil", 1.0)) - 0.35, 0.0, 1.0), float(w2["mag"]) / 100.0]
	var now_s: Array = stat.call(w)
	var was_s: Array = stat.call(base_w)
	var labels := ["Damage", "Fire rate", "Range", "Accuracy", "Control", "Rounds"]
	for i in 6:
		grid.add_child(K.label(labels[i] + ("  %d" % int(w["mag"]) if i == 5 else ""), 16, K.INK_SOFT, 600, HORIZONTAL_ALIGNMENT_LEFT))
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(230, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var nv := clampf(float(now_s[i]), 0.03, 1.0)
		var wv := clampf(float(was_s[i]), 0.03, 1.0)
		bar.draw.connect(func():
			bar.draw_rect(Rect2(Vector2.ZERO, bar.size), K.LINE)
			bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * minf(nv, wv), bar.size.y)), K.TEAL_DK)
			if nv > wv + 0.005:
				bar.draw_rect(Rect2(Vector2(bar.size.x * wv, 0), Vector2(bar.size.x * (nv - wv), bar.size.y)), Color("3fd26b"))
			elif nv < wv - 0.005:
				bar.draw_rect(Rect2(Vector2(bar.size.x * nv, 0), Vector2(bar.size.x * (wv - nv), bar.size.y)), Color("ff5c7a")))
		grid.add_child(bar)
	var extras: Array = []
	if bool(w.get("quiet", false)):
		extras.append("suppressed")
	if float(w.get("zoom", 1.0)) > 1.05:
		extras.append("zoom %.1f×" % float(w["zoom"]))
	if float(w.get("hip", 1.0)) < 0.99:
		extras.append("laser / light")
	if not extras.is_empty():
		g_panel.add_child(K.label(" · ".join(extras), 15, Color("5cc8ff"), 600))
	# buy it / carry it
	var act: Button
	var need: int = int(w0["lvl"])
	if not have:
		if lv < need:
			act = K.button("Level %d  ·  %s" % [need, K.money(int(w0["price"]))], Color("c9c3bb"), Color("aba59d"), 24, 0, 62, "lock")
			act.disabled = true
		else:
			act = K.button("Buy  ·  " + K.money(int(w0["price"])), K.CORAL, K.CORAL_DK, 26, 0, 62, "coin")
	elif String(s.get("gun", "pistol")) == g_gun:
		act = K.button("Carrying this one", Color("c9c3bb"), Color("aba59d"), 24, 0, 62, "check")
		act.disabled = true
	else:
		act = K.button("Carry this one", K.TEAL, K.TEAL_DK, 26, 0, 62, "play")
	_tap(act, func():
		if not (g_gun in owned):
			if int(s["coins"]) < int(w0["price"]):
				toast("Not enough cash", "coin", Color("ff5c7a"), Color.WHITE)
				return
			s["coins"] = int(s["coins"]) - int(w0["price"])
			owned.append(g_gun)
			game.sfx("purchase", -4.0)
			game.buzz(50, 0.8)
		s["gun"] = g_gun
		game.save.save()
		if game.gunplay:
			game.gunplay.equip()
		_garage_refresh())
	act.custom_minimum_size.y = 54
	g_panel.add_child(act)
	if not have:
		g_panel.add_child(K.label("Buy it to build it up: every part's swappable here", 16, K.INK_SOFT, 500))
		return
	# the parts: a slot for each socket the build has (tap one: what fits there)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 110)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	g_panel.add_child(sc)
	_drag_scroll(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	if g_slot == "":
		_gun_slots(list, w0, shown)
	else:
		_gun_picker(list, w0, mine, g_slot)

func _gun_step(d: int) -> void:
	var i := 0
	for k in Weapons.LIST.size():
		if Weapons.LIST[k]["id"] == g_gun:
			i = k
	g_gun = String(Weapons.LIST[posmod(i + d, Weapons.LIST.size())]["id"])
	g_slot = ""
	g_try = {}
	_garage_refresh()

## The sockets this build has that take a part (in a sensible order), each with what's on it.
func _gun_sockets(w: Dictionary, b: Dictionary) -> Array:
	var have := {}
	var base: Dictionary = Weapons.part(String(b.get("base", "")))
	for s2 in base.get("sockets", {}):
		have[s2] = true
	for s3 in (b.get("parts", {}) as Dictionary):
		for s4 in Weapons.part(String(b["parts"][s3])).get("sockets", {}):
			have[s4] = true
	var out: Array = []
	for s5 in have:
		if Weapons.parts_for(w, s5).size() > 0 and not String(s5).begins_with("hand"):
			out.append(s5)
	out.sort_custom(func(a, c):
		var ia := Weapons.SOCKET_ORDER.find(a)
		var ic := Weapons.SOCKET_ORDER.find(c)
		return (ia if ia >= 0 else 99) < (ic if ic >= 0 else 99))
	return out

func _part_icon(nm: String, h := 34.0) -> Control:
	var path := "res://assets/guns/icons/%s.png" % nm
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(h * 3.0, h)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(path):
		tr.texture = load(path)
	return tr

func _gun_slots(list: VBoxContainer, w: Dictionary, b: Dictionary) -> void:
	# the builds it comes in, as a start
	var ps: Array = Weapons.presets(w)
	if ps.size() > 1:
		# (wrapping onto more rows: a gun with a lot of builds mustn't push the panel off the screen)
		var pr := HFlowContainer.new()
		pr.add_theme_constant_override("h_separation", 6)
		pr.add_theme_constant_override("v_separation", 6)
		list.add_child(pr)
		for pn in ps:
			var pb := Weapons.preset_build(w, String(pn))
			var cost := 0
			for pv in (pb["parts"] as Dictionary).values():
				if not _owns_part(String(pv)):
					cost += Weapons.part_price(w, String(pv))
			var same: bool = JSON.stringify(pb["parts"], "", true) == JSON.stringify(b.get("parts", {}), "", true)
			var lbl := Weapons.nice(String(pn)).replace(String(w["name"]), "").strip_edges()
			var chip := K.button(lbl if cost == 0 else "%s %s" % [lbl, K.money(cost)], K.CORAL if same else K.CREAM, K.CORAL_DK if same else K.LINE_DK, 14, 0, 44)
			if not same:
				chip.add_theme_color_override("font_color", K.INK)
			chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var pnn := String(pn)
			_tap(chip, func(): _buy_build(w, Weapons.preset_build(w, pnn)))
			pr.add_child(chip)
	for sk in _gun_sockets(w, b):
		var on := String((b.get("parts", {}) as Dictionary).get(sk, ""))
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, 52)
		row.add_theme_stylebox_override("normal", K.box(K.CREAM, 14, 0, Color.TRANSPARENT, 8))
		row.add_theme_stylebox_override("pressed", K.box(K.LINE, 14, 0, Color.TRANSPARENT, 8))
		row.add_theme_stylebox_override("hover", K.box(K.CREAM, 14, 0, Color.TRANSPARENT, 8))
		var hb := HBoxContainer.new()
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 12
		hb.offset_right = -26
		hb.add_theme_constant_override("separation", 10)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hb)
		var sl := K.label(Weapons.socket_name(sk), 16, K.INK_SOFT, 700, HORIZONTAL_ALIGNMENT_LEFT)
		sl.custom_minimum_size = Vector2(120, 0)
		hb.add_child(sl)
		if on != "":
			hb.add_child(_part_icon(on, 30))
		var pl := K.label(Weapons.nice(on) if on != "" else "None", 17, K.INK, 600, HORIZONTAL_ALIGNMENT_LEFT)
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pl.clip_text = true
		pl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hb.add_child(pl)
		var n_opts := Weapons.parts_for(w, sk).size()
		hb.add_child(K.label("%d ›" % n_opts, 16, K.INK_SOFT, 600))
		var skk := String(sk)
		_tap(row, func():
			g_slot = skk
			g_try = {}
			_garage_refresh())
		list.add_child(row)

func _gun_picker(list: VBoxContainer, w: Dictionary, mine: Dictionary, sk: String) -> void:
	var lv: int = Progress.level(game.save)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	list.add_child(top)
	var bk := K.button("‹ " + Weapons.socket_name(sk), K.PAPER, K.LINE, 18, 0, 46)
	_tap(bk, func():
		g_slot = ""
		g_try = {}
		_garage_refresh())
	top.add_child(bk)
	var opts: Array = Weapons.parts_for(w, sk)
	var cur := String((mine.get("parts", {}) as Dictionary).get(sk, ""))
	var can_none: bool = opts.size() > 0 and not Weapons.socket_required(w, sk)
	if can_none:
		opts.push_front("")
	for nm in opts:
		var pn := String(nm)
		var owned_p: bool = pn == "" or _owns_part(pn)
		var need: int = Weapons.part_level(w, pn) if pn != "" else 1
		var price: int = Weapons.part_price(w, pn) if pn != "" else 0
		var on := pn == cur
		var trying := pn == g_try_part and not g_try.is_empty() and not on
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, 58)
		var bg: Color = K.CORAL if on else (K.SKY if trying else K.CREAM)
		row.add_theme_stylebox_override("normal", K.box(bg, 14, 0, Color.TRANSPARENT, 8))
		row.add_theme_stylebox_override("pressed", K.box(K.LINE, 14, 0, Color.TRANSPARENT, 8))
		row.add_theme_stylebox_override("hover", K.box(bg, 14, 0, Color.TRANSPARENT, 8))
		var hb := HBoxContainer.new()
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 10
		hb.offset_right = -26
		hb.add_theme_constant_override("separation", 10)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hb)
		if pn != "":
			hb.add_child(_part_icon(pn, 34))
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", -3)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(vb)
		var t1 := K.label(Weapons.nice(pn) if pn != "" else "None", 17, K.INK, 650, HORIZONTAL_ALIGNMENT_LEFT)
		t1.clip_text = true
		vb.add_child(t1)
		vb.add_child(K.label(Weapons.describe(pn) if pn != "" else "Leave it bare", 13, Color(1, 1, 1, 0.85) if on else K.INK_SOFT, 500, HORIZONTAL_ALIGNMENT_LEFT))
		var right := ""
		if on:
			right = "On"
		elif owned_p:
			right = "Owned"
		elif lv < need:
			right = "Lv %d" % need
		else:
			right = K.money(price)
		hb.add_child(K.label(right, 16, K.INK if not (lv < need and not owned_p) else K.INK_SOFT, 700))
		_tap(row, func():
			var nb: Dictionary = {"base": String(mine.get("base", "")), "parts": (mine.get("parts", {}) as Dictionary).duplicate()}
			if pn == "":
				nb["parts"].erase(sk)
			else:
				nb["parts"][sk] = pn
			# (a part's own sockets go if it does: a barrel's muzzle with the barrel)
			if cur != "" and cur != pn:
				for s2 in Weapons.part(cur).get("sockets", {}):
					if not (pn != "" and (Weapons.part(pn).get("sockets", {}) as Dictionary).has(s2)):
						nb["parts"].erase(s2)
			if owned_p:
				g_try = {}
				_set_build(nb)
			elif g_try_part != pn or g_try.is_empty():
				g_try = nb            # (on show first: tap again to buy it)
				g_try_part = pn
				_garage_refresh()
			elif lv < need:
				toast("Opens up at level %d" % need, "lock", K.PAPER, K.INK, 2.0)
			else:
				_buy_build(w, nb))
		list.add_child(row)

## Put a build on the gun, buying any parts it needs that you haven't got.
func _buy_build(w: Dictionary, nb: Dictionary) -> void:
	var s = game.save.data
	var lv: int = Progress.level(game.save)
	var cost := 0
	var buy: Array = []
	for pv in (nb.get("parts", {}) as Dictionary).values():
		if not _owns_part(String(pv)):
			if lv < Weapons.part_level(w, String(pv)):
				toast("%s opens up at level %d" % [Weapons.nice(String(pv)), Weapons.part_level(w, String(pv))], "lock", K.PAPER, K.INK, 2.0)
				return
			cost += Weapons.part_price(w, String(pv))
			buy.append(String(pv))
	if int(s["coins"]) < cost:
		toast("Not enough cash", "coin", Color("ff5c7a"), Color.WHITE)
		return
	s["coins"] = int(s["coins"]) - cost
	var po: Array = s.get("parts_owned", [])
	po.append_array(buy)
	s["parts_owned"] = po
	if cost > 0:
		game.sfx("purchase", -4.0)
		game.buzz(40, 0.7)
	g_try = {}
	_set_build(nb)

func _set_build(nb: Dictionary) -> void:
	var s = game.save.data
	var gb: Dictionary = s.get("gun_builds", {})
	gb[g_gun] = nb
	s["gun_builds"] = gb
	game.save.save()
	if game.gunplay and String(s.get("gun", "")) == g_gun:
		game.gunplay.equip()
	game.sfx("mag_in", -6.0, 1.1)
	_garage_refresh()

## The gun on the turntable, big, on its own.
func _show_gun() -> void:
	for c in g_car.get_children():
		c.queue_free()
	g_neon = null
	var w0: Dictionary = Weapons.by_id(g_gun if g_gun != "" else String(game.save.data.get("gun", "pistol")))
	var b: Dictionary = g_try if not g_try.is_empty() else Weapons.build_of(game.save, String(w0["id"]))
	var asm: Dictionary = Weapons.assemble(w0, b)
	var mi := MeshInstance3D.new()
	mi.mesh = asm["mesh"]
	mi.material_override = g_mat
	var ab: AABB = (asm["mesh"] as Mesh).get_aabb()
	var k: float = 4.2 / maxf(ab.size.z, 0.2)
	mi.scale = Vector3.ONE * k
	mi.position = Vector3(-ab.get_center().x * k, 1.3 - ab.get_center().y * k, -ab.get_center().z * k)
	g_car.add_child(mi)
	# (lit up for the showroom: these are dark guns)
	for lp in [Vector3(2.5, 3.0, 3.5), Vector3(-3.0, 2.0, -2.5)]:
		var ol := OmniLight3D.new()
		ol.position = lp
		ol.omni_range = 9.0
		ol.light_energy = 1.6
		g_car.add_child(ol)

func _show_driver(with_gun := false) -> void:
	for c in g_car.get_children():
		c.queue_free()
	g_neon = null
	var av := Avatar.new()
	g_car.add_child(av)
	av.setup(g_char_try if g_char_try != "" and not with_gun else String(game.save.data.get("avatar", "male-a")), String(game.save.data.get("acc", "")), g_mat)
	av.scale = Vector3.ONE * 1.55         # (bigger than life on the turntable, facing you)
	av.play("idle")
	if with_gun and av.skel:
		var s = game.save.data
		var w: Dictionary = Weapons.loadout(game.save, String(s.get("gun", "pistol")))
		av.hold(w, g_mat)
		av.play("holding-both")
		# a showroom pose: both hands on it, aimed off ahead and to their right (in the character's own space,
		# so it turns round with them on the turntable)
		if av.aim:
			# (a long gun shouldered, the body side-on to it: the target's off to their left)
			av.aim.target_local = av.local_point(Vector3(1.7, 1.3, 2.8) if float(w.get("fore", 0.0)) > 0.0 else Vector3(-1.2, 1.3, 3.2))
			av.aim.weight = 1.0

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
	if d.get("legend", false):
		g_panel.add_child(K.label("LEGENDARY · %d of %d" % [g_index + 1, CARS.LIST.size()], 20, Color("b8892b"), 800))
	else:
		g_panel.add_child(K.label("%d of %d" % [g_index + 1, CARS.LIST.size()], 20, K.INK_SOFT, 600))
	# drift car or road car: says what the handbrake does in it
	var drifter: bool = d.get("drifter", false)
	g_panel.add_child(K.label("DRIFT CAR · the handbrake throws it into a drift" if drifter else "ROAD CAR · grips, no drifting (that needs a drift car)",
		18, Color("ff4fb0") if drifter else K.INK_SOFT, 800))
	var stats := [["Power", d["power"], 0.95, 1.6], ["Top speed", d["speed"], 0.95, 1.25], ["Grip", d["grip"], 0.95, 1.16]]
	if drifter:
		stats.append(["Drift", d["drift"], 1.0, 1.6])
	for st in stats:
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
			pip.add_theme_stylebox_override("panel", K.box(K.CORAL if k < n else K.LINE, 8, 0, Color.TRANSPARENT, 0))
			pips.add_child(pip)
		hb.add_child(pips)
		g_panel.add_child(hb)
	var owned: bool = game.save.owns(d["id"])
	var selected: bool = String(s["car"]) == d["id"]
	var price: int = d["price"]
	var need: int = Progress.car_level(String(d["id"]))
	var act: Button
	if selected:
		act = K.button("Driving this one", Color("c9c3bb"), Color("aba59d"), 30, 0, 84, "check")
		act.disabled = true
	elif owned:
		act = K.button("Drive this one", K.TEAL, K.TEAL_DK, 32, 0, 84, "play")
	elif g_mode != "customs":
		act = K.button("Sold at Lo-Fi Customs", Color("c9c3bb"), Color("aba59d"), 26, 0, 84, "lock")
		act.disabled = true
	elif Progress.level(game.save) < need:
		act = K.button("Level %d  ·  %s" % [need, K.money(price)], Color("c9c3bb"), Color("aba59d"), 28, 0, 84, "lock")
		act.disabled = true
	elif int(s["coins"]) >= price:
		act = K.button("Buy · " + K.money(price), K.CORAL, K.CORAL_DK, 32, 0, 84, "coin")
	else:
		act = K.button(K.money(price), Color("c9c3bb"), Color("aba59d"), 30, 0, 84, "lock")
		act.disabled = true
	_tap(act, _garage_action)
	g_panel.add_child(act)

func _garage_step(dlt: int) -> void:
	g_index = posmod(g_index + dlt, CARS.LIST.size())
	if g_mode == "own":
		# (your own cars only)
		var tries := 0
		while not game.save.owns(String(CARS.LIST[g_index]["id"])) and tries < CARS.LIST.size():
			g_index = posmod(g_index + dlt, CARS.LIST.size())
			tries += 1
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
	elif g_mode == "customs" and int(s["coins"]) >= int(d["price"]) and Progress.level(game.save) >= Progress.car_level(String(d["id"])):
		s["coins"] = int(s["coins"]) - int(d["price"])
		s["owned"].append(d["id"])
		s["car"] = d["id"]
		game.save.save()
		game.car_changed()
		game.sfx("purchase")
		game.buzz(60, 0.9)
		game.ach_check()
		toast("Yours! Parked in your garage too" if game.property.garage_open() else "Yours! Call Dez any time to have it brought to you",
			"car", Color("3fd26b"), Color.WHITE, 2.6)
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
		var nb := K.button("Neon underglow kit · " + K.money(SaveData.NEON_KIT), K.CORAL, K.CORAL_DK, 22, 0, 58, "coin")
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
	# tyre smoke: any colour you like (free)
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 6)
	sr.add_child(K.label("Smoke", 20, K.INK_SOFT, 650))
	var cur_s := int(tn.get("smoke", 0))
	for si in CarScript.SMOKE.size():
		var sw2 := Button.new()
		sw2.focus_mode = Control.FOCUS_NONE
		sw2.custom_minimum_size = Vector2(40, 40)
		var sb2 := K.box(Color(CarScript.SMOKE[si]), 20, 0, Color.TRANSPARENT, 0)
		sb2.border_color = K.INK if si == cur_s else K.LINE_DK
		sb2.set_border_width_all(4 if si == cur_s else 1)
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			sw2.add_theme_stylebox_override(st, sb2)
		var sv := si
		_tap(sw2, func(): set_tn.call("smoke", sv))
		sr.add_child(sw2)
	g_panel.add_child(sr)

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
		pip.add_theme_stylebox_override("panel", K.box((K.CORAL if col.get_luminance() < 0.35 or col.a < 0.95 else col) if k <= v else K.LINE, 6, 0, Color.TRANSPARENT, 0))
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
			b = K.button(K.money(cost), cols[u], (cols[u] as Color).darkened(0.2), 24, 120, 60, "coin")
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

# ---------------------------------------------------------------- the weapon wheel
## Hold the weapon button and slide onto a gun (let go to take it), or tap the button and tap a gun.
## "Hands" puts it away. The world waits while it's open.
var wheel_layer: Control
var _wh_ring: Control
var _wh_ids: Array = []      # round the wheel from the top, clockwise: "" (hands), then your guns
var _wh_hi := -1             # the one under your finger
var _wh_t := 0
var _wh_moved := false
const WH_R := 214.0
const WH_IN := 86.0

func wheel_open() -> bool:
	return wheel_layer != null and wheel_layer.visible

func open_weapon_wheel() -> void:
	if game.state != game.DRIVE or wheel_open():
		return
	if wheel_layer == null:
		wheel_layer = Control.new()
		wheel_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		wheel_layer.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(wheel_layer)
		var dim := ColorRect.new()
		dim.color = Color(K.DIM, 0.45)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wheel_layer.add_child(dim)
		_wh_ring = Control.new()
		_wh_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_wh_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_wh_ring.draw.connect(_draw_weapon_wheel)
		wheel_layer.add_child(_wh_ring)
	var gp = game.gunplay
	_wh_ids = [""]
	var owned: Array = game.save.data.get("guns", ["pistol"])
	for w in Weapons.LIST:
		if w["id"] in owned:
			_wh_ids.append(String(w["id"]))
	_wh_hi = 0 if gp.holstered else maxi(0, _wh_ids.find(String(gp.weapon.get("id", ""))))
	_wh_t = Time.get_ticks_msec()
	_wh_moved = false
	game.pause(false)
	wheel_layer.visible = true
	wheel_layer.modulate.a = 0.0
	create_tween().tween_property(wheel_layer, "modulate:a", 1.0, 0.1)
	_wh_ring.queue_redraw()

func _close_wheel(pick: Variant) -> void:
	wheel_layer.visible = false
	game.drop_touches()
	game.resume()
	if pick != null:
		game.gunplay.select(String(pick))

## Which slice is under pos (-1: the middle, or off the wheel).
func _wheel_seg(pos: Vector2) -> int:
	var d := pos - _vs() * 0.5
	var r := d.length()
	if r < WH_IN * 0.75 or r > WH_R * 1.12:
		return -1
	var n := _wh_ids.size()
	var step := TAU / n
	return int(floor(fposmod(atan2(d.y, d.x) + PI * 0.5 + step * 0.5, TAU) / step)) % n

func _wheel_input(e: InputEvent) -> void:
	var pos := Vector2.INF
	var press := -1           # 1 down, 0 up, -1 a move
	if DisplayServer.is_touchscreen_available():
		if e is InputEventScreenTouch:
			pos = e.position
			press = 1 if e.pressed else 0
		elif e is InputEventScreenDrag:
			pos = e.position
	else:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			pos = e.position
			press = 1 if e.pressed else 0
		elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			pos = e.position
	if pos == Vector2.INF:
		return
	get_viewport().set_input_as_handled()
	var seg := _wheel_seg(pos)
	if press != 0:
		if seg >= 0 and seg != _wh_hi:
			_wh_hi = seg
			_wh_moved = true
			game.ui_tap()
			_wh_ring.queue_redraw()
		return
	# let go: on a slice takes it; a quick tap on the button leaves it open for a second tap;
	# anywhere else shuts it as it was
	if seg >= 0:
		_close_wheel(_wh_ids[seg])
	elif Time.get_ticks_msec() - _wh_t < 350 and not _wh_moved:
		return
	else:
		_close_wheel(null)

func _draw_weapon_wheel() -> void:
	var ci := _wh_ring
	var c := _vs() * 0.5
	var n := _wh_ids.size()
	var step := TAU / n
	var gp = game.gunplay
	ci.draw_circle(c, WH_R + 10.0, Color(0.04, 0.035, 0.06, 0.5))
	for i in n:
		var a0 := -PI * 0.5 + (float(i) - 0.5) * step + 0.03
		var a1 := a0 + step - 0.06
		var pts := PackedVector2Array()
		for k in 21:
			var a := lerpf(a0, a1, k / 20.0)
			pts.append(c + Vector2(cos(a), sin(a)) * WH_R)
		for k in 21:
			var a := lerpf(a1, a0, k / 20.0)
			pts.append(c + Vector2(cos(a), sin(a)) * WH_IN)
		var hi := i == _wh_hi
		ci.draw_colored_polygon(pts, Color(K.CORAL, 0.9) if hi else Color(0.1, 0.095, 0.14, 0.9))
		pts.append(pts[0])
		ci.draw_polyline(pts, Color(1, 1, 1, 0.55 if hi else 0.2), 1.5, true)
		var am := -PI * 0.5 + i * step
		var mid := c + Vector2(cos(am), sin(am)) * (WH_IN + WH_R) * 0.5
		var id: String = _wh_ids[i]
		var col := Color.WHITE if hi else Color(1, 1, 1, 0.82)
		gun_glyph(ci, id, mid + Vector2(0, -10), 30.0, col)
		var nm := "Hands" if id == "" else String(Weapons.by_id(id)["name"])
		ci.draw_string(K.font(650), mid + Vector2(-60, 30), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, col)
	# the middle: what you'd take, and its rounds
	ci.draw_circle(c, WH_IN - 8.0, Color(0.06, 0.055, 0.09, 0.92))
	ci.draw_arc(c, WH_IN - 8.0, 0, TAU, 48, Color(1, 1, 1, 0.18), 1.5, true)
	if _wh_hi >= 0 and _wh_hi < n:
		var id2: String = _wh_ids[_wh_hi]
		var title := "Hands" if id2 == "" else String(Weapons.by_id(id2)["name"])
		var sub := "put it away" if id2 == "" else "%d / %d" % [int(gp.ammo.get(id2, Weapons.by_id(id2)["mag"])), int(Weapons.by_id(id2)["mag"])]
		ci.draw_string(K.font(700), c + Vector2(-70, -2), title, HORIZONTAL_ALIGNMENT_CENTER, 140, 20, Color.WHITE)
		ci.draw_string(K.font(500), c + Vector2(-70, 22), sub, HORIZONTAL_ALIGNMENT_CENTER, 140, 14, Color(1, 1, 1, 0.6))

## A flat silhouette of a gun (pointing right), s pixels to half its length; "" is an open hand.
func gun_glyph(ci: CanvasItem, id: String, p: Vector2, s: float, col: Color) -> void:
	var shapes: Array = GLYPHS.get(id, GLYPHS["pistol"]) if id != "" else GLYPHS["hand"]
	for sh in shapes:
		var pts := PackedVector2Array()
		var a: Array = sh
		if a.size() == 4:
			pts = PackedVector2Array([Vector2(a[0], a[1]), Vector2(a[2], a[1]), Vector2(a[2], a[3]), Vector2(a[0], a[3])])
		else:
			for k in range(0, a.size(), 2):
				pts.append(Vector2(a[k], a[k + 1]))
		for k in pts.size():
			pts[k] = p + pts[k] * s
		ci.draw_colored_polygon(pts, col)

## Each a list of boxes [x0, y0, x1, y1] or polygons [x, y, x, y, ...], in half-lengths.
const GLYPHS := {
	"pistol": [[-0.62, -0.42, 0.62, -0.1], [-0.6, -0.1, -0.22, -0.1, -0.36, 0.55, -0.76, 0.55], [-0.2, -0.1, 0.08, -0.1, 0.08, 0.12, -0.24, 0.12]],
	"revolver": [[-0.05, -0.34, 0.82, -0.16], [-0.32, -0.4, 0.02, 0.04], [-0.6, -0.04, -0.3, -0.04, -0.36, 0.56, -0.72, 0.5], [-0.45, -0.36, -0.3, 0.0]],
	"smg": [[-0.55, -0.3, 0.55, 0.02], [0.55, -0.2, 0.86, -0.1], [-0.02, 0.02, 0.16, 0.66], [-0.42, 0.02, -0.24, 0.02, -0.3, 0.45, -0.48, 0.45], [-0.95, -0.22, -0.55, -0.12], [-0.95, -0.12, -0.85, 0.2]],
	"shotgun": [[-0.38, -0.24, -0.02, 0.06], [-0.02, -0.2, 1.0, -0.08], [0.2, -0.08, 0.62, 0.06], [-1.0, -0.12, -0.38, -0.24, -0.38, 0.06, -0.9, 0.24, -1.0, 0.24], [-0.32, 0.06, -0.2, 0.06, -0.24, 0.3, -0.36, 0.3]],
	"rifle": [[-0.48, -0.26, 0.32, 0.04], [0.32, -0.2, 1.0, -0.12], [0.3, -0.3, 0.42, -0.2], [0.0, 0.04, 0.16, 0.04, 0.3, 0.56, 0.12, 0.6], [-0.36, 0.04, -0.2, 0.04, -0.26, 0.42, -0.42, 0.42], [-1.0, -0.2, -0.48, -0.24, -0.48, 0.04, -1.0, 0.2]],
	"sniper": [[-0.4, -0.2, 0.22, 0.06], [0.22, -0.14, 1.05, -0.06], [-0.3, -0.44, 0.22, -0.3], [-0.12, -0.3, 0.0, -0.2], [-0.02, 0.06, 0.1, 0.06, 0.08, 0.36, -0.04, 0.36], [-1.0, -0.16, -0.4, -0.2, -0.4, 0.06, -0.7, 0.06, -0.84, 0.28, -1.0, 0.28]],
	"hand": [[-0.36, -0.05, 0.3, 0.55], [-0.36, -0.5, -0.22, -0.05], [-0.18, -0.62, -0.04, -0.05], [0.0, -0.58, 0.14, -0.05], [0.18, -0.46, 0.3, -0.05], [0.3, 0.1, 0.3, 0.3, 0.58, 0.0, 0.52, -0.12]],
}
