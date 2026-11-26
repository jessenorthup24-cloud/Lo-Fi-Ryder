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
- After dusk the street lamps nearest you really light things (road, pavements, walls, cars) with a warm
  soft falloff, and your headlights light the road ahead (point lights in the toon shader: 16 at a time,
  the furthest fading out so nothing pops). Bloom gives lit windows, lamps and neon a soft glow.
- A few things in the air round you: pollen on spring and summer days, leaves in autumn, snow in winter,
  fireflies at night. Settings → Bloom and Ambient particles turn them off (for slower phones).
- The car is drawn smoothly between physics steps (physics interpolation, with the physics jitter fix
  off as Godot needs), so it stays sharp on 90/120 Hz screens. From about 120 km/h (building to 240) the
  outer edges of the screen blur a little outward from the road ahead and faint streaks rush past; the
  middle (the road, the buildings beside it) stays sharp, an oval round your car is kept sharp, and the
  blur never samples the car itself (so no ghost of it smears across the background).
  The camera's aim is eased every frame, so on a 120 Hz screen the view never steps along with the 60 Hz
  physics. Settings → Speed blur turns it off; Settings → Cap at 60 fps holds the frame rate at 60 (smoother
  on phones that pace 120 Hz unevenly, and easier on the battery).
- Shadows hold still: the sun moves in small steps (a game minute, about every half second) rather than a
  little every frame, which made the shadow map re-sample every frame and the edges of building shadows
  shimmer; their edges are soft, so a step is a nudge rather than a jump. Enough shadow bias that nothing
  shadows itself (no speckled "acne" on a bonnet), the near and far shadow cascades blend into each other,
  shadows reach 110 m and fade out there, and with the sun (or moon) low they soften back rather than go
  patchy. The turn from lit to shade is soft over the first few degrees, so a car's flat panels don't flick
  between light and dark one facet at a time.
- Tuning (garage, Tune tab, per car): camber (0-10°) and ride height (slammed to lifted) change the look
  and the handling. More camber and lower: drifts more easily but less race grip and worse off-road.
  Less camber and higher: harder to drift, more grip, better on grass, dirt and sand. Bars show the
  trade-off as you go. Neon underglow (a one-off kit for all cars) in eight colours: real light in the
  toon shader (global shader values `neon_pos`, `neon_fwd`, `neon_col`), so it lies on whatever's under
  the car (road, kerb, grass, the sills) with nothing to clip into the ground; it fades as the car leaves
  the ground or tips over, brighter at night, with the tubes themselves only visible from underneath. Tyre smoke in nine colours (free, per car): it's
  the smoke your tyres make on tarmac (dirt, sand and grass still throw up their own dust). In
  the garage a swipe on the car turns it; the arrows change cars.
- Settings → Show FPS puts the frame rate and the slowest frame of the last second by the clock.
- Rewind: hold REWIND (by the camera button; Backspace or Z on a keyboard) to take back the last 10
  seconds. The picture goes blue and plays backwards at double speed; let go to carry on from there, at
  the speed you had then (fuel, nitrous, damage, the drift you were holding and any challenge clock go
  back too). In a street race the other racers and the race clock rewind with you. The traffic doesn't,
  so for a moment after a rewind it can't hit you. Not during a countdown, after the finish, or with the
  police after you.
- The police, GTA style. Patrol cars drive about in the traffic, and each sees in a cone ahead of it
  (and anything right beside it). Speed past one more than 15 km/h over the limit (a limit sign comes
  up by the speedo while one's about: 50 in town, 70 on the main roads, 80 on the ring road, 40 on
  lanes), hit one, or crash into someone in front of one, and the patrol car just pulls out after you
  (it's the same model as the cars that chase you). Ram one and it takes the hit like a police car, not
  a bit of traffic: it rocks, stays on its wheels and comes straight after you. Police cars are built
  heavy: shoved side-on they lean and right themselves rather than going over. No banners: wanted stars come up under the minimap
  with a crackle of police radio and a line saying what for, and the minimap's rim flashes red and blue.
  - The chase: each police car has its own siren (you hear it pass, the pitch dropping) and a flashing
    light bar. The traffic pulls over to the kerb for them. They follow you along the roads, some head
    you off where you're going, they weave round the traffic, sit on your tail and (from two stars) line
    up a PIT to spin you out, and when you stop they pen you in front and back.
  - They drive well: they keep to the way they've worked out (and work out a new one if they're knocked
    off it), pass the traffic when there's room and sit behind it when there isn't, and the ones heading you
    off go for where you'll be down the road you're on. New cars only ever turn up out of view, well away
    from the ones already after you, and a patrol car that pulls out after you leaves no copy of itself
    behind (patrol cars are always the patrol model, knocked about or not).
  - Getting worse: a star more every minute they've had you in sight, and for ramming or wrecking them.
    New cars come in out of sight. From three stars there are roadblocks (two cars parked across the road
    ahead of you, set up out of sight); from four a helicopter joins in, built in code, with a
    searchlight after dark. It watches a circle round you; hiding under the railway viaduct breaks its
    view, and a long flat-out run gets you out of its circle.
  - Losing them: their sight cones show on the minimap. Get out of all of them and stay out till the
    stars stop flashing (8 s at one star, up to 16 s at five), and the stars fade away with a bounty in
    coins. Stopped with one on your bumper for 3.5 s and you're busted: the picture slows and drains to
    grey, BUSTED across it, and a fine. Either way they switch off their lights and drive off.
  - No challenges, garage or fast travel while they're after you. Half the street races (never a race on
    a circuit) get a visit:
    they turn up some way in, go for the racers too (a racer they stop is out of the race) and the chase
    goes on after the finish line. Trophies for losing them once and ten times, and for five stars.
