extends Control
## Reward screen (REWARD phase): the run-start deployment orders, then after each won fight one
## 1-of-3 pick per soldier each local player controls (solo picks for all four), the Doctrine
## vote after an act boss, and rank-up picks from Progression once the gear picks are done.
## Beside the cards, the compare column: what the soldier has on now, and while a card is
## hovered (or picked) that card against what it replaces, stat and tag deltas included.
## L opens the soldier's full loadout over the screen; the pick waits underneath.
## Sends gear_pick / gear_doctrine through session.submit_run. Keys: 1-4 pick a card, Enter
## take, S skip (not for orders), Tab next soldier, L loadout.

const UI := preload("res://ui/gear/gear_ui.gd")
const GearCard := preload("res://ui/gear/gear_card.gd")
const W := preload("res://ui/widgets.gd")
const Tips := preload("res://ui/tips/tips.gd")
const Feel := preload("res://ui/ui_feel.gd")
const CompareView := preload("res://ui/gear/compare_view.gd")
const LoadoutScreen := preload("res://ui/gear/loadout_screen.gd")
## Width of the compare column beside the cards.
const COMPARE_W := 420
## Text in the column runs a step larger than in a hover card, to sit with the cards' text.
const BOOST := 2

## Eyebrow over the title for each reward source (GearRun.reward_source).
const HEADERS := {"kit": "Act %d · Deployment", "skirmish": "Act %d · Fight won",
	"nest": "Act %d · Nest cleared", "boss": "Act %d · Boss down"}

var run: RunState
var session
var _sid := -1
var _card := -1
var _to_stash := false
var _took := {}          # sid -> what this screen saw them take
var _dirty := false

var _title: Label
var _sub: Label
var _tabs: HBoxContainer
var _center: HBoxContainer
var _hint: Label
var _skip: Button
var _stash: Button
var _take: Button
var _squad: VBoxContainer
var _cards: Array = []
var _prog_box: Control
var _backdrop: Control
var _fit: Container
var _loadout_btn: Button
var _compare: VBoxContainer   # the compare column's content (null when no offer is shown)
var _compare_for := -2        # card index the column shows (-1 = the soldier's kit)
var _hovered := -1
var _overlay: Control         # loadout opened from here


func setup(r: RunState, s) -> void:
	run = r
	session = s
	_build()
	run.event.connect(func(_ev) -> void: _queue_refresh())
	_refresh()


func _local_players() -> Array:
	return session.local_players() if session != null and session.has_method("local_players") else run.players


func _queue_refresh() -> void:
	if not _dirty:
		_dirty = true
		call_deferred("_refresh")


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = preload("res://ui/styles.gd").make_theme()
	var bg := ColorRect.new()
	bg.color = Color(UI.BG, 0.93)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_backdrop = DropZone.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	_fit = W.FitBox.new()
	_fit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fit)
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 40)
	m.add_theme_constant_override("margin_top", 26)
	m.add_theme_constant_override("margin_bottom", 26)
	_fit.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	_sub = UI.caps("", 15, UI.GOOD)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_sub)
	_title = UI.caps("Choose your gear", 52)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.wrap(_title, 200)
	head.add_child(_title)
	_hint = UI.label("", 15, UI.DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.wrap(_hint, 200)
	head.add_child(_hint)
	# The title stays centred between the squad panel (right) and a twin spacer (left); the
	# panel sits in the layout so it pushes the tabs down instead of covering them.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	var twin := Control.new()
	twin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(twin)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(head)
	v.add_child(top)
	_tabs = HBoxContainer.new()
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs.add_theme_constant_override("separation", 10)
	v.add_child(_tabs)
	_center = HBoxContainer.new()
	_center.alignment = BoxContainer.ALIGNMENT_CENTER
	_center.add_theme_constant_override("separation", 30)
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_center)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	_loadout_btn = UI.button("LOADOUT", false, "L")
	_loadout_btn.pressed.connect(open_loadout)
	bar.add_child(_loadout_btn)
	_skip = UI.button("Skip for +%d Supplies" % GearRun.SKIP_SUPPLIES, false, "S")
	_skip.pressed.connect(_skip_pick)
	bar.add_child(_skip)
	_stash = UI.button("Send to stash", false)
	_stash.toggle_mode = true
	_stash.toggled.connect(func(on: bool) -> void:
		_to_stash = on
		_update_take())
	bar.add_child(_stash)
	_take = UI.button("Take", true, "Enter")
	_take.custom_minimum_size.x = 300
	_take.pressed.connect(_take_pick)
	bar.add_child(_take)
	v.add_child(bar)
	# Squad status, top right.
	var sq := PanelContainer.new()
	sq.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	sq.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	sq.custom_minimum_size = Vector2(260, 0)
	_squad = VBoxContainer.new()
	_squad.add_theme_constant_override("separation", 6)
	sq.add_child(_squad)
	top.add_child(sq)
	sq.minimum_size_changed.connect(func() -> void: twin.custom_minimum_size.x = sq.get_combined_minimum_size().x)


