extends Node3D
## The drivers: named street drivers out on the island in cars like yours, driving fast and loose but
## well. They take the corners flat out (drifting a lot of them, depending on who it is), weave past the
## traffic, and now and then a patrol car sees one go by at twice the limit and goes after them (they run
## for it: they lose them or get busted).
##
## Drive up close to one and you swap numbers. Then open the phone and call them: they come and find you
## and drive with you, up to three at once. Your crew keep up with you (with a squirt of nitrous when
## they've fallen behind), sit off your rear quarters, drift when you drift (tandem) and park up round you
## when you stop. Call them again to send them on their way.
##
## Driver cars are real cars, the same physics as yours (like the police and the racers).

const Car := preload("res://scripts/game/drift_car.gd")
const CARS := preload("res://scripts/game/cars.gd")
const M := preload("res://scripts/core/models.gd")
const K := preload("res://scripts/ui/kit.gd")

const LAYER := 32
const CREW_MAX := 3
const MAX_CARS := 6          # drivers out at once, your crew included
const ROAM_N := 4            # roaming about (when you've no crew)
const MEET_R := 26.0         # this close for a moment and you swap numbers
const MEET_T := 1.0
## Who's out there. style: drift (drifts most corners), grip (fast and tidy), wild (fast, takes chances).
const ROSTER := [
	{"name": "Kai", "car": "hotrod", "style": "drift", "line": "Say less. On my way!"},
	{"name": "Nova", "car": "racer", "style": "grip", "line": "Pulling up on you now"},
	{"name": "Rico", "car": "bus", "style": "wild", "line": "Ha! Try and keep up"},
	{"name": "Yuki", "car": "roadster", "style": "drift", "line": "Tandem? Let's go!"},
	{"name": "Zane", "car": "monster", "style": "wild", "line": "I'm coming in hot"},
	{"name": "Lola", "car": "taxi", "style": "drift", "line": "Ooh, a cruise. Coming!"},
	{"name": "Dex", "car": "dump", "style": "grip", "line": "Be there in a sec"},
	{"name": "Mara", "car": "tractor", "style": "drift", "line": "Wait for me!"},
	{"name": "Taz", "car": "firetruck", "style": "wild", "line": "Yeah yeah, coming"},
	{"name": "Ivy", "car": "mail", "style": "grip", "line": "Omw. Don't crash"},
	{"name": "Bo", "car": "wagon", "style": "drift", "line": "Sliding over now"},
	{"name": "Sasha", "car": "icecream", "style": "wild", "line": "Hold up, I'm close"},
]
## By style: chance to drift a corner, top speed (m/s), cornering (m/s² sideways), how close it passes.
const STYLE := {
	"drift": {"drift": 0.75, "vmax": 36.0, "lat": 9.0, "pass": 2.4},
	"grip": {"drift": 0.12, "vmax": 41.0, "lat": 10.0, "pass": 2.6},
	"wild": {"drift": 0.45, "vmax": 43.0, "lat": 10.4, "pass": 2.1},
}
## Where your crew sit behind you: [metres back, metres to the side].
const SLOTS := [[8.5, -2.4], [8.5, 2.4], [16.0, 0.0]]

var game: Node
var island: Node
var traffic: Node
var drivers: Array = []      # {car, who, mode (roam, crew, flee, busted), ...}
var held := false
var _spawn_cd := 1.5
var _scan := 0.0
var _n := 0
var _blip_mat: StandardMaterial3D
var _crew_mat: StandardMaterial3D
var _away: Array = []        # your crew, while a challenge is on (they're back after)
var _calls: Array = []       # [who, t]: calls ringing out
var trail := PackedVector3Array()   # where you've driven (a point every couple of metres): your crew follow it
const TRAIL_STEP := 2.5
const TRAIL_MAX := 140
var stats := {"spawned": 0, "drifts": 0, "tandem": 0, "crew_t": 0.0, "near_t": 0.0, "chases": 0, "busted": 0, "lost": 0, "respawns": 0, "rights": 0}

func setup(g: Node, isl: Node, tr: Node) -> void:
	game = g
	island = isl
	traffic = tr
	_blip_mat = _map_mat(Color("ffb347"))
	_crew_mat = _map_mat(Color("54e08a"))
	game.car.collision_mask = game.car.collision_mask | LAYER
	if not game.save.data.has("contacts"):
		game.save.data["contacts"] = ["Kai", "Yuki"]

func _map_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return m

# ------------------------------------------------------------------ for the phone

## Everyone in your phone: [{who, name, car, style, state ("crew", "near", "away", "cops", "calling"), dist}]
func contacts() -> Array:
	var out := []
	var cp: Vector3 = game.car.global_position
	for nm in game.save.data.get("contacts", []):
		var who := _who(String(nm))
		if who < 0:
			continue
		var r: Dictionary = ROSTER[who]
		var e := {"who": who, "name": r["name"], "car": CARS.by_id(r["car"])["name"], "style": r["style"], "state": "away", "dist": -1.0}
		var d := _driver_of(who)
		if not d.is_empty():
			e["dist"] = (d["car"] as Node3D).global_position.distance_to(cp)
			e["state"] = "crew" if d["mode"] == "crew" else ("cops" if d["chased"] else ("busted" if d["mode"] == "busted" else "near"))
		for cl in _calls:
			if int(cl[0]) == who:
				e["state"] = "calling"
		out.append(e)
	return out

func crew_count() -> int:
	var n := 0
	for d in drivers:
		if d["mode"] == "crew":
			n += 1
	for cl in _calls:
		n += 1
	return n

## Ring them. They pick up after a moment (game.ui.phone_said gets what they say).
func call_driver(who: int) -> void:
	if crew_count() >= CREW_MAX or game.challenge_on():
		return
	for cl in _calls:
		if int(cl[0]) == who:
			return
	_calls.append([who, randf_range(1.2, 2.0)])
	game.sfx("phone_ring" if game.sound._stream("phone_ring") else "checkpoint", -8.0, 1.4)

## Tell one of your crew they can go.
func dismiss(who: int) -> void:
	var d := _driver_of(who)
	if d.is_empty() or d["mode"] != "crew":
		return
	_roam(d)
	(d["tag"] as Label3D).modulate = Color(1, 1, 1, 0.95)
	game.ui.toast("%s: Later! Hit me up anytime" % String(ROSTER[who]["name"]), "phone", K.PAPER, K.INK, 2.2)

