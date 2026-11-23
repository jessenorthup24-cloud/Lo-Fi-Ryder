extends RefCounted
## Building blocks for the UI: fonts, chunky pill buttons, cards, labels.

const Icon := preload("res://scripts/ui/icon.gd")

# a calm, neutral palette: warm whites, stone greys and charcoal (names kept from the old colourful kit)
const CREAM := Color("efebe5")
const PAPER := Color("f7f5f1")
const INK := Color("2f2d2a")
const INK_SOFT := Color("7a756f")
const CORAL := Color("34322f")      # primary: charcoal
const CORAL_DK := Color("1d1c1a")
const TEAL := Color("7d8780")       # sage grey
const TEAL_DK := Color("5e6862")
const SUN := Color("bfae90")        # sand
const SUN_DK := Color("9c8c70")
const LILAC := Color("9e978f")      # taupe
const LILAC_DK := Color("7f7871")
const SKY := Color("8995a0")        # slate
const SKY_DK := Color("6a7580")
const LEAF := Color("8b9681")
const LINE := Color("dcd6cd")       # light edges and empty pips
const LINE_DK := Color("c3bcb2")
const DIM := Color(0.08, 0.08, 0.08, 0.45)
static var _fonts := {}

static func font(weight := 600) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var fv := FontVariation.new()
	fv.base_font = load("res://assets/fonts/Fredoka.ttf")
	fv.variation_opentype = {"wght": weight}
	_fonts[weight] = fv
	return fv

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

static func outlined(l: Label, outline := INK, w := 10) -> Label:
	l.add_theme_color_override("font_outline_color", outline)
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

static func card(bg := PAPER, radius := 36) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(bg, radius, 8, LINE_DK, 28)
	sb.shadow_color = Color(0.1, 0.1, 0.1, 0.18)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 8)
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
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(st, Color.WHITE if bg != PAPER and bg != CREAM else INK)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.75))
	var normal := box(bg, int(h * 0.5), 8, dk, 26)
	var hover := box(bg.lightened(0.05), int(h * 0.5), 8, dk, 26)
	var pressed := box(bg.darkened(0.04), int(h * 0.5), 2, dk, 26)
	pressed.content_margin_top += 6
	var disabled := box(Color("d6d1ca"), int(h * 0.5), 8, Color("bdb7af"), 26)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if icon != "":
		# icon + text centered together; the button keeps its text for later updates via set_meta
		var fg: Color = Color.WHITE if bg != PAPER and bg != CREAM else INK
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
	squishy(b)
	return b

## Buttons shrink a touch while held, like pressing a toy.
static func squishy(b: Control) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	if b is BaseButton:
		b.button_down.connect(func():
			b.create_tween().tween_property(b, "scale", Vector2(0.95, 0.95), 0.06))
		b.button_up.connect(func():
			b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

## Round icon button (pause, settings…).
static func round_button(icon: String, bg := PAPER, dk := LINE, d := 96.0, icol := INK) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(d, d)
	var normal := box(bg, int(d * 0.5), 7, dk, 0)
	var pressed := box(bg.darkened(0.04), int(d * 0.5), 2, dk, 0)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ic := Icon.new(icon, icol, d * 0.46)
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
	var sb := box(PAPER, 40, 6, LINE, 18)
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
	var track := box(Color("eadccd"), 10, 0, Color.TRANSPARENT, 0)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	var fill := box(TEAL, 10, 0, Color.TRANSPARENT, 0)
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
				img.set_pixel(x, y, Color.WHITE if d < 15.0 else TEAL_DK)
	var tex := ImageTexture.create_from_image(img)
	s.add_theme_icon_override("grabber", tex)
	s.add_theme_icon_override("grabber_highlight", tex)
	return s

static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
