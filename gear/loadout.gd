class_name Loadout
extends RefCounted
## A soldier's equipment, kept on their run record as `record.gear` (plain data, so it
## serializes for saves and network sync):
##   {"slots": {"head", "body", "offhand", "melee", "gun", "weapon", "ammo", "utility", "utility2": {"id", "mk"} | null},
##    "pockets": [{"id", "charges"} | null, ...], "primary": bool (ranged soldiers: found their class gun)}
## Guns live in combat/weapons.gd and are gear: the one in the Gun slot is the one fired, spares
## ride in the stash, and a gun's tag counts like a gear item's.
## The squad stash lives in `run.gear.stash` as an Array of {"id", "mk"} (GearRun owns it).
## Every rule about duplicates, Mk II and the stash is here, so other modules call these
## functions instead of writing the dictionaries.

const SCRAP_SUPPLIES := 10  # an item that no longer fits anywhere is scrapped for Supplies


static func make() -> Dictionary:
	var slots := {}
	for slot in GearData.SLOTS:
		slots[slot] = null
	var pockets := []
	pockets.resize(GearData.POCKETS)
	return {"slots": slots, "pockets": pockets}


## The record's loadout, created on first use.
static func of(record) -> Dictionary:
	if record.get("gear") == null or (record.gear is Dictionary and record.gear.is_empty()):
		record["gear"] = make()
	_migrate(record.gear)
	_fill_gun(record)
	return record.gear


## Saves from before the slot rework kept "armor" and "gadget" slots.
static func _migrate(g: Dictionary) -> void:
	for slot in GearData.SLOTS:
		if not g.slots.has(slot):
			g.slots[slot] = null
	# Saves from before guns were gear kept the carried gun in "gun" and the spares in "guns".
	if g.has("gun") or g.has("guns"):
		var old := str(g.get("gun", ""))
		if old != "" and g.slots.gun == null:
			g.slots.gun = {"id": old, "mk": 1}
		g.erase("gun")
		g.erase("guns")
	for old in ["armor", "gadget"]:
		if not g.slots.has(old):
			continue
		var it = g.slots[old]
		g.slots.erase(old)
		if it != null:
			var s: String = GearData.slots_for(GearData.slot_of(it.id))[0]
			if g.slots.get(s) != null and s == "utility":
				s = "utility2"
			g.slots[s] = it


## A soldier always holds a gun: an empty Gun slot takes their class gun.
static func _fill_gun(record) -> void:
	var g: Dictionary = record.gear
	if g.slots.get("gun") == null:
		g.slots["gun"] = {"id": Weapons.id_for(str(record.get("kind", ""))), "mk": 1}


static func item_at(record, slot: String):
	return of(record).slots.get(slot)


## Every equipped gear item as {"slot", "id", "mk"}, in slot order. The gun is not listed:
## it is always there (see `gun_id`) and has its own rules.
static func equipped(record) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var g := of(record)
	for slot in GearData.SLOTS:
		if slot == "gun":
			continue
		var it = g.slots.get(slot)
		if it != null:
			out.append({"slot": slot, "id": it.id, "mk": it.mk})
	return out


static func has_item(record, id: String) -> bool:
	return equipped(record).any(func(e): return e.id == id)


static func mk_of(record, id: String) -> int:
	for e in equipped(record):
		if e.id == id:
			return e.mk
	return 0


## Tag counts from gear alone ({"Mark": 2, ...}). Prototypes count for both tags, the gun
## being carried counts for its tag.
static func gear_tags(record) -> Dictionary:
	var out := {}
	for e in equipped(record):
		for t in GearData.tags_of(e.id):
			out[t] = out.get(t, 0) + 1
	var gt := Weapons.tag_of(gun_id(record))
	if gt != "":
		out[gt] = out.get(gt, 0) + 1
	return out


# --- Guns ---------------------------------------------------------------------------------

## The gun the soldier carries when it is not their class gun, or "" for the class gun.
static func gun(record) -> String:
	var id := gun_id(record)
	return "" if id == Weapons.id_for(str(record.get("kind", ""))) else id


