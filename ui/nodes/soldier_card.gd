extends VBoxContainer
## One soldier's state at a glance, for the node screens: portrait with the Infection ring,
## name, class and rank, HP pips, the Infection bar and tier, mutations (dormant ones dimmed)
## and key gear, plus the graft body diagram once grafts are open. `show_delta` overlays what a hovered choice would do (EventRules.preview /
## FieldHospital.preview shape): ghost pips and arcs, "30 > 45" with the tier it lands in,
## incoming or purged mutations and gear. No frame; SquadPanel and the hospital wrap it.

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const Tips := preload("res://ui/tips/tips.gd")
const GraftFigure := preload("res://ui/graft_figure.gd")

var run: RunState
var session
var rec: Dictionary
var compact := false
var delta := {}


func setup(r: RunState, s, soldier: Dictionary, is_compact := false) -> void:
	run = r
	session = s
	rec = soldier
	compact = is_compact
	add_theme_constant_override("separation", 6 if compact else 12)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()


func show_delta(d: Dictionary) -> void:
	if d == delta:
		return
	delta = d
	_build()


func _build() -> void:
	NodeUi.clear(self)
	var pcol := NodeUi.player_color(rec.owner)
	var inf: int = rec.infection
	var inf_to: int = delta.get("infection", inf)
	var hp_to: int = delta.get("hp", rec.hp)
	# Who: portrait, name, class (and owner in co-op), rank.
	var head := NodeUi.hbox(12)
	var face := W.Portrait.new(46.0 if compact else 56.0)
	face.setup(rec.kind, pcol, inf, false, rec.get("sit_out", 0) > 0)
	face.preview = inf_to if inf_to != inf else -1
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Tips.soldier_class(face, rec.kind)
	head.add_child(face)
	var names := NodeUi.vbox(1)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.add_child(NodeUi.title(rec.name, 17 if compact else 24))
	var sub: String = UnitData.SOLDIERS.get(rec.kind, {}).get("name", str(rec.kind).capitalize())
	if run.present_players().size() > 1:
		sub += " · " + NodeUi.player_name(session, rec.owner)
	names.add_child(NodeUi.label(sub, 13, NodeUi.DIM))
	head.add_child(names)
	var grafts := Grafts.of(rec)
	var incoming: String = delta.get("graft", "")
	if not grafts.is_empty() or incoming != "" or Grafts.eligible(run, rec):
		var fig := GraftFigure.new(Vector2(30, 46) if compact else Vector2(36, 54))
		fig.setup(grafts, incoming)
		Tips.term(fig, "graft")
		fig.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(fig)
	var rank := NodeUi.chip("rank", str(rec.get("prog", {}).get("rank", 1)), NodeUi.DIM, 13)
	rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Tips.term(rank, "rank")
	head.add_child(rank)
	add_child(head)
	add_child(_hp_row(hp_to))
	add_child(_infection_row(inf, inf_to))
	# The full card sits above the buttons that preview on it (hospital), so it keeps its
	# height: no tier banner (the Infection line names the tier) and a fixed extras line.
	var cross := _tier_callout(inf, inf_to) if compact else null
	if cross != null:
		add_child(cross)
	var muts := _mutation_row(inf_to)
	var gear := _gear_row()
	if compact:
		# One wrapping line of chips: mutations first, then kit.
		if RunAccess.mutations_of(rec).is_empty() and delta.get("mutation", 0) == 0:
			muts.get_child(0).queue_free()
			muts.remove_child(muts.get_child(0))
		for c in gear.get_children():
			gear.remove_child(c)
			muts.add_child(c)
		gear.queue_free()
		add_child(muts)
	else:
		add_child(muts)
		add_child(gear)
	var extra := _extras()
	if not compact:
		extra.custom_minimum_size.y = 24
		add_child(extra)
	elif extra.get_child_count() > 0:
		add_child(extra)


func _hp_row(hp_to: int) -> Control:
	var row := NodeUi.hbox(8)
	row.add_child(W.Icon.new("health", NodeUi.HEALTH, 15, 1.7))
	var pips := W.HpPips.new(Vector2(12, 6) if compact else Vector2(14, 7), 3.0)
	var low: bool = mini(rec.hp, hp_to) * 3 <= rec.max_hp
	pips.set_values(rec.max_hp, rec.hp, maxi(0, rec.hp - hp_to), Styles.DANGER if low else Styles.HP, maxi(0, hp_to - rec.hp))
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pips)
	row.add_child(Styles.spacer())
	if hp_to != rec.hp:
		row.add_child(_change("%d/%d" % [rec.hp, rec.max_hp], "%d" % hp_to, NodeUi.HEALTH if hp_to > rec.hp else NodeUi.BAD))
	else:
		row.add_child(Styles.mono("%d/%d" % [rec.hp, rec.max_hp], 12, NodeUi.TEXT))
	Tips.term(row, "healing")
	return row


