extends Node3D
## Safe heists, and cash.
##
## Twenty-five safes stand about the island (always in the same places). Walk up to one and start the heist:
## the map rings a patch of town where a core drill's been stashed, and you've 90 seconds to find it and
## get it back to the safe before someone tips off the police (after that they're after you). Mount the drill
## on the safe and it starts cutting: two minutes, and every police car in town knows where you are (stay
## near it: it only cuts with you there; die and it's over). Then the door swings open: grab the duffle, lose
## the police, and take the money to the safehouse. A cracked safe's empty for a while (20 minutes).
##
## Cash is the money of the game (the save's "coins" key, kept as it was). People and officers you take down
## drop a little; it's picked up by walking or driving over it.

const PROP := "res://assets/props/"
const SCALE := 2.3             # the props are made at the size of the people (the people are 2.3x)
const SAFE_SCALE := 3.0        # (the safe a bit bigger: a proper strongbox next to these chunky people)
const SAFES := 25
const FETCH_T := 90.0
const DEFEND_T := 120.0
const ZONE_R := 85.0           # the ring on the map round where the drill is (it's somewhere inside: look)
const DRILL_NEAR := 300.0      # how far away the drill can be...
const DRILL_FAR := 550.0       # ...and no further
const LEAVE_R := 45.0          # further than this from the drill and it stops cutting
const RESET_S := 1200          # seconds (real) till a cracked safe's full again
const PAY := [7500, 12500]     # what's in a safe
const OPEN := 1.75             # the door's angle, open (rad)

enum { IDLE, FETCH, RETURN, DEFEND, CRACKED, ESCAPE, DELIVER, STASH }
const STEP_NAMES := ["", "Find the tool bag", "Bring the tool bag to the safe", "Defend the drill", "Grab the money",
	"Lose the police", "Take the money to the safehouse", "Stash the bag in your car"]
const CREW_CUT := 0.15         # each friend who comes along takes this share
## The more heists you've pulled, the bigger they get: more money, a longer drill, more bags to carry out
## (a trip to your car with each), and later on the drill can burn out halfway (go and find another).
const TIER_MAX := 6

var game: Node
var island: Node
var state := IDLE
var safes: Array = []          # {id, pos, yaw, node, door, open (0..1), dot}
var safehouse := {}            # {pos, yaw, node, dot}
var cur: Dictionary = {}       # the safe you're on
var t := 0.0                   # the drill hunt's clock / the drilling's progress (s)
var tipped := false            # the police were tipped off
var drill: Node3D              # the drill (where it's stashed, then on the safe)
var drill_bit: Node3D
var drill_light: OmniLight3D
var zone_c := Vector3.ZERO     # the middle of the ring on the map
var zone_mi: MeshInstance3D
var carrying := ""             # "", "tool_duffle" (the drill's bag), "duffle" (the money)
var duffle: Node3D
var near: Dictionary = {}      # the safe you're stood by (the START HEIST button), {} if none
var cash: Array = []           # dropped cash: {node, value, t}
var pay := 0
var tier := 0
var defend_t := DEFEND_T       # how long this one's drill takes
var drill_t := 0.0             # how far the drill's got (kept through a breakdown)
var break_at := -1.0           # the drill burns out at this point (-1: it won't)
var bags_total := 1
var bags_left := 1
var crew_in: Array = []        # the names of the friends in on it (each takes CREW_CUT)
var _drill_snd: AudioStreamPlayer3D
var _carry_on: Node3D          # what's on your back (the avatar it's on)
var _cash_mesh: Mesh
var _beacon_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _hint_t := 0.0
var _road_hash := {}           # 25 m cells -> road points in them (for "how far from a road")

func setup(g: Node) -> void:
	game = g
	island = g.island
	_cash_mesh = load(PROP + "cash.res")
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beacon_mat.albedo_color = Color(0.35, 1.0, 0.45, 0.35)
	_beacon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(1.0, 0.55, 0.15, 0.4)
	_place_safes()
	_place_safehouse()
	print("HEIST %d safes, safehouse at %s" % [safes.size(), safehouse["pos"]])

# ------------------------------------------------------------------ the world

