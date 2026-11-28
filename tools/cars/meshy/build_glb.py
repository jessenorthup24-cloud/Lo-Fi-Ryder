## The Deplorable (a Meshy model: one low-poly mesh, its looks in a texture) into the shape bake_glb_car.gd
## wants: the texture sampled into vertex colours (the mesh split finer for it, finest round the wheels so they
## cut out round), the wheels as their own nodes, the lamps as glowing parts.
import trimesh, numpy as np, json
from trimesh.visual.material import PBRMaterial
from PIL import Image

m = trimesh.load('/tmp/dp/dp.glb', force='mesh', process=False)
V = np.asarray(m.vertices, dtype=np.float64); F = np.asarray(m.faces); uv = np.asarray(m.visual.uv, dtype=np.float64)
W = json.load(open('/tmp/dp/wheels.json'))

def near_wheel(cen):
    out = np.zeros(len(cen), bool)
    for w in W.values():
        fz = 1 if w['zo'] > 0 else -1
        d = np.hypot(cen[:, 0] - w['x'], cen[:, 1] - w['y'])
        out |= (d < w['r'] * 1.35) & (cen[:, 2] * fz > 0.2)
    return out

for it in range(12):
    e = np.linalg.norm(V[F[:, [1, 2, 0]]] - V[F], axis=2).max(1)
    lim = np.where(near_wheel(V[F].mean(1)), 0.028, 0.09)
    big = np.where(e > lim)[0]
    if len(big) == 0: break
    V, F, attr = trimesh.remesh.subdivide(V, F, face_index=big, vertex_attributes={'uv': uv})
    uv = attr['uv']
print('faces', len(F))

tex = m.visual.material.baseColorTexture.convert('RGB').resize((1024, 1024), Image.LANCZOS)
A = np.asarray(tex).astype(np.float64) / 255
px = np.clip((uv[:, 0] % 1) * 1023, 0, 1023).astype(int); py = np.clip((1 - uv[:, 1] % 1) * 1023, 0, 1023).astype(int)
C = A[py, px]
# soften the brush strokes a little: each colour eased toward its neighbours' (same place, same seam side)
key = np.round(V * 1e4).astype(np.int64); _, inv = np.unique(key, axis=0, return_inverse=True); inv = inv.ravel()
edges = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
for _ in range(2):
    acc = C.copy(); n = np.ones(len(C))
    for a, b in ((edges[:, 0], edges[:, 1]), (edges[:, 1], edges[:, 0])):
        np.add.at(acc, a, C[b]); np.add.at(n, a, 1)
    C = 0.5 * C + 0.5 * acc / n[:, None]

# ground at y = 0, centred
off = np.array([-(V[:, 0].min() + V[:, 0].max()) / 2, -V[:, 1].min(), -(V[:, 2].min() + V[:, 2].max()) / 2])
V = V + off
for w in W.values():
    w['x'] += off[0]; w['y'] += off[1]
cen = V[F].mean(1); fc = C[F].mean(1)
lum = fc.mean(1); sat = fc.max(1) - fc.min(1)
xmin, xmax = V[:, 0].min(), V[:, 0].max()

owner = np.full(len(F), '', dtype=object)
for k, w in W.items():
    fz = 1 if k.endswith('L') else -1
    d = np.hypot(cen[:, 0] - w['x'], cen[:, 1] - w['y'])
    msk = (d < w['r'] * 0.99) & (cen[:, 2] * fz > 0.27)
    owner[msk] = k
    print(k, msk.sum())
free = owner == ''
r, g, b = fc[:, 0], fc[:, 1], fc[:, 2]
head = free & (cen[:, 0] < xmin + 0.12) & (lum > 0.62) & (sat < 0.25)
amber = free & (cen[:, 0] < xmin + 0.2) & (r > 0.6) & (r - b > 0.3) & (g > 0.35)
tail = free & (cen[:, 0] > xmax - 0.14) & ((lum > 0.45) & (r - b > 0.15) | (r > 0.5) & (r > g * 1.6))
side_red = free & (cen[:, 0] > 0.3) & (r > 0.5) & (r > g * 1.8)
tail |= side_red
print('lamps: head', head.sum(), 'amber', amber.sum(), 'tail', tail.sum())

