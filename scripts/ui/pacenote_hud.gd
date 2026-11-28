extends Control
## The co-driver's notes, on screen: in a race or a timed trial, the next corner (or crest, or the finish)
## as a road sign at the top of the screen, how far off it is on a distance plate under it, "!!" when it
## bites, and the one straight after it, smaller, beside it. Close in, the sign pulses.

const PN := preload("res://scripts/game/pacenotes.gd")
const DIR := "res://assets/ui/pacenotes/"
const SHOW := 320.0           # (metres: a note shows this far out)

var game: Node
var notes: Array = []
var _for = null               # what the notes are for (the race, or the trial's gates)
var _loop := 0.0              # a race's lap length (0: a trial, start to finish)
var _tex := {}
var row: HBoxContainer
var sign_rect: TextureRect
var plate_rect: TextureRect
var danger_rect: TextureRect
var then_rect: TextureRect
var _shown := ""
var _pulse := 0.0
var cur: Dictionary = {}      # (the note on screen: for the tests)

func setup(g: Node) -> void:
	game = g
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# (top middle, under the race card)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -260.0
	offset_right = 260.0
	offset_top = 150.0
	offset_bottom = 290.0
	row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	danger_rect = _rect(Vector2(96, 44))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	sign_rect = _rect(Vector2(104, 104), col)
	plate_rect = _rect(Vector2(110, 34), col)
	then_rect = _rect(Vector2(66, 66))
	visible = false

func _rect(sz: Vector2, parent: Control = null) -> TextureRect:
	var r := TextureRect.new()
	r.custom_minimum_size = sz
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.pivot_offset = sz * 0.5
	(parent if parent else row).add_child(r)
	return r

func tex(name: String) -> Texture2D:
	if name == "":
		return null
	if not _tex.has(name):
		_tex[name] = load(DIR + name + ".png") if ResourceLoader.exists(DIR + name + ".png") else null
	return _tex[name]

func tick(dt: float) -> void:
	var at := _where()
	if at.is_empty() or not bool(game.save.data["settings"].get("pacenotes", true)):
		visible = false
		cur = {}
		return
	var s: float = at[0]
	var left_to_go: float = at[1]
	# the next note ahead (round the loop, in a race)
	var best: Dictionary = {}
	var best_d := INF
	for i in notes.size():
		var nt: Dictionary = notes[i]
		var d := float(nt["s"]) - s
		if _loop > 0.0:
			d = fposmod(d, _loop)
			if d > _loop - 6.0:
				d -= _loop       # (just into it: still showing it a moment)
		if d > -6.0 and d < best_d:
			best_d = d
			best = nt
	var show_note := best
	var dist := best_d
	# the finish, when it's the next thing (the last lap's last few hundred metres, or the last gate)
	if left_to_go < SHOW and (best.is_empty() or left_to_go < best_d):
		show_note = {"sign": "finish", "s": s + left_to_go, "danger": false, "len": 0.0}
		dist = left_to_go
	if show_note.is_empty() or dist > SHOW:
		visible = false
		cur = {}
		return
	visible = true
	cur = show_note
	cur["d"] = dist
	var nm := String(show_note["sign"])
	var key := "%s@%.0f" % [nm, float(show_note["s"])]
	if key != _shown:
		_shown = key
		sign_rect.texture = tex(nm)
		danger_rect.texture = tex("danger")
		danger_rect.visible = bool(show_note.get("danger", false))
		# what comes right after it
		then_rect.visible = false
		if nm != "finish":
			var end_s := float(show_note["s"]) + float(show_note.get("len", 0.0))
			for nt in notes:
				var gap := float(nt["s"]) - end_s
				if _loop > 0.0:
					gap = fposmod(gap, _loop)
				if nt != show_note and gap >= 0.0 and gap < 45.0:
					then_rect.texture = tex(String(nt["sign"]))
					then_rect.visible = true
					break
		# (in: a little drop and settle)
		modulate.a = 0.0
		sign_rect.scale = Vector2(1.25, 1.25)
	modulate.a = move_toward(modulate.a, 1.0, dt * 6.0)
	var pl := PN.plate(dist)
	plate_rect.texture = tex(pl)
	plate_rect.modulate.a = 1.0 if pl != "" else 0.0
	# close in: it pulses
	_pulse += dt * 9.0
	var want := 1.0 + (0.08 * (0.5 + 0.5 * sin(_pulse)) if dist < 50.0 else 0.0)
	sign_rect.scale = sign_rect.scale.lerp(Vector2(want, want), 1.0 - exp(-dt * 12.0))

## [how far along you are, how far to the finish], or empty: no notes now.
func _where() -> Array:
	var race = game.race
	if race != null and race.state <= 1 and race.you.size() > 0:
		if _for != race:
			_for = race
			_loop = race.length
			var hy := PackedFloat32Array()
			for i in race.pts.size():
				hy.append(game.island.height_at(race.pts[i].x, race.pts[i].y))
			notes = PN.from_line(race.pts, hy, true)
			_shown = ""
		var rs := float(race.you["s"])
		return [fposmod(rs + race.start_s, race.length), race.length * race.laps - rs]
	var tr: Dictionary = game.trial
	if not tr.is_empty() and game.intro.is_empty() and game.timed_kind(tr["kind"]):
		var gates: Array = tr["gates"]
		if _for != gates:
			_for = gates
			_loop = 0.0
			notes = PN.from_gates(gates)
			_shown = ""
		# along the gates: up to the last one you went through, and on along the leg you're on
		var g: int = clampi(game.trial_gate, 1, gates.size() - 1)
		var s := 0.0
		for i in range(1, g):
			var a: Vector3 = (gates[i - 1] as Transform3D).origin
			var b: Vector3 = (gates[i] as Transform3D).origin
			s += Vector2(b.x - a.x, b.z - a.z).length()
		var a2: Vector3 = (gates[g - 1] as Transform3D).origin
		var b2: Vector3 = (gates[g] as Transform3D).origin
		var leg := Vector2(b2.x - a2.x, b2.z - a2.z)
		var p: Vector3 = game.car.global_position
		var along := clampf(Vector2(p.x - a2.x, p.z - a2.z).dot(leg.normalized()), 0.0, leg.length())
		s += along
		var total := s - along + leg.length()
		for i in range(g + 1, gates.size()):
			var a3: Vector3 = (gates[i - 1] as Transform3D).origin
			var b3: Vector3 = (gates[i] as Transform3D).origin
			total += Vector2(b3.x - a3.x, b3.z - a3.z).length()
		return [s, total - s]
	_for = null
	return []
