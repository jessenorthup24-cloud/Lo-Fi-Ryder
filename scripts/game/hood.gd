extends RefCounted
## North of downtown, off Castle Road: two rough neighbourhoods and the old cemetery, and a new suburb east
## of downtown. (Their own random seed, so the rest of the island comes out as it always has.)
##
## - Palmer Street: a cul-de-sac of little stucco duplexes and bungalows in faded pastels, fenced front yards,
##   palms, cars parked up on the kerb, people hanging out on the corner, a corner store, wires over the street.
## - The Courts (Court Street): brick and stucco walk-ups with balconies and fire escapes, a parking court,
##   rows of garages, dumpsters, a building under scaffolding, broken walls, barriers.
## - Low Street joins the two.
## - Old Hill Cemetery, at the end of Court Street: iron railings, a gravel drive through rows of headstones,
##   crypts, lamps, crooked pines, the groundskeeper, and (after dark) a ghost.
## - Sycamore Heights: a loop of houses off Bay Avenue and Main Street.
## The buildings are the Retro Urban Kit's wall blocks put together by tools/kenney/bake_hood.gd.

const PALMER_Z := -100.0
const COURT_Z := -175.0
const SAC := Vector2(22, -100)            # the turning circle at the end of Palmer Street
const SAC_HS := 14.0
const PARK_C := Vector2(2, -155)          # the Courts' parking court, in off Low Street
const PARK_HS := Vector2(18, 9)
const VACANT := Vector2(30, -128)         # a vacant lot
const CEM := Vector2(80, -175)            # the cemetery: its middle and half size
const CEM_HS := Vector2(38, 32)
const SYC := Vector2(142, -10)            # Sycamore Heights
const HOOD_RECT := Rect2(-78, -215, 126, 132)   # (the hoods: no meadow trees in here)
const SYC_RECT := Rect2(104, -58, 72, 92)

const DUPLEX := ["k_hood_duplex-a", "k_hood_duplex-a2", "k_hood_duplex-c", "k_hood_duplex-c2", "k_hood_bungalow-a",
	"k_hood_bungalow-a2", "k_hood_bungalow-b", "k_hood_duplex-b"]
const WALKUP := ["k_hood_walkup-a", "k_hood_walkup-b", "k_hood_walkup-c", "k_hood_walkup-d"]
const LOWRIDERS := ["sedan", "sedan-sports", "hatchback-sports", "suv", "van", "taxi"]
const PALMS := ["k_pirate_palm-straight", "k_pirate_palm-bend", "k_pirate_palm-detailed-straight", "k_pirate_palm-detailed-bend"]
const STONES := ["k_grave_gravestone-round", "k_grave_gravestone-bevel", "k_grave_gravestone-cross", "k_grave_gravestone-roof",
	"k_grave_gravestone-decorative", "k_grave_gravestone-wide", "k_grave_cross", "k_grave_gravestone-cross-large",
	"k_grave_gravestone-broken", "k_grave_cross-wood"]