func _infection_row(inf: int, inf_to: int) -> Control:
	var row := NodeUi.hbox(8)
	row.add_child(W.Icon.new("infection", NodeUi.TEAL, 15, 1.7))
	var bar := W.InfBar.new(6.0 if compact else 7.0)
	bar.set_value(inf, inf_to if inf_to != inf else -1)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var tier_to := Infection.tier(inf_to)
	var tname := Infection.tier_name(tier_to).to_upper()
	if inf_to != inf:
		row.add_child(_change(str(inf), "%d %s" % [inf_to, tname], Infection.tier_color(tier_to) if inf_to > inf else NodeUi.TEAL))
	else:
		row.add_child(Styles.mono("%d %s" % [inf, tname], 12, NodeUi.TEAL if tier_to >= 1 else Styles.TEAL_DIM))
	Tips.term(row, "infection", {"value": inf_to})
	return row


## "12 > 18": the old value faint, an arrow, the new one bright.
func _change(from: String, to: String, col: Color) -> Control:
	var h := NodeUi.hbox(4)
	h.add_child(Styles.mono(from, 12, NodeUi.FAINT))
	var arrow := W.Icon.new("arrow_right", col, 12, 1.8)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(arrow)
	h.add_child(Styles.mono(to, 12, col))
	return h


## A banner when the preview moves the soldier into another Infection tier.
func _tier_callout(inf: int, inf_to: int) -> Control:
	var t0 := Infection.tier(inf)
	var t1 := Infection.tier(inf_to)
	if t0 == t1:
		return null
	var up := t1 > t0
	var col := Infection.tier_color(t1) if up else NodeUi.HEALTH
	var text := ("Into %s" if up else "Back to %s") % Infection.tier_name(t1)
	if up and t1 >= Infection.Tier.MUTATING:
		text += " · %d%% Lapse" % roundi(Infection.LAPSE_CHANCE.get(t1, 0.0) * 100)
	var c := NodeUi.chip("infection" if up else "purge", text.to_upper(), col, 13)
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	Tips.term(c, "lapse" if up and t1 >= Infection.Tier.MUTATING else "infection", {"value": inf_to})
	return c


func _mutation_row(inf_to: int) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var muts := RunAccess.mutations_of(rec)
	var lose: int = delta.get("lose_mutation", 0)
	var tier_now := Infection.tier(rec.infection)
	var tier_to := Infection.tier(inf_to)
	for i in muts.size():
		var id: String = muts[i]
		var mname := RunAccess.mutation_name(id).to_upper()
		var need := MutationData.awake_at(id)
		var awake := tier_to >= need
		var desc: String = MutationData.get_def(id).get("desc", "")
		var tip := desc if awake else "Dormant until %s. %s" % [Infection.tier_name(need), desc]
		var chip: Control
		if i >= muts.size() - lose:
			chip = NodeUi.chip("close", mname, NodeUi.FAINT, 12, "Removed. " + desc)
		elif awake and tier_now < need:
			chip = NodeUi.chip("mutation", mname + " WAKES", NodeUi.TEAL, 12, tip)
		else:
			chip = NodeUi.chip("mutation", mname, NodeUi.TEAL if awake else NodeUi.FAINT, 12, tip)
		Tips.term(chip, "mutation", {"value": inf_to})
		flow.add_child(chip)
	var gain: int = delta.get("mutation", 0)
	if gain > 0:
		var t := "+1 RANDOM MUTATION" if gain == 1 else "+%d RANDOM MUTATIONS" % gain
		var g := NodeUi.chip("plus", t, Infection.tier_color(Infection.Tier.MUTATING), 12, "Drawn at random from the mutation pool")
		Tips.term(g, "mutation")
		flow.add_child(g)
	if flow.get_child_count() == 0:
		var none := NodeUi.label("No mutations", 12, NodeUi.FAINT)
		Tips.term(none, "mutation")
		flow.add_child(none)
	return flow


