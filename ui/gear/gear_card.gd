extends PanelContainer
## One reward card (gear, Prototype, alternate gun, perk, mutation, Bloom graft, consumable,
## cache, or a run-start deployment order bundling several of those). Shows the slot,
## rarity and Mk, the tags, the effect, the threshold preview (a tag about to reach 3 glows
## gold with the bonus it switches on), and what it replaces. Hover lifts it; selected cards
## get an amber frame; Prototypes get a shifting multicolour frame.

signal pressed

const Tips := preload("res://ui/tips/tips.gd")
const UI := preload("res://ui/gear/gear_ui.gd")
const GraftFigure := preload("res://ui/graft_figure.gd")
const IconArt := preload("res://ui/icon_art.gd")
const W := 330
const H := 470

var card: Dictionary
var record: Dictionary
var selected := false
var _hover := false
var _sb: StyleBoxFlat
var _t := 0.0
var _art_at := 99  # child index to put the art panel at (after the effect text)


func setup(c: Dictionary, rec: Dictionary, index: int) -> void:
	card = c
	record = rec
	custom_minimum_size = Vector2(W, H)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pivot_offset = Vector2(W, H) / 2
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_sb = UI.box(UI.PANEL, UI.BORDER, 1, 0, 20)
	add_theme_stylebox_override("panel", _sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	match str(c.get("kind", "gear")):
		"gear": _build_gear(v)
		"gun": _build_gun(v)
		"perk", "mutation": _build_power(v)
		"consumable": _build_consumable(v)
		"cache": _build_cache(v)
		"order": _build_order(v)
		"graft": _build_graft(v)
	var art: Control
	if str(c.get("kind", "")) == "graft":
		# The soldier's body diagram, the offered slot pulsing.
		var fig := GraftFigure.new()
		fig.setup(Grafts.of(rec), str(c.id))
		art = fig
	else:
		art = Art.new()
		art.kind = _art_kind()
		art.texture = IconArt.item(str(c.get("id", "")))
		art.color = _art_color()
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.custom_minimum_size = Vector2(0, 70)
	v.add_child(art)
	v.move_child(art, mini(_art_at, v.get_child_count() - 1))
	var key := UI.mono("%d" % (index + 1), 12, UI.FAINT)
	key.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(key)
	for n in v.get_children():
		if n is Control:
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Parts with a hover card (tag chips, set previews, Mk II, ...) still take the pointer;
	# PASS hands their clicks on to the card.
	for n in v.find_children("*", "Control", true, false):
		if n.has_meta(Tips.META):
			(n as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(func() -> void:
		_hover = true
		UI.play(self, "ui_hover")
		_refresh())
	mouse_exited.connect(func() -> void:
		_hover = false
		_refresh())
	_refresh()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()


func set_selected(on: bool) -> void:
	selected = on
	_refresh()


func _refresh() -> void:
	var lift := 1.04 if selected else (1.02 if _hover else 1.0)
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(lift, lift), 0.18)
	var proto: bool = card.get("rarity", "") == "prototype"
	_sb.set_border_width_all(3 if selected or proto else (2 if _hover else 1))
	if not proto:
		_sb.border_color = UI.AMBER if selected else (UI.BORDER_HI if _hover else UI.BORDER)
	_sb.shadow_size = 24 if selected else (10 if _hover else 0)
	_sb.shadow_color = Color(UI.AMBER, 0.18) if selected else Color(0, 0, 0, 0.6)
	z_index = 2 if selected else (1 if _hover else 0)


func _process(delta: float) -> void:
	if card.get("rarity", "") != "prototype":
		return
	_t += delta * 0.6
	var n := UI.PROTO_COLORS.size()
	var i := int(_t) % n
	_sb.border_color = UI.PROTO_COLORS[i].lerp(UI.PROTO_COLORS[(i + 1) % n], fmod(_t, 1.0))


func _row(v: Container, left: Control, right: Control) -> void:
	var h := HBoxContainer.new()
	h.add_child(left)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	h.add_child(right)
	v.add_child(h)


func _build_gear(v: VBoxContainer) -> void:
	var id: String = card.id
	var item := GearData.get_item(id)
	var pv := Loadout.preview_equip(record, id)
	var mk := 2 if pv.mode == "upgrade" or item.rarity == "prototype" else 1
	var rar := UI.rarity_color(item.rarity)
	var rar_text := "%s · %s" % [GearData.RARITY_NAMES[item.rarity], "Upgrade" if pv.mode == "upgrade" else "Mk %s" % ("II" if mk == 2 else "I")]
	_row(v, UI.label(GearData.SLOT_NAMES[item.slot].to_upper(), 12, UI.FAINT, "mono"), UI.caps(rar_text, 13, rar))
	v.add_child(UI.wrap(UI.caps(item.name, 36), W - 40))
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	for t in item.tags:
		tags.add_child(UI.tag_chip(t))
	v.add_child(tags)
	v.add_child(UI.text(GearData.desc(id, mk), 15, UI.COPY, W - 40))
	_art_at = v.get_child_count()
	# Threshold preview / upgrade box.
	if pv.mode == "upgrade":
		var b := _boxed(v, rar)
		var h := HBoxContainer.new()
		h.add_child(UI.caps("Mk I  →  Mk II", 20, rar))
		Tips.term(h, "mk2")
		b.add_child(h)
		b.add_child(UI.text(GearData.desc(id, 2), 14, UI.TEXT, W - 70))
		v.add_child(UI.label("Duplicate of an item %s owns. No slot used." % UI.short_name(record), 13, UI.FAINT))
	elif pv.mode == "stash":
		v.add_child(UI.text("Already at Mk II: this copy goes to the stash.", 13, UI.FAINT, W - 40))
	else:
		for p in GearTags.preview(record, id):
			if p.to <= p.from:
				continue
			var hot: bool = p.unlocks
			var b := _boxed(v, UI.AMBER if hot else GearData.tag_color(p.tag).darkened(0.4))
			var h := HBoxContainer.new()
			h.add_child(UI.caps("%s %d → %d" % [p.tag, p.from, p.to], 16, GearData.tag_color(p.tag)))
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(sp)
			h.add_child(UI.pips(p.tag, p.from, p.to))
			Tips.term(h, "set_bonus", {"count": p.to, "color": GearData.tag_color(p.tag)})
			b.add_child(h)
			if hot:
				b.add_child(UI.text("Set bonus: " + GearData.TAG_INFO[p.tag].bonus, 14, UI.AMBER, W - 70, "bold"))
		if item.rarity == "prototype":
			v.add_child(UI.label("Unlocked by %s + %s at 2" % [item.tags[0], item.tags[1]], 13, UI.AMBER))
		if pv.mode == "replace":
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 8)
			h.add_child(UI.label("vs %s:" % GearData.item_name(pv.old.id), 13, UI.FAINT))
			var diff := UI.tag_diff(id, pv.old.id)
			h.add_child(UI.label(diff, 13, UI.GOOD if not diff.contains("−") else UI.DANGER))
			v.add_child(h)
			for p in GearTags.preview(record, id):
				if p.loses:
					v.add_child(UI.text("Turns off the %s set bonus" % p.tag, 13, UI.DANGER, W - 40, "bold"))
		elif pv.mode == "equip":
			v.add_child(UI.label("Fills the empty %s slot" % GearData.SLOT_NAMES[item.slot].to_lower(), 13, UI.FAINT))