# --- State -----------------------------------------------------------------------------

## Soldiers this screen's players pick for, in squad order.
func _my_soldiers() -> Array:
	var out: Array = []
	for r in run.squad():
		if _local_players().has(run.controller_of(r)):
			out.append(r)
	return out


func _pending(r: Dictionary) -> bool:
	return not GearRun.offer_for(run, r.id).is_empty()


func _next_pending() -> int:
	var mine := _my_soldiers()
	for r in mine:
		if _pending(r):
			return r.id
	return -1


func _refresh() -> void:
	_dirty = false
	if run == null:
		return
	if _sid == -1 or not _pending(run.get_soldier(_sid)):
		var nxt := _next_pending()
		if nxt != _sid:
			_sid = nxt
			_card = -1
			_to_stash = false
	var vote := GearRun.doctrine_vote(run)
	# Read from the run, not the soldier on screen: once this player's picks are done the
	# header must still say what the squad is waiting on.
	var source := GearRun.reward_source(run)
	var kit := source == "kit"
	_sub.text = (HEADERS.get(source, HEADERS.skirmish) % run.act).to_upper()
	_sub.add_theme_color_override("font_color", UI.AMBER if kit else UI.GOOD)
	_title.text = "DEPLOYMENT ORDERS" if kit else "CHOOSE YOUR GEAR"
	_backdrop.visible = kit
	_build_tabs()
	_build_squad()
	for c in _center.get_children():
		_center.remove_child(c)
		c.queue_free()
	_cards.clear()
	_prog_box = null
	_compare = null
	_compare_for = -2
	_hovered = -1
	if _sid != -1:
		_show_offer(run.get_soldier(_sid))
	elif not vote.is_empty():
		_show_doctrines(vote)
	elif _progression_pending():
		_show_progression()
	else:
		_show_waiting()
	_update_take()
	# Each soldier's offer is new content: fit it from full size, or the zoom only ratchets down.
	_fit.refit()


func _build_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	var mine := _my_soldiers()
	_tabs.visible = mine.size() > 1 and _sid != -1
	for r in mine:
		var tab := PanelContainer.new()
		var on: bool = r.id == _sid
		tab.add_theme_stylebox_override("panel", UI.box(UI.HELD if on else UI.PANEL_SOFT, UI.AMBER if on else UI.BORDER, 2 if on else 1, 0, 10))
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var stripe := ColorRect.new()
		stripe.color = UI.player_color(r.owner)
		stripe.custom_minimum_size = Vector2(4, 40)
		h.add_child(stripe)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 6)
		name_row.add_child(UI.caps(UI.short_name(r), 17))
		name_row.add_child(UI.caps(UI.class_name_of(r), 13, UI.FAINT))
		col.add_child(name_row)
		var vitals := UI.vitals(r)
		col.add_child(vitals)
		var status := ""
		var scol := UI.DIM
		if _pending(r):
			status = "Choosing" if on else "Pick waiting"
			scol = UI.player_color(r.owner) if on else UI.AMBER
		else:
			status = _took.get(r.id, "Done")
			scol = UI.GOOD
		var tags := HBoxContainer.new()
		tags.add_theme_constant_override("separation", 4)
		var counts := GearTags.counts(r)
		for t in GearTags.ranked(counts).slice(0, 2):
			tags.add_child(UI.tag_chip(t, "%s %d" % [t, counts[t]]))
		tags.add_child(UI.caps(status, 12, scol))
		col.add_child(tags)
		h.add_child(col)
		tab.add_child(h)
		var sid: int = r.id
		tab.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and _pending(run.get_soldier(sid)):
				_sid = sid
				_card = -1
				UI.play(self, "ui_click")
				_refresh())
		for n in h.find_children("*", "Control", true, false):
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hoverable(vitals)
		_tabs.add_child(tab)


