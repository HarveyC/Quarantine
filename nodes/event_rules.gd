class_name EventRules
extends RefCounted
## Runs the text events in EventData: picks one, walks its steps, collects co-op choices
## (vote, secret, per-player, volunteer, owner) and applies outcomes to the run.
## Called through NodeRules; all state lives in run.node_state. OWNER: nodes workstream.

const KINDS: Array[String] = ["vote", "secret", "per_player", "volunteer", "owner"]


## A weighted random event that hasn't been seen this run and fits the act and squad, or "".
static func pick(run) -> String:
	var ids: Array = []
	var weights: Array = []
	var total := 0
	for id in EventData.EVENTS:
		if not eligible(run, id):
			continue
		var w: int = EventData.EVENTS[id].get("weight", {}).get(run.act, 1)
		ids.append(id)
		weights.append(w)
		total += w
	if ids.is_empty():
		return ""
	var roll: int = run.rng.randi_range(0, total - 1)
	for i in ids.size():
		roll -= weights[i]
		if roll < 0:
			return ids[i]
	return ids[-1]


static func eligible(run, id: String) -> bool:
	var ev: Dictionary = EventData.EVENTS[id]
	if id in run.seen_events:
		return false
	if not run.act in ev.get("acts", [1, 2, 3]):
		return false
	var req: Dictionary = ev.get("requires", {})
	if req.has("infected_soldier") and not RunAccess.active_soldiers(run).any(func(r): return r.infection >= req.infected_soldier):
		return false
	if req.get("wounded_soldier", false) and not RunAccess.active_soldiers(run).any(func(r): return r.hp < r.max_hp):
		return false
	return true


static func subject_for(run, how: String):
	var best = null
	for rec in RunAccess.active_soldiers(run):
		match how:
			"most_infected":
				if best == null or rec.infection > best.infection:
					best = rec
			"most_wounded":
				if best == null or float(rec.hp) / rec.max_hp < float(best.hp) / best.max_hp:
					best = rec
	return best


## Opens event `id` (or a random one when id is "") as the run's node_state.
static func enter(run, id: String = "") -> Dictionary:
	if id == "":
		id = pick(run)
	var ns := {
		"kind": "event", "event": id, "step": "", "subject": -1, "choices": {}, "passed": [],
		"generated": {}, "results": [], "fight": {}, "finished": false, "left": [],
	}
	run.node_state = ns
	if id == "":
		ns.event = "quiet"
		ns.results.append(EventData.QUIET_STREETS.text)
		RunAccess.add_supplies(run, EventData.QUIET_STREETS.supplies)
		_finish(run, ns)
		return ns
	run.seen_events.append(id)
	var ev: Dictionary = EventData.EVENTS[id]
	if ev.has("subject"):
		var subj = subject_for(run, ev.subject)
		ns.subject = subj.id if subj != null else -1
	RunAccess.emit(run, {"type": "event_start", "event": id, "subject": ns.subject})
	_enter_step(run, ns, ev.start)
	return ns


## Display text for the open event, with {subject} filled in.
static func title(ns: Dictionary) -> String:
	return EventData.QUIET_STREETS.title if ns.event == "quiet" else event_def(ns).get("title", "")


static func scene(run: RunState, ns: Dictionary) -> String:
	if ns.event == "quiet":
		return EventData.QUIET_STREETS.text
	return _fill(run, ns, event_def(ns).get("text", ""))


static func prompt(run: RunState, ns: Dictionary) -> String:
	return _fill(run, ns, step_def(ns).get("prompt", ""))


## Short label for how the current step is decided.
static func kind_label(run: RunState, ns: Dictionary) -> String:
	match step_def(ns).get("kind", ""):
		"vote": return "Squad vote" if run.present_players().size() > 1 else "Your call"
		"secret": return "Secret pick: revealed together"
		"per_player": return "Each player decides for their own soldiers"
		"volunteer": return "Volunteer: the first to claim it pays"
		"owner": return "%s's owner decides" % _fill(run, ns, "{subject}")
	return ""


static func event_def(ns: Dictionary) -> Dictionary:
	return EventData.EVENTS.get(ns.event, {})


static func step_def(ns: Dictionary) -> Dictionary:
	return event_def(ns).get("steps", {}).get(ns.step, {})