func _answer(who: int) -> void:
	var r: Dictionary = ROSTER[who]
	if game.challenge_on():
		return
	var d := _driver_of(who)
	if not d.is_empty() and d["chased"]:
		game.ui.toast("%s: Can't now, the cops are on me!" % String(r["name"]), "phone", Color("ff5c7a"), Color.WHITE, 2.6)
		return
	if not d.is_empty() and d["mode"] == "busted":
		game.ui.toast("%s: Just got busted... next time" % String(r["name"]), "phone", K.PAPER, K.INK, 2.6)
		return
	if d.is_empty():
		_make_room()
		d = _spawn(who, true)
		if d.is_empty():
			game.ui.toast("%s didn't pick up" % String(r["name"]), "phone", K.PAPER, K.INK, 2.0)
			return
	_join_crew(d)
	game.ui.toast("%s: %s" % [String(r["name"]), String(r["line"])], "phone", Color("54e08a"), K.INK, 2.6)

func _join_crew(d: Dictionary) -> void:
	d["mode"] = "crew"
	d["path"] = PackedVector3Array()
	d["replan"] = 0.0
	var used := []
	for o in drivers:
		if o != d and o["mode"] == "crew":
			used.append(int(o["slot"]))
	for s in SLOTS.size():
		if not s in used:
			d["slot"] = s
			break
	(d["tag"] as Label3D).modulate = Color("8ff0b0")
	(d["blip"] as MeshInstance3D).material_override = _crew_mat

## A roaming driver gives up their place, so someone you've called can come.
func _make_room() -> void:
	if drivers.size() < MAX_CARS:
		return
	var cp: Vector3 = game.car.global_position
	var far := {}
	var fd := -1.0
	for d in drivers:
		if d["mode"] == "crew":
			continue
		var dd := (d["car"] as Node3D).global_position.distance_to(cp)
		if dd > fd:
			fd = dd
			far = d
	if not far.is_empty():
		_free(far)

# ------------------------------------------------------------------ every frame

func tick(dt: float) -> void:
	if held:
		return
	var cp: Vector3 = game.car.global_position
	# a challenge or a race: the streets are closed. Your crew wait it out and come back after
	if game.challenge_on():
		if not drivers.is_empty():
			for d in drivers.duplicate():
				if d["mode"] == "crew":
					_away.append(int(d["who"]))
				_free(d)
		_calls.clear()
		return
	if not _away.is_empty():
		for who in _away:
			var d := _spawn(int(who), true)
			if not d.is_empty():
				_join_crew(d)
		_away.clear()
	# your line: where you've been, for your crew to follow round the corners the way you went
	var tp := Vector3(cp.x, 0, cp.z)
	if trail.is_empty() or trail[trail.size() - 1].distance_to(tp) > 30.0:
		trail = PackedVector3Array([tp])
	elif trail[trail.size() - 1].distance_to(tp) >= TRAIL_STEP:
		trail.append(tp)
		if trail.size() > TRAIL_MAX:
			trail = trail.slice(trail.size() - TRAIL_MAX)
	for cl in _calls.duplicate():
		cl[1] = float(cl[1]) - dt
		if float(cl[1]) <= 0.0:
			_calls.erase(cl)
			_answer(int(cl[0]))
	# keep a few about (out of sight, round you)
	_spawn_cd -= dt
	var roam := 0
	var crew := 0
	for d in drivers:
		if d["mode"] == "crew":
			crew += 1
		else:
			roam += 1
	if _spawn_cd <= 0.0 and roam < maxi(1, ROAM_N - crew) and drivers.size() < MAX_CARS and game.state == game.DRIVE:
		_spawn_cd = 2.5
		var pick := _pick_stranger()
		if pick >= 0:
			_spawn(pick, false)
	# (the traffic doesn't put a new car down on top of any of these)
	var av := []
	for d in drivers:
		if is_instance_valid(d["car"]):
			av.append((d["car"] as Node3D).global_position)
	for u in game.police.units:
		if is_instance_valid(u["car"]):
			av.append((u["car"] as Node3D).global_position)
	traffic.avoid = av
	_scan -= dt
	var scan := _scan <= 0.0
	if scan:
		_scan = 0.5
	for d in drivers.duplicate():
		if not is_instance_valid(d["car"]):
			drivers.erase(d)
			continue
		_drive(d, dt)
		_upkeep(d, dt, cp, scan)
	if game.args.has("crewlog") and int(game.time * 0.5) != int((game.time - dt) * 0.5):
		var line := "CREW t=%.1f you=%.0fkmh drift=%.2f %s" % [game.time, absf(game.car.speed) * 3.6, game.car.drift, str(stats)]
		for d in drivers:
			var c: Car = d["car"]
			line += " | %s %s/%s d=%.0f v=%.0f slip=%.0f%s" % [String(ROSTER[int(d["who"])]["name"]), String(d["mode"]), String(d["ds"]),
				c.global_position.distance_to(cp), c.linear_velocity.length() * 3.6, rad_to_deg(c.slip), " COPS" if d["chased"] else ""]
			if game.args.has("crewdebug"):
				var gl: Vector3 = d["goal"]
				line += " pos=(%.0f,%.0f) spd=%.1f thr=%.1f br=%.1f hb=%.1f st=%.2f path=%d pi=%d goal_d=%.0f rev=%.1f stk=%.1f av=%.2f" % [c.global_position.x, c.global_position.z,
					c.speed, c.throttle, c.brake, c.handbrake, c.steer_in, (d["path"] as PackedVector3Array).size(), int(d["pi"]),
					Vector2(gl.x, gl.z).distance_to(Vector2(c.global_position.x, c.global_position.z)), float(d["rev"]), float(d["stuck"]), c.angular_velocity.y]
		print(line)

func _upkeep(d: Dictionary, dt: float, cp: Vector3, scan: bool) -> void:
	var c: Car = d["car"]
	var p := c.global_position
	var dist := p.distance_to(cp)
	var cam: Camera3D = game.cam
	var in_view := cam.is_position_in_frustum(p) and dist < 220.0
	if d["mode"] == "crew":
		stats["crew_t"] += dt
		if dist < 35.0:
			stats["near_t"] += dt
	# the minimap dot and the name over the car
	(d["blip"] as Node3D).global_position = Vector3(p.x, 300.7, p.z)
	var tag: Label3D = d["tag"]
	tag.visible = dist < 75.0 and dist > 4.0
	# the engine note
	var eng: AudioStreamPlayer3D = d["eng"]
	if eng.stream:
		eng.pitch_scale = clampf((0.72 + c.rpm * 0.75) * float(d["pitch"]), 0.4, 2.2)
		eng.volume_db = lerpf(-14.0, -6.0, c.throttle)
	# swapping numbers: drive up beside one for a moment
	if d["mode"] != "crew" and dist < MEET_R and game.state == game.DRIVE:
		d["meet"] = float(d["meet"]) + dt
		var nm := String(ROSTER[int(d["who"])]["name"])
		var book: Array = game.save.data["contacts"]
		if float(d["meet"]) > MEET_T and not nm in book:
			book.append(nm)
			game.ui.toast("Swapped numbers with %s: call them from the phone" % nm, "phone", Color("8ff0b0"), K.INK, 2.8)
			game.sfx("coin", -8.0, 1.3)
	# a patrol car sees one fly past
	if scan and not d["chased"] and d["mode"] != "busted":
		d["cool"] = float(d["cool"]) - 0.5
		if float(d["cool"]) <= 0.0 and c.linear_velocity.length() * 3.6 > 82.0:
			_patrol_check(d)
	# gone: well away from you and out of sight (your crew get put back behind you instead)
	d["life"] = float(d["life"]) + dt
	if d["mode"] == "crew":
		d["far_t"] = float(d.get("far_t", 0.0)) + dt if (dist > 170.0 and not in_view) else 0.0
		if float(d["far_t"]) > 3.0 or (dist > 300.0 and not in_view):
			d["far_t"] = 0.0
			if game.args.has("crashlog"):
				print("BRINGBACK %s t=%.1f dist=%.0f you=%.0fkmh" % [String(ROSTER[int(d["who"])]["name"]), game.time, dist, game.car.linear_velocity.length() * 3.6])
			_bring_back(d)
	elif d["mode"] == "busted":
		if float(d["life"]) - float(d["bust_at"]) > 8.0 and not in_view:
			_free(d)
	elif dist > 430.0 and not in_view:
		_free(d)