## Re-enables hover on the tip-carrying parts of a tab whose children were set to ignore the mouse.
func _hoverable(vitals: Control) -> void:
	for n in vitals.get_children():
		if n.has_meta(Tips.META):
			n.mouse_filter = Control.MOUSE_FILTER_PASS


func _build_squad() -> void:
	for c in _squad.get_children():
		_squad.remove_child(c)
		c.queue_free()
	_squad.add_child(UI.caps("Squad", 13, UI.DIM))
	var names: Dictionary = session.player_names if session != null and "player_names" in session and session.player_names is Dictionary else {}
	for p in run.players:
		var left := 0
		for r in run.squad():
			if run.controller_of(r) == p and _pending(r):
				left += 1
		var voted: bool = GearRun.doctrine_vote(run).get("votes", {}).has(p)
		var h := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = UI.player_color(p)
		sw.custom_minimum_size = Vector2(10, 10)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sw)
		h.add_child(UI.label("  " + str(names.get(p, "Player %d" % (p + 1))), 15, UI.TEXT, "bold"))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(sp)
		var txt := "%d to pick" % left if left > 0 else ("Voted" if voted else "Ready")
		h.add_child(UI.caps(txt, 13, UI.player_color(p) if left > 0 else UI.GOOD))
		_squad.add_child(h)
	_squad.add_child(UI.label("Supplies  %d" % run.supplies, 14, UI.AMBER, "mono"))
	var st := Loadout.stash(run)
	_squad.add_child(UI.label("Stash  %d / %d" % [st.size(), GearData.STASH_SIZE], 14, UI.DIM, "mono"))


func _show_offer(r: Dictionary) -> void:
	var offer := GearRun.offer_for(run, r.id)
	var cards: Array = offer.get("cards", [])
	if offer.get("source", "") == "kit":
		_hint.text = "%s gives %s one order for the drop." % [_player_name(run.controller_of(r)), UI.soldier_name(r)]
	else:
		_hint.text = "%s picks 1 of %d for %s" % [_player_name(run.controller_of(r)), cards.size(), UI.soldier_name(r)]
	for i in cards.size():
		var c: GearCard = GearCard.new()
		c.setup(cards[i], r, i)
		var idx := i
		c.pressed.connect(func() -> void: _select(idx))
		c.mouse_entered.connect(func() -> void:
			_hovered = idx
			_show_compare())
		c.mouse_exited.connect(func() -> void:
			if _hovered == idx:
				_hovered = -1
				_show_compare())
		_center.add_child(c)
		_cards.append(c)
		c.set_selected(i == _card)
		# Deal the cards in.
		c.modulate.a = 0.0
		var tw := c.create_tween()
		tw.tween_interval(0.06 * i)
		tw.tween_property(c, "modulate:a", 1.0, 0.22)
	_center.add_child(_compare_column(r))
	_show_compare()