## Who may pick in the current step: the subject's owner for "owner", every present player otherwise.
static func deciders(run, ns: Dictionary) -> Array:
	if step_def(ns).get("kind") == "owner":
		var subj = RunAccess.soldier(run, ns.subject)
		return [subj.owner] if subj != null and RunAccess.is_active(run, subj.owner) else []
	return RunAccess.active_players(run)


## The options `player` sees in the current step: [{id, label, desc, ok, reason, target}].
## Labels and descriptions already have {subject} filled in.
static func options_for(run, ns: Dictionary, player: int) -> Array:
	var step := step_def(ns)
	var out: Array = []
	if step.has("generate"):
		for id in ns.generated.get(player, []):
			var it := GearData.get_item(id)
			out.append({"id": id, "label": it.get("name", id), "desc": it.get("desc", ""),
				"ok": true, "reason": "", "target": "own_soldier"})
		return out
	for opt in step.get("options", []):
		var reason := _option_blocker(run, ns, opt, player)
		out.append({"id": opt.id, "label": _fill(run, ns, opt.label), "desc": _fill(run, ns, opt.get("desc", "")),
			"ok": reason == "", "reason": reason, "target": opt.get("target", "")})
	return out


static func _option(ns: Dictionary, id: String) -> Dictionary:
	if step_def(ns).has("generate"):
		return {"id": id, "target": "own_soldier", "generated": true}
	for opt in step_def(ns).get("options", []):
		if opt.id == id:
			return opt
	return {}


static func _option_blocker(run, _ns: Dictionary, opt: Dictionary, player: int) -> String:
	var req: Dictionary = opt.get("requires", {})
	var waived: bool = req.has("waived_by") and RunAccess.has_class(run, req.waived_by)
	if not waived and run.supplies < req.get("supplies", 0):
		return "Not enough Supplies"
	if run.intel < req.get("intel", 0):
		return "Not enough Intel"
	if opt.get("target", "") == "own_soldier" and _eligible_soldiers(run, opt, player).is_empty():
		return "None of your soldiers can"
	return ""


static func _eligible_soldiers(run, opt: Dictionary, player: int) -> Array:
	var tr: Dictionary = opt.get("target_requires", {})
	return RunAccess.soldiers_of(run, player).filter(func(rec):
		if tr.get("has_mutation", false) and RunAccess.mutations_of(rec).is_empty():
			return false
		if tr.get("graft_ready", false) and not Grafts.eligible(run, rec):
			return false
		if rec.infection < tr.get("infection_at_least", 0):
			return false
		return rec.infection < tr.get("infection_below", 1000))


static func validate(run, ns: Dictionary, action: Dictionary) -> String:
	var player: int = action.get("player", -1)
	match action.type:
		"node_choose":
			if ns.finished:
				return "event is over"
			if not player in deciders(run, ns):
				return "not your choice"
			var kind: String = step_def(ns).kind
			if kind == "volunteer" and player in ns.passed:
				return "already passed"
			if kind in ["secret", "per_player", "volunteer", "owner"] and ns.choices.has(player):
				return "already chosen"
			var opt := _option(ns, action.get("option", ""))
			if opt.is_empty():
				return "no such option"
			if opt.get("generated", false):
				if not action.option in ns.generated.get(player, []):
					return "no such option"
			else:
				var blocker := _option_blocker(run, ns, opt, player)
				if blocker != "":
					return blocker
			if opt.get("target", "") == "own_soldier":
				var rec = RunAccess.soldier(run, action.get("soldier", -1))
				if rec == null or not rec in _eligible_soldiers(run, opt, player):
					return "pick one of your own soldiers"
			return ""
		"node_pass":
			if ns.finished or step_def(ns).kind != "volunteer":
				return "nothing to pass on"
			if not player in deciders(run, ns) or player in ns.passed:
				return "already passed"
			return ""
		"node_timeout":
			return "event is over" if ns.finished else ""
	return "unknown action"