## The gun they carry and an icon per equipped item, rarity coloured, named on hover.
func _gear_row() -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var gun := Loadout.gun_id(rec)
	var g := Weapons.get_gun(gun)
	var gun_col: Color = GearData.RARITY_COLORS.get(g.get("rarity", "common"), NodeUi.DIM) if Loadout.gun(rec) != "" else NodeUi.DIM
	flow.add_child(NodeUi.chip("weapon", Weapons.gun_name(gun).to_upper(), gun_col, 12, g.get("desc", "")))
	var preview: Dictionary = delta.get("gear", {})
	for it in Loadout.equipped(rec):
		if it.slot == "gun":
			continue
		var col: Color = GearData.RARITY_COLORS.get(GearData.rarity_of(it.id), NodeUi.DIM)
		var tip := "%s%s\n%s" % [GearData.item_name(it.id), " Mk II" if it.mk >= 2 else "", GearData.desc(it.id, it.mk)]
		var gone: bool = preview.get("slot", "") == it.slot and preview.get("mode", "") in ["replace", "remove"]
		var label := "II" if it.mk >= 2 else ""
		if preview.get("slot", "") == it.slot and preview.get("mode", "") == "upgrade":
			label = "> II"
			col = NodeUi.TEXT
		flow.add_child(_gear_chip(it.slot, label, NodeUi.FAINT if gone else col, tip))
	if preview.get("mode", "") in ["equip", "replace"]:
		var id: String = preview.id
		var col: Color = GearData.RARITY_COLORS.get(GearData.rarity_of(id), NodeUi.TEXT)
		flow.add_child(NodeUi.chip("plus", GearData.item_name(id).to_upper(), col, 12, GearData.desc(id)))
	if delta.has("pocket"):
		flow.add_child(NodeUi.chip("plus", str(delta.pocket).to_upper(), NodeUi.TEXT, 12, "Goes in a pocket"))
	var items: int = delta.get("items", 0)
	if items > 0:
		flow.add_child(NodeUi.chip("plus", "%d ITEM%s" % [items, "S" if items > 1 else ""], NodeUi.TEXT, 12, "Random gear, equipped straight away"))
	var guns: int = delta.get("gun", 0)
	if guns > 0:
		flow.add_child(NodeUi.chip("plus", "NEW GUN", NodeUi.TEXT, 12, "An alternate gun for their class"))
	return flow


func _gear_chip(slot: String, text: String, col: Color, tip: String) -> Control:
	var p := PanelContainer.new()
	var sb := Styles.panel_box(Color(col, 0.08), Color(col, 0.4), Styles.PILL)
	sb.content_margin_left = 7
	sb.content_margin_right = 7 if text == "" else 9
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := Styles.hbox(4)
	var ic := W.Icon.new(slot, col, 15, 1.7)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	if text != "":
		row.add_child(Styles.mono(text, 11, col))
	p.add_child(row)
	return p


## Injuries, benched fights, perk picks and anything else the preview adds.
func _extras() -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var inj: int = rec.get("injuries", 0)
	var inj_to: int = delta.get("injuries", inj)
	if inj > 0 or inj_to > 0:
		var t := str(inj) if inj_to == inj else "%d > %d" % [inj, inj_to]
		flow.add_child(Tips.term(NodeUi.chip("wound", "INJURIES " + t, NodeUi.BAD, 12, "Patch up closes one."), "injury"))
	var scars: int = rec.get("scars", []).size()
	var scars_to: int = maxi(0, scars + delta.get("scar", 0))
	if scars > 0:
		var t := str(scars) if scars_to == scars else "%d > %d" % [scars, scars_to]
		flow.add_child(Tips.term(NodeUi.chip("wound", "SCARS " + t, NodeUi.DIM, 12, "Lasting wounds from going down. Full cure leaves them."), "scar"))
	var sit: int = rec.get("sit_out", 0) + delta.get("sit_out", 0)
	if sit > 0:
		var c := NodeUi.chip("waiting", "SITS OUT %d" % sit, NodeUi.BAD, 12, "Misses the next %d fight%s" % [sit, "s" if sit > 1 else ""])
		flow.add_child(c)
	var perk: int = delta.get("perk", 0)
	if perk > 0:
		flow.add_child(Tips.term(NodeUi.chip("perk", "+%d PERK PICK" % perk, NodeUi.TEXT, 12, "Pick one of three perks for their class"), "perk"))
	if delta.get("leaves", false):
		flow.add_child(NodeUi.chip("close", "LEAVES THE SQUAD", NodeUi.BAD, 12, "A fresh recruit takes their place in the reserve"))
	if delta.get("maybe", false):
		flow.add_child(NodeUi.chip("unknown", "ONLY IF THE ROLL HITS", NodeUi.DIM, 12, "Part of this effect is a chance"))
	return flow
