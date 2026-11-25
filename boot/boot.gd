extends Control
## Boot: install the APK once, then the game updates itself over the air.
##
## On launch this asks GitHub for the newest content pack (manifest.json on the repo's `ota` branch).
## If it's newer than what's on the phone, it downloads it (everything but the engine: scripts, scenes,
## models, audio) to user://, checks its hash, loads it over the built-in content and starts the game.
## No network or nothing new: it starts with the last downloaded pack, or the APK's own content.
##
## Only a new Godot version or new Android permissions need a fresh APK.
## This script can't update the copy of itself that's already installed, so it stays small and has
## no dependencies on game code. The game has no autoloads and no class_names on purpose, so a pack
## can replace any script before it's first loaded.

const UPDATE_BASE := "https://raw.githubusercontent.com/jessenorthup24-cloud/Lo-Fi-Ryder/ota"
const PACK_PATH := "user://content.pck"
const STATE_PATH := "user://content.json"
const PENDING_PATH := "user://content_pending"
const MAIN := "res://scenes/main.tscn"

var _label: Label
var _bar: ProgressBar
var _skip: Button
var _http: HTTPRequest
var _manifest: Dictionary = {}
var _started := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.043, 0.039, 0.067)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var font: Font = null
	var thin: FontVariation = null
	if ResourceLoader.exists("res://assets/fonts/Fredoka.ttf"):
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/Fredoka.ttf")
		fv.variation_opentype = {"wght": 400}
		font = fv
		thin = FontVariation.new()
		thin.base_font = fv.base_font
		thin.variation_opentype = {"wght": 300}
		thin.spacing_glyph = 9
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560, 0)
	box.position = Vector2(-280, -90)
	box.add_theme_constant_override("separation", 18)
	add_child(box)
	# the wordmark, as the game writes it (kit.gd wordmark): LO-FI in pink, DRYFTER in white, thin and spaced
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	for w in [["LO-FI", Color("ff4f8b")], ["DRYFTER", Color("f2f0f7")]]:
		var title := Label.new()
		title.text = w[0]
		title.add_theme_font_size_override("font_size", 56)
		title.add_theme_color_override("font_color", w[1])
		if thin: title.add_theme_font_override("font", thin)
		row.add_child(title)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(0.65, 0.64, 0.71))
	if font: _label.add_theme_font_override("font", font)
	box.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(560, 22)
	_bar.show_percentage = false
	_bar.visible = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("ff4f8b")
	fill.set_corner_radius_all(11)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	back.set_corner_radius_all(11)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	box.add_child(_bar)
	_skip = Button.new()
	_skip.text = "Play now, update next time"
	_skip.visible = false
	_skip.flat = true
	_skip.add_theme_font_size_override("font_size", 24)
	_skip.add_theme_color_override("font_color", Color(0.66, 0.64, 0.61))
	if font: _skip.add_theme_font_override("font", font)
	_skip.pressed.connect(_on_skip)
	box.add_child(_skip)
	_http = HTTPRequest.new()
	_http.timeout = 6.0
	_http.max_redirects = 8
	add_child(_http)

	# A pack that crashed the game last launch is thrown away.
	if FileAccess.file_exists(PENDING_PATH):
		_remove(PACK_PATH)
		_remove(STATE_PATH)
		_remove(PENDING_PATH)

	var args := OS.get_cmdline_user_args()
	var forced := Array(args).any(func(a): return String(a).begins_with("--update-base="))
	if "--no-update" in args or OS.has_feature("editor") or (OS.get_name() != "Android" and not forced):
		_start(false)
		return
	_say("Checking for updates…")
	_http.request_completed.connect(_on_manifest, CONNECT_ONE_SHOT)
	if _http.request(_url("manifest.json") + "?t=%d" % int(Time.get_unix_time_from_system())) != OK:
		_start(true)

func _url(file: String) -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--update-base="):
			return String(a).substr(14) + "/" + file
	return UPDATE_BASE + "/" + file

func _say(t: String) -> void:
	_label.text = t

func _remove(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}

## The content build this phone runs now: the downloaded pack's, or the APK's own.
func _installed_build() -> int:
	var b := int(_read_json("res://version.json").get("build", 0))
	var got := _read_json(STATE_PATH)
	if FileAccess.file_exists(PACK_PATH) and int(got.get("build", 0)) > b:
		b = int(got.get("build", 0))
	return b

func _engine_id() -> int:
	var v := Engine.get_version_info()
	return int(v["major"]) * 10000 + int(v["minor"]) * 100 + int(v["patch"])

func _on_manifest(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_start(true)
		return
	var m = JSON.parse_string(body.get_string_from_utf8())
	if not (m is Dictionary) or int(m.get("build", 0)) <= _installed_build() or int(m.get("engine", 0)) != _engine_id():
		_start(true)
		return
	_manifest = m
	_say("Downloading update %s (%.1f MB)…" % [String(m.get("label", "")), float(m.get("size", 0)) / 1048576.0])
	_bar.visible = true
	_skip.visible = true
	_bar.max_value = maxf(1.0, float(m.get("size", 1)))
	_http.timeout = 0.0   # no time limit on the pack itself; the player can skip instead
	_http.download_file = PACK_PATH + ".part"
	_http.request_completed.connect(_on_pack, CONNECT_ONE_SHOT)
	if _http.request(_url(String(m["pack"]))) != OK:
		_start(true)

func _process(_dt: float) -> void:
	if _bar and _bar.visible and _http:
		_bar.value = _http.get_downloaded_bytes()

func _on_skip() -> void:
	_http.cancel_request()
	_remove(PACK_PATH + ".part")
	_start(true)

func _on_pack(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if _started:
		return
	var part := PACK_PATH + ".part"
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200 and FileAccess.file_exists(part)
	if ok and _manifest.has("sha256"):
		ok = FileAccess.get_sha256(part) == String(_manifest["sha256"])
	if not ok:
		_remove(part)
		_start(true)
		return
	_remove(PACK_PATH)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(part), ProjectSettings.globalize_path(PACK_PATH))
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"build": int(_manifest["build"]), "label": _manifest.get("label", "")}))
	f.close()
	_start(true)

func _start(use_pack: bool) -> void:
	if _started:
		return
	_started = true
	_bar.visible = false
	_skip.visible = false
	var own := int(_read_json("res://version.json").get("build", 0))
	if FileAccess.file_exists(PACK_PATH):
		if int(_read_json(STATE_PATH).get("build", 0)) <= own:
			_remove(PACK_PATH)   # a newer APK has replaced it
		elif use_pack:
			var p := FileAccess.open(PENDING_PATH, FileAccess.WRITE)   # main.gd deletes this once it runs
			p.store_string("1")
			p.close()
			ProjectSettings.load_resource_pack(PACK_PATH, true)
	var v := _read_json("res://version.json")
	_say("Starting · %s" % String(v.get("label", "dev")))
	print("Lo-Fi Dryfter boot: content build ", int(v.get("build", 0)), " ", v.get("label", ""))
	await get_tree().process_frame
	get_tree().change_scene_to_file(MAIN)
