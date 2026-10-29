extends Control
## A short story scene: a staged 3D shot (StoryStage) behind letterbox bars, a title card, then
## one caption at a time with its speaker, spoken by Soundscape.say() (a voiced caption stays up
## until its line is said). Space, Enter or a click moves to the next caption, Esc skips the
## scene. Local presentation only: nothing here touches the run.
##
## play(spec) with spec = {stage, title, sub, lines: [[speaker, text]], cast, boss, carrier_index}.

signal finished

const Styles := preload("res://ui/styles.gd")
const Stage := preload("res://ui/story/story_stage.gd")

const TITLE_SECS := 2.6
const LINE_BASE := 2.6
const LINE_PER_CHAR := 0.045
const BAR_H := 0.15   # letterbox height, share of the screen; captions sit in the bottom bar
const SPEAKERS := {"OKAFOR": "Major Okafor · Cordon Command", "SOURCE": "The Source",
	"HALE": "Colonel Hale", "HALDEN-VOSS": "Halden-Voss Recovery", "DIRECTOR": "The Director · Halden-Voss", "PROPHET": "The Choir Prophet"}

var spec := {}
var _stage: Node3D
var _vp: SubViewport
var _top: ColorRect
var _bottom: ColorRect
var _title_box: VBoxContainer
var _title: Label
var _sub: Label
var _speaker: Label
var _line: Label
var _hint: Label
var _lines: Array = []
var _i := -1
var _t := 0.0
var _hold := TITLE_SECS
var _fade := 0.0
var _done := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Styles.make_theme()
	modulate.a = 0.0


func play(s: Dictionary) -> void:
	spec = s
	_lines = s.get("lines", [])
	var total := TITLE_SECS
	for l in _lines:
		total += _secs(l[1])
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	holder.add_child(_vp)
	_stage = Stage.new()
	_stage.configure(s.get("stage", "wall"), s.get("cast", []), s.get("boss", ""), s.get("carrier_index", 0), total + 1.0)
	_vp.add_child(_stage)
	_build_overlay()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.6)


func _build_overlay() -> void:
	_top = ColorRect.new()
	_top.color = Color.BLACK
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)
	_bottom = ColorRect.new()
	_bottom.color = Color.BLACK
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bottom)
	_title_box = Styles.vbox(4)
	_title_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_title_box.offset_left = 96
	_title_box.offset_top = -60
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_box)
	_sub = Styles.caps(str(spec.get("sub", "")), 18, Styles.DIM)
	_title = Styles.caps(str(spec.get("title", "")), 64, Styles.TEXT)
	_title_box.add_child(_sub)
	_title_box.add_child(_title)
	var rule := ColorRect.new()
	rule.color = Styles.AMBER
	rule.custom_minimum_size = Vector2(72, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_title_box.add_child(rule)
	_speaker = Styles.caps("", 15, Styles.AMBER)
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_speaker)
	_line = Styles.label("", 26, Styles.TEXT)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_line)
	_hint = Styles.caps("Space next · Esc skip", 12, Styles.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_hint)
	_layout()
	resized.connect(_layout)


## The bottom bar grows to fit a long caption at a big text size, keeping a line free for the
## key hint under it.
func _layout() -> void:
	var w := minf(size.x - 160, 1100.0)
	_line.size = Vector2(w, 0)
	var sp_h := _speaker.get_combined_minimum_size().y
	var line_h := _line.get_combined_minimum_size().y
	var hint_h := _hint.get_combined_minimum_size().y
	var h := size.y * BAR_H
	var bottom_h := maxf(h, 16 + sp_h + 4 + line_h + hint_h + 14)
	_top.position = Vector2.ZERO
	_top.size = Vector2(size.x, h)
	_bottom.position = Vector2(0, size.y - bottom_h)
	_bottom.size = Vector2(size.x, bottom_h)
	_speaker.position = Vector2((size.x - w) * 0.5, size.y - bottom_h + 16)
	_speaker.size = Vector2(w, sp_h)
	_line.position = Vector2((size.x - w) * 0.5, size.y - bottom_h + 16 + sp_h + 4)
	_line.size = Vector2(w, line_h)
	_hint.position = Vector2(size.x - 340, size.y - hint_h - 10)
	_hint.size = Vector2(300, hint_h)
	Styles.fit_width(_title, size.x - 192)


func _secs(text: String) -> float:
	return LINE_BASE + text.length() * LINE_PER_CHAR


func _process(delta: float) -> void:
	if _done or _stage == null:
		return
	_t += delta
	_title_box.modulate.a = clampf(_t / 0.8, 0.0, 1.0) if _i < 0 else maxf(0.0, _title_box.modulate.a - delta * 2.0)
	if _fade > 0.0:
		_fade -= delta
		_line.modulate.a = clampf(1.0 - _fade / 0.25, 0.0, 1.0)
		_speaker.modulate.a = _line.modulate.a
	if _t >= _hold:
		_next()


func _next() -> void:
	_i += 1
	if _i >= _lines.size():
		_finish()
		return
	var l: Array = _lines[_i]
	var who: String = l[0]
	_speaker.text = SPEAKERS.get(who, who).to_upper() if who != "" else ""
	_speaker.add_theme_color_override("font_color", Styles.TEAL if who in ["SOURCE", "PROPHET"] else Styles.AMBER)
	_line.text = l[1]
	_layout()
	_line.add_theme_color_override("font_color", Styles.TEAL if who in ["SOURCE", "PROPHET"] else (Styles.DIM if who == "" else Styles.TEXT))
	_line.modulate.a = 0.0
	_speaker.modulate.a = 0.0
	_fade = 0.25
	_t = 0.0
	_hold = maxf(_secs(l[1]), _speak(who, l[1]) + 0.8)


## Speaks a caption, returns its length (0 if unvoiced or there's no sound).
func _speak(who: String, text: String) -> float:
	var s := get_node_or_null("/root/Soundscape")
	if s == null or who == "":
		return 0.0
	return s.say(who, text, {"scene": true})


func _finish() -> void:
	if _done:
		return
	_done = true
	var s := get_node_or_null("/root/Soundscape")
	if s != null:
		s.stop_speech()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		finished.emit()
		queue_free())


## Skips straight to the end (tests, Esc).
func skip() -> void:
	_finish()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_advance()
		accept_event()


func _unhandled_key_input(ev: InputEvent) -> void:
	if _done or not is_visible_in_tree() or not ev.is_pressed() or ev.is_echo():
		return
	var k := (ev as InputEventKey).keycode
	if k == KEY_ESCAPE:
		skip()
	elif k in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_advance()
	else:
		return
	get_viewport().set_input_as_handled()


func _advance() -> void:
	if _i < 0:
		_t = _hold   # past the title card
	else:
		_next()
