extends RefCounted
## HUD theme, "Bloom": the Infection grows into the interface. Deep night-blue ground, soft
## rounded glass panels, pill buttons, ring gauges. Two lights only: the amber lantern means
## "you can act" (buttons, the active soldier, action points), the teal Bloom means Infection
## (gauges, tendrils, mutations). Enemies and danger are a hot pink. Unbounded for display
## words, Outfit for body text, JetBrains Mono for small numbers and key caps.
## See the "Bloom" direction in the UI style canvas for the reference look.

const _UNBOUNDED := preload("res://ui/fonts/Unbounded-Variable.ttf")
const _OUTFIT := preload("res://ui/fonts/Outfit-Variable.ttf")
const FONT_MONO := preload("res://ui/fonts/JetBrainsMono-Bold.ttf")

static var FONT_BODY: Font = _weight(_OUTFIT, 400)
static var FONT_BODY_BOLD: Font = _weight(_OUTFIT, 600)
static var FONT_COND: Font = _weight(_OUTFIT, 600)
static var FONT_COND_BOLD: Font = _weight(_OUTFIT, 700)
static var FONT_DISPLAY: Font = _weight(_UNBOUNDED, 700)
static var FONT_DISPLAY_BLACK: Font = _weight(_UNBOUNDED, 900)
static var FONT_DISPLAY_MEDIUM: Font = _weight(_UNBOUNDED, 500)

const GROUND := Color("0a0e18")
const BG := Color(0.039, 0.055, 0.094, 0.86)
const BG_SOFT := Color(0.055, 0.075, 0.118, 0.92)
const BG_RAISED := Color("121a27")
const BORDER := Color(0.66, 0.78, 0.8, 0.2)
const BORDER_SOFT := Color(0.66, 0.78, 0.8, 0.13)
const BORDER_STRONG := Color(0.66, 0.78, 0.8, 0.38)
const TEXT := Color("e8f4f2")
const DIM := Color("a9bcc0")
const MUTED := Color("7f9298")

const AMBER := Color("ffb347")
const AMBER_LIGHT := Color("ffd08a")
const AMBER_DEEP := Color("d9822a")
const AMBER_DARK := Color("2a1604")
const TEAL := Color("3fe0c5")
const TEAL_DIM := Color("7fb9ae")
const TEAL_DEEP := Color("127a6b")
const DANGER := Color("ff5fa2")
const DANGER_TEXT := Color("ff8cbc")
const HP := Color("b4d77a")
const HP_OFF := Color(0.66, 0.78, 0.8, 0.12)
const GRAZE := Color("d8c27e")

## Corner radius of a standard panel; buttons are pills.
const RADIUS := 16
const PILL := 999

## Player colours (index = player id). Blue and coral differ in lightness as well as hue.
const PLAYERS: Array[Color] = [Color("79b0ff"), Color("ff9a6b"), Color("c4a6ff"), Color("e0d06a")]

## Text size multiplier from Settings > Accessibility (GameSettings sets it). Screens pick it
## up as they are built.
static var text_scale := 1.0


static func _weight(base: FontFile, wght: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): wght}
	return f


static func fs(size: int) -> int:
	return roundi(size * text_scale)


static func player_color(p: int) -> Color:
	return PLAYERS[posmod(p, PLAYERS.size())]


static func panel_box(bg := BG, border := BORDER, radius := RADIUS) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 10
	sb.anti_aliasing = true
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


