extends Node
## Music playlist, one-shot sounds, and the vehicle mix: a 4-layer engine that follows a simulated RPM,
## tyre noise for the surface under the car, skids, air rush, police siren, wind and rain.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
# The build drops CC0 lo-fi tracks and their tracks.json into MUSIC_DIR (see tools/music/).
const TRACK_LIST := "res://assets/audio/music/tracks.json"
# RPM each engine layer was recorded at (tools/audio/make_vehicle.py)
const FAMILY_RPM := {
	"small": [900.0, 2300.0, 4000.0, 6200.0],
	"truck": [650.0, 1400.0, 2300.0, 3300.0],
	"v8": [750.0, 1900.0, 3400.0, 5400.0],
	"putt": [600.0, 1300.0, 2200.0, 3200.0],
}
const ROLLS := ["road", "grass", "gravel", "wood", "snow"]

var streams := {}
var pool: Array[AudioStreamPlayer] = []
var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var music_on_a := true
var tracks: Array = []
var track_i := 0
var lowpass: AudioEffectLowPassFilter
var muffle := 0.0
var music_vol := 0.75
var sfx_vol := 0.9
var music_bus := 0
var sfx_bus := 0
var credits: Array = []   # [{title, artist, license, page}]

# vehicle
var eng: Array[AudioStreamPlayer] = []
var family := "small"
var car_pitch := 1.0
var rpm := 900.0
var sputter := 0.0
var rolls := {}
var skid_road: AudioStreamPlayer
var skid_dirt: AudioStreamPlayer
var air: AudioStreamPlayer
var siren: AudioStreamPlayer
var grind: AudioStreamPlayer
var wind: AudioStreamPlayer
var rain: AudioStreamPlayer
var _t := 0.0
var _silent := false

func setup() -> void:
	_bus("Music")
	_bus("SFX")
	music_bus = AudioServer.get_bus_index("Music")
	sfx_bus = AudioServer.get_bus_index("SFX")
	lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(music_bus, lowpass)
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		pool.append(p)
	music_a = _player("Music")
	music_b = _player("Music")
	music_a.finished.connect(_next_track)
	music_b.finished.connect(_next_track)
	for i in 4:
		eng.append(_player("SFX"))
	for r in ROLLS:
		rolls[r] = _loop("roll_" + r)
	skid_road = _loop("skid_road")
	skid_dirt = _loop("skid_dirt")
	air = _loop("air_rush")
	siren = _loop("siren")
	grind = _loop("grind")
	wind = _loop("wind")
	rain = _loop("rain")
	set_engine("small", 1.0)
	if FileAccess.file_exists(TRACK_LIST):
		var v = JSON.parse_string(FileAccess.get_file_as_string(TRACK_LIST))
		if v is Dictionary:
			for t in v.get("tracks", []):
				var path := MUSIC_DIR + String(t.get("file", ""))
				if ResourceLoader.exists(path):
					tracks.append(path)
					credits.append(t)
	tracks.shuffle()

## "HoliznaCC0, omfgdude" for the settings screen.
func credit_line() -> String:
	var names := []
	for c in credits:
		if not names.has(c["artist"]):
			names.append(c["artist"])
	return ", ".join(names)

func _bus(n: String) -> void:
	if AudioServer.get_bus_index(n) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, n)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")

func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

func _looped(n: String) -> AudioStream:
	var s = _stream(n)
	if s is AudioStreamWAV:
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s

func _loop(n: String) -> AudioStreamPlayer:
	var p := _player("SFX")
	var s := _looped(n)
	if s:
		p.stream = s
		p.volume_db = -80.0
		p.play()
	return p

func _stream(n: String) -> AudioStream:
	if streams.has(n):
		return streams[n]
	var path := SFX_DIR + n + ".wav"
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	streams[n] = s
	return s

## Switch engine voice for the selected car (family from cars.gd, pitch tweaks small vs big).
func set_engine(fam: String, pitch: float) -> void:
	if not FAMILY_RPM.has(fam):
		fam = "small"
	family = fam
	car_pitch = pitch
	for i in 4:
		eng[i].stream = _looped("eng_%s_%d" % [fam, i])
		eng[i].volume_db = -80.0
		if eng[i].stream:
			eng[i].play(randf() * 0.5)
	rpm = FAMILY_RPM[fam][0]

func horn() -> void:
	play("horn_hi" if family in ["small", "putt"] else "horn_lo", -6.0, car_pitch, 0.02)

func set_volumes(music: float, sfx: float) -> void:
	music_vol = music
	sfx_vol = sfx
	AudioServer.set_bus_volume_db(music_bus, linear_to_db(maxf(music, 0.0001)))
	AudioServer.set_bus_mute(music_bus, music < 0.01)
	AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(maxf(sfx, 0.0001)))
	AudioServer.set_bus_mute(sfx_bus, sfx < 0.01)

func play(n: String, vol_db := 0.0, pitch := 1.0, rand_pitch := 0.06) -> void:
	var s := _stream(n)
	if s == null:
		return
	var p: AudioStreamPlayer = null
	for q in pool:
		if not q.playing:
			p = q
			break
	if p == null:
		p = pool[0]
		pool.push_back(pool.pop_front())
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = maxf(0.1, pitch * (1.0 + randf_range(-rand_pitch, rand_pitch)))
	p.play()

func start_music() -> void:
	if tracks.is_empty() or music_a.playing or music_b.playing:
		return
	_play_track(music_a)

func _play_track(p: AudioStreamPlayer) -> void:
	if tracks.is_empty():
		return
	var s = load(tracks[track_i % tracks.size()])
	track_i += 1
	p.stream = s
	p.volume_db = -3.0
	p.play()

