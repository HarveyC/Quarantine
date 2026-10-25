extends RichTextLabel
## Body text on a screen (an item's effect, a perk, a graft, an event choice) with every game
## term in it set in bold and hoverable: resting the pointer on a bold word opens that term's
## hover card (TermTips reads tip_at). Off the bold words it is see-through to the mouse like
## a plain label, so the card, tile or button under it still gets hover and clicks.
##   v.add_child(TermText.make(desc, 15, Styles.DIM, 280))
## Text with no glossary words in it behaves exactly like a plain label.

const Styles := preload("res://ui/styles.gd")

## Term keys this text links, first mention each (tests and screenshots read it).
var terms: Array[String] = []
## Glossary key of the bold word under the pointer ("" when it is on plain words).
var hover_term := ""

var link_color := Styles.TEXT
## Centre every line (set before set_text_terms).
var center := false

var _base_cursor := -1


## A wrapping text block `width` px wide (0 = as wide as its container gives it). `font` is
## the regular face; links use the bold face of the same family.
static func make(text: String, px := 15, color := Styles.TEXT, width := 0.0, font: Font = null, centered := false) -> RichTextLabel:
	var r = new()
	r.setup(text, px, color, width, font, centered)
	return r


func setup(text_in: String, px := 15, color := Styles.TEXT, width := 0.0, font: Font = null, centered := false) -> void:
	center = centered
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_underlined = false
	selection_enabled = false
	if width > 0.0:
		custom_minimum_size.x = width
	else:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_font_size_override("normal_font_size", px)
	add_theme_font_size_override("bold_font_size", px)
	add_theme_color_override("default_color", color)
	# Bold words read a step brighter than the text around them, in the same hue.
	link_color = color.lightened(0.35)
	add_theme_font_override("normal_font", font if font != null else Styles.FONT_BODY)
	add_theme_font_override("bold_font", Styles.FONT_BODY_BOLD)
	set_text_terms(text_in)
	if not meta_hover_started.is_connected(_on_hover):
		meta_hover_started.connect(_on_hover)
		meta_hover_ended.connect(_on_unhover)
		mouse_exited.connect(_on_unhover.bind(null))


## Replaces the text, relinking its terms.
func set_text_terms(s: String) -> void:
	terms = Glossary.scan(s)
	text = ("[center]%s[/center]" if center else "%s") % Glossary.bbcode(s, [], link_color)
	hover_term = ""
	# Nothing to hover: stay out of the mouse's way like a plain label.
	mouse_filter = Control.MOUSE_FILTER_IGNORE if terms.is_empty() else Control.MOUSE_FILTER_PASS


func _enter_tree() -> void:
	_base_cursor = _cursor_under()
	if hover_term == "":
		mouse_default_cursor_shape = _base_cursor as Control.CursorShape


## What TermTips shows for the point under the pointer: the bold word's card, or nothing (and
## then the control under this text gets its turn).
func tip_at(_pos: Vector2) -> Dictionary:
	return {"terms": [hover_term], "ctx": {}} if hover_term != "" and Glossary.has(hover_term) else {}


func _on_hover(meta: Variant) -> void:
	if _base_cursor < 0:
		_base_cursor = _cursor_under()
	hover_term = str(meta)
	mouse_default_cursor_shape = Control.CURSOR_HELP


func _on_unhover(_meta: Variant) -> void:
	hover_term = ""
	mouse_default_cursor_shape = (_base_cursor if _base_cursor >= 0 else _cursor_under()) as Control.CursorShape


## The cursor the control under this text shows (a card's pointing hand), so plain words keep it.
func _cursor_under() -> int:
	var n := get_parent()
	while n is Control:
		if (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return (n as Control).mouse_default_cursor_shape
		n = n.get_parent()
	return Control.CURSOR_ARROW
