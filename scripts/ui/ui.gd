extends CanvasLayer
## Every screen: title, HUD, game over, garage, missions, settings, pause, toasts and score popups.

const K := preload("res://scripts/ui/kit.gd")
const Icon := preload("res://scripts/ui/icon.gd")
const CARS := preload("res://scripts/game/cars.gd")
const M := preload("res://scripts/core/models.gd")
const PAL := preload("res://scripts/core/palette.gd")
const Missions := preload("res://scripts/game/missions.gd")
const SaveData := preload("res://scripts/game/save.gd")

var game: Node
var root: Control
var title: Control
var hud: Control
var over: Control
var garage: Control
var overlay: Control       # dim + sheets (missions, settings, pause)
var toasts: VBoxContainer
var popups: Control
var wipe: ColorRect
var wipe_mat: ShaderMaterial

# title refs
var title_logo: Control
var title_best: Label
var title_coins: PanelContainer
var title_tap: Label
var mission_badge: Label
var daily_dot: Control
# hud refs
var hud_dist: Label
var hud_best: Label
var hud_fuel: ProgressBar
var hud_fuel_icon: Control
var hud_coins: PanelContainer
var hud_combo: Label
var _fuel_flash := 0.0
var _passed_best := false
# garage refs
var g_view: SubViewport
var g_world_root: Node3D
var g_car: Node3D
var g_turntable: Node3D
var g_index := 0
var g_name: Label
var g_stats: VBoxContainer
var g_action: Button
var g_coins: PanelContainer
var g_tab_cars: Button
var g_tab_up: Button
var g_cars_box: Control
var g_up_box: VBoxContainer
var g_mat: ShaderMaterial
var g_drag := 0.0
var g_spin := 0.0
var g_dots: HBoxContainer

## Extra top padding (in UI units) so nothing sits under a camera hole or notch.
func safe_top() -> int:
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if screen.y <= 0 or safe.size.y <= 0:
		return 0
	var vs := get_viewport().get_visible_rect().size
	return clampi(int(float(safe.position.y) * vs.y / float(screen.y)), 0, 90)

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
	over = _full(Control.MOUSE_FILTER_IGNORE)
	over.visible = false
	_build_garage()
	overlay = _full(Control.MOUSE_FILTER_STOP)
	overlay.visible = false
	toasts = VBoxContainer.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toasts.position = Vector2(-300, 250)
	toasts.custom_minimum_size = Vector2(600, 0)
	toasts.size = Vector2(600, 0)
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.add_theme_constant_override("separation", 12)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)
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

var hit_controls: Array = []

## True if a screen point is on a button or a sheet, so the game ignores that touch.
func blocks(pos: Vector2) -> bool:
	hit_controls = hit_controls.filter(func(c): return is_instance_valid(c))
	if overlay.visible or garage.visible or (over.visible and over.mouse_filter == Control.MOUSE_FILTER_STOP):
		return true
	for c in hit_controls:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().grow(8).has_point(pos):
			return true
	return false

func _tap(b: BaseButton, f: Callable) -> void:
	hit_controls.append(b)
	b.pressed.connect(func():
		game.ui_tap()
		f.call())

# ------------------------------------------------------------------ wipe

func _set_wipe(p: float) -> void:
	wipe_mat.set_shader_parameter("progress", p)
	var vs := root.get_viewport_rect().size
	wipe_mat.set_shader_parameter("aspect", Vector2(vs.x / maxf(vs.y, 1.0), 1.0))
	wipe.visible = p > 0.001
	wipe.mouse_filter = Control.MOUSE_FILTER_STOP if p > 0.5 else Control.MOUSE_FILTER_IGNORE

