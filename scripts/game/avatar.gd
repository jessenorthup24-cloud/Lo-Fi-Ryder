extends Node3D
## A playable character: one of the Kenney Mini Characters (tools/chars/bake_chars.gd), rigged and animated,
## drawn with the game's toon material, at the same size as the people about the island. An accessory
## (glasses, shades, a mask) rides on the head bone.
## (The pack's medical mask is left out: it's an oxygen mask, not a look.)

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
	if anim == null or not anim.has_animation(n):
		return
	if n != _now:
		anim.play(n, blend)
		_now = n
	anim.speed_scale = speed

func current() -> String:
	return _now
