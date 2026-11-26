extends Node3D
## A character (you, the officers, the people near you, the one on the garage turntable): one of the
## Blendpoly characters (tools/chars/bake_blendpoly.gd: assets/chars/bp/<id>.scn, a Mixamo skeleton), moved
## by the shared clips (assets/chars/bp_anims.res: the Mixamo clips, made on this same skeleton:
## tools/chars/bake_bp_clips.gd). Drawn with the game's toon material, each triangle coloured from one of the
## pack's twelve colour sheets. The game asks for a few
## moves (idle, walk, sprint, jump, fall, aim) and gets the right clip for what's in your hands.

const AimMod := preload("res://scripts/game/aim_mod.gd")
const RagdollRig := preload("res://scripts/game/ragdoll_rig.gd")
const Weapons := preload("res://scripts/game/weapons.gd")
const DIR := "res://assets/chars/bp/"
const ANIMS := "res://assets/chars/bp_anims.res"
const HEIGHT := 1.8            # metres, head to heel
const SCALE := 1.0
## each gun's real length, metres (the models are made to all sorts of sizes)
const GUN_LEN := {"pistol": 0.21, "revolver": 0.28, "smg": 0.5, "shotgun": 1.0, "rifle": 0.88, "sniper": 1.15}

## [id, name] for the character picker; each wears one of the pack's twelve colour sheets (SKINS). An id
## can name the sheet too: "male_casual1@02_B" (the people about the island are dealt them at random).
const CHARS := [
	["male_casual1", "Marcus"], ["women_casual2", "Dee"], ["male_hoodie", "Jonah"], ["male_t_shirt", "Theo"],
	["male_jacket", "Rico"], ["male_casual2", "Sam"], ["woman_casual1", "Maya"], ["woman_casual3", "Rosa"],
	["women_coat", "Ivy"], ["businessman_suit", "Victor"], ["businessman_shirt", "Kenji"], ["businesswoman", "Lena"],
	["male_beach", "Bo"], ["women_beach", "Jade"], ["man_fitness", "Rex"], ["women_fitness", "Nia"],
	["male_constructor", "Hank"], ["factoryman", "Sarge"], ["male_engineer", "Otis"], ["male_fireman", "Flint"],
	["male_doctor", "Dr. Amos"], ["women_doctor", "Dr. Ana"], ["male_teacher", "Mr. Gray"], ["women_teacher", "Ms. Bloom"],
	["male_waiter1", "Luca"], ["male_waiter2", "Pip"], ["woman_waiter1", "Bea"], ["woman_waiter2", "Cleo"],
	["male_greengrocer", "Gus"], ["women_greengrocer", "Flo"], ["male_prisoner", "Rook"], ["women_prisoner", "Kat"],
]
const SKINS := ["01_A", "01_B", "01_C", "02_A", "02_B", "02_C", "03_A", "03_B", "03_C", "04_A", "04_B", "04_C"]
## the characters older saves had picked, in the order these took their places
const OLD_IDS := ["marcus", "dee", "jonah", "theo", "rico", "sam", "kenji", "maya", "rosa", "ivy", "nia", "lena", "jade",
	"sarge", "bo", "raider", "bolt", "zib", "lance", "mort", "male-a", "male-b", "male-c", "male-d", "male-e", "male-f", "male-g",
	"female-a", "female-b", "female-c", "female-d", "female-e", "female-f", "soldier", "worker", "raider", "robot", "alien", "knight", "zombie"]
const ACCS := [["", "None"]]

var anim: AnimationTree        # the moves (_build_tree): the walking about blended, the other clips mixed over it
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
var sk_scale := 1.0            # world metres per skeleton unit (the rig's made tiny, then scaled up)
var hand := Vector3.ZERO       # the middle of the right fist, on its bone

static var _painted := {}      # outfit id -> the body mesh painted in it

static func name_of(id: String) -> String:
	id = id.get_slice("@", 0)
	for c in CHARS:
		if c[0] == id:
			return c[1]
	return CHARS[0][1]

