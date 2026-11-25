extends SceneTree
## Builds the island and checks that everything placed stands on something: for each static (and each
## knock-over-able thing), a ray down from just under its base to whatever's below (ground, road, a lot,
## another solid thing). Lists what floats (a gap under it) and what's sunk well into the ground, grouped
## by name, worst first.
##   godot --headless --path . -s res://tools/test/float_audit.gd [-- min_gap]
const Island := preload("res://scripts/game/island.gd")
const M := preload("res://scripts/core/models.gd")
# things that are meant to be up in the air (or hang off something with no collider)
const AIRBORNE := ["hoop", "gold_hoop", "flag", "banner", "lantern", "lights-colored", "cables", "overhead", "billboard",
	"crypt-large-roof", "crypt-small-roof", "scaffolding", "pennant", "bannerTower", "light", "lamp"]

var isl: Node3D
var frames := 0
var min_gap := 0.3

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		min_gap = float(a[0])
	isl = Island.new()
	isl.audit_on = true
	get_root().add_child(isl)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon.gdshader")
	isl.build(mat, 2)

func _process(_dt: float) -> bool:
	frames += 1
	if frames < 4:
		return false
	var space := isl.get_world_3d().direct_space_state
	var found := {}       # name -> [count, worst gap, at]
	var checked := 0
	var items := []
	items.append_array(isl.placed_log)
	for b in isl.breakables:
		items.append([b["pool"], Transform3D(b["basis"], b["pos"])])
	for it in items:
		var nm: String = it[0]
		var skip := false
		for w in AIRBORNE:
			if w in nm:
				skip = true
		if skip:
			continue
		var xf: Transform3D = it[1]
		var ab: AABB = M.get_mesh(nm).get_aabb()
		checked += 1
		# the middle of the base, and the four corners: how far down to something solid from each
		var pts := [Vector3(ab.get_center().x, ab.position.y, ab.get_center().z)]
		if ab.size.x * xf.basis.get_scale().x > 2.0 or ab.size.z * xf.basis.get_scale().z > 2.0:
			for o in [Vector3(ab.position.x, ab.position.y, ab.position.z), Vector3(ab.end.x, ab.position.y, ab.position.z),
					Vector3(ab.position.x, ab.position.y, ab.end.z), Vector3(ab.end.x, ab.position.y, ab.end.z)]:
				pts.append(o.lerp(pts[0], 0.15))
		var least := INF
		for lp in pts:
			var wp: Vector3 = xf * lp
			var q := PhysicsRayQueryParameters3D.create(wp + Vector3(0, 0.25, 0), wp + Vector3(0, -12.0, 0), 0xFFFFFFFF)
			var hit := space.intersect_ray(q)
			var gy: float = hit["position"].y if not hit.is_empty() else isl.height_at(wp.x, wp.z)
			gy = maxf(gy, isl.height_at(wp.x, wp.z))
			least = minf(least, wp.y - gy)
		var base: Vector3 = xf * pts[0]
		var g2: float = isl.height_at(base.x, base.z)
		var kind := ""
		if least > min_gap:
			kind = "FLOAT"
		elif base.y < g2 - 1.2 and ab.size.y * xf.basis.get_scale().y < 6.0:
			kind = "SUNK"
			least = base.y - g2
		if kind == "":
			continue
		var k2 := kind + " " + nm
		if not found.has(k2):
			found[k2] = [0, 0.0, Vector3.ZERO]
		found[k2][0] += 1
		if absf(least) > absf(float(found[k2][1])):
			found[k2][1] = least
			found[k2][2] = base
	var keys := found.keys()
	keys.sort_custom(func(x, y): return absf(float(found[x][1])) > absf(float(found[y][1])))
	for k in keys:
		var e: Array = found[k]
		print("%-46s x%-3d worst %+.2f m at (%.0f, %.1f, %.0f)" % [k, e[0], e[1], e[2].x, e[2].y, e[2].z])
	print("FLOAT AUDIT checked %d, %d kinds off the ground" % [checked, keys.size()])
	return true
