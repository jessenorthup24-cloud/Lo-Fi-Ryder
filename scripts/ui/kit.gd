extends RefCounted
## Building blocks for the UI: fonts, chunky pill buttons, cards, labels.

const Icon := preload("res://scripts/ui/icon.gd")

# Lo-fi night: dark glass panels, near-white type, one warm neon accent. (The names are kept from the old
# pastel kit, so every screen picks the new look up: PAPER is the glass, INK the type on it, CORAL the accent;
# the other colours are quieter glass for secondary buttons.)
const CREAM := Color(1, 1, 1, 0.06)  # a row on a panel: a shade lighter than the glass
const PAPER := Color(0.075, 0.07, 0.105, 0.86)
const INK := Color("f2f0f7")
const INK_SOFT := Color("a6a2b4")
const CORAL := Color("ff4f8b")      # the accent: neon pink
const CORAL_DK := Color("ff8db4")
const TEAL := Color(0.2, 0.19, 0.26, 0.92)
const TEAL_DK := Color(1, 1, 1, 0.16)
const SUN := Color(0.2, 0.19, 0.26, 0.92)
const SUN_DK := Color(1, 1, 1, 0.16)
const LILAC := Color(0.2, 0.19, 0.26, 0.92)
const LILAC_DK := Color(1, 1, 1, 0.16)
const SKY := Color(0.2, 0.19, 0.26, 0.92)
const SKY_DK := Color(1, 1, 1, 0.16)
const LEAF := Color(0.2, 0.19, 0.26, 0.92)
const LINE := Color(1, 1, 1, 0.12)  # hairlines and empty pips
const LINE_DK := Color(1, 1, 1, 0.22)
const DIM := Color(0.02, 0.02, 0.05, 0.62)
const AMBER := Color("ffb347")      # a second, warm highlight (coins, warnings)
const SHADE := Color("17151d")      # dark, for outlines round type over the 3D view
# the in-car controls keep their illustrated sticker colours (they're art, not panels)
const STK_INK := Color("2f2d2a")
const STK_PAPER := Color("f7f5f1")
const STK_LINE := Color("dcd6cd")
static var _fonts := {}

## The game's face: Outfit (OFL), a clean geometric sans, variable weight; what it hasn't got (accented
## letters past Latin-1: its own extension; symbols: Fredoka) comes from the fallbacks.
static var _base: Font
static func base_font() -> Font:
	if _base == null:
		var f: FontFile = load("res://assets/fonts/Outfit.woff2")
		var fb: Array[Font] = []
		for p in ["res://assets/fonts/Outfit-ext.woff2", "res://assets/fonts/Fredoka.ttf"]:
			if ResourceLoader.exists(p):
				fb.append(load(p))
		f.fallbacks = fb
		_base = f
	return _base

static func font(weight := 600) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var fv := FontVariation.new()
	fv.base_font = base_font()
	fv.variation_opentype = {"wght": weight}
	_fonts[weight] = fv
	return fv

## The same face with the letters spread (titles, the DRIVE button).
static func font_spaced(weight: int, spacing: int) -> Font:
	var key := weight * 1000 + spacing
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	fv.base_font = base_font()
	fv.variation_opentype = {"wght": weight}
	fv.spacing_glyph = spacing
	_fonts[key] = fv
	return fv

## The game's name, the one way it's ever written: the Lo-Fi Life logo (assets/ui: the wordmark on one line;
## stacked, the full logo with the car, the pines and the viaduct over it). size: about the letters' height.
static func wordmark(size := 64, stacked := false, align := HORIZONTAL_ALIGNMENT_LEFT) -> Control:
	var path := "res://assets/ui/logo.png" if stacked else "res://assets/ui/wordmark.png"
	var tr := TextureRect.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(path):
		tr.texture = load(path)
	if tr.texture == null:
		return label("LO-FI LIFE", size, INK, 800, align)
	var h := size * (3.2 if stacked else 1.25)
	tr.custom_minimum_size = Vector2(h * tr.texture.get_width() / tr.texture.get_height(), h)
	tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if align == HORIZONTAL_ALIGNMENT_CENTER else Control.SIZE_SHRINK_BEGIN
	return tr

## A quiet text link (icon and word, no box): soft grey, white when pressed.
static func link(text: String, icon := "", size := 26) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.text = ""
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var ic: Control = null
	if icon != "":
		ic = Icon.new(icon, INK_SOFT, size * 1.05)
		(ic as Icon).color2 = SHADE
		hb.add_child(ic)
	var l: Label = null
	if text != "":
		l = label(text, size, INK_SOFT, 500)
		l.add_theme_font_override("font", font_spaced(500, 2))
		hb.add_child(l)
	# (sized from its contents: an icon, the gap, the word)
	var w := (size * 1.05 + 10.0 if icon != "" else 0.0) + (font_spaced(500, 2).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x if text != "" else 0.0)
	b.custom_minimum_size = Vector2(w + 8.0, size * 2.2)
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tint := func(on: bool):
		var c := INK if on else INK_SOFT
		if l:
			l.add_theme_color_override("font_color", c)
		if ic:
			(ic as Icon).color = c
			ic.queue_redraw()
	b.button_down.connect(func(): tint.call(true))
	b.button_up.connect(func(): tint.call(false))
	b.mouse_entered.connect(func(): tint.call(true))
	b.mouse_exited.connect(func(): tint.call(false))
	squishy(b)
	return b