## A panel box with a soft coloured glow around it (the lantern or the Bloom shining through).
static func glow_box(bg: Color, border: Color, glow: Color, glow_px := 14, radius := RADIUS) -> StyleBoxFlat:
	var sb := panel_box(bg, border, radius)
	sb.shadow_color = glow
	sb.shadow_size = glow_px
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT_BODY
	t.default_font_size = fs(15)
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("outline_size", "Label", 0)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	t.set_stylebox("normal", "Button", panel_box(Color(0.91, 0.96, 0.95, 0.05), BORDER_STRONG, PILL))
	t.set_stylebox("hover", "Button", glow_box(Color(AMBER, 0.08), AMBER, Color(AMBER, 0.22), 10, PILL))
	t.set_stylebox("pressed", "Button", glow_box(Color(AMBER, 0.16), AMBER, Color(AMBER, 0.3), 12, PILL))
	t.set_stylebox("hover_pressed", "Button", glow_box(Color(AMBER, 0.16), AMBER, Color(AMBER, 0.3), 12, PILL))
	t.set_stylebox("disabled", "Button", panel_box(Color(0.91, 0.96, 0.95, 0.02), BORDER_SOFT, PILL))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", FONT_COND)
	t.set_font_size("font_size", "Button", fs(16))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", AMBER_LIGHT)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.6))
	t.set_color("font_pressed_color", "Button", AMBER)
	t.set_color("font_hover_pressed_color", "Button", AMBER)
	t.set_stylebox("background", "ProgressBar", panel_box(Color(0.91, 0.96, 0.95, 0.07), Color(0, 0, 0, 0), PILL))
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", FONT_BODY)
	t.set_font("bold_font", "RichTextLabel", FONT_BODY_BOLD)
	t.set_font("mono_font", "RichTextLabel", FONT_MONO)
	t.set_stylebox("normal", "LineEdit", panel_box(Color(0.91, 0.96, 0.95, 0.05), BORDER_STRONG, 12))
	t.set_stylebox("focus", "LineEdit", glow_box(Color(0.91, 0.96, 0.95, 0.06), AMBER, Color(AMBER, 0.2), 8, 12))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_color("caret_color", "LineEdit", AMBER)
	t.set_color("selection_color", "LineEdit", Color(AMBER, 0.3))
	_add_extras(t)
	return t


## Tooltips, sliders, check boxes, drop-downs and scroll bars in the same look, so no screen
## falls back to Godot's default grey widgets.
static func _add_extras(t: Theme) -> void:
	var tip := glow_box(Color(0.035, 0.05, 0.085, 0.97), BORDER_STRONG, Color(0, 0, 0, 0.4), 10, 12)
	tip.content_margin_left = 14
	tip.content_margin_right = 14
	tip.content_margin_top = 9
	tip.content_margin_bottom = 9
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_font("font", "TooltipLabel", FONT_BODY)
	t.set_font_size("font_size", "TooltipLabel", 14)
	t.set_color("font_color", "TooltipLabel", TEXT)
	# Sliders: a rounded track with an amber fill and a glowing round grabber.
	var track := panel_box(Color(0.91, 0.96, 0.95, 0.1), Color(0, 0, 0, 0), PILL)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := panel_box(AMBER, Color(0, 0, 0, 0), PILL)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _orb_tex(18, AMBER))
	t.set_icon("grabber_highlight", "HSlider", _orb_tex(20, AMBER_LIGHT))
	t.set_icon("tick", "HSlider", _square_tex(2, BORDER_STRONG))
	# Check boxes: an outlined circle that fills with a lantern dot.
	for kind in ["CheckBox", "CheckButton"]:
		t.set_icon("unchecked", kind, _ring_tex(20, BORDER_STRONG, false))
		t.set_icon("checked", kind, _ring_tex(20, AMBER, true))
		t.set_icon("unchecked_disabled", kind, _ring_tex(20, BORDER, false))
		t.set_icon("checked_disabled", kind, _ring_tex(20, BORDER_STRONG, true))
		t.set_stylebox("normal", kind, _flat_margin(6))
		t.set_stylebox("hover", kind, _flat_margin(6))
		t.set_stylebox("pressed", kind, _flat_margin(6))
		t.set_stylebox("hover_pressed", kind, _flat_margin(6))
		t.set_stylebox("focus", kind, StyleBoxEmpty.new())
		t.set_font("font", kind, FONT_BODY)
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_hover_color", kind, TEXT)
		t.set_color("font_pressed_color", kind, TEXT)
		t.set_color("font_hover_pressed_color", kind, TEXT)
	# Drop-downs and their pop-up list.
	t.set_stylebox("normal", "OptionButton", panel_box(Color(0.91, 0.96, 0.95, 0.05), Color(AMBER, 0.45), PILL))
	t.set_stylebox("hover", "OptionButton", glow_box(Color(AMBER, 0.08), AMBER, Color(AMBER, 0.2), 8, PILL))
	t.set_stylebox("pressed", "OptionButton", glow_box(Color(AMBER, 0.12), AMBER, Color(AMBER, 0.2), 8, PILL))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_font("font", "OptionButton", FONT_BODY)
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_hover_color", "OptionButton", TEXT)
	t.set_stylebox("panel", "PopupMenu", glow_box(Color(0.035, 0.05, 0.085, 0.98), BORDER_STRONG, Color(0, 0, 0, 0.45), 12, 14))
	var hl := panel_box(Color(AMBER, 0.16), Color(0, 0, 0, 0), 10)
	t.set_stylebox("hover", "PopupMenu", hl)
	t.set_font("font", "PopupMenu", FONT_BODY)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", AMBER)
	# Thin rounded scroll bars.
	for kind in ["VScrollBar", "HScrollBar"]:
		var bar := panel_box(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), PILL)
		bar.content_margin_left = 3
		bar.content_margin_right = 3
		bar.content_margin_top = 3
		bar.content_margin_bottom = 3
		t.set_stylebox("scroll", kind, bar)
		t.set_stylebox("grabber", kind, panel_box(BORDER_STRONG, Color(0, 0, 0, 0), PILL))
		var gh := panel_box(DIM, Color(0, 0, 0, 0), PILL)
		t.set_stylebox("grabber_highlight", kind, gh)
		t.set_stylebox("grabber_pressed", kind, gh)


