extends SceneTree
## Prints the road network: every junction with its arms, and every road end that isn't on one.
##   godot --headless --path . -s res://tools/test/road_net.gd
const Island := preload("res://scripts/game/island.gd")
func _init() -> void:
	var isl: Node3D = Island.new()
	get_root().add_child(isl)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon.gdshader")
	isl.build(mat, 2)
	for ni in isl.nodes.size():
		var nd: Dictionary = isl.nodes[ni]
		var names := []
		for m in nd["members"]:
			names.append("%s@%.1f" % [isl.roads[m[0]]["name"], m[1]])
		var arms := []
		for a in nd["arms"]:
			arms.append("%s%s%s" % [isl.roads[a["r"]]["name"].substr(0, 8), "+" if a["dir"] > 0 else "-", "*" if a["minor"] else ""])
		print("node %2d (%.0f, %.0f)  %s   arms: %s" % [ni, nd["c"].x, nd["c"].y, ", ".join(names), " ".join(arms)])
	for ri in isl.roads.size():
		var r: Dictionary = isl.roads[ri]
		if r["closed"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		for e in [0, pts.size() - 1]:
			var on := false
			for nd in isl.nodes:
				for m in nd["members"]:
					if m[0] == ri and absf(float(m[1]) - e) < 6.0:
						on = true
			if not on:
				var best := 1e9
				var bn := ""
				for rj in isl.roads.size():
					if rj != ri:
						var d: float = isl.road_nearest(rj, pts[e])[0]
						if d < best:
							best = d
							bn = isl.roads[rj]["name"]
				print("END  %-14s %s (%.0f, %.0f)  nearest road %s at %.1f m" % [r["name"], "start" if e == 0 else "end", pts[e].x, pts[e].y, bn, best])
	print("timings ", isl.timings)
	quit()
