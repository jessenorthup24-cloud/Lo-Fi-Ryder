extends RefCounted
## The story of Lo-Fi Life, mission by mission: you come off the ferry with nothing, and by the end the
## island's yours. Seven chapters, thirty-eight missions, built on everything there is to do: the races, the
## drift zones, Mo's fights, the safes, the banks, Main Street, the garage and the mansion. campaign.gd runs it;
## cutscene.gd plays the scenes.
##
## A mission: {id, ch (chapter, 1-7), title, giver, start, intro (a scene), steps, outro (lines), pay}
##   start: "auto" (straight after the last one), "call" (the giver rings you a little later), or an anchor
##          (a gold beacon there: drive or walk in and start it).
##   steps: [type, args..., the objective as it shows]; done one after another:
##     goto anchor r · race id best_place · zone id score · trial id medal · fight id · heist n · bank $ ·
##     upgrade n · buy_car · buy_gun · property id stage · escape heat · wanted heat · cash $ · pay $ anchor ·
##     tutorial · scene key
## Anchors: "place:<name>", "race:<id>", "zone:<id>", "trial:<id>", "fight:<id>", "door:<shop>", "bank:<id>",
##   "plot:<id>", "safehouse", "you", "xyz:x,y,z".
## A scene: {shots: [{at, cam, dur, title, lines, actors, clear}]}
##   cam: ["orbit", radius, height, from°, to°] · ["fly", from height, to height, distance] ·
##        ["dolly", [from offset], [to offset], [look offset]]  (offsets from the anchor, metres)
##   actors: [who, [x, z] from the anchor, facing ("cam", "you", or degrees), anim]
##   lines: [speaker, line] (speaker "" for a caption)

## Who's who: their look (an avatar id), and the colour of their name in the subtitles.
const CAST := {
	"Jay": {"look": "male_casual2@02_C", "col": Color("7fd6ff")},
	"Ivy": {"look": "women_fitness@04_B", "col": Color("ff8bd1")},
	"Mo": {"look": "male_t_shirt@02_A", "col": Color("ffb347")},
	"Dez": {"look": "male_casual1@04_C", "col": Color("9be37a")},
	"Rook": {"look": "male_casual1@01_C", "col": Color("ff6b6b")},
	"Holloway": {"look": "cop@01_A", "col": Color("8fa8ff")},
	"Crane": {"look": "businessman_suit@03_A", "col": Color("e8d27a")},
	"King Lo": {"look": "businessman_shirt", "col": Color("ffd23f")},
	"Radio": {"look": "", "col": Color("c0c0c8")},
}

const CHAPTERS := [
	["Off the Ferry", "New in town, with a borrowed car and nothing in the bank"],
	["The Scene", "Every night the island races. Time to get noticed"],
	["Hands", "Some debts get settled with fists"],
	["Heat", "The law here has a price. So does everything else"],
	["Moving Up", "Roots, wheels, and a reputation"],
	["The Crane", "One man owns this island. He's noticed you"],
	["Run the Island", "Take it all"],
]

## What each chapter opens up (on a fresh story: an old save has it all already).
const OPENS := {
	1: ["race:downtown", "shop:customs", "zones"],
	2: ["race:northloop", "race:beachloop", "trials", "shop:threads"],
	3: ["fights:1"],
	4: ["heists", "shop:armory"],
	5: ["race:raceway", "property:garage", "fights:2", "dez"],
	6: ["race:ringroad", "fights:3"],
	7: ["race:cliffside", "race:eastpoint", "race:southshore", "property:mansion", "fights:4"],
}
## Which fighters are on at which chapter (fights:1 opens the first three, and so on).
const FIGHT_TIER := {"dre": 1, "tuna": 1, "kiko": 1, "deacon": 2, "marco": 2, "sasha": 3, "hammer": 3, "king": 4}

