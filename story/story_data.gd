class_name StoryData
extends RefCounted
## Every line of story text: briefings, act transitions, boss intros, endings, radio barks,
## Source whispers and lore logs. Text only, as data. Story and StoryDirector read it.
## Lines are short on purpose: scenes show one caption at a time over a staged shot.
##
## A scene line is [speaker, text]. Speakers: "OKAFOR" (Major Ines Okafor, Cordon Command, on the
## radio), "SOURCE" (the Source, teal), "HALE", "HALDEN-VOSS", "SQUAD" (a soldier of the squad,
## named at play time), "" (a plain caption). {wave}, {last_wave}, {name} are filled in.

const FIRST_WAVE := 7   # Lantern Company has sent six waves before the player's first run

## The briefing before act 1. "first" for the very first run, then one opener per last result.
const INTRO_OPENERS := {
	"first": [
		["OKAFOR", "Port Ardent fell in eleven days. The wall has held for two hundred."],
		["OKAFOR", "Everything past it belongs to the Bloom."],
	],
	"lost": [
		["OKAFOR", "Wave {last_wave} never came back. Their lanterns are still moving out there."],
	],
	"burn": [
		["OKAFOR", "Wave {last_wave} burned the Source. The drones already see regrowth."],
	],
	"sample": [
		["OKAFOR", "Halden-Voss got its sample. Their shuttle left this morning. Nobody told us where."],
	],
	"carry": [
		["OKAFOR", "Wave {last_wave}'s carrier is still down there, holding it shut. The Bore is quiet. Mostly."],
	],
}
const INTRO_ORDERS := [
	["OKAFOR", "You are Lantern Company. You carry the Bloom, so it lets you walk where it lives."],
	["OKAFOR", "Every power it gives you pulls you closer to the Source. Use them anyway."],
	["OKAFOR", "Through the breach, down the Bore. Burn the Source and come home."],
]

## Extra briefing lines before act 1 when a given boss waits at its end, so the first act names what
## is coming. Same shape as INTRO_ORDERS.
const INTRO_BY_BOSS := {
	"breaker": [["OKAFOR", "The wall crews' demolition rigs went quiet last week. One of them is moving again."]],
}

const ACT_SCENES := {
	2: {"title": "Act II · Port Ardent", "sub": "Downtown and the Halden-Voss labs", "stage": "port", "lines": [
		["OKAFOR", "You're past the wall. Port Ardent is ahead of you."],
		["OKAFOR", "Signal's breaking up. The labs... Halden-Voss knew... don't trust..."],
		["SQUAD", "Command's gone. We keep moving."],
	]},
	3: {"title": "Act III · The Bore", "sub": "Nine kilometres down", "stage": "bore", "lines": [
		["SQUAD", "No radio this deep. Just the glow."],
		["SOURCE", "You came."],
		["SOURCE", "Every one of you is already part of me. Come down."],
	]},
}
## An act's transition scene when a given boss waits at its end, same shape as ACT_SCENES (lines,
## title, sub, stage). It replaces the act's default scene, so the story foreshadows the boss.
## A new boss adds its entry here and in BOSS_SCENES; bosses without one use ACT_SCENES.
const ACT_SCENES_BY_BOSS := {
	"choir_prophet": {"title": "Act II · Port Ardent", "sub": "Every channel carries the same hymn", "stage": "port", "lines": [
		["SQUAD", "Every channel is playing the same hymn. Do not listen to it for long."],
		["SQUAD", "It sounds like someone we knew."],
		["", "The harbour speakers are on. Whatever is singing, it is singing to you."],
	]},
	"director": {"title": "Act II · Port Ardent", "sub": "Downtown and the Halden-Voss labs", "stage": "port", "lines": [
		["OKAFOR", "You're past the wall. Port Ardent's harbour lights are on."],
		["OKAFOR", "Nobody here turned them on. A Halden-Voss recovery team is on the docks. They are not here for the Infected."],
		["DIRECTOR", "Lantern Company. Your blood work is under contract. Stay exactly where you are."],
		["SQUAD", "Command's gone quiet. We keep moving."],
	]},
	"bore_engine": {"title": "Act III · The Bore", "sub": "Nine kilometres down", "stage": "bore", "lines": [
		["SQUAD", "No radio this deep. Just the glow."],
		["", "Something below is turning over. The whole shaft hums with it."],
		["SQUAD", "That is the drill. Somebody started it."],
		["SOURCE", "You came."],
	]},
	"lantern_echoes": {"title": "Act III · The Bore", "sub": "A hall of lanterns", "stage": "bore", "lines": [
		["SQUAD", "No radio this deep. Just the glow."],
		["SOURCE", "You came."],
		["SQUAD", "There are lanterns down here. Hundreds of them, still lit."],
	]},
}
## Act 3's second line when an earlier wave has reached the Source.
const SOURCE_REMEMBERS := ["SOURCE", "You came back. I remember the fire."]
## The Source's extra boss line when the last wave burned it.
const SOURCE_BURNED := ["SOURCE", "Last time, you burned me. I grew back."]

