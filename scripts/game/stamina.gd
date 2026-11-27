extends RefCounted
## Stamina: for you, the people you fight, the people about and the police on foot. Running, swinging and
## taking blows on your guard use it up; it comes back once you ease off (quickest stood still). Run it right
## out and you're spent: everything's slower and weaker (punches, kicks, running) until you've stopped and got
## your breath back (most of the way up again). Hurt badly, people limp.
## A stamina is a dictionary: {v (0..MAX), spent, idle (since it was last used)}.

const MAX := 100.0
const BACK_AT := 0.65          # spent until it's back up this far
const REGEN := 22.0            # a second, stood still (moving about: less; running: none)
const WAIT := 0.6              # it starts coming back this long after it was last used
const SPENT_K := 0.6           # spent: this much of your speed, punch speed and power
const HURT_AT := 0.4           # under this much of your health you limp

static func make() -> Dictionary:
	return {"v": MAX, "spent": false, "idle": 9.0}

static func use(st: Dictionary, amt: float) -> void:
	st["v"] = maxf(0.0, float(st["v"]) - amt)
	st["idle"] = 0.0
	if float(st["v"]) <= 0.0:
		st["spent"] = true

## rate: 1 stood still, about half on the move, 0 running.
static func tick(st: Dictionary, dt: float, rate := 1.0) -> void:
	st["idle"] = float(st["idle"]) + dt
	if float(st["idle"]) > WAIT and rate > 0.0:
		st["v"] = minf(MAX, float(st["v"]) + REGEN * rate * (1.25 if st["spent"] else 1.0) * dt)
	if st["spent"] and float(st["v"]) >= MAX * BACK_AT:
		st["spent"] = false

## How much of your speed and power you've got: 1, or less, spent.
static func k(st: Dictionary) -> float:
	return SPENT_K if st.get("spent", false) else 1.0

static func frac(st: Dictionary) -> float:
	return float(st["v"]) / MAX

## Can it pay for this (a block, say)?
static func has(st: Dictionary, amt: float) -> bool:
	return not st.get("spent", false) and float(st["v"]) >= amt