func _build_gun(v: VBoxContainer) -> void:
	var g := Weapons.get_gun(card.id)
	_row(v, UI.label("GUN", 12, UI.FAINT, "mono"), UI.caps(GearData.RARITY_NAMES[g.rarity], 13, UI.rarity_color(g.rarity)))
	v.add_child(UI.wrap(UI.caps(g.name, 36), W - 40))
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	if g.has("tag"):
		tags.add_child(UI.tag_chip(g.tag))
	v.add_child(tags)
	v.add_child(UI.mag_row(Weapons.mag_for(card.id, str(record.get("kind", "")))))
	v.add_child(UI.text(g.desc, 15, UI.COPY, W - 40))
	_art_at = v.get_child_count()
	for p in GearTags.preview_gun(record, card.id):
		if p.to <= p.from:
			continue
		var b := _boxed(v, UI.AMBER if p.unlocks else GearData.tag_color(p.tag).darkened(0.4))
		var h := HBoxContainer.new()
		h.add_child(UI.caps("%s %d → %d" % [p.tag, p.from, p.to], 16, GearData.tag_color(p.tag)))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(sp)
		h.add_child(UI.pips(p.tag, p.from, p.to))
		Tips.term(h, "set_bonus", {"count": p.to, "color": GearData.tag_color(p.tag)})
		b.add_child(h)
		if p.unlocks:
			b.add_child(UI.text("Set bonus: " + GearData.TAG_INFO[p.tag].bonus, 14, UI.AMBER, W - 70, "bold"))
	var now := Weapons.gun_name(Loadout.gun_id(record))
	v.add_child(UI.text("Replaces the %s in hand. You keep it, and can swap back from the loadout." % now, 13, UI.FAINT, W - 40))


