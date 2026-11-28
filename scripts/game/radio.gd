extends Node
## The radio. Stations, each its own kind of music, each playing all the time whether you're listening or
## not: tune in and you land wherever that station's got to (mid-song, like a real one). Turning the dial
## crackles, then the station's little three-note ident, then the music. A card says what's on when you
## tune in and when a new song starts. Out of the car it's quieter (the car's radio, across the street).
## The build drops the music in (tools/music: each source says its station); a station with nothing in it
## isn't on the dial.

const K := preload("res://scripts/ui/kit.gd")

const STATIONS := [
	{"id": "neon", "name": "Neon 88", "freq": "88.8", "tag": "Synthwave", "col": Color("ff5ccf"), "key": 174.6, "motif": [0, 3, 7, 10]},
	{"id": "lofi", "name": "Lo-Fi FM", "freq": "89.1", "tag": "Lo-fi beats", "col": Color("ffb36b"), "key": 220.0, "motif": [0, 4, 7]},
	{"id": "beats", "name": "Boom Bap 92", "freq": "92.5", "tag": "Hip-hop beats", "col": Color("c9a0ff"), "key": 146.8, "motif": [0, 3, 5]},
	{"id": "chill", "name": "Drift Chill", "freq": "94.3", "tag": "Chill and acoustic", "col": Color("8fd9c8"), "key": 196.0, "motif": [0, 7, 12]},
	{"id": "punk", "name": "Pixel Punk", "freq": "97.7", "tag": "Chiptune pop-punk", "col": Color("7be36b"), "key": 261.6, "motif": [0, 4, 7, 12]},
	{"id": "jazz", "name": "Smooth 98", "freq": "98.1", "tag": "Jazz and blues", "col": Color("e0b25c"), "key": 233.1, "motif": [0, 4, 7, 11]},
	{"id": "rock", "name": "Redline Rock", "freq": "101.5", "tag": "Rock", "col": Color("ff5a4a"), "key": 164.8, "motif": [0, 5, 7]},
	{"id": "funk", "name": "Groove Line", "freq": "104.7", "tag": "Funk", "col": Color("ffd34d"), "key": 207.7, "motif": [0, 3, 5, 7]},
	{"id": "pulse", "name": "Pulse 106", "freq": "106.2", "tag": "Electronic and drum & bass", "col": Color("5cc8ff"), "key": 185.0, "motif": [0, 7, 10, 12]},
	{"id": "epic", "name": "Big Screen", "freq": "107.9", "tag": "Cinematic", "col": Color("b8c4ff"), "key": 130.8, "motif": [0, 7, 12, 19]},
]
const OFF := "off"
const ON_FOOT_DB := -9.0

var game: Node
var lists := {}                 # station id -> [{path, title, artist, seconds}], in its running order
var dial: Array = []            # the stations with music in them, by frequency, then "off"
var cur := OFF
var player: AudioStreamPlayer
var fx: AudioStreamPlayer       # the crackle and the ident
var _idx := -1                  # which song of the station's list is on
var _start_t := -1.0            # tuning: the music starts when this runs out
var _start_from := 0.0
var _idents := {}
var _static: AudioStreamWAV
var card: Control
var _card_t := 0.0
var _c_top: Label
var _c_title: Label
var _c_by: Label
var _c_bar: ColorRect
var on_foot := false

