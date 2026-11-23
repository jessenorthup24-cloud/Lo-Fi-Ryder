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
var g_spin := 0.0
var g_drag := 0.0

func setup(g: Node) -> void:
	game = g
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	popups = _full(Control.MOUSE_FILTER_IGNORE)
	_build_hud()
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
		game.ui_tap()
		f.call())

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
	left.add_child(K.outlined(K.label("drift around a cozy little island", 34, Color.WHITE, 650, HORIZONTAL_ALIGNMENT_LEFT), K.INK, 10))
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
	var camb := K.round_button("eye", K.PAPER, K.LINE, 64)
	camb.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	camb.position = Vector2(-300, 230)
	_tap(camb, func(): game.toggle_cam())
	hud.add_child(camb)
	# the challenge card, top middle
	chal_card = K.card(K.PAPER, 30)
	chal_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	chal_card.custom_minimum_size = Vector2(380, 0)
	chal_card.position = Vector2(-190, 18)
	chal_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(chal_card)
	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", -2)
	chal_card.add_child(cvb)
	chal_name = K.label("", 24, K.INK_SOFT, 650)
	cvb.add_child(chal_name)
	chal_main = K.label("", 44, K.INK, 700)
	cvb.add_child(chal_main)
	chal_sub = K.label("", 22, K.INK_SOFT, 600)
	cvb.add_child(chal_sub)
	chal_card.visible = false
	# the drift meter, below it
	drift_card = PanelContainer.new()
	drift_card.add_theme_stylebox_override("panel", K.box(Color(0.12, 0.12, 0.12, 0.5), 30, 0, Color.TRANSPARENT, 16))
	drift_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	drift_card.custom_minimum_size = Vector2(340, 0)
	drift_card.position = Vector2(-170, 150)
	drift_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(drift_card)
	var dvb := VBoxContainer.new()
	dvb.add_theme_constant_override("separation", 0)
	drift_card.add_child(dvb)
	var dh := HBoxContainer.new()
	dh.alignment = BoxContainer.ALIGNMENT_CENTER
	dh.add_theme_constant_override("separation", 12)
	dvb.add_child(dh)
	drift_lbl = K.outlined(K.label("0", 54, Color.WHITE, 700), K.INK, 12)
	dh.add_child(drift_lbl)
	combo_lbl = K.outlined(K.label("x1", 40, Color("e8dcc4"), 700), K.INK, 10)
	dh.add_child(combo_lbl)
	angle_lbl = K.label("DRIFT", 22, Color(1, 1, 1, 0.85), 650)
	dvb.add_child(angle_lbl)
	combo_bar = K.bar(300, 10, Color("e8dcc4"), Color(1, 1, 1, 0.25))
	dvb.add_child(combo_bar)
	drift_card.modulate.a = 0.0
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
	# steering, bottom left
	ctl["left"] = _pad("left", Vector2(40, -210), Vector2(170, 170), true, K.PAPER)
	ctl["right"] = _pad("right", Vector2(230, -210), Vector2(170, 170), true, K.PAPER)
	# pedals, bottom right
	ctl["brake"] = _pad("brake", Vector2(-420, -210), Vector2(130, 170), false, K.PAPER)
	ctl["gas"] = _pad("gas", Vector2(-270, -250), Vector2(150, 210), false, K.PAPER)
	ctl["hand"] = _pad("hand", Vector2(-420, -360), Vector2(130, 120), false, K.PAPER)
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
	hud.add_child(p)
	return p

## Which control (if any) a touch at pos lands on. Pads have generous edges.
func control_at(pos: Vector2) -> String:
	if not hud.visible or overlay.visible:
		return ""
	for k in ["hand", "gas", "brake", "left", "right"]:
		var c: Control = ctl[k]
		if c.get_global_rect().grow(22).has_point(pos):
			return k
	return ""

func pressed_controls(held: Dictionary) -> void:
	for k in ctl:
		var c: Control = ctl[k]
		var on: bool = held.get(k, false)
		c.scale = c.scale.lerp(Vector2.ONE * (0.93 if on else 1.0), 0.5)
		c.modulate = Color(1.15, 1.15, 1.15, 1.0) if on else Color(1, 1, 1, 0.9)

func show_hud() -> void:
	title.visible = false
	garage.visible = false
	hud.visible = true