## Someone not out already (and not someone you'd rather keep as crew).
func _pick_stranger() -> int:
	var free := []
	for i in ROSTER.size():
		if _driver_of(i).is_empty() and not i in _away:
			var busy := false
			for cl in _calls:
				if int(cl[0]) == i:
					busy = true
			if not busy:
				free.append(i)
	if free.is_empty():
		return -1
	return free[randi() % free.size()]

# ------------------------------------------------------------------ cars

func _spawn(who: int, called: bool) -> Dictionary:
	var spot := _spot(called)
	if spot.is_empty():
		return {}
	var r: Dictionary = ROSTER[who]
	var def := CARS.by_id(r["car"])
	var c: Car = Car.new()
	_n += 1
	c.name = "Driver_%d" % _n
	c.set_meta("driver", true)
	c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	game.add_child(c)
	var paints: int = M.paints(def).size()
	c.setup(def, game.toon, island, (who * 7 + 3) % maxi(paints, 1))
	# well sorted cars: tuned up, as a regular's would be
	c.tune(def, {"engine": 3, "turbo": 3, "tyres": 3, "steering": 4})
	c.assist = 1.0
	c.collision_layer = LAYER
	c.collision_mask = 1 | 2 | 4 | 16 | LAYER
	var xf: Transform3D = spot["xf"]
	c.place(xf)
	c.linear_velocity = -xf.basis.z * (14.0 if not called else 10.0)
	c.reset_physics_interpolation()
	c.rammed.connect(func(b, v, j, at): traffic.knock(b, v, j, at))
	# a dot on the minimap
	var blip := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 4.2
	cyl.bottom_radius = 4.2
	cyl.height = 0.2
	cyl.radial_segments = 12
	blip.mesh = cyl
	blip.material_override = _blip_mat
	blip.layers = island.MAP_LAYER
	blip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blip.top_level = true
	blip.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	c.add_child(blip)
	# their name, over the car
	var tag := Label3D.new()
	tag.text = String(r["name"])
	tag.font = K.font(700)
	tag.font_size = 54
	tag.outline_size = 14
	tag.outline_modulate = K.INK
	tag.modulate = Color(1, 1, 1, 0.95)
	tag.pixel_size = 0.01
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.fixed_size = false
	tag.position = Vector3(0, float(c.info["top"]) + 0.85, 0)
	tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.add_child(tag)
	# an engine you hear go by
	var eng := AudioStreamPlayer3D.new()
	var fam := String(def.get("engine", "small"))
	var snd: Node = game.sound
	if snd.has_pack:
		eng.stream = snd._looped(({"v8": "muscle_car", "truck": "truck"} as Dictionary).get(fam, "car") + "_mid_loop")
	if eng.stream == null:
		eng.stream = snd._looped("eng_%s_2" % fam)
	eng.bus = "SFX"
	eng.unit_size = 9.0
	eng.max_distance = 140.0
	eng.volume_db = -10.0
	eng.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	c.add_child(eng)
	if eng.stream:
		eng.play(randf())
	var st: Dictionary = STYLE[r["style"]]
	var d := {"car": c, "who": who, "mode": "roam", "style": r["style"], "st": st, "path": PackedVector3Array(), "pi": 0, "replan": 0.0,
		"goal": Vector3.ZERO, "ds": "grip", "dt": 0.0, "dsteer": 0.0, "bend_k": -1, "stuck": 0.0, "rev": 0.0, "flip": 0.0, "slot": 0,
		"blip": blip, "tag": tag, "eng": eng, "pitch": float(def.get("pitch", 1.0)), "chased": false, "cool": randf_range(4.0, 10.0),
		"meet": 0.0, "life": 0.0, "bust_at": 0.0, "look": 0.0, "clear": false, "lane": 1.7, "nos": 0.0, "you_drift": 0.0}
	drivers.append(d)
	_roam(d)
	if not called:
		# set off along the way it's going (not facing back down it)
		var path: PackedVector3Array = d["path"]
		if path.size() >= 3:
			var pd := Vector2(path[2].x - path[0].x, path[2].z - path[0].z)
			if pd.length() > 0.5 and pd.normalized().dot(Vector2(-xf.basis.z.x, -xf.basis.z.z)) < 0.0:
				var flipped: Transform3D = game.on_ground(Transform3D(Basis(Vector3.UP, atan2(-pd.x, -pd.y)), xf.origin))
				c.place(flipped)
				c.linear_velocity = -flipped.basis.z * 14.0
				c.reset_physics_interpolation()
	stats["spawned"] += 1
	return d

