extends RefCounted
## Car cards: fifty real cars, each with a true fact, in five rarities. You level up by playing (XP comes from
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

## [id, name, year, from, rarity 0-4, fact]
const LIST := [
	["corolla", "Toyota Corolla", 1966, "Japan", 0, "The best-selling car nameplate in history: more than 50 million sold across its generations."],
	["beetle", "Volkswagen Beetle", 1938, "Germany", 0, "More than 21.5 million of the original Beetle were built. The last one rolled out of Puebla, Mexico, in 2003."],
	["civic", "Honda Civic", 1972, "Japan", 0, "Its CVCC engine met the 1970s US emissions rules without a catalytic converter."],
	["model_t", "Ford Model T", 1908, "USA", 0, "Over 15 million built. Ford's moving assembly line cut the time to build one from about 12 hours to about 90 minutes."],
	["mini", "Mini", 1959, "UK", 0, "Alec Issigonis turned the engine sideways so that 80% of the tiny car's floor was left for people and luggage."],
	["fiat500", "Fiat 500", 1957, "Italy", 0, "Under 3 metres long, and nearly 4 million made between 1957 and 1975."],
	["2cv", "Citroën 2CV", 1948, "France", 0, "Its brief: carry two farmers and a basket of eggs across a ploughed field without breaking any."],
	["hilux", "Toyota Hilux", 1968, "Japan", 0, "Top Gear tried to kill one in 2003: sunk in the sea, set on fire, left on a building as it was demolished. It still started."],
	["f150", "Ford F-Series", 1948, "USA", 0, "America's best-selling pickup truck every year since 1977."],
	["accord", "Honda Accord", 1976, "Japan", 0, "In 1982 it became the first Japanese car built in the USA, at Marysville, Ohio."],
	["prius", "Toyota Prius", 1997, "Japan", 0, "The first mass-produced hybrid car, launched in Japan in 1997."],
	["landcruiser", "Toyota Land Cruiser", 1951, "Japan", 0, "Toyota's longest-running model: it began in 1951 as the BJ and took the Land Cruiser name in 1954."],
	["volvo240", "Volvo 240", 1974, "Sweden", 0, "Built for 19 years: around 2.8 million of the 200 series were made."],
	["smart", "Smart Fortwo", 1998, "Germany", 0, "About 2.5 metres long: short enough to park nose-in to the kerb in some cities."],
	["gti", "Volkswagen Golf GTI", 1976, "Germany", 1, "The first GTI made 110 hp from a fuel-injected 1.6 and helped start the hot hatch craze."],
	["mx5", "Mazda MX-5", 1989, "Japan", 1, "Guinness lists it as the best-selling two-seat sports car ever: over a million built."],
	["mustang", "Ford Mustang", 1964, "USA", 1, "Unveiled at the New York World's Fair in April 1964; about 22,000 were ordered on its first day."],
	["willys", "Willys MB Jeep", 1941, "USA", 1, "Willys built over 360,000 for the Second World War, and Ford about 280,000 more to the same design."],
	["belair", "Chevrolet Bel Air", 1957, "USA", 1, "With optional fuel injection its 283 cubic-inch V8 made 283 hp: one horsepower per cubic inch."],
	["240z", "Datsun 240Z", 1969, "Japan", 1, "A six-cylinder sports car that sold in America for about $3,500."],
	["corvette", "Chevrolet Corvette", 1953, "USA", 1, "Only 300 were built in 1953, every one Polo White with a red interior."],
	["delorean", "DeLorean DMC-12", 1981, "UK", 1, "Unpainted stainless-steel body panels and gull-wing doors. About 9,000 were made."],
	["gto", "Pontiac GTO", 1964, "USA", 1, "Often called the first muscle car: a big 389 cubic-inch V8 dropped into the mid-size Tempest."],
	["camaro", "Chevrolet Camaro", 1966, "USA", 1, "Revealed in September 1966 as Chevrolet's answer to the Mustang."],
	["s15", "Nissan Silvia S15", 1999, "Japan", 1, "Light, rear-wheel drive and turbocharged (an SR20DET): a drifting favourite."],
	["s2000", "Honda S2000", 1999, "Japan", 1, "Its 2.0-litre engine revved to 9,000 rpm and made about 120 hp per litre with no turbo."],
	["models", "Tesla Model S", 2012, "USA", 1, "Tesla claims 0-60 mph in 1.99 seconds for the Plaid version (with a one-foot rollout)."],
	["ae86", "Toyota AE86 Trueno", 1983, "Japan", 2, "A drifting icon: Keiichi Tsuchiya, the 'Drift King', raced one."],
	["r32", "Nissan Skyline GT-R R32", 1989, "Japan", 2, "It won so much in Australian touring cars that the press there nicknamed it 'Godzilla'."],
	["supra", "Toyota Supra Mk4", 1993, "Japan", 2, "Its 2JZ-GTE twin-turbo straight-six is famous for taking far more power than it left the factory with."],
	["rx7", "Mazda RX-7 FD", 1992, "Japan", 2, "Powered by a 1.3-litre twin-rotor Wankel engine with sequential twin turbos."],
	["m3", "BMW M3 E30", 1986, "Germany", 2, "Built to race in Group A, it's often called the most successful touring car of all time."],
	["911", "Porsche 911", 1964, "Germany", 2, "Built since 1964, always with its engine behind the rear axle."],
	["quattro", "Audi Quattro", 1980, "Germany", 2, "It brought four-wheel drive to world rallying and changed the sport."],
	["etype", "Jaguar E-Type", 1961, "UK", 2, "Enzo Ferrari is said to have called it the most beautiful car ever made."],
	["evo", "Mitsubishi Lancer Evolution", 1992, "Japan", 2, "Tommi Mäkinen won four World Rally drivers' titles in a row (1996-99) in Mitsubishis."],
	["impreza", "Subaru Impreza WRX", 1992, "Japan", 2, "Subaru took three World Rally manufacturers' titles in a row, 1995-97, with the Impreza."],
	["nsx", "Honda NSX", 1990, "Japan", 3, "The first mass-produced car with an all-aluminium body. Ayrton Senna helped test it."],
	["countach", "Lamborghini Countach", 1974, "Italy", 3, "Its name is a Piedmontese exclamation of astonishment. Those scissor doors started a trend."],
	["gt40", "Ford GT40", 1966, "USA", 3, "Finished first, second and third at Le Mans in 1966, beating Ferrari."],
	["cobra", "Shelby Cobra", 1962, "USA", 3, "Carroll Shelby put a Ford V8 into the light British AC Ace."],
	["stratos", "Lancia Stratos", 1973, "Italy", 3, "Built for rallying from the start, it won the World Rally Championship in 1974, 1975 and 1976."],
	["300sl", "Mercedes-Benz 300SL", 1954, "Germany", 3, "Its gull-wing doors were there because the tall frame sides left no room for normal ones."],
	["959", "Porsche 959", 1986, "Germany", 3, "A technology showcase with computer-controlled four-wheel drive. A 959 won the Paris-Dakar Rally in 1986."],
	["daytona", "Dodge Charger Daytona", 1969, "USA", 3, "With its tall wing and pointed nose, it was the first car to lap a NASCAR track at over 200 mph (1970)."],
	["f40", "Ferrari F40", 1987, "Italy", 4, "The last new Ferrari Enzo Ferrari approved, and the first road car claimed to top 200 mph."],
	["mclarenf1", "McLaren F1", 1992, "UK", 4, "The driver sits in the middle. In 1998 one reached 386 km/h (240 mph), a production-car record then."],
	["veyron", "Bugatti Veyron", 2005, "France", 4, "1,001 metric horsepower from a quad-turbo W16: the first production car past 400 km/h."],
	["miura", "Lamborghini Miura", 1966, "Italy", 4, "Often called the first supercar: a V12 mounted sideways behind the driver."],
	["agera", "Koenigsegg Agera RS", 2015, "Sweden", 4, "In 2017 it averaged 447 km/h (278 mph) both ways along a closed public road in Nevada."],
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
		+ g.call("cars_taken") * 40.0 + (save.data.get("coins_taken", []) as Array).size() * 50.0 \
		+ (save.data.get("places", []) as Array).size() * 80.0 + medals * 120.0 + (save.data.get("ach", {}) as Dictionary).size() * 100.0
	return int(x)

## XP to get from level n to n+1.
static func step(n: int) -> int:
	return 800 + 200 * n

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
