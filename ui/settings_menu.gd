extends Control
## Settings screen: Graphics, Audio, Gameplay, Accessibility and Controls tabs. Every change
## applies and saves at once (GameSettings, or the Soundscape autoload for volumes).
## Opened by SettingsHost (F10 anywhere, gamepad Back, or GameSettings.open_menu()).
## Fully usable on a gamepad: d-pad / stick moves focus, A changes, LB/RB switch tabs, B closes.

signal closed

const Styles := preload("res://ui/styles.gd")
const TABS := [["graphics", "Graphics"], ["audio", "Audio"], ["gameplay", "Gameplay"],
	["accessibility", "Accessibility"], ["controls", "Controls"]]
const VOLUME_LABELS := {"Master": "Master", "Music": "Music", "Ambience": "Ambience", "SFX": "Effects", "UI": "Interface"}
const MODIFIER_KEYS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]

var tab := "graphics"
var _tab_buttons := {}
var _content: VBoxContainer
var _scroll: ScrollContainer
var _capture: Array = []        # [action, slot, Button] while waiting for a key
var _tick_at := 0


## The game theme plus a visible amber focus frame, so gamepad focus is always clear.
static func make_theme() -> Theme:
	var t := Styles.make_theme()
	var focus := Styles.panel_box(Color(0, 0, 0, 0), Styles.AMBER)
	focus.draw_center = false
	focus.set_border_width_all(2)
	for cls in ["Button", "CheckBox", "OptionButton", "HSlider", "CheckButton"]:
		t.set_stylebox("focus", cls, focus)
	t.set_font("font", "OptionButton", Styles.FONT_COND)
	t.set_font_size("font_size", "OptionButton", Styles.fs(16))
	t.set_font_size("font_size", "CheckBox", Styles.fs(15))
	t.set_font_size("font_size", "PopupMenu", Styles.fs(15))
	return t


func _ready() -> void:
	add_to_group("pad_focus")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_tab_buttons.clear()
	theme = make_theme()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 0)
	panel.add_theme_stylebox_override("panel", Styles.panel_box(Styles.BG_RAISED, Styles.AMBER.darkened(0.45)))
	center.add_child(panel)
	var box := Styles.vbox(10)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(box)
	var head := Styles.hbox(10)
	head.add_child(Styles.caps("Settings", 26, Styles.AMBER))
	head.add_child(Styles.spacer())
	if GameSettings.is_steam_deck():
		head.add_child(Styles.label("Steam Deck detected: defaults tuned for it", 13, Styles.MUTED))
	box.add_child(head)
	var tabs := Styles.hbox(6)
	tabs.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(tabs)
	for t in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(128, 36)
		var id: String = t[0]
		b.pressed.connect(func() -> void: show_tab(id))
		tabs.add_child(b)
		_tab_buttons[id] = b
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 430)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	box.add_child(_scroll)
	_content = Styles.vbox(8)
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	var foot := Styles.hbox(8)
	foot.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(foot)
	foot.add_child(Styles.label("F10 / gamepad Back opens this anywhere · LB/RB switch tabs", 13, Styles.MUTED))
	foot.add_child(Styles.spacer())
	var reset := Button.new()
	reset.text = "Restore defaults"
	reset.custom_minimum_size = Vector2(150, 38)
	reset.pressed.connect(_reset_tab)
	foot.add_child(reset)
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(110, 38)
	done.pressed.connect(func() -> void: closed.emit())
	foot.add_child(done)
	show_tab(tab)


func show_tab(id: String) -> void:
	tab = id
	_capture = []
	for k in _tab_buttons:
		_tab_buttons[k].button_pressed = k == id
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	match id:
		"graphics": _graphics()
		"audio": _audio()
		"gameplay": _gameplay()
		"accessibility": _accessibility()
		"controls": _controls()
	if _tab_buttons.has(id) and is_inside_tree():
		_tab_buttons[id].grab_focus.call_deferred()


