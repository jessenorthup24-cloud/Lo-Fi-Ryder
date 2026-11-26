extends Node3D
## The police helicopter (four stars and up): built in code (there's no helicopter in the kits), it flies
## in about 40 m up, hangs back and to one side of you and keeps you in view; after dark its searchlight
## follows its gaze down to the road. It sees you if you're inside the circle it's watching and nothing's
## in between (under the railway viaduct, you're hidden). Lose it and it searches round where you were seen;
## it's not as quick as a car flat out, so a long straight run gets you out of its circle.

const MB := preload("res://scripts/core/mesh_builder.gd")

const ALT := 40.0           # height over the ground
const VMAX := 46.0          # top speed, m/s (it keeps up with all but the quickest cars)
const ACC := 9.0
const WATCH_R := 34.0       # the circle on the ground it can see (around where it's looking)
const SEE_R := 70.0         # and anything out in the open this near below it: you have to get under something
const HP := 650.0           # (twenty-odd rifle rounds bring it down)

var island: Node
var vel := Vector3.ZERO
var look := Vector3.ZERO    # where it's watching, on the ground
var rotor: Node3D
var tail_rotor: Node3D
var beam: MeshInstance3D
var pool: MeshInstance3D
var leaving := false
var gone := false
var hp := HP
var downed := false         # shot down: falling, smoking, spinning
var crashed := false        # hit the ground (police.gd blows it up)
var _sound: AudioStreamPlayer3D
var _t := 0.0

func build(isl: Node, mat: Material, atmos: Node) -> void:
	island = isl
	var mb := MB.new()
	var navy := MB.rgb("1d3461")
	var white := MB.rgb("eef1f4")
	var dark := MB.rgb("2b2f36")
	var glass := MB.rgb("8fc8ee")
	mb.cbox(Vector3(0, 0, 0), Vector3(2.3, 2.0, 4.4), 0.55, navy)
	mb.cbox(Vector3(0, -0.62, 0.1), Vector3(2.36, 0.55, 4.2), 0.25, white)
	mb.cbox(Vector3(0, 0.25, -1.75), Vector3(2.0, 1.2, 1.5), 0.45, glass)
	mb.cbox(Vector3(0, 0.35, 4.3), Vector3(0.55, 0.55, 4.8), 0.2, navy)
	mb.cbox(Vector3(0, 1.05, 6.5), Vector3(0.16, 1.5, 1.0), 0.06, navy)
	mb.cbox(Vector3(0, 0.45, 6.4), Vector3(1.8, 0.12, 0.6), 0.04, white)
	mb.cbox(Vector3(0, 1.15, 0.2), Vector3(0.8, 0.5, 1.6), 0.15, dark)
	for sd in [-1.0, 1.0]:
		mb.cbox(Vector3(1.15 * sd, -1.55, 0.0), Vector3(0.16, 0.16, 4.0), 0.06, dark)
		mb.cbox(Vector3(0.95 * sd, -1.25, -0.9), Vector3(0.12, 0.6, 0.12), 0.03, dark)
		mb.cbox(Vector3(0.95 * sd, -1.25, 0.9), Vector3(0.12, 0.6, 0.12), 0.03, dark)
	var body := MeshInstance3D.new()
	body.mesh = mb.commit()
	body.material_override = mat
	add_child(body)
	# rotors (spun every frame)
	rotor = Node3D.new()
	rotor.position = Vector3(0, 1.5, 0.2)
	add_child(rotor)
	var rb := MB.new()
	rb.cbox(Vector3.ZERO, Vector3(0.38, 0.06, 11.5), 0.02, dark)
	rb.cbox(Vector3.ZERO, Vector3(11.5, 0.06, 0.38), 0.02, dark)
	rb.cbox(Vector3(0, 0.1, 0), Vector3(0.5, 0.25, 0.5), 0.05, dark)
	var rmi := MeshInstance3D.new()
	rmi.mesh = rb.commit()
	rmi.material_override = mat
	rotor.add_child(rmi)
	tail_rotor = Node3D.new()
	tail_rotor.position = Vector3(0.2, 1.15, 6.6)
	add_child(tail_rotor)
	var tb := MB.new()
	tb.cbox(Vector3.ZERO, Vector3(0.06, 1.6, 0.18), 0.01, dark)
	var tmi := MeshInstance3D.new()
	tmi.mesh = tb.commit()
	tmi.material_override = mat
	tail_rotor.add_child(tmi)
	# the searchlight: a beam (a long soft cone) and a pool of light where it lands
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://shaders/searchlight.gdshader")
	atmos.add_material(bm)
	beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 7.5
	cyl.height = 1.0
	cyl.radial_segments = 16
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.top_level = true
	add_child(beam)
	var pm := ShaderMaterial.new()
	pm.shader = preload("res://shaders/searchlight.gdshader")
	pm.set_shader_parameter("pool", true)
	atmos.add_material(pm)
	pool = MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(24.0, 24.0)          # (the light's pool; it watches a wider circle than it lights)
	pool.mesh = pl
	pool.material_override = pm
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.top_level = true
	add_child(pool)
	_sound = AudioStreamPlayer3D.new()
	var st = load("res://assets/audio/sfx/heli_loop.wav")
	if st is AudioStreamWAV:
		st = (st as AudioStreamWAV).duplicate()
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * st.mix_rate)
	_sound.stream = st
	_sound.bus = "SFX"
	_sound.unit_size = 30.0
	_sound.max_distance = 500.0
	_sound.volume_db = -2.0
	_sound.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_IDLE_STEP
	_sound.autoplay = true
	add_child(_sound)

