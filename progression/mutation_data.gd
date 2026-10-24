class_name MutationData
extends RefCounted
## Mutation table. OWNER: progression workstream. Effects live in Mutations (actives) and Kit (passives).
##
## Every mutation sits in one slot ("exposed", "mutating", "critical", or the Vector's "strain")
## and is awake while the soldier's Infection tier is at least "awake_at" (an Infection.Tier).
## Fields: name, slot, awake_at, active (bool), tag, targeting ("none"|"unit"|"cell"), actions,
## cost (Infection per use, before class modifiers), graft (Infection added when taken),
## desc, drawback, and optional "bonded" / "vector" / "pending" (effect needs a system the build
## doesn't have yet; the mutation still grafts and counts for tags).

const SLOTS: Array[String] = ["exposed", "mutating", "critical", "strain"]
## Infection.Tier needed for each regular slot to be awake.
const SLOT_TIER := {"exposed": 1, "mutating": 2, "critical": 3, "strain": 1}
const GRAFT := {"exposed": 10, "mutating": 15, "critical": 20, "strain": 10}
const USE_COST := {"exposed": 5, "mutating": 10, "critical": 15}

const MUTATIONS := {
	# --- Exposed (25+): graft +10, actives cost 5
	"spore_sense": {"name": "Spore Sense", "slot": "exposed", "active": false, "tag": "Mark",
		"desc": "See infected enemies through walls within 6 tiles; teammates see them as ghost outlines.",
		"drawback": "Spore zones give you double Infection."},
	"adrenal_surge": {"name": "Adrenal Surge", "slot": "exposed", "active": true, "tag": "Strain", "targeting": "none", "actions": 0,
		"desc": "Gain a third action this turn.", "drawback": "Next turn you have only 1 action."},
	"barbed_hide": {"name": "Barbed Hide", "slot": "exposed", "active": false, "tag": "Close",
		"desc": "Melee attackers take 2 damage.", "drawback": "Allies next to you at the end of your turn gain 2 Infection."},
	"hollow_bones": {"name": "Hollow Bones", "slot": "exposed", "active": false, "tag": "Close",
		"desc": "+2 movement.", "drawback": "Take +1 damage from every hit."},
	"lure_scent": {"name": "Lure Scent", "slot": "exposed", "active": true, "tag": "Overwatch", "targeting": "none", "actions": 1,
		"desc": "Until your next turn, teammates' overwatch shots get +15 aim against enemies within 6 tiles of you.",
		"drawback": "Infected enemies go for you, and you can't hunker down this turn."},
	"clotting_blood": {"name": "Clotting Blood", "slot": "exposed", "active": false, "tag": "Strain",
		"desc": "Heal 1 HP at the start of each team phase.", "drawback": "Medic heals on you are halved."},
	# --- Mutating (50+): graft +15, actives cost 10
	"chitin_plates": {"name": "Chitin Plates", "slot": "mutating", "active": false, "tag": "Guard",
		"desc": "+2 armour: hits on you deal 2 less damage (minimum 1).", "drawback": "-1 movement, and you can't hunker down."},
	"leech_bite": {"name": "Leech Bite", "slot": "mutating", "active": true, "tag": "Close", "targeting": "unit", "actions": 1,
		"desc": "Melee attack an adjacent enemy and heal for the damage dealt.", "drawback": "+5 extra Infection if the target is infected."},
	"acid_spit": {"name": "Acid Spit", "slot": "mutating", "active": true, "tag": "Suppress", "targeting": "unit", "actions": 1,
		"desc": "Spit at an enemy within 5 tiles for 3 damage, ignoring cover, and Suppress it.",
		"drawback": "Allies next to the target gain 5 Infection."},
	"second_heart": {"name": "Second Heart", "slot": "mutating", "active": false, "tag": "Strain",
		"desc": "The first time you'd go down each fight, you stay up at 1 HP.", "drawback": "You gain 15 Infection when it triggers."},
	"rally_musk": {"name": "Rally Musk", "slot": "mutating", "active": true, "tag": "Guard", "targeting": "none", "actions": 1,
		"desc": "Allies within 3 tiles get +1 movement and +10 aim this turn.", "drawback": "Each of them gains 3 Infection."},
	"hive_hush": {"name": "Hive Hush", "slot": "mutating", "active": false, "tag": "Purge",
		"desc": "Dormant infected enemies can't spot you beyond 4 tiles.", "drawback": "Medic Purge on you is half as effective."},
	# --- Critical (75+): graft +20, actives cost 15
	"rampage": {"name": "Rampage", "slot": "critical", "active": true, "tag": "Close", "targeting": "cell", "actions": 1,
		"desc": "Move your full range and claw every enemy you pass next to.", "drawback": "You roll for a Lapse straight after."},
	"regenerator": {"name": "Regenerator", "slot": "critical", "active": false, "tag": "Strain",
		"desc": "Heal 3 HP each team phase.", "drawback": "Medics can't heal you, and you gain 2 Infection each turn."},
	"hollow_voice": {"name": "Hollow Voice", "slot": "critical", "active": true, "tag": "Suppress", "targeting": "unit", "actions": 1,
		"desc": "Seize a visible non-boss infected enemy: it attacks its nearest ally now and loses its next turn.",
		"drawback": "Your Lapse chance doubles for the rest of the fight."},
	"bloom": {"name": "Bloom", "slot": "critical", "active": false, "tag": "Strain",
		"desc": "When you're hit, spores deal 2 damage to every adjacent enemy.", "drawback": "Adjacent allies gain 5 Infection too."},
	"overgrowth": {"name": "Overgrowth", "slot": "critical", "active": true, "tag": "Guard", "targeting": "cell", "actions": 1,
		"desc": "Grow fungal walls on the empty cells of a 3x3 patch for 2 turns.", "drawback": "The patch is also a spore zone."},
	"martyr_strain": {"name": "Martyr Strain", "slot": "critical", "active": false, "tag": "Purge",
		"desc": "When you die or Turn, every teammate's Infection drops by 20.", "drawback": "Nobody can talk you down from a Lapse."},
	# --- Bonded (nest rewards only): link two soldiers of different players, uses the Mutating slot
	"shared_blood": {"name": "Shared Blood", "slot": "mutating", "active": false, "tag": "Guard", "bonded": true,
		"desc": "Damage to either soldier is split between both.", "drawback": "If one Lapses, the other rolls too."},
	"twin_sight": {"name": "Twin Sight", "slot": "mutating", "active": false, "tag": "Overwatch", "bonded": true,
		"desc": "Either one's overwatch triggers on enemies the other can see.",
		"drawback": "If they end a turn more than 6 tiles apart, both lose an action."},
	"mirror_graft": {"name": "Mirror Graft", "slot": "mutating", "active": false, "tag": "Strain", "bonded": true,
		"desc": "When one uses an active mutation, the other can use it the same turn without spending an action.",
		"drawback": "Both pay its Infection cost."},
	# --- Vector only: the Strain slot, awake from Exposed, graft +10
	"host_body": {"name": "Host Body", "slot": "strain", "active": false, "tag": "Purge", "vector": true,
		"desc": "Once per turn, when an ally within 2 tiles would gain Infection, you take it instead.",
		"drawback": "All of it lands on you."},
	"spore_burst": {"name": "Spore Burst", "slot": "strain", "active": true, "tag": "Strain", "vector": true,
		"targeting": "cell", "actions": 1, "cost": 10,
		"desc": "A cloud of radius 2 deals 2 damage per turn to enemies inside for 2 turns.", "drawback": "Allies inside gain 5 Infection."},
	"hive_link": {"name": "Hive Link", "slot": "strain", "active": true, "tag": "Purge", "vector": true,
		"targeting": "unit", "actions": 0, "cost": 0,
		"desc": "Once per fight, link an ally: they can use your awake Exposed mutation, paying with their own Infection.",
		"drawback": "When you Lapse, they lose their next action."},
	"flies": {"name": "Flies", "slot": "strain", "active": true, "tag": "Mark", "vector": true,
		"targeting": "unit", "actions": 1, "cost": 5,
		"desc": "Mark a visible enemy: every hit on it does +1 damage.",
		"drawback": "When it dies, the flies move to the nearest soldier, who gains 5 Infection."},
	"ride_the_wave": {"name": "Ride the Wave", "slot": "strain", "active": false, "tag": "Strain", "vector": true,
		"desc": "At 100 you don't Turn straight away: the squad gets 2 team phases to bring you below 100.",
		"drawback": "If they don't, you Turn."},
	"patient_zero": {"name": "Patient Zero", "slot": "strain", "active": false, "tag": "Strain", "vector": true, "awake_at": 3,
		"desc": "Awake at Critical only. Your active mutations cost no Infection.",
		"drawback": "You also roll for a Lapse at the start of every enemy phase."},
}


