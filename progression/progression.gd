class_name Progression
extends RefCounted
## A soldier's growth within a run: rank 1-5, class perks, grafted mutations, Serum cures.
## OWNER: progression workstream. Called by the run framework (RunSoldier, RunRules) through
## RunHooks, by GearRun for perk/mutation reward cards and tag counts, and by NodeRules for events.
##
## The record ("prog") is a plain Dictionary stored at soldier_record.prog, opaque to other modules:
##   kind, rank (1-5), perks: Array[String], picks (rank-up perk picks waiting),
##   bonus_picks (extra picks that don't raise rank), picks_taken (counter, seeds the offers),
##   mutations: {slot: id}, inoculated (fights left at half Infection gain),
##   bond: {"id", "partner"} (partner = soldier sid), offers: Array of pending mutation offers
##   ({"cards": [ids], "source": "nest"|"event"}), grafts: {slot: id} and bedding (see Grafts).
## Functions that take `record` accept the framework soldier record (Infection lives there as
## record.infection; prog at record.prog) or a bare prog Dictionary.

const TAGS: Array[String] = ["Burn", "Mark", "Suppress", "Overwatch", "Close", "Strain", "Purge", "Guard"]
const MAX_RANK := 5
## Run fight numbers after which a surviving soldier ranks up.
const RANK_FIGHTS: Array[int] = [1, 3, 5, 7]
const RARE_FROM_RANK := 4
const OFFER_SIZE := 3
const INOCULATED_FIGHTS := 2
## Serum samples for one full cure (2 doses of 2 samples).
const CURE_SAMPLES := 4
const BASE_CLASSES: Array[String] = ["trooper", "marksman", "medic", "breacher"]
## Graft Infection never Turns a soldier between fights.
const GRAFT_CAP := 99
const MUTATING_AT := 50

## Starter mutations for a one-off mission (main menu quick play), so the mutation buttons still
## have something to show when a soldier gets infected.
const QUICK_PLAY_MUTATIONS := {
	"trooper": {"exposed": "adrenal_surge", "mutating": "chitin_plates"},
	"marksman": {"exposed": "adrenal_surge", "mutating": "acid_spit"},
	"medic": {"exposed": "clotting_blood", "mutating": "rally_musk"},
	"breacher": {"exposed": "hollow_bones", "mutating": "leech_bite"},
	"hazmat": {"exposed": "lure_scent", "mutating": "acid_spit"},
	"vector": {"exposed": "adrenal_surge", "mutating": "leech_bite", "strain": "flies"},
	"reaper": {"exposed": "hollow_bones", "mutating": "leech_bite"},
	"warden": {"exposed": "clotting_blood", "mutating": "chitin_plates"},
}

## How each unlockable class is earned, one short sentence for menus (Field HQ).
const CLASS_UNLOCK_HINTS := {
	"hazmat": "Beat the Act 1 boss.",
	"vector": "Win a fight with a soldier at Mutating Infection or higher who didn't Turn.",
	"reaper": "Win a fight where one soldier killed 3 enemies standing next to them.",
	"warden": "Win a fight where one soldier was hit 4 times and lived.",
}
## Unlock thresholds for the melee classes (Unit status counters kept by Kit).
const REAPER_CLOSE_KILLS := 3
const WARDEN_HITS_TAKEN := 4


# ---------------------------------------------------------------- record

static func new_record(kind: String) -> Dictionary:
	return {"kind": kind, "rank": 1, "perks": [], "picks": 0, "bonus_picks": 0, "picks_taken": 0,
		"mutations": {}, "inoculated": 0, "bond": {}, "offers": [], "grafts": {}, "bedding": false}


static func quick_play_record(kind: String) -> Dictionary:
	var p := new_record(kind)
	p.mutations = QUICK_PLAY_MUTATIONS.get(kind, {}).duplicate()
	return p


static func _prog(record: Dictionary) -> Dictionary:
	if record.has("prog"):
		return record.prog
	return record


