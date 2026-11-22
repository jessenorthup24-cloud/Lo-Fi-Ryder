extends MultiMeshInstance3D
## Many copies of one mesh in a single draw call. Slots are handed out and returned; a free slot is
## scaled to zero. (The compatibility renderer needs instance colors switched on for vertex colors
## and custom data to reach the shader, so every slot gets white.)

var _free: Array[int] = []
var _cap := 0
var HIDDEN := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -9999, 0))

func setup(mesh: Mesh, capacity: int, mat: Material, custom := false, shadows := true) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = capacity
	_cap = capacity
	for i in capacity:
		mm.set_instance_transform(i, HIDDEN)
		mm.set_instance_color(i, Color.WHITE)
	multimesh = mm
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-5000, -200, -5000), Vector3(10000, 400, 10000))
	_free.clear()
	for i in range(capacity - 1, -1, -1):
		_free.push_back(i)

func alloc() -> int:
	if _free.is_empty():
		return -1
	return _free.pop_back()

func release(i: int) -> void:
	if i < 0:
		return
	multimesh.set_instance_transform(i, HIDDEN)
	multimesh.set_instance_color(i, Color.WHITE)
	_free.push_back(i)

func put(i: int, xf: Transform3D) -> void:
	if i >= 0:
		multimesh.set_instance_transform(i, xf)

## Tints a whole instance (for meshes built white on purpose: towels, tents, canoes…).
func tint(i: int, c: Color) -> void:
	if i >= 0:
		multimesh.set_instance_color(i, c)

func custom(i: int, c: Color) -> void:
	if i >= 0:
		multimesh.set_instance_custom_data(i, c)

func used() -> int:
	return _cap - _free.size()

func clear_all() -> void:
	for i in _cap:
		multimesh.set_instance_transform(i, HIDDEN)
	_free.clear()
	for i in range(_cap - 1, -1, -1):
		_free.push_back(i)
