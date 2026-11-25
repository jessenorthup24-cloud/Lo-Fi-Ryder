extends RefCounted
## Southside Green: the open ground between the bottom of town and the beach road used to be a bare lawn
## that the avenues' crossings led out onto. Now it's a park: a path up from each avenue's crossing to a
## long promenade, lamps along it, benches with people on them, clumps of trees, planters, a statue on a
## little plaza, a picnic table or two, dogs. Kept off the roads and the lots (the Stunt Yard, the Bowl).

const P := preload("res://scripts/core/palette.gd")

const AREA := Rect2(-275, 174, 400, 62)          # x, z, width, depth
const AVENUES := [-260.0, -200.0, -140.0, -80.0, -20.0, 40.0, 100.0]   # the avenues' crossings (x), districts.gd
const PROM_Z := 200.0                           # the promenade, east to west across the park
const PLAZA := Vector2(-50, 200)

static func populate(I, D) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 5521
	# the promenade, and a path up from each avenue that comes down this far
	var x0 := AREA.position.x
	var x1 := AREA.end.x
	# (in runs of open ground: it stops at a lot or a road and picks up again past it)
	var run0 := NAN
	var xx := x0
	while xx <= x1 + 0.1:
		var free := _ok(I, Vector2(xx, PROM_Z), 1.6)
		if free and is_nan(run0):
			run0 = xx
		elif (not free or xx >= x1) and not is_nan(run0):
			if xx - run0 > 12.0:
				_path(I, Vector2(run0, PROM_Z), Vector2(xx - 2.0, PROM_Z))
			run0 = NAN
		xx += 2.0
	for ax in AVENUES:
		if ax < x0 - 1.0 or ax > x1 + 1.0:
			continue
		var top := Vector2(ax, AREA.position.y + 2.0)
		if _ok(I, top, 1.6) and _ok(I, Vector2(ax, PROM_Z - 4.0), 1.6):
			_path(I, Vector2(ax, AREA.position.y - 4.0), Vector2(ax, PROM_Z))
	# the plaza: a round of paving, the statue in the middle, benches round it
	if I.is_free(PLAZA, Vector2(7, 7)):
		I.decal(PLAZA, Vector2(7, 7), 0.0, P.PATH)
		I.put("k_arena_statue", PLAZA.x, PLAZA.y, 0.0, 0.7, "box")
		for k in 4:
			var a := TAU * k / 4.0 + PI * 0.25
			var bp := PLAZA + Vector2(cos(a), sin(a)) * 5.6
			I.put_breakable("k_holi_bench", bp.x, bp.y, D._yaw_to(PLAZA - bp), 1.0, 0.8)
			if k % 2 == 0:
				D._person(I, bp.x, bp.y, "sit", D._yaw_to(PLAZA - bp), 0.5)
		I.block_rect(PLAZA, Vector2(7.5, 7.5), 0.0, 0.0)
	# lamps along the promenade, benches between them facing it
	var x := x0 + 6.0
	var side := 1.0
	while x < x1 - 4.0:
		var lp := Vector2(x, PROM_Z + 2.6 * side)
		if _ok(I, lp, 0.6) and _ok(I, Vector2(x, PROM_Z), 1.0) and absf(x - PLAZA.x) > 10.0:
			I.put("k_retro_detail-light-single", lp.x, lp.y, D._yaw_to(Vector2(0, -side)), 1.0, "cyl")
			I.block_rect(lp, Vector2(0.8, 0.8), 0.0, 0.0)
		var bp2 := Vector2(x + 7.0, PROM_Z + 3.0 * side)
		if _ok(I, bp2, 1.4) and _ok(I, Vector2(bp2.x, PROM_Z), 1.0) and absf(bp2.x - PLAZA.x) > 10.0:
			I.put_breakable("k_retro_detail-bench", bp2.x, bp2.y, D._yaw_to(Vector2(0, -side)), 1.0, 0.8)
			if rr.randf() < 0.45:
				D._person(I, bp2.x, bp2.y, "sit", D._yaw_to(Vector2(0, -side)), 0.5)
			I.block_rect(bp2, Vector2(1.4, 0.8), 0.0, 0.0)
		x += 14.0
		side = -side
	# clumps of trees, planters and picnic tables on the lawns either side
	var trees := ["k_sub_tree-large", "k_castle_tree-large", "k_surv_tree", "k_castle_tree-small", "k_surv_tree-autumn"]
	var placed := 0
	for k in 520:
		var p := Vector2(rr.randf_range(x0, x1), rr.randf_range(AREA.position.y + 3.0, AREA.end.y))
		if absf(p.y - PROM_Z) < 5.0 or _near_path(p, x0, x1) or not _ok(I, p, 2.2):
			continue
		var roll := rr.randf()
		if roll < 0.72:
			I.put(trees[rr.randi_range(0, trees.size() - 1)], p.x, p.y, rr.randf() * TAU, rr.randf_range(0.8, 1.15), "cyl")
			I.block_rect(p, Vector2(2.2, 2.2), 0.0, 0.0)
		elif roll < 0.84:
			I.put("k_sub_planter", p.x, p.y, rr.randf() * TAU, 1.0, "box")
			I.block_rect(p, Vector2(1.6, 1.6), 0.0, 0.0)
		elif roll < 0.94:
			I.put("k_surv_workbench", p.x, p.y, rr.randf() * TAU, 1.0, "box")
			D._person(I, p.x + 1.4, p.y, "sit", rr.randf() * TAU, 0.45)
			I.block_rect(p, Vector2(2.0, 2.0), 0.0, 0.0)
		else:
			D._pet(I, ["dog", "dog", "bunny"][rr.randi_range(0, 2)], p.x, p.y)
		placed += 1
		if placed > 130:
			break
	# a few people out for a walk on the promenade
	for k in 6:
		var wp := Vector2(rr.randf_range(x0 + 6, x1 - 6), PROM_Z + rr.randf_range(-0.8, 0.8))
		if _ok(I, wp, 0.6):
			D._person(I, wp.x, wp.y, "stand", rr.randf_range(-0.3, 0.3) + (PI * 0.5 if k % 2 == 0 else -PI * 0.5))

## A paved path (a decal) from a to b, kept clear.
static func _path(I, a: Vector2, b: Vector2) -> void:
	var m := (a + b) * 0.5
	var d := b - a
	var hs := Vector2(1.6, d.length() * 0.5) if absf(d.y) > absf(d.x) else Vector2(d.length() * 0.5, 1.6)
	I.decal(m, hs, 0.0, P.PATH)

static func _near_path(p: Vector2, x0: float, x1: float) -> bool:
	for ax in AVENUES:
		if ax >= x0 - 1.0 and ax <= x1 + 1.0 and absf(p.x - ax) < 4.0 and p.y < PROM_Z:
			return true
	return false

## Free ground, off the roads.
static func _ok(I, p: Vector2, r: float) -> bool:
	if not I.is_free(p, Vector2(r, r)):
		return false
	for ri in I.roads.size():
		var nr: Array = I.road_nearest(ri, p)
		if float(nr[0]) < float(I.roads[ri]["w"]) * 0.5 + 3.5 + r:
			return false
	return true
