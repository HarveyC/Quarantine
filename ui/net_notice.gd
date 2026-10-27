extends CanvasLayer
## Short online messages that sit at the top of any screen (lobby, run map or fight): a player
## dropped, rejoined or left, or our own connection is being retried. The newest few show at once.

const Styles := preload("res://ui/styles.gd")

const SHOW_SECS := 6.0
const MAX_LINES := 3

var _box: VBoxContainer
var _lines: Array = []   # [Label, seconds left]


func _init() -> void:
	layer = 40
	_box = Styles.vbox(4)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 56)
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_box)


## Shows `text` for a few seconds. The same text again just restarts its timer.
func notice(text: String) -> void:
	for l in _lines:
		if l[0].text == text:
			l[1] = SHOW_SECS
			l[0].modulate.a = 1.0
			return
	var lab := Styles.caps(text, 16, Styles.AMBER)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.add_theme_constant_override("outline_size", 6)
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_box.add_child(lab)
	_lines.append([lab, SHOW_SECS])
	while _lines.size() > MAX_LINES:
		_drop_line(0)


## The messages on show, oldest first.
func texts() -> Array:
	return _lines.map(func(l: Array) -> String: return l[0].text)


func _drop_line(i: int) -> void:
	_lines[i][0].queue_free()
	_lines.remove_at(i)


func _process(delta: float) -> void:
	var i := 0
	while i < _lines.size():
		_lines[i][1] -= delta
		if _lines[i][1] <= 0.0:
			_drop_line(i)
			continue
		_lines[i][0].modulate.a = clampf(_lines[i][1] / 0.5, 0.0, 1.0)
		i += 1
