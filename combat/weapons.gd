class_name Weapons
extends RefCounted
## Weapon archetypes: each class (and each enemy that shoots) carries one signature gun.
## A weapon only shapes how a shot plays out: its range bands, crit and graze odds and one
## trait. Damage still comes from the unit (UnitData), so class tuning stays in one place.
## Pure rules data and helpers; the view's look and sound for each gun is in view/gun_feel.gd.
##
## Range terms replace the old flat close/long range modifiers. Distances are Euclidean
## tiles, like the rest of Combat:
##   "close": tiles at or under which the "close_aim" term applies (it may be negative).
##   "falloff": distance past which every started tile costs "falloff_aim" aim.
## Traits: "pin" (a miss still suppresses the target), "snap" (overwatch reaction shots take
## "reaction" instead of Combat.REACTION_PENALTY), "spread" (a wider graze band).

const DEFAULT := "rifle"

const TABLE := {
	"rifle": {"name": "Assault rifle", "close": 3.0, "close_aim": 15, "falloff": 10.0, "falloff_aim": 3,
		"desc": "Reliable at any range."},
	"dmr": {"name": "Marksman rifle", "close": 2.0, "close_aim": -10, "falloff": 14.0, "falloff_aim": 3,
		"crit": 15, "close_label": "Too close to scope",
		"desc": "No range penalty out to sight range, +15% crit. -10 aim at 2 tiles or less."},
	"pdw": {"name": "PDW", "close": 4.0, "close_aim": 20, "falloff": 7.0, "falloff_aim": 5,
		"desc": "+20 aim within 4 tiles; falls off fast past 7."},
	"shotgun": {"name": "Combat shotgun", "close": 3.0, "close_aim": 25, "falloff": 5.0, "falloff_aim": 8,
		"graze": 20, "trait": "spread",
		"desc": "+25 aim within 3 tiles, steep falloff past 5. Spread: wider graze band."},
	"lmg": {"name": "Light machine gun", "close": 3.0, "close_aim": 5, "falloff": 11.0, "falloff_aim": 2,
		"trait": "pin",
		"desc": "Pinning fire: a miss still suppresses the target (-30 aim on its next shot)."},
	"carbine": {"name": "Bio-carbine", "close": 3.0, "close_aim": 10, "falloff": 9.0, "falloff_aim": 3,
		"trait": "snap", "reaction": 0,
		"desc": "Snap shots: overwatch reaction shots take no aim penalty."},
	"spit": {"name": "Spit", "close": 3.0, "close_aim": 15, "falloff": 10.0, "falloff_aim": 3,
		"desc": "Acidic spit."},
}

## Unit kind -> weapon id. Anything not listed fires the default rifle profile.
const BY_KIND := {
	"trooper": "rifle", "marksman": "dmr", "medic": "pdw", "breacher": "shotgun",
	"hazmat": "lmg", "vector": "carbine",
	"fallen": "rifle", "colonel_hale": "rifle", "sharpshooter": "dmr", "spitter": "spit",
}


static func id_for(kind: String) -> String:
	return BY_KIND.get(kind, DEFAULT)


static func of(u: Unit) -> Dictionary:
	return TABLE[id_for(u.kind)]


static func display_name(kind: String) -> String:
	return TABLE[id_for(kind)].name


static func has_trait(u: Unit, t: String) -> bool:
	return of(u).get("trait", "") == t


## Appends the weapon's range term (if any) for a shot over `dist` tiles to `breakdown`.
static func range_terms(u: Unit, dist: float, breakdown: Array) -> void:
	var w := of(u)
	if dist <= float(w.close):
		if int(w.close_aim) != 0:
			breakdown.append([w.get("close_label", "Close range"), int(w.close_aim)])
	elif dist > float(w.falloff):
		breakdown.append(["Long range", -int(w.falloff_aim) * ceili(dist - float(w.falloff))])


## Aim penalty on an overwatch reaction shot (positive number).
static func reaction_penalty(u: Unit, base: int) -> int:
	return int(of(u).get("reaction", base))


static func crit_bonus(u: Unit) -> int:
	return int(of(u).get("crit", 0))


static func graze_band(u: Unit, base: int) -> int:
	return int(of(u).get("graze", base))


## After a missed shot: pinning fire suppresses the target until its next shot.
static func after_miss(s: GameState, u: Unit, t: Unit) -> void:
	if has_trait(u, "pin") and t.is_alive():
		t.status["suppressed"] = Combat.phase_index(s) + 2
		s.emit({"type": "pinned", "unit": u.id, "target": t.id})