func hud_update(d: Dictionary) -> void:
	_hud_data = d
	speed_lbl.text = str(int(round(d["kmh"])))
	gear_lbl.text = "R" if game.car.speed < -0.5 else str(int(d["gear"]))
	rpm_bar.value = d["rpm"]
	clock_lbl.text = d["clock"] if bool(game.save.setting("clock")) else ""
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
		angle_lbl.text = "%d°" % int(d["angle"])
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
	chal_card.visible = not z.is_empty() or not t.is_empty()
	if not z.is_empty():
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
	drift_card.pivot_offset = drift_card.size * 0.5
	drift_card.scale = Vector2(1.15, 1.15)
	create_tween().tween_property(drift_card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func drift_lost() -> void:
	_bank_t = 0.9
	drift_lbl.text = "Crashed!"
	angle_lbl.text = "drift lost"
	_drift_show = 1.0

func popup_text(text: String, col := Color.WHITE) -> void:
	var l := K.outlined(K.label(text, 40, col, 700), K.INK, 12)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	popups.add_child(l)
	l.size = Vector2(600, 60)
	l.position = _vs() * 0.5 - Vector2(300, 150)
	l.pivot_offset = Vector2(300, 30)
	l.scale = Vector2(0.5, 0.5)
	var t := create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "position:y", l.position.y - 50, 1.0)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.7)
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

func challenge_end() -> void:
	chal_card.visible = false