static func apply(run, ns: Dictionary, action: Dictionary) -> void:
	var player: int = action.get("player", -1)
	var step := step_def(ns)
	match action.type:
		"node_choose":
			var pick := {"option": action.option, "soldier": action.get("soldier", -1)}
			RunAccess.emit(run, {"type": "event_choice", "player": player, "step": ns.step,
				"option": "" if step.kind == "secret" else action.option})
			match step.kind:
				"vote":
					ns.choices[player] = pick
					if ns.choices.size() >= deciders(run, ns).size():
						_resolve_vote(run, ns)
				"secret":
					ns.choices[player] = pick
					if ns.choices.size() >= deciders(run, ns).size():
						_resolve_secret(run, ns)
				"per_player":
					ns.choices[player] = pick
					_apply_option(run, ns, _option(ns, pick.option), player, pick.soldier)
					if ns.choices.size() >= deciders(run, ns).size():
						_enter_step(run, ns, step.get("next", ""))
				"volunteer", "owner":
					ns.choices[player] = pick
					var opt := _option(ns, pick.option)
					_apply_option(run, ns, opt, player, pick.soldier)
					_advance(run, ns, opt)
		"node_pass":
			ns.passed.append(player)
			if ns.passed.size() >= deciders(run, ns).size():
				_nobody(run, ns)
		"node_timeout":
			_timeout(run, ns)


## Fills in every missing pick with the step's default and resolves the step.
static func _timeout(run, ns: Dictionary) -> void:
	var step := step_def(ns)
	match step.kind:
		"vote":
			_resolve_vote(run, ns)
		"volunteer":
			_nobody(run, ns)
		_:
			for p in deciders(run, ns):
				if ns.choices.has(p):
					continue
				var pick := _default_pick(run, ns, p)
				ns.choices[p] = pick
				if step.kind != "secret" and pick.option != "":
					_apply_option(run, ns, _option(ns, pick.option), p, pick.soldier)
			if step.kind == "secret":
				_resolve_secret(run, ns)
			elif step.kind == "owner":
				var p0: Array = deciders(run, ns)
				_advance(run, ns, _option(ns, ns.choices[p0[0]].option) if not p0.is_empty() else {})
			else:
				_enter_step(run, ns, step.get("next", ""))


## The default option for a player who didn't pick: one marked default, else the last allowed.
## A generated-item step defaults to the first item on the player's first soldier.
static func _default_pick(run, ns: Dictionary, player: int) -> Dictionary:
	var step := step_def(ns)
	if step.has("generate"):
		var mine := RunAccess.soldiers_of(run, player)
		var gen: Array = ns.generated.get(player, [])
		if mine.is_empty() or gen.is_empty():
			return {"option": "", "soldier": -1}
		return {"option": gen[0], "soldier": mine[0].id}
	var fallback := {}
	for opt in step.get("options", []):
		if _option_blocker(run, ns, opt, player) != "":
			continue
		fallback = opt
		if opt.get("default", false):
			break
	if fallback.is_empty():
		return {"option": "", "soldier": -1}
	var soldier := -1
	if fallback.get("target", "") == "own_soldier":
		soldier = _eligible_soldiers(run, fallback, player)[0].id
	return {"option": fallback.id, "soldier": soldier}


static func _resolve_vote(run, ns: Dictionary) -> void:
	var step := step_def(ns)
	var counts := {}
	for p in ns.choices:
		var o: String = ns.choices[p].option
		counts[o] = counts.get(o, 0) + 1
	var best := 0
	for o in counts:
		best = maxi(best, counts[o])
	var tied: Array = counts.keys().filter(func(o): return counts[o] == best)
	var winner := ""
	if tied.size() == 1:
		winner = tied[0]
	elif ns.choices.has(run.host_player) and ns.choices[run.host_player].option in tied:
		winner = ns.choices[run.host_player].option
	else:
		for opt in step.options:
			if opt.id in tied:
				winner = opt.id
				break
	if winner == "":
		winner = _default_pick(run, ns, run.host_player).option
	var opt := _option(ns, winner)
	RunAccess.emit(run, {"type": "event_vote", "step": ns.step, "option": winner, "votes": counts})
	_apply_option(run, ns, opt, -1, -1)
	_advance(run, ns, opt)


static func _resolve_secret(run, ns: Dictionary) -> void:
	var step := step_def(ns)
	var picks := {}
	for p in ns.choices:
		picks[p] = ns.choices[p].option
	RunAccess.emit(run, {"type": "event_reveal", "step": ns.step, "picks": picks})
	var players: Array = ns.choices.keys()
	players.sort()
	for p in players:
		var c: Dictionary = ns.choices[p]
		if c.option != "":
			_apply_option(run, ns, _option(ns, c.option), p, c.soldier)
	var una: Dictionary = step.get("unanimous", {})
	if not una.is_empty() and not players.is_empty() and players.all(func(p): return ns.choices[p].option == una.option):
		if una.get("outcome", "") != "":
			ns.results.append(_fill(run, ns, una.outcome))
		if una.get("per_player", false):
			for p in players:
				_run_effects(run, ns, una.get("effects", []), {"player": p, "soldier": RunAccess.soldier(run, ns.choices[p].soldier)})
		else:
			_run_effects(run, ns, una.get("effects", []), {"player": -1, "soldier": null})
	_enter_step(run, ns, step.get("next", ""))


