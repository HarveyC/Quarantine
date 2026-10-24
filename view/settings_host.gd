extends Node
## Autoloaded as "SettingsHost". Loads and applies GameSettings at startup and owns the parts
## of the settings that need a node:
##   - the Settings screen (F10 or gamepad Back anywhere, or GameSettings.open_menu()),
##   - the colour vision filter (a full-screen daltonize pass over the 3D view and the UI),
##   - the FPS readout,
##   - the gamepad pointer: the left stick moves the mouse pointer, A clicks and B is Escape,
##     so every screen works on a gamepad (Steam Deck) without its own pad code. While a
##     focus-driven screen is up (group "pad_focus": Settings, the quick action menu) the
##     pointer stands down and the d-pad / A / B drive Godot's built-in ui_* focus instead.

const SettingsMenu := preload("res://ui/settings_menu.gd")
const Styles := preload("res://ui/styles.gd")
## Pointer speed at full stick, in viewport pixels per second.
const POINTER_SPEED := 1100.0
const NUDGE_PX := 48.0

const DALTONIZE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform int mode = 0;          // 1 protanopia, 2 deuteranopia, 3 tritanopia
uniform float strength = 1.0;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	mat3 to_lms = mat3(vec3(17.8824, 3.45565, 0.0299566), vec3(43.5161, 27.1554, 0.184309), vec3(4.11935, 3.86714, 1.46709));
	mat3 to_rgb = mat3(vec3(0.0809444479, -0.0102485335, -0.000365296938), vec3(-0.130504409, 0.0540193266, -0.00412161469),
		vec3(0.116721066, -0.113614708, 0.693511405));
	vec3 lms = to_lms * c;
	vec3 sim = lms;
	if (mode == 1) {
		sim.x = 2.02344 * lms.y - 2.52581 * lms.z;
	} else if (mode == 2) {
		sim.y = 0.494207 * lms.x + 1.24827 * lms.z;
	} else {
		sim.z = -0.395913 * lms.x + 0.801109 * lms.y;
	}
	vec3 err = c - to_rgb * sim;
	// Push what the viewer can't see into the channels they can.
	vec3 shift = vec3(0.0, 0.7 * err.r + err.g, 0.7 * err.r + err.b);
	COLOR = vec4(clamp(c + shift * strength, 0.0, 1.0), 1.0);
}
"""

var _menu: Control
var _menu_layer: CanvasLayer
var _filter: ColorRect
var _fps: Label
var _fps_t := 0.0
var _pad_down := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameSettings.load_settings()
	GameSettings.apply_all()
	var filter_layer := CanvasLayer.new()
	filter_layer.layer = 128
	add_child(filter_layer)
	_filter = ColorRect.new()
	_filter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = DALTONIZE
	var m := ShaderMaterial.new()
	m.shader = sh
	_filter.material = m
	filter_layer.add_child(_filter)
	var fps_layer := CanvasLayer.new()
	fps_layer.layer = 127
	add_child(fps_layer)
	_fps = Styles.mono("", 13, Styles.HP)
	_fps.position = Vector2(8, 4)
	fps_layer.add_child(_fps)
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 60
	add_child(_menu_layer)
	refresh_overlays()


func refresh_overlays() -> void:
	if _filter == null:
		return
	var mode := GameSettings.COLORBLIND.find(str(GameSettings.get_value("accessibility", "colorblind")))
	var strength := float(GameSettings.get_value("accessibility", "colorblind_strength"))
	_filter.visible = mode > 0 and strength > 0.0
	(_filter.material as ShaderMaterial).set_shader_parameter("mode", maxi(mode, 1))
	(_filter.material as ShaderMaterial).set_shader_parameter("strength", strength)
	_fps.visible = bool(GameSettings.get_value("graphics", "show_fps"))


# --- the Settings screen --------------------------------------------------------------------

func is_menu_open() -> bool:
	return _menu != null and is_instance_valid(_menu)


func open_menu(tab := "") -> void:
	if is_menu_open():
		if tab != "":
			_menu.show_tab(tab)
		return
	_menu = SettingsMenu.new()
	if tab != "":
		_menu.tab = tab
	_menu.closed.connect(close_menu)
	_menu_layer.add_child(_menu)
	_ui_sound("open")


func close_menu() -> void:
	if is_menu_open():
		_menu.queue_free()
		_ui_sound("close")
	_menu = null


func toggle_menu() -> void:
	if is_menu_open():
		close_menu()
	else:
		open_menu()


func _ui_sound(kind: String) -> void:
	var ss := get_node_or_null("/root/Soundscape")
	if ss != null:
		ss.ui(kind)


# --- input ----------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if e.is_action_pressed("settings") and not is_menu_open():
		open_menu()
		get_viewport().set_input_as_handled()
		return
	var jb := e as InputEventJoypadButton
	if jb == null or _focus_mode():
		return
	match jb.button_index:
		JOY_BUTTON_A:
			if jb.pressed != _pad_down:
				_pad_down = jb.pressed
				_click(jb.pressed)
			get_viewport().set_input_as_handled()
		JOY_BUTTON_B:
			if jb.pressed:
				for down in [true, false]:
					var k := InputEventKey.new()
					k.keycode = KEY_ESCAPE
					k.pressed = down
					Input.parse_input_event(k)
			get_viewport().set_input_as_handled()


func _unhandled_input(e: InputEvent) -> void:
	# D-pad outside a fight nudges the pointer (in a fight the input controller steps cells).
	if e is InputEventJoypadButton and e.pressed and not _focus_mode():
		var dirs := {"cell_left": Vector2.LEFT, "cell_right": Vector2.RIGHT, "cell_up": Vector2.UP, "cell_down": Vector2.DOWN}
		for action in dirs:
			if e.is_action_pressed(action):
				_move_pointer(dirs[action] * NUDGE_PX)
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _fps.visible:
		_fps_t -= delta
		if _fps_t <= 0.0:
			_fps_t = 0.5
			_fps.text = "%d FPS  %.1f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second())]
	if not InputMap.has_action("pad_left") or _focus_mode():
		return
	var v := Input.get_vector("pad_left", "pad_right", "pad_up", "pad_down")
	if v.length() > 0.0:
		# Ease in: small tilts for precise aim, full tilt to cross the screen.
		_move_pointer(v * pow(v.length(), 0.8) * POINTER_SPEED * delta)


func _move_pointer(by: Vector2) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vp := get_viewport()
	var rect := vp.get_visible_rect()
	var to := (vp.get_mouse_position() + by).clamp(rect.position, rect.end - Vector2.ONE)
	vp.warp_mouse(to)


func _click(down: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = down
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	# Synthetic events are read in window pixels (before the UI stretch), like real ones.
	var at := Vector2(DisplayServer.mouse_get_position() - DisplayServer.window_get_position())
	mb.position = at
	mb.global_position = at
	Input.parse_input_event(mb)


## True while a screen that takes gamepad focus is up.
func _focus_mode() -> bool:
	for n in get_tree().get_nodes_in_group("pad_focus"):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			return true
	return false
