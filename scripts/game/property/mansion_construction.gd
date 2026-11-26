extends Node3D
## Godot 4.x. Attach to a Node3D containing the imported GLB.
## Set model to the imported scene root; never play Build_All simultaneously.
signal investment_changed(total: int, goal: int)
signal stage_completed(index: int, stage_name: String)
signal construction_finished

const STAGE_NAMES: Array[String] = [
	"01_Dirt_Lot", "02_Foundation", "13_Scaffolding", "14_Ground_Framing",
	"03_Ground_Structure", "04_Ground_Facade", "15_Upper_Framing", "05_Upper_Structure",
	"06_Upper_Facade", "07_Roof", "08_Ground_Interiors", "09_Upper_Interiors",
	"10_Outdoor_Amenities", "11_Landscape", "12_Luxury_Details"
]
# Map temporary stage index to the stage index at which it is retired.
const RETIRE = {2: 9, 3: 4, 6: 7}
@export var model: Node3D
@export var funding_targets: Array[int] = [0, 50000, 90000, 140000, 200000, 350000, 450000, 550000, 700000, 850000, 1100000, 1350000, 1600000, 1800000, 2000000]
@export var build_seconds: float = 1.15
@export var generate_collisions: bool = false
var invested: int = 0
var built_count: int = 0
var _stages: Array[Node3D] = []
var _positions: Array[Vector3] = []
var _active_tween: Tween
var _bodies: Dictionary = {}
var _initialized := false

func _ready() -> void:
	if model == null:
		model = self
	if funding_targets.size() != STAGE_NAMES.size() or funding_targets[0] != 0:
		push_error("Expected 15 cumulative funding targets starting with zero.")
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
