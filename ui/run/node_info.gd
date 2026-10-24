extends RefCounted
## What the run map says about a node: its icon, colour, short name and the hover card text.
## Reads the run; never changes it.

const Styles := preload("res://ui/styles.gd")

const NEST_RED := Color("ff5fa2")
const DEPOT_GOLD := Color("d9b46a")

const ICON := {
	RunMap.SKIRMISH: "skirmish", RunMap.AMBUSH: "ambush", RunMap.NEST: "nest", RunMap.EVENT: "event",
	RunMap.DEPOT: "depot", RunMap.HOSPITAL: "hospital", RunMap.SURVIVORS: "survivors",
	RunMap.BOSS: "boss", RunMap.UNKNOWN: "unknown",
}
const SHORT := {
	RunMap.SKIRMISH: "Skirmish", RunMap.AMBUSH: "Ambush", RunMap.NEST: "Nest", RunMap.EVENT: "Event",
	RunMap.DEPOT: "Depot", RunMap.HOSPITAL: "Hospital", RunMap.SURVIVORS: "Survivors",
	RunMap.BOSS: "Boss", RunMap.UNKNOWN: "Unknown",
}
const OBJECTIVE_NAMES := {"skirmish": "Clear", "extract": "Extract", "hold": "Hold", "rescue": "Rescue", "purge": "Purge", "boss": "Boss"}
const OBJECTIVE_TEXT := {
	"skirmish": "Kill every enemy.",
	"extract": "Get everyone to the evac zone.",
	"hold": "Hold the beacon for %d turns." % 4,
	"rescue": "Escort the civilians to the drop zone.",
	"purge": "Destroy the spore nests.",
	"boss": "Kill the boss.",
}
## Legend order, as shown under the map.
const LEGEND: Array[String] = [RunMap.SKIRMISH, RunMap.NEST, RunMap.EVENT, RunMap.DEPOT, RunMap.HOSPITAL,
	RunMap.SURVIVORS, RunMap.UNKNOWN, RunMap.BOSS]


static func icon(type: String) -> String:
	return ICON.get(type, "dot")


static func color(type: String) -> Color:
	match type:
		RunMap.NEST, RunMap.BOSS, RunMap.AMBUSH: return NEST_RED
		RunMap.DEPOT: return DEPOT_GOLD
		RunMap.HOSPITAL: return Styles.HP
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
			c.rows.append(["Outbreak", "-%d after the fight" % RunRules.BOSS_OUTBREAK_DROP, Styles.TEAL])
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
		RunMap.SURVIVORS:
			c.tag = "Recruit"
			c.body = "Survivors to bring home: a new soldier for someone's reserve."
			c.rows.append(["Reward", "+10 Supplies, a recruit", Styles.TEXT])
		RunMap.UNKNOWN:
			c.tag = "Hidden"
			c.body = "Most likely an event. Could be an ambush, a depot or survivors."
			c.rows.append(["Intel", "Spend 1 to reveal it (you have %d)" % run.intel, Styles.TEXT])
	c.rows.append(["Outbreak", "+1 when the squad arrives", Styles.TEAL])
	return c