## Spots by the side of a road (on the verge or the pavement, clear of buildings and other roads).
func _roadside(rng: RandomNumberGenerator, near_p: Vector2, r_lo: float, r_hi: float, tries: int, clear := 1.0) -> Dictionary:
	var roads: Array = []
	for r in island.roads:
		if r["kind"] in ["main", "street", "road", "lane", "ring"]:
			roads.append(r)
	for k in tries:
		var r: Dictionary = roads[rng.randi() % roads.size()]
		var pts: PackedVector2Array = r["pts"]
		var i := rng.randi() % pts.size()
		var p := pts[i]
		if near_p != Vector2.INF:
			var d := p.distance_to(near_p)
			if d < r_lo or d > r_hi:
				continue
		var tg: Vector2 = island._tangent(pts, i, r["closed"])
		var side := Vector2(-tg.y, tg.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var at := p + side * (float(r["w"]) * 0.5 + 2.6)
		if island.height_at(at.x, at.y) < 0.6 or island.surface_at(at.x, at.y) == 1:
			continue
		if not island.is_free(at, Vector2(clear, clear)):
			continue
		var stunt: Rect2 = island.stunt.get("rect", Rect2())
		if stunt.grow(15.0).has_point(at):
			continue
		# (facing the road)
		var yaw := atan2(-side.x, -side.y)
		return {"pos": Vector3(at.x, island.height_at(at.x, at.y), at.y), "yaw": yaw}
	return {}

## Safes are stashed where you'd not see them from the road: round the back of buildings, under the
## railway viaduct, behind the gas stations.
func _place_safes() -> void:
	_build_road_hash()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var cands: Array = []
	# behind the gas stations
	for st in island.stations:
		var c: Vector3 = st["pos"]
		var sp := _tucked(rng, Vector2(c.x, c.z), 10.0, 26.0, 160, 5.0)
		if not sp.is_empty():
			sp["kind"] = "station"
			cands.append(sp)
	# under the viaduct
	if island.rail and (island.rail.pts as PackedVector2Array).size() > 0:
		var rp: PackedVector2Array = island.rail.pts
		var n := rp.size()
		for k in 10:
			var i := int(float(k) / 10.0 * n + rng.randi_range(0, n / 20)) % n
			for tries in 30:
				var j := (i + tries * 3) % n
				var tg := (rp[(j + 1) % n] - rp[j]).normalized()
				var off := rng.randf_range(2.5, 6.0) * (1.0 if rng.randf() < 0.5 else -1.0)
				var at := rp[j] + Vector2(-tg.y, tg.x) * off
				if _ok_spot(at, 1.0) and _road_dist(at) > 3.0:
					cands.append({"pos": Vector3(at.x, island.height_at(at.x, at.y), at.y), "yaw": atan2(tg.x, tg.y) + PI * 0.5, "kind": "viaduct"})
					break
	# round the back of buildings, about town
	var places: Array = island.places.duplicate()
	for k in 60:
		var pl: Dictionary = places[rng.randi() % places.size()]
		if pl["name"] == "Stunt Yard":
			continue
		var c2: Vector3 = pl["pos"]
		var sp2 := _tucked(rng, Vector2(c2.x, c2.z), 0.0, float(pl["r"]), 120, 12.0)
		if not sp2.is_empty():
			sp2["kind"] = "tucked"
			cands.append(sp2)
	# spread out: no two within 70 m (the gas stations and the viaduct first)
	var spots: Array = []
	for cd in cands:
		if spots.size() >= SAFES:
			break
		var ok := true
		for o in spots:
			if (o["pos"] as Vector3).distance_to(cd["pos"]) < 70.0:
				ok = false
				break
		if ok:
			spots.append(cd)
	# (short of 25: fill in by the roads)
	var guard := 0
	while spots.size() < SAFES and guard < 3000:
		guard += 1
		var s2 := _roadside(rng, Vector2.INF, 0, 0, 1, 1.2)
		if s2.is_empty():
			continue
		var ok2 := true
		for o in spots:
			if (o["pos"] as Vector3).distance_to(s2["pos"]) < 70.0:
				ok2 = false
				break
		if ok2:
			spots.append(s2)
	var kinds := {}
	for sp4 in spots:
		kinds[sp4.get("kind", "road")] = int(kinds.get(sp4.get("kind", "road"), 0)) + 1
	print("HEIST safe spots ", kinds)
	for i in spots.size():
		var sp3: Dictionary = spots[i]
		var sf := {"id": "s%d" % i, "pos": sp3["pos"], "yaw": sp3["yaw"], "open": 0.0}
		_build_safe(sf)
		safes.append(sf)
	_refresh_dots()

## A spot out of sight: off the road (at least `off` metres from one), backed onto a wall (a building's, a
## fence's), in an annulus round c. Facing out from the wall.
func _tucked(rng: RandomNumberGenerator, c: Vector2, r_lo: float, r_hi: float, tries: int, off: float) -> Dictionary:
	for k in tries:
		var a := rng.randf() * TAU
		var d := rng.randf_range(r_lo, maxf(r_hi, r_lo + 1.0))
		var at := c + Vector2(cos(a), sin(a)) * d
		if not _ok_spot(at, 1.1) or _road_dist(at) < off:
			continue
		# a wall close behind it?
		for w in 8:
			var wa := TAU * w / 8.0
			var dir := Vector2(cos(wa), sin(wa))
			if island.is_blocked(at.x + dir.x * 2.6, at.y + dir.y * 2.6):
				var front := -dir
				return {"pos": Vector3(at.x, island.height_at(at.x, at.y), at.y), "yaw": atan2(front.x, front.y)}
	return {}

func _ok_spot(at: Vector2, clear: float) -> bool:
	if island.height_at(at.x, at.y) < 0.6 or island.surface_at(at.x, at.y) == 1:
		return false
	var stunt: Rect2 = island.stunt.get("rect", Rect2())
	if stunt.grow(15.0).has_point(at):
		return false
	return island.is_free(at, Vector2(clear, clear))

func _build_road_hash() -> void:
	for r in island.roads:
		var pts: PackedVector2Array = r["pts"]
		for i in range(0, pts.size(), 2):
			var key := Vector2i(floori(pts[i].x / 25.0), floori(pts[i].y / 25.0))
			if not _road_hash.has(key):
				_road_hash[key] = PackedVector2Array()
			(_road_hash[key] as PackedVector2Array).append(pts[i])

## Roughly how far it is to the middle of the nearest road (a road's half its width either side of that).
func _road_dist(p: Vector2) -> float:
	var best := 60.0
	var k0 := Vector2i(floori(p.x / 25.0), floori(p.y / 25.0))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var arr = _road_hash.get(k0 + Vector2i(dx, dz))
			if arr == null:
				continue
			for q in (arr as PackedVector2Array):
				best = minf(best, q.distance_to(p))
	return maxf(best - 6.0, 0.0)

func _build_safe(sf: Dictionary) -> void:
	var n := StaticBody3D.new()
	n.collision_layer = 1
	n.collision_mask = 0
	add_child(n)
	n.global_transform = Transform3D(Basis(Vector3.UP, sf["yaw"]), sf["pos"])
	var mi := MeshInstance3D.new()
	mi.mesh = load(PROP + "safe.res")
	mi.scale = Vector3.ONE * SAFE_SCALE
	mi.set_surface_override_material(0, game.toon)
	n.add_child(mi)
	var pv: Array = _meta("safe")["pivots"]["doorpivot"]
	var hinge := Node3D.new()
	hinge.position = Vector3(pv[0], pv[1], pv[2])
	mi.add_child(hinge)
	var door := MeshInstance3D.new()
	door.mesh = load(PROP + "safe_doorpivot.res")
	door.set_surface_override_material(0, game.toon)
	hinge.add_child(door)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.5, 0.52, 0.47) * SAFE_SCALE
	cs.shape = bx
	cs.position = Vector3(0, 0.26 * SAFE_SCALE, 0)
	n.add_child(cs)
	sf["node"] = n
	sf["door"] = hinge
	var dot: MeshInstance3D = island.map_marker(sf["pos"], Color("8d9bb5"), 4.5)
	sf["dot"] = dot