static func plan(I) -> void:
	I.flats.append([Vector2(-15, -148), Vector2(66, 64), 30.0])        # the hoods
	I.flats.append([CEM, CEM_HS + Vector2(4, 4), 24.0])                 # the cemetery
	I.flats.append([SYC, Vector2(36, 46), 28.0])                         # Sycamore Heights
	I.add_road("Palmer Street", [Vector2(-80, PALMER_Z), Vector2(-50, PALMER_Z), Vector2(-20, PALMER_Z), Vector2(SAC.x - SAC_HS + 2.0, PALMER_Z)], "street")
	I.add_road("Court Street", [Vector2(-80, COURT_Z), Vector2(-50, COURT_Z), Vector2(-20, COURT_Z), Vector2(10, COURT_Z), Vector2(CEM.x - CEM_HS.x - 8.0, COURT_Z)], "street")
	I.add_road("Low Street", [Vector2(-20, PALMER_Z), Vector2(-20, -125), Vector2(-20, -150), Vector2(-20, COURT_Z)], "lane")
	I.add_lot(SAC, Vector2(SAC_HS, SAC_HS), I.S_ASPHALT)                     # the turning circle
	I.add_lot(PARK_C, PARK_HS, I.S_ASPHALT)                                   # the Courts' parking court (in off Low Street)
	# the cemetery's drive: from the end of Court Street in through the gate to the crypts
	I.add_lot(Vector2((CEM.x - CEM_HS.x - 6.0 + CEM.x + CEM_HS.x - 4.0) * 0.5, CEM.y), Vector2((CEM_HS.x * 2.0 + 2.0) * 0.5, 3.2), I.S_COBBLE)
	I.add_road("Sycamore Loop", [Vector2(118, -40), Vector2(146, -52), Vector2(168, -30), Vector2(170, 2), Vector2(158, 26),
		Vector2(128, 28), Vector2(114, 4)], "lane", true)
	I.add_road("Sycamore Way", [Vector2(100, -30), Vector2(108, -33), Vector2(117, -37)], "lane")
	I.add_road("Sycamore Lane", [Vector2(143, 27), Vector2(146, 42), Vector2(150, 58)], "lane")

static func places() -> Array:
	return [
		{"name": "Palmer Street", "pos": Vector3(-30, 0, PALMER_Z), "r": 55.0},
		{"name": "The Courts", "pos": Vector3(-35, 0, COURT_Z), "r": 50.0},
		{"name": "Old Hill Cemetery", "pos": Vector3(CEM.x, 0, CEM.y), "r": 45.0},
		{"name": "Sycamore Heights", "pos": Vector3(SYC.x, 0, SYC.y), "r": 50.0},
	]

static func in_hood(x: float, z: float) -> bool:
	return HOOD_RECT.has_point(Vector2(x, z)) or SYC_RECT.has_point(Vector2(x, z)) or \
		Rect2(CEM - CEM_HS, CEM_HS * 2.0).grow(4.0).has_point(Vector2(x, z))

static func populate(I, D) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 9137
	_palmer(I, D, rr)
	_courts(I, D, rr)
	_cemetery(I, D, rr)
	_sycamore(I, D, rr)

static func _yaw_to(dir: Vector2) -> float:
	return atan2(-dir.x, -dir.y)

static func _car(I, rr: RandomNumberGenerator, p: Vector2, yaw: float) -> void:
	if I.is_free(p, Vector2(1.2, 2.4), yaw):
		I.put("k_car_" + LOWRIDERS[rr.randi_range(0, LOWRIDERS.size() - 1)], p.x, p.y, yaw, 1.0, "box")
		I.block_rect(p, Vector2(1.2, 2.4), yaw, 0.4)

## A few people stood about together, chatting.
static func _crowd(I, D, rr: RandomNumberGenerator, c: Vector2, n: int) -> void:
	for k in n:
		var a := TAU * k / n + rr.randf_range(-0.3, 0.3)
		var p := c + Vector2(cos(a), sin(a)) * rr.randf_range(0.9, 1.4)
		if not I.is_blocked(p.x, p.y):
			D._person(I, p.x, p.y, "stand", _yaw_to(c - p))

