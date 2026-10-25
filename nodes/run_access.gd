class_name RunAccess
extends RefCounted
## Every read and write the non-combat nodes make on the run goes through here, so the
## contracts this module leans on (RunState / RunRules from the run framework, Progression
## for perks and mutations) sit in one file. OWNER: nodes workstream.
##
## Progression is called late-bound (RunHooks) with fallbacks, so the nodes work before it lands.

## Outside a fight a soldier can't Turn: events and treatments stop just short of it.
const MAX_INFECTION_OUT_OF_FIGHT := 99
## The hidden carrier from Stragglers joins at Mutating, so they can Lapse in their first fight.
const CARRIER_INFECTION := 50


static func emit(run: RunState, ev: Dictionary) -> void:
	run.emit(ev)


## Players who are here and decide things (benched players don't).
static func active_players(run: RunState) -> Array:
	return Array(run.present_players())


static func is_active(run: RunState, player: int) -> bool:
	return player in run.present_players()


static func soldier(run: RunState, id: int):
	var r := run.get_soldier(id)
	return null if r.is_empty() else r


## Squad soldiers of present players (a benched player's soldiers are frozen).
static func active_soldiers(run: RunState) -> Array:
	var present := run.present_players()
	return run.squad().filter(func(r): return r.owner in present)


static func soldiers_of(run: RunState, player: int) -> Array:
	return run.soldiers_of(player)


static func has_class(run: RunState, kind: String) -> bool:
	return active_soldiers(run).any(func(r): return r.kind == kind)


static func add_supplies(run: RunState, amount: int, reason := "node") -> void:
	RunRules.add_supplies(run, amount, reason)


static func add_intel(run: RunState, amount: int, reason := "node") -> void:
	RunRules.add_intel(run, amount, reason)


static func add_outbreak(run: RunState, amount: int, reason := "node") -> void:
	RunRules.add_outbreak(run, amount, reason)


static func serum(run: RunState, player: int) -> int:
	return run.serum.get(player, 0)


static func add_serum(run: RunState, player: int, samples: int, reason := "node") -> void:
	RunRules.add_serum(run, player, samples, reason)


static func set_infection(run: RunState, rec: Dictionary, value: int) -> void:
	var low: int = RunHooks.call_static("Grafts", "record_floor", [rec], 0)   # Bloom grafts
	rec.infection = clampi(value, mini(low, MAX_INFECTION_OUT_OF_FIGHT), MAX_INFECTION_OUT_OF_FIGHT)
	emit(run, {"type": "soldier_infection", "sid": rec.id, "value": rec.infection})


static func add_infection(run: RunState, rec: Dictionary, amount: int) -> void:
	set_infection(run, rec, rec.infection + amount)


static func heal(run: RunState, rec: Dictionary, amount: int) -> void:
	rec.hp = clampi(rec.hp + amount, 1, rec.max_hp)
	emit(run, {"type": "soldier_hp", "sid": rec.id, "hp": rec.hp})


static func heal_pct(run: RunState, rec: Dictionary, pct: int) -> void:
	heal(run, rec, ceili(rec.max_hp * pct / 100.0))


## Loses `pct` of max HP, never below 1.
static func hurt_pct(run: RunState, rec: Dictionary, pct: int) -> void:
	rec.hp = maxi(1, rec.hp - ceili(rec.max_hp * pct / 100.0))
	emit(run, {"type": "soldier_hp", "sid": rec.id, "hp": rec.hp})


# --- perks and mutations (Progression) -------------------------------------------------

static func mutations_of(rec: Dictionary) -> Array:
	var fallback: Array = []
	return RunHooks.call_static("Progression", "mutations_of", [rec], fallback)


static func mutation_name(id: String) -> String:
	var fallback: String = id.capitalize()
	return RunHooks.call_static("Progression", "mutation_name", [id], fallback)


## Gives a random mutation the soldier doesn't have; returns its id, or "" if none is left.
static func add_random_mutation(run: RunState, rec: Dictionary) -> String:
	var id := ""
	if RunHooks.has("Progression", "grant_random_mutation"):
		# Progression adds the graft's own Infection; the event sets its own number instead.
		var before: int = rec.infection
		id = RunHooks.call_static("Progression", "grant_random_mutation", [run, rec], "")
		rec.infection = before
	else:
		var have := mutations_of(rec)
		var pool: Array = MutationData.MUTATIONS.keys().filter(func(m): return not m in have)
		if pool.is_empty():
			return ""
		id = pool[run.rng.randi_range(0, pool.size() - 1)]
		_fallback_mutations(rec).append(id)
	if id != "":
		emit(run, {"type": "soldier_mutation", "sid": rec.id, "mutation": id, "gained": true})
	return id


