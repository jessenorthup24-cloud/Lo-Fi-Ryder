extends RefCounted
## The guns: fourteen kinds, the whole PIXEL ARSENAL Mega Pack. Each gun is put together from its parts: a
## base receiver, and a part on each of its sockets (grip, magazine, handguard, stock, barrel, muzzle, optics,
## underbarrel, rail...), some parts bringing sockets of their own (a barrel's muzzle, a scope's top rail).
## You start each gun as one of its presets and change any part at the Armory; parts change how it shoots.
## The pack is licensed: the baked parts (tools/guns/bake_kit.gd) live only in the private assets repo and
## ship inside the built game. Without them (a checkout without the ASSETS_TOKEN secret) each gun is a
## plain blocky stand-in.

const MB := preload("res://scripts/core/mesh_builder.gd")
const DIR := "res://assets/guns/"
const KIT := "res://assets/guns/kit.json"
const PACK_M := 0.92               # metres per pack unit (the pack's guns are a touch over life size)

## id: the pack family, name, the level the Armory sells it from, price, damage a hit, shots a second,
## magazine (the stock one: a build's magazine part sets it), reload (s), spread (rad), pellets, range (m),
## auto (hold to fire), two-handed, sound. Damage is against 100 health (people, officers, you); a car
## takes 450.
const LIST := [
	{"id": "pistol", "family": "Pistol", "name": "Pistol", "lvl": 1, "price": 0, "dmg": 21.0, "rate": 3.2, "mag": 17, "reload": 1.1,
		"spread": 0.03, "pellets": 1, "range": 60.0, "auto": false, "both": false, "fore": 0.0, "sound": "shot_pistol"},
	{"id": "revolver", "family": "Revolver", "name": "Revolver", "lvl": 3, "price": 1500, "dmg": 42.0, "rate": 1.4, "mag": 6, "reload": 1.8,
		"spread": 0.015, "pellets": 1, "range": 75.0, "auto": false, "both": false, "fore": 0.0, "sound": "shot_revolver"},
	{"id": "pdw", "family": "PDW", "name": "PDW", "lvl": 5, "price": 3200, "dmg": 13.0, "rate": 12.0, "mag": 30, "reload": 1.3,
		"spread": 0.055, "pellets": 1, "range": 50.0, "auto": true, "both": true, "fore": 0.26, "sound": "shot_smg"},
	{"id": "smg", "family": "SMG", "name": "SMG", "lvl": 7, "price": 4500, "dmg": 14.0, "rate": 11.0, "mag": 30, "reload": 1.4,
		"spread": 0.05, "pellets": 1, "range": 55.0, "auto": true, "both": true, "fore": 0.26, "sound": "shot_smg"},
	{"id": "shotgun", "family": "Pump_Shotgun", "name": "Pump Shotgun", "lvl": 8, "price": 6000, "dmg": 10.0, "rate": 1.1, "mag": 6, "reload": 2.2,
		"spread": 0.13, "pellets": 8, "range": 28.0, "auto": false, "both": true, "fore": 0.26, "sound": "shot_shotgun"},
	{"id": "breakaction", "family": "BreakAction_Shotgun", "name": "Double Barrel", "lvl": 10, "price": 7500, "dmg": 13.0, "rate": 2.4, "mag": 2, "reload": 1.8,
		"spread": 0.15, "pellets": 9, "range": 24.0, "auto": false, "both": true, "fore": 0.26, "sound": "shot_shotgun"},
	{"id": "carbine", "family": "AR_Carbine", "name": "Carbine", "lvl": 11, "price": 11000, "dmg": 28.0, "rate": 8.5, "mag": 30, "reload": 1.7,
		"spread": 0.032, "pellets": 1, "range": 90.0, "auto": true, "both": true, "fore": 0.26, "sound": "shot_rifle"},
	{"id": "rifle", "family": "AK_Rifle", "name": "AK Rifle", "lvl": 13, "price": 13000, "dmg": 31.0, "rate": 7.5, "mag": 30, "reload": 1.8,
		"spread": 0.036, "pellets": 1, "range": 90.0, "auto": true, "both": true, "fore": 0.26, "sound": "shot_rifle"},
	{"id": "lever", "family": "Lever_Action", "name": "Lever Rifle", "lvl": 14, "price": 12000, "dmg": 55.0, "rate": 1.6, "mag": 8, "reload": 2.4,
		"spread": 0.012, "pellets": 1, "range": 130.0, "auto": false, "both": true, "fore": 0.26, "sound": "shot_rifle"},
	{"id": "bullpup", "family": "Bullpup", "name": "Bullpup", "lvl": 16, "price": 17000, "dmg": 29.0, "rate": 9.0, "mag": 30, "reload": 1.6,
		"spread": 0.03, "pellets": 1, "range": 95.0, "auto": true, "both": true, "fore": 0.26, "sound": "shot_rifle"},
	{"id": "battle", "family": "Battle_Rifle", "name": "Battle Rifle", "lvl": 18, "price": 22000, "dmg": 44.0, "rate": 5.0, "mag": 20, "reload": 2.0,
		"spread": 0.025, "pellets": 1, "range": 120.0, "auto": true, "both": true, "fore": 0.26, "sound": "shot_rifle"},
	{"id": "sniper", "family": "Sniper_Rifle", "name": "Sniper", "lvl": 20, "price": 28000, "dmg": 105.0, "rate": 0.8, "mag": 5, "reload": 2.6,
		"spread": 0.004, "pellets": 1, "range": 220.0, "auto": false, "both": true, "fore": 0.26, "sound": "shot_sniper"},
	{"id": "lmg", "family": "LMG", "name": "LMG", "lvl": 23, "price": 36000, "dmg": 30.0, "rate": 10.0, "mag": 100, "reload": 4.0,
		"spread": 0.05, "pellets": 1, "range": 100.0, "auto": true, "both": true, "fore": 0.26, "sound": "shot_rifle"},
	{"id": "amr", "family": "AntiMateriel_Rifle", "name": "Anti-Materiel", "lvl": 26, "price": 48000, "dmg": 220.0, "rate": 0.5, "mag": 5, "reload": 3.4,
		"spread": 0.003, "pellets": 1, "range": 300.0, "auto": false, "both": true, "fore": 0.26, "sound": "shot_sniper"},
]

