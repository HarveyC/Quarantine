extends RefCounted
## The item compare, ARPG style: what a reward card (or depot buy) does to one soldier, laid
## out from a GearCompare.compare() result. The slot it lands in with the equipped piece and
## the offered one side by side, where the old piece goes, then the stats and tag counts that
## move (green better, red worse, gold when a set bonus switches on) and Prototypes it opens.
## `kit()` is the idle view: what the soldier has on them right now.
## Draws straight into a VBoxContainer with no frames of its own, so it sits in the reward
## screen's compare column or in a hover card (Tips.compare) alike. Mechanical terms carry
## both hover metas: a glossary card on a screen, a nested card inside a hover card.

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const Tips := preload("res://ui/tips/tips.gd")
const UI := preload("res://ui/gear/gear_ui.gd")

## Point sizes grow by this much in the reward screen's column (it is scaled down with the
## cards); hover cards draw at the base sizes.
static var _boost := 0

const GOOD := Styles.HP
const BAD := Styles.DANGER_TEXT
## Hover-card term for each swap's slot caption.
const SLOT_TERMS := {"perk": "perk", "mutation": "mutation", "graft": "graft", "consumable": "pocket",
	"cache": "supplies"}


static func build(box: VBoxContainer, d: Dictionary, inner: float, who_color := Styles.DIM, boost := 0) -> void:
	_boost = boost
	box.add_child(_head("Compare", d, who_color))
	var swaps: Array = d.get("swaps", [])
	if swaps.size() == 1:
		_swap(box, swaps[0], inner)
	else:
		for s in swaps:
			box.add_child(_swap_row(s, inner))
	var fates := _fates(d, inner)
	for f in fates:
		box.add_child(f)
	var stats: Array = d.get("stats", [])
	var tags: Array = d.get("tags", [])
	if not stats.is_empty():
		box.add_child(_rule())
		for r in stats:
			box.add_child(_stat_row(r))
	if not tags.is_empty() or not d.get("protos_on", []).is_empty() or not d.get("protos_off", []).is_empty():
		box.add_child(_rule())
		for t in tags:
			box.add_child(_tag_row(t))
			if t.unlocks:
				box.add_child(_note(GearData.TAG_INFO[t.tag].bonus, Styles.AMBER, inner, "set_bonus"))
		for id in d.get("protos_on", []):
			box.add_child(_line("plus", "Prototype unlocked · " + GearData.item_name(id), Styles.AMBER, "", inner))
		for id in d.get("protos_off", []):
			box.add_child(_line("minus", "Prototype closed · " + GearData.item_name(id), BAD, "", inner))
	if stats.is_empty() and tags.is_empty() and swaps.size() == 1 and swaps[0].kind in ["gear", "gun"]:
		box.add_child(_line("dot", "Stats and tags stay the same", Styles.MUTED, "", inner))


## Idle view: the gun in hand, the four gear slots, pockets and the tags building up.
static func kit(box: VBoxContainer, rec: Dictionary, inner: float, who_color := Styles.DIM, boost := 0) -> void:
	_boost = boost
	box.add_child(_head("Equipped", {"name": rec.get("name", ""), "kind": rec.get("kind", "")}, who_color))
	var gun := GearCompare.gun_side(Loadout.gun_id(rec))
	box.add_child(_kit_row("weapon", "Gun", gun, Loadout.gun(rec) != "", inner))
	for slot in GearData.SLOTS:
		var it = Loadout.item_at(rec, slot)
		box.add_child(_kit_row(slot, GearData.SLOT_NAMES[slot], GearCompare.gear_side(it.id, int(it.mk)) if it != null else {}, true, inner))
	var ps := Loadout.pockets(rec)
	var pock := Styles.hbox(8)
	pock.add_child(_icon("consumable", Styles.MUTED))
	var cap := Styles.caps("Pockets", _px(11), Styles.MUTED)
	cap.custom_minimum_size.x = 104 + _boost * 8
	pock.add_child(_termed(cap, "pocket"))
	var names: PackedStringArray = []
	for p in ps:
		if p != null:
			names.append("%s ×%d" % [GearData.item_name(p.id), int(p.charges)])
	var pl := Styles.label(", ".join(names) if not names.is_empty() else "Empty", _px(13), Styles.TEXT if not names.is_empty() else Styles.MUTED)
	pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pl.custom_minimum_size.x = inner - 140
	pock.add_child(pl)
	box.add_child(pock)
	var counts := GearTags.counts(rec)
	var ranked := GearTags.ranked(counts)
	if ranked.is_empty():
		return
	box.add_child(_rule())
	for t in ranked.slice(0, 4):
		box.add_child(_tag_row({"tag": t, "from": counts[t], "to": counts[t], "unlocks": false, "loses": false}))