const MISSIONS := [
	# ---------------------------------------------------------------- 1. OFF THE FERRY
	{"id": "arrival", "ch": 1, "title": "Welcome to the Island", "giver": "Jay", "start": "auto",
		"intro": {"shots": [
			{"at": "place:Castle Hill", "cam": ["fly", 160, 90, 220], "dur": 4.5, "title": ["LO-FI LIFE", ""]},
			{"at": "place:Downtown", "cam": ["fly", 110, 55, 140], "dur": 4.0, "title": ["DOWNTOWN", "Glass, neon, and nobody sleeps"]},
			{"at": "place:Sunny Bay", "cam": ["orbit", 120, 40, 200, 250], "dur": 4.0, "title": ["SUNNY BAY", "Where the money comes to tan"]},
			{"at": "place:Old Harbour", "cam": ["orbit", 70, 22, 300, 345], "dur": 4.5, "title": ["OLD HARBOUR", "The ferry comes in at dusk"],
				"lines": [["", "Three years away. One bag, no plan, and an old friend waiting."]]},
			{"at": "you", "cam": ["dolly", [5, 2.2, 6], [3, 1.7, 3.5], [0, 1.2, 0]], "dur": 3.0,
				"actors": [["Jay", [1.6, 1.2], "you", "wave"]],
				"lines": [["Jay", "Look who finally came home!"], ["Jay", "Island's changed. Rent's up, the races pay, and everybody's hustling."],
					["Jay", "That old Bug's yours. Not pretty, but she runs. Let's see if you still can."]]},
		]},
		"steps": [["tutorial", "Learn the ropes with Jay"]],
		"outro": [["Jay", "Still got it. Now let's get you some money."]], "pay": 200},
	{"id": "first_taste", "ch": 1, "title": "First Taste", "giver": "Jay", "start": "race:downtown",
		"intro": {"shots": [
			{"at": "race:downtown", "cam": ["orbit", 14, 4, 20, 80], "dur": 3.5, "title": ["THE DOWNTOWN LOOP", "Three laps of the blocks. Everybody starts here"],
				"actors": [["Jay", [2.5, -1.5], "cam", "talk"]],
				"lines": [["Jay", "Downtown Loop. Seven drivers, three laps, streets closed."], ["Jay", "Get on the podium and you'll walk away with real cash."]]},
		]},
		"steps": [["race", "downtown", 3, "Finish the Downtown Loop on the podium"]],
		"outro": [["Jay", "Podium on your first night? People are gonna talk."]], "pay": 400},
	{"id": "bank_on_it", "ch": 1, "title": "Bank on It", "giver": "Jay", "start": "call",
		"intro": {"shots": [
			{"at": "bank:bank_main", "cam": ["orbit", 26, 9, 160, 210], "dur": 3.5, "title": ["LO-FI BANK", "Three branches, ATMs all over"],
				"lines": [["Jay", "Rule one on this island: never carry what you can't afford to lose."],
					["Jay", "You go down with cash in your pocket, it's on the ground for anyone. Bank it."]]},
		]},
		"steps": [["bank", 300, "Bank at least $300 at an ATM or a bank"]],
		"outro": [["Jay", "Good. Banked is safe. Pocket money's anybody's."]], "pay": 150},
	{"id": "fill_up", "ch": 1, "title": "Running on Fumes", "giver": "Jay", "start": "call",
		"intro": {"shots": [
			{"at": "you", "cam": ["orbit", 7, 2.2, 30, 70], "dur": 3.0,
				"lines": [["Jay", "That Bug drinks like a sailor and rattles like one."], ["Jay", "Fill her up and get her fixed at a gas station. Coast Road's close."]]},
		]},
		"steps": [["goto", "place:Old Harbour", 400.0, "Head west to Coast Road"], ["goto", "station:Coast Road", 9.0, "Pull onto the pad at the Coast Road gas station"]],
		"outro": [["Jay", "Listen to that. Purring. Kind of."]], "pay": 100},
	{"id": "main_street", "ch": 1, "title": "Main Street", "giver": "Jay", "start": "call",
		"intro": {"shots": [
			{"at": "door:customs", "cam": ["fly", 60, 22, 70], "dur": 4.0, "title": ["MAIN STREET", "Cars, guns and threads. Cash only"],
				"lines": [["Jay", "Lo-Fi Customs. Engines, turbos, tyres, paint. Every car on the island goes through there."],
					["Jay", "Put some of that race money into the Bug. You'll need it where we're going."]]},
		]},
		"steps": [["goto", "door:customs", 8.0, "Go to Lo-Fi Customs"], ["upgrade", 1, "Buy any upgrade at Customs"]],
		"outro": [["Jay", "Now we're talking. Somebody wants to meet you, by the way."]], "pay": 300},
	# ---------------------------------------------------------------- 2. THE SCENE
	{"id": "ivy", "ch": 2, "title": "The Bowl", "giver": "Ivy", "start": "zone:bowl",
		"intro": {"shots": [
			{"at": "place:The Drift Bowl", "cam": ["fly", 80, 30, 90], "dur": 4.0, "title": ["THE DRIFT BOWL", "Concrete, tyre smoke, and an audience"]},
			{"at": "zone:bowl", "cam": ["dolly", [6, 2, 5], [3.5, 1.7, 3], [0, 1.3, 0]], "dur": 3.0,
				"actors": [["Ivy", [1.5, 1.0], "you", "talk"]],
				"lines": [["Ivy", "So you're Jay's mystery driver. He said you were good."], ["Ivy", "Everybody's good on a straight. But that Bug grips, it won't slide."],
					["Ivy", "Get yourself a real drift car. Customs has a Pop-Up 86. Then show me in the Bowl."]]},
		]},
		"steps": [["buy_drift", "Get a drift car at Lo-Fi Customs (the Pop-Up 86 is the cheapest)"], ["drive_drift", "Drive your drift car to the Drift Bowl"],
			["zone", "bowl", 6000, "Score 6,000 in the Drift Bowl"]],
		"outro": [["Ivy", "Okay. Okay! You can slide. Keep your phone on."]], "pay": 500},
	{"id": "night_moves", "ch": 2, "title": "Night Moves", "giver": "Ivy", "start": "race:northloop",
		"intro": {"shots": [
			{"at": "race:northloop", "cam": ["orbit", 16, 4, 300, 350], "dur": 3.5, "title": ["THE NORTHERN LOOP", "Main Street out east, then the ring road round the north"],
				"actors": [["Ivy", [2.0, -2.0], "cam", "lean"]],
				"lines": [["Ivy", "The Northern Loop sorts the tourists from the drivers."], ["Ivy", "Top three and I'll introduce you to the real scene."]]},
		]},
		"steps": [["race", "northloop", 3, "Finish the Northern Loop on the podium"]],
		"outro": [["Ivy", "That's the one. Tomorrow night, Sunny Bay. Somebody's been asking about you."]], "pay": 700},
	{"id": "saltline", "ch": 2, "title": "Saltline", "giver": "Ivy", "start": "race:beachloop",
		"intro": {"shots": [
			{"at": "place:Sunny Bay", "cam": ["orbit", 90, 30, 160, 210], "dur": 3.5, "title": ["SUNNY BAY", "The beach front, the bars, the Saltline crew"]},
			{"at": "race:beachloop", "cam": ["dolly", [7, 2.2, 4], [4, 1.8, 2], [0, 1.4, 0]], "dur": 4.0,
				"actors": [["Rook", [1.8, 0.8], "you", "talk"], ["Ivy", [-1.6, 1.2], "you", "idle"]],
				"lines": [["Rook", "This is the one? Jay's charity case in a rust bucket?"], ["Ivy", "Rook runs the Saltline crew. Thinks the Beach Loop's his living room."],
					["Rook", "Make the podium on the Beach Loop and I'll learn your name. Miss it, and you never come back to this beach."]]},
		]},
		"steps": [["race", "beachloop", 3, "Beat Rook: finish the Beach Loop on the podium"]],
		"outro": [["Ivy", "You just embarrassed Rook in front of his whole crew. I love it. He won't."]], "pay": 900},
	{"id": "stunt_work", "ch": 2, "title": "Stunt Work", "giver": "Ivy", "start": "zone:stunt",
		"intro": {"shots": [
			{"at": "place:Stunt Yard", "cam": ["fly", 70, 28, 80], "dur": 4.0, "title": ["THE STUNT YARD", "Loops, kickers and half-pipes on the meadow"],
				"lines": [["Ivy", "Sponsors pay for footage. Flips, rolls, big air."], ["Ivy", "Give me a jam worth filming and I'll get you paid."]]},
		]},
		"steps": [["zone", "stunt", 4000, "Score 4,000 in the Stunt Yard jam"]],
		"outro": [["Ivy", "That's going straight on every phone on the island."]], "pay": 600},
	{"id": "look_the_part", "ch": 2, "title": "Look the Part", "giver": "Ivy", "start": "call",
		"intro": {"shots": [
			{"at": "door:threads", "cam": ["orbit", 14, 4, 140, 190], "dur": 3.5, "title": ["LO-FI THREADS", "New look, new you"],
				"lines": [["Ivy", "You're famous now. Sort of. Dress like it."], ["Ivy", "Threads on Main Street. Pick something that says you."]]},
		]},
		"steps": [["goto", "door:threads", 8.0, "Visit Lo-Fi Threads"]],
		"outro": [["Jay", "Heard you're Ivy's new project. Careful. And call Mo back, he's been asking."]], "pay": 300},
	# ---------------------------------------------------------------- 3. HANDS
	{"id": "mo", "ch": 3, "title": "Mo", "giver": "Mo", "start": "fight:dre",
		"intro": {"shots": [
			{"at": "fight:dre", "cam": ["fly", 60, 24, 70], "dur": 3.5, "title": ["STREET FIGHTS", "Mo's card. Cash purses, no rules"]},
			{"at": "fight:dre", "cam": ["dolly", [5, 2, 5], [3, 1.7, 3], [0, 1.4, 0]], "dur": 4.0,
				"actors": [["Mo", [1.6, 1.0], "you", "talk"]],
				"lines": [["Mo", "Jay's friend. The driver. You know what this island really bets on?"], ["Mo", "Fists. Street fights, cash purses, I set the odds."],
					["Mo", "Dre's first. Loud, fast hands, glass jaw. Win, and you're on my card."]]},
		]},
		"steps": [["fight", "dre", "Win your street fight against Dre"]],
		"outro": [["Mo", "Ha! Paper Hands folded. You and me are gonna make money."]], "pay": 500},
	{"id": "big_tuna", "ch": 3, "title": "Big Tuna", "giver": "Mo", "start": "fight:tuna",
		"intro": {"shots": [
			{"at": "fight:tuna", "cam": ["orbit", 8, 2.4, 200, 250], "dur": 3.5,
				"actors": [["Mo", [-1.8, 1.2], "you", "talk"]],
				"lines": [["Mo", "Tony Baptiste. Big Tuna. Hits like a dock crane, moves like one too."], ["Mo", "Don't trade with him. Block, wait, punish."]]},
		]},
		"steps": [["fight", "tuna", "Beat Big Tuna"]],
		"outro": [["Mo", "The harbour boys are still picking their jaws up."]], "pay": 700},
	{"id": "kiko", "ch": 3, "title": "Viral", "giver": "Mo", "start": "fight:kiko",
		"intro": {"shots": [
			{"at": "fight:kiko", "cam": ["orbit", 8, 2.4, 20, 70], "dur": 3.5,
				"actors": [["Mo", [1.8, 1.4], "you", "talk"]],
				"lines": [["Mo", "Kiko Reyes. Half a million followers and the quickest feet on the island."], ["Mo", "She'll make you look slow. Don't chase. Make her come to you."]]},
		]},
		"steps": [["fight", "kiko", "Beat Kiko"]],
		"outro": [["Mo", "You know who's watching now? The man who owns the card I'm on."]], "pay": 900},
	{"id": "word", "ch": 3, "title": "Word on the Street", "giver": "Mo", "start": "call",
		"intro": {"shots": [
			{"at": "you", "cam": ["orbit", 7, 2.2, 90, 130], "dur": 3.5,
				"lines": [["Mo", "Every purse on this island comes from one place. Crane Marine, down the harbour."],
					["Mo", "Victor Crane. Owns the docks, half the cops, and King Lo, the best fighter alive."], ["Mo", "Go take a look. Quietly."]]},
		]},
		"steps": [["goto", "place:Old Harbour", 40.0, "Take a look at Old Harbour"], ["scene", "crane_yard"]],
		"outro": [["Jay", "Crane? Stay away from that man. I mean it."]], "pay": 400},
	# ---------------------------------------------------------------- 4. HEAT
	{"id": "holloway", "ch": 4, "title": "Sergeant Holloway", "giver": "Holloway", "start": "place:Town Square",
		"intro": {"shots": [
			{"at": "place:Town Square", "cam": ["orbit", 12, 3.5, 60, 110], "dur": 4.0, "title": ["TOWN SQUARE", "The heart of town. Mostly"],
				"actors": [["Holloway", [1.8, 0.8], "you", "talk"]],
				"lines": [["Holloway", "Sergeant Holloway. You've been busy. Racing, brawling, scaring the tourists."],
					["Holloway", "Here's how it works. A thousand a week and I never heard of you."],
					["Holloway", "Pay up. Town Square. I'll be waiting."]]},
		]},
		"steps": [["pay", 1000, "place:Town Square", "Bring Holloway $1,000 (have it on you at Town Square)"], ["scene", "holloway_setup"],
			["escape", 1, "He set you up: lose the police"]],
		"outro": [["Jay", "He took your money AND called it in? Welcome to the island, man."]], "pay": 800},
	{"id": "armory", "ch": 4, "title": "Protection", "giver": "Dez", "start": "door:armory",
		"intro": {"shots": [
			{"at": "door:armory", "cam": ["orbit", 12, 3.5, 200, 250], "dur": 3.5, "title": ["THE ARMORY", "No questions. Cash only"],
				"actors": [["Dez", [2.0, 1.0], "you", "talk"]],
				"lines": [["Dez", "Dez. Jay's cousin, sort of. I get things to people."], ["Dez", "With cops like Holloway, you want something on your hip. Armory's open."]]},
		]},
		"steps": [["buy_gun", "Buy a gun at the Armory"]],
		"outro": [["Dez", "Pick it off the wheel by the map. And don't wave it at people, they run."]], "pay": 500},
	{"id": "first_safe", "ch": 4, "title": "The First Safe", "giver": "Jay", "start": "call",
		"intro": {"shots": [
			{"at": "safehouse", "cam": ["orbit", 14, 4, 120, 170], "dur": 4.0, "title": ["THE SAFEHOUSE", "Where the money goes to rest"],
				"actors": [["Jay", [1.8, 1.2], "you", "talk"]],
				"lines": [["Jay", "I said stay away from trouble. Holloway changed my mind."], ["Jay", "There's safes all over this island, cash from Crane's people. Find one, grab the drill, crack it, bring the bag here."],
					["Jay", "Bring the money home and we're square with this town."]]},
		]},
		"steps": [["heist", 1, "Crack a safe and get the money to the safehouse"]],
		"outro": [["Jay", "We did it. We actually did it. Don't spend it all at once."]], "pay": 1500},
	{"id": "clean_money", "ch": 4, "title": "Clean Money", "giver": "Jay", "start": "call",
		"intro": {"shots": [
			{"at": "bank:bank_main", "cam": ["fly", 50, 20, 50], "dur": 3.5,
				"lines": [["Jay", "That's a lot of cash to carry round with Holloway's boys about."], ["Jay", "Get five grand into the bank. Today."]]},
		]},
		"steps": [["bank", 5000, "Bank $5,000"]],
		"outro": [["Jay", "Now we've got something to build on."]], "pay": 1000},
	# ---------------------------------------------------------------- 5. MOVING UP
	{"id": "roots", "ch": 5, "title": "Roots", "giver": "Jay", "start": "plot:garage",
		"intro": {"shots": [
			{"at": "plot:garage", "cam": ["fly", 60, 20, 60], "dur": 4.0, "title": ["THE DIRT LOT", "South of town. Yours, if you build it"],
				"actors": [["Jay", [3.0, 2.0], "you", "talk"]],
				"lines": [["Jay", "Every crew needs a home. This lot's been empty since I was a kid."], ["Jay", "Put money in, stage by stage. A garage worth showing off."]]},
		]},
		"steps": [["property", "garage", 2, "Build the garage up to its foundation (stage 2)"]],
		"outro": [["Jay", "Foundation's in. It's a start."]], "pay": 800},
	{"id": "wheels", "ch": 5, "title": "New Wheels", "giver": "Dez", "start": "call",
		"intro": {"shots": [
			{"at": "door:customs", "cam": ["orbit", 14, 4, 300, 350], "dur": 3.5,
				"lines": [["Dez", "No offence, but the Bug's embarrassing you now."], ["Dez", "Customs has real cars. Buy one, and I'll bring it wherever you are."]]},
		]},
		"steps": [["buy_car", "Buy a new car at Lo-Fi Customs"]],
		"outro": [["Dez", "Now that's a car. Call me any time: I deliver."]], "pay": 1000},
	{"id": "grand_prix", "ch": 5, "title": "Grand Prix", "giver": "Ivy", "start": "race:raceway",
		"intro": {"shots": [
			{"at": "race:raceway", "cam": ["fly", 90, 30, 110], "dur": 4.0, "title": ["THE RACEWAY", "A real circuit. Real grandstands"],
				"lines": [["Ivy", "The Raceway Grand Prix. Proper circuit, proper crowd, proper money."], ["Ivy", "Rook's crew will be there. Podium, and the whole island knows your name."]]},
		]},
		"steps": [["race", "raceway", 3, "Finish the Raceway Grand Prix on the podium"]],
		"outro": [["Ivy", "Rook didn't even make the podium. He's furious. It's beautiful."]], "pay": 1500},
	{"id": "hot_lap", "ch": 5, "title": "Hot Lap", "giver": "Ivy", "start": "trial:hotlap",
		"intro": {"shots": [
			{"at": "trial:hotlap", "cam": ["orbit", 12, 3.5, 100, 150], "dur": 3.0,
				"lines": [["Ivy", "A sponsor wants a lap record. Just you and the clock."]]},
		]},
		"steps": [["trial", "hotlap", 1, "Set a medal time on the Raceway Hot Lap"]],
		"outro": [["Ivy", "Sponsor's happy. You're on a billboard now. Sort of."]], "pay": 800},
	{"id": "deacon", "ch": 5, "title": "The Deacon", "giver": "Mo", "start": "fight:deacon",
		"intro": {"shots": [
			{"at": "fight:deacon", "cam": ["orbit", 8, 2.4, 140, 190], "dur": 3.5,
				"actors": [["Mo", [1.8, 1.4], "you", "talk"]],
				"lines": [["Mo", "The Deacon. Quiet, patient, blocks everything. He'll wait you out."], ["Mo", "Wear him down. Make him spend his breath."]]},
		]},
		"steps": [["fight", "deacon", "Beat the Deacon"]],
		"outro": [["Mo", "Nobody's broken the Deacon's guard in two years."]], "pay": 1200},
	{"id": "marco", "ch": 5, "title": "Marco", "giver": "Mo", "start": "fight:marco",
		"intro": {"shots": [
			{"at": "fight:marco", "cam": ["orbit", 8, 2.4, 260, 310], "dur": 3.5,
				"actors": [["Mo", [-1.8, 1.4], "you", "talk"]],
				"lines": [["Mo", "Marco throws four-punch combos all night. Don't be there for them."], ["Mo", "Beat him and Crane's people come knocking. That's the plan."]]},
		]},
		"steps": [["fight", "marco", "Beat Marco"]],
		"outro": [["Mo", "There it is. Crane wants a meeting."]], "pay": 1400},
	# ---------------------------------------------------------------- 6. THE CRANE
	{"id": "offer", "ch": 6, "title": "An Offer", "giver": "Crane", "start": "place:Old Harbour",
		"intro": {"shots": [
			{"at": "place:Old Harbour", "cam": ["orbit", 40, 12, 20, 60], "dur": 3.5, "title": ["CRANE MARINE", "Old Harbour"]},
			{"at": "place:Old Harbour", "cam": ["dolly", [6, 2, 4], [3.5, 1.7, 2.5], [0, 1.5, 0]], "dur": 5.0,
				"actors": [["Crane", [1.8, 0.6], "you", "talk"], ["King Lo", [3.2, -0.8], "you", "idle"]],
				"lines": [["Crane", "So you're the one costing my fighters their purses. Sit. Have a drink."],
					["Crane", "The Ring Road Classic. Rook wins it. You finish well back, and you're on my payroll."],
					["Crane", "Or you don't. This is my island. Think carefully."]]},
		]},
		"steps": [["race", "ringroad", 3, "Ignore Crane: finish the Ring Road Classic on the podium"]],
		"outro": [["Ivy", "Podium? On Crane's race? Oh, you're in so much trouble."]], "pay": 2000},
	{"id": "consequences", "ch": 6, "title": "Consequences", "giver": "Holloway", "start": "call",
		"intro": {"shots": [
			{"at": "you", "cam": ["orbit", 8, 2.5, 200, 250], "dur": 3.5,
				"lines": [["Radio", "All units, all units. Suspect vehicle, armed and dangerous."], ["Holloway", "Mr Crane sends his regards."]]},
		]},
		"steps": [["wanted", 3, "Holloway's after you: survive it (3 stars)"], ["escape", 3, "Lose the police"]],
		"outro": [["Jay", "You lost them. All of them. Where did you learn to drive like that?"]], "pay": 2000},
	{"id": "sasha", "ch": 6, "title": "Sasha", "giver": "Mo", "start": "fight:sasha",
		"intro": {"shots": [
			{"at": "fight:sasha", "cam": ["orbit", 8, 2.4, 320, 370], "dur": 3.5,
				"actors": [["Mo", [1.8, -1.4], "you", "talk"]],
				"lines": [["Mo", "Sasha's kicks end fights. Long reach, heavy feet."], ["Mo", "Crane's betting against you now. Make him pay."]]},
		]},
		"steps": [["fight", "sasha", "Beat Sasha"]],
		"outro": [["Mo", "Crane just lost a fortune on you. He's not laughing."]], "pay": 1800},
	{"id": "hammer", "ch": 6, "title": "The Hammer", "giver": "Mo", "start": "fight:hammer",
		"intro": {"shots": [
			{"at": "fight:hammer", "cam": ["orbit", 9, 2.6, 60, 110], "dur": 3.5,
				"actors": [["Mo", [-2.0, 1.2], "you", "talk"]],
				"lines": [["Mo", "The Hammer. Biggest man on the island, hits like a truck."], ["Mo", "Get hit clean once and you're asleep. Don't get hit."]]},
		]},
		"steps": [["fight", "hammer", "Beat the Hammer"]],
		"outro": [["Mo", "Only one left. King Lo. Not yet. You're not ready, and Crane knows it."]], "pay": 2200},
	{"id": "bigger_fish", "ch": 6, "title": "Bigger Fish", "giver": "Jay", "start": "call",
		"intro": {"shots": [
			{"at": "safehouse", "cam": ["orbit", 14, 4, 220, 270], "dur": 3.5,
				"actors": [["Jay", [1.8, 1.0], "you", "talk"]],
				"lines": [["Jay", "Crane wants a war, he pays for it. Every one of those safes is his money."], ["Jay", "Two more. Get a crew if you can: call drivers you've swapped numbers with."]]},
		]},
		"steps": [["heist", 2, "Pull two more heists"]],
		"outro": [["Jay", "Crane's bleeding money. Watch your back."]], "pay": 3000},
	{"id": "jay_gone", "ch": 6, "title": "Jay", "giver": "Ivy", "start": "call",
		"intro": {"shots": [
			{"at": "you", "cam": ["orbit", 7, 2.2, 0, 40], "dur": 4.0,
				"lines": [["Ivy", "They took Jay. Holloway and four squad cars, at his shop."], ["Ivy", "Police yard, east of town. Go get him. I'll have the engine running."]]},
		]},
		"steps": [["goto", "plot:police_hq", 18.0, "Get to the police yard"], ["scene", "jay_free"], ["escape", 2, "Get Jay out: lose the police"]],
		"outro": [["Jay", "I owe you my life. And Crane owes us everything."]], "pay": 3000},
	# ---------------------------------------------------------------- 7. RUN THE ISLAND
	{"id": "home_by_sea", "ch": 7, "title": "Home by the Sea", "giver": "Jay", "start": "plot:mansion",
		"intro": {"shots": [
			{"at": "plot:mansion", "cam": ["fly", 70, 24, 70], "dur": 4.0, "title": ["THE PLOT BY THE SEA", "The best view on the island"],
				"actors": [["Jay", [3.0, 2.0], "you", "talk"]],
				"lines": [["Jay", "Crane's got the harbour. We'll have the coast."], ["Jay", "Build a mansion up here. Somewhere to plan the end of Victor Crane."]]},
		]},
		"steps": [["property", "mansion", 6, "Build the mansion up to its first floor (stage 6)"]],
		"outro": [["Jay", "Now that's a house. Ivy's got news."]], "pay": 3000},
	{"id": "cliffside", "ch": 7, "title": "Cliffside", "giver": "Ivy", "start": "race:cliffside",
		"intro": {"shots": [
			{"at": "race:cliffside", "cam": ["fly", 100, 35, 130], "dur": 4.0, "title": ["CLIFFSIDE CIRCUIT", "A headland off the west coast"],
				"lines": [["Ivy", "The Island Championship: three circuits, winner takes everything. Crane sponsors it."], ["Ivy", "Rook's his driver. Podium the first two, win the final, and Crane's name goes in the sea."]]},
		]},
		"steps": [["race", "cliffside", 3, "Podium at Cliffside Circuit"]],
		"outro": [["Ivy", "One down."]], "pay": 3000},
	{"id": "eastpoint", "ch": 7, "title": "Eastpoint", "giver": "Ivy", "start": "race:eastpoint",
		"intro": {"shots": [
			{"at": "race:eastpoint", "cam": ["fly", 100, 35, 130], "dur": 4.0, "title": ["EASTPOINT SPEEDWAY", "Fast, with a chicane that bites"],
				"lines": [["Rook", "Lucky once. Not twice."]]},
		]},
		"steps": [["race", "eastpoint", 3, "Podium at Eastpoint Speedway"]],
		"outro": [["Ivy", "Rook's crew is falling apart. One more."]], "pay": 3500},
	{"id": "southshore", "ch": 7, "title": "Southshore", "giver": "Ivy", "start": "race:southshore",
		"intro": {"shots": [
			{"at": "race:southshore", "cam": ["fly", 100, 35, 130], "dur": 4.0, "title": ["SOUTHSHORE CIRCUIT", "The final. The hairpin decides it"],
				"actors": [],
				"lines": [["Ivy", "This is it. Win this and the championship's yours."], ["Rook", "Crane says if I lose, I swim home."]]},
		]},
		"steps": [["race", "southshore", 1, "Win at Southshore Circuit"]],
		"outro": [["Rook", "...Fine. You're the best on this island. I'm done driving for Crane."]], "pay": 5000},
	{"id": "king", "ch": 7, "title": "The King", "giver": "Mo", "start": "fight:king",
		"intro": {"shots": [
			{"at": "fight:king", "cam": ["orbit", 9, 2.6, 180, 240], "dur": 5.0, "title": ["KING LO", "Undefeated"],
				"actors": [["Mo", [-2.0, 1.5], "you", "talk"]],
				"lines": [["Mo", "King Lo. Crane's champion. Never lost, never been knocked down."], ["Mo", "Everything's on this. Every bet on the island. Breathe, guard up, and take his crown."]]},
		]},
		"steps": [["fight", "king", "Beat King Lo"]],
		"outro": [["Mo", "THE KING IS DOWN! Crane just lost everything he bet. Everything!"]], "pay": 6000},
	{"id": "harbour_job", "ch": 7, "title": "The Harbour Job", "giver": "Jay", "start": "call",
		"intro": {"shots": [
			{"at": "place:Old Harbour", "cam": ["orbit", 60, 18, 90, 150], "dur": 4.0,
				"lines": [["Jay", "Crane's broke and scared. He's moving what's left through his safes tonight."], ["Jay", "One last job. Crack a safe, get it home, and bank every dollar you're carrying."]]},
		]},
		"steps": [["heist", 1, "Pull the last heist"], ["bank", 1, "Bank everything you're carrying"]],
		"outro": [["Jay", "That's it. Crane's done. But Holloway's not going quietly."]], "pay": 5000},
	{"id": "last_run", "ch": 7, "title": "Last Run", "giver": "Holloway", "start": "call",
		"intro": {"shots": [
			{"at": "you", "cam": ["orbit", 8, 2.5, 100, 150], "dur": 4.0,
				"lines": [["Holloway", "You ruined a good man, kid. Every car I've got is coming for you."], ["Radio", "All units. Shoot on sight."]]},
		]},
		"steps": [["wanted", 4, "Holloway's whole force is coming (4 stars)"], ["escape", 4, "Survive it: lose them"]],
		"outro": [["Radio", "...Holloway's badge has been suspended pending investigation. Repeat, suspended."]], "pay": 6000},
	{"id": "lofi_life", "ch": 7, "title": "Lo-Fi Life", "giver": "Jay", "start": "plot:mansion",
		"intro": {"shots": [
			{"at": "plot:mansion", "cam": ["orbit", 16, 4, 200, 260], "dur": 4.0,
				"actors": [["Jay", [1.8, 1.0], "you", "talk"], ["Ivy", [-1.6, 1.4], "you", "idle"], ["Mo", [0.4, 2.6], "you", "idle"], ["Dez", [-2.8, -0.4], "you", "idle"]],
				"lines": [["Jay", "Look at this. You came off that ferry with one bag."], ["Ivy", "Now you've got the fastest car, the best crew, and the whole island."],
					["Mo", "And no Crane."], ["Dez", "I'll get the drinks."]]},
			{"at": "place:Lighthouse Point", "cam": ["fly", 140, 70, 260], "dur": 5.0, "title": ["LO-FI LIFE", "The island's yours. Ride out."]},
		]},
		"steps": [],
		"outro": [["", "THE END · Everything's open. Keep playing: races, fights, safes, cars, the house."]], "pay": 10000},
]

