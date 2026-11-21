extends RefCounted
## Builds one vertex-colored ArrayMesh out of simple parts (boxes, bevelled boxes, cylinders, spheres).
## Colors are encoded for the toon shader:
##   pal(i)   palette slot i (changes with the season)
##   rgb(c)   a fixed color
##   glow(c)  a fixed color that lights up at night
##   TOP/SIDE a tile part whose slot comes from the MultiMesh instance

const TOP := Color(1, 0, 0, 0.3)
const SIDE := Color(0, 0, 0, 0.3)

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var ix := PackedInt32Array()

static func pal(i: int) -> Color:
	return Color(i / 255.0, 0, 0, 0.0)

static func rgb(col) -> Color:
	var k: Color = Color(col) if col is String else col
	return Color(k.r, k.g, k.b, 1.0)

static func glow(col) -> Color:
	var k: Color = Color(col) if col is String else col
	return Color(k.r, k.g, k.b, 0.5)

func _vert(p: Vector3, nm: Vector3, col: Color) -> int:
	v.push_back(p)
	n.push_back(nm)
	c.push_back(col)
	return v.size() - 1

## A triangle, wound so that its front faces the given normals (Godot fronts are clockwise).
func tri(a: Vector3, b: Vector3, d: Vector3, na: Vector3, nb: Vector3, nd: Vector3, col: Color) -> void:
	var fn := (b - a).cross(d - a)
	if fn.dot(na + nb + nd) > 0.0:
		var t := b; b = d; d = t
		var tn := nb; nb = nd; nd = tn
	ix.push_back(_vert(a, na, col))
	ix.push_back(_vert(b, nb, col))
	ix.push_back(_vert(d, nd, col))

func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, nm: Vector3, col: Color) -> void:
	# a b d e go around the quad
	tri(a, b, d, nm, nm, nm, col)
	tri(a, d, e, nm, nm, nm, col)

func _xf(basis: Basis, origin: Vector3, p: Vector3) -> Vector3:
	return basis * p + origin

func _xn(basis: Basis, nm: Vector3) -> Vector3:
	return (basis.inverse().transposed() * nm).normalized()

## Axis box. `size` full extents, centered on `center`.
func box(center: Vector3, size: Vector3, col: Color, basis := Basis()) -> void:
	cbox(center, size, 0.0, col, basis)

## Bevelled box (chunky toy look). bevel 0 gives a plain box.
func cbox(center: Vector3, size: Vector3, bevel: float, col: Color, basis := Basis(), col_top = null) -> void:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.95)
	var ct: Color = col if col_top == null else col_top
	for ax in 3:
		for s in [-1.0, 1.0]:
			var nm := Vector3.ZERO
			nm[ax] = s
			var u := (ax + 1) % 3
			var w := (ax + 2) % 3
			var pts := []
			for k in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				var p := Vector3.ZERO
				p[ax] = s * h[ax]
				p[u] = k[0] * (h[u] - b)
				p[w] = k[1] * (h[w] - b)
				pts.append(_xf(basis, center, p))
			var fcol: Color = ct if (ax == 1 and s > 0) else col
			quad(pts[0], pts[1], pts[2], pts[3], _xn(basis, nm), fcol)
	if b <= 0.0:
		return
	# edge bevels
	for ax in 3:
		var u := (ax + 1) % 3
		var w := (ax + 2) % 3
		for su in [-1.0, 1.0]:
			for sw in [-1.0, 1.0]:
				var nm := Vector3.ZERO
				nm[u] = su
				nm[w] = sw
				var pts := []
				for sa in [-1.0, 1.0]:
					var p1 := Vector3.ZERO
					p1[ax] = sa * (h[ax] - b)
					p1[u] = su * h[u]
					p1[w] = sw * (h[w] - b)
					var p2 := Vector3.ZERO
					p2[ax] = sa * (h[ax] - b)
					p2[u] = su * (h[u] - b)
					p2[w] = sw * h[w]
					pts.append(_xf(basis, center, p1))
					pts.append(_xf(basis, center, p2))
				var ecol: Color = ct if ((u == 1 and su > 0) or (w == 1 and sw > 0)) else col
				quad(pts[0], pts[2], pts[3], pts[1], _xn(basis, nm.normalized()), ecol)
	# corners
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var px := Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b))
				var py := Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b))
				var pz := Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z)
				var nm := _xn(basis, Vector3(sx, sy, sz).normalized())
				tri(_xf(basis, center, px), _xf(basis, center, py), _xf(basis, center, pz), nm, nm, nm, ct if sy > 0 else col)