## [model, sheet] for an id ("cop" / "cop_f": the police; an older save's id: the one in its place).
static func _outfit(id: String) -> Array:
	var skin := "01_A"
	if "@" in id:
		skin = id.get_slice("@", 1)
		id = id.get_slice("@", 0)
	if id == "cop":
		return ["male_police", skin]
	if id == "cop_f":
		return ["women_police", skin]
	for c in CHARS:
		if c[0] == id:
			return [id, skin]
	var i := OLD_IDS.find(id)
	if i >= 20:
		i -= 20                  # (the Kenney ones sat in the same order as the Quaternius ones)
	return [CHARS[(i if i >= 0 else absi(hash(id))) % CHARS.size()][0], skin]

static var _skins := {}
static func _skin(key: String) -> Image:
	if not _skins.has(key):
		var path := "res://assets/chars/bp/skin_%s.res" % key
		_skins[key] = load(path) if ResourceLoader.exists(path) else null
	return _skins[key]

func setup(id: String, _acc: String, mat: Material) -> void:
	for c in get_children():
		c.queue_free()
	var of := _outfit(id)
	model = (load(DIR + String(of[0]) + ".scn") as PackedScene).instantiate()
	add_child(model)
	var sks := model.find_children("*", "Skeleton3D", true, false)
	skel = sks[0] if sks.size() > 0 else null
	_build_tree()
	_now = ""
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.mesh = _paint(m, of)
		m.material_override = mat
	if skel:
		# the right height, feet on the ground (they're made facing +Z, as the game's characters face)
		var sg := _skel_xf()
		var head := sg * skel.get_bone_global_rest(skel.find_bone("HeadTop_End")).origin
		var toe := sg * skel.get_bone_global_rest(skel.find_bone("LeftToe_End")).origin
		var foot := sg * skel.get_bone_global_rest(skel.find_bone("LeftFoot")).origin
		var ground := minf(toe.y, foot.y - 0.08)
		var k := HEIGHT / maxf(head.y - ground, 0.01)
		model.transform = Transform3D(Basis().scaled(Vector3.ONE * k), Vector3(0, -ground * k, 0))
		sk_scale = _skel_xf().basis.get_scale().x
		var mid := skel.find_bone("RightHandMiddle1")
		hand = skel.get_bone_rest(mid).origin * 0.55 if mid >= 0 else Vector3.ZERO
		aim = AimMod.new()
		skel.add_child(aim)
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

## The body in its colours: each triangle the colour of its sheet under the middle of its UVs (the sheets
## are flat swatches), its corners its own (no colours smudging along the seams). Made once per model and sheet.
func _paint(mi: MeshInstance3D, of: Array) -> Mesh:
	var key := String(of[0]) + "|" + String(of[1])
	if _painted.has(key):
		return _painted[key]
	var src: Mesh = mi.mesh
	var img := _skin(String(of[1]))
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var a := src.surface_get_arrays(si)
		var vn: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var per := 4
		if a[Mesh.ARRAY_BONES] != null and vn > 0:
			per = (a[Mesh.ARRAY_BONES] as PackedInt32Array).size() / vn
		var uv = a[Mesh.ARRAY_TEX_UV]
		var idx := PackedInt32Array()
		if a[Mesh.ARRAY_INDEX] != null and (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
			idx = a[Mesh.ARRAY_INDEX]
		else:
			for v in vn:
				idx.append(v)
		var out_a := []
		out_a.resize(Mesh.ARRAY_MAX)
		for at in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			if a[at] == null:
				continue
			var srcv = a[at]
			var w := per if at in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS] else 1
			var dst = srcv.duplicate()
			dst.resize(idx.size() * w)
			for q in idx.size():
				for c in w:
					dst[q * w + c] = srcv[idx[q] * w + c]
			out_a[at] = dst
		var cc := PackedColorArray()
		cc.resize(idx.size())
		for q in range(0, idx.size(), 3):
			var col := Color(0.8, 0.8, 0.8)
			if img and uv != null:
				var u: Vector2 = ((uv as PackedVector2Array)[idx[q]] + (uv as PackedVector2Array)[idx[q + 1]] + (uv as PackedVector2Array)[idx[q + 2]]) / 3.0
				col = img.get_pixel(clampi(int(u.x * 1024.0), 0, img.get_width() - 1), clampi(int(u.y * 1024.0), 0, img.get_height() - 1))
			for e in 3:
				cc[q + e] = Color(col.r, col.g, col.b, 0.7)
		out_a[Mesh.ARRAY_COLOR] = cc
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_a, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
	_painted[key] = out
	return out