## The parts a gun has to have (you can swap them, not take them off); every other socket can be left bare.
const REQUIRED := ["Mags", "Grips", "Handguards", "Barrels", "Slides", "Cylinders", "Stocks", "Forends", "Pumps", "Levers", "Bolts",
	"Chassis", "Triggers", "Base"]
## Each kind of part: the level it's sold from (on top of the gun's own), its price, what it's called.
const CAT_INFO := {
	"Mags": [1, 350, "Magazine"], "Grips": [1, 250, "Grip"], "Stocks": [2, 400, "Stock"], "Handguards": [2, 500, "Handguard"],
	"Muzzles": [4, 600, "Muzzle"], "Optics": [3, 700, "Optic"], "Foregrips": [5, 350, "Foregrip"], "RailAccessories": [6, 450, "Light / laser"],
	"Barrels": [7, 900, "Barrel"], "Magnifiers": [16, 900, "Magnifier"], "Bipods": [10, 500, "Bipod"], "Sights": [2, 200, "Sights"],
	"OffsetOptics": [12, 600, "Offset sight"], "PiggybackOptics": [12, 500, "Piggyback dot"], "Forends": [3, 450, "Forend"],
	"Mounts": [4, 300, "Mount"], "FrontSights": [2, 200, "Front sight"], "Handles": [6, 400, "Handle"], "Pumps": [3, 450, "Pump"],
	"ShellSaddles": [5, 300, "Shell saddle"], "Buttpads": [3, 200, "Buttpad"], "Lights": [6, 450, "Light"], "Slides": [6, 900, "Slide"],
	"Cylinders": [5, 700, "Cylinder"], "Rangefinders": [18, 1200, "Rangefinder"], "Chokes": [6, 400, "Choke"], "Levers": [4, 400, "Lever"],
	"Bolts": [5, 500, "Bolt"], "Launchers": [28, 6000, "Launcher"], "Triggers": [4, 350, "Trigger"], "TangSights": [8, 400, "Tang sight"],
	"Chassis": [10, 1500, "Chassis"], "Underbarrel": [8, 500, "Underbarrel"], "FrontPosts": [2, 200, "Front post"],
	"SlingRings": [1, 100, "Sling ring"], "Magwells": [5, 300, "Magwell"], "HeatShields": [6, 300, "Heat shield"],
	"CheekPads": [4, 250, "Cheek pad"], "Ammo": [3, 300, "Speed loader"], "Base": [1, 1200, "Receiver"],
}
## Socket order (how the slots are listed at the Armory).
const SOCKET_ORDER := ["slide", "barrel", "cylinder", "handguard", "forend", "pump", "mag", "grip", "stock", "muzzle", "optic",
	"optic_top", "optic_offset", "magnifier", "side_mount", "rail_side", "rail_top", "underbarrel", "bipod", "light"]
