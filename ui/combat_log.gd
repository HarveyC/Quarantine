extends "res://ui/frame.gd"
## Field log, fed by the event player as each beat starts. Shows the latest lines straight on
## the scene over a soft haze (no box), and fades back once nothing new has come in for a while,
## until the pointer is over it.

const IDLE := 0.4      # how far it fades when nothing is happening
const HOLD := 4.0      # seconds a new line keeps it at full strength

const MAX_LINES := 200

var _text: RichTextLabel
var _count := 0
var _fresh := 0.0


func _init() -> void:
	super(Vector4(14, 10, 14, 10))


func build() -> void:
	name = "CombatLog"
	custom_minimum_size = Vector2(320, 150)
	set_haze(0.5)
	var box := Styles.vbox(4)
	add_child(box)
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
	_fresh = HOLD


func line_count() -> int:
	return _count


func clear() -> void:
	_text.clear()
	_count = 0


func _process(delta: float) -> void:
	_fresh = maxf(0.0, _fresh - delta)
	var near := get_global_rect().grow(12).has_point(get_global_mouse_position())
	var want := 1.0 if near or _fresh > 0.0 else IDLE
	# Not `modulate`: the HUD owns that one to hide the log during shot cinematics.
	_text.modulate.a = move_toward(_text.modulate.a, want, delta * 2.5)
	self_modulate.a = _text.modulate.a
