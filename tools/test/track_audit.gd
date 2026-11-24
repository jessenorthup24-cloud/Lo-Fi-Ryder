extends SceneTree
## Checks the Raceway's loops: sample spacing, kinks (heading jumps between samples), folds, the seam where
## each loop closes, heights along it, and the junctions on it.
##   godot --headless --path . -s res://tools/test/track_audit.gd
const Island := preload("res://scripts/game/island.gd")

func _init() -> void:
	var isl: Node3D = Island.new()
	get_root().add_child(isl)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon.gdshader")
	isl.build(mat, 2)
	for ri in isl.roads.size():
		var r: Dictionary = isl.roads[ri]
		if not (r["kind"] in ["track", "drift", "yard"]) or not String(r["name"]).begins_with("Ra") and r["name"] != "Drift Course":
			continue
		var pts: PackedVector2Array = r["pts"]
		var ys: PackedFloat32Array = r["y"]
		var n := pts.size()
		var segs := n if r["closed"] else n - 1
		var mn := 1e9
		var mx := 0.0
		var kinks := 0
		var worst := 0.0
		var worst_at := Vector2.ZERO
		var len := 0.0
		for k in segs:
			var d := pts[k].distance_to(pts[(k + 1) % n])
			len += d
			mn = minf(mn, d)
			mx = maxf(mx, d)
			if k + 2 <= segs or r["closed"]:
				var t0 := (pts[(k + 1) % n] - pts[k]).normalized()
				var t1 := (pts[(k + 2) % n] - pts[(k + 1) % n]).normalized()
				var a := absf(rad_to_deg(t0.angle_to(t1)))
				if k + 2 > n - 1 and not r["closed"]:
					continue
				if a > worst:
					worst = a
					worst_at = pts[(k + 1) % n]
				if a > 30.0:          # (a 9 m drift hairpin turns ~16° a sample; a fold is ~180°)
					kinks += 1
					print("  KINK %s at %d (%.1f, %.1f): %.1f deg  (seg %.2f m)" % [r["name"], k + 1, pts[(k + 1) % n].x, pts[(k + 1) % n].y, a, d])
		var ymn := 1e9
		var ymx := -1e9
		for v in ys:
			ymn = minf(ymn, v)
			ymx = maxf(ymx, v)
		print("%s [%s] closed=%s n=%d len=%.0f m  seg %.2f..%.2f  worst turn %.1f deg at (%.0f, %.0f)  kinks %d  y %.2f..%.2f" % [
			r["name"], r["kind"], r["closed"], n, len, mn, mx, worst, worst_at.x, worst_at.y, kinks, ymn, ymx])
		if r["closed"]:
			print("   seam: first (%.2f, %.2f) last (%.2f, %.2f) gap %.2f" % [pts[0].x, pts[0].y, pts[n - 1].x, pts[n - 1].y, pts[0].distance_to(pts[n - 1])])
		# self-overlap: two bits of the same road closer than its width that are far apart along it
		var hw: float = float(r["w"]) * 0.5
		var close := 0
		for i in n:
			for j in range(i + 8, n):
				if r["closed"] and n - (j - i) < 8:
					continue
				if pts[i].distance_to(pts[j]) < hw * 2.0:
					close += 1
		if close > 0:
			print("   overlaps itself at %d sample pairs" % close)
	for ni in isl.nodes.size():
		var nd: Dictionary = isl.nodes[ni]
		var hit := false
		var names := []
		for m in nd["members"]:
			var nm: String = isl.roads[m[0]]["name"]
			names.append("%s@%.1f" % [nm, m[1]])
			if nm.begins_with("Raceway") or nm == "Drift Course":
				hit = true
		if hit:
			var arms := []
			for a in nd["arms"]:
				arms.append("%s%s%s" % [isl.roads[a["r"]]["name"].substr(0, 8), "+" if a["dir"] > 0 else "-", "*" if a["minor"] else ""])
			print("node %2d (%.1f, %.1f)  %s   arms: %s  all_way=%s" % [ni, nd["c"].x, nd["c"].y, ", ".join(names), " ".join(arms), nd.get("all_way", false)])
	# where the circuit and the drift course come close to each other or other roads
	quit()
