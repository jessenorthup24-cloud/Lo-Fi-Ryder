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
var aiming := 0.0              # firing: you face the target (gunplay sets facing), not where you walk

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

var scripted := false          # the game's moving you (climbing into a car): no walking, no physics
var down_t := 0.0              # knocked flat (bailed out of a moving car): ragdolling, then up again

func _physics_process(dt: float) -> void:
	if scripted:
		velocity = Vector3.ZERO
		avatar.rotation.y = facing + PI
		return
	if down_t > 0.0:
		_down_tick(dt)
		return
	var m := move.limit_length(1.0)
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var rgt := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	var dir := fwd * m.y + rgt * m.x
	var spd := 0.0
	if m.length() > 0.08:
		spd = SPRINT if sprint else lerpf(WALK, RUN, clampf((m.length() - 0.5) / 0.5, 0.0, 1.0))
	var want := dir.normalized() * spd if spd > 0.0 else Vector3.ZERO
	var grounded := is_on_floor()
	# a bit of weight: it takes a moment to get going and to stop (stopping's a little quicker)
	var cur := Vector3(velocity.x, 0, velocity.z)
	var acc := (9.0 if want.length() > cur.length() else 13.0) if grounded else 4.0
	if want.length() > 0.1 and cur.length() > 0.5 and want.normalized().dot(cur.normalized()) < 0.3:
		acc = 16.0       # (a hard change of direction digs in)
	var hv := cur.move_toward(want, acc * dt)
	velocity.x = hv.x
	velocity.z = hv.z
	if grounded:
		# down hard after a long drop: a heavy landing (move to shrug it off)
		if _air > 0.75:
			avatar.play_once("land", 0.35, 0.9)
		_air = 0.0
		if jump_req:
			velocity.y = JUMP_V
	else:
		_air += dt
		velocity.y -= GRAV * dt
	jump_req = false
	move_and_slide()
	# face where you're going (quickly, but not snapping)
	aiming = maxf(0.0, aiming - dt)
	if hv.length() > 0.4 and aiming <= 0.0:
		facing = lerp_angle(facing, atan2(-hv.x, -hv.z), 1.0 - exp(-dt * 7.5))
	avatar.rotation.y = facing + PI          # (the Kenney characters face +Z)
	# below the sea or fallen off the world: back up on land
	if global_position.y < -6.0:
		var p: Vector3 = global_position
		global_position = Vector3(p.x, island.height_at(p.x, p.z) + 1.0, p.z)
		velocity = Vector3.ZERO
	_animate(hv.length(), grounded)

var _gait := 0      # 0 stood, 1 walking, 2 running

func _animate(v: float, grounded: bool) -> void:
	if avatar.lock_t > 0.0:
		# a one-off move playing (out of the car, a landing): pushing the stick cuts it short
		if move.length() > 0.35 and avatar.lock_t < 10.0:
			avatar.lock_t = 0.0
		else:
			return
	# the gait, with a little give either side of each change so it doesn't flicker between two
	if v < 0.25:
		_gait = 0
	elif v > 3.9:
		_gait = 2
	elif _gait == 0 and v > 0.5:
		_gait = 1
	elif _gait == 2 and v < 3.0:
		_gait = 1
	if not grounded and _air > 0.18:
		avatar.play("jump" if velocity.y > 0.5 else "fall", 1.0, 0.2)
	elif _gait == 0:
		avatar.play("idle", 1.0, 0.3)
	elif _gait == 1:
		avatar.play("walk", clampf(v / 1.5, 0.7, 1.6), 0.3)
	else:
		avatar.play("sprint", clampf(v / 4.4, 0.85, 1.6), 0.3)

## Put down here, facing this way, stood still.
func place(p: Vector3, yaw: float) -> void:
	global_position = p
	velocity = Vector3.ZERO
	facing = yaw
	avatar.rotation.y = facing + PI

## Thrown down (out of a moving car): the ragdoll takes over, moving `vel`; a couple of seconds later you get
## up where the body ended up.
func knock_down(world: Node3D, vel: Vector3, t := 2.4) -> void:
	down_t = t
	velocity = Vector3.ZERO
	avatar.go_limp(world, vel, Vector3(0, 1.0, 0))

func _down_tick(dt: float) -> void:
	down_t -= dt
	var tp: Vector3 = avatar.limp.torso_pos() if avatar.limp else Vector3.INF
	if down_t > 0.0 or tp == Vector3.INF:
		if tp != Vector3.INF:
			# (the capsule follows the body along the ground, so the camera does too)
			var at := Vector3(tp.x, island.height_at(tp.x, tp.z), tp.z)
			global_position = Vector3(at.x, maxf(at.y, global_position.y - 0.5), at.z)
		if down_t <= 0.0:
			_get_up(global_position)
		return
	_get_up(Vector3(tp.x, island.height_at(tp.x, tp.z) + 0.05, tp.z))

func _get_up(p: Vector3) -> void:
	down_t = 0.0
	global_position = p
	velocity = Vector3.ZERO
	avatar.recover()
	avatar.rotation.y = facing + PI
	avatar.play_once("get_up", 0.0, 1.1, 1.2)