## Each house along a street: a fenced front yard (low wall or railings, with a gap for the path), a palm or
## two, a car on the drive or at the kerb, maybe someone out front.
static func _yards(I, D, rr: RandomNumberGenerator, placed: Array) -> void:
	for h in placed:
		var c: Vector2 = h["c"]
		var nrm: Vector2 = h["n"]
		var sz: Vector3 = h["size"]
		var along := Vector2(-nrm.y, nrm.x)
		var front := c - nrm * (sz.z * 0.5)
		var edge := float(h.get("edge", 3.0))
		var fence_at := front - nrm * maxf(edge - 1.4, 1.5)
		var fname := "k_urb_wall-fence" if rr.randf() < 0.6 else "k_urb_wall-type-a"
		var seg := 4.6
		var nseg := int(floor(sz.x / seg))
		for k in nseg:
			var off := (float(k) - (nseg - 1) * 0.5) * seg
			if absf(off) < 1.0 and nseg % 2 == 1:
				continue         # (the gap for the path up to the door)
			var fp := fence_at + along * off
			if I.is_free(fp, Vector2(seg * 0.5, 0.3), _yaw_to(-nrm)):
				I.put(fname, fp.x, fp.y, _yaw_to(-nrm), 1.0, "box")
				I.block_rect(fp, Vector2(seg * 0.5, 0.3), _yaw_to(-nrm), 0.2)
		I.decal(front - nrm * (edge * 0.5 - 0.6), Vector2(0.9, edge * 0.5), _yaw_to(nrm), D.P.CONCRETE)
		if rr.randf() < 0.75:
			var pp := front - nrm * 1.8 + along * (sz.x * 0.5 - 1.2) * (1.0 if rr.randf() < 0.5 else -1.0)
			if not I.is_blocked(pp.x, pp.y):
				I.put(PALMS[rr.randi_range(0, PALMS.size() - 1)], pp.x, pp.y, rr.randf() * TAU, rr.randf_range(0.9, 1.2), "cyl")
		if rr.randf() < 0.55:
			var side := along * (sz.x * 0.5 + 2.4) * (1.0 if rr.randf() < 0.5 else -1.0)
			_car(I, rr, front + side + nrm * 1.0, _yaw_to(-nrm if rr.randf() < 0.5 else nrm))
		if rr.randf() < 0.35:
			var sp := front - nrm * 1.2
			D._person(I, sp.x, sp.y, "sit" if rr.randf() < 0.4 else "stand", _yaw_to(-nrm), 0.0)

## Street lamps down both sides of a road, and the odd car parked at the kerb.
static func _street_bits(I, D, rr: RandomNumberGenerator, road: String, parked: float) -> void:
	for side in [-1.0, 1.0]:
		for s in D._along(I, road, 7.2 * side, 26.0, 6.0 if side > 0 else 19.0):
			var p: Vector2 = s["p"]
			if not I.is_blocked(p.x, p.y) and not D._near_junction(I, p, 12.0):
				I.put_breakable("k_retro_detail-light-single", p.x, p.y, _yaw_to(-s["n"] * side), 1.0, 0.3)
		for s in D._along(I, road, 3.6 * side, 13.0, 4.0 if side > 0 else 10.0):
			if rr.randf() < parked and not D._near_junction(I, s["p"], 16.0):
				var t: Vector2 = s["t"]
				_car(I, rr, s["p"], _yaw_to(t * side))