## Scenes played in the middle of a mission (a "scene" step).
const SCENES := {
	"crane_yard": {"shots": [
		{"at": "place:Old Harbour", "cam": ["orbit", 30, 8, 120, 170], "dur": 4.0, "title": ["CRANE MARINE", "Nobody goes in. Nothing comes out"],
			"actors": [["King Lo", [3.0, 1.0], "you", "idle"]],
			"lines": [["", "A big man watches you from the dock gates. He doesn't blink."], ["King Lo", "Mr Crane says hello. Run along."]]},
	]},
	"holloway_setup": {"shots": [
		{"at": "you", "cam": ["orbit", 8, 2.5, 30, 80], "dur": 3.5,
			"actors": [["Holloway", [1.6, 1.0], "you", "talk"]],
			"lines": [["Holloway", "Pleasure doing business."], ["Holloway", "Oh, and dispatch? I've got a suspect at Town Square. Armed. Go get him."]]},
	]},
	"jay_free": {"shots": [
		{"at": "plot:police_hq", "cam": ["orbit", 16, 4, 60, 120], "dur": 4.0,
			"actors": [["Jay", [1.5, 0.8], "you", "wave"]],
			"lines": [["Jay", "I knew you'd come! Go, go, GO!"], ["Radio", "Prisoner escape, police yard. All units!"]]},
	]},
}
