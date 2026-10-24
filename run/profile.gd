class_name Profile
extends RefCounted
## The player's profile on this machine: unlock flags, Field Data and its unlocks, Severity, run
## history, lifetime stats and achievements, all carried between runs.
## Runs read a copy as `run.meta`. Modules unlock things by setting a true bool flag in `run.meta`
## (or `run.modifiers.unlocks`) during a run, e.g. Progression's "vector_unlocked"; the profile
## picks them up as the run goes. "act1_boss_beaten" is set by the framework.
## `meta()` also carries "packs" (owned Field Data unlocks, see MetaUnlocks) and "severity" (the
## level picked for the next run, see Severity).
##
## Sections: "meta" (unlock flags), "field" (Field Data balance, packs, Severity), "history"
## (lifetime stats), "runs" (recent run log), "achievements" (id -> unix time).

const SECTION := "meta"
const HISTORY_SIZE := 25
## Lifetime stats kept in "history" (Achievements.stats() exposes them).
const STATS: Array[String] = ["runs", "wins", "fights_won", "bosses_killed", "nests_cleared", "soldiers_turned",
	"field_data_earned", "highest_severity"]

## Tests point this somewhere else.
static var path := "user://profile.cfg"


static func _load() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(path)
	return cf


static func meta() -> Dictionary:
	var cf := _load()
	var out := {}
	if cf.has_section(SECTION):
		for k in cf.get_section_keys(SECTION):
			out[k] = cf.get_value(SECTION, k)
	out["packs"] = packs()
	out["severity"] = severity()
	out["story"] = RunHooks.call_static("StoryProfile", "snapshot", [], {})
	return out


# --- Field Data and unlocks ------------------------------------------------------------

static func field_data() -> int:
	return int(_load().get_value("field", "data", 0))


static func packs() -> Array:
	return Array(_load().get_value("field", "packs", [])).duplicate()


## Buys a Field Data unlock. Returns "" on success, otherwise why not.
static func buy(id: String) -> String:
	var cf := _load()
	var have: Array = cf.get_value("field", "packs", [])
	var fd := int(cf.get_value("field", "data", 0))
	var err := MetaUnlocks.can_buy(have, fd, id)
	if err != "":
		return err
	have = have.duplicate()
	have.append(id)
	cf.set_value("field", "packs", have)
	cf.set_value("field", "data", fd - int(MetaUnlocks.PACKS[id].cost))
	cf.save(path)
	Achievements.check_profile()
	return ""


# --- Severity -----------------------------------------------------------------------------

## Highest Severity this profile may pick (beating the Source at N unlocks N+1).
static func severity_max() -> int:
	return clampi(int(_load().get_value("field", "severity_max", 0)), 0, Severity.MAX)


## The level picked for the next run.
static func severity() -> int:
	return clampi(int(_load().get_value("field", "severity", 0)), 0, severity_max())


static func set_severity(n: int) -> void:
	var cf := _load()
	cf.set_value("field", "severity", clampi(n, 0, severity_max()))
	cf.save(path)


# --- history and stats -------------------------------------------------------------------

static func stat(key: String) -> int:
	return int(_load().get_value("history", key, 0))


static func stats() -> Dictionary:
	var cf := _load()
	var out := {}
	for k in STATS:
		out[k] = int(cf.get_value("history", k, 0))
	return out


## Recent runs, newest first. Each entry: see MetaProgress.history_entry.
static func run_log() -> Array:
	return Array(_load().get_value("runs", "log", [])).duplicate(true)


## Field Data the last finished run paid out.
static func last_field_data() -> int:
	var l := run_log()
	return int(l[0].get("field_data", 0)) if not l.is_empty() else 0


## Folds a run's progress into the profile. Safe to call after every run action, on every peer.
## `player` is whose profile this is (for the run log's classes); -1 = the host, player 0.
static func record_run(run: RunState, player: int = -1) -> void:
	var cf := _load()
	var changed := false
	# Flags this run earned. Flags the run started with may be the host's, not this player's.
	var start: Array = run.meta.get("start_flags", [])
	var flags: Dictionary = run.modifiers.get("unlocks", {}).duplicate()
	for k in run.meta:
		if run.meta[k] is bool and not start.has(k):
			flags[k] = flags.get(k, false) or run.meta[k]
	if run.act >= 2:
		flags["act1_boss_beaten"] = true
	for k in flags:
		if flags[k] and not cf.get_value(SECTION, k, false):
			cf.set_value(SECTION, k, true)
			changed = true
	if run.phase == RunState.Phase.ENDED and cf.get_value("history", "last_seed", 0) != run.seed:
		cf.set_value("history", "last_seed", run.seed)
		MetaProgress.fold_run(cf, run, maxi(0, player))
		changed = true
	if changed:
		cf.save(path)
	Achievements.check_run(run)
	RunHooks.call_static("StoryProfile", "record_run", [run])