## Cylinder along local Y. r2 < 0 means same radius at the top (r2 = 0 makes a cone).
func cyl(center: Vector3, r: float, height: float, col: Color, segs := 12, basis := Basis(), r2 := -1.0, caps := true, smooth := true) -> void:
	var rt := r if r2 < 0.0 else r2
	var y0 := -height * 0.5
	var y1 := height * 0.5
	var slope := (r - rt) / height
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		if not smooth:
			var dm := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
			n0 = (dm + Vector3(0, slope, 0)).normalized()
			n1 = n0
		var b0 := _xf(basis, center, d0 * r + Vector3(0, y0, 0))
		var b1 := _xf(basis, center, d1 * r + Vector3(0, y0, 0))
		var t0 := _xf(basis, center, d0 * rt + Vector3(0, y1, 0))
		var t1 := _xf(basis, center, d1 * rt + Vector3(0, y1, 0))
		var wn0 := _xn(basis, n0)
		var wn1 := _xn(basis, n1)
		if rt > 0.0001:
			tri(b0, b1, t1, wn0, wn1, wn1, col)
			tri(b0, t1, t0, wn0, wn1, wn0, col)
		else:
			tri(b0, b1, t0, wn0, wn1, _xn(basis, ((n0 + n1) * 0.5).normalized()), col)
		if caps:
			var up := _xn(basis, Vector3.UP)
			var dn := _xn(basis, Vector3.DOWN)
			if rt > 0.0001:
				tri(_xf(basis, center, Vector3(0, y1, 0)), t0, t1, up, up, up, col)
			tri(_xf(basis, center, Vector3(0, y0, 0)), b1, b0, dn, dn, dn, col)

## Ellipsoid (smooth). `scale` stretches it.
func sphere(center: Vector3, r: float, col: Color, segs := 12, rings := 7, scale := Vector3.ONE, basis := Basis()) -> void:
	var bs := basis * Basis.from_scale(scale)
	for j in rings:
		var p0 := PI * j / rings
		var p1 := PI * (j + 1) / rings
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var q := [
				Vector3(sin(p0) * cos(a0), cos(p0), sin(p0) * sin(a0)),
				Vector3(sin(p0) * cos(a1), cos(p0), sin(p0) * sin(a1)),
				Vector3(sin(p1) * cos(a1), cos(p1), sin(p1) * sin(a1)),
				Vector3(sin(p1) * cos(a0), cos(p1), sin(p1) * sin(a0)),
			]
			var w := []
			var wn := []
			for k in 4:
				w.append(_xf(bs, center, q[k] * r))
				wn.append(_xn(bs, q[k]))
			if j > 0:
				tri(w[0], w[1], w[2], wn[0], wn[1], wn[2], col)
			if j < rings - 1:
				tri(w[0], w[2], w[3], wn[0], wn[2], wn[3], col)

## Wedge: a ramp shape rising along -Z (local), full size `size`, base at y=0.
func wedge(center: Vector3, size: Vector3, col: Color, basis := Basis(), col_top = null) -> void:
	var h := size * 0.5
	var ct: Color = col if col_top == null else col_top
	var A := _xf(basis, center, Vector3(-h.x, 0, h.z))      # low front left
	var B := _xf(basis, center, Vector3(h.x, 0, h.z))       # low front right
	var Cc := _xf(basis, center, Vector3(h.x, 0, -h.z))     # back right bottom
	var D := _xf(basis, center, Vector3(-h.x, 0, -h.z))     # back left bottom
	var E := _xf(basis, center, Vector3(h.x, size.y, -h.z)) # back right top
	var F := _xf(basis, center, Vector3(-h.x, size.y, -h.z))
	var slope_n := _xn(basis, Vector3(0, size.z, size.y).normalized())
	quad(A, B, E, F, slope_n, ct)
	quad(D, Cc, E, F, _xn(basis, Vector3(0, 0, -1)), col)
	tri(B, Cc, E, _xn(basis, Vector3.RIGHT), _xn(basis, Vector3.RIGHT), _xn(basis, Vector3.RIGHT), col)
	tri(A, D, F, _xn(basis, Vector3.LEFT), _xn(basis, Vector3.LEFT), _xn(basis, Vector3.LEFT), col)
	quad(A, B, Cc, D, _xn(basis, Vector3.DOWN), col)

func is_empty() -> bool:
	return v.is_empty()

func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	var m := mesh if mesh else ArrayMesh.new()
	if v.is_empty():
		return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = ix
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
