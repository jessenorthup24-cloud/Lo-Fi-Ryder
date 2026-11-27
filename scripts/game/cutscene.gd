extends Node
## The story's scenes, in the game's own world: the camera flies, orbits and dollies over the places and the
## people in them, black bars top and bottom, the names of places in big letters, subtitles with who's
## speaking. Tap to move the talk on; Skip for the lot. The game holds still underneath (paused, not frozen:
## the world carries on) and comes back where it was. campaign_data.gd says what's in each scene.

const Avatar := preload("res://scripts/game/avatar.gd")
const K := preload("res://scripts/ui/kit.gd")
const Data := preload("res://scripts/game/campaign_data.gd")

var game: Node
var active := false
var cam_xf := Transform3D()
var _scene: Dictionary = {}
var _shot := -1
var _t := 0.0
var _dur := 0.0
var _line := -1
var _line_t := 0.0
var _done: Callable
var _actors := {}               # name -> Avatar (kept across the shots of one scene)
var _was_paused := false
var _hud_was := true
# the screen
var layer: CanvasLayer
var _top: ColorRect
var _bot: ColorRect
var _sub: VBoxContainer
var _who: Label
var _say: Label
var _title: Label
var _title_sub: Label
var _skip: Button
var _tap_hint: Label
var _shown := 0.0               # (the typing: how much of the line's out)

func setup(g: Node) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = CanvasLayer.new()
	layer.layer = 40
	layer.visible = false
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(_gui)
	layer.add_child(root)
	_top = ColorRect.new()
	_top.color = Color.BLACK
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_top)
	_bot = ColorRect.new()
	_bot.color = Color.BLACK
	_bot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bot)
	# a place's name, big and spaced, and a line under it
	_title = K.outlined(K.label("", 64, Color.WHITE, 600), Color(0, 0, 0, 0.55), 10)
	_title.add_theme_font_override("font", K.font_spaced(600, 14))
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_title.offset_left = -640
	_title.offset_right = 640
	_title.offset_top = -70
	_title.offset_bottom = 10
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_title)
	_title_sub = K.outlined(K.label("", 22, Color(1, 1, 1, 0.9), 600), Color(0, 0, 0, 0.55), 6)
	_title_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_title_sub.offset_left = -640
	_title_sub.offset_right = 640
	_title_sub.offset_top = 14
	_title_sub.offset_bottom = 50
	_title_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_title_sub)
	# the subtitles, in the bottom bar
	_sub = VBoxContainer.new()
	_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_sub.offset_left = -520
	_sub.offset_right = 520
	_sub.offset_top = -112
	_sub.offset_bottom = -14
	_sub.add_theme_constant_override("separation", 2)
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_sub)
	_who = K.label("", 17, K.CORAL, 800, HORIZONTAL_ALIGNMENT_CENTER)
	_who.add_theme_font_override("font", K.font_spaced(800, 3))
	_sub.add_child(_who)
	_say = K.label("", 23, Color.WHITE, 500, HORIZONTAL_ALIGNMENT_CENTER)
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_say.custom_minimum_size = Vector2(1040, 0)
	_sub.add_child(_say)
	_skip = K.button("Skip  ›", K.PAPER, K.LINE, 18, 120, 46)
	_skip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_skip.position = Vector2(-150, 18)
	_skip.pressed.connect(func(): finish())
	root.add_child(_skip)
	_tap_hint = K.label("tap to continue", 13, Color(1, 1, 1, 0.4), 600)
	_tap_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_tap_hint.position = Vector2(-170, -30)
	_tap_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_tap_hint)

## Play a scene; `done` when it's over (or skipped).
func play(scene: Dictionary, done := Callable()) -> void:
	if active:
		finish()
	_scene = scene
	_done = done
	active = true
	_was_paused = game.state != game.DRIVE
	if game.state == game.DRIVE:
		game.pause(false)
	_hud_was = game.ui.hud.visible
	game.ui.hud.visible = false
	game.drop_touches()
	layer.visible = true
	_bars(true)
	_shot = -1
	_next_shot()

