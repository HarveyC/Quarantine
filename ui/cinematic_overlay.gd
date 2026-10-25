extends Control
## Letterbox bars for shot cinematics, and a large HIT / MISS / CRITICAL stamp on impact.
## Who is attacking whom sits in the bottom bar as the attack callout (ui/attack_callout.gd).

const Styles := preload("res://ui/styles.gd")

const BAR_FRACTION := 0.11   # of screen height, each bar

var active := false
var _top: ColorRect
var _bottom: ColorRect
var _result: Label
var _k := 0.0          # letterbox slide 0..1
var _result_t := 0.0


func build() -> void:
	name = "CinematicOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top = _bar()
	_bottom = _bar()
	_result = Styles.label("", 64)
	_result.add_theme_constant_override("outline_size", 12)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_result.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result.pivot_offset = Vector2.ZERO
	add_child(_result)
	_apply()


func _bar() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func set_active(on: bool) -> void:
	active = on
	if not on:
		_result_t = 0.0


## Height of each letterbox bar as it stands now (0 when they are away).
func bar_height() -> float:
	return (size.y if size.y > 0.0 else 900.0) * BAR_FRACTION * _k


func result(word: String, color: Color) -> void:
	_result.text = word
	_result.add_theme_color_override("font_color", color)
	_result_t = 1.4


func result_text() -> String:
	return _result.text if _result_t > 0.0 else ""


func _process(delta: float) -> void:
	_k = move_toward(_k, 1.0 if active else 0.0, delta * 5.0)
	_result_t = maxf(0.0, _result_t - delta)
	_apply()


func _apply() -> void:
	var h := size.y if size.y > 0.0 else 900.0
	var w := size.x if size.x > 0.0 else 1600.0
	var bar := h * BAR_FRACTION * _k
	_top.position = Vector2.ZERO
	_top.size = Vector2(w, bar)
	_bottom.position = Vector2(0, h - bar)
	_bottom.size = Vector2(w, bar)
	_top.visible = _k > 0.0
	_bottom.visible = _k > 0.0
	# Stamp: punches in large, then settles and fades.
	var r := _result_t / 1.4
	_result.modulate.a = clampf(_result_t / 0.4, 0.0, 1.0)
	var s := 1.0 + maxf(0.0, r - 0.85) * 4.0
	_result.scale = Vector2(s, s)
	_result.pivot_offset = _result.size * 0.5
	_result.position.y = h * 0.5 - _result.size.y * 0.5 + h * 0.18
