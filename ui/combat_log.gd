extends PanelContainer
## Scrolling combat log fed by the event player as each beat starts.

const MAX_LINES := 200

var _text: RichTextLabel
var _count := 0


func build() -> void:
	name = "CombatLog"
	custom_minimum_size = Vector2(380, 200)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_following = true
	_text.selection_enabled = false
	_text.add_theme_font_size_override("normal_font_size", 13)
	_text.add_theme_font_size_override("bold_font_size", 13)
	add_child(_text)


func add_line(bbcode: String) -> void:
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
