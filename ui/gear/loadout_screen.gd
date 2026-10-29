extends Control
## Loadout screen (from the map, or during REWARD): squad bar, the selected soldier as a silhouette between two slot
## columns (gear on the left, guns and what hangs on them on the right; spare guns ride in the stash), pockets, their tag strip with 3 pips per tag and the set bonuses, and the shared
## 4-item stash, and the soldier's graft body diagram. Drag a stash item onto a slot to equip it (the old item swaps into the stash),
## drag a slot onto the stash to store it, or click a stash item then a slot. While dragging or
## hovering a stash item, the tag strip previews the change (2→3 in gold) and the slots that
## feed that tag light up. Only soldiers a local player controls can be changed.

signal closed

const Tips := preload("res://ui/tips/tips.gd")
const UI := preload("res://ui/gear/gear_ui.gd")
const W := preload("res://ui/widgets.gd")
const GraftFigure := preload("res://ui/graft_figure.gd")

const LEFT_SLOTS: Array[String] = ["head", "body", "offhand", "utility", "utility2"]
const RIGHT_SLOTS: Array[String] = ["gun", "weapon", "ammo", "melee"]
const PARTS := {"head": ["head"], "body": ["body"], "arms": ["offhand", "melee", "gun", "weapon", "ammo"], "legs": ["utility", "utility2"]}

var run: RunState
var session
var _sid := -1
var _held := -1          # stash index picked up by click
var _preview_id := ""    # item being previewed in the tag strip
var _dirty := false

var _squad_bar: HBoxContainer
var _name: Label
var _sub: Label
var _col_l: VBoxContainer
var _col_r: VBoxContainer
var _figure: Control
var _pockets: HBoxContainer
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


## Opens a loadout over `host` (the reward screen or a node screen) without touching what is
## under it, so a half-made pick is still there after Back. Starts on soldier `sid` when it's
## given. Returns the screen; it frees itself when closed.
static func open_over(host: Control, r: RunState, s, sid := -1) -> Control:
	var scr: Control = load("res://ui/gear/loadout_screen.gd").new()
	scr.name = "LoadoutOverlay"
	# Above everything on the host, lifted reward cards included, on a solid backdrop.
	scr.z_index = 10
	host.add_child(scr)
	scr.setup(r, s)
	(scr.get_child(0) as ColorRect).color.a = 1.0
	if sid != -1 and not r.get_soldier(sid).is_empty():
		scr.focus(sid)
	scr.closed.connect(scr.queue_free)
	return scr


## Shows soldier `sid`.
func focus(sid: int) -> void:
	_sid = sid
	_held = -1
	_preview_id = ""
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
	# The soldier between two slot columns: head, body, offhand and utility on the left, the
	# guns and what hangs on them on the right.
	var sil := HBoxContainer.new()
	sil.add_theme_constant_override("separation", 14)
	_col_l = VBoxContainer.new()
	_col_l.add_theme_constant_override("separation", 8)
	_col_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sil.add_child(_col_l)
	_figure = preload("res://ui/gear/soldier_silhouette.gd").new()
	sil.add_child(_figure)
	_col_r = VBoxContainer.new()
	_col_r.add_theme_constant_override("separation", 8)
	_col_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sil.add_child(_col_r)
	left.add_child(sil)
	left.add_child(UI.caps("Pockets", 13, UI.DIM))
	_pockets = HBoxContainer.new()
	_pockets.add_theme_constant_override("separation", 10)
	left.add_child(_pockets)
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
	st_head.add_child(UI.label("Click a stash item to equip it, or drag gear between a soldier and the stash. Anyone in the squad can take from it.", 13, UI.FAINT))
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
	for n in [_col_l, _col_r, _pockets, _tags, _stash_row, _build_box]:
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
	var feeding := _preview_tags()
	for slot in LEFT_SLOTS:
		_col_l.add_child(_slot_tile(r, slot, feeding))
	for slot in RIGHT_SLOTS:
		_col_r.add_child(_slot_tile(r, slot, feeding))
	_col_r.add_child(_graft_tile(r, "arm"))
	_col_l.add_child(_graft_tile(r, "legs"))
	_figure.setup(_lit_parts(r))
	var ps := Loadout.pockets(r)
	for i in ps.size():
		_pockets.add_child(_pocket_tile(ps[i]))
	_build_tags(r)
	_build_stash(r)
	_build_summary(r)