## The column beside the cards: one glass panel, the compare drawn straight into it.
func _compare_column(r: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.name = "Compare"
	p.add_theme_stylebox_override("panel", UI.box(UI.PANEL_SOFT, UI.BORDER, 1, 0, 18))
	p.custom_minimum_size = Vector2(COMPARE_W, GearCard.H)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var stripe_row := HBoxContainer.new()
	stripe_row.add_theme_constant_override("separation", 14)
	var stripe := ColorRect.new()
	stripe.color = UI.player_color(r.owner)
	stripe.custom_minimum_size = Vector2(3, 0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe_row.add_child(stripe)
	_compare = VBoxContainer.new()
	_compare.add_theme_constant_override("separation", 9)
	_compare.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stripe_row.add_child(_compare)
	p.add_child(stripe_row)
	return p


## Fills the compare column for the hovered card, else the picked one, else the kit.
func _show_compare() -> void:
	if _compare == null or _sid == -1:
		return
	var idx := _hovered if _hovered >= 0 else _card
	if idx >= _cards.size():
		idx = -1
	if idx == _compare_for:
		return
	_compare_for = idx
	for c in _compare.get_children():
		_compare.remove_child(c)
		c.queue_free()
	var r := run.get_soldier(_sid)
	var inner := COMPARE_W - 18 * 2 - 17
	if idx < 0:
		CompareView.kit(_compare, r, inner, UI.player_color(r.owner), BOOST)
	else:
		CompareView.build(_compare, compare_data(idx), inner, UI.player_color(r.owner), BOOST)


## GearCompare for card `idx` on the soldier picking (in co-op, always that player's soldier).
func compare_data(idx: int) -> Dictionary:
	return GearCompare.compare(run, run.get_soldier(_sid), _cards[idx].card)


## The soldier's full loadout over this screen; Back returns to the same pick.
func open_loadout() -> void:
	if is_instance_valid(_overlay):
		return
	UI.play(self, "ui_click")
	var sid := _sid
	if sid == -1:
		var mine := _my_soldiers()
		sid = mine[0].id if not mine.is_empty() else -1
	_overlay = LoadoutScreen.open_over(self, run, session, sid)


func _show_doctrines(vote: Dictionary) -> void:
	_title.text = "CHOOSE A DOCTRINE"
	# Rewards come before the next act starts, so run.act is still the boss's act.
	_sub.text = (HEADERS.boss % run.act).to_upper()
	_hint.text = "Squad-wide for the rest of the run. Majority wins; the host breaks a tie."
	var mine: Array = _local_players().filter(func(p): return not run.benched.get(p, false))
	for i in vote.options.size():
		var id: String = vote.options[i]
		var d: Dictionary = GearData.DOCTRINES.get(id, {})
		var p := W.Frame.new(Vector4(24, 22, 24, 22))
		p.custom_minimum_size = Vector2(330, 360)
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 12)
		var art := W.Icon.new("doctrine", UI.AMBER, 56, 2.0)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(art)
		var nm := UI.caps(d.get("name", id), 32)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nm)
		v.add_child(NodeUi.effect_row(d.get("desc", ""), 16))
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(sp)
		# One pip per player: lit in their colour once they back this doctrine.
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 6)
		pips.alignment = BoxContainer.ALIGNMENT_CENTER
		for pl in run.players:
			var on: bool = vote.votes.get(pl, "") == id
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(26, 6)
			pip.color = UI.player_color(pl) if on else UI.BORDER
			pip.tooltip_text = _player_name(pl)
			pips.add_child(pip)
		v.add_child(pips)
		for pl in mine:
			var b := UI.button("Vote" if mine.size() == 1 else "Vote · %s" % _player_name(pl), vote.votes.get(pl) != id)
			b.disabled = vote.votes.get(pl) == id
			if b.disabled:
				b.text = "VOTED"
			var player: int = pl
			b.pressed.connect(func() -> void:
				UI.play(self, "ui_confirm")
				Feel.sound("vote")
				session.submit_run({"type": "gear_doctrine", "player": player, "doctrine": id}))
			v.add_child(b)
		p.add_child(v)
		_center.add_child(p)


func _progression_pending() -> bool:
	return RunHooks.call_static("Progression", "has_pending", [run], false) and RunHooks.has("Progression", "pick_screen")


func _show_progression() -> void:
	_title.text = "RANK UP"
	_sub.text = "PERKS AND MUTATIONS"
	_hint.text = ""
	var script = RunHooks.call_static("Progression", "pick_screen")
	if script == null:
		_show_waiting()
		return
	var ctl: Control = script.new() if script is Script else script
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.add_child(ctl)
	if ctl.has_method("setup"):
		ctl.setup(run, session)
	_prog_box = ctl


func _show_waiting() -> void:
	_hint.text = ""
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	var ic := W.Icon.new("waiting", UI.DIM, 40, 2.0)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ic)
	box.add_child(UI.caps("Waiting for teammates", 26, UI.DIM))
	_center.add_child(box)


func _player_name(p: int) -> String:
	if session != null and "player_names" in session and session.player_names is Dictionary and session.player_names.has(p):
		return str(session.player_names[p])
	return "You" if run.is_solo() else "Player %d" % (p + 1)