func _reset_tab() -> void:
	if tab == "audio":
		var ss := _soundscape()
		if ss != null:
			for bus in ss.VOLUME_BUSES:
				ss.set_volume(bus, ss.VOLUME_BUSES[bus])
			ss.set_muted(false)
	else:
		GameSettings.reset_section(tab)
	if tab == "accessibility":
		_build()   # text size may have changed
	else:
		show_tab(tab)


# --- tabs -----------------------------------------------------------------------------------

func _graphics() -> void:
	_section("Display")
	_option("Window", "graphics", "window_mode", [["windowed", "Windowed"], ["borderless", "Borderless fullscreen"], ["fullscreen", "Fullscreen"]])
	var res: Array = []
	for r in GameSettings.RESOLUTIONS:
		res.append([r, r.replace("x", " × ")])
	_option("Window size", "graphics", "resolution", res, "Used in windowed mode.")
	_toggle("V-sync", "graphics", "vsync")
	var caps: Array = []
	for f in GameSettings.FPS_CAPS:
		caps.append([f, "Unlimited" if f == 0 else "%d FPS" % f])
	_option("Frame rate cap", "graphics", "fps_cap", caps, "30 or 60 saves battery on a Steam Deck or laptop.")
	_toggle("Show FPS", "graphics", "show_fps")
	_section("Quality")
	_option("Preset", "graphics", "quality", [["low", "Low"], ["medium", "Medium"], ["high", "High"], ["ultra", "Ultra"]],
		"Low: no ambient occlusion, volumetric fog or floodlight shadows, coarser models in the distance. Steam Deck: Medium.")
	_slider("3D resolution", "graphics", "render_scale", 0.5, 1.0, 0.05, "%d%%", 100.0,
		"Below 100% renders the 3D view smaller and upscales it (FSR). The interface stays sharp.")


func _audio() -> void:
	var ss := _soundscape()
	_section("Volume")
	if ss == null:
		_content.add_child(Styles.label("Sound is not available.", 15, Styles.MUTED))
		return
	for bus in VOLUME_LABELS:
		var s := _slider_row(VOLUME_LABELS[bus], 0.0, 1.0, 0.05, float(ss.volumes.get(bus, 1.0)), "%d%%", 100.0)
		s.value_changed.connect(func(v: float) -> void:
			ss.set_volume(bus, v)
			if Time.get_ticks_msec() - _tick_at > 60:
				_tick_at = Time.get_ticks_msec()
				ss.ui("tick"))
	var mute := CheckBox.new()
	mute.text = "Mute all (M in a fight)"
	mute.button_pressed = ss.is_muted()
	mute.toggled.connect(func(on: bool) -> void: ss.set_muted(on))
	_row("", mute)


func _gameplay() -> void:
	_section("Pace")
	_option("Game speed", "gameplay", "game_speed", [[1.0, "Normal"], [1.5, "Fast (1.5×)"], [2.0, "Faster (2×)"], [3.0, "Fastest (3×)"]],
		"How fast moves, shots and enemy turns play out. 2× and up skip the shot cameras.")
	_toggle("Shot cameras", "gameplay", "shot_cams", "Over-the-shoulder camera for your own shots (C in a fight).")
	_section("Camera")
	_toggle("Edge scrolling", "gameplay", "edge_pan", "Pan when the mouse touches the screen edge.")
	_slider("Camera pan speed", "gameplay", "camera_speed", 0.25, 3.0, 0.25, "%d%%", 100.0)
	_section("Tips")
	var tips := CheckBox.new()
	tips.text = "On"
	tips.button_pressed = Onboarding.hints_enabled()
	tips.toggled.connect(func(on: bool) -> void: Onboarding.set_hints_enabled(on))
	_row("Show tips", tips, "First-time hints that explain each screen and rule as you meet it.")
	var reset := Button.new()
	reset.text = "Show all tips again"
	reset.custom_minimum_size = Vector2(0, 36)
	reset.pressed.connect(func() -> void:
		Onboarding.reset_hints()
		Onboarding.set_hints_enabled(true)
		tips.button_pressed = true
		reset.text = "Tips reset")
	_row("Reset tips", reset)