static func remove_mutation(run: RunState, rec: Dictionary, id: String) -> void:
	if RunHooks.has("Progression", "remove_mutation"):
		RunHooks.call_static("Progression", "remove_mutation", [rec, id])
	else:
		_fallback_mutations(rec).erase(id)
	emit(run, {"type": "soldier_mutation", "sid": rec.id, "mutation": id, "gained": false})


static func _fallback_mutations(rec: Dictionary) -> Array:
	if not rec.has("prog"):
		rec["prog"] = {}
	if not rec.prog.has("mutations"):
		rec.prog["mutations"] = []
	return rec.prog.mutations


## Hospital Full cure: Infection 0 and every mutation gone (Progression also sets Inoculated).
static func full_cure(run: RunState, rec: Dictionary) -> void:
	if RunHooks.has("Progression", "full_cure"):
		RunHooks.call_static("Progression", "full_cure", [rec])
	else:
		_fallback_mutations(rec).clear()
	set_infection(run, rec, 0)
	emit(run, {"type": "full_cure", "sid": rec.id})


## An extra 1-of-3 perk pick from the class pool that doesn't raise rank (hospital Train).
static func grant_perk_pick(run: RunState, rec: Dictionary) -> void:
	if RunHooks.has("Progression", "grant_perk_pick"):
		RunHooks.call_static("Progression", "grant_perk_pick", [run, rec])
	else:
		if not rec.has("prog"):
			rec["prog"] = {}
		rec.prog["extra_picks"] = rec.prog.get("extra_picks", 0) + 1
	emit(run, {"type": "perk_pick_granted", "sid": rec.id})


# --- recruits ----------------------------------------------------------------------------

static func reserve_size(run: RunState, player: int) -> int:
	return run.reserve_of(player).size()


## The present player with the smallest reserve (ties go to the lowest player id).
static func fewest_recruits(run: RunState) -> int:
	var best := -1
	for p in active_players(run):
		if best == -1 or reserve_size(run, p) < reserve_size(run, best):
			best = p
	return best


## The present player with the least Serum (ties go to the lowest player id).
static func least_serum(run: RunState) -> int:
	var best := -1
	for p in active_players(run):
		if best == -1 or serum(run, p) < serum(run, best):
			best = p
	return best


static func random_recruit_kind(run: RunState) -> String:
	return RunRules.RESERVE_CLASSES[run.rng.randi() % RunRules.RESERVE_CLASSES.size()]


## A surname no soldier in the run has yet (falls back to any if all are taken).
static func unused_name(run: RunState) -> String:
	var taken := run.soldiers.map(func(r): return r.name)
	var free: Array = RunSoldier.NAMES.filter(func(n): return not n in taken)
	if free.is_empty():
		free = RunSoldier.NAMES.duplicate()
	return free[run.rng.randi() % free.size()]


## A new recruit in `player`'s reserve. Returns the soldier record.
static func add_recruit(run: RunState, player: int, kind := "", infection := 0, name := "") -> Dictionary:
	var r := RunRules.add_recruit(run, player, kind, infection)
	r.name = name if name != "" else unused_name(run)
	return r


## The soldier leaves the run for good (not a death: Last seat flies them out).
static func send_home(run: RunState, rec: Dictionary) -> void:
	rec.status = RunSoldier.GONE
	emit(run, {"type": "soldier_lost", "sid": rec.id, "how": "sent_home"})


## Next-fight and map effects (see "Run framework" in docs/ARCHITECTURE.md). Ints add up,
## anything else is set.
static func add_modifier(run: RunState, key: String, value) -> void:
	var cur = run.modifiers.get(key)
	run.modifiers[key] = cur + value if cur is int and value is int else value
	emit(run, {"type": "modifier", "key": key, "value": run.modifiers[key]})


## Adds a soldier id to the list modifiers[key] (first_turn_action_loss).
static func mark_soldier(run: RunState, key: String, sid: int) -> void:
	var list: Array = run.modifiers.get(key, [])
	if not sid in list:
		list.append(sid)
	run.modifiers[key] = list
	emit(run, {"type": "modifier", "key": key, "value": list.duplicate()})


static func has_doctrine(run: RunState, id: String) -> bool:
	return id in run.modifiers.get("doctrines", [])
