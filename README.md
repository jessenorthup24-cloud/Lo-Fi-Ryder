# Lo-Fi Ryder

A cozy endless drive for Android, made in Godot 4.7. Steer a little toy car across floating diorama
islands that crumble away behind you, while the days, seasons and weather roll by and lo-fi music plays.

## Getting the game

- **First install:** open **Releases → Latest** on your phone and install `lofi-ryder.apk`.
- **After that:** every push to `main` publishes an update. Open the game and it downloads the new
  version on the start screen. You only need a new APK when the Godot version changes or the app
  needs new Android permissions.

## How to play

- Hold the left or right arrow to steer (anywhere on that half of the screen counts). A quick tap is a
  gentle turn; holding winds up to full lock and throws the tail out into a drift. Let go of a long
  drift for a little speed kick.
- The run keeps speeding up the farther you get (about 32 km/h at the start, ~50 km/h by 900 m).
- Bumping rocks and walls glances you along them; if you ever get wedged, the car hops back to the road.
- A cute toy world floating over a pastel galaxy whose nebula colours change with each region, with
  motes, petals and fireflies drifting by. The cars are the Tiny Car Pack (baked into assets/cars by
  tools/cars/export_cars.gd from the pack's FBX, which stays outside the repo).
- Handling: the car has some weight: steering eases in and out, tyres grip up to a limit and then
  slide (hold an arrow to step the rear out), the body rolls and squats, and it gets light over crests
  and drops instead of sticking to the ground.
- Challenge pieces span long drops: plank bridges on stilts, and twisty toy race tracks with candy
  kerbs and little hills. They crumble away behind you, piece by piece.
- Offroad sections are real uneven terrain: rolling dirt tracks, and red rock canyons you crawl through
  (slower on the climbs, the car pitches and rolls and each wheel finds the ground).
- Gauntlets chain it all: a kicker onto a grind rail (you lock on automatically), down onto a plank
  bridge, over rough ground and through a red rock canyon.
- Police cruisers are sloppy drivers: they weave and run wide, and often go over the edge on bridges.
- In the air, hold an arrow to spin the car. Land straight for a clean landing bonus.
- The run ends if you drive off an edge, land in the water, or run out of fuel. Grab red cans and drive
  through gas stations to refuel.
- Police chases: drive past a parked cruiser and it gives chase along your exact path. Hit the glowing
  boost pads to stay ahead for the stretch shown on screen. Get away for +40 coins; get caught and you
  lose 30% of your fuel.
- The road runs past little places (farms, villages, ponds, orchards, beaches, piers, cafés, campsites,
  mountains, cabins, sky ruins, balloon ports, cloud gardens) with toy people who wave as you pass and
  cheer your stunts. They always hop out of the way.
- Score = distance + style (drifts, near misses, air, spins, clean landings) + 5 per coin.
- Coins buy cars and upgrades in the Garage. Missions pay out extra coins. The Daily run gives everyone
  the same road for the day, and your best daily attempt comes back as a ghost.
- Trophies: 36 achievements (distance, speed, drifts, stunts, bridges, chases, regions, garage) that
  each pay coins once. They unlock live during a run.

## Project layout

| Path | What |
| --- | --- |
| `boot/` | The over-the-air updater (first scene). Keep it small: the copy inside an installed APK can't update itself. |
| `scenes/main.tscn`, `scripts/main.gd` | Game states, input, camera, scoring, fuel, missions, ghost |
| `scripts/game/world.gd` | Terrain generation, crumbling, props, pickups, ground queries |
| `scripts/game/car.gd` | Car physics and toy-like body animation |
| `scripts/game/police.gd` | The chase cruiser (follows your breadcrumb trail) |
| `scripts/game/achievements.gd` | Trophy list, lifetime stats, unlock checks |
| `scripts/game/people.gd` | Toy people: watch, wave, cheer, hop aside |
| `scripts/game/atmos.gd` | Day/night, seasons, weather, sky and the far parallax layer |
| `scripts/core/` | Palette (season colors), mesh builder, every model built in code |
| `scripts/ui/` | All screens (built in code), icons drawn in code |
| `shaders/` | Toon shader with the season palette, sky, ghost, outline, wipe |
| `tools/audio/make_audio.py` | Synthesizes the UI and pickup sound effects (`python3 tools/audio/make_audio.py sfx`) |
| `tools/audio/make_vehicle.py` | Synthesizes the vehicle sounds: 4-layer engines per family, tyres per surface, skids, siren |
| `tools/music/` | CC0 music list and the script the build uses to fetch, trim and encode it (cached on the `music` branch) |
| `tools/look/` | Icon renderer and look-dev scripts |

There are no autoloads and no `class_name`s, so an update pack can replace any script before it loads.

## Testing without a phone

```
godot --path . -- --auto              # autopilot drives
godot --path . -- --run --hour=22 --weather=rain --biome=seaside --season=2
godot --path . -- --garage --coins=5000
godot --path . -- --run --deck=plank --warp=deck   # jump onto a plank bridge (or --deck=track)
godot --path . -- --auto --biome=forest --hug=4.2  # autopilot grinds along the rim walls
godot --path . -- --auto --kind=gauntlet --warp=kind   # jump to a gauntlet (or --kind=rough / dirt)
xvfb-run godot --path . -- --auto --shot=/tmp/x.png --frames=200   # screenshot, then quit
```

## Later: Play Store and ads

- The CI builds a **debug** APK signed with `tools/android/debug.keystore` (so updates install over each
  other). A Play Store build needs a real release key kept in a GitHub secret, never in the repo.
- `scripts/game/ads.gd` is the hook for rewarded ads (e.g. "watch an ad to keep driving"). It does
  nothing today. Ads need an AdMob plugin and the Gradle Android build.

## Credits

Models and sound effects are made in code for this game. Music: CC0 lo-fi hip hop by HoliznaCC0 and
omfgdude from OpenGameArt (see `tools/music/sources.json`; the list of tracks actually used is
`tracks.json` on the `music` branch). The font is Fredoka (SIL Open Font License,
`assets/fonts/LICENSE_Fredoka.txt`).