## What the Source says by aspect (SourceBoss.ASPECTS): in its boss intro, when the core opens
## ("open"), when a root grows back ("regrow") and when the shaft gives way ("collapse"). All are
## voiced (VoiceLines.templates).
const SOURCE_ASPECT_LINES := {
	"hunger": {"intro": ["SOURCE", "You carry so much of me already. Bring me the rest."],
		"open": "Closer. Let me hold what is already mine.",
		"collapse": "There is nothing left to hold you up."},
	"remembers": {"intro": ["SOURCE", "I kept every name. Listen, they are calling you."],
		"open": "Hear them? They remember you too.",
		"collapse": "Come down. They are waiting."},
	"regrown": {"intro": ["SOURCE", "You cannot burn what grows back."],
		"open": "Cut me down. I have done this before.",
		"regrow": "Again. I am not finished.",
		"collapse": "Roots are patient. So am I."},
}

const BOSS_SCENES := {
	"choir_prophet": {"title": "The Choir Prophet", "sub": "The hymn from the harbour", "lines": [
		["", "One voice. All of them are singing in time with it."],
		["PROPHET", "Come inside the circle. There is no one left outside to hurt you."],
		["PROPHET", "It is not a disease. It is a conversation. Stop shouting."],
	]},
	"brood_mother": {"title": "The Brood Mother", "sub": "She nests in the breach", "lines": [
		["OKAFOR", "That's what has been feeding on the camps."],
		["OKAFOR", "Break the egg sacs first. While they live, she can't be hurt."],
	]},
	"broker": {"title": "The Broker", "sub": "Harrow's biggest looter", "lines": [
		["SQUAD", "That's the Broker. He has been stripping the cordon dead for months."],
		["BROKER", "Whatever you carry, I have already priced it."],
		["BROKER", "Set it down and walk away. Or I take it from you."],
	]},
	"breaker": {"title": "The Breaker", "sub": "The wall engineers' rig", "lines": [
		["OKAFOR", "The wall rig is running again, and nobody is driving it."],
		["OKAFOR", "It flattens whatever is in its way. Don't stand behind anything you need."],
	]},
	"colonel_hale": {"title": "Colonel Hale", "sub": "Halden-Voss Recovery", "lines": [
		["HALE", "Lantern Company. You are carrying company property."],
		["HALE", "Stand down and we'll take you home. In jars."],
	]},
	"director": {"title": "The Director", "sub": "Halden-Voss Recovery", "lines": [
		["DIRECTOR", "I don't need all of you. I need one of you, breathing."],
		["DIRECTOR", "My team will do the lifting. Please don't make it hard."],
	]},
	"bore_engine": {"title": "The Bore Engine", "sub": "The drill that cut the shaft", "lines": [
		["", "The drill head wakes. The platform shudders under every boot."],
		["SQUAD", "Coolant lines. Three valves ring the shaft. Cut them and the core opens."],
		["SQUAD", "It won't stay open long. Be ready when it does."],
	]},
	"the_source": {"title": "The Source", "sub": "The bottom of the Bore", "lines": [
		["SOURCE", "I know all of your names."],
		["SOURCE", "Cut my roots, and then we will talk."],
	]},
	"lantern_echoes": {"title": "The Lantern Echoes", "sub": "The Wake, under the Bore", "lines": [
		["SOURCE", "I know all of your names."],
		["SQUAD", "That's our people. They're wearing our faces."],
		["SQUAD", "It's not hunting us. It's calling us by name."],
	]},
}
## Extra ending lines when the Lantern Echoes were the last fight, spoken after the ending's first
## line. The Echoes were the Source learning to say Lantern Company's names, so each ending reads
## them its own way.
const ENDING_AFTER_ECHOES := {
	"burn": ["", "Every lantern in the Wake goes out at once. Nobody says a name."],
	"sample": ["", "The sample hums in the case, very softly, in the voices of the dead."],
	"carry": ["SQUAD", "Those weren't traps. It's been practising how to talk to us."],
}

