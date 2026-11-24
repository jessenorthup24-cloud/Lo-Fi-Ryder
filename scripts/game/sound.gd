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

# The vehicle sound pack (assets/audio/pack, unlocked at build time; without it the built-in sounds play).
const PACK_DIR := "res://assets/audio/pack/"
# each voice's loops, idle to redline, and the pitch each was recorded at (Hz, measured), then its off-throttle loop
const VOICES := {
	"car": [28.4, 66.1, 113.2, 160.0, 206.8, 131.9],
	"sports_car": [50.1, 121.8, 212.4, 300.0, 393.4, 247.4],
	"muscle_car": [23.3, 29.3, 51.4, 73.4, 95.6, 60.2],
	"truck": [30.0, 48.1, 70.8, 92.7, 116.5, 79.7],
}
const LAYERS := ["idle", "low", "mid", "high", "redline", "decel"]
# a sound the game asks for -> the pack's takes of it (one picked at random each time)
const ALIAS := {
	"bump": ["bump_01", "bump_02", "bump_03"],
	"land": ["jump_land_01", "jump_land_02"],
	"land_hard": ["suspension_bottom_out"],
	"bonk": ["fender_bender_01", "fender_bender_02", "fender_bender_03"],
	"fender": ["fender_bender_01", "fender_bender_02", "fender_bender_03"],
	"crash_wall": ["crash_wall_01", "crash_wall_02", "crash_wall_03", "guardrail_hit"],
	"crash_car": ["crash_car_01", "crash_car_02", "crash_car_03"],
	"crash_heavy": ["crash_heavy_01", "crash_heavy_02"],
	"scrape": ["metal_scrape_01", "metal_scrape_02"],
	"glass": ["windscreen_shatter_01", "windscreen_shatter_02"],
	"headlight": ["headlight_break"],
	"debris": ["debris_01", "debris_02"],
	"hubcap": ["hubcap_roll"],
	"rollover": ["rollover"],
	"knock_soft": ["traffic_cone_hit_01", "traffic_cone_hit_02"],
	"knock_wood": ["plastic_barrier_hit", "fence_crash"],
	"tyre_wall": ["tyre_wall_hit"],
	"horn_hi": ["small_car_horn", "car_horn_short_02"],
	"horn_lo": ["car_horn_short_01", "car_horn_double", "car_horn_long"],
	"horn_truck": ["truck_air_horn_01"],
	"shift": ["car_gear_shift"],
	"shift_sport": ["sports_car_gear_shift"],
	"backfire": ["backfire_01", "backfire_02", "backfire_03", "backfire_04"],
	"blowoff": ["turbo_blow_off_01", "turbo_blow_off_02"],
	"handbrake": ["handbrake_turn_01", "handbrake_turn_02"],
	"chirp": ["skid_short_01", "skid_short_02", "skid_short_03", "skid_short_04"],
	"checkpoint": ["checkpoint"],
	"finish": ["race_finish"],
	"record": ["best_time"],
	"go": ["countdown_go"],
	"medal": ["position_up"],
	"upgrade": ["impact_wrench_01", "impact_wrench_02"],
	"select": ["door_close_01", "door_close_02", "door_close_03"],
	"ignition": ["ignition_key"],
	"start_car": ["car_start"],
	"start_sports_car": ["sports_car_start"],
	"start_muscle_car": ["muscle_car_start"],
	"start_truck": ["truck_start"],
}
# without the pack, what to play instead ("" = nothing)
const FALLBACK := {"land": "", "land_hard": "", "fender": "bump", "crash_wall": "bonk", "crash_car": "bonk", "crash_heavy": "bonk",
	"scrape": "", "glass": "", "headlight": "", "debris": "", "hubcap": "", "rollover": "", "tyre_wall": "bonk", "horn_truck": "horn_lo",
	"shift": "", "shift_sport": "", "backfire": "", "blowoff": "", "handbrake": "", "chirp": "", "checkpoint": "coin", "finish": "mission",
	"go": "boost", "medal": "mission", "ignition": "", "start_car": "", "start_sports_car": "", "start_muscle_car": "", "start_truck": ""}
