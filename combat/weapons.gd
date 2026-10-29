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
## Alternate gun fields: "classes" (the soldier kinds it was made for; any soldier may carry it, melee classes only the one-handed ones), "rarity" ("uncommon" |
## "rare", for draws and depot prices), "tag" (counts toward gear set bonuses), "look" (the
## signature gun whose feel and model it borrows in the view).
## Range terms replace the old flat close/long range modifiers. Distances are Euclidean
## tiles, like the rest of Combat:
##   "close": tiles at or under which the "close_aim" term applies (it may be negative).
##   "falloff": distance past which every started tile costs "falloff_aim" aim.
## "mag": rounds in a full magazine (see Ammo).
## Traits: "pin" (a miss still suppresses the target), "snap" (overwatch reaction shots take
## "reaction" instead of Combat.REACTION_PENALTY), "spread" (a wider graze band).

const DEFAULT := "rifle"

const TABLE := {
	"rifle": {"rarity": "rare", "name": "Assault rifle", "mag": 6, "close": 3.0, "close_aim": 15, "falloff": 10.0, "falloff_aim": 3,
		"desc": "Reliable at any range."},
	"dmr": {"rarity": "rare", "name": "Marksman rifle", "mag": 4, "close": 2.0, "close_aim": -10, "falloff": 14.0, "falloff_aim": 3,
		"crit": 15, "close_label": "Too close to scope",
		"desc": "No range penalty out to sight range, +15% crit. -10 aim at 2 tiles or less."},
	"pdw": {"rarity": "rare", "name": "PDW", "mag": 8, "close": 4.0, "close_aim": 20, "falloff": 7.0, "falloff_aim": 5,
		"trait": "quarters",
		"desc": "+20 aim within 4 tiles; falls off fast past 7. Close quarters: a kill within 4 tiles gives the round back."},
	"shotgun": {"rarity": "rare", "name": "Combat shotgun", "mag": 4, "close": 3.0, "close_aim": 25, "falloff": 5.0, "falloff_aim": 8,
		"graze": 20, "trait": "spread", "also": "breach",
		"desc": "+25 aim within 3 tiles, steep falloff past 5. Spread: wider graze band. Breach: shots within 2 tiles ignore the target's cover."},
	"lmg": {"rarity": "rare", "name": "Light machine gun", "mag": 10, "close": 3.0, "close_aim": 5, "falloff": 11.0, "falloff_aim": 2,
		"trait": "pin",
		"desc": "Pinning fire: a miss still suppresses the target (-30 aim on its next shot)."},
	"carbine": {"rarity": "rare", "name": "Bio-carbine", "mag": 6, "close": 3.0, "close_aim": 10, "falloff": 9.0, "falloff_aim": 3,
		"trait": "snap", "reaction": 0,
		"desc": "Snap shots: overwatch reaction shots take no aim penalty."},
	"sidearm": {"name": "Sidearm", "mag": 6, "close": 3.0, "close_aim": 10, "falloff": 7.0, "falloff_aim": 4,
		"desc": "Backup pistol: +10 aim within 3 tiles, falls off past 7. As a starter pistol on a ranged soldier: -1 damage and 4 rounds."},
	"revolver": {"name": "Heavy revolver", "mag": 6, "close": 3.0, "close_aim": 5, "falloff": 6.0, "falloff_aim": 4, "crit": 10,
		"desc": "One-handed over the shield rim: +10% crit, falls off past 6."},
	# Alternate guns.
	"battle_rifle": {"name": "Battle rifle", "mag": 5, "classes": ["trooper", "marksman"], "rarity": "uncommon", "tag": "Suppress",
		"look": "rifle", "close": 3.0, "close_aim": 10, "falloff": 12.0, "falloff_aim": 2, "aim": -5, "dmg": 1,
		"trait": "heavy",
		"desc": "+1 damage, -5 aim, holds its accuracy out to 12 tiles. Heavy rounds: hits shove the target back a tile."},
	"burst_carbine": {"name": "Burst carbine", "mag": 6, "classes": ["trooper", "vector"], "rarity": "rare", "tag": "Overwatch",
		"look": "carbine", "close": 4.0, "close_aim": 15, "falloff": 8.0, "falloff_aim": 4, "crit": 5,
		"trait": "snap", "reaction": 5,
		"desc": "Snap shots: overwatch reaction shots take only -5 aim. +15 aim within 4 tiles."},
	"anti_materiel": {"name": "Anti-materiel rifle", "mag": 3, "classes": ["marksman"], "rarity": "rare", "tag": "Mark",
		"look": "dmr", "close": 3.0, "close_aim": -20, "falloff": 16.0, "falloff_aim": 3, "crit": 20, "dmg": 2,
		"mobility": -1, "close_label": "Too close to scope", "trait": "pierce",
		"desc": "+2 damage, +20% crit, no range penalty to 16 tiles. -20 aim at 3 tiles or less, -1 movement. Pierce: the round carries on and hits the next enemy in line for half damage."},
	"scout_carbine": {"name": "Scout carbine", "mag": 6, "classes": ["marksman", "medic"], "rarity": "uncommon", "tag": "Close",
		"look": "pdw", "close": 3.0, "close_aim": 10, "falloff": 9.0, "falloff_aim": 3, "crit": 10, "trait": "skirmish",
		"desc": "+10% crit, +10 aim within 3 tiles. Skirmisher: after a move of 3 or more tiles, your first shot this turn costs no action."},
	"flechette_smg": {"name": "Flechette SMG", "mag": 8, "classes": ["medic", "vector", "breacher"], "rarity": "uncommon", "tag": "Close",
		"look": "pdw", "close": 3.0, "close_aim": 25, "falloff": 5.0, "falloff_aim": 6, "graze": 20, "trait": "spread", "also": "barbs",
		"desc": "+25 aim within 3 tiles, falls off fast past 5. Spread: wider graze band. Barbs: a hit leaves a barb, and a barbed enemy that moves takes 1 damage per barb."},
	"dart_rifle": {"name": "Dart rifle", "mag": 5, "classes": ["medic"], "rarity": "rare", "tag": "Purge",
		"look": "dmr", "close": 2.0, "close_aim": 0, "falloff": 12.0, "falloff_aim": 2, "aim": 10,
		"trait": "tranq",
		"desc": "+10 aim, holds that out to 12 tiles. Tranquiliser: a second hit on the same target stuns it."},
	"slug_gun": {"name": "Slug shotgun", "mag": 4, "classes": ["breacher"], "rarity": "uncommon", "tag": "Mark",
		"look": "shotgun", "close": 3.0, "close_aim": 15, "falloff": 8.0, "falloff_aim": 4, "crit": 10, "trait": "doorkick",
		"desc": "+15 aim within 3 tiles, +10% crit, reaches out to 8 tiles. Door kicker: slugs ignore half cover."},
	"auto_shotgun": {"name": "Auto shotgun", "mag": 5, "classes": ["breacher", "hazmat"], "rarity": "rare", "tag": "Suppress",
		"look": "shotgun", "close": 3.0, "close_aim": 20, "falloff": 5.0, "falloff_aim": 8, "trait": "pin",
		"desc": "+20 aim within 3 tiles, steep falloff past 5. Pinning fire: a miss still suppresses the target."},
	"pump_shotgun": {"name": "Pump shotgun", "mag": 4, "classes": ["trooper", "hazmat"], "rarity": "uncommon", "tag": "Guard",
		"look": "shotgun", "close": 3.0, "close_aim": 20, "falloff": 5.0, "falloff_aim": 8, "graze": 20, "trait": "spread",
		"dmg": 1, "desc": "+1 damage, +20 aim within 3 tiles, steep falloff past 5. Spread: wider graze band."},
	"heavy_mg": {"name": "Heavy machine gun", "mag": 12, "classes": ["hazmat"], "rarity": "rare", "tag": "Overwatch",
		"look": "lmg", "close": 3.0, "close_aim": 0, "falloff": 12.0, "falloff_aim": 2, "dmg": 1, "mobility": -1,
		"trait": "pin", "desc": "+1 damage, pinning fire (a miss still suppresses), holds out to 12 tiles. -1 movement."},
	"spore_rifle": {"name": "Spore rifle", "mag": 5, "classes": ["vector"], "rarity": "rare", "tag": "Strain",
		"look": "carbine", "close": 3.0, "close_aim": 5, "falloff": 10.0, "falloff_aim": 3, "crit": 10, "dmg": 1, "aim": -5,
		"trait": "snap", "reaction": 0,
		"desc": "+1 damage, +10% crit, -5 aim. Snap shots: overwatch reaction shots take no aim penalty."},
	# Melee classes' alternates are all one-handed, so they ride in the hand the sidearm did.
	"machine_pistol": {"name": "Machine pistol", "mag": 8, "classes": ["reaper"], "rarity": "uncommon", "tag": "Close",
		"look": "sidearm", "close": 3.0, "close_aim": 20, "falloff": 5.0, "falloff_aim": 6, "graze": 20, "trait": "spread", "also": "spray",
		"desc": "+20 aim within 3 tiles, falls off fast past 5. Spread: wider graze band. Spray: one action fires twice, the second shot at -20 aim."},
	"bloom_pistol": {"name": "Bloom pistol", "mag": 5, "classes": ["reaper"], "rarity": "rare", "tag": "Strain",
		"look": "sidearm", "close": 3.0, "close_aim": 10, "falloff": 7.0, "falloff_aim": 4, "dmg": 1, "aim": -5,
		"trait": "snap", "reaction": 0,
		"desc": "+1 damage, -5 aim. Snap shots: overwatch reaction shots take no aim penalty."},
	"hand_cannon": {"name": "Hand cannon", "mag": 4, "classes": ["reaper", "warden"], "rarity": "rare", "tag": "Mark",
		"look": "revolver", "close": 3.0, "close_aim": 5, "falloff": 6.0, "falloff_aim": 4, "dmg": 1, "crit": 15, "aim": -5,
		"trait": "recoil",
		"desc": "+1 damage, +15% crit, -5 aim, falls off past 6. Recoil: a crit ends the target's turn."},
	"stun_pistol": {"name": "Stun pistol", "mag": 6, "classes": ["warden"], "rarity": "uncommon", "tag": "Suppress",
		"look": "sidearm", "close": 3.0, "close_aim": 10, "falloff": 6.0, "falloff_aim": 4, "dmg": -1, "trait": "pin",
		"desc": "-1 damage. Pinning fire: a miss still suppresses the target."},
	"longslide": {"name": "Longslide pistol", "mag": 6, "classes": ["warden"], "rarity": "uncommon", "tag": "Overwatch",
		"look": "sidearm", "close": 3.0, "close_aim": 0, "falloff": 9.0, "falloff_aim": 3, "aim": 5, "crit": 5,
		"desc": "Long barrel: +5 aim, +5% crit, holds out to 9 tiles."},
	"spit": {"name": "Spit", "mag": 6, "close": 3.0, "close_aim": 15, "falloff": 10.0, "falloff_aim": 3,
		"desc": "Acidic spit."},
}