static func _palmer(I, D, rr: RandomNumberGenerator) -> void:
	# the corner store on Castle Road, people out front
	var st := Vector2(-64, PALMER_Z - 14.5)
	if I.is_free(st, Vector2(7, 7), 0.0):
		I.put("k_hood_corner-store", st.x, st.y, _yaw_to(Vector2(0, 1)), 1.0, "box")
		I.block_rect(st, Vector2(6.4, 6.4), 0.0, 0.6)
		_crowd(I, D, rr, st + Vector2(-3, 9.5), 3)
		I.put_breakable("k_retro_detail-dumpster-closed", st.x + 8.5, st.y - 3.0, PI * 0.5, 1.0, 0.8)
		I.put_breakable("k_urb_detail-dumpster-open", st.x + 8.5, st.y + 0.6, PI * 0.5, 1.0, 0.8)
	var placed := []
	# round the turning circle first (three houses looking in), then down both sides of the street
	for dirn in [Vector2(1, 0), Vector2(0.55, -0.83), Vector2(0.55, 0.83)]:
		var nm0: String = DUPLEX[rr.randi_range(0, 4)]
		var sz0: Vector3 = D._size(nm0)
		var c0: Vector2 = SAC + dirn * (SAC_HS + 3.0 + sz0.z * 0.5)
		var yaw0 := _yaw_to(-dirn)
		if I.is_free(c0, Vector2(sz0.x * 0.5, sz0.z * 0.5), yaw0):
			I.put(nm0, c0.x, c0.y, yaw0, 1.0, "box")
			I.block_rect(c0, Vector2(sz0.x * 0.5, sz0.z * 0.5), yaw0, 1.0)
			placed.append({"name": nm0, "c": c0, "yaw": yaw0, "n": dirn, "size": sz0, "edge": 3.0})
	for side in [-1.0, 1.0]:
		placed.append_array(D._row(I, "Palmer Street", side, 0.08, 0.98, DUPLEX, 7.0, rr, Vector2(1.5, 3.0)))
	_yards(I, D, rr, placed)
	_street_bits(I, D, rr, "Palmer Street", 0.45)
	# the gang on the corner by the turning circle, a car with its doors open, a barbecue's worth of crates
	_crowd(I, D, rr, SAC + Vector2(-4, -10), 4)
	_car(I, rr, SAC + Vector2(4, 6), PI * 0.35)
	I.put_breakable("k_pirate_crate", SAC.x - 8, SAC.y + 10, 0.4, 1.0, 0.5)
	I.put_breakable("k_pirate_barrel", SAC.x - 9.5, SAC.y + 9, 0.0, 1.0, 0.5)
	D._pet(I, "dog", SAC.x - 2, SAC.y - 7)

