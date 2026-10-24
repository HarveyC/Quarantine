extends PanelContainer
## Rank-up perk picks and mutation offers, hosted inside the reward screen (Progression.pick_screen()).
## One section per local player, one row per soldier with something waiting, so a solo player picks
## for all four. Sends prog_* run actions through session.submit_run. Amber = something to click,
## teal = Infection, a player-colour stripe marks whose soldier it is.

const Styles := preload("res://ui/styles.gd")
const Palette := preload("res://view/palette.gd")

const PANEL := Color(0.05, 0.06, 0.055, 0.82)
const CARD := Color(0.09, 0.1, 0.09, 0.9)
const CARD_HOVER := Color(0.16, 0.14, 0.09, 0.95)

var run: RunState
var session
var _list: VBoxContainer
## sid -> partner sid picked for a Bonded card
var _partner := {}


func setup(p_run: RunState, p_session) -> void:
	run = p_run
	session = p_session
	add_theme_stylebox_override("panel", Styles.panel_box(PANEL, Color(0.2, 0.22, 0.2, 0.6), 2))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
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
		var rows: Array = []
		for r in run.soldiers_of(p):
			if Progression.pending_picks(r) > 0 or not r.prog.get("offers", []).is_empty():
				rows.append(r)
		if rows.is_empty():
			continue
		any = true
		_list.add_child(Styles.label("Player %d" % (p + 1), 16, Palette.player_ui(p)))
		for r in rows:
			_list.add_child(_soldier_row(p, r))
	if not any:
		_list.add_child(Styles.label("No rank-ups waiting.", 15, Styles.MUTED))


func _soldier_row(p: int, r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var stripe := ColorRect.new()
	stripe.color = Palette.player_ui(p)
	stripe.custom_minimum_size = Vector2(4, 0)
	row.add_child(stripe)
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(170, 0)
	info.add_child(Styles.label("%s %s" % [UnitData.SOLDIERS.get(r.kind, {}).get("name", r.kind), r.get("name", "")], 16))
	info.add_child(Styles.label("Rank %d" % int(r.prog.get("rank", 1)), 14, Styles.MUTED))
	var inf := int(r.get("infection", 0))
	info.add_child(Styles.label("Infection %d (%s)" % [inf, Infection.tier_name(Infection.tier(inf))], 13, Palette.TEAL))
	row.add_child(info)
	if Progression.pending_picks(r) > 0:
		var picks := Progression.pending_picks(r)
		info.add_child(Styles.label("Pick a perk%s" % (" (%d waiting)" % picks if picks > 1 else ""), 13, Palette.AMBER))
		for id in Progression.perk_offer(run, r):
			var perk: Dictionary = PerkData.PERKS[id]
			var tag: String = perk.tag if perk.tag != "" else "No tag"
			var title := "%s%s" % [perk.name, "  (rare)" if perk.rare else ""]
			row.add_child(_card(title, tag, perk.desc, Styles.MUTED,
				func(): _submit({"type": "prog_perk_pick", "player": p, "sid": r.id, "perk": id})))
	else:
		var offer: Dictionary = r.prog.offers[0]
		info.add_child(Styles.label("Graft a mutation", 13, Palette.AMBER))
		for id in offer.cards:
			var c := Progression.mutation_card_for(id)
			var sub := "%s  ·  %s tier  ·  +%d Infection" % [c.tag, Infection.tier_name(c.tier), c.graft]
			var card := _card(c.name, sub, c.desc, Palette.TEAL, func(): _graft(p, r, id))
			if c.bonded:
				card.get_child(0).add_child(_partner_picker(r))
			row.add_child(card)
		var skip := Button.new()
		skip.text = "Skip"
		skip.pressed.connect(func(): _submit({"type": "prog_skip_offer", "player": p, "sid": r.id}))
		row.add_child(skip)
	return row


func _card(title: String, sub: String, desc: String, sub_color: Color, on_pick: Callable) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(210, 120)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", Styles.panel_box(CARD, Palette.AMBER.darkened(0.35), 2))
	b.add_theme_stylebox_override("hover", Styles.panel_box(CARD_HOVER, Palette.AMBER, 2))
	b.add_theme_stylebox_override("pressed", Styles.panel_box(CARD_HOVER, Palette.AMBER.lightened(0.2), 2))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	box.add_child(Styles.label(title, 15, Palette.AMBER))
	box.add_child(Styles.label(sub, 12, sub_color))
	var d := Styles.label(desc, 12, Styles.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(190, 0)
	box.add_child(d)
	b.pressed.connect(on_pick)
	return b


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