# --- Pieces ------------------------------------------------------------------------------

## "COMPARE" (or "EQUIPPED") and whose kit it is.
static func _head(title: String, d: Dictionary, who_color: Color) -> Control:
	var h := Styles.hbox(8)
	h.add_child(Styles.caps(title, _px(12), Styles.MUTED))
	h.add_child(Styles.spacer())
	var cls: String = UnitData.SOLDIERS.get(str(d.get("kind", "")), {}).get("name", "")
	var who := Styles.caps(("%s · %s" % [d.get("name", ""), cls]) if cls != "" else str(d.get("name", "")), _px(12), who_color)
	h.add_child(who)
	return h


## One swap, side by side: the equipped piece (or the empty slot) and the offered one.
static func _swap(box: VBoxContainer, s: Dictionary, inner: float) -> void:
	var cap := Styles.hbox(8)
	cap.add_child(_icon(s.icon, Styles.DIM))
	var slot_cap := Styles.caps(s.slot_name, _px(12), Styles.DIM)
	if SLOT_TERMS.has(s.kind):
		_termed(slot_cap, SLOT_TERMS[s.kind])
	cap.add_child(slot_cap)
	box.add_child(cap)
	if s.kind in ["perk", "cache"]:
		box.add_child(_side(s.new, "Gains", Styles.AMBER, inner, s, false))
		return
	var row := Styles.hbox(10)
	var col_w := (inner - 30.0) / 2.0
	row.add_child(_side(s.old, "Now", Styles.MUTED, col_w, s, true))
	var arrow := _icon("arrow_right", Styles.AMBER, 16)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(arrow)
	row.add_child(_side(s.new, "Offered" if s.fate != "upgrade" else "Upgraded", Styles.AMBER, col_w, s, false))
	box.add_child(row)


## One column of a swap: caption, name in its rarity colour, rarity and Mk, tags, effect.
static func _side(side: Dictionary, caption: String, cap_col: Color, w: float, s: Dictionary, old: bool) -> Control:
	var v := Styles.vbox(4)
	v.custom_minimum_size.x = w
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	v.add_child(Styles.caps(caption, _px(10), cap_col))
	if side.is_empty():
		var empty := "Open" if s.kind == "graft" else ("None" if s.kind in ["mutation", "consumable"] else "Empty")
		v.add_child(Styles.caps(empty, _px(15), Styles.MUTED))
		return v
	var rar := str(side.get("rarity", ""))
	var col := _side_color(s.kind, rar)
	if old:
		col = col.lerp(Styles.MUTED, 0.35)
	var nm := Styles.caps(side.name, _px(15), col)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size.x = w
	v.add_child(nm)
	var meta := _meta_text(s.kind, side)
	if meta != "":
		var ml := Styles.caps(meta, _px(10), col.darkened(0.1))
		if side.has("mk") and int(side.mk) >= 2:
			_termed(ml, "mk2")
		v.add_child(ml)
	var tags: Array = side.get("tags", [])
	if not tags.is_empty():
		var th := Styles.hbox(2)
		for t in tags:
			if str(t) != "":
				th.add_child(_termed(UI.tag_chip(str(t), "", old), "tag_" + str(t).to_lower()))
		v.add_child(th)
	var desc := Styles.label(str(side.get("desc", "")), _px(12), Styles.DIM if old else Styles.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = w
	if desc.text != "":
		v.add_child(desc)
	return v


## A compact swap line for orders that bundle several: slot icon, old, arrow, new.
static func _swap_row(s: Dictionary, inner: float) -> Control:
	var h := Styles.hbox(8)
	h.add_child(_icon(s.icon, Styles.DIM))
	var old_name: String = s.old.get("name", "Empty") if not s.old.is_empty() else "Empty"
	var ol := Styles.label(old_name, _px(13), Styles.MUTED)
	ol.custom_minimum_size.x = inner * 0.36
	ol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(ol)
	var arrow := _icon("arrow_right", Styles.AMBER, 12)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(arrow)
	var nl := Styles.bold(s.new.get("name", ""), _px(13), _side_color(s.kind, str(s.new.get("rarity", ""))))
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nl)
	return h


