extends SceneTree
## The Mixamo clips, downloaded on one of the Blendpoly characters (the same skeleton all 34 share), into one
## library: assets/chars/bp_anims.res. Each is named <group>_<file name> ("pistol_walk", "x_entering_car");
## the hips' travel across the ground is taken off (they play in place: the game moves the body; their bob is
## kept), and the moves that go round and round loop.
##   CLIPS="act=/dir;pistol=/dir;rifle=/dir;x=/dir;..." godot --headless --path . -s tools/chars/bake_bp_clips.gd

const OUT := "res://assets/chars/bp_anims.res"
const ONCE := ["jump", "death", "turn", "to_stand", "to_kneel", "kneel_to", "stand_to", "landing", "entering", "exiting",
	"roll", "gesture", "nod", "sigh", "shake", "acknowledging", "cocky", "to_stop", "to_cover", "look_away", "ending",
	"to_freeze", "to_idle", "sit_to", "to_sit", "slide", "down", "up"]

func _init() -> void:
	var lib := AnimationLibrary.new()
	for spec in OS.get_environment("CLIPS").split(";"):
		var pre := spec.get_slice("=", 0)
		var dir := spec.get_slice("=", 1)
		for f in DirAccess.get_files_at(dir):
			if not f.to_lower().ends_with(".fbx") or f.begins_with("SM_"):
				continue
			var doc := FBXDocument.new()
			var st := FBXState.new()
			if doc.append_from_file(dir.path_join(f), st) != OK:
				push_warning("skip " + f)
				continue
			var r: Node = doc.generate_scene(st)
			var aps := r.find_children("*", "AnimationPlayer", true, false)
			if aps.is_empty():
				r.free()
				continue
			var ap: AnimationPlayer = aps[0]
			# (a clip saved with the character carries the character's own "Take 001" too: the clip's "mixamo_com")
			var take := "mixamo_com" if ap.has_animation("mixamo_com") else String(ap.get_animation_list()[0])
			var a: Animation = ap.get_animation(take).duplicate()
			for t in range(a.get_track_count() - 1, -1, -1):
				var path := String(a.track_get_path(t))
				# (the bones only, by their plain names: "Skeleton3D:Hips")
				if not path.begins_with("Skeleton3D:"):
					a.remove_track(t)
					continue
				var bone := path.get_slice(":", 1).trim_prefix("mixamorig_")
				a.track_set_path(t, NodePath("Skeleton3D:" + bone))
				if bone == "Hips" and a.track_get_type(t) == Animation.TYPE_POSITION_3D and a.track_get_key_count(t) > 0:
					var v0: Vector3 = a.track_get_key_value(t, 0)
					for k in a.track_get_key_count(t):
						var v: Vector3 = a.track_get_key_value(t, k)
						a.track_set_key_value(t, k, Vector3(v0.x, v.y, v0.z))
			var nm := _clean(f.get_basename())
			nm = nm if nm.begins_with(pre + "_") else pre + "_" + nm
			var loops := true
			for w in ONCE:
				if w in nm.trim_prefix(pre + "_"):
					loops = false
			a.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
			if lib.has_animation(nm):
				nm += "_b"
			lib.add_animation(nm, a)
			r.free()
	ResourceSaver.save(lib, OUT, ResourceSaver.FLAG_COMPRESS)
	print("BPCLIPS %d: %s" % [lib.get_animation_list().size(), ", ".join(lib.get_animation_list())])
	quit()

func _clean(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while "__" in out:
		out = out.replace("__", "_")
	return out.strip_edges().trim_prefix("_").trim_suffix("_")
