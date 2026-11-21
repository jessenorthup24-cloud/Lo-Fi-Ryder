extends Node
## Music playlist, one-shot sounds, and the engine / drift / weather loops.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const TRACKS := ["sunday_morning.ogg", "golden_hour.ogg", "window_seat.ogg", "night_drive.ogg", "rain_on_the_roof.ogg"]

var streams := {}
var pool: Array[AudioStreamPlayer] = []
var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var music_on_a := true
var tracks: Array = []
var track_i := 0
var engine: AudioStreamPlayer
var drift: AudioStreamPlayer
var wind: AudioStreamPlayer
var rain: AudioStreamPlayer
var lowpass: AudioEffectLowPassFilter
var muffle := 0.0
var music_vol := 0.75
var sfx_vol := 0.9
var music_bus := 0
var sfx_bus := 0
var _fade := 0.0

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
	engine = _loop("engine")
	drift = _loop("drift")
	wind = _loop("wind")
	rain = _loop("rain")
	for t in TRACKS:
		if ResourceLoader.exists(MUSIC_DIR + t):
			tracks.append(MUSIC_DIR + t)
	tracks.shuffle()

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

func _loop(n: String) -> AudioStreamPlayer:
	var p := _player("SFX")
	var s = _stream(n)
	if s:
		if s is AudioStreamWAV:
			s = s.duplicate()
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
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

func tick(dt: float, car_speed: float, steer: float, grounded: bool, running: bool, drift_amt: float, windy: float, rainy: float, low_fuel: bool) -> void:
	var cut := lerpf(20000.0, 900.0, muffle)
	lowpass.cutoff_hz = lerpf(lowpass.cutoff_hz, cut, 1.0 - exp(-dt * 4.0))
	if engine.stream:
		var target := -9.0 if running else -18.0
		if not grounded:
			target -= 6.0
		if car_speed < 0.5 and running:
			target = -24.0
		engine.volume_db = lerpf(engine.volume_db, target, 1.0 - exp(-dt * 6.0))
		var pitch := 0.8 + car_speed / 9.0 * 0.45 + absf(steer) * 0.06 + (0.25 if not grounded else 0.0)
		if low_fuel:
			pitch *= 0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.02)
		engine.pitch_scale = lerpf(engine.pitch_scale, maxf(0.5, pitch), 1.0 - exp(-dt * 8.0))
	if drift.stream:
		drift.volume_db = lerpf(drift.volume_db, linear_to_db(maxf(drift_amt, 0.0001)) - 6.0, 1.0 - exp(-dt * 12.0))
	if wind.stream:
		wind.volume_db = lerpf(wind.volume_db, linear_to_db(maxf(windy, 0.0001)) - 8.0, 1.0 - exp(-dt * 3.0))
	if rain.stream:
		rain.volume_db = lerpf(rain.volume_db, linear_to_db(maxf(rainy, 0.0001)) - 8.0, 1.0 - exp(-dt * 2.0))

func silence_loops() -> void:
	for p in [engine, drift, wind, rain]:
		if p.stream:
			p.volume_db = -80.0
