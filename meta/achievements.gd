class_name Achievements
extends RefCounted
## In-game achievements, kept on the profile ("achievements" section: id -> unix time).
## Store integrations (Steam) bind to this API: read `DEFS`, sync `unlocked()` on startup,
## register `on_unlocked(cb)` for new ones, and mirror `stats()`. Keep ids stable: Steam's API
## names are the ids in upper case.
##
## Run achievements are checked from Profile.record_run (every run action, on every peer) using
## run.tally; profile achievements (unlock collections) after a purchase.

## id -> {name, desc, icon (an Icons id)}. Order here is the display order.
const DEFS := {
	"first_win": {"name": "First blood", "desc": "Win a fight", "icon": "skirmish"},
	"brood_breaker": {"name": "Brood breaker", "desc": "Beat the act 1 boss", "icon": "boss"},
	"colonel_down": {"name": "Colonel down", "desc": "Beat the act 2 boss", "icon": "boss"},
	"source_sealed": {"name": "Source sealed", "desc": "Win a run", "icon": "flag"},
	"lone_lantern": {"name": "Lone lantern", "desc": "Win a solo run", "icon": "trooper"},
	"full_company": {"name": "Full company", "desc": "Win a 4-player run", "icon": "survivors"},
	"no_one_left": {"name": "No one left behind", "desc": "Win a run without losing a soldier", "icon": "medic"},
	"clean_blood": {"name": "Clean blood", "desc": "Win a run without anyone Turning", "icon": "serum"},
	"nest_burner": {"name": "Nest burner", "desc": "Clear 3 nests in one run", "icon": "nest"},
	"overachiever": {"name": "Overachiever", "desc": "Complete 5 bonus objectives in one run", "icon": "check"},
	"lost_to_bloom": {"name": "Lost to the Bloom", "desc": "Have a soldier Turn", "icon": "enemy"},
	"severity_5": {"name": "Rampant", "desc": "Win at Severity 5", "icon": "outbreak"},
	"severity_10": {"name": "Ground zero", "desc": "Win at Severity 10", "icon": "outbreak"},
	"veteran": {"name": "Veteran", "desc": "Finish 10 runs", "icon": "clock"},
	"researcher": {"name": "Field researcher", "desc": "Buy your first Field Data unlock", "icon": "intel"},
	"archivist": {"name": "Archivist", "desc": "Buy every Field Data unlock", "icon": "intel"},
}

static var _listeners: Array[Callable] = []


## cb(id: String) runs once each time an achievement is newly earned on this machine.
static func on_unlocked(cb: Callable) -> void:
	if not _listeners.has(cb):
		_listeners.append(cb)


static func is_unlocked(id: String) -> bool:
	return _cfg().has_section_key("achievements", id)


static func unlocked() -> Array[String]:
	var cf := _cfg()
	var out: Array[String] = []
	for id in DEFS:
		if cf.has_section_key("achievements", id):
			out.append(id)
	return out


## Lifetime int stats: runs, wins, fights_won, bosses_killed, nests_cleared, soldiers_turned,
## field_data_earned, highest_severity.
static func stats() -> Dictionary:
	return Profile.stats()


## Earns `id` if it isn't yet. Returns true if it was new.
static func unlock(id: String) -> bool:
	if not DEFS.has(id):
		return false
	var cf := _cfg()
	if cf.has_section_key("achievements", id):
		return false
	cf.set_value("achievements", id, int(Time.get_unix_time_from_system()))
	cf.save(Profile.path)
	for cb in _listeners:
		if cb.is_valid():
			cb.call(id)
	return true


## Achievements a run (in progress or finished) has earned. Pure, for tests and the check below.
static func earned_by(run) -> Array[String]:
	var t := MetaProgress.tally(run)
	var out: Array[String] = []
	var fights := 0
	for k in t.fights:
		fights += int(t.fights[k])
	if fights > 0:
		out.append("first_win")
	if t.boss_acts.has(1):
		out.append("brood_breaker")
	if t.boss_acts.has(2):
		out.append("colonel_down")
	if int(t.fights.get("nest", 0)) >= 3:
		out.append("nest_burner")
	if int(t.bonus) >= 5:
		out.append("overachiever")
	if int(t.turned) > 0:
		out.append("lost_to_bloom")
	if MetaProgress.won(run):
		out.append("source_sealed")
		if run.players.size() == 1:
			out.append("lone_lantern")
		if run.players.size() >= 4:
			out.append("full_company")
		if int(t.dead) + int(t.turned) == 0:
			out.append("no_one_left")
		if int(t.turned) == 0:
			out.append("clean_blood")
		if Severity.level(run) >= 5:
			out.append("severity_5")
		if Severity.level(run) >= 10:
			out.append("severity_10")
	return out


static func check_run(run) -> void:
	for id in earned_by(run):
		unlock(id)
	check_profile()


## Profile-wide achievements (runs finished, unlocks bought).
static func check_profile() -> void:
	if Profile.stat("runs") >= 10:
		unlock("veteran")
	var have := Profile.packs()
	if not have.is_empty():
		unlock("researcher")
	if MetaUnlocks.PACKS.keys().all(func(id): return have.has(id)):
		unlock("archivist")


static func _cfg() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(Profile.path)
	return cf
