class_name NodeUi
extends RefCounted
## Look and widget helpers for the node screens, following the approved UI mockups: dark
## see-through panels with amber corner marks, amber only for things you can press, teal only
## for Infection, a player-colour stripe on soldier cards. OWNER: nodes workstream.

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")

const BG := Color(0.043, 0.051, 0.047, 0.9)
const PANEL := Color(0.059, 0.075, 0.063, 0.94)
const PANEL_SOFT := Color(0.071, 0.086, 0.075, 0.96)
const BORDER := Styles.BORDER_SOFT
const TEXT := Styles.TEXT
const DIM := Styles.DIM
const FAINT := Styles.MUTED
const AMBER := Styles.AMBER
const AMBER_DARK := Styles.AMBER_DARK
const TEAL := Styles.TEAL
const HEALTH := Styles.HP
const BAD := Styles.DANGER_TEXT
const SUPPLY := Color("c9a24a")

const CornerPanel := preload("res://ui/nodes/corner_panel.gd")

## Resource words an effect line can name, and how a chip for each looks.
const EFFECT_LOOK := {
	"Supplies": ["supplies", SUPPLY], "Intel": ["intel", Styles.DIM], "Infection": ["infection", Styles.TEAL],
	"Outbreak": ["outbreak", Styles.TEAL], "HP": ["health", Styles.HP], "max HP": ["health", Styles.HP],
	"Serum": ["serum", Styles.TEAL], "Serum sample": ["serum", Styles.TEAL], "Serum samples": ["serum", Styles.TEAL],
	"Serum doses": ["serum", Styles.TEAL], "enemy": ["skull", Styles.DANGER], "action": ["clock", Styles.AMBER],
}
static var _re_num_first: RegEx
static var _re_word_first: RegEx


static func player_color(p: int) -> Color:
	return Styles.player_color(p)


static func player_name(session, p: int) -> String:
	var names = session.get("player_names") if session != null else null
	if names is Dictionary and names.has(p):
		return str(names[p])
	return "Player %d" % (p + 1)


static func box(bg := PANEL, border := BORDER, pad := 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


## A panel with amber corner marks; `stripe` draws a coloured bar along the top (a player).
static func panel(stripe := Color(0, 0, 0, 0), pad := 16) -> PanelContainer:
	var p: PanelContainer = CornerPanel.new()
	p.add_theme_stylebox_override("panel", box(PANEL, BORDER, pad))
	p.stripe = stripe
	return p


static func label(text: String, size := 15, color := TEXT, wrap := false) -> Label:
	var l := Styles.label(text, size, color)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 120
	return l


## Small uppercase caption ("SQUAD VOTE", "HEALTH").
static func caption(text: String, color := FAINT, size := 13) -> Label:
	return Styles.caps(text, size, color)


## Big condensed title.
static func title(text: String, size := 30, color := TEXT) -> Label:
	return Styles.caps(text, size, color)


static func vbox(sep := 10) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func hbox(sep := 10) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


## A button. `primary` = the amber call to action; anything pressable that isn't primary
## gets an outline that turns amber on hover, and disabled buttons go flat grey. `icon` draws a
## line icon left of the text.
static func button(text: String, enabled := true, primary := false, tooltip := "", icon := "") -> Button:
	var b := Styles.icon_button(text, icon, "primary" if primary else "secondary", 16, 40)
	b.text = text
	b.disabled = not enabled
	b.tooltip_text = tooltip
	return b


## A thin labelled bar: HP in green, Infection in teal with tier ticks.
static func meter(caption_text: String, value: int, max_value: int, color: Color, value_text := "", ticks := false) -> VBoxContainer:
	var v := vbox(4)
	var top := hbox()
	var c := caption(caption_text)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(c)
	top.add_child(Styles.mono(value_text if value_text != "" else "%d/%d" % [value, max_value], 12, color if color == TEAL else TEXT))
	v.add_child(top)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.max_value = max_value
	bar.value = value
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("1d2420")
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	if ticks:
		for t in [25, 50, 75]:
			var tick := ColorRect.new()
			tick.color = Color("0b0d0c")
			tick.anchor_left = t / 100.0
			tick.anchor_right = t / 100.0
			tick.anchor_bottom = 1.0
			tick.offset_right = 2
			bar.add_child(tick)
	v.add_child(bar)
	return v


static func infection_text(value: int) -> String:
	return "%d · %s" % [value, Infection.tier_name(Infection.tier(value))]


## A soldier's one-line identity: "Marksman Okafor".
static func soldier_title(rec: Dictionary) -> String:
	return "%s %s" % [UnitData.SOLDIERS.get(rec.kind, {}).get("name", rec.kind.capitalize()), rec.name]


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## A small chip: line icon and a short value ("+20" with the Supplies crate).
static func chip(icon: String, text: String, col: Color, size := 15, tip := "") -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.08)
	sb.border_color = Color(col, 0.55)
	sb.set_border_width_all(1)
	sb.content_margin_left = 7
	sb.content_margin_right = 9
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_PASS if tip != "" else Control.MOUSE_FILTER_IGNORE
	var row := Styles.hbox(6)
	if icon != "":
		var ic := W.Icon.new(icon, col, size + 1, 1.7)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	row.add_child(Styles.mono(text, size - 2, col))
	p.add_child(row)
	return p