static func _courts(I, D, rr: RandomNumberGenerator) -> void:
	# (the parking court and the vacant lot kept clear of the houses)
	I.block_rect(PARK_C, PARK_HS, 0.0, 0.5)
	I.block_rect(VACANT, Vector2(11, 11), 0.0, 0.5)
	var placed := []
	for side in [-1.0, 1.0]:
		placed.append_array(D._row(I, "Court Street", side, 0.06, 0.97, WALKUP, 7.5, rr, Vector2(3.0, 6.0)))
	for h in placed:
		var c: Vector2 = h["c"]
		var nrm: Vector2 = h["n"]
		var sz: Vector3 = h["size"]
		var along := Vector2(-nrm.y, nrm.x)
		var front := c - nrm * (sz.z * 0.5)
		# a dumpster by the side, rubbish, people on the steps
		var dp := front + along * (sz.x * 0.5 + 1.6) + nrm * 2.0
		if I.is_free(dp, Vector2(1.6, 1.2), _yaw_to(-nrm)):
			I.put_breakable(["k_retro_detail-dumpster-closed", "k_urb_detail-dumpster-open"][rr.randi_range(0, 1)], dp.x, dp.y, _yaw_to(-nrm), 1.0, 0.8)
		if rr.randf() < 0.5:
			var bp := front - nrm * 1.6 + along * rr.randf_range(-sz.x * 0.3, sz.x * 0.3)
			if not I.is_blocked(bp.x, bp.y):
				I.put(["k_urb_detail-bricks-type-a", "k_urb_detail-bricks-type-b", "k_urb_planks", "k_urb_pallet-small"][rr.randi_range(0, 3)],
					bp.x, bp.y, rr.randf() * TAU, 1.0, "")
		if rr.randf() < 0.45:
			_crowd(I, D, rr, front - nrm * 2.2 + along * 2.0, rr.randi_range(2, 3))
	# one of them is having work done: scaffolding up its front
	if not placed.is_empty():
		var h0: Dictionary = placed[rr.randi_range(0, placed.size() - 1)]
		var c0: Vector2 = h0["c"]
		var n0: Vector2 = h0["n"]
		var sz0: Vector3 = h0["size"]
		var al0 := Vector2(-n0.y, n0.x)
		for i in int(sz0.x / 4.6):
			for k in 2:
				var sp := c0 - n0 * (sz0.z * 0.5 + 2.3) + al0 * ((float(i) - (int(sz0.x / 4.6) - 1) * 0.5) * 4.6)
				I.put("k_urb_scaffolding-structure", sp.x, sp.y, _yaw_to(-n0), 1.0, "box" if k == 0 else "", I.height_at(sp.x, sp.y) + k * 4.6)
	# the parking court behind Castle Road: rows of garages, cars, a truck, a broken wall, the drift-worthy lot
	var pc := PARK_C
	for k in 2:
		var gp := pc + Vector2(-8.5 + k * 17.0, PARK_HS.y + 4.6)
		if I.is_free(gp, Vector2(8, 4), 0.0) or true:
			I.put("k_hood_garages", gp.x, gp.y, 0.0, 1.0, "box")     # (doors to the court)
			I.block_rect(gp, Vector2(8, 4), 0.0, 0.5)
	for k in 4:
		_car(I, rr, pc + Vector2(-11 + k * 6.5, 6.5), PI if k % 2 == 0 else 0.0)
	var tk := pc + Vector2(12, -2)
	if I.is_free(tk, Vector2(2, 4), 0.0):
		I.put(["k_urb_truck-green-cargo", "k_urb_truck-grey-cargo"][rr.randi_range(0, 1)], tk.x, tk.y, 0.2, 1.0, "box")
		I.block_rect(tk, Vector2(2, 4), 0.2, 0.4)
	for k in 3:
		var wp := pc + Vector2(-PARK_HS.x - 1.0, -6.0 + k * 4.6)
		if I.is_free(wp, Vector2(0.4, 2.3), PI * 0.5):
			I.put(["k_urb_wall-broken-type-a", "k_urb_wall-broken-type-b", "k_urb_wall-type-b"][k], wp.x, wp.y, PI * 0.5, 1.0, "box")
			I.block_rect(wp, Vector2(0.4, 2.3), PI * 0.5, 0.2)
	for k in 3:
		I.put_breakable(["k_retro_detail-barrier-strong-type-a", "k_urb_detail-barrier-strong-damaged", "k_urb_detail-barrier-strong-type-b"][k],
			pc.x + 6.0 + k * 2.4, pc.y - PARK_HS.y + 1.0, 0.0, 1.0, 0.8)
	_crowd(I, D, rr, pc + Vector2(4, 0), 3)
	_street_bits(I, D, rr, "Court Street", 0.5)
	# Low Street: little houses down the east side (the court's on the west)
	var low: Array = D._row(I, "Low Street", -1.0, 0.18, 0.86, ["k_hood_bungalow-a", "k_hood_bungalow-a2", "k_hood_bungalow-b", "k_hood_duplex-c2"], 6.5, rr, Vector2(2.0, 3.0))
	low.append_array(D._row(I, "Low Street", 1.0, 0.18, 0.86, ["k_hood_bungalow-b", "k_hood_duplex-a2"], 6.5, rr, Vector2(2.0, 3.0)))
	_yards(I, D, rr, low)
	_street_bits(I, D, rr, "Low Street", 0.3)
	# a vacant lot between the streets: broken walls round it, pallets, a burning barrel and people round it
	var vl := VACANT
	if true:
		I.decal(vl, Vector2(11, 11), 0.0, D.P.ASPHALT_DK)
		for k in 4:
			var wp2 := vl + Vector2(-9.2 + k * 4.6, -11.5)
			I.put(["k_urb_wall-broken-type-a", "k_urb_wall-type-a", "k_urb_wall-broken-type-b", "k_urb_wall-steps-type-a"][k], wp2.x, wp2.y, 0.0, 1.0, "box")
		var fb := vl + Vector2(1, 1)
		I.put("k_grave_fire-basket", fb.x, fb.y, 0.0, 1.6, "")
		var fire: Dictionary = I.add_anim("flame", Vector3(fb.x, I.height_at(fb.x, fb.y) + 0.5, fb.y), 0.0, 1.4)
		if not fire.is_empty():
			fire["kind"] = "flame"
		_crowd(I, D, rr, fb, 4)
		I.put("k_urb_pallet-small", vl.x - 6, vl.y + 5, 0.4, 1.0, "")
		I.put("k_urb_planks", vl.x + 6, vl.y - 4, 1.2, 1.0, "")
		I.put_breakable("k_pirate_barrel", vl.x + 7, vl.y + 6, 0.0, 1.0, 0.5)
		_car(I, rr, vl + Vector2(-6, -4), 0.7)
		I.block_rect(vl, Vector2(11, 11), 0.0, 0.0)

