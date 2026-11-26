extends Node3D
## A playable character (you, the officers, the one on the garage turntable): the Quaternius base character
## (tools/chars/bake_quaternius.gd: assets/chars/q_base.scn, its own clips and the Mixamo ones), drawn with
## the game's toon material. It's one plain figure: each outfit is painted onto it by body part (the bones
## each vertex hangs from: the head and hands skin, the chest and upper arms the top, the hips and legs the
## trousers, the feet the shoes). The game asks for a few moves (idle, walk, sprint, jump, fall, holding-both)
## and gets the right clip for what's in your hands: nothing, a pistol, or a long gun.

const AimMod := preload("res://scripts/game/aim_mod.gd")
const RagdollRig := preload("res://scripts/game/ragdoll_rig.gd")
const FootFix := preload("res://scripts/game/foot_fix.gd")
const Weapons := preload("res://scripts/game/weapons.gd")
const BASE := "res://assets/chars/q_base.scn"
const HEIGHT := 1.78           # metres, head to heel
const SCALE := 1.0             # (the old rig's scale: the avatar node itself isn't scaled now)

## [id, name, skin, top, trousers, shoes] for the character picker, in order
const CHARS := [
	["marcus", "Marcus", "8d5a3b", "e8e4d8", "2b3a55", "1c1c22"], ["dee", "Dee", "5b3a29", "ff4f8b", "1f1f26", "f2f0f7"],
	["jonah", "Jonah", "f0c8a0", "3d7a5a", "6b5a44", "3a2a20"], ["theo", "Theo", "c58c5c", "f5b041", "3b4a6b", "e8e4d8"],
	["rico", "Rico", "a8714a", "c0392b", "222228", "222228"], ["sam", "Sam", "e8b894", "4a6fa5", "c8b896", "6b4a2e"],
	["kenji", "Kenji", "f1cfa6", "1f1f26", "1f1f26", "ffffff"], ["maya", "Maya", "7a4a32", "9b59b6", "2c2c34", "f2f0f7"],
	["rosa", "Rosa", "d9a37a", "e74c3c", "f2f0f7", "c0392b"], ["ivy", "Ivy", "f3d2b3", "52b788", "3a3a44", "2a2a30"],
	["nia", "Nia", "4a2e20", "f9e79f", "5d6d7e", "f2f0f7"], ["lena", "Lena", "f5d6bc", "5dade2", "34495e", "ecf0f1"],
	["jade", "Jade", "e2b48c", "16a085", "1b2631", "16a085"], ["sarge", "Sarge", "b07a52", "556b2f", "4b5320", "2b2b20"],
	["bo", "Bo", "d8a47f", "f39c12", "2e4057", "5a3e2b"], ["raider", "Raider", "c49067", "7b241c", "17202a", "17202a"],
	["bolt", "Bolt", "b8c2cc", "5d6d7e", "34495e", "212f3d"], ["zib", "Zib", "7dcea0", "8e44ad", "4a235a", "1d8348"],
	["lance", "Sir Lance", "e0b08a", "aab7b8", "7f8c8d", "566573"], ["mort", "Mort", "9fb3a0", "6e5d4e", "4d4033", "2e2620"],
]
## the Kenney characters these took the place of, in the same order
const OLD_IDS := ["male-a", "male-b", "male-c", "male-d", "male-e", "male-f", "male-g", "female-a", "female-b", "female-c",
	"female-d", "female-e", "female-f", "soldier", "worker", "raider", "robot", "alien", "knight", "zombie"]
const COP := ["cop", "Officer", "c08a62", "1f2f57", "1a2240", "111115"]
const ACCS := [["", "None"]]

var anim: AnimationPlayer
var skel: Skeleton3D
var model: Node3D
var _now := ""
var aim: AimMod                # points the gun arm(s) at a target (aim_at)
var _feet: FootFix
var _aim_w := 0.0
var gun: MeshInstance3D        # the gun in the right fist (hold), turned onto what's aimed at
var gun_def: Dictionary = {}
var gun_extra := Basis()       # a turn on top of pointing at the target (the kick, a reload's tip)
var gun_nudge := Vector3.ZERO  # and a shove (back along the arm: the kick)
var limp: RagdollRig           # gone limp (dead): the ragdoll driving the bones
var sk_scale := 1.0            # world metres per skeleton unit (the rig's made tiny, then scaled up)
var hand := Vector3.ZERO       # the middle of the right fist, on its bone

static var _painted := {}      # outfit id -> the body mesh painted in it

static func name_of(id: String) -> String:
	for c in CHARS:
		if c[0] == id:
			return c[1]
	return CHARS[0][1]

static func _outfit(id: String) -> Array:
	if id == "cop":
		return COP
	for c in CHARS:
		if c[0] == id:
			return c
	var i := OLD_IDS.find(id)                     # (an old save's Kenney character: the one in its place)
	return CHARS[i] if i >= 0 else CHARS[absi(hash(id)) % CHARS.size()]

