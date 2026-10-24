extends VBoxContainer
## Left-hand squad roster: one card per soldier for the whole squad, owner shown by a
## colour stripe. Cards show HP pips, action diamonds, the Infection bar with tier
## marks and statuses. Clicking a card selects that soldier.

signal unit_clicked(id: int)

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const UnitView := preload("res://view/unit_view.gd")
const Tips := preload("res://ui/tips/tips.gd")

const WIDTH := 320.0

var _cards: VBoxContainer


func build() -> void:
	name = "SquadRoster"
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := Styles.hbox(6)
	head.add_child(Styles.caps("Squad", 13, Styles.DIM))
	head.add_child(Styles.spacer())
	head.add_child(W.keycap("Tab"))
	head.add_child(Styles.caps("cycle", 11, Styles.MUTED, false))
	add_child(head)
	_cards = Styles.vbox(6)
	add_child(_cards)


func refresh(view: MissionView, selected_id: int, can_act: bool) -> void:
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	var views: Array = view.unit_views.values().filter(func(uv: UnitView) -> bool: return uv.is_soldier)
	views.sort_custom(func(a: UnitView, b: UnitView) -> bool:
		return a.owner_player < b.owner_player or (a.owner_player == b.owner_player and a.unit_id < b.unit_id))
	for uv in views:
		_cards.add_child(_card(view, uv, uv.unit_id == selected_id, can_act))


static func owner_name(view: MissionView, p: int) -> String:
	var n: String = view.session.player_names.get(p, "")
	return n if n != "" else "Player %d" % (p + 1)


func _card(view: MissionView, uv: UnitView, selected: bool, can_act: bool) -> Control:
	var u := view.state.get_unit(uv.unit_id)
	var out_of_play := uv.dead or uv.turned or uv.lapsed
	var mine: bool = view.session.is_local(uv.owner_player)
	var pcol := Styles.player_color(uv.owner_player)
	var card := W.Frame.new(Vector4(14, 9, 12, 9))
	card.stripe = pcol
	if selected:
		card.set_look(Color(0.12, 0.11, 0.07, 0.94), Styles.AMBER, Styles.AMBER, false)
	elif uv.tier >= 2 and not uv.dead:
		card.set_look(Color(0.066, 0.082, 0.07, 0.92), Color(Styles.TEAL, 0.35), Styles.AMBER, false)
	else:
		card.set_look(Color(0.066, 0.082, 0.07, 0.9), Styles.BORDER_SOFT, Styles.AMBER, false)
	if out_of_play:
		card.modulate = Color(1, 1, 1, 0.55)
	elif not mine or (u != null and u.actions_left == 0):
		card.modulate = Color(1, 1, 1, 0.82)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_ARROW if out_of_play else Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(e: InputEvent) -> void:
		if not out_of_play and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			unit_clicked.emit(uv.unit_id))

	var row := Styles.hbox(12)
	card.add_child(row)
	row.add_child(W.glyph(uv.kind, pcol, 46.0, pcol if selected else Color("3a443a")))
	var col := Styles.vbox(5)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	var top := Styles.hbox(6)
	top.add_child(Styles.caps(uv.display_name, 17))
	top.add_child(Styles.spacer())
	var status := _status(view, uv, u)
	var corner: Control
	if status[0] != "":
		corner = Styles.caps(status[0], 12, status[1])
		top.add_child(corner)
	else:
		var d := W.Diamonds.new(8.0)
		d.set_values(2, u.actions_left if u != null else 0)
		corner = d
		top.add_child(d)
	col.add_child(top)

	var mid := Styles.hbox(6)
	var sub := UnitData.SOLDIERS.get(uv.kind, {}).get("name", uv.kind.capitalize()) as String
	if sub == uv.display_name:
		sub = "HP %d/%d" % [uv.hp, uv.max_hp]
	if not mine or not view.session is LocalSession:
		sub += " · " + owner_name(view, uv.owner_player)
	mid.add_child(Styles.label(sub, 13, Styles.DIM))
	mid.add_child(Styles.spacer())
	var hp := W.Pips.new(Vector2(11, 5))
	hp.set_values(uv.max_hp, uv.hp, 0, Styles.DANGER if uv.hp * 3 <= uv.max_hp else Styles.HP)
	mid.add_child(hp)
	col.add_child(mid)

	var inf := Styles.hbox(8)
	var bar := W.InfBar.new(5.0)
	bar.set_value(uv.infection)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inf.add_child(bar)
	var tl := Styles.mono("%d %s" % [uv.infection, Infection.tier_name(uv.tier).to_upper()], 10, Styles.TEAL if uv.tier >= 1 else Styles.TEAL_DIM)
	tl.custom_minimum_size = Vector2(84, 0)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inf.add_child(tl)
	col.add_child(inf)

	var flags := PackedStringArray()
	if uv.overwatch:
		flags.append("Overwatch")
	if uv.hunkered:
		flags.append("Hunkered")
	var flag_label: Label
	if not flags.is_empty() and not out_of_play:
		flag_label = Styles.label(" · ".join(flags), 12, Styles.AMBER)
		col.add_child(flag_label)
	for c in card.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Hover cards: the Infection bar, the corner word or action diamonds, and the flags.
	Tips.term(inf, "infection", {"value": uv.infection})
	if status[0] == "":
		Tips.term(corner, "actions")
	else:
		Tips.auto(corner, str(status[0]))
	if flag_label != null:
		Tips.terms(flag_label, Glossary.scan(flag_label.text))
	return card


## Right-hand corner word for the card: [text, colour], or "" to show action diamonds.
func _status(view: MissionView, uv: UnitView, u: Unit) -> Array:
	if uv.dead:
		return ["KIA", Styles.DANGER_TEXT]
	if uv.turned:
		return ["Turned", Styles.TEAL]
	if uv.lapsed:
		return ["Lapsed", Styles.TEAL]
	if view.player != null and view.player.enemy_phase:
		return ["Holding", Styles.MUTED]
	if view.state.ready.get(uv.owner_player, false):
		return ["Ready", Styles.HP]
	if u == null:
		return ["", Styles.TEXT]
	return ["", Styles.TEXT]