const ENDINGS := {
	"burn": {"title": "Burn it", "sub": "Cordon Command's order",
		"desc": "Set the charges and burn the Source. The colony gets a few quiet years.",
		"stage": "burn", "lines": [
			["SQUAD", "Charges set. Light it."],
			["OKAFOR", "We can see the fire from the wall. Come home, Lanterns."],
			["", "Eight days later, the drones over the Bore report regrowth."],
		]},
	"sample": {"title": "Deliver a sample", "sub": "The Halden-Voss contract",
		"desc": "Cut a living piece of the Source and hand it to Halden-Voss. They pay well.",
		"locked": "Needs contact with Halden-Voss this run (their field lab or a courier bag).",
		"stage": "sample", "lines": [
			["HALDEN-VOSS", "Sample secured. Your contracts are complete."],
			["SQUAD", "And the colony?"],
			["HALDEN-VOSS", "The colony was never the product."],
		]},
	"carry": {"title": "Carry it", "sub": "The true ending",
		"desc": "{name} takes the Source into themselves and seals the Bore from inside.",
		"locked_lore": "Recover every intel log to learn what the Source really wants.",
		"locked_soldier": "Needs a living soldier at Critical Infection.",
		"stage": "carry", "lines": [
			["", "{name} walks down into the light."],
			["SQUAD", "It isn't attacking us. It's been trying to talk."],
			["SQUAD", "Someone has to listen. Seal it behind me."],
			["", "The Bore closes from the inside. Across Harrow, the glow goes out one district at a time."],
		]},
}
const ENDING_ORDER: Array[String] = ["burn", "sample", "carry"]

## Run summary headline per ending, and for a lost run.
const SUMMARY_TITLES := {"burn": "The Source is burning", "sample": "Contract complete",
	"carry": "The Bore is sealed", "lost": "Lantern Company is lost"}

