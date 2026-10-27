class_name FieldHospital
extends RefCounted
## Field hospital: one treatment per soldier, chosen by the soldier's owner (design doc,
## Economy and rewards). Healing or purging anyone raises Outbreak by 1, once per visit;
## Train doesn't, so it's the "fast" rest. From Act 2 a Rank 3+ soldier can also be Refit with
## a Machine graft (one part offered per soldier per visit), and a Bloom part can be cut out and
## replaced by the slot's Machine one (Amputate and refit, see Grafts). OWNER: nodes workstream.

const PURGE_AMOUNT := 30
const PURGE_PRICE := 15
const CURE_SAMPLES := 4  # 2 doses
const OUTBREAK_COST := 1

const TREATMENTS := {
	"patch": {"name": "Patch up", "desc": "Heal to full HP and clear 1 injury", "cost": "Free"},
	"purge": {"name": "Purge", "desc": "-30 Infection", "cost": "15 Supplies"},
	"train": {"name": "Train", "desc": "One extra perk pick for the soldier's class", "cost": "Free"},
	"cure": {"name": "Full cure", "desc": "Infection to 0, removes all mutations, Scars stay", "cost": "2 Serum doses"},
	"refit": {"name": "Refit", "desc": "A Machine graft for a free body slot. -1 move next fight while it beds in", "cost": "40 Supplies"},
	"amputate": {"name": "Amputate", "desc": "Cut out a Bloom graft and Refit the slot with its Machine part", "cost": "30 Supplies"},
}
const ORDER: Array[String] = ["patch", "purge", "train", "cure", "refit", "amputate"]
## Treatments that raise Outbreak (once per visit).
const OUTBREAK_TREATMENTS: Array[String] = ["patch", "purge", "cure"]


static func enter(run) -> Dictionary:
	var ns := {"kind": "hospital", "treated": {}, "outbreak_paid": false, "left": [], "finished": true, "refits": {}}
	for rec in RunAccess.active_soldiers(run):
		var id := Grafts.machine_offer(run, rec, "hospital%d" % int(run.fights_won))
		if id != "":
			ns.refits[rec.id] = id
	run.node_state = ns
	RunAccess.emit(run, {"type": "hospital_open"})
	return ns


## Why `treatment` can't be given to `rec` right now ("" if it can).
static func blocker(run, ns: Dictionary, rec, treatment: String) -> String:
	if ns.treated.has(rec.id):
		return "already treated"
	match treatment:
		"patch":
			if rec.hp >= rec.max_hp and rec.injuries <= 0:
				return "not hurt"
		"purge":
			if rec.infection <= 0:
				return "already clean"
			if run.supplies < PURGE_PRICE:
				return "Not enough Supplies"
		"train":
			if RunHooks.has("Progression", "can_take_pick") and not RunHooks.call_static("Progression", "can_take_pick", [rec], true):
				return "no perks left"
		"cure":
			if rec.infection <= Grafts.record_floor(rec) and RunAccess.mutations_of(rec).is_empty():
				return "already clean"
			if RunAccess.serum(run, rec.owner) < CURE_SAMPLES:
				return "needs 2 Serum doses"
		"refit":
			if not ns.get("refits", {}).has(rec.id):
				var why := Grafts.eligible_error(run, rec)
				return why if why != "" else "no part for them"
			if run.supplies < Grafts.refit_price(rec):
				return "Not enough Supplies"
		"amputate":
			if Grafts.amputate_slot(rec) == "":
				return "no Bloom graft"
			if run.supplies < GraftData.AMPUTATE_PRICE:
				return "Not enough Supplies"
		_:
			return "unknown treatment"
	return ""


static func validate(run, ns: Dictionary, action: Dictionary) -> String:
	if action.type != "node_treat":
		return "unknown action"
	var rec = RunAccess.soldier(run, action.get("soldier", -1))
	if rec == null or rec.owner != action.get("player", -1) or rec.hp <= 0:
		return "pick one of your soldiers"
	return blocker(run, ns, rec, action.get("treatment", ""))


static func apply(run, ns: Dictionary, action: Dictionary) -> void:
	var rec = RunAccess.soldier(run, action.soldier)
	var t: String = action.treatment
	ns.treated[rec.id] = t
	match t:
		"patch":
			rec.injuries = maxi(0, rec.injuries - 1)
			RunAccess.heal(run, rec, rec.max_hp)
		"purge":
			RunAccess.add_supplies(run, -PURGE_PRICE)
			RunAccess.add_infection(run, rec, -PURGE_AMOUNT)
		"train":
			RunAccess.grant_perk_pick(run, rec)
		"cure":
			RunAccess.add_serum(run, rec.owner, -CURE_SAMPLES)
			RunAccess.full_cure(run, rec)
		"refit":
			var id: String = ns.refits[rec.id]
			RunAccess.add_supplies(run, -Grafts.refit_price(rec))
			Grafts.take(rec, id)
			RunAccess.emit(run, {"type": "soldier_graft", "sid": rec.id, "graft": id})
		"amputate":
			RunAccess.add_supplies(run, -GraftData.AMPUTATE_PRICE)
			var id := Grafts.amputate(rec, Grafts.amputate_slot(rec))
			RunAccess.emit(run, {"type": "soldier_graft", "sid": rec.id, "graft": id, "amputated": true})
	RunAccess.emit(run, {"type": "hospital_treat", "soldier": rec.id, "treatment": t})
	if t in OUTBREAK_TREATMENTS and not ns.outbreak_paid:
		ns.outbreak_paid = true
		RunAccess.add_outbreak(run, OUTBREAK_COST)


## What treatment `t` would do to `rec`, in the squad panel's preview shape (see
## EventRules.preview).
static func preview(rec, t: String) -> Dictionary:
	match t:
		"patch":
			return {"hp": rec.max_hp, "injuries": maxi(0, rec.injuries - 1)}
		"purge":
			return {"infection": maxi(0, rec.infection - PURGE_AMOUNT)}
		"train":
			return {"perk": 1}
		"cure":
			return {"infection": Grafts.record_floor(rec), "lose_mutation": RunAccess.mutations_of(rec).size()}
	return {}


## Preview that needs the visit: the part a Refit would graft, or what Amputate cuts.
static func preview_in(ns: Dictionary, rec, t: String) -> Dictionary:
	match t:
		"refit":
			var id: String = ns.get("refits", {}).get(rec.id, "")
			return {"graft": id} if id != "" else {}
		"amputate":
			var slot := Grafts.amputate_slot(rec)
			if slot == "":
				return {}
			return {"graft": GraftData.for_slot(slot, GraftData.MACHINE), "hp": maxi(1, rec.hp - GraftData.AMPUTATE_HP)}
	return preview(rec, t)


## Treatments this soldier's card shows: the four basics, Refit when a part is on offer for
## them, Amputate when they carry a Bloom graft.
static func options(ns: Dictionary, rec) -> Array[String]:
	var out: Array[String] = ["patch", "purge", "train", "cure"]
	if ns.get("refits", {}).has(rec.id):
		out.append("refit")
	if Grafts.amputate_slot(rec) != "":
		out.append("amputate")
	return out


## The cost line on a treatment's tile.
static func cost_text(rec, t: String) -> String:
	if t == "refit":
		return "%d Supplies" % Grafts.refit_price(rec)
	return TREATMENTS[t].cost