func challenge_result(name: String, score: String, medal: int, pay: int, record: bool) -> void:
	var cols := [Color("c9c3bb"), Color("b98b62"), Color("b3b8bd"), Color("d4b25c")]
	var names := ["No medal", "Bronze", "Silver", "Gold"]
	var p := K.card(K.PAPER, 36)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
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
	if pay > 0:
		vb.add_child(K.label("+%d coins" % pay, 30, K.INK, 700))
	if record:
		vb.add_child(K.label("New personal best!", 26, K.INK_SOFT, 700))
	popups.add_child(p)
	await get_tree().process_frame
	p.position = (_vs() - p.size) * 0.5 - Vector2(0, 60)
	p.pivot_offset = p.size * 0.5
	p.scale = Vector2(0.6, 0.6)
	var t := create_tween()
	t.tween_property(p, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(3.2)
	t.tween_property(p, "modulate:a", 0.0, 0.4)
	t.tween_callback(p.queue_free)
	if medal > 0:
		game.sfx("record")
		game.buzz(80, 0.8)

func tick(dt: float) -> void:
	if title.visible:
		_title_tick(Time.get_ticks_msec() / 1000.0)
	if garage.visible:
		g_spin += dt * 0.35
		g_turn.rotation.y = g_spin
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
	mini_vp.size = Vector2i(196, 196)
	mini_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(mini_vp)
	mini_cam = Camera3D.new()
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
	var vb: VBoxContainer = await _sheet("Settings", "gear", K.LILAC, 700.0)
	var st = game.save.data["settings"]
	vb.add_child(_setting_slider("music", "Music", st["music"], func(v): game.set_setting("music", v)))
	vb.add_child(_setting_slider("sound", "Sounds", st["sfx"], func(v): game.set_setting("sfx", v)))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 26)
	g.add_theme_constant_override("v_separation", 8)
	vb.add_child(g)
	g.add_child(_setting_toggle("tire", "Drift help", st["assist"], func(v): game.set_setting("assist", v)))
	g.add_child(_setting_toggle("vibe", "Vibration", st["haptics"], func(v): game.set_setting("haptics", v)))
	g.add_child(_setting_toggle("shadow", "Shadows", st["shadows"], func(v): game.set_setting("shadows", v)))
	g.add_child(_setting_toggle("sun", "Show clock", st["clock"], func(v): game.set_setting("clock", v)))
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
	vb.add_child(reset)
	var credit: String = game.sound.credit_line()
	var cl := K.label(("Music by %s (CC0) · " % credit if credit != "" else "") + "Models: Kenney (CC0), Tiny Car Pack · " + build_label(), 18, K.INK_SOFT, 500)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(cl)
	var done := K.button("Done", K.LILAC, K.LILAC_DK, 32, 0, 76)
	_tap(done, func(): _back_from(from_pause))
	vb.add_child(done)

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
	var vb: VBoxContainer = await _sheet("How to drive", "car", K.TEAL, 760.0)
	for line in [
		["left", "Steer with the arrows on the left."],
		["play", "GAS and BRAKE on the right. Hold BRAKE when stopped to reverse."],
		["tire", "Tap DRIFT (the handbrake) while steering to swing the tail out, then keep the gas down and steer into the slide."],
		["star", "Drifts score points and coins. Chain them for a bigger multiplier. Don't crash mid-drift!"],
		["flag", "Drive into an orange ring for a drift zone, a blue ring for a time trial, a purple ring for a drift run. Hidden coins are dotted all over the island."],
	]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		hb.add_child(Icon.new(line[0], K.INK, 38))
		var l := K.label(line[1], 24, K.INK, 600, HORIZONTAL_ALIGNMENT_LEFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(640, 0)
		hb.add_child(l)
		vb.add_child(hb)
	var ok := K.button("Let's go", K.TEAL, K.TEAL_DK, 32, 0, 76, "play")
	_tap(ok, close_sheet)
	vb.add_child(ok)

# ------------------------------------------------------------------ the map

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
	vp.size = Vector2i(int(sz), int(sz))
	svc.add_child(vp)
	var mc := Camera3D.new()
	mc.projection = Camera3D.PROJECTION_ORTHOGONAL
	mc.size = 1000.0
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
		var c := Vector2((cp.x / 1000.0 + 0.5) * sz, (cp.z / 1000.0 + 0.5) * sz)
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
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	sc.add_child(list)
	for z in island.zones:
		var best := int(game.save.data["zones"].get(z["id"], 0))
		list.add_child(_chal_row(z["name"], "Drift zone · best %s" % K.fmt(best) if best > 0 else "Drift zone", int(game.save.data["medals"].get(z["id"], 0)), Color("ff8a5c"),
			game._road_spot(z["start"], 0.0)))
	for t in island.trials:
		var best2: float = float(game.save.data["trials"].get(t["id"], 0.0))
		var info := "Time trial" if t["kind"] == "time" else "Drift run"
		if best2 > 0.0:
			info += (" · best %.2f s" % best2) if t["kind"] == "time" else (" · best %s" % K.fmt(int(best2)))
		var g0: Transform3D = t["gates"][0]
		list.add_child(_chal_row(t["name"], info, int(game.save.data["medals"].get(t["id"], 0)), Color("5cc8ff") if t["kind"] == "time" else Color("c38bff"),
			Transform3D(g0.basis, g0.origin + Vector3(0, 1.0, 0)).translated_local(Vector3(0, 0, 16))))
	var back := K.button("Back", K.PAPER, K.LINE, 28, 0, 68)
	_tap(back, func():
		if game.state == game.PAUSED:
			open_pause()
		else:
			close_sheet())
	vb.add_child(back)

func _chal_row(name: String, info: String, medal: int, col: Color, xf: Transform3D) -> Control:
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
	var mcol: Color = [K.LINE, Color("b98b62"), Color("b3b8bd"), Color("d4b25c")][medal]
	hb.add_child(Icon.new("trophy", mcol, 34))
	var go := K.button("Go", K.TEAL, K.TEAL_DK, 22, 76, 54)
	_tap(go, func():
		close_sheet()
		transition(func(): game.travel_to(xf)))
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
	_garage_refresh()

func hide_garage() -> void:
	garage.visible = false

func _garage_refresh() -> void:
	var s = game.save.data
	g_coins.get_meta("label").text = K.fmt(int(s["coins"]))
	for c in g_panel.get_children():
		c.queue_free()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	g_panel.add_child(tabs)
	for tdef in [["cars", "Cars", "car"], ["up", "Upgrades", "gear"]]:
		var on: bool = g_tab == tdef[0]
		var b := K.button(tdef[1], K.CORAL if on else K.CREAM, K.CORAL_DK if on else K.LINE_DK, 28, 0, 66, tdef[2])
		if not on:
			b.add_theme_color_override("font_color", K.INK)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = tdef[0]
		_tap(b, func():
			g_tab = id
			_garage_refresh())
		tabs.add_child(b)
	_show_car(CARS.LIST[g_index])
	if g_tab == "cars":
		_cars_tab()
	else:
		_upgrades_tab()

func _show_car(d: Dictionary) -> void:
	for c in g_car.get_children():
		c.queue_free()
	var c := M.car(d)
	var body := MeshInstance3D.new()
	body.mesh = c["body"]
	body.material_override = g_mat
	g_car.add_child(body)
	for i in 4:
		var w := MeshInstance3D.new()
		w.mesh = M.wheel_mesh(c, i)
		w.material_override = g_mat
		w.position = c["wheels"][i]
		g_car.add_child(w)

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

func _upgrades_tab() -> void:
	var s = game.save
	g_panel.add_child(K.label("Upgrades work on every car you own.", 20, K.INK_SOFT, 600))
	var cols := {"engine": K.CORAL, "turbo": K.SKY, "tyres": K.TEAL, "steering": K.LILAC}
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
		if absf(g_drag) > 160.0:
			_garage_step(-1 if g_drag > 0 else 1)
			game.ui_tap()
		g_drag = 0.0