## Slot tiles on screen, in no particular order (the tests and the drop checks walk them).
func slot_tiles() -> Array:
	return (_col_l.get_children() + _col_r.get_children()).filter(func(c): return c is DropTile)


## Which body parts of the figure have something on them.
func _lit_parts(r: Dictionary) -> Dictionary:
	var out := {}
	for part in PARTS:
		out[part] = PARTS[part].any(func(slot): return Loadout.item_at(r, slot) != null)
	var grafts := Grafts.of(r)
	out["arms"] = out.arms or grafts.has("arm")
	out["legs"] = out.legs or grafts.has("legs")
	return out


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
		var vitals := UI.vitals(r)
		col.add_child(vitals)
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
		for n in vitals.get_children():
			if n.has_meta(Tips.META):
				n.mouse_filter = Control.MOUSE_FILTER_PASS
		_squad_bar.add_child(p)


# --- Tiles -----------------------------------------------------------------------------

## Tags the previewed item would change, so the slots feeding them can be outlined.
func _preview_tags() -> Array:
	return GearData.tags_of(_preview_id) if _preview_id != "" else []


func _slot_tile(r: Dictionary, slot: String, feeding: Array) -> Control:
	var it = Loadout.item_at(r, slot)
	var t := DropTile.new()
	t.custom_minimum_size = Vector2(0, 84)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var target_slot := _preview_id != "" and GearData.slots_for(GearData.slot_of(_preview_id)).has(slot)
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
		head.add_child(UI.caps(_rarity_text(it), 12, UI.rarity_color(rar)))
	v.add_child(head)
	if it == null:
		v.add_child(UI.caps("Empty", 20, UI.FAINT))
		if target_slot:
			v.add_child(UI.label("Drop to equip " + GearData.item_name(_preview_id), 13, UI.AMBER))
	else:
		v.add_child(UI.wrap(UI.caps(GearData.item_name(it.id), 20), 260))
		if target_slot:
			v.add_child(UI.label("Drop to swap. %s goes to the stash." % GearData.item_name(it.id), 13, UI.AMBER))
		var tags := HBoxContainer.new()
		tags.add_theme_constant_override("separation", 4)
		for tg in GearData.tags_of(it.id):
			tags.add_child(UI.tag_chip(tg))
		v.add_child(tags)
		if slot == "gun":
			v.add_child(UI.mag_row(Weapons.mag_for(it.id, str(r.kind)), 11.0))
			t.tooltip_text = "%s\nMagazine: %d rounds\n%s" % [GearData.item_name(it.id), Weapons.mag_for(it.id, str(r.kind)), GearData.desc(it.id, 1)]
		else:
			t.tooltip_text = "%s\nMk I: %s\nMk II: %s" % [GearData.item_name(it.id), GearData.desc(it.id, 1), GearData.desc(it.id, 2)]
		_tag_terms(t, r, GearData.tags_of(it.id))
	for n in v.find_children("*", "Control", true, false):
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(v)
	var editable := _can_edit(r)
	var sid: int = r.id
	if editable and it != null and slot != "gun":
		t.drag_data = {"from": "slot", "slot": slot, "soldier": sid, "id": it.id}
		t.drag_label = GearData.item_name(it.id)
		t.drag_sub = GearData.SLOT_NAMES[slot]
	t.can_drop = func(d) -> bool:
		return editable and d is Dictionary and d.get("from") == "stash" and GearData.slots_for(GearData.slot_of(d.id)).has(slot) \
			and _can_hold(r, str(d.id))
	t.dropped = func(d) -> void: _equip_from_stash(int(d.index))
	t.drop_hover = func(d, on: bool) -> void:
		if on and d is Dictionary and d.get("from") == "stash":
			_show_toast(_swap_text(r, str(d.id)))
	t.clicked = func() -> void:
		if editable and _held >= 0 and GearData.slots_for(GearData.slot_of(Loadout.stash(run)[_held].id)).has(slot) \
				and _can_hold(r, str(Loadout.stash(run)[_held].id)):
			_equip_from_stash(_held)
	t.drag_state = func(on: bool, d) -> void: _set_preview(d.get("id", "") if on and d is Dictionary and d.get("from") == "stash" else "")
	return t


