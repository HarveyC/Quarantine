extends "res://ui/nodes/node_screen.gd"
## Supply depot: 7 stock cards bought from the squad's shared Supplies, each bought for one of
## your own soldiers, plus reroll and sell-back.

const Icons := preload("res://ui/icons.gd")
const GraftFigure := preload("res://ui/graft_figure.gd")
const SLOT_LABELS := GearData.SLOT_NAMES


## The shelf tile picked for the detail panel, and which tab (buy or sell) is showing.
var _sel := 0
var _tab := "buy"


func _build(into: VBoxContainer) -> void:
	into.add_child(header("Supply depot · Act %d" % run.act, "Quartermaster's cage", NodeUi.SUPPLY, wallet(), "depot"))
	var main := NodeUi.vbox(18)
	# The squad panel has to exist before the buy buttons hook their previews to it.
	into.add_child(with_squad(main))
	# Margin keeps the active tab's glow inside the scroll box.
	var tabs := MarginContainer.new()
	tabs.add_theme_constant_override("margin_left", 14)
	tabs.add_theme_constant_override("margin_top", 10)
	tabs.add_child(_tabs())
	main.add_child(tabs)
	if _tab == "sell":
		main.add_child(_sell_list())
	else:
		var row := NodeUi.hbox(20)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_sel = clampi(_sel, 0, ns().stock.size() - 1)
		for i in ns().stock.size():
			grid.add_child(_tile(i))
		row.add_child(grid)
		row.add_child(_detail(_sel))
		main.add_child(row)
	var note := footer("", true, "Leave depot")
	note.tooltip_text = "Anyone can buy; every purchase comes out of the squad's Supplies."
	into.add_child(note)


func _tabs() -> Control:
	var row := NodeUi.hbox(12)
	for t in [["buy", "Buy", "buy"], ["sell", "Sell back", "sell"]]:
		var b := NodeUi.button(t[1], true, _tab == t[0], "", t[2])
		b.pressed.connect(_set_tab.bind(t[0]))
		row.add_child(b)
	row.add_child(Styles.spacer())
	var price := Depot.reroll_price(run, ns())
	for p in local_players().slice(0, 1):
		var a := _entry("Reroll  %d" % price, {"type": "node_reroll", "player": p}, "reroll")
		var b := NodeUi.button(a.text, a.ok, false, a.reason if not a.ok else "New gear and consumables. Serum and the service stay.", "reroll")
		b.pressed.connect(submit.bind(a.action))
		row.add_child(b)
	return row


func _set_tab(t: String) -> void:
	_tab = t
	rebuild()


func _select(i: int) -> void:
	_sel = i
	rebuild()


## One shelf tile: icon, name, kind and price. Click to see it in the detail panel.
func _tile(i: int) -> Control:
	var e: Dictionary = ns().stock[i]
	var info := _info(e)
	var card := NodeUi.panel()
	card.custom_minimum_size = Vector2(250, 84)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.marks = not e.sold
	if i == _sel:
		card.add_theme_stylebox_override("panel", NodeUi.box(NodeUi.PANEL, NodeUi.AMBER, 16))
	var h := NodeUi.hbox(12)
	card.add_child(h)
	var ic := W.Icon.new(info.icon, info.rarity_color if not e.sold else NodeUi.FAINT, 30, 1.9)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var names := NodeUi.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.add_child(NodeUi.title(info.name, 17, NodeUi.TEAL if e.type == "serum" else NodeUi.TEXT))
	names.add_child(NodeUi.caption(info.slot if info.rarity == "" or info.rarity == info.slot else "%s · %s" % [info.slot, info.rarity], NodeUi.FAINT, 12))
	h.add_child(names)
	if e.sold:
		h.add_child(W.Icon.new("check", NodeUi.FAINT, 18, 1.8))
		card.modulate = Color(1, 1, 1, 0.55)
	elif not (e.type == "service" and e.id == "armorer"):
		var price := NodeUi.chip("supplies", str(Depot.price_of(run, e)), NodeUi.SUPPLY, 17, "%d Supplies" % Depot.price_of(run, e))
		price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(price)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_select(i))
	return card


