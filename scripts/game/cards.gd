extends RefCounted
## Car cards: fifty cars (made up, each a nod to a classic), each with a blurb, in five rarities. You level up by playing (XP comes from
## what you've done: drifting, distance, races, escapes, heists, trophies, places, hidden cash...), and every
## level is a new pack of three cards. A card you already have pays out in cash instead.
## Save: "cards" (id -> how many), "packs_opened", "level_seen".

const RARITY := [
	{"name": "Common", "col": Color("9aa3ad"), "odds": 0.55, "dupe": 100},
	{"name": "Uncommon", "col": Color("5ccf7a"), "odds": 0.25, "dupe": 250},
	{"name": "Rare", "col": Color("4aa8ff"), "odds": 0.13, "dupe": 600},
	{"name": "Epic", "col": Color("b36bff"), "odds": 0.055, "dupe": 1500},
	{"name": "Legendary", "col": Color("ffb020"), "odds": 0.015, "dupe": 4000},
]

## [id, name, year, from, rarity 0-4, blurb]. The cars are made up (makers and all), each one a nod to a
## classic; the blurbs are an enthusiast's, not a fact sheet. (The ids are only for the art files.)
const LIST := [
	["corolla", "Tokara Commuter", 1966, "Japan", 0, "The sensible little sedan that quietly took over the world, one driveway at a time. Boring? Maybe. Unkillable? Absolutely."],
	["beetle", "Volkhaus Pebble", 1938, "Germany", 0, "Round as a river stone, air-cooled and so simple you could fix it with a coin and some patience. Everybody's first car, or their parents'."],
	["civic", "Hikari City", 1972, "Japan", 0, "A tiny hatch with a clever little engine that sipped fuel while everyone else was guzzling it."],
	["model_t", "Hartwell Type 1", 1908, "USA", 0, "The car that put a whole nation on wheels. Tall, spindly, and built so fast the factory could barely keep up with itself."],
	["mini", "Brixton Minim", 1959, "UK", 0, "Four seats in a shoebox, and it corners like a go-kart. Rally drivers loved it more than they'd ever admit."],
	["fiat500", "Piccolo Topo", 1957, "Italy", 0, "Barely bigger than a scooter and twice as charming. Parks anywhere, makes everyone smile."],
	["2cv", "Duclos Escargot", 1948, "France", 0, "Soft as a sofa and light as a tent. Built for bumpy farm tracks, and somehow still adorable."],
	["hilux", "Tokara Mule", 1968, "Japan", 0, "The pickup legends say you can't kill. People have tried. It just coughs, starts up and asks for more."],
	["f150", "Hartwell Haulmaster", 1948, "USA", 0, "The workhorse of every ranch, building site and tailgate party. Big bed, bigger heart."],
	["accord", "Hikari Harmony", 1976, "Japan", 0, "The family sedan that did everything right and never once asked for attention."],
	["prius", "Tokara Whisper", 1997, "Japan", 0, "Half petrol, half battery, completely silent away from the lights. Drives everyone else a little mad."],
	["landcruiser", "Tokara Outrider", 1951, "Japan", 0, "When the road ends it doesn't even notice. Desert, jungle, glacier: it's been there and come back."],
	["volvo240", "Nordvik Brick", 1974, "Sweden", 0, "Square, safe and close to indestructible. The boxiest way there is to be cool."],
	["smart", "Mikro Two", 1998, "Germany", 0, "Two seats and almost nothing else. Fits in parking spots other cars can only dream about."],
	["gti", "Volkhaus Rally GT", 1976, "Germany", 1, "A plain little hatchback that learned to sprint, and started a whole craze of family cars with attitude."],
	["mx5", "Mizuho Breeze", 1989, "Japan", 1, "Light, balanced, roof down, grin on. Proof you don't need big power for big fun."],
	["mustang", "Hartwell Sundance", 1964, "USA", 1, "Long hood, short tail, rumbling V8. It invented a whole kind of car and never looked back."],
	["willys", "Patrol Scout", 1941, "USA", 1, "Built for hard times, it climbs, wades and crawls almost anywhere. The grandad of every off-roader."],
	["belair", "Bellmont Starliner", 1957, "USA", 1, "Chrome everywhere and tail fins sharp enough to slice the sky. Peak cruising, windows down, radio up."],
	["240z", "Seiran Zephyr", 1969, "Japan", 1, "A long-nosed six-cylinder sports car that punched way, way above its price tag."],
	["corvette", "Bellmont Comet", 1953, "USA", 1, "A white roadster with big dreams: the first of a long line of all-American sports cars."],
	["delorean", "Ostrander Chrono", 1981, "UK", 1, "Bare brushed-metal skin, doors that open like wings, and an air of mystery that never quite went away."],
	["gto", "Ridgeway Thunder", 1964, "USA", 1, "Somebody dropped a monster engine into a family coupe, and a whole era of muscle was born."],
	["camaro", "Bellmont Rival", 1966, "USA", 1, "Built to take on the pony-car king, and it came out swinging."],
	["s15", "Seiran Sylph", 1999, "Japan", 1, "Light, turbocharged, rear-wheel drive. Drifters fight over the clean ones."],
	["s2000", "Hikari Redline", 1999, "Japan", 1, "A roadster that screams all the way to the sky before it changes gear. Turbos? Who needs them."],
	["models", "Volta Silent", 2012, "USA", 1, "A quiet executive saloon that embarrasses supercars at the lights, then plugs itself in at home."],
	["ae86", "Tokara Ridgeback", 1983, "Japan", 2, "A humble little coupe that mountain-pass drifters turned into a cult hero. Pop-up lights, sideways forever."],
	["r32", "Seiran Thunderbolt GT", 1989, "Japan", 2, "All-wheel drive, twin turbos, and a nasty habit of embarrassing everything else on the racetrack."],
	["supra", "Tokara Apex", 1993, "Japan", 2, "A smooth grand tourer hiding an engine that tuners just can't seem to break."],
	["rx7", "Mizuho Spinner", 1992, "Japan", 2, "Curvy, light, and powered by a strange little engine that hums instead of thumps."],
	["m3", "Halden Sport 3", 1986, "Germany", 2, "A boxy saloon with bulging arches, built to win touring car races and very, very good at it."],
	["911", "Kessler Classic", 1964, "Germany", 2, "Engine hanging out past the back wheels, and they've kept that recipe for decades. Tricky, rewarding, timeless."],
	["quattro", "Kranich Grip", 1980, "Germany", 2, "It took all-wheel drive to the rally stages, and the rest of the field spent years catching up."],
	["etype", "Ashcombe Velvet", 1961, "UK", 2, "An impossibly long bonnet and curves for days. Plenty of people still call it the most beautiful car ever made."],
	["evo", "Ryujin Stage", 1992, "Japan", 2, "A four-door rally weapon with all-wheel drive and a turbo that never stops pulling."],
	["impreza", "Kisaragi Rally", 1992, "Japan", 2, "A flat-four burble, all-wheel drive and a gravel pedigree that put it on a million bedroom walls."],
	["nsx", "Hikari Aero", 1990, "Japan", 3, "A mid-engined supercar you could drive every single day. It made the old-school exotics very nervous."],
	["countach", "Vespucci Furia", 1974, "Italy", 3, "All wedges and angles, with doors that swing up to the sky. The poster car of a generation."],
	["gt40", "Hartwell Endurance", 1966, "USA", 3, "Built for one job: beat the best at the world's toughest twenty-four hour race. Job done."],
	["cobra", "Halvorsen Asp", 1962, "USA", 3, "A tiny roadster with far too much engine. Terrifying, glorious, and very, very loud."],
	["stratos", "Ventura Cuneo", 1973, "Italy", 3, "A wedge built for exactly one thing: owning the rally stages. And it did, again and again."],
	["300sl", "Ardent Wingdoor", 1954, "Germany", 3, "Its doors lift like a gull's wings. Elegant, fast, and the holy grail of a lot of collections."],
	["959", "Kessler Sandstorm", 1986, "Germany", 3, "A tech-packed supercar that also went and conquered a brutal desert rally. Total overachiever."],
	["daytona", "Ridgeway Spearhead", 1969, "USA", 3, "A nose like a missile, a wing like a goalpost, built for one thing: ridiculous speed on the oval."],
	["f40", "Corsini Rossa", 1987, "Italy", 4, "Raw, loud, no driver aids, all carbon and turbos. Plenty of people say it's the ultimate driver's car."],
	["mclarenf1", "Sterling Uno", 1992, "UK", 4, "The driver sits dead centre with a passenger either side. For years nothing on the road could touch it."],
	["veyron", "Aurelle Grand", 2005, "France", 4, "Sixteen cylinders, four turbos, and a top speed that made physics nervous."],
	["miura", "Vespucci Aurora", 1966, "Italy", 4, "The car that invented the supercar: a big engine right behind your head and a body like a sculpture."],
	["agera", "Fjell Hyper", 2015, "Sweden", 4, "A small team from a cold country built a hypercar that briefly wore the crown of fastest car on the planet."],
]