static func _nobody(run, ns: Dictionary) -> void:
	var nb: Dictionary = step_def(ns).get("nobody", {})
	if nb.get("outcome", "") != "":
		ns.results.append(_fill(run, ns, nb.outcome))
	_run_effects(run, ns, nb.get("effects", []), {"player": -1, "soldier": null})
	_enter_step(run, ns, nb.get("next", ""))


static func _advance(run, ns: Dictionary, opt: Dictionary) -> void:
	if not ns.fight.is_empty():
		_finish(run, ns)
		return
	_enter_step(run, ns, opt.get("next", step_def(ns).get("next", "")))


static func _apply_option(run, ns: Dictionary, opt: Dictionary, player: int, soldier_id: int) -> void:
	if opt.is_empty():
		return
	var rec = RunAccess.soldier(run, soldier_id)
	var ctx := {"player": player, "soldier": rec}
	if opt.get("generated", false):
		Loadout.equip(run, rec, opt.id)
		ns.results.append("%s takes the %s." % [rec.name, GearData.item_name(opt.id)])
		RunAccess.emit(run, {"type": "item_gained", "sid": rec.id, "item": opt.id})
		return
	if opt.get("outcome", "") != "":
		ns.results.append(_fill(run, ns, opt.outcome, ctx))
	_run_effects(run, ns, opt.get("effects", []), ctx)


static func _enter_step(run, ns: Dictionary, step_id: String) -> void:
	ns.choices = {}
	ns.passed = []
	ns.generated = {}
	ns.step = step_id
	if step_id == "" or not ns.fight.is_empty():
		_finish(run, ns)
		return
	var step := step_def(ns)
	var skip: Dictionary = step.get("skip_if_class", {})
	if not skip.is_empty() and RunAccess.has_class(run, skip["class"]):
		if skip.get("outcome", "") != "":
			ns.results.append(_fill(run, ns, skip.outcome))
		_enter_step(run, ns, skip.to)
		return
	if step.has("generate"):
		for p in RunAccess.active_players(run):
			var counts := {}
			for rec in RunAccess.soldiers_of(run, p):
				for t in GearTags.counts(rec):
					counts[t] = counts.get(t, 0) + GearTags.counts(rec)[t]
			var drawn: Array = []
			for i in step.generate.items:
				var id := GearDraw.draw_item(run.rng, counts, step.generate.get("rarity", "common"), drawn)
				if id != "":
					drawn.append(id)
			ns.generated[p] = drawn
	RunAccess.emit(run, {"type": "event_step", "event": ns.event, "step": step_id, "kind": step.kind})
	if deciders(run, ns).is_empty():
		_timeout(run, ns)


static func _finish(run, ns: Dictionary) -> void:
	if ns.finished:
		return
	ns.finished = true
	ns.step = ""
	RunAccess.emit(run, {"type": "event_end", "event": ns.event, "results": ns.results.duplicate(), "fight": ns.fight.duplicate()})


static func _targets(run, ns: Dictionary, who: String, ctx: Dictionary) -> Array:
	match who:
		"soldier":
			return [ctx.soldier] if ctx.soldier != null else []
		"subject":
			var s = RunAccess.soldier(run, ns.subject)
			return [s] if s != null else []
		"all":
			return RunAccess.active_soldiers(run)
	return []