func transition(mid: Callable) -> void:
	var t := create_tween()
	t.tween_method(_set_wipe, 0.0, 1.0, 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(mid)
	t.tween_interval(0.12)
	t.tween_method(_set_wipe, 1.0, 0.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# ------------------------------------------------------------------ title

func _build_title() -> void:
	title = _full(Control.MOUSE_FILTER_IGNORE)
	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("margin_left", 28)
	top.add_theme_constant_override("margin_right", 28)
	top.add_theme_constant_override("margin_top", 40 + safe_top())
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(top)
	var tb := HBoxContainer.new()
	tb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(tb)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(sp)
	title_coins = K.pill("coin", "0")
	tb.add_child(title_coins)
	# logo
	title_logo = VBoxContainer.new()
	title_logo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title_logo.position = Vector2(-330, 170)
	title_logo.custom_minimum_size = Vector2(660, 0)
	title_logo.size = Vector2(660, 0)
	title_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_logo.add_theme_constant_override("separation", -6)
	title.add_child(title_logo)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_logo.add_child(row)
	var word := "Lo-Fi Ryder"
	var cols := [Color("ff8a6b"), Color("ffb85c"), Color("ffd166"), Color("ffd166"), Color("8fd19e"), Color("ffffff"),
		Color("6ec6ff"), Color("8f9dff"), Color("b99cff"), Color("f59fd0"), Color("ff8a6b")]
	for i in word.length():
		var ch := K.outlined(K.label(word[i], 104, cols[i], 700), K.INK, 22)
		ch.set_meta("i", i)
		ch.pivot_offset = Vector2(30, 60)
		row.add_child(ch)
	var sub := K.outlined(K.label("a cozy little drive", 34, Color.WHITE, 600), Color(0.29, 0.23, 0.2, 0.85), 10)
	title_logo.add_child(sub)
	title_best = K.outlined(K.label("", 30, Color.WHITE, 600), Color(0.29, 0.23, 0.2, 0.85), 10)
	title_logo.add_child(K.spacer(14))
	title_logo.add_child(title_best)
	# bottom
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.position = Vector2(-330, -360)
	bottom.custom_minimum_size = Vector2(660, 0)
	bottom.size = Vector2(660, 0)
	bottom.add_theme_constant_override("separation", 22)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(bottom)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 26)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(buttons)
	var defs := [["car", "Garage", K.CORAL, K.CORAL_DK, func(): game.open_garage()],
		["flag", "Missions", K.TEAL, K.TEAL_DK, func(): open_missions()],
		["calendar", "Daily", K.SUN, K.SUN_DK, func(): open_daily()],
		["gear", "Settings", K.LILAC, K.LILAC_DK, func(): open_settings()]]
	for d in defs:
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 6)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var b := K.round_button(d[0], d[2], d[3], 112, Color.WHITE)
		_tap(b, d[4])
		vb.add_child(b)
		var cap := K.outlined(K.label(d[1], 26, Color.WHITE, 600), Color(0.29, 0.23, 0.2, 0.85), 8)
		vb.add_child(cap)
		buttons.add_child(vb)
		if d[1] == "Missions":
			mission_badge = K.label("", 24, Color.WHITE, 700)
			var badge := PanelContainer.new()
			var sb := K.box(K.CORAL, 20, 0, Color.TRANSPARENT, 8)
			sb.content_margin_top = 0
			sb.content_margin_bottom = 0
			badge.add_theme_stylebox_override("panel", sb)
			badge.add_child(mission_badge)
			badge.position = Vector2(76, -8)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(badge)
			b.set_meta("badge", badge)
		if d[1] == "Daily":
			daily_dot = Panel.new()
			var sb2 := K.box(K.CORAL, 14, 0, Color.TRANSPARENT, 0)
			daily_dot.add_theme_stylebox_override("panel", sb2)
			daily_dot.size = Vector2(26, 26)
			daily_dot.position = Vector2(84, 0)
			daily_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(daily_dot)
	title_tap = K.outlined(K.label("Tap to drive · slide to steer", 38, Color.WHITE, 650), Color(0.29, 0.23, 0.2, 0.9), 12)
	bottom.add_child(K.spacer(10))
	bottom.add_child(title_tap)

func show_title() -> void:
	title.visible = true
	hud.visible = false
	over.visible = false
	garage.visible = false
	refresh_title()
	for c in title_logo.get_children():
		c.modulate.a = 1.0
	title.modulate.a = 0.0
	create_tween().tween_property(title, "modulate:a", 1.0, 0.5)

func hide_title() -> void:
	var t := create_tween()
	t.tween_property(title, "modulate:a", 0.0, 0.25)
	t.tween_callback(func(): title.visible = false)

func refresh_title() -> void:
	var s = game.save.data
	title_coins.get_meta("label").text = K.fmt(int(s["coins"]))
	title_best.text = ("Best  %s" % K.fmt(int(s["best"]))) if int(s["best"]) > 0 else ""
	var done := 0
	for m in s["missions"]:
		if m["done"]:
			done += 1
	mission_badge.get_parent().visible = false
	daily_dot.visible = String(s["daily"]["date"]) != game.today()

# ------------------------------------------------------------------ hud

func _build_hud() -> void:
	hud = _full(Control.MOUSE_FILTER_IGNORE)
	hud.visible = false
	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("margin_left", 26)
	top.add_theme_constant_override("margin_right", 26)
	top.add_theme_constant_override("margin_top", 40 + safe_top())
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)
	var pause := K.round_button("pause", K.PAPER, Color("e2d3c2"), 82)
	pause.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_tap(pause, func(): game.pause())
	row.add_child(pause)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mid)
	hud_dist = K.outlined(K.label("0 m", 64, Color.WHITE, 700), K.INK, 16)
	mid.add_child(hud_dist)
	var fuel_row := HBoxContainer.new()
	fuel_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fuel_row.add_theme_constant_override("separation", 10)
	fuel_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(fuel_row)
	hud_fuel_icon = Icon.new("fuel", K.INK, 40)
	fuel_row.add_child(hud_fuel_icon)
	var fuel_back := PanelContainer.new()
	var fsb := K.box(K.PAPER, 18, 5, Color("e2d3c2"), 6)
	fsb.content_margin_top = 6
	fsb.content_margin_bottom = 6
	fuel_back.add_theme_stylebox_override("panel", fsb)
	fuel_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fuel_row.add_child(fuel_back)
	hud_fuel = K.bar(230, 20, Color("ff8a5c"), Color("f3e7da"))
	fuel_back.add_child(hud_fuel)
	hud_best = K.outlined(K.label("", 24, Color.WHITE, 600), Color(0.29, 0.23, 0.2, 0.8), 8)
	mid.add_child(hud_best)
	hud_coins = K.pill("coin", "0", 32)
	hud_coins.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(hud_coins)
	hud_combo = K.outlined(K.label("", 34, K.SUN, 700), K.INK, 12)
	hud_combo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hud_combo.position = Vector2(-200, 300)
	hud_combo.size = Vector2(400, 50)
	hud.add_child(hud_combo)

