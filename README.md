# Lo-Fi Ryder

A cozy endless drive for Android, made in Godot 4.7. Steer a little toy car across floating diorama
islands that crumble away behind you, while the days, seasons and weather roll by and lo-fi music plays.

## Getting the game

- **First install:** open **Releases → Latest** on your phone and install `lofi-ryder.apk`.
- **After that:** every push to `main` publishes an update. Open the game and it downloads the new
  version on the start screen. You only need a new APK when the Godot version changes or the app
  needs new Android permissions.

## How to play

- Hold anywhere and slide your thumb left or right to steer. The farther you slide, the harder you turn
  (and the more you drift).
- In the air, slide to spin the car. Land straight for a clean landing bonus.
- The run ends if you drive off an edge, land in the water, or run out of fuel. Grab red cans and drive
  through gas stations to refuel.
- Score = distance + style (drifts, near misses, air, spins, clean landings) + 5 per coin.
- Coins buy cars and upgrades in the Garage. Missions pay out extra coins. The Daily run gives everyone
  the same road for the day, and your best daily attempt comes back as a ghost.

## Project layout

| Path | What |
| --- | --- |
| `boot/` | The over-the-air updater (first scene). Keep it small: the copy inside an installed APK can't update itself. |
| `scenes/main.tscn`, `scripts/main.gd` | Game states, input, camera, scoring, fuel, missions, ghost |
| `scripts/game/world.gd` | Terrain generation, crumbling, props, pickups, ground queries |
| `scripts/game/car.gd` | Car physics and toy-like body animation |
| `scripts/game/atmos.gd` | Day/night, seasons, weather, sky and the far parallax layer |
| `scripts/core/` | Palette (season colors), mesh builder, every model built in code |
| `scripts/ui/` | All screens (built in code), icons drawn in code |
| `shaders/` | Toon shader with the season palette, sky, ghost, outline, wipe |
| `tools/audio/make_audio.py` | Synthesizes all music and sound effects (`python3 tools/audio/make_audio.py`) |
| `tools/look/` | Icon renderer and look-dev scripts |

There are no autoloads and no `class_name`s, so an update pack can replace any script before it loads.

## Testing without a phone

```
godot --path . -- --auto              # autopilot drives
godot --path . -- --run --hour=22 --weather=rain --biome=seaside --season=2
godot --path . -- --garage --coins=5000
xvfb-run godot --path . -- --auto --shot=/tmp/x.png --frames=200   # screenshot, then quit
```

## Later: Play Store and ads

- The CI builds a **debug** APK signed with `tools/android/debug.keystore` (so updates install over each
  other). A Play Store build needs a real release key kept in a GitHub secret, never in the repo.
- `scripts/game/ads.gd` is the hook for rewarded ads (e.g. "watch an ad to keep driving"). It does
  nothing today. Ads need an AdMob plugin and the Gradle Android build.

## Credits

Everything is made in code for this game, including models, music and sound effects. The font is
Fredoka (SIL Open Font License, `assets/fonts/LICENSE_Fredoka.txt`).
