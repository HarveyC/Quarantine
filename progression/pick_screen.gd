extends PanelContainer
## Rank-up perk picks and mutation offers, hosted inside the reward screen (Progression.pick_screen()).
## One section per local player, one row per soldier with something waiting, so a solo player picks
## for all four. Sends prog_* run actions through session.submit_run. Amber = something to click,
## teal = Infection, a player-colour stripe marks whose soldier it is.

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const Feel := preload("res://ui/ui_feel.gd")

var run: RunState
var session
var _list: VBoxContainer
## sid -> partner sid picked for a Bonded card
var _partner := {}


func setup(p_run: RunState, p_session) -> void:
	run = p_run
	session = p_session
	theme = Styles.make_theme()
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 18)
	scroll.add_child(_list)
	if run.has_signal("event"):
		run.event.connect(func(_ev): rebuild())
	rebuild()


func _players() -> Array:
	if session != null and session.has_method("local_players"):
		return session.local_players()
	return run.players


func rebuild() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var any := false
	for p in _players():
		for r in run.soldiers_of(p):
			if Progression.pending_picks(r) > 0 or not r.prog.get("offers", []).is_empty():
				any = true
				_list.add_child(_soldier_row(p, r))
	if not any:
		_list.add_child(Styles.caps("No rank-ups waiting", 18, Styles.MUTED))
	if is_inside_tree():
		Feel.deal(_list.get_children(), 0.06)


## A soldier on the left, their three cards to the right (and Skip for a mutation offer).
func _soldier_row(p: int, r: Dictionary) -> Control:
	var pcol := Styles.player_color(p)
	var row := Styles.hbox(14)
	var who := W.Frame.new(Vector4(18, 14, 16, 14))
	who.stripe = pcol
	who.set_look(Color(0.043, 0.065, 0.103, 0.92), Styles.BORDER_SOFT, Styles.AMBER, false)
	who.custom_minimum_size = Vector2(250, 0)
	var info := Styles.vbox(8)
	who.add_child(info)
	var head := Styles.hbox(10)
	head.add_child(W.glyph(r.kind, pcol, 44.0))
	var names := Styles.vbox(0)
	names.add_child(Styles.caps(str(r.get("name", "")), 22))
	names.add_child(Styles.label(UnitData.SOLDIERS.get(r.kind, {}).get("name", r.kind), 13, Styles.DIM))
	head.add_child(names)
	info.add_child(head)
	var inf := int(r.get("infection", 0))
	var ir := Styles.hbox(8)
	ir.add_child(W.Icon.new("infection", Styles.TEAL, 15, 1.7))
	var bar := W.InfBar.new(6.0)
	bar.set_value(inf)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ir.add_child(bar)
	ir.add_child(Styles.mono("%d %s" % [inf, Infection.tier_name(Infection.tier(inf)).to_upper()], 10, Styles.TEAL))
	info.add_child(ir)
	var what := Styles.hbox(8)
	var picks := Progression.pending_picks(r)
	if picks > 0:
		what.add_child(W.Icon.new("rank", Styles.AMBER, 18, 1.8))
		what.add_child(Styles.caps("Rank %d · pick a perk" % int(r.prog.get("rank", 1)), 14, Styles.AMBER))
		if picks > 1:
			what.add_child(W.chip("%d waiting" % picks, Styles.AMBER, false, 11))
	else:
		what.add_child(W.Icon.new("mutation", Styles.TEAL, 18, 1.8))
		what.add_child(Styles.caps("Graft a mutation", 14, Styles.TEAL))
	info.add_child(what)
	row.add_child(who)
	if picks > 0:
		for id in Progression.perk_offer(run, r):
			var perk: Dictionary = PerkData.PERKS[id]
			var chips: Array = []
			if perk.tag != "":
				chips.append(GearUiTag.new(perk.tag))
			if perk.rare:
				chips.append(W.chip("Rare", Styles.AMBER, true, 11))
			row.add_child(_card("perk", perk.name, Styles.AMBER, chips, perk.desc,
				func(): _submit({"type": "prog_perk_pick", "player": p, "sid": r.id, "perk": id})))
	else:
		var offer: Dictionary = r.prog.offers[0]
		for id in offer.cards:
			var c := Progression.mutation_card_for(id)
			var chips: Array = [GearUiTag.new(c.tag), _cost(c.graft), W.chip("%s tier" % Infection.tier_name(c.tier), Styles.TEAL_DIM, false, 11)]
			var card := _card("mutation", c.name, Styles.TEAL, chips, c.desc, func(): _graft(p, r, id))
			if c.bonded:
				card.get_child(0).add_child(_partner_picker(r))
			row.add_child(card)
		var skip := Styles.icon_button("Skip", "close", "ghost", 15, 44)
		skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		skip.pressed.connect(func(): _submit({"type": "prog_skip_offer", "player": p, "sid": r.id}))
		row.add_child(skip)
	return row