func _next_track() -> void:
	var p := music_b if music_on_a else music_a
	music_on_a = not music_on_a
	_play_track(p)

## Muffle the music on menus and game over (0 = clear, 1 = muffled).
func set_muffle(k: float) -> void:
	muffle = k

## Kick the revs (landing dips them, a boost spikes them).
func rev(mult: float) -> void:
	rpm *= mult

func _ease_db(p: AudioStreamPlayer, target_lin: float, dt: float, rate: float) -> void:
	if p.stream == null:
		return
	var cur := db_to_linear(p.volume_db)
	cur = lerpf(cur, target_lin, 1.0 - exp(-dt * rate))
	p.volume_db = linear_to_db(maxf(cur, 0.00001))

## v: speed, grounded, active, drift (0..1), air_t, boost (0..1), empty (out of fuel), roll (surface),
## windy, rainy, siren (0..1), siren_close (0..1).
func tick(dt: float, v: Dictionary) -> void:
	_t += dt
	var cut := lerpf(20000.0, 900.0, muffle)
	lowpass.cutoff_hz = lerpf(lowpass.cutoff_hz, cut, 1.0 - exp(-dt * 4.0))
	if _silent:
		return
	var R: Array = FAMILY_RPM[family]
	var speed: float = v.get("speed", 0.0)
	var active: bool = v.get("active", false)
	var grounded: bool = v.get("grounded", true)
	var pace: float = v.get("pace", 1.0)
	var k := clampf(speed / (9.0 * pace), 0.0, 2.0)
	# where the RPM wants to be
	var target: float
	if not active:
		target = R[0] * (1.0 + 0.025 * sin(_t * 9.0))
	elif v.get("empty", false):
		target = lerpf(R[0], R[1], clampf(k, 0.0, 1.0))
	elif not grounded:
		target = R[3] * 0.9
	else:
		target = lerpf(R[1], R[2], 0.62 * minf(k, 1.0)) + maxf(0.0, k - 1.0) * (R[3] - R[2]) * 1.2
		target *= 1.0 + float(v.get("drift", 0.0)) * 0.09
		target += float(v.get("boost", 0.0)) * (R[3] - R[2]) * 0.55
		target *= 1.0 + (pace - 1.0) * 0.14
	rpm = lerpf(rpm, target, 1.0 - exp(-dt * (5.0 if target > rpm else 2.6)))
	rpm = clampf(rpm, R[0] * 0.8, R[3] * 1.15)
	# crossfade the two layers around the current RPM and bend their pitch to match
	var load_gain := 0.55 if not active else (0.85 if grounded else 0.7)
	if v.get("empty", false):
		sputter -= dt
		if sputter <= 0.0:
			sputter = randf_range(0.08, 0.35)
		load_gain *= 0.25 if sputter < 0.06 else 0.8
	var lo := 0
	while lo < 2 and rpm > R[lo + 1]:
		lo += 1
	var t := clampf((rpm - R[lo]) / (R[lo + 1] - R[lo]), 0.0, 1.0)
	for i in 4:
		var w := 0.0
		if i == lo:
			w = cos(t * PI * 0.5)
		elif i == lo + 1:
			w = sin(t * PI * 0.5)
		_ease_db(eng[i], w * load_gain * 0.62, dt, 18.0)
		eng[i].pitch_scale = clampf(rpm / R[i] * car_pitch, 0.45, 2.2)
	# tyres: only the surface we're on rolls
	var roll: String = v.get("roll", "grass")
	var rv := clampf(k, 0.0, 1.3) * (1.0 if grounded and active else 0.0)
	for r in ROLLS:
		var p: AudioStreamPlayer = rolls[r]
		_ease_db(p, rv * (0.5 if r != "wood" else 0.62) if r == roll else 0.0, dt, 10.0)
		if p.stream:
			p.pitch_scale = clampf((0.55 + 0.5 * k) if r != "wood" else maxf(0.45, k * 0.95), 0.4, 1.8)
	var drift: float = v.get("drift", 0.0) if grounded and active else 0.0
	var paved := roll in ["road", "wood"]
	_ease_db(skid_road, drift * 0.55 if paved else 0.0, dt, 14.0)
	_ease_db(skid_dirt, drift * 0.6 if not paved else 0.0, dt, 14.0)
	if skid_road.stream:
		skid_road.pitch_scale = 0.9 + drift * 0.2
	var air_t: float = v.get("air_t", 0.0)
	_ease_db(air, clampf(air_t * 2.0, 0.0, 1.0) * clampf(k, 0.0, 1.2) * 0.5 if not grounded and active else 0.0, dt, 6.0)
	var gv: float = 1.0 if v.get("grind", false) else 0.0
	_ease_db(grind, gv * 0.55, dt, 18.0)
	if grind.stream:
		grind.pitch_scale = 0.85 + speed / 30.0
	var sv: float = v.get("siren", 0.0)
	_ease_db(siren, sv * (0.35 + 0.45 * float(v.get("siren_close", 0.0))), dt, 5.0)
	if siren.stream:
		siren.pitch_scale = 1.0 + float(v.get("siren_close", 0.0)) * 0.04
	_ease_db(wind, float(v.get("windy", 0.0)) * 0.4, dt, 3.0)
	_ease_db(rain, float(v.get("rainy", 0.0)) * 0.4, dt, 2.0)

func silence_loops() -> void:
	for p in eng + [skid_road, skid_dirt, air, siren, grind, wind, rain] + rolls.values():
		if p.stream:
			p.volume_db = -80.0

## Hold every loop silent (pause, game over) until unmute().
func mute_loops(on: bool) -> void:
	_silent = on
	if on:
		silence_loops()
