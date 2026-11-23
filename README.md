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

- Landscape, third-person chase camera (tap the camera button for near or far).
- Controls: steer left and right on the left; brake, gas and the handbrake (DRIFT) on the right.
  Hold brake when stopped to reverse.
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
    The Drift Bowl, the town square, the harbour lot, the farmyard, the beach car park and the skate
    park.
  - Time trials (blue): race through the gates. Drift runs (purple): drift through every gate.
  - Each has bronze, silver and gold medals that pay out once.
  - Hidden coins are tucked around the island, and finding all 12 places counts toward trophies.
- The garage: 18 cars (each with its own power, top speed, grip and drift), plus four upgrades that
  work on every car you own (engine, turbo, tyres, steering angle).
- 29 trophies, each paying coins once.
- If you flip, land in the water or get stuck, the car is put back on the road.

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
| `tools/look/` | Look-dev: `island_look.gd` photographs parts of the island, `kgrid.gd` makes a model contact sheet |
| `tools/test/` | `handling.gd` (handling report), `road_audit.gd` (nothing in roads or pavements), `road_surface.gd` (roads meet the ground and each other), `road_net.gd` (junctions and loose ends), `traffic_soak.gd` (overlaps, jams, cars off the road), `collide_test.gd`, `probe.gd` |
| `tools/audio/`, `tools/music/` | Sound synthesis scripts; the CC0 music list the build fetches |

There are no autoloads and no `class_name`s, so an update pack can replace any script before it loads.

## Testing without a phone

```
godot --path . -- --auto                         # autopilot drives the roads
godot --path . -- --drive --at=harbour --hour=21 # start at a zone, trial, place name or x,z[,yaw]
godot --path . -- --garage=up --fresh            # garage on the Upgrades tab, fresh save
godot --path . -- --drive --season=3             # 0 spring, 1 summer, 2 autumn, 3 winter
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

The buildings, people, pets, vehicles, ships and props are from Kenney's CC0 kits (kenney.nl: City Kit
Suburban and Commercial, Modular Buildings, Retro Urban Kit, Car Kit, Mini Characters, Cube Pets,
Mini Skate, Survival Kit, Mini Forest, Castle Kit, Holiday Kit, Mini Arena, Pirate Kit). The player cars
are the Tiny Car Pack. Terrain, roads and the remaining props are made in code. Music: CC0 lo-fi hip hop
by HoliznaCC0 and omfgdude from OpenGameArt (see `tools/music/sources.json`; the tracks actually used
are listed in `tracks.json` on the `music` branch). The font is Fredoka (SIL Open Font License,
`assets/fonts/LICENSE_Fredoka.txt`).
