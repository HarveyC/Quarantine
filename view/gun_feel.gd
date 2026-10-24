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
	"spit": {"rounds": 1, "gap": 0.0, "flash": 0.0, "recoil": 0.6, "shake": 0.2, "kick": 0.0,
		"sound": "spit", "bullet": 1.6, "casing": false, "color": Palette.TEAL},
}


static func for_kind(kind: String) -> Dictionary:
	return FEEL.get(Weapons.id_for(kind), FEEL.rifle)


## Tracer / round colour for a shooter: amber for the squad, red for hostile guns,
## teal for spit and Turned soldiers.
static func color(feel: Dictionary, is_squad: bool, turned: bool) -> Color:
	if feel.has("color"):
		return feel.color
	if turned:
		return Palette.TEAL
	return SQUAD if is_squad else HOSTILE
