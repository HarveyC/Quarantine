extends VBoxContainer
## Left-hand squad roster: one entry per soldier for the whole squad, straight on the scene over
## a soft haze (no card box), owner shown by a colour stripe and the portrait's inner ring.
## Entries show the portrait with its teal Infection ring, HP pips, lantern action orbs and
## statuses; soldiers with nothing left to do this turn fade back. Clicking one selects it.

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
	_cards = Styles.vbox(2)
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
	var card := W.Frame.new(Vector4(10, 7, 18, 7))
	card.stripe = pcol
	card.radius = 40
	# No box: the selected soldier gets a warm lantern haze, the rest a plain dark one.
	if selected:
		card.set_haze(0.13, Styles.AMBER)
	else:
		card.set_haze(0.4)
	if out_of_play:
		card.modulate = Color(1, 1, 1, 0.45)
	elif not selected and (not mine or (u != null and u.actions_left == 0)):
		card.modulate = Color(1, 1, 1, 0.6)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_ARROW if out_of_play else Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(e: InputEvent) -> void:
		if not out_of_play and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			unit_clicked.emit(uv.unit_id))

	var row := Styles.hbox(12)
	card.add_child(row)
	var face := W.Portrait.new(62.0)
	face.setup(uv.kind, pcol, uv.infection, selected, out_of_play)
	row.add_child(face)
	var col := Styles.vbox(5)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	var top := Styles.hbox(6)
	var name_l := Styles.bold(uv.display_name, 16, Styles.AMBER_LIGHT if selected else Styles.TEXT)
	top.add_child(name_l)
	top.add_child(Styles.spacer())
	var status := _status(view, uv, u)
	var corner: Control
	var losses: Array = Rules.action_losses(view.state, u) if u != null and not out_of_play else []
	var why := "\n".join(PackedStringArray(losses.map(func(l: Dictionary) -> String: return str(l.text))))
	if not losses.is_empty() and int(losses[0].lost) >= Types.ACTIONS_PER_TURN:
		# Out of the turn through no choice of theirs: say why in the corner, not "Ready".
		corner = Styles.hbox(4)
		corner.add_child(W.Icon.new(str(losses[0].icon), Styles.DANGER_TEXT, 14, 1.8))
		corner.add_child(Styles.caps(str(losses[0].title), 12, Styles.DANGER_TEXT))
		top.add_child(corner)
	elif status[0] != "":
		corner = Styles.caps(status[0], 12, status[1])
		top.add_child(corner)
	else:
		var d := W.Diamonds.new(8.0)
		d.set_values(2, u.actions_left if u != null else 0)
		corner = d
		top.add_child(d)
	col.add_child(top)

	# The name already says the class and the portrait shows it, so the line under it is just
	# HP, Infection and (online, or someone else's soldier) the owner.
	var mid := Styles.hbox(10)
	var hp := W.HpPips.new(Vector2(11, 5), 3.0)
	hp.set_values(uv.max_hp, uv.hp, 0, Styles.DANGER if uv.hp * 3 <= uv.max_hp else Styles.HP)
	hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(hp)
	# Infection is the teal ring round the portrait; the words say how far gone.
	var inf := Styles.hbox(4)
	var inf_col := Styles.TEAL if uv.tier >= 1 else Styles.TEAL_DIM
	inf.add_child(W.Icon.new("infection", inf_col, 13, 1.6))
	inf.add_child(Styles.mono(str(uv.infection), 12, inf_col))
	if uv.tier >= 1:
		inf.add_child(Styles.label(Infection.tier_name(uv.tier), 12, inf_col))
	mid.add_child(inf)
	col.add_child(mid)
	var sub := ""
	var kind_name := UnitData.SOLDIERS.get(uv.kind, {}).get("name", uv.kind.capitalize()) as String
	if not uv.display_name.contains(kind_name):
		sub = kind_name
	if not mine or not view.session is LocalSession:
		sub += (" · " if sub != "" else "") + owner_name(view, uv.owner_player)
	if sub != "":
		col.add_child(Styles.label(sub, 12, Styles.DIM))

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
	if why != "":
		# The card's whole corner explains the lost actions: the cause, then the term card.
		corner.tooltip_text = why
		if str(losses[0].key) != "":
			Tips.term(corner, str(losses[0].key))
		corner.mouse_filter = Control.MOUSE_FILTER_PASS
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