static func label(text: String, size := 32, col := INK, weight := 600, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func outlined(l: Label, outline := SHADE, w := 10) -> Label:
	# (always a dark outline: type over the 3D view is light)
	if outline.get_luminance() > 0.5:
		outline = SHADE
	l.add_theme_color_override("font_outline_color", Color(outline, 0.85))
	l.add_theme_constant_override("outline_size", w)
	return l

static func box(bg: Color, radius := 28, lip := 0, lip_col := Color.TRANSPARENT, pad := 20) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	if lip > 0:
		sb.border_width_bottom = lip
		sb.border_color = lip_col
	return sb

static func card(bg := PAPER, radius := 28) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(bg if bg.get_luminance() < 0.5 else PAPER, radius, 0, Color.TRANSPARENT, 30)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.13)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 24
	sb.shadow_offset = Vector2(0, 10)
	p.add_theme_stylebox_override("panel", sb)
	return p

## Chunky toy button with a lip that squashes when pressed.
static func button(text: String, bg := CORAL, dk := CORAL_DK, size := 38, min_w := 0.0, h := 92.0, icon := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, h)
	b.add_theme_font_override("font", font(650))
	b.add_theme_font_size_override("font_size", size)
	var accent := bg == CORAL
	if bg.get_luminance() > 0.6 and not accent:
		bg = TEAL      # (an old light button colour: quiet glass now)
	var fg := Color("1a0f16") if accent else INK
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(st, fg)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))
	var normal := _glass(bg, int(h * 0.5), accent)
	var hover := _glass(bg.lightened(0.06), int(h * 0.5), accent)
	var pressed := _glass(bg.darkened(0.12), int(h * 0.5), accent)
	pressed.content_margin_top += 3
	var disabled := _glass(Color(1, 1, 1, 0.05), int(h * 0.5), false)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if icon != "":
		# icon + text centered together; the button keeps its text for later updates via set_meta
		var hb := HBoxContainer.new()
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.offset_bottom = -6
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", 14)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(Icon.new(icon, fg, h * 0.4))
		var l := label(text, size, fg, 650)
		hb.add_child(l)
		b.add_child(hb)
		b.text = ""
		b.set_meta("label", l)
		# (a safety net: text set straight on the button moves into its label, never drawn twice over)
		b.draw.connect(func() -> void:
			if b.text != "":
				l.text = b.text
				b.text = "")
	squishy(b)
	return b

## Change a button's words (icon buttons keep theirs in a label beside the icon).
static func button_text(b: Button) -> String:
	var l = b.get_meta("label") if b.has_meta("label") else null
	return (l as Label).text if l is Label else b.text

static func set_text(b: Button, t: String) -> void:
	var l = b.get_meta("label") if b.has_meta("label") else null
	if l is Label:
		(l as Label).text = t
	else:
		b.text = t

## A glass pill: the colour, a hairline round it; the accent ones glow softly.
static func _glass(bg: Color, radius: int, accent: bool) -> StyleBoxFlat:
	var sb := box(bg, radius, 0, Color.TRANSPARENT, 26)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.35) if accent else Color(1, 1, 1, 0.14)
	if accent:
		sb.shadow_color = Color(CORAL, 0.45)
		sb.shadow_size = 14
	return sb

