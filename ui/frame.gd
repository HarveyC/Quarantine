extends PanelContainer
## Bloom glass panel: a soft rounded translucent fill with a hairline border. `accent` lights the
## border and a soft glow (the lantern for the active thing, the Bloom for Infected cards); an
## optional owner `stripe` is a short pill on the left edge. Children get `pad` of margin.

const Styles := preload("res://ui/styles.gd")

var fill := Styles.BG
var line := Styles.BORDER
var accent := Styles.AMBER
var corners := true   # kept for callers; Bloom panels glow instead of drawing corner marks
var stripe := Color.TRANSPARENT   # optional owner stripe on the left edge
var radius := Styles.RADIUS

var _box: StyleBoxFlat


func _init(pad := Vector4(14, 10, 14, 10)) -> void:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_look(f: Color, l: Color, a := Styles.AMBER, show_corners := true) -> void:
	fill = f
	line = l
	accent = a
	corners = show_corners
	_box = null
	queue_redraw()


func _draw() -> void:
	if _box == null:
		_box = Styles.panel_box(fill, line, radius)
		# A border in a lit colour (amber or teal) glows softly around the panel.
		if line.a > 0.6 and line.s > 0.4:
			_box.shadow_color = Color(line, 0.28)
			_box.shadow_size = 14
		else:
			_box.shadow_color = Color(0, 0, 0, 0.25)
			_box.shadow_size = 10
			_box.shadow_offset = Vector2(0, 4)
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	if stripe.a > 0.0:
		var h := minf(size.y - radius, 34.0)
		var r := Rect2(-1, (size.y - h) * 0.5, 4, h)
		draw_rect(Rect2(r.position.x, r.position.y + 2, 4, r.size.y - 4), stripe)
		draw_circle(Vector2(1, r.position.y + 2), 2, stripe)
		draw_circle(Vector2(1, r.end.y - 2), 2, stripe)