def sub(faces, shift=np.zeros(3)):
    used, iv = np.unique(F[faces].ravel(), return_inverse=True)
    return V[used] - shift, iv.reshape(-1, 3), C[used]

def part(faces, name, col, node, parent, shift=np.zeros(3), vcol=True):
    v, t, c = sub(faces, shift)
    mm = trimesh.Trimesh(v, t, process=False)
    mm.visual = trimesh.visual.TextureVisuals(material=PBRMaterial(name=name, baseColorFactor=list(col) + [1.0], metallicFactor=0.0, roughnessFactor=0.6))
    if vcol:
        mm.visual = trimesh.visual.ColorVisuals(mm, vertex_colors=(np.c_[c, np.ones(len(c))] * 255).astype(np.uint8))
    sc.add_geometry(mm, node_name=node, geom_name=node, parent_node_name=parent)

# the lamps: lenses of their own (the texture's lamps are too small for vertex colours to show), set onto
# the surface where a ray from in front (or behind) meets it, a small tile at a time so they follow its slope
bodymesh = trimesh.Trimesh(V, F[free], process=False)
def lenses(zs, ys, front, step=0.018):
    tiles = []
    for side in (1, -1):
        for z in np.arange(zs[0], zs[1] + 1e-6, step):
            for y in np.arange(ys[0], ys[1] + 1e-6, step * 0.8):
                o = np.array([[xmin - 1.0 if front else xmax + 1.0, y, z * side]])
                dvec = np.array([[1.0 if front else -1.0, 0, 0]])
                loc, ri, fi = bodymesh.ray.intersects_location(o, dvec, multiple_hits=False)
                if len(loc) == 0: continue
                n = bodymesh.face_normals[fi[0]]
                if n[0] * (-1 if front else 1) < 0: n = -n
                b = trimesh.creation.box(extents=[0.012, step * 0.8 * 1.02, step * 1.02])
                R = trimesh.geometry.align_vectors([1, 0, 0], n)
                b.apply_transform(R); b.apply_translation(loc[0] + n * 0.003)
                tiles.append(b)
    return trimesh.util.concatenate(tiles) if tiles else None
def glow_part(mesh, name, col, node):
    if mesh is None: print('no', node); return
    mesh.visual = trimesh.visual.TextureVisuals(material=PBRMaterial(name=name, baseColorFactor=list(col) + [1.0], metallicFactor=0.0, roughnessFactor=0.6))
    sc.add_geometry(mesh, node_name=node, geom_name=node, parent_node_name='Body')
    print(node, len(mesh.faces) // 12, 'tiles')

sc = trimesh.Scene()
sc.graph.update(frame_to='Body', frame_from=sc.graph.base_frame, matrix=np.eye(4))
part(np.where(free & ~side_red)[0], 'paint', [1, 1, 1], 'body', 'Body')
part(np.where(side_red)[0], 'red', [1.0, 0.1, 0.06], 'side_markers', 'Body', vcol=False)
glow_part(lenses((0.165, 0.325), (0.228, 0.272), True), 'light', [0.97, 0.97, 1.0], 'headlights')
glow_part(lenses((0.2, 0.28), (0.172, 0.188), True, step=0.016), 'Warm headlight lens', [1.0, 0.62, 0.12], 'indicators')
glow_part(lenses((0.16, 0.31), (0.284, 0.316), False), 'red', [1.0, 0.1, 0.06], 'taillights')
for k, w in W.items():
    node = 'Wheel_' + k
    ctr = np.array([w['x'], w['y'], cen[owner == k][:, 2].mean()])
    M = np.eye(4); M[:3, 3] = ctr
    sc.graph.update(frame_to=node, frame_from=sc.graph.base_frame, matrix=M)
    part(np.where(owner == k)[0], 'wheel', [1, 1, 1], node + '_mesh', node, shift=ctr)
sc.export('/tmp/dp/dp_clean.glb')
print('ok')