## A spot on a road out of your sight: round you (a roamer), or nearer, behind you (someone you've called).
func _spot(called: bool) -> Dictionary:
	var cam: Camera3D = game.cam
	var you: Vector3 = game.car.global_position
	var back := Vector2(cam.global_transform.basis.z.x, cam.global_transform.basis.z.z).normalized()
	for tries in 40:
		var dirn := Vector2.from_angle(randf() * TAU)
		if called and tries < 28:
			dirn = back.rotated(randf_range(-1.2, 1.2))
		var q := Vector2(you.x, you.z) + dirn * (randf_range(70.0, 130.0) if called else randf_range(120.0, 260.0))
		var loc: Array = game.router.nearest_near(q, 20.0)
		if int(loc[0]) < 0:
			continue
		var ri := int(loc[0])
		if not game.police.LIMIT.has(island.roads[ri]["kind"]) or String(island.roads[ri]["kind"]) == "dirt":
			continue
		var s := float(loc[1])
		var pt: Vector2 = game.router.road_at(ri, s)
		var pos := Vector3(pt.x, island.height_at(pt.x, pt.y) + 0.7, pt.y)
		if pos.distance_to(you) < (55.0 if called else 100.0):
			continue
		if cam.is_position_in_frustum(pos) and pos.distance_to(cam.global_position) < 240.0 and _sees(cam.global_position, pos + Vector3(0, 0.6, 0)):
			continue
		var clear := true
		for d in drivers:
			if (d["car"] as Node3D).global_position.distance_to(pos) < 14.0:
				clear = false
		for u in game.police.units:
			if is_instance_valid(u["car"]) and (u["car"] as Node3D).global_position.distance_to(pos) < 14.0:
				clear = false
		for tc in traffic.cars:
			if (tc["body"] as Node3D).global_position.distance_to(pos) < 10.0:
				clear = false
		if not clear:
			continue
		var t: Vector2 = (game.router.road_at(ri, s + 1.0) - game.router.road_at(ri, s - 1.0)).normalized()
		if called and t.dot(Vector2(you.x, you.z) - pt) < 0.0:
			t = -t           # (someone you've called sets off your way)
		elif not called and randf() < 0.5:
			t = -t
		var xf: Transform3D = game.on_ground(Transform3D(Basis(Vector3.UP, atan2(-t.x, -t.y)), pos))
		return {"xf": xf}
	return {}

## One of your crew got left way behind: back on a road behind you, out of sight.
func _bring_back(d: Dictionary) -> void:
	var spot := _spot(true)
	if spot.is_empty():
		return
	var c: Car = d["car"]
	var xf: Transform3D = spot["xf"]
	c.place(xf)
	c.linear_velocity = -xf.basis.z * 14.0
	c.reset_physics_interpolation()
	d["path"] = PackedVector3Array()
	d["replan"] = 0.0
	d["ds"] = "grip"
	stats["respawns"] += 1

## Teleported (fast travel, a reset): your crew come along.
func you_moved() -> void:
	trail = PackedVector3Array()
	for d in drivers.duplicate():
		if d["mode"] == "crew":
			_bring_back(d)
		elif (d["car"] as Node3D).global_position.distance_to(game.car.global_position) > 300.0:
			_free(d)

func _free(d: Dictionary) -> void:
	if is_instance_valid(d["car"]):
		(d["car"] as Node).queue_free()
	drivers.erase(d)

func _driver_of(who: int) -> Dictionary:
	for d in drivers:
		if int(d["who"]) == who and is_instance_valid(d["car"]):
			return d
	return {}

func _driver_by_car(n: Node) -> Dictionary:
	for d in drivers:
		if d["car"] == n:
			return d
	return {}

func _who(nm: String) -> int:
	for i in ROSTER.size():
		if ROSTER[i]["name"] == nm:
			return i
	return -1

## Off on their own: somewhere a good way off, by the roads.
func _roam(d: Dictionary) -> void:
	d["mode"] = "roam"
	_plan(d)
	if is_instance_valid(d["blip"]):
		(d["blip"] as MeshInstance3D).material_override = _blip_mat

## Somewhere to head for, and the way there: one whose way starts off the way the car's pointing if it
## can (so it doesn't have to turn round), from a few picks.
func _plan(d: Dictionary, away_from := Vector3.INF) -> void:
	var c: Car = d["car"]
	var pos := c.global_position
	var f := -c.global_transform.basis.z
	var f2 := Vector2(f.x, f.z).normalized()
	var best := PackedVector3Array()
	var best_goal := Vector3.ZERO
	var best_dot := -2.0
	for tries in 4:
		var goal := _somewhere(d, 260.0, 520.0, away_from)
		var path: PackedVector3Array = game.router.find(pos, goal, true)
		if path.size() < 3:
			continue
		var k := mini(4, path.size() - 1)
		var pd := Vector2(path[k].x - pos.x, path[k].z - pos.z)
		var dot := pd.normalized().dot(f2) if pd.length() > 0.5 else 0.0
		if dot > best_dot:
			best_dot = dot
			best = path
			best_goal = goal
		if dot > 0.5:
			break
	d["goal"] = best_goal if not best.is_empty() else _somewhere(d, 260.0, 520.0, away_from)
	d["path"] = best
	d["pi"] = 0
	d["replan"] = 30.0
	d["prog"] = INF
	d["prog_t"] = 0.0

## A road point some way off (mostly ahead of where the car's pointing, so it keeps going).
func _somewhere(d: Dictionary, rmin: float, rmax: float, away_from := Vector3.INF) -> Vector3:
	var c: Car = d["car"]
	var p := c.global_position
	var f := -c.global_transform.basis.z
	var dir := Vector2(f.x, f.z).normalized()
	if away_from != Vector3.INF:
		dir = Vector2(p.x - away_from.x, p.z - away_from.z).normalized()
	for tries in 12:
		var q := Vector2(p.x, p.z) + dir.rotated(randf_range(-1.4, 1.4)) * randf_range(rmin, rmax)
		q = q.clamp(Vector2(-560, -560), Vector2(560, 560))
		var loc: Array = game.router.nearest_near(q, 30.0)
		if int(loc[0]) < 0 or not game.police.LIMIT.has(island.roads[int(loc[0])]["kind"]):
			continue
		var pt: Vector2 = game.router.road_at(int(loc[0]), float(loc[1]))
		if Vector2(p.x, p.z).distance_to(pt) > rmin * 0.6:
			return Vector3(pt.x, 0, pt.y)
	return p + Vector3(randf_range(-300, 300), 0, randf_range(-300, 300))

# ------------------------------------------------------------------ the police

func _patrol_check(d: Dictionary) -> void:
	var police: Node = game.police
	var c: Car = d["car"]
	var p := c.global_position
	if police.npc_chases() >= 2:
		return
	for tc in traffic.cars:
		if String(tc["model"]) != "k_car_police" or int(tc["mode"]) >= traffic.KNOCKED:
			continue
		var b: Node3D = tc["body"]
		if b.global_position.distance_to(p) > police.SEE_R:
			continue
		if police._cone(b.global_position, -b.global_transform.basis.z, p, police.SEE_R, police.SEE_ANG, police.NEAR_R):
			d["cool"] = 25.0
			if randf() > (0.12 if d["mode"] == "crew" else 0.4):
				return           # (they let this one go)
			police.chase_npc(tc, c)
			d["chased"] = true
			stats["chases"] += 1
			if d["mode"] == "roam":
				d["mode"] = "flee"
				_plan(d, b.global_position)
			var nm := String(ROSTER[int(d["who"])]["name"])
			if d["mode"] == "crew" or p.distance_to(game.car.global_position) < 90.0:
				game.ui.toast("The police are after %s!" % nm, "eye", Color("ff5c7a"), Color.WHITE, 2.2)
			return

