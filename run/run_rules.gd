class_name RunRules
extends RefCounted
## The single entry point for changing a RunState, like Rules is for a GameState.
## A run action is a Dictionary {"type": String, "player": int, ...}. Built-in types are below;
## types with a module prefix are routed to that module ("gear_" -> GearRun, "prog_" -> Progression,
## "node_" -> NodeRules). Sessions replicate run actions exactly like mission actions.

const VOTE := "vote"               # + "node": id. Vote for a reachable node on the map.
const CLOSE_VOTE := "close_vote"   # host only: the vote timer ran out, resolve with the votes cast.
const REVEAL := "reveal"           # + "node": id. Spend 1 Intel to reveal a "?" node.
const BENCH := "bench"             # host only, + "target": player, "on": bool. A player left / came back.
const FIGHT_END := "fight_end"     # host only, + "outcome": RunRules.fight_outcome(state).

const ROUTES := {"gear_": "GearRun", "prog_": "Progression", "node_": "NodeRules", "story_": "Story"}

const START_SUPPLIES := 60
const START_INTEL := 1
const START_RESERVE := 1           # recruits per player, +1 for each 2 soldiers past the first (reserve_for)
const RESERVE_CLASSES: Array[String] = ["trooper", "marksman", "medic", "breacher"]
const HEAL_AFTER_FIGHT := 0.35
const BOSS_OUTBREAK_DROP := 3
## Fight income (Supplies, and Serum samples per soldier controlled), see "Income per node".
const INCOME := {
	RunMap.SKIRMISH: {"supplies": 40, "serum": 0}, RunMap.AMBUSH: {"supplies": 40, "serum": 0},
	RunMap.NEST: {"supplies": 50, "serum": 1}, RunMap.BOSS: {"supplies": 60, "serum": 1},
}
const BONUS_SUPPLIES := 10
## Doctrine pack effects (MetaUnlocks "doctrine_1"; the Doctrines themselves are in GearData).
const SCAVENGERS_INTEL := 1
const SUPPLY_DROP := 25
const TRIAGE_DRILLS_HP := 2
const SERUM_CACHE := 1


# --- setup -------------------------------------------------------------------------

## A new run for `num_players` (1 = solo). Each player commands their own squad of 1 to 4
## soldiers, at most 4 in all (MatchConfig.squad_plan); `picks` maps player -> Array of classes
## (left out: a solo player gets 4, co-op players 1 each). `meta` is the profile's unlock flags.
static func new_run(num_players: int, seed: int = 0, meta: Dictionary = {}, picks: Dictionary = {}) -> RunState:
	var run := RunState.new()
	var n := clampi(num_players, 1, 4)
	run.seed = seed if seed != 0 else randi() % 1000000 + 1
	run.rng.seed = run.seed
	run.players.clear()
	for p in n:
		run.players.append(p)
		run.serum[p] = 0
	run.meta = meta.duplicate(true)
	run.meta["start_flags"] = meta.keys().filter(func(k): return meta[k] is bool and meta[k])
	MetaUnlocks.bind(run.meta)
	run.supplies = START_SUPPLIES
	run.intel = START_INTEL
	for e in MatchConfig.squad_plan(n, picks):
		run.soldiers.append(RunSoldier.make(run, e.kind, e.player))
		run.serum[e.player] += 2 if MetaUnlocks.owns(run.meta, "serum_reserve") else 1   # 1 sample per soldier you control (+1 Serum reserve)
	for p in n:
		for k in reserve_for(run.soldiers_of(p).size()):
			run.soldiers.append(RunSoldier.make(run, random_class(run), p, RunSoldier.RESERVE))
	Severity.apply_new_run(run)
	RunHooks.call_static("Story", "init_run", [run])
	return run


## Starting recruits for a player who commands `soldiers`: 1 for 1-2 soldiers, 2 for 3-4.
static func reserve_for(soldiers: int) -> int:
	return START_RESERVE + floori(maxi(0, soldiers - 1) / 2.0)


## Starts the run: act 1 map, then the starting-kit pick if GearRun offers one.
static func start_run(run: RunState) -> void:
	run.emit({"type": "run_start", "players": run.players.duplicate(), "seed": run.seed})
	RunHooks.call_static("GearRun", "init_run", [run])
	_start_act(run, 1)
	RunHooks.call_static("GearRun", "starting_kit_offers", [run])
	if not _rewards_done(run):
		run.steps = [{"step": "rewards"}]
		run.phase = RunState.Phase.REWARD
		run.emit({"type": "step", "step": "rewards"})


