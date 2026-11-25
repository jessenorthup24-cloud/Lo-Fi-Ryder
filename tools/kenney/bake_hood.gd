extends "bake_kenney.gd"
## Bakes the Graveyard Kit, more of the Retro Urban Kit and a few City Kit Suburban pieces (CC0, kenney.nl),
## and builds the hood's buildings out of the Retro Urban Kit's wall blocks: each a grid of 1 x 1 x 1 blocks
## (brick "a" or painted stucco "b"), every outside face turned out with its window, door or garage, the
## middle of the top floor filled in for the roof, then balconies, a fire escape, a shop awning and some
## roof clutter, all merged into one mesh (k_hood_<name>.res, in the kit's units; models.gd scales it).
## Run from a scratch project (next to bake_kenney.gd) whose res://packs/urb, res://packs/grave and
## res://packs/sub2 hold those packs' "GLB format" folders:  godot --headless --path <scratch> -s bake_hood.gd

const GRAVE := ["altar-stone", "bench", "bench-damaged", "border-pillar", "brick-wall", "brick-wall-end", "candle-multiple",
	"character-ghost", "character-keeper", "column-large", "cross", "cross-column", "cross-wood", "crypt", "crypt-a",
	"crypt-large", "crypt-large-door", "crypt-large-roof", "crypt-small", "crypt-small-roof", "debris", "fire-basket", "grave",
	"grave-border", "gravestone-bevel", "gravestone-broken", "gravestone-cross", "gravestone-cross-large", "gravestone-debris",
	"gravestone-decorative", "gravestone-roof", "gravestone-round", "gravestone-wide", "iron-fence-border",
	"iron-fence-border-column", "iron-fence-border-gate", "iron-fence-damaged", "lantern-candle", "lightpost-double",
	"lightpost-single", "pillar-obelisk", "pillar-square", "pine", "pine-crooked", "pine-fall", "pine-fall-crooked",
	"pumpkin", "pumpkin-carved", "pumpkin-tall-carved", "rocks", "rocks-tall", "shovel", "shovel-dirt", "stone-wall",
	"stone-wall-column", "stone-wall-damaged", "trunk", "urn-round"]
const URB := ["detail-dumpster-open", "detail-barrier-strong-damaged", "detail-barrier-strong-type-b", "detail-block",
	"detail-bricks-type-a", "detail-bricks-type-b", "detail-cables-type-a", "detail-cables-type-b", "detail-beam", "pallet-small",
	"planks", "wall-fence", "wall-broken-type-a", "wall-broken-type-b", "wall-type-a", "wall-type-b", "wall-steps-type-a",
	"wall-c-flat", "wall-c-flat-low", "scaffolding-structure", "scaffolding-poles", "scaffolding-floor", "truck-green-cargo",
	"truck-grey-cargo", "tree-park-large", "tree-shrub", "tree-large", "detail-light-traffic"]
const SUB2 := ["fence-2x3", "fence-3x2", "path-stones-messy"]

