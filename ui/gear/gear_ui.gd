extends RefCounted
## Shared look for the gear screens (loadout, rewards), after the approved UI mockups:
## near-black see-through panels with #2c342d borders, amber only for actionable things,
## teal only for Infection, tag colours from GearData.TAG_INFO, Barlow / JetBrains Mono.
## Fonts are picked up from res://ui/fonts/ when the UI module ships them.

const PANEL := Color("#111511")
const PANEL_SOFT := Color("#121613")
const BORDER := Color("#2c342d")
const BORDER_HI := Color("#4d574b")
const BG := Color("#0b0d0c")
const TEXT := Color("#e9e4d4")
const DIM := Color("#a8aa98")
const FAINT := Color("#8c8e7e")
const AMBER := Color("#f2c14e")
const TEAL := Color("#3fe0c5")
const DANGER := Color("#ff8a6e")
const GOOD := Color("#a9c46c")
const PLAYER_COLORS: Array[Color] = preload("res://ui/styles.gd").PLAYERS
const PROTO_COLORS: Array[Color] = [Color("#f2c14e"), Color("#3fe0c5"), Color("#ff5c86"), Color("#6fc3ff")]

const FONT_FILES := {
	"cond": ["res://ui/fonts/BarlowCondensed-Bold.ttf", "res://ui/fonts/BarlowCondensed-SemiBold.ttf"],
	"body": ["res://ui/fonts/Barlow-Regular.ttf"],
	"bold": ["res://ui/fonts/Barlow-SemiBold.ttf"],
	"mono": ["res://ui/fonts/JetBrainsMono-Bold.ttf"],
}
static var _fonts := {}


static func font(kind: String) -> Font:
	if not _fonts.has(kind):
		var f: Font = null
		for path in FONT_FILES.get(kind, []):
			if ResourceLoader.exists(path):
				f = load(path)
				break
		if f == null:
			var sf := SystemFont.new()
			sf.font_names = PackedStringArray(["Barlow Condensed", "Roboto Condensed", "Arial Narrow", "sans-serif"]) \
				if kind == "cond" else PackedStringArray(["JetBrains Mono", "monospace"]) if kind == "mono" \
				else PackedStringArray(["Barlow", "Roboto", "Arial", "sans-serif"])
			sf.font_weight = 700 if kind in ["cond", "bold", "mono"] else 400
			f = sf
		_fonts[kind] = f
	return _fonts[kind]


static func player_color(p: int) -> Color:
	return PLAYER_COLORS[posmod(p, PLAYER_COLORS.size())]


static func rarity_color(r: String) -> Color:
	return GearData.RARITY_COLORS.get(r, DIM)


static func box(bg := PANEL, border := BORDER, width := 1, radius := 0, pad := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


static func label(text: String, size := 15, color := TEXT, kind := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Condensed uppercase heading.
static func caps(text: String, size := 15, color := TEXT) -> Label:
	var l := label(text.to_upper(), size, color, "cond")
	return l


static func mono(text: String, size := 14, color := TEXT) -> Label:
	return label(text, size, color, "mono")


static func wrap(l: Label, width := 0) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if width > 0:
		l.custom_minimum_size.x = width
	return l


## A tag chip: outlined in the tag's colour. `dashed` = dormant / preview look.
static func tag_chip(tag: String, text := "", dim := false) -> PanelContainer:
	var c := GearData.tag_color(tag)
	if dim:
		c = c.darkened(0.45)
	var p := PanelContainer.new()
	var sb := box(Color(0, 0, 0, 0.35), c, 1, 0, 0)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var dot := ColorRect.new()
	dot.color = c
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	row.add_child(caps(text if text != "" else tag, 13, c))
	p.add_child(row)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Three pips for a tag count toward the set bonus; `preview` lights the next pip in gold.
static func pips(tag: String, count: int, preview_to := -1) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var c := GearData.tag_color(tag)
	if count == 0 and preview_to <= 0:
		c = Color("#3a403a")
	for i in GearData.SET_THRESHOLD:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(22, 10)
		var on := i < count
		var gold := preview_to > count and i >= count and i < preview_to
		var lost := preview_to >= 0 and preview_to < count and i >= preview_to and i < count
		var col := AMBER if gold else (DANGER if lost else c)
		var sb := box(col if (on or gold) and not lost else Color(0, 0, 0, 0), col, 1, 0, 0)
		if lost:
			sb.bg_color = Color(col, 0.25)
		if gold:
			sb.shadow_color = Color(AMBER, 0.6)
			sb.shadow_size = 6
		pip.add_theme_stylebox_override("panel", sb)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)
	if count > GearData.SET_THRESHOLD:
		row.add_child(mono("+%d" % (count - GearData.SET_THRESHOLD), 11, c))
	return row


## Amber action button (the one thing to press), or a quiet outlined one.
static func button(text: String, primary := false, key := "") -> Button:
	var b := Button.new()
	b.text = text.to_upper() + ("   [%s]" % key if key != "" else "")
	b.add_theme_font_override("font", font("cond"))
	b.add_theme_font_size_override("font_size", 18 if primary else 16)
	b.custom_minimum_size = Vector2(0, 46)
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		b.add_theme_stylebox_override("normal", box(AMBER, AMBER, 0, 0, 14))
		b.add_theme_stylebox_override("hover", box(AMBER.lightened(0.15), AMBER, 0, 0, 14))
		b.add_theme_stylebox_override("pressed", box(AMBER.darkened(0.15), AMBER, 0, 0, 14))
		b.add_theme_stylebox_override("disabled", box(Color("#3a3524"), Color("#3a3524"), 0, 0, 14))
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, Color("#15130b"))
		b.add_theme_color_override("font_disabled_color", Color("#7d7660"))
	else:
		b.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0.3), BORDER_HI, 1, 0, 14))
		b.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 0.05), DIM, 1, 0, 14))
		b.add_theme_stylebox_override("pressed", box(Color(1, 1, 1, 0.08), TEXT, 1, 0, 14))
		b.add_theme_stylebox_override("disabled", box(Color(0, 0, 0, 0.2), BORDER, 1, 0, 14))
		b.add_theme_color_override("font_color", Color("#c9c6b6"))
		b.add_theme_color_override("font_hover_color", TEXT)
		b.add_theme_color_override("font_disabled_color", Color("#55584c"))
	return b


## Short "+Mark −Guard" diff text between two items' tags.
static func tag_diff(new_id: String, old_id: String) -> String:
	var a := GearData.tags_of(new_id)
	var b := GearData.tags_of(old_id)
	var parts: PackedStringArray = []
	for t in a:
		if not b.has(t):
			parts.append("+" + t)
	for t in b:
		if not a.has(t):
			parts.append("−" + t)
	return " ".join(parts) if not parts.is_empty() else "same tag"


static func soldier_name(r: Dictionary) -> String:
	var cls: String = UnitData.SOLDIERS.get(r.get("kind", ""), {}).get("name", str(r.get("kind", "")).capitalize())
	var nm: String = r.get("name", "")
	return ("%s %s" % [cls, nm]) if nm != "" else cls


static func short_name(r: Dictionary) -> String:
	var nm: String = r.get("name", "")
	return nm if nm != "" else UnitData.SOLDIERS.get(r.get("kind", ""), {}).get("name", "Soldier")


static func class_name_of(r: Dictionary) -> String:
	return UnitData.SOLDIERS.get(r.get("kind", ""), {}).get("name", str(r.get("kind", "")).capitalize())


static func play(node: Node, sound: String) -> void:
	var path := "res://audio/%s.wav" % sound
	if not ResourceLoader.exists(path) or not node.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = -8.0
	node.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