static func _flat_margin(m: int) -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = m
	sb.content_margin_right = m
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


static func _square_tex(px: int, col: Color) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(col)
	return ImageTexture.create_from_image(img)


## A soft glowing round grabber.
static func _orb_tex(px: int, col: Color) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := Vector2(px, px) * 0.5
	for x in px:
		for y in px:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var core := clampf(px * 0.36 - d + 0.5, 0.0, 1.0)
			var halo := clampf(1.0 - d / (px * 0.5), 0.0, 1.0) * 0.45
			var out := col.lightened(0.25 * clampf(1.0 - d / (px * 0.36), 0.0, 1.0))
			out.a = maxf(core, halo)
			img.set_pixel(x, y, out)
	return ImageTexture.create_from_image(img)


## A ring, optionally with a filled dot inside (check boxes).
static func _ring_tex(px: int, col: Color, filled: bool) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := Vector2(px, px) * 0.5
	var r := px * 0.5 - 1.5
	for x in px:
		for y in px:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(1.2 - absf(d - r) / 0.9, 0.0, 1.0)
			if filled:
				a = maxf(a, clampf(r - 4.0 - d + 0.5, 0.0, 1.0))
			img.set_pixel(x, y, Color(col, a * col.a))
	return ImageTexture.create_from_image(img)


## Body text label.
static func label(text: String, size := 15, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Caps label. Small captions are Outfit with open letter spacing; headings (22 px and up)
## switch to the Unbounded display face, which runs wide, so they are set a little smaller.
static func caps(text: String, size := 15, color := TEXT, bold := true) -> Label:
	if size >= 22:
		return display(text, size, color, bold)
	var l := label(text.to_upper(), size, color)
	var f := FontVariation.new()
	f.base_font = FONT_COND_BOLD if bold else FONT_COND
	f.spacing_glyph = maxi(1, roundi(size * 0.1))
	l.add_theme_font_override("font", f)
	return l


## Display heading in Unbounded (wordmarks, screen titles, big numbers). Sized so `size` is
## roughly the cap height a condensed face of that size would have had.
static func display(text: String, size := 28, color := TEXT, heavy := true, upper := true) -> Label:
	var l := label(text.to_upper() if upper else text, roundi(size * 0.8), color)
	var f := FontVariation.new()   # its own variation, so a caller may tune spacing
	f.base_font = FONT_DISPLAY if heavy else FONT_DISPLAY_MEDIUM
	l.add_theme_font_override("font", f)
	return l


## Gives a label a soft coloured glow behind its letters (the Bloom shining through a title).
static func glow_text(l: Label, col := TEAL, px := 16, alpha := 0.4) -> void:
	l.add_theme_color_override("font_shadow_color", Color(col, alpha))
	l.add_theme_constant_override("shadow_outline_size", px)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)