static func is_vector(record: Dictionary) -> bool:
	return _prog(record).get("kind", record.get("kind", "")) == "vector"


static func max_hp(kind: String, prog: Dictionary) -> int:
	var hp: int = UnitData.SOLDIERS.get(kind, {}).get("max_hp", 1) + int(prog.get("rank", 1)) - 1
	for id in prog.get("perks", []):
		hp += int(PerkData.PERKS.get(id, {}).get("max_hp", 0))
	return hp


## Stamps the record onto a freshly made Unit (before HP and Infection are restored).
static func apply_record(u: Unit, prog: Dictionary) -> void:
	u.status["rank"] = int(prog.get("rank", 1))
	u.status["perks"] = (prog.get("perks", []) as Array).duplicate()
	u.status["mutations"] = (prog.get("mutations", {}) as Dictionary).duplicate()
	if not (prog.get("bond", {}) as Dictionary).is_empty():
		u.status["bond"] = {"id": prog.bond.id, "partner_sid": prog.bond.partner}
	if int(prog.get("inoculated", 0)) > 0:
		u.status["inoculated"] = true
	u.max_hp = max_hp(u.kind, prog)
	Grafts.apply_to_unit(u, prog)
	u.hp = u.max_hp
	for id in prog.get("perks", []):
		var p: Dictionary = PerkData.PERKS.get(id, {})
		u.defense += int(p.get("defense", 0))
		u.mobility += int(p.get("mobility", 0))
		if p.has("ability") and not u.abilities.has(p.ability):
			u.abilities.append(p.ability)
	var sig := Signatures.for_class(u.kind)
	if sig != "" and int(prog.get("rank", 1)) >= Signatures.UNLOCK_RANK and not u.abilities.has(sig):
		u.abilities.append(sig)
	Infection.sync_passives(u)
	Kit.refresh_stats(null, u)


## After a fight the soldier survived. The framework has already copied HP/Infection back.
## Queues a rank-up pick after fights 1, 3, 5 and 7. Returns true if the soldier ranked up.
static func after_fight(prog: Dictionary, u: Unit, fight_number: int) -> bool:
	if u.status.get("cured", false):
		prog.mutations = {}
		prog.bond = {}
		prog.inoculated = INOCULATED_FIGHTS
	elif int(prog.get("inoculated", 0)) > 0:
		prog.inoculated = int(prog.inoculated) - 1
	prog.bedding = false   # a fresh Machine part has bedded in
	if RANK_FIGHTS.has(fight_number) and int(prog.get("rank", 1)) < MAX_RANK:
		prog.rank = int(prog.get("rank", 1)) + 1
		prog.picks = int(prog.get("picks", 0)) + 1
		return true
	return false


## A reserve recruit replaces a lost soldier: one rank below them (minimum 1), picks made on arrival.
static func on_recruit_deployed(new_prog: Dictionary, lost_prog: Dictionary) -> void:
	var rank := maxi(1, int(lost_prog.get("rank", 1)) - 1)
	new_prog.rank = rank
	new_prog.picks = rank - 1


static func pending_picks(record: Dictionary) -> int:
	var p := _prog(record)
	return int(p.get("picks", 0)) + int(p.get("bonus_picks", 0))


## True while any active soldier has a perk pick or mutation offer waiting (holds the REWARD phase).
static func has_pending(run: RunState) -> bool:
	for r in run.soldiers:
		if r.get("status", "") == RunSoldier.ACTIVE and (pending_picks(r) > 0 or not _prog(r).get("offers", []).is_empty()):
			return true
	return false


static func grant_perk_pick(_run: RunState, record: Dictionary) -> void:
	var p := _prog(record)
	p.bonus_picks = int(p.get("bonus_picks", 0)) + 1


# ---------------------------------------------------------------- perks

## Perk ids the soldier could be offered now: their class pool minus owned, rares from Rank 4.
static func perk_pool(record: Dictionary) -> Array[String]:
	var p := _prog(record)
	var out: Array[String] = []
	for id in PerkData.pool(p.get("kind", record.get("kind", ""))):
		if p.get("perks", []).has(id):
			continue
		if PerkData.PERKS[id].rare and int(p.get("rank", 1)) < RARE_FROM_RANK:
			continue
		out.append(id)
	return out


