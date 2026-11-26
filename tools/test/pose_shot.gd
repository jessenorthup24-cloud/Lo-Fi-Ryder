extends SceneTree
## A character on its own, posed, shot from a few sides (no world): for checking how guns sit in the hands.
## godot --path . --resolution 900x900 -s tools/test/pose_shot.gd -- gun=rifle aim=1 crouch=0 move=0,0 out=/tmp/x
const Avatar := preload("res://scripts/game/avatar.gd")
const Weapons := preload("res://scripts/game/weapons.gd")
const PAL := preload("res://scripts/core/palette.gd")
var av: Node3D
var cam: Camera3D
var f := 0
var args := {}
var shots := [[0.0, "back"], [PI * 0.5, "side"], [PI * 0.75, "front3q"], [-PI * 0.3, "ots"]]
func _init() -> void:
	for a in OS.get_cmdline_user_args():
		args[a.get_slice("=", 0)] = a.get_slice("=", 1)
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	root3.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	fl.mesh = pm
	root3.add_child(fl)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon.gdshader")
	mat.set_shader_parameter("palette", PAL.make_texture())
	av = Avatar.new()
	root3.add_child(av)
	av.setup(String(args.get("who", "male_casual1")), "", mat)
	var g := String(args.get("gun", ""))
	if g != "":
		var w := Weapons.by_id(g)
		if args.has("preset"):
			w = Weapons.with_build(w, Weapons.preset_build(w, String(args["preset"])))
		av.hold(w, mat)
	av.crouch = String(args.get("crouch", "0")) == "1"
	cam = Camera3D.new()
	cam.fov = 40
	root3.add_child(cam)

func _process(dt: float) -> bool:
	f += 1
	var mv := String(args.get("move", "0,0")).split(",")
	var aiming: bool = args.get("aim", "0") == "1"
	if aiming:
		av.aim_at(Vector3(0, 1.45, 12.0), true, dt)
		av.rotation.y = float(args.get("blade", "0"))
		if float(mv[0]) == 0.0 and float(mv[1]) == 0.0:
			av.play("holding-both", 1.0, 0.2)
	if args.has("clip"):
		av.play(String(args["clip"]))
	else:
		av.locomote(Vector2(float(mv[0]), float(mv[1])))
	if args.has("wounds") and f == 30:
		# (shot from behind the camera's first view: the chest, the arm, the head, a leg)
		for pt in [Vector3(0.05, 1.3, 0.2), Vector3(-0.2, 1.4, 0.15), Vector3(0.0, 1.65, 0.1), Vector3(0.1, 0.7, 0.1), Vector3(-0.08, 1.15, 0.2)]:
			av.wound(pt, Vector3(0, 0, -1))
	if args.has("hitnow") and f == 38:
		av.hit(Vector3(0, 1.65, 0.1), Vector3(0, 0, -1), 1.4)
	var start := 40
	var k := (f - start) / 6
	if f >= start and (f - start) % 6 == 0 and k < shots.size():
		pass
	if f >= start and (f - start) % 6 == 5 and k < shots.size():
		var img := get_root().get_texture().get_image()
		img.save_png("%s_%s.png" % [String(args.get("out", "/tmp/pose")), shots[k][1]])
	if f >= start and k < shots.size():
		var a: float = shots[k][0]
		var d := 2.6 if shots[k][1] != "ots" else 2.2
		var c := Vector3(0, 1.25, 0)
		if shots[k][1] == "ots":
			cam.position = Vector3(-0.6, 1.7, -2.2)
			cam.look_at(Vector3(-0.3, 1.45, 4.0))
		else:
			cam.position = c + Vector3(sin(a), 0.15, -cos(a)) * d
			cam.look_at(c)
	return f > start + shots.size() * 6 + 2