## Rarity and mark for a tile header. Guns have no marks.
func _rarity_text(it: Dictionary) -> String:
	var name: String = GearData.RARITY_NAMES.get(GearData.rarity_of(it.id), "")
	return name if Weapons.is_item(it.id) else "%s · Mk %s" % [name, "II" if it.mk >= 2 else "I"]


## Can this soldier take `id` into their hands? Only melee classes are picky (see Weapons.can_carry).
func _can_hold(r: Dictionary, id: String) -> bool:
	return not Weapons.is_item(id) or Weapons.can_carry(str(r.get("kind", "")), id)


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
	var shown := BuildRead.visible_tags(str(r.kind), counts, Profile.tags_all_shown())
	for tag in changes:
		if not shown.has(tag):
			shown.append(tag)
	var strip := _build_strip(counts)
	strip.add_theme_constant_override("margin_top", 10)
	_tags.add_child(strip)
	for job in BuildRead.JOBS:
		var in_job: Array = BuildRead.JOB_TAGS[job].filter(func(t): return shown.has(t))
		if in_job.is_empty():
			continue
		_tags.add_child(_job_head(job))
		for tag in in_job:
			_add_tag_row(tag, counts, changes)
	if not protos.is_empty():
		var names := protos.map(func(id): return GearData.item_name(id))
		_tags.add_child(_bonus_line("Prototypes unlocked: " + ", ".join(names) + ". Rare rewards may become one.", UI.AMBER))


## Setup > Payoff / Sustain: the strongest tag the soldier has in each job, open where they have none.
func _build_strip(counts: Dictionary) -> Control:
	var leads := BuildRead.leads(counts)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	for i in BuildRead.JOBS.size():
		var job: String = BuildRead.JOBS[i]
		var tag: String = leads[job]
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", -2)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(UI.caps(job, 11, UI.FAINT))
		cell.add_child(UI.caps(tag if tag != "" else "Open", 18, GearData.tag_color(tag) if tag != "" else Color(UI.FAINT, 0.6)))
		Tips.term(cell, "job_" + job.to_lower())
		row.add_child(cell)
		if i < BuildRead.JOBS.size() - 1:
			var sep := UI.caps(">" if i == 0 else "/", 18, UI.FAINT)
			sep.size_flags_vertical = Control.SIZE_SHRINK_END
			row.add_child(sep)
	var box := MarginContainer.new()
	box.add_theme_constant_override("margin_bottom", 6)
	box.add_child(row)
	return box


func _job_head(job: String) -> Control:
	var l := UI.caps(job, 11, UI.FAINT)
	Tips.term(l, "job_" + job.to_lower())
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 6)
	m.add_child(l)
	return m