## Where the money goes: your mansion, once it's built; the safehouse till then.
func _drop_at() -> Vector3:
	if game.property != null and game.property.finished("mansion"):
		return game.property.mansion_door()
	return safehouse["pos"]

func _place_safehouse() -> void:
	# by where you start, on Main Street
	var start := Vector2(-262, 61)
	var s := {}
	var best := INF
	for r in island.roads:
		if not (r["kind"] in ["main", "street", "road", "lane"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		for i in range(0, pts.size(), 2):
			var d := pts[i].distance_to(start)
			if d < 30.0 or d > 140.0 or d > best:
				continue
			var tg: Vector2 = island._tangent(pts, i, r["closed"])
			for sd in [1.0, -1.0]:
				var side: Vector2 = Vector2(-tg.y, tg.x) * float(sd)
				var at: Vector2 = pts[i] + side * (float(r["w"]) * 0.5 + 3.5)
				if island.height_at(at.x, at.y) > 0.6 and island.surface_at(at.x, at.y) != 1 and island.is_free(at, Vector2(2.0, 2.0)):
					best = d
					s = {"pos": Vector3(at.x, island.height_at(at.x, at.y), at.y), "yaw": atan2(-side.x, -side.y)}
					break
	if s.is_empty():
		s = {"pos": Vector3(-240, island.height_at(-240, 75), 75), "yaw": 0.0}
	safehouse = s
	var n := Node3D.new()
	add_child(n)
	n.global_position = s["pos"]
	# a green column of light, and a sign
	var beam := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 2.2
	cy.bottom_radius = 2.2
	cy.height = 26.0
	cy.cap_top = false
	cy.cap_bottom = false
	beam.mesh = cy
	beam.material_override = _beacon_mat
	beam.position.y = 13.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(beam)
	var lb := Label3D.new()
	lb.text = "SAFEHOUSE"
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.font_size = 96
	lb.outline_size = 18
	lb.modulate = Color(0.6, 1.0, 0.65)
	lb.position.y = 4.0
	lb.no_depth_test = false
	n.add_child(lb)
	s["node"] = n
	s["beam"] = beam
	var dot: MeshInstance3D = island.map_marker(s["pos"], Color("3fd26b"), 7.0)
	s["dot"] = dot
	_show_safehouse(false)

func _show_safehouse(on: bool) -> void:
	(safehouse["node"] as Node3D).visible = on
	(safehouse["dot"] as Node3D).visible = on

static func _meta(k: String) -> Dictionary:
	var f := FileAccess.open(PROP + "props_meta.json", FileAccess.READ)
	if f == null:
		return {"pivots": {"doorpivot": [0.212, 0.26, 0.25], "bitpivot": [0, 0.48, 0.115]}}
	return (JSON.parse_string(f.get_as_text()) as Dictionary)[k]

## A safe's empty for a while after you've had it.
func _cracked(sf: Dictionary) -> bool:
	var at := int((game.save.data.get("safes", {}) as Dictionary).get(sf["id"], 0))
	return at > 0 and int(Time.get_unix_time_from_system()) - at < RESET_S

func _refresh_dots() -> void:
	for sf in safes:
		var dot: MeshInstance3D = sf["dot"]
		dot.visible = not _cracked(sf) and (state == IDLE or sf == cur)
		var col := Color("ffd34d") if sf == cur else Color("8d9bb5")
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = col
		dot.material_override = mat
		# (cracked: the door stands open)
		if state == IDLE or sf != cur:
			sf["open"] = 1.0 if _cracked(sf) else 0.0
			(sf["door"] as Node3D).rotation.y = OPEN * float(sf["open"])

# ------------------------------------------------------------------ every frame

func tick(dt: float) -> void:
	var you: Node3D = game.you()
	var yp := you.global_position
	var on_foot: bool = game.on_foot
	_cash_tick(dt, yp)
	_carry_tick()
	_hint_t -= dt
	match state:
		IDLE:
			near = {}
			if on_foot and not game.challenge_on() and (game.Progress.level(game.save) >= game.Progress.HEIST_LEVEL or game.args.has("heisttest")):
				for sf in safes:
					if (sf["pos"] as Vector3).distance_to(yp) < 3.4 and not _cracked(sf):
						near = sf
						break
			if on_foot and _hint_t <= 0.0 and game.Progress.level(game.save) < game.Progress.HEIST_LEVEL:
				for sf in safes:
					if (sf["pos"] as Vector3).distance_to(yp) < 4.0:
						_hint_t = 6.0
						game.ui.toast("A safe. Heists open up at level %d" % game.Progress.HEIST_LEVEL, "lock", Color(0.12, 0.13, 0.16, 0.85), Color.WHITE, 2.4)
						break
			game.ui.heist_prompt("START HEIST" if not near.is_empty() else "")
		FETCH, RETURN:
			t += dt
			if not tipped and t >= FETCH_T:
				tipped = true
				game.police.start(2.0, "Someone tipped off the police")
				game.ui.toast("Tipped off: the police are coming", "star", Color("ff4f6b"), Color.WHITE, 2.6)
			if state == FETCH:
				drill_light.light_energy = 1.2 + sin(Time.get_ticks_msec() * 0.008) * 0.8
				if drill.global_position.distance_to(yp) < 2.6:
					if on_foot:
						_pick_drill()
					elif _hint_t <= 0.0:
						_hint_t = 3.0
						game.ui.toast("Get out to grab the drill", "help", K_PAPER(), Color.WHITE, 1.6)
			elif (cur["pos"] as Vector3).distance_to(yp) < 3.6:
				if on_foot:
					_mount()
				elif _hint_t <= 0.0:
					_hint_t = 3.0
					game.ui.toast("Get out to set up the drill", "help", K_PAPER(), Color.WHITE, 1.6)
			var left := maxf(FETCH_T - t, 0.0)
			game.ui.heist_hud(STEP_NAMES[state], ("%d:%02d" % [int(left) / 60, int(left) % 60]) if not tipped else "The police are onto you", left / FETCH_T, tipped)
		DEFEND:
			var there := yp.distance_to(cur["pos"]) < LEAVE_R
			if there:
				drill_t += dt
			if break_at > 0.0 and drill_t >= break_at:
				_burn_out()
				return
			drill_bit.rotate_object_local(Vector3.FORWARD, dt * (30.0 if there else 4.0))
			if there and randf() < dt * 20.0:
				var tip: Vector3 = drill_bit.global_transform * Vector3(0, 0, 0.2)
				game.fx.spark_burst(tip, (drill.global_transform.basis.z).normalized(), 3, 4.0)
			_drill_snd.pitch_scale = 1.0 if there else 0.55
			game.police.heat_pts = maxf(game.police.heat_pts, 3.0)
			var left := maxf(defend_t - drill_t, 0.0)
			game.ui.heist_hud(STEP_NAMES[state] if there else "Get back to the drill!", "%d:%02d" % [int(left) / 60, int(left) % 60], drill_t / defend_t, not there)
			if drill_t >= defend_t:
				_crack()
		STASH:
			var cpos: Vector3 = game.car.global_position
			game.ui.heist_hud(STEP_NAMES[state], "%d more in the safe" % bags_left, float(bags_total - bags_left) / float(bags_total), game.police.wanted())
			if on_foot and cpos.distance_to(yp) < 4.5:
				_stash()
		CRACKED:
			var sf: Dictionary = cur
			sf["open"] = move_toward(float(sf["open"]), 1.0, dt * 1.2)
			(sf["door"] as Node3D).rotation.y = OPEN * ease(float(sf["open"]), 0.4)
			game.ui.heist_hud(STEP_NAMES[state], ("$" + _fmt(pay)) + ("  ·  bag %d of %d" % [bags_total - bags_left + 1, bags_total] if bags_total > 1 else ""), 1.0, false)
			if duffle and float(sf["open"]) > 0.85 and duffle.global_position.distance_to(yp) < 2.8 and on_foot:
				_grab_duffle()
		ESCAPE:
			game.ui.heist_hud(STEP_NAMES[state], "$" + _fmt(pay) + " in the bag", -1.0, true)
			if not game.police.wanted():
				_escaped()
		DELIVER:
			game.ui.heist_hud(STEP_NAMES[state], "$" + _fmt(pay) + " in the bag", -1.0, false)
			if game.police.wanted():
				state = ESCAPE
				game.ui.toast("They've spotted you: lose them first", "star", Color("ff4f6b"), Color.WHITE, 2.0)
			elif _drop_at().distance_to(yp) < 7.0:
				_complete()

static func K_PAPER() -> Color:
	return Color(0.1, 0.11, 0.15, 0.9)

static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

## Where the GPS takes you during a heist ({} when it shouldn't: you're searching the ring).
func route() -> Dictionary:
	match state:
		FETCH:
			if Vector2(zone_c.x, zone_c.z).distance_to(Vector2(game.you().global_position.x, game.you().global_position.z)) > ZONE_R * 0.8:
				return {"pos": zone_c, "name": "The drill's round here", "kind": "heist"}
		RETURN, DEFEND, CRACKED:
			if (cur["pos"] as Vector3).distance_to(game.you().global_position) > 12.0:
				return {"pos": cur["pos"], "name": "The safe", "kind": "heist"}
		DELIVER:
			return {"pos": _drop_at(), "name": "Your mansion" if _drop_at() != safehouse["pos"] else "Safehouse", "kind": "heist"}
	return {}

## The nearest safe that's not been cracked lately ({} if none).
func nearest_safe(p: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for sf in safes:
		if _cracked(sf):
			continue
		var d := (sf["pos"] as Vector3).distance_to(p)
		if d < bd:
			bd = d
			best = sf
	return best

func active() -> bool:
	return state != IDLE

# ------------------------------------------------------------------ the steps

## The START HEIST button.
func start() -> void:
	if state != IDLE or near.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var sp: Vector3 = near["pos"]
	# the drill's tucked away too (behind something, off the road), a good way off
	var s := _tucked(rng, Vector2(sp.x, sp.z), DRILL_NEAR, DRILL_FAR, 1500, 4.0)
	if s.is_empty():
		s = _roadside(rng, Vector2(sp.x, sp.z), DRILL_NEAR, DRILL_FAR, 3000, 0.8)
	if s.is_empty():
		s = _roadside(rng, Vector2(sp.x, sp.z), 150.0, 600.0, 3000, 0.6)
	if s.is_empty():
		game.ui.toast("No drill to be had right now", "help")
		return
	cur = near
	near = {}
	state = FETCH
	t = 0.0
	tipped = false
	tier = clampi(int(game.save.stat("heists")) if not game.args.has("heisttier") else int(game.args["heisttier"]), 0, TIER_MAX)
	pay = int(rng.randi_range(PAY[0], PAY[1]) * (1.0 + 0.35 * tier)) / 50 * 50
	defend_t = DEFEND_T + 25.0 * tier
	drill_t = 0.0
	bags_total = 1 + (1 if tier >= 2 else 0) + (1 if tier >= 4 else 0)
	bags_left = bags_total
	break_at = defend_t * rng.randf_range(0.35, 0.7) if tier >= 1 and rng.randf() < 0.3 + 0.1 * tier else -1.0
	crew_in.clear()
	for d in game.crew.drivers:
		if String(d["mode"]) == "crew":
			crew_in.append(String(game.crew.ROSTER[int(d["who"])]["name"]))
	game.ui.heist_prompt("")
	# the tool bag (the core drill's in it), stashed by a road somewhere; the ring on the map is round it,
	# but not centred on it
	drill = _prop("tool_duffle")
	add_child(drill)
	drill.global_transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU), s["pos"])
	drill_bit = null
	drill_light = OmniLight3D.new()
	drill_light.light_color = Color(1.0, 0.3, 0.25)
	drill_light.omni_range = 5.0
	drill_light.position.y = 1.4
	drill.add_child(drill_light)
	var a := rng.randf() * TAU
	zone_c = (s["pos"] as Vector3) + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, ZONE_R * 0.7)
	zone_mi = MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = ZONE_R
	cy.bottom_radius = ZONE_R
	cy.height = 0.5
	cy.radial_segments = 40
	zone_mi.mesh = cy
	zone_mi.material_override = _ring_mat
	zone_mi.layers = island.MAP_LAYER
	zone_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(zone_mi)
	zone_mi.global_position = Vector3(zone_c.x, 302.0, zone_c.z)
	_refresh_dots()
	game.sfx("mission", -4.0, 1.0)
	game.ui.toast("Find the yellow tool bag (the drill's in it): it's in the orange ring on the map", "map", Color("ffb347"), Color.WHITE, 3.2)
	var more := []
	if bags_total > 1:
		more.append("%d bags in this one" % bags_total)
	if not crew_in.is_empty():
		more.append("%s in for %d%% each" % [", ".join(crew_in), int(CREW_CUT * 100.0)])
	if not more.is_empty():
		get_tree().create_timer(3.4, false).timeout.connect(func():
			game.ui.toast(" · ".join(more), "group", Color(0.12, 0.13, 0.16, 0.9), Color.WHITE, 3.0))

