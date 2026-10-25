extends Control
## Loadout screen (from the map, or during REWARD): squad bar, the selected soldier's guns
## (click one to carry it), 4 gear slots and pockets, their tag strip with 3 pips per tag and the set bonuses, and the shared
## 4-item stash, and the soldier's graft body diagram. Drag a stash item onto a slot to equip it (the old item swaps into the stash),
## drag a slot onto the stash to store it, or click a stash item then a slot. While dragging or
## hovering a stash item, the tag strip previews the change (2→3 in gold) and the slots that
## feed that tag light up. Only soldiers a local player controls can be changed.

signal closed

const Tips := preload("res://ui/tips/tips.gd")
const UI := preload("res://ui/gear/gear_ui.gd")
const W := preload("res://ui/widgets.gd")
const GraftFigure := preload("res://ui/graft_figure.gd")

var run: RunState
var session
var _sid := -1
var _held := -1          # stash index picked up by click
var _preview_id := ""    # item being previewed in the tag strip
var _dirty := false

var _squad_bar: HBoxContainer
var _name: Label
var _sub: Label
var _guns: HBoxContainer
var _slots: GridContainer
var _pockets: HBoxContainer
var _grafts: HBoxContainer
var _tags: VBoxContainer
var _stash_row: HBoxContainer
var _stash_title: Label
var _toast: Label
var _supplies: Label
var _build_box: VBoxContainer
var _fit: Container


func setup(r: RunState, s) -> void:
	run = r
	session = s
	_build()
	run.event.connect(func(ev) -> void:
		if ev.get("type") == "rejected" and str(ev.get("action", {}).get("type", "")).begins_with("gear_"):
			_show_toast(str(ev.get("reason", "")))
		_queue_refresh())
	var mine := _editable_soldiers()
	_sid = mine[0].id if not mine.is_empty() else (run.squad()[0].id if not run.squad().is_empty() else -1)
	_refresh()


func _local_players() -> Array:
	return session.local_players() if session != null and session.has_method("local_players") else run.players


func _editable_soldiers() -> Array:
	return run.squad().filter(func(r): return _local_players().has(run.controller_of(r)))


func _can_edit(r: Dictionary) -> bool:
	return not r.is_empty() and _local_players().has(run.controller_of(r))


func _queue_refresh() -> void:
	if not _dirty:
		_dirty = true
		call_deferred("_refresh")