static func _region(bone: String) -> String:
	if bone.begins_with("Head") or bone == "Neck" or bone.contains("Hand") or bone.contains("ForeArm"):
		return "skin"
	if bone.contains("Foot") or bone.contains("Toe"):
		return "shoes"
	if bone == "Hips" or bone.contains("UpLeg") or bone.ends_with("Leg"):
		return "legs"
	return "top"

## The clip for a move, by what's in your hands.
func _clip(n: String) -> String:
	var kind := "" if gun_def.is_empty() else ("rifle" if float(gun_def.get("fore", 0.0)) > 0.0 else "pistol")
	var table := {
		"": {"idle": "act_idle", "walk": "act_walking", "sprint": "act_running", "jump": "act_jumping_up", "fall": "act_falling_idle",
			"land": "act_hard_landing", "holding-both": "act_idle", "die": "rifle_death_from_the_front", "get_up": "act_cover_to_stand",
			"sit": "x_sitting", "sit_down": "x_stand_to_sit", "stand_up": "x_sit_to_stand", "cheer_sit": "x_cheering_while_sitting",
			"drive": "x_driving", "enter_car": "x_entering_car", "exit_car": "x_exiting_car", "slide": "x_running_slide",
			"terrified": "x_terrified", "wave": "x_waving", "talk": "x_talking", "text": "x_texting_while_standing",
			"text_walk": "x_walking_while_texting", "phone": "x_talking", "lean": "x_leaning", "dance": "dance_breakdance_footwork_1",
			"dance2": "dance_breakdance_uprock", "kneel": "pistol_kneeling_idle", "shrug": "gest_weight_shift",
			"idle2": "act_idle_2", "idle3": "act_idle_3", "idle4": "act_idle_4", "idle5": "act_idle_5",
			"hurt_idle": "hurt_injured_idle", "hurt_walk": "hurt_injured_walk", "hurt_run": "hurt_injured_run"},
		"pistol": {"idle": "pistol_idle", "walk": "pistol_walk", "sprint": "pistol_run", "jump": "pistol_jump_2",
			"holding-both": "pistol_idle"},
		"rifle": {"idle": "rifle_idle", "walk": "rifle_walk_forward", "sprint": "rifle_run_forward", "jump": "rifle_jump_up",
			"fall": "rifle_jump_loop", "land": "rifle_jump_down", "holding-both": "rifle_idle_aiming", "die": "rifle_death_from_the_front"},
	}
	var t: Dictionary = table[kind]
	return String(t.get(n, table[""].get(n, n)))

