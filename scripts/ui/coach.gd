extends Control
## The first ride's coach: a card at the top in the middle (under the GPS arrow, clear of every control)
## saying what to do, step dots and a skip, and a pulsing ring with a bobbing arrow on the button it means. Cards change with a quick slide;
## a step done flashes green first.

const K := preload("res://scripts/ui/kit.gd")
const W := 440.0
const ACC := Color("ff4f8b")
const OK := Color("3fd26b")

var ui: Node
var box: PanelContainer
var title: Label
var sub: Label
var dots: HBoxContainer
var skip_btn: Button
var dest_btn: Button          # Set as destination: the step's place, on the GPS (only if you want it)
var target: Variant = null         # a Control, an Array of them, or a Callable giving one
var _t := 0.0
var _on := false
var _busy: Tween
var _want: Array = []              # the card waiting to come in: [title, sub, target, k, n, final]
var _home_y := 0.0

func _init(u: Node) -> void:
	ui = u
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	box = PanelContainer.new()
	var sb := K.box(Color(0.06, 0.055, 0.085, 0.94), 26, 0, Color.TRANSPARENT, 18)
	sb.border_color = Color(ACC, 0.55)
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 18
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	box.add_theme_stylebox_override("panel", sb)
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.custom_minimum_size = Vector2(W, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(vb)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(top)
	dots = HBoxContainer.new()
	dots.add_theme_constant_override("separation", 6)
	dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(dots)
	skip_btn = Button.new()
	skip_btn.text = "Skip tutorial"
	skip_btn.flat = true
	skip_btn.focus_mode = Control.FOCUS_NONE
	skip_btn.add_theme_font_override("font", K.font(600))
	skip_btn.add_theme_font_size_override("font_size", 15)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		skip_btn.add_theme_color_override(st, Color(1, 1, 1, 0.5))
	skip_btn.pressed.connect(func():
		ui.game.ui_tap()
		ui.game.tutorial.skip())
	top.add_child(skip_btn)
	title = K.label("", 28, Color.WHITE, 750, HORIZONTAL_ALIGNMENT_LEFT)
	vb.add_child(title)
	sub = K.label("", 17, Color(1, 1, 1, 0.72), 550, HORIZONTAL_ALIGNMENT_LEFT)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(W - 48, 0)
	vb.add_child(sub)
	# the guide's suggestion, yours to follow: a tap puts it on the GPS
	dest_btn = K.button("Set as destination", ACC, Color(ACC.darkened(0.35)), 19, 0, 48, "flag")
	dest_btn.visible = false
	dest_btn.pressed.connect(func():
		var r: Dictionary = ui.game.tutorial.route()
		if not r.is_empty():
			ui.game.ui_tap()
			ui.game.set_route_pick(r["pos"], String(r["name"])))
	vb.add_child(dest_btn)
	box.visible = false

func _place() -> void:
	box.reset_size()
	_home_y = _top_y()
	box.position = Vector2((get_viewport_rect().size.x - box.size.x) * 0.5, _home_y)

## Under whatever's at the top in the middle: the GPS arrow, or a challenge's start card.
func _top_y() -> float:
	var y := 96.0
	if ui.route_box != null and ui.route_box.visible:
		y = maxf(y, ui.route_box.get_global_rect().end.y + 8.0)
	if ui.start_card != null and is_instance_valid(ui.start_card) and ui.start_card.visible:
		y = maxf(y, ui.start_card.get_global_rect().end.y + 12.0)
	return y

## A card: what to do, how, and what to point at.
func show_step(t: String, s: String, tgt: Variant, k: int, n: int, final := false) -> void:
	_want = [t, s, tgt, k, n, final]
	if _busy and _busy.is_valid():
		return              # (the card going out picks this one up)
	if box.visible:
		_busy = create_tween().set_parallel(true)
		_busy.tween_property(box, "modulate:a", 0.0, 0.16)
		_busy.tween_property(box, "position:y", _home_y + 18.0, 0.16).set_ease(Tween.EASE_IN)
		_busy.chain().tween_callback(_bring_in)
	else:
		_bring_in()

func _bring_in() -> void:
	_busy = null
	if _want.is_empty():
		return
	var w: Array = _want
	_want = []
	title.text = w[0]
	sub.text = w[1]
	sub.visible = String(w[1]) != ""
	target = w[2]
	var final: bool = w[5]
	skip_btn.visible = not final
	for c in dots.get_children():
		c.queue_free()
	if not final:
		for d in int(w[4]):
			var dot := Panel.new()
			var on: bool = d < int(w[3])
			dot.custom_minimum_size = Vector2(22 if d == int(w[3]) - 1 else 8, 8)
			dot.add_theme_stylebox_override("panel", K.box(ACC if on else Color(1, 1, 1, 0.18), 4, 0, Color.TRANSPARENT, 0))
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dots.add_child(dot)
	(box.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color(OK if final else ACC, 0.55)
	title.add_theme_color_override("font_color", OK if final else Color.WHITE)
	box.visible = true
	_on = true
	_place()
	box.modulate.a = 0.0
	box.position.y = _home_y + 26.0
	box.pivot_offset = box.size * 0.5
	box.scale = Vector2(0.96, 0.96)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(box, "modulate:a", 1.0, 0.22)
	tw.tween_property(box, "position:y", _home_y, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## That step's done: a green flash and a little pop before the next card.
func done_flash() -> void:
	if not box.visible:
		return
	target = null
	title.text = "✓  " + title.text
	title.add_theme_color_override("font_color", OK)
	(box.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color(OK, 0.8)
	box.pivot_offset = box.size * 0.5
	_busy = create_tween()
	_busy.tween_property(box, "scale", Vector2(1.05, 1.05), 0.09).set_ease(Tween.EASE_OUT)
	_busy.tween_property(box, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK)
	_busy.tween_interval(0.35)
	_busy.set_parallel(true)
	_busy.tween_property(box, "modulate:a", 0.0, 0.16)
	_busy.tween_property(box, "position:y", _home_y + 18.0, 0.16).set_ease(Tween.EASE_IN)
	_busy.chain().tween_callback(func():
		box.visible = false
		_bring_in())

func hide_all() -> void:
	_want = []
	target = null
	if _busy and _busy.is_valid():
		_busy.kill()
	_busy = null
	if not box.visible:
		return
	_on = false
	var tw := create_tween()
	tw.tween_property(box, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func():
		if not _on:
			box.visible = false)

func _process(dt: float) -> void:
	_t += dt
	# (following the top of the screen down when a start card comes up, and back)
	if box.visible and not (_busy and _busy.is_valid()):
		var want := _top_y()
		if absf(want - _home_y) > 0.5:
			_home_y = lerpf(_home_y, want, minf(1.0, dt * 10.0))
			box.position.y = _home_y
	# (out of the way while a screen's over the HUD)
	visible = ui.hud.visible and not ui.overlay.visible and not (ui.phone_layer != null and ui.phone_layer.visible)
	if box.visible and not (_busy and _busy.is_valid()):
		var r: Dictionary = ui.game.tutorial.route() if ui.game.tutorial else {}
		var want_d: bool = not r.is_empty() and String(r.get("kind", "")) == "tut" and ui.game.on_foot == false
		var set_already: bool = want_d and not ui.game.route_pick.is_empty() and String(ui.game.route_pick["name"]) == String(r["name"])
		if dest_btn.visible != want_d:
			dest_btn.visible = want_d
			_place()
		if want_d:
			var tx := "✓  On your GPS" if set_already else "Set as destination"
			if K.button_text(dest_btn) != tx:
				K.set_text(dest_btn, tx)
			dest_btn.disabled = set_already
	queue_redraw()

func _targets() -> Array:
	var tg: Variant = target
	if tg is Callable:
		tg = (tg as Callable).call()
	var out: Array = []
	for c in (tg if tg is Array else [tg]):
		if c is Control and is_instance_valid(c) and (c as Control).is_visible_in_tree():
			out.append(c)
	return out

func _draw() -> void:
	if not box.visible or box.modulate.a < 0.5:
		return
	var vs := get_viewport_rect().size
	for c in _targets():
		var r: Rect2 = (c as Control).get_global_rect()
		r.position -= get_global_rect().position
		var cen := r.get_center()
		var rad: float = maxf(r.size.x, r.size.y) * 0.5 + 10.0
		rad = minf(rad, 150.0)
		var pulse := 0.5 + 0.5 * sin(_t * 5.0)
		draw_arc(cen, rad + pulse * 5.0, 0.0, TAU, 64, Color(ACC, 0.9), 4.0, true)
		# a ripple going out from it
		var ph := fmod(_t, 1.3) / 1.3
		draw_arc(cen, rad + ph * 36.0, 0.0, TAU, 64, Color(ACC, 0.55 * (1.0 - ph)), 3.0, true)
		# the arrow: from above it (or below, for things at the top of the screen), bobbing at it
		var down := cen.y > vs.y * 0.4
		var dir := Vector2(0, 1) if down else Vector2(0, -1)
		var tip := cen - dir * (rad + 14.0 + pulse * 10.0)
		var back := tip - dir * 34.0
		var side := Vector2(dir.y, -dir.x) * 18.0
		var pts := PackedVector2Array([tip, back + side, back + side * 0.4, back - dir * 26.0 + side * 0.4, back - dir * 26.0 - side * 0.4, back - side * 0.4, back - side])
		var outline := pts.duplicate()
		outline.append(tip)
		draw_colored_polygon(pts, Color.WHITE)
		draw_polyline(outline, Color(ACC, 1.0), 3.0, true)