# --- Layout ----------------------------------------------------------------------------

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = preload("res://ui/styles.gd").make_theme()
	var bg := ColorRect.new()
	bg.color = Color(UI.BG, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_fit = W.FitBox.new()
	_fit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fit)
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 36)
	m.add_theme_constant_override("margin_top", 20)
	m.add_theme_constant_override("margin_bottom", 20)
	_fit.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	# Header.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	head.add_child(UI.caps("Loadout", 38))
	var where := UI.caps("Act %d" % run.act, 15, UI.FAINT)
	where.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(where)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_supplies = UI.mono("", 16, UI.AMBER)
	_supplies.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_supplies)
	var back := UI.button("Back", true, "Esc")
	back.pressed.connect(_close)
	head.add_child(back)
	v.add_child(head)
	_squad_bar = HBoxContainer.new()
	_squad_bar.add_theme_constant_override("separation", 12)
	v.add_child(_squad_bar)
	# Body: soldier on the left, tags on the right.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 30)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 14)
	_name = UI.caps("", 44)
	name_row.add_child(_name)
	_sub = UI.caps("", 15, UI.DIM)
	_sub.size_flags_vertical = Control.SIZE_SHRINK_END
	name_row.add_child(_sub)
	left.add_child(name_row)
	left.add_child(UI.caps("Gun", 13, UI.DIM))
	_guns = HBoxContainer.new()
	_guns.add_theme_constant_override("separation", 12)
	left.add_child(_guns)
	left.add_child(UI.caps("Gear", 13, UI.DIM))
	_slots = GridContainer.new()
	_slots.columns = 4
	_slots.add_theme_constant_override("h_separation", 12)
	_slots.add_theme_constant_override("v_separation", 12)
	left.add_child(_slots)
	left.add_child(UI.caps("Pockets", 13, UI.DIM))
	_pockets = HBoxContainer.new()
	_pockets.add_theme_constant_override("separation", 10)
	left.add_child(_pockets)
	left.add_child(UI.caps("Grafts", 13, UI.DIM))
	_grafts = HBoxContainer.new()
	_grafts.add_theme_constant_override("separation", 18)
	left.add_child(_grafts)
	left.add_child(UI.caps("Build", 13, UI.DIM))
	_build_box = VBoxContainer.new()
	_build_box.add_theme_constant_override("separation", 4)
	left.add_child(_build_box)
	_toast = UI.label("", 15, UI.AMBER, "bold")
	left.add_child(_toast)
	var tag_panel := PanelContainer.new()
	tag_panel.custom_minimum_size = Vector2(470, 0)
	# A column, not a box: one hairline on its left keeps it apart from the slots.
	var tag_sb := UI.box(Color(0, 0, 0, 0), UI.BORDER, 0, 0, 14)
	tag_sb.border_width_left = 1
	tag_sb.shadow_size = 0
	tag_sb.set_corner_radius_all(0)
	tag_sb.content_margin_left = 24
	tag_panel.add_theme_stylebox_override("panel", tag_sb)
	_tags = VBoxContainer.new()
	_tags.add_theme_constant_override("separation", 2)
	tag_panel.add_child(_tags)
	body.add_child(tag_panel)
	# Stash.
	var st := VBoxContainer.new()
	st.add_theme_constant_override("separation", 8)
	var st_head := HBoxContainer.new()
	_stash_title = UI.caps("", 13, UI.DIM)
	st_head.add_child(_stash_title)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st_head.add_child(sp2)
	st_head.add_child(UI.label("Drag gear between a soldier and the stash. Anyone in the squad can take from it.", 13, UI.FAINT))
	st.add_child(st_head)
	_stash_row = HBoxContainer.new()
	_stash_row.add_theme_constant_override("separation", 12)
	st.add_child(_stash_row)
	v.add_child(st)


func _refresh() -> void:
	_dirty = false
	if run == null:
		return
	var r := run.get_soldier(_sid)
	if r.is_empty() or r.status != RunSoldier.ACTIVE:
		var sq := run.squad()
		_sid = sq[0].id if not sq.is_empty() else -1
		r = run.get_soldier(_sid)
	if _held >= Loadout.stash(run).size():
		_held = -1
	_supplies.text = "%d Supplies" % run.supplies
	_build_squad_bar()
	# Take the old tiles out now: queued for deletion they still count toward the size, and the
	# FitBox would zoom the next soldier out to fit both. Then fit the new content from full size.
	for n in [_guns, _slots, _pockets, _grafts, _tags, _stash_row, _build_box]:
		for c in n.get_children():
			n.remove_child(c)
			c.queue_free()
	_fit.refit()
	if r.is_empty():
		return
	_name.text = UI.short_name(r).to_upper()
	var rank = r.get("prog", {}).get("rank", null) if r.get("prog") is Dictionary else null
	_sub.text = ("%s%s · %s" % ["Rank %d " % int(rank) if rank != null else "", UI.class_name_of(r), _player_name(r.owner)]).to_upper()
	if not _can_edit(r):
		_sub.text += "  ·  VIEW ONLY"
	for id in [Weapons.id_for(r.kind)] + Loadout.guns(r):
		_guns.add_child(_gun_tile(r, id))
	var feeding := _preview_tags()
	for slot in GearData.SLOTS:
		_slots.add_child(_slot_tile(r, slot, feeding))
	var ps := Loadout.pockets(r)
	for i in ps.size():
		_pockets.add_child(_pocket_tile(ps[i]))
	_build_grafts(r)
	_build_tags(r)
	_build_stash(r)
	_build_summary(r)


