class_name FieldHospital
extends RefCounted
## Field hospital: one treatment per soldier, chosen by the soldier's owner (design doc,
## Economy and rewards). Healing or purging anyone raises Outbreak by 1, once per visit;
## Train doesn't, so it's the "fast" rest. OWNER: nodes workstream.

const PURGE_AMOUNT := 30
const PURGE_PRICE := 15
const CURE_SAMPLES := 4  # 2 doses
const OUTBREAK_COST := 1

const TREATMENTS := {
	"patch": {"name": "Patch up", "desc": "Heal to full HP and clear 1 injury", "cost": "Free"},
	"purge": {"name": "Purge", "desc": "-30 Infection", "cost": "15 Supplies"},
	"train": {"name": "Train", "desc": "One extra perk pick from the class pool", "cost": "Free"},
	"cure": {"name": "Full cure", "desc": "Infection to 0, removes all mutations, Scars stay", "cost": "2 Serum doses"},
}
const ORDER: Array[String] = ["patch", "purge", "train", "cure"]


static func enter(run) -> Dictionary:
	var ns := {"kind": "hospital", "treated": {}, "outbreak_paid": false, "left": [], "finished": true}
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
			pass
		"cure":
			if rec.infection <= 0 and RunAccess.mutations_of(rec).is_empty():
				return "already clean"
			if RunAccess.serum(run, rec.owner) < CURE_SAMPLES:
				return "needs 2 Serum doses"
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
	RunAccess.emit(run, {"type": "hospital_treat", "soldier": rec.id, "treatment": t})
	if t != "train" and not ns.outbreak_paid:
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
			return {"infection": 0, "lose_mutation": RunAccess.mutations_of(rec).size()}
	return {}
