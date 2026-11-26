extends SceneTree
## The Blendpoly colour sheets (the pack's Textures: BlendPoly_City_Texture_0N_X.png): only the corner the
## characters' UVs use (the top-left 512 x 152 of the 1024 sheet), kept as images: assets/chars/bp/skin_<0N_X>.res.
## The avatar reads each triangle's colour from one (avatar.gd _paint).
##   TEX=/path/to/Textures godot --headless --path . -s tools/chars/bake_blendpoly_skins.gd

func _init() -> void:
	var dir := OS.get_environment("TEX")
	var n := 0
	for f in DirAccess.get_files_at(dir):
		if not f.to_lower().ends_with(".png"):
			continue
		var im := Image.load_from_file(dir.path_join(f))
		var crop := im.get_region(Rect2i(0, 0, im.get_width() / 2, int(im.get_height() * 0.1485)))
		crop.convert(Image.FORMAT_RGB8)
		var key := f.get_basename().trim_prefix("BlendPoly_City_Texture_")
		ResourceSaver.save(crop, "res://assets/chars/bp/skin_%s.res" % key, ResourceSaver.FLAG_COMPRESS)
		n += 1
	print("SKINS ", n)
	quit()