const PRESET_PRICE := 0.35         # a preset build (besides the one it comes as) costs this share of the gun

static var _kit: Dictionary = {}
static var _cache := {}

static func kit() -> Dictionary:
	if _kit.is_empty() and FileAccess.file_exists(KIT):
		var v = JSON.parse_string(FileAccess.get_file_as_string(KIT))
		if v is Dictionary:
			_kit = v
	return _kit

## Whether the licensed models are in this build.
static func have_models() -> bool:
	return not kit().is_empty()

static func by_id(id: String) -> Dictionary:
	for w in LIST:
		if w["id"] == id:
			return w
	return LIST[0]

## The presets a gun comes in (its first is how you get it).
static func presets(w: Dictionary) -> Array:
	var f: Dictionary = kit().get("families", {}).get(String(w["family"]), {})
	var ps: Array = (f.get("presets", {}) as Dictionary).keys()
	ps.sort()
	# (the plainest first: the one with the fewest parts)
	ps.sort_custom(func(a, b): return (f["presets"][a]["parts"] as Dictionary).size() < (f["presets"][b]["parts"] as Dictionary).size())
	return ps

static func preset_build(w: Dictionary, preset: String) -> Dictionary:
	var f: Dictionary = kit().get("families", {}).get(String(w["family"]), {})
	var p: Dictionary = (f.get("presets", {}) as Dictionary).get(preset, {})
	if p.is_empty():
		return {"base": "", "parts": {}}
	return _complete(w, {"base": String(p["base"]), "parts": (p["parts"] as Dictionary).duplicate()})

## Fill any socket that needs a part (a barrel, a magazine...) and hasn't got one with the plainest that fits.
static func _complete(w: Dictionary, b: Dictionary) -> Dictionary:
	for pass_i in 3:
		var socks := {}
		for s0 in part(String(b["base"])).get("sockets", {}):
			socks[s0] = true
		for s1 in (b["parts"] as Dictionary):
			for s2 in part(String(b["parts"][s1])).get("sockets", {}):
				socks[s2] = true
		for sk in socks:
			if (b["parts"] as Dictionary).has(sk):
				continue
			var opts := parts_for(w, String(sk))
			if opts.size() > 0 and socket_required(w, String(sk)):
				b["parts"][sk] = opts[0]
	return b

## A socket every one of the gun's presets has a part on (a barrel, a magazine): it can't be left bare.
static func socket_required(w: Dictionary, sk: String) -> bool:
	var f: Dictionary = kit().get("families", {}).get(String(w["family"]), {})
	var ps: Dictionary = f.get("presets", {})
	if ps.is_empty():
		return false
	for pn in ps:
		if not (ps[pn]["parts"] as Dictionary).has(sk):
			return false
	return true

static func default_build(w: Dictionary) -> Dictionary:
	var ps := presets(w)
	return preset_build(w, String(ps[0])) if ps.size() > 0 else {"base": "", "parts": {}}

static func part(nm: String) -> Dictionary:
	return (kit().get("parts", {}) as Dictionary).get(nm, {})