static func _cemetery(I, D, rr: RandomNumberGenerator) -> void:
	var lo := CEM - CEM_HS
	var hi := CEM + CEM_HS
	var seg := 2.2           # (the railing's panel, at the kit's scale)
	var gate_hw := 5.0       # the gateway on the west side, where Court Street comes in
	# iron railings all the way round, a gateway with stone pillars
	for side in 4:
		var a: Vector2
		var b: Vector2
		match side:
			0: a = Vector2(lo.x, lo.y); b = Vector2(hi.x, lo.y)
			1: a = Vector2(hi.x, lo.y); b = Vector2(hi.x, hi.y)
			2: a = Vector2(hi.x, hi.y); b = Vector2(lo.x, hi.y)
			_: a = Vector2(lo.x, hi.y); b = Vector2(lo.x, lo.y)
		var dirn := (b - a).normalized()
		var n := int((b - a).length() / seg)
		for k in n:
			var p := a + dirn * (seg * (k + 0.5))
			if side == 3 and absf(p.y - CEM.y) < gate_hw:
				continue
			var nm := "k_grave_iron-fence-border-column" if k % 5 == 0 else ("k_grave_iron-fence-damaged" if rr.randf() < 0.08 else "k_grave_iron-fence-border")
			I.put(nm, p.x, p.y, _yaw_to(Vector2(-dirn.y, dirn.x)), 1.0, "box")
	for sgn in [-1.0, 1.0]:
		var gp := Vector2(lo.x, CEM.y + sgn * (gate_hw + 0.4))
		I.put("k_grave_pillar-square", gp.x, gp.y, 0.0, 1.4, "box")
		I.put_breakable("k_grave_lantern-candle", gp.x, gp.y, 0.0, 1.0, 0.3, I.height_at(gp.x, gp.y) + 1.15 * 2.2 * 1.4)
	I.block_rect(CEM, CEM_HS, 0.0, 0.0)
	# rows of graves either side of the drive
	for row_side in [-1.0, 1.0]:
		var z: float = CEM.y + float(row_side) * 7.5
		while absf(z - CEM.y) < CEM_HS.y - 3.0:
			var x := lo.x + 6.0
			while x < hi.x - 14.0:
				if rr.randf() < 0.85:
					var sp := Vector2(x + rr.randf_range(-0.3, 0.3), z)
					var face: float = 0.0 if float(row_side) > 0.0 else PI          # (headstones face the drive)
					I.put(STONES[rr.randi_range(0, STONES.size() - 1)], sp.x, sp.y, face + rr.randf_range(-0.12, 0.12), 1.0, "box")
					var mound: Vector2 = sp + Vector2(0, -float(row_side) * 1.9)
					I.put("k_grave_grave-border" if rr.randf() < 0.4 else "k_grave_grave", mound.x, mound.y, face, 1.0, "")
					if I.season == 2 and rr.randf() < 0.12:
						I.put_breakable(["k_grave_pumpkin-carved", "k_grave_pumpkin-tall-carved"][rr.randi_range(0, 1)], sp.x + 0.8, mound.y, rr.randf() * TAU, 1.0, 0.3)
					elif rr.randf() < 0.08:
						I.put_breakable("k_grave_candle-multiple", sp.x + 0.7, mound.y, 0.0, 1.0, 0.2)
				x += 3.4
			z += float(row_side) * 5.2
	# the crypts at the far end, the groundskeeper's spot, obelisks
	for k in 2:
		var cp := Vector2(hi.x - 8.0, CEM.y + (k * 2 - 1) * 15.0)
		var yaw := PI * 0.5      # (doors to the drive's end)
		I.put("k_grave_crypt-large", cp.x, cp.y, yaw, 1.0, "box")
		var cy: float = I.height_at(cp.x, cp.y)
		I.put("k_grave_crypt-large-roof", cp.x, cp.y, yaw, 1.0, "", cy + 1.0 * 2.6)
	var sc := Vector2(hi.x - 7.0, CEM.y)
	I.put("k_grave_crypt-small", sc.x, sc.y, PI * 0.5, 1.0, "box")
	I.put("k_grave_crypt-small-roof", sc.x, sc.y, PI * 0.5, 1.0, "", I.height_at(sc.x, sc.y) + 1.0 * 2.6)
	for p in [Vector2(lo.x + 20, CEM.y - 4.6), Vector2(lo.x + 40, CEM.y + 4.6), Vector2(hi.x - 20, CEM.y - 4.6)]:
		I.put("k_grave_pillar-obelisk", p.x, p.y, 0.0, 1.0, "box")
	for k in 5:
		var lp := Vector2(lo.x + 8.0 + k * 14.0, CEM.y + (4.2 if k % 2 == 0 else -4.2))
		I.put_breakable("k_grave_lightpost-single", lp.x, lp.y, 0.0 if k % 2 == 0 else PI, 1.0, 0.3)
	var kp := Vector2(lo.x + 12.0, CEM.y - 5.5)
	I.put("k_grave_character-keeper", kp.x, kp.y, PI * 0.5, 1.0, "")
	I.put("k_grave_shovel-dirt", kp.x + 1.6, kp.y - 1.0, 0.3, 1.0, "")
	I.put("k_grave_bench", lo.x + 30.0, hi.y - 3.0, PI, 1.0, "box")
	# crooked pines round the edge
	for k in 14:
		var t := float(k) / 14.0
		var e := rr.randi_range(0, 3)
		var p2: Vector2
		match e:
			0: p2 = Vector2(lerpf(lo.x + 3, hi.x - 3, t), lo.y + 3.0)
			1: p2 = Vector2(lerpf(lo.x + 3, hi.x - 3, t), hi.y - 3.0)
			2: p2 = Vector2(hi.x - 3.0, lerpf(lo.y + 3, hi.y - 3, t))
			_: p2 = Vector2(lo.x + 3.0, lerpf(lo.y + 3, CEM.y - gate_hw - 3, t))
		I.put(["k_grave_pine-crooked", "k_grave_pine", "k_grave_pine-fall-crooked"][rr.randi_range(0, 2)], p2.x, p2.y, rr.randf() * TAU,
			rr.randf_range(0.85, 1.15), "cyl")
	# and something drifting about between the crypts after dark
	I.ghost = I.add_anim("k_grave_character-ghost", Vector3(hi.x - 18.0, I.height_at(hi.x - 18.0, CEM.y + 6.0) + 1.1, CEM.y + 6.0), -PI * 0.5, 1.0)
	if not I.ghost.is_empty():
		I.ghost["kind"] = "bob"

