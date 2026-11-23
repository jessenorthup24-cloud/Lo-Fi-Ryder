extends RefCounted
## GPS routes: the road network as a graph (junctions and road ends joined along the roads) and the
## shortest way along it between two places. find() returns the way as a line of points (x, 0, z) from
## where you are to the target, following the roads, with the target itself on the end.

const STEP := 2.5               # metres between a road's samples

var island
var verts: Array = []           # vertex -> Vector2
var adj: Array = []             # vertex -> [[other, length, road, s_here, s_there, dir]]
var on_road := {}               # road -> [[s, vertex]] sorted by s

func build(isl) -> void:
	island = isl
	verts.clear()
	adj.clear()
	on_road.clear()
	for ri in isl.roads.size():
		on_road[ri] = []
	for nd in isl.nodes:
		var vid := _vert(_road_pt(nd["members"][0][0], float(nd["members"][0][1])))
		for m in nd["members"]:
			on_road[m[0]].append([float(m[1]), vid])
	for ri in isl.roads.size():
		var r: Dictionary = isl.roads[ri]
		var n: int = (r["pts"] as PackedVector2Array).size()
		var list: Array = on_road[ri]
		if not r["closed"]:
			# the ends of the road, unless a junction is right there already
			for s_end in [0.0, float(n - 1)]:
				var near := false
				for e in list:
					if absf(float(e[0]) - s_end) < 3.0:
						near = true
				if not near:
					list.append([s_end, _vert(_road_pt(ri, s_end))])
		list.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		for i in list.size() - 1:
			_link(list[i], list[i + 1], ri, 1, float(list[i + 1][0]) - float(list[i][0]))
		if r["closed"] and list.size() >= 2:
			var last: Array = list[list.size() - 1]
			var first: Array = list[0]
			_link(last, first, ri, 1, float(n) - float(last[0]) + float(first[0]))

func _vert(p: Vector2) -> int:
	verts.append(p)
	adj.append([])
	return verts.size() - 1

func _road_pt(ri: int, s: float) -> Vector2:
	var pts: PackedVector2Array = island.roads[ri]["pts"]
	return pts[clampi(int(round(s)), 0, pts.size() - 1)]

## a and b are [s, vertex] on road ri; going from a to b steps s by dir (wrapping on a closed road).
func _link(a: Array, b: Array, ri: int, dir: int, samples: float) -> void:
	var va: int = a[1]
	var vb: int = b[1]
	if va == vb:
		return
	var l := absf(samples) * STEP
	adj[va].append([vb, l, ri, float(a[0]), float(b[0]), dir])
	adj[vb].append([va, l, ri, float(b[0]), float(a[0]), -dir])

## The nearest road to p: [road, s] (any road you can drive: lanes and tracks too).
func _nearest(p: Vector2) -> Array:
	var best := [0, 0.0]
	var bd := INF
	for ri in island.roads.size():
		var rn: Array = island.road_nearest(ri, p)
		if float(rn[0]) < bd:
			bd = float(rn[0])
			best = [ri, float(rn[1])]
	return best

## The vertices either side of s on road ri: [[vertex, samples to it, dir]].
func _sides(ri: int, s: float) -> Array:
	var r: Dictionary = island.roads[ri]
	var n := float((r["pts"] as PackedVector2Array).size())
	var list: Array = on_road[ri]
	var out := []
	if list.is_empty():
		return out
	var after = null
	var before = null
	for e in list:
		if float(e[0]) >= s and after == null:
			after = e
		if float(e[0]) <= s:
			before = e
	if r["closed"]:
		if after == null:
			after = list[0]
		if before == null:
			before = list[list.size() - 1]
		out.append([after[1], fposmod(float(after[0]) - s, n), 1])
		out.append([before[1], fposmod(s - float(before[0]), n), -1])
	else:
		if after != null:
			out.append([after[1], float(after[0]) - s, 1])
		if before != null:
			out.append([before[1], s - float(before[0]), -1])
	return out