func _add_tag_row(tag: String, counts: Dictionary, changes: Dictionary) -> void:
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
	var cap := BuildRead.capstone_at()
	if cap > 0:
		h.add_child(_capstone_mark(tag, n >= cap))
	row.add_child(h)
	Tips.term(row, "tag_" + tag.to_lower(), {"count": n, "color": GearData.tag_color(tag)})
	_tags.add_child(row)
	if n >= GearData.SET_THRESHOLD and not ch.get("loses", false):
		_tags.add_child(_bonus_line("Set bonus on: " + GearData.TAG_INFO[tag].bonus, col))
	elif ch.get("unlocks", false):
		_tags.add_child(_bonus_line("Completes the set: " + GearData.TAG_INFO[tag].bonus, UI.AMBER))
	elif ch.get("loses", false):
		_tags.add_child(_bonus_line("Turns off: " + GearData.TAG_INFO[tag].bonus, UI.DANGER))
	if GearData.has_capstone(tag) and n >= GearData.CAPSTONE_THRESHOLD:
		var cap_info: Dictionary = GearData.TAG_INFO[tag]
		_tags.add_child(_bonus_line("Capstone on, %s: %s" % [cap_info.capstone_name, cap_info.capstone], col))


## A diamond after the pips: the capstone, lit when the soldier has enough of the tag.
func _capstone_mark(tag: String, on: bool) -> Control:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(10, 10)
	d.pivot_offset = Vector2(5, 5)
	d.rotation = PI / 4.0
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.color = GearData.tag_color(tag) if on else Color(UI.DIM, 0.35)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


## What the soldier's build does right now, and the next step toward a set bonus.
func _build_summary(r: Dictionary) -> void:
	var counts := GearTags.counts(r)
	var sets := GearTags.active_sets(counts)
	for t in sets:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.add_child(UI.tag_chip(t, "%s set" % t))
		h.add_child(UI.text(GearData.TAG_INFO[t].bonus, 14, UI.TEXT, 640))
		_build_box.add_child(h)
	for t in GearTags.active_capstones(counts):
		var cap: Dictionary = GearData.TAG_INFO[t]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.add_child(UI.tag_chip(t, "%s capstone" % t))
		h.add_child(UI.text("%s: %s" % [cap.capstone_name, cap.capstone], 14, UI.TEXT, 640))
		_build_box.add_child(h)
	var close: Array = GearTags.ranked(counts).filter(func(t): return counts[t] == GearData.SET_THRESHOLD - 1)
	for t in close:
		_build_box.add_child(UI.text("One more %s item switches on: %s" % [t, GearData.TAG_INFO[t].bonus], 14, GearData.tag_color(t), 640))
	if sets.is_empty() and close.is_empty():
		_build_box.add_child(UI.label("Stack 3 of one tag (gear, perks, awake mutations) to switch on its set bonus.", 14, UI.FAINT))
	var d: Array = run.modifiers.get("doctrines", [])
	if not d.is_empty():
		var names := d.map(func(id): return GearData.DOCTRINES.get(id, {}).get("name", id))
		_build_box.add_child(UI.label("Squad Doctrines: " + ", ".join(names), 14, UI.DIM))


