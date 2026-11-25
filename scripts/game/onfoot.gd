extends CharacterBody3D
## You, out of the car: walk, sprint, jump about the island in third person. main.gd feeds the input
## (move: the stick or WASD, camera-relative; sprint; jump) and the camera follows; this does the moving,
## the turning to face where you're going, and the animation (idle, walk, sprint, jump, fall).

const Avatar := preload("res://scripts/game/avatar.gd")
const LAYER := 128             # what you are, for collisions
const WALK := 2.6              # m/s at a light push of the stick
const RUN := 4.6               # full stick
const SPRINT := 7.2            # holding sprint
const JUMP_V := 5.2
const GRAV := 16.0
const RADIUS := 0.34
const HEIGHT := 1.7

var avatar: Avatar
var move := Vector2.ZERO       # stick, in the camera's frame: x right, y forward (-1..1)
var cam_yaw := 0.0             # the camera's heading (main sets it): forward on the stick is where it looks
var sprint := false
var jump_req := false
var facing := 0.0              # where the character points (yaw)
var island: Node
var _air := 0.0

func setup(isl: Node, id: String, acc: String, mat: Material) -> void:
	island = isl
	collision_layer = LAYER
	collision_mask = 1 | 2 | 4 | 8 | 16 | 32
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	cs.shape = cap
	cs.position.y = HEIGHT * 0.5
	add_child(cs)
	avatar = Avatar.new()
	add_child(avatar)
	avatar.setup(id, acc, mat)

func _physics_process(dt: float) -> void:
	var m := move.limit_length(1.0)
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var rgt := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	var dir := fwd * m.y + rgt * m.x
	var spd := 0.0
	if m.length() > 0.08:
		spd = SPRINT if sprint else lerpf(WALK, RUN, clampf((m.length() - 0.5) / 0.5, 0.0, 1.0))
	var want := dir.normalized() * spd if spd > 0.0 else Vector3.ZERO
	var grounded := is_on_floor()
	var acc := 30.0 if grounded else 6.0
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(want, acc * dt)
	velocity.x = hv.x
	velocity.z = hv.z
	if grounded:
		_air = 0.0
		if jump_req:
			velocity.y = JUMP_V
	else:
		_air += dt
		velocity.y -= GRAV * dt
	jump_req = false
	move_and_slide()
	# face where you're going (quickly, but not snapping)
	if hv.length() > 0.4:
		facing = lerp_angle(facing, atan2(-hv.x, -hv.z), 1.0 - exp(-dt * 12.0))
	avatar.rotation.y = facing + PI          # (the Kenney characters face +Z)
	# below the sea or fallen off the world: back up on land
	if global_position.y < -6.0:
		var p: Vector3 = global_position
		global_position = Vector3(p.x, island.height_at(p.x, p.z) + 1.0, p.z)
		velocity = Vector3.ZERO
	_animate(hv.length(), grounded)

func _animate(v: float, grounded: bool) -> void:
	if not grounded and _air > 0.12:
		avatar.play("jump" if velocity.y > 0.5 else "fall")
	elif v < 0.35:
		avatar.play("idle")
	elif v < 3.4:
		avatar.play("walk", clampf(v / 2.2, 0.6, 1.5))
	else:
		avatar.play("sprint", clampf(v / 6.4, 0.7, 1.4))

## Put down here, facing this way, stood still.
func place(p: Vector3, yaw: float) -> void:
	global_position = p
	velocity = Vector3.ZERO
	facing = yaw
	avatar.rotation.y = facing + PI
