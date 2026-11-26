extends Node3D
## Godot 4.x. Attach to a Node3D containing the imported GLB.
## Set model to the imported scene root; never play Build_All simultaneously.
signal investment_changed(total: int, goal: int)
signal stage_completed(index: int, stage_name: String)
signal construction_finished

const STAGE_NAMES: Array[String] = [
	"00_Dirt_Lot", "01_Site_Work", "02_Foundation", "03_Structural_Frame",
	"04_Marble_Floor", "05_Exterior_Walls", "06_Roof_Skylights", "07_Rollup_Door",
	"08_West_Bays", "09_East_Bays", "10_Landscape", "11_Luxury_Details"
]
const RETIRE = {1: 6, 3: 6}
@export var model: Node3D
@export var funding_targets: Array[int] = [0, 15000, 60000, 120000, 220000, 350000, 460000, 530000, 620000, 710000, 760000, 850000]
@export var build_seconds: float = 1.15
@export var generate_collisions: bool = false
var invested: int = 0
var built_count: int = 0
var _stages: Array[Node3D] = []
var _positions: Array[Vector3] = []
var _active_tween: Tween
var _bodies: Dictionary = {}
var _initialized := false
var door_fraction: float = 0.0
var _door_tween: Tween
var _slats: Array[Node3D] = []
var _door_blocker: StaticBody3D
@export var door_seconds: float = 2.6
signal door_state_changed(is_open: bool)


func _ready() -> void:
	if model == null:
		model = self
	if funding_targets.size() != STAGE_NAMES.size() or funding_targets[0] != 0:
		push_error("Expected 12 cumulative funding targets starting with zero.")
		return
	for i in range(1, funding_targets.size()):
		if funding_targets[i] <= funding_targets[i - 1]:
			push_error("Funding targets must strictly increase.")
			return
	for child in model.find_children("*", "AnimationPlayer", true, false):
		var player := child as AnimationPlayer
		player.stop()
		player.active = false
	for stage_name in STAGE_NAMES:
		var stage := model.find_child(stage_name, true, false) as Node3D
		if stage == null:
			push_error("Missing stage: " + stage_name)
			return
		_stages.append(stage)
		_positions.append(stage.position)
	for i in range(22):
		var slat := model.find_child("DoorSlat_%02d" % i, true, false) as Node3D
		if slat == null:
			push_error("Missing roll-up door slat")
			return
		_slats.append(slat)
	if generate_collisions:
		var assembly := model.find_child("DoorAssembly", true, false) as Node3D
		_door_blocker = StaticBody3D.new()
		_door_blocker.name = "DoorBlocker"
		assembly.add_child(_door_blocker)
		_door_blocker.position = Vector3(0.0, 2.9, 39.06)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(13.15, 5.4, 0.20)
		collider.shape = shape
		_door_blocker.add_child(collider)
	_initialized = true
	restore_investment(invested)


func total_cost() -> int:
	return funding_targets.back()

func progress_ratio() -> float:
	return float(invested) / maxf(float(total_cost()), 1.0)

func next_target() -> int:
	for target in funding_targets:
		if target > invested:
			return target
	return total_cost()

## Caller verifies funds and deducts the accepted amount from the player's wallet.
func deposit(amount: int) -> int:
	if not _initialized or amount <= 0:
		return 0
	var accepted := mini(amount, maxi(0, total_cost() - invested))
	if accepted > 0:
		invested += accepted
		investment_changed.emit(invested, total_cost())
		_advance()
	return accepted

## Save invested; restore reconstructs both permanent and temporary visibility.
func restore_investment(amount: int) -> void:
	invested = clampi(amount, 0, total_cost())
	if not _initialized:
		return
	if _active_tween != null:
		_active_tween.kill()
		_active_tween = null
	built_count = 0
	for i in range(_stages.size()):
		if invested >= funding_targets[i]:
			built_count += 1
	for i in range(_stages.size()):
		var retired: bool = RETIRE.has(i) and built_count > int(RETIRE.get(i, 999))
		var visible_now: bool = i < built_count and not retired
		# Explicitly restore the authored identity basis even if the GLB starts at zero scale.
		_stages[i].transform = Transform3D(Basis.IDENTITY, _positions[i])
		_stages[i].visible = visible_now
		_set_collision(i, visible_now)
	_set_door_fraction(0.0 if built_count <= 7 else door_fraction)
	investment_changed.emit(invested, total_cost())