## Monospaced numbers.
static func mono(text: String, size := 13, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", FONT_MONO)
	return l


static func bold(text: String, size := 15, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", FONT_BODY_BOLD)
	return l


## A thin rounded bar (ProgressBar with a flat pill fill).
static func bar(color: Color, height := 8) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, height)
	p.max_value = 100
	set_bar_color(p, color)
	return p


static func set_bar_color(p: ProgressBar, color: Color) -> void:
	var fill := panel_box(color, Color(0, 0, 0, 0), PILL)
	fill.set_content_margin_all(0)
	if color == TEAL:
		fill.shadow_color = Color(TEAL, 0.45)
		fill.shadow_size = 6
	p.add_theme_stylebox_override("fill", fill)


static func hbox(sep := 8) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func vbox(sep := 6) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Pill button with a drawn icon left of its text. `kind`: "primary" (the glowing lantern, the
## one thing to press), "secondary" (glass pill) or "ghost" (text only). The icon follows the
## font colour.
static func icon_button(text: String, icon: String, kind := "secondary", size := 17, height := 46.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, height)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if icon != "" else HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_override("font", FONT_DISPLAY_MEDIUM if kind != "primary" else FONT_DISPLAY)
	b.add_theme_font_size_override("font_size", roundi(size * 0.78))
	var pad := 22 + (int(height * 0.5) + 8 if icon != "" else 0)
	style_button(b, kind, pad)
	if icon != "":
		var ic := ButtonIcon.new(icon, height * 0.42)
		b.add_child(ic)
	return b


## Applies the primary / secondary / ghost look to any button. `pad_left` leaves room for an icon.
static func style_button(b: Button, kind := "secondary", pad_left := 20) -> void:
	var boxes := {}
	match kind:
		"primary":
			boxes = {"normal": glow_box(AMBER, AMBER_LIGHT, Color(AMBER, 0.42), 16, PILL),
				"hover": glow_box(AMBER_LIGHT, Color("fff0d6"), Color(AMBER, 0.6), 22, PILL),
				"pressed": glow_box(AMBER_DEEP, AMBER, Color(AMBER, 0.35), 10, PILL),
				"disabled": panel_box(Color(AMBER, 0.12), Color(AMBER, 0.2), PILL)}
			for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
				b.add_theme_color_override(k, AMBER_DARK)
			b.add_theme_color_override("font_disabled_color", Color(AMBER, 0.45))
		"ghost":
			boxes = {"normal": panel_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), PILL),
				"hover": panel_box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), PILL),
				"pressed": panel_box(Color(AMBER, 0.1), Color(0, 0, 0, 0), PILL),
				"disabled": panel_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), PILL)}
			b.add_theme_color_override("font_color", DIM)
			b.add_theme_color_override("font_hover_color", TEXT)
			b.add_theme_color_override("font_pressed_color", AMBER)
			b.add_theme_color_override("font_disabled_color", Color(MUTED, 0.5))
		_:
			boxes = {"normal": panel_box(Color(0.91, 0.96, 0.95, 0.05), BORDER_STRONG, PILL),
				"hover": glow_box(Color(AMBER, 0.08), AMBER, Color(AMBER, 0.22), 12, PILL),
				"pressed": glow_box(Color(AMBER, 0.16), AMBER, Color(AMBER, 0.3), 12, PILL),
				"disabled": panel_box(Color(0.91, 0.96, 0.95, 0.02), BORDER_SOFT, PILL)}
			b.add_theme_color_override("font_color", TEXT)
			b.add_theme_color_override("font_hover_color", AMBER_LIGHT)
			b.add_theme_color_override("font_pressed_color", AMBER)
			b.add_theme_color_override("font_hover_pressed_color", AMBER)
			b.add_theme_color_override("font_disabled_color", Color(MUTED, 0.6))
	for state in boxes:
		var sb: StyleBoxFlat = boxes[state]
		sb.content_margin_left = pad_left
		sb.content_margin_right = 22
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("hover_pressed", b.get_theme_stylebox("pressed"))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## Gives a styled button a fixed corner radius (tiles and cards that aren't pills).
static func round_button(b: Button, radius := RADIUS) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := b.get_theme_stylebox(state) as StyleBoxFlat
		if sb != null and b.has_theme_stylebox_override(state):
			sb = sb.duplicate()
			sb.set_corner_radius_all(radius)
			b.add_theme_stylebox_override(state, sb)


## The icon inside an icon_button: drawn at the left, in the button's current font colour.
class ButtonIcon extends Control:
	const Icons := preload("res://ui/icons.gd")
	var id := ""

	func _init(icon_id: String, px: float) -> void:
		id = icon_id
		custom_minimum_size = Vector2(px, px)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		var b := get_parent() as Button
		if b != null:
			b.resized.connect(_place)
			for s in ["mouse_entered", "mouse_exited", "button_down", "button_up"]:
				b.connect(s, queue_redraw)
		_place()

	func _place() -> void:
		var b := get_parent() as Control
		if b != null:
			position = Vector2(maxf(18.0, b.size.y * 0.42), (b.size.y - size.y) * 0.5)

	func _draw() -> void:
		var b := get_parent() as Button
		var col := TEXT
		if b != null:
			var key := "font_color"
			if b.disabled:
				key = "font_disabled_color"
			elif b.button_pressed or b.is_pressed():
				key = "font_pressed_color"
			elif b.is_hovered():
				key = "font_hover_color"
			col = b.get_theme_color(key)
		Icons.draw(self, id, Rect2(Vector2.ZERO, size), col, 1.9)