func setup(id: String, _acc: String, mat: Material) -> void:
	for c in get_children():
		c.queue_free()
	model = (load(BASE) as PackedScene).instantiate()
	add_child(model)
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	anim = aps[0] if aps.size() > 0 else null
	var sks := model.find_children("*", "Skeleton3D", true, false)
	skel = sks[0] if sks.size() > 0 else null
	_now = ""
	var of := _outfit(id)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.mesh = _paint(m, of)
		m.material_override = mat
	if skel:
		# stood up: the right height, feet on the ground, facing +Z (the way the game's characters face)
		var sg := _skel_xf()
		var head := sg * FootFix._rest_global(skel, skel.find_bone("Head_end")).origin
		var foot := sg * FootFix._rest_global(skel, skel.find_bone("Foot.L")).origin
		var toe := sg * FootFix._rest_global(skel, skel.find_bone("Foot.L_end")).origin
		var ground := minf(foot.y, toe.y)
		var h := maxf(head.y - ground, 0.01)
		var k := HEIGHT / h
		var tf := Vector3(toe.x - foot.x, 0, toe.z - foot.z)
		var turn := atan2(tf.x, tf.z) if tf.length() > 0.0001 else 0.0
		model.transform = Transform3D(Basis(Vector3.UP, -turn).scaled(Vector3.ONE * k), Vector3(0, -ground * k, 0))
		sk_scale = _skel_xf().basis.get_scale().x
		var fe := skel.find_bone("Fist.R_end")
		hand = skel.get_bone_rest(fe).origin * 0.5 if fe >= 0 else Vector3.ZERO
		aim = AimMod.new()
		skel.add_child(aim)
		_feet = FootFix.new()
		skel.add_child(_feet)
	play("idle")

## The skeleton's transform from this node (it needn't be in the tree yet).
func _skel_xf() -> Transform3D:
	var t := Transform3D()
	var n: Node = skel
	while n != null and n != self:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

## The body painted in an outfit, by which bone each vertex hangs from most (made once per outfit).
func _paint(mi: MeshInstance3D, of: Array) -> Mesh:
	var key := String(of[0]) + "|" + String(mi.name)
	if _painted.has(key):
		return _painted[key]
	var src: Mesh = mi.mesh
	var out := ArrayMesh.new()
	var region := {}
	if mi.skin and skel:
		for i in mi.skin.get_bind_count():
			var bn := String(mi.skin.get_bind_name(i))
			if bn == "":
				bn = skel.get_bone_name(mi.skin.get_bind_bone(i))
			region[i] = _region(bn)
	var cols := {"skin": Color(String(of[2])), "top": Color(String(of[3])), "legs": Color(String(of[4])), "shoes": Color(String(of[5]))}
	for si in src.get_surface_count():
		var a := src.surface_get_arrays(si)
		var vn: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var cc := PackedColorArray()
		cc.resize(vn)
		var bones = a[Mesh.ARRAY_BONES]
		var wts = a[Mesh.ARRAY_WEIGHTS]
		var per := 4
		if bones != null and vn > 0:
			per = (bones as PackedInt32Array).size() / vn
		var surf_col := Color.WHITE
		var mat := src.surface_get_material(si)
		if mat is BaseMaterial3D:
			surf_col = (mat as BaseMaterial3D).albedo_color
		var is_face := surf_col.get_luminance() > 0.6      # (the eyes and the mouth: as they are)
		for v in vn:
			var c := surf_col
			if not is_face and bones != null:
				var best := 0
				var bw := -1.0
				for k in per:
					var w: float = (wts as PackedFloat32Array)[v * per + k]
					if w > bw:
						bw = w
						best = (bones as PackedInt32Array)[v * per + k]
				c = cols.get(region.get(best, "top"), surf_col)
			cc[v] = Color(c.r, c.g, c.b, 0.7)
		a[Mesh.ARRAY_COLOR] = cc
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
	_painted[key] = out
	return out

static func _region(bone: String) -> String:
	if bone.begins_with("Head") or bone.begins_with("Neck") or bone.begins_with("Fist") or bone.begins_with("LowerArm"):
		return "skin"
	if bone.begins_with("Foot"):
		return "shoes"
	if bone.begins_with("Hips") or bone.begins_with("UpperLeg") or bone.begins_with("LowerLeg") or bone == "Body" or bone == "Bone":
		return "legs"
	return "top"

