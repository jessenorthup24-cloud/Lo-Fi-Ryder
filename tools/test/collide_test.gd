extends SceneTree
## Checks the props collider exists: rays across a city block must hit buildings.
var main: Node
var f := 0
func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	f += 1
	if f < 30:
		return false
	var space := root.get_world_3d().direct_space_state
	var hits := 0
	var tries := 0
	for x in [-230.0, -170.0, -110.0, -50.0, 10.0, 70.0]:
		for z in [-30.0, 90.0, 150.0]:
			tries += 1
			var y: float = main.island.height_at(x, z - 29.0) + 3.0
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, y, z - 29.0), Vector3(x, y, z + 29.0), 1)
			var r := space.intersect_ray(q)
			if not r.is_empty():
				hits += 1
	print("COLLIDE hits=%d/%d" % [hits, tries])
	quit()
	return true