## Something on the road near us: [metres ahead, metres to the right, its speed along our way].
func _ob(out: Array, p: Vector3, vel: Vector3, pos: Vector3, fwd: Vector3, rgt: Vector3, look_d: float) -> void:
	var rel := p - pos
	var ahead := rel.dot(fwd)
	if ahead < -8.0 or ahead > look_d * 1.6:
		return
	var lat := rel.dot(rgt)
	if absf(lat) > 9.0:
		return
	out.append([ahead, lat, vel.dot(fwd)])

## Where the police car after this one is (or the car itself, if none).
func _chaser_pos(d: Dictionary) -> Vector3:
	for u in game.police.units:
		if u.get("npc", false) and u["target"] == d["car"] and is_instance_valid(u["car"]):
			return (u["car"] as Node3D).global_position
	return (d["car"] as Node3D).global_position - (d["car"] as Node3D).global_transform.basis.z * -10.0

## (from the police) they've stopped one.
func npc_busted(n: Node) -> void:
	var d := _driver_by_car(n)
	if d.is_empty():
		return
	d["chased"] = false
	stats["busted"] += 1
	var nm := String(ROSTER[int(d["who"])]["name"])
	var close := (d["car"] as Node3D).global_position.distance_to(game.car.global_position) < 120.0
	if d["mode"] == "crew" or close:
		game.ui.toast("%s got busted!" % nm, "eye", Color("ff5c7a"), Color.WHITE, 2.4)
	d["mode"] = "busted"
	d["bust_at"] = float(d["life"])
	(d["blip"] as MeshInstance3D).material_override = _blip_mat
	(d["tag"] as Label3D).modulate = Color(1, 0.6, 0.6, 0.9)

## (from the police) they've lost one.
func npc_lost(n: Node) -> void:
	var d := _driver_by_car(n)
	if d.is_empty():
		return
	d["chased"] = false
	stats["lost"] += 1
	var nm := String(ROSTER[int(d["who"])]["name"])
	if d["mode"] == "crew":
		game.ui.toast("%s: Lost 'em!" % nm, "phone", Color("8ff0b0"), K.INK, 2.0)
	elif d["mode"] == "flee":
		_roam(d)

# ------------------------------------------------------------------ driving

