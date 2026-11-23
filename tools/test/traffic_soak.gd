extends SceneTree
## Runs the traffic on its own for a while and reports what went wrong: cars overlapping, cars stuck,
## cars off the road, cars inside buildings, sudden turns.
##   godot --headless --path . -s res://tools/test/traffic_soak.gd -- [seconds] [x,z of the watcher]
const Island := preload("res://scripts/game/island.gd")
const Traffic := preload("res://scripts/game/traffic.gd")
var isl: Node3D
var tr: Node3D
var t := 0.0
var dur := 300.0
var watch := Vector3(-80, 0, 60)
var overl := {}        # pair -> frames
var events := []
var stuck := {}
var offroad := 0
var inprop := {}
var snaps := 0
var last_yaw := {}
var frames := 0
var box := BoxShape3D.new()

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		dur = float(a[0])
	if a.size() > 1:
		var xz := a[1].split(",")
		watch = Vector3(float(xz[0]), 0, float(xz[1]))

func _rect(c: Dictionary) -> Array:
	var bn: Node3D = c["body"]
	var p := Vector2(bn.global_position.x, bn.global_position.z)
	var f3 := -bn.global_transform.basis.z
	var f := Vector2(f3.x, f3.z).normalized()
	return [p, f, Vector2(-f.y, f.x), float(c["len"]) * 0.45, float(c["w"]) * 0.45]

func _overlap(a: Array, b: Array) -> bool:
	for ax in [a[1], a[2], b[1], b[2]]:
		var pa: float = (a[0] as Vector2).dot(ax)
		var ra: float = absf((a[1] as Vector2).dot(ax)) * a[3] + absf((a[2] as Vector2).dot(ax)) * a[4]
		var pb: float = (b[0] as Vector2).dot(ax)
		var rb: float = absf((b[1] as Vector2).dot(ax)) * b[3] + absf((b[2] as Vector2).dot(ax)) * b[4]
		if absf(pa - pb) > ra + rb:
			return false
	return true

func _physics_process(dt: float) -> bool:
	if isl == null:
		isl = Island.new()
		get_root().add_child(isl)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/toon.gdshader")
		isl.build(mat, 2)
		tr = Traffic.new()
		get_root().add_child(tr)
		tr.setup(isl, mat)
		tr.ignore_player = true
		return false
	t += dt
	frames += 1
	tr.tick(dt, watch, Vector3.ZERO, Vector3.ZERO)
	var rects := []
	for c in tr.cars:
		rects.append(_rect(c))
	for i in tr.cars.size():
		var c: Dictionary = tr.cars[i]
		var w: String = "%s/g%d" % [c.get("why", ""), tr._green(isl.nodes[c["plan"]["ni"]]) if not c["plan"].is_empty() else 9]
		var hist: Array = c.get("hist", [])
		if hist.is_empty() or hist[hist.size() - 1] != w:
			hist.append(w)
			if hist.size() > 8:
				hist.remove_at(0)
		c["hist"] = hist
		var bn: Node3D = c["body"]
		var p := bn.global_position
		for j in range(i + 1, tr.cars.size()):
			if _overlap(rects[i], rects[j]):
				var key := "%d-%d" % [i, j]
				if not overl.has(key):
					events.append("t=%.0f overlap cars %d (%s %s) & %d (%s %s) at (%.0f, %.0f)" % [t, i, ["road", "turn"][c["mode"]], isl.roads[c["r"]]["name"],
						j, ["road", "turn"][tr.cars[j]["mode"]], isl.roads[tr.cars[j]["r"]]["name"], p.x, p.z])
				overl[key] = overl.get(key, 0) + 1
			else:
				overl.erase("%d-%d" % [i, j])
		if float(c["wait"]) > 25.0 and not stuck.has(i):
			stuck[i] = true
			var extra := ""
			if not c["plan"].is_empty():
				var ni: int = c["plan"]["ni"]
				var occ := []
				for o in tr.busy[ni]:
					var oc: Dictionary = tr.cars[o[0]]
					occ.append("car %d %s r=%s s=%.1f v=%.1f plan=%s" % [o[0], ["road", "turn"][oc["mode"]], isl.roads[oc["r"]]["name"], oc["s"], oc["v"], str(oc["plan"])])
				extra = " hist=%s why=%s v=%.1f green=%d exit_clear=%s busy=%s" % [str(c["hist"]), c.get("why", "?"), c["v"], tr._green(isl.nodes[ni]), str(tr._exit_clear(c, ni, c["plan"]["ei"])), str(occ)]
			events.append("t=%.0f stuck car %d on %s (%s) at (%.0f, %.0f) plan %s%s" % [t, i, isl.roads[c["r"]]["name"], ["road", "turn"][c["mode"]], p.x, p.z, str(c["plan"]), extra])
		if float(c["wait"]) < 1.0:
			stuck.erase(i)
		if frames % 20 == 0 and not isl.on_carriageway(Vector2(p.x, p.z), -1, 0.8):
			offroad += 1
			if offroad < 6:
				events.append("t=%.0f off road car %d (%s) near %s at (%.0f, %.0f)" % [t, i, ["road", "turn"][c["mode"]], isl.roads[c["r"]]["name"], p.x, p.z])
		var yaw := bn.global_rotation.y
		if c.get("jumped", false):
			c["jumped"] = false
			last_yaw.erase(i)
		if last_yaw.has(i) and absf(angle_difference(last_yaw[i], yaw)) > 0.35:
			snaps += 1
			if snaps < 14:
				events.append("t=%.0f snap car %d %.0f° (%s) at (%.0f, %.0f)" % [t, i, rad_to_deg(angle_difference(last_yaw[i], yaw)), ["road", "turn"][c["mode"]], p.x, p.z])
		last_yaw[i] = yaw
		if frames % 30 == i % 30:
			var q := PhysicsShapeQueryParameters3D.new()
			box.size = Vector3(float(c["w"]) * 0.7, 1.0, float(c["len"]) * 0.7)
			q.shape = box
			q.transform = Transform3D(bn.global_transform.basis, p + Vector3(0, 0.9, 0))
			q.collision_mask = 1
			q.exclude = [isl.body.get_rid()]
			var hits := get_root().get_world_3d().direct_space_state.intersect_shape(q, 1)
			if not hits.is_empty():
				var key2 := "%d@%d,%d" % [i, int(p.x / 5), int(p.z / 5)]
				if not inprop.has(key2):
					inprop[key2] = true
					if inprop.size() < 12:
						events.append("t=%.0f car %d inside something at (%.0f, %.0f) on %s" % [t, i, p.x, p.z, isl.roads[c["r"]]["name"]])
	if t >= dur:
		for e in events.slice(0, 60):
			print(e)
		var moving := 0
		for c in tr.cars:
			if float(c["v"]) > 1.0:
				moving += 1
		print("SOAK %.0fs: overlap events %d, stuck %d, off-road samples %d, inside props %d, snaps %d, crossed %d, uturns %d, respawns %d, moving now %d/%d" % [
			dur, events.filter(func(e): return "overlap" in e).size(), events.filter(func(e): return "stuck" in e).size(), offroad, inprop.size(), snaps,
			tr.stats["crossed"], tr.stats["uturns"], tr.stats["respawns"], moving, tr.cars.size()])
		quit()
	return false
