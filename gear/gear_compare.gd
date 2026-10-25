class_name GearCompare
extends RefCounted
## What taking a reward card (or a depot buy) would change on one soldier, for the hover
## compare card (ui/tips/compare_tip.gd): which slot it lands in, what it replaces and where
## the old piece goes (stash, scrapped, kept as a spare gun), the soldier's stats and tag
## counts before and after, and Prototypes it opens or closes. Everything is worked out on a
## copy of the record, so the run never changes.
##
## compare() returns:
##   {"sid", "name", "kind" (the soldier's class),
##    "swaps": [{"kind", "slot", "slot_name", "icon", "mode", "old": side, "new": side, "fate"}],
##    "stats": [{"key", "name", "icon", "from", "to", "better": bool}],   changed stats only
##    "tags": [{"tag", "from", "to", "unlocks", "loses"}],
##    "protos_on": [ids], "protos_off": [ids], "supplies": int, "stash": [before, after]}
## A side is {"name", "rarity", "mk", "tags", "desc", "id", "charges"}; {} is an empty slot.
## Fates: fill (empty slot), stash (old piece to the stash), scrap (stash full: old piece
## scrapped for Supplies), upgrade (merges into Mk II), copy_stash / copy_scrap (a duplicate
## already at Mk II), spare (old gun kept), lost (old mutation removed), add, stack, full,
## supplies, owned (already has it).

## Stat rows in display order: key, name, icon, and the glossary term the name links to.
const STATS := [
	["max_hp", "Max HP", "health", "healing"],
	["aim", "Aim", "marksman", "hit_chance"],
	["damage", "Damage", "attack", ""],
	["crit", "Crit", "star", "crit"],
	["defense", "Defense", "cover_half", "cover"],
	["mobility", "Move", "move", "tile_move"],
	["range", "Range", "shoot", ""],
	["infection", "Infection", "infection", "infection"],
]
## Stats where a lower number is the better one.
const LOWER_IS_BETTER := ["infection"]


static func compare(run, record: Dictionary, card: Dictionary) -> Dictionary:
	var after: Dictionary = record.duplicate(true)
	var stash_now := Loadout.stash(run).size() if run != null else 0
	var st := {"stash": stash_now, "supplies": 0}
	var swaps: Array = []
	var contents: Array = card.get("contents", []) if str(card.get("kind", "")) == "order" else [card]
	for c in contents:
		var s := _apply(after, c, st)
		if not s.is_empty():
			swaps.append(s)
	if str(card.get("kind", "")) == "order" and int(card.get("infection", 0)) > int(after.get("infection", 0)):
		after["infection"] = int(card.infection)
	var before_tags := GearTags.counts(record)
	var after_tags := GearTags.counts(after)
	var p_before := GearTags.qualified_prototypes(before_tags)
	var p_after := GearTags.qualified_prototypes(after_tags)
	return {
		"sid": record.get("id", -1), "name": str(record.get("name", "")), "kind": str(record.get("kind", "")),
		"swaps": swaps,
		"stats": stat_rows(stats(record), stats(after)),
		"tags": GearTags.diff(before_tags, after_tags),
		"protos_on": p_after.filter(func(id): return not p_before.has(id)),
		"protos_off": p_before.filter(func(id): return not p_after.has(id)),
		"supplies": st.supplies,
		"stash": [stash_now, st.stash],
	}


## The soldier's numbers as a mission would field them: class base, rank and perks, grafts,
## gear, gun, and the Infection tier's passives.
static func stats(record: Dictionary) -> Dictionary:
	var kind := str(record.get("kind", "trooper"))
	if not UnitData.SOLDIERS.has(kind):
		return {}
	var u := UnitData.make(kind, Types.Team.PLAYER)
	var prog = GearTags.progression()
	if GearTags.provides(prog, "apply_record") and record.get("prog") is Dictionary:
		prog.apply_record(u, record.prog)
	GearRun.apply_to_unit(u, record)
	u.infection = int(record.get("infection", 0))
	Infection.sync_passives(u)
	Kit.refresh_stats(null, u)
	var gun := Weapons.get_gun(Loadout.gun_id(record))
	return {
		"max_hp": u.max_hp, "aim": u.aim, "damage": u.damage, "crit": int(gun.get("crit", 0)),
		"defense": u.defense, "mobility": u.mobility, "range": int(gun.get("falloff", 0)),
		"infection": u.infection,
	}


## The rows that differ between two stats() results, in STATS order.
static func stat_rows(before: Dictionary, after: Dictionary) -> Array:
	var out: Array = []
	for s in STATS:
		var k: String = s[0]
		if not before.has(k) or before[k] == after.get(k):
			continue
		var a = before[k]
		var b = after.get(k)
		var up: bool = (b.x + b.y > a.x + a.y) if a is Vector2i else b > a
		out.append({"key": k, "name": s[1], "icon": s[2], "term": s[3], "from": a, "to": b,
			"better": up != LOWER_IS_BETTER.has(k)})
	return out


