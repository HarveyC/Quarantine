class_name GraftData
extends RefCounted
## Grafts: late-run body-part upgrades (design: the Grafts plan). Every soldier has four slots,
## Head, Arm, Chest and Legs. A slot takes one graft for the rest of the soldier's life, either a
## Machine "Refit" (Cordon machinery: steady bonuses, slows Infection gain) or a Bloom part
## (strong powers that grow with Infection, sets an Infection floor). A soldier may mix paths.
## Rules live in Grafts; this file is data only. OWNER: progression workstream.

const SLOTS: Array[String] = ["head", "arm", "chest", "legs"]
const SLOT_NAMES := {"head": "Head", "arm": "Arm", "chest": "Chest", "legs": "Legs"}
const MACHINE := "machine"
const BLOOM := "bloom"

## Grafts open from this act, on soldiers of this rank or higher.
const FROM_ACT := 2
const FROM_RANK := 3
## Machine: Supplies per refit (Hazmat's Sealed Suit makes them cheaper), and the soldier fights
## the next mission at -1 move while it beds in.
const REFIT_PRICE := 40
const HAZMAT_REFIT_PRICE := 25
const BEDDING_MOBILITY := -1
## Machine: Infection gain cut per Machine part, in tenths (-10% each, up to -30%).
const GAIN_CUT_PER_PART := 1
const GAIN_CUT_MAX := 3
## Bloom: Infection on taking it (Vector pays 5 less), and the floor per Bloom part.
const BLOOM_INFECTION := 15
const VECTOR_BLOOM_INFECTION := 10
const FLOOR_PER_PART := 10
## Field hospital "Amputate and refit": swaps a Bloom part for that slot's Machine one.
const AMPUTATE_PRICE := 30
const AMPUTATE_HP := 3

## Numbers for the effects below (first guesses for the balance sim).
const OPTIC_AIM := 15
const LATTICE_RADIUS := 6
const SERVO_MELEE := 1
const SERVO_THROW := 2.0
const RIBS_HP := 2
const HEART_REGEN := 1
const HEART_SLOW := -2
const HYDRAULIC_MOBILITY := 1
const CLAW_DAMAGE := Vector2i(3, 5)
const CLAW_KILL_HEAL := 1
const LEAP_RANGE := 4

const GRAFTS := {
	"targeting_optic": {"name": "Targeting optic", "slot": "head", "path": MACHINE, "tag": "Mark",
		"desc": "+15 aim, and your Marks last one turn longer.",
		"look": "A large targeting lens with a range-finder in place of one mask optic"},
	"lattice_sight": {"name": "Lattice sight", "slot": "head", "path": BLOOM, "tag": "Overwatch",
		"desc": "Sense Infected through walls within 6 tiles. At Critical, the Source's Whispers come through as +1 Intel after each fight.",
		"look": "The mask cracked open, teal crystals growing through the visor"},
	"servo_arm": {"name": "Servo arm", "slot": "arm", "path": MACHINE, "tag": "Suppress",
		"desc": "+1 melee damage, +2 throw range, +2 rounds in your magazine, and heavy guns no longer slow you.",
		"look": "A bare servo forearm and hand, pistons showing"},
	"bloom_limb": {"name": "Bloom limb", "slot": "arm", "path": BLOOM, "tag": "Close",
		"desc": "Bloom Claw: strike an adjacent enemy for 3-5, +1 per Infection tier. A kill heals 1 HP.",
		"look": "A swollen fungal limb with a long claw and glowing veins"},
	"plated_ribs": {"name": "Plated ribs", "slot": "chest", "path": MACHINE, "tag": "Guard",
		"desc": "+2 max HP, and Infection from spores and Spitters is halved.",
		"look": "An armoured ribcage plate with a second regulator and hoses"},
	"heart_knot": {"name": "Heart knot", "slot": "chest", "path": BLOOM, "tag": "Strain",
		"desc": "Regenerate 1 HP a turn while Mutating or higher. Enemies that hit you in melee are slowed for a turn.",
		"look": "A pulsing knot bursting through the plate carrier"},
	"hydraulic_legs": {"name": "Hydraulic legs", "slot": "legs", "path": MACHINE, "tag": "Guard",
		"desc": "+1 move, and ladders cost a normal step.",
		"look": "Hydraulic braces from hip to boot"},
	"runner_legs": {"name": "Runner legs", "slot": "legs", "path": BLOOM, "tag": "Close",
		"desc": "Leap: once per fight, jump up to 4 tiles, over cover and past overwatch. 1 action.",
		"look": "Reverse-jointed, bark-like legs with spines"},
}


static func get_def(id: String) -> Dictionary:
	return GRAFTS.get(id, {})


static func name_of(id: String) -> String:
	return get_def(id).get("name", id)


static func slot_of(id: String) -> String:
	return get_def(id).get("slot", "")


static func path_of(id: String) -> String:
	return get_def(id).get("path", "")


static func is_bloom(id: String) -> bool:
	return path_of(id) == BLOOM


## The graft of `path` that fits `slot` ("" if none).
static func for_slot(slot: String, path: String) -> String:
	for id in GRAFTS:
		if GRAFTS[id].slot == slot and GRAFTS[id].path == path:
			return id
	return ""
