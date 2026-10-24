extends PanelContainer
## Panel with a flat translucent fill, a hairline border and amber corner brackets
## (top-left and bottom-right). Draws itself; children get `pad` of margin.

const Styles := preload("res://ui/styles.gd")

var fill := Styles.BG
var line := Styles.BORDER
var accent := Styles.AMBER
var corners := true
var stripe := Color.TRANSPARENT   # optional owner stripe on the left edge

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
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, fill)
	draw_rect(r.grow(-0.5), line, false, 1.0)
	if stripe.a > 0.0:
		draw_rect(Rect2(0, 0, 4, size.y), stripe)
	if corners:
		var k := 11.0
		draw_polyline(PackedVector2Array([Vector2(0, k), Vector2(0, 0), Vector2(k, 0)]), accent, 2.0)
		draw_polyline(PackedVector2Array([Vector2(size.x - k, size.y), Vector2(size.x, size.y), Vector2(size.x, size.y - k)]), accent, 2.0)
