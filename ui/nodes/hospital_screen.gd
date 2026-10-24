extends "res://ui/nodes/node_screen.gd"
## Field hospital: one card per soldier with their HP pips, Infection bar and mutations, and the
## four treatments as icon tiles (cost on each tile, details on hover). Each player treats their
## own soldiers; one treatment each.

const Icons := preload("res://ui/icons.gd")
const ICON_COLORS := {"patch": NodeUi.HEALTH, "purge": NodeUi.TEAL, "train": NodeUi.AMBER, "cure": NodeUi.TEAL}


func _build(into: VBoxContainer) -> void:
	into.add_child(header("Field hospital · Act %d" % run.act, "One treatment each", NodeUi.HEALTH, wallet(), "hospital"))
	var rule := NodeUi.hbox(10)
	var paid: bool = ns().outbreak_paid
	rule.add_child(NodeUi.chip("outbreak", "+1", NodeUi.TEAL, 14))
	rule.add_child(NodeUi.label("Paid this visit" if paid else "The first heal or purge this visit", 14, NodeUi.DIM))
	rule.tooltip_text = "Healing or purging anyone raises Outbreak by 1, once per visit. Training doesn't."
	rule.mouse_filter = Control.MOUSE_FILTER_PASS
	into.add_child(rule)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	for rec in RunAccess.active_soldiers(run):
		grid.add_child(_card(rec))
	into.add_child(grid)
	into.add_child(footer("", true, "Leave hospital"))


func _card(rec: Dictionary) -> Control:
	var pcol := NodeUi.player_color(rec.owner)
	var card := NodeUi.panel(pcol)
	card.custom_minimum_size = Vector2(340, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := NodeUi.vbox(12)
	card.add_child(v)
	var head := NodeUi.hbox(12)
	head.add_child(W.glyph(rec.kind, pcol, 48.0))
	var names := NodeUi.vbox(2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(NodeUi.title(rec.name, 24))
	var sub := "%s · %s" % [UnitData.SOLDIERS.get(rec.kind, {}).get("name", rec.kind), NodeUi.player_name(session, rec.owner)]
	names.add_child(NodeUi.label(sub, 13, NodeUi.DIM))
	head.add_child(names)
	var rank := NodeUi.chip("rank", str(rec.get("prog", {}).get("rank", 1)), NodeUi.DIM, 13, "Rank")
	rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(rank)
	v.add_child(head)
	# Health as pips, Infection as the tiered bar.
	var hp := NodeUi.hbox(8)
	hp.add_child(W.Icon.new("health", NodeUi.HEALTH, 16, 1.7))
	var pips := W.Pips.new(Vector2(14, 7))
	pips.set_values(rec.max_hp, rec.hp, 0, Styles.DANGER if rec.hp * 3 <= rec.max_hp else Styles.HP)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp.add_child(pips)
	hp.add_child(Styles.spacer())
	hp.add_child(Styles.mono("%d/%d" % [rec.hp, rec.max_hp], 12, NodeUi.TEXT))
	if rec.injuries > 0:
		hp.add_child(NodeUi.chip("wound", str(rec.injuries), NodeUi.BAD, 12, "Injuries"))
	v.add_child(hp)
	var inf := NodeUi.hbox(8)
	inf.add_child(W.Icon.new("infection", NodeUi.TEAL, 16, 1.7))
	var bar := W.InfBar.new(7.0)
	bar.set_value(rec.infection)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inf.add_child(bar)
	inf.add_child(Styles.mono(NodeUi.infection_text(rec.infection).to_upper(), 11, NodeUi.TEAL))
	v.add_child(inf)
	var muts := RunAccess.mutations_of(rec)
	if not muts.is_empty():
		var mrow := HFlowContainer.new()
		mrow.add_theme_constant_override("h_separation", 6)
		mrow.add_theme_constant_override("v_separation", 6)
		for m in muts:
			mrow.add_child(NodeUi.chip("mutation", RunAccess.mutation_name(m).to_upper(), NodeUi.TEAL, 12))
		v.add_child(mrow)
	var done: String = ns().treated.get(rec.id, "")
	if done != "":
		var d := NodeUi.hbox(10)
		d.add_child(W.Icon.new(done, ICON_COLORS[done], 26, 1.9))
		d.add_child(NodeUi.caption("Treated: " + FieldHospital.TREATMENTS[done].name, ICON_COLORS[done], 16))
		d.add_child(Styles.spacer())
		d.add_child(W.Icon.new("check", NodeUi.HEALTH, 20, 2.0))
		v.add_child(d)
		return card
	if not rec.owner in local_players():
		var w := NodeUi.hbox(8)
		w.add_child(W.Icon.new("waiting", pcol, 18, 1.8))
		w.add_child(NodeUi.caption("%s is deciding" % NodeUi.player_name(session, rec.owner), pcol, 14))
		v.add_child(w)
		return card
	var tiles := GridContainer.new()
	tiles.columns = 2
	tiles.add_theme_constant_override("h_separation", 8)
	tiles.add_theme_constant_override("v_separation", 8)
	for t in FieldHospital.ORDER:
		var info: Dictionary = FieldHospital.TREATMENTS[t]
		var action := {"type": "node_treat", "player": rec.owner, "soldier": rec.id, "treatment": t}
		var why := NodeRules.validate(run, action)
		var tip: String = info.desc + ("\n" + why if why != "" else "")
		var b := NodeUi.tile_button(t, info.name, ICON_COLORS[t], NodeUi.cost_chip(info.cost), why == "", tip)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(submit.bind(action))
		tiles.add_child(b)
	v.add_child(tiles)
	return card