## ------------------------------------------------------------------ the moves
## An AnimationTree. Walking about is a blend space for what's in your hands (u: nothing, p: a pistol,
## r: a long gun; "uc", "pc", "rc" crouched), placed by how fast and which way you're going: the clips at the
## speeds they're made to go (so the feet don't slide), forwards, back and to the sides blended between, and
## a Transition crossfading between the spaces (drawing a gun, crouching). Any other clip (sitting, a jump, a
## wave) goes into one of two slots, crossfaded between, mixed in over the walking: everything eases.
## [clip, x (to the left), y (ahead)] in m/s, the speed each clip's made to travel at (its hips, in the
## download); the first three: stood, walking ahead, running ahead.
const SPACE_PTS := {
	"u": [["act_idle", 0, 0], ["act_walking", 0, 1.65], ["act_running", 0, 4.39], ["act_walking", 1.65, 0],
		["act_walking", -1.65, 0], ["act_walking", 0, -1.65], ["act_running", 4.39, 0], ["act_running", -4.39, 0],
		["act_running", 0, -4.39]],
	"p": [["pistol_idle", 0, 0], ["pistol_walk", 0, 2.47], ["pistol_run", 0, 4.6], ["pistol_walk_backward", 0, -1.27],
		["pistol_run_backward", 0, -3.19], ["pistol_strafe", 2.08, 0], ["pistol_strafe_2", -2.22, 0],
		["pistol_walk_arc", -0.5, 2.36], ["pistol_walk_arc_2", 0.59, 2.38], ["pistol_run_arc", -0.88, 3.16],
		["pistol_run_arc_2", 1.04, 2.96], ["pistol_walk_backward_arc_2", -0.67, -1.56], ["pistol_run_backward_arc_2", -0.39, -2.57]],
	"r": [["rifle_idle", 0, 0], ["rifle_walk_forward", 0, 1.79], ["rifle_run_forward", 0, 4.47],
		["rifle_walk_forward_left", 1.26, 1.26], ["rifle_walk_left", 1.79, 0], ["rifle_walk_backward_left", 1.26, -1.26],
		["rifle_walk_backward", 0, -1.73], ["rifle_walk_backward_right", -1.23, -1.23], ["rifle_walk_right", -1.79, 0],
		["rifle_walk_forward_right", -1.26, 1.26], ["rifle_run_forward_left", 3.16, 3.16], ["rifle_run_left", 4.47, 0],
		["rifle_run_backward_left", 3.16, -3.16], ["rifle_run_backward", 0, -4.47], ["rifle_run_backward_right", -2.98, -2.98],
		["rifle_run_right", -4.47, 0], ["rifle_run_forward_right", -3.16, 3.16], ["rifle_sprint_forward", 0, 6.7],
		["rifle_sprint_forward_left", 4.74, 4.74], ["rifle_sprint_forward_right", -4.74, 4.74]],
	"rc": [["rifle_idle_crouching", 0, 0], ["rifle_walk_crouching_forward", 0, 1.9], ["rifle_walk_crouching_forward", 0, 1.9],
		["rifle_walk_crouching_forward_left", 1.34, 1.34], ["rifle_walk_crouching_left", 1.9, 0],
		["rifle_walk_crouching_backward_left", 1.34, -1.34], ["rifle_walk_crouching_backward", 0, -1.9],
		["rifle_walk_crouching_backward_right", -1.3, -1.3], ["rifle_walk_crouching_right", -1.9, 0],
		["rifle_walk_crouching_forward_right", -1.29, 1.3]],
}
const SPACE_KEYS := ["u", "p", "r", "uc", "pc", "rc", "ra", "rca"]     # (ra, rca: a long gun up, aimed: stood still, it's held to the eye)
const LOCO := ["idle", "walk", "sprint", "holding-both"]
static var _spaces := {}       # key -> [AnimationNodeBlendSpace2D, its outline (convex, closed), walk y, run y]
static var _lib: AnimationLibrary
var _bt: AnimationNodeBlendTree
var crouch := false            # crouched (onfoot sets it)
var _key := "u"
var _loco_v := Vector2.ZERO    # where the walking's placed (m/s: x to the left, y ahead)
var _loco_ts := 1.0
var _bp := Vector2.ZERO        # (eased toward it)
var _act := 0.0                # the slots over the walking: 0..1, eased toward _act_to
var _act_to := 0.0
var _act_rate := 4.0
var _ab := 0.0                 # slot A (0) to slot B (1)
var _ab_to := 0.0
var _ab_rate := 4.0
var _slot := ["", ""]

## The crouched clips for no gun and a pistol: the long gun's crouch with the arms from standing with nothing
## (hanging) or with the pistol (held low), as there are no crouching clips made for those.
static func _compose(lib: AnimationLibrary) -> void:
	for kv in [["uc", "act_idle"], ["pc", "pistol_idle"]]:
		var src: Animation = lib.get_animation(String(kv[1]))
		for e in SPACE_PTS["rc"]:
			var nm := String(kv[0]) + "_" + String(e[0])
			if lib.has_animation(nm):
				continue
			var a: Animation = (lib.get_animation(String(e[0])) as Animation).duplicate()
			for t in range(a.get_track_count() - 1, -1, -1):
				var b := String(a.track_get_path(t)).get_slice(":", 1)
				if "Arm" in b or "Hand" in b or "Shoulder" in b:
					a.remove_track(t)
			for t in src.get_track_count():
				var b := String(src.track_get_path(t)).get_slice(":", 1)
				if not ("Arm" in b or "Hand" in b or "Shoulder" in b):
					continue
				var nt := a.add_track(src.track_get_type(t))
				a.track_set_path(nt, src.track_get_path(t))
				a.track_set_interpolation_type(nt, src.track_get_interpolation_type(t))
				for k in src.track_get_key_count(t):
					var kt := src.track_get_key_time(t, k)
					if kt <= a.length + 0.001:
						a.track_insert_key(nt, kt, src.track_get_key_value(t, k))
			lib.add_animation(nm, a)

