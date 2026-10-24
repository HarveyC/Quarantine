extends Control
## Quick action menu for gamepads (Y) and keys (R): the selected soldier's actions as a
## focusable list. D-pad / left stick to choose, A to use, B to close.

signal picked(key: String)

const Styles := preload("res://ui/styles.gd")
const SettingsMenu := preload("res://ui/settings_menu.gd")

var _title := ""
var _actions: Array[Dictionary] = []
var _first: Button


func setup(title: String, actions: Array[Dictionary]) -> void:
	_title = title
	_actions = actions


func _ready() -> void:
	add_to_group("pad_focus")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = SettingsMenu.make_theme()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.add_theme_stylebox_override("panel", Styles.panel_box(Styles.BG_RAISED, Styles.AMBER.darkened(0.45)))
	center.add_child(panel)
	var box := Styles.vbox(6)
	panel.add_child(box)
	box.add_child(Styles.caps(_title if _title != "" else "Actions", 20, Styles.AMBER))
	for a in _actions:
		var b := Button.new()
		var hot := " [%s]" % a.hotkey if str(a.get("hotkey", "")) != "" else ""
		b.text = str(a.label) + hot
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not a.enabled
		b.custom_minimum_size = Vector2(0, 38)
		if a.has("desc"):
			b.tooltip_text = str(a.desc)
		var key: String = a.key
		b.pressed.connect(func() -> void:
			close()
			picked.emit(key))
		box.add_child(b)
		if _first == null and not b.disabled:
			_first = b
	box.add_child(Styles.label("A use · B close", 13, Styles.MUTED))
	if _first != null and is_inside_tree():
		_first.grab_focus.call_deferred()


func close() -> void:
	if is_queued_for_deletion():
		return
	queue_free()


func _input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("quick_menu"):
		close()
		get_viewport().set_input_as_handled()
	elif (e is InputEventKey or e is InputEventJoypadButton) and not (e.is_action("ui_accept") or e.is_action("ui_up") \
			or e.is_action("ui_down") or e.is_action("ui_left") or e.is_action("ui_right") or e.is_action("ui_focus_next") or e.is_action("ui_focus_prev")):
		# Swallow fight hotkeys while the menu is up.
		get_viewport().set_input_as_handled()