func _drive(d: Dictionary, dt: float) -> void:
	var c: Car = d["car"]
	if c.freeze or c.righting():
		return
	# (a safety net: if the physics ever flings one, calm it down rather than let it fly off)
	if c.linear_velocity.length() > 60.0 or c.angular_velocity.length() > 12.0:
		c.linear_velocity = c.linear_velocity.limit_length(30.0)
		c.angular_velocity = c.angular_velocity.limit_length(3.0)
	var you: Car = game.car
	var pos := c.global_position
	var p2 := Vector2(pos.x, pos.z)
	var v := c.linear_velocity.length()
	var fwd := -c.global_transform.basis.z
	var rgt := c.global_transform.basis.x
	fwd.y = 0.0
	rgt.y = 0.0
	fwd = fwd.normalized()
	rgt = rgt.normalized()
	var st: Dictionary = d["st"]
	var mode := String(d["mode"])
	c.nitro = 0.0
	if mode == "busted":
		c.throttle = 0.0
		c.brake = 1.0 if v > 1.0 else 0.0
		c.handbrake = 1.0
		c.steer_in = 0.0
		return
	var vmax: float = float(st["vmax"]) * (1.08 if mode == "flee" else 1.0)
	var yp := you.global_position
	var yv := you.linear_velocity
	var yspd := yv.length()
	var d_you := p2.distance_to(Vector2(yp.x, yp.z))
	# ---- where to go, and how fast
	var aim := Vector2.ZERO
	var vt := vmax
	var close := false
	var bend := 0.0           # the turn coming up (radians, + right), and how far off it starts
	var bend_at := INF
	var on_trail := {}
	if mode == "crew":
		d["look"] = float(d["look"]) - dt
		if float(d["look"]) <= 0.0:
			d["look"] = 0.3
			d["clear"] = d_you < 70.0 and _sees(pos, yp)
		on_trail = _on_trail(d, p2)
		close = not on_trail.is_empty() or (bool(d["clear"]) and d_you < 30.0)
	if close:
		# with you: along the line you drove (so round the corners as you took them), sat off your back
		# quarter at your speed
		var sl: Array = SLOTS[int(d["slot"])]
		var yf := yv.normalized() if yspd > 4.0 else -you.global_transform.basis.z
		yf.y = 0.0
		yf = yf.normalized()
		var behind := 0.0          # metres along your line from us to you
		if not on_trail.is_empty():
			var ti: int = on_trail["i"]
			var proj: Vector2 = on_trail["p"]
			behind = float(on_trail["left"])
			var la := 6.0 + v * 0.4
			var tpts := trail
			if behind - la < float(sl[0]) * 0.5:
				# (nearly up to you: aim past you, along where you're heading)
				aim = Vector2(yp.x, yp.z) + Vector2(yf.x, yf.z) * (la - behind + 4.0)
			else:
				aim = _ahead(tpts, ti + 1, proj, la)
			# off to our side of your line (less of it round the bends)
			var a2 := _ahead(tpts, ti + 1, proj, la + 2.5)
			var pd := (a2 - aim).normalized()
			var bd := _bend(tpts, ti, proj)
			if pd.length() > 0.5:
				aim += Vector2(-pd.y, pd.x) * float(sl[1]) * (0.35 if absf(float(bd[0])) > 0.5 and float(bd[1]) < 25.0 else 1.0)
			vt = minf(vt, _corner_speed(tpts, ti, proj, float(st["lat"]) * 1.05, vmax * 1.1, 3))
			bend = bd[0]
			bend_at = bd[1]
		else:
			behind = (yp - pos).dot(yf)
			var slot := yp - yf * float(sl[0]) + Vector3(-yf.z, 0, yf.x) * float(sl[1])
			aim = Vector2(slot.x, slot.z)
		var gap := behind - float(sl[0])             # (+: further back than our place)
		var v_corner := vt                            # (what the bends ahead allow: never more than that)
		vt = minf(v_corner, yspd + clampf(gap * 0.55, -9.0, 14.0))
		if gap > 25.0:
			vt = minf(v_corner, maxf(vt, yspd + 10.0))
		if yspd < 2.0:
			var slot2 := yp - yf * float(sl[0]) + Vector3(-yf.z, 0, yf.x) * float(sl[1])
			var ds := pos.distance_to(slot2)
			aim = Vector2(slot2.x, slot2.z)
			vt = 0.0 if ds < 3.5 else clampf(ds * 0.8, 2.0, 12.0)
		# (never into the back of you)
		var to_you := yp - pos
		if to_you.length() < 7.0 and to_you.normalized().dot(fwd) > 0.6:
			vt = minf(vt, yspd - 1.5)
		if gap > 30.0 and absf(bend) < 0.3 and v > 12.0:
			c.nitro = 1.0
		d["path"] = PackedVector3Array()
	else:
		# (your crew head for where you're going, a few seconds on, not where you were)
		var lead_v := yv * clampf(d_you / 30.0, 0.0, 3.0)
		var goal: Vector3 = (yp + lead_v.limit_length(35.0)) if mode == "crew" else d["goal"]
		var path: PackedVector3Array = d["path"]
		d["replan"] = float(d["replan"]) - dt
		if path.size() < 2 or float(d["replan"]) <= 0.0:
			var np: PackedVector3Array = game.router.find(pos, goal, true)
			# (a new way that starts by turning round, while the one it's on still goes somewhere near: keep going)
			var keep := false
			if mode == "crew" and path.size() >= 2 and np.size() >= 3 and v > 8.0 and not bool(d.get("off", false)):
				var k := mini(4, np.size() - 1)
				var nd2 := Vector2(np[k].x - pos.x, np[k].z - pos.z)
				var end := path[path.size() - 1]
				if nd2.length() > 0.5 and nd2.normalized().dot(Vector2(fwd.x, fwd.z)) < -0.2 and Vector2(end.x - goal.x, end.z - goal.z).length() < 90.0 and int(d["pi"]) < path.size() - 4:
					keep = true
			if not keep:
				path = np
				d["path"] = path
				d["pi"] = 0
			d["off"] = false
			d["replan"] = randf_range(2.0, 2.8) if mode == "crew" else 30.0
		if path.size() < 2:
			aim = Vector2(goal.x, goal.z)
			d["replan"] = minf(float(d["replan"]), 0.5)
		else:
			# where it is along the way: its nearest point on the next stretch of it (projected, so the point
			# it steers for is always down the road from there, never one it's circling round)
			var pi: int = d["pi"]
			var nd := INF
			var proj := p2
			for k in range(pi, mini(pi + 16, path.size() - 1)):
				var a := Vector2(path[k].x, path[k].z)
				var b := Vector2(path[k + 1].x, path[k + 1].z)
				var ab := b - a
				var t := clampf((p2 - a).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
				var q := a + ab * t
				var dk := p2.distance_to(q)
				if dk < nd - 0.01:
					nd = dk
					pi = k
					proj = q
			d["pi"] = pi
			# well off the way (pushed off, a wrong turn): a new way from here
			if nd > 14.0 and float(d["replan"]) > 0.6:
				d["replan"] = 0.0
				d["off"] = true
			var la := 7.0 + v * 0.42
			aim = _ahead(path, pi + 1, proj, la)
			# on the right-hand side of the road (traffic drives on the right), out to the left to pass
			var a2 := _ahead(path, pi + 1, proj, la + 2.0)
			var pd := (a2 - aim).normalized()
			if pd.length() > 0.5:
				aim += Vector2(-pd.y, pd.x) * float(d["lane"])
			vt = minf(vt, _corner_speed(path, pi, p2, float(st["lat"]), vmax))
			var bd := _bend(path, pi, p2)
			bend = bd[0]
			bend_at = bd[1]
			d["bend_k"] = int(bd[2]) if bend_at < INF else int(d["bend_k"])
			if mode != "crew" and (p2.distance_to(Vector2(goal.x, goal.z)) < 30.0 or pi >= path.size() - 2):
				if d["chased"]:
					_plan(d, _chaser_pos(d))     # (still got them on its tail: keep running)
				else:
					_roam(d)
		if mode == "crew":
			# catching up: flat out, with a squirt of nitrous on the straights
			vt = minf(vmax * 1.1, vt * 1.06)
			if d_you > 70.0 and absf(bend) < 0.3 and v > 12.0:
				c.nitro = 1.0
			# you're coming this way: pull over and wait for you to go by (don't turn round in front of you)
			var to_us := pos - yp
			if yspd > 6.0 and d_you < 130.0 and yv.normalized().dot(to_us.normalized()) > 0.6 and fwd.dot(to_us.normalized()) < -0.2:
				vt = minf(vt, 6.0)
				d["wait_you"] = 0.6
	d["wait_you"] = maxf(0.0, float(d.get("wait_you", 0.0)) - dt)
	# ---- the traffic, the police, the other drivers and you: past them if there's room (looking out for
	# what's coming the other way), or sit behind at their speed till there is
	var look_d := 10.0 + v * 1.5
	var pass_w: float = float(st["pass"])
	var dodge := 0.0
	var lane_want := 1.7
	var obs := []            # [ahead, lateral, speed along our way]
	for tc in traffic.cars:
		var tb: Node3D = tc["body"]
		_ob(obs, tb.global_position, -tb.global_transform.basis.z * float(tc["v"]), pos, fwd, rgt, look_d)
	for u in game.police.units:
		if is_instance_valid(u["car"]):
			_ob(obs, (u["car"] as Node3D).global_position, (u["car"] as RigidBody3D).linear_velocity, pos, fwd, rgt, look_d)
	for o in drivers:
		if o != d and is_instance_valid(o["car"]):
			_ob(obs, (o["car"] as Node3D).global_position, (o["car"] as RigidBody3D).linear_velocity, pos, fwd, rgt, look_d)
	if not close or d_you < 12.0:
		_ob(obs, yp, yv, pos, fwd, rgt, look_d)
	# the nearest thing in our way that we'd reach in the next few seconds
	var block := []
	for o in obs:
		var ahead: float = o[0]
		var lat: float = o[1]
		if ahead < 0.5 or absf(lat) > pass_w:
			continue
		var closing: float = v - float(o[2])
		if ahead / maxf(closing, 0.5) < 3.2 or ahead < 9.0:
			if block.is_empty() or ahead < float(block[0]):
				block = o
	if not block.is_empty():
		var b_ahead: float = block[0]
		var b_lat: float = block[1]
		var b_v: float = block[2]
		# round it: left first (overtaking), then right, if nothing's there (or coming) on that side
		var went := false
		for side in [-1.0, 1.0]:
			var want_lat: float = b_lat + float(side) * (pass_w + 0.9)
			if absf(want_lat) > 5.5:
				continue
			var free := true
			for o in obs:
				if o == block:
					continue
				var oa: float = o[0]
				var closing2: float = v - float(o[2])
				# (anything alongside that lane from just behind us to well past it, coming towards us further)
				var reach := b_ahead + 12.0 + maxf(closing2 - (v - b_v), 0.0) * 2.0
				if oa > -6.0 and oa < reach and absf(float(o[1]) - want_lat) < 2.4:
					free = false
					break
			if free:
				dodge = want_lat
				lane_want = -1.8 if float(side) < 0.0 else 1.7
				went = true
				break
		if not went:
			# no way by: sit behind it, closing the gap gently
			vt = minf(vt, b_v + clampf((b_ahead - 9.0) * 0.6, -8.0, 4.0))
	d["lane"] = move_toward(float(d["lane"]), lane_want, dt * 3.0)
	if dodge != 0.0:
		aim += Vector2(rgt.x, rgt.z) * dodge
	var to := Vector3(aim.x - pos.x, 0, aim.y - pos.z)
	var ang := atan2(fwd.z * to.x - fwd.x * to.z, fwd.x * to.x + fwd.z * to.z)
	var steer := clampf(-ang * 2.4, -1.0, 1.0)
	if game.args.has("crewdebug2") and int(d["who"]) == 0 and int(game.time * 2.0) != int((game.time - dt) * 2.0):
		print("K t=%.1f close=%s d_you=%.0f v=%.1f vt=%.1f ang=%.2f dodge=%.1f lane=%.1f path=%d pi=%d bend=%.2f@%.0f ds=%s wait=%.1f pos=(%.0f,%.0f) you=(%.0f,%.0f) aim=(%.0f,%.0f) gr=%d" % [game.time, close, d_you, v, vt, ang, dodge,
			float(d["lane"]), (d["path"] as PackedVector3Array).size(), int(d["pi"]), bend, bend_at, String(d["ds"]), float(d.get("wait_you", 0.0)), pos.x, pos.z, yp.x, yp.z, aim.x, aim.y, c.grounded])
	# ---- drifting
	var ds := String(d["ds"])
	d["dt"] = float(d["dt"]) + dt
	var you_drifting := you.drift_mode and you.drift > 0.15 and yspd > 10.0
	if game.args.has("fakedrift"):
		you_drifting = yspd > 10.0 and fmod(game.time, 8.0) < 2.5      # (a test: as if you were drifting)
	d["you_drift"] = float(d["you_drift"]) + dt if you_drifting else 0.0
	if you_drifting:
		stats["you_drift_t"] = float(stats.get("you_drift_t", 0.0)) + dt
		if close and d_you < 32.0:
			stats["you_drift_near"] = float(stats.get("you_drift_near", 0.0)) + dt
	match ds:
		"grip":
			var go := false
			var dir := 0.0
			if mode == "crew":
				# tandem: you're drifting and we're right on you: in we go too, the same way
				if close and float(d["you_drift"]) > 0.15 and v > 11.0 and d_you < 32.0:
					go = true
					stats["tandem"] += 1
					dir = -signf(you.angular_velocity.y) if absf(you.angular_velocity.y) > 0.15 else signf(steer)
			elif bend_at < 16.0 and absf(bend) > 0.75 and v > 13.0 and v < 34.0 and dodge == 0.0:
				# a proper corner coming up: drift it? (decided once per corner)
				if int(d["bend_k"]) != int(d.get("rolled_k", -99)):
					d["rolled_k"] = int(d["bend_k"])
					d["want_drift"] = randf() < float(st["drift"])
				if d.get("want_drift", false):
					go = true
					dir = signf(bend)
			if go and dir != 0.0:
				d["ds"] = "flick"
				d["dt"] = 0.0
				d["dsteer"] = dir
				stats["drifts"] += 1
		"flick":
			# a pull on the handbrake with the wheel turned in: the tail steps out
			c.handbrake = 1.0
			c.throttle = 1.0
			c.brake = 0.0
			c.steer_in = float(d["dsteer"])
			if float(d["dt"]) > 0.22:
				d["ds"] = "drift"
				d["dt"] = 0.0
			return
		"drift":
			# balanced on the throttle, the wheel aimed down the road (the car's own hands catch the slide)
			var done := false
			if mode == "crew":
				done = float(d["you_drift"]) <= 0.0 and float(d["dt"]) > 0.4
				if not close:
					done = true
			else:
				done = float(d["dt"]) > 0.6 and absf(ang) < 0.3 and absf(bend) < 0.35
			if float(d["dt"]) > 4.5 or absf(c.slip) > deg_to_rad(75.0) or v < 6.0 or dodge != 0.0:
				done = true
			if done:
				d["ds"] = "exit"
				d["dt"] = 0.0
			else:
				c.handbrake = 0.0
				c.brake = 0.0
				c.throttle = 0.9 if (mode != "crew" or v < vt + 2.0) else 0.55
				c.steer_in = clampf(-ang * 2.0, -1.0, 1.0)
				return
		"exit":
			# off the gas a moment: it straightens up and grips again
			c.handbrake = 0.0
			c.brake = 0.0
			c.throttle = 0.35
			c.steer_in = steer
			if float(d["dt"]) > 0.35 or not c.drift_mode:
				d["ds"] = "grip"
				d["dt"] = 0.0
			return
	if game.args.has("crashlog"):
		var lv := float(d.get("lastv", v))
		if lv - v > 9.0:
			var h: Dictionary = c.hit
			var who = h.get("who")
			print("CRASH %s t=%.1f %s close=%s %.0f->%.0f kmh kind=%s who=%s ds=%s dodge=%.1f bend=%.2f@%.0f pos=(%.0f,%.0f)" % [String(ROSTER[int(d["who"])]["name"]), game.time, mode, close, lv * 3.6, v * 3.6,
				String(h.get("kind", "?")), (who as Node).name if who is Node else str(who), String(d["ds"]), dodge, bend, bend_at, pos.x, pos.z])
		d["lastv"] = v
	# ---- grip driving: hold the speed it wants
	c.handbrake = 0.0
	if absf(ang) > 0.7 and v > 9.0:
		vt = minf(vt, v - 2.0)
	if vt <= 0.0 and v < 1.0:
		c.throttle = 0.0
		c.brake = 0.0
		c.handbrake = 1.0
	elif v < vt - 0.6:
		c.throttle = 1.0
		c.brake = 0.0
	elif v > vt + 1.2:
		c.throttle = 0.0
		c.brake = clampf((v - vt) / 4.0, 0.3, 1.0)
	else:
		c.throttle = 0.45
		c.brake = 0.0
	c.steer_in = steer
	var parked := close and yspd < 2.0
	# the way on is behind it: quick, a handbrake turn; slow, back round (a three-point turn)
	d["behind_t"] = float(d.get("behind_t", 0.0)) + dt if absf(ang) > 1.7 else 0.0
	if float(d["behind_t"]) > 0.8 and not close and float(d["rev"]) <= 0.0 and dodge == 0.0 and float(d["wait_you"]) <= 0.0:
		d["behind_t"] = 0.0
		if v > 9.0 and v < 22.0:
			d["ds"] = "flick"
			d["dt"] = -0.25            # (a longer pull: right round)
			d["dsteer"] = signf(steer) if steer != 0.0 else 1.0
		elif v < 6.0:
			d["rev"] = 1.1
	# stuck against something (or nosed up to it, going nowhere): back up, wheel the other way
	if float(d["rev"]) > 0.0:
		d["rev"] = float(d["rev"]) - dt
		c.throttle = 0.0
		c.brake = 1.0
		c.handbrake = 0.0
		c.steer_in = -steer
	elif v < 1.0 and not parked:
		d["stuck"] = float(d["stuck"]) + dt
		if float(d["stuck"]) > 2.0:
			d["stuck"] = 0.0
			d["rev"] = 1.5
	else:
		d["stuck"] = maxf(0.0, float(d["stuck"]) - dt)
	# going round in circles (getting no nearer where it's going): a new way, from scratch
	if not close:
		var gd := p2.distance_to(Vector2(yp.x, yp.z) if mode == "crew" else Vector2((d["goal"] as Vector3).x, (d["goal"] as Vector3).z))
		if gd < float(d.get("prog", INF)) - 6.0:
			d["prog"] = gd
			d["prog_t"] = 0.0
		else:
			d["prog_t"] = float(d.get("prog_t", 0.0)) + dt
			if float(d["prog_t"]) > (8.0 if mode != "crew" else 5.0):
				d["prog_t"] = 0.0
				d["prog"] = INF
				d["replan"] = 0.0
				if mode != "crew":
					_roam(d)
	# on its roof or side: back on its wheels
	d["flip"] = float(d["flip"]) + dt if c.global_transform.basis.y.y < 0.35 else 0.0
	if float(d["flip"]) > 1.8:
		d["flip"] = 0.0
		c.right_up()
		stats["rights"] += 1

## Where we are on your line, if we're on it: {i (segment), p (the nearest point on it), left (metres
## from there along it to you)}; empty if we're not near it.
func _on_trail(d: Dictionary, p2: Vector2) -> Dictionary:
	var n := trail.size()
	if n < 3:
		return {}
	var start := clampi(int(d.get("ti", 0)), 0, n - 2)
	var best := -1
	var bd := 9.0
	var bp := p2
	# (from where we were last time, onwards; or anywhere, if that's no good)
	for pass_i in 2:
		var from := start if pass_i == 0 else 0
		for k in range(from, n - 1):
			var a := Vector2(trail[k].x, trail[k].z)
			var b := Vector2(trail[k + 1].x, trail[k + 1].z)
			var ab := b - a
			var t := clampf((p2 - a).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
			var q := a + ab * t
			var dk := p2.distance_to(q)
			if dk < bd:
				bd = dk
				best = k
				bp = q
		if best >= 0:
			break
	if best < 0:
		d["ti"] = 0
		return {}
	d["ti"] = best
	var left := bp.distance_to(Vector2(trail[best + 1].x, trail[best + 1].z)) + float(n - 2 - best) * TRAIL_STEP
	return {"i": best, "p": bp, "left": left}

## The point la metres along the path ahead of from.
func _ahead(path: PackedVector3Array, pi: int, from: Vector2, la: float) -> Vector2:
	var cur := from
	var left := la
	var k := pi
	while k < path.size():
		var nxt := Vector2(path[k].x, path[k].z)
		var l := cur.distance_to(nxt)
		if l >= left:
			return cur.lerp(nxt, left / maxf(l, 0.001))
		left -= l
		cur = nxt
		k += 1
	return Vector2(path[path.size() - 1].x, path[path.size() - 1].z)

## How fast it can go and still make the bends coming up (braking in time).
func _corner_speed(path: PackedVector3Array, pi: int, from: Vector2, lat: float, vmax: float, step := 1) -> float:
	var vt := vmax
	var acc := from.distance_to(Vector2(path[mini(pi, path.size() - 1)].x, path[mini(pi, path.size() - 1)].z))
	for k in range(pi, mini(pi + 18 * step, path.size() - 2 * step), step):
		var d1 := Vector2(path[k + step].x - path[k].x, path[k + step].z - path[k].z)
		var d2 := Vector2(path[k + 2 * step].x - path[k + step].x, path[k + 2 * step].z - path[k + step].z)
		var l1 := d1.length()
		var l2 := d2.length()
		if l1 < 0.5 or l2 < 0.5:
			acc += l1
			continue
		var turn := absf(d1.angle_to(d2))
		if turn > 0.06:
			var rad := (l1 + l2) * 0.5 / turn
			var vc := clampf(sqrt(lat * 0.88 * rad), 8.0, vmax)
			vt = minf(vt, sqrt(vc * vc + 2.0 * 6.0 * maxf(acc - 6.0, 0.0)))
		acc += l1
	return vt

## The next proper bend along the path: [turn over it (radians, + right), metres till it starts, index].
func _bend(path: PackedVector3Array, pi: int, from: Vector2) -> Array:
	var acc := from.distance_to(Vector2(path[mini(pi, path.size() - 1)].x, path[mini(pi, path.size() - 1)].z))
	for k in range(pi, mini(pi + 12, path.size() - 2)):
		var d1 := Vector2(path[k + 1].x - path[k].x, path[k + 1].z - path[k].z)
		if d1.length() < 0.5:
			continue
		# how far the road turns over the next 20 m from here
		var tot := 0.0
		var run := 0.0
		var j := k
		while j < path.size() - 2 and run < 20.0:
			var a := Vector2(path[j + 1].x - path[j].x, path[j + 1].z - path[j].z)
			var b := Vector2(path[j + 2].x - path[j + 1].x, path[j + 2].z - path[j + 1].z)
			if a.length() > 0.3 and b.length() > 0.3:
				tot += a.angle_to(b)
			run += a.length()
			j += 1
		if absf(tot) > 0.75:
			return [tot, acc, k]
		acc += d1.length()
		if acc > 30.0:
			break
	return [0.0, INF, -1]

## Nothing solid between a and b, at about head height.
func _sees(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 1.3, 0), b + Vector3(0, 1.0, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

# ------------------------------------------------------------------ pause, garage, title

func hold(on: bool) -> void:
	held = on
	for d in drivers:
		var c: RigidBody3D = d["car"]
		if not is_instance_valid(c):
			continue
		(d["eng"] as AudioStreamPlayer3D).stream_paused = on
		if on and not c.freeze:
			d["held"] = [c.linear_velocity, c.angular_velocity]
			c.freeze = true
		elif not on and d.has("held"):
			c.freeze = false
			c.linear_velocity = d["held"][0]
			c.angular_velocity = d["held"][1]
			d.erase("held")

func clear() -> void:
	for d in drivers.duplicate():
		_free(d)
	_calls.clear()
	_away.clear()
