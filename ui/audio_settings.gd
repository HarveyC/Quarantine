extends Control
## Sound panel: a volume slider per bus and a mute toggle, saved by the Soundscape autoload.
## Opened with F10 anywhere or the Sound button on the title screen.

signal closed

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const Feel := preload("res://ui/ui_feel.gd")
const LABELS := {"Master": "Master", "Music": "Music", "Ambience": "Ambience", "SFX": "Effects", "UI": "Interface"}
const ICONS := {"Master": "master", "Music": "music", "Ambience": "ambience", "SFX": "effects", "UI": "interface"}

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
	var panel := W.Frame.new(Vector4(26, 22, 26, 24))
	panel.set_look(Color(0.034, 0.05, 0.08, 0.96), Styles.BORDER)
	panel.custom_minimum_size = Vector2(500, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var head := Styles.hbox(10)
	head.add_child(W.Icon.new("sound", Styles.AMBER, 22, 2.0))
	head.add_child(Styles.caps("Sound", 28))
	head.add_child(Styles.spacer())
	head.add_child(W.keycap("F10"))
	box.add_child(head)
	var ss := _soundscape()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for bus in LABELS:
		var ic := W.Icon.new(ICONS[bus], Styles.DIM, 18, 1.7)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(ic)
		grid.add_child(Styles.caps(LABELS[bus], 15, Styles.TEXT))
		var s := HSlider.new()
		s.name = bus
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.custom_minimum_size = Vector2(220, 24)
		s.focus_mode = Control.FOCUS_NONE
		s.value = ss.volumes.get(bus, 1.0) if ss != null else 1.0
		var pct := Styles.mono("%d%%" % roundi(s.value * 100), 13, Styles.DIM)
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
	_mute.text = "Mute everything"
	_mute.tooltip_text = "M mutes in a fight too."
	_mute.focus_mode = Control.FOCUS_NONE
	_mute.button_pressed = ss.is_muted() if ss != null else false
	_mute.toggled.connect(func(on: bool) -> void:
		if ss != null:
			ss.set_muted(on))
	box.add_child(_mute)
	var done := Styles.icon_button("Done", "check", "primary", 17, 46)
	done.pressed.connect(func() -> void: closed.emit())
	box.add_child(done)
	Feel.enter(panel, 0.0, 16.0)


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k != null and k.pressed and k.keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()


func _soundscape() -> Node:
	return get_node_or_null("/root/Soundscape")
