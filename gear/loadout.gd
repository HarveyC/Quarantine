class_name Loadout
extends RefCounted
## A soldier's equipment, kept on their run record as `record.gear` (plain data, so it
## serializes for saves and network sync):
##   {"slots": {"weapon": {"id", "mk"} | null, "ammo": .., "armor": .., "gadget": ..},
##    "pockets": [{"id", "charges"} | null, ...]}
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
	return record.gear


static func item_at(record, slot: String):
	return of(record).slots.get(slot)


## Every equipped item as {"slot", "id", "mk"}, in slot order.
static func equipped(record) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var g := of(record)
	for slot in GearData.SLOTS:
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


## Tag counts from gear alone ({"Mark": 2, ...}). Prototypes count for both tags.
static func gear_tags(record) -> Dictionary:
	var out := {}
	for e in equipped(record):
		for t in GearData.tags_of(e.id):
			out[t] = out.get(t, 0) + 1
	return out


## How picking `id` would land: "upgrade" (duplicate -> Mk II), "equip" (empty slot),
## "replace" (old item goes to the stash), or "stash" (duplicate already at Mk II).
static func preview_equip(record, id: String) -> Dictionary:
	var slot := GearData.slot_of(id)
	var cur = item_at(record, slot)
	if cur == null:
		return {"mode": "equip", "slot": slot}
	if cur.id == id:
		return {"mode": "upgrade" if cur.mk < 2 else "stash", "slot": slot}
	return {"mode": "replace", "slot": slot, "old": cur.duplicate()}


## Equips `id` on the soldier. A duplicate upgrades to Mk II; a different item in the slot
## is moved to the stash (or scrapped for Supplies if the stash is full). Returns
## {"mode", "slot", "displaced": {id, mk} or null, "scrapped": bool}.
static func equip(run, record, id: String, mk: int = 1) -> Dictionary:
	assert(GearData.exists(id), "unknown item %s" % id)
	if GearData.PROTOTYPES.has(id):
		mk = 2
	var p := preview_equip(record, id)
	var g := of(record)
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
	return res


## Moves the item in `slot` to the stash. False if the slot is empty or the stash is full.
static func unequip(run, record, slot: String) -> bool:
	var it = item_at(record, slot)
	if it == null or stash_full(run):
		return false
	stash_add(run, it.id, it.mk)
	of(record).slots[slot] = null
	_fit_pockets(run, record)
	return true


## Armorer / reward upgrade of the item in `slot` to Mk II. False if empty or already Mk II.
static func upgrade(record, slot: String) -> bool:
	var it = item_at(record, slot)
	if it == null or it.mk >= 2:
		return false
	it.mk = 2
	return true


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
