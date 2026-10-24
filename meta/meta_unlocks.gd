class_name MetaUnlocks
extends RefCounted
## Field Data unlocks bought between runs (design doc, "Economy and rewards"): gear, Doctrine and
## mutation packs plus two starting perks. Packs live on each player's profile; in co-op the run
## uses the host's (Harvey, 2026-10-24), so `meta.packs` is the host's list.
##
## Gear pack I is cheap and holds the build basics: with it every tag has a gadget and at least 3
## pieces, enough for its set bonus. Later packs add keystones and Prototypes.
##
## Content listed in a pack is locked until the run's host owns that pack; everything not
## listed is available from the start, so new content is unlocked by default. To make new gear,
## Doctrines or mutations a pack reward, append their ids to the pack's `content`.
##
## A run binds its lock set when it is created or loaded (`bind(run.meta)`); the draws in
## GearDraw, GearRun and MutationData then skip locked ids through `is_locked`. A meta without a
## "packs" key (tests, dev tools, the balance sim) locks nothing.

## id -> {name, cost, needs (pack bought first), kind, about, content (locked ids)}.
const PACKS := {
	"gear_1": {"name": "Gear pack I: Field issue", "short": "Field issue", "cost": 50, "needs": "", "kind": "gear",
		"about": "Build basics: a gadget for every tag",
		"content": ["thermite_charge", "concussion_launcher", "grapple", "adrenal_pump", "deployable_cover"]},
	"gear_2": {"name": "Gear pack II: Specialist", "short": "Specialist", "cost": 200, "needs": "gear_1", "kind": "gear",
		"about": "A second weapon or ammo pick for five tags",
		"content": ["phosphor_rounds", "suppressor", "rangefinder", "choke", "purifier_rounds", "feral_grip"]},
	"gear_3": {"name": "Gear pack III: Prototype", "short": "Prototype", "cost": 350, "needs": "gear_2", "kind": "gear",
		"about": "Keystone Rares and combo Prototypes",
		"content": ["sentry_turret", "riot_shield", "crossfire", "quarantine_field"]},
	"doctrine_1": {"name": "Doctrine pack", "short": "Doctrines", "cost": 300, "needs": "", "kind": "doctrine",
		"about": "4 new squad Doctrines after act bosses",
		"content": ["scavengers", "supply_drop", "triage_drills", "serum_cache"]},
	"mutation_1": {"name": "Mutation pack I: Bonded strains", "short": "Bonded", "cost": 300, "needs": "", "kind": "mutation",
		"about": "Bonded mutations that link two soldiers",
		"content": ["shared_blood", "twin_sight", "mirror_graft", "hive_hush"]},
	"mutation_2": {"name": "Mutation pack II: Deep strains", "short": "Deep strains", "cost": 450, "needs": "mutation_1", "kind": "mutation",
		"about": "Late, dangerous Critical mutations",
		"content": ["rampage", "hollow_voice", "overgrowth", "patient_zero"]},
	"field_kit": {"name": "Field kit", "short": "Field kit", "cost": 150, "needs": "", "kind": "perk",
		"about": "A 4th starting item choice per soldier", "content": []},
	"serum_reserve": {"name": "Serum reserve", "short": "Serum reserve", "cost": 250, "needs": "", "kind": "perk",
		"about": "+1 starting Serum sample per soldier", "content": []},
}
## Display order on the Field HQ screen.
const ORDER: Array[String] = ["gear_1", "gear_2", "gear_3", "doctrine_1", "mutation_1", "mutation_2", "field_kit", "serum_reserve"]

static var _locked := {}


## Pack ids the meta's players own between them, or every pack when the meta has no "packs" key.
static func owned(meta: Dictionary) -> Array:
	if not meta.has("packs"):
		return PACKS.keys()
	return meta.packs.filter(func(id): return PACKS.has(id))


static func has_pack(meta: Dictionary, id: String) -> bool:
	return owned(meta).has(id)


## Whether the meta's players actually bought `id` (for the starting perks, which a meta without
## "packs" doesn't get).
static func owns(meta: Dictionary, id: String) -> bool:
	return Array(meta.get("packs", [])).has(id)


## Ids of content locked for a run with this meta.
static func locked_ids(meta: Dictionary) -> Dictionary:
	var have := owned(meta)
	var out := {}
	for id in PACKS:
		if not have.has(id):
			for c in PACKS[id].content:
				out[c] = true
	return out


## Sets the lock set the draws use. Called when a run is created or loaded.
static func bind(meta: Dictionary) -> void:
	_locked = locked_ids(meta)


static func is_locked(id: String) -> bool:
	return _locked.has(id)


## Known pack ids from several lists, deduplicated and sorted.
static func pool(lists: Array) -> Array:
	var out: Array = []
	for l in lists:
		for id in l:
			if PACKS.has(id) and not out.has(id):
				out.append(id)
	out.sort()
	return out


## "" if `packs` (a profile's owned list) can buy `id` with `field_data`, otherwise why not.
static func can_buy(packs: Array, field_data: int, id: String) -> String:
	if not PACKS.has(id):
		return "Unknown unlock"
	if packs.has(id):
		return "Owned"
	var needs: String = PACKS[id].needs
	if needs != "" and not packs.has(needs):
		return "Needs %s" % PACKS[needs].short
	if field_data < int(PACKS[id].cost):
		return "Needs %d Field Data" % PACKS[id].cost
	return ""


static func total_cost() -> int:
	var n := 0
	for id in PACKS:
		n += int(PACKS[id].cost)
	return n
