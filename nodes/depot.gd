class_name Depot
extends RefCounted
## Supply depot: an 8-slot shop paid from shared Supplies (design doc, Economy and rewards).
## Stock: 2 gear, 1 alternate gun, 3 consumables, 1 Serum dose, a Machine graft from Act 2 (when a
## soldier can take one) and 1 service (recruit, Scar removal or Armorer).
## Anyone buys for their own soldiers; there is no vote. OWNER: nodes workstream.

const SERUM_PRICE := 50
const SERUM_SAMPLES := 2
const RECRUIT_PRICE := 45
const SCAR_PRICE := 40
const REROLL_PRICES: Array[int] = [20, 35]
const SELL_RATE := 0.4
const CONSUMABLE_SLOTS := 3
## Service roll weights; Scar removal only rolls when some soldier has a Scar.
const SERVICE_WEIGHTS := {"armorer": 5, "recruit": 3, "scar": 2}
## Quartermaster Doctrine.
const QUARTERMASTER_MULT := 0.85


static func enter(run) -> Dictionary:
	var ns := {"kind": "depot", "stock": [], "rerolls": 0, "left": [], "finished": true}
	run.node_state = ns
	_roll_goods(run, ns)
	ns.stock.append({"type": "serum", "id": "serum", "price": SERUM_PRICE, "sold": false})
	var refit := _roll_refit(run)
	if refit != "":
		ns.stock.append({"type": "graft", "id": refit, "price": GraftData.REFIT_PRICE, "sold": false})
	ns.stock.append({"type": "service", "id": _roll_service(run), "price": 0, "sold": false})
	RunAccess.emit(run, {"type": "depot_open", "stock": ns.stock.duplicate(true)})
	return ns


## Gear and consumable slots, replaced on a reroll. Gear 1 is Common or Uncommon and leans
## to the squad's tags; gear 2 is Uncommon, or Rare from act 2, and fully random.
static func _roll_goods(run, ns: Dictionary) -> void:
	var goods: Array = []
	var counts := {}
	for rec in RunAccess.active_soldiers(run):
		var c := GearTags.counts(rec)
		for t in c:
			counts[t] = counts.get(t, 0) + c[t]
	var r1 := "common" if run.rng.randf() < 0.6 else "uncommon"
	var g1 := GearDraw.draw_item(run.rng, counts, r1)
	goods.append({"type": "gear", "id": g1, "price": GearData.price(g1), "sold": false})
	var r2 := "rare" if run.act >= 2 and run.rng.randf() < 0.4 else "uncommon"
	var g2 := GearDraw.draw_item(run.rng, {}, r2, [g1])
	goods.append({"type": "gear", "id": g2, "price": GearData.price(g2), "sold": false})
	var gun := _roll_gun(run)
	if gun != "":
		goods.append({"type": "gun", "id": gun, "price": Weapons.price(gun), "sold": false})
	var ids: Array = GearData.CONSUMABLES.keys()
	ids.sort()
	for i in CONSUMABLE_SLOTS:
		var id: String = ids.pop_at(run.rng.randi_range(0, ids.size() - 1))
		goods.append({"type": "consumable", "id": id, "price": GearData.price(id), "sold": false})
	var kept: Array = ns.stock.filter(func(e): return e.type in ["serum", "graft", "service"])
	ns.stock = goods + kept


## An alternate gun for one of the squad's soldiers (Rare from act 2 sometimes). "" when
## every soldier already owns every gun their class can carry.
static func _roll_gun(run) -> String:
	var squad: Array = RunAccess.active_soldiers(run).filter(func(r): return not Loadout.gun_pool(r).is_empty())
	if squad.is_empty():
		return ""
	var rec = squad[run.rng.randi_range(0, squad.size() - 1)]
	var rarity := "rare" if run.act >= 2 and run.rng.randf() < 0.4 else "uncommon"
	return GearRun.gun_card(run.rng, rec, rarity).get("id", "")


## A Machine graft (Refit) for one of the squad's soldiers who can take one: from Act 2, Rank 3.
## "" when nobody can. Stays through rerolls, like Serum.
static func _roll_refit(run) -> String:
	var squad: Array = RunAccess.active_soldiers(run).filter(func(r): return Grafts.eligible(run, r))
	if squad.is_empty():
		return ""
	var rec = squad[run.rng.randi_range(0, squad.size() - 1)]
	return Grafts.machine_offer(run, rec, "depot%d" % int(run.fights_won))


static func _roll_service(run) -> String:
	var scars := RunAccess.active_soldiers(run).any(func(r): return not r.scars.is_empty())
	var ids: Array = SERVICE_WEIGHTS.keys().filter(func(k): return k != "scar" or scars)
	var total := 0
	for k in ids:
		total += SERVICE_WEIGHTS[k]
	var roll: int = run.rng.randi_range(0, total - 1)
	for k in ids:
		roll -= SERVICE_WEIGHTS[k]
		if roll < 0:
			return k
	return ids[-1]


static func _mult(run) -> float:
	return (QUARTERMASTER_MULT if RunAccess.has_doctrine(run, "quartermaster") else 1.0) * Severity.depot_mult(run)


## What a stock entry costs right now. The Armorer's price depends on the item upgraded, a
## Refit's on the soldier (Hazmat pays less).
static func price_of(run, entry: Dictionary, upgrade_item: String = "", rec = null) -> int:
	var base: int = entry.price
	if entry.type == "graft" and rec != null:
		base = Grafts.refit_price(rec)
	if entry.type == "service":
		match entry.id:
			"recruit": base = RECRUIT_PRICE
			"scar": base = SCAR_PRICE
			"armorer": base = GearData.upgrade_price(upgrade_item) if upgrade_item != "" else GearData.UPGRADE_PRICES.common
	return roundi(base * _mult(run))