func _pick_drill() -> void:
	state = RETURN
	drill.queue_free()
	drill = null
	zone_mi.queue_free()
	zone_mi = null
	carrying = "tool_duffle"
	game.sfx("mag_in", -2.0, 0.6)
	game.ui.toast("Got the tool bag: back to the safe", "check", Color("3fd26b"), Color.WHITE, 2.2)

func _mount() -> void:
	state = DEFEND
	t = 0.0
	carrying = ""
	if drill and is_instance_valid(drill):
		drill.queue_free()          # (the burnt-out one, if it broke down)
	var sf: Dictionary = cur
	var n: Node3D = sf["node"]
	# the drill on its tripod in front of the door, bit to the lock
	drill = _prop("drill")
	add_child(drill)
	var fwd: Vector3 = n.global_transform.basis.z
	drill.global_transform = Transform3D(Basis(Vector3.UP, float(sf["yaw"]) + PI), n.global_position + fwd * (0.21 * SAFE_SCALE + 0.78))
	drill_bit = drill.get_meta("bit")
	_drill_snd = AudioStreamPlayer3D.new()
	var st = load("res://assets/audio/sfx/drill.wav")
	if st is AudioStreamWAV:
		st = (st as AudioStreamWAV).duplicate()
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * st.mix_rate)
	_drill_snd.stream = st
	_drill_snd.bus = "SFX"
	_drill_snd.unit_size = 6.0
	_drill_snd.volume_db = -4.0
	drill.add_child(_drill_snd)
	_drill_snd.play()
	game.police.pinned = true
	if game.police.wanted():
		game.police.heat_pts = maxf(game.police.heat_pts, 3.0)
	else:
		game.police.start(3.0, "Alarm: a safe's being drilled")
	game.ui.toast(("Drilling: hold them off for %d:%02d" % [int(defend_t - drill_t) / 60, int(defend_t - drill_t) % 60]) if drill_t <= 0.0 else "New drill on: keep them off it",
		"star", Color("ff4f6b"), Color.WHITE, 2.6)

