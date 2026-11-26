extends Control
## Small vector icons drawn in code (no image files).

var kind := "coin"
var color := Color("4a3a33")
var color2 := Color("ffffff")

func _init(k := "coin", c := Color("4a3a33"), sz := 40.0) -> void:
	kind = k
	color = c
	custom_minimum_size = Vector2(sz, sz)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var c := o + Vector2(s, s) * 0.5
	match kind:
		"coin":
			# cash: a green banknote with a dollar sign (the game's money; the kind's kept its old name)
			var bill := Rect2(o + Vector2(s * 0.02, s * 0.22), Vector2(s * 0.96, s * 0.56))
			_round_rect(Rect2(bill.position + Vector2(s * 0.03, s * 0.05), bill.size), s * 0.08, Color("2f8f3a"))
			_round_rect(bill, s * 0.08, Color("66d31f"))
			_round_rect(bill.grow(-s * 0.07), s * 0.05, Color("8fe35a"))
			draw_circle(c, s * 0.17, Color("3fa52a"))
			var f := ThemeDB.fallback_font
			var fs := int(s * 0.3)
			var tw := f.get_string_size("$", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, c + Vector2(-tw * 0.5, fs * 0.36), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("f2ffe6"))
		"heart":
			var r := s * 0.24
			draw_circle(o + Vector2(s * 0.32, s * 0.38), r, color)
			draw_circle(o + Vector2(s * 0.68, s * 0.38), r, color)
			draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.1, s * 0.46), o + Vector2(s * 0.9, s * 0.46), o + Vector2(s * 0.5, s * 0.9)]), color)
		"fuel":
			var body := Rect2(o + Vector2(s * 0.16, s * 0.26), Vector2(s * 0.62, s * 0.7))
			_round_rect(body, s * 0.12, Color("ec4b3f"))
			_round_rect(Rect2(o + Vector2(s * 0.26, s * 0.1), Vector2(s * 0.3, s * 0.12)), s * 0.05, Color("c43328"))
			draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.62, s * 0.28), o + Vector2(s * 0.84, s * 0.06), o + Vector2(s * 0.92, s * 0.14), o + Vector2(s * 0.74, s * 0.34)]), Color("ffd36b"))
			_round_rect(Rect2(o + Vector2(s * 0.28, s * 0.42), Vector2(s * 0.38, s * 0.38)), s * 0.08, Color("ff8a7e"))
		"car":
			_round_rect(Rect2(o + Vector2(s * 0.08, s * 0.42), Vector2(s * 0.84, s * 0.3)), s * 0.1, color)
			_round_rect(Rect2(o + Vector2(s * 0.24, s * 0.22), Vector2(s * 0.5, s * 0.28)), s * 0.1, color)
			draw_circle(o + Vector2(s * 0.28, s * 0.74), s * 0.11, color)
			draw_circle(o + Vector2(s * 0.72, s * 0.74), s * 0.11, color)
			draw_circle(o + Vector2(s * 0.28, s * 0.74), s * 0.05, color2)
			draw_circle(o + Vector2(s * 0.72, s * 0.74), s * 0.05, color2)
		"flag":
			draw_line(o + Vector2(s * 0.24, s * 0.1), o + Vector2(s * 0.24, s * 0.92), color, s * 0.09, true)
			var pts := PackedVector2Array([o + Vector2(s * 0.28, s * 0.12), o + Vector2(s * 0.84, s * 0.26), o + Vector2(s * 0.28, s * 0.52)])
			draw_colored_polygon(pts, color)
		"calendar":
			_round_rect(Rect2(o + Vector2(s * 0.1, s * 0.18), Vector2(s * 0.8, s * 0.72)), s * 0.12, color)
			_round_rect(Rect2(o + Vector2(s * 0.18, s * 0.4), Vector2(s * 0.64, s * 0.42)), s * 0.06, color2)
			draw_rect(Rect2(o + Vector2(s * 0.26, s * 0.08), Vector2(s * 0.09, s * 0.2)), color)
			draw_rect(Rect2(o + Vector2(s * 0.65, s * 0.08), Vector2(s * 0.09, s * 0.2)), color)
			draw_circle(o + Vector2(s * 0.36, s * 0.55), s * 0.05, color)
			draw_circle(o + Vector2(s * 0.5, s * 0.55), s * 0.05, color)
			draw_circle(o + Vector2(s * 0.64, s * 0.55), s * 0.05, color)
			draw_circle(o + Vector2(s * 0.36, s * 0.69), s * 0.05, color)
		"gear":
			for i in 8:
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * s * 0.2, c + d * s * 0.46, color, s * 0.16)
			draw_circle(c, s * 0.32, color)
			draw_circle(c, s * 0.13, color2)
		"pause":
			_round_rect(Rect2(o + Vector2(s * 0.26, s * 0.22), Vector2(s * 0.16, s * 0.56)), s * 0.05, color)
			_round_rect(Rect2(o + Vector2(s * 0.58, s * 0.22), Vector2(s * 0.16, s * 0.56)), s * 0.05, color)
		"play":
			draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.3, s * 0.18), o + Vector2(s * 0.82, s * 0.5), o + Vector2(s * 0.3, s * 0.82)]), color)
		"back":
			draw_polyline(PackedVector2Array([o + Vector2(s * 0.62, s * 0.18), o + Vector2(s * 0.3, s * 0.5), o + Vector2(s * 0.62, s * 0.82)]), color, s * 0.14, true)
		"left":
			draw_polyline(PackedVector2Array([o + Vector2(s * 0.62, s * 0.2), o + Vector2(s * 0.34, s * 0.5), o + Vector2(s * 0.62, s * 0.8)]), color, s * 0.13, true)
		"right":
			draw_polyline(PackedVector2Array([o + Vector2(s * 0.38, s * 0.2), o + Vector2(s * 0.66, s * 0.5), o + Vector2(s * 0.38, s * 0.8)]), color, s * 0.13, true)
		"check":
			draw_polyline(PackedVector2Array([o + Vector2(s * 0.2, s * 0.52), o + Vector2(s * 0.42, s * 0.74), o + Vector2(s * 0.82, s * 0.28)]), color, s * 0.15, true)
		"lock":
			draw_arc(c + Vector2(0, -s * 0.08), s * 0.2, PI, TAU, 16, color, s * 0.1)
			_round_rect(Rect2(o + Vector2(s * 0.2, s * 0.4), Vector2(s * 0.6, s * 0.46)), s * 0.08, color)
		"home":
			draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.5, s * 0.12), o + Vector2(s * 0.9, s * 0.48), o + Vector2(s * 0.1, s * 0.48)]), color)
			_round_rect(Rect2(o + Vector2(s * 0.2, s * 0.44), Vector2(s * 0.6, s * 0.44)), s * 0.05, color)
			_round_rect(Rect2(o + Vector2(s * 0.42, s * 0.6), Vector2(s * 0.16, s * 0.28)), s * 0.03, color2)
		"trophy":
			_round_rect(Rect2(o + Vector2(s * 0.24, s * 0.12), Vector2(s * 0.52, s * 0.42)), s * 0.18, color)
			draw_arc(o + Vector2(s * 0.24, s * 0.3), s * 0.12, PI * 0.5, PI * 1.5, 12, color, s * 0.07)
			draw_arc(o + Vector2(s * 0.76, s * 0.3), s * 0.12, -PI * 0.5, PI * 0.5, 12, color, s * 0.07)
			draw_rect(Rect2(o + Vector2(s * 0.44, s * 0.5), Vector2(s * 0.12, s * 0.22)), color)
			_round_rect(Rect2(o + Vector2(s * 0.28, s * 0.72), Vector2(s * 0.44, s * 0.14)), s * 0.04, color)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + TAU * i / 10.0
				var r := s * (0.46 if i % 2 == 0 else 0.2)
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, color)
		"music":
			draw_line(o + Vector2(s * 0.36, s * 0.7), o + Vector2(s * 0.36, s * 0.16), color, s * 0.08)
			draw_line(o + Vector2(s * 0.76, s * 0.6), o + Vector2(s * 0.76, s * 0.08), color, s * 0.08)
			draw_line(o + Vector2(s * 0.36, s * 0.18), o + Vector2(s * 0.76, s * 0.1), color, s * 0.12)
			draw_circle(o + Vector2(s * 0.28, s * 0.72), s * 0.13, color)
			draw_circle(o + Vector2(s * 0.68, s * 0.62), s * 0.13, color)
		"sound":
			draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.12, s * 0.36), o + Vector2(s * 0.32, s * 0.36), o + Vector2(s * 0.56, s * 0.14), o + Vector2(s * 0.56, s * 0.86), o + Vector2(s * 0.32, s * 0.64), o + Vector2(s * 0.12, s * 0.64)]), color)
			draw_arc(o + Vector2(s * 0.56, s * 0.5), s * 0.18, -0.9, 0.9, 10, color, s * 0.07)
			draw_arc(o + Vector2(s * 0.56, s * 0.5), s * 0.32, -0.9, 0.9, 12, color, s * 0.07)
		"vibe":
			_round_rect(Rect2(o + Vector2(s * 0.32, s * 0.12), Vector2(s * 0.36, s * 0.76)), s * 0.08, color)
			_round_rect(Rect2(o + Vector2(s * 0.37, s * 0.2), Vector2(s * 0.26, s * 0.54)), s * 0.03, color2)
			draw_line(o + Vector2(s * 0.16, s * 0.34), o + Vector2(s * 0.16, s * 0.66), color, s * 0.07)
			draw_line(o + Vector2(s * 0.84, s * 0.34), o + Vector2(s * 0.84, s * 0.66), color, s * 0.07)
		"shadow":
			draw_circle(c + Vector2(-s * 0.06, -s * 0.08), s * 0.26, color)
			draw_set_transform(c + Vector2(s * 0.08, s * 0.3), 0, Vector2(1, 0.35))
			draw_circle(Vector2.ZERO, s * 0.32, Color(color, 0.45))
			draw_set_transform(Vector2.ZERO)
		"sun":
			for i in 8:
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * s * 0.3, c + d * s * 0.46, color, s * 0.08)
			draw_circle(c, s * 0.22, color)
		"moon":
			draw_circle(c, s * 0.36, color)
			draw_circle(c + Vector2(s * 0.16, -s * 0.12), s * 0.3, color2)
		"leaf":
			draw_set_transform(c, -0.6, Vector2(1, 0.55))
			draw_circle(Vector2.ZERO, s * 0.4, color)
			draw_set_transform(Vector2.ZERO)
			draw_line(c + Vector2(-s * 0.32, s * 0.24), c + Vector2(s * 0.3, -s * 0.2), color2, s * 0.05)
		"snow":
			for i in 3:
				var a := PI * i / 3.0
				var d := Vector2(cos(a), sin(a))
				draw_line(c - d * s * 0.42, c + d * s * 0.42, color, s * 0.08)
			draw_circle(c, s * 0.1, color)
		"rain":
			draw_circle(c + Vector2(-s * 0.15, -s * 0.12), s * 0.2, color)
			draw_circle(c + Vector2(s * 0.12, -s * 0.18), s * 0.24, color)
			_round_rect(Rect2(o + Vector2(s * 0.12, s * 0.28), Vector2(s * 0.72, s * 0.2)), s * 0.1, color)
			for i in 3:
				var x := s * (0.26 + i * 0.22)
				draw_line(o + Vector2(x, s * 0.6), o + Vector2(x - s * 0.06, s * 0.82), color, s * 0.07)
		"wind":
			draw_polyline(PackedVector2Array([o + Vector2(s * 0.1, s * 0.36), o + Vector2(s * 0.66, s * 0.36)]), color, s * 0.08)
			draw_arc(o + Vector2(s * 0.66, s * 0.26), s * 0.1, PI * 0.5, PI * 2.2, 10, color, s * 0.08)
			draw_polyline(PackedVector2Array([o + Vector2(s * 0.1, s * 0.6), o + Vector2(s * 0.78, s * 0.6)]), color, s * 0.08)
			draw_arc(o + Vector2(s * 0.78, s * 0.72), s * 0.12, -PI * 0.5, PI * 1.2, 10, color, s * 0.08)
		"fog":
			for i in 3:
				var y := s * (0.3 + i * 0.2)
				var x0 := s * (0.12 + (i % 2) * 0.1)
				draw_line(o + Vector2(x0, y), o + Vector2(x0 + s * 0.66, y), color, s * 0.1)
		"map":
			draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.1, s * 0.2), o + Vector2(s * 0.36, s * 0.1), o + Vector2(s * 0.64, s * 0.2), o + Vector2(s * 0.9, s * 0.1), o + Vector2(s * 0.9, s * 0.8), o + Vector2(s * 0.64, s * 0.9), o + Vector2(s * 0.36, s * 0.8), o + Vector2(s * 0.1, s * 0.9)]), color)
			draw_line(o + Vector2(s * 0.36, s * 0.12), o + Vector2(s * 0.36, s * 0.8), color2, s * 0.04)
			draw_line(o + Vector2(s * 0.64, s * 0.2), o + Vector2(s * 0.64, s * 0.88), color2, s * 0.04)
		"magnet":
			draw_arc(c + Vector2(0, -s * 0.04), s * 0.28, PI, TAU, 16, color, s * 0.16)
			draw_rect(Rect2(o + Vector2(s * 0.14, s * 0.44), Vector2(s * 0.16, s * 0.24)), color)
			draw_rect(Rect2(o + Vector2(s * 0.7, s * 0.44), Vector2(s * 0.16, s * 0.24)), color)
			draw_rect(Rect2(o + Vector2(s * 0.14, s * 0.66), Vector2(s * 0.16, s * 0.12)), color2)
			draw_rect(Rect2(o + Vector2(s * 0.7, s * 0.66), Vector2(s * 0.16, s * 0.12)), color2)
		"tire":
			# a wheel: a thick tyre, a hub, five spokes (drawn in the one colour, so it reads on any button)
			draw_arc(c, s * 0.37, 0.0, TAU, 40, color, s * 0.14, true)
			draw_circle(c, s * 0.1, color)
			for i in 5:
				var a := TAU * i / 5.0 - PI * 0.5
				draw_line(c, c + Vector2(cos(a), sin(a)) * s * 0.3, color, s * 0.06, true)
		"radar":
			# a radar: rings, a sweep and a blip
			draw_arc(c, s * 0.42, 0.0, TAU, 40, color, s * 0.06, true)
			draw_arc(c, s * 0.25, 0.0, TAU, 32, color, s * 0.05, true)
			var sw := PackedVector2Array([c])
			for i in 9:
				var a := -PI * 0.5 + i * 0.12
				sw.append(c + Vector2(cos(a), sin(a)) * s * 0.42)
			draw_colored_polygon(sw, Color(color, 0.55))
			draw_circle(c + Vector2(s * 0.2, -s * 0.12), s * 0.06, color)
		"target":
			# crosshairs
			draw_arc(c, s * 0.3, 0.0, TAU, 36, color, s * 0.07, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * s * 0.16, c + d * s * 0.46, color, s * 0.07, true)
			draw_circle(c, s * 0.05, color)
		"paint":
			# a spray can
			_round_rect(Rect2(o + Vector2(s * 0.3, s * 0.3), Vector2(s * 0.4, s * 0.6)), s * 0.08, color)
			draw_rect(Rect2(o + Vector2(s * 0.42, s * 0.18), Vector2(s * 0.16, s * 0.12)), color)
			for k in 3:
				draw_circle(o + Vector2(s * (0.76 + 0.07 * k), s * (0.14 + 0.06 * (k % 2))), s * 0.035, color)
		"person":
			# a head and shoulders
			draw_circle(c + Vector2(0, -s * 0.16), s * 0.17, color)
			var sh := PackedVector2Array()
			for i in 13:
				var a := PI + PI * i / 12.0
				sh.append(c + Vector2(cos(a) * s * 0.34, s * 0.42 + sin(a) * s * 0.34))
			draw_colored_polygon(sh, color)
		"rewind":
			# two triangles pointing back
			for k in 2:
				var x0 := s * (0.5 + 0.02 - 0.32 * k)
				draw_colored_polygon(PackedVector2Array([o + Vector2(x0 + s * 0.32, s * 0.22), o + Vector2(x0 + s * 0.32, s * 0.78), o + Vector2(x0, s * 0.5)]), color)
		"wrench":
			# a spanner: a bar on the slant, an open jaw at the top
			draw_line(c + Vector2(-s * 0.26, s * 0.26), c + Vector2(s * 0.12, -s * 0.12), color, s * 0.16)
			draw_circle(c + Vector2(s * 0.18, -s * 0.18), s * 0.2, color)
			draw_circle(c + Vector2(s * 0.3, -s * 0.3), s * 0.1, color2)
			draw_circle(c + Vector2(-s * 0.27, s * 0.27), s * 0.1, color)
		"help":
			draw_arc(c + Vector2(0, -s * 0.12), s * 0.2, PI * 1.05, PI * 2.35, 14, color, s * 0.13)
			draw_line(c + Vector2(s * 0.06, s * 0.02), c + Vector2(0, s * 0.16), color, s * 0.13)
			draw_circle(c + Vector2(0, s * 0.34), s * 0.08, color)
		"gauge":
			draw_arc(c + Vector2(0, s * 0.1), s * 0.38, PI * 1.05, PI * 1.95, 16, color, s * 0.1)
			draw_line(c + Vector2(0, s * 0.1), c + Vector2(s * 0.2, -s * 0.12), color, s * 0.1)
			draw_circle(c + Vector2(0, s * 0.1), s * 0.08, color)
		"eye":
			# a little camera
			_round_rect(Rect2(o + Vector2(s * 0.08, s * 0.3), Vector2(s * 0.84, s * 0.56)), s * 0.12, color)
			draw_rect(Rect2(o + Vector2(s * 0.32, s * 0.18), Vector2(s * 0.3, s * 0.16)), color)
			draw_circle(c + Vector2(0, s * 0.08), s * 0.19, color2)
			draw_circle(c + Vector2(0, s * 0.08), s * 0.1, color)
		"group":
			# two little cars side by side, a frame round them
			for ox in [0.08, 0.52]:
				_round_rect(Rect2(o + Vector2(s * ox, s * 0.42), Vector2(s * 0.4, s * 0.2)), s * 0.06, color)
				_round_rect(Rect2(o + Vector2(s * (ox + 0.08), s * 0.3), Vector2(s * 0.24, s * 0.16)), s * 0.05, color)
				draw_circle(o + Vector2(s * (ox + 0.1), s * 0.64), s * 0.06, color)
				draw_circle(o + Vector2(s * (ox + 0.3), s * 0.64), s * 0.06, color)
			for cn in [[0.02, 0.12, 1, 1], [0.98, 0.12, -1, 1], [0.02, 0.88, 1, -1], [0.98, 0.88, -1, -1]]:
				var pc := o + Vector2(s * cn[0], s * cn[1])
				draw_line(pc, pc + Vector2(s * 0.16 * cn[2], 0), color, s * 0.06)
				draw_line(pc, pc + Vector2(0, s * 0.16 * cn[3]), color, s * 0.06)
		"phone":
			# a handset: the body, the screen, the button
			_round_rect(Rect2(o + Vector2(s * 0.26, s * 0.06), Vector2(s * 0.48, s * 0.88)), s * 0.1, color)
			_round_rect(Rect2(o + Vector2(s * 0.32, s * 0.16), Vector2(s * 0.36, s * 0.58)), s * 0.04, color2)
			draw_circle(o + Vector2(s * 0.5, s * 0.84), s * 0.045, color2)
		"tank":
			_round_rect(Rect2(o + Vector2(s * 0.14, s * 0.14), Vector2(s * 0.72, s * 0.78)), s * 0.14, color)
			_round_rect(Rect2(o + Vector2(s * 0.26, s * 0.5), Vector2(s * 0.48, s * 0.3)), s * 0.06, color2)
			draw_rect(Rect2(o + Vector2(s * 0.4, s * 0.04), Vector2(s * 0.2, s * 0.14)), color)

func _round_rect(r: Rect2, rad: float, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	draw_style_box(sb, r)