## Unit kind -> weapon id. Anything not listed fires the default rifle profile.
const BY_KIND := {
	"trooper": "rifle", "marksman": "dmr", "medic": "pdw", "breacher": "shotgun",
	"hazmat": "lmg", "vector": "carbine", "reaper": "sidearm", "warden": "revolver",
	"fallen": "rifle", "colonel_hale": "rifle", "director": "dmr", "choir_prophet": "pdw", "sharpshooter": "dmr", "spitter": "spit",
}


## Ranged classes start a run on the sidearm and find their class gun later (see Loadout.has_primary).
const START_GUN := "sidearm"
## A ranged soldier's starting pistol is weaker than the Reaper's: -1 damage and a short magazine.
const STARTER_DAMAGE_PENALTY := 1
const STARTER_MAG := 4
const FOUND_PRIMARY: Array[String] = ["trooper", "marksman", "medic", "breacher", "hazmat", "vector"]

const MELEE_KINDS: Array[String] = ["reaper", "warden"]

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
		if is_alternate(id) and can_carry(kind, id) and (rarity == "" or g.rarity == rarity):
			out.append(id)
	out.sort()
	return out


## Guns are universal gear: any soldier may carry any alternate, except that the melee
## classes hold only one-handed pistols (their model has one free hand, see view/melee_kit.gd).
static func can_carry(kind: String, id: String) -> bool:
	if id == "" or id == id_for(kind) or (id == START_GUN and starts_on_sidearm(kind)):
		return true
	if not is_alternate(id):
		return false
	return not MELEE_KINDS.has(kind) or look_of(id) in ["sidearm", "revolver"]