static func _start_act(run: RunState, act: int) -> void:
	run.act = act
	run.row = 0
	run.node = -1
	run.votes.clear()
	run.map = RunMap.generate(run.rng, act)
	run.phase = RunState.Phase.MAP
	run.emit({"type": "act_start", "act": act})
	var docs: Array = run.modifiers.get("doctrines", [])
	if act > 1 and docs.has("scavengers"):
		add_intel(run, SCAVENGERS_INTEL, "Scavengers")
	if act > 1 and docs.has("supply_drop"):
		add_supplies(run, SUPPLY_DROP, "Supply drop")


# --- actions -----------------------------------------------------------------------

## "" if legal, otherwise a human-readable reason.
static func validate(run: RunState, action: Dictionary) -> String:
	if run.phase == RunState.Phase.ENDED:
		return "The run is over"
	var player: int = action.get("player", -1)
	if not run.players.has(player):
		return "Not in this run"
	var type: String = action.get("type", "")
	for prefix in ROUTES:
		if type.begins_with(prefix):
			var cls: String = ROUTES[prefix]
			if not RunHooks.has(cls, "validate"):
				return "%s is not available yet" % cls
			return RunHooks.call_static(cls, "validate", [run, action], "Rejected")
	match type:
		VOTE:
			if run.phase != RunState.Phase.MAP:
				return "Not choosing a route now"
			if run.benched.get(player, false):
				return "Benched players don't vote"
			var target: int = action.get("node", -1)
			if not run.reachable_nodes().has(target):
				return "Can't reach that node"
			var forced := _forced_nests(run)
			if not forced.is_empty() and not forced.has(target):
				return "Air support: the squad must hit the nest"
			return ""
		CLOSE_VOTE:
			if player != run.host_player:
				return "Only the host can close the vote"
			if run.phase != RunState.Phase.MAP or run.votes.is_empty():
				return "No votes to count"
			return ""
		REVEAL:
			if run.phase != RunState.Phase.MAP:
				return "Reveal nodes from the map"
			if run.intel < 1:
				return "No Intel left"
			var n := run.get_node(action.get("node", -1))
			if n.is_empty() or not n.hidden:
				return "Nothing hidden there"
			return ""
		BENCH:
			if player != run.host_player:
				return "Only the host can bench a player"
			if not run.players.has(action.get("target", -1)) or action.get("target") == run.host_player:
				return "Can't bench that player"
			return ""
		FIGHT_END:
			if player != run.host_player:
				return "Only the host reports a fight"
			return "" if run.phase == RunState.Phase.FIGHT else "No fight running"
	return "Unknown run action"


## Validates and applies a run action. Returns false (and changes nothing) if illegal.
static func apply(run: RunState, action: Dictionary) -> bool:
	var err := validate(run, action)
	if err != "":
		run.emit({"type": "rejected", "action": action, "reason": err})
		return false
	var type: String = action.type
	for prefix in ROUTES:
		if type.begins_with(prefix):
			RunHooks.call_static(ROUTES[prefix], "apply", [run, action])
			_after_module_action(run)
			return true
	match type:
		VOTE:
			run.votes[action.player] = action.node
			run.emit({"type": "vote", "player": action.player, "node": action.node})
			_maybe_resolve_vote(run)
		CLOSE_VOTE:
			_resolve_vote(run)
		REVEAL:
			var n := run.get_node(action.node)
			run.intel -= 1
			run.emit({"type": "intel", "amount": -1, "total": run.intel, "reason": "reveal"})
			RunMap.resolve_unknown(run, n)
			n.hidden = false
			run.emit({"type": "reveal", "node": n.id, "as": n.resolved})
		BENCH:
			if action.on:
				run.benched[action.target] = true
				run.votes.erase(action.target)
			else:
				run.benched.erase(action.target)
			run.emit({"type": "bench", "player": action.target, "on": action.on})
			_maybe_resolve_vote(run)
		FIGHT_END:
			_end_fight(run, action.outcome)
	return true


# --- route vote ----------------------------------------------------------------------

static func _maybe_resolve_vote(run: RunState) -> void:
	if run.phase != RunState.Phase.MAP or run.votes.is_empty():
		return
	for p in run.present_players():
		if not run.votes.has(p):
			return
	_resolve_vote(run)