static func _run_effects(run, ns: Dictionary, effects: Array, ctx: Dictionary) -> void:
	for e in effects:
		if e.has("unless_class") and RunAccess.has_class(run, e.unless_class):
			continue
		match e.op:
			"supplies":
				RunAccess.add_supplies(run, e.amount)
			"intel":
				RunAccess.add_intel(run, e.amount)
			"outbreak":
				RunAccess.add_outbreak(run, e.amount)
			"infection":
				for rec in _targets(run, ns, e.who, ctx):
					RunAccess.add_infection(run, rec, e.amount)
			"heal_pct":
				for rec in _targets(run, ns, e.who, ctx):
					RunAccess.heal_pct(run, rec, e.pct)
			"hurt_pct":
				for rec in _targets(run, ns, e.who, ctx):
					RunAccess.hurt_pct(run, rec, e.pct)
			"mutation":
				for rec in _targets(run, ns, e.who, ctx):
					var m := RunAccess.add_random_mutation(run, rec)
					if m != "":
						ns.results.append("%s gains %s." % [rec.name, RunAccess.mutation_name(m)])
			"bloom_graft":
				for rec in _targets(run, ns, e.who, ctx):
					var g := Grafts.grant_bloom(run, rec)
					if g != "":
						RunAccess.emit(run, {"type": "soldier_graft", "sid": rec.id, "graft": g})
						ns.results.append("%s's %s takes root: %s." % [rec.name, GraftData.SLOT_NAMES[GraftData.slot_of(g)].to_lower(), GraftData.name_of(g)])
			"remove_mutation":
				for rec in _targets(run, ns, e.who, ctx):
					var muts := RunAccess.mutations_of(rec)
					if not muts.is_empty():
						RunAccess.remove_mutation(run, rec, muts[-1])
						RunAccess.add_serum(run, rec.owner, e.get("serum", 0))
			"perk_pick":
				for rec in _targets(run, ns, e.who, ctx):
					RunAccess.grant_perk_pick(run, rec)
			"serum":
				var to: int = ctx.player if e.get("to", "player") == "player" else RunAccess.least_serum(run)
				if to != -1:
					RunAccess.add_serum(run, to, e.samples)
			"recruit":
				_recruits(run, ns, e, ctx)
			"item":
				for rec in _targets(run, ns, e.who, ctx):
					var got: Array = []
					var counts := GearTags.counts(rec)
					for i in e.get("count", 1):
						var id := GearDraw.draw_item(run.rng, counts, e.get("rarity", "common"), got)
						if id != "":
							got.append(id)
							Loadout.equip(run, rec, id)
							RunAccess.emit(run, {"type": "item_gained", "sid": rec.id, "item": id})
					if not got.is_empty():
						ns.results.append("%s gets %s." % [rec.name, ", ".join(got.map(func(id): return GearData.item_name(id)))])
			"gun":
				for rec in _targets(run, ns, e.who, ctx):
					var id: String = GearRun.gun_card(run.rng, rec, e.get("rarity", "uncommon")).get("id", "")
					if id == "":
						RunAccess.add_supplies(run, Weapons.PRICES.uncommon / 2)
						ns.results.append("%s already carries everything in there; the rest is sold on." % rec.name)
						continue
					Loadout.add_gun(rec, id)
					ns.results.append("%s takes the %s." % [rec.name, Weapons.gun_name(id)])
					RunAccess.emit(run, {"type": "gun_gained", "sid": rec.id, "gun": id})
			"modifier":
				RunAccess.add_modifier(run, e.key, e.value)
			"mark":
				for rec in _targets(run, ns, e.who, ctx):
					RunAccess.mark_soldier(run, e.key, rec.id)
			"sit_out":
				for rec in _targets(run, ns, e.who, ctx):
					rec.sit_out += 1
					RunAccess.emit(run, {"type": "sit_out", "sid": rec.id, "fights": rec.sit_out})
			"fight":
				var ambush: bool = e.get("ambush", false)
				ns.fight = {"kind": RunMap.AMBUSH if ambush else RunMap.SKIRMISH, "objective": e.objective}
				run.modifiers["pending_fight"] = ns.fight.duplicate()
				if ambush:
					RunAccess.add_modifier(run, "ambush", true)
				if e.get("small", false):
					RunAccess.add_modifier(run, "extra_enemies", -1)
			"send_home":
				for rec in _targets(run, ns, e.who, ctx):
					RunAccess.send_home(run, rec)
					var r := RunAccess.add_recruit(run, rec.owner)
					RunAccess.grant_perk_pick(run, r)
					ns.results.append("%s joins %s's reserve." % [r.name, "their owner"])
			"chance":
				var hit: bool = run.rng.randf() < e.p
				_run_effects(run, ns, e.then if hit else e.get("else", []), ctx)
			"if_infected":
				var recs := _targets(run, ns, e.who, ctx)
				var yes: bool = not recs.is_empty() and recs[0].infection >= e.at_least
				_run_effects(run, ns, e.then if yes else e.get("else", []), ctx)