func _crack() -> void:
	state = CRACKED
	# (still a shootout while you get the bags out: they don't come and cuff you mid-heist)
	if _drill_snd:
		_drill_snd.stop()
	game.sfx("safe_open", 0.0)
	var sf: Dictionary = cur
	sf["open"] = 0.0
	var n: Node3D = sf["node"]
	duffle = _prop("duffle")
	add_child(duffle)
	# (in the doorway, between the safe and the drill)
	duffle.global_transform = Transform3D(Basis(Vector3.UP, float(sf["yaw"])), n.global_position + n.global_transform.basis.z * (0.21 * SAFE_SCALE + 0.35) + Vector3(0, 0.02, 0))
	var saves: Dictionary = game.save.data.get("safes", {})
	saves[sf["id"]] = int(Time.get_unix_time_from_system())
	game.save.data["safes"] = saves
	game.ui.toast("It's open: grab the money", "check", Color("3fd26b"), Color.WHITE, 2.2)

func _grab_duffle() -> void:
	duffle.queue_free()
	duffle = null
	bags_left -= 1
	carrying = "duffle"
	game.sfx("cash", 0.0, 0.9)
	game.police.heat_pts = maxf(game.police.heat_pts, 4.0)
	if not game.police.wanted():
		game.police.start(4.0, "Safe robbery")
	if bags_left > 0:
		# (more in there: this one to your car first, then back for the next)
		state = STASH
		game.ui.toast("Get this bag in your car: %d more to come" % bags_left, "car", Color("ffb347"), Color.WHITE, 2.4)
		return
	if drill:
		var dn := drill
		get_tree().create_timer(20.0).timeout.connect(func():
			if is_instance_valid(dn):
				dn.queue_free())
		drill = null
	game.police.pinned = false
	state = ESCAPE