## Radio barks between nodes and in fights. Each key has a few variants; act 3 has no radio, so
## barks there come from the squad.
const BARKS := {
	"skirmish": ["Contacts ahead. Keep it tight.", "Infected in the street. Clear it and move on.",
		"Hostiles on thermals. Your call how you go in."],
	"ambush": ["Movement on every side. It's a trap.", "That was too quiet. Weapons up."],
	"nest": ["That's a nest. Burn it out before it spreads.", "Spore readings off the scale. That's a nest."],
	"event": ["Something up ahead. Eyes open.", "Picking up something strange. Go and look."],
	"depot": ["Supply drop at the depot. Take what you need.", "Depot's still stocked. Spend it before the Bloom does."],
	"hospital": ["Field hospital. Patch up while you can.", "Medical tent ahead. Get the wounded seen to."],
	"survivors": ["Civilians on thermals. Bring them home.", "Survivors. Alive, for now."],
	"boss": ["Big signature ahead. This is it.", "Whatever is holding this district, it's right there."],
	"dead": ["We lost {name}.", "{name} is down. They're not getting up."],
	"turned": ["{name} is gone. That isn't them any more.", "{name} turned. Don't hesitate."],
	"recruit": ["{name}, you're up.", "{name} is moving up to the line."],
	"outbreak": ["Outbreak is climbing. The Bloom is moving faster than you are.",
		"The glow is spreading behind you. Don't stop."],
	"contact": ["They've seen us.", "Contact. Here they come."],
	"echo": ["Contact. That's {name}, wave {wave}. They aren't ours any more.",
		"I know that one. {name}. Put them down gently."],
	"echo_laid": ["{name}'s tags recovered. Rest easy."],
	# Boss fights: "<boss>_<phase>" on a phase change, "<boss>_open" when its shield breaks.
	"brood_mother_open": ["Sacs are down. She's open. Hit her now.", "That's the last sac. Light her up."],
	"brood_mother_2": ["She's tunnelling! Watch the ground and get off the roofs.",
		"She's under you somewhere. Move when the ground cracks."],
	"brood_mother_3": ["She's lost it. No more sacs. Finish her.", "She's coming straight at you. Put her down."],
	# The Director: "director_open" when her snipers are down, then one line per phase.
	"director_open": ["Her snipers are down. She's exposed. Hit her now.", "That's the last post. She has no cover. Go."],
	"director_2": ["A second team is on the roofs. Clear them again, and watch who she marks.",
		"She's marked one of you. Break her sight lines and keep that soldier moving."],
	"director_3": ["She's calling the extraction. Kill the Collectors and keep everyone on their feet.",
		"Cages incoming. Don't let anyone stand pinned under one."],
	"breaker_2": ["Its plate is off. It's tearing the yard down on top of you.", "Plate's gone. Get off the high ground."],
	"breaker_3": ["It's stripped to the frame. Two runs at once, watch both lanes.", "No more plating, and it's fast. Keep moving."],
	"lore": ["Intel recovered."],
}
## Boss fight lines spoken by a soldier of the squad (act 3 has no radio), same keys as the boss lines
## in BARKS. They are mask babble at play time, so they need no recorded clips.
const SQUAD_BARKS := {
	"lantern_echoes_2": ["That's one of ours, getting back up.",
		"The Source took the body. Put it down before it spreads."],
	"lantern_echoes_3": ["That's the last of them. It's wearing someone's face.",
		"Only one left, and it knows every move we have."],
	"lantern_echoes_open": ["Nothing left to shield it. Hit it now."],
	"choir_prophet_2": ["He's fixed on someone. Break his line of sight or get them cleansed.", "That's a link on {name}'s head. Cut it before it lands."],
	"choir_prophet_3": ["The circle is closing. Find solid cover before the hymn peaks.", "Every third bar he stops singing and the whole room hurts. Hide, then hit him."],
	"bore_engine_2": ["Valve's gone! Get off that platform, it's dropping.", "One down. The deck won't hold where that valve was."],
	"bore_engine_open": ["Last valve! The core's open, hit it now!", "It's bare. Everything you've got, right now."],
	"bore_engine_sealed": ["It sealed again. Cut the valves before the next window.", "The core shut. Valves are growing back, go!"],
	"broker_2": ["He's taken your best kit and he's making for the gate. Hit him, he'll drop it.",
		"He's running with your gear. Cut him off before he reaches the gate."],
	"broker_3": ["He's torched what he carried. Finish him before he torches you.", "Cornered. He's burning everything. Put him down."],
}
## Colonel Hale's voice in his boss fight, by phase: on the company radio, then after the Bloom
## takes him (phase 2). Heard, not captioned.
const HALE_BARKS := {
	1: ["Suppress them. Nobody leaves.", "Recovery team, move up.", "Take the carriers alive. The rest is optional.",
		"Lantern Company. You are carrying company property.", "Keep them pinned. I want those samples intact."],
	2: ["Stand down. Stand down. Come home.", "It's warm down here. Why is it so warm.", "Company property. All of it. All of us."],
}
## The Director's voice in her boss fight, by phase (the company radio, cool and polite). Heard, not captioned.
const DIRECTOR_BARKS := {
	1: ["Hold your positions. Nobody touches the carriers.", "Posts, lock your lanes.", "Lantern Company. Please stay where you are.",
		"Collectors, the nearest one. Gently."],
	2: ["Mark the warm one. The most Infected, I want that one.", "Second team, take the roofs.", "You are making this harder than it is."],
	3: ["Extraction is called. Everyone clear the lane.", "Cage the marked carrier. Now.", "I only need one. One will do."],
}
## In act 2 Okafor's signal breaks up: words are dropped for "--".
const STATIC_EVERY := 4

