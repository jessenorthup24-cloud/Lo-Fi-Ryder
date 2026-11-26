extends RefCounted
## The guns: six kinds, each with a few looks to pick from (the PIXEL ARSENAL presets, which ship only in
## the built game from the private assets repo: see tools/guns/bake_guns.gd). Without that pack (a local
## checkout, a build without the ASSETS_TOKEN secret) each kind falls back to a plain blocky gun.

const MB := preload("res://scripts/core/mesh_builder.gd")
const DIR := "res://assets/guns/"

## id: name, price, damage a hit, shots a second, magazine, reload (s), spread (rad), pellets, range (m),
## auto (hold to fire), two-handed, sound, how big it's held (scale: these are chunky toy-like people, so
## the guns are bigger than life too), looks (presets; the first is free); grip: where the right hand holds
## it, from the model's origin (y up, z back; as a share of the gun's length: the models are baked with the
## origin a fifth of the way up from the back, not at the grip); fore: where the left hand goes, a share of the
## length on from the grip (0: both hands on the grip, a pistol's cupped hold).
## Damage is against 100 health (people, officers, you): a pistol takes 4 to 6, a rifle 3 or 4 (each hit
## varies a little); a car takes 450 (a rifle: about 15).
const LIST := [
	{"id": "pistol", "name": "Pistol", "price": 0, "dmg": 21.0, "rate": 3.2, "mag": 12, "reload": 1.1, "spread": 0.03, "pellets": 1, "range": 60.0,
		"grip": Vector2(-0.12, 0.02), "fore": 0.0, "auto": false, "both": false, "sound": "shot_pistol", "scale": 2.6, "looks": ["Pistol_Duty", "Pistol_Race", "Pistol_Tactical", "Pistol_Carbine", "Pistol_Drum"]},
	{"id": "revolver", "name": "Revolver", "price": 900, "dmg": 40.0, "rate": 1.4, "mag": 6, "reload": 1.8, "spread": 0.015, "pellets": 1, "range": 75.0,
		"grip": Vector2(-0.15, 0.06), "fore": 0.0, "auto": false, "both": false, "sound": "shot_revolver", "scale": 2.5, "looks": ["Revolver_Service", "Revolver_Snub", "Revolver_Stainless", "Revolver_Hunter", "Revolver_Competition"]},
	{"id": "smg", "name": "SMG", "price": 1800, "dmg": 12.0, "rate": 11.0, "mag": 30, "reload": 1.4, "spread": 0.06, "pellets": 1, "range": 50.0,
		"grip": Vector2(-0.04, -0.14), "fore": 0.24, "auto": true, "both": true, "sound": "shot_smg", "scale": 2.2, "looks": ["SMG_Modern", "SMG_Fixed_Stock", "SMG_Suppressed", "SMG_Raider", "SMG_Drum"]},
	{"id": "shotgun", "name": "Shotgun", "price": 2400, "dmg": 9.0, "rate": 1.1, "mag": 6, "reload": 2.2, "spread": 0.13, "pellets": 8, "range": 28.0,
		"grip": Vector2(-0.02, -0.03), "fore": 0.32, "auto": false, "both": true, "sound": "shot_shotgun", "scale": 1.9, "looks": ["Shotgun_Field", "Shotgun_Riot", "Shotgun_Tactical", "Shotgun_Entry", "Shotgun_Breacher"]},
	{"id": "rifle", "name": "Rifle", "price": 4200, "dmg": 30.0, "rate": 7.5, "mag": 30, "reload": 1.8, "spread": 0.035, "pellets": 1, "range": 90.0,
		"grip": Vector2(0.0, -0.1), "fore": 0.26, "auto": true, "both": true, "sound": "shot_rifle", "scale": 1.75, "looks": ["AK_Classic_Wood", "AK_Classic_Plum", "AK_Modernized", "AK_Modern", "AK_Marksman_Scope"]},
	{"id": "sniper", "name": "Sniper", "price": 6500, "dmg": 105.0, "rate": 0.8, "mag": 5, "reload": 2.6, "spread": 0.004, "pellets": 1, "range": 220.0,
		"grip": Vector2(-0.03, -0.05), "fore": 0.27, "auto": false, "both": true, "sound": "shot_sniper", "scale": 1.6, "looks": ["Sniper_Hunter", "Sniper_Tactical", "Sniper_Recon", "Sniper_Integral", "Sniper_Chassis"]},
]
const LOOK_PRICE := 350        # each extra look for a gun you own

