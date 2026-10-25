class_name Grafts
extends RefCounted
## Graft rules: four body-part slots per soldier, Machine Refits and Bloom parts (data in
## GraftData). OWNER: progression workstream.
##
## Record keys (on soldier_record.prog): grafts {slot: id}, bedding (true while a fresh Machine
## part beds in: -1 move in the next fight). Unit status keys (stamped by apply_record):
##   "grafts": {slot: id}     every graft the soldier wears
##   "graft_bedding": true    fights this mission at -1 move
##   "k_jammed": int          phase index a Shrieker's scream jams Machine parts until
##   "k_slowed": int          phase index an enemy that clawed a Heart knot is slowed until
##   "k_leapt": true          Runner legs' Leap is spent this fight
##
## Functions that take `record` accept the framework soldier record or a bare prog Dictionary.
## Grafts survive Serum: only the Field hospital's Amputate and refit removes a Bloom part.

static func _prog(record: Dictionary) -> Dictionary:
	return record.prog if record.has("prog") else record


static func of(record: Dictionary) -> Dictionary:
	return _prog(record).get("grafts", {})


static func of_unit(u: Unit) -> Dictionary:
	return u.status.get("grafts", {})


static func count(grafts: Dictionary, path: String) -> int:
	var n := 0
	for id in grafts.values():
		if GraftData.path_of(id) == path:
			n += 1
	return n


## Lowest Infection a soldier can go to: 10 per Bloom part, even with Serum.
static func floor_of(grafts: Dictionary) -> int:
	return count(grafts, GraftData.BLOOM) * GraftData.FLOOR_PER_PART


static func record_floor(record: Dictionary) -> int:
	return floor_of(of(record))


static func unit_floor(u: Unit) -> int:
	return floor_of(of_unit(u))


static func open_slots(record: Dictionary) -> Array[String]:
	var have := of(record)
	var out: Array[String] = []
	for slot in GraftData.SLOTS:
		if not have.has(slot):
			out.append(slot)
	return out


static func _act(run) -> int:
	return int(run.act) if run != null else GraftData.FROM_ACT


## Why `record` can't take a graft at all right now ("" if it can): from Act 2, Rank 3, a free slot.
static func eligible_error(run, record: Dictionary) -> String:
	if _act(run) < GraftData.FROM_ACT:
		return "Grafts open in Act %d" % GraftData.FROM_ACT
	if int(_prog(record).get("rank", 1)) < GraftData.FROM_RANK:
		return "Needs Rank %d" % GraftData.FROM_RANK
	if open_slots(record).is_empty():
		return "Every slot is grafted"
	return ""


static func eligible(run, record: Dictionary) -> bool:
	return eligible_error(run, record) == ""


static func can_take_error(run, record: Dictionary, id: String) -> String:
	if GraftData.get_def(id).is_empty():
		return "Unknown graft"
	var err := eligible_error(run, record)
	if err != "":
		return err
	if of(record).has(GraftData.slot_of(id)):
		return "%s slot is taken" % GraftData.SLOT_NAMES[GraftData.slot_of(id)]
	return ""


static func _kind(record: Dictionary) -> String:
	return str(_prog(record).get("kind", record.get("kind", "")))


## Supplies a Machine refit costs this soldier (Hazmat's Sealed Suit pairs with Machine parts).
static func refit_price(record: Dictionary) -> int:
	return GraftData.HAZMAT_REFIT_PRICE if _kind(record) == "hazmat" else GraftData.REFIT_PRICE


## Infection a Bloom graft adds to this soldier (Vector pays less).
static func bloom_infection(record: Dictionary) -> int:
	return GraftData.VECTOR_BLOOM_INFECTION if _kind(record) == "vector" else GraftData.BLOOM_INFECTION


## Grafts `id` into its slot. Machine: the next fight at -1 move (the caller takes the Supplies).
## Bloom: +15 Infection on the record, never past 99 between fights.
static func take(record: Dictionary, id: String) -> void:
	var p := _prog(record)
	if not p.has("grafts"):
		p.grafts = {}
	p.grafts[GraftData.slot_of(id)] = id
	_on_gain(record, id)
	if GraftData.is_bloom(id):
		if record.has("prog"):
			record.infection = mini(Progression.GRAFT_CAP, maxi(record_floor(record), int(record.get("infection", 0)) + bloom_infection(record)))
	else:
		p.bedding = true


## Plated ribs' +2 max HP lands on the run record straight away (like gear HP).
static func _on_gain(record: Dictionary, id: String) -> void:
	if id == "plated_ribs" and record.has("max_hp"):
		record.max_hp = int(record.max_hp) + GraftData.RIBS_HP
		record.hp = int(record.hp) + GraftData.RIBS_HP


## The Bloom slot Amputate and refit would cut ("" if none): the first in slot order.
static func amputate_slot(record: Dictionary) -> String:
	var have := of(record)
	for slot in GraftData.SLOTS:
		if have.has(slot) and GraftData.is_bloom(have[slot]):
			return slot
	return ""