## Applies one card to the copied record and says what it swapped. `st` carries the stash
## size and Supplies across an order's several contents.
static func _apply(after: Dictionary, c: Dictionary, st: Dictionary) -> Dictionary:
	var id := str(c.get("id", ""))
	match str(c.get("kind", "gear")):
		"gear":
			return _apply_gear(after, id, st)
		"gun":
			var s := {"kind": "gun", "slot": "gun", "slot_name": "Gun", "icon": "weapon",
				"old": gun_side(Loadout.gun_id(after)), "new": gun_side(id), "mode": "carry", "fate": "spare"}
			if Loadout.owns_gun(after, id):
				s.fate = "owned"
			Loadout.add_gun(after, id)
			return s
		"perk":
			var s := {"kind": "perk", "slot": "perk", "slot_name": "Perk", "icon": "perk", "mode": "add",
				"old": {}, "new": power_side(c), "fate": "add"}
			_apply_card(after, c)
			return s
		"mutation":
			var m := MutationData.get_def(id)
			var slot := str(m.get("slot", ""))
			var old := str(after.get("prog", {}).get("mutations", {}).get(slot, ""))
			var s := {"kind": "mutation", "slot": slot, "icon": "mutation",
				"slot_name": "Mutation · %s" % Infection.tier_name(MutationData.awake_at(id)),
				"old": power_side(Progression.mutation_card_for(old)) if old != "" else {}, "new": power_side(c),
				"mode": "replace" if old != "" else "add", "fate": "lost" if old != "" else "add"}
			_apply_card(after, c)
			return s
		"graft":
			var slot := GraftData.slot_of(id)
			var old := str(Grafts.of(after).get(slot, ""))
			var s := {"kind": "graft", "slot": slot, "slot_name": "Graft · %s" % GraftData.SLOT_NAMES.get(slot, slot),
				"icon": "bloom" if GraftData.is_bloom(id) else "refit",
				"old": graft_side(old) if old != "" else {}, "new": graft_side(id), "mode": "add",
				"fate": "owned" if old != "" else "add"}
			_apply_card(after, c)
			return s
		"consumable":
			var charges := int(c.get("charges", GearData.CONSUMABLE_CHARGES))
			var have := 0
			for p in Loadout.pockets(after):
				if p != null and p.id == id:
					have = int(p.charges)
			var s := {"kind": "consumable", "slot": "pocket", "slot_name": "Pocket", "icon": "consumable", "mode": "add",
				"old": {"name": GearData.item_name(id), "charges": have, "desc": GearData.desc(id), "id": id} if have > 0 else {},
				"new": {"name": GearData.item_name(id), "charges": have + charges, "desc": GearData.desc(id), "id": id},
				"fate": "stack" if have > 0 else "add"}
			if not Loadout.add_consumable(after, id, charges):
				s.fate = "full"
				s.new.charges = 0
			return s
		"cache":
			var n := int(c.get("supplies", GearRun.CACHE_SUPPLIES))
			st.supplies += n
			return {"kind": "cache", "slot": "supplies", "slot_name": "Supplies", "icon": "supplies", "mode": "add",
				"old": {}, "new": {"name": "+%d Supplies" % n}, "fate": "supplies"}
	return {}


static func _apply_gear(after: Dictionary, id: String, st: Dictionary) -> Dictionary:
	if not GearData.exists(id):
		return {}
	var pv := Loadout.preview_equip(after, id)
	var slot: String = pv.slot
	var proto := GearData.PROTOTYPES.has(id)
	var s := {"kind": "gear", "slot": slot, "slot_name": GearData.SLOT_NAMES.get(slot, slot), "icon": slot,
		"mode": pv.mode, "old": {}, "new": gear_side(id, 2 if proto else 1), "fate": "fill"}
	var g := Loadout.of(after)
	match pv.mode:
		"equip":
			g.slots[slot] = {"id": id, "mk": 2 if proto else 1}
		"upgrade":
			s.old = gear_side(id, int(g.slots[slot].mk))
			s.new = gear_side(id, 2)
			s.fate = "upgrade"
			g.slots[slot].mk = 2
		"stash":
			s.old = gear_side(id, 2)
			s.new = gear_side(id, 2)
			s.fate = _to_stash(st, "copy_stash", "copy_scrap")
		"replace":
			s.old = gear_side(pv.old.id, int(pv.old.mk))
			s.fate = _to_stash(st, "stash", "scrap")
			g.slots[slot] = {"id": id, "mk": 2 if proto else 1}
	return s


## One more item into the stash: `room` if it fits, else `full` and the scrap Supplies.
static func _to_stash(st: Dictionary, room: String, full: String) -> String:
	if st.stash < GearData.STASH_SIZE:
		st.stash += 1
		return room
	st.supplies += Loadout.SCRAP_SUPPLIES
	return full


static func _apply_card(after: Dictionary, c: Dictionary) -> void:
	var prog = GearTags.progression()
	if GearTags.provides(prog, "apply_card"):
		prog.apply_card(after, c)


static func gear_side(id: String, mk: int) -> Dictionary:
	var it := GearData.get_item(id)
	return {"id": id, "name": str(it.get("name", id)), "rarity": str(it.get("rarity", "")), "mk": mk,
		"tags": it.get("tags", []), "desc": GearData.desc(id, mk)}


static func gun_side(id: String) -> Dictionary:
	var g := Weapons.get_gun(id)
	var tag := str(g.get("tag", ""))
	return {"id": id, "name": str(g.get("name", id)), "rarity": str(g.get("rarity", "")),
		"tags": [tag] if tag != "" else [], "desc": str(g.get("desc", ""))}


static func power_side(c: Dictionary) -> Dictionary:
	if c.is_empty():
		return {}
	var tag := GearTags.normalize(str(c.get("tag", "")))
	return {"id": str(c.get("id", "")), "name": str(c.get("name", c.get("id", ""))), "rarity": str(c.get("rarity", "")),
		"tags": [tag] if tag != "" else [], "desc": str(c.get("desc", ""))}


static func graft_side(id: String) -> Dictionary:
	var d := GraftData.get_def(id)
	var tag := GearTags.normalize(str(d.get("tag", "")))
	return {"id": id, "name": GraftData.name_of(id), "rarity": "bloom" if GraftData.is_bloom(id) else "machine",
		"tags": [tag] if tag != "" else [], "desc": str(d.get("desc", ""))}