## Majority wins; a split is broken by the host's pick, or the leftmost tied node if the host
## didn't vote for one of them.
static func vote_winner(run: RunState) -> int:
	var counts := {}
	for p in run.votes:
		counts[run.votes[p]] = counts.get(run.votes[p], 0) + 1
	var best := 0
	for id in counts:
		best = maxi(best, counts[id])
	var tied: Array = counts.keys().filter(func(id: int) -> bool: return counts[id] == best)
	if tied.size() == 1:
		return tied[0]
	if tied.has(run.votes.get(run.host_player, -1)):
		return run.votes[run.host_player]
	tied.sort()
	return tied[0]


static func _resolve_vote(run: RunState) -> void:
	var winner := vote_winner(run)
	run.emit({"type": "vote_result", "node": winner, "votes": run.votes.duplicate()})
	enter_node(run, winner)


## Nest nodes the squad must pick next (the Air support event), if any are reachable.
static func _forced_nests(run: RunState) -> Array[int]:
	var out: Array[int] = []
	if not run.modifiers.get("force_nest_next", false):
		return out
	for id in run.reachable_nodes():
		if RunMap.shown_type(run.get_node(id)) == RunMap.NEST:
			out.append(id)
	return out


# --- node flow -----------------------------------------------------------------------

## Moves the squad onto a node and runs its steps. Called when a route vote resolves.
static func enter_node(run: RunState, id: int) -> void:
	var n := run.get_node(id)
	run.node = id
	run.row = n.row
	run.votes.clear()
	n.visited = true
	run.modifiers.erase("force_nest_next")
	add_outbreak(run, 1, "node")
	if n.hidden:
		RunMap.resolve_unknown(run, n)
		n.hidden = false
		run.emit({"type": "reveal", "node": n.id, "as": n.resolved})
	elif n.type == RunMap.UNKNOWN:
		pass   # revealed earlier with Intel
	var type := RunMap.shown_type(n)
	run.emit({"type": "node_enter", "node": id, "node_type": type, "row": n.row})
	if RunMap.is_fight(type):
		run.steps = [{"step": "fight", "kind": type, "objective": n.objective, "seed": n.seed}, {"step": "rewards"}]
	else:
		run.steps = [{"step": "node", "kind": type}]
	_advance(run)


## Runs steps until one needs player input, then waits in that step's phase.
static func _advance(run: RunState) -> void:
	while not run.steps.is_empty():
		if run.phase == RunState.Phase.ENDED:
			return
		var st: Dictionary = run.steps.pop_front()
		run.emit({"type": "step", "step": st.step})
		match st.step:
			"fight":
				_start_fight(run, st)
				return
			"node":
				if RunHooks.has("NodeRules", "enter"):
					run.node_state = {}
					RunHooks.call_static("NodeRules", "enter", [run, st.kind])
					if not RunHooks.call_static("NodeRules", "is_done", [run], true):
						run.phase = RunState.Phase.NODE
						return
				_after_node(run)
			"rewards":
				if not _rewards_done(run):
					run.phase = RunState.Phase.REWARD
					return
			"victory":
				_end_run(run, Types.Result.VICTORY)
				return
	_node_finished(run)


## A module action (gear_, prog_, node_) may finish the step the run is waiting in.
static func _after_module_action(run: RunState) -> void:
	match run.phase:
		RunState.Phase.NODE:
			if RunHooks.call_static("NodeRules", "is_done", [run], true):
				_after_node(run)
				_advance(run)
		RunState.Phase.REWARD:
			if _rewards_done(run):
				_advance(run)


## An event can end in a fight (e.g. Checkpoint: force the gate): NodeRules puts it in
## modifiers.pending_fight = {"kind", "objective"} and it runs next, with rewards after.
static func _after_node(run: RunState) -> void:
	var pf: Dictionary = run.modifiers.get("pending_fight", {})
	if not pf.is_empty():
		run.modifiers.erase("pending_fight")
		run.steps.push_front({"step": "rewards"})
		run.steps.push_front({"step": "fight", "kind": pf.get("kind", RunMap.SKIRMISH),
			"objective": pf.get("objective", "extract"), "seed": run.rng.randi() % 1000000 + 1})


static func _rewards_done(run: RunState) -> bool:
	return not RunHooks.call_static("GearRun", "has_pending", [run], false) \
		and not RunHooks.call_static("Progression", "has_pending", [run], false) \
		and not RunHooks.call_static("Story", "has_pending", [run], false)


