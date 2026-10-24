class_name RunAutoplay
extends RefCounted
## Default choices that move a run past a node or reward screen: used by headless autoplay, the
## net playtest and tests. Modules can supply their own with `autoplay_actions(run) -> Array`.


static func actions(run: RunState) -> Array:
	match run.phase:
		RunState.Phase.NODE:
			return RunHooks.call_static("NodeRules", "autoplay_actions", [run], [])
		RunState.Phase.REWARD:
			var out: Array = []
			if RunHooks.has("GearRun", "autoplay_actions"):
				out.append_array(RunHooks.call_static("GearRun", "autoplay_actions", [run], []))
			else:
				out.append_array(_gear_defaults(run))
			if RunHooks.has("Progression", "autoplay_actions"):
				out.append_array(RunHooks.call_static("Progression", "autoplay_actions", [run], []))
			else:
				out.append_array(_progression_defaults(run))
			return out
	return []


## Rank-up picks take the first perk on offer; mutation offers are skipped.
static func _progression_defaults(run: RunState) -> Array:
	var out: Array = []
	if not RunHooks.has("Progression", "pending_picks"):
		return out
	for r in run.squad():
		var who := run.controller_of(r)
		if RunHooks.call_static("Progression", "pending_picks", [r], 0) > 0:
			var offer: Array = RunHooks.call_static("Progression", "perk_offer", [run, r], [])
			if not offer.is_empty():
				out.append({"type": "prog_perk_pick", "player": who, "sid": r.id, "perk": offer[0]})
		var prog: Dictionary = r.get("prog", {})
		if not prog.get("offers", []).is_empty():
			out.append({"type": "prog_skip_offer", "player": who, "sid": r.id})
	return out


## Takes each soldier's first card (or skips it), and votes for the first Doctrine.
static func _gear_defaults(run: RunState) -> Array:
	var out: Array = []
	for sid in run.gear.get("offers", {}).keys():
		var r := run.get_soldier(sid)
		if r.is_empty():
			continue
		var pick := {"type": "gear_pick", "player": run.controller_of(r), "soldier": sid, "card": 0}
		if RunRules.validate(run, pick) != "":
			pick.card = -1
		out.append(pick)
	var vote: Dictionary = run.gear.get("doctrine_vote", {})
	if not vote.is_empty() and not vote.get("options", []).is_empty():
		for p in run.present_players():
			out.append({"type": "gear_doctrine", "player": p, "doctrine": vote.options[0]})
	return out


## Applies default actions until the run leaves NODE / REWARD (or nothing more is legal).
static func settle(run: RunState, submit: Callable) -> void:
	for guard in 60:
		if run.phase != RunState.Phase.NODE and run.phase != RunState.Phase.REWARD:
			return
		var acted := false
		for a in actions(run):
			if RunRules.validate(run, a) == "":
				submit.call(a)
				acted = true
				break   # one at a time: an action can change what the next one may do
		if not acted:
			return