static func _make_spaces() -> void:
	_lib = load(ANIMS)
	_compose(_lib)
	for key in SPACE_KEYS:
		var pts: Array = SPACE_PTS[key] if SPACE_PTS.has(key) else SPACE_PTS["rc"]
		var pre: String = "" if SPACE_PTS.has(key) else key + "_"
		if key == "ra" or key == "rca":
			pts = (SPACE_PTS["r" if key == "ra" else "rc"] as Array).duplicate()
			pts[0] = ["rifle_idle_aiming" if key == "ra" else "rifle_idle_crouching_aiming", 0, 0]
			pre = ""
		var bs := AnimationNodeBlendSpace2D.new()
		bs.min_space = Vector2(-8, -8)
		bs.max_space = Vector2(8, 8)
		bs.sync = false          # (the clips not in the blend wait: only the two or three in it are worked out)
		var seen := {}
		var cloud := PackedVector2Array()
		for e in pts:
			var p := Vector2(float(e[1]), float(e[2]))
			if seen.has(p):
				continue
			seen[p] = true
			var an := AnimationNodeAnimation.new()
			an.animation = pre + String(e[0])
			bs.add_blend_point(an, p)
			cloud.append(p)
		_spaces[key] = [bs, Geometry2D.convex_hull(cloud), float(pts[1][2]), float(pts[2][2])]

## How far out the outline is that way (beyond it a clip just plays faster).
static func _reach(hull: PackedVector2Array, d: Vector2) -> float:
	var far := d.normalized() * 100.0
	var best := 0.0
	for i in hull.size() - 1:
		var p = Geometry2D.segment_intersects_segment(Vector2.ZERO, far, hull[i], hull[i + 1])
		if p != null:
			best = maxf(best, (p as Vector2).length())
	return best

func _build_tree() -> void:
	if _spaces.is_empty():
		_make_spaces()
	anim = AnimationTree.new()
	anim.name = "Anim"
	model.add_child(anim)
	anim.root_node = anim.get_path_to(model)
	anim.add_animation_library("", _lib)
	_bt = AnimationNodeBlendTree.new()
	var tr := AnimationNodeTransition.new()
	tr.xfade_time = 0.3
	tr.xfade_curve = _ease_curve()
	tr.input_count = SPACE_KEYS.size()
	for i in SPACE_KEYS.size():
		tr.set_input_name(i, SPACE_KEYS[i])
	_bt.add_node("loco", tr)
	for i in SPACE_KEYS.size():
		_bt.add_node("s_" + SPACE_KEYS[i], _spaces[SPACE_KEYS[i]][0])
		_bt.connect_node("loco", i, "s_" + SPACE_KEYS[i])
	_bt.add_node("loco_ts", AnimationNodeTimeScale.new())
	_bt.connect_node("loco_ts", 0, "loco")
	for sl in ["a", "b"]:
		var an := AnimationNodeAnimation.new()
		an.animation = "act_idle"
		_bt.add_node(sl, an)
		_bt.add_node(sl + "_seek", AnimationNodeTimeSeek.new())
		_bt.connect_node(sl + "_seek", 0, sl)
		_bt.add_node(sl + "_ts", AnimationNodeTimeScale.new())
		_bt.connect_node(sl + "_ts", 0, sl + "_seek")
	_bt.add_node("ab", AnimationNodeBlend2.new())
	_bt.connect_node("ab", 0, "a_ts")
	_bt.connect_node("ab", 1, "b_ts")
	_bt.add_node("mix", AnimationNodeBlend2.new())
	_bt.connect_node("mix", 0, "loco_ts")
	_bt.connect_node("mix", 1, "ab")
	_bt.connect_node("output", 0, "mix")
	anim.tree_root = _bt
	anim.active = true
	_key = "u"
	_act = 0.0
	_act_to = 0.0
	_slot = ["", ""]