## The body diagram and one line per slot: the part's name in its path colour, or open.
## An Arm or Legs graft as a slot of the same kind as the gear around it. Grafts are for life:
## they come from the hospital, the depot and nests, not from the stash.
func _graft_tile(r: Dictionary, slot: String) -> Control:
	var g := Grafts.of(r)
	var id: String = g.get(slot, "")
	var t := PanelContainer.new()
	t.custom_minimum_size = Vector2(0, 84)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_stylebox_override("panel", UI.box(UI.PANEL_SOFT, UI.BORDER, 1, 0, 14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_child(UI.label("%s GRAFT" % GraftData.SLOT_NAMES[slot].to_upper(), 11, UI.FAINT, "mono"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	if id != "":
		head.add_child(UI.caps("Bloom" if GraftData.is_bloom(id) else "Machine", 12, GraftFigure.path_color(id)))
	v.add_child(head)
	if id != "":
		v.add_child(UI.caps(GraftData.name_of(id), 20, GraftFigure.path_color(id)))
		var tip: String = GraftData.get_def(id).desc
		var floor_at := Grafts.floor_of(g)
		if GraftData.is_bloom(id) and floor_at > 0:
			tip += "\nInfection floor %d" % floor_at
		t.tooltip_text = "%s\n%s" % [GraftData.name_of(id), tip]
		Tips.term(t, "graft")
	else:
		v.add_child(UI.caps("Open", 20, UI.FAINT))
		var err := Grafts.eligible_error(run, r)
		t.tooltip_text = err if err != "" and err != "Every slot is grafted" else "A Machine Refit at the hospital or depot, or a Bloom part from nests."
		if err.begins_with("Grafts open") or err.begins_with("Needs Rank"):
			v.add_child(UI.label("Act %d, Rank %d" % [GraftData.FROM_ACT, GraftData.FROM_RANK], 13, UI.FAINT))
	for n in v.find_children("*", "Control", true, false):
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(v)
	return t


func _bonus_line(text: String, col: Color) -> Control:
	var l := UI.text(text, 13, col, 420)
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
			head.add_child(UI.caps(_rarity_text(it), 12, UI.rarity_color(rar)))
			v.add_child(head)
			v.add_child(UI.caps(GearData.item_name(it.id), 19))
			var tags := HBoxContainer.new()
			tags.add_theme_constant_override("separation", 4)
			for tg in GearData.tags_of(it.id):
				tags.add_child(UI.tag_chip(tg))
			v.add_child(tags)
			t.tooltip_text = "%s%s\n%s" % [GearData.item_name(it.id), "" if Weapons.is_item(it.id) else " (Mk %s)" % ("II" if it.mk >= 2 else "I"), GearData.desc(it.id, it.mk)]
			# The stash is shared: viewing a teammate's soldier you can still pick from it. A click
			# equips straight onto the soldier on screen (the old item swaps into the stash); from a
			# teammate's view it jumps to one of your own soldiers with the item held. A drag also works,
			# on your own soldiers only (switching would rebuild the screen under it).
			var mine := _editable_soldiers()
			if editable or not mine.is_empty():
				var idx := i
				var normal := UI.box(UI.HELD if held else UI.PANEL_SOFT, UI.AMBER if held else UI.BORDER, 2 if held else 1, 0, 10)
				var lit := UI.box(UI.HELD, UI.AMBER, 2, 0, 10)
				if editable:
					t.drag_data = {"from": "stash", "index": i, "id": it.id}
					t.drag_label = GearData.item_name(it.id)
					t.drag_sub = GearData.SLOT_NAMES[GearData.slot_of(it.id)]
				t.clicked = func() -> void:
					UI.play(self, "ui_click")
					if editable:
						_equip_from_stash(idx)
						return
					_sid = mine[0].id
					_held = idx
					_preview_id = st[idx].id
					_refresh()
				t.hovered = func(on: bool) -> void:
					t.add_theme_stylebox_override("panel", lit if on else normal)
					if _held == -1:
						_set_preview(it.id if on else "")
				t.drag_state = func(on: bool, d) -> void: _set_preview(it.id if on else "")
				var who: Dictionary = r if editable else run.get_soldier(mine[0].id)
				var card := {"kind": "gear", "id": it.id}
				Tips.compare(t, func() -> Dictionary: return GearCompare.compare(run, who, card), UI.player_color(who.owner),
					"Click to equip on %s." % UI.short_name(who))
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
		t.drop_hover = func(d, on: bool) -> void:
			if on and d is Dictionary and d.get("from") == "slot":
				_show_toast("%s goes to the stash." % GearData.item_name(str(d.id)))
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


## What dropping stash item `id` on `r` does, for the toast while you hover a slot.
func _swap_text(r: Dictionary, id: String) -> String:
	var pv := Loadout.preview_equip(r, id)
	match pv.mode:
		"replace":
			return "%s replaces %s, which goes to the stash." % [GearData.item_name(id), GearData.item_name(pv.old.id)]
		"upgrade":
			return "%s upgrades to Mk II." % GearData.item_name(id)
	return "Equip %s on %s." % [GearData.item_name(id), UI.short_name(r)]


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
	var drag_sub := ""
	var can_drop: Callable
	var dropped: Callable
	var clicked: Callable
	var hovered: Callable
	var drag_state: Callable
	var drop_hover: Callable   # (data, on): what dropping here would do, while something is dragged over it

	var _saved_box: StyleBox
	var _had_box := false
	var _marked := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		if drag_data != null or clicked.is_valid():
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void:
			if hovered.is_valid():
				hovered.call(true)
			_drag_hover(true))
		mouse_exited.connect(func() -> void:
			if hovered.is_valid():
				hovered.call(false)
			_drag_hover(false))
		# Tiles rebuilt mid-drag (the tag strip previews while you carry) pick the drag up here.
		if is_inside_tree() and get_viewport().gui_is_dragging():
			_mark_drag(get_viewport().gui_get_drag_data())

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed and clicked.is_valid():
			clicked.call()

	func _get_drag_data(_at: Vector2) -> Variant:
		if drag_data == null:
			return null
		# The card follows the cursor, tilted and lifted.
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UIS.box(UIS.HELD, UIS.AMBER, 2, 0, 10))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		if drag_sub != "":
			v.add_child(UIS.label(drag_sub.to_upper(), 11, UIS.AMBER, "mono"))
		v.add_child(UIS.caps(drag_label, 20))
		p.add_child(v)
		p.custom_minimum_size = Vector2(190, 0)
		p.rotation_degrees = -4
		p.pivot_offset = Vector2(20, 20)
		var holder := Control.new()
		holder.add_child(p)
		p.position = Vector2(-60, -24)
		set_drag_preview(holder)
		modulate.a = 0.4
		if drag_state.is_valid():
			drag_state.call(true, drag_data)
		return drag_data

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_BEGIN:
			_mark_drag(get_viewport().gui_get_drag_data())
		elif what == NOTIFICATION_DRAG_END:
			_unmark_drag()
			modulate.a = 1.0
			if drag_data != null and drag_state.is_valid() and is_inside_tree():
				drag_state.call(false, drag_data)

	## While something is dragged: the tile it came from is dimmed, tiles it can land on are
	## framed amber, and tiles that can't take it fade back.
	func _mark_drag(data: Variant) -> void:
		if _marked or data == null:
			return
		if drag_data != null and drag_data == data:
			modulate.a = 0.4
			return
		if not can_drop.is_valid():
			return
		_marked = true
		if can_drop.call(data):
			_had_box = has_theme_stylebox_override("panel")
			_saved_box = get_theme_stylebox("panel")
			add_theme_stylebox_override("panel", UIS.box(Color(UIS.AMBER, 0.10), UIS.AMBER, 2, 0, 10))
		else:
			modulate.a = 0.45

	func _unmark_drag() -> void:
		if not _marked:
			return
		_marked = false
		modulate.a = 1.0
		if _saved_box != null:
			if _had_box:
				add_theme_stylebox_override("panel", _saved_box)
			else:
				remove_theme_stylebox_override("panel")
			_saved_box = null

	func _drag_hover(on: bool) -> void:
		if not is_inside_tree() or not get_viewport().gui_is_dragging() or not _marked or _saved_box == null:
			return
		var data = get_viewport().gui_get_drag_data()
		add_theme_stylebox_override("panel", UIS.box(UIS.HELD if on else Color(UIS.AMBER, 0.10), UIS.AMBER, 3 if on else 2, 0, 10))
		if drop_hover.is_valid():
			drop_hover.call(data, on)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return can_drop.is_valid() and can_drop.call(data)

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if dropped.is_valid():
			dropped.call(data)
