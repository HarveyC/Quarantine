extends "res://ui/nodes/node_screen.gd"
## Field hospital: one card per soldier with their HP, Infection and mutations, and the four
## treatments. Each player treats their own soldiers; one treatment each.

const ICON_COLORS := {"patch": NodeUi.HEALTH, "purge": NodeUi.TEAL, "train": NodeUi.AMBER, "cure": NodeUi.TEAL}


func _build(into: VBoxContainer) -> void:
	into.add_child(header("Field hospital · Act %d" % run.act, "One treatment each", NodeUi.HEALTH, wallet()))
	into.add_child(NodeUi.label("Every soldier gets one treatment, chosen by their player. Healing or purging anyone raises Outbreak by 1 (once per visit); training doesn't.", 15, NodeUi.DIM, true))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	for rec in RunAccess.active_soldiers(run):
		grid.add_child(_card(rec))
	into.add_child(grid)
	var paid: bool = ns().outbreak_paid
	into.add_child(footer("Outbreak +1 paid this visit" if paid else "", true, "Leave hospital"))


func _card(rec: Dictionary) -> Control:
	var card := NodeUi.panel(NodeUi.player_color(rec.owner))
	card.custom_minimum_size = Vector2(320, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := NodeUi.vbox(10)
	card.add_child(v)
	v.add_child(NodeUi.label(NodeUi.soldier_title(rec).to_upper(), 22))
	var sub := "Rank %s · %s" % [str(rec.get("prog", {}).get("rank", 1)), NodeUi.player_name(session, rec.owner)]
	if rec.injuries > 0:
		sub += " · %d injur%s" % [rec.injuries, "y" if rec.injuries == 1 else "ies"]
	v.add_child(NodeUi.label(sub, 13, NodeUi.DIM))
	v.add_child(NodeUi.meter("Health", rec.hp, rec.max_hp, NodeUi.HEALTH))
	v.add_child(NodeUi.meter("Infection", rec.infection, 100, NodeUi.TEAL, NodeUi.infection_text(rec.infection), true))
	var muts := RunAccess.mutations_of(rec)
	var mtext := "No mutations" if muts.is_empty() else ", ".join(muts.map(func(m): return RunAccess.mutation_name(m)))
	v.add_child(NodeUi.label(mtext, 13, NodeUi.FAINT if muts.is_empty() else NodeUi.TEAL, true))
	var done: String = ns().treated.get(rec.id, "")
	if done != "":
		v.add_child(NodeUi.caption("Treated: " + FieldHospital.TREATMENTS[done].name, ICON_COLORS[done], 15))
		return card
	if not rec.owner in local_players():
		v.add_child(NodeUi.label("%s is deciding" % NodeUi.player_name(session, rec.owner), 14, NodeUi.player_color(rec.owner)))
		return card
	for t in FieldHospital.ORDER:
		var info: Dictionary = FieldHospital.TREATMENTS[t]
		var action := {"type": "node_treat", "player": rec.owner, "soldier": rec.id, "treatment": t}
		var why := NodeRules.validate(run, action)
		var b := NodeUi.button("%s  ·  %s  ·  %s" % [info.name, info.desc, info.cost], why == "", false, why)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(submit.bind(action))
		v.add_child(b)
	return card
