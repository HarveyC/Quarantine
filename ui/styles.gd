extends RefCounted
## HUD theme: dark translucent panels with amber corner marks, condensed caps for
## headings, mono for numbers. Amber means "you can act", teal means Infection.
## See the UI mockups (Combat HUD) for the reference look.

const FONT_BODY := preload("res://ui/fonts/Barlow-Regular.ttf")
const FONT_BODY_BOLD := preload("res://ui/fonts/Barlow-SemiBold.ttf")
const FONT_COND := preload("res://ui/fonts/BarlowCondensed-SemiBold.ttf")
const FONT_COND_BOLD := preload("res://ui/fonts/BarlowCondensed-Bold.ttf")
const FONT_MONO := preload("res://ui/fonts/JetBrainsMono-Bold.ttf")

const GROUND := Color("0b0d0c")
const BG := Color(0.043, 0.055, 0.047, 0.88)
const BG_SOFT := Color(0.067, 0.082, 0.07, 0.92)
const BG_RAISED := Color("141915")
const BORDER := Color("2f3830")
const BORDER_SOFT := Color("2a322b")
const BORDER_STRONG := Color("4d574b")
const TEXT := Color("e9e4d4")
const DIM := Color("a8aa98")
const MUTED := Color("8c8e7e")

const AMBER := Color("f2c14e")
const AMBER_DARK := Color("15130b")
const TEAL := Color("3fe0c5")
const TEAL_DIM := Color("8fb8ad")
const DANGER := Color("ff6a4d")
const DANGER_TEXT := Color("ff8a6e")
const HP := Color("a9c46c")
const HP_OFF := Color("2c332c")
const GRAZE := Color("c9b57a")

## Player colours (index = player id). Blue and coral differ in lightness as well as hue.
const PLAYERS: Array[Color] = [Color("79b0ff"), Color("ff9a6b"), Color("c9a8ff"), Color("e0d06a")]


static func player_color(p: int) -> Color:
	return PLAYERS[posmod(p, PLAYERS.size())]


static func panel_box(bg := BG, border := BORDER, radius := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT_BODY
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("outline_size", "Label", 0)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	t.set_stylebox("normal", "Button", panel_box(BG_RAISED, Color("333d33")))
	t.set_stylebox("hover", "Button", panel_box(Color("1a2019"), BORDER_STRONG))
	t.set_stylebox("pressed", "Button", panel_box(Color("2a2613"), AMBER))
	t.set_stylebox("hover_pressed", "Button", panel_box(Color("2a2613"), AMBER))
	t.set_stylebox("disabled", "Button", panel_box(Color(0.06, 0.07, 0.065, 0.9), Color("222823")))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", FONT_COND)
	t.set_font_size("font_size", "Button", 16)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color("5b6052"))
	t.set_color("font_pressed_color", "Button", AMBER)
	t.set_color("font_hover_pressed_color", "Button", AMBER)
	t.set_stylebox("background", "ProgressBar", panel_box(Color(0.05, 0.06, 0.055, 0.95), BORDER_SOFT))
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", FONT_BODY)
	t.set_font("bold_font", "RichTextLabel", FONT_BODY_BOLD)
	t.set_font("mono_font", "RichTextLabel", FONT_MONO)
	t.set_stylebox("normal", "LineEdit", panel_box(BG_RAISED, Color("333d33")))
	t.set_stylebox("focus", "LineEdit", panel_box(BG_RAISED, AMBER))
	return t


## Body text label.
static func label(text: String, size := 15, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Condensed caps heading with letter spacing.
static func caps(text: String, size := 15, color := TEXT, bold := true) -> Label:
	var l := label(text.to_upper(), size, color)
	var f := FontVariation.new()
	f.base_font = FONT_COND_BOLD if bold else FONT_COND
	f.spacing_glyph = maxi(1, roundi(size * 0.08))
	l.add_theme_font_override("font", f)
	return l


## Monospaced numbers.
static func mono(text: String, size := 13, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", FONT_MONO)
	return l


static func bold(text: String, size := 15, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", FONT_BODY_BOLD)
	return l


## A thin coloured bar (ProgressBar with a flat fill).
static func bar(color: Color, height := 8) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, height)
	p.max_value = 100
	set_bar_color(p, color)
	return p


static func set_bar_color(p: ProgressBar, color: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
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
