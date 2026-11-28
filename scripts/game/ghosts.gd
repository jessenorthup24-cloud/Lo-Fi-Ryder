extends Node
## Ghosts: your best run at a time trial, a rock crawl or a race, driven again beside you, see-through, the
## next time you go for it. And at each gate, how far ahead or behind it you are.
## A run is where the car was ten times a second (and when it went through each gate); the best one for each
## challenge is kept in a file of its own (user://ghosts), with the car it was set in.

const M := preload("res://scripts/core/models.gd")
const CARS := preload("res://scripts/game/cars.gd")
const DT := 0.1
const DIR := "user://ghosts/"
const MAX_T := 900.0            # (a run longer than this isn't kept: nobody's racing that)

var game: Node
var key := ""
var rec := PackedFloat32Array()  # x, y, z, qx, qy, qz, qw a sample
var splits: Array = []           # time at each gate
var _next_t := 0.0
var best: Dictionary = {}        # {score, car, splits, data}
var node: Node3D                 # the ghost car
var _mat: StandardMaterial3D

func setup(g: Node) -> void:
	game = g
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(0.45, 0.9, 1.0, 0.32)
	_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_mat.no_depth_test = false

func enabled() -> bool:
	return bool(game.save.data["settings"].get("ghosts", true))

static func _file(k: String) -> String:
	return DIR + k.validate_filename() + ".ghost"

## A run starting: record it, and bring out the best one there is (if there is one).
func start(k: String) -> void:
	stop()
	key = k
	rec = PackedFloat32Array()
	splits = []
	_next_t = 0.0
	best = load_best(k)
	if not best.is_empty() and enabled():
		_make_ghost(String(best.get("car", "")))

## Called each frame while the run's on, with the run's clock.
func tick(t: float) -> void:
	if key == "":
		return
	var car: Node3D = game.car
	while t >= _next_t and t < MAX_T:
		var tr := car.global_transform
		var q := tr.basis.get_rotation_quaternion()
		rec.append_array([tr.origin.x, tr.origin.y, tr.origin.z, q.x, q.y, q.z, q.w])
		_next_t += DT
	if node:
		_place(t)

## Through a gate: its time kept, and the gap to the ghost's (negative: ahead of it). NAN with no ghost.
func split(i: int, t: float) -> float:
	while splits.size() <= i:
		splits.append(-1.0)
	splits[i] = t
	if best.is_empty():
		return NAN
	var bs: Array = best.get("splits", [])
	if i < bs.size() and float(bs[i]) >= 0.0:
		return t - float(bs[i])
	return NAN

## The run's over. A new best (lower `score` than the kept one): this run's the ghost now.
func finish(score: float) -> void:
	if key == "":
		return
	var old := float(best.get("score", INF)) if not best.is_empty() else INF
	if score < old and rec.size() >= 7 * 10:
		DirAccess.make_dir_recursive_absolute(DIR)
		var f := FileAccess.open_compressed(_file(key), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
		if f:
			f.store_var({"score": score, "car": String(game.drive_def.get("id", game.save.data.get("car", ""))), "splits": splits, "dt": DT, "data": rec})
			f.close()
	stop()

func stop() -> void:
	key = ""
	if node:
		node.queue_free()
		node = null

static func load_best(k: String) -> Dictionary:
	var p := _file(k)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open_compressed(p, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var v = f.get_var()
	f.close()
	return v if v is Dictionary and (v as Dictionary).has("data") else {}

func _make_ghost(car_id: String) -> void:
	var def: Dictionary = CARS.by_id(car_id) if car_id != "" else {}
	if def.is_empty():
		def = game.drive_def
	var info: Dictionary = M.car(def)
	node = Node3D.new()
	node.name = "Ghost"
	var b := MeshInstance3D.new()
	b.mesh = info["body"]
	b.material_override = _mat
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(b)
	var spots: Array = info["wheels"]
	for i in 4:
		var w := MeshInstance3D.new()
		w.mesh = M.wheel_mesh(info, i)
		w.material_override = _mat
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.position = spots[i]
		node.add_child(w)
	game.add_child(node)
	_place(0.0)

func _place(t: float) -> void:
	var data: PackedFloat32Array = best["data"]
	var n := data.size() / 7
	if n == 0:
		return
	var f := clampf(t / DT, 0.0, float(n - 1))
	var i := int(f)
	var j := mini(i + 1, n - 1)
	var k := f - i
	var a := Vector3(data[i * 7], data[i * 7 + 1], data[i * 7 + 2])
	var b := Vector3(data[j * 7], data[j * 7 + 1], data[j * 7 + 2])
	var qa := Quaternion(data[i * 7 + 3], data[i * 7 + 4], data[i * 7 + 5], data[i * 7 + 6])
	var qb := Quaternion(data[j * 7 + 3], data[j * 7 + 4], data[j * 7 + 5], data[j * 7 + 6])
	# (a jump: a reset to the last gate; no sliding across the map between)
	var p := a if a.distance_to(b) > 8.0 else a.lerp(b, k)
	node.global_transform = Transform3D(Basis(qa.slerp(qb, k)), p)
	# finished its run: it waits at the line. Faded when it's right on top of you (or the camera).
	var near := minf(p.distance_to(game.car.global_position), p.distance_to(game.cam.global_position))
	_mat.albedo_color.a = 0.32 * clampf((near - 2.5) / 5.0, 0.0, 1.0)
	node.visible = _mat.albedo_color.a > 0.01