func _player_name(p: int) -> String:
	if session != null and "player_names" in session and session.player_names is Dictionary and session.player_names.has(p):
		return str(session.player_names[p])
	return "Player %d" % (p + 1)


func _build_squad_bar() -> void:
	for c in _squad_bar.get_children():
		_squad_bar.remove_child(c)
		c.queue_free()
	for r in run.squad():
		var on: bool = r.id == _sid
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.add_theme_stylebox_override("panel", UI.box(UI.HELD if on else UI.PANEL_SOFT, UI.AMBER if on else UI.BORDER, 2 if on else 1, 0, 10))
		p.modulate.a = 1.0 if _can_edit(r) else 0.75
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var stripe := ColorRect.new()
		stripe.color = UI.player_color(r.owner)
		stripe.custom_minimum_size = Vector2(4, 42)
		h.add_child(stripe)
		var col := VBoxContainer.new()
		var nr := HBoxContainer.new()
		nr.add_theme_constant_override("separation", 6)
		nr.add_child(UI.caps(UI.short_name(r), 18))
		nr.add_child(UI.caps(UI.class_name_of(r), 13, UI.FAINT))
		col.add_child(nr)
		var tags := HBoxContainer.new()
		tags.add_theme_constant_override("separation", 4)
		var counts := GearTags.counts(r)
		var ranked := GearTags.ranked(counts)
		for t in ranked.slice(0, 2):
			tags.add_child(UI.tag_chip(t, "%s %d" % [t, counts[t]]))
		if ranked.is_empty():
			tags.add_child(UI.label("No tags yet", 12, UI.FAINT))
		col.add_child(tags)
		h.add_child(col)
		p.add_child(h)
		var sid: int = r.id
		p.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_sid = sid
				_held = -1
				_preview_id = ""
				UI.play(self, "ui_click")
				_refresh())
		for n in p.find_children("*", "Control", true, false):
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_squad_bar.add_child(p)


# --- Tiles -----------------------------------------------------------------------------

## Tags the previewed item would change, so the slots feeding them can be outlined.
func _preview_tags() -> Array:
	return GearData.tags_of(_preview_id) if _preview_id != "" else []


