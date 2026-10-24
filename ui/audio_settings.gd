extends Control
## Sound panel: a volume slider per bus and a mute toggle, saved by the Soundscape autoload.
## Opened with F10 anywhere or the Sound button on the title screen.

signal closed

const Styles := preload("res://ui/styles.gd")
const LABELS := {"Master": "Master", "Music": "Music", "Ambience": "Ambience", "SFX": "Effects", "UI": "Interface"}

var _mute: CheckBox
var _tick_at := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Styles.make_theme()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			closed.emit())
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", Styles.panel_box(Styles.BG_RAISED, Styles.AMBER.darkened(0.45)))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(Styles.caps("SOUND", 26, Styles.AMBER))
	var ss := _soundscape()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for bus in LABELS:
		grid.add_child(Styles.label(LABELS[bus], 16, Styles.TEXT))
		var s := HSlider.new()
		s.name = bus
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.custom_minimum_size = Vector2(220, 24)
		s.focus_mode = Control.FOCUS_NONE
		s.value = ss.volumes.get(bus, 1.0) if ss != null else 1.0
		var pct := Styles.label("%d%%" % roundi(s.value * 100), 15, Styles.DIM)
		pct.custom_minimum_size.x = 48
		s.value_changed.connect(func(v: float) -> void:
			pct.text = "%d%%" % roundi(v * 100)
			if ss != null:
				ss.set_volume(bus, v)
				if Time.get_ticks_msec() - _tick_at > 60:
					_tick_at = Time.get_ticks_msec()
					ss.ui("tick"))
		grid.add_child(s)
		grid.add_child(pct)
	_mute = CheckBox.new()
	_mute.text = "Mute all (M in a fight)"
	_mute.focus_mode = Control.FOCUS_NONE
	_mute.button_pressed = ss.is_muted() if ss != null else false
	_mute.toggled.connect(func(on: bool) -> void:
		if ss != null:
			ss.set_muted(on))
	box.add_child(_mute)
	box.add_child(Styles.label("F10 opens this panel anywhere.", 13, Styles.MUTED))
	var done := Button.new()
	done.text = "Done"
	done.focus_mode = Control.FOCUS_NONE
	done.custom_minimum_size = Vector2(0, 40)
	done.pressed.connect(func() -> void: closed.emit())
	box.add_child(done)


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k != null and k.pressed and k.keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()


func _soundscape() -> Node:
	return get_node_or_null("/root/Soundscape")
