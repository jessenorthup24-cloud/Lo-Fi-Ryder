# A Meshy (AI-generated) car into the game

The Deplorable came from Meshy: one low-poly mesh (about 3,000 triangles), its looks in a 4K texture, the
wheels part of the body. These get it into the shape `tools/cars/bake_glb_car.gd` wants (front along -X,
wheels as their own `Wheel_*` nodes, lamps as glowing parts):

1. `fit_wheels.py car.glb FRONT_X REAR_X > /tmp/dp/wheels.json`: the wheel centres and radius.
2. `build_glb.py` (reads /tmp/dp/dp.glb and wheels.json, writes /tmp/dp/dp_clean.glb): the mesh split finer
   (finest round the wheels, so they cut out round), the texture sampled into vertex colours, the wheels cut
   out, and lamp lenses added as their own glowing tiles set onto the surface (the texture's lamps are too
   small for vertex colours): white headlights, amber indicators, red taillights. The lamp spots are measured
   off front and rear views of the model, so a new car needs its own.
3. `VCOL=1 SMOOTH=50 GLB=/tmp/dp/dp_clean.glb KEY=deplorable LEN=4.4 NOTEX=1 ONE_SIDED=1 KEEP=1 KEEP_WHEEL=1 godot --headless --path . -s tools/cars/bake_glb_car.gd`

Needs `pip install trimesh rtree`. Don't decimate a high-poly Meshy model down to size: it comes out lumpy and
blotchy. Ask Meshy for a low-poly one instead. The source GLB (14 MB) isn't kept in the repo.