static var _cache := {}

## How a gun sits in the right fist of a character scaled `char_scale`, on its arm bone (whose fist is at
## `hand`, the arm along -X): turned by `rot` (the gun's basis in the bone's frame, unscaled; default: along
## the arm), placed so its grip is in the fist.
static func hand_xf(w: Dictionary, m: Mesh, char_scale: float, hand: Vector3, rot := Basis(Vector3.UP, PI * 0.5)) -> Transform3D:
	var k: float = float(w["scale"]) / char_scale
	var b := rot.orthonormalized().scaled(Vector3.ONE * k)
	return Transform3D(b, hand - b * grip_of(w, m))

## The grip, in the model's own units.
static func grip_of(w: Dictionary, m: Mesh) -> Vector3:
	if m == null or not have_models():
		return Vector3.ZERO
	var g: Vector2 = w.get("grip", Vector2.ZERO)
	var len := m.get_aabb().size.z
	return Vector3(0, g.x * len, g.y * len)

static func by_id(id: String) -> Dictionary:
	for w in LIST:
		if w["id"] == id:
			return w
	return LIST[0]

## A look's display name ("Pistol_Race" -> "Race").
static func look_name(preset: String) -> String:
	var p := preset.split("_")
	return " ".join(p.slice(1 if p.size() > 1 else 0)).replace("AK ", "").capitalize() if p.size() > 1 else preset

## Whether the licensed models are in this build.
static func have_models() -> bool:
	return ResourceLoader.exists(DIR + "Pistol_Duty.res")

## The mesh for a gun in one of its looks (pointing down -Z, the grip at the origin), at the size it's held.
static func mesh(w: Dictionary, look: int) -> Mesh:
	var looks: Array = w["looks"]
	var preset := String(looks[clampi(look, 0, looks.size() - 1)])
	var key := preset
	if _cache.has(key):
		return _cache[key]
	var m: Mesh = null
	if ResourceLoader.exists(DIR + preset + ".res"):
		m = load(DIR + preset + ".res")
	else:
		m = _blocky(w, look)
	_cache[key] = m
	return m

## The stand-in: a blocky gun of about the right shape and size, in a colour for the look.
static func _blocky(w: Dictionary, look: int) -> Mesh:
	var b := MB.new()
	var dark := MB.rgb(["2b2b30", "5a4632", "3c4a3a", "8f949b", "6b2f3a"][look % 5])
	var metal := MB.rgb("1d1d20")
	match String(w["id"]):
		"pistol", "revolver":
			b.box(Vector3(0, 0.06, -0.09), Vector3(0.035, 0.05, 0.2), dark)
			b.box(Vector3(0, -0.02, -0.0), Vector3(0.032, 0.11, 0.045), metal)
		"smg":
			b.box(Vector3(0, 0.05, -0.15), Vector3(0.05, 0.07, 0.36), dark)
			b.box(Vector3(0, -0.04, -0.06), Vector3(0.035, 0.12, 0.04), metal)
			b.box(Vector3(0, -0.06, -0.18), Vector3(0.03, 0.14, 0.04), metal)
		"shotgun":
			b.box(Vector3(0, 0.05, -0.3), Vector3(0.05, 0.05, 0.75), metal)
			b.box(Vector3(0, 0.0, 0.12), Vector3(0.045, 0.09, 0.3), dark)
		"rifle":
			b.box(Vector3(0, 0.05, -0.28), Vector3(0.05, 0.07, 0.75), metal)
			b.box(Vector3(0, -0.06, -0.25), Vector3(0.035, 0.16, 0.05), dark)
			b.box(Vector3(0, 0.02, 0.16), Vector3(0.045, 0.1, 0.26), dark)
		_:
			b.box(Vector3(0, 0.05, -0.4), Vector3(0.045, 0.06, 1.0), metal)
			b.box(Vector3(0, 0.11, -0.2), Vector3(0.04, 0.05, 0.22), dark)
			b.box(Vector3(0, 0.02, 0.2), Vector3(0.045, 0.1, 0.3), dark)
	return b.commit()
