class_name Story
extends RefCounted
## Story rules inside a run: the wave number, Echoes (soldiers who Turned in earlier runs come back
## as named elite enemies), intel logs recovered from bosses and Echoes, and the ending vote after
## the act 3 boss. Owns `run.story`; the framework calls it through RunHooks, and run actions
## with the "story_" prefix are routed here. Presentation (scenes, radio, whispers) is
## StoryDirector's, which only reads.
##
## run.story keys: wave, runs, last_result, last_ending, last_wave, source_reached, known (log ids
## the host's profile had at the start), lore (log ids recovered this run), echoes ([{key, kind,
## name, wave, met, laid}]), open (the ending vote is up), votes (player -> ending id), ending,
## carrier (sid of the soldier who carried it).

const ENDING_VOTE := "story_ending"   # + "ending": "burn" | "sample" | "carry"

const ECHOES_PER_RUN := 2
## An Echo shows up in the first non-boss fight once this many fights are won (one per entry).
const ECHO_AFTER: Array[int] = [1, 4]
const ECHO_SUPPLIES := 15
const ECHO_HP_MULT := 2
const CRITICAL := 75


# --- setup -------------------------------------------------------------------------

## Called by RunRules.new_run (host side). Reads the profile copy in run.meta["story"].
static func init_run(run: RunState) -> void:
	var snap: Dictionary = run.meta.get("story", {})
	var echoes: Array = []
	for e in snap.get("echoes", []):
		if echoes.size() >= ECHOES_PER_RUN:
			break
		if UnitData.SOLDIERS.has(e.get("kind", "")):
			echoes.append({"key": e.key, "kind": e.kind, "name": e.name, "wave": e.get("wave", 0),
				"met": false, "laid": false})
	run.story = {
		"wave": snap.get("wave", StoryData.FIRST_WAVE), "runs": snap.get("runs", 0),
		"last_result": snap.get("last_result", ""), "last_ending": snap.get("last_ending", ""),
		"last_wave": snap.get("last_wave", 0), "source_reached": snap.get("source_reached", false),
		"known": snap.get("lore", []).duplicate(), "lore": [], "echoes": echoes,
		"open": false, "votes": {}, "ending": "", "carrier": -1,
	}


# --- Echoes ------------------------------------------------------------------------------

## Called by MatchConfig.for_fight on every peer: the Echo joining this fight, or {}.
static func fight_echo(run: RunState, st: Dictionary) -> Dictionary:
	if run.story.is_empty() or st.get("kind", "") == RunMap.BOSS:
		return {}
	var echoes: Array = run.story.get("echoes", [])
	for i in echoes.size():
		var e: Dictionary = echoes[i]
		if e.met:
			continue
		if run.fights_won < ECHO_AFTER[mini(i, ECHO_AFTER.size() - 1)]:
			return {}
		e.met = true
		run.emit({"type": "echo_met", "key": e.key, "name": e.name})
		return e.duplicate()
	return {}


## Called by MatchConfig.build once the GameState exists: adds the Echo as a Turned soldier on
## the enemy team, at an enemy spawn.
static func setup_echo(s: GameState, echo: Dictionary) -> Unit:
	var u := UnitData.make(echo.kind, Types.Team.ENEMY)
	u.owner_player = -1
	u.ai_controlled = true
	u.status["turned"] = true
	u.status["alerted"] = true
	u.status["elite"] = true
	u.status["echo"] = echo.key
	u.status["echo_wave"] = echo.get("wave", 0)
	u.max_hp *= ECHO_HP_MULT
	u.hp = u.max_hp
	u.infection = 100
	u.aim += 10        # the Turned tier passives (Infection.add skips Turned units)
	u.mobility += 1
	u.display_name = "Echo %s" % echo.name
	var spawns: Array = s.grid.enemy_spawns
	var spawn: Vector2i = spawns[s.units.size() % spawns.size()] if not spawns.is_empty() else Vector2i.ZERO
	if s.unit_at(spawn) != null or not s.grid.is_walkable(spawn):
		spawn = Rules._nearest_free(s, spawn)
	s.add_unit(u, spawn)
	return u


## Keys of the Echoes killed in a finished fight (RunRules.fight_outcome adds them).
static func echoes_down(s: GameState) -> Array:
	var out: Array = []
	for u in s.units:
		if u.status.has("echo") and not u.is_alive():
			out.append(u.status.echo)
	return out


