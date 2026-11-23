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
	# pavements: the middle strip (from 0.9 m to 2.5 m out from the kerb) is for walking
	var walkers := 0
	for it in isl.audit:
		var at := Vector2.ZERO
		var hitn := ""
		for q in it[1]:
			var key := Vector2i(int(floor(q.x / 10.0)), int(floor(q.y / 10.0)))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for e in grid.get(key + Vector2i(dx, dz), []):
						var r: Dictionary = isl.roads[isl.roads.map(func(x): return x["name"]).find(e[2])]
						if not r["walk"]:
							continue
						var d: float = q.distance_to(e[0])
						if d > float(e[1]) + 0.9 and d < float(e[1]) + 2.5 and not isl.on_carriageway(q, -1, 0.0):
							var dd: float = isl.road_nearest(isl.roads.find(r), q)[0]
							if dd > float(e[1]) + 0.9 and dd < float(e[1]) + 2.5:
								hitn = e[2]
								at = q
		if hitn != "":
			walkers += 1
			if walkers < 40:
				print("ON PAVEMENT  %-34s (%.0f, %.0f)  %s" % [it[0], at.x, at.y, hitn])
	print("%d things in a pavement's walking strip" % walkers)
	quit()