func show_hud() -> void:
	hud.visible = true
	hud.modulate.a = 0.0
	_passed_best = false
	create_tween().tween_property(hud, "modulate:a", 1.0, 0.35)

func hud_update(dt: float, dist: int, fuel: float, coins: int, best: int, combo: float) -> void:
	hud_dist.text = "%s m" % K.fmt(dist)
	hud_fuel.value = fuel
	var low := fuel < 0.25
	_fuel_flash += dt * (7.0 if low else 0.0)
	var fill: StyleBoxFlat = hud_fuel.get_theme_stylebox("fill")
	fill.bg_color = Color("ff8a5c").lerp(Color("ff4d3d"), (0.5 + 0.5 * sin(_fuel_flash)) if low else 0.0)
	if fuel > 0.6:
		fill.bg_color = Color("ffb85c").lerp(Color("8fd19e"), (fuel - 0.6) / 0.4)
	hud_fuel_icon.scale = Vector2.ONE * (1.0 + (0.12 * maxf(0.0, sin(_fuel_flash)) if low else 0.0))
	var cl: Label = hud_coins.get_meta("label")
	var ct := K.fmt(coins)
	if cl.text != ct:
		cl.text = ct
		hud_coins.pivot_offset = hud_coins.size * 0.5
		var t := hud_coins.create_tween()
		t.tween_property(hud_coins, "scale", Vector2(1.15, 1.15), 0.06)
		t.tween_property(hud_coins, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if best > 0 and not _passed_best:
		hud_best.text = "Best %s" % K.fmt(best)
	hud_combo.text = ""

func passed_best() -> void:
	if _passed_best:
		return
	_passed_best = true
	hud_best.text = "New best!"
	hud_best.add_theme_color_override("font_color", K.SUN)
	var t := create_tween()
	hud_best.pivot_offset = hud_best.size * 0.5
	t.tween_property(hud_best, "scale", Vector2(1.4, 1.4), 0.15)
	t.tween_property(hud_best, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)

func hide_hud() -> void:
	var t := create_tween()
	t.tween_property(hud, "modulate:a", 0.0, 0.25)
	t.tween_callback(func(): hud.visible = false)
	hud_best.add_theme_color_override("font_color", Color.WHITE)

# ------------------------------------------------------------------ popups & toasts

func popup(text: String, world_pos: Vector3, col := Color.WHITE, size := 34, sub := "") -> void:
	var cam: Camera3D = game.cam
	if cam.is_position_behind(world_pos):
		return
	var sp := cam.unproject_position(world_pos)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", -8)
	var l := K.outlined(K.label(text, size, col, 700), K.INK, 12)
	vb.add_child(l)
	if sub != "":
		vb.add_child(K.outlined(K.label(sub, int(size * 0.7), Color.WHITE, 650), K.INK, 9))
	popups.add_child(vb)
	vb.size = Vector2(420, 0)
	vb.position = sp - Vector2(210, 120 + randf_range(0, 30))
	vb.pivot_offset = Vector2(210, 30)
	vb.scale = Vector2(0.4, 0.4)
	var t := create_tween()
	t.tween_property(vb, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(vb, "position:y", vb.position.y - 70, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(vb, "modulate:a", 0.0, 0.35).set_delay(0.75)
	t.tween_callback(vb.queue_free)

func toast(text: String, icon := "", col := K.PAPER, icol := K.INK, hold := 2.2) -> void:
	var p := PanelContainer.new()
	var sb := K.box(col, 40, 6, col.darkened(0.12), 22)
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(hb)
	if icon != "":
		hb.add_child(Icon.new(icon, icol, 40))
	hb.add_child(K.label(text, 32, icol, 650))
	toasts.add_child(p)
	p.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(p, "modulate:a", 1.0, 0.25)
	t.tween_interval(hold)
	t.tween_property(p, "modulate:a", 0.0, 0.4)
	t.tween_callback(p.queue_free)

# ------------------------------------------------------------------ game over

func show_over(r: Dictionary) -> void:
	for c in over.get_children():
		c.queue_free()
	over.visible = true
	over.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = K.DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	over.add_child(dim)
	dim.modulate.a = 0.0
	create_tween().tween_property(dim, "modulate:a", 1.0, 0.4)
	var card := K.card()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	card.custom_minimum_size = Vector2(640, 0)
	over.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)
	var why := {"fuel": "Out of fuel", "fall": "Took a tumble", "splash": "Splash!", "quit": "Run over"}
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 12)
	head.add_child(Icon.new({"fuel": "fuel", "fall": "star", "splash": "rain", "quit": "flag"}.get(r["why"], "star"), K.INK_SOFT, 42))
	head.add_child(K.label(why.get(r["why"], "Run over"), 40, K.INK_SOFT, 600))
	vb.add_child(head)
	var score_l := K.label("0", 104, K.INK, 700)
	vb.add_child(score_l)
	if r["record"]:
		var rec := PanelContainer.new()
		rec.add_theme_stylebox_override("panel", K.box(K.SUN, 30, 6, K.SUN_DK, 22))
		rec.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 10)
		rh.add_child(Icon.new("trophy", Color.WHITE, 38))
		rh.add_child(K.label("New record!", 34, Color.WHITE, 700))
		rec.add_child(rh)
		vb.add_child(rec)
		rec.pivot_offset = Vector2(150, 30)
		rec.scale = Vector2.ZERO
		var rt := create_tween()
		rt.tween_interval(0.9)
		rt.tween_property(rec, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		vb.add_child(K.label("Best  %s" % K.fmt(int(r["best"])), 30, K.INK_SOFT, 600))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var rows := [["Distance", "%s m" % K.fmt(r["dist"])], ["Style", "+%s" % K.fmt(r["style"])], ["Coins", "+%s" % K.fmt(r["coins"])]]
	if r.get("mission_coins", 0) > 0:
		rows.append(["Missions", "+%s coins" % K.fmt(r["mission_coins"])])
	if r.get("daily", false):
		rows.push_front(["Daily run", r.get("date", "")])
	for row in rows:
		grid.add_child(K.label(row[0], 30, K.INK_SOFT, 500, HORIZONTAL_ALIGNMENT_LEFT))
		grid.add_child(K.label(row[1], 30, K.INK, 650, HORIZONTAL_ALIGNMENT_RIGHT))
	vb.add_child(grid)
	# missions
	var ml := VBoxContainer.new()
	ml.add_theme_constant_override("separation", 6)
	for m in r.get("missions", []):
		ml.add_child(_mission_row(m, r["run"], true))
	if ml.get_child_count() > 0:
		vb.add_child(K.spacer(4))
		vb.add_child(ml)
	vb.add_child(K.spacer(8))
	var again := K.button("Drive again", K.CORAL, K.CORAL_DK, 44, 0, 104, "play")
	_tap(again, func(): game.restart(r.get("daily", false)))
	vb.add_child(again)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	var gar := K.button("Garage", K.TEAL, K.TEAL_DK, 34, 0, 84, "car")
	gar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tap(gar, func(): game.open_garage())
	var home := K.button("Home", K.PAPER, Color("e2d3c2"), 34, 0, 84, "home")
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tap(home, func(): game.go_home())
	hb.add_child(gar)
	hb.add_child(home)
	vb.add_child(hb)
	# slide up
	await get_tree().process_frame
	if not is_instance_valid(card):
		return
	var vs := root.get_viewport_rect().size
	card.position = Vector2((vs.x - card.size.x) * 0.5, vs.y + 20)
	var t := card.create_tween()
	t.tween_property(card, "position:y", vs.y - card.size.y - 60, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# count the score up
	t.parallel().tween_method(func(v): score_l.text = K.fmt(int(v)), 0.0, float(r["score"]), 1.0).set_delay(0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func hide_over() -> void:
	over.visible = false
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in over.get_children():
		c.queue_free()

func _mission_row(m: Dictionary, run: Dictionary, compact := false) -> Control:
	var p := PanelContainer.new()
	var done: bool = m["done"]
	p.add_theme_stylebox_override("panel", K.box(Color("eaf7ee") if done else Color("f6ede2"), 22, 0, Color.TRANSPARENT, 16))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	p.add_child(hb)
	var ic := Icon.new("check" if done else "flag", K.TEAL if done else K.INK_SOFT, 34 if compact else 40)
	hb.add_child(ic)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)
	hb.add_child(vb)
	var t := K.label(Missions.text(m), 24 if compact else 28, K.INK, 550, HORIZONTAL_ALIGNMENT_LEFT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(t)
	if not compact or not done:
		var val := Missions.value(m, run) if not run.is_empty() else 0.0
		var b := K.bar(300, 12, K.TEAL)
		b.value = 1.0 if done else clampf(val / float(m["target"]), 0.0, 1.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(b)
	var rw := HBoxContainer.new()
	rw.add_theme_constant_override("separation", 4)
	rw.add_child(Icon.new("coin", K.INK, 30))
	rw.add_child(K.label(str(m["reward"]), 26, K.INK, 650))
	hb.add_child(rw)
	return p

# ------------------------------------------------------------------ sheets (missions, daily, settings, pause)

func _sheet(title_text: String, icon: String, col: Color) -> VBoxContainer:
	for c in overlay.get_children():
		c.queue_free()
	overlay.visible = true
	var dim := ColorRect.new()
	dim.color = K.DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var card := K.card()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.custom_minimum_size = Vector2(640, 0)
	overlay.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	card.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", K.box(col, 30, 0, Color.TRANSPARENT, 12))
	badge.add_child(Icon.new(icon, Color.WHITE, 44))
	head.add_child(badge)
	var tl := K.label(title_text, 46, K.INK, 700, HORIZONTAL_ALIGNMENT_LEFT)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	vb.add_child(head)
	await get_tree().process_frame
	var vs := root.get_viewport_rect().size
	card.position = (vs - card.size) * 0.5
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(0.85, 0.85)
	card.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(card, "modulate:a", 1.0, 0.2)
	card.resized.connect(func():
		var v2 := root.get_viewport_rect().size
		card.position = (v2 - card.size) * 0.5
		card.pivot_offset = card.size * 0.5)
	return vb

func close_sheet() -> void:
	overlay.visible = false
	for c in overlay.get_children():
		c.queue_free()

func open_missions() -> void:
	var vb: VBoxContainer = await _sheet("Missions", "flag", K.TEAL)
	vb.add_child(K.label("Finish missions during runs to earn coins.", 28, K.INK_SOFT, 500))
	game.missions.ensure()
	for m in game.save.data["missions"]:
		vb.add_child(_mission_row(m, {}))
	vb.add_child(K.spacer(6))
	var ok := K.button("Got it", K.TEAL, K.TEAL_DK, 38, 0, 92)
	_tap(ok, close_sheet)
	vb.add_child(ok)

func open_daily() -> void:
	var vb: VBoxContainer = await _sheet("Daily Run", "calendar", K.SUN)
	var d = game.save.data["daily"]
	var today: String = game.today()
	vb.add_child(K.label("Everyone gets the same road today.\nRace your own ghost from earlier tries.", 28, K.INK_SOFT, 500))
	var best := int(d["best"]) if String(d["date"]) == today else 0
	var info := HBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 12)
	info.add_child(Icon.new("trophy", K.SUN_DK, 44))
	info.add_child(K.label(("Today's best  %s" % K.fmt(best)) if best > 0 else "No run yet today", 34, K.INK, 650))
	vb.add_child(info)
	vb.add_child(K.label(today, 26, K.INK_SOFT, 500))
	var go := K.button("Drive today's road", K.SUN, K.SUN_DK, 38, 0, 100, "play")
	_tap(go, func():
		close_sheet()
		game.start_daily())
	vb.add_child(go)
	var back := K.button("Not now", K.PAPER, Color("e2d3c2"), 32, 0, 80)
	_tap(back, close_sheet)
	vb.add_child(back)

func open_settings(from_pause := false) -> void:
	var vb: VBoxContainer = await _sheet("Settings", "gear", K.LILAC)
	var st = game.save.data["settings"]
	vb.add_child(_setting_slider("music", "Music", st["music"], func(v): game.set_setting("music", v)))
	vb.add_child(_setting_slider("sound", "Sounds", st["sfx"], func(v): game.set_setting("sfx", v)))
	vb.add_child(_setting_toggle("vibe", "Vibration", st["haptics"], func(v): game.set_setting("haptics", v)))
	vb.add_child(_setting_toggle("shadow", "Shadows", st["shadows"], func(v): game.set_setting("shadows", v)))
	var reset := K.button("Reset progress", K.PAPER, Color("e2d3c2"), 28, 0, 72)
	reset.add_theme_color_override("font_color", K.CORAL_DK)
	var armed := [false]
	reset.pressed.connect(func():
		game.ui_tap()
		if not armed[0]:
			armed[0] = true
			reset.text = "Tap again to erase everything"
		else:
			game.reset_progress()
			close_sheet())
	vb.add_child(reset)
	vb.add_child(K.label("Lo-Fi Ryder · %s" % game.build_label(), 22, K.INK_SOFT, 500))
	var done := K.button("Done", K.LILAC, K.LILAC_DK, 38, 0, 92)
	_tap(done, func():
		if from_pause:
			open_pause()
		else:
			close_sheet())
	vb.add_child(done)

func _setting_slider(icon: String, text: String, value: float, cb: Callable) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	hb.add_child(Icon.new(icon, K.INK, 44))
	var l := K.label(text, 32, K.INK, 600, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(150, 0)
	hb.add_child(l)
	var s := K.slider(value)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(cb)
	hb.add_child(s)
	return hb

func _setting_toggle(icon: String, text: String, value: bool, cb: Callable) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	hb.add_child(Icon.new(icon, K.INK, 44))
	var l := K.label(text, 32, K.INK, 600, HORIZONTAL_ALIGNMENT_LEFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	var b := K.button("On" if value else "Off", K.TEAL if value else Color("cbbfb3"), K.TEAL_DK if value else Color("ad9f92"), 30, 130, 70)
	var state := [value]
	b.pressed.connect(func():
		game.ui_tap()
		state[0] = not state[0]
		b.text = "On" if state[0] else "Off"
		var col: Color = K.TEAL if state[0] else Color("cbbfb3")
		var dk: Color = K.TEAL_DK if state[0] else Color("ad9f92")
		for sname in ["normal", "hover"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(sname).duplicate()
			sb.bg_color = col
			sb.border_color = dk
			b.add_theme_stylebox_override(sname, sb)
		cb.call(state[0]))
	hb.add_child(b)
	return hb

func open_pause() -> void:
	var vb: VBoxContainer = await _sheet("Paused", "pause", K.CORAL)
	var resume := K.button("Keep driving", K.CORAL, K.CORAL_DK, 40, 0, 100, "play")
	_tap(resume, func():
		close_sheet()
		game.resume())
	vb.add_child(resume)
	var st := K.button("Settings", K.LILAC, K.LILAC_DK, 34, 0, 84, "gear")
	_tap(st, func(): open_settings(true))
	vb.add_child(st)
	var quit := K.button("End run", K.PAPER, Color("e2d3c2"), 34, 0, 84, "flag")
	_tap(quit, func():
		close_sheet()
		game.end_run_from_pause())
	vb.add_child(quit)

# ------------------------------------------------------------------ garage

func _build_garage() -> void:
	garage = _full(Control.MOUSE_FILTER_STOP)
	garage.visible = false
	var bg := ColorRect.new()
	bg.color = K.CREAM
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	garage.add_child(bg)
	# soft stripes
	var stripes := ColorRect.new()
	stripes.name = "Stripes"
	stripes.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripes.offset_bottom = 780
	stripes.color = Color("ffe9d1")
	garage.add_child(stripes)
	# 3D showroom
	var svc := SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	svc.offset_top = 120
	svc.offset_bottom = 120 + 640
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	garage.add_child(svc)
	g_view = SubViewport.new()
	g_view.own_world_3d = true
	g_view.transparent_bg = true
	g_view.msaa_3d = Viewport.MSAA_4X
	g_view.size = Vector2i(720, 640)
	svc.add_child(g_view)
	g_world_root = Node3D.new()
	g_view.add_child(g_world_root)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b8b4e6")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	g_world_root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_color = Color("fff1dc")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	g_world_root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0, 2.4, 5.8)
	cam.rotation_degrees = Vector3(-21, 0, 0)
	g_world_root.add_child(cam)
	g_mat = ShaderMaterial.new()
	g_mat.shader = load("res://shaders/toon.gdshader")
	g_mat.set_shader_parameter("palette", PAL.make_texture())
	g_mat.set_shader_parameter("haze", 0.0)
	g_turntable = Node3D.new()
	g_world_root.add_child(g_turntable)
	var tt := MeshInstance3D.new()
	var mb := preload("res://scripts/core/mesh_builder.gd").new()
	mb.cyl(Vector3(0, -0.12, 0), 1.75, 0.24, mb.pal(PAL.GRASS), 40)
	mb.cyl(Vector3(0, -0.45, 0), 1.6, 0.44, mb.pal(PAL.DIRT), 40, Basis(), 1.3)
	mb.cyl(Vector3(0, -0.95, 0), 1.2, 0.6, mb.pal(PAL.DIRT_DARK), 12, Basis(), 0.0, false)
	for i in 10:
		var a := TAU * i / 10.0
		mb.sphere(Vector3(cos(a) * 1.55, 0.06, sin(a) * 1.55), 0.12, mb.pal(PAL.FLOWER_A if i % 2 == 0 else PAL.FLOWER_B), 6, 4)
	tt.mesh = mb.commit()
	tt.material_override = g_mat
	g_turntable.add_child(tt)
	g_car = Node3D.new()
	g_car.rotation.y = PI
	g_turntable.add_child(g_car)
	# top bar
	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("margin_left", 26)
	top.add_theme_constant_override("margin_right", 26)
	top.add_theme_constant_override("margin_top", 40 + safe_top())
	garage.add_child(top)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 16)
	top.add_child(tb)
	var back := K.round_button("back", K.PAPER, Color("e2d3c2"), 86)
	_tap(back, func(): game.close_garage())
	tb.add_child(back)
	var tl := K.label("Garage", 50, K.INK, 700, HORIZONTAL_ALIGNMENT_LEFT)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.add_child(tl)
	g_coins = K.pill("coin", "0")
	g_coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tb.add_child(g_coins)
	# tabs
	var tabs := HBoxContainer.new()
	tabs.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	tabs.position = Vector2(-250, 150)
	tabs.size = Vector2(500, 70)
	tabs.add_theme_constant_override("separation", 12)
	garage.add_child(tabs)
	g_tab_cars = K.button("Cars", K.CORAL, K.CORAL_DK, 30, 240, 70)
	g_tab_up = K.button("Upgrades", K.PAPER, Color("e2d3c2"), 30, 240, 70)
	_tap(g_tab_cars, func(): _garage_tab(true))
	_tap(g_tab_up, func(): _garage_tab(false))
	tabs.add_child(g_tab_cars)
	tabs.add_child(g_tab_up)
	# cars panel (bottom)
	g_cars_box = VBoxContainer.new()
	g_cars_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	g_cars_box.offset_top = -520
	g_cars_box.offset_left = 40
	g_cars_box.offset_right = -40
	g_cars_box.offset_bottom = -50
	g_cars_box.add_theme_constant_override("separation", 14)
	garage.add_child(g_cars_box)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	g_cars_box.add_child(nav)
	var prev := K.round_button("left", K.PAPER, Color("e2d3c2"), 90)
	_tap(prev, func(): _garage_step(-1))
	nav.add_child(prev)
	g_name = K.label("", 46, K.INK, 700)
	g_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(g_name)
	var nxt := K.round_button("right", K.PAPER, Color("e2d3c2"), 90)
	_tap(nxt, func(): _garage_step(1))
	nav.add_child(nxt)
	g_dots = HBoxContainer.new()
	g_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	g_dots.add_theme_constant_override("separation", 6)
	g_cars_box.add_child(g_dots)
	for i in CARS.LIST.size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.add_theme_stylebox_override("panel", K.box(Color("e2d3c2"), 7, 0, Color.TRANSPARENT, 0))
		g_dots.add_child(dot)
	g_stats = VBoxContainer.new()
	g_stats.add_theme_constant_override("separation", 8)
	g_cars_box.add_child(g_stats)
	g_action = K.button("Select", K.CORAL, K.CORAL_DK, 40, 0, 104)
	_tap(g_action, _garage_action)
	g_cars_box.add_child(g_action)
	# upgrades panel
	g_up_box = VBoxContainer.new()
	g_up_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g_up_box.offset_top = 250
	g_up_box.offset_left = 36
	g_up_box.offset_right = -36
	g_up_box.offset_bottom = -40
	g_up_box.add_theme_constant_override("separation", 16)
	g_up_box.visible = false
	garage.add_child(g_up_box)
	garage.gui_input.connect(_garage_input)

func show_garage() -> void:
	garage.visible = true
	title.visible = false
	over.visible = false
	hud.visible = false
	g_index = CARS.index_of(String(game.save.data["car"]))
	_garage_tab(true)
	_garage_refresh()

func hide_garage() -> void:
	garage.visible = false

func _garage_tab(cars: bool) -> void:
	g_cars_box.visible = cars
	g_up_box.visible = not cars
	var sel := [g_tab_cars, g_tab_up] if cars else [g_tab_up, g_tab_cars]
	for i in 2:
		var b: Button = sel[i]
		var on := i == 0
		var col: Color = K.CORAL if on else K.PAPER
		var dk: Color = K.CORAL_DK if on else Color("e2d3c2")
		for sname in ["normal", "hover"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(sname).duplicate()
			sb.bg_color = col
			sb.border_color = dk
			b.add_theme_stylebox_override(sname, sb)
		for st in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(st, Color.WHITE if on else K.INK)
	g_view.get_parent().visible = true
	garage.get_node("Stripes").visible = cars
	if not cars:
		_build_upgrades()
		g_view.get_parent().visible = false

func _garage_step(d: int) -> void:
	g_index = posmod(g_index + d, CARS.LIST.size())
	g_spin = 0.0
	_garage_refresh()
	g_car.scale = Vector3(0.7, 0.7, 0.7)
	var t := create_tween()
	t.tween_property(g_car, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _garage_refresh() -> void:
	var d: Dictionary = CARS.LIST[g_index]
	var s = game.save.data
	g_coins.get_meta("label").text = K.fmt(int(s["coins"]))
	for c in g_car.get_children():
		c.queue_free()
	var c := M.car(d)
	var body := MeshInstance3D.new()
	body.mesh = c["body"]
	var bm: ShaderMaterial = g_mat.duplicate()
	var om := ShaderMaterial.new()
	om.shader = load("res://shaders/outline.gdshader")
	om.set_shader_parameter("width", 0.02)
	bm.next_pass = om
	body.material_override = bm
	body.position.y = c["ride"]
	g_car.add_child(body)
	for i in 4:
		var w := MeshInstance3D.new()
		w.mesh = c["wheel_f"] if i < 2 else c["wheel_r"]
		w.material_override = g_mat
		w.position = c["wheels"][i]
		g_car.add_child(w)
	var owned: bool = game.save.owns(d["id"])
	var selected: bool = String(s["car"]) == d["id"]
	g_name.text = d["name"]
	for i in g_dots.get_child_count():
		var dot: Panel = g_dots.get_child(i)
		var col := K.CORAL if i == g_index else (K.TEAL if game.save.owns(CARS.LIST[i]["id"]) else Color("e2d3c2"))
		dot.add_theme_stylebox_override("panel", K.box(col, 7, 0, Color.TRANSPARENT, 0))
	for ch in g_stats.get_children():
		ch.queue_free()
	for st in [["Grip", d["grip"], 0.85, 1.15], ["Drift", d["drift"], 0.85, 1.2], ["Bounce", d["bounce"], 0.85, 1.5]]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		var l := K.label(st[0], 30, K.INK_SOFT, 600, HORIZONTAL_ALIGNMENT_LEFT)
		l.custom_minimum_size = Vector2(130, 0)
		hb.add_child(l)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 8)
		var n := 1 + int(round(clampf((float(st[1]) - st[2]) / (st[3] - st[2]), 0.0, 1.0) * 4.0))
		for k in 5:
			var pip := Panel.new()
			pip.custom_minimum_size = Vector2(54, 20)
			pip.add_theme_stylebox_override("panel", K.box(K.TEAL if k < n else Color("eadccd"), 10, 0, Color.TRANSPARENT, 0))
			pips.add_child(pip)
		hb.add_child(pips)
		g_stats.add_child(hb)
	var price: int = d["price"]
	g_action.disabled = false
	if selected:
		g_action.text = "Driving this one"
		g_action.disabled = true
	elif owned:
		g_action.text = "Drive this one"
	elif int(s["coins"]) >= price:
		g_action.text = "Buy  ·  %s coins" % K.fmt(price)
	else:
		g_action.text = "%s coins" % K.fmt(price)
		g_action.disabled = true

func _garage_action() -> void:
	var d: Dictionary = CARS.LIST[g_index]
	var s = game.save.data
	if game.save.owns(d["id"]):
		s["car"] = d["id"]
		game.save.save()
		game.car_changed()
		game.sfx("select")
		game.buzz(25, 0.5)
	elif int(s["coins"]) >= int(d["price"]):
		s["coins"] = int(s["coins"]) - int(d["price"])
		s["owned"].append(d["id"])
		s["car"] = d["id"]
		game.save.save()
		game.car_changed()
		game.sfx("purchase")
		game.buzz(60, 0.9)
		_confetti_garage()
	_garage_refresh()

func _confetti_garage() -> void:
	for i in 26:
		var p := Panel.new()
		var col: Color = [K.CORAL, K.SUN, K.TEAL, K.LILAC, K.SKY][i % 5]
		p.add_theme_stylebox_override("panel", K.box(col, 4, 0, Color.TRANSPARENT, 0))
		p.size = Vector2(16, 24)
		p.position = Vector2(360, 460)
		p.pivot_offset = Vector2(8, 12)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		garage.add_child(p)
		var dest := p.position + Vector2(randf_range(-320, 320), randf_range(-380, 120))
		var t := create_tween()
		t.tween_property(p, "position", dest, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(p, "rotation", randf_range(-8, 8), 0.9)
		t.parallel().tween_property(p, "modulate:a", 0.0, 0.4).set_delay(0.6)
		t.tween_callback(p.queue_free)

func _build_upgrades() -> void:
	for c in g_up_box.get_children():
		c.queue_free()
	var s = game.save
	g_coins.get_meta("label").text = K.fmt(int(s.data["coins"]))
	var icons := {"tank": "tank", "grip": "tire", "magnet": "magnet", "wind": "wind"}
	var cols := {"tank": K.CORAL, "grip": K.TEAL, "magnet": K.SUN, "wind": K.LILAC}
	for u in SaveData.UPGRADES:
		var card := K.card(K.PAPER, 30)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 18)
		card.add_child(hb)
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", K.box(cols[u], 26, 0, Color.TRANSPARENT, 14))
		var bic := Icon.new(icons[u], Color.WHITE, 56)
		bic.color2 = cols[u]
		badge.add_child(bic)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(badge)
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 6)
		hb.add_child(vb)
		vb.add_child(K.label(SaveData.UPGRADE_INFO[u]["name"], 34, K.INK, 700, HORIZONTAL_ALIGNMENT_LEFT))
		var desc := K.label(SaveData.UPGRADE_INFO[u]["desc"], 24, K.INK_SOFT, 500, HORIZONTAL_ALIGNMENT_LEFT)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(desc)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 8)
		var lvl: int = s.level(u)
		for k in SaveData.MAX_LEVEL:
			var pip := Panel.new()
			pip.custom_minimum_size = Vector2(40, 16)
			pip.add_theme_stylebox_override("panel", K.box(cols[u] if k < lvl else Color("eadccd"), 8, 0, Color.TRANSPARENT, 0))
			pips.add_child(pip)
		vb.add_child(pips)
		var cost: int = s.upgrade_cost(u)
		var b: Button
		if cost < 0:
			b = K.button("Max", Color("cbbfb3"), Color("ad9f92"), 28, 150, 80)
			b.disabled = true
		else:
			b = K.button(K.fmt(cost), cols[u], cols[u].darkened(0.2), 30, 150, 80)
			b.disabled = int(s.data["coins"]) < cost
			var uu: String = u
			_tap(b, func(): _buy_upgrade(uu))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(b)
		g_up_box.add_child(card)

func _buy_upgrade(u: String) -> void:
	var s = game.save
	var cost: int = s.upgrade_cost(u)
	if cost < 0 or int(s.data["coins"]) < cost:
		return
	s.data["coins"] = int(s.data["coins"]) - cost
	s.data["up"][u] = s.level(u) + 1
	s.save()
	game.sfx("upgrade")
	game.buzz(50, 0.8)
	_build_upgrades()

func _garage_input(e: InputEvent) -> void:
	if not g_cars_box.visible:
		return
	if e is InputEventScreenDrag:
		g_drag += e.relative.x
		g_spin += e.relative.x * 0.01
	elif e is InputEventScreenTouch and not e.pressed:
		if absf(g_drag) > 110.0 and e.position.y < 800:
			_garage_step(-1 if g_drag > 0 else 1)
			game.ui_tap()
		g_drag = 0.0

func garage_tick(dt: float) -> void:
	if garage.visible:
		g_spin += dt * 0.5
		g_turntable.rotation.y = g_spin + 0.7
		g_turntable.position.y = sin(Time.get_ticks_msec() * 0.002) * 0.04

func title_tick(t: float) -> void:
	if not title.visible:
		return
	var row: HBoxContainer = title_logo.get_child(0)
	for ch in row.get_children():
		var i: int = ch.get_meta("i")
		ch.position.y = sin(t * 2.2 + i * 0.55) * 7.0
		ch.rotation = sin(t * 1.6 + i * 0.8) * 0.04
	title_tap.modulate.a = 0.6 + 0.4 * sin(t * 3.2)
	title_tap.scale = Vector2.ONE * (1.0 + 0.03 * sin(t * 3.2))
	title_tap.pivot_offset = title_tap.size * 0.5
