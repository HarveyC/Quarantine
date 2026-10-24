extends RefCounted
## Finds text the player can't fully read: labels and buttons whose text is wider than they
## are (cut or "..."), wrapped text with lines past the bottom, rich text taller than its box,
## and text that sits off screen or spills out of the panel or clipping box around it.
## Used by tools/shot_ui.gd (`report`) and tests/test_ui_overflow.gd.
##   var problems := UiOverflow.scan(root)   # -> ["<path>: <what>", ...]
## Text inside a ScrollContainer is only checked against the scroll box's width, since the
## player can scroll to the rest. Tag a control with set_meta("overflow_ok", true) to skip it
## and everything under it (for text that slides in from off screen on purpose), or
## set_meta("spill_ok", true) for a caption that hangs outside its box by design but must
## still stay on screen.

## Pixels of slack before something counts, so sub-pixel layout and font hinting don't trip it.
const SLACK := 2.0


static func scan(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var view := Rect2(Vector2.ZERO, root.get_viewport().get_visible_rect().size) if root is Viewport \
			else root.get_viewport().get_visible_rect()
	for c in root.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree() or _skipped(ctl) or (_text(ctl) == "" and not ctl is BaseButton):
			continue
		if ctl.modulate.a < 0.05 or _faded(ctl):
			continue
		var what := _check(ctl, view)
		if what != "":
			var t := _text(ctl) if _text(ctl) != "" else "(icon button)"
			out.append("%s \"%s\": %s" % [_short_path(ctl), t.left(40).replace("\n", " "), what])
	return out


static func _check(ctl: Control, view: Rect2) -> String:
	var r := ctl.get_global_rect()
	if r.size.x < 1 or r.size.y < 1:
		return "has no room (%dx%d)" % [r.size.x, r.size.y]
	var scroll := _scroll_parent(ctl)
	var cut := _cut(ctl)
	if cut != "":
		return cut
	if scroll == null:
		if not _inside(r, view):
			return "off screen (%s, screen %s)" % [_rect_str(r), _rect_str(view)]
	if _skipped(ctl, "spill_ok"):
		return ""
	for a in _boxes(ctl):
		var box: Rect2 = a.get_global_rect()
		if a == scroll:
			if r.position.x < box.position.x - SLACK or r.end.x > box.end.x + SLACK:
				return "wider than its scroll box %s (%s)" % [_short_path(a), _rect_str(r)]
			break
		if not _inside(r, box):
			return "spills out of %s (%s in %s)" % [_short_path(a), _rect_str(r), _rect_str(box)]
	return ""


## Text cut inside the control itself.
static func _cut(ctl: Control) -> String:
	if ctl is Label:
		var l := ctl as Label
		if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
			var font := l.get_theme_font("font")
			var fsize := l.get_theme_font_size("font_size")
			var room := l.size.x - _box_w(l.get_theme_stylebox("normal"))
			for word in l.text.split(" ", false):
				for part in word.split("\n", false):
					if _text_width(part, font, fsize) > room + SLACK:
						return "breaks the word \"%s\" (%dpx wide, %dpx of room)" % [part, _text_width(part, font, fsize), room]
			var lines := l.get_line_count()
			var shown := l.get_visible_line_count()
			if shown < lines:
				return "shows %d of %d lines" % [shown, lines]
			return ""
		var need := _text_width(l.text, l.get_theme_font("font"), l.get_theme_font_size("font_size"))
		need += _box_w(l.get_theme_stylebox("normal"))
		if need > l.size.x + SLACK:
			return "text needs %dpx, has %dpx" % [need, l.size.x]
	elif ctl is Button:
		var b := ctl as Button
		if b.text == "":
			return ""
		var need := _text_width(b.text, b.get_theme_font("font"), b.get_theme_font_size("font_size"))
		need += _box_w(b.get_theme_stylebox("normal"))
		if b.icon != null and not b.expand_icon:
			need += b.icon.get_width() + b.get_theme_constant("h_separation")
		if need > b.size.x + SLACK:
			return "text needs %dpx, has %dpx" % [need, b.size.x]
	elif ctl is RichTextLabel:
		var t := ctl as RichTextLabel
		if not t.scroll_active and not t.fit_content:
			var h := t.get_content_height()
			if h > t.size.y + SLACK:
				return "text needs %dpx tall, has %dpx" % [h, t.size.y]
	return ""


## Ancestors whose edges the text should stay inside: panels and buttons draw a box around it,
## clip_contents cuts it. Stops at the first scroll box.
static func _boxes(ctl: Control) -> Array[Control]:
	var out: Array[Control] = []
	var p := ctl.get_parent()
	while p != null:
		if p is Control:
			var pc := p as Control
			if pc is ScrollContainer:
				out.append(pc)
				break
			if pc.clip_contents or pc is PanelContainer or pc is Panel or pc is Button:
				if pc.size.x >= 1 and pc.size.y >= 1:
					out.append(pc)
		elif p is CanvasLayer or p is Window:
			break
		p = p.get_parent()
	return out


static func _scroll_parent(ctl: Control) -> ScrollContainer:
	var p := ctl.get_parent()
	while p != null and not (p is CanvasLayer or p is Window):
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


static func _skipped(ctl: Node, key := "overflow_ok") -> bool:
	var p := ctl
	while p != null:
		if p.has_meta(key):
			return true
		p = p.get_parent()
	return false


## True when an ancestor is fully faded out (a screen mid-transition).
static func _faded(ctl: Node) -> bool:
	var p := ctl.get_parent()
	while p != null:
		if p is CanvasItem and (p as CanvasItem).modulate.a < 0.05:
			return true
		if p is CanvasLayer and not (p as CanvasLayer).visible:
			return true
		p = p.get_parent()
	return false


static func _text(ctl: Control) -> String:
	if ctl is Label:
		return (ctl as Label).text.strip_edges()
	if ctl is Button:
		return (ctl as Button).text.strip_edges()
	if ctl is RichTextLabel:
		return (ctl as RichTextLabel).get_parsed_text().strip_edges()
	return ""


static func _text_width(text: String, font: Font, size: int) -> float:
	var w := 0.0
	for line in text.split("\n"):
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	return ceilf(w)


static func _box_w(sb: StyleBox) -> float:
	return sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT) if sb != null else 0.0


static func _inside(r: Rect2, box: Rect2) -> bool:
	return r.position.x >= box.position.x - SLACK and r.position.y >= box.position.y - SLACK \
			and r.end.x <= box.end.x + SLACK and r.end.y <= box.end.y + SLACK


static func _rect_str(r: Rect2) -> String:
	return "%d,%d %dx%d" % [r.position.x, r.position.y, r.size.x, r.size.y]


static func _short_path(n: Node) -> String:
	var parts := PackedStringArray()
	var p := n
	while p != null and parts.size() < 4 and not (p is Window):
		parts.insert(0, p.name if not String(p.name).begins_with("@") else p.get_class())
		p = p.get_parent()
	return "/".join(parts)