func _build_power(v: VBoxContainer) -> void:
	var is_mut: bool = card.kind == "mutation"
	var col := UI.TEAL if is_mut else UI.GOOD
	# The left caption already says Mutation / Class perk; the right one adds only the tier.
	var sub := "Mutation" if is_mut else "Perk"
	if card.has("tier"):
		sub = Infection.tier_name(int(card.tier))
	elif card.has("rarity"):
		sub = str(card.rarity).capitalize()
	var sub_label := UI.caps(sub, 13, col)
	Tips.term(sub_label, "mutation" if is_mut else "perk", {"value": Infection.THRESHOLDS[clampi(int(card.get("tier", 1)), 0, 4)]} if is_mut else {})
	_row(v, UI.label(("MUTATION" if is_mut else "CLASS PERK"), 12, UI.FAINT, "mono"), sub_label)
	v.add_child(UI.wrap(UI.caps(str(card.get("name", card.get("id", "?"))), 36), W - 40))
	var t := GearTags.normalize(str(card.get("tag", "")))
	if t != "":
		var tags := HBoxContainer.new()
		tags.add_child(UI.tag_chip(t))
		v.add_child(tags)
	v.add_child(UI.text(str(card.get("desc", "")), 15, UI.COPY, W - 40))
	_art_at = v.get_child_count()
	if t != "":
		var before: int = GearTags.counts(record).get(t, 0)
		if before + 1 == GearData.SET_THRESHOLD:
			var b := _boxed(v, UI.AMBER)
			b.add_child(UI.caps("%s %d → %d" % [t, before, before + 1], 16, GearData.tag_color(t)))
			b.add_child(UI.text("Set bonus: " + GearData.TAG_INFO[t].bonus, 14, UI.AMBER, W - 70, "bold"))
	if is_mut:
		v.add_child(UI.text("Grafting adds Infection. Works only while Infection is at its tier.", 13, UI.TEAL, W - 40))


## Bloom graft: the slot it takes, what it does, and what it costs for good.
func _build_graft(v: VBoxContainer) -> void:
	var slot: String = GraftData.SLOT_NAMES.get(str(card.get("slot", "")), "")
	_row(v, UI.label("BLOOM GRAFT", 12, UI.FAINT, "mono"), UI.caps(slot, 13, UI.TEAL))
	v.add_child(UI.wrap(UI.caps(str(card.get("name", "")), 36), W - 40))
	var t := GearTags.normalize(str(card.get("tag", "")))
	if t != "":
		var tags := HBoxContainer.new()
		tags.add_child(UI.tag_chip(t))
		v.add_child(tags)
	v.add_child(UI.text(str(card.get("desc", "")), 15, UI.COPY, W - 40))
	_art_at = v.get_child_count()
	v.add_child(UI.text("+%d Infection. For good: Infection can't drop below %d per Bloom part, even with Serum." % [
		int(card.get("infection", GraftData.BLOOM_INFECTION)), GraftData.FLOOR_PER_PART], 13, UI.TEAL, W - 40))