## The weapon id the soldier fires: whatever sits in their Gun slot.
static func gun_id(record) -> String:
	var it = of(record).slots.get("gun")
	return str(it.id) if it != null else Weapons.id_for(str(record.get("kind", "")))


## True when the soldier carries `id` (spares in the stash are not theirs yet).
static func owns_gun(record, id: String) -> bool:
	return id == "" or gun_id(record) == id


## False while a ranged soldier is still on the starting sidearm. Records without the flag
## (older saves, melee classes) count as having their class gun.
static func has_primary(record) -> bool:
	return not Weapons.starts_on_sidearm(str(record.get("kind", ""))) or bool(of(record).get("primary", true))


## Puts a new ranged soldier on the sidearm until they find their class gun.
static func start_on_sidearm(record) -> void:
	if not Weapons.starts_on_sidearm(str(record.get("kind", ""))):
		return
	var g := of(record)
	g["primary"] = false
	g.slots["gun"] = {"id": Weapons.START_GUN, "mk": 1}


## Takes a gun found on a run and carries it; the gun it replaces goes to the stash when
## `run` is given (and is dropped for a throwaway record, as in previews and the balance sim).
## False if the soldier can't use it.
static func take_gun(record, id: String, run = null) -> bool:
	if not Weapons.is_item(id) or not Weapons.can_carry(str(record.get("kind", "")), id):
		return false
	if id == Weapons.id_for(str(record.get("kind", ""))):
		of(record)["primary"] = true
	if gun_id(record) == id:
		return true
	if run != null:
		equip(run, record, id)
	else:
		of(record).slots["gun"] = {"id": id, "mk": 1}
	return true


## Throwaway helper for sims and previews: carries `id` with no stash involved.
static func add_gun(record, id: String, carry: bool = true) -> bool:
	if not carry:
		return Weapons.is_item(id) and Weapons.can_carry(str(record.get("kind", "")), id)
	return take_gun(record, id)


## Alternate guns this soldier could still be offered (not the one in their hands).
static func gun_pool(record, rarity: String = "") -> Array[String]:
	var have := gun_id(record)
	return Weapons.alternates_for(str(record.get("kind", "")), rarity).filter(func(id): return id != have)


## How picking `id` would land: "upgrade" (duplicate -> Mk II), "equip" (empty slot),
## "replace" (old item goes to the stash), or "stash" (duplicate already at Mk II).
static func preview_equip(record, id: String) -> Dictionary:
	var options := GearData.slots_for(GearData.slot_of(id))
	for slot in options:
		var held = item_at(record, slot)
		if held != null and held.id == id:
			return {"mode": "upgrade" if held.mk < 2 and slot != "gun" else "stash", "slot": slot}
	for slot in options:
		if item_at(record, slot) == null:
			return {"mode": "equip", "slot": slot}
	return {"mode": "replace", "slot": options[0], "old": item_at(record, options[0]).duplicate()}


## Equips `id` on the soldier. A duplicate upgrades to Mk II; a different item in the slot
## is moved to the stash (or scrapped for Supplies if the stash is full). Returns
## {"mode", "slot", "displaced": {id, mk} or null, "scrapped": bool}.
static func equip(run, record, id: String, mk: int = 1) -> Dictionary:
	assert(GearData.exists(id), "unknown item %s" % id)
	if GearData.PROTOTYPES.has(id):
		mk = 2
	var p := preview_equip(record, id)
	var g := of(record)
	if id == Weapons.id_for(str(record.get("kind", ""))):
		g["primary"] = true
	var hp_before := gear_max_hp(record)
	var res := {"mode": p.mode, "slot": p.slot, "displaced": null, "scrapped": false}
	match p.mode:
		"equip":
			g.slots[p.slot] = {"id": id, "mk": mk}
		"upgrade":
			g.slots[p.slot].mk = 2
		"stash":
			res.scrapped = not stash_add(run, id, 2)
		"replace":
			res.displaced = p.old
			res.scrapped = not stash_add(run, p.old.id, p.old.mk)
			g.slots[p.slot] = {"id": id, "mk": mk}
	_fit_pockets(run, record)
	_sync_hp(record, hp_before)
	return res


