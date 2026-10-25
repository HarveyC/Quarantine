extends "res://ui/nodes/node_screen.gd"
## Field hospital: one card per soldier with their HP pips, Infection bar, mutations and gear,
## and the treatments as icon tiles (cost on each tile, details on hover): the four basics,
## plus Refit and Amputate when grafts are open to that soldier. Hovering a
## treatment previews it on the card. Each player treats their own soldiers; one treatment each.

const Icons := preload("res://ui/icons.gd")
const SoldierCard := preload("res://ui/nodes/soldier_card.gd")
const GraftFigure := preload("res://ui/graft_figure.gd")
## The glossary card each treatment tile opens.
const TERMS := {"patch": "patch_up", "purge": "purge", "train": "train", "cure": "full_cure", "refit": "refit", "amputate": "amputate"}
const ICON_COLORS := {"patch": NodeUi.HEALTH, "purge": NodeUi.TEAL, "train": NodeUi.AMBER, "cure": NodeUi.TEAL,
	"refit": GraftFigure.STEEL, "amputate": GraftFigure.STEEL}


func _build(into: VBoxContainer) -> void:
	into.add_child(header("Field hospital · Act %d" % run.act, "One treatment each", NodeUi.HEALTH, wallet(), "hospital"))
	var rule := NodeUi.hbox(10)
	var paid: bool = ns().outbreak_paid
	rule.add_child(NodeUi.chip("outbreak", "+1", NodeUi.TEAL, 14))
	rule.add_child(NodeUi.label("Paid this visit" if paid else "The first heal or purge this visit", 14, NodeUi.DIM))
	rule.tooltip_text = "Healing or purging anyone raises Outbreak by 1, once per visit. Training doesn't."
	Tips.term(rule, "outbreak", {"value": run.outbreak})
	var top := NodeUi.hbox(10)
	top.add_child(rule)
	top.add_child(Styles.spacer())
	top.add_child(loadout_button())
	into.add_child(top)
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
	var sc := SoldierCard.new()
	sc.setup(run, session, rec)
	v.add_child(sc)
	var done: String = ns().treated.get(rec.id, "")
	if done != "":
		var d := NodeUi.hbox(10)
		d.add_child(W.Icon.new(done, ICON_COLORS[done], 26, 1.9))
		var treated := NodeUi.caption("Treated: " + FieldHospital.TREATMENTS[done].name, ICON_COLORS[done], 16)
		Tips.term(treated, TERMS[done])
		d.add_child(treated)
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
	for t in FieldHospital.options(ns(), rec):
		var info: Dictionary = FieldHospital.TREATMENTS[t]
		var action := {"type": "node_treat", "player": rec.owner, "soldier": rec.id, "treatment": t}
		var why := NodeRules.validate(run, action)
		var tip: String = "\n".join([_tip(rec, t), why].filter(func(s: String) -> bool: return s != ""))
		var b := NodeUi.tile_button(t, info.name, ICON_COLORS[t], NodeUi.cost_chip(FieldHospital.cost_text(rec, t)), why == "", tip)
		Tips.term(b, TERMS[t])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(submit.bind(action))
		_hook(b, sc, FieldHospital.preview_in(ns(), rec, t))
		tiles.add_child(b)
	v.add_child(tiles)
	return card


## The line over a tile's treatment card (which explains the treatment itself): Refit and
## Amputate name the part.
func _tip(rec: Dictionary, t: String) -> String:
	var id: String = FieldHospital.preview_in(ns(), rec, t).get("graft", "")
	if id == "":
		return ""
	var lead := "%s: %s" % [GraftData.SLOT_NAMES[GraftData.slot_of(id)], GraftData.name_of(id)]
	if t == "amputate":
		lead = "Cuts out the %s for a %s, costs %d HP" % [GraftData.name_of(Grafts.of(rec)[GraftData.slot_of(id)]), GraftData.name_of(id), GraftData.AMPUTATE_HP]
	return "%s. %s" % [lead, GraftData.get_def(id).desc]


## Hovering or focusing a treatment tile shows `delta` on the soldier's card.
func _hook(b: Control, card, delta: Dictionary) -> void:
	var on := func() -> void: card.show_delta(delta)
	var off := func() -> void: card.show_delta({})
	b.mouse_entered.connect(on)
	b.focus_entered.connect(on)
	b.mouse_exited.connect(off)
	b.focus_exited.connect(off)