## A bag in the car: back to the safe for the next.
func _stash() -> void:
	carrying = ""
	game.sfx("cash", -2.0, 1.1)
	state = CRACKED
	var sf: Dictionary = cur
	var n: Node3D = sf["node"]
	duffle = _prop("duffle")
	add_child(duffle)
	duffle.global_transform = Transform3D(Basis(Vector3.UP, float(sf["yaw"])), n.global_position + n.global_transform.basis.z * (0.21 * SAFE_SCALE + 0.35) + Vector3(0, 0.02, 0))
	game.ui.toast("In the car. Back to the safe: %d to go" % bags_left, "check", Color("3fd26b"), Color.WHITE, 2.0)

## The drill's burnt out halfway: smoke, and off to find another (closer this time). It picks up where the
## last one stopped.
func _burn_out() -> void:
	break_at = -1.0
	if _drill_snd:
		_drill_snd.stop()
	if drill:
		for k in 6:
			game.fx.flame(drill.global_position + Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3)), 0.5, Vector3(0, 0.6, 0), 0.6)
	game.sfx("backfire", -2.0, 0.7)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var sp: Vector3 = cur["pos"]
	var s2 := _tucked(rng, Vector2(sp.x, sp.z), 140.0, 300.0, 1500, 4.0)
	if s2.is_empty():
		s2 = _roadside(rng, Vector2(sp.x, sp.z), 140.0, 400.0, 3000, 0.8)
	if s2.is_empty():
		return
	state = FETCH
	t = maxf(t, FETCH_T * 0.5)
	var old := drill
	drill = _prop("tool_duffle")
	add_child(drill)
	drill.global_transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU), s2["pos"])
	drill_bit = null
	drill_light = OmniLight3D.new()
	drill_light.light_color = Color(1.0, 0.3, 0.25)
	drill_light.omni_range = 5.0
	drill_light.position.y = 1.4
	drill.add_child(drill_light)
	if old and is_instance_valid(old):
		get_tree().create_timer(15.0, false).timeout.connect(func():
			if is_instance_valid(old):
				old.queue_free())
	var a := rng.randf() * TAU
	zone_c = (s2["pos"] as Vector3) + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, ZONE_R * 0.6)
	zone_mi = MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = ZONE_R
	cy.bottom_radius = ZONE_R
	cy.height = 0.5
	cy.radial_segments = 40
	zone_mi.mesh = cy
	zone_mi.material_override = _ring_mat
	zone_mi.layers = island.MAP_LAYER
	add_child(zone_mi)
	zone_mi.global_position = Vector3(zone_c.x, 302.0, zone_c.z)
	game.ui.toast("The drill's burnt out! Find another tool bag: orange ring on the map", "map", Color("ff4f6b"), Color.WHITE, 3.0)

