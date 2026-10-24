class_name Weapons
extends RefCounted
## Weapon archetypes: each class (and each enemy that shoots) carries one signature gun, and
## soldiers can find alternate guns for their class as rewards, depot stock and event loot.
## A weapon shapes how a shot plays out: its range bands, crit and graze odds and one trait.
## Damage still comes from the unit (UnitData), so class tuning stays in one place; an
## alternate gun may shift it with flat "aim" / "dmg" / "mobility" terms, stamped onto the
## Unit when the mission starts (GearRun.apply_to_unit).
## Pure rules data and helpers; the view's look and sound for each gun is in view/gun_feel.gd.
##
## Which gun a soldier carries: `record.gear.gun` on the run record ("" = the class signature,
## see Loadout.gun), copied to `unit.status.weapon` for the mission. Units without one (enemies,
## quick matches) use BY_KIND.
##
## Alternate gun fields: "classes" (soldier kinds that may carry it), "rarity" ("uncommon" |
## "rare", for draws and depot prices), "tag" (counts toward gear set bonuses), "look" (the
## signature gun whose feel and model it borrows in the view).
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
	"sidearm": {"name": "Sidearm", "close": 3.0, "close_aim": 10, "falloff": 7.0, "falloff_aim": 4,
		"desc": "Backup pistol: +10 aim within 3 tiles, falls off past 7. The real weapon is in the other hand."},
	"revolver": {"name": "Heavy revolver", "close": 3.0, "close_aim": 5, "falloff": 6.0, "falloff_aim": 4, "crit": 10,
		"desc": "One-handed over the shield rim: +10% crit, falls off past 6."},
	# Alternate guns.
	"battle_rifle": {"name": "Battle rifle", "classes": ["trooper", "marksman"], "rarity": "uncommon", "tag": "Suppress",
		"look": "rifle", "close": 3.0, "close_aim": 10, "falloff": 12.0, "falloff_aim": 2, "aim": -5, "dmg": 1,
		"desc": "Heavier rounds: +1 damage, -5 aim. Holds its accuracy out to 12 tiles."},
	"burst_carbine": {"name": "Burst carbine", "classes": ["trooper", "vector"], "rarity": "rare", "tag": "Overwatch",
		"look": "carbine", "close": 4.0, "close_aim": 15, "falloff": 8.0, "falloff_aim": 4, "crit": 5,
		"trait": "snap", "reaction": 5,
		"desc": "Snap shots: overwatch reaction shots take only -5 aim. +15 aim within 4 tiles."},
	"anti_materiel": {"name": "Anti-materiel rifle", "classes": ["marksman"], "rarity": "rare", "tag": "Mark",
		"look": "dmr", "close": 3.0, "close_aim": -20, "falloff": 16.0, "falloff_aim": 3, "crit": 20, "dmg": 2,
		"mobility": -1, "close_label": "Too close to scope",
		"desc": "+2 damage, +20% crit, no range penalty to 16 tiles. -20 aim at 3 tiles or less, -1 movement."},
	"scout_carbine": {"name": "Scout carbine", "classes": ["marksman", "medic"], "rarity": "uncommon", "tag": "Close",
		"look": "pdw", "close": 3.0, "close_aim": 10, "falloff": 9.0, "falloff_aim": 3, "crit": 10, "mobility": 1,
		"desc": "Light and quick: +1 movement, +10% crit, +10 aim within 3 tiles."},
	"flechette_smg": {"name": "Flechette SMG", "classes": ["medic", "vector", "breacher"], "rarity": "uncommon", "tag": "Close",
		"look": "pdw", "close": 3.0, "close_aim": 25, "falloff": 5.0, "falloff_aim": 6, "graze": 20, "trait": "spread",
		"desc": "+25 aim within 3 tiles, falls off fast past 5. Spread: wider graze band."},
	"dart_rifle": {"name": "Dart rifle", "classes": ["medic"], "rarity": "rare", "tag": "Purge",
		"look": "dmr", "close": 2.0, "close_aim": 0, "falloff": 12.0, "falloff_aim": 2, "aim": 10,
		"desc": "Steady: +10 aim, and it holds that out to 12 tiles."},
	"slug_gun": {"name": "Slug shotgun", "classes": ["breacher"], "rarity": "uncommon", "tag": "Mark",
		"look": "shotgun", "close": 3.0, "close_aim": 15, "falloff": 8.0, "falloff_aim": 4, "crit": 10,
		"desc": "Single slugs: +15 aim within 3 tiles, +10% crit, reaches out to 8 tiles."},
	"auto_shotgun": {"name": "Auto shotgun", "classes": ["breacher", "hazmat"], "rarity": "rare", "tag": "Suppress",
		"look": "shotgun", "close": 3.0, "close_aim": 20, "falloff": 5.0, "falloff_aim": 8, "trait": "pin",
		"desc": "+20 aim within 3 tiles, steep falloff past 5. Pinning fire: a miss still suppresses the target."},
	"pump_shotgun": {"name": "Pump shotgun", "classes": ["trooper", "hazmat"], "rarity": "uncommon", "tag": "Guard",
		"look": "shotgun", "close": 3.0, "close_aim": 20, "falloff": 5.0, "falloff_aim": 8, "graze": 20, "trait": "spread",
		"dmg": 1, "desc": "+1 damage, +20 aim within 3 tiles, steep falloff past 5. Spread: wider graze band."},
	"heavy_mg": {"name": "Heavy machine gun", "classes": ["hazmat"], "rarity": "rare", "tag": "Overwatch",
		"look": "lmg", "close": 3.0, "close_aim": 0, "falloff": 12.0, "falloff_aim": 2, "dmg": 1, "mobility": -1,
		"trait": "pin", "desc": "+1 damage, pinning fire (a miss still suppresses), holds out to 12 tiles. -1 movement."},
	"spore_rifle": {"name": "Spore rifle", "classes": ["vector"], "rarity": "rare", "tag": "Strain",
		"look": "carbine", "close": 3.0, "close_aim": 5, "falloff": 10.0, "falloff_aim": 3, "crit": 10, "dmg": 1, "aim": -5,
		"trait": "snap", "reaction": 0,
		"desc": "+1 damage, +10% crit, -5 aim. Snap shots: overwatch reaction shots take no aim penalty."},
	"spit": {"name": "Spit", "close": 3.0, "close_aim": 15, "falloff": 10.0, "falloff_aim": 3,
		"desc": "Acidic spit."},
}