## True for classes that start a run on the sidearm and have to find their signature gun.
static func starts_on_sidearm(kind: String) -> bool:
	return FOUND_PRIMARY.has(kind)


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
	var d := int(st.get("dmg", 0)) - (STARTER_DAMAGE_PENALTY if id == START_GUN and starts_on_sidearm(u.kind) else 0)
	u.damage = Vector2i(maxi(1, u.damage.x + d), maxi(1, u.damage.y + d))


## Rounds in a full magazine of this unit's gun, before gear and perks (Ammo.mag_size).
static func mag_of(u: Unit) -> int:
	if id_of(u) == START_GUN and starts_on_sidearm(u.kind):
		return STARTER_MAG
	return int(of(u).get("mag", Ammo.DEFAULT_MAG))


## Rounds in a full magazine of gun `id` in the hands of class `kind`, before gear and perks.
static func mag_for(id: String, kind: String = "") -> int:
	if id == START_GUN and kind != "" and starts_on_sidearm(kind):
		return STARTER_MAG
	return int(get_gun(id).get("mag", Ammo.DEFAULT_MAG))


static func has_trait(u: Unit, t: String) -> bool:
	var g := of(u)
	return g.get("trait", "") == t or g.get("also", "") == t


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


# ---------------------------------------------------------------- traits