## The hood's buildings. front: per floor (ground first), what each block across the front has:
## d door, w window, g garage, o open (a shop front), p plain. Extras: bal (balconies on these floors),
## esc (a fire escape up the right side), awn (an awning over the ground floor), roof (clutter on top).
const BUILDINGS := {
	"duplex-a": {"w": 3, "d": 2, "h": 2, "s": "b", "front": ["dwd", "www"], "bal": [1], "roof": true, "paint": "93c4a0"},
	"duplex-a2": {"w": 3, "d": 2, "h": 2, "s": "b", "front": ["dwd", "www"], "bal": [1], "paint": "e3a982"},
	"duplex-b": {"w": 4, "d": 2, "h": 2, "s": "a", "front": ["wddw", "wwww"], "bal": [1], "paint": "a3533e"},
	"duplex-c": {"w": 3, "d": 2, "h": 2, "s": "b", "front": ["gdw", "pww"], "roof": true, "paint": "e0cc94"},
	"duplex-c2": {"w": 3, "d": 2, "h": 2, "s": "b", "front": ["gdw", "pww"], "paint": "d99aa6"},
	"bungalow-a": {"w": 3, "d": 2, "h": 1, "s": "b", "front": ["wdg"], "roof": true, "paint": "6aa5a0"},
	"bungalow-a2": {"w": 3, "d": 2, "h": 1, "s": "b", "front": ["wdg"], "paint": "e6d6b0"},
	"bungalow-b": {"w": 2, "d": 2, "h": 1, "s": "b", "front": ["dw"], "roof": true, "paint": "a99cc6"},
	"corner-store": {"w": 3, "d": 3, "h": 1, "s": "a", "front": ["ood"], "awn": true, "roof": true, "paint": "b8754e"},
	"walkup-a": {"w": 4, "d": 3, "h": 3, "s": "a", "front": ["wddw", "wwww", "wwww"], "esc": true, "roof": true, "paint": "9c4b3a"},
	"walkup-b": {"w": 5, "d": 2, "h": 3, "s": "b", "front": ["wwdww", "wwwww", "wwwww"], "bal": [1, 2], "roof": true, "paint": "c9b48a"},
	"walkup-c": {"w": 3, "d": 3, "h": 3, "s": "a", "front": ["wdw", "www", "www"], "esc": true, "paint": "b06a4c"},
	"walkup-d": {"w": 4, "d": 2, "h": 3, "s": "b", "front": ["wdgw", "wwww", "wwww"], "bal": [2], "esc": true, "paint": "7fa6b8"},
	"garages": {"w": 4, "d": 2, "h": 1, "s": "a", "front": ["gggg"], "paint": "9a9286"},
}
## Flat colours for the kit's tiling materials (the walls' own paint comes from each building's spec).
const MATS := {"concrete": "cfc7b8", "concreteSmooth": "bdb6a9", "metal": "a3a7ac", "bars": "2e2f31", "roof": "4a4846",
	"roof_plates": "8a7d74", "doors": "7d3a2e", "wall_garage": "a9aeb4", "windows": "3e5a70", "signs": "c9a83a",
	"planks": "8a6c50", "dirt": "7d6a55", "wall": "c98f55", "wall_lines": "a3533e", "wall_metal": "6f8f6c", "truck": "a7adb3",
	"truck_alien": "4e8a70", "treeA": "6f8f3e", "treeB": "3f6b4a", "asphalt": "3d3b39", "_defaultMat": "cfc7b8",
	"grass": "6f8f4e", "rock": "8a857c"}

