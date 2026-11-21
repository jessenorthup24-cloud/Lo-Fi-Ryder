extends SceneTree
const M := preload("res://scripts/core/models.gd")
const CARS := preload("res://scripts/game/cars.gd")
func _init() -> void:
	var names := []
	var src := FileAccess.get_file_as_string("res://scripts/core/models.gd")
	var re := RegEx.new()
	re.compile("static func _m_(\\w+)\\(")
	var n := 0
	for r in re.search_all(src):
		var nm := r.get_string(1)
		var mesh := M.get_mesh(nm)
		var tris := 0
		for s in mesh.get_surface_count():
			tris += mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
		print(nm, ": ", tris, " tris")
		n += 1
	for d in CARS.LIST:
		var c := M.car(d)
		var tris := 0
		var mesh: ArrayMesh = c["body"]
		tris = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
		print("car ", d["id"], ": ", tris)
	print("models ok: ", n)
	quit()
