extends "res://ui/nodes/node_screen.gd"
## Supply depot: 7 stock cards bought from the squad's shared Supplies, each bought for one of
## your own soldiers, plus reroll and sell-back.

const SLOT_LABELS := {"weapon": "Weapon mod", "ammo": "Ammo", "armor": "Armor", "gadget": "Gadget"}


func _build(into: VBoxContainer) -> void:
	into.add_child(header("Supply depot · Act %d" % run.act, "Quartermaster's cage", NodeUi.AMBER, wallet()))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	for i in ns().stock.size():
		grid.add_child(_card(i))
	into.add_child(grid)
	into.add_child(_services())
	into.add_child(footer("Anyone can buy; every purchase comes out of the squad's Supplies.", true, "Leave depot"))


func _card(i: int) -> Control:
	var e: Dictionary = ns().stock[i]
	var card := NodeUi.panel()
	card.custom_minimum_size = Vector2(300, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.marks = not e.sold
	var v := NodeUi.vbox(8)
	card.add_child(v)
	var info := _info(e)
	var top := NodeUi.hbox()
	var slot := NodeUi.caption(info.slot)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(slot)
	top.add_child(NodeUi.caption(info.rarity, info.rarity_color))
	v.add_child(top)
	v.add_child(NodeUi.label(info.name.to_upper(), 24, NodeUi.TEAL if e.type == "serum" else NodeUi.TEXT))
	if info.tag != "":
		v.add_child(NodeUi.caption(info.tag, GearData.tag_color(info.tag)))
	v.add_child(NodeUi.label(info.desc, 14, NodeUi.DIM, true))
	if e.sold:
		v.add_child(NodeUi.caption("Sold", NodeUi.FAINT, 15))
		return card
	var price := Depot.price_of(run, e)
	if not (e.type == "service" and e.id == "armorer"):
		v.add_child(NodeUi.label("%d Supplies" % price, 20, NodeUi.AMBER))
	var buys := HFlowContainer.new()
	buys.add_theme_constant_override("h_separation", 8)
	buys.add_theme_constant_override("v_separation", 8)
	for a in _buy_actions(i):
		var b := NodeUi.button(a.text, a.ok, false, a.reason)
		b.pressed.connect(submit.bind(a.action))
		buys.add_child(b)
	v.add_child(buys)
	return card


func _info(e: Dictionary) -> Dictionary:
	match e.type:
		"gear":
			var it := GearData.get_item(e.id)
			return {"slot": SLOT_LABELS.get(it.slot, it.slot), "name": it.name, "desc": it.desc, "tag": it.tag,
				"rarity": GearData.RARITY_NAMES[it.rarity], "rarity_color": GearData.RARITY_COLORS[it.rarity]}
		"consumable":
			var c: Dictionary = GearData.CONSUMABLES[e.id]
			return {"slot": "Pocket", "name": c.name, "desc": c.desc, "tag": "", "rarity": "Consumable", "rarity_color": NodeUi.DIM}
		"serum":
			return {"slot": "Serum", "name": "Serum dose", "desc": "Two samples for your own stock: a dose purges 25 Infection in a fight, two doses fully cure at a Field hospital. Once per depot.",
				"tag": "", "rarity": "Serum", "rarity_color": NodeUi.TEAL}
	var svc := {
		"recruit": {"name": "Recruit", "desc": "A fresh soldier for your reserve."},
		"scar": {"name": "Scar removal", "desc": "Remove one Scar from one of your soldiers."},
		"armorer": {"name": "Armorer", "desc": "Upgrade one equipped item to Mk II: 30 for Common or Uncommon, 50 for Rare."},
	}
	return {"slot": "Service", "name": svc[e.id].name, "desc": svc[e.id].desc, "tag": "", "rarity": "Service", "rarity_color": NodeUi.DIM}


## Every buy button for stock entry `i`: one per own soldier (or per item, for the Armorer),
## one per local player for Serum and recruits. Each carries the rules' verdict.
func _buy_actions(i: int) -> Array:
	var e: Dictionary = ns().stock[i]
	var out: Array = []
	var many := local_players().size() > 1
	for p in local_players():
		var base := {"type": "node_buy", "player": p, "index": i}
		match [e.type, e.id]:
			["serum", _], ["service", "recruit"]:
				out.append(_entry("Buy" if not many else "Buy · %s" % NodeUi.player_name(session, p), base))
			["service", "armorer"]:
				for rec in run.soldiers_of(p):
					for it in Loadout.equipped(rec):
						if it.mk >= 2:
							continue
						var a := base.duplicate()
						a.soldier = rec.id
						a.slot = it.slot
						out.append(_entry("%s · %s (%d)" % [GearData.item_name(it.id), rec.name, GearData.upgrade_price(it.id)], a))
			_:
				for rec in run.soldiers_of(p):
					var a := base.duplicate()
					a.soldier = rec.id
					out.append(_entry("For %s" % rec.name, a))
	return out


func _entry(text: String, action: Dictionary) -> Dictionary:
	var why := NodeRules.validate(run, action)
	return {"text": text, "action": action, "ok": why == "", "reason": why}


func _services() -> Control:
	var row := NodeUi.hbox(18)
	var reroll := NodeUi.panel()
	var rv := NodeUi.vbox(8)
	reroll.add_child(rv)
	rv.add_child(NodeUi.caption("Reroll the shelf"))
	rv.add_child(NodeUi.label("New gear and consumables. Serum and the service stay.", 14, NodeUi.DIM, true))
	var price := Depot.reroll_price(run, ns())
	for p in local_players().slice(0, 1):
		var a := _entry("Reroll · %d" % price, {"type": "node_reroll", "player": p})
		var b := NodeUi.button(a.text, a.ok, false, a.reason)
		b.pressed.connect(submit.bind(a.action))
		rv.add_child(b)
	reroll.custom_minimum_size.x = 320
	row.add_child(reroll)
	var sell := NodeUi.panel()
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sv := NodeUi.vbox(8)
	sell.add_child(sv)
	sv.add_child(NodeUi.caption("Sell back (40% of the price)"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for p in local_players():
		for rec in run.soldiers_of(p):
			for it in Loadout.equipped(rec):
				var a := _entry("%s · %s +%d" % [GearData.item_name(it.id), rec.name, Depot.sell_price(it.id)],
					{"type": "node_sell", "player": p, "soldier": rec.id, "slot": it.slot})
				var b := NodeUi.button(a.text, a.ok, false, a.reason)
				b.pressed.connect(submit.bind(a.action))
				flow.add_child(b)
	if flow.get_child_count() == 0:
		sv.add_child(NodeUi.label("Nothing equipped to sell.", 14, NodeUi.FAINT))
	sv.add_child(flow)
	row.add_child(sell)
	return row