## A preset's or a part's name for people ("AK_Optic_Red_Dot" -> "Red Dot").
static func nice(nm: String) -> String:
	var p := nm.split("_")
	var cut := 1
	var info := part(nm)
	if not info.is_empty():
		cut = 2 if p.size() > 2 else 1      # (family, then the category)
		if String(info.get("cat", "")) == "Base":
			cut = 2
	var s := " ".join(p.slice(cut)).replace("4x", "4×").replace("3x", "3×").replace("5x", "5×")
	return s if s != "" else nm

## Every part of this gun's family that fits a socket (bases aside).
static func parts_for(w: Dictionary, socket: String) -> Array:
	var out: Array = []
	var fam := String(w["family"])
	for nm in kit().get("parts", {}):
		var p: Dictionary = kit()["parts"][nm]
		if String(p["family"]) == fam and String(p["cat"]) != "Base" and (p["mounts"] as Array).has(socket):
			out.append(nm)
	out.sort_custom(func(a, b): return part_price(w, a) < part_price(w, b))
	return out

static func part_level(w: Dictionary, nm: String) -> int:
	var p := part(nm)
	var ci: Array = CAT_INFO.get(String(p.get("cat", "")), [3, 400, ""])
	var lv := maxi(int(w.get("lvl", 1)), int(ci[0]))
	if "Suppressor" in nm:
		lv = maxi(lv, 12)
	if "Drum" in nm:
		lv = maxi(lv, 15)
	if "Scope" in nm or "LPVO" in nm:
		lv = maxi(lv, 14)
	return mini(lv, 30)

static func part_price(w: Dictionary, nm: String) -> int:
	var p := part(nm)
	var ci: Array = CAT_INFO.get(String(p.get("cat", "")), [3, 400, ""])
	var k := 1.0 + float(int(w.get("lvl", 1))) * 0.06
	if "Suppressor" in nm:
		k *= 2.2
	if "Drum" in nm:
		k *= 1.8
	if "Scope" in nm or "LPVO" in nm or "Prism" in nm:
		k *= 1.6
	return int(round(float(ci[1]) * k / 50.0)) * 50

## What a part does, in a few words (for the Armory's list).
static func describe(nm: String) -> String:
	var cat := String(part(nm).get("cat", ""))
	var n := _num(nm)
	match cat:
		"Muzzles":
			if "Suppressor" in nm or "Silencer" in nm or "Can" in nm:
				return "Suppressed: quiet shots, the police rarely hear"
			if "Brake" in nm or "Comp" in nm:
				return "Muzzle brake: much less kick"
			return "Flash hider: a little less kick"
		"Optics":
			if "Scope" in nm or "LER" in nm:
				return "Scope: zooms right in, steadier"
			if "4x" in nm or "Prism" in nm:
				return "4× prism: zooms in, steadier"
			if "LPVO" in nm:
				return "Variable optic: zooms in, steadier"
			return "Red dot: a touch of zoom, steadier"
		"OffsetOptics", "PiggybackOptics":
			return "Backup dot: steadier"
		"Rangefinders":
			return "Rangefinder: steadier"
		"Magnifiers":
			return "Flipped aside" if "Flipped" in nm else ("Magnifier: more zoom (%s)" % ("5×" if "5x" in nm else "3×"))
		"Mags":
			if "Extension" in nm:
				return "+5 rounds"
			return ("%d rounds" % n if n > 0 else "Magazine") + (", slower to reload" if "Drum" in nm else "")
		"Ammo":
			return "Reloads faster"
		"Cylinders":
			return "%d rounds" % n if n > 0 else "Cylinder"
		"Stocks", "Chassis", "Buttpads", "CheekPads":
			return "Folded: a little less control" if ("Folded" in nm or "Collapsed" in nm) else "Less kick"
		"Grips", "Handles":
			return "Steadier aim"
		"Foregrips", "Underbarrel":
			return "Less kick, steadier"
		"RailAccessories", "Lights":
			return "Laser: tighter shots from the hip" if "Laser" in nm else "Light: a little tighter from the hip"
		"Bipods":
			return "Less kick"
		"Barrels", "Slides":
			if "Long" in nm or "Hunter" in nm or "Heavy" in nm or n >= 20 or "FullLug" in nm:
				return "Longer: more range and damage"
			if "Snub" in nm or "Short" in nm or (n > 0 and n <= 14):
				return "Shorter: quicker, less range"
			return "Ported: less kick" if ("Ported" in nm or "Comp" in nm) else "Standard"
		"Chokes":
			return "Tighter spread"
		"Launchers":
			return "Grenade launcher (looks the part)"
	return cat_name(nm)