func _escaped() -> void:
	state = DELIVER
	_show_safehouse(true)
	game.ui.toast("Lost them: take the money to the safehouse", "home", Color("3fd26b"), Color.WHITE, 2.6)

func _complete() -> void:
	# your crew take their cut
	var cut := int(float(pay) * CREW_CUT) * crew_in.size()
	var mine := pay - cut
	game.save.data["coins"] = int(game.save.data["coins"]) + mine
	game.save.add_stat("heists", 1)
	game.sfx("mission", 0.0)
	game.sfx("cash", -2.0)
	game.ui.heist_done(mine)
	if cut > 0:
		game.ui.toast("%s took %s between them" % [", ".join(crew_in), "$" + _fmt(cut)], "group", Color(0.12, 0.13, 0.16, 0.9), Color.WHITE, 3.0)
	_reset()
	game._save_now()

## It's over, without the money: you died, or got busted.
func fail(why: String) -> void:
	if state == IDLE:
		return
	if state >= CRACKED and not cur.is_empty():
		pass        # (the safe's been emptied all the same)
	game.ui.toast("Heist failed: " + why, "lock", Color("ff4f6b"), Color.WHITE, 2.8)
	_reset()

func _reset() -> void:
	state = IDLE
	carrying = ""
	game.police.pinned = false
	for n in [drill, duffle, zone_mi]:
		if n and is_instance_valid(n):
			(n as Node).queue_free()
	drill = null
	duffle = null
	zone_mi = null
	if _drill_snd and is_instance_valid(_drill_snd):
		_drill_snd.stop()
	cur = {}
	_show_safehouse(false)
	game.ui.heist_hud("", "", -1.0, false)
	_refresh_dots()