## Every step of the node is done: back to the map, or on to the next act after the boss.
static func _node_finished(run: RunState) -> void:
	if run.phase == RunState.Phase.ENDED:
		return
	run.node_state = {}
	if run.modifiers.get("remove_column", false):
		run.modifiers.erase("remove_column")
		RunMap.remove_column(run.map, run.row)
		run.emit({"type": "map_changed", "reason": "remove_column"})
	if run.current_node().get("type", "") == RunMap.BOSS:
		_start_act(run, run.act + 1)
		return
	run.phase = RunState.Phase.MAP
	run.emit({"type": "map"})


# --- fights --------------------------------------------------------------------------

static func _start_fight(run: RunState, st: Dictionary) -> void:
	run.phase = RunState.Phase.FIGHT
	run.fight_config = MatchConfig.for_fight(run, st)
	run.fight_snapshot = {}
	# One-shot event effects are spent on this fight.
	for k in ["extra_enemies", "enemies_dead_at_start", "first_turn_action_loss", "ambush", "detected", "boss_health_mult"]:
		run.modifiers.erase(k)
	run.emit({"type": "fight_start", "kind": st.kind, "objective": st.objective})


## What the host sends in FIGHT_END once a mission is over. Built from the GameState, so every
## peer could compute it, but only the host's copy is applied. The bonus objective comes from
## Objectives.bonus_met(state) once that module lands.
static func fight_outcome(s: GameState, bonus: Variant = null) -> Dictionary:
	if bonus == null:
		bonus = RunHooks.call_static("Objectives", "bonus_met", [s], false)
	var out := {"result": s.result, "bonus": bonus, "soldiers": [],
		"echoes_down": RunHooks.call_static("Story", "echoes_down", [s], [])}
	for u in s.units:
		if u.status.has("sid"):
			out.soldiers.append({"sid": u.status.sid, "unit": u.to_dict()})
	return out


static func _end_fight(run: RunState, outcome: Dictionary) -> void:
	var kind: String = run.fight_config.get("fight", {}).get("node", RunMap.SKIRMISH)
	run.fight_config = {}
	run.fight_snapshot = {}
	var fought := {}
	var lost := {RunSoldier.DEAD: 0, RunSoldier.TURNED: 0}
	for entry in outcome.soldiers:
		var r := run.get_soldier(entry.sid)
		if r.is_empty():
			continue
		fought[r.id] = true
		var what := RunSoldier.absorb(r, Unit.from_dict(entry.unit), run.fights_won + 1)
		if what == RunSoldier.TURNED:
			run.echoes.append({"sid": r.id, "kind": r.kind, "name": r.name, "act": run.act,
				"grafts": r.get("prog", {}).get("grafts", {}).duplicate()})
		if lost.has(what):
			lost[what] += 1
		if what != RunSoldier.ACTIVE:
			run.emit({"type": "soldier_lost", "sid": r.id, "how": what})
			_deploy_recruit(run, r)
	for r in run.squad():
		if not fought.has(r.id) and r.sit_out > 0:
			r.sit_out -= 1
	run.emit({"type": "fight_end", "result": outcome.result, "kind": kind})
	MetaProgress.on_fight_end(run, kind, outcome.result == Types.Result.VICTORY and not run.squad().is_empty(),
		bool(outcome.get("bonus", false)), lost[RunSoldier.DEAD], lost[RunSoldier.TURNED])
	RunHooks.call_static("Progression", "on_fight_end", [run, outcome])
	RunHooks.call_static("Story", "on_fight_end", [run, outcome, kind])
	if outcome.result != Types.Result.VICTORY or run.squad().is_empty():
		_end_run(run, Types.Result.DEFEAT)
		return
	run.fights_won += 1
	if kind == RunMap.BOSS and run.act >= RunState.ACTS:
		# The ending vote (Story) runs in the reward phase, then the run is won.
		if RunHooks.call_static("Story", "begin_ending", [run], false):
			run.steps = [{"step": "rewards"}, {"step": "victory"}]
			_advance(run)
		else:
			_end_run(run, Types.Result.VICTORY)
		return
	var heal: float = run.modifiers.get("heal_after_fight", HEAL_AFTER_FIGHT)
	var docs: Array = run.modifiers.get("doctrines", [])
	var extra_hp := TRIAGE_DRILLS_HP if docs.has("triage_drills") else 0
	for r in run.squad():
		if fought.has(r.id):
			r.hp = mini(r.max_hp, r.hp + ceili(r.max_hp * heal) + extra_hp)
	var income: Dictionary = INCOME.get(kind, INCOME[RunMap.SKIRMISH])
	add_supplies(run, Severity.income(run, income.supplies) + (BONUS_SUPPLIES if outcome.bonus else 0), kind)
	if outcome.bonus:
		add_intel(run, 1, "bonus objective")
	if income.serum > 0:
		for p in run.players:
			add_serum(run, p, income.serum * run.soldiers_of(p).size(), kind)
	if kind == RunMap.BOSS:
		add_outbreak(run, -Severity.boss_outbreak_drop(run, BOSS_OUTBREAK_DROP), "boss")
		if docs.has("serum_cache"):
			for p in run.players:
				add_serum(run, p, SERUM_CACHE * run.soldiers_of(p).size(), "Serum cache")
	RunHooks.call_static("GearRun", "on_fight_won", [run, RunMap.SKIRMISH if kind == RunMap.AMBUSH else kind])
	_advance(run)


