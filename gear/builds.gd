class_name Builds
extends RefCounted
## The starter builds from the class build atlas: one easy build per class, plus Spotter and Killbox for the Mark and
## Overwatch capstones. Each is a complete, legal soldier (class perks, one item per gear slot,
## Grafts, mutations, an alternate gun) that reaches CAPSTONE_THRESHOLD in its lane tag, so a
## player who follows it has the capstone on by Act 2. The balance sim can play them as "full
## build" squads; tests/test_capstones.gd keeps every one honest as the tag tables change.
##
## Fields: class, name, tag (the tag it builds), perks (rank picks), gear (item ids, one per
## slot), grafts ({slot: id}), mutations ({slot: id}), gun ("" = class signature), infection
## (the Infection the soldier carries, which decides which mutations are awake).

const BUILDS := {
	"anchor": {"class": "trooper", "name": "Anchor", "tag": "Guard",
		"perks": ["steadfast", "hold_the_line", "battle_hardened", "last_stand"],
		"gear": ["compensator", "shock_rounds", "plated_ribs", "deployable_cover"],
		"grafts": {}, "mutations": {}, "gun": "pump_shotgun", "infection": 0},
	"spotter": {"class": "trooper", "name": "Spotter", "tag": "Mark",
		"perks": [],
		"gear": ["laser_sight", "tracer_rounds", "targeting_optic", "rig_tag"],
		"grafts": {}, "mutations": {"exposed": "spore_sense"}, "gun": "anti_materiel", "infection": 30},
	"field_surgeon": {"class": "medic", "name": "Field Surgeon", "tag": "Purge",
		"perks": ["long_reach", "transfusion", "calm_voice", "field_surgeon"],
		"gear": ["bayonet", "purge_canister", "filter_mask", "med_injector", "plated_ribs"],
		"grafts": {}, "mutations": {}, "gun": "dart_rifle", "infection": 0},
	"door_kicker": {"class": "breacher", "name": "Door Kicker", "tag": "Close",
		"perks": ["kick_in", "long_fuse", "frag_charge", "run_and_gun"],
		"gear": ["bayonet", "slug_rounds", "light_harness", "grapple"],
		"grafts": {"legs": "hydraulic_legs"}, "mutations": {}, "gun": "flechette_smg", "infection": 0},
	"pyre": {"class": "hazmat", "name": "Pyre", "tag": "Burn",
		"perks": ["napalm", "wide_nozzle", "fuel_line", "backdraft"],
		"gear": ["pilot_light", "incendiary_rounds", "flame_coat", "thermite_charge"],
		"grafts": {"arm": "servo_arm"}, "mutations": {"mutating": "kindled_spores"}, "gun": "auto_shotgun", "infection": 55},
	"lightning_rod": {"class": "vector", "name": "Lightning Rod", "tag": "Purge",
		"perks": ["deep_siphon", "iron_will", "open_veins", "contagion"],
		"gear": ["bayonet", "purge_canister", "filter_mask", "med_injector", "plated_ribs"],
		"grafts": {},
		"mutations": {"strain": "host_body", "critical": "martyr_strain"}, "gun": "", "infection": 80},
	"riposte": {"class": "reaper", "name": "Riposte", "tag": "Guard",
		"perks": ["riposte", "long_stride", "hamstring", "cleave"],
		"gear": ["bayonet", "slug_rounds", "plated_ribs", "deployable_cover", "riot_shield"],
		"grafts": {"legs": "hydraulic_legs"}, "mutations": {"mutating": "chitin_plates"},
		"gun": "", "infection": 55},
	# Not one of the easy six: the Overwatch capstone's build.
	"killbox": {"class": "trooper", "name": "Killbox", "tag": "Overwatch",
		"perks": ["return_fire", "walking_fire"],
		"gear": ["killbox", "match_rounds", "lattice_sight", "motion_tracker", "steady_hands"],
		"grafts": {}, "mutations": {}, "gun": "", "infection": 0},
}

## The six easy builds, one per class, in class order.
const EASY: Array[String] = ["anchor", "field_surgeon", "door_kicker", "pyre", "lightning_rod", "riposte"]


## A run soldier record wearing build `id` (progression and loadout in one dictionary).
static func record(id: String) -> Dictionary:
	var b: Dictionary = BUILDS[id]
	var rec := Progression.new_record(b.class)
	rec["rank"] = Progression.MAX_RANK
	rec["perks"] = (b.perks as Array).duplicate()
	rec["mutations"] = (b.mutations as Dictionary).duplicate()
	rec["grafts"] = (b.grafts as Dictionary).duplicate()
	rec["infection"] = int(b.infection)
	var run := {"supplies": 0, "soldiers": [rec]}
	for item in b.gear:
		Loadout.equip(run, rec, item)
	if b.gun != "":
		Loadout.take_gun(rec, b.gun)
	return rec


## Tag counts of the finished build, the same sum the loadout and the mission use.
static func counts(id: String) -> Dictionary:
	return GearTags.counts(record(id))