## Called by RunRules after a fight's results are in: Echoes laid to rest pay out, and a boss
## win recovers the next intel log.
static func on_fight_end(run: RunState, outcome: Dictionary, kind: String) -> void:
	if run.story.is_empty():
		return
	for key in outcome.get("echoes_down", []):
		for e in run.story.echoes:
			if e.key == key and not e.laid:
				e.laid = true
				run.emit({"type": "echo_laid", "key": key, "name": e.name})
				RunRules.add_supplies(run, ECHO_SUPPLIES, "dog tags")
				recover_lore(run)
	if kind == RunMap.BOSS and outcome.get("result", 0) == Types.Result.VICTORY:
		recover_lore(run)


## The next intel log nobody on the host's profile has found yet, in story order.
static func recover_lore(run: RunState) -> String:
	for entry in StoryData.LORE:
		if not run.story.known.has(entry.id) and not run.story.lore.has(entry.id):
			run.story.lore.append(entry.id)
			run.emit({"type": "lore", "id": entry.id})
			return entry.id
	return ""


static func knows(run: RunState, id: String) -> bool:
	return run.story.get("known", []).has(id) or run.story.get("lore", []).has(id)


# --- ending vote ---------------------------------------------------------------------------

## Called by RunRules when the act 3 boss falls. True: the vote is open and the run waits for it.
static func begin_ending(run: RunState) -> bool:
	if run.story.is_empty():
		return false
	run.story.open = true
	run.story.votes = {}
	run.emit({"type": "ending_vote"})
	return true


static func has_pending(run: RunState) -> bool:
	return run.story.get("open", false) and run.story.get("ending", "") == ""


## The soldier who could carry the Source: the most infected living squad soldier at Critical.
static func carrier(run: RunState) -> Dictionary:
	var best := {}
	for r in run.squad():
		if r.infection >= CRITICAL and r.hp > 0 and (best.is_empty() or r.infection > best.infection):
			best = r
	return best


## [{id, ok, reason}] for the three endings, in order.
static func ending_options(run: RunState) -> Array:
	var out: Array = []
	for id in StoryData.ENDING_ORDER:
		var o := {"id": id, "ok": true, "reason": ""}
		match id:
			"sample":
				if not StoryData.HV_EVENTS.any(func(ev: String) -> bool: return run.seen_events.has(ev)):
					o.ok = false
					o.reason = StoryData.ENDINGS.sample.locked
			"carry":
				if not knows(run, StoryData.CARRY_LORE):
					o.ok = false
					o.reason = StoryData.ENDINGS.carry.locked_lore
				elif carrier(run).is_empty():
					o.ok = false
					o.reason = StoryData.ENDINGS.carry.locked_soldier
		out.append(o)
	return out


static func validate(run: RunState, action: Dictionary) -> String:
	if action.get("type", "") != ENDING_VOTE:
		return "Unknown story action"
	if not has_pending(run):
		return "No ending to choose"
	var p: int = action.get("player", -1)
	if run.benched.get(p, false):
		return "Benched players don't vote"
	for o in ending_options(run):
		if o.id == action.get("ending", ""):
			return "" if o.ok else o.reason
	return "Unknown ending"


static func apply(run: RunState, action: Dictionary) -> void:
	run.story.votes[action.player] = action.ending
	run.emit({"type": "ending_voted", "player": action.player, "ending": action.ending})
	for p in run.present_players():
		if not run.story.votes.has(p):
			return
	_resolve(run)


## Majority wins; a tie goes to the host's pick.
static func _resolve(run: RunState) -> void:
	var counts := {}
	for p in run.story.votes:
		counts[run.story.votes[p]] = counts.get(run.story.votes[p], 0) + 1
	var best: int = counts.values().max()
	var tied: Array = StoryData.ENDING_ORDER.filter(func(id: String) -> bool: return counts.get(id, 0) == best)
	var pick: String = tied[0]
	if tied.size() > 1 and tied.has(run.story.votes.get(run.host_player, "")):
		pick = run.story.votes[run.host_player]
	run.story.ending = pick
	run.story.open = false
	if pick == "carry":
		run.story.carrier = carrier(run).get("id", -1)
	run.emit({"type": "ending", "ending": pick, "carrier": run.story.carrier})


static func autoplay_actions(run: RunState) -> Array:
	var out: Array = []
	if not has_pending(run):
		return out
	for p in run.present_players():
		if not run.story.votes.has(p):
			out.append({"type": ENDING_VOTE, "player": p, "ending": "burn"})
	return out


## The ending vote screen, shown by RunView while the vote is open.
static func screen() -> Script:
	return load("res://ui/story/ending_screen.gd")
