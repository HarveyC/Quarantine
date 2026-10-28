extends "res://ui/nodes/node_screen.gd"
## Supply depot: 7 stock cards bought from the squad's shared Supplies, each bought for one of
## your own soldiers, plus reroll and sell-back.

const Icons := preload("res://ui/icons.gd")
const GraftFigure := preload("res://ui/graft_figure.gd")
const SLOT_LABELS := GearData.SLOT_NAMES


func _build(into: VBoxContainer) -> void:
	into.add_child(header("Supply depot · Act %d" % run.act, "Quartermaster's cage", NodeUi.SUPPLY, wallet(), "depot"))
	var main := NodeUi.vbox(22)
	into.add_child(with_squad(main))
	# Wraps to the width left beside the squad panel.
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	for i in ns().stock.size():
		grid.add_child(_card(i))
	main.add_child(grid)
	main.add_child(_services())
	var note := footer("", true, "Leave depot")
	note.tooltip_text = "Anyone can buy; every purchase comes out of the squad's Supplies."
	into.add_child(note)


func _card(i: int) -> Control:
	var e: Dictionary = ns().stock[i]
	var card := NodeUi.panel()
	card.custom_minimum_size = Vector2(280, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.marks = not e.sold
	var v := NodeUi.vbox(10)
	card.add_child(v)
	var info := _info(e)
	var top := NodeUi.hbox(10)
	var ic := W.Icon.new(info.icon, info.rarity_color if not e.sold else NodeUi.FAINT, 28, 1.9)
	top.add_child(ic)
	var names := NodeUi.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(NodeUi.caption(info.slot, NodeUi.FAINT, 12))
	names.add_child(NodeUi.title(info.name, 22, NodeUi.TEAL if e.type == "serum" else NodeUi.TEXT))
	top.add_child(names)
	if not e.sold and not (e.type == "service" and e.id == "armorer"):
		var price := NodeUi.chip("supplies", str(Depot.price_of(run, e)), NodeUi.SUPPLY, 17, "%d Supplies" % Depot.price_of(run, e))
		price.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top.add_child(price)
	v.add_child(top)
	var tags := NodeUi.hbox(8)
	if info.tag != "":
		tags.add_child(NodeUi.chip("", info.tag.to_upper(), GearData.tag_color(info.tag), 13))
	if info.rarity != "" and info.rarity != info.slot:
		tags.add_child(NodeUi.caption(info.rarity, info.rarity_color, 12))
	if tags.get_child_count() > 0:
		v.add_child(tags)
	v.add_child(NodeUi.effect_row(info.desc, 14))
	if e.sold:
		var s := NodeUi.hbox(8)
		s.add_child(W.Icon.new("check", NodeUi.FAINT, 16, 1.8))
		s.add_child(NodeUi.caption("Sold", NodeUi.FAINT, 15))
		v.add_child(s)
		card.modulate = Color(1, 1, 1, 0.55)
		return card
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grow)
	var buys := HFlowContainer.new()
	buys.add_theme_constant_override("h_separation", 8)
	buys.add_theme_constant_override("v_separation", 8)
	for a in _buy_actions(i):
		var b := NodeUi.button(a.text, a.ok, false, a.reason, a.get("icon", "buy"))
		b.pressed.connect(submit.bind(a.action))
		_hook(b, "%s · %s" % [info.name, a.text], a.action)
		_compare(b, e, a)
		buys.add_child(b)
	v.add_child(buys)
	return card


func _info(e: Dictionary) -> Dictionary:
	match e.type:
		"gear":
			var it := GearData.get_item(e.id)
			return {"slot": SLOT_LABELS.get(it.slot, it.slot), "name": it.name, "desc": it.desc, "tag": it.tag, "icon": it.slot,
				"rarity": GearData.RARITY_NAMES[it.rarity], "rarity_color": GearData.RARITY_COLORS[it.rarity]}
		"gun":
			var g := Weapons.get_gun(e.id)
			var who: Array = g.classes.map(func(k): return UnitData.SOLDIERS.get(k, {}).get("name", str(k).capitalize()))
			return {"slot": "Gun · " + ", ".join(who), "name": g.name, "desc": g.desc, "tag": g.tag, "icon": "weapon",
				"rarity": GearData.RARITY_NAMES[g.rarity], "rarity_color": GearData.RARITY_COLORS[g.rarity]}
		"consumable":
			var c: Dictionary = GearData.CONSUMABLES[e.id]
			return {"slot": "Pocket", "name": c.name, "desc": c.desc, "tag": "", "rarity": "", "rarity_color": NodeUi.DIM, "icon": "consumable"}
		"serum":
			return {"slot": "Serum", "name": "Serum dose", "desc": "+2 Serum samples. Once per depot.",
				"tag": "", "rarity": "", "rarity_color": NodeUi.TEAL, "icon": "serum"}
		"graft":
			var d := GraftData.get_def(e.id)
			return {"slot": "Refit · " + GraftData.SLOT_NAMES[d.slot], "name": d.name, "desc": d.desc + " Beds in: -1 move next fight.",
				"tag": d.tag, "rarity": "Machine", "rarity_color": GraftFigure.STEEL, "icon": "refit"}
	var svc := {
		"recruit": {"name": "Recruit", "desc": "A fresh soldier for your reserve.", "icon": "recruit"},
		"scar": {"name": "Scar removal", "desc": "Remove one Scar from one of your soldiers.", "icon": "patch"},
		"armorer": {"name": "Armorer", "desc": "Upgrade an equipped item to Mk II.", "icon": "rank"},
	}
	return {"slot": "Service", "name": svc[e.id].name, "desc": svc[e.id].desc, "tag": "", "rarity": "", "rarity_color": NodeUi.AMBER,
		"icon": svc[e.id].icon}


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
						out.append(_entry("%s · %s  %d" % [GearData.item_name(it.id), rec.name, GearData.upgrade_price(it.id)], a, "rank"))
			_:
				for rec in run.soldiers_of(p):
					var a := base.duplicate()
					a.soldier = rec.id
					var text := "For %s" % rec.name
					if e.type == "graft" and Depot.price_of(run, e, "", rec) != Depot.price_of(run, e):
						text += "  %d" % Depot.price_of(run, e, "", rec)   # Hazmat refits for less
					out.append(_entry(text, a, Icons.for_class(rec.kind)))
	return out


