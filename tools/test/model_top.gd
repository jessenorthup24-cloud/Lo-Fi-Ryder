extends SceneTree
## tools: what's on the roof of a car model (is there a light bar?): the top vertices, their spread and colours.
const M := preload("res://scripts/core/models.gd")
const CARS := preload("res://scripts/game/cars.gd")
func _init() -> void:
	var id := "police"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car="):
			id = a.substr(6)
	var d := CARS.by_id(id)
	var info := M.car(d)
	var mesh: Mesh = info["body"]
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var top := -1e9
	for p in v:
		top = maxf(top, p.y)
	print("top=%.3f info.top=%.3f height=%.3f front=%.3f back=%.3f width=%.3f length=%.3f" % [top, info["top"], info["height"], info["front"], info["back"], info["width"], info["length"]])
	for band in [0.03, 0.08, 0.15, 0.25]:
		var bb := AABB()
		var first := true
		var cols := {}
		for i in v.size():
			if v[i].y > top - band:
				if first:
					bb = AABB(v[i], Vector3.ZERO)
					first = false
				else:
					bb = bb.expand(v[i])
				cols[c[i].to_html(false)] = int(cols.get(c[i].to_html(false), 0)) + 1
		print("band %.2f: %s cols=%s" % [band, bb, cols])
	quit()