func _bars(on: bool) -> void:
	var h := 84.0 if on else 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_top, "offset_bottom", h, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bot, "offset_top", -h - 24.0 if on else 0.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _next_shot() -> void:
	var shots: Array = _scene.get("shots", [])
	_shot += 1
	if _shot >= shots.size():
		finish()
		return
	var s: Dictionary = shots[_shot]
	if s.get("clear", false):
		_clear_actors()
	var lines: Array = s.get("lines", [])
	_t = 0.0
	_dur = float(s.get("dur", 3.0))
	var talk := 0.0
	for l in lines:
		talk += 1.2 + String(l[1]).length() * 0.045
	_dur = maxf(_dur, talk)
	_line = -1
	_line_t = 0.0
	_who.text = ""
	_say.text = ""
	for a in s.get("actors", []):
		_actor(a, s)
	var tt: Array = s.get("title", [])
	_title.modulate.a = 0.0
	_title_sub.modulate.a = 0.0
	if tt.size() > 0:
		_title.text = String(tt[0])
		_title_sub.text = String(tt[1]) if tt.size() > 1 else ""
		var tw := create_tween()
		tw.tween_interval(0.4)
		tw.tween_property(_title, "modulate:a", 1.0, 0.7)
		tw.parallel().tween_property(_title_sub, "modulate:a", 1.0, 0.9)
		tw.tween_interval(maxf(1.6, minf(_dur - 2.2, 3.0)))
		tw.tween_property(_title, "modulate:a", 0.0, 0.6)
		tw.parallel().tween_property(_title_sub, "modulate:a", 0.0, 0.6)
	if not lines.is_empty():
		_next_line()

func _next_line() -> void:
	var lines: Array = (_scene["shots"][_shot] as Dictionary).get("lines", [])
	_line += 1
	if _line >= lines.size():
		_who.text = ""
		_say.text = ""
		return
	var l: Array = lines[_line]
	var who := String(l[0])
	_who.text = who.to_upper()
	_who.add_theme_color_override("font_color", (Data.CAST[who]["col"] as Color) if Data.CAST.has(who) else Color(1, 1, 1, 0.7))
	_say.text = String(l[1])
	_say.visible_ratio = 0.0
	_shown = 0.0
	_line_t = 1.2 + String(l[1]).length() * 0.045
	# the speaker talks while they're speaking
	if _actors.has(who) and is_instance_valid(_actors[who]):
		(_actors[who] as Avatar).play("talk")