static var _curve: Curve
static func _ease_curve() -> Curve:
	if _curve == null:
		_curve = Curve.new()
		_curve.add_point(Vector2(0, 0), 0, 0)
		_curve.add_point(Vector2(1, 1), 0, 0)
	return _curve

var _aim_pose_t := 0.0         # (asked for "holding-both" lately: a long gun's held up to the eye)
func _kind_key() -> String:
	var k := "u" if gun_def.is_empty() else ("r" if float(gun_def.get("fore", 0.0)) > 0.0 else "p")
	k += "c" if crouch else ""
	if k.begins_with("r") and _aim_pose_t > 0.0:
		k += "a"
	return k

## Walking about, as you're actually going: v in m/s in the character's own frame (x to their left, y ahead).
func locomote(v: Vector2, blend := 0.25) -> void:
	if anim == null or lock_t > 0.0 or (limp != null):
		return
	_loco_v = v
	_loco_ts = 1.0
	_to_loco(blend)
	_now = "loco"

func _to_loco(blend: float) -> void:
	if _act_to != 0.0:
		_act_to = 0.0
		_act_rate = 1.0 / maxf(blend, 0.05)

## A clip into a slot (crossfaded from what's playing): `from` seconds in (-1: carry on if it's already on).
func _act_in(c: String, blend: float, from: float, speed: float) -> void:
	var cur := 1 if _ab_to > 0.5 else 0
	var sl := ["a", "b"]
	if from < 0.0 and _act_to > 0.5 and _slot[cur] == c:
		anim.set("parameters/%s_ts/scale" % sl[cur], speed)
		return
	var n := cur if _act <= 0.01 else 1 - cur
	(_bt.get_node(sl[n]) as AnimationNodeAnimation).animation = c
	anim.set("parameters/%s_seek/seek_request" % sl[n], maxf(from, 0.0))
	anim.set("parameters/%s_ts/scale" % sl[n], speed)
	_slot[n] = c
	_ab_to = float(n)
	_ab_rate = 1.0 / maxf(blend, 0.05)
	if _act <= 0.01:
		_ab = _ab_to
	_act_to = 1.0
	_act_rate = 1.0 / maxf(blend, 0.05)

func _anim_tick(dt: float) -> void:
	if anim == null:
		return
	_aim_pose_t = maxf(0.0, _aim_pose_t - dt)
	_act = move_toward(_act, _act_to, dt * _act_rate)
	_ab = move_toward(_ab, _ab_to, dt * _ab_rate)
	anim.set("parameters/mix/blend_amount", smoothstep(0.0, 1.0, _act))
	anim.set("parameters/ab/blend_amount", smoothstep(0.0, 1.0, _ab))
	var key := _kind_key()
	if key != _key:
		_key = key
		anim.set("parameters/loco/transition_request", key)
	var sp: Array = _spaces[key]
	var v := _loco_v
	var ts := _loco_ts
	if v.length() > 0.01:
		var r := _reach(sp[1], v)
		if r > 0.01 and v.length() > r:
			ts *= v.length() / r
			v *= r / v.length()
	_bp = _bp.lerp(v, 1.0 - exp(-dt * 9.0))
	anim.set("parameters/s_%s/blend_position" % key, _bp)
	anim.set("parameters/loco_ts/scale", ts)

## A move played once (getting up, landing hard, a jump), from `from` seconds in, for `dur` seconds
## (to its end if dur < 0): the ordinary moves wait till it's done (or till `lock_t` is cleared).
var lock_t := 0.0
var lock_hard := false        # (a jump: moving doesn't cut it short)
func play_once(n: String, from := 0.0, dur := -1.0, speed := 1.0, hard := false, blend := 0.15) -> void:
	lock_hard = hard
	var c := _clip(n)
	if anim == null or limp != null or not anim.has_animation(c):
		return
	_act_in(c, blend, from, speed)
	_now = c
	lock_t = dur if dur > 0.0 else (anim.get_animation(c).length - from) / speed

