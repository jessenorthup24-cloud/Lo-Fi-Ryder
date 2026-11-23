extends SceneTree
## Prints ground heights on a grid: godot --headless -s res://tools/test/probe.gd -- x0,z0,x1,z1,step
const Island := preload("res://scripts/game/island.gd")
func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()[0].split(",")
	var isl: Node3D = Island.new()
	get_root().add_child(isl)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon.gdshader")
	isl.build(mat, 2)
	var x0 := float(a[0]); var z0 := float(a[1]); var x1 := float(a[2]); var z1 := float(a[3]); var st := float(a[4])
	var hdr := "      "
	var x := x0
	while x <= x1:
		hdr += "%6d" % int(x)
		x += st
	print(hdr)
	var z := z0
	while z <= z1:
		var line := "%6d" % int(z)
		x = x0
		while x <= x1:
			var h: float = isl.height_at(x, z)
			line += "%6s" % ("~" if h < -0.3 else ("%.1f" % h))
			x += st
		print(line)
		z += st
	quit()