static func by_id(id: String) -> Array:
	for c in LIST:
		if c[0] == id:
			return c
	return []

## All the XP you've earned, worked out from what you've done.
static func xp(save) -> int:
	var st: Dictionary = save.data.get("stats", {})
	var g := func(k: String) -> float: return float(st.get(k, 0.0))
	var medals := 0
	for m in (save.data.get("medals", {}) as Dictionary).values():
		medals += int(m)
	var x: float = g.call("drift_points") / 40.0 + g.call("stunt_points") / 40.0 + g.call("distance") / 40.0 \
		+ g.call("races") * 120.0 + g.call("race_wins") * 200.0 + g.call("hard_wins") * 300.0 \
		+ g.call("heists") * 800.0 + g.call("escapes") * 150.0 + g.call("cars_blown") * 60.0 + g.call("cops_down") * 40.0 \
		+ g.call("cars_taken") * 40.0 + g.call("fights_won") * 350.0 + (save.data.get("coins_taken", []) as Array).size() * 50.0 \
		+ (save.data.get("places", []) as Array).size() * 80.0 + medals * 120.0 + (save.data.get("ach", {}) as Dictionary).size() * 100.0
	return int(x)

## XP to get from level n to n+1.
static func step(n: int) -> int:
	return 600 + 150 * n          # (level 10 about an hour and a half in, level 30 about ten hours)