## Where the replaced piece goes, one line per swap that has something to say.
static func _fates(d: Dictionary, inner: float) -> Array:
	var out: Array = []
	var st: Array = d.get("stash", [0, 0])
	var stash_txt := "%d/%d" % [st[1], GearData.STASH_SIZE]
	for s in d.get("swaps", []):
		var old: String = s.old.get("name", "") if not s.old.is_empty() else ""
		match str(s.fate):
			"fill":
				out.append(_line("plus", "Fills the empty slot", Styles.DIM, "", inner))
			"stash":
				out.append(_line("loadout", "%s goes to the stash · %s" % [old, stash_txt], Styles.DIM, "stash", inner))
			"scrap":
				out.append(_line("supplies", "Stash full: %s is scrapped for +%d Supplies" % [old, Loadout.SCRAP_SUPPLIES], BAD, "stash", inner))
			"upgrade":
				out.append(_line("plus", "Merges into Mk II. No slot used", Styles.AMBER, "mk2", inner))
			"copy_stash":
				out.append(_line("loadout", "Already Mk II: this copy goes to the stash · %s" % stash_txt, Styles.DIM, "stash", inner))
			"copy_scrap":
				out.append(_line("supplies", "Already Mk II, stash full: scrapped for +%d Supplies" % Loadout.SCRAP_SUPPLIES, BAD, "stash", inner))
			"spare":
				out.append(_line("weapon", "%s stays in the kit as a spare" % old, Styles.DIM, "", inner))
			"owned":
				out.append(_line("check", "Already has it", Styles.MUTED, "", inner))
			"lost":
				out.append(_line("close", "%s is removed for good" % old, BAD, "mutation", inner))
			"stack":
				out.append(_line("plus", "Stacks: ×%d → ×%d" % [int(s.old.get("charges", 0)), int(s.new.get("charges", 0))], Styles.DIM, "pocket"))
			"full":
				out.append(_line("close", "Pockets full: no room for it", BAD, "pocket", inner))
	return out


## Stat, old value, arrow, new value, and the change in green (better) or red (worse).
static func _stat_row(r: Dictionary) -> Control:
	var h := Styles.hbox(8)
	var col := GOOD if r.better else BAD
	h.add_child(_icon(r.icon, Styles.DIM, 14))
	var nm := Styles.caps(r.name, _px(12), Styles.TEXT)
	if str(r.get("term", "")) != "":
		_termed(nm, r.term)
	h.add_child(nm)
	h.add_child(Styles.spacer())
	h.add_child(Styles.mono(_val(r.key, r.from), _px(13), Styles.MUTED))
	var arrow := _icon("arrow_right", col, 11)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(arrow)
	var to := Styles.mono(_val(r.key, r.to), _px(13), Styles.TEXT)
	to.custom_minimum_size.x = 44
	h.add_child(to)
	var dl := Styles.mono(_delta(r.from, r.to), _px(13), col)
	dl.custom_minimum_size.x = 40
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(dl)
	return h


## Tag, count (or old → new), three set pips, and SET ON / SET OFF when the bonus flips.
static func _tag_row(t: Dictionary) -> Control:
	var h := Styles.hbox(8)
	var tc := GearData.tag_color(t.tag)
	var dot := ColorRect.new()
	dot.color = tc
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dot)
	var nm := Styles.caps(t.tag, _px(12), tc)
	nm.custom_minimum_size.x = 84
	h.add_child(_termed(nm, "tag_" + str(t.tag).to_lower()))
	var moved: bool = t.from != t.to
	var num := Styles.mono("%d → %d" % [t.from, t.to] if moved else str(t.to), _px(13),
		(Styles.AMBER if t.to > t.from else BAD) if moved else Styles.TEXT)
	num.custom_minimum_size.x = 52
	h.add_child(num)
	h.add_child(Styles.spacer())
	if t.unlocks or t.loses:
		var badge := Styles.caps("Set on" if t.unlocks else "Set off", _px(11), Styles.AMBER if t.unlocks else BAD)
		h.add_child(_termed(badge, "set_bonus"))
	elif t.to >= GearData.SET_THRESHOLD:
		h.add_child(_termed(Styles.caps("Set", _px(11), tc), "set_bonus"))
	var pips := UI.pips(t.tag, t.from, t.to if moved else -1)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pips)
	return h


