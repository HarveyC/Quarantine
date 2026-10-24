extends "res://ui/frame.gd"
## Field log, fed by the event player as each beat starts. Shows the latest lines.

const MAX_LINES := 200

var _text: RichTextLabel
var _count := 0


func _init() -> void:
	super(Vector4(14, 10, 14, 10))


func build() -> void:
	name = "CombatLog"
	custom_minimum_size = Vector2(320, 150)
	var box := Styles.vbox(4)
	add_child(box)
	box.add_child(Styles.caps("Field log", 12, Styles.DIM))
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_following = true
	_text.selection_enabled = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 13)
	_text.add_theme_font_size_override("bold_font_size", 13)
	_text.add_theme_constant_override("line_separation", 3)
	box.add_child(_text)


func add_line(bbcode: String) -> void:
	if bbcode == "":
		return
	if _count >= MAX_LINES:
		_text.remove_paragraph(0)
		_count -= 1
	_text.append_text(("\n" if _count > 0 else "") + bbcode)
	_count += 1


func line_count() -> int:
	return _count


func clear() -> void:
	_text.clear()
	_count = 0
