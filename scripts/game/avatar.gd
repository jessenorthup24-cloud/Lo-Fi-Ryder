extends Node3D
## A playable character: one of the Kenney Mini Characters (tools/chars/bake_chars.gd), rigged and animated,
## drawn with the game's toon material, at the same size as the people about the island. An accessory
## (glasses, shades, a mask) rides on the head bone.
## (The pack's medical mask is left out: it's an oxygen mask, not a look.)

const AimMod := preload("res://scripts/game/aim_mod.gd")
const RagdollRig := preload("res://scripts/game/ragdoll_rig.gd")
const Weapons := preload("res://scripts/game/weapons.gd")
const HAND := Vector3(-0.28, -0.01, 0.0)    # the middle of the right fist, on its arm bone
const SCALE := 2.3            # (the people's scale: models.gd K_PACK_SCALE["chars"])

## [id, name] for the character picker, in order
const CHARS := [["male-a", "Marcus"], ["male-b", "Dee"], ["male-c", "Jonah"], ["male-d", "Theo"], ["male-e", "Rico"],
	["male-f", "Sam"], ["male-g", "Kenji"], ["female-a", "Maya"], ["female-b", "Rosa"], ["female-c", "Ivy"],
	["female-d", "Nia"], ["female-e", "Lena"], ["female-f", "Jade"], ["soldier", "Sarge"], ["worker", "Bo"],
	["raider", "Raider"], ["robot", "Bolt"], ["alien", "Zib"], ["knight", "Sir Lance"], ["zombie", "Mort"]]
const ACCS := [["", "None"], ["glasses", "Glasses"], ["sunglasses", "Shades"]]
## where each sits from the head bone (in the model's own units): eyes, or over the mouth
const ACC_AT := {"glasses": Vector3(0, 0.125, 0.13), "sunglasses": Vector3(0, 0.135, 0.135)}

var anim: AnimationPlayer
var skel: Skeleton3D
var model: Node3D
var _now := ""
var aim: AimMod                # points the gun arm(s) at a target (aim_at)
var _aim_w := 0.0
var gun: MeshInstance3D        # the gun in the right fist (hold), turned onto what's aimed at
var gun_def: Dictionary = {}
var gun_extra := Basis()       # a turn on top of pointing at the target (the kick, a reload's tip)
var gun_nudge := Vector3.ZERO  # and a shove (back along the arm: the kick)
var limp: RagdollRig           # gone limp (dead): the ragdoll driving the bones

static func name_of(id: String) -> String:
	for c in CHARS:
		if c[0] == id:
			return c[1]
	return id

func setup(id: String, acc: String, mat: Material) -> void:
	for c in get_children():
		c.queue_free()
	var path := "res://assets/chars/%s.scn" % id
	if not ResourceLoader.exists(path):
		path = "res://assets/chars/male-a.scn"
	model = (load(path) as PackedScene).instantiate()
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	anim = aps[0] if aps.size() > 0 else null
	var sks := model.find_children("*", "Skeleton3D", true, false)
	skel = sks[0] if sks.size() > 0 else null
	_now = ""
	if skel:
		aim = AimMod.new()
		skel.add_child(aim)
	if acc != "" and skel and ResourceLoader.exists("res://assets/chars/acc_%s.res" % acc):
		var ba := BoneAttachment3D.new()
		ba.bone_name = "head"
		skel.add_child(ba)
		var am := MeshInstance3D.new()
		am.mesh = load("res://assets/chars/acc_%s.res" % acc)
		am.position = ACC_AT.get(acc, Vector3.ZERO)      # (they're made at the origin: onto the face)
		am.material_override = mat
		ba.add_child(am)
	play("idle")

## Play an animation (eased in from the last one), at a speed.
func play(n: String, speed := 1.0, blend := 0.15) -> void:
	if anim == null or not anim.has_animation(n) or (limp != null and n != "idle"):
		return
	if n != _now:
		anim.play(n, blend)
		_now = n
	anim.speed_scale = speed

## Aim the gun at a world point (INF: lower it). Eased, so the arm swings up rather than snapping.
func aim_at(p: Vector3, _both: bool, dt: float) -> void:
	if aim == null or limp != null:
		return
	var on := p != Vector3.INF
	_aim_w = move_toward(_aim_w, 1.0 if on else 0.0, dt * (9.0 if on else 4.0))
	if on:
		aim.target = p
	aim.weight = _aim_w
	if _aim_w <= 0.0:
		aim.target = Vector3.INF

func current() -> String:
	return _now

## A gun in the right fist (both hands on it when aiming). w: weapons.gd entry; {} for none.
func hold(w: Dictionary, look: int, mat: Material) -> void:
	if gun and is_instance_valid(gun):
		gun.get_parent().queue_free()
	gun = null
	gun_def = w
	if w.is_empty() or skel == null:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = "arm-right"
	skel.add_child(ba)
	gun = MeshInstance3D.new()
	gun.mesh = Weapons.mesh(w, look)
	gun.material_override = mat
	gun.transform = Weapons.hand_xf(w, gun.mesh, SCALE, HAND)
	ba.add_child(gun)
	if aim:
		aim.fore = float(w.get("fore", 0.0)) * gun.mesh.get_aabb().size.z * float(w["scale"]) / SCALE
		aim.shoulder = float(w.get("fore", 0.0)) > 0.0

## Knocked by a hit from direction d (world): the upper body jolts back.
func flinch(d: Vector3) -> void:
	if aim == null or skel == null:
		return
	var dl := (skel.global_transform.basis.inverse() * d).normalized()
	var ax := Vector3.UP.cross(dl)
	if ax.length() < 0.01:
		return
	aim.flinch_axis = ax.normalized()
	aim.flinch = 1.0

## Dead: limp, thrown at vel (and a push), the bodies made under `world` (an unscaled node).
func go_limp(world: Node3D, vel: Vector3, push: Vector3) -> void:
	if limp or skel == null:
		return
	# (an animation keeps playing underneath: the skeleton only runs its modifiers while something moves it)
	play("idle", 1.0, 0.0)
	if aim:
		aim.weight = 0.0
		aim.flinch = 0.0
	_aim_w = 0.0
	limp = RagdollRig.new()
	skel.add_child(limp)
	limp.start(skel, world, vel, push)
	# (the gun drops out of the hand: it'd only spin about on the arm)
	if gun:
		gun.visible = false

func _process(dt: float) -> void:
	if aim:
		aim.flinch = move_toward(aim.flinch, 0.0, dt * 3.5)
	if gun == null or limp != null:
		return
	# the gun: in the fist, turned to face where the arms point (blended in with them)
	var ba := gun.get_parent() as Node3D
	var t := aim.aim_point_local(skel) if aim else Vector3.INF
	var w: float = aim.weight if aim else 0.0
	var rest := Basis(Vector3.UP, PI * 0.5)
	if t == Vector3.INF or w <= 0.01 or not ba.is_inside_tree():
		gun.transform = Weapons.hand_xf(gun_def, gun.mesh, SCALE, HAND, rest * gun_extra)
		gun.position += gun_nudge
		return
	var tw := skel.global_transform * t
	var d := tw - ba.global_transform * HAND
	if d.length() < 0.05:
		return
	var gb := Basis.looking_at(d.normalized(), Vector3.UP) * gun_extra
	var lb := ba.global_transform.basis.orthonormalized().inverse() * gb
	var q := rest.get_rotation_quaternion().slerp(lb.orthonormalized().get_rotation_quaternion(), w)
	gun.transform = Weapons.hand_xf(gun_def, gun.mesh, SCALE, HAND, Basis(q))
	gun.position += gun_nudge