## The way from a to b along the roads, as points (x, 0, z); empty if there's no way.
func find(a: Vector3, b: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if verts.is_empty():
		return out
	var ra := _nearest(Vector2(a.x, a.z))
	var rb := _nearest(Vector2(b.x, b.z))
	var ri_a: int = ra[0]
	var ri_b: int = rb[0]
	var s_a: float = ra[1]
	var s_b: float = rb[1]
	# the same stretch of road: straight along it
	var direct := INF
	var direct_dir := 1
	if ri_a == ri_b:
		var sa := _sides(ri_a, s_a)
		var sb := _sides(ri_b, s_b)
		var same := sa.size() == sb.size()
		if same:
			for i in sa.size():
				if sa[i][0] != sb[i][0]:
					same = false
		if same or sa.is_empty():
			var n := float((island.roads[ri_a]["pts"] as PackedVector2Array).size())
			direct = absf(s_b - s_a) * STEP
			direct_dir = 1 if s_b >= s_a else -1
			if island.roads[ri_a]["closed"] and absf(s_b - s_a) > n * 0.5:
				direct = (n - absf(s_b - s_a)) * STEP
				direct_dir = -direct_dir
	# Dijkstra from where you are
	var dist := {}
	var prev := {}
	var open := []
	for sd in _sides(ri_a, s_a):
		var v: int = sd[0]
		var d: float = float(sd[1]) * STEP
		if d < float(dist.get(v, INF)):
			dist[v] = d
			prev[v] = [-1, ri_a, s_a, float(island.roads[ri_a]["pts"].size()), int(sd[2])]
			open.append(v)
	var done := {}
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if float(dist[open[i]]) < float(dist[open[bi]]):
				bi = i
		var u: int = open[bi]
		open.remove_at(bi)
		if done.has(u):
			continue
		done[u] = true
		for e in adj[u]:
			var v2: int = e[0]
			var nd: float = float(dist[u]) + float(e[1])
			if nd < float(dist.get(v2, INF)):
				dist[v2] = nd
				prev[v2] = [u, e[2], e[3], e[4], e[5]]
				open.append(v2)
	# and the best way in to the target
	var best_v := -1
	var best_d := direct
	var best_side := []
	for sd in _sides(ri_b, s_b):
		var v3: int = sd[0]
		if dist.has(v3) and float(dist[v3]) + float(sd[1]) * STEP < best_d:
			best_d = float(dist[v3]) + float(sd[1]) * STEP
			best_v = v3
			best_side = sd
	if best_v < 0:
		if direct == INF:
			return out
		_walk(out, ri_a, s_a, s_b, direct_dir)
	else:
		# vertices from the start to best_v
		var chain := []
		var v4 := best_v
		while v4 >= 0:
			chain.push_front([v4, prev[v4]])
			v4 = int(prev[v4][0])
		# first stretch: from you to the first vertex, along your road
		var p0: Array = chain[0][1]
		var first_v: int = chain[0][0]
		for e in on_road[ri_a]:
			if int(e[1]) == first_v:
				_walk(out, ri_a, s_a, float(e[0]), int(p0[4]))
		for i in range(1, chain.size()):
			var pr: Array = chain[i][1]
			_walk(out, int(pr[1]), float(pr[2]), float(pr[3]), int(pr[4]))
		# last stretch: from the last vertex to the target, along its road
		for e in on_road[ri_b]:
			if int(e[1]) == best_v:
				_walk(out, ri_b, float(e[0]), s_b, -int(best_side[2]))
	out.append(Vector3(b.x, 0, b.z))
	return out

## Points along road ri from s0 to s1, going the way dir says (round the wrap on a closed road).
func _walk(out: PackedVector3Array, ri: int, s0: float, s1: float, dir: int) -> void:
	var pts: PackedVector2Array = island.roads[ri]["pts"]
	var n := pts.size()
	var closed: bool = island.roads[ri]["closed"]
	var count: int
	if closed:
		count = int(fposmod((s1 - s0) * dir, float(n)))
	else:
		count = int(absf(s1 - s0))
		dir = 1 if s1 >= s0 else -1
	var s := int(round(s0))
	for k in range(0, count + 1, 2):
		var i := posmod(s + k * dir, n) if closed else clampi(s + k * dir, 0, n - 1)
		var p := pts[i]
		out.append(Vector3(p.x, 0, p.y))