func _build_consumable(v: VBoxContainer) -> void:
	_row(v, Tips.term(UI.label("POCKET", 12, UI.FAINT, "mono"), "pocket"), UI.caps("Consumable ×%d" % int(card.get("charges", 2)), 13, UI.DIM))
	v.add_child(UI.caps(GearData.item_name(card.id), 36))
	v.add_child(UI.text(GearData.desc(card.id), 15, UI.COPY, W - 40))
	if not Loadout.can_add_consumable(record, card.id):
		v.add_child(UI.label("Pockets are full", 13, UI.DANGER, "bold"))


func _build_cache(v: VBoxContainer) -> void:
	_row(v, UI.label("CACHE", 12, UI.FAINT, "mono"), UI.caps("Squad", 13, UI.DIM))
	v.add_child(UI.caps("Supply cache", 36))
	v.add_child(UI.mono("+%d" % int(card.get("supplies", GearRun.CACHE_SUPPLIES)), 40, UI.AMBER))
	v.add_child(Tips.term(UI.label("Supplies to the squad, for the depot and the hospital.", 15, UI.COPY), "supplies"))


## Deployment order: insignia, what's in the bundle (one row per item), and the Infection the
## soldier deploys at on a tier bar.
func _build_order(v: VBoxContainer) -> void:
	var inf := int(card.get("infection", 0))
	var risk := Tips.term(UI.caps("+%d Infection" % inf, 13, UI.TEAL if inf > 0 else UI.DIM), "infection")
	_row(v, UI.label("ORDER", 12, UI.FAINT, "mono"), risk)
	v.add_child(UI.wrap(UI.caps(str(card.get("name", "")), 34), W - 40))
	v.add_child(UI.text(str(card.get("desc", "")), 15, UI.COPY, W - 40))
	_art_at = v.get_child_count()
	for c in card.get("contents", []):
		v.add_child(_content_row(c))
	v.add_child(InfectionBar.new(inf))


## One line of an order's bundle: a rarity stripe, what it is and its tags.
func _content_row(c: Dictionary) -> Control:
	var kind := str(c.get("kind", "gear"))
	var col := UI.TEAL if kind == "mutation" else UI.rarity_color(str(c.get("rarity", "common")))
	var nm := ""
	var what := ""
	var desc := ""
	var tags: Array = []
	match kind:
		"gear":
			var item := GearData.get_item(c.id)
			nm = item.name
			what = "%s · %s" % [GearData.RARITY_NAMES[item.rarity], GearData.SLOT_NAMES[item.slot]]
			desc = GearData.desc(c.id, 2 if item.rarity == "prototype" else 1)
			tags = item.tags
		"gun":
			var g := Weapons.get_gun(c.id)
			col = UI.rarity_color(g.rarity)
			nm = g.name
			what = "%s · Gun" % GearData.RARITY_NAMES[g.rarity]
			desc = g.desc
			tags = [g.tag] if g.has("tag") else []
		"mutation":
			nm = str(c.get("name", c.id))
			what = "Mutation · %s" % Infection.tier_name(int(c.get("tier", 1)))
			desc = str(c.get("desc", ""))
			tags = [GearTags.normalize(str(c.get("tag", "")))]
	# No box: the colour stripe alone ties the block together.
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var stripe := ColorRect.new()
	stripe.color = col
	stripe.custom_minimum_size = Vector2(3, 0)
	h.add_child(stripe)
	var col_box := VBoxContainer.new()
	col_box.add_theme_constant_override("separation", 3)
	col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_box.add_child(UI.caps(what, 11, col))
	col_box.add_child(UI.wrap(UI.caps(nm, 19), W - 80))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 4)
	for t in tags:
		if str(t) != "":
			chips.add_child(UI.tag_chip(str(t)))
	if chips.get_child_count() > 0:
		col_box.add_child(chips)
	col_box.add_child(UI.text(desc, 13, UI.COPY, W - 80))
	h.add_child(col_box)
	p.add_child(h)
	return p


