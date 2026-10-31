class_name NodeRules
extends RefCounted
## Entry point for the non-combat run nodes: Event, Supply depot, Field hospital, Survivors.
## Like Rules for a mission, every change goes through validate/apply with an action
## Dictionary, so online co-op can replicate node screens the same way. The open screen is
## run.node_state. OWNER: nodes workstream. Contract: docs/ARCHITECTURE.md, "Non-combat nodes".
##
## Actions (all carry "player"):
##   node_choose {option, soldier?}   event: vote / pick / claim / owner decision
##   node_pass                        event: decline a volunteer step
##   node_timeout                     event: the choice timer ran out (fills defaults)
##   node_leave                       done with this node; it closes once every present player has left
##   node_timeout is the host's (the view's timer ran out); everything else is any present player's.
##   depot:     node_buy {index, soldier?, slot?}  node_sell {soldier, slot} or {stash: index}  node_reroll
##   hospital:  node_treat {soldier, treatment}
##   survivors: node_claim

const KINDS: Array[String] = ["event", "depot", "hospital", "survivors"]


## Opens a node. For "event", `event_id` forces a specific event (otherwise one is drawn).
static func enter(run: RunState, kind: String, event_id: String = "") -> Dictionary:
	match kind:
		"event": return EventRules.enter(run, event_id)
		"depot": return Depot.enter(run)
		"hospital": return FieldHospital.enter(run)
		"survivors": return Survivors.enter(run)
	assert(false, "unknown node kind %s" % kind)
	return {}


static func validate(run: RunState, action: Dictionary) -> String:
	var ns: Dictionary = run.node_state
	if run.phase != RunState.Phase.NODE or ns.is_empty():
		return "no node open"
	var player: int = action.get("player", -1)
	if action.get("type") == "node_timeout":
		if player != run.host_player:
			return "only the host closes a choice"
	elif not RunAccess.is_active(run, player):
		return "benched players can't act"
	elif player in ns.left:
		return "already left"
	match action.get("type"):
		"node_leave":
			return "" if ns.finished or ns.kind == "survivors" else "finish the event first"
		"node_choose", "node_pass", "node_timeout":
			return EventRules.validate(run, ns, action) if ns.kind == "event" else "not an event"
		"node_buy", "node_sell", "node_reroll":
			return Depot.validate(run, ns, action) if ns.kind == "depot" else "not a depot"
		"node_treat":
			return FieldHospital.validate(run, ns, action) if ns.kind == "hospital" else "not a hospital"
		"node_claim":
			return Survivors.validate(run, ns, action) if ns.kind == "survivors" else "not a survivors node"
	return "unknown action"


static func apply(run: RunState, action: Dictionary) -> bool:
	var err := validate(run, action)
	if err != "":
		RunAccess.emit(run, {"type": "rejected", "action": action, "reason": err})
		return false
	var ns: Dictionary = run.node_state
	match action.type:
		"node_leave":
			ns.left.append(action.player)
			RunAccess.emit(run, {"type": "node_leave", "player": action.player})
			if is_done(run) and ns.kind == "survivors":
				Survivors.settle(run, ns)
		"node_choose", "node_pass", "node_timeout":
			EventRules.apply(run, ns, action)
		"node_buy", "node_sell", "node_reroll":
			Depot.apply(run, ns, action)
		"node_treat":
			FieldHospital.apply(run, ns, action)
		"node_claim":
			Survivors.apply(run, ns, action)
	return true


## The screen for a node kind: a Control script with setup(run, session). See ui/nodes/.
static func screen(kind: String) -> Script:
	match kind:
		"event": return load("res://ui/nodes/event_screen.gd")
		"depot": return load("res://ui/nodes/depot_screen.gd")
		"hospital": return load("res://ui/nodes/hospital_screen.gd")
		"survivors": return load("res://ui/nodes/survivors_screen.gd")
	return null


## True once every present player has left the node (the run goes back to the map, or into
## pending_fight if the event ended in one).
static func is_done(run: RunState) -> bool:
	var ns: Dictionary = run.node_state
	if ns.is_empty():
		return true
	return RunAccess.active_players(run).all(func(p): return p in ns.left)


## A fight the event ended in: {objective, ambush, small}, or {} if none.
static func pending_fight(run: RunState) -> Dictionary:
	return run.node_state.get("fight", {})


## Actions that close the open node with defaults: the host times out an open event choice,
## then every present player leaves. For absent players' timers and headless tests; apply them
## in order and call again until is_done (an event may need one timeout per step).
static func autoplay_actions(run: RunState) -> Array:
	var ns: Dictionary = run.node_state
	if ns.is_empty():
		return []
	if ns.kind == "event" and not ns.finished:
		return [{"type": "node_timeout", "player": run.host_player}]
	var out: Array = []
	for p in RunAccess.active_players(run):
		if not p in ns.left:
			out.append({"type": "node_leave", "player": p})
	return out