static func _kit_row(icon: String, cap_text: String, side: Dictionary, colored: bool, inner: float) -> Control:
	var h := Styles.hbox(8)
	h.add_child(_icon(icon, Styles.MUTED))
	var cap := Styles.caps(cap_text, _px(11), Styles.MUTED)
	cap.custom_minimum_size.x = 104 + _boost * 8
	h.add_child(cap)
	if side.is_empty():
		h.add_child(Styles.caps("Empty", _px(13), Styles.MUTED))
		return h
	var rar := str(side.get("rarity", ""))
	var nm := Styles.bold(side.name + (" II" if int(side.get("mk", 1)) >= 2 else ""), _px(14),
		UI.rarity_color(rar) if colored and rar != "" else Styles.TEXT)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.custom_minimum_size.x = inner - 140
	nm.tooltip_text = str(side.get("desc", ""))
	nm.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(nm)
	for t in side.get("tags", []):
		if str(t) != "":
			var dot := ColorRect.new()
			dot.color = GearData.tag_color(str(t))
			dot.custom_minimum_size = Vector2(8, 8)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(dot)
	return h


## An icon and one line of rules text, hoverable for `term` when given.
static func _line(icon: String, text: String, col: Color, term: String, inner := 0.0) -> Control:
	var h := Styles.hbox(8)
	var ic := _icon(icon, col, 14)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var l := Styles.bold(text, _px(13), col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if inner > 0:
		l.custom_minimum_size.x = inner - 24
	h.add_child(l)
	if term != "":
		_termed(h, term)
	return h


## A set bonus's text under its tag row, indented to the tag name.
static func _note(text: String, col: Color, inner: float, term: String) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Styles.label(text, _px(12), col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = inner - 16
	m.add_child(l)
	_termed(m, term)
	return m


static func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Styles.BORDER_SOFT
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _icon(id: String, col: Color, px := 15) -> Control:
	var ic := W.Icon.new(id, col, px, 1.7)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


## Makes `c` open the term's card: on a screen (Tips.term) and inside a hover card (a link).
static func _termed(c: Control, key: String) -> Control:
	if not Glossary.has(key):
		return c
	Tips.term(c, key)
	c.set_meta(Tips.META_TERM, key)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.mouse_default_cursor_shape = Control.CURSOR_HELP
	for n in c.find_children("*", "Control", true, false):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func _px(n: int) -> int:
	return n + _boost


static func _side_color(kind: String, rar: String) -> Color:
	match kind:
		"mutation":
			return Styles.TEAL
		"graft":
			return Styles.TEAL if rar == "bloom" else Color("#9fb4c8")
		"perk":
			return Styles.HP
		"consumable", "cache":
			return Styles.TEXT
	return UI.rarity_color(rar) if rar != "" else Styles.TEXT


static func _meta_text(kind: String, side: Dictionary) -> String:
	var rar := str(side.get("rarity", ""))
	match kind:
		"gear":
			return "%s · Mk %s" % [GearData.RARITY_NAMES.get(rar, rar.capitalize()), "II" if int(side.get("mk", 1)) >= 2 else "I"]
		"gun":
			return GearData.RARITY_NAMES.get(rar, "Signature") if rar != "" else "Signature"
		"graft":
			return "Bloom" if rar == "bloom" else "Machine"
		"consumable":
			return "×%d" % int(side.get("charges", 0)) if int(side.get("charges", 0)) > 0 else ""
	return rar.capitalize()


static func _val(key: String, v) -> String:
	if v is Vector2i:
		return "%d-%d" % [v.x, v.y]
	if key == "crit":
		return "%d%%" % int(v)
	return str(v)


static func _delta(a, b) -> String:
	var n: int = (b.x - a.x) if a is Vector2i else int(b) - int(a)
	if a is Vector2i and b.y - a.y != n:
		n = b.y - a.y
	return ("+%d" % n) if n > 0 else ("−%d" % -n)
