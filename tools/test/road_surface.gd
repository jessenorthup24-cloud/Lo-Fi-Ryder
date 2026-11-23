extends SceneTree
## Checks every road surface against the ground: where the ground pokes up through the asphalt, where the
## asphalt floats above the ground, and how far apart the roads' heights are where they meet.
##   godot --headless --path . -s res://tools/test/road_surface.gd
const Island := preload("res://scripts/game/island.gd")
func _init() -> void:
	var isl: Node3D = Island.new()
	get_root().add_child(isl)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon.gdshader")
	isl.build(mat, 2)
	var pokes := []
	var floats := []
	for r in isl.roads:
		var pts: PackedVector2Array = r["pts"]
		var ys: PackedFloat32Array = r["y"]
		var hw: float = float(r["w"]) * 0.5
		var n := pts.size()
		for k in n:
			var t: Vector2 = isl._tangent(pts, k, r["closed"])
			var nrm := Vector2(-t.y, t.x)
			var offs := [-hw, -hw * 0.5, 0.0, hw * 0.5, hw]
			if r["walk"]:
				offs += [-hw - 3.0, hw + 3.0]
			for o in offs:
				var q: Vector2 = pts[k] + nrm * o
				var top: float = ys[k] + isl.ROAD_LIFT + (0.04 if absf(o) > hw + 0.1 else 0.0)
				var g: float = isl.height_at(q.x, q.y)
				if g > top + 0.02:
					pokes.append([g - top, r["name"], q])
				elif top - g > 0.3:
					floats.append([top - g, r["name"], q])
	pokes.sort_custom(func(a, b): return a[0] > b[0])
	floats.sort_custom(func(a, b): return a[0] > b[0])
	print("ground through the road: %d spots" % pokes.size())
	for p in pokes.slice(0, 12):
		print("  %.2f m  %s (%.0f, %.0f)" % [p[0], p[1], p[2].x, p[2].y])
	print("road floating: %d spots" % floats.size())
	for p in floats.slice(0, 12):
		print("  %.2f m  %s (%.0f, %.0f)" % [p[0], p[1], p[2].x, p[2].y])
	var worst := []
	for nd in isl.nodes:
		var lo := 1e9
		var hi := -1e9
		for m in nd["members"]:
			var ys2: PackedFloat32Array = isl.roads[m[0]]["y"]
			var k := clampi(int(round(m[1])), 0, ys2.size() - 1)
			lo = minf(lo, ys2[k])
			hi = maxf(hi, ys2[k])
		worst.append([hi - lo, nd["c"]])
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("junction height spread, worst:")
	for w in worst.slice(0, 8):
		print("  %.2f m at (%.0f, %.0f)" % [w[0], w[1].x, w[1].y])
	quit()