const BREACH_RANGE := 2.0
const SPRAY_PENALTY := 20
const BARB_MAX := 3
const SKIRMISH_STEPS := 3


## Odds terms from the gun's trait: Breach and Door kicker take cover away, Spray's second shot is wilder.
static func odds_terms(s: GameState, u: Unit, t: Unit, from: Vector2i, cover: int, breakdown: Array) -> void:
	if cover != Types.Cover.NONE and has_trait(u, "breach") and from.distance_to(t.pos) <= BREACH_RANGE:
		breakdown.append(["Breach", Combat.COVER_FULL if cover == Types.Cover.FULL else Combat.COVER_HALF])
	elif cover == Types.Cover.HALF and has_trait(u, "doorkick"):
		breakdown.append(["Door kicker", Combat.COVER_HALF])
	if u.status.get("spray_second", false):
		breakdown.append(["Spray", -SPRAY_PENALTY])


## A shot from `u` hit `t` for `dmg` (after the damage landed): Pierce, Heavy rounds, Barbs, Tranquiliser,
## Recoil and Close quarters.
static func after_hit(s: GameState, u: Unit, t: Unit, dmg: int, crit: bool) -> void:
	if dmg <= 0 or u.status.get("w_busy", false):
		return
	var dir := Vector2i(signi(t.pos.x - u.pos.x), signi(t.pos.y - u.pos.y))
	if has_trait(u, "pierce") and dir != Vector2i.ZERO:
		var behind: Unit = s.unit_at(t.pos + dir)
		if behind != null and behind.is_alive() and u.is_enemy_of(behind):
			u.status["w_busy"] = true
			s.emit({"type": "perk", "unit": u.id, "perk": "pierce", "target": behind.id})
			Rules.deal_damage(s, behind, maxi(1, dmg / 2), u)
			u.status.erase("w_busy")
	if not t.is_alive():
		if has_trait(u, "quarters") and u.pos.distance_to(t.pos) <= float(of(u).close) and Ammo.give(u, 1) > 0:
			s.emit({"type": "gear", "unit": u.id, "item": "rounds_back", "ammo": Ammo.rounds(u), "rounds": 1})
		return
	if has_trait(u, "heavy") and dir != Vector2i.ZERO:
		var before := t.pos
		EnemyAbilities.knockback(s, t, dir, 1)
		if t.pos != before:
			s.emit({"type": "perk", "unit": u.id, "perk": "heavy", "target": t.id})
	if has_trait(u, "barbs"):
		t.status["k_barbs"] = mini(BARB_MAX, int(t.status.get("k_barbs", 0)) + 1)
	if has_trait(u, "tranq"):
		if t.status.get("k_tranq", false):
			t.status.erase("k_tranq")
			t.status["k_skip_turn"] = true
			t.actions_left = 0
			s.emit({"type": "perk", "unit": u.id, "perk": "tranq", "target": t.id})
		else:
			t.status["k_tranq"] = true
	if has_trait(u, "recoil") and crit:
		t.status["k_skip_turn"] = true
		t.actions_left = 0
		s.emit({"type": "perk", "unit": u.id, "perk": "recoil", "target": t.id})


## Skirmisher: after a move of SKIRMISH_STEPS or more, the first shot each turn costs no action.
static func skirmish_free(s: GameState, u: Unit) -> bool:
	if not has_trait(u, "skirmish") or int(u.status.get("gear_moved_turn", -1)) != s.turn \
			or int(u.status.get("gear_move_len", 0)) < SKIRMISH_STEPS or int(u.status.get("w_skirmish_turn", -1)) == s.turn:
		return false
	u.status["w_skirmish_turn"] = s.turn
	return true


## Barbs: a barbed enemy that moved this turn takes a point per barb, then works them loose.
static func barbs_tick(s: GameState, u: Unit, start: Vector2i) -> void:
	var n := int(u.status.get("k_barbs", 0))
	if n <= 0 or not u.is_alive() or u.pos == start:
		return
	u.status.erase("k_barbs")
	s.emit({"type": "perk", "unit": u.id, "perk": "barbs"})
	Rules.cause = "Barbs"
	Rules.deal_damage(s, u, n, null)
	Rules.cause = ""