## The Source speaks to a soldier who reaches Mutating or Critical. Only that soldier's player
## sees it.
const WHISPERS := {
	2: ["I can feel you, {name}.", "You're burning up, {name}. That's me.", "Use it. Use all of it."],
	3: ["Come down to me, {name}.", "They will burn you too, when this is over.", "You're nearly home."],
}

## Intel logs, in the order they are recovered across runs. The last one unlocks Carry it.
## A boss win recovers the next log; so does putting down an Echo.
const LORE := [
	{"id": "cordon_7", "title": "Cordon order 7", "from": "Cordon Command",
		"text": "Carriers are to be treated as expendable. Recovery of bodies is not required."},
	{"id": "survey_0419", "title": "Survey 0419", "from": "Halden-Voss, drilling",
		"text": "Core sample at 6.2 km shows organised fungal structures. Recommend continued drilling. Do not log this."},
	{"id": "seedstock", "title": "Seedstock memo", "from": "Halden-Voss, terraforming",
		"text": "Seedstock will fuse with any compatible network. There is no compatible network on Harrow. Approved."},
	{"id": "day_three", "title": "Day 3", "from": "A diary, Port Ardent",
		"text": "The glow came up the drains. The neighbours stood in the street, listening to something."},
	{"id": "rev_nine", "title": "Carrier strain, rev. 9", "from": "Dr. Lio Marr",
		"text": "The tamed strain is stable. We grew it from tissue taken at the bottom of the Bore."},
	{"id": "choir", "title": "Choir pamphlet", "from": "The Choir",
		"text": "It is not a disease. It is a conversation. Stop shouting."},
	{"id": "hale_log", "title": "Personal log", "from": "Colonel Hale",
		"text": "The board wants it alive. I lost forty men proving it can't be caged. They want it anyway."},
	{"id": "wave_three", "title": "Recovered audio", "from": "Wave 3",
		"text": "It said my daughter's name. How does it know her name?"},
	{"id": "marr_okafor", "title": "Marr to Okafor", "from": "Dr. Lio Marr",
		"text": "Every Carrier who turns walks down the Bore. Not to fight. To join."},
	{"id": "pattern", "title": "Lattice pulse analysis", "from": "Cordon signals",
		"text": "The pulses repeat at prime intervals. That isn't biology. That is a signal."},
	{"id": "unsent", "title": "Unsent", "from": "Major Ines Okafor",
		"text": "If we burn it again, it grows back again. I am running out of soldiers to send."},
	{"id": "contact", "title": "The last log", "from": "Dr. Lio Marr",
		"text": "It isn't attacking us. It is trying to make contact, and we keep sending it soldiers with guns. If one of ours could carry it, it might finally be heard."},
]
const CARRY_LORE := "contact"

## Events whose scenes involve Halden-Voss: visiting one this run unlocks Deliver a sample.
const HV_EVENTS: Array[String] = ["the_trial", "field_chapel"]


static func lore_entry(id: String) -> Dictionary:
	for e in LORE:
		if e.id == id:
			return e
	return {}


## `text` with {keys} from `vars` filled in.
static func fill(text: String, vars: Dictionary) -> String:
	var out := text
	for k in vars:
		out = out.replace("{%s}" % k, str(vars[k]))
	return out


## Drops every STATIC_EVERY-th word and trails the line off with "...": a radio signal breaking up.
static func garble(text: String, salt: int = 0) -> String:
	var out: PackedStringArray = []
	var words := text.split(" ")
	for i in words.size():
		if (i + salt) % STATIC_EVERY == STATIC_EVERY - 1 and words[i].length() > 2:
			if out.is_empty():
				out.append("...")
			elif not out[-1].ends_with("..."):
				out[-1] = out[-1].rstrip(".,!?") + "..."
			continue
		out.append(words[i])
	return " ".join(out)

