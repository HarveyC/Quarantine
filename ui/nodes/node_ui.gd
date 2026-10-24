class_name NodeUi
extends RefCounted
## Look and widget helpers for the node screens, following the approved UI mockups: dark
## see-through panels with amber corner marks, amber only for things you can press, teal only
## for Infection, a player-colour stripe on soldier cards. OWNER: nodes workstream.

const BG := Color(0.043, 0.051, 0.047, 0.9)
const PANEL := Color(0.059, 0.075, 0.063, 0.94)
const PANEL_SOFT := Color(0.071, 0.086, 0.075, 0.96)
const BORDER := Color("2a322b")
const TEXT := Color("e9e4d4")
const DIM := Color("a8aa98")
const FAINT := Color("8c8e7e")
const AMBER := Color("f2c14e")
const AMBER_DARK := Color("15130b")
const TEAL := Color("3fe0c5")
const HEALTH := Color("a9c46c")
const BAD := Color("ff8a6e")
## Player stripe colours, as in the mockups (player 0 blue, 1 orange, then green and pink).
const PLAYER: Array[Color] = [Color("79b0ff"), Color("ff9a6b"), Color("a9c46c"), Color("ff5c86")]

const CornerPanel := preload("res://ui/nodes/corner_panel.gd")


static func player_color(p: int) -> Color:
	return PLAYER[posmod(p, PLAYER.size())]


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
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 120
	return l


## Small uppercase caption ("SQUAD VOTE", "HEALTH").
static func caption(text: String, color := FAINT, size := 13) -> Label:
	return label(text.to_upper(), size, color)


static func vbox(sep := 10) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func hbox(sep := 10) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


## A button. `primary` = the amber call to action; anything pressable that isn't primary
## gets an amber outline, and disabled buttons go flat grey.
static func button(text: String, enabled := true, primary := false, tooltip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size.y = 36
	var normal := box(AMBER if primary else PANEL_SOFT, AMBER if primary else Color("6a5a2c"), 8)
	var hover := box(AMBER.lightened(0.15) if primary else Color("1c1b12"), AMBER, 8)
	var disabled := box(Color(0.07, 0.08, 0.07, 0.8), Color("222a23"), 8)
	for st in ["normal", "focus"]:
		b.add_theme_stylebox_override(st, normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	var fg := AMBER_DARK if primary else TEXT
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color("5d6058"))
	return b


## A thin labelled bar: HP in green, Infection in teal with tier ticks.
static func meter(caption_text: String, value: int, max_value: int, color: Color, value_text := "", ticks := false) -> VBoxContainer:
	var v := vbox(4)
	var top := hbox()
	var c := caption(caption_text)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(c)
	top.add_child(label(value_text if value_text != "" else "%d / %d" % [value, max_value], 13, color if color == TEAL else TEXT))
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