- The controls are illustrated stickers in the HUD's cream and ink (thick outlines, offset shadows): ghost
  chevrons to steer (when the wheel's off), a drilled aluminium sport gas pedal and a grooved brake pedal
  that tip back on their hinges, a handbrake lever in a stitched leather boot with a red button (pulled up
  while held), the nitrous bottle with its red valve, a gauge for what's left and an arming switch that
  flips up when it's on, and the cruise button with a little green LCD showing the speed it's holding.
- Cruise control: tap the dial (Q) to hold the speed you're doing; the gas takes you faster and that
  becomes the new speed; the brake or the handbrake switches it off.
- Nitrous: tap the NOS canister (N or E on a keyboard) to switch it on, again to switch it off (it goes off
  by itself when the bottle's empty), for a hard shove and a higher top speed, with blue
  flames, a wider view and more speed blur. The bottle refills slowly as you drive, quicker drifting or
  in the air. The Nitrous Tank upgrade makes it bigger (3 s up to 9 s).
- Knock things over: hit a tree, a street lamp, a signpost or a traffic light at more than about
  16 km/h and it falls over the way you were going (you lose some speed and take a little damage);
  slower than that it just stops you. They're back about 40 s later once you're well away.
- Controls: steer with the steering wheel at the bottom left (the top half of a wheel: put a thumb on it
  and turn it; it springs back when you let go; Settings → Steering wheel switches back to arrow
  buttons); brake, gas, NOS and the handbrake (DRIFT) on the right.
  Hold brake when stopped to reverse.
- Handling: normally the car grips like a race car (planted rear, traction control, a stability system
  that catches a slide), so you can carry speed through corners. Drifting only happens when you ask
  for it with the handbrake, and the car goes back to gripping once you've straightened up.
  Turn-in is Forza Horizon quick: grip-mode tyres bite early, the steering reaches full lock in about a
  tenth of a second at any speed, and a steering assist makes the car rotate as much as the wheel asks
  (half the wheel, half the grip; it's proportional at every speed) without the dart-then-settle of a
  bare car. The brakes stop a car from 100 km/h in 34 to 38 m. The touch wheel reaches full lock at
  about 77° of turn. The handling report (`tools/test/handling.gd`) measures it: step80/step120 time how
  quickly the car answers a step of steering (63% of its turn in 0.10 s, against 0.15 s before),
  lane80 how far it moves over in a quick lane change.
- Drifting, CarX style: pull the handbrake (DRIFT) with some steering to swing the tail out, then
  balance it. The gas holds it out (more gas, more angle) and carries your speed round a long arc;
  steering into the turn deepens the angle and tightens the arc, countersteering opens it out; the foot
  brake throws it deeper and sharpens the turn. Off the gas and the brake, it straightens up and grips
  again. Steer the other way with the gas down to swing into a drift the other way. The sweet spot is
  22-42°: the drift readout shows your angle on a little scale, green inside it, worth ×1.4.
- Points build with angle and speed. Keep drifting to raise the combo (up to x10); chain drifts within
  a moment of each other to keep it going. A drift banks once you're straight again, and every 120
  points of a banked drift is a coin. Drifting within a metre or so of a wall, a parked car or the
  traffic scores half as much again. Hitting something hard loses the drift you were holding.
- Challenges, marked on the map and on the road by a ring with a column of light. Drive into one and
  its card comes up (what it is, the target, your best and medal) with a START button; nothing starts
  by driving through. START lines you up, a title band slides across while the camera swings round the
  car, then 3-2-1-GO. Medals stamp onto the results card, with confetti for a podium, and a Try again
  button for another go from the start. The card warns you first if the engine's hurt or the tank's
  nearly empty. While one's on, the pause menu has Restart (or Restart race) and Stop challenge (Leave
  race).
  - Drift zones (orange rings): score as much as you can inside the zone before the clock runs out.
    The Drift Bowl, the town square, the harbour lot, the farmyard, the beach car park, the skate
    park and the Stunt Yard (where jumps, flips and the loop count too).
  - Time trials (blue): race through the gates. Drift runs (purple): drift through every gate.
  - Street races (red ring): press START in the ring (or tap Race on the map) and you're lined up on
    a grid with seven CPU drivers for three laps of the Downtown Loop; the streets are closed to
    traffic while it's on. A racing line is painted on the road like Forza's (blue: on the power,
    amber: the corner, red: brake now). It's a real racing line: out wide on the run-up to a corner, in
    to the inside edge at the apex and back out wide on the exit. The CPU drivers drive it, leave it only
    to pass on the straights, and tuck back in for the corners, checkpoint arches stand across it, the course is drawn on the
    minimap and the arrow up top points the way with the distance to the next checkpoint. Gold for 1st,
    silver 2nd, bronze 3rd. Lost or upside down: reset puts you back at the last checkpoint.
  - Eight races in all. Street races: the Downtown Loop (3 laps round the town blocks), Ring Road
    Classic (2 laps of the whole ring road, about 2.2 km a lap), the Northern Loop (2 laps: Main Street
    out east, then the ring road round the north) and the Beach Loop (3 laps: down Beach Road, along the
    south of the ring and back up Main Street). Circuit races, on their own tracks: the Raceway Grand
    Prix, Cliffside Circuit (on a headland off the west coast), Eastpoint Speedway (off the east coast,
    with a chicane) and Southshore Circuit (on the south shore, with a hairpin notch); each circuit has
    kerbs, barrier walls, a start gantry, grandstands, banner towers, a paddock and its own access road.
  - Difficulty: the race card has Easy, Medium and Hard chips (remembered between races). Easy is the
    old pace on stock cars. Medium: faster drivers that brake later and corner harder, in the quicker
    cars with upgrades. Hard: the quickest cars, well upgraded, driven close to the limit, and they
    don't wait for you. Bests and medals are kept per difficulty, and medals pay more (Medium 1.6×,
    Hard 2.4×).
  - CPU drivers ease off over crests (fast enough to keep the wheels on the road), back off and go
    round a post or wall they've nosed into, and are put back on the line if they're stuck or off.
  - Each has bronze, silver and gold medals that pay out once.
  - Hidden coins are tucked around the island (a few hang in the Stunt Yard's air), and finding all 17
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
- Bunny hops and grind rails, Mario Kart style. Tap DRIFT (a quick tap, under a quarter of a second)
  with the wheel straight and the car pops up about two thirds of a metre, nose kicked up, and comes
  down quick. Hop onto one of the yellow-and-black
  grind rails lined up with it and you lock on and slide along it with sparks flying, a little slower
  all the time, until you shoot off the end (or tap DRIFT again to hop off). A grind scores by how long
  and how fast, and keeps the combo going. There are 25 rails round the island, marked with yellow
  dashes on the minimap and a yellow-and-black pole at each end: in the Drift Bowl, the harbour lot,
  the skate park, the Courts' parking court and the Stunt Yard's run-up, down the middle of the
  bigger car parks and yards, and along the side of the straight streets, just past the pavement, so
  you can hop off the road onto one; kickers, low ramps and a boost pad
  from the stunt kit are dotted round the beach car park, the Bowl, the harbour lot and the farmyard.
  The drivers on the road don't hop.
- The garage: 20 cars (each with its own power, top speed, grip and drift), plus four upgrades that
  work on every car you own (engine, turbo, tyres, steering angle).
- The legendary Mountain Ghost ($20,000): a panda-coloured hatch, white over black, with pop-up lamps
  and a louvred back window. Light and high-revving: not the fastest in a straight line, but the
  tightest, quickest-switching drifter there is.
- The legendary Haywire ($20,000, last in the garage): a black widebody with gold fracture
  livery, the 00 roundel and taped-X headlamps. The quickest car in the game (0-100 in 4.8 s) and the
  slidiest: it holds drifts about 10 degrees deeper than anything else, and still doesn't spin.
- 46 trophies, each paying coins once (among them winning a race on Hard and winning every race,
  grinding rails, riding with your crew and owning a legendary car; the "every zone / trial / place /
  race" ones count however many there are on the island).
- The look is "lo-fi night": dark glass panels with a hairline edge, near-white type, one neon-pink
  accent (the main button on each screen glows with it). The title sits at dusk (the island's own clock
  carries on from where it was once you drive): a thin, letter-spaced LO-FI DRYFTER, one DRIVE button,
  and Garage, Map, Trophies and Settings as quiet text links, over a slow orbit of your car with a dark
  wash and letterbox bars. The garage is a night studio, a neon rim round the turntable. Toasts are
  dark pills, their colour on the icon. The in-car controls keep their illustrated sticker look.
- On foot: the EXIT button (above the handbrake, or F) gets you out when you're nearly stopped (not
  while the police are after you, or mid-challenge). You walk, run and jump about in third person: a
  stick on the left (WASD), JUMP and RUN on the right (Space, Shift), drag to swing the camera round. The
  traffic stops for you and for your parked car. ENTER (lit when you're by a car) gets you in.
- Take any car: walk up to one in the traffic (stopped or crawling) and ENTER: its driver jumps out and
  runs, and it's yours to drive (a truck's slow and heavy, a sports car quick). The car you were in stays
  parked where you left it, and you can go back to it. Take a police car, or take one with a patrol car
  looking on, and you're wanted.
- Car cards: fifty made-up cars (each a nod to a classic, with an enthusiast's blurb), Common to Legendary. You level up by playing (drifting,
  distance, races, escapes, heists, trophies, places found, hidden cash) and every level is a pack of three
  (the third at least Uncommon); a duplicate pays cash instead. From the title screen or the pause menu.
- The map is the island in 3D from above (drag, pinch); tap anywhere to drop a waypoint for the GPS. The
  phone pulls up over the screen; its Safe radar app pulses toward the nearest safe.
- Cash is the money (the green bill on the HUD: $). It buys everything in the garage. People and officers you
  take down drop a bundle or two (walk or drive over it); bundles of hidden cash are tucked about the island.
- Heists: 25 safes stand by the roads (grey dots on the map). Walk up to one and tap START HEIST (or H). An
  orange ring on the map shows roughly where a core drill's been stashed: find it (on foot, to pick it up)
  and bring it back inside 90 seconds, or someone tips off the police. Set it up on the safe and it cuts for
  two minutes: the alarm goes, every police car knows where you are (no busting: it's a shootout), and it
  only cuts while you're within 45 m. Then the door swings open: grab the duffle, lose the police, and take
  it to the safehouse (a green beam, west end of town) for $7,500 to $12,500. Die or get busted on the way
  and it's gone. A cracked safe's empty for 20 minutes.
- Guns, on foot: six kinds (pistol, revolver, SMG, shotgun, rifle, sniper), each with five looks, bought
  and picked in the garage's Guns tab (you start with a pistol; the first look's free). Every gun's held
  in both hands. Holding FIRE (or switching AIM on: the button left of the door, or B) puts you in aim:
  the camera comes in over your right shoulder and narrows, a reticle sits mid-screen, and it locks on to
  the person or officer nearest it (red brackets round them; the view drifts onto them); with nobody near,
  shots go wherever the reticle points. Hits show an X on the reticle (red, with a ding, for a kill), with
  blood, sparks and bullet holes; the gun kicks and the camera with it (a sharp kick for single shots, a
  small steady one for automatics). Holding FIRE with a pistol, revolver, shotgun or sniper keeps firing,
  a little slower than tapping. Everyone has 100 health: a pistol takes 4 to 6 hits, a rifle 3 or 4 (hits
  vary a little), a sniper round one. Hit people bleed and run; officers flinch. People drop as ragdolls,
  and officers (and you) go limp: a ragdoll of the rigged character itself (scripts/game/ragdoll_rig.gd).
  Taking hits, you bleed and flinch; out of health, you fall, the camera watches, then WASTED. Cars take
  about 15 rifle hits: they smoke, catch fire at about 11 (going up a few seconds later on their own) and blow
  up, knocking down people and officers near them, throwing other cars about (and setting them off) and
  leaving a burnt-out shell. RELOAD (under the swap pill, or X) lowers and tips the gun while the magazine
  swaps; an empty gun clicks and reloads itself. The swap pill (left of FIRE, or Tab) changes gun, and after your last one puts it away (FIRE or AIM draws it again). Drag the finger that's holding FIRE to steer your aim while you shoot. Long guns are shouldered, the body side-on. Shots fired
  bring the police; shooting people and officers brings more. When you're wanted and on foot, police
  cars that reach you stop and the officers get out and come at you with pistols. Your health's the red
  bar under the minimap (it comes back once you're out of a fight). Run out and you're WASTED: a
  hospital bill, the wanted level gone, back in your car.
- The guns are PIXEL ARSENAL models (a paid pack: they ship only inside the built game, fetched by the
  build from a private repo with the `ASSETS_TOKEN` secret, never committed here). Without them (a local
  checkout, or a build without the secret) each gun's a plain blocky stand-in. Gun sounds are made by the
  game (no samples).
- Your driver is one of 20 Kenney mini characters (garage, Driver tab), with glasses or shades if you like.
  They're rigged and animated (idle, walk, run, jump, fall), drawn in the game's toon style.
- The HUD: the phone, camera and rewind are one column of matching round buttons beside the minimap
  (the group view sits beside the phone while you've a crew); wanted stars are gold, under the minimap;
  the bars either side of the speedo are fuel and the car's condition (a spanner). Menus hide the
  driving controls behind them. "How to drive" is four short pages (Driving, Drifting, Tricks, Around
  town), shown on the first run and any time from the pause menu, which also has Call the crew.
- Southside Green: the open ground between the bottom of town and the beach road is a park, with paths
  up from each avenue's crossing to a promenade, lamps, benches, a statue on a little plaza, picnic
  tables, clumps of trees, and people and dogs about.
- Shadows: one shadow map out to 90 m (not two splits), and the town's props cast theirs from simplified
  copies of themselves; about a quarter less drawing in town, a third less at the harbour, and no visible
  difference. Roadsides are flat a full terrain cell past the edge (no grass poking over the tarmac on a
  steep hill), and a road's cuttings and embankments are grassed (rock only on real cliffs). Each batch
  of identical props (benches, parasols, people...) knows how far its copies spread, so the renderer
  skips a batch that's nowhere near the view: another 10-25% fewer draw calls. In winter the roads stay
  dark (ploughed and wet) so the lane lines read against the snow. The circuits' infields have trees, marshals' tents
  and flags, billboards and radar masts rather than bare lawn.
- The drift meter is a slim readout in the top left, with call-outs ("Close!", stunts) stacked beside it,
  so the middle of the screen stays clear.
- If you flip, land in the water or get stuck, the car is put back on the road.
- Fuel and condition: two gauges by the speedo. Fuel burns with the throttle (a tank lasts about 20 minutes
  of driving); below 15% the GPS takes you to the nearest gas station, and an empty tank leaves a quarter
  of the power to limp there. Four gas stations (Castle Road, Coast Road, Beach Road, Main Street East):
  stop on the pad by the pumps and buy fuel (1 coin a percent) and repairs (2 coins a percent; dents and
  scuffs go, and the lamps light again). Run out with no coins and they give you enough to get going.
- The GPS: during a trial it points to the next gate, out of a zone back into it, and when you're low on
  fuel, battered or with a hurt engine to a station. On the map (the whole island and the circuits off its
  coasts), every challenge and gas station has a Route button. The route
  shows on the minimap and an arrow at the top of the screen points along it, with the distance.
- Paint jobs: every car comes in the pack's other liveries too (Garage, Paint tab; 250 coins each, kept
  per car).
- Crashes: hit a traffic car and it gets shoved and spun by the knock (you share it by weight), then the
  driver straightens up and carries on, dents and all (hit one hard side-on and it rolls over). Your own
  car crumples where it hits (deeper the harder), with sparks, bits of bodywork and glass that bounce and
  skid along the road, a jolt of the camera and, on a big one, a pale flash and a beat of slow motion.
  It comes back from a save looking as battered as it was.
- Engine damage: knocks to the front hurt the engine most (small knocks don't touch it; a flat-out
  head-on takes about a fifth of it). A hurt engine pulls a little less (a wrecked one about 80%), and
  past two thirds it coughs now and then under throttle (a bang from the exhaust, a puff of black smoke, a
  moment's dip in power); it smokes from under the bonnet, white, then grey, then thick black with flames,
  and when it's gone you limp along at a bit over half the power. A hard knock on a front corner bends that wheel: it leans
  and wobbles and pulls the steering. Gas stations fix it all (the condition gauge shows the worse of the
  body and the engine).
- Rollovers: T-boned by a car at about 40 km/h or more (or slammed sideways into a wall at 60+) and the car
  goes over, rolling away from the hit, longer the harder (traffic cars too). Sliding on the roof throws
  sparks and dents it. Once it stops on its roof or side it's lifted and set back on its wheels where it
  lies. Nose first into something at 80+ kicks the back end up.
- Trading paint: rubbing along another car (traffic, racers, the police) costs you no speed; the knock
  itself shares the speed out by weight, as before. Scraping a wall still costs some, more the squarer on.

## The drivers

- Named street drivers roam the island in cars like yours (tuned up), quick but skilled: a pace for each
  kind of road (sensible in town, flat out on the ring road), easing off for junctions, braking for the bends, past the traffic when there's room (looking out for what's
  coming), and drifting corners, some much more than others (drifters, grip drivers, wild ones). Their
  names float over their cars and they're orange dots on the minimap.
- Drive up close to one and you swap numbers. The phone (the handset button under the coins, or T) lists
  your contacts: Call one and they come and find you (up to three at once). Your crew ride in formation on
  the road you're on: beside you in their own lane when there's room (the side with more road first), just
  behind you when there isn't or there's traffic in the way, following the road's curves at your speed, never
  passing off the road; round a junction, or off the roads, they follow the line you drove. They drift when you
  drift, park up round you when you stop, and catch up with a squirt of nitrous (left far behind and out of
  sight, they turn up behind you again). Send off from the phone lets them go. They're green on the minimap.
- Now and then a patrol car sees one of them fly past and goes after them (no stars for you): they run
  for it, and lose them or get busted. One of your crew they're after keeps driving with you.
- Group ride view: with a crew, a button by the phone (or G) pulls the camera back and up to keep you and
  your crew in the picture (centred between you, you counting double), easing back when they're gone.
- During a challenge or a race they're off the streets; your crew come back once it's over.

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
- Hit someone: at a crawl anyone steps aside, but going at a lick only the quick ones get clear. Hit, they
  go down as a ragdoll (the upper body and the legs jointed at the hips, the arms at the shoulders, about
  70 kg in all): swept off their feet, over the bonnet, tumbling and sliding to a stop, with a heavy thump,
  a spray of blood that spatters the road, a smear where they slide and a pool where they come to rest
  (and some on your bumper until a repair). People round about run off. In front of the police it's two
  stars; otherwise someone who saw it usually calls it in a few seconds later (one star); with them after
  you already, it adds to the heat. They're back on their feet a while later, once you're well away.
- Weather (`scripts/game/weather.gd`): clear, cloudy, rain, storms (wind, lightning, thunder) and fog, changing
  every few minutes and blending over half a minute; wetter in spring and autumn, misty mornings, snow
  instead of rain in winter. Cloud greys the sky and softens the sun and its shadows, fog and rain thicken
  the air, rain falls round you and you hear it, and wet roads go darker and every car grips a little less
  until they dry. The clock shows what it's doing. Settings → Weather off keeps it fine.
- Seasons: autumn colours from September, snow and decorations in winter, blossom in spring. Windows
  and lamps light up after dusk.
- North of downtown, off Castle Road, the rough side of town: Palmer Street, a cul-de-sac of little stucco
  duplexes and bungalows in faded pastels with fenced front yards, palms, cars pulled up on the kerb,
  people hanging out on the corner, a corner store, and a vacant lot with a burning barrel; Low Street;
  and the Courts on Court Street, brick and stucco walk-ups with balconies and fire escapes, a parking
  court with rows of garages, dumpsters, a building under scaffolding, broken walls. The buildings are the
  Retro Urban Kit's wall blocks put together by `tools/kenney/bake_hood.gd` (one mesh each, painted).
- Old Hill Cemetery, at the end of Court Street: iron railings, a cobbled drive in through the gate between
  rows of headstones (pumpkins on the graves in autumn, candles on some), crypts at the far end, lamps,
  crooked pines, the groundskeeper with his shovel, and after dark a ghost drifting about by the crypts.
- Sycamore Heights, east of downtown (off Bay Avenue and Main Street): a loop of suburban houses with
  drives, back-yard fences, stepping-stone paths and a green in the middle.
- Farm fields are ploughed in ridges with crops growing along them (wheat, cabbages, corn, sunflowers,
  potatoes), coloured with the seasons. Dirt tracks stop at the edge of the paved roads they join, and a
  field stops at any road that runs through it (a corner cut off by a road is left as plain verge).
- The railway: a viaduct all the way round the island, a little outside the ring road and high enough
  that every road passes under it, on pillars wherever there's no road or yard below (its strip is kept
  clear before the town is built, so nothing stands under it). Three trains run round it a third of the
  loop apart: a city electric, a steam train with old coaches and a goods train (containers, a tank,
  coal, lumber). You hear their rumble as they pass and a toot of the horn when one comes up on you.
  It's on the map as a dark line.
- Boats: speedboats, sailing boats, a fishing boat, tugs and a tow boat go round the island not far off
  the shore, each on its own loop (worked out from the coastline, so they go round the harbour, the
  pier and the Raceway), rocking on the swell with a white wake; cargo ships, a big ship and an ocean
  liner go round further out. Buoys bob off the beach.
- The Raceway: a race track on its own peninsula off the south-east coast (built up flat, reached by
  Raceway Road off the ring road, under the railway). The Grand Prix circuit (about 630 m a lap, 14 m
  wide) has a long main straight past the pit garages and covered grandstands, a fast right-hander, a
  sweeping south end, an S through the back and a last corner onto the straight, with red and white
  kerbs on every bend, barrier walls round the outside, the start gantry over a chequered line, banner
  towers, billboards, tents and parked race cars. Inside it, reached across the main straight, is a
  tight drift course lined with red and white blocks to run along (its kerbs on the inside of each
  bend only, the wall side left clear). Both loops are drawn as smooth curves with unbroken white edge
  lines; the way in crosses the main straight and meets the drift course on its top straight, with the
  walls stopping square either side of it. Challenges: Raceway Grand Prix
  (a race, 8 cars, 3 laps), Raceway Hot Lap (one timed lap) and Raceway Drift Course (drift it all the
  way round).

## Project layout

| Path | What |
| --- | --- |
| `boot/` | The over-the-air updater (first scene). Keep it small: the copy inside an installed APK can't update itself. |
| `scenes/main.tscn`, `scripts/main.gd` | Game states, input, camera, drift scoring, challenges, saving |
| `scripts/game/island.gd` | Heightfield, roads (splines cut into the land), the junction network, road markings, lots, colliders, merged static meshes, minimap layer |
| `scripts/game/districts.gd` | The island plan: districts, blocks, places, challenges and everything placed in them |
| `scripts/game/drift_car.gd` | Car physics: raycast wheels, tyre model, gearbox, handbrake and drift assist |
| `scripts/game/traffic.gd` | Traffic: lanes, junction turns and right of way, traffic lights |
| `scripts/game/people.gd` | People: stand, sit, walk, watch, wave, hop aside, get knocked down, run off |
| `scripts/game/ragdoll.gd` | People knocked down: jointed ragdolls (hips, shoulders), the blood they leave |
| `scripts/game/atmos.gd` | Day and night, seasons, sky and sun |
| `scripts/game/achievements.gd`, `save.gd`, `cars.gd` | Trophies, save data, the car list |
| `scripts/core/` | Palette (season colours), mesh builder, model loading and scales |
| `scripts/ui/` | All screens (built in code), icons drawn in code |
| `shaders/` | Toon shader with the season palette, sea, wipe |
| `tools/kenney/bake_kenney.gd` | Bakes the chosen Kenney kit models into `assets/kenney/` (people posed, arms loose) |
| `tools/kenney/bake_hood.gd` | Bakes the Graveyard Kit, more of the Retro Urban Kit and some City Kit Suburban pieces (`k_grave_*`, `k_urb_*`, `k_sub2_*`), and builds the hood's buildings from the Retro Urban Kit's wall blocks (`k_hood_*`) |
| `scripts/game/hood.gd` | Palmer Street, the Courts, Low Street, Old Hill Cemetery, Sycamore Heights |
| `scripts/game/onfoot.gd` | You on foot: walking, running, jumping, the animation (main.gd drives it and the camera) |
| `scripts/game/avatar.gd` | A playable character: the baked Kenney mini character, its animations, an accessory on its head |
| `tools/chars/bake_chars.gd` | Bakes the Kenney Mini Characters 2.0 (CC0) to `assets/chars/`: rig, animations, colours in the vertices |
| `scripts/game/cards.gd` | The fifty car cards (made-up cars, blurbs, rarities), XP and levels, packs; art in assets/cards/<id>.png |
| `shaders/card.gdshader` | The cards' look: metal frames, foil and holo by rarity, the card back, the foil pack |
| `shaders/sky.gdshader` | The sky: sun, moon, stars, drifting clouds |
| `scripts/game/ragdoll_rig.gd` | (see below) |
| `scripts/game/heist.gd` | The safes, the heist (drill hunt, drilling, the crack, the getaway, the safehouse), dropped cash |
| `tools/props/bake_props.gd` | Bakes the heist props (safe, core drill, duffle, cash) from glTF; `tools/audio/make_heist.py` their sounds |
| `scripts/game/gunplay.gd` | Guns on foot: aim and lock-on, firing, hits and effects, reloads, cars burning and blowing up, your health, officers on foot, WASTED |
| `scripts/game/ragdoll_rig.gd` | A rigged character gone limp: rigid bodies for its parts, driving its skeleton (you and officers) |
| `scripts/game/aim_mod.gd` | Points a character's arms (both hands on the gun) and upper body at what they're aiming at, over the animation |
| `scripts/game/weapons.gd` | The six guns: stats, looks, models (or blocky stand-ins without the licensed pack) |
| `tools/guns/bake_guns.gd` | Bakes PIXEL ARSENAL presets to game meshes (run against the private pack; output goes to the private repo) |
| `scripts/game/green.gd` | Southside Green, the park along the south edge of town |
| `scripts/game/street_stunts.gd` | Grind rails, kickers, low ramps and a boost pad on the town's open lots (the car's hop and grind are in `drift_car.gd`) |
| `tools/kenney/bake_klyo.gd` | Bakes the Klyo stunt kit models (and their simple collision meshes, `_col`) into `assets/kenney/k_klyo_*` |
| `tools/look/` | Look-dev: `island_look.gd` photographs parts of the island, `kgrid.gd` makes a model contact sheet, `piece_look.gd` photographs one model from four sides on a 1 m grid |
| `tools/test/` | `handling.gd` (handling report), `road_audit.gd` (nothing in roads or pavements), `road_surface.gd` (roads meet the ground and each other), `road_net.gd` (junctions and loose ends), `traffic_soak.gd` (overlaps, jams, cars off the road), `collide_test.gd`, `probe.gd` |
| `tools/audio/`, `tools/music/` | Sound synthesis scripts (the fallback sounds); the CC0 music list the build fetches |
| `scripts/game/dents.gd` | Crash damage: bends a mesh in around an impact and scuffs the paint |
| `scripts/game/route.gd` | GPS: the road network as a graph and the shortest way along it |
| `scripts/game/railway.gd` | The railway: the line (the ring road pushed out and smoothed), the viaduct, track and pillars, the trains and their sounds |
| `scripts/game/boats.gd` | Boats and ships going round the island off the shore, their wakes, the buoys |
| `scripts/game/raceway.gd` | The Raceway peninsula: its land, the circuit and drift course, the dressing, its challenges |
| `scripts/game/circuits.gd` | The three other circuits (Cliffside, Eastpoint, Southshore): their headlands, tracks, access roads, dressing and races |
| `scripts/game/heli.gd` | The police helicopter (built in code): flying, banking, its searchlight, what it can see |
| `scripts/game/police.gd` | The police: patrol cars in the traffic noticing you, wanted stars, the police cars (road-following, ramming, boxing in, getting unstuck, coming in out of sight), busted and escaped, police at street races |
| `scripts/game/crew.gd` | The drivers: roaming, swapping numbers, your crew following your line, tandem drifts, the police after them |
| `scripts/ui/phone.gd` | The phone: your contacts, Call and Send off |
| `scripts/game/race.gd` | Races: the racing line (the streets' middle, or a route along the roads, pulled tight within their width, with a speed for every metre and crests capped), the difficulty levels, the CPU drivers (follow, pass, back off, recover), checkpoints, laps and places |
| `tools/cars/bake_glb_car.gd` | Bakes a car made as a glTF (the Haywire, the Mountain Ghost) the same way: vertex colours, wheels split out, big plain parts simplified, its livery kept as UVs into one atlas (`assets/cars/<key>_detail.png`) that the toon shader reads through the `car_detail` global |
| `tools/cars/export_paints.gd` | Bakes each car's other liveries as per-vertex colour rows (`assets/cars/*_paints.res`) |

There are no autoloads and no `class_name`s, so an update pack can replace any script before it loads.

## Testing without a phone

```
godot --path . -- --auto                         # autopilot drives the roads
godot --path . -- --drive --at=harbour --hour=21 # start at a zone, trial, place name or x,z[,yaw]
godot --path . -- --garage=up --fresh            # garage on the Upgrades tab, fresh save
godot --path . -- --drive --put=-108,284,90 --stunt=backflip   # exactly here (x,z,yaw), gas on, a trick in the air
godot --path . -- --drive --season=3             # 0 spring, 1 summer, 2 autumn, 3 winter
godot --path . -- --drive --weather=storm         # clear, cloudy, rain, storm, fog, snow
godot --path . -- --drive --grindtest=0          # line up on grind rail 0, hop on, ride it off the end (logged)
godot --path . -- --drive --ramcop               # drive into the nearest patrol car (--ramcop_v=12 to coast in at 12 m/s)
godot --path . -- --drive --perfdump=2           # what's drawn, grouped and biggest first (--perfshadow: just what casts shadows)
godot --path . -- --drive --foottest             # out of the car, walk, run, jump, turn, back in (logged)
godot --path . -- --drive --guntest=rifle --at=square   # out with a gun, shooting; police come (logged)
godot --path . -- --drive --guntest=smg --guncar          # shoot the nearest car till it blows (logged)
godot --path . -- --drive --guntest=rifle --gunhold       # out and aiming, holding still (the pose, the reticle)
godot --path . -- --drive --guntest=rifle --gundie        # shot dead: the ragdoll, WASTED
godot --path . -- --drive --heisttest=0                   # the whole heist on safe 0, fast (logged)
godot --path . -- --garage=guns --gun=shotgun --look=1    # the Guns tab, holding this gun
godot --path . -- --drive --stealtest=k_car_taxi # out, take the nearest taxi, drive it, back to your own car (logged)
godot --path . -- --garage=driver --avatar=robot --acc=glasses   # the Driver tab, as this character
godot --path . -- --drive --perfdraws=3          # what's in view and in range right now, grouped (each at least a draw call)
godot --path . -- --drive --noshadow             # (or --shadowdist=60) to see what shadows cost: RESULT has tris and draws
godot --path . -- --drive --race=downtown --raceauto --racelog   # straight into a race, CPU drives you too
godot --path . -- --drive --crashtest=tbone --crashv=20   # crash tests (tbone, wall, front, swipe, swipe0, ped), logged
godot --path . -- --drive --damage=90 --engine=95          # start battered, the engine on fire
godot --path . -- --drive --begin=trial:main      # as if START was pressed (race:downtown, zone:bowl...)
godot --path . -- --drive --demo=100 --aim=tree   # lined up for a run at a tree (lamp, light)
godot --path . -- --drive --race=downtown --topcam=-170,120,190  # ...watched from straight above
godot --path . -- --auto --wanted=3 --copslog     # the police after you from the start (3 stars), logged
godot --path . -- --drive --begin=race:downtown --raceauto --cops=1 --copsat=12   # police at this race, 12 s in
godot --path . -- --drive --demo=3 --rwtest=6     # hold REWIND at 6 s for 1.5 s, logged
godot --headless --path . --fixed-fps 120 -- --drive --demo=8 --interp   # the car between physics steps, per frame
godot --path . -- --drive --traincam=0            # alongside a train (1, 2: the others); --boatcam=3 a boat
godot --path . -- --drive --lookcam=-60,40,330,-60,0,560   # the camera here, looking there
godot --path . -- --drive --begin=race:raceway --raceauto --racelog   # the Raceway Grand Prix
godot --path . -- --drive --race=northloop --diff=2 --raceauto --racelog   # on Hard (0 easy, 1 medium); ringroad, beachloop, cliffside, eastpoint, southshore
godot --path . -- --drive --race=northloop --racelog --linedump=1640:1740 --quit_after=3   # the line and its speeds, every 4 m
godot --path . -- --drive --begin=race:cliffside --raceauto --restartat=14 --quitat=40   # the pause menu's Restart, then Leave
godot --path . -- --drive --auto --begin=zone:square --againtest   # the results card's Try again, pressed for you
godot --path . -- --drive --begin=race:downtown --pauseat=6        # the pause menu (--sheet=settings, help, map, trophies too)
godot --path . -- --drive --car=mail --tunetest=5,-2,8 --hour=21   # this car, slammed, blue neon, at night
godot --path . -- --drive --padtest --shot_t=7:pads.png   # the controls in use (gas, NOS, handbrake)
godot --path . -- --drive --patrolcam             # beside a patrol car in the traffic
godot --headless --path . -- --auto --crew=3 --crewlog --crashlog   # three of the drivers called to you, logged
godot --path . -- --drive --crew=Kai,Rico --phone_at=6               # these two with you, the phone up 6 s in
godot --path . -- --drive --wanted=1 --shot_busted=busted.png   # stand still, get busted, screenshot it
godot --path . -- --auto --wanted=4 --shot_t=14:heli.png        # a screenshot at a game time
xvfb-run godot --path . -- --drive --shot=/tmp/x.png --shot_at=200 --quit_after=30
godot --headless --path . -s res://tools/test/handling.gd -- bug,hotrod all   # handling report
godot --headless --path . -s res://tools/test/road_audit.gd                  # props in the road
godot --headless --path . -s res://tools/test/float_audit.gd                 # anything floating, or sunk in the ground
godot --headless --path . -s res://tools/test/track_audit.gd                 # the Raceway's loops: kinks, folds, seams
xvfb-run godot --path . -s res://tools/look/shadow_flicker.gd -- street 60   # pixels that change frame to frame
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
the game falls back to its own synthesized sounds (`tools/audio/`; the train, the police radio, the
helicopter and someone being hit are always synthesized). The buildings, people, pets, vehicles,
ships and props are from Kenney's CC0 kits (kenney.nl: City Kit
Suburban and Commercial, Modular Buildings, Retro Urban Kit, Car Kit, Mini Characters, Cube Pets,
Mini Skate, Survival Kit, Mini Forest, Castle Kit, Holiday Kit, Mini Arena, Pirate Kit, Train Kit, Racing
Kit, Watercraft Pack, Graveyard Kit). The player cars
are the Tiny Car Pack. The Stunt Yard's ramps, platforms, half-pipes, gap jump, boost pads, gate, hoop,
tunnel and yard props are "Stunt arena 3D models: ramps, hoop, barriers (GLB)" and "Stunt arena 3D
expansion: loop, half-pipe, tunnel, obstacles" by Klyo Games (https://games.klyo.pl/free-game-assets/),
licensed CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/); they're baked to the game's
flat-colour style, and the loop is built in code to match (the kit's loop is a closed ring a car can't
drive into). Terrain, roads and the remaining props are made in code. Music: CC0 lo-fi hip hop
by HoliznaCC0 and omfgdude from OpenGameArt (see `tools/music/sources.json`; the tracks actually used
are listed in `tracks.json` on the `music` branch). The font is Fredoka (SIL Open Font License,
`assets/fonts/LICENSE_Fredoka.txt`).