const LOOP_ALIAS := {"skid_road": "tyre_squeal_loop", "roll_road": "asphalt_roll_loop", "roll_grass": "grass_roll_loop",
	"roll_gravel": "gravel_roll_loop", "roll_snow": "snow_roll_loop", "grind": "guardrail_scrape_loop", "wind": "wind_fast_loop"}

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
var has_pack := false
var voice := "car"
var voice_pitch := 1.0
var freq := 30.0             # engine note (Hz) when the pack is in
var decel: AudioStreamPlayer
var reverse_loop: AudioStreamPlayer
var _last_throttle := 0.0
var turbo := 0

func setup() -> void:
	_bus("Music")
	_bus("SFX")
	music_bus = AudioServer.get_bus_index("Music")
	sfx_bus = AudioServer.get_bus_index("SFX")
	lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(music_bus, lowpass)
	# crashes on top of a screaming engine never clip
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(sfx_bus, lim)
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		pool.append(p)
	music_a = _player("Music")
	music_b = _player("Music")
	music_a.finished.connect(_next_track)
	music_b.finished.connect(_next_track)
	has_pack = ResourceLoader.exists(PACK_DIR + "car_idle_loop.ogg")
	for i in (5 if has_pack else 4):
		eng.append(_player("SFX"))
	decel = _player("SFX")
	reverse_loop = _loop("car_reverse_loop") if has_pack else _player("SFX")
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
	if has_pack and (LOOP_ALIAS.has(n) or n.ends_with("_loop")):
		var ps: AudioStream = _pack(LOOP_ALIAS.get(n, n))
		if ps is AudioStreamOggVorbis:
			ps = ps.duplicate()
			(ps as AudioStreamOggVorbis).loop = true
			return ps
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

func _pack(n: String) -> AudioStream:
	var key := "pk:" + n
	if not streams.has(key):
		var path := PACK_DIR + n + ".ogg"
		streams[key] = load(path) if ResourceLoader.exists(path) else null
	return streams[key]

func _stream(n: String) -> AudioStream:
	if has_pack and ALIAS.has(n):
		var takes: Array = ALIAS[n]
		return _pack(takes[randi() % takes.size()])
	if FALLBACK.has(n):
		n = FALLBACK[n]
		if n == "":
			return null
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
	if has_pack:
		# small engines that sing (the sporty ones) get the sports car; big lazy V8s the muscle car
		voice = {"v8": "muscle_car", "truck": "truck", "putt": "car"}.get(fam, "sports_car" if pitch >= 1.3 else "car")
		voice_pitch = clampf(pitch / (1.32 if voice == "sports_car" else 1.12), 0.9, 1.1) if fam == "small" else clampf(pitch, 0.9, 1.1)
		for i in 5:
			eng[i].stream = _looped("%s_%s_loop" % [voice, LAYERS[i]])
			eng[i].volume_db = -80.0
			if eng[i].stream:
				eng[i].play(randf() * 0.5)
		decel.stream = _looped("%s_decel_loop" % voice)
		decel.volume_db = -80.0
		if decel.stream:
			decel.play(randf() * 0.5)
		freq = VOICES[voice][0]
		return
	for i in 4:
		eng[i].stream = _looped("eng_%s_%d" % [fam, i])
		eng[i].volume_db = -80.0
		if eng[i].stream:
			eng[i].play(randf() * 0.5)
	rpm = FAMILY_RPM[fam][0]

## A gear change.
func shift() -> void:
	if has_pack:
		play("shift_sport" if voice == "sports_car" else "shift", -14.0, voice_pitch, 0.05)

## The engine catching as you set off.
func start_engine() -> void:
	if has_pack:
		play("start_" + voice, -8.0, voice_pitch, 0.02)

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
	if has_pack:
		_pack_engine(dt, v, active, grounded, speed)
	else:
		_synth_engine(dt, v, R, active, grounded, pace, k)
	_rest(dt, v, active, grounded, speed, k)

