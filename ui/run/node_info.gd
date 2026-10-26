extends RefCounted
## What the run map says about a node: its icon, colour, short name and the hover card text.
## Reads the run; never changes it.

const Styles := preload("res://ui/styles.gd")

const NEST_RED := Color("ff5fa2")
const DEPOT_GOLD := Color("d9b46a")

const ICON := {
	RunMap.SKIRMISH: "skirmish", RunMap.AMBUSH: "ambush", RunMap.NEST: "nest", RunMap.EVENT: "event",
	RunMap.DEPOT: "depot", RunMap.HOSPITAL: "hospital", RunMap.SURVIVORS: "survivors", RunMap.ARMORY: "armory",
	RunMap.BOSS: "boss", RunMap.UNKNOWN: "unknown",
}
const SHORT := {
	RunMap.SKIRMISH: "Skirmish", RunMap.AMBUSH: "Ambush", RunMap.NEST: "Nest", RunMap.EVENT: "Event",
	RunMap.DEPOT: "Depot", RunMap.HOSPITAL: "Hospital", RunMap.SURVIVORS: "Survivors", RunMap.ARMORY: "Cache",
	RunMap.BOSS: "Boss", RunMap.UNKNOWN: "Unknown",
}
const OBJECTIVE_NAMES := {"skirmish": "Clear", "extract": "Extract", "hold": "Hold", "rescue": "Rescue", "purge": "Purge", "boss": "Boss",
	"escort": "Escort", "demolish": "Sabotage", "hack": "Hack", "samples": "Samples"}
const OBJECTIVE_TEXT := {
	"skirmish": "Kill every enemy.",
	"extract": "Get everyone to the evac zone.",
	"hold": "Hold the beacon for %d turns. Don't leave it to the enemy two rounds running." % 4,
	"rescue": "Escort the civilians to the drop zone.",
	"purge": "Destroy the spore nests.",
	"escort": "Walk the courier to the evac zone. It only moves while a soldier is close.",
	"demolish": "Stand on each charge site to arm it, then get clear. All must blow within 10 rounds.",
	"hack": "Hold a relay for 2 turns to hack it. Hack 2 of the 3 before the enemy wrecks them.",
	"samples": "Pick up samples and carry 2 of the 3 back to the drop zone.",
	"boss": "Kill the boss.",
}
## Legend order, as shown under the map.
const LEGEND: Array[String] = [RunMap.SKIRMISH, RunMap.NEST, RunMap.EVENT, RunMap.DEPOT, RunMap.HOSPITAL,
	RunMap.ARMORY, RunMap.SURVIVORS, RunMap.UNKNOWN, RunMap.BOSS]


static func icon(type: String) -> String:
	return ICON.get(type, "dot")


static func color(type: String) -> Color:
	match type:
		RunMap.NEST, RunMap.BOSS, RunMap.AMBUSH: return NEST_RED
		RunMap.DEPOT: return DEPOT_GOLD
		RunMap.HOSPITAL: return Styles.HP
		RunMap.ARMORY: return DEPOT_GOLD
	return Styles.TEXT


static func short_name(type: String) -> String:
	return SHORT.get(type, type.capitalize())


## "Skirmish · Hold" style title.
static func title(n: Dictionary) -> String:
	var type := RunMap.shown_type(n)
	var t: String = RunMap.NAMES.get(type, type)
	if n.objective != "" and type != RunMap.UNKNOWN and type != RunMap.BOSS:
		t += " · " + OBJECTIVE_NAMES.get(n.objective, n.objective)
	return t


static func boss_name(run: RunState) -> String:
	var pv: Dictionary = RunHooks.call_static("FightBuilder", "preview", [{"act": run.act, "node": RunMap.BOSS, "seed": 1}], {})
	return pv.get("title", "The boss")


