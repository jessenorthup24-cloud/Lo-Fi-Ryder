# A one-piece car mesh's wheels: rough centres given (FRONT_X, REAR_X, read off a side view), each fitted as a
# circle to the dark tyre ring on the wheel's outer face; the radius is centre to ground. Writes wheels.json.
#   python3 fit_wheels.py /tmp/dp/dp.glb -0.506 0.56 > /tmp/dp/wheels.json
import sys, json, numpy as np, trimesh
from PIL import Image
m = trimesh.load(sys.argv[1], force='mesh', process=False)
P = np.asarray(m.vertices); uv = np.asarray(m.visual.uv)
A = np.asarray(m.visual.material.baseColorTexture.convert('RGB').resize((1024, 1024))).astype(float) / 255
C = A[np.clip((1 - uv[:, 1] % 1) * 1023, 0, 1023).astype(int), np.clip((uv[:, 0] % 1) * 1023, 0, 1023).astype(int)]
lum = C.mean(1); ymin = P[:, 1].min(); out = {}
for name, x0 in (('Front', float(sys.argv[2])), ('Rear', float(sys.argv[3]))):
    for fz, side in ((1, 'L'), (-1, 'R')):
        dd = np.hypot(P[:, 0] - x0, P[:, 1] - ymin - 0.15)
        Q = P[(P[:, 2] * fz > 0.30) & (dd > 0.09) & (dd < 0.2) & (lum < 0.2)]
        zo = np.percentile(Q[:, 2] * fz, 95); Q = Q[Q[:, 2] * fz > zo - 0.05]
        a = np.c_[2 * Q[:, 0], 2 * Q[:, 1], np.ones(len(Q))]
        cx, cy, _ = np.linalg.lstsq(a, (Q[:, :2] ** 2).sum(1), rcond=None)[0]
        out[name + '_' + side] = dict(x=float(cx), y=float(cy), r=float(cy - ymin), zo=float(zo * fz))
print(json.dumps(out))