static func cat_name(nm: String) -> String:
	return String((CAT_INFO.get(String(part(nm).get("cat", "")), [0, 0, "Part"]) as Array)[2])

static func socket_name(s: String) -> String:
	return {"optic_top": "Top dot", "optic_offset": "Offset sight", "side_mount": "Side mount", "rail_side": "Side rail",
		"rail_top": "Top rail", "underbarrel": "Underbarrel", "mag": "Magazine"}.get(s, s.capitalize())

static func required(nm: String) -> bool:
	return REQUIRED.has(String(part(nm).get("cat", "")))

## How many attachments open up at the Armory at this level (for the level-up card).
static func parts_at_level(lv: int) -> int:
	var n := 0
	for w in LIST:
		if int(w["lvl"]) > lv:
			continue
		for nm in kit().get("parts", {}):
			var p: Dictionary = kit()["parts"][nm]
			if String(p["family"]) == String(w["family"]) and String(p["cat"]) != "Base" and part_level(w, nm) == lv:
				n += 1
	return n

# ------------------------------------------------------------------ a gun as you've built it

## Your build of a gun (save "gun_builds": id -> {base, parts}), or how it comes.
static func build_of(save, id: String) -> Dictionary:
	var w := by_id(id)
	var b = (save.data.get("gun_builds", {}) as Dictionary).get(id)
	if b is Dictionary and String(b.get("base", "")) != "" and not part(String(b["base"])).is_empty():
		return b
	return default_build(w)

## The gun with its build: the stats as its parts change them, and the build itself ("build").
static func loadout(save, id: String) -> Dictionary:
	var w := by_id(id).duplicate()
	var b := build_of(save, id)
	return with_build(w, b)