## [level, xp into it, xp it takes]
static func level_of(x: int) -> Array:
	var n := 1
	var left := x
	while left >= step(n):
		left -= step(n)
		n += 1
	return [n, left, step(n)]

## Packs you've got to open: one to start with, one more each level.
static func packs(save) -> int:
	var lv: int = level_of(xp(save))[0]
	return maxi(0, lv - int(save.data.get("packs_opened", 0)))

## Open a pack: three cards (the last one at least Uncommon). Returns [[card, new?, cash for a dupe], ...].
static func open_pack(save) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var got: Dictionary = save.data.get("cards", {})
	var out: Array = []
	for k in 3:
		var r := _roll(rng, k == 2)
		var pool: Array = []
		for c in LIST:
			if int(c[4]) == r:
				pool.append(c)
		var card: Array = pool[rng.randi() % pool.size()]
		var id: String = card[0]
		var have := int(got.get(id, 0))
		got[id] = have + 1
		var cash := 0 if have == 0 else int(RARITY[r]["dupe"])
		out.append([card, have == 0, cash])
		save.data["coins"] = int(save.data["coins"]) + cash
	save.data["cards"] = got
	save.data["packs_opened"] = int(save.data.get("packs_opened", 0)) + 1
	return out

static func _roll(rng: RandomNumberGenerator, uncommon_up: bool) -> int:
	var x := rng.randf()
	var acc := 0.0
	var lo := 1 if uncommon_up else 0
	var total := 0.0
	for i in range(lo, RARITY.size()):
		total += float(RARITY[i]["odds"])
	for i in range(lo, RARITY.size()):
		acc += float(RARITY[i]["odds"]) / total
		if x <= acc:
			return i
	return RARITY.size() - 1

static func owned(save) -> int:
	return (save.data.get("cards", {}) as Dictionary).size()