func _init():
	var meta := {}
	if FileAccess.file_exists(OUT + "kenney_meta.json"):
		meta = JSON.parse_string(FileAccess.get_file_as_string(OUT + "kenney_meta.json"))
	for pr in [["grave", GRAVE], ["urb", URB], ["sub2", SUB2]]:
		mat_colors = {}
		glass_mats = []
		if pr[0] == "urb":
			for k in MATS:
				mat_colors[k] = Color(MATS[k])
		for nm in pr[1]:
			var path := "res://packs/%s/%s.glb" % [pr[0], nm]
			if not ResourceLoader.exists(path):
				print("MISSING ", path)
				continue
			var root: Node = (load(path) as PackedScene).instantiate()
			var m := _bake(root, "", Vector3.ZERO, false, nm in ["lantern-candle", "lightpost-double", "lightpost-single", "fire-basket", "candle-multiple"])
			root.free()
			_save(meta, "k_%s_%s" % [pr[0], nm], m)
	glass_mats = ["windows"]
	for bn in BUILDINGS:
		mat_colors = {}
		for k in MATS:
			mat_colors[k] = Color(MATS[k])
		var paint := Color(String(BUILDINGS[bn].get("paint", "a3533e")))
		mat_colors["wall_lines" if BUILDINGS[bn]["s"] == "a" else "wall_metal"] = paint
		var root := _building(BUILDINGS[bn])
		var m2 := _bake(root, "", Vector3.ZERO, true, false)
		root.free()
		_save(meta, "k_hood_" + bn, m2)
	var f := FileAccess.open(OUT + "kenney_meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	print("baked ", meta.size())
	quit()

func _save(meta: Dictionary, key: String, m: ArrayMesh) -> void:
	ResourceSaver.save(m, OUT + key + ".res", ResourceSaver.FLAG_COMPRESS)
	var ab := m.get_aabb()
	meta[key] = [snappedf(ab.position.x, 0.001), snappedf(ab.position.y, 0.001), snappedf(ab.position.z, 0.001),
		snappedf(ab.size.x, 0.001), snappedf(ab.size.y, 0.001), snappedf(ab.size.z, 0.001), m.surface_get_array_len(0)]

func _add(root: Node3D, nm: String, pos: Vector3, yaw: float) -> void:
	var sc: PackedScene = load("res://packs/urb/%s.glb" % nm)
	if sc == null:
		print("MISSING urb ", nm)
		return
	var n: Node3D = sc.instantiate()
	n.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	root.add_child(n)

## A building from the spec (Kenney's own facing: the front is +Z; the bake turns it to -Z).
func _building(b: Dictionary) -> Node3D:
	var root := Node3D.new()
	var w: int = b["w"]
	var d: int = b["d"]
	var h: int = b["h"]
	var s: String = b["s"]
	var front: Array = b["front"]
	var kinds := {"d": "-door", "w": "-window", "g": "-garage", "o": "-open", "p": ""}
	for k in h:
		for i in w:
			for j in d:
				var x := float(i) - (w - 1) * 0.5
				var z := (d - 1) * 0.5 - float(j)
				var edge := i == 0 or i == w - 1 or j == 0 or j == d - 1
				if not edge:
					if k == h - 1:
						_add(root, "wall-" + s, Vector3(x, k, z), 0.0)       # (the roof over the middle)
					continue
				# which way this block faces out (the front and back win at the corners)
				var yaw := 0.0
				var what := "p"
				if j == 0:
					yaw = 0.0
					what = String(front[mini(k, front.size() - 1)]).substr(i, 1)
				elif j == d - 1:
					yaw = PI
					what = "w" if (i + k) % 2 == 0 else "p"
				elif i == 0:
					yaw = -PI * 0.5
					what = "w" if (j + k) % 2 == 1 else "p"
				else:
					yaw = PI * 0.5
					what = "w" if (j + k) % 2 == 1 else "p"
				if k > 0 and what in ["d", "g", "o"]:
					what = "w"
				# (the kit's blocks have their window, door or garage on their -Z face: turned round to face out)
				_add(root, "wall-" + s + String(kinds[what]), Vector3(x, k, z), yaw + PI)
	var fz := d * 0.5            # the front face
	for k in b.get("bal", []):
		for i in w:
			if i % 2 == (1 if w % 2 == 1 else 0) or w <= 3:
				_add(root, "balcony-type-a", Vector3(float(i) - (w - 1) * 0.5, float(k) - 0.02, fz + 0.14), 0.0)
	if b.get("esc", false):
		# a fire escape up the right-hand side: a landing on each floor, a ladder between them
		var sx := w * 0.5 + 0.14
		var sz := (d - 1) * 0.5 - 1.0 if d > 2 else 0.0
		for k in range(1, h):
			_add(root, "balcony-ladder-top" if k == h - 1 else "balcony-ladder-bottom", Vector3(sx, float(k) - 0.02, sz), PI * 0.5)
	if b.get("awn", false):
		for i in w:
			_add(root, "detail-awning-wide", Vector3(float(i) - (w - 1) * 0.5, 0.7, fz + 0.15), 0.0)
	if b.get("roof", false):
		_add(root, "roof-metal-poles", Vector3((w - 1) * 0.5 - 0.5, float(h), -(d - 1) * 0.5 + 0.3), 0.0)
		if w >= 3:
			_add(root, "detail-block", Vector3(-(w - 1) * 0.5 + 0.3, float(h), 0.0), 0.0)
	return root
