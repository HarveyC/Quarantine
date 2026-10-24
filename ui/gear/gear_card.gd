extends PanelContainer
## One reward card (gear, Prototype, perk, mutation, consumable or cache). Shows the slot,
## rarity and Mk, the tags, the effect, the threshold preview (a tag about to reach 3 glows
## gold with the bonus it switches on), and what it replaces. Hover lifts it; selected cards
## get an amber frame; Prototypes get a shifting multicolour frame.

signal pressed

const UI := preload("res://ui/gear/gear_ui.gd")
const W := 330
const H := 470

var card: Dictionary
var record: Dictionary
var selected := false
var _hover := false
var _sb: StyleBoxFlat
var _t := 0.0


func setup(c: Dictionary, rec: Dictionary, index: int) -> void:
	card = c
	record = rec
	custom_minimum_size = Vector2(W, H)
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
		"perk", "mutation": _build_power(v)
		"consumable": _build_consumable(v)
		"cache": _build_cache(v)
	var key := UI.mono("%d" % (index + 1), 12, UI.FAINT)
	key.size_flags_vertical = Control.SIZE_SHRINK_END
	key.size_flags_horizontal = Control.SIZE_SHRINK_END
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	v.add_child(key)
	for n in v.get_children():
		if n is Control:
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	v.add_child(UI.wrap(UI.label(GearData.desc(id, mk), 15, Color("#cfccbd")), W - 40))
	# Threshold preview / upgrade box.
	if pv.mode == "upgrade":
		var b := _boxed(v, rar)
		var h := HBoxContainer.new()
		h.add_child(UI.caps("Mk I  →  Mk II", 20, rar))
		b.add_child(h)
		b.add_child(UI.wrap(UI.label(GearData.desc(id, 2), 14, UI.TEXT), W - 70))
		v.add_child(UI.label("Duplicate of an item %s owns. No slot used." % UI.short_name(record), 13, UI.FAINT))
	elif pv.mode == "stash":
		v.add_child(UI.wrap(UI.label("Already at Mk II: this copy goes to the stash.", 13, UI.FAINT), W - 40))
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
			b.add_child(h)
			if hot:
				b.add_child(UI.wrap(UI.label("Set bonus: " + GearData.TAG_INFO[p.tag].bonus, 14, UI.AMBER, "bold"), W - 70))
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
					v.add_child(UI.label("Turns off the %s set bonus" % p.tag, 13, UI.DANGER, "bold"))
		elif pv.mode == "equip":
			v.add_child(UI.label("Fills the empty %s slot" % GearData.SLOT_NAMES[item.slot].to_lower(), 13, UI.FAINT))


func _build_power(v: VBoxContainer) -> void:
	var is_mut: bool = card.kind == "mutation"
	var col := UI.TEAL if is_mut else UI.GOOD
	var sub := "Mutation" if is_mut else "Perk"
	if card.has("tier"):
		sub += " · " + Infection.tier_name(int(card.tier))
	elif card.has("rarity"):
		sub += " · " + str(card.rarity).capitalize()
	_row(v, UI.label(("MUTATION" if is_mut else "CLASS PERK"), 12, UI.FAINT, "mono"), UI.caps(sub, 13, col))
	v.add_child(UI.wrap(UI.caps(str(card.get("name", card.get("id", "?"))), 36), W - 40))
	var t := GearTags.normalize(str(card.get("tag", "")))
	if t != "":
		var tags := HBoxContainer.new()
		tags.add_child(UI.tag_chip(t))
		v.add_child(tags)
	v.add_child(UI.wrap(UI.label(str(card.get("desc", "")), 15, Color("#cfccbd")), W - 40))
	if t != "":
		var before: int = GearTags.counts(record).get(t, 0)
		if before + 1 == GearData.SET_THRESHOLD:
			var b := _boxed(v, UI.AMBER)
			b.add_child(UI.caps("%s %d → %d" % [t, before, before + 1], 16, GearData.tag_color(t)))
			b.add_child(UI.wrap(UI.label("Set bonus: " + GearData.TAG_INFO[t].bonus, 14, UI.AMBER, "bold"), W - 70))
	if is_mut:
		v.add_child(UI.wrap(UI.label("Grafting adds Infection. Works only while Infection is at its tier.", 13, UI.TEAL), W - 40))


func _build_consumable(v: VBoxContainer) -> void:
	_row(v, UI.label("POCKET", 12, UI.FAINT, "mono"), UI.caps("Consumable ×%d" % int(card.get("charges", 2)), 13, UI.DIM))
	v.add_child(UI.caps(GearData.item_name(card.id), 36))
	v.add_child(UI.wrap(UI.label(GearData.desc(card.id), 15, Color("#cfccbd")), W - 40))
	if not Loadout.can_add_consumable(record, card.id):
		v.add_child(UI.label("Pockets are full", 13, UI.DANGER, "bold"))


func _build_cache(v: VBoxContainer) -> void:
	_row(v, UI.label("CACHE", 12, UI.FAINT, "mono"), UI.caps("Squad", 13, UI.DIM))
	v.add_child(UI.caps("Supply cache", 36))
	v.add_child(UI.mono("+%d" % int(card.get("supplies", GearRun.CACHE_SUPPLIES)), 40, UI.AMBER))
	v.add_child(UI.label("Supplies to the squad, for the depot and the hospital.", 15, Color("#cfccbd")))


func _boxed(v: VBoxContainer, col: Color) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := UI.box(Color(col, 0.07), col, 1, 0, 10)
	p.add_theme_stylebox_override("panel", sb)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	p.add_child(inner)
	v.add_child(p)
	return inner


## Short label for the Take button.
func title() -> String:
	match str(card.get("kind", "gear")):
		"gear":
			return GearData.item_name(card.id)
		"consumable":
			return GearData.item_name(card.id)
		"cache":
			return "+%d Supplies" % int(card.get("supplies", 25))
	return str(card.get("name", card.get("id", "card")))