## A callout inside the card (an upgrade, a set step): a colour stripe on its left, no box.
func _boxed(v: VBoxContainer, col: Color) -> VBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var stripe := ColorRect.new()
	stripe.color = col
	stripe.custom_minimum_size = Vector2(3, 0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(stripe)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(inner)
	v.add_child(h)
	return inner


## Short label for the Take button.
func title() -> String:
	match str(card.get("kind", "gear")):
		"gear":
			return GearData.item_name(card.id)
		"consumable":
			return GearData.item_name(card.id)
		"gun":
			return Weapons.gun_name(card.id)
		"cache":
			return "+%d Supplies" % int(card.get("supplies", 25))
		"order":
			return str(card.get("name", "order"))
	return str(card.get("name", card.get("id", "card")))


func _art_kind() -> String:
	match str(card.get("kind", "gear")):
		"gear":
			return GearData.slot_of(card.id)
	return str(card.get("kind", "gear"))


func _art_color() -> Color:
	match str(card.get("kind", "gear")):
		"gear":
			return UI.rarity_color(GearData.rarity_of(card.id))
		"gun":
			return UI.rarity_color(Weapons.rarity_of(card.id))
		"mutation":
			return UI.TEAL
		"perk":
			return UI.GOOD
		"cache":
			return UI.AMBER
		"order":
			return UI.TEAL if int(card.get("infection", 0)) > 0 else UI.AMBER
	return UI.DIM


## Line-art glyph for the card's slot or kind.
class Art:
	extends Control

	var kind := "weapon"
	var color := Color.WHITE
	var texture: Texture2D  # generated art for this item; null keeps the line glyph

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		# The glyph straight on the card: no framed grid box round it.
		var c := size / 2
		var s := minf(size.y * 0.36, 60.0)
		var w := 2.0
		if texture != null:
			var box := Vector2(minf(size.x - 24.0, 280.0), minf(size.y, 150.0))
			var k := minf(box.x / texture.get_width(), box.y / texture.get_height())
			var sz := Vector2(texture.get_size()) * k
			draw_texture_rect(texture, Rect2(c - sz * 0.5, sz), false, color)
			return
		match kind:
			"weapon":
				draw_arc(c, s, 0, TAU, 48, color, w, true)
				draw_arc(c, s * 0.35, 0, TAU, 24, color, w, true)
				for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(c + d * s * 0.55, c + d * s * 1.3, color, w, true)
			"ammo":
				for i in 3:
					var bx := c.x + (i - 1) * s * 0.75
					var top := c.y - s * 0.8
					draw_polyline(PackedVector2Array([Vector2(bx - s * 0.22, c.y + s), Vector2(bx - s * 0.22, top + s * 0.3),
						Vector2(bx, top), Vector2(bx + s * 0.22, top + s * 0.3), Vector2(bx + s * 0.22, c.y + s),
						Vector2(bx - s * 0.22, c.y + s)]), color, w, true)
			"armor":
				draw_polyline(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.85, -s * 0.65), c + Vector2(s * 0.85, 0),
					c + Vector2(0, s), c + Vector2(-s * 0.85, 0), c + Vector2(-s * 0.85, -s * 0.65), c + Vector2(0, -s)]), color, w, true)
			"gadget", "consumable":
				var pts := PackedVector2Array()
				for i in 7:
					pts.append(c + Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * s)
				draw_polyline(pts, color, w, true)
				draw_polyline(PackedVector2Array([c + Vector2(s * 0.1, -s * 0.6), c + Vector2(-s * 0.25, s * 0.05),
					c + Vector2(s * 0.2, s * 0.05), c + Vector2(-s * 0.1, s * 0.6)]), color, w, true)
			"mutation":
				draw_arc(c + Vector2(0, -s * 0.45), s * 0.4, 0, TAU, 32, color, w, true)
				draw_arc(c + Vector2(-s * 0.5, s * 0.35), s * 0.4, 0, TAU, 32, color, w, true)
				draw_arc(c + Vector2(s * 0.5, s * 0.35), s * 0.4, 0, TAU, 32, color, w, true)
			"perk":
				for i in 3:
					var yy := c.y - s * 0.6 + i * s * 0.55
					draw_polyline(PackedVector2Array([Vector2(c.x - s * 0.7, yy + s * 0.4), Vector2(c.x, yy), Vector2(c.x + s * 0.7, yy + s * 0.4)]), color, w, true)
			"gun":
				var u := s * 0.5
				draw_polyline(PackedVector2Array([c + Vector2(-3.4, -0.3) * u, c + Vector2(2.6, -0.3) * u, c + Vector2(2.6, 0.15) * u,
					c + Vector2(-0.2, 0.15) * u, c + Vector2(-0.6, 1.1) * u, c + Vector2(-1.1, 1.1) * u, c + Vector2(-0.9, 0.15) * u,
					c + Vector2(-1.9, 0.15) * u, c + Vector2(-3.4, 0.7) * u, c + Vector2(-3.4, -0.3) * u]), color, w, true)
				draw_line(c + Vector2(2.6, -0.1) * u, c + Vector2(3.6, -0.1) * u, color, w, true)
				draw_rect(Rect2(c + Vector2(0.2, 0.15) * u, Vector2(0.45, 0.9) * u), color, false, w)
			"order":
				# Drop insignia: a ring with a descending chevron stack.
				draw_arc(c, s, 0, TAU, 48, color, w, true)
				for i in 3:
					var yy := c.y - s * 0.5 + i * s * 0.38
					draw_polyline(PackedVector2Array([Vector2(c.x - s * 0.55, yy), Vector2(c.x, yy + s * 0.32), Vector2(c.x + s * 0.55, yy)]), color, w, true)
			"cache":
				draw_rect(Rect2(c - Vector2(s, s * 0.7), Vector2(s * 2, s * 1.4)), color, false, w)
				draw_line(c + Vector2(-s, -s * 0.2), c + Vector2(s, -s * 0.2), color, w, true)
				draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.35), Vector2(s * 0.4, s * 0.3)), color, false, w)


