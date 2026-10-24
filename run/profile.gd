class_name Profile
extends RefCounted
## The player's profile on this machine: unlock flags and run history that carry between runs.
## Runs read a copy as `run.meta`. Modules unlock things by setting a true bool flag in `run.meta`
## (or `run.modifiers.unlocks`) during a run, e.g. Progression's "vector_unlocked"; the profile
## picks them up as the run goes. "act1_boss_beaten" is set by the framework.

const PATH := "user://profile.cfg"
const SECTION := "meta"


static func _load() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(PATH)
	return cf


static func meta() -> Dictionary:
	var cf := _load()
	var out := {}
	if cf.has_section(SECTION):
		for k in cf.get_section_keys(SECTION):
			out[k] = cf.get_value(SECTION, k)
	return out


## Folds a run's progress into the profile. Safe to call after every run action.
static func record_run(run: RunState) -> void:
	var cf := _load()
	var changed := false
	var flags: Dictionary = run.modifiers.get("unlocks", {}).duplicate()
	for k in run.meta:
		if run.meta[k] is bool:
			flags[k] = flags.get(k, false) or run.meta[k]
	if run.act >= 2:
		flags["act1_boss_beaten"] = true
	for k in flags:
		if flags[k] and not cf.get_value(SECTION, k, false):
			cf.set_value(SECTION, k, true)
			changed = true
	if run.phase == RunState.Phase.ENDED and cf.get_value("history", "last_seed", 0) != run.seed:
		cf.set_value("history", "last_seed", run.seed)
		cf.set_value("history", "runs", cf.get_value("history", "runs", 0) + 1)
		if run.result == Types.Result.VICTORY:
			cf.set_value("history", "wins", cf.get_value("history", "wins", 0) + 1)
		changed = true
	if changed:
		cf.save(PATH)