static func _sycamore(I, D, rr: RandomNumberGenerator) -> void:
	var houses := []
	for s in D.HOUSES:
		houses.append("k_sub_building-type-" + s)
	var placed := []
	placed.append_array(D._row(I, "Sycamore Loop", 1.0, 0.0, 1.0, houses, 8.5, rr, Vector2(5.0, 9.0)))
	placed.append_array(D._row(I, "Sycamore Loop", -1.0, 0.05, 0.95, houses, 8.5, rr, Vector2(6.0, 10.0)))
	for h in placed:
		var c: Vector2 = h["c"]
		var nrm: Vector2 = h["n"]
		var sz: Vector3 = h["size"]
		var along := Vector2(-nrm.y, nrm.x)
		var front := c - nrm * (sz.z * 0.5)
		var edge := float(h.get("edge", 3.0))
		var side := along * (sz.x * 0.5 + 2.2)
		I.decal(front + side - nrm * (edge * 0.5 - 1.6), Vector2(1.6, edge * 0.5 + 1.6), _yaw_to(nrm), D.P.CONCRETE)
		if rr.randf() < 0.6:
			var dc := front + side + nrm * 2.6
			var dy := _yaw_to(-nrm if rr.randf() < 0.5 else nrm)
			if I.is_free(dc, Vector2(1.2, 2.4), dy):
				I.put("k_car_" + D.PARKED[rr.randi_range(0, 5)], dc.x, dc.y, dy, 1.0, "box")
		var mb := front - nrm * (edge - 0.8) - along * (sz.x * 0.25)
		I.put_breakable("mailbox", mb.x, mb.y, _yaw_to(-nrm), 2.2, 0.35)
		var back := c + nrm * (sz.z * 0.5 + 6.0)
		var fen: String = ["k_sub_fence-3x3", "k_sub2_fence-2x3", "k_sub2_fence-3x2"][rr.randi_range(0, 2)]
		var fs: Vector3 = D._size(fen)
		if I.is_free(back, Vector2(fs.x * 0.5 + 0.2, fs.z * 0.5 + 0.2), _yaw_to(nrm)):
			I.put(fen, back.x, back.y, _yaw_to(-nrm), 1.0, "box")
			I.block_rect(back, Vector2(fs.x * 0.5 + 0.2, fs.z * 0.5 + 0.2), _yaw_to(nrm), 0.5)
		var pp := front - nrm * (edge * 0.5) + along * (sz.x * 0.15)
		if not I.is_blocked(pp.x, pp.y):
			I.put("k_sub2_path-stones-messy", pp.x, pp.y, _yaw_to(-nrm), 1.0, "")
		var tp := front - nrm * (edge * 0.5) - along * (sz.x * 0.5 + 1.2)
		if not I.is_blocked(tp.x, tp.y):
			I.put("k_sub_tree-large" if rr.randf() < 0.6 else "k_sub_tree-small", tp.x, tp.y, rr.randf() * TAU, rr.randf_range(0.85, 1.1), "cyl")
		if rr.randf() < 0.3:
			D._pet(I, ["dog", "cat", "bunny"][rr.randi_range(0, 2)], front.x + side.x - nrm.x * 1.2, front.y + side.y - nrm.y * 1.2)
		if rr.randf() < 0.3:
			D._person(I, mb.x + along.x * 1.5, mb.y + along.y * 1.5)
		if I.season == 2 and rr.randf() < 0.3:
			I.put_breakable("k_grave_pumpkin-carved", mb.x - along.x * 1.4, mb.y - along.y * 1.4, _yaw_to(-nrm), 1.0, 0.3)
	# a little green in the middle of the loop
	for k in 8:
		var a := TAU * k / 8.0
		var p := SYC + Vector2(cos(a), sin(a)) * rr.randf_range(6.0, 16.0)
		if not I.is_blocked(p.x, p.y):
			I.put("k_sub_tree-large" if k % 2 == 0 else "k_castle_tree-large", p.x, p.y, rr.randf() * TAU, rr.randf_range(0.8, 1.05), "cyl")
	I.put_breakable("k_holi_bench", SYC.x + 4, SYC.y, PI * 0.5, 1.0, 0.8)
	D._person(I, SYC.x + 4, SYC.y, "sit", -PI * 0.5, 0.5)

## The ghost: only out after dark (called every frame by the island with how dark it is).
static func ghost_tick(I, night: float) -> void:
	var g: Dictionary = I.ghost
	if g.is_empty():
		return
	var on := night > 0.5
	if on != bool(g.get("on", true)):
		g["on"] = on
		var pool = I.pools[g["pool"]]
		if not on:
			pool.put(g["slot"], Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(g["pos"]) - Vector3(0, 50, 0)))
	if not on:
		g["kind"] = ""
	else:
		g["kind"] = "bob"