## Where an order leaves the soldier's Infection: a 0-100 bar with the tier marks, teal fill to
## the starting value, and a caption with the tier.
class InfectionBar:
	extends VBoxContainer

	var value := 0

	func _init(v: int) -> void:
		value = v
		add_theme_constant_override("separation", 4)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var head := HBoxContainer.new()
		var lbl := UI.label("STARTING INFECTION", 11, UI.FAINT, "mono")
		head.add_child(lbl)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(sp)
		var t := Infection.tier(value)
		var txt := "%d · %s" % [value, Infection.tier_name(t)]
		head.add_child(UI.mono(txt, 13, UI.TEAL if value > 0 else UI.DIM))
		Tips.term(head, "infection")
		add_child(head)
		var bar := Bar.new()
		bar.value = value
		bar.custom_minimum_size = Vector2(0, 10)
		add_child(bar)


	class Bar:
		extends Control

		var value := 0

		func _draw() -> void:
			var r := Rect2(Vector2.ZERO, size)
			draw_rect(r, Color(1, 1, 1, 0.04))
			if value > 0:
				draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * value / float(Infection.MAX), size.y)), UI.TEAL)
			for th in [Infection.EXPOSED_AT, Infection.MUTATING_AT, Infection.CRITICAL_AT]:
				var x: float = size.x * th / float(Infection.MAX)
				draw_line(Vector2(x, -2), Vector2(x, size.y + 2), UI.BORDER_HI, 1.0)
			draw_rect(r, UI.BORDER, false, 1.0)
