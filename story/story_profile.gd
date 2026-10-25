class_name StoryProfile
extends RefCounted
## What the story remembers between runs on this machine, in the profile file next to Profile's
## sections: section "story" (runs recorded, last result and ending, endings seen, intel logs
## found) and section "echoes" (soldiers who Turned, waiting to come back as Echoes).
##
## A run gets a copy through Profile.meta()["story"] (snapshot()), so Story.init_run reads only
## run data and the host's copy travels with the RunState. record_run(run) folds a run back in;
## it is safe to call after every run action, on every peer.

const SECTION := "story"
const ECHO_SECTION := "echoes"
## Echoes kept waiting at most; the oldest drop off.
const MAX_POOL := 12

static func _load() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(Profile.path)   # the same file as Profile (tests point Profile.path elsewhere)
	return cf


## The wave number of the next run (Lantern Company's count, not the player's).
static func wave() -> int:
	return StoryData.FIRST_WAVE + int(_load().get_value(SECTION, "runs", 0))


static func snapshot() -> Dictionary:
	var cf := _load()
	var pool: Array = []
	if cf.has_section(ECHO_SECTION):
		for k in cf.get_section_keys(ECHO_SECTION):
			pool.append(cf.get_value(ECHO_SECTION, k))
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("wave", 0) < b.get("wave", 0))
	return {
		"wave": StoryData.FIRST_WAVE + int(cf.get_value(SECTION, "runs", 0)),
		"runs": int(cf.get_value(SECTION, "runs", 0)),
		"last_result": cf.get_value(SECTION, "last_result", ""),
		"last_ending": cf.get_value(SECTION, "last_ending", ""),
		"last_wave": int(cf.get_value(SECTION, "last_wave", 0)),
		"endings": cf.get_value(SECTION, "endings", []),
		"lore": cf.get_value(SECTION, "lore", []),
		"source_reached": cf.get_value(SECTION, "source_reached", false),
		"echoes": pool,
	}


static func lore() -> Array:
	return _load().get_value(SECTION, "lore", [])


static func endings() -> Array:
	return _load().get_value(SECTION, "endings", [])


## Folds a run in: intel found, Echoes laid to rest, and once the run is over the wave count,
## result, ending and the soldiers who Turned (they wait in the pool for a later run).
static func record_run(run: RunState) -> void:
	var st: Dictionary = run.story
	if st.is_empty():
		return
	var cf := _load()
	var changed := false
	var found: Array = cf.get_value(SECTION, "lore", [])
	for id in st.get("lore", []):
		if not found.has(id):
			found.append(id)
			changed = true
	if changed:
		cf.set_value(SECTION, "lore", found)
	for e in st.get("echoes", []):
		if e.get("laid", false) and cf.has_section_key(ECHO_SECTION, e.key):
			cf.erase_section_key(ECHO_SECTION, e.key)
			changed = true
	if run.act >= RunState.ACTS and not cf.get_value(SECTION, "source_reached", false):
		cf.set_value(SECTION, "source_reached", true)
		changed = true
	if run.phase == RunState.Phase.ENDED and cf.get_value(SECTION, "last_seed", 0) != run.seed:
		cf.set_value(SECTION, "last_seed", run.seed)
		cf.set_value(SECTION, "runs", int(cf.get_value(SECTION, "runs", 0)) + 1)
		var ending: String = st.get("ending", "")
		var won := run.result == Types.Result.VICTORY
		cf.set_value(SECTION, "last_result", "won" if won else "lost")
		cf.set_value(SECTION, "last_wave", st.get("wave", 0))
		cf.set_value(SECTION, "last_ending", ending if won else "")
		if won and ending != "":
			var seen: Array = cf.get_value(SECTION, "endings", [])
			if not seen.has(ending):
				seen.append(ending)
				cf.set_value(SECTION, "endings", seen)
		for t in run.echoes:
			cf.set_value(ECHO_SECTION, "%d_%d" % [run.seed, t.sid],
				{"key": "%d_%d" % [run.seed, t.sid], "kind": t.kind, "name": t.name, "act": t.act, "wave": st.get("wave", 0),
					"grafts": t.get("grafts", {})})
		_trim_pool(cf)
		changed = true
	if changed:
		cf.save(Profile.path)


static func _trim_pool(cf: ConfigFile) -> void:
	if not cf.has_section(ECHO_SECTION):
		return
	var keys := Array(cf.get_section_keys(ECHO_SECTION))
	keys.sort_custom(func(a: String, b: String) -> bool:
		return cf.get_value(ECHO_SECTION, a).get("wave", 0) < cf.get_value(ECHO_SECTION, b).get("wave", 0))
	while keys.size() > MAX_POOL:
		cf.erase_section_key(ECHO_SECTION, keys.pop_front())


## Wipes the story sections (tests).
static func clear() -> void:
	var cf := _load()
	for s in [SECTION, ECHO_SECTION]:
		if cf.has_section(s):
			cf.erase_section(s)
	cf.save(Profile.path)
