extends SceneTree
## Measures shadow shimmer: builds the island with the game's sky and sun, holds the camera still on a street
## while the day runs at its real speed, and counts the pixels that change from one frame to the next.
##   xvfb-run -a godot --path . -s res://tools/look/shadow_flicker.gd -- [view] [frames] [save_prefix]
## Add `frozen` after the prefix to hold the sun still for a baseline.
## Views: street (Main Street), town (over the rooftops), suburbs.

const PAL := preload("res://scripts/core/palette.gd")
const Island := preload("res://scripts/game/island.gd")
const Atmos := preload("res://scripts/game/atmos.gd")

const VIEWS := {
	"street": [Vector3(-235, 3.2, 61), Vector3(-150, 3, 60), 65.0],
	"town": [Vector3(-60, 30, 120), Vector3(-110, 5, 30), 55.0],
	"suburbs": [Vector3(-160, 14, -60), Vector3(-200, 2, -130), 60.0],
}

var atmos: Node
var cam: Camera3D
var frames := 0
var want := 40
var prev: Image
var changed: Array = []
var prefix := ""

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var view: String = a[0] if a.size() > 0 else "street"
	if a.size() > 1:
		want = int(a[1])
	if a.size() > 2:
		prefix = a[2]
	var toon := ShaderMaterial.new()
	toon.shader = load("res://shaders/toon.gdshader")
	toon.set_shader_parameter("palette", PAL.make_texture())
	atmos = Atmos.new()
	get_root().add_child(atmos)
	atmos.setup(get_root(), toon)
	atmos.hour = 15.5
	var isl: Node3D = Island.new()
	get_root().add_child(isl)
	isl.build(toon, 1)
	atmos.add_material(isl.road_mat)
	cam = Camera3D.new()
	cam.far = 2500.0
	cam.near = 0.3
	cam.cull_mask = 0xFFFFF & ~Island.MAP_LAYER
	get_root().add_child(cam)
	cam.make_current()
	var d: Array = VIEWS[view]
	cam.fov = d[2]
	cam.look_at_from_position(d[0], d[1], Vector3.UP)
	if a.size() > 3 and a[3] == "frozen":
		atmos.running = false         # (the sun held still: what's left is the sea and the swaying trees)

func _process(_dt: float) -> bool:
	frames += 1
	atmos.tick(1.0 / 60.0)
	if frames < 10:
		return false
	var img := get_root().get_texture().get_image()
	if prefix != "" and frames in [12, 13]:
		img.save_png("%s_%d.png" % [prefix, frames])
	if prev:
		var n := 0
		var w := img.get_width()
		var h := img.get_height()
		for y in range(0, h, 2):
			for x in range(0, w, 2):
				var c1 := img.get_pixel(x, y)
				var c2 := prev.get_pixel(x, y)
				if absf(c1.r - c2.r) + absf(c1.g - c2.g) + absf(c1.b - c2.b) > 0.12:
					n += 1
		changed.append(n)
	prev = img
	if changed.size() >= want:
		var tot := 0
		var mx := 0
		var nz := 0
		for v in changed:
			tot += v
			mx = maxi(mx, v)
			if v > 0:
				nz += 1
		print("FLICKER frames %d: mean %.1f px changed per frame, max %d, frames with any change %d" % [changed.size(), float(tot) / changed.size(), mx, nz])
		return true
	return false
