extends RefCounted
## How screens hook into the hover cards (the TermTips autoload draws them):
##   Tips.term(control, "cover")             hovering `control` explains Cover
##   Tips.term(control, "outbreak", {"value": 7})   ...with the live value marked on the diagram
##   Tips.terms(control, ["infection", "lapse"])    first term's card, the rest as links
##   Tips.chip("lapse")                       a small hoverable term chip to put in a layout
##   Tips.auto(label)                         tags a label whose text is a term ("Half cover")
##   Tips.soldier_class(tile, "medic")        the full class card (stats, gun, abilities, passive)
##   Tips.compare(button, func(): ...)        an item compare (GearCompare.compare result)
## Plain `tooltip_text` works too: it is drawn in the same card, with any glossary term in it
## turned into a hoverable link. Hold Shift (or rest the gamepad pointer) for the detailed view.

const Styles := preload("res://ui/styles.gd")

const META := "tip"
const META_TERM := "tip_term"
const META_OFF := "tip_off"


static func term(c: Control, key: String, ctx := {}) -> Control:
	return terms(c, [key], ctx)


static func terms(c: Control, keys: Array, ctx := {}) -> Control:
	var known := keys.filter(func(k) -> bool: return Glossary.has(str(k)))
	if known.is_empty():
		return c
	c.set_meta(META, {"terms": known, "ctx": ctx})
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
	return c


## Hovering `c` shows the soldier class card for `kind` (ClassTip): stats, gun, abilities,
## passive, and how to unlock it when `locked`.
static func soldier_class(c: Control, kind: String, locked := false) -> Control:
	c.set_meta(META, {"terms": [], "ctx": {"class": kind, "locked": locked}})
	c.tooltip_text = ""
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
	return c


## Hovering `c` shows an item compare card (ui/gear/compare_view.gd). `data` is a
## GearCompare.compare() result or a Callable returning one, worked out on first hover.
## `who_color` tints the soldier's name (their player colour); `note` (why the choice is
## blocked) goes on top in red. Takes over the control's plain tooltip.
static func compare(c: Control, data: Variant, who_color := Styles.DIM, note := "") -> Control:
	var memo := {}
	var get_ctx := func() -> Dictionary:
		if memo.is_empty():
			memo["compare"] = data.call() if data is Callable else data
			memo["who_color"] = who_color
			memo["note"] = note
		return memo
	c.set_meta(META, {"terms": [], "ctx": get_ctx})
	c.tooltip_text = ""
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
	return c


## Tags `c` with the term its own text names, if any. Returns the key ("" if none).
static func auto(c: Control, text := "") -> String:
	if text == "" and c is Label:
		text = (c as Label).text
	var key := Glossary.find(text)
	if key != "":
		term(c, key)
	return key


## Keeps `c` (and its children) from showing any card.
static func off(c: Control) -> void:
	c.set_meta(META_OFF, true)


## A small outlined chip naming a term; hovering it opens the term's card.
static func chip(key: String, size := 11, label := "") -> PanelContainer:
	var e := Glossary.entry(key)
	var col := Glossary.tone(key)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.08)
	sb.border_color = Color(col, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(Styles.PILL)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.mouse_default_cursor_shape = Control.CURSOR_HELP
	p.set_meta(META_TERM, key)
	p.add_child(Styles.caps(label if label != "" else str(e.get("name", key)), size, col))
	return p


## The running TermTips host, or null (headless scripts and tests run without autoloads).
static func host() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("TermTips") if tree != null else null


## True while the player asks for the detailed view (Shift, or a resting gamepad pointer).
static func expanded() -> bool:
	var h := host()
	return h != null and h.expanded
