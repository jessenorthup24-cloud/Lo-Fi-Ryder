# Lo-Fi Dryfter

An open-world drift game for Android, made in Godot 4.7. Drive a little car around an island town:
a dense city grid with traffic and people out walking, suburbs, a castle on its hill, forest passes,
farms, a working harbour and a beach front. Drift for points, bank them for coins, and spend the coins
on cars and upgrades. The day runs in real time on the island and the season follows your calendar.

## Getting the game

- **First install:** open **Releases → Latest** on your phone and install `lofi-ryder.apk`.
- **After that:** every push to `main` publishes an update. Open the game and it downloads the new
  version on the start screen. You only need a new APK when the Godot version changes or the app
  needs new Android permissions.

## How to play

- Landscape, third-person chase camera. The camera button cycles near, far and a close, low view. Drag a
  finger anywhere off the buttons to swing the view round the car (it settles back behind after a moment)
  and pinch to zoom (the zoom is kept).
- Street lamps hang out over the road and throw a warm pool of light on it after dusk.
- The car is drawn smoothly between physics steps (physics interpolation, with the physics jitter fix
  off as Godot needs), so it stays sharp on 90/120 Hz screens. From about 70 km/h the surroundings blur
  outward from the road ahead and light streaks rush past the edges; an oval round your car is kept
  sharp. Settings → Speed blur turns it off.
- Knock things over: hit a tree, a street lamp, a signpost or a traffic light at more than about
  16 km/h and it falls over the way you were going (you lose some speed and take a little damage);
  slower than that it just stops you. They're back about 40 s later once you're well away.
- Controls: steer left and right on the left; brake, gas and the handbrake (DRIFT) on the right.
  Hold brake when stopped to reverse.
- Handling: normally the car grips like a race car (planted rear, traction control, a stability system
  that catches a slide), so you can carry speed through corners. Drifting only happens when you ask
  for it with the handbrake, and the car goes back to gripping once you've straightened up.
- Drifting: at speed, tap the handbrake (DRIFT) while steering to kick the rear out, then hold the gas
  and keep steering into the turn to hold the angle. Steer the other way with the gas down to swing
  into a drift the other way. Let go of steering, or ease off the gas, to straighten up. Drift assist
  (Settings) helps hold the angle.
- Points build with angle and speed. Keep drifting to raise the combo (up to x10); chain drifts within
  a moment of each other to keep it going. A drift banks once you're straight again, and every 120
  points of a banked drift is a coin. Drifting within a metre or so of a wall, a parked car or the
  traffic scores half as much again. Hitting something hard loses the drift you were holding.
- Challenges, marked on the map and on the road:
  - Drift zones (orange rings): score as much as you can inside the zone before the clock runs out.
    The Drift Bowl, the town square, the harbour lot, the farmyard, the beach car park, the skate
    park and the Stunt Yard (where jumps, flips and the loop count too).
  - Time trials (blue): race through the gates. Drift runs (purple): drift through every gate.
  - Street races (red ring): roll into the ring gently (or tap Race on the map) and you're lined up on
    a grid with seven CPU drivers for three laps of the Downtown Loop; the streets are closed to
    traffic while it's on. A racing line is painted on the road like Forza's (blue: on the power,
    amber: the corner, red: brake now), checkpoint arches stand across it, the course is drawn on the
    minimap and the arrow up top points the way with the distance to the next checkpoint. Gold for 1st,
    silver 2nd, bronze 3rd. Lost or upside down: reset puts you back at the last checkpoint.
  - Each has bronze, silver and gold medals that pay out once.
  - Hidden coins are tucked around the island (a few hang in the Stunt Yard's air), and finding all 13
    places counts toward trophies.
- Stunts, GTA style. In the air, GAS tips the nose down and BRAKE pulls it up (hold to flip); steering
  spins the car round, and DRIFT + steering barrel-rolls it. Let go and it eases its spin and levels
  out for the landing. A button you were already holding as you left the ground doesn't count until
  you press it again, so ordinary jumps with your foot down don't nose-dive. Flips, barrel rolls,
  180s, air time and distance all score when you land on your wheels, half as much again for a clean
  landing; land on the roof and it's lost. Stunts take the drift combo and keep it going.
- The Stunt Yard, on the meadow south of town (Stunt Lane, off South Street): in under the gate and
  over a boost pad into a corkscrew loop; Big Air on the south side (boost, kicker, a gold hoop to fly
  through); two half-pipes end to end; a raised platform run with a jump across the gap; a container
  jump, cones and a tunnel. Crash in there and you're put back at the start of the nearest run.
- The garage: 18 cars (each with its own power, top speed, grip and drift), plus four upgrades that
  work on every car you own (engine, turbo, tyres, steering angle).
- 35 trophies, each paying coins once.
- The drift meter is a slim readout in the top left, with call-outs ("Close!", stunts) stacked beside it,
  so the middle of the screen stays clear.
- If you flip, land in the water or get stuck, the car is put back on the road.
- Fuel and condition: two gauges by the speedo. Fuel burns with the throttle (a tank lasts about 20 minutes
  of driving); below 15% the GPS takes you to the nearest gas station, and an empty tank leaves a quarter
  of the power to limp there. Four gas stations (Castle Road, Coast Road, Beach Road, Main Street East):
  stop on the pad by the pumps and buy fuel (1 coin a percent) and repairs (2 coins a percent; dents and
  scuffs go, and the lamps light again). Run out with no coins and they give you enough to get going.
- The GPS: during a trial it points to the next gate, out of a zone back into it, and when you're low on
  fuel or battered to a station. On the map, every challenge and gas station has a Route button. The route
  shows on the minimap and an arrow at the top of the screen points along it, with the distance.
- Paint jobs: every car comes in the pack's other liveries too (Garage, Paint tab; 250 coins each, kept
  per car).