static func with_build(w0: Dictionary, b: Dictionary) -> Dictionary:
	var w := w0.duplicate()
	w["build"] = b
	w["zoom"] = 1.0
	w["recoil"] = 1.0
	w["quiet"] = false
	w["hip"] = 1.0
	var mag_set := false
	for s in (b.get("parts", {}) as Dictionary):
		var nm := String(b["parts"][s])
		var cat := String(part(nm).get("cat", ""))
		match cat:
			"Muzzles":
				if "Suppressor" in nm or "Silencer" in nm or "Can" in nm:
					w["quiet"] = true
					w["dmg"] = float(w["dmg"]) * 0.95
					w["range"] = float(w["range"]) * 1.05
				elif "Brake" in nm or "Comp" in nm:
					w["recoil"] = float(w["recoil"]) * 0.72
				else:
					w["recoil"] = float(w["recoil"]) * 0.88
			"Optics", "OffsetOptics", "PiggybackOptics", "Rangefinders":
				var z := 1.18
				if "Scope" in nm or "LER" in nm:
					z = 2.4
				elif "4x" in nm or "Prism" in nm:
					z = 1.7
				elif "LPVO" in nm:
					z = 1.6
				if cat == "Optics":
					w["zoom"] = maxf(float(w["zoom"]), z)
				w["spread"] = float(w["spread"]) * 0.88
			"Magnifiers":
				if not "Flipped" in nm:
					w["zoom"] = float(w["zoom"]) * (1.5 if "5x" in nm else 1.3)
			"Mags", "Ammo":
				var n := _num(nm)
				if "Extension" in nm:
					w["mag"] = int(w["mag"]) + 5
					mag_set = true
				elif n > 0 and cat == "Mags":
					w["mag"] = n
					mag_set = true
				if "Drum" in nm:
					w["reload"] = float(w["reload"]) * 1.3
				if cat == "Ammo":
					w["reload"] = float(w["reload"]) * 0.75
			"Stocks", "Chassis", "Buttpads", "CheekPads":
				w["recoil"] = float(w["recoil"]) * (0.95 if ("Folded" in nm or "Collapsed" in nm) else 0.85)
			"Grips", "Handles":
				w["spread"] = float(w["spread"]) * 0.95
			"Foregrips", "Underbarrel":
				w["recoil"] = float(w["recoil"]) * 0.86
				w["spread"] = float(w["spread"]) * 0.92
			"RailAccessories", "Lights":
				w["hip"] = float(w["hip"]) * (0.78 if "Laser" in nm else 0.9)
			"Bipods":
				w["recoil"] = float(w["recoil"]) * 0.85
			"Barrels", "Slides":
				var n2 := _num(nm)
				if "Long" in nm or "Hunter" in nm or "Heavy" in nm or n2 >= 20 or "FullLug" in nm:
					w["range"] = float(w["range"]) * 1.22
					w["dmg"] = float(w["dmg"]) * 1.08
					w["spread"] = float(w["spread"]) * 0.9
				elif "Snub" in nm or "Short" in nm or (n2 > 0 and n2 <= 14):
					w["range"] = float(w["range"]) * 0.85
					w["rate"] = float(w["rate"]) * 1.06
				if "Ported" in nm or "Comp" in nm:
					w["recoil"] = float(w["recoil"]) * 0.85
			"Cylinders":
				var n3 := _num(nm)
				if n3 > 0:
					w["mag"] = n3
					mag_set = true
			"Chokes":
				w["spread"] = float(w["spread"]) * 0.8
			"Launchers":
				w["launcher"] = true
	if not mag_set and int(w["mag"]) <= 0:
		w["mag"] = int(w0["mag"])
	return w

## The last number in a part's name (a magazine's rounds, a barrel's length): 0 if none.
static func _num(nm: String) -> int:
	var parts := nm.split("_")
	for i in range(parts.size() - 1, -1, -1):
		if parts[i].is_valid_int():
			return int(parts[i])
	return 0

## A build put together as one mesh, in the game's frame: pointing down -Z, the right hand's grip at the
## origin. Returns {mesh, support (where the left hand goes: INF for a one-handed gun), muzzle, len (m)}.
## Cached by build.
static func assemble(w: Dictionary, b: Dictionary) -> Dictionary:
	var key := String(w["id"]) + "|" + String(b.get("base", "")) + "|" + JSON.stringify(b.get("parts", {}), "", true)
	if _cache.has(key):
		return _cache[key]
	var out := {}
	if not have_models() or String(b.get("base", "")) == "":
		out = _blocky(w)
	else:
		out = _put_together(w, b)
	_cache[key] = out
	return out

static func _xf(a: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))