func setup(g: Node) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	player.bus = "Music"
	add_child(player)
	player.finished.connect(_song_done)
	fx = AudioStreamPlayer.new()
	fx.bus = "Music"
	add_child(fx)
	_static = _make_static()
	# the songs, by station (the lo-fi ones from before stations were a thing: Lo-Fi FM)
	for c in game.sound.credits:
		var st := String(c.get("station", "lofi"))
		if not lists.has(st):
			lists[st] = []
		(lists[st] as Array).append({"path": "res://assets/audio/music/" + String(c["file"]), "title": String(c.get("title", "")),
			"artist": String(c.get("artist", "")), "seconds": maxf(float(c.get("seconds", 180.0)), 30.0)})
	for st in lists:
		# each station's running order: shuffled, but the same every time (it's a station, not a playlist)
		var l: Array = lists[st]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(st)
		for i in range(l.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = l[i]
			l[i] = l[j]
			l[j] = tmp
	for s in STATIONS:
		if lists.has(s["id"]):
			dial.append(s["id"])
	dial.append(OFF)
	_build_card()

static func station(id: String) -> Dictionary:
	for s in STATIONS:
		if s["id"] == id:
			return s
	return {}

## On at the start: the station you had on last time (or Lo-Fi FM), no crackle.
func start() -> void:
	var want := String(game.save.data["settings"].get("radio", "lofi"))
	if not dial.has(want):
		want = dial[0]
	tune(want, true)

## The next station along the dial (and off, after the last).
func next() -> void:
	var i := dial.find(cur)
	tune(dial[(i + 1) % dial.size()])

func tune(id: String, quiet := false) -> void:
	if not dial.has(id):
		return
	cur = id
	game.save.data["settings"]["radio"] = id
	player.stop()
	_start_t = -1.0
	if id == OFF:
		if not quiet:
			fx.stream = _static
			fx.volume_db = -14.0
			fx.play()
			_show("RADIO", "Off", "", Color(0.6, 0.6, 0.6))
		return
	var at := _live(id)
	_idx = int(at[0])
	_start_from = float(at[1])
	if quiet:
		_start_t = 0.0
	else:
		# the dial: a crackle, then the station's ident, then the music
		fx.stream = _static
		fx.volume_db = -12.0
		fx.play()
		_start_t = 0.95
		get_tree().create_timer(0.3, true).timeout.connect(func():
			if cur == id:
				fx.stream = _ident(id)
				fx.volume_db = -6.0
				fx.play())
	var s := station(id)
	var song: Dictionary = (lists[id] as Array)[_idx]
	_show("%s  %s" % [s["freq"], String(s["name"]).to_upper()], song["title"], "%s · %s" % [song["artist"], s["tag"]], s["col"])

## Where the station's got to: [song, seconds into it]. It's been playing all along (by the clock).
func _live(id: String) -> Array:
	var l: Array = lists[id]
	var total := 0.0
	for e in l:
		total += float(e["seconds"])
	var t := fposmod(Time.get_unix_time_from_system() + float(hash(id) % 100000), total)
	for i in l.size():
		var d := float(l[i]["seconds"])
		if t < d:
			return [i, clampf(t, 0.0, maxf(d - 8.0, 0.0))]
		t -= d
	return [0, 0.0]

func _play_now() -> void:
	if cur == OFF or not lists.has(cur):
		return
	var song: Dictionary = (lists[cur] as Array)[_idx]
	var stream = load(String(song["path"]))
	if stream == null:
		return
	player.stream = stream
	player.play(_start_from)

func _song_done() -> void:
	if cur == OFF or not lists.has(cur):
		return
	_idx = (_idx + 1) % (lists[cur] as Array).size()
	_start_from = 0.0
	_play_now()
	var s := station(cur)
	var song: Dictionary = (lists[cur] as Array)[_idx]
	_show("%s  %s" % [s["freq"], String(s["name"]).to_upper()], song["title"], "%s · %s" % [song["artist"], s["tag"]], s["col"])

func tick(dt: float) -> void:
	if _start_t >= 0.0:
		_start_t -= dt
		if _start_t < 0.0:
			_play_now()
	# out of the car it's the car's radio, over there: quieter
	var want := ON_FOOT_DB if on_foot else 0.0
	player.volume_db = move_toward(player.volume_db, want - 2.0, dt * 12.0)
	if card:
		_card_t -= dt
		card.modulate.a = clampf(minf(_card_t, 4.0 - _card_t) * 3.0, 0.0, 1.0) if _card_t > 0.0 else 0.0
		var cine := float(game.ui.get("_cine_t")) if game.ui.get("_cine_t") != null else 0.0
		card.visible = _card_t > 0.0 and cine <= 0.0

# ---------------------------------------------------------------- the card

func _build_card() -> void:
	if game.ui == null or game.ui.get("hud") == null:
		return
	card = K.card(K.PAPER, 16)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.position = Vector2(22, 182)          # (under the money and the story's next step)
	card.custom_minimum_size = Vector2(300, 0)
	card.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	_c_bar = ColorRect.new()
	_c_bar.custom_minimum_size = Vector2(6, 0)
	row.add_child(_c_bar)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	_c_top = K.label("", 13, K.INK_SOFT, 700)
	_c_title = K.label("", 19, K.INK, 700)
	_c_by = K.label("", 14, K.INK_SOFT, 600)
	for l in [_c_top, _c_title, _c_by]:
		col.add_child(l)
	game.ui.hud.add_child(card)

func _show(top: String, title: String, by: String, c: Color) -> void:
	if card == null:
		return
	_c_top.text = top
	_c_top.add_theme_color_override("font_color", c.darkened(0.25))
	_c_title.text = title
	_c_by.text = by
	_c_by.visible = by != ""
	_c_bar.color = c
	_card_t = 4.0

# ---------------------------------------------------------------- sounds made here

const RATE := 22050

## Tuning crackle: noise, softened, with a hiss of a whistle through it.
func _make_static() -> AudioStreamWAV:
	var n := int(RATE * 0.38)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var k := float(i) / n
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.35)
		var whistle := sin(TAU * (1800.0 - 1300.0 * k) * float(i) / RATE) * 0.12
		var env := minf(k * 12.0, 1.0) * (1.0 - k)
		data.encode_s16(i * 2, int(clampf((lp * 0.8 + whistle) * env, -1.0, 1.0) * 26000.0))
	return _wav(data)

## The station's ident: its notes, one after another, then together.
func _ident(id: String) -> AudioStreamWAV:
	if _idents.has(id):
		return _idents[id]
	var s := station(id)
	var notes: Array = s["motif"]
	var root: float = s["key"]
	var step := 0.14
	var tail := 0.55
	var n := int(RATE * (step * notes.size() + tail))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for j in notes.size():
			var t0 := step * j
			if t < t0:
				continue
			var f := root * pow(2.0, float(notes[j]) / 12.0) * 2.0
			var lt := t - t0
			# a soft electric-piano sort of note: a sine and its octave, struck and dying away
			var env := exp(-lt * (7.0 if j < notes.size() - 1 else 3.2)) * minf(lt * 200.0, 1.0)
			v += (sin(TAU * f * lt) + 0.3 * sin(TAU * f * 2.0 * lt) + 0.1 * sin(TAU * f * 3.0 * lt)) * env
		v *= 0.32
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var w := _wav(data)
	_idents[id] = w
	return w

static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
