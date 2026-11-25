extends MultiMeshInstance3D
## Many copies of one mesh in a single draw call. Slots are handed out and returned; a free slot is
## scaled to zero, and only slots up to the highest one in use are drawn. (The compatibility renderer needs instance colors switched on for vertex colors
## and custom data to reach the shader, so every slot gets white.)

var _free: Array[int] = []
var _cap := 0
var _on := PackedByteArray()   # which slots are handed out
var _hi := 0                   # slots past this are all free, so they aren't drawn
var HIDDEN := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -9999, 0))
var _box := AABB()
var _has := false
var _r := 4.0

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
	# the box round what's been put down so far (grows as copies are put out), so the renderer can skip the
	# whole lot when none of them is anywhere near the view or the sun's shadow box; till then, nothing
	_r = mesh.get_aabb().size.length() * 0.5 + mesh.get_aabb().get_center().length() if mesh else 4.0
	_box = AABB()
	_has = false
	custom_aabb = AABB(Vector3(0, -9999, 0), Vector3.ONE)
	_free.clear()
	for i in range(capacity - 1, -1, -1):
		_free.push_back(i)
	_on.resize(capacity)
	_on.fill(0)
	_set_hi(0)

func _set_hi(h: int) -> void:
	_hi = h
	multimesh.visible_instance_count = h

func alloc() -> int:
	if _free.is_empty():
		return -1
	var i: int = _free.pop_back()
	_on[i] = 1
	if i >= _hi:
		_set_hi(i + 1)
	return i

func release(i: int) -> void:
	if i < 0:
		return
	multimesh.set_instance_transform(i, HIDDEN)
	multimesh.set_instance_color(i, Color.WHITE)
	_free.push_back(i)
	_on[i] = 0
	if i == _hi - 1:
		var h := i
		while h > 0 and _on[h - 1] == 0:
			h -= 1
		_set_hi(h)

func put(i: int, xf: Transform3D) -> void:
	if i >= 0:
		multimesh.set_instance_transform(i, xf)
		if xf.origin.y > -9000.0:
			var r := _r * maxf(xf.basis.get_scale().x, maxf(xf.basis.get_scale().y, xf.basis.get_scale().z)) + 1.0
			var b := AABB(xf.origin - Vector3.ONE * r, Vector3.ONE * r * 2.0)
			if not _has:
				_box = b
				_has = true
				custom_aabb = _box
			elif not _box.encloses(b):
				_box = _box.merge(b)
				custom_aabb = _box

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
	_on.fill(0)
	_set_hi(0)