## Moves the item in `slot` to the stash. False if the slot is empty or the stash is full.
static func unequip(run, record, slot: String) -> bool:
	var it = item_at(record, slot)
	if it == null or slot == "gun" or stash_full(run):
		return false
	var hp_before := gear_max_hp(record)
	stash_add(run, it.id, it.mk)
	of(record).slots[slot] = null
	_fit_pockets(run, record)
	_sync_hp(record, hp_before)
	return true


## Armorer / reward upgrade of the item in `slot` to Mk II. False if empty or already Mk II.
static func upgrade(record, slot: String) -> bool:
	var it = item_at(record, slot)
	if it == null or it.mk >= 2 or slot == "gun":
		return false
	var hp_before := gear_max_hp(record)
	it.mk = 2
	_sync_hp(record, hp_before)
	return true


## Max HP the soldier's equipped gear adds (Kevlar vest, Filter mask Mk II, ...).
static func gear_max_hp(record) -> int:
	var total := 0
	for e in equipped(record):
		total += int(GearData.stats(e.id, e.mk).get("max_hp", 0))
	return total


## Gear max HP changed outside a fight: the run record's max_hp and hp move with it, so new
## armour arrives with its HP filled and dropping it can't leave hp above max (never below 1).
static func _sync_hp(record, before: int) -> void:
	var delta := gear_max_hp(record) - before
	if delta == 0 or not record.has("max_hp"):
		return
	record.max_hp += delta
	record.hp = clampi(int(record.hp) + delta, 1, record.max_hp) if int(record.hp) > 0 else record.hp


# --- Stash -----------------------------------------------------------------------------

static func stash(run) -> Array:
	var gs: Dictionary = GearRun.state(run)
	return gs.stash


static func stash_full(run) -> bool:
	return stash(run).size() >= GearData.STASH_SIZE


## Adds an item to the squad stash. If it's full the item is scrapped for Supplies and this
## returns false.
static func stash_add(run, id: String, mk: int = 1) -> bool:
	if stash_full(run):
		GearRun.add_supplies(run, SCRAP_SUPPLIES)
		return false
	stash(run).append({"id": id, "mk": mk})
	return true


## Takes stash item `index` and equips it on the soldier (the item it replaces goes into the
## freed stash space, so a swap never scraps anything).
static func take_from_stash(run, record, index: int) -> Dictionary:
	var st := stash(run)
	if index < 0 or index >= st.size():
		return {}
	var it: Dictionary = st[index]
	st.remove_at(index)
	return equip(run, record, it.id, it.mk)


# --- Pockets ---------------------------------------------------------------------------

static func pocket_count(record) -> int:
	return GearData.POCKETS + (1 if has_item(record, "exo_frame") else 0)


static func pockets(record) -> Array:
	return of(record).pockets


## Can `id` go into a pocket (stacking onto the same consumable or an empty pocket)?
static func can_add_consumable(record, id: String) -> bool:
	for p in pockets(record):
		if p == null or p.id == id:
			return true
	return false


static func add_consumable(record, id: String, charges: int = 1) -> bool:
	assert(GearData.CONSUMABLES.has(id), "unknown consumable %s" % id)
	var ps := pockets(record)
	for p in ps:
		if p != null and p.id == id:
			p.charges += charges
			return true
	for i in ps.size():
		if ps[i] == null:
			ps[i] = {"id": id, "charges": charges}
			return true
	return false


## Uses one charge of `id`; empties the pocket at 0. False if the soldier has none.
static func use_consumable(record, id: String) -> bool:
	var ps := pockets(record)
	for i in ps.size():
		if ps[i] != null and ps[i].id == id:
			ps[i].charges -= 1
			if ps[i].charges <= 0:
				ps[i] = null
			return true
	return false


## Grows or shrinks the pocket array when Exo frame comes or goes. A pocket that disappears
## sells its contents at half price.
static func _fit_pockets(run, record) -> void:
	var ps := pockets(record)
	var n := pocket_count(record)
	while ps.size() < n:
		ps.append(null)
	while ps.size() > n:
		var last = ps.pop_back()
		if last != null and not add_consumable(record, last.id, last.charges):
			GearRun.add_supplies(run, GearData.price(last.id) / 2 * last.charges)