## Field hospital: swaps the Bloom part in `slot` for the Machine one, at AMPUTATE_HP HP.
static func amputate(record: Dictionary, slot: String) -> String:
	var machine := GraftData.for_slot(slot, GraftData.MACHINE)
	_prog(record).grafts[slot] = machine
	_prog(record).bedding = true
	_on_gain(record, machine)
	if record.has("hp"):
		record.hp = maxi(1, int(record.hp) - GraftData.AMPUTATE_HP)
	return machine


## A soldier's slots in a deterministic order for offers, rolled from the run seed and `salt`.
static func _roll_slot(run, record: Dictionary, salt: String) -> String:
	var open := open_slots(record)
	if open.is_empty():
		return ""
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(run.seed) if run != null else 0, record.get("id", 0), salt])
	return open[r.randi() % open.size()]


## The Machine part a node offers this soldier (a random free slot), "" if they can't take one.
static func machine_offer(run, record: Dictionary, salt: String) -> String:
	if not eligible(run, record):
		return ""
	return GraftData.for_slot(_roll_slot(run, record, salt), GraftData.MACHINE)


static func bloom_offer(run, record: Dictionary, salt: String) -> String:
	if not eligible(run, record):
		return ""
	return GraftData.for_slot(_roll_slot(run, record, salt), GraftData.BLOOM)


## A Bloom graft reward card for GearRun's 1-of-3 ({} if none).
static func card_for(record: Dictionary, id: String) -> Dictionary:
	if id == "":
		return {}
	var d := GraftData.get_def(id)
	return {"kind": "graft", "id": id, "name": d.name, "desc": d.desc, "slot": d.slot, "path": d.path,
		"tag": d.tag, "infection": bloom_infection(record) if GraftData.is_bloom(id) else 0}


## Called by GearRun.on_fight_won for each soldier's offer: a Bloom graft card after a nest, or
## when the soldier ended the fight at Critical (75+). Replaces the offer's last card.
static func add_reward_card(run, record: Dictionary, fight_kind: String, cards: Array) -> void:
	if cards.is_empty() or fight_kind == "boss":
		return
	if fight_kind != "nest" and int(record.get("infection", 0)) < Infection.CRITICAL_AT:
		return
	var card := card_for(record, bloom_offer(run, record, "reward%d" % int(run.fights_won)))
	if not card.is_empty():
		cards[cards.size() - 1] = card


## Event hook (Choir stall): a Bloom graft in a random free slot. Returns its id or "".
static func grant_bloom(run, record: Dictionary) -> String:
	var id := bloom_offer(run, record, "event%d" % int(run.fights_won))
	if id != "":
		take(record, id)
	return id


static func tag_counts(grafts: Dictionary) -> Dictionary:
	var out := {}
	for id in grafts.values():
		var t: String = GraftData.get_def(id).get("tag", "")
		if t != "":
			out[t] = int(out.get(t, 0)) + 1
	return out


# ---------------------------------------------------------------- missions

## Stamps the record's grafts on a fresh Unit (from Progression.apply_record).
static func apply_to_unit(u: Unit, prog: Dictionary) -> void:
	var g: Dictionary = prog.get("grafts", {})
	if g.is_empty():
		return
	u.status["grafts"] = g.duplicate()
	if prog.get("bedding", false):
		u.status["graft_bedding"] = true
	if has(u, "plated_ribs"):
		u.max_hp += GraftData.RIBS_HP
	for id in ["bloom_limb", "runner_legs"]:
		var ability: String = {"bloom_limb": "bloom_claw", "runner_legs": "runner_leap"}[id]
		if has(u, id) and not u.abilities.has(ability):
			u.abilities.append(ability)


static func has(u: Unit, id: String) -> bool:
	return of_unit(u).get(GraftData.slot_of(id), "") == id


## True while the graft works: Bloom parts always, Machine parts unless a scream jammed them.
static func active(s: GameState, u: Unit, id: String) -> bool:
	if not has(u, id):
		return false
	return GraftData.is_bloom(id) or s == null or not Combat.has_status(s, u, "k_jammed")


## Flat stat deltas from grafts, folded into Kit.refresh_stats.
static func stat_mods(s: GameState, u: Unit, want: Dictionary) -> void:
	if s != null and u.status.has("k_slowed") and Combat.has_status(s, u, "k_slowed"):
		want.mobility += GraftData.HEART_SLOW
	if of_unit(u).is_empty():
		return
	if active(s, u, "targeting_optic"):
		want.aim += GraftData.OPTIC_AIM
	if active(s, u, "hydraulic_legs"):
		want.mobility += GraftData.HYDRAULIC_MOBILITY
	if u.status.get("graft_bedding", false):
		want.mobility += GraftData.BEDDING_MOBILITY
	if active(s, u, "servo_arm"):
		# Heavy guns no longer slow the soldier: give back what the gun took.
		var gun := int(Weapons.stats(Weapons.id_of(u)).get("mobility", 0))
		if gun < 0:
			want.mobility -= gun