# ------------------------------------------------------------------ props

## A prop at game size (the drill with its bit on a pivot, so it can spin).
func _prop(k: String) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = load(PROP + k + ".res")
	mi.scale = Vector3.ONE * SCALE
	mi.set_surface_override_material(0, game.toon)
	root.add_child(mi)
	if k == "drill":
		var pv: Array = _meta("drill")["pivots"]["bitpivot"]
		var piv := Node3D.new()
		piv.position = Vector3(pv[0], pv[1], pv[2])
		mi.add_child(piv)
		var bit := MeshInstance3D.new()
		bit.mesh = load(PROP + "drill_bitpivot.res")
		bit.set_surface_override_material(0, game.toon)
		piv.add_child(bit)
		root.set_meta("bit", piv)
	return root

## What you're carrying, on your back while you're on foot.
func _carry_tick() -> void:
	var av: Node3D = game.foot.avatar if game.on_foot and game.foot else null
	var want := carrying if av != null else ""
	if _carry_on and is_instance_valid(_carry_on) and (_carry_on.get_meta("what", "") != want or av == null):
		_carry_on.queue_free()
		_carry_on = null
	if want == "" or (_carry_on and is_instance_valid(_carry_on)):
		return
	var sk: Skeleton3D = av.skel
	if sk == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = load(PROP + want + ".res")
	mi.set_surface_override_material(0, game.toon)
	# (slung across the back, long side across the shoulders: the tool bag, or the cash bag)
	mi.transform = Transform3D(Basis(Vector3.RIGHT, -0.3).scaled(Vector3.ONE * (1.15 if want == "tool_duffle" else 1.4)), Vector3.ZERO)
	var ba: BoneAttachment3D = av.carry_on_back(mi, 0.24, 0.0)
	if ba == null:
		return
	ba.set_meta("what", want)
	_carry_on = ba

# ------------------------------------------------------------------ cash

## Cash dropped where someone went down: a bundle that turns slowly, picked up walking or driving over it.
func drop_cash(p: Vector3, value: int) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _cash_mesh
	mi.scale = Vector3.ONE * SCALE * 1.5
	mi.set_surface_override_material(0, game.toon)
	add_child(mi)
	mi.global_position = Vector3(p.x, island.height_at(p.x, p.z) + 0.25, p.z)
	cash.append({"node": mi, "value": value, "t": 0.0, "y": mi.global_position.y})
	while cash.size() > 30:
		var old: Dictionary = cash.pop_front()
		(old["node"] as Node).queue_free()

func _cash_tick(dt: float, yp: Vector3) -> void:
	var r: float = 1.8 if game.on_foot else 3.6
	for c in cash.duplicate():
		var n: MeshInstance3D = c["node"]
		c["t"] = float(c["t"]) + dt
		n.rotation.y += dt * 1.6
		n.global_position.y = float(c["y"]) + 0.12 + sin(float(c["t"]) * 3.0) * 0.08
		if float(c["t"]) > 0.6 and n.global_position.distance_to(yp) < r:
			game.save.data["coins"] = int(game.save.data["coins"]) + int(c["value"])
			game.sfx("cash", -4.0, randf_range(0.95, 1.1))
			game.ui.popup_text("+$%d" % int(c["value"]), Color("7be36b"))
			n.queue_free()
			cash.erase(c)
		elif float(c["t"]) > 90.0:
			n.queue_free()
			cash.erase(c)