## Play a move (eased in from the last one), at a speed. The walking ones (idle, walk, sprint) go to the
## blend space, straight ahead at that clip's own pace (the people about: onfoot uses locomote).
func play(n: String, speed := 1.0, blend := 0.28) -> void:
	if anim == null or (limp != null and n != "idle") or lock_t > 0.0:
		return
	if n in LOCO:
		if n == "holding-both":
			_aim_pose_t = 0.25
		var sp: Array = _spaces[_kind_key()]
		_loco_v = Vector2(0, 0.0 if n == "idle" or n == "holding-both" else (float(sp[2]) if n == "walk" else float(sp[3])))
		_loco_ts = speed
		_to_loco(blend)
		_now = _clip(n)
		return
	var c := _clip(n)
	if not anim.has_animation(c):
		return
	_act_in(c, blend, -1.0, speed)
	_now = c

## Aim the gun at a world point (INF: lower it). Eased, so the arm swings up rather than snapping.
func aim_at(p: Vector3, _both: bool, dt: float) -> void:
	if aim == null or limp != null:
		return
	var on := p != Vector3.INF
	_aim_w = move_toward(_aim_w, 1.0 if on else 0.0, dt * (9.0 if on else 4.0))
	if on:
		aim.target = p
	aim.weight = smoothstep(0.0, 1.0, _aim_w)     # (eased in and out: the arms come up and settle)
	if _aim_w <= 0.0:
		aim.target = Vector3.INF

## Where a point in the character's own space (metres: x to their left, y up, z ahead) is in the skeleton's
## space (for aiming at something that turns round with them: the garage turntable).
func local_point(v: Vector3) -> Vector3:
	return _skel_xf().affine_inverse() * v

func current() -> String:
	return _now

## The scale to hand Weapons.hand_xf so the gun comes out its real length in this hand.
func _gun_cs(w: Dictionary, m: Mesh) -> float:
	var ln := maxf(m.get_aabb().size.z, 0.001)
	var world := float(GUN_LEN.get(String(w.get("id", "")), 0.3)) / ln
	return float(w["scale"]) * sk_scale / world