## The clip for a move, by what's in your hands.
func _clip(n: String) -> String:
	var kind := "" if gun_def.is_empty() else ("rifle" if float(gun_def.get("fore", 0.0)) > 0.0 else "pistol")
	var table := {
		"": {"idle": "q_idle", "walk": "loco_walking", "sprint": "loco_running", "jump": "loco_jump", "fall": "act_falling_idle",
			"land": "act_hard_landing", "holding-both": "q_idle", "punch": "q_punch", "hit": "q_recievehit", "die": "q_death",
			"sit": "x_sitting_idle", "drive": "x_driving", "enter_car": "x_entering_car", "exit_car": "x_exiting_car",
			"terrified": "x_terrified", "wave": "x_waving", "talk": "x_talking", "text": "x_texting_while_standing",
			"phone": "x_talking_phone_pacing", "lean": "x_leaning", "dance": "x_samba_dancing", "dance2": "x_gangnam_style",
			"hurt_idle": "hurt_injured_idle", "hurt_walk": "hurt_injured_walk", "hurt_run": "hurt_injured_run"},
		"pistol": {"idle": "x_pistol_idle", "walk": "pistol_walk", "sprint": "pistol_run", "jump": "pistol_jump",
			"holding-both": "x_pistol_aim_idle_1"},
		"rifle": {"idle": "rifle_idle", "walk": "rifle_walk_forward", "sprint": "rifle_run_forward", "jump": "rifle_jump_loop",
			"fall": "rifle_jump_loop", "holding-both": "rifle_idle_aiming", "die": "rifle_death_from_the_front"},
	}
	var t: Dictionary = table[kind]
	return String(t.get(n, table[""].get(n, n)))

## Play a move (eased in from the last one), at a speed.
func play(n: String, speed := 1.0, blend := 0.15) -> void:
	if anim == null or (limp != null and n != "idle"):
		return
	var c := _clip(n)
	if not anim.has_animation(c):
		return
	if c != _now:
		anim.play(c, blend)
		_now = c
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

## Where a point in the character's own space (metres: x to their left, y up, z ahead) is in the skeleton's
## space (for aiming at something that turns round with them: the garage turntable).
func local_point(v: Vector3) -> Vector3:
	return _skel_xf().affine_inverse() * v

func current() -> String:
	return _now

## A gun in the right fist (both hands on it when aiming). w: weapons.gd entry; {} for none.
func hold(w: Dictionary, look: int, mat: Material) -> void:
	if gun and is_instance_valid(gun):
		gun.get_parent().queue_free()
	gun = null
	gun_def = w
	_now = ""                    # (the clips change with what's in your hands)
	if w.is_empty() or skel == null:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = "Fist.R"
	skel.add_child(ba)
	gun = MeshInstance3D.new()
	gun.mesh = Weapons.mesh(w, look)
	gun.material_override = mat
	gun.transform = Weapons.hand_xf(w, gun.mesh, sk_scale, hand)
	ba.add_child(gun)
	if aim:
		aim.fore = float(w.get("fore", 0.0)) * gun.mesh.get_aabb().size.z * float(w["scale"]) / sk_scale
		aim.shoulder = float(w.get("fore", 0.0)) > 0.0

## Something carried on the back (the drill, the bag): put `n` on the chest bone, `back` metres behind the
## middle of the back and `up` metres up from it, at its own size.
func carry_on_back(n: Node3D, back: float, up: float) -> BoneAttachment3D:
	if skel == null:
		return null
	var ba := BoneAttachment3D.new()
	ba.bone_name = "Torso"
	skel.add_child(ba)
	var bi := skel.find_bone("Torso")
	var bw := _skel_xf() * skel.get_bone_global_pose(bi)       # the bone, in this node's space
	var want := Transform3D(n.transform.basis, Vector3(0, bw.origin.y + up, -back))
	n.transform = bw.affine_inverse() * want
	ba.add_child(n)
	return ba

## Knocked by a hit from direction d (world): the upper body jolts back.
func flinch(d: Vector3) -> void:
	if aim == null or skel == null:
		return
	var ax := Vector3.UP.cross(Vector3(d.x, 0, d.z).normalized())
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
	if _feet:
		skel.move_child(_feet, -1)       # (the feet onto the shins after the ragdoll's moved them)
	limp.start(skel, world, vel, push)
	# (the gun drops out of the hand: it'd only spin about on the arm)
	if gun:
		gun.visible = false

func _process(dt: float) -> void:
	if aim:
		aim.flinch = move_toward(aim.flinch, 0.0, dt * 3.5)
	if gun == null or limp != null:
		return
	# the gun: in the fist, turned to face where the arms point (blended in with them); lowered, it points
	# ahead and down
	var ba := gun.get_parent() as Node3D
	if not ba.is_inside_tree():
		return
	var t := aim.aim_point_local(skel) if aim else Vector3.INF
	var w: float = aim.weight if aim else 0.0
	var fwd := global_transform.basis.z.normalized()
	var low := Basis.looking_at((fwd + Vector3(0, -0.9, 0)).normalized(), Vector3.UP)
	var gb := low
	if t != Vector3.INF and w > 0.01:
		var d := skel.global_transform * t - ba.global_transform * hand
		if d.length() > 0.05:
			gb = Basis(low.get_rotation_quaternion().slerp(Basis.looking_at(d.normalized(), Vector3.UP).get_rotation_quaternion(), w))
	gb = gb * gun_extra
	var lb := ba.global_transform.basis.orthonormalized().inverse() * gb
	gun.transform = Weapons.hand_xf(gun_def, gun.mesh, sk_scale, hand, lb.orthonormalized())
	gun.position += gun_nudge