static func _put_together(w: Dictionary, b: Dictionary) -> Dictionary:
	var want: Dictionary = (b.get("parts", {}) as Dictionary).duplicate()
	var placed := {}              # part -> its transform (pack frame)
	var avail := {}               # socket -> transform: where it is now (a part's own socket wins over the base's)
	var base := String(b["base"])
	placed[base] = Transform3D()
	for s in part(base).get("sockets", {}):
		avail[s] = _xf(part(base)["sockets"][s])
	# put the parts on, the ones that bring sockets first (so whatever goes on those sockets ends up on them)
	for pass_i in 6:
		var did := false
		for s in want.keys():
			if not avail.has(s):
				continue
			var nm := String(want[s])
			var p := part(nm)
			if p.is_empty():
				want.erase(s)
				continue
			# (wait if a part still to go on brings this socket itself)
			var later := false
			for s2 in want:
				if s2 != s and avail.has(s2) and (part(String(want[s2])).get("sockets", {}) as Dictionary).has(s):
					later = true
			if later and pass_i < 5:
				continue
			var at: Transform3D = avail[s]
			placed[nm] = at
			for s3 in p.get("sockets", {}):
				avail[s3] = at * _xf(p["sockets"][s3])
			want.erase(s)
			did = true
		if not did and pass_i >= 1:
			break
	# the hands: the right on the grip; the left on a foregrip (or a pump, a forend) if there is one, else
	# the handguard, else wherever the receiver has its mark
	var primary := Transform3D()
	var have_p := false
	var support := Vector3.INF
	var sup_rank := -1
	var sup_style := ""
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for nm in placed:
		var at: Transform3D = placed[nm]
		var p := part(nm)
		var path := DIR + "kit/" + String(nm) + ".res"
		if ResourceLoader.exists(path):
			var m: Mesh = load(path)
			st.append_from(m, 0, at)
			any = true
		var cat := String(p.get("cat", ""))
		for h in p.get("hands", {}):
			var hx: Transform3D = at * _xf(p["hands"][h])
			if String(h).begins_with("hand_primary"):
				if not have_p or cat == "Grips":
					primary = hx
					have_p = true
			elif String(h).begins_with("hand_support"):
				var rank := 0 if cat == "Base" else (2 if cat in ["Foregrips", "Pumps", "Forends", "Underbarrel", "Handles"] else 1)
				if rank > sup_rank:
					sup_rank = rank
					support = hx.origin
					sup_style = String(h)
	if not any:
		return _blocky(w)
	if not have_p and avail.has("grip"):
		primary = avail["grip"]
		have_p = true
	var pack := st.commit()
	var ab := pack.get_aabb()
	var muz: Vector3 = avail.get("muzzle", Transform3D(Basis(), Vector3(0, ab.get_center().y, ab.end.z))).origin
	muz.z = ab.end.z
	# into the game's frame: turned to point down -Z, the grip at the origin
	var turn := Basis(Vector3.UP, PI)
	var org := primary.origin if have_p else Vector3(0, ab.get_center().y, ab.position.z + ab.size.z * 0.3)
	var game_xf := Transform3D(turn, Vector3.ZERO) * Transform3D(Basis(), -org)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	st2.append_from(pack, 0, game_xf)
	var mesh := st2.commit()
	var sup := Vector3.INF
	if support != Vector3.INF and bool(w.get("both", true)):
		sup = game_xf * support
		# (an underhand hold: the palm's under the handguard, the middle of the fist a little lower still)
		if "underhand" in sup_style:
			sup.y -= 0.03 / PACK_M
	return {"mesh": mesh, "support": sup, "muzzle": game_xf * muz, "len": ab.size.z * PACK_M}

## The stand-in: a blocky gun of about the right shape and size.
static func _blocky(w: Dictionary) -> Dictionary:
	var b := MB.new()
	var dark := MB.rgb("2b2b30")
	var metal := MB.rgb("1d1d20")
	var two: bool = w.get("both", true)
	var ln := 0.22 if not two else (0.6 if w["id"] in ["pdw", "smg"] else 0.95)
	b.box(Vector3(0, 0.05, -ln * 0.45), Vector3(0.04, 0.06, ln), metal)
	b.box(Vector3(0, -0.03, 0.0), Vector3(0.032, 0.1, 0.04), dark)
	if two:
		b.box(Vector3(0, 0.02, ln * 0.25), Vector3(0.045, 0.09, ln * 0.35), dark)
	var k := 1.0 / PACK_M
	var m := b.commit()
	return {"mesh": m, "support": Vector3(0, 0.0, -ln * 0.5 * k) if two else Vector3.INF, "muzzle": Vector3(0, 0.05, -ln * 0.95), "len": ln}

## How a gun sits in the right fist (on its arm bone, whose fist is at `hand`): the mesh's grip (its origin)
## in the fist, turned by rot (the gun's basis in the bone's frame), at scale k (bone units a pack unit).
static func hand_xf(k: float, hand: Vector3, rot := Basis(Vector3.UP, PI * 0.5)) -> Transform3D:
	return Transform3D(rot.orthonormalized().scaled(Vector3.ONE * k), hand)