- Crashes: hit a traffic car and it gets shoved and spun by the knock (you share it by weight), then the
  driver straightens up and carries on, dents and all. Your own car dents where it hits, smokes once
  it's battered and pulls a little less. The gas station on Castle Road (and the garage) fix it up.

## The world

- 1.2 km square island, built when the game starts (`scripts/game/island.gd` is the land, roads and
  helpers; `scripts/game/districts.gd` decides what goes where).
- The city is a grid of named avenues and streets. Every block is filled in neat rows of buildings
  sized to fit, with shops along Main Street, tall towers downtown, and gardens or car parks in the
  middle of each block. Nothing is scattered at random inside town.
- Roads meet at proper junctions: pavements stop at the kerb and pick up across a zebra crossing, side
  roads have stop lines, and every junction sits level. Nothing solid stands in a road or in the middle
  of a pavement (lamps at the kerb, people by the shop fronts).
- Traffic drives on the right and follows smooth curves through junctions. Side roads give way to the
  main road, equal streets take turns, left turns wait for oncoming cars, and Main Street's crossroads
  run on traffic lights (timed as a green wave). Cars keep their distance, never stop in a junction,
  stop for you and U-turn at dead ends. People walk the pavements (they don't wander into the road),
  sit on benches, watch you drift and wave.
- Seasons: autumn colours from September, snow and decorations in winter, blossom in spring. Windows
  and lamps light up after dusk.
- Farm fields are ploughed in ridges with crops growing along them (wheat, cabbages, corn, sunflowers,
  potatoes), coloured with the seasons. Dirt tracks stop at the edge of the paved roads they join, and a
  field stops at any road that runs through it (a corner cut off by a road is left as plain verge).

## Project layout

| Path | What |
| --- | --- |
| `boot/` | The over-the-air updater (first scene). Keep it small: the copy inside an installed APK can't update itself. |
| `scenes/main.tscn`, `scripts/main.gd` | Game states, input, camera, drift scoring, challenges, saving |
| `scripts/game/island.gd` | Heightfield, roads (splines cut into the land), the junction network, road markings, lots, colliders, merged static meshes, minimap layer |
| `scripts/game/districts.gd` | The island plan: districts, blocks, places, challenges and everything placed in them |
| `scripts/game/drift_car.gd` | Car physics: raycast wheels, tyre model, gearbox, handbrake and drift assist |
| `scripts/game/traffic.gd` | Traffic: lanes, junction turns and right of way, traffic lights |
| `scripts/game/people.gd` | People: stand, sit, walk, watch, wave and hop aside |
| `scripts/game/atmos.gd` | Day and night, seasons, sky and sun |
| `scripts/game/achievements.gd`, `save.gd`, `cars.gd` | Trophies, save data, the car list |
| `scripts/core/` | Palette (season colours), mesh builder, model loading and scales |
| `scripts/ui/` | All screens (built in code), icons drawn in code |
| `shaders/` | Toon shader with the season palette, sea, wipe |
| `tools/kenney/bake_kenney.gd` | Bakes the chosen Kenney kit models into `assets/kenney/` (people posed, arms loose) |
| `tools/kenney/bake_klyo.gd` | Bakes the Klyo stunt kit models (and their simple collision meshes, `_col`) into `assets/kenney/k_klyo_*` |
| `tools/look/` | Look-dev: `island_look.gd` photographs parts of the island, `kgrid.gd` makes a model contact sheet, `piece_look.gd` photographs one model from four sides on a 1 m grid |
| `tools/test/` | `handling.gd` (handling report), `road_audit.gd` (nothing in roads or pavements), `road_surface.gd` (roads meet the ground and each other), `road_net.gd` (junctions and loose ends), `traffic_soak.gd` (overlaps, jams, cars off the road), `collide_test.gd`, `probe.gd` |
| `tools/audio/`, `tools/music/` | Sound synthesis scripts (the fallback sounds); the CC0 music list the build fetches |
| `scripts/game/dents.gd` | Crash damage: bends a mesh in around an impact and scuffs the paint |
| `scripts/game/route.gd` | GPS: the road network as a graph and the shortest way along it |
| `scripts/game/race.gd` | Street races: the racing line (the streets' middle pulled tight within their width, with a speed for every metre), the CPU drivers (follow, pass, recover), checkpoints, laps and places |
| `tools/cars/export_paints.gd` | Bakes each car's other liveries as per-vertex colour rows (`assets/cars/*_paints.res`) |

There are no autoloads and no `class_name`s, so an update pack can replace any script before it loads.

## Testing without a phone

```
godot --path . -- --auto                         # autopilot drives the roads
godot --path . -- --drive --at=harbour --hour=21 # start at a zone, trial, place name or x,z[,yaw]
godot --path . -- --garage=up --fresh            # garage on the Upgrades tab, fresh save
godot --path . -- --drive --put=-108,284,90 --stunt=backflip   # exactly here (x,z,yaw), gas on, a trick in the air
godot --path . -- --drive --season=3             # 0 spring, 1 summer, 2 autumn, 3 winter
godot --path . -- --drive --race=downtown --raceauto --racelog   # straight into a race, CPU drives you too
godot --path . -- --drive --race=downtown --topcam=-170,120,190  # ...watched from straight above
xvfb-run godot --path . -- --drive --shot=/tmp/x.png --shot_at=200 --quit_after=30
godot --headless --path . -s res://tools/test/handling.gd -- bug,hotrod all   # handling report
godot --headless --path . -s res://tools/test/road_audit.gd                  # props in the road
godot --headless --path . -s res://tools/test/traffic_soak.gd -- 300         # five minutes of traffic
```

## Later: Play Store and ads

- The CI builds a **debug** APK signed with `tools/android/debug.keystore` (so updates install over each
  other). A Play Store build needs a real release key kept in a GitHub secret, never in the repo.
- `scripts/game/ads.gd` is the hook for rewarded ads. It does nothing today. Ads need an AdMob plugin
  and the Gradle Android build.

## Credits

The car sounds (engines, tyres, crashes, horns) are from heyheythere's Vehicle SFX pack
(heyheythere.itch.io). Its licence lets the game use them but not share the files, so the repo keeps them
encrypted (`assets/audio/pack.tar.enc`) and the build unlocks them with the `SFX_KEY` secret; without it
the game falls back to its own synthesized sounds (`tools/audio/`). The buildings, people, pets, vehicles,
ships and props are from Kenney's CC0 kits (kenney.nl: City Kit
Suburban and Commercial, Modular Buildings, Retro Urban Kit, Car Kit, Mini Characters, Cube Pets,
Mini Skate, Survival Kit, Mini Forest, Castle Kit, Holiday Kit, Mini Arena, Pirate Kit). The player cars
are the Tiny Car Pack. The Stunt Yard's ramps, platforms, half-pipes, gap jump, boost pads, gate, hoop,
tunnel and yard props are "Stunt arena 3D models: ramps, hoop, barriers (GLB)" and "Stunt arena 3D
expansion: loop, half-pipe, tunnel, obstacles" by Klyo Games (https://games.klyo.pl/free-game-assets/),
licensed CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/); they're baked to the game's
flat-colour style, and the loop is built in code to match (the kit's loop is a closed ring a car can't
drive into). Terrain, roads and the remaining props are made in code. Music: CC0 lo-fi hip hop
by HoliznaCC0 and omfgdude from OpenGameArt (see `tools/music/sources.json`; the tracks actually used
are listed in `tracks.json` on the `music` branch). The font is Fredoka (SIL Open Font License,
`assets/fonts/LICENSE_Fredoka.txt`).