static func reroll_price(run, ns: Dictionary) -> int:
	return roundi(REROLL_PRICES[mini(ns.rerolls, REROLL_PRICES.size() - 1)] * _mult(run))


static func sell_price(id: String) -> int:
	return roundi(GearData.price(id) * SELL_RATE)


static func _own(run, player: int, soldier_id: int):
	var rec = RunAccess.soldier(run, soldier_id)
	return rec if rec != null and rec.owner == player and rec.hp > 0 else null


static func validate(run, ns: Dictionary, action: Dictionary) -> String:
	var player: int = action.get("player", -1)
	match action.type:
		"node_buy":
			var i: int = action.get("index", -1)
			if i < 0 or i >= ns.stock.size():
				return "no such item"
			var entry: Dictionary = ns.stock[i]
			if entry.sold:
				return "sold out"
			var rec = _own(run, player, action.get("soldier", -1))
			var upgrade_item := ""
			match [entry.type, entry.id]:
				["gear", _]:
					if rec == null:
						return "pick one of your soldiers"
				["gun", _]:
					if rec == null:
						return "pick one of your soldiers"
					if not Weapons.can_carry(rec.kind, entry.id):
						return "%s can't use it" % UnitData.SOLDIERS.get(rec.kind, {}).get("name", rec.kind)
					if Loadout.owns_gun(rec, entry.id):
						return "already has one"
				["consumable", _]:
					if rec == null:
						return "pick one of your soldiers"
					if not Loadout.can_add_consumable(rec, entry.id):
						return "no free pocket"
				["graft", _]:
					if rec == null:
						return "pick one of your soldiers"
					var why := Grafts.can_take_error(run, rec, entry.id)
					if why != "":
						return why
				["service", "scar"]:
					if rec == null or rec.scars.is_empty():
						return "pick a soldier with a Scar"
				["service", "armorer"]:
					if rec == null:
						return "pick one of your soldiers"
					var g = Loadout.item_at(rec, action.get("slot", ""))
					if not g:
						return "nothing in that slot"
					if g.mk >= 2:
						return "already Mk II"
					upgrade_item = g.id
			if run.supplies < price_of(run, entry, upgrade_item, rec):
				return "Not enough Supplies"
			return ""
		"node_sell":
			if action.has("stash"):
				var i: int = action.stash
				return "" if i >= 0 and i < Loadout.stash(run).size() else "nothing there"
			var rec = _own(run, player, action.get("soldier", -1))
			if rec == null:
				return "pick one of your soldiers"
			if Loadout.item_at(rec, action.get("slot", "")) == null or action.get("slot", "") == "gun":
				return "nothing in that slot"
			return ""
		"node_reroll":
			if run.supplies < reroll_price(run, ns):
				return "Not enough Supplies"
			return ""
	return "unknown action"


static func apply(run, ns: Dictionary, action: Dictionary) -> void:
	var player: int = action.get("player", -1)
	match action.type:
		"node_buy":
			var entry: Dictionary = ns.stock[action.index]
			var rec = RunAccess.soldier(run, action.get("soldier", -1))
			var cost := price_of(run, entry, "", rec)
			match [entry.type, entry.id]:
				["gear", _]:
					Loadout.equip(run, rec, entry.id)
				["gun", _]:
					Loadout.take_gun(rec, entry.id, run)
				["consumable", _]:
					Loadout.add_consumable(rec, entry.id)
				["graft", _]:
					Grafts.take(rec, entry.id)
					RunAccess.emit(run, {"type": "soldier_graft", "sid": rec.id, "graft": entry.id})
				["serum", _]:
					RunAccess.add_serum(run, player, SERUM_SAMPLES)
				["service", "recruit"]:
					RunAccess.add_recruit(run, player)
				["service", "scar"]:
					rec.scars.remove_at(rec.scars.size() - 1)
				["service", "armorer"]:
					cost = price_of(run, entry, Loadout.item_at(rec, action.slot).id)
					Loadout.upgrade(rec, action.slot)
			entry.sold = true
			RunAccess.add_supplies(run, -cost)
			RunAccess.emit(run, {"type": "depot_bought", "player": player, "item": entry.id, "price": cost,
				"soldier": rec.id if rec != null else -1})
		"node_sell":
			if action.has("stash"):
				var spare: Dictionary = Loadout.stash(run).pop_at(action.stash)
				RunAccess.add_supplies(run, sell_price(spare.id))
				RunAccess.emit(run, {"type": "depot_sold", "player": player, "item": spare.id, "soldier": -1})
				return
			var rec = RunAccess.soldier(run, action.soldier)
			var id: String = Loadout.item_at(rec, action.slot).id
			Loadout.of(rec).slots[action.slot] = null
			RunAccess.add_supplies(run, sell_price(id))
			RunAccess.emit(run, {"type": "depot_sold", "player": player, "item": id, "soldier": rec.id})
		"node_reroll":
			var cost := reroll_price(run, ns)
			ns.rerolls += 1
			RunAccess.add_supplies(run, -cost)
			_roll_goods(run, ns)
			RunAccess.emit(run, {"type": "node_reroll", "player": player, "price": cost, "stock": ns.stock.duplicate(true)})