func _slot_tile(r: Dictionary, slot: String, feeding: Array) -> Control:
	var it = Loadout.item_at(r, slot)
	var t := DropTile.new()
	t.custom_minimum_size = Vector2(0, 176)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var target_slot := _preview_id != "" and GearData.slot_of(_preview_id) == slot
	var feeds := it != null and GearData.tags_of(it.id).any(func(x): return feeding.has(x))
	var border := UI.BORDER
	var bg := UI.PANEL_SOFT
	if target_slot:
		border = UI.AMBER
		bg = UI.HELD
	elif feeds:
		border = GearData.tag_color(feeding[0])
	var sb := UI.box(bg, border, 2 if target_slot else 1, 0, 14)
	if it != null and GearData.rarity_of(it.id) == "prototype":
		sb.border_color = UI.AMBER if target_slot else UI.PROTO_COLORS[2]
		sb.set_border_width_all(2)
	t.add_theme_stylebox_override("panel", sb)
	if _preview_id != "" and not target_slot and not feeds:
		t.modulate.a = 0.55
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_child(UI.label(GearData.SLOT_NAMES[slot].to_upper(), 11, UI.FAINT, "mono"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	if it != null:
		var rar := GearData.rarity_of(it.id)
		head.add_child(UI.caps("%s · Mk %s" % [GearData.RARITY_NAMES[rar], "II" if it.mk >= 2 else "I"], 12, UI.rarity_color(rar)))
	v.add_child(head)
	if it == null:
		v.add_child(UI.caps("Empty", 22, UI.FAINT))
		if target_slot:
			v.add_child(UI.label("Drop to equip " + GearData.item_name(_preview_id), 13, UI.AMBER))
	else:
		v.add_child(UI.wrap(UI.caps(GearData.item_name(it.id), 22), 200))
		v.add_child(UI.wrap(UI.label(GearData.desc(it.id, it.mk), 13, UI.COPY), 200))
		if target_slot:
			v.add_child(UI.label("Drop to swap. %s goes to the stash." % GearData.item_name(it.id), 13, UI.AMBER))
		var tags := HBoxContainer.new()
		tags.add_theme_constant_override("separation", 4)
		for tg in GearData.tags_of(it.id):
			tags.add_child(UI.tag_chip(tg))
		var sp2 := Control.new()
		sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(sp2)
		v.add_child(tags)
		t.tooltip_text = "%s\nMk I: %s\nMk II: %s" % [GearData.item_name(it.id), GearData.desc(it.id, 1), GearData.desc(it.id, 2)]
		_tag_terms(t, r, GearData.tags_of(it.id))
	for n in v.find_children("*", "Control", true, false):
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(v)
	var editable := _can_edit(r)
	var sid: int = r.id
	if editable and it != null:
		t.drag_data = {"from": "slot", "slot": slot, "soldier": sid, "id": it.id}
		t.drag_label = GearData.item_name(it.id)
	t.can_drop = func(d) -> bool:
		return editable and d is Dictionary and d.get("from") == "stash" and GearData.slot_of(d.id) == slot
	t.dropped = func(d) -> void: _equip_from_stash(int(d.index))
	t.clicked = func() -> void:
		if editable and _held >= 0 and GearData.slot_of(Loadout.stash(run)[_held].id) == slot:
			_equip_from_stash(_held)
	t.drag_state = func(on: bool, d) -> void: _set_preview(d.get("id", "") if on and d is Dictionary and d.get("from") == "stash" else "")
	return t


## One gun the soldier owns; the one in hand is framed amber. Click another to carry it.
func _gun_tile(r: Dictionary, id: String) -> Control:
	var g := Weapons.get_gun(id)
	var carried := Loadout.gun_id(r) == id
	var t := DropTile.new()
	t.custom_minimum_size = Vector2(0, 96)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_stylebox_override("panel", UI.box(UI.HELD if carried else UI.PANEL_SOFT, UI.AMBER if carried else UI.BORDER, 2 if carried else 1, 0, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_child(UI.label("IN HAND" if carried else "SPARE", 11, UI.AMBER if carried else UI.FAINT, "mono"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var rar: String = g.get("rarity", "")
	head.add_child(UI.caps(GearData.RARITY_NAMES[rar] if rar != "" else "Signature", 12, UI.rarity_color(rar) if rar != "" else UI.DIM))
	v.add_child(head)
	v.add_child(UI.caps(g.name, 19))
	if g.get("tag", "") != "":
		var tags := HBoxContainer.new()
		tags.add_child(UI.tag_chip(g.tag))
		v.add_child(tags)
	t.tooltip_text = "%s\n%s" % [g.name, g.desc]
	if g.get("tag", "") != "":
		_tag_terms(t, r, [g.tag])
	for n in v.find_children("*", "Control", true, false):
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(v)
	if _can_edit(r) and not carried:
		var sid: int = r.id
		t.clicked = func() -> void:
			var msg := "%s now carries the %s" % [UI.short_name(r), g.name]
			for p in GearTags.preview_gun(r, "" if id == Weapons.id_for(r.kind) else id):
				if p.unlocks:
					msg += ". %s set bonus on!" % p.tag
				elif p.loses:
					msg += ". %s set bonus off" % p.tag
			_submit({"type": "gear_gun", "player": run.controller_of(r), "soldier": sid, "gun": "" if id == Weapons.id_for(r.kind) else id})
			_show_toast(msg)
	return t


func _pocket_tile(p) -> Control:
	var t := PanelContainer.new()
	t.custom_minimum_size = Vector2(150, 74)
	t.add_theme_stylebox_override("panel", UI.box(UI.PANEL_SOFT, UI.BORDER, 1, 0, 10))
	var v := VBoxContainer.new()
	v.add_child(UI.label("POCKET", 11, UI.FAINT, "mono"))
	if p == null:
		v.add_child(UI.caps("Empty", 16, UI.FAINT))
	else:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.add_child(UI.caps(GearData.item_name(p.id), 17))
		h.add_child(UI.mono("×%d" % int(p.charges), 13, UI.DIM))
		v.add_child(h)
		t.tooltip_text = GearData.desc(p.id)
	Tips.term(t, "pocket")
	t.add_child(v)
	return t


## Hover card for a gear tile: the item text, then its tag with this soldier's count.
func _tag_terms(t: Control, r: Dictionary, tags: Array) -> void:
	if tags.is_empty():
		return
	var tag := str(tags[0])
	Tips.terms(t, tags.map(func(x): return "tag_" + str(x).to_lower()),
		{"count": GearTags.counts(r).get(tag, 0), "color": GearData.tag_color(tag)})


func _build_tags(r: Dictionary) -> void:
	var head := HBoxContainer.new()
	head.add_child(UI.caps("Tags · " + UI.short_name(r), 13, UI.DIM))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(Tips.term(UI.label("set bonus at %d" % GearData.SET_THRESHOLD, 12, UI.FAINT), "set_bonus"))
	_tags.add_child(head)
	var counts := GearTags.counts(r)
	var changes := {}
	if _preview_id != "":
		for p in GearTags.preview(r, _preview_id):
			changes[p.tag] = p
	var protos := GearTags.qualified_prototypes(counts)
	for tag in GearData.TAGS:
		var n: int = counts.get(tag, 0)
		var ch: Dictionary = changes.get(tag, {})
		var col := GearData.tag_color(tag) if n > 0 or not ch.is_empty() else UI.FAINT
		var row := PanelContainer.new()
		var hot := not ch.is_empty()
		row.add_theme_stylebox_override("panel", UI.box(Color(col, 0.08) if hot else Color(0, 0, 0, 0), col if hot else Color(0, 0, 0, 0), 1, 0, 8))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var dot := ColorRect.new()
		dot.color = col
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(dot)
		var nm := UI.caps(tag, 17, col)
		nm.custom_minimum_size.x = 120
		h.add_child(nm)
		var num := UI.mono(str(n), 19, col)
		if hot:
			num.text = "%d→%d" % [ch.from, ch.to]
			num.add_theme_color_override("font_color", UI.AMBER if ch.to > ch.from else UI.DANGER)
		num.custom_minimum_size.x = 64
		h.add_child(num)
		var sp2 := Control.new()
		sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(sp2)
		h.add_child(UI.pips(tag, n, ch.get("to", -1)))
		row.add_child(h)
		Tips.term(row, "tag_" + tag.to_lower(), {"count": n, "color": GearData.tag_color(tag)})
		_tags.add_child(row)
		if n >= GearData.SET_THRESHOLD and not ch.get("loses", false):
			_tags.add_child(_bonus_line("Set bonus on: " + GearData.TAG_INFO[tag].bonus, col))
		elif ch.get("unlocks", false):
			_tags.add_child(_bonus_line("Completes the set: " + GearData.TAG_INFO[tag].bonus, UI.AMBER))
		elif ch.get("loses", false):
			_tags.add_child(_bonus_line("Turns off: " + GearData.TAG_INFO[tag].bonus, UI.DANGER))
	if not protos.is_empty():
		var names := protos.map(func(id): return GearData.item_name(id))
		_tags.add_child(_bonus_line("Prototypes unlocked: " + ", ".join(names) + ". Rare rewards may become one.", UI.AMBER))


## What the soldier's build does right now, and the next step toward a set bonus.
func _build_summary(r: Dictionary) -> void:
	var counts := GearTags.counts(r)
	var sets := GearTags.active_sets(counts)
	for t in sets:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.add_child(UI.tag_chip(t, "%s set" % t))
		h.add_child(UI.wrap(UI.label(GearData.TAG_INFO[t].bonus, 14, UI.TEXT), 640))
		_build_box.add_child(h)
	var close: Array = GearTags.ranked(counts).filter(func(t): return counts[t] == GearData.SET_THRESHOLD - 1)
	for t in close:
		_build_box.add_child(UI.label("One more %s item switches on: %s" % [t, GearData.TAG_INFO[t].bonus], 14, GearData.tag_color(t)))
	if sets.is_empty() and close.is_empty():
		_build_box.add_child(UI.label("Stack 3 of one tag (gear, perks, awake mutations) to switch on its set bonus.", 14, UI.FAINT))
	var d: Array = run.modifiers.get("doctrines", [])
	if not d.is_empty():
		var names := d.map(func(id): return GearData.DOCTRINES.get(id, {}).get("name", id))
		_build_box.add_child(UI.label("Squad Doctrines: " + ", ".join(names), 14, UI.DIM))


## The body diagram and one line per slot: the part's name in its path colour, or open.
func _build_grafts(r: Dictionary) -> void:
	var g := Grafts.of(r)
	var locked := g.is_empty() and Grafts.eligible_error(run, r) not in ["", "Every slot is grafted"]
	var fig := GraftFigure.new(Vector2(52, 78))
	fig.setup(g, "", locked)
	_grafts.add_child(fig)
	if locked:
		var why := UI.label("Body grafts open in Act %d, from Rank %d: a Machine Refit at the hospital or depot, or a Bloom part from nests." % [
			GraftData.FROM_ACT, GraftData.FROM_RANK], 13, UI.FAINT)
		why.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_grafts.add_child(UI.wrap(why, 420))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for slot in GraftData.SLOTS:
		grid.add_child(UI.caps(GraftData.SLOT_NAMES[slot], 12, UI.FAINT))
		var id: String = g.get(slot, "")
		var l := UI.label(GraftData.name_of(id) if id != "" else "Open", 15, GraftFigure.path_color(id) if id != "" else UI.FAINT, "bold" if id != "" else "body")
		if id != "":
			l.tooltip_text = GraftData.get_def(id).desc
			Tips.term(l, "graft")
			l.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(l)
	_grafts.add_child(grid)
	var floor_at := Grafts.floor_of(g)
	if floor_at > 0:
		var fl := UI.label("Infection floor %d" % floor_at, 13, UI.TEAL)
		fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_grafts.add_child(fl)


func _bonus_line(text: String, col: Color) -> Control:
	var l := UI.wrap(UI.label(text, 13, col), 420)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 30)
	m.add_theme_constant_override("margin_bottom", 4)
	m.add_child(l)
	return m


func _build_stash(r: Dictionary) -> void:
	var st := Loadout.stash(run)
	_stash_title.text = "SHARED STASH · %d / %d" % [st.size(), GearData.STASH_SIZE]
	var editable := _can_edit(r)
	for i in GearData.STASH_SIZE:
		var t := DropTile.new()
		t.custom_minimum_size = Vector2(0, 96)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		if i < st.size():
			var it: Dictionary = st[i]
			var rar := GearData.rarity_of(it.id)
			var held := i == _held
			t.add_theme_stylebox_override("panel", UI.box(UI.HELD if held else UI.PANEL_SOFT, UI.AMBER if held else UI.BORDER, 2 if held else 1, 0, 10))
			var head := HBoxContainer.new()
			head.add_child(UI.label(GearData.SLOT_NAMES[GearData.slot_of(it.id)].to_upper(), 11, UI.FAINT, "mono"))
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			head.add_child(sp)
			head.add_child(UI.caps("%s · Mk %s" % [GearData.RARITY_NAMES[rar], "II" if it.mk >= 2 else "I"], 12, UI.rarity_color(rar)))
			v.add_child(head)
			v.add_child(UI.caps(GearData.item_name(it.id), 19))
			var tags := HBoxContainer.new()
			tags.add_theme_constant_override("separation", 4)
			for tg in GearData.tags_of(it.id):
				tags.add_child(UI.tag_chip(tg))
			v.add_child(tags)
			t.tooltip_text = "%s (Mk %s)\n%s" % [GearData.item_name(it.id), "II" if it.mk >= 2 else "I", GearData.desc(it.id, it.mk)]
			if editable:
				t.drag_data = {"from": "stash", "index": i, "id": it.id}
				t.drag_label = GearData.item_name(it.id)
				var idx := i
				t.clicked = func() -> void:
					_held = -1 if _held == idx else idx
					_set_preview(st[idx].id if _held == idx else "")
					UI.play(self, "ui_click")
				t.hovered = func(on: bool) -> void:
					if _held == -1:
						_set_preview(it.id if on else "")
				t.drag_state = func(on: bool, d) -> void: _set_preview(it.id if on else "")
		else:
			t.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0), UI.BORDER, 1, 0, 10))
			t.modulate.a = 0.5
			v.add_child(UI.label("EMPTY", 11, UI.FAINT, "mono"))
		for n in v.find_children("*", "Control", true, false):
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.add_child(v)
		t.can_drop = func(d) -> bool:
			return editable and d is Dictionary and d.get("from") == "slot" and st.size() < GearData.STASH_SIZE
		t.dropped = func(d) -> void: _unequip(str(d.slot))
		_stash_row.add_child(t)


# --- Actions ---------------------------------------------------------------------------

func _set_preview(id: String) -> void:
	if id == _preview_id:
		return
	_preview_id = id
	_queue_refresh()


func _submit(a: Dictionary) -> void:
	var err := RunRules.validate(run, a)
	if err != "":
		_show_toast(err)
		UI.play(self, "ui_deny")
		return
	UI.play(self, "ui_confirm")
	session.submit_run(a)


func _equip_from_stash(index: int) -> void:
	var r := run.get_soldier(_sid)
	var it: Dictionary = Loadout.stash(run)[index]
	var pv := Loadout.preview_equip(r, it.id)
	var msg := "%s equipped on %s" % [GearData.item_name(it.id), UI.short_name(r)]
	if pv.mode == "replace":
		msg += "; %s went to the stash" % GearData.item_name(pv.old.id)
	elif pv.mode == "upgrade":
		msg = "%s upgraded to Mk II" % GearData.item_name(it.id)
	for p in GearTags.preview(r, it.id):
		if p.unlocks:
			msg += ". %s set bonus on!" % p.tag
	_held = -1
	_preview_id = ""
	_submit({"type": "gear_stash_take", "player": run.controller_of(r), "soldier": _sid, "index": index})
	_show_toast(msg)


func _unequip(slot: String) -> void:
	var r := run.get_soldier(_sid)
	_preview_id = ""
	_submit({"type": "gear_unequip", "player": run.controller_of(r), "soldier": _sid, "slot": slot})


func _show_toast(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := _toast.create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.6)


func _close() -> void:
	UI.play(self, "ui_click")
	closed.emit()
	hide()


func _unhandled_key_input(ev: InputEvent) -> void:
	if visible and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()


## A panel that can be dragged from and dropped onto, wired with callables.
class DropTile:
	extends PanelContainer

	const UIS := preload("res://ui/gear/gear_ui.gd")

	var drag_data: Variant = null
	var drag_label := ""
	var can_drop: Callable
	var dropped: Callable
	var clicked: Callable
	var hovered: Callable
	var drag_state: Callable

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		if drag_data != null or clicked.is_valid():
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: if hovered.is_valid(): hovered.call(true))
		mouse_exited.connect(func() -> void: if hovered.is_valid(): hovered.call(false))

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed and clicked.is_valid():
			clicked.call()

	func _get_drag_data(_at: Vector2) -> Variant:
		if drag_data == null:
			return null
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UIS.box(UIS.HELD, UIS.AMBER, 2, 0, 10))
		p.add_child(UIS.caps(drag_label, 18))
		p.rotation_degrees = -3
		set_drag_preview(p)
		modulate.a = 0.4
		if drag_state.is_valid():
			drag_state.call(true, drag_data)
		return drag_data

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			modulate.a = 1.0
			if drag_data != null and drag_state.is_valid() and is_inside_tree():
				drag_state.call(false, drag_data)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return can_drop.is_valid() and can_drop.call(data)

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if dropped.is_valid():
			dropped.call(data)