## Splits an effect line ("Outbreak -2, but the next fight has +1 enemy") into chips for the
## numbers it names and the words left over: {"chips": [[icon, text, colour, word]], "rest": String}.
static func effects(desc: String) -> Dictionary:
	if _re_num_first == null:
		var words := "max HP|HP|Supplies|Intel|Infection|Outbreak|Serum samples|Serum sample|Serum doses|Serum|enemy|action"
		_re_num_first = RegEx.create_from_string("(^|[\\s(,:])([+\\-]\\d+%?)\\s+(" + words + ")(?=$|[\\s.,;)])")
		_re_word_first = RegEx.create_from_string("(^|[\\s(,:])(Outbreak|Infection|Supplies|Intel)\\s+([+\\-]\\d+)(?=$|[\\s.,;)])")
	var chips: Array = []
	var rest := desc
	for m in _re_num_first.search_all(desc):
		var word := m.get_string(3)
		var look: Array = EFFECT_LOOK.get(word, ["dot", Styles.DIM])
		chips.append([look[0], m.get_string(2), look[1], word])
		rest = _strip_clause(rest, m.get_string(0).strip_edges())
	for m in _re_word_first.search_all(desc):
		var word := m.get_string(2)
		var look: Array = EFFECT_LOOK.get(word, ["dot", Styles.DIM])
		chips.append([look[0], m.get_string(3), look[1], word])
		rest = _strip_clause(rest, m.get_string(0).strip_edges())
	return {"chips": chips, "rest": rest}


## Removes `part` from `text` when it closes a clause, then tidies the joins left behind.
static func _strip_clause(text: String, part: String) -> String:
	var i := text.find(part)
	if i < 0:
		return text
	var after := text.substr(i + part.length())
	var closes := after == "" or after.begins_with(",") or after.begins_with(".") or after.begins_with(" and ") or after.begins_with(";")
	if not closes:
		return text
	var out := (text.substr(0, i) + after).strip_edges()
	for junk in [" and ,", " and.", ", ,", " ,", ",,"]:
		out = out.replace(junk, junk.right(1))
	while out.ends_with(" and") or out.ends_with(",") or out.ends_with(":"):
		out = out.trim_suffix(" and").trim_suffix(",").trim_suffix(":").strip_edges()
	for lead in [", ", ". ", "and ", "but ", ": ", "; "]:
		if out.begins_with(lead):
			out = out.substr(lead.length())
	out = out.strip_edges()
	if out.length() > 0:
		out = out[0].to_upper() + out.substr(1)
	return out


## The chips for an effect line, plus what's left of it as quiet text under them.
static func effect_row(desc: String, size := 15) -> Control:
	var e := effects(desc)
	var box := Styles.vbox(6)
	if not e.chips.is_empty():
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		for c in e.chips:
			row.add_child(chip(c[0], c[1], c[2], size, "%s %s" % [c[1], c[3]]))
		box.add_child(row)
	var rest: String = e.rest
	if rest != "" and rest.to_lower() != "nothing" and rest.to_lower() != "nothing happens":
		box.add_child(label(rest, size - 1, DIM, true))
	elif e.chips.is_empty():
		box.add_child(label("No effect", size - 1, FAINT))
	return box


## A square-ish button with a big icon over a caps title and an optional line under it (a cost
## chip, an effect). Used for treatments and other "pick one" tiles.
static func tile_button(icon: String, title_text: String, col: Color, under: Control = null, enabled := true, tip := "") -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(140, 118)
	Styles.style_button(b, "secondary")
	var v := Styles.vbox(7)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var c := col if enabled else Color("4d5148")
	var ic := W.Icon.new(icon, c, 30, 1.9)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := Styles.caps(title_text, 15, TEXT if enabled else Color("5b6052"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	if under != null:
		under.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if not enabled:
			under.modulate = Color(1, 1, 1, 0.4)
		v.add_child(under)
	b.add_child(v)
	return b


## "Free" / "15" with a Supplies crate / "2" with a Serum vial, from a cost line.
static func cost_chip(cost: String) -> Control:
	if cost.to_lower() == "free":
		return chip("", "FREE", HEALTH, 13)
	var parts := cost.split(" ", false, 1)
	if parts.size() == 2 and parts[0].is_valid_int():
		var word := parts[1]
		var look: Array = EFFECT_LOOK.get(word, EFFECT_LOOK.get(word.trim_suffix("s"), ["dot", DIM]))
		if word.begins_with("Serum"):
			look = EFFECT_LOOK.Serum
		return chip(look[0], parts[0], look[1], 13, cost)
	return chip("", cost.to_upper(), DIM, 13)
