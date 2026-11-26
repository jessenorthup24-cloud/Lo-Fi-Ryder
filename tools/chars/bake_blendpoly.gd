extends SceneTree
## The Blendpoly characters (Mixamo skeleton: Hips, Spine, LeftArm...), each baked from its FBX into a plain
## scene: assets/chars/bp/<id>.scn (the skeleton and the skinned body; no animation player: the avatar adds
## one with the shared retargeted clips, assets/chars/bp_anims.res). The UVs are kept for the pack's colour
## textures. ids: the file name, less "SM_Character_", lower case.
##   SRC=/path/to/fbx_dir godot --headless --path . -s tools/chars/bake_blendpoly.gd

const OUT := "res://assets/chars/bp/"

func _init() -> void:
	var dir := OS.get_environment("SRC")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ids := []
	for f in DirAccess.get_files_at(dir):
		if not f.to_lower().ends_with(".fbx"):
			continue
		var doc := FBXDocument.new()
		var st := FBXState.new()
		if doc.append_from_file(dir.path_join(f), st) != OK:
			push_warning("skip " + f)
			continue
		var root: Node3D = doc.generate_scene(st)
		for ap in root.find_children("*", "AnimationPlayer", true, false):
			ap.get_parent().remove_child(ap)
			ap.free()
		var id := f.get_basename().trim_prefix("SM_Character_").to_lower()
		root.name = id
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).name = "Body"
		_own(root, root)
		var ps := PackedScene.new()
		ps.pack(root)
		ResourceSaver.save(ps, OUT + id + ".scn", ResourceSaver.FLAG_COMPRESS)
		ids.append(id)
		root.free()
	ids.sort()
	print("BLENDPOLY ", ids.size(), " ", ids)
	quit()

func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)
