class_name RunAutoplay
extends RefCounted
## Default choices that move a run past a node or reward screen: used by headless autoplay, the
## net playtest and tests. Modules can supply their own with `autoplay_actions(run) -> Array`.


static func actions(run: RunState) -> Array:
	match run.phase:
		RunState.Phase.NODE:
			return RunHooks.call_static("NodeRules", "autoplay_actions", [run], [])
		RunState.Phase.REWARD:
			if RunHooks.has("GearRun", "autoplay_actions"):
				return RunHooks.call_static("GearRun", "autoplay_actions", [run], [])
			return _gear_defaults(run)
	return []


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
		if not acted:
			return