## Fly: towards a spot back and to one side of `focus` (and over it), watching `aim`.
## Shot: true when this one brings it down.
func hit(dmg: float) -> bool:
	if downed or leaving:
		return false
	hp -= dmg
	if hp <= 0.0:
		downed = true
		beam.visible = false
		pool.visible = false
		return true
	return false

func tick(dt: float, focus: Vector3, aim: Vector3, night: float) -> void:
	_t += dt
	if downed:
		# falling: tail spinning round, nose down, till it hits
		vel.y -= 16.0 * dt
		vel.x *= 1.0 - dt * 0.4
		vel.z *= 1.0 - dt * 0.4
		global_position += vel * dt
		rotate_y(dt * 5.0)
		rotation.x = move_toward(rotation.x, -0.5, dt * 0.6)
		rotor.rotate_y(dt * 20.0)
		if global_position.y <= maxf(island.height_at(global_position.x, global_position.z), island.sea_y) + 1.0:
			crashed = true
			gone = true
		return
	var gy: float = maxf(island.height_at(global_position.x, global_position.z), island.sea_y)
	var want: Vector3
	if leaving:
		want = global_position + Vector3(global_position.x, 0, global_position.z).normalized() * 60.0 + Vector3(0, 30, 0)
	else:
		var side := Vector3(cos(_t * 0.15), 0, sin(_t * 0.15)) * 22.0      # (it drifts round you slowly)
		want = focus + side + Vector3(0, ALT + maxf(island.height_at(focus.x, focus.z), island.sea_y) - focus.y, 0)
		want.y = maxf(want.y, gy + 28.0)
	var to := want - global_position
	var dv := to.limit_length(VMAX) - vel
	if to.length() < 30.0:
		dv = to * 0.6 - vel                    # (settles over the spot instead of overshooting)
	vel += dv.limit_length(ACC * dt)
	vel = vel.limit_length(VMAX)
	global_position += vel * dt
	# nose round to the way it's going (or towards what it's watching when it's hanging there), tipped
	# into the acceleration like a real one
	look = look.lerp(aim, 1.0 - exp(-dt * 2.5)) if look != Vector3.ZERO else aim
	var face := Vector3(vel.x, 0, vel.z)
	if face.length() < 6.0:
		face = Vector3(look.x - global_position.x, 0, look.z - global_position.z)
	var yaw := atan2(-face.x, -face.z) if face.length() > 0.5 else rotation.y
	var acc_local := Basis(Vector3.UP, yaw).inverse() * dv / maxf(dt, 0.001)
	var pitch := clampf(acc_local.z * 0.02, -0.3, 0.3) + clampf(-Vector3(vel.x, 0, vel.z).length() * 0.006, -0.18, 0.0)
	var roll := clampf(-acc_local.x * 0.02, -0.3, 0.3)
	var cur := global_transform.basis.get_euler()
	global_transform.basis = Basis.from_euler(Vector3(lerp_angle(cur.x, -pitch, dt * 3.0), lerp_angle(cur.y, yaw, dt * 1.6), lerp_angle(cur.z, roll, dt * 3.0)))
	rotor.rotate_y(dt * 38.0)
	tail_rotor.rotate_x(dt * 55.0)
	# the searchlight (after dark)
	var on := night > 0.25 and not leaving
	beam.visible = on
	pool.visible = on
	if on:
		var from := global_position + Vector3(0, -1.2, -1.6)
		var ground := Vector3(look.x, maxf(island.height_at(look.x, look.z), island.sea_y) + 0.15, look.z)
		# (the cone's axis runs from the ground up to the lamp, stretched to the distance between)
		var l := from.distance_to(ground)
		var yv := (from - ground).normalized()
		var xv := yv.cross(Vector3.FORWARD) if absf(yv.dot(Vector3.FORWARD)) < 0.95 else yv.cross(Vector3.RIGHT)
		xv = xv.normalized()
		var zv := xv.cross(yv).normalized()
		beam.global_transform = Transform3D(Basis(xv, yv * l, zv), (from + ground) * 0.5)
		pool.global_transform = Transform3D(Basis(), ground)
	if leaving and global_position.distance_to(focus) > 450.0:
		gone = true

## Whether it can see p: inside the circle it's watching, nothing in between.
func sees(p: Vector3) -> bool:
	if leaving or downed:
		return false
	var under := Vector2(p.x - global_position.x, p.z - global_position.z).length() < SEE_R
	if not under and Vector2(p.x - look.x, p.z - look.z).length() > WATCH_R:
		return false
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, -2.0, 0), p + Vector3(0, 1.0, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func quiet(on: bool) -> void:
	_sound.stream_paused = on