## A dead or turned soldier's owner deploys a recruit from their reserve, if they have one.
static func _deploy_recruit(run: RunState, lost: Dictionary) -> void:
	var reserve := run.reserve_of(lost.owner)
	if reserve.is_empty() or run.squad().size() >= 4:
		return
	var r: Dictionary = reserve[0]
	r.status = RunSoldier.ACTIVE
	RunHooks.call_static("Progression", "on_recruit_deployed", [r.prog, lost.prog])
	run.emit({"type": "recruit_deployed", "sid": r.id, "replaces": lost.id, "player": r.owner})


static func _end_run(run: RunState, result: int) -> void:
	run.result = result
	run.phase = RunState.Phase.ENDED
	run.steps.clear()
	run.emit({"type": "run_end", "result": result})


# --- helpers modules call from inside their apply ----------------------------------------

static func add_supplies(run: RunState, amount: int, reason: String = "") -> void:
	run.supplies = maxi(0, run.supplies + amount)
	run.emit({"type": "supplies", "amount": amount, "total": run.supplies, "reason": reason})


static func add_intel(run: RunState, amount: int, reason: String = "") -> void:
	run.intel = maxi(0, run.intel + amount)
	run.emit({"type": "intel", "amount": amount, "total": run.intel, "reason": reason})


static func add_serum(run: RunState, player: int, samples: int, reason: String = "") -> void:
	run.serum[player] = maxi(0, run.serum.get(player, 0) + samples)
	run.emit({"type": "serum", "player": player, "amount": samples, "total": run.serum[player], "reason": reason})


static func add_outbreak(run: RunState, amount: int, reason: String = "") -> void:
	run.outbreak = maxi(0, run.outbreak + amount)
	run.emit({"type": "outbreak", "amount": amount, "total": run.outbreak, "reason": reason})


## A new recruit in `player`'s reserve (Survivors node, events, depot).
static func add_recruit(run: RunState, player: int, kind: String = "", infection: int = 0) -> Dictionary:
	if kind == "":
		kind = random_class(run)
	var r := RunSoldier.make(run, kind, player, RunSoldier.RESERVE)
	r.infection = infection
	run.soldiers.append(r)
	RunHooks.call_static("GearRun", "on_recruit", [run, r])
	run.emit({"type": "recruit", "sid": r.id, "player": player, "kind": kind})
	# A player with an empty slot (everyone dead) deploys at once.
	if run.squad().size() < 4 and run.soldiers_of(player).is_empty():
		r.status = RunSoldier.ACTIVE
	return r


## A random recruit class from those the profile has unlocked.
static func random_class(run: RunState) -> String:
	var pool: Array = RunHooks.call_static("Progression", "unlocked_classes", [run.meta], RESERVE_CLASSES)
	pool = pool.filter(func(k: String) -> bool: return UnitData.SOLDIERS.has(k))
	if pool.is_empty():
		pool = RESERVE_CLASSES
	return pool[run.rng.randi() % pool.size()]


static func outbreak_stage(outbreak: int) -> int:
	if outbreak >= 13: return 4
	if outbreak >= 9: return 3
	if outbreak >= 6: return 2
	if outbreak >= 3: return 1
	return 0


const OUTBREAK_NAMES: Array[String] = ["Contained", "Spreading", "Rampant", "Critical", "Collapse"]