## The 1-of-3 perk offer for this soldier's next pick. Deterministic from the run seed, the
## soldier and how many picks they've made, so every peer and the pick screen agree without state.
static func perk_offer(run: RunState, record: Dictionary) -> Array[String]:
	var r := RandomNumberGenerator.new()
	r.seed = hash([run.seed, record.get("id", 0), int(_prog(record).get("picks_taken", 0)), "perk"])
	return _draw(r, perk_pool(record), OFFER_SIZE)


static func _draw(r: RandomNumberGenerator, pool: Array[String], n: int) -> Array[String]:
	var left := pool.duplicate()
	var out: Array[String] = []
	while out.size() < n and not left.is_empty():
		out.append(left.pop_at(r.randi() % left.size()))
	return out


static func take_perk(record: Dictionary, id: String) -> void:
	var p := _prog(record)
	if not p.has("perks"):
		p.perks = []
	p.perks.append(id)
	p.picks_taken = int(p.get("picks_taken", 0)) + 1


static func perk_name(id: String) -> String:
	return PerkData.PERKS.get(id, {}).get("name", id)


# ---------------------------------------------------------------- mutations

static func mutation_name(id: String) -> String:
	return MutationData.get_def(id).get("name", id)


static func mutations_of(record: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in _prog(record).get("mutations", {}).values():
		out.append(id)
	return out


## Infection.Tier the record's carried Infection is at (bare prog records count as Clean).
static func _tier(record: Dictionary) -> int:
	return Infection.tier(int(record.get("infection", 0)))


## Grafts `id` into its slot (replacing what was there) and adds the graft cost to the soldier's
## Infection. Returns "" on success or a reason.
static func graft(record: Dictionary, id: String) -> String:
	var err := graft_error(record, id)
	if err != "":
		return err
	var m := MutationData.get_def(id)
	var p := _prog(record)
	if not p.has("mutations"):
		p.mutations = {}
	var old: String = p.mutations.get(m.slot, "")
	if old != "" and MutationData.get_def(old).get("bonded", false):
		p.bond = {}
	p.mutations[m.slot] = id
	if record.has("prog"):
		record.infection = mini(GRAFT_CAP, int(record.get("infection", 0)) + MutationData.graft_cost(id))
	return ""


static func graft_error(record: Dictionary, id: String) -> String:
	var m := MutationData.get_def(id)
	if m.is_empty():
		return "Unknown mutation"
	if m.get("vector", false) and not is_vector(record):
		return "Only a Vector can take that"
	if mutations_of(record).has(id):
		return "Already grafted"
	return ""


## Bonded graft: both soldiers pay and use their Mutating slot. Records are framework records.
static func graft_bonded(a: Dictionary, b: Dictionary, id: String) -> String:
	if not MutationData.get_def(id).get("bonded", false):
		return "Not a Bonded mutation"
	if a == b or a.get("id", -1) == b.get("id", -2):
		return "Bond two different soldiers"
	for r in [a, b]:
		var err := graft(r, id)
		if err != "":
			return err
	_prog(a).bond = {"id": id, "partner": b.get("id", -1)}
	_prog(b).bond = {"id": id, "partner": a.get("id", -1)}
	return ""


static func remove_mutation(record: Dictionary, id: String) -> void:
	var p := _prog(record)
	for slot in p.get("mutations", {}).keys():
		if p.mutations[slot] == id:
			p.mutations.erase(slot)
	if p.get("bond", {}).get("id", "") == id:
		p.bond = {}


## Full cure between fights: Infection to its floor (0 without Bloom grafts), every mutation
## wiped, Inoculated for 2 fights. Grafts stay.
static func full_cure(record: Dictionary) -> void:
	var p := _prog(record)
	p.mutations = {}
	p.bond = {}
	p.inoculated = INOCULATED_FIGHTS
	if record.has("prog"):
		record.infection = Grafts.record_floor(record)


## Slot a mutation card should come from: weighted toward the tier the soldier's Infection is
## closest to (3:1:1).
static func _pick_slot(rng: RandomNumberGenerator, record: Dictionary) -> String:
	var inf := int(record.get("infection", 0))
	var near := "exposed" if inf < 37 else ("mutating" if inf < 62 else "critical")
	var weights := {"exposed": 1, "mutating": 1, "critical": 1}
	weights[near] = 3
	var roll := rng.randi() % 5
	for slot in ["exposed", "mutating", "critical"]:
		roll -= weights[slot]
		if roll < 0:
			return slot
	return near


static func _candidates(record: Dictionary, pool: Array[String]) -> Array[String]:
	var have := mutations_of(record)
	return pool.filter(func(id): return not have.has(id))


## One mutation reward card for GearRun's 1-of-3 ({} if none). Vectors draw from their Strain
## pool half the time.
static func mutation_card(rng: RandomNumberGenerator, record: Dictionary) -> Dictionary:
	var pool: Array[String] = []
	if is_vector(record) and rng.randf() < 0.5:
		pool = _candidates(record, MutationData.vector_pool())
	if pool.is_empty():
		pool = _candidates(record, MutationData.regular_pool(_pick_slot(rng, record)))
	if pool.is_empty():
		for slot in ["exposed", "mutating", "critical"]:
			pool.append_array(_candidates(record, MutationData.regular_pool(slot)))
	if pool.is_empty():
		return {}
	return mutation_card_for(pool[rng.randi() % pool.size()])


static func mutation_card_for(id: String) -> Dictionary:
	var m := MutationData.get_def(id)
	return {"kind": "mutation", "id": id, "name": m.name, "desc": "%s Drawback: %s" % [m.desc, m.drawback],
		"tag": m.tag, "tier": MutationData.awake_at(id), "slot": m.slot, "graft": MutationData.graft_cost(id),
		"bonded": m.get("bonded", false)}


## One perk reward card (an extra pick from the class pool, no rank change), {} if none left.
static func perk_card(rng: RandomNumberGenerator, record: Dictionary) -> Dictionary:
	var pool := perk_pool(record)
	if pool.is_empty():
		return {}
	var id: String = pool[rng.randi() % pool.size()]
	var p: Dictionary = PerkData.PERKS[id]
	return {"kind": "perk", "id": id, "name": p.name, "desc": p.desc, "tag": p.tag,
		"rarity": "rare" if p.rare else "common"}


## Applies a reward card picked in GearRun's screen. Returns "" or a reason.
static func apply_card(record: Dictionary, card: Dictionary) -> String:
	match card.get("kind", ""):
		"perk":
			if _prog(record).get("perks", []).has(card.id):
				return "Already has that perk"
			take_perk(record, card.id)
			return ""
		"mutation":
			return graft(record, card.id)
		"graft":
			if Grafts.of(record).has(GraftData.slot_of(card.id)):
				return "That slot is taken"
			Grafts.take(record, card.id)
			return ""
	return "Unknown card"


## GearRun.on_fight_won: a Bloom graft card in the offer after a nest or a Critical fight end.
static func add_graft_card(run: RunState, record: Dictionary, fight_kind: String, cards: Array) -> void:
	Grafts.add_reward_card(run, record, fight_kind, cards)


## Who `record` can share a Bonded mutation with: in co-op a soldier of another player, solo any
## other soldier in the squad.
static func bond_partners(run: RunState, record: Dictionary) -> Array:
	var solo := run.players.size() <= 1
	return run.squad().filter(func(o: Dictionary) -> bool:
		return o.get("id", -1) != record.get("id", -2) and (solo or o.get("owner", -1) != record.get("owner", -1)))


## Queues an Infested nest's 1-of-3 mutation pick for this soldier (at least one Mutating or
## Critical; a Bonded one may appear when it has a partner, see bond_partners). Picked with prog_graft.
static func queue_nest_offer(run: RunState, record: Dictionary) -> void:
	var rng: RandomNumberGenerator = run.rng
	var high := _candidates(record, MutationData.regular_pool("mutating") + MutationData.regular_pool("critical"))
	var cards: Array[String] = []
	if not high.is_empty():
		cards.append(high[rng.randi() % high.size()])
	if not bond_partners(run, record).is_empty() and rng.randf() < 0.5:
		var bonded := _candidates(record, MutationData.bonded_pool())
		if not bonded.is_empty():
			cards.append(bonded[rng.randi() % bonded.size()])
	var guard := 0
	while cards.size() < OFFER_SIZE and guard < 20:
		guard += 1
		var c := mutation_card(rng, record)
		if not c.is_empty() and not cards.has(c.id):
			cards.append(c.id)
	if not cards.is_empty():
		_prog(record).offers.append({"cards": cards, "source": "nest"})


## Event hook: a random mutation the soldier doesn't have, grafted now. Returns the id or "".
static func grant_random_mutation(run: RunState, record: Dictionary) -> String:
	var c := mutation_card(run.rng, record)
	if c.is_empty() or graft(record, c.id) != "":
		return ""
	return c.id


# ---------------------------------------------------------------- tags

## Tag counts from class perks, grafts and awake mutations (+1 Strain per awake mutation), only
## tags above 0, e.g. {"Guard": 2, "Strain": 1}. GearRun adds gear.
static func tag_counts(record: Dictionary) -> Dictionary:
	var p := _prog(record)
	return _count(p.get("perks", []), p.get("mutations", {}), _tier(record), Grafts.of(record))


static func unit_tag_counts(u: Unit) -> Dictionary:
	return _count(u.status.get("perks", []), u.status.get("mutations", {}), Infection.tier(u.infection), Grafts.of_unit(u))


static func _count(perks: Array, mutations: Dictionary, tier: int, grafts: Dictionary = {}) -> Dictionary:
	var out := Grafts.tag_counts(grafts)
	for id in perks:
		var tag: String = PerkData.PERKS.get(id, {}).get("tag", "")
		if tag != "":
			out[tag] = int(out.get(tag, 0)) + 1
	for id in mutations.values():
		if tier >= MutationData.awake_at(id) and tier < Infection.Tier.TURNED:
			var tag: String = MutationData.get_def(id).tag
			out[tag] = int(out.get(tag, 0)) + 1
			out["Strain"] = int(out.get("Strain", 0)) + 1
	return out


# ---------------------------------------------------------------- unlocks

static func unlocked_classes(meta: Dictionary) -> Array[String]:
	var out := BASE_CLASSES.duplicate()
	if meta.get("act1_boss_beaten", false) or meta.get("hazmat_unlocked", false):
		out.append("hazmat")
	if meta.get("vector_unlocked", false):
		out.append("vector")
	for kind in ["reaper", "warden"]:
		if meta.get(kind + "_unlocked", false):
			out.append(kind)
	return out


## After every fight (outcome = RunRules.fight_outcome), a won fight unlocks a class when one
## surviving, un-Turned soldier ended it: at Mutating or higher (Vector), with 3 kills on adjacent
## enemies (Reaper), or after taking 4 hits (Warden). See CLASS_UNLOCK_HINTS.
static func on_fight_end(run: RunState, outcome: Dictionary) -> void:
	Grafts.on_fight_end(run, outcome)
	if outcome.get("result", Types.Result.NONE) != Types.Result.VICTORY:
		return
	for e in outcome.get("soldiers", []):
		var u := Unit.from_dict(e.unit)
		if not u.is_alive() or u.status.get("turned", false):
			continue
		if u.infection >= MUTATING_AT:
			_unlock(run, "vector")
		if int(u.status.get("close_kills", 0)) >= REAPER_CLOSE_KILLS:
			_unlock(run, "reaper")
		if int(u.status.get("hits_taken", 0)) >= WARDEN_HITS_TAKEN:
			_unlock(run, "warden")


static func _unlock(run: RunState, kind: String) -> void:
	if run.meta.get(kind + "_unlocked", false):
		return
	run.meta[kind + "_unlocked"] = true
	run.emit({"type": "class_unlocked", "kind": kind})


# ---------------------------------------------------------------- run actions

## prog_perk_pick {sid, perk}, prog_graft {sid, mutation, partner?} (from a queued offer),
## prog_skip_offer {sid}, prog_serum {sid} (full cure for 4 of the player's Serum samples).
static func validate(run: RunState, action: Dictionary) -> String:
	var r := run.get_soldier(int(action.get("sid", -1)))
	if r.is_empty() or r.get("status", "") != RunSoldier.ACTIVE:
		return "No such soldier"
	if run.controller_of(r) != int(action.get("player", -1)):
		return "Not your soldier"
	if run.phase == RunState.Phase.FIGHT or run.phase == RunState.Phase.ENDED:
		return "Not now"
	var p := _prog(r)
	match action.get("type", ""):
		"prog_perk_pick":
			if pending_picks(r) <= 0:
				return "No perk pick waiting"
			if not perk_offer(run, r).has(str(action.get("perk", ""))):
				return "Not on offer"
		"prog_graft":
			if p.get("offers", []).is_empty():
				return "No mutation offer waiting"
			var id := str(action.get("mutation", ""))
			if not p.offers[0].cards.has(id):
				return "Not on offer"
			if MutationData.get_def(id).get("bonded", false):
				var partner := run.get_soldier(int(action.get("partner", -1)))
				if partner.is_empty() or partner.get("status", "") != RunSoldier.ACTIVE:
					return "Pick a partner"
				if not bond_partners(run, r).has(partner):
					return "Bond two soldiers of different players" if run.players.size() > 1 else "Bond two different soldiers"
			else:
				return graft_error(r, id)
		"prog_skip_offer":
			if p.get("offers", []).is_empty():
				return "No mutation offer waiting"
		"prog_serum":
			if int(run.serum.get(int(action.player), 0)) < CURE_SAMPLES:
				return "Not enough Serum (%d samples needed)" % CURE_SAMPLES
		_:
			return "Unknown action"
	return ""


static func apply(run: RunState, action: Dictionary) -> void:
	var r := run.get_soldier(int(action.sid))
	var p := _prog(r)
	match action.type:
		"prog_perk_pick":
			take_perk(r, action.perk)
			if int(p.get("picks", 0)) > 0:
				p.picks = int(p.picks) - 1
			else:
				p.bonus_picks = int(p.bonus_picks) - 1
			run.emit({"type": "perk_pick", "sid": r.id, "perk": action.perk})
		"prog_graft":
			p.offers.pop_front()
			var id: String = action.mutation
			if MutationData.get_def(id).get("bonded", false):
				graft_bonded(r, run.get_soldier(int(action.partner)), id)
			else:
				graft(r, id)
			run.emit({"type": "graft", "sid": r.id, "mutation": id})
		"prog_skip_offer":
			p.offers.pop_front()
		"prog_serum":
			RunRules.add_serum(run, int(action.player), -CURE_SAMPLES, "full cure")
			full_cure(r)
			run.emit({"type": "cured", "sid": r.id})


static func pick_screen() -> Script:
	return load("res://progression/pick_screen.gd")


## Default choices for headless autoplay (RunAutoplay, net playtest): each waiting perk pick takes
## the first card on offer, and mutation offers are skipped.
static func autoplay_actions(run: RunState) -> Array:
	var out: Array = []
	for r in run.squad():
		var player := run.controller_of(r)
		if pending_picks(r) > 0:
			var offer := perk_offer(run, r)
			if not offer.is_empty():
				out.append({"type": "prog_perk_pick", "player": player, "sid": r.id, "perk": offer[0]})
		elif not _prog(r).get("offers", []).is_empty():
			out.append({"type": "prog_skip_offer", "player": player, "sid": r.id})
	return out