## Hovering a buy or sell button shows the item landing on (or leaving) that soldier.
func _hook(b: Control, what: String, action: Dictionary) -> void:
	if squad_panel == null or not action.has("soldier"):
		return
	squad_panel.hook(b, what, func() -> Dictionary:
		var rec = RunAccess.soldier(run, action.soldier)
		if rec == null:
			return {}
		var d := {}
		if action.type == "node_sell":
			d = {"gear": {"slot": action.slot, "mode": "remove"}}
		else:
			var e: Dictionary = ns().stock[action.index]
			match e.type:
				"gear":
					d = {"gear": Loadout.preview_equip(rec, e.id).merged({"id": e.id})}
				"gun":
					d = {"gun": 1}
				"consumable":
					d = {"pocket": GearData.CONSUMABLES[e.id].name}
				"graft":
					d = {"graft": e.id}
				"service":
					if e.id == "armorer":
						d = {"gear": {"slot": action.slot, "mode": "upgrade"}}
					else:
						d = {"scar": -1}
		return {rec.id: d})


## Hovering a "For <soldier>" buy shows the item against what that soldier has on.
func _compare(b: Control, e: Dictionary, a: Dictionary) -> void:
	var armorer: bool = e.type == "service" and e.id == "armorer"
	if not a.action.has("soldier") or not (e.type in ["gear", "gun", "consumable", "graft"] or armorer):
		return
	var rec = RunAccess.soldier(run, a.action.soldier)
	if rec == null:
		return
	var card := {"kind": e.type, "id": e.id, "charges": 1}
	if armorer:
		# The Armorer merges the item into Mk II: the same compare as a duplicate drop.
		var it = Loadout.item_at(rec, str(a.action.get("slot", "")))
		if it == null:
			return
		card = {"kind": "gear", "id": it.id}
	Tips.compare(b, func() -> Dictionary: return GearCompare.compare(run, rec, card), NodeUi.player_color(rec.owner), a.reason)


func _entry(text: String, action: Dictionary, icon := "buy") -> Dictionary:
	var why := NodeRules.validate(run, action)
	return {"text": text, "action": action, "ok": why == "", "reason": why, "icon": icon}


func _services() -> Control:
	var row := NodeUi.hbox(18)
	var reroll := NodeUi.panel()
	var rv := NodeUi.vbox(10)
	reroll.add_child(rv)
	var rh := NodeUi.hbox(10)
	rh.add_child(W.Icon.new("reroll", NodeUi.AMBER, 24, 1.9))
	rh.add_child(NodeUi.title("Reroll", 20))
	rv.add_child(rh)
	reroll.tooltip_text = "New gear and consumables. Serum and the service stay."
	var price := Depot.reroll_price(run, ns())
	for p in local_players().slice(0, 1):
		var a := _entry("Reroll  %d" % price, {"type": "node_reroll", "player": p}, "supplies")
		var b := NodeUi.button(a.text, a.ok, false, a.reason, "supplies")
		b.pressed.connect(submit.bind(a.action))
		rv.add_child(b)
	reroll.custom_minimum_size.x = 300
	row.add_child(reroll)
	var sell := NodeUi.panel()
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sv := NodeUi.vbox(10)
	sell.add_child(sv)
	var sh := NodeUi.hbox(10)
	sh.add_child(W.Icon.new("sell", NodeUi.SUPPLY, 24, 1.9))
	sh.add_child(NodeUi.title("Sell back", 20))
	sh.add_child(NodeUi.chip("", "40%", NodeUi.DIM, 13, "Sells for 40% of the price"))
	sv.add_child(sh)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for p in local_players():
		for rec in run.soldiers_of(p):
			for it in Loadout.equipped(rec):
				var a := _entry("%s · %s  +%d" % [GearData.item_name(it.id), rec.name, Depot.sell_price(it.id)],
					{"type": "node_sell", "player": p, "soldier": rec.id, "slot": it.slot}, it.slot)
				var b := NodeUi.button(a.text, a.ok, false, a.reason, it.slot)
				b.pressed.connect(submit.bind(a.action))
				_hook(b, "Sell " + GearData.item_name(it.id), a.action)
				flow.add_child(b)
	if flow.get_child_count() == 0:
		sv.add_child(NodeUi.label("Nothing equipped to sell", 14, NodeUi.FAINT))
	sv.add_child(flow)
	row.add_child(sell)
	return row
