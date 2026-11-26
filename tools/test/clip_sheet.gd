extends SceneTree
## A contact sheet of a clip: the character frozen at n moments through it, seen from the front-right,
## side by side in one picture (for timing hits and checking poses).
##   xvfb-run godot --path . --resolution 1500x300 -s tools/test/clip_sheet.gd -- clip=fight_cross_punch n=6 out=/tmp/x.png

const Avatar := preload("res://scripts/game/avatar.gd")
var args := {}
var av: Node3D
var cam: Camera3D
var f := 0
var k := 0
var n := 6
var shots: Array = []
var length := 1.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		args[a.get_slice("=", 0)] = a.get_slice("=", 1)
	n = int(args.get("n", "6"))
	var root3 := Node3D.new()
	root.add_child(root3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8a9bb0")
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	root3.add_child(sun)
	av = Avatar.new()
	root3.add_child(av)
	av.setup(String(args.get("who", "male_casual1")), "", null)
	cam = Camera3D.new()
	cam.fov = 40
	root3.add_child(cam)
	var yaw := float(args.get("yaw", "40"))
	var a := deg_to_rad(yaw)
	cam.look_at_from_position(Vector3(sin(a) * 3.6, 1.2, cos(a) * 3.6), Vector3(0, 0.95, 0))

func _process(_dt: float) -> bool:
	f += 1
	var clip := String(args.get("clip", "fight_cross_punch"))
	if f == 10:
		length = av.anim.get_animation(clip).length
	if f >= 10 and k < n:
		var t := length * (float(k) + 0.5) / float(n) if not args.has("t0") else float(args["t0"]) + float(args.get("dt", "0.1")) * k
		if f % 6 == 4:
			av._act_in(clip, 0.01, t, 0.0)
			av.lock_t = 99.0
		if f % 6 == 3 and f > 12:
			var img := root.get_texture().get_image()
			shots.append([img, t])
			k += 1
	if k >= n:
		var w: int = shots[0][0].get_width()
		var h: int = shots[0][0].get_height()
		var out := Image.create(w * n, h, false, Image.FORMAT_RGB8)
		for i in n:
			var im: Image = shots[i][0]
			im.convert(Image.FORMAT_RGB8)
			out.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
		out.save_png(String(args.get("out", "/tmp/sheet.png")))
		print("SHEET ", ", ".join(shots.map(func(s): return "%.2f" % s[1])))
		return true
	return false
