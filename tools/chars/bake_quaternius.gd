extends SceneTree
## Bakes the Quaternius base character and its animations into one scene: assets/chars/q_base.scn
## (the rig, the body, an AnimationPlayer with every clip). The rig's own clips come in as q_<name>; the
## Mixamo clips (retargeted to this rig) as <pack>_<file name>, with their root motion taken off (they play
## in place: the game moves the body) and the locomotion ones looping.
##   BASE=/path/BaseCharacter.fbx CLIPS="loco=/dir;pistol=/dir;rifle=/dir" godot --headless --path . -s tools/chars/bake_quaternius.gd
## (the Mixamo clips have no foot tracks: this rig's feet hang off the root, so the game snaps them to the
## shins every frame: scripts/game/foot_fix.gd)

const OUT := "res://assets/chars/q_base.scn"

func _init() -> void:
	var doc := FBXDocument.new()
	var st := FBXState.new()
	if doc.append_from_file(OS.get_environment("BASE"), st) != OK:
		push_error("can't read the base")
		quit(1)
		return
	var root: Node3D = doc.generate_scene(st)
	root.name = "QBase"
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var lib := AnimationLibrary.new()
	for an in ap.get_animation_list():
		if String(an).begins_with("CharacterArmature|"):
			var a: Animation = ap.get_animation(an).duplicate()
			var nm := "q_" + _clean(String(an).trim_prefix("CharacterArmature|"))
			if nm in ["q_idle", "q_walk", "q_run", "q_walk_carry", "q_run_carry"]:
				a.loop_mode = Animation.LOOP_LINEAR
			lib.add_animation(nm, a)
	var n := 0
	for spec in OS.get_environment("CLIPS").split(";"):
		var pre := spec.get_slice("=", 0)
		var dir := spec.get_slice("=", 1)
		for f in DirAccess.get_files_at(dir):
			if not f.to_lower().ends_with(".fbx") or f.begins_with("BaseCharacter"):
				continue
			var d2 := FBXDocument.new()
			var s2 := FBXState.new()
			if d2.append_from_file(dir.path_join(f), s2) != OK:
				push_warning("skip " + f)
				continue
			var r2: Node = d2.generate_scene(s2)
			var p2: AnimationPlayer = r2.find_children("*", "AnimationPlayer", true, false)[0]
			if not p2.has_animation("mixamo_com"):
				r2.free()
				continue
			var a2: Animation = p2.get_animation("mixamo_com").duplicate()
			# in place: the armature's own tracks (the root motion, and its turn) off
			for t in range(a2.get_track_count() - 1, -1, -1):
				if String(a2.track_get_path(t)) == "CharacterArmature":
					a2.remove_track(t)
			var base_nm := _clean(f.get_basename())
			var nm2 := base_nm if base_nm.begins_with(pre + "_") else pre + "_" + base_nm
			var once := ["jump", "death", "turn", "to_stand", "to_kneel", "kneel_to", "stand_to", "landing", "entering", "exiting",
				"roll", "gesture", "nod", "uppercut", "sigh", "shake", "acknowledging", "cocky", "to_stop", "to_cover", "look_away"]
			var loops := true
			for w in once:
				if w in nm2:
					loops = false
			a2.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
			lib.add_animation(nm2, a2)
			n += 1
			r2.free()
	for l in ap.get_animation_library_list():
		ap.remove_animation_library(l)
	ap.add_animation_library("", lib)
	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, OUT, ResourceSaver.FLAG_COMPRESS)
	print("QBAKE %d clips (%d from Mixamo): %s" % [lib.get_animation_list().size(), n, ", ".join(lib.get_animation_list())])
	quit()

## "pistol run arc (2)" -> "run_arc_2"-style names: lower case, words joined by _.
func _clean(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while "__" in out:
		out = out.replace("__", "_")
	return out.strip_edges().trim_prefix("_").trim_suffix("_")

func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)