# --- Picking ---------------------------------------------------------------------------

func _select(i: int) -> void:
	if i < 0 or i >= _cards.size():
		return
	_card = i
	UI.play(self, "ui_click")
	for j in _cards.size():
		_cards[j].set_selected(j == i)
	_show_compare()
	_update_take()


func _update_take() -> void:
	var has_offer := _sid != -1
	_skip.visible = has_offer
	_take.visible = has_offer
	_stash.visible = false
	if not has_offer:
		return
	var kit: bool = GearRun.offer_for(run, _sid).get("source", "") == "kit"
	_skip.visible = not kit
	_skip.text = "SKIP FOR +%d SUPPLIES   [S]" % GearRun.SKIP_SUPPLIES
	if _card < 0 or _card >= _cards.size():
		_take.text = "%s   [1-%d]" % ["PICK AN ORDER" if kit else "PICK A CARD", maxi(1, _cards.size())]
		_take.disabled = true
		return
	var c: GearCard = _cards[_card]
	var is_gear: bool = c.card.get("kind") == "gear"
	_stash.visible = is_gear and Loadout.preview_equip(c.record, c.card.id).mode != "upgrade"
	_stash.set_pressed_no_signal(_to_stash)
	var verb := "Stash" if _to_stash and _stash.visible else ("Deploy with" if kit else "Take")
	_take.text = "%s %s   [Enter]" % [verb, c.title()]
	var err := GearRun.validate(run, _action(_card))
	_take.disabled = err != ""
	if err != "":
		_take.text = err.to_upper()


func _action(card: int) -> Dictionary:
	var r := run.get_soldier(_sid)
	var a := {"type": "gear_pick", "player": run.controller_of(r), "soldier": _sid, "card": card}
	if _to_stash and card >= 0 and _stash.visible:
		a["to_stash"] = true
	return a


func _take_pick() -> void:
	if _card < 0 or _take.disabled:
		return
	var c: GearCard = _cards[_card]
	_took[_sid] = "Took " + c.title()
	UI.play(self, "ui_confirm")
	var a := _action(_card)
	var tw := c.create_tween().set_parallel()
	tw.tween_property(c, "scale", Vector2(1.12, 1.12), 0.16)
	tw.tween_property(c, "modulate", Color(1.4, 1.3, 0.9, 0.0), 0.22)
	for o in _cards:
		if o != c:
			o.create_tween().tween_property(o, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(func() -> void: session.submit_run(a))


func _skip_pick() -> void:
	if _sid == -1 or not _skip.visible:
		return
	_took[_sid] = "Skipped"
	UI.play(self, "ui_click")
	session.submit_run(_action(-1))


func _unhandled_key_input(ev: InputEvent) -> void:
	if not ev.pressed or ev.echo or is_instance_valid(_overlay):
		return
	if ev.keycode == KEY_L:
		open_loadout()
		get_viewport().set_input_as_handled()
		return
	if _sid == -1:
		return
	match ev.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			_select(ev.keycode - KEY_1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_take_pick()
		KEY_S:
			_skip_pick()
		KEY_TAB:
			var mine := _my_soldiers().filter(func(r): return _pending(r))
			if mine.size() > 1:
				var i := mine.find_custom(func(r): return r.id == _sid)
				_sid = mine[(i + 1) % mine.size()].id
				_card = -1
				_refresh()
		_:
			return
	get_viewport().set_input_as_handled()


## Behind the deployment orders: a faint landing grid and a drop-zone ring, so the run-start
## pick reads as its own moment rather than another reward.
class DropZone:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var g := Color(UI.AMBER, 0.035)
		var step := 48.0
		var x := fmod(size.x / 2, step)
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), g)
			x += step
		var y := fmod(size.y / 2, step)
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), g)
			y += step
		var c := size / 2 + Vector2(0, size.y * 0.1)
		var r := minf(size.x, size.y) * 0.36
		for i in 3:
			draw_arc(c, r * (1.0 - i * 0.28), 0, TAU, 96, Color(UI.AMBER, 0.07 - i * 0.015), 2.0, true)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * r * 1.04, c + d * r * 1.14, Color(UI.AMBER, 0.12), 2.0, true)
