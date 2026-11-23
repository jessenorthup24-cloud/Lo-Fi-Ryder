extends SceneTree
## Builds the island and lists everything solid that stands on a road's carriageway (not the pavement).
##   godot --headless --path . -s res://tools/test/road_audit.gd
const Island := preload("res://scripts/game/island.gd")
func _init() -> void:
	var isl: Node3D = Island.new()
	isl.audit_on = true
	get_root().add_child(isl)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon.gdshader")
	isl.build(mat, 2)
	# a grid of road centre points
	var grid := {}
	for r in isl.roads:
		var hw: float = float(r["w"]) * 0.5
		for p in (r["pts"] as PackedVector2Array):
			var key := Vector2i(int(floor(p.x / 10.0)), int(floor(p.y / 10.0)))
			if not grid.has(key):
				grid[key] = []
			grid[key].append([p, hw, r["name"]])
	var bad := 0
	for it in isl.audit:
		var hitn := ""
		var at := Vector2.ZERO
		for q in it[1]:
			var key := Vector2i(int(floor(q.x / 10.0)), int(floor(q.y / 10.0)))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for e in grid.get(key + Vector2i(dx, dz), []):
						if q.distance_to(e[0]) < float(e[1]) - 0.5:
							hitn = e[2]
							at = q
		if hitn != "":
			bad += 1
			print("ON ROAD  %-40s (%.0f, %.0f)  %s" % [it[0], at.x, at.y, hitn])
	print("checked %d things, %d on a road" % [isl.audit.size(), bad])
	quit()
