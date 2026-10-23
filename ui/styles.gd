extends RefCounted
## Dark, readable HUD theme and small widget helpers.

const BG := Color(0.07, 0.08, 0.075, 0.88)
const BG_SOFT := Color(0.12, 0.13, 0.12, 0.92)
const BORDER := Color(0.28, 0.31, 0.27)
const TEXT := Color(0.86, 0.87, 0.82)
const MUTED := Color(0.58, 0.6, 0.56)


static func panel_box(bg := BG, border := BORDER, radius := 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("outline_size", "Label", 3)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	t.set_stylebox("normal", "Button", panel_box(BG_SOFT, BORDER))
	t.set_stylebox("hover", "Button", panel_box(Color(0.18, 0.2, 0.17), Color(0.5, 0.56, 0.45)))
	t.set_stylebox("pressed", "Button", panel_box(Color(0.22, 0.3, 0.2), Color(0.6, 0.75, 0.45)))
	t.set_stylebox("disabled", "Button", panel_box(Color(0.08, 0.08, 0.08, 0.8), Color(0.18, 0.18, 0.18)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.4, 0.38))
	t.set_color("font_pressed_color", "Button", Color(0.95, 1.0, 0.85))
	t.set_stylebox("background", "ProgressBar", panel_box(Color(0.05, 0.05, 0.05, 0.9), Color(0.2, 0.2, 0.2), 2))
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	return t


static func label(text: String, size := 15, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
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
	fill.set_corner_radius_all(2)
	p.add_theme_stylebox_override("fill", fill)
