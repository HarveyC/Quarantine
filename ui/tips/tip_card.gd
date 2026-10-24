extends PanelContainer
## One hover card. Compact: the term's icon and name, one line, a diagram and its big numbers.
## Expanded (Shift held): a few more short lines and related terms as chips. Glossary words in
## any line are links; hovering a link or chip opens a card for it next to this one.
## Uses the theme's TooltipPanel box so it follows whatever the UI theme is.

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const Tips := preload("res://ui/tips/tips.gd")
const TipArt := preload("res://ui/tips/tip_art.gd")

const WIDTH := 300.0
const WIDE := 340.0

var terms: Array = []
var text := ""
var ctx := {}
var expanded := false
var pad := false
## Glossary key of the first term ("" for a card that is only text).
var key := ""
## Where the card was asked for: the pointer for a root card, the link's rect for a nested one.
var anchor := Rect2()
## The card whose link opened this one (null for a root card).
var parent_card: Control
## The term link under the pointer inside one of this card's text lines ("" if none).
var hover_term := ""

var _box: VBoxContainer


func _init(card_terms: Array, card_text := "", card_ctx := {}) -> void:
	terms = card_terms
	text = card_text
	ctx = card_ctx
	key = str(terms[0]) if not terms.is_empty() else ""
	name = "TipCard"
	theme_type_variation = "TooltipPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = Styles.vbox(7)
	add_child(_box)
	_build()


func set_expanded(on: bool, on_pad := false) -> void:
	if on == expanded and on_pad == pad:
		return
	expanded = on
	pad = on_pad
	_build()


## The term the pointer is on, if `c` (the hovered control) is a chip or link in this card.
func term_at(c: Control) -> String:
	var n: Node = c
	while n != null and n != self:
		if n.has_meta(Tips.META_TERM):
			return str(n.get_meta(Tips.META_TERM))
		if n is RichTextLabel:
			return hover_term
		n = n.get_parent()
	return ""


func width() -> float:
	return WIDE if expanded else WIDTH


func _build() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	hover_term = ""
	var w := width()
	custom_minimum_size.x = w
	var inner := w - 26.0
	if text != "":
		_box.add_child(rich(Glossary.plain(text) if key != "" else text, inner, 14 if key == "" else 13,
			Styles.TEXT if key == "" else Styles.DIM))
		if key != "":
			_box.add_child(_rule())
	var see: Array = []
	if key != "":
		_term_block(_box, key, inner, ctx, expanded)
		see = terms.slice(1) + Glossary.entry(key).get("see", [])
	else:
		# A plain tooltip: its linked terms become compact blocks in the detailed view.
		var found := Glossary.scan(text)
		if expanded:
			for k in found.slice(0, 2):
				_box.add_child(_rule())
				_term_block(_box, k, inner, {}, false)
		see = found.slice(2) if expanded else []
	if expanded:
		var related: Array = []
		for k in see:
			if Glossary.has(str(k)) and str(k) != key and not related.has(str(k)):
				related.append(str(k))
		if not related.is_empty():
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 5)
			flow.add_theme_constant_override("v_separation", 5)
			flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			for k in related.slice(0, 8):
				flow.add_child(Tips.chip(k, 10))
			_box.add_child(flow)
	elif _has_more():
		_box.add_child(_footer())
	reset_size()


func _has_more() -> bool:
	if key == "":
		return not Glossary.scan(text).is_empty()
	var e := Glossary.entry(key)
	return not e.get("more", []).is_empty() or not e.get("see", []).is_empty() or terms.size() > 1


## "[Shift] more" (or the gamepad hint) at the bottom of a compact card.
func _footer() -> Control:
	var row := Styles.hbox(6)
	row.add_child(Styles.spacer())
	if pad:
		row.add_child(DwellRing.new())
		row.add_child(Styles.caps("hold still for more", 10, Styles.MUTED, false))
	else:
		row.add_child(W.keycap("Shift", 10))
		row.add_child(Styles.caps("more", 10, Styles.MUTED, false))
	return row


static func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Styles.BORDER_SOFT
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Header, line, diagram and numbers for `k` into `box`; `full` adds the extra lines.
func _term_block(box: VBoxContainer, k: String, inner: float, art_ctx: Dictionary, full: bool) -> void:
	var e := Glossary.entry(k)
	var col := Glossary.tone(k)
	var head := Styles.hbox(8)
	var ic := W.Icon.new(str(e.get("icon", "dot")), col, 18, 1.8)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	head.add_child(Styles.caps(str(e.name), 17, col))
	head.add_child(Styles.spacer())
	var kind := Styles.caps(str(e.get("kind", "")), 10, Styles.MUTED, false)
	kind.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(kind)
	box.add_child(head)
	box.add_child(rich(str(e.get("line", "")), inner, 14, Styles.TEXT, [k]))
	var art := str(e.get("art", ""))
	if TipArt.supports(art):
		var actx: Dictionary = e.get("art_ctx", {}).duplicate()
		actx.merge(art_ctx, true)
		box.add_child(TipArt.new(art, actx, col, inner))
	var stats: Array = e.get("stats", [])
	if not stats.is_empty():
		var row := Styles.hbox(0)
		for i in stats.size():
			var cell := Styles.vbox(0)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_child(Styles.mono(str(stats[i][0]), 20, col if i == 0 else Styles.TEXT))
			var l := Styles.caps(Glossary.plain(str(stats[i][1])), 10, Styles.MUTED, false)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = inner / stats.size() - 6
			cell.add_child(l)
			row.add_child(cell)
		box.add_child(row)
	if full:
		for line in e.get("more", []):
			var r := Styles.hbox(8)
			var dot := ColorRect.new()
			dot.color = col
			dot.custom_minimum_size = Vector2(4, 4)
			dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var dot_box := MarginContainer.new()
			dot_box.add_theme_constant_override("margin_top", 8)
			dot_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot_box.add_child(dot)
			r.add_child(dot_box)
			r.add_child(rich(str(line), inner - 12, 13, Styles.DIM, [k]))
			box.add_child(r)


## A wrapped text line whose glossary words are hoverable links.
func rich(s: String, w: float, px: int, col: Color, skip: Array = []) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(w, 0)
	r.add_theme_font_size_override("normal_font_size", Styles.fs(px))
	r.add_theme_color_override("default_color", col)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.mouse_default_cursor_shape = Control.CURSOR_ARROW
	r.meta_underlined = true
	r.text = Glossary.bbcode(s, skip)
	r.meta_hover_started.connect(func(m: Variant) -> void: hover_term = str(m))
	r.meta_hover_ended.connect(func(_m: Variant) -> void: hover_term = "")
	return r


## Ring that fills while the gamepad pointer rests on a card (TermTips.dwell).
class DwellRing extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(12, 12)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var h := Tips.host()
		var p: float = h.dwell_progress() if h != null else 0.0
		var c := size * 0.5
		draw_arc(c, 5.5, 0, TAU, 24, Styles.BORDER_STRONG, 2.0, true)
		if p > 0.0:
			draw_arc(c, 5.5, -PI * 0.5, -PI * 0.5 + TAU * p, 24, Styles.AMBER, 2.0, true)