## Unit kind -> weapon id. Anything not listed fires the default rifle profile.
const BY_KIND := {
	"trooper": "rifle", "marksman": "dmr", "medic": "pdw", "breacher": "shotgun",
	"hazmat": "lmg", "vector": "carbine", "reaper": "sidearm", "warden": "revolver",
	"fallen": "rifle", "colonel_hale": "rifle", "sharpshooter": "dmr", "spitter": "spit",
}


const PRICES := {"uncommon": 55, "rare": 90}


## The signature gun of a unit kind.
static func id_for(kind: String) -> String:
	return BY_KIND.get(kind, DEFAULT)


## The gun this unit carries: its own pick if it has one, else its kind's signature.
static func id_of(u: Unit) -> String:
	var w := str(u.status.get("weapon", ""))
	return w if TABLE.has(w) else id_for(u.kind)


static func of(u: Unit) -> Dictionary:
	return TABLE[id_of(u)]


static func get_gun(id: String) -> Dictionary:
	return TABLE.get(id, {})


static func gun_name(id: String) -> String:
	return TABLE.get(id, {}).get("name", id)


## Name of the gun a unit kind carries by default, or of `weapon` when given.
static func display_name(kind: String, weapon: String = "") -> String:
	return TABLE[weapon if TABLE.has(weapon) else id_for(kind)].name


## Signature gun whose view (feel, model) `id` borrows.
static func look_of(id: String) -> String:
	return TABLE.get(id, {}).get("look", id)


static func is_alternate(id: String) -> bool:
	return TABLE.get(id, {}).has("classes")


## Alternate guns `kind` may carry, sorted by id; filtered by rarity when one is given.
static func alternates_for(kind: String, rarity: String = "") -> Array[String]:
	var out: Array[String] = []
	for id in TABLE:
		var g: Dictionary = TABLE[id]
		if g.get("classes", []).has(kind) and (rarity == "" or g.rarity == rarity):
			out.append(id)
	out.sort()
	return out


static func can_carry(kind: String, id: String) -> bool:
	return id == "" or id == id_for(kind) or TABLE.get(id, {}).get("classes", []).has(kind)


static func rarity_of(id: String) -> String:
	return TABLE.get(id, {}).get("rarity", "")


static func price(id: String) -> int:
	return PRICES.get(rarity_of(id), -1)


static func tag_of(id: String) -> String:
	return TABLE.get(id, {}).get("tag", "")


## Flat stat terms a gun puts on its carrier: {aim, dmg, mobility}, only the non-zero ones.
static func stats(id: String) -> Dictionary:
	var out := {}
	for k in ["aim", "dmg", "mobility"]:
		var n := int(TABLE.get(id, {}).get(k, 0))
		if n != 0:
			out[k] = n
	return out


## Stamps a gun onto a mission Unit: status.weapon plus its flat stat terms. No-op for "", an
## unknown id or a gun the unit's class can't carry, so a stale save keeps the signature gun.
static func equip_unit(u: Unit, id: String) -> void:
	if id == "" or not TABLE.has(id) or id == id_for(u.kind) or not can_carry(u.kind, id):
		return
	u.status["weapon"] = id
	var st := stats(id)
	u.aim += int(st.get("aim", 0))
	u.mobility = maxi(1, u.mobility + int(st.get("mobility", 0)))
	var d := int(st.get("dmg", 0))
	u.damage = Vector2i(maxi(1, u.damage.x + d), maxi(1, u.damage.y + d))


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