func _accessibility() -> void:
	_section("Colour")
	_option("Colour vision", "accessibility", "colorblind", [["off", "Standard"], ["protanopia", "Protanopia (red-weak)"],
		["deuteranopia", "Deuteranopia (green-weak)"], ["tritanopia", "Tritanopia (blue-weak)"]],
		"Shifts colours the game relies on (amber orders, teal Infection, red danger, player colours) into ones you can tell apart.")
	_slider("Colour filter strength", "accessibility", "colorblind_strength", 0.0, 1.0, 0.1, "%d%%", 100.0)
	_section("Size")
	_option("Interface scale", "accessibility", "ui_scale", [[0.75, "75%"], [0.9, "90%"], [1.0, "100%"], [1.15, "115%"], [1.3, "130%"], [1.5, "150%"]])
	_option("Text size", "accessibility", "text_scale", [[0.85, "Small"], [1.0, "Normal"], [1.15, "Large"], [1.3, "Larger"], [1.5, "Largest"]],
		"Applies to each screen as it opens.", true)
	_section("Motion")
	_slider("Screen shake", "accessibility", "screen_shake", 0.0, 1.0, 0.1, "%d%%", 100.0, "Also scales the recoil punch on shots. 0% turns both off.")


func _controls() -> void:
	_section("Keyboard (click a key, then press the new one · Delete clears · Esc keeps)")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(grid)
	for h in ["Action", "Key", "Alternate", "Gamepad"]:
		grid.add_child(Styles.caps(h, 13, Styles.MUTED))
	for a in GameSettings.ACTIONS:
		var name_l := Styles.label(a[1], 15, Styles.TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_l)
		for slot in 2:
			var b := Button.new()
			b.custom_minimum_size = Vector2(130, 32)
			_set_key_text(b, a[0], slot)
			var action: String = a[0]
			var s: int = slot
			b.pressed.connect(func() -> void: _start_capture(action, s, b))
			grid.add_child(b)
		grid.add_child(Styles.label(GameSettings.pad_label(a[0]), 14, Styles.DIM))
	_section("Gamepad")
	for line in ["Left stick moves the pointer · D-pad steps it one cell · A clicks / moves / fires · B cancels",
			"X shoots · Y quick action menu · LB/RB cycle soldiers or targets · Start = Ready",
			"Right stick pans · LT/RT rotate · L3/R3 zoom · Back opens Settings"]:
		var l := Styles.label(line, 14, Styles.DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		_content.add_child(l)


# --- row builders ---------------------------------------------------------------------------

func _section(text: String) -> void:
	var l := Styles.caps(text, 15, Styles.AMBER.darkened(0.1))
	if _content.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 4
		_content.add_child(gap)
	_content.add_child(l)


func _row(label: String, control: Control, hint := "") -> void:
	var row := Styles.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var l := Styles.label(label, 15, Styles.TEXT)
	l.custom_minimum_size.x = 220
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	_content.add_child(row)
	if hint != "":
		var h := Styles.label(hint, 13, Styles.MUTED)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD
		h.custom_minimum_size.x = 700
		_content.add_child(h)


func _option(label: String, section: String, key: String, choices: Array, hint := "", rebuild := false) -> OptionButton:
	var ob := OptionButton.new()
	var cur: Variant = GameSettings.get_value(section, key)
	for i in choices.size():
		ob.add_item(str(choices[i][1]), i)
		if _same(choices[i][0], cur):
			ob.select(i)
	ob.custom_minimum_size = Vector2(0, 36)
	ob.item_selected.connect(func(i: int) -> void:
		GameSettings.set_value(section, key, choices[i][0])
		if rebuild:
			_build.call_deferred())
	_row(label, ob, hint)
	return ob


func _toggle(label: String, section: String, key: String, hint := "") -> CheckBox:
	var cb := CheckBox.new()
	cb.text = "On"
	cb.button_pressed = bool(GameSettings.get_value(section, key))
	cb.toggled.connect(func(on: bool) -> void:
		GameSettings.set_value(section, key, on))
	_row(label, cb, hint)
	return cb


func _slider(label: String, section: String, key: String, lo: float, hi: float, step: float, fmt: String, mul: float, hint := "") -> HSlider:
	var s := _slider_row(label, lo, hi, step, float(GameSettings.get_value(section, key)), fmt, mul, hint)
	s.value_changed.connect(func(v: float) -> void: GameSettings.set_value(section, key, v))
	return s


func _slider_row(label: String, lo: float, hi: float, step: float, value: float, fmt: String, mul: float, hint := "") -> HSlider:
	var wrap := Styles.hbox(10)
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(260, 28)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pct := Styles.mono(fmt % roundi(value * mul), 14, Styles.DIM)
	pct.custom_minimum_size.x = 56
	s.value_changed.connect(func(v: float) -> void: pct.text = fmt % roundi(v * mul))
	wrap.add_child(s)
	wrap.add_child(pct)
	_row(label, wrap, hint)
	return s


static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return absf(float(a) - float(b)) < 0.001
	return str(a) == str(b)


# --- key capture ----------------------------------------------------------------------------

func _set_key_text(b: Button, action: String, slot: int) -> void:
	var keys: Array = GameSettings.keys_for(action)
	var k: int = keys[slot] if slot < keys.size() else 0
	b.text = GameSettings.key_name(k) if k != 0 else "—"


func _start_capture(action: String, slot: int, b: Button) -> void:
	if not _capture.is_empty():
		_set_key_text(_capture[2], _capture[0], _capture[1])
	_capture = [action, slot, b]
	b.text = "Press a key…"


func _input(e: InputEvent) -> void:
	if not visible:
		return
	var k := e as InputEventKey
	if not _capture.is_empty():
		if k == null or not k.pressed or k.echo or MODIFIER_KEYS.has(k.keycode):
			if k != null:
				get_viewport().set_input_as_handled()
			return
		var action: String = _capture[0]
		var slot: int = _capture[1]
		var b: Button = _capture[2]
		_capture = []
		get_viewport().set_input_as_handled()
		if k.keycode == KEY_ESCAPE:
			_set_key_text(b, action, slot)
			return
		GameSettings.bind_key(action, slot, 0 if k.keycode in [KEY_DELETE, KEY_BACKSPACE] else int(k.get_keycode_with_modifiers()))
		show_tab("controls")   # a key may have moved off another action
		return
	var settings_key := e.is_action_pressed("settings") if InputMap.has_action("settings") else (k != null and k.pressed and not k.echo and k.keycode == KEY_F10)
	if e.is_action_pressed("ui_cancel") or settings_key:
		closed.emit()
		get_viewport().set_input_as_handled()
		return
	if InputMap.has_action("next_soldier") and (e.is_action_pressed("next_soldier") or e.is_action_pressed("prev_soldier")):
		var back := e.is_action_pressed("prev_soldier") or (k != null and k.shift_pressed)
		var i := 0
		for j in TABS.size():
			if TABS[j][0] == tab:
				i = j
		show_tab(TABS[posmod(i + (-1 if back else 1), TABS.size())][0])
		get_viewport().set_input_as_handled()
		return
	if (k != null or e is InputEventJoypadButton) and not _gui_nav(e):
		# Swallow fight hotkeys and the like while the screen is up.
		get_viewport().set_input_as_handled()


static func _gui_nav(e: InputEvent) -> bool:
	for a in ["ui_accept", "ui_select", "ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev", "ui_page_up", "ui_page_down"]:
		if e.is_action(a):
			return true
	return false


func _soundscape() -> Node:
	return get_node_or_null("/root/Soundscape")
