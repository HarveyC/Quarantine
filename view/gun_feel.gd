extends RefCounted
## How each weapon (combat/weapons.gd) looks and sounds when it fires. View-only.
##
## "rounds": rounds per trigger pull (the last one carries the shot's outcome; earlier ones
##   hit too on a hit, or chew up cover on a miss), "gap": seconds between rounds,
## "pellets": >0 makes each round a spread of pellets, "flash" / "recoil" / "shake" / "kick":
##   scale of the muzzle flash, weapon recoil, camera shake and camera kick per round,
## "sound": per round, "tail": once, after the first round (the echo off the buildings),
## "mech": once after the last round (pump, bolt), "mech_delay" seconds later,
## "bullet": size of the glowing round, "casing": eject brass, "color": tracer tint.

const Palette := preload("res://view/palette.gd")

const SQUAD := Color(1.0, 0.78, 0.4)
const HOSTILE := Color(1.0, 0.42, 0.28)

const FEEL := {
	"rifle": {"rounds": 3, "gap": 0.075, "flash": 1.0, "recoil": 0.9, "shake": 0.3, "kick": 0.5,
		"sound": "rifle", "tail": "tail_rifle", "bullet": 1.0, "casing": true},
	"dmr": {"rounds": 1, "gap": 0.0, "flash": 1.7, "recoil": 1.7, "shake": 0.75, "kick": 1.4,
		"sound": "sniper", "tail": "tail_heavy", "mech": "bolt", "mech_delay": 0.5, "bullet": 1.5, "casing": true,
		"smoke": true},
	"pdw": {"rounds": 5, "gap": 0.05, "flash": 0.7, "recoil": 0.45, "shake": 0.18, "kick": 0.3,
		"sound": "smg", "tail": "tail_rifle", "bullet": 0.8, "casing": true},
	"shotgun": {"rounds": 1, "gap": 0.0, "pellets": 9, "flash": 2.0, "recoil": 1.9, "shake": 0.95, "kick": 1.6,
		"sound": "shotgun", "tail": "tail_heavy", "mech": "pump", "mech_delay": 0.42, "bullet": 0.6, "casing": true,
		"smoke": true},
	"lmg": {"rounds": 6, "gap": 0.085, "flash": 1.25, "recoil": 0.8, "shake": 0.4, "kick": 0.7,
		"sound": "lmg", "tail": "tail_heavy", "bullet": 1.1, "casing": true},
	"carbine": {"rounds": 2, "gap": 0.09, "flash": 0.9, "recoil": 0.7, "shake": 0.28, "kick": 0.5,
		"sound": "carbine", "tail": "tail_rifle", "bullet": 1.0, "casing": true, "color": Color(0.75, 1.0, 0.6)},
	"sidearm": {"rounds": 1, "gap": 0.0, "flash": 0.55, "recoil": 0.5, "shake": 0.15, "kick": 0.25,
		"sound": "pistol", "tail": "tail_rifle", "bullet": 0.75, "casing": true},
	"revolver": {"rounds": 1, "gap": 0.0, "flash": 1.1, "recoil": 1.1, "shake": 0.45, "kick": 0.8,
		"sound": "revolver", "tail": "tail_heavy", "bullet": 1.1, "casing": false, "smoke": true},
	"spit": {"rounds": 1, "gap": 0.0, "flash": 0.0, "recoil": 0.6, "shake": 0.2, "kick": 0.0,
		"sound": "spit", "bullet": 1.6, "casing": false, "color": Palette.TEAL},
}


## Alternate guns: their look's feel with these keys changed (null removes a key).
const VARIANTS := {
	"battle_rifle": {"rounds": 2, "gap": 0.11, "flash": 1.3, "recoil": 1.25, "shake": 0.45, "kick": 0.8, "tail": "tail_heavy", "bullet": 1.2},
	"burst_carbine": {"rounds": 3, "gap": 0.06, "color": null},
	"anti_materiel": {"flash": 2.3, "recoil": 2.4, "shake": 1.15, "kick": 2.0, "bullet": 1.9, "mech_delay": 0.65},
	"scout_carbine": {"rounds": 3, "gap": 0.07, "sound": "carbine"},
	"flechette_smg": {"rounds": 6, "gap": 0.04, "bullet": 0.6, "recoil": 0.4},
	"dart_rifle": {"sound": "carbine", "flash": 0.6, "recoil": 0.8, "shake": 0.3, "kick": 0.6, "smoke": null, "bullet": 0.9,
		"color": Color(0.7, 0.95, 1.0)},
	"slug_gun": {"pellets": null, "bullet": 1.5},
	"auto_shotgun": {"rounds": 3, "gap": 0.16, "pellets": 6, "mech": null, "recoil": 1.4, "shake": 0.7},
	"pump_shotgun": {"pellets": 8},
	"heavy_mg": {"rounds": 7, "gap": 0.1, "flash": 1.6, "recoil": 1.1, "shake": 0.6, "kick": 0.9, "bullet": 1.3},
	"spore_rifle": {"rounds": 1, "flash": 1.1, "recoil": 1.0, "kick": 0.8, "bullet": 1.5, "color": Palette.TEAL},
}


static func for_kind(kind: String) -> Dictionary:
	return for_weapon(Weapons.id_for(kind))


## Feel for a weapon id; alternates build theirs from their look's.
static func for_weapon(id: String) -> Dictionary:
	if FEEL.has(id):
		return FEEL[id]
	var base: Dictionary = FEEL.get(Weapons.look_of(id), FEEL.rifle).duplicate()
	var v: Dictionary = VARIANTS.get(id, {})
	for k in v:
		if v[k] == null:
			base.erase(k)
		else:
			base[k] = v[k]
	return base


## Tracer / round colour for a shooter: amber for the squad, red for hostile guns,
## teal for spit and Turned soldiers.
static func color(feel: Dictionary, is_squad: bool, turned: bool) -> Color:
	if feel.has("color"):
		return feel.color
	if turned:
		return Palette.TEAL
	return SQUAD if is_squad else HOSTILE