static func _recruits(run, ns: Dictionary, e: Dictionary, ctx: Dictionary) -> void:
	var count: int = e.get("count", 1)
	var carrier: int = run.rng.randi_range(0, count - 1) if e.get("carrier", false) else -1
	for i in count:
		var to: int = ctx.player if e.get("to", "player") == "player" else RunAccess.fewest_recruits(run)
		if to == -1:
			return
		var infection: int = RunAccess.CARRIER_INFECTION if i == carrier else e.get("infection", 0)
		var r := RunAccess.add_recruit(run, to, "", infection)
		if i == carrier:
			r["hidden_carrier"] = true
		ns.results.append("%s joins the reserve." % r.name)


## Fills {subject} and {soldier} with soldier names.
static func _fill(run, ns: Dictionary, text: String, ctx: Dictionary = {}) -> String:
	if "{subject}" in text:
		var s = RunAccess.soldier(run, ns.subject)
		text = text.replace("{subject}", s.name if s != null else "A soldier")
	if "{soldier}" in text:
		var rec = ctx.get("soldier")
		text = text.replace("{soldier}", rec.name if rec != null else "Someone")
	return text


# --- previews ------------------------------------------------------------------------------

## What picking option `id` would do to each soldier, without touching the run, for the squad
## panel's hover preview: {soldier id: {"infection": new value, "hp": new value, "mutation": +n,
## "lose_mutation": n, "perk": n, "items": n, "gun": n, "sit_out": n, "leaves": true,
## "graft": id, "maybe": true}}. Walks the same effect list as _run_effects; a chance roll previews its
## hit branch, marked "maybe".
static func preview(run, ns: Dictionary, id: String, player: int, soldier_id := -1) -> Dictionary:
	var out := {}
	var opt := _option(ns, id)
	if opt.is_empty():
		return out
	var ctx := {"player": player, "soldier": RunAccess.soldier(run, soldier_id) if soldier_id != -1 else null}
	if opt.get("generated", false):
		if ctx.soldier != null:
			out[ctx.soldier.id] = {"items": 1}
		return out
	_preview_effects(run, ns, opt.get("effects", []), ctx, out, false)
	return out


static func _preview_effects(run, ns: Dictionary, effects: Array, ctx: Dictionary, out: Dictionary, maybe: bool) -> void:
	for e in effects:
		if e.has("unless_class") and RunAccess.has_class(run, e.unless_class):
			continue
		match e.op:
			"chance":
				_preview_effects(run, ns, e.then, ctx, out, true)
			"if_infected":
				var recs := _targets(run, ns, e.who, ctx)
				var yes: bool = not recs.is_empty() and _previewed(out, recs[0], "infection", recs[0].infection) >= e.at_least
				_preview_effects(run, ns, e.then if yes else e.get("else", []), ctx, out, maybe)
			_:
				if not e.has("who"):
					continue
				for rec in _targets(run, ns, e.who, ctx):
					var d: Dictionary = out.get(rec.id, {})
					match e.op:
						"infection":
							var from: int = d.get("infection", rec.infection)
							d.infection = clampi(from + e.amount, 0, RunAccess.MAX_INFECTION_OUT_OF_FIGHT)
						"heal_pct":
							var from: int = d.get("hp", rec.hp)
							d.hp = clampi(from + ceili(rec.max_hp * e.pct / 100.0), 1, rec.max_hp)
						"hurt_pct":
							var from: int = d.get("hp", rec.hp)
							d.hp = maxi(1, from - ceili(rec.max_hp * e.pct / 100.0))
						"mutation":
							d.mutation = d.get("mutation", 0) + 1
						"remove_mutation":
							d.lose_mutation = d.get("lose_mutation", 0) + 1
						"bloom_graft":
							var g := Grafts.bloom_offer(run, rec, "event%d" % int(run.fights_won))
							if g != "":
								d.graft = g
								var from: int = d.get("infection", rec.infection)
								d.infection = mini(RunAccess.MAX_INFECTION_OUT_OF_FIGHT, from + Grafts.bloom_infection(rec))
						"perk_pick":
							d.perk = d.get("perk", 0) + 1
						"item":
							d.items = d.get("items", 0) + int(e.get("count", 1))
						"gun":
							d.gun = d.get("gun", 0) + 1
						"sit_out":
							d.sit_out = d.get("sit_out", 0) + 1
						"send_home":
							d.leaves = true
						_:
							continue
					if maybe:
						d.maybe = true
					out[rec.id] = d


static func _previewed(out: Dictionary, rec: Dictionary, key: String, now: int) -> int:
	return out.get(rec.id, {}).get(key, now)
