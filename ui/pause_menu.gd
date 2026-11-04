extends Control
## System menu: Resume, Settings, Controls, Leave to title and Quit to desktop (both ask for a
## second click while a game is running). The game keeps running underneath, since online play
## can't pause. Opened by Esc anywhere (SettingsHost) and by the map's Menu button.

signal closed
signal leave_requested

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const Feel := preload("res://ui/ui_feel.gd")
const SETTINGS_SCRIPT := "res://view/game_settings.gd"

## Key, icon and what it does, for the Controls page.
const CONTROLS := [
	["LMB", "interface", "Select a soldier, move, pick a target"],
	["RMB / Esc", "close", "Cancel, then deselect"],
	["1-9", "ability", "Actions on the bar"],
	["Tab", "squad", "Next soldier / next target"],
	["Space", "check", "Fire while aiming, else Ready"],
	["WASD", "route", "Pan the camera"],
	["Q / E", "turn", "Rotate"],
	["Wheel", "reveal", "Zoom"],
	["F", "marksman", "Focus the selected soldier"],
	["C", "shoot", "Shot cameras on or off"],
	["M", "mute", "Mute"],
	["F10", "sound", "Sound settings"],
]

## False on the title screen, where there is no game to leave.
var show_leave := true
var _leave: Button
var _quit: Button
var _main: Control
var _controls: Control


func _ready() -> void:
	add_to_group("pause_menu")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Styles.make_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.009, 0.015, 0.028, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_main = _build_main()
	_controls = _build_controls()
	center.add_child(_main)
	center.add_child(_controls)
	_controls.visible = false
	Feel.enter(_main, 0.0, 18.0)
	Feel.sound("open")


func _build_main() -> Control:
	var f := W.Frame.new(Vector4(28, 24, 28, 26))
	f.custom_minimum_size = Vector2(380, 0)
	var v := Styles.vbox(10)
	f.add_child(v)
	var head := Styles.hbox(10)
	head.add_child(W.Icon.new("pause", Styles.AMBER, 22, 2.0))
	head.add_child(Styles.caps("Menu", 30))
	v.add_child(head)
	v.add_child(_gap(6))
	_button(v, "Resume", "play", "primary", close)
	_button(v, "Settings", "settings", "secondary", _open_settings)
	_button(v, "Controls", "keyboard", "secondary", _show_controls)
	v.add_child(_gap(6))
	if show_leave:
		_leave = _button(v, "Leave to title", "leave", "ghost", func() -> void: _confirm(_leave, "CLICK AGAIN TO LEAVE", leave_requested.emit))
	_quit = _button(v, "Quit to desktop", "power", "ghost", func() -> void:
		_confirm(_quit, "CLICK AGAIN TO QUIT", _quit_game, show_leave))
	return f


func _build_controls() -> Control:
	var f := W.Frame.new(Vector4(28, 24, 28, 26))
	f.custom_minimum_size = Vector2(620, 0)
	var v := Styles.vbox(14)
	f.add_child(v)
	var head := Styles.hbox(10)
	head.add_child(W.Icon.new("keyboard", Styles.AMBER, 22, 2.0))
	head.add_child(Styles.caps("Controls", 30))
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 10)
	for c in CONTROLS:
		var row := Styles.hbox(10)
		var keys := Styles.hbox(4)
		keys.custom_minimum_size.x = 96
		for k in str(c[0]).split(" / "):
			keys.add_child(W.keycap(k, 12))
		row.add_child(keys)
		row.add_child(W.Icon.new(c[1], Styles.DIM, 16, 1.6))
		row.add_child(Styles.label(c[2], 14, Styles.TEXT))
		grid.add_child(row)
	v.add_child(grid)
	_button(v, "Back", "arrow_left", "secondary", func() -> void:
		_controls.visible = false
		_main.visible = true
		Feel.enter(_main, 0.0, 0.0))
	return f


func _button(parent: Control, text: String, icon: String, kind: String, cb: Callable) -> Button:
	var b := Styles.icon_button(text, icon, kind, 18, 50)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _gap(px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = px
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _show_controls() -> void:
	_main.visible = false
	_controls.visible = true
	Feel.enter(_controls, 0.0, 0.0)
	Feel.sound("page")


func _open_settings() -> void:
	if ResourceLoader.exists(SETTINGS_SCRIPT):
		var gs: Script = load(SETTINGS_SCRIPT)
		if gs.has_method("open_menu"):
			gs.call("open_menu")
			return
	var ss := get_node_or_null("/root/Soundscape")
	if ss != null:
		ss.toggle_settings()


## Destructive buttons ask for a second click. `ask` false skips the check (nothing to lose).
func _confirm(b: Button, text: String, go: Callable, ask := true) -> void:
	if ask and b.get_meta("armed", false) == false:
		b.set_meta("armed", true)
		b.text = text
		Styles.style_button(b, "secondary", 16 + 31)
		b.add_theme_color_override("font_color", Styles.DANGER_TEXT)
		return
	go.call()


## Leaves any session cleanly (online: tells the others) before closing the window.
func _quit_game() -> void:
	var app := get_tree().root.get_node_or_null("App")
	if app != null and app.get("session") != null and app.has_method("_leave"):
		app.call("_leave")
	get_tree().quit()


func close() -> void:
	Feel.sound("close")
	closed.emit()


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _controls.visible:
			_controls.visible = false
			_main.visible = true
		else:
			close()
