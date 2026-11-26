extends CharacterBody3D
## You, out of the car: walk, sprint, jump about the island in third person. main.gd feeds the input
## (move: the stick or WASD, camera-relative; sprint; jump) and the camera follows; this does the moving,
## the turning to face where you're going, and the animation (idle, walk, sprint, jump, fall).

const Avatar := preload("res://scripts/game/avatar.gd")
const LAYER := 128             # what you are, for collisions
const WALK := 2.6              # m/s at a light push of the stick
const RUN := 4.6               # full stick
const SPRINT := 7.2            # holding sprint
const CROUCH := 1.9            # crouched, full stick
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

var crouch := false            # crouched down (the button); pressed running, you slide into it
var slide_t := 0.0             # sliding: carried on by the run, slowing, no steering
var _slide_dir := Vector3.ZERO
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
	if sprint and crouch and slide_t <= 0.0:
		crouch = false           # (sprinting stands you up)
	if m.length() > 0.08:
		if crouch:
			spd = lerpf(0.9, CROUCH, clampf((m.length() - 0.3) / 0.7, 0.0, 1.0))
		else:
			spd = SPRINT if sprint else lerpf(WALK, RUN, clampf((m.length() - 0.5) / 0.5, 0.0, 1.0))
	var want := dir.normalized() * spd if spd > 0.0 else Vector3.ZERO
	if slide_t > 0.0:
		slide_t -= dt
		want = _slide_dir
	var grounded := is_on_floor()
	# a bit of weight: it takes a moment to get going and to stop (stopping's a little quicker)
	var cur := Vector3(velocity.x, 0, velocity.z)
	var acc := (9.0 if want.length() > cur.length() else 13.0) if grounded else 4.0
	if want.length() > 0.1 and cur.length() > 0.5 and want.normalized().dot(cur.normalized()) < 0.3:
		acc = 16.0       # (a hard change of direction digs in)
	if slide_t > 0.0:
		acc = 6.5        # (the slide: the run bleeds off along the ground)
	var hv := cur.move_toward(want, acc * dt)
	velocity.x = hv.x
	velocity.z = hv.z
	if grounded:
		# down hard after a long drop: a heavy landing (move to shrug it off); a long gun lands from any jump
		if _air > 0.75:
			avatar.play_once("land", 0.35, 0.9)
		elif _air > 0.25 and float(avatar.gun_def.get("fore", 0.0)) > 0.0:
			avatar.play_once("land", 0.3, 0.35)
		_air = 0.0
		if jump_req and crouch:
			crouch = false       # (jump from a crouch: you stand up first)
			jump_req = false
		if jump_req and slide_t <= 0.0:
			velocity.y = JUMP_V
			# up: the jump from its push-off (the clip for what's in your hands), held through the rise
			var kind := "" if avatar.gun_def.is_empty() else ("rifle" if float(avatar.gun_def.get("fore", 0.0)) > 0.0 else "pistol")
			match kind:
				"rifle":
					avatar.play_once("jump", 0.15, 0.38, 1.0, true)
				"pistol":
					avatar.play_once("jump", 0.0, 0.7, 1.15, true)
				_:
					avatar.play_once("jump", 0.0, 0.23, 1.0, true)
	else:
		_air += dt
		velocity.y -= GRAV * dt
	jump_req = false
	move_and_slide()
	# face where you're going (quickly, but not snapping)
	aiming = maxf(0.0, aiming - dt)
	if hv.length() > 0.4 and aiming <= 0.0 and slide_t <= 0.0:
		facing = lerp_angle(facing, atan2(-hv.x, -hv.z), 1.0 - exp(-dt * 7.5))
	avatar.rotation.y = facing + PI          # (the Kenney characters face +Z)
	# below the sea or fallen off the world: back up on land
	if global_position.y < -6.0:
		var p: Vector3 = global_position
		global_position = Vector3(p.x, island.height_at(p.x, p.z) + 1.0, p.z)
		velocity = Vector3.ZERO
	_animate(hv, grounded)

## Crouch (or stand back up). Running, you slide into it: down on one hip, carried on by the run.
func toggle_crouch() -> void:
	if scripted or down_t > 0.0 or slide_t > 0.0:
		return
	var hv := Vector3(velocity.x, 0, velocity.z)
	if not crouch and hv.length() > 3.6 and is_on_floor():
		slide_t = 0.85
		_slide_dir = hv.normalized() * 2.0
		facing = atan2(-hv.x, -hv.z)
		sprint = false
		avatar.play_once("slide", 0.05, 0.85, 1.0, true, 0.1)
	crouch = not crouch

func _animate(hv: Vector3, grounded: bool) -> void:
	avatar.crouch = crouch
	if avatar.lock_t > 0.0:
		# a one-off move playing (a landing): pushing the stick cuts it short (not a jump, not a slide)
		if move.length() > 0.35 and avatar.lock_t < 10.0 and not avatar.lock_hard:
			avatar.lock_t = 0.0
		else:
			return
	if not grounded and _air > 0.12:
		avatar.play("fall", 1.0, 0.2)      # (in the air: held; the jump's own clip played at the push-off)
		return
	# walking about: how fast and which way, in the character's own frame (strafing and backing up while you
	# face what you're shooting at)
	var fwd := Vector3(-sin(facing), 0, -cos(facing))
	var left := Vector3(-cos(facing), 0, sin(facing))
	var v := Vector2(hv.dot(left), hv.dot(fwd))
	avatar.locomote(v if v.length() > 0.15 else Vector2.ZERO)

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