## Where the left hand holds a long gun: along from the muzzle (a fraction of its length) to the handguard,
## the middle of the fist just under it. In the gun model's own space; INF for a one-handed gun.
const FORE_AT := {"smg": 0.22, "shotgun": 0.27, "rifle": 0.33, "sniper": 0.46}
static var _fore_cache := {}
func _fore_pt(w: Dictionary, m: Mesh) -> Vector3:
	var id := String(w.get("id", ""))
	if not FORE_AT.has(id) or m == null:
		return Vector3.INF
	if _fore_cache.has(m):
		return _fore_cache[m]
	var ab := m.get_aabb()
	var z := ab.position.z + ab.size.z * float(FORE_AT[id])
	var half := ab.size.z * 0.03
	var lo := INF
	var cx := 0.0
	var n := 0
	for si in m.get_surface_count():
		for v in (m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if absf(v.z - z) < half:
				lo = minf(lo, v.y)
				cx += v.x
				n += 1
	if n == 0:
		lo = 0.0
	var per_m := ab.size.z / float(GUN_LEN.get(id, 0.9))     # (model units a metre)
	var p := Vector3(cx / maxf(n, 1), lo - 0.03 * per_m, z)
	_fore_cache[m] = p
	return p

## A gun in the right fist (both hands on it when aiming). w: weapons.gd entry; {} for none.
func hold(w: Dictionary, look: int, mat: Material) -> void:
	if gun and is_instance_valid(gun):
		gun.get_parent().queue_free()
	gun = null
	gun_def = w
	if aim:
		aim.fore_pt = Vector3.INF
		aim.support = 0.0
	_now = ""                    # (the clips change with what's in your hands)
	if w.is_empty() or skel == null:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = "RightHand"
	skel.add_child(ba)
	gun = MeshInstance3D.new()
	gun.mesh = Weapons.mesh(w, look)
	gun.material_override = mat
	gun.transform = Weapons.hand_xf(w, gun.mesh, _gun_cs(w, gun.mesh), hand)
	ba.add_child(gun)
	if aim:
		aim.fore = float(w.get("fore", 0.0)) * float(GUN_LEN.get(String(w["id"]), 0.3)) / sk_scale
		aim.shoulder = float(w.get("fore", 0.0)) > 0.0
		aim.fore_pt = _fore_pt(w, gun.mesh)

## Something carried on the back (the drill, the bag): put `n` on the chest bone, `back` metres behind the
## middle of the back and `up` metres up from it, at its own size.
func carry_on_back(n: Node3D, back: float, up: float) -> BoneAttachment3D:
	if skel == null:
		return null
	var ba := BoneAttachment3D.new()
	ba.bone_name = "Spine2"
	skel.add_child(ba)
	var bi := skel.find_bone("Spine2")
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
	lock_t = 0.0
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

## The way the gun lies in the hands as the clip holds them (world).
func _held_basis() -> Basis:
	var sg := skel.global_transform
	var rh := sg * skel.get_bone_global_pose(skel.find_bone("RightHand")).origin
	var up := Vector3.UP
	var dir: Vector3
	if float(gun_def.get("fore", 0.0)) > 0.0:
		dir = sg * skel.get_bone_global_pose(skel.find_bone("LeftHand")).origin - rh
	else:
		# (a pistol: the barrel along the back of the hand, wrist to knuckles; the slide's top on the index
		# finger's side of the fist, the grip down through the curled fingers)
		var mid := sg * skel.get_bone_global_pose(skel.find_bone("RightHandMiddle1")).origin
		dir = mid - rh
		# (across the knuckles, index side up; some of the characters have fewer finger bones)
		var ib := skel.find_bone("RightHandIndex1")
		var pb := skel.find_bone("RightHandPinky1")
		if pb < 0:
			pb = skel.find_bone("RightHandRing1")
		if pb < 0:
			pb = skel.find_bone("RightHandMiddle1")
		if ib >= 0 and pb >= 0 and ib != pb:
			up = sg * skel.get_bone_global_pose(ib).origin - sg * skel.get_bone_global_pose(pb).origin
		up = (up - dir.normalized() * up.dot(dir.normalized()))
		if up.length() < 0.001:
			up = Vector3.UP
	if dir.length() < 0.02:
		dir = global_transform.basis.z
	return Basis.looking_at(dir.normalized(), up.normalized())

## Back from limp (knocked down, not dead): the ragdoll gone, the bones back to the animation, the gun back.
func recover() -> void:
	if limp == null:
		return
	limp.queue_free()          # (its bodies go with it)
	limp = null
	if gun:
		gun.visible = true
	_now = ""

func _process(dt: float) -> void:
	lock_t = maxf(0.0, lock_t - dt)
	_anim_tick(dt)
	if aim and is_inside_tree():
		aim.facing = global_transform.basis.z
	if aim:
		aim.flinch = move_toward(aim.flinch, 0.0, dt * 3.5)
	if gun == null or limp != null:
		if aim:
			aim.support = 0.0
		return
	# (put away while a one-off move plays: getting in or out, a landing)
	gun.visible = lock_t <= 0.0
	if aim:
		aim.support = move_toward(aim.support, 1.0 if gun.visible and aim.fore_pt != Vector3.INF else 0.0, dt * 6.0)
	# the gun: in the fist, turned to face where the arms point (blended in with them); lowered, it points
	# ahead and down
	var ba := gun.get_parent() as Node3D
	if not ba.is_inside_tree():
		return
	var t := aim.aim_point_local(skel) if aim else Vector3.INF
	var w: float = aim.weight if aim else 0.0
	# lowered: the gun lies in the hands the clip has it in (a long gun from the right hand to the left on its
	# fore-end; a pistol along the hand); aimed, it points at the target (blended between)
	var low := _held_basis()
	var gb := low
	if t != Vector3.INF and w > 0.01:
		var d := skel.global_transform * t - ba.global_transform * hand
		if d.length() > 0.05:
			gb = Basis(low.get_rotation_quaternion().slerp(Basis.looking_at(d.normalized(), Vector3.UP).get_rotation_quaternion(), w))
	gb = gb * gun_extra
	var lb := ba.global_transform.basis.orthonormalized().inverse() * gb
	gun.transform = Weapons.hand_xf(gun_def, gun.mesh, _gun_cs(gun_def, gun.mesh), hand, lb.orthonormalized())
	if aim:
		aim.gun_xf = gun.transform
	# the kick: gun_nudge.x metres straight back along the barrel (in the bone's own, scaled, space)
	if gun_nudge.x != 0.0:
		gun.position += ba.global_transform.basis.inverse() * (gb.orthonormalized() * Vector3(0, 0, gun_nudge.x))
