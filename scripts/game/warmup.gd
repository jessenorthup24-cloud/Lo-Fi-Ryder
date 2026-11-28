extends Node3D
## Shader warm-up, behind the loading card. The renderer (GL Compatibility) builds each shader the first time
## something drawn with it appears, under the lights it's in: the first gunshot (its flash is a point light),
## the first police car, the first night, each one used to stutter as it was built. Here every material the
## game has, and every shader in shaders/, is drawn once, high above the island where nobody sees it: as a
## plain mesh and as a multimesh (the effects pools), lit by the sun and its shadows, then again with a
## point light and a spot light beside it. The screen-space effects are drawn once under the card too.
## Then the card lifts. A few frames; the GPU driver keeps what it built, so later launches are quicker still.

const M := preload("res://scripts/core/models.gd")
const Avatar := preload("res://scripts/game/avatar.gd")
const AT := Vector3(0, 420, 0)       # the showroom, up in the sky
const FRAMES := 8

signal finished

var game: Node
var _done: Callable
var _n := 0
var _items: Array = []
var _canvas: CanvasLayer
var _omni: OmniLight3D
var _spot: SpotLight3D
var count := 0                        # (how many materials it built: for the tests)

func run(g: Node, done: Callable) -> void:
	game = g
	_done = done
	process_mode = Node.PROCESS_MODE_ALWAYS
	var mats := _collect()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	var cols := 8
	var i := 0
	for m in mats:
		var p := AT + Vector3((i % cols) * 0.9 - cols * 0.45, (i / cols) * 0.9, 0)
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = m
		add_child(mi)
		mi.global_position = p
		# the same as a multimesh (the effects pools and the island's props draw this way)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = box
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis(), Vector3.ZERO))
		mm.set_instance_color(0, Color(1, 1, 1, 0.7))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		add_child(mmi)
		mmi.global_position = p + Vector3(0, 0, -0.9)
		_items.append(mi)
		_items.append(mmi)
		i += 1
	count = mats.size()
	# the people: each look painted once now (a first meeting with each used to be a stutter), and stood here
	# so the skinned (bending) version of the shader's built too
	var looks := {}
	for c in M.CHARS:
		looks[String(c)] = true
	var pmat: Material = game.island.people.mat if game.island.people.mat else game.toon
	var k := 0
	for id in looks:
		var av := Avatar.new()
		add_child(av)
		av.setup(String(id), "", pmat)
		av.position = AT + Vector3((k % 8) * 0.8 - 3.2, -1.5 - (k / 8) * 2.0, 1.0)
		k += 1
	# the screen effects, drawn once under the loading card
	_canvas = CanvasLayer.new()
	_canvas.layer = -5
	add_child(_canvas)
	for sh in _shaders("canvas_item"):
		var cr := ColorRect.new()
		cr.size = Vector2(8, 8)
		var sm := ShaderMaterial.new()
		sm.shader = sh
		cr.material = sm
		_canvas.add_child(cr)
	set_process(true)

## Every material in the scene now, the toon and the car paint by name, and one of every spatial shader in
## shaders/ (with its defaults: uniforms don't make new shaders, only the lights and the mesh's kind do).
func _collect() -> Array:
	var out := {}
	var seen_shaders := {}
	for m in [game.toon, game.car_paint, game.island.road_mat, game.fx.smoke_mat]:
		if m:
			out[m] = true
			if m is ShaderMaterial:
				seen_shaders[(m as ShaderMaterial).shader] = true
	for n in game.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi.material_override:
			_add(gi.material_override, out, seen_shaders)
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
			var msh: Mesh = (gi as MeshInstance3D).mesh
			for s in msh.get_surface_count():
				var sm := msh.surface_get_material(s)
				if sm:
					_add(sm, out, seen_shaders)
		if out.size() > 140:
			break
	for sh in _shaders("spatial"):
		if not seen_shaders.has(sh):
			var nm := ShaderMaterial.new()
			nm.shader = sh
			out[nm] = true
	return out.keys()

func _add(m: Material, out: Dictionary, seen: Dictionary) -> void:
	if m is ShaderMaterial:
		var sh: Shader = (m as ShaderMaterial).shader
		if sh == null or seen.has(sh):
			return
		seen[sh] = true
		out[m] = true
	elif m is BaseMaterial3D:
		# (standard materials: one per kind: shaded or not, see-through or not, textured or not)
		var bm := m as BaseMaterial3D
		var key := "std_%d_%d_%d_%d" % [bm.shading_mode, bm.transparency, int(bm.albedo_texture != null), int(bm.vertex_color_use_as_albedo)]
		if not seen.has(key):
			seen[key] = true
			out[m] = true

static func _shaders(kind: String) -> Array:
	var out := []
	var dir := DirAccess.open("res://shaders")
	if dir == null:
		return out
	for f in dir.get_files():
		var fn := f.trim_suffix(".remap")
		if not fn.ends_with(".gdshader"):
			continue
		var sh: Shader = load("res://shaders/" + fn)
		if sh and sh.get_mode() == (Shader.MODE_SPATIAL if kind == "spatial" else Shader.MODE_CANVAS_ITEM):
			out.append(sh)
	return out

func _process(_dt: float) -> void:
	_n += 1
	# the camera on the showroom (main's camera, put back afterwards by main itself)
	var cam: Camera3D = game.cam
	cam.global_transform = Transform3D(Basis(), AT + Vector3(0, 1.2, 8.0)).looking_at(AT + Vector3(0, 1.0, 0), Vector3.UP)
	if _n == 3:
		# now with the lights a gunshot, a drill or a shop lamp brings
		_omni = OmniLight3D.new()
		_omni.omni_range = 12.0
		_omni.light_energy = 2.0
		add_child(_omni)
		_omni.global_position = AT + Vector3(0, 1.5, 2.0)
		_spot = SpotLight3D.new()
		_spot.spot_range = 14.0
		add_child(_spot)
		_spot.global_transform = Transform3D(Basis(), AT + Vector3(2, 2, 4)).looking_at(AT, Vector3.UP)
	if _n == 5 and _omni:
		_omni.shadow_enabled = true
	if _n >= FRAMES:
		set_process(false)
		finished.emit()
		if _done.is_valid():
			_done.call()
		queue_free()