## The picked item: rules text and one buy button per soldier (or per item, for the Armorer).
func _detail(i: int) -> Control:
	var e: Dictionary = ns().stock[i]
	var info := _info(e)
	var card := NodeUi.panel(Color(0, 0, 0, 0), 22)
	card.custom_minimum_size = Vector2(380, 0)
	var v := NodeUi.vbox(14)
	card.add_child(v)
	var top := NodeUi.hbox(14)
	top.add_child(W.Icon.new(info.icon, info.rarity_color if not e.sold else NodeUi.FAINT, 44, 1.9))
	var names := NodeUi.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(NodeUi.caption(info.slot if info.rarity == "" or info.rarity == info.slot else "%s · %s" % [info.slot, info.rarity], NodeUi.FAINT, 13))
	names.add_child(NodeUi.title(info.name, 30, NodeUi.TEAL if e.type == "serum" else NodeUi.TEXT))
	top.add_child(names)
	v.add_child(top)
	if info.tag != "":
		var tags := NodeUi.hbox(8)
		tags.add_child(NodeUi.chip("", info.tag.to_upper(), GearData.tag_color(info.tag), 13))
		v.add_child(tags)
	v.add_child(NodeUi.effect_row(info.desc, 16))
	if e.sold:
		var s := NodeUi.hbox(8)
		s.add_child(W.Icon.new("check", NodeUi.FAINT, 16, 1.8))
		s.add_child(NodeUi.caption("Sold", NodeUi.FAINT, 15))
		v.add_child(s)
		return card
	v.add_child(NodeUi.caption("Buy for", NodeUi.FAINT, 13))
	for a in _buy_actions(i):
		var b := NodeUi.button(a.text, a.ok, false, a.reason, a.get("icon", "buy"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(submit.bind(a.action))
		_hook(b, "%s · %s" % [info.name, a.text], a.action)
		_compare(b, e, a)
		v.add_child(b)
	return card


## Everything that can be sold: each soldier's equipped items, then spares in the squad stash.
## Every row says which it is.
func _sell_list() -> Control:
	var panel := NodeUi.panel(Color(0, 0, 0, 0), 20)
	var v := NodeUi.vbox(12)
	panel.add_child(v)
	var head := NodeUi.hbox(10)
	head.add_child(W.Icon.new("sell", NodeUi.SUPPLY, 24, 1.9))
	head.add_child(NodeUi.title("Sell back", 20))
	head.add_child(NodeUi.chip("", "40%", NodeUi.DIM, 13, "Sells for 40% of the price"))
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 8)
	var p0 = local_players()[0] if not local_players().is_empty() else -1
	for p in local_players():
		for rec in run.soldiers_of(p):
			for it in Loadout.equipped(rec):
				if it.slot == "gun":
					continue
				var act := {"type": "node_sell", "player": p, "soldier": rec.id, "slot": it.slot}
				var b := _sell_row(it.id, it.slot, "Equipped · " + rec.name, NodeUi.AMBER, act)
				_hook(b.get_meta("btn"), "Sell " + GearData.item_name(it.id), act)
				grid.add_child(b)
	var stash := Loadout.stash(run)
	for i in stash.size():
		grid.add_child(_sell_row(stash[i].id, GearData.get_item(stash[i].id).slot, "Spare · Stash", NodeUi.FAINT,
			{"type": "node_sell", "player": p0, "stash": i}))
	if grid.get_child_count() == 0:
		v.add_child(NodeUi.label("Nothing to sell", 14, NodeUi.FAINT))
	v.add_child(grid)
	return panel


func _sell_row(id: String, slot: String, state: String, state_color: Color, action: Dictionary) -> Control:
	var h := NodeUi.hbox(12)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ic := W.Icon.new(slot, state_color, 26, 1.8)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var names := NodeUi.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.add_child(NodeUi.label(GearData.item_name(id), 17))
	names.add_child(NodeUi.caption(state, state_color, 12))
	h.add_child(names)
	var a := _entry("Sell  +%d" % Depot.sell_price(id), action, "sell")
	var b := NodeUi.button(a.text, a.ok, false, a.reason, "sell")
	b.pressed.connect(submit.bind(a.action))
	h.add_child(b)
	h.set_meta("btn", b)
	return h


func _info(e: Dictionary) -> Dictionary:
	match e.type:
		"gear":
			var it := GearData.get_item(e.id)
			return {"slot": SLOT_LABELS.get(it.slot, it.slot), "name": it.name, "desc": it.desc, "tag": it.tag, "icon": it.slot,
				"rarity": GearData.RARITY_NAMES[it.rarity], "rarity_color": GearData.RARITY_COLORS[it.rarity]}
		"gun":
			var g := Weapons.get_gun(e.id)
			return {"slot": "Gun", "name": g.name, "desc": g.desc, "tag": g.tag, "icon": "weapon",
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
						if it.mk >= 2 or it.slot == "gun":
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
