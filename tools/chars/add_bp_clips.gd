extends SceneTree
## More Mixamo clips into the library that's there (assets/chars/bp_anims.res), the same way bake_bp_clips.gd
## makes them: named <group>_<file name>, the hips' travel across the ground taken off, loops set. Only the
## names listed in LOOPS go round and round; everything else plays once.
##   ADD="fight=/dir" godot --headless --path . -s tools/chars/add_bp_clips.gd

const OUT := "res://assets/chars/bp_anims.res"
const LOOPS := ["zombie_crawl", "crawl_backwards", "crawling", "fight_idle", "laying_seizure", "tonic_seizure", "left_strafe_walking", "right_strafe_walking", "left_strafe", "right_strafe"]

func _init() -> void:
	var lib: AnimationLibrary = load(OUT)
	var added := []
	for spec in OS.get_environment("ADD").split(";"):
		var pre := spec.get_slice("=", 0)
		var dir := spec.get_slice("=", 1)
		for f in DirAccess.get_files_at(dir):
			if not f.to_lower().ends_with(".fbx"):
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
			var take := "mixamo_com" if ap.has_animation("mixamo_com") else String(ap.get_animation_list()[0])
			var a: Animation = ap.get_animation(take).duplicate()
			for t in range(a.get_track_count() - 1, -1, -1):
				var path := String(a.track_get_path(t))
				if not path.begins_with("Skeleton3D:"):
					a.remove_track(t)
					continue
				var bone := path.get_slice(":", 1).trim_prefix("mixamorig_")
				a.track_set_path(t, NodePath("Skeleton3D:" + bone))
				if bone == "Hips" and a.track_get_type(t) == Animation.TYPE_POSITION_3D and a.track_get_key_count(t) > 0:
					var v0: Vector3 = a.track_get_key_value(t, 0)
					var v1: Vector3 = a.track_get_key_value(t, a.track_get_key_count(t) - 1)
					var span := a.track_get_key_time(t, a.track_get_key_count(t) - 1) - a.track_get_key_time(t, 0)
					print("TRAVEL %s: %s per s (raw units)" % [f, (v1 - v0) / maxf(span, 0.01)])
					for k in a.track_get_key_count(t):
						var v: Vector3 = a.track_get_key_value(t, k)
						a.track_set_key_value(t, k, Vector3(v0.x, v.y, v0.z))
			var nm := pre + "_" + _clean(f.get_basename())
			a.loop_mode = Animation.LOOP_LINEAR if nm.trim_prefix(pre + "_") in LOOPS else Animation.LOOP_NONE
			a.optimize(0.01, 0.01, 3)
			if lib.has_animation(nm):
				lib.remove_animation(nm)
			lib.add_animation(nm, a)
			added.append("%s(%.2fs)" % [nm, a.length])
			r.free()
	ResourceSaver.save(lib, OUT, ResourceSaver.FLAG_COMPRESS)
	print("ADDED %d: %s" % [added.size(), ", ".join(added)])
	quit()

func _clean(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while "__" in out:
		out = out.replace("__", "_")
	return out.strip_edges().trim_prefix("_").trim_suffix("_")
