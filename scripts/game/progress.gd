extends RefCounted
## Your level, and what it opens up. XP comes from everything you do (cards.gd works it out from your stats:
## races, medals, drifting, distance, escapes, heists, places found...). Each level pays out cash and a pack
## of car cards, and some levels open things up: the harder races, heists (level 10), and what the shops will
## sell you (cars at Lo-Fi Customs, guns and attachments at the Armory, looks at Lo-Fi Threads).
## Paced for a long haul: level 10 a couple of hours in, everything open by about level 30.

const Cards := preload("res://scripts/game/cards.gd")
const CARS := preload("res://scripts/game/cars.gd")
const Weapons := preload("res://scripts/game/weapons.gd")

const MAX_LEVEL := 30
const RACE_LEVEL := [1, 5, 12]          # easy, medium, hard
const HEIST_LEVEL := 10
const DELIVERY_LEVEL := 3              # the car delivery contact in your phone

static func level(save) -> int:
	return mini(int(Cards.level_of(Cards.xp(save))[0]), MAX_LEVEL)

## [level, xp into this level, xp this level takes, total xp]
static func progress(save) -> Array:
	var x: int = Cards.xp(save)
	var lv: Array = Cards.level_of(x)
	if int(lv[0]) >= MAX_LEVEL:
		return [MAX_LEVEL, 1, 1, x]
	return [int(lv[0]), int(lv[1]), int(lv[2]), x]

## Cash for reaching a level.
static func cash_for(lv: int) -> int:
	return 500 + 250 * lv

## The level a car's sold from: the cheapest few to start with, then up through the list by price.
static func car_level(id: String) -> int:
	var d: Dictionary = CARS.by_id(id)
	if d.has("lvl"):
		return int(d["lvl"])
	var i := CARS.index_of(id)
	if i <= 0 or int(d.get("price", 0)) == 0:
		return 1
	var n: int = CARS.LIST.size()
	return clampi(1 + int(round(float(i) * 27.0 / float(n - 1))), 1, MAX_LEVEL)

static func gun_level(id: String) -> int:
	return int(Weapons.by_id(id).get("lvl", 1))

## Characters at Lo-Fi Threads: the first few free, the rest open up a level or so apart.
static func char_level(i: int) -> int:
	return 1 if i < 6 else clampi(2 + int((i - 6) * 24 / 26), 2, MAX_LEVEL)

static func char_price(i: int) -> int:
	return 0 if i < 6 else 400 + (i - 6) * 150

static func race_ok(save, diff: int) -> bool:
	return level(save) >= int(RACE_LEVEL[clampi(diff, 0, 2)])

## What opens up at a level: [[icon, line], ...] for the level-up card.
static func unlocks_at(lv: int) -> Array:
	var out: Array = []
	if lv == RACE_LEVEL[1]:
		out.append(["flag", "Medium races"])
	if lv == RACE_LEVEL[2]:
		out.append(["flag", "Hard races"])
	if lv == HEIST_LEVEL:
		out.append(["star", "Heists: crack the safes around the island"])
	if lv == DELIVERY_LEVEL:
		out.append(["phone", "Car delivery: call Dez to bring any car you own"])
	for d in CARS.LIST:
		if int(d.get("price", 0)) > 0 and car_level(String(d["id"])) == lv:
			out.append(["car", "%s at Lo-Fi Customs" % String(d["name"])])
	for w in Weapons.LIST:
		if int(w.get("price", 0)) > 0 and int(w.get("lvl", 1)) == lv:
			out.append(["star", "%s at the Armory" % String(w["name"])])
	var parts: int = Weapons.parts_at_level(lv)
	if parts > 0:
		out.append(["gear", "%d new attachments at the Armory" % parts])
	return out