## Hover card contents: {title, tag, tag_color, body, rows: [[label, text, colour]]}.
static func card(run: RunState, n: Dictionary) -> Dictionary:
	var type := RunMap.shown_type(n)
	var c := {"title": RunMap.NAMES.get(type, type), "tag": "", "tag_color": Styles.DIM, "body": "", "rows": []}
	var obj: String = OBJECTIVE_TEXT.get(n.objective, "")
	match type:
		RunMap.SKIRMISH, RunMap.AMBUSH:
			c.tag = "Fight"
			c.body = ("Enemies are alerted and strike first. " if type == RunMap.AMBUSH else "") + obj
			c.rows.append(["Reward", "+%d Supplies, a gear pick each" % RunRules.INCOME[type].supplies, Styles.TEXT])
		RunMap.NEST:
			c.tag = "Elite"
			c.tag_color = NEST_RED
			var pv: Dictionary = RunHooks.call_static("FightBuilder", "preview", [{"act": run.act, "row": n.row, "node": type, "objective": n.objective, "seed": n.seed}], {})
			var elite: String = pv.get("elite", "")
			c.body = ("An elite %s guards the nest. " % UnitData.ENEMIES[elite].name if elite != "" and UnitData.ENEMIES.has(elite) else "") + obj
			c.rows.append(["Reward", "+%d Supplies, Serum, a better gear pick" % RunRules.INCOME[type].supplies, Styles.TEXT])
			c.rows.append(["Risk", "Heavy Infection pressure", Styles.TEAL])
		RunMap.BOSS:
			c.title = boss_name(run)
			c.tag = "Boss"
			c.tag_color = NEST_RED
			c.body = "End of act %d. Kill the boss to push deeper." % run.act
			c.rows.append(["Reward", "+%d Supplies, Serum, a Doctrine" % RunRules.INCOME[type].supplies, Styles.TEXT])
		RunMap.EVENT:
			c.tag = "Event"
			c.body = "Something happened here. A choice with a price, decided together."
		RunMap.DEPOT:
			c.tag = "Shop"
			c.tag_color = DEPOT_GOLD
			c.body = "Spend Supplies on gear, consumables, a Serum dose and one service."
			c.rows.append(["Supplies", "%d to spend" % run.supplies, Styles.TEXT])
		RunMap.HOSPITAL:
			c.tag = "Rest"
			c.tag_color = Styles.HP
			c.body = "One treatment per soldier: patch up, purge Infection, or train."
			c.rows.append(["Outbreak", "+1 more if anyone heals or purges", Styles.TEAL])
		RunMap.ARMORY:
			c.tag = "Guns"
			c.tag_color = DEPOT_GOLD
			c.body = "Every soldier takes a gun. Anyone still on the sidearm gets their class gun."
		RunMap.SURVIVORS:
			c.tag = "Recruit"
			c.body = "Survivors to bring home: a new soldier for someone's reserve."
			c.rows.append(["Reward", "+10 Supplies, a recruit", Styles.TEXT])
		RunMap.UNKNOWN:
			c.tag = "Hidden"
			c.body = "Most likely an event. Could be an ambush, a depot or survivors."
			c.rows.append(["Intel", "Spend 1 to reveal it (you have %d)" % run.intel, Styles.TEXT])
	c.rows.append(["Outbreak", arrival(run, n), Styles.TEAL])
	var back := push_back(run, n)
	if back != "":
		c.rows.append(["Push back", back, Styles.TEAL])
	return c


## What reaching a new Outbreak stage adds to fights, for the hover card.
const STAGE_ADDS: Array[String] = ["", "a spore patch in every fight", "reinforcements from turn 4",
	"elites in skirmishes", "every soldier starts at +10 Infection"]


## "+1 on arrival: 6, Rampant now (reinforcements from turn 4)" for a node in the next row; the
## plain "+1 on arrival" further ahead, where the number would be a guess.
static func arrival(run: RunState, n: Dictionary) -> String:
	if RunState.is_extra_row(run.act, n.row):
		return "No rise on arrival"
	if n.row != run.row + 1:
		return "+1 on arrival"
	var to := run.outbreak + 1
	var st := RunRules.outbreak_stage(to)
	if st == RunRules.outbreak_stage(run.outbreak):
		return "+1 on arrival: %d, %s" % [to, RunRules.OUTBREAK_NAMES[st]]
	return "+1 on arrival: %d, %s now (%s)" % [to, RunRules.OUTBREAK_NAMES[st], STAGE_ADDS[st]]


## How winning this fight lowers Outbreak (RunRules.fight_outbreak and the boss drop), or "".
static func push_back(run: RunState, n: Dictionary) -> String:
	var type := RunMap.shown_type(n)
	if type == RunMap.BOSS:
		return "-%d after the fight" % Severity.boss_outbreak_drop(run, RunRules.BOSS_OUTBREAK_DROP)
	if not type in [RunMap.SKIRMISH, RunMap.AMBUSH, RunMap.NEST]:
		return ""
	var parts: Array[String] = ["-%d for the bonus objective" % RunRules.BONUS_OUTBREAK_DROP]
	if type == RunMap.NEST:
		parts.append("-%d when the nest falls" % RunRules.NEST_OUTBREAK_DROP)
	if n.objective == "purge":
		parts.append("-%d for burning the spore nests" % RunRules.PURGE_OUTBREAK_DROP)
	return ", ".join(parts)