## Infection change after Machine parts (-10% of a gain per part, up to -30%).
static func infection_gain(s: GameState, u: Unit, amount: int) -> int:
	if amount <= 0:
		return amount
	var g := of_unit(u)
	if g.is_empty() or Combat.has_status(s, u, "k_jammed"):
		return amount
	var cut := mini(GraftData.GAIN_CUT_MAX, count(g, GraftData.MACHINE) * GraftData.GAIN_CUT_PER_PART)
	if cut <= 0:
		return amount
	return maxi(1, roundi(amount * (10 - cut) / 10.0))


## Plated ribs: Infection from spores and Spitters is halved.
static func filtered(s: GameState, u: Unit, amount: int) -> int:
	if amount <= 0 or not active(s, u, "plated_ribs"):
		return amount
	return maxi(1, amount / 2)


static func is_spitter(source: Unit) -> bool:
	return source != null and source.kind == "spitter"


## Targeting optic: Tags this soldier places last one turn (two phases) longer.
static func tag_bonus(s: GameState, u: Unit) -> int:
	return 2 if active(s, u, "targeting_optic") else 0


static func melee_bonus(s: GameState, u: Unit) -> int:
	return GraftData.SERVO_MELEE if active(s, u, "servo_arm") else 0


static func throw_bonus(u: Unit) -> float:
	return GraftData.SERVO_THROW if has(u, "servo_arm") else 0.0


## Hydraulic legs: ladders cost a normal step.
static func climbs(u: Unit) -> bool:
	return has(u, "hydraulic_legs")


static func sense_radius(u: Unit) -> int:
	return GraftData.LATTICE_RADIUS if has(u, "lattice_sight") else 0


## Start of the squad's phase: Heart knot regeneration.
static func on_team_phase_start(s: GameState, u: Unit) -> void:
	if has(u, "heart_knot") and Infection.tier(u.infection) >= Infection.Tier.MUTATING:
		Kit._heal(s, u, GraftData.HEART_REGEN, "heart_knot")


## A melee hit landed on `target`: a Heart knot slows the attacker for a turn.
static func after_melee(s: GameState, attacker: Unit, target: Unit) -> void:
	if not has(target, "heart_knot") or not attacker.is_alive() or not attacker.is_enemy_of(target):
		return
	attacker.status["k_slowed"] = Combat.phase_index(s) + 2
	s.emit({"type": "slowed", "unit": attacker.id, "by": target.id})
	Kit.refresh_stats(s, attacker)


## A Shrieker's scream: soldiers within `radius` jam their Machine parts until the end of their
## next phase.
static func jam(s: GameState, screamer: Unit, radius: float) -> void:
	for u in s.living(Types.Team.PLAYER):
		if count(of_unit(u), GraftData.MACHINE) == 0 or u.pos.distance_to(screamer.pos) > radius:
			continue
		u.status["k_jammed"] = Combat.phase_index(s) + 2
		s.emit({"type": "jammed", "unit": u.id, "by": screamer.id})
		Kit.refresh_stats(s, u)


# ---------------------------------------------------------------- abilities

## Cells a Leap can land on: free, walkable, within LEAP_RANGE (any level).
static func leap_cells(s: GameState, u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := GraftData.LEAP_RANGE
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := u.pos + Vector2i(dx, dy)
			if c == u.pos or Vector2(dx, dy).length() > r + 0.5:
				continue
			if s.grid.in_bounds(c) and s.grid.is_walkable(c) and s.unit_at(c) == null:
				out.append(c)
	return out


static func leap_error(s: GameState, u: Unit, cell: Variant) -> String:
	if u.status.get("k_leapt", false):
		return "Already used this fight"
	if not cell is Vector2i:
		return "No target cell"
	if not leap_cells(s, u).has(cell):
		return "Out of reach"
	return ""


## Leap: the soldier lands at `cell` in one bound. No overwatch fires on a jump.
static func leap(s: GameState, u: Unit, cell: Vector2i) -> void:
	var from := u.pos
	u.status["k_leapt"] = true
	u.hunkered = false
	u.pos = cell
	s.emit({"type": "move", "unit": u.id, "from": from, "path": [cell] as Array[Vector2i], "leap": true})
	s.emit({"type": "ability", "unit": u.id, "ability": "runner_leap", "cell": cell, "from": from})
	Vision.on_step(s, u)
	Hazards.on_move(s, u, [cell] as Array[Vector2i])


## Bloom Claw against `t`: one melee strike (ClassAbilities.strike) with the claw's damage.
static func claw(s: GameState, u: Unit, t: Unit) -> void:
	ClassAbilities.strike(s, u, t, "bloom_claw")
	if not t.is_alive() and u.is_alive():
		Kit._heal(s, u, GraftData.CLAW_KILL_HEAL, "bloom_limb")


# ---------------------------------------------------------------- after a fight

## Called from Progression.on_fight_end for every fight: Lattice sight at Critical hears the
## Source's Whispers (+1 Intel per soldier), whatever the result.
static func on_fight_end(run, outcome: Dictionary) -> void:
	for e in outcome.get("soldiers", []):
		var u := Unit.from_dict(e.unit)
		if u.is_alive() and not u.status.get("turned", false) and has(u, "lattice_sight") \
				and Infection.tier(u.infection) == Infection.Tier.CRITICAL:
			RunRules.add_intel(run, 1, "Whispers")
