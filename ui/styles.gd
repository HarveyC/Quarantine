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

## Text size multiplier from Settings > Accessibility (GameSettings sets it). Screens pick it
## up as they are built.
static var text_scale := 1.0


static func fs(size: int) -> int:
	return roundi(size * text_scale)


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
	t.default_font_size = fs(15)
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
	t.set_font_size("font_size", "Button", fs(16))
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
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color("5f6457"))
	t.set_color("caret_color", "LineEdit", AMBER)
	t.set_color("selection_color", "LineEdit", Color(AMBER, 0.3))
	_add_extras(t)
	return t


## Tooltips, sliders, check boxes, drop-downs and scroll bars in the same look, so no screen
## falls back to Godot's default grey widgets.
static func _add_extras(t: Theme) -> void:
	var tip := panel_box(Color(0.035, 0.045, 0.04, 0.97), BORDER_STRONG)
	tip.border_width_left = 2
	tip.border_color = BORDER_STRONG
	tip.content_margin_left = 12
	tip.content_margin_right = 12
	tip.content_margin_top = 8
	tip.content_margin_bottom = 8
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_font("font", "TooltipLabel", FONT_BODY)
	t.set_font_size("font_size", "TooltipLabel", 14)
	t.set_color("font_color", "TooltipLabel", TEXT)
	# Sliders: a thin track with an amber fill and a square amber grabber.
	var track := StyleBoxFlat.new()
	track.bg_color = Color("1d2420")
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = AMBER
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _square_tex(14, AMBER))
	t.set_icon("grabber_highlight", "HSlider", _square_tex(16, AMBER.lightened(0.25)))
	t.set_icon("tick", "HSlider", _square_tex(2, BORDER_STRONG))
	# Check boxes: an outlined square that fills amber.
	for kind in ["CheckBox", "CheckButton"]:
		t.set_icon("unchecked", kind, _box_tex(18, BORDER_STRONG, false))
		t.set_icon("checked", kind, _box_tex(18, AMBER, true))
		t.set_icon("unchecked_disabled", kind, _box_tex(18, BORDER, false))
		t.set_icon("checked_disabled", kind, _box_tex(18, BORDER_STRONG, true))
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
	t.set_stylebox("normal", "OptionButton", panel_box(BG_RAISED, Color("6a5a2c")))
	t.set_stylebox("hover", "OptionButton", panel_box(Color("1c1b12"), AMBER))
	t.set_stylebox("pressed", "OptionButton", panel_box(Color("1c1b12"), AMBER))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_font("font", "OptionButton", FONT_BODY)
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_hover_color", "OptionButton", TEXT)
	t.set_stylebox("panel", "PopupMenu", panel_box(Color(0.035, 0.045, 0.04, 0.98), BORDER_STRONG))
	var hl := StyleBoxFlat.new()
	hl.bg_color = Color(AMBER, 0.16)
	t.set_stylebox("hover", "PopupMenu", hl)
	t.set_font("font", "PopupMenu", FONT_BODY)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", AMBER)
	# Thin scroll bars.
	for kind in ["VScrollBar", "HScrollBar"]:
		var bar := StyleBoxFlat.new()
		bar.bg_color = Color(1, 1, 1, 0.03)
		bar.content_margin_left = 3
		bar.content_margin_right = 3
		bar.content_margin_top = 3
		bar.content_margin_bottom = 3
		t.set_stylebox("scroll", kind, bar)
		var g := StyleBoxFlat.new()
		g.bg_color = BORDER_STRONG
		t.set_stylebox("grabber", kind, g)
		var gh := StyleBoxFlat.new()
		gh.bg_color = DIM
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


static func _box_tex(px: int, col: Color, filled: bool) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in px:
		for j in [0, 1, px - 2, px - 1]:
			img.set_pixel(i, j, col)
			img.set_pixel(j, i, col)
	if filled:
		for x in range(4, px - 4):
			for y in range(4, px - 4):
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Body text label.
static func label(text: String, size := 15, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs(size))
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


## Button with a drawn icon left of its text. `kind`: "primary" (solid amber, the one thing to
## press), "secondary" (outlined) or "ghost" (text only). The icon follows the font colour.
static func icon_button(text: String, icon: String, kind := "secondary", size := 17, height := 46.0) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, height)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if icon != "" else HORIZONTAL_ALIGNMENT_CENTER
	var f := FontVariation.new()
	f.base_font = FONT_COND_BOLD
	f.spacing_glyph = 1
	b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", size)
	style_button(b, kind, 16 + (int(height * 0.5) + 6 if icon != "" else 0))
	if icon != "":
		var ic := ButtonIcon.new(icon, height * 0.42)
		b.add_child(ic)
	return b


## Applies the primary / secondary / ghost look to any button. `pad_left` leaves room for an icon.
static func style_button(b: Button, kind := "secondary", pad_left := 16) -> void:
	var boxes := {}
	match kind:
		"primary":
			boxes = {"normal": [AMBER, AMBER], "hover": [AMBER.lightened(0.14), AMBER.lightened(0.14)],
				"pressed": [AMBER.darkened(0.12), AMBER.darkened(0.12)], "disabled": [Color("2e2a1c"), Color("3a3524")]}
			for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
				b.add_theme_color_override(k, AMBER_DARK)
			b.add_theme_color_override("font_disabled_color", Color("7d7660"))
		"ghost":
			boxes = {"normal": [Color(0, 0, 0, 0), Color(0, 0, 0, 0)], "hover": [Color(1, 1, 1, 0.04), Color(0, 0, 0, 0)],
				"pressed": [Color(AMBER, 0.1), Color(0, 0, 0, 0)], "disabled": [Color(0, 0, 0, 0), Color(0, 0, 0, 0)]}
			b.add_theme_color_override("font_color", DIM)
			b.add_theme_color_override("font_hover_color", TEXT)
			b.add_theme_color_override("font_pressed_color", AMBER)
			b.add_theme_color_override("font_disabled_color", Color("4d5148"))
		_:
			boxes = {"normal": [Color(0.07, 0.085, 0.073, 0.92), Color("3a4438")], "hover": [Color("1c1b12"), AMBER],
				"pressed": [Color("2a2613"), AMBER], "disabled": [Color(0.05, 0.06, 0.055, 0.8), Color("222823")]}
			b.add_theme_color_override("font_color", TEXT)
			b.add_theme_color_override("font_hover_color", AMBER)
			b.add_theme_color_override("font_pressed_color", AMBER)
			b.add_theme_color_override("font_hover_pressed_color", AMBER)
			b.add_theme_color_override("font_disabled_color", Color("5b6052"))
	for state in boxes:
		var sb := panel_box(boxes[state][0], boxes[state][1])
		sb.content_margin_left = pad_left
		sb.content_margin_right = 16
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("hover_pressed", b.get_theme_stylebox("pressed"))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


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
			position = Vector2(16, (b.size.y - size.y) * 0.5)

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
		Icons.draw(self, id, Rect2(Vector2.ZERO, size), col, 1.8)