## Buttons shrink a touch while held, like pressing a toy.
static func squishy(b: Control) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	if b is BaseButton:
		b.button_down.connect(func():
			b.create_tween().tween_property(b, "scale", Vector2(0.95, 0.95), 0.06))
		b.button_up.connect(func():
			b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

## The HUD's one button look: a disc of dark smoked glass, a soft shadow under it, a faint sheen across
## the top and a hairline rim; pressed (or on), it fills with the accent and the rim lights. Drawn as circles
## (a StyleBoxFlat as round as it is wide leaves a hairline seam down the middle on some phones).
static func disc(ci: CanvasItem, cc: Vector2, r: float, on := false, accent := CORAL, lit := true) -> void:
	ci.draw_circle(cc + Vector2(0, r * 0.06 + 1.5), r + 1.0, Color(0, 0, 0, 0.2 if lit else 0.1))
	ci.draw_circle(cc, r, Color(0.055, 0.05, 0.08, 0.6 if lit else 0.34))
	if on:
		ci.draw_circle(cc, r, Color(accent, 0.34))
	ci.draw_arc(cc, r - r * 0.09, PI * 1.18, PI * 1.82, 24, Color(1, 1, 1, 0.09 if lit else 0.04), maxf(2.0, r * 0.05), true)
	ci.draw_arc(cc, r - 0.75, 0, TAU, maxi(32, int(r)), Color(accent, 0.95) if on else Color(1, 1, 1, 0.22 if lit else 0.1), 2.5 if on else 1.5, true)

## The HUD's button art (assets/ui/hud: <name>_idle.png, <name>_on.png, the lo-fi hardware set): drawn
## fitted into rect, keeping its shape; pressed, the "on" art at the same scale, sat on the same bottom
## edge (it's drawn pushed in). False if there's no art by that name.
static var _art := {}
static func art(name: String) -> Array:
	if not _art.has(name):
		var p := "res://assets/ui/hud/%s_idle.png" % name
		var q := "res://assets/ui/hud/%s_on.png" % name
		_art[name] = [load(p), load(q) if ResourceLoader.exists(q) else load(p)] if ResourceLoader.exists(p) else []
	return _art[name]

static func draw_art(ci: CanvasItem, rect: Rect2, name: String, on: bool) -> bool:
	var t := art(name)
	if t.is_empty():
		return false
	var idle: Texture2D = t[0]
	var tex: Texture2D = t[1] if on else t[0]
	var s := minf(rect.size.x / idle.get_width(), rect.size.y / idle.get_height())
	var ts := tex.get_size() * s
	var bottom := rect.get_center().y + idle.get_height() * s * 0.5
	ci.draw_texture_rect(tex, Rect2(Vector2(rect.get_center().x - ts.x * 0.5, bottom - ts.y), ts), false)
	return true

## A round button drawn with the HUD art instead (its icon hidden).
static func set_art(b: Button, name: String) -> void:
	if art(name).is_empty():
		return
	b.set_meta("art", name)
	if b.has_meta("icon"):
		(b.get_meta("icon") as Control).visible = false
	b.queue_redraw()

## Round icon button (pause, settings…).
static func round_button(icon: String, bg := PAPER, dk := LINE, d := 96.0, icol := INK) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(d, d)
	if bg.get_luminance() > 0.6:
		bg = PAPER
	if icol.get_luminance() < 0.3:
		icol = INK
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.draw.connect(func():
		var pr := b.get_draw_mode() == BaseButton.DRAW_PRESSED or b.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED
		if b.has_meta("art") and draw_art(b, Rect2(Vector2.ZERO, b.size), String(b.get_meta("art")), pr):
			return
		disc(b, b.size * 0.5, minf(b.size.x, b.size.y) * 0.5 - 1.0, pr))
	var ic := Icon.new(icon, icol, d * 0.46)
	ic.color2 = SHADE            # (the cut-outs in an icon: dark, so a white icon keeps its details)
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = d * 0.27
	ic.offset_right = -d * 0.27
	ic.offset_top = d * 0.23
	ic.offset_bottom = -d * 0.31
	b.add_child(ic)
	b.set_meta("icon", ic)
	squishy(b)
	return b

## A pill showing an icon and a value (coins in the corner).
static func pill(icon: String, text: String, size := 34) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _glass(Color(PAPER, 0.62), 40, false)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)
	hb.add_child(Icon.new(icon, INK, size * 1.1))
	var l := label(text, size, INK, 650)
	hb.add_child(l)
	p.set_meta("label", l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func bar(w: float, h: float, fill: Color, back := LINE) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(w, h)
	pb.show_percentage = false
	pb.max_value = 1.0
	pb.step = 0.0
	if fill.get_luminance() < 0.35 or fill.a < 0.95:
		fill = CORAL     # (a dark fill would vanish on the glass)
	var f := box(fill, int(h * 0.5), 0, Color.TRANSPARENT, 0)
	var b := box(back, int(h * 0.5), 0, Color.TRANSPARENT, 0)
	pb.add_theme_stylebox_override("fill", f)
	pb.add_theme_stylebox_override("background", b)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pb

static func slider(value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = value
	s.custom_minimum_size = Vector2(300, 60)
	s.focus_mode = Control.FOCUS_NONE
	var track := box(Color(1, 1, 1, 0.14), 10, 0, Color.TRANSPARENT, 0)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	var fill := box(CORAL, 10, 0, Color.TRANSPARENT, 0)
	fill.content_margin_top = 8
	fill.content_margin_bottom = 8
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var img := Image.create(44, 44, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 44:
		for x in 44:
			var d := Vector2(x - 21.5, y - 21.5).length()
			if d < 21.0:
				img.set_pixel(x, y, Color.WHITE if d < 15.0 else CORAL)
	var tex := ImageTexture.create_from_image(img)
	s.add_theme_icon_override("grabber", tex)
	s.add_theme_icon_override("grabber_highlight", tex)
	return s

static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## Money, as the HUD shows it: $12,500.
static func money(n: int) -> String:
	return ("-$" if n < 0 else "$") + fmt(absi(n))

static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