func _advance() -> void:
	if _active_tween != null or built_count >= _stages.size():
		return
	if invested < funding_targets[built_count]:
		return
	var index := built_count
	# Remove temporary geometry before its permanent replacement grows in.
	for temporary in RETIRE.keys():
		if int(RETIRE[temporary]) == index:
			_stages[temporary].visible = false
			_set_collision(temporary, false)
	var stage := _stages[index]
	stage.transform = Transform3D(Basis.IDENTITY, _positions[index])
	stage.scale = Vector3(1.0, 0.001, 1.0)
	stage.visible = true
	_active_tween = create_tween()
	_active_tween.tween_property(stage, "scale", Vector3.ONE, maxf(build_seconds, 0.05)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_active_tween.finished.connect(func():
		_active_tween = null
		built_count = index + 1
		_set_collision(index, true)
		if index == 7:
			_set_door_fraction(door_fraction)
		stage_completed.emit(index + 1, STAGE_NAMES[index])
		if built_count == _stages.size():
			construction_finished.emit()
		else:
			_advance()
	)

func _set_collision(index: int, enabled: bool) -> void:
	if not generate_collisions:
		return
	if enabled and not _bodies.has(index):
		var bodies: Array[StaticBody3D] = []
		for child in _stages[index].find_children("*", "MeshInstance3D", true, false):
			var mesh_node := child as MeshInstance3D
			# Keep paint, dirt decoration and small decorative elements non-colliding.
			if mesh_node.name.ends_with("_line") or mesh_node.name.ends_with("_dirt_light") or mesh_node.name.ends_with("_gold") or mesh_node.name.ends_with("_marble_vein") or mesh_node.name.begins_with("DoorSlat_") or mesh_node.name.ends_with("_emission"):
				continue
			if mesh_node.mesh == null:
				continue
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			shape.shape = mesh_node.mesh.create_trimesh_shape()
			body.add_child(shape)
			mesh_node.add_child(body)
			bodies.append(body)
		_bodies[index] = bodies
	if _bodies.has(index):
		for body in _bodies[index]:
			body.collision_layer = 1 if enabled else 0
			body.collision_mask = 1 if enabled else 0

## Returns only completed parking bays, ordered by bay number.
## Spawn cars outside the construction stage hierarchy to avoid inherited scaling.
func available_bays() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not _initialized:
		return result
	for i in range(1, 26):
		var needed := 8 if i <= 13 else 9
		if built_count <= needed:
			continue
		var marker := model.find_child("Bay_%02d" % i, true, false) as Node3D
		if marker != null:
			result.append(marker)
	return result

## Returns transform for the requested bay. +Z is vehicle-forward by default.
## Set vehicle_forward_is_negative_z for Godot models pointing toward -Z.
func bay_transform(bay_number: int, vehicle_forward_is_negative_z: bool = false) -> Transform3D:
	var wanted := "Bay_%02d" % bay_number
	for marker in available_bays():
		if String(marker.name) == wanted:
			var t := marker.global_transform
			if vehicle_forward_is_negative_z:
				t.basis = t.basis * Basis(Vector3.UP, PI)
			return t
	push_warning("Parking bay unavailable: " + wanted)
	return Transform3D.IDENTITY

## The controller drives door slats directly, so construction and door motion can run independently.
func _set_door_fraction(value: float) -> void:
	door_fraction = clampf(value, 0.0, 1.0)
	for i in range(_slats.size()):
		var y: float = 0.32 + float(i) * 0.24
		var threshold: float = (5.64 - y) / 5.6
		var factor: float = clampf(1.0 - maxf(0.0, door_fraction - threshold) / 0.035, 0.0001, 1.0)
		var slat := _slats[i]
		slat.position = Vector3(0.0, minf(y + 5.6 * door_fraction, 5.90), 39.06)
		slat.scale = Vector3(1.0, factor, 1.0) if factor > 0.0001 else Vector3.ONE * 0.0001
		slat.visible = factor > 0.0001
	if is_instance_valid(_door_blocker):
		var block: bool = built_count > 7 and door_fraction < 0.999
		_door_blocker.set_deferred("collision_layer", 1 if block else 0)
		_door_blocker.set_deferred("collision_mask", 1 if block else 0)

func set_door_open(open: bool, animate: bool = true) -> void:
	if not _initialized or built_count <= 7:
		return
	if _door_tween != null:
		_door_tween.kill()
		_door_tween = null
	var goal: float = 1.0 if open else 0.0
	if not animate:
		_set_door_fraction(goal)
		door_state_changed.emit(open)
		return
	_door_tween = create_tween()
	_door_tween.tween_method(_set_door_fraction, door_fraction, goal, maxf(0.05, door_seconds * absf(goal - door_fraction)))
	_door_tween.finished.connect(func():
		_door_tween = null
		door_state_changed.emit(open)
	)

func save_state() -> Dictionary:
	return {"invested": invested, "door_open": door_fraction >= 0.5}

func restore_state(data: Dictionary) -> void:
	if _door_tween != null:
		_door_tween.kill()
		_door_tween = null
	restore_investment(int(data.get("invested", 0)))
	set_door_open(bool(data.get("door_open", false)), false)
