extends RefCounted
## Shared look for the gear screens (loadout, rewards) in the Bloom style: rounded glass
## panels, pill chips and buttons, amber only for actionable things, teal only for Infection,
## tag colours from GearData.TAG_INFO. Colours and fonts come from ui/styles.gd.

const Styles := preload("res://ui/styles.gd")
const Tips := preload("res://ui/tips/tips.gd")
const TermText := preload("res://ui/tips/term_text.gd")

const PANEL := Color(0.05, 0.07, 0.11, 0.92)
const PANEL_SOFT := Color(0.06, 0.082, 0.125, 0.94)
const BORDER := Styles.BORDER
const BORDER_HI := Styles.BORDER_STRONG
const BG := Styles.GROUND
const TEXT := Styles.TEXT
const DIM := Styles.DIM
const FAINT := Styles.MUTED
const AMBER := Styles.AMBER
const TEAL := Styles.TEAL
const DANGER := Styles.DANGER_TEXT
const GOOD := Styles.HP
const PLAYER_COLORS: Array[Color] = Styles.PLAYERS
const PROTO_COLORS: Array[Color] = [Color("#ffb347"), Color("#3fe0c5"), Color("#ff5fa2"), Color("#6fc3ff")]
## Body copy on cards, a touch dimmer than TEXT.
const COPY := Color("c9d8d8")
## Fill of a held / selected tile.
const HELD := Color(1.0, 0.7, 0.28, 0.1)
## Corner radius used when a caller asks for radius 0 (the old square look).
const RADIUS := 14


## kind: "cond" (headings), "body", "bold", "mono".
static func font(kind: String) -> Font:
	match kind:
		"cond":
			return Styles.FONT_COND_BOLD
		"bold":
			return Styles.FONT_BODY_BOLD
		"mono":
			return Styles.FONT_MONO
		"display":
			return Styles.FONT_DISPLAY
	return Styles.FONT_BODY


static func player_color(p: int) -> Color:
	return PLAYER_COLORS[posmod(p, PLAYER_COLORS.size())]


static func rarity_color(r: String) -> Color:
	return GearData.RARITY_COLORS.get(r, DIM)


static func box(bg := PANEL, border := BORDER, width := 1, radius := 0, pad := 12) -> StyleBoxFlat:
	var sb := Styles.panel_box(bg, border, radius if radius > 0 else RADIUS)
	sb.set_border_width_all(width)
	if width >= 2 and border == AMBER:
		sb.shadow_color = Color(AMBER, 0.25)
		sb.shadow_size = 10
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


## Rules text on a card: wraps at `width` and sets every game term in bold with its hover
## card (TermText). `kind` picks the face like label().
static func text(s: String, size := 15, color := TEXT, width := 0, kind := "body") -> RichTextLabel:
	return TermText.make(s, size, color, width, font(kind))


## Uppercase heading (Unbounded from 22 px up, spaced Outfit below).
static func caps(text: String, size := 15, color := TEXT) -> Label:
	return Styles.caps(text, size, color)


static func mono(text: String, size := 14, color := TEXT) -> Label:
	return label(text, size, color, "mono")


static func wrap(l: Label, width := 0) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Styles.keep_words(l)
	if width > 0:
		l.custom_minimum_size.x = width
	return l


## A tag: a dot and the name in the tag's colour, straight on the card (no pill round it).
## `dim` = dormant / preview look.
static func tag_chip(tag: String, text := "", dim := false) -> PanelContainer:
	var c := GearData.tag_color(tag)
	if dim:
		c = c.darkened(0.45)
	var p := PanelContainer.new()
	var gap := StyleBoxEmpty.new()
	gap.content_margin_right = 8   # without a pill, a little air keeps neighbours apart
	p.add_theme_stylebox_override("panel", gap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var dot := Panel.new()
	dot.add_theme_stylebox_override("panel", box(c, c, 0, Styles.PILL, 0))
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)
	row.add_child(caps(text if text != "" else tag, 13, c))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Tips.term(p, "tag_" + tag.to_lower())
	return p


## Three pips for a tag count toward the set bonus (six, in two groups, for a tag with a capstone);
## `preview` lights the next pip in gold.
static func pips(tag: String, count: int, preview_to := -1) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var c := GearData.tag_color(tag)
	if count == 0 and preview_to <= 0:
		c = Color(Styles.DIM, 0.3)
	var total := GearData.SET_THRESHOLD
	for i in total:
		if i == GearData.SET_THRESHOLD:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(6, 10)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(gap)
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(22 if total == GearData.SET_THRESHOLD else 13, 10)
		var on := i < count
		var gold := preview_to > count and i >= count and i < preview_to
		var lost := preview_to >= 0 and preview_to < count and i >= preview_to and i < count
		var col := AMBER if gold else (DANGER if lost else c)
		var sb := box(col if (on or gold) and not lost else Color(0, 0, 0, 0), col, 1, Styles.PILL, 0)
		if lost:
			sb.bg_color = Color(col, 0.25)
		if gold:
			sb.shadow_color = Color(AMBER, 0.6)
			sb.shadow_size = 6
		pip.add_theme_stylebox_override("panel", sb)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)
	if count > total:
		row.add_child(mono("+%d" % (count - total), 11, c))
	return row


## The glowing amber pill (the one thing to press), or a quiet glass one.
static func button(text: String, primary := false, key := "") -> Button:
	var b := Button.new()
	b.text = text + ("   [%s]" % key if key != "" else "")
	b.add_theme_font_override("font", Styles.FONT_DISPLAY if primary else Styles.FONT_DISPLAY_MEDIUM)
	b.add_theme_font_size_override("font_size", 15 if primary else 13)
	b.custom_minimum_size = Vector2(0, 46)
	b.focus_mode = Control.FOCUS_NONE
	Styles.style_button(b, "primary" if primary else "secondary", 22)
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