func _gui(e: InputEvent) -> void:
	var tap: bool = (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if not tap or not active:
		return
	# a tap: the line all at once, then on to the next (and past the last, the next shot)
	if _say.visible_ratio < 1.0:
		_say.visible_ratio = 1.0
		return
	var lines: Array = (_scene["shots"][_shot] as Dictionary).get("lines", [])
	if _line < lines.size() - 1:
		_next_line()
	else:
		_next_shot()

func _process(dt: float) -> void:
	if not active:
		return
	var shots: Array = _scene.get("shots", [])
	if _shot < 0 or _shot >= shots.size():
		return
	var s: Dictionary = shots[_shot]
	_t += dt
	# the typing
	if _say.visible_ratio < 1.0:
		_say.visible_ratio = minf(1.0, _say.visible_ratio + dt * 40.0 / maxf(_say.text.length(), 1.0))
	var lines: Array = s.get("lines", [])
	if _line >= 0 and _line < lines.size():
		_line_t -= dt
		if _line_t <= 0.0:
			if _line < lines.size() - 1:
				_next_line()
			else:
				_line = lines.size()
	_tap_hint.visible = _line >= 0 and _line < lines.size() and _say.visible_ratio >= 1.0
	var k := clampf(_t / maxf(_dur, 0.1), 0.0, 1.0)
	cam_xf = _cam(s, smoothstep(0.0, 1.0, k))
	game.cam.global_transform = cam_xf
	if _t >= _dur and (_line < 0 or _line >= lines.size()):
		_next_shot()

## The camera along a shot, k from 0 to 1.
func _cam(s: Dictionary, k: float) -> Transform3D:
	var at: Vector3 = game.campaign.anchor(String(s["at"]))
	var c: Array = s.get("cam", ["orbit", 10, 3, 0, 40])
	match String(c[0]):
		"orbit":
			var r := float(c[1])
			var hh := float(c[2])
			var look := at
			var acts: Array = s.get("actors", [])
			if not acts.is_empty():
				# people in the shot: in close enough to see faces, aimed at the middle of the group
				r = minf(r, 8.5)
				hh = minf(hh, 2.6)
				for ac in acts:
					look += Vector3(float(ac[1][0]), 0, float(ac[1][1])) / float(acts.size() + 1)
			var a := deg_to_rad(lerpf(float(c[3]), float(c[4]), k))
			var p := look + Vector3(sin(a) * r, hh, cos(a) * r)
			p.y = maxf(p.y, game.island.height_at(p.x, p.z) + 1.2)
			return Transform3D(Basis(), p).looking_at(look + Vector3(0, 1.3, 0), Vector3.UP)
		"fly":
			var h := lerpf(float(c[1]), float(c[2]), k)
			var d := float(c[3]) * lerpf(1.0, 0.65, k)
			var a2 := lerpf(0.0, 0.5, k) + float(s.get("yaw", 0.6))
			var p2 := at + Vector3(sin(a2) * d, h, cos(a2) * d)
			return Transform3D(Basis(), p2).looking_at(at, Vector3.UP)
		"dolly":
			var a0: Array = c[1]
			var a1: Array = c[2]
			var lk: Array = c[3]
			var p3 := at + Vector3(a0[0], a0[1], a0[2]).lerp(Vector3(a1[0], a1[1], a1[2]), k)
			return Transform3D(Basis(), p3).looking_at(at + Vector3(lk[0], lk[1], lk[2]), Vector3.UP)
	return Transform3D(Basis(), at + Vector3(0, 5, 8)).looking_at(at, Vector3.UP)

## Someone in the scene: [who, [x, z] from the anchor, facing, anim].
func _actor(a: Array, s: Dictionary) -> void:
	var who := String(a[0])
	var at: Vector3 = game.campaign.anchor(String(s["at"]))
	var off: Array = a[1]
	var p := at + Vector3(float(off[0]), 0, float(off[1]))
	p.y = game.island.height_at(p.x, p.z)
	var av: Avatar
	if _actors.has(who) and is_instance_valid(_actors[who]):
		av = _actors[who]
	else:
		var look := String(Data.CAST.get(who, {}).get("look", ""))
		if look == "":
			return
		av = Avatar.new()
		av.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(av)
		av.setup(look, "", game.toon)
		_actors[who] = av
	av.global_position = p
	var face = a[2]
	var tgt: Vector3 = game.you().global_position
	if String(s["at"]) != "you":
		tgt = at
	if face is String and face == "cam":
		tgt = _cam(s, 0.5).origin
	if face is String:
		var to: Vector3 = tgt - p
		av.rotation.y = atan2(to.x, to.z)
	else:
		av.rotation.y = deg_to_rad(float(face))
	av.play(String(a[3]) if a.size() > 3 else "idle")

func _clear_actors() -> void:
	for k in _actors:
		if is_instance_valid(_actors[k]):
			(_actors[k] as Node).queue_free()
	_actors.clear()

## Over (or skipped): the bars away, the people gone, the game back as it was.
func finish() -> void:
	if not active:
		return
	active = false
	_clear_actors()
	_bars(false)
	_title.modulate.a = 0.0
	_title_sub.modulate.a = 0.0
	_who.text = ""
	_say.text = ""
	get_tree().create_timer(0.45, true).timeout.connect(func():
		if not active:
			layer.visible = false)
	game.ui.hud.visible = _hud_was
	if not _was_paused and game.state == game.PAUSED:
		game.resume()
	var d := _done
	_done = Callable()
	if d.is_valid():
		d.call()