static func has(id: String) -> bool:
	return MUTATIONS.has(id)


static func get_def(id: String) -> Dictionary:
	return MUTATIONS.get(id, {})


## Infection.Tier the mutation needs to be awake.
static func awake_at(id: String) -> int:
	var m := get_def(id)
	return int(m.get("awake_at", SLOT_TIER.get(m.get("slot", "exposed"), 1)))


static func graft_cost(id: String) -> int:
	return int(GRAFT.get(get_def(id).get("slot", "exposed"), 10))


## Base Infection per use, before Sealed Suit / Willing Host / Apex / Patient Zero.
static func base_use_cost(id: String) -> int:
	var m := get_def(id)
	if not m.get("active", false):
		return 0
	return int(m.get("cost", USE_COST.get(m.slot, 5)))


## Mutation ids a soldier may be offered in the regular pool for `slot` (no Bonded, no Vector).
static func regular_pool(slot: String) -> Array[String]:
	var out: Array[String] = []
	for id in MUTATIONS:
		var m: Dictionary = MUTATIONS[id]
		if m.slot == slot and not m.get("bonded", false) and not m.get("vector", false) and not MetaUnlocks.is_locked(id):
			out.append(id)
	return out


static func vector_pool() -> Array[String]:
	var out: Array[String] = []
	for id in MUTATIONS:
		if MUTATIONS[id].get("vector", false) and not MetaUnlocks.is_locked(id):
			out.append(id)
	return out


static func bonded_pool() -> Array[String]:
	var out: Array[String] = []
	for id in MUTATIONS:
		if MUTATIONS[id].get("bonded", false) and not MetaUnlocks.is_locked(id):
			out.append(id)
	return out