## "+15" next to the Infection icon: what grafting costs.
func _cost(n: int) -> Control:
	var h := Styles.hbox(4)
	h.add_child(W.Icon.new("infection", Styles.TEAL, 14, 1.6))
	h.add_child(Styles.mono("+%d" % n, 12, Styles.TEAL))
	return h


## A pick card: kind icon and name, chips (tag, cost, tier), then the effect in a line or two.
func _card(icon: String, title: String, col: Color, chips: Array, desc: String, on_pick: Callable) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(250, 150)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	Styles.style_button(b, "secondary")
	Styles.round_button(b, 22)
	var box := Styles.vbox(8)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	b.add_child(box)
	var head := Styles.hbox(10)
	var ic := W.Icon.new(icon, col, 24, 1.8)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(ic)
	var name := Styles.keep_words(Styles.caps(title, 20))
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.custom_minimum_size.x = 60
	head.add_child(name)
	box.add_child(head)
	var cr := HFlowContainer.new()
	cr.add_theme_constant_override("h_separation", 6)
	cr.add_theme_constant_override("v_separation", 6)
	for c in chips:
		if c is Control:
			cr.add_child(c)
	box.add_child(cr)
	var d := Styles.label(desc, 14, Styles.DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(d)
	# The card is a Button (for its hover look), which doesn't size to what it holds: grow it
	# to fit the text, so big text sizes push the card taller instead of spilling out.
	box.minimum_size_changed.connect(func() -> void:
		b.custom_minimum_size = Vector2(250, maxf(150.0, box.get_combined_minimum_size().y + 28.0)))
	b.pressed.connect(func():
		Feel.sound("pick")
		on_pick.call())
	return b


## A tag chip in the tag's own colour (Mark, Guard...).
class GearUiTag extends PanelContainer:
	const Styles := preload("res://ui/styles.gd")

	func _init(tag: String) -> void:
		var c := GearData.tag_color(tag) if tag != "" else Styles.DIM
		var sb := Styles.panel_box(Color(c, 0.1), Color(c, 0.7), Styles.PILL)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		add_theme_stylebox_override("panel", sb)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(Styles.caps(tag if tag != "" else "No tag", 12, c))


## Bonded mutations pick a partner soldier of another player.
func _partner_picker(r: Dictionary) -> Control:
	var opt := OptionButton.new()
	opt.mouse_filter = Control.MOUSE_FILTER_STOP
	var sids: Array = []
	for o in run.squad():
		if o.get("owner", -1) != r.get("owner", -1):
			sids.append(o.id)
			opt.add_item("Bond with %s" % o.get("name", "?"))
	if sids.is_empty():
		opt.add_item("Needs another player's soldier")
		opt.disabled = true
	else:
		_partner[r.id] = sids[0]
		opt.item_selected.connect(func(i): _partner[r.id] = sids[i])
	return opt


func _graft(p: int, r: Dictionary, id: String) -> void:
	var act := {"type": "prog_graft", "player": p, "sid": r.id, "mutation": id}
	if MutationData.get_def(id).get("bonded", false):
		act["partner"] = _partner.get(r.id, -1)
	_submit(act)


func _submit(action: Dictionary) -> void:
	if session != null and session.has_method("submit_run"):
		session.submit_run(action)
	else:
		RunRules.apply(run, action)
	rebuild()
