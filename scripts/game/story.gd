extends Node
## The story: you're new in town. Your friend Jay's handed you his old car (the Sunny Bug: not pretty, but it
## runs) and texts you what to do: win some cash at the races and challenges, spend it on Main Street, level
## up, build your garage, and at level 10 start on the safes with a crew, the money going into the mansion.
## A step at a time (save "story"): each one a text or two from Jay and a goal on the HUD, done when you've
## done it.

const Progress := preload("res://scripts/game/progress.gd")
const FRIEND := "Jay"

## [goal on the HUD, Jay's texts when it starts]
const STEPS := [
	["Get in Jay's old car", ["Yo! You made it. Welcome to town", "That old Bug's yours now. Not pretty but it runs. Keys are in it"]],
	["Win some cash: a race or a challenge (the markers on the map)", ["Money's tight round here. Races and challenges pay, every time you run them",
		"Easy races first. The better your place, the more you make"]],
	["Spend it on Main Street: Lo-Fi Customs, the Armory, Lo-Fi Threads", ["Nice! Main Street's got everything: cars at Lo-Fi Customs, guns at the Armory, threads at Lo-Fi Threads",
		"Everything you do levels you up. Each level's cash and a pack of car cards, and the shops open up more"]],
	["Reach level 3 (Dez delivers your cars from then)", ["Keep racing, drifting, exploring. It all counts", "At level 3 my boy Dez can bring any car you own wherever you are"]],
	["Start your garage: the dirt lot south of town", ["You're doing good. Time to put roots down",
		"There's a lot south of town: build a garage on it, stage by stage. Your cars live there when it's done"]],
	["Reach level 10 for the safes", ["Medium races open at level 5, hard at 12. They pay way more",
		"And there's safes all over this island, stuffed with cash. Get to level 10 and we'll talk"]],
	["Pull a heist (grab a crew first: swap numbers with drivers)", ["Level 10. Let's get serious", "Find a safe, start the heist, get the tool bag, drill it, grab the money, lose the cops, get it home",
		"Bring friends: they ride with you and shoot back. They take 15% each, worth it"]],
	["Build the mansion: the plot by the sea", ["That's what I'm talking about!", "Every heist gets bigger. Put it in the mansion by the sea: that's your safehouse",
		"Collect the cars, build the place up. This town's yours"]],
	["", ["Look at you. This is your town now. Ride out"]],
]

var game: Node
var step := 0
var _t := 0.0
var _flag_shop := false
var _seen_foot := false       # (you start stood by the car: getting in counts once you've been out of it)

func setup(g: Node) -> void:
	game = g
	if not game.save.data.has("story"):
		# an old save: pick up where they are (no welcome for someone who's played)
		step = 0 if _fresh() else _catch_up()
		game.save.data["story"] = step
	step = int(game.save.data["story"])

func _fresh() -> bool:
	var s: Dictionary = game.save.data
	return int(s.get("coins", 0)) <= 0 and (s.get("medals", {}) as Dictionary).is_empty() and game.save.stat("distance") < 500.0

func _catch_up() -> int:
	var k := 1
	while k < STEPS.size() - 1 and _done(k):
		k += 1
	return k

func goal() -> String:
	return String(STEPS[clampi(step, 0, STEPS.size() - 1)][0])

func shop_visited() -> void:
	_flag_shop = true

## Has the goal of this step been met?
func _done(k: int) -> bool:
	var s = game.save
	var lv: int = Progress.level(s)
	match k:
		0:
			return _seen_foot and not game.on_foot
		1:
			return s.stat("races") > 0 or not (s.data.get("medals", {}) as Dictionary).is_empty()
		2:
			return _flag_shop or (s.data.get("owned", []) as Array).size() > 1 or (s.data.get("guns", ["pistol"]) as Array).size() > 1
		3:
			return lv >= 3
		4:
			return int((s.data.get("property", {}) as Dictionary).get("garage", 0)) > 0
		5:
			return lv >= Progress.HEIST_LEVEL
		6:
			return s.stat("heists") > 0
		7:
			return game.property.finished("mansion")
	return false

func tick(dt: float) -> void:
	if game.on_foot:
		_seen_foot = true
	if game.campaign.on:
		return                  # (story mode's running the goals and the texts)
	_t -= dt
	if _t > 0.0 or game.state != game.DRIVE or game.challenge_on():
		return
	_t = 0.5
	if step >= STEPS.size() - 1:
		return
	if _done(step):
		step += 1
		game.save.data["story"] = step
		game.save.save()
		if game.tutorial.active:
			return              # (the first ride's coach is talking: Jay's texts wait till it's over)
		_texts(step)
		game.ui.story_goal(goal())

## The first ride's coach is done (or skipped): Jay picks it up from wherever you've got to.
func tutorial_over() -> void:
	if game.campaign.on:
		game.campaign.tutorial_over()
		return
	_texts(step)
	game.ui.story_goal(goal())

## Jay's texts for a step, one after another.
func _texts(k: int) -> void:
	var lines: Array = STEPS[clampi(k, 0, STEPS.size() - 1)][1]
	var d := 0.6
	for l in lines:
		var ll := String(l)
		get_tree().create_timer(d, false).timeout.connect(func(): game.ui.text_msg(FRIEND, ll))
		d += 3.4

## The very start: the title card, then the first ride's coach (you're stood by the car).
func intro() -> void:
	game.ui.intro_card("LO-FI LIFE", "New in town")
	if not bool(game.save.data.get("tut", false)):
		if not game.tutorial.active:
			game.tutorial.start()        # (its first card comes once the title card's gone)
		return
	get_tree().create_timer(3.0, false).timeout.connect(func():
		_texts(0)
		game.ui.story_goal(goal()))

func begin() -> void:
	if game.tutorial.active:
		return
	if game.campaign.on:
		game.campaign._show_goal()
		return
	game.ui.story_goal(goal())
