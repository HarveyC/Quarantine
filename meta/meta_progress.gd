class_name MetaProgress
extends RefCounted
## Bridges a run and the profile: tallies what happens in the run (`run.tally`), works out the
## Field Data it pays, and folds a finished run into the profile's stats and run log.
##
## run.tally: {"fights": {kind: wins}, "boss_acts": [act, ...], "bonus": n, "dead": n, "turned": n,
##             "lost_fights": n (fights where someone died or Turned)}

## Field Data per fight won, by kind ("Economy and rewards"); the act 3 boss (the Source) pays SOURCE.
const FIELD_DATA := {"skirmish": 15, "ambush": 15, "nest": 25, "boss": 60}
const SOURCE := 120


static func tally(run) -> Dictionary:
	if not run.tally.has("fights"):
		run.tally.merge({"fights": {}, "boss_acts": [], "bonus": 0, "dead": 0, "turned": 0, "lost_fights": 0})
	return run.tally


## Called by RunRules._end_fight once the soldiers' fates are known.
static func on_fight_end(run, kind: String, won: bool, bonus: bool, dead: int, turned: int) -> void:
	var t := tally(run)
	t.dead += dead
	t.turned += turned
	if dead + turned > 0:
		t.lost_fights += 1
	if not won:
		return
	t.fights[kind] = int(t.fights.get(kind, 0)) + 1
	if kind == "boss":
		t.boss_acts.append(run.act)
	if bonus:
		t.bonus += 1


## Field Data the run has earned so far, Severity bonus included. Every player earns all of it.
static func field_data(run) -> int:
	var t := tally(run)
	var base := 0
	for kind in t.fights:
		if kind != "boss":
			base += int(FIELD_DATA.get(kind, FIELD_DATA.skirmish)) * int(t.fights[kind])
	for act in t.boss_acts:
		base += SOURCE if act >= RunState.ACTS else int(FIELD_DATA.boss)
	return roundi(base * Severity.field_data_mult(Severity.level(run)))


static func won(run) -> bool:
	return run.phase == RunState.Phase.ENDED and run.result == Types.Result.VICTORY


## One run log line, newest first in Profile.run_log().
static func history_entry(run, player: int) -> Dictionary:
	var t := tally(run)
	var classes: Array = []
	for r in run.soldiers:
		if r.owner == player and r.status != RunSoldier.RESERVE:
			classes.append(r.kind)
	var nests := int(t.fights.get("nest", 0))
	var fights := 0
	for k in t.fights:
		fights += int(t.fights[k])
	var e := {
		"time": int(Time.get_unix_time_from_system()), "seed": run.seed, "won": won(run),
		"act": run.act, "row": run.row, "severity": Severity.level(run), "players": run.players.size(),
		"classes": classes, "fights": fights, "nests": nests, "bosses": t.boss_acts.size(),
		"dead": t.dead, "turned": t.turned, "outbreak": run.outbreak, "field_data": field_data(run),
	}
	var story = run.get("story")
	if story is Dictionary and story.has("ending"):
		e["ending"] = story.ending
	return e


## Adds a finished run to the profile (stats, run log, Field Data, Severity unlock). Once per run.
static func fold_run(cf: ConfigFile, run, player: int) -> void:
	var e := history_entry(run, player)
	var add := func(key: String, n: int) -> void:
		cf.set_value("history", key, int(cf.get_value("history", key, 0)) + n)
	add.call("runs", 1)
	if e.won:
		add.call("wins", 1)
		var lvl: int = e.severity
		cf.set_value("history", "highest_severity", maxi(int(cf.get_value("history", "highest_severity", 0)), lvl))
		cf.set_value("field", "severity_max", clampi(maxi(int(cf.get_value("field", "severity_max", 0)), lvl + 1), 0, Severity.MAX))
	add.call("fights_won", e.fights)
	add.call("bosses_killed", e.bosses)
	add.call("nests_cleared", e.nests)
	add.call("soldiers_turned", e.turned)
	add.call("field_data_earned", e.field_data)
	cf.set_value("field", "data", int(cf.get_value("field", "data", 0)) + e.field_data)
	var log: Array = Array(cf.get_value("runs", "log", [])).duplicate(true)
	log.push_front(e)
	cf.set_value("runs", "log", log.slice(0, Profile.HISTORY_SIZE))