## The pack's engine: five recorded loops from idle to redline, crossfaded around the engine note and bent
## to match it, an off-throttle loop when you lift, and the reversing whine.
func _pack_engine(dt: float, v: Dictionary, active: bool, grounded: bool, speed: float) -> void:
	var F: Array = VOICES[voice]
	var throttle: float = v.get("throttle", 0.0)
	var target: float = F[0] * (1.0 + 0.02 * sin(_t * 7.0))
	if active and v.has("rpm_k"):
		var rk: float = v["rpm_k"]
		target = lerpf(F[1] * 0.92, F[4], rk) * (1.0 + float(v.get("drift", 0.0)) * 0.04)
		if not grounded:
			target = maxf(target, F[3] * 0.9 * throttle)
		if absf(speed) < 0.6 and throttle < 0.1:
			target = F[0]
	# a hurt engine runs rough: the note lumps about
	var ek := clampf((float(v.get("eng_dmg", 0.0)) - 30.0) / 70.0, 0.0, 1.0)
	if ek > 0.0 and active:
		target *= 1.0 + (sin(_t * 23.0) * 0.6 + sin(_t * 37.0) * 0.4) * 0.04 * ek
	freq = lerpf(freq, target, 1.0 - exp(-dt * (6.0 if target > freq else 3.0)))
	# lifting off at high revs: a pop from the exhaust (and a whoosh with a turbo)
	if active and _last_throttle > 0.6 and throttle < 0.1 and float(v.get("rpm_k", 0.0)) > 0.7:
		if randf() < 0.45:
			play("backfire", -9.0, voice_pitch, 0.08)
		if turbo > 0:
			play("blowoff", -11.0, 1.0, 0.05)
	_last_throttle = throttle
	var off := clampf((absf(speed) - 3.0) / 4.0, 0.0, 1.0) * (1.0 - throttle) if active else 0.0
	var gain := 0.0 if not active and not v.get("idle", true) else (0.55 if active else 0.35)
	if v.get("misfire", false):
		gain *= 0.3                  # (coughing: the engine cuts out for a moment)
	var lo := 0
	while lo < 3 and freq > F[lo + 1]:
		lo += 1
	var t := clampf((freq - F[lo]) / (F[lo + 1] - F[lo]), 0.0, 1.0)
	for i in 5:
		var w := 0.0
		if i == lo:
			w = cos(t * PI * 0.5)
		elif i == lo + 1:
			w = sin(t * PI * 0.5)
		_ease_db(eng[i], w * gain * (1.0 - off * 0.75), dt, 16.0)
		eng[i].pitch_scale = clampf(freq / F[i] * voice_pitch, 0.55, 1.9)
	_ease_db(decel, off * gain * 0.8, dt, 10.0)
	decel.pitch_scale = clampf(freq / F[5] * voice_pitch, 0.55, 1.9)
	var back := clampf(-speed / 4.0, 0.0, 1.0) if active else 0.0
	_ease_db(reverse_loop, back * 0.5, dt, 8.0)
	if reverse_loop.stream:
		reverse_loop.pitch_scale = clampf(0.8 + absf(speed) / 10.0, 0.8, 1.6)

func _synth_engine(dt: float, v: Dictionary, R: Array, active: bool, grounded: bool, pace: float, k: float) -> void:
	# where the RPM wants to be
	var target: float
	if not active:
		target = R[0] * (1.0 + 0.025 * sin(_t * 9.0))
	elif v.get("empty", false):
		target = lerpf(R[0], R[1], clampf(k, 0.0, 1.0))
	elif v.has("rpm_k"):
		# the car's own gearbox says where the needle is
		var rk: float = v["rpm_k"]
		target = lerpf(R[1] * 0.9, R[3] * 1.02, rk) * (1.0 + float(v.get("drift", 0.0)) * 0.05)
		if not grounded:
			target = maxf(target, R[3] * 0.85 * float(v.get("throttle", 0.0)))
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

func _rest(dt: float, v: Dictionary, active: bool, grounded: bool, speed: float, k: float) -> void:
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
	var rush := clampf((absf(speed) - 14.0) / 26.0, 0.0, 1.0) * 0.32 if active and has_pack else 0.0
	_ease_db(wind, maxf(float(v.get("windy", 0.0)) * 0.4, rush), dt, 3.0)
	if has_pack and wind.stream:
		wind.pitch_scale = 0.85 + rush * 0.6
	_ease_db(rain, float(v.get("rainy", 0.0)) * 0.4, dt, 2.0)

func silence_loops() -> void:
	for p in eng + [skid_road, skid_dirt, air, siren, grind, wind, rain, decel, reverse_loop] + rolls.values():
		if p.stream:
			p.volume_db = -80.0

## Hold every loop silent (pause, game over) until unmute().
func mute_loops(on: bool) -> void:
	_silent = on
	if on:
		silence_loops()
