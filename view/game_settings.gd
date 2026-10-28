class_name GameSettings
extends RefCounted
## Player settings: graphics, gameplay, accessibility and key bindings, saved to
## user://settings.cfg. View-only (nothing here reaches the rules, so it cannot affect
## online sync). Volumes stay with the Soundscape autoload (user://audio.cfg).
##
## All state is static so any script can read it without a node (tests included).
## The SettingsHost autoload (view/settings_host.gd) loads and applies everything at
## startup, owns the colourblind filter, FPS readout and gamepad pointer, and opens the
## Settings screen (ui/settings_menu.gd) with F10, the gamepad Back button or open_menu().

const PATH := "user://settings.cfg"
const EventPlayer := preload("res://view/event_player.gd")
const Styles := preload("res://ui/styles.gd")

const WINDOW_MODES := ["windowed", "borderless", "fullscreen"]
const RESOLUTIONS := ["1280x720", "1280x800", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
const FPS_CAPS := [30, 60, 90, 120, 144, 0]   # 0 = no cap
const QUALITIES := ["low", "medium", "high", "ultra"]
const GAME_SPEEDS := [1.0, 1.5, 2.0, 3.0]
const COLORBLIND := ["off", "protanopia", "deuteranopia", "tritanopia"]

## What each quality preset turns on. "lights" is how many infection puddles on a map
## get their own light; "lod" is the mesh LOD threshold in pixels (higher = coarser).
const PRESETS := {
	"low": {"sun_shadow": 1024, "spot_shadow": 0, "soft": 0, "ssao": false, "ssil": false,
		"volumetric": false, "glow": true, "msaa": 0, "lod": 4.0, "lights": 0},
	"medium": {"sun_shadow": 2048, "spot_shadow": 2048, "soft": 1, "ssao": true, "ssil": false,
		"volumetric": false, "glow": true, "msaa": 0, "lod": 2.0, "lights": 4},
	"high": {"sun_shadow": 4096, "spot_shadow": 4096, "soft": 2, "ssao": true, "ssil": true,
		"volumetric": true, "glow": true, "msaa": 2, "lod": 1.0, "lights": 8},
	"ultra": {"sun_shadow": 8192, "spot_shadow": 8192, "soft": 4, "ssao": true, "ssil": true,
		"volumetric": true, "glow": true, "msaa": 4, "lod": 1.0, "lights": 12},
}

## Rebindable actions in Settings > Controls order: [action, label, default keys].
## Gamepad bindings are fixed (PAD below); the A button clicks and B goes back (settings_host.gd).
const ACTIONS := [
	["cam_forward", "Pan camera forward", [KEY_W, KEY_UP]],
	["cam_back", "Pan camera back", [KEY_S, KEY_DOWN]],
	["cam_left", "Pan camera left", [KEY_A, KEY_LEFT]],
	["cam_right", "Pan camera right", [KEY_D, KEY_RIGHT]],
	["cam_rotate_left", "Rotate camera left", [KEY_Q]],
	["cam_rotate_right", "Rotate camera right", [KEY_E]],
	["cam_zoom_in", "Zoom in", [KEY_EQUAL, KEY_KP_ADD]],
	["cam_zoom_out", "Zoom out", [KEY_MINUS, KEY_KP_SUBTRACT]],
	["next_soldier", "Next soldier / target (Shift: back)", [KEY_TAB]],
	["prev_soldier", "Previous soldier / target", []],
	["ready", "Ready (fires while aiming)", [KEY_SPACE]],
	["confirm", "Fire / confirm", [KEY_ENTER, KEY_KP_ENTER]],
	["cancel", "Cancel / back", [KEY_ESCAPE]],
	["focus", "Centre on soldier", [KEY_F]],
	["quick_menu", "Quick action menu", [KEY_R]],
	["shot_cams", "Shot cameras on/off", [KEY_C]],
	["mute", "Mute", [KEY_M]],
	["ping", "Ping (tap) / ping wheel (hold)", [KEY_G]],
	["draw", "Draw on the map (hold)", [KEY_V]],
	["action_1", "Action 1 (Shoot)", [KEY_1]],
	["action_2", "Action 2", [KEY_2]],
	["action_3", "Action 3", [KEY_3]],
	["action_4", "Action 4", [KEY_4]],
	["action_5", "Action 5", [KEY_5]],
	["action_6", "Action 6", [KEY_6]],
	["action_7", "Action 7", [KEY_7]],
	["action_8", "Action 8", [KEY_8]],
	["action_9", "Action 9", [KEY_9]],
	["settings", "Settings", [KEY_F10]],
	["tip_more", "Term details (hold over a tooltip)", [KEY_SHIFT]],
]

## Fixed gamepad bindings: action -> [["button", JoyButton] | ["axis", JoyAxis, sign]].
## pad_* and cell_* are gamepad-only: the left stick moves the pointer, the d-pad steps it a cell.
## The stick clicks ping (L3) and draw (R3); a tap of R3 steps the camera zoom (CameraRig.zoom_cycle).
const PAD := {
	"cam_forward": [["axis", JOY_AXIS_RIGHT_Y, -1]], "cam_back": [["axis", JOY_AXIS_RIGHT_Y, 1]],
	"cam_left": [["axis", JOY_AXIS_RIGHT_X, -1]], "cam_right": [["axis", JOY_AXIS_RIGHT_X, 1]],
	"cam_rotate_left": [["axis", JOY_AXIS_TRIGGER_LEFT, 1]], "cam_rotate_right": [["axis", JOY_AXIS_TRIGGER_RIGHT, 1]],
	"ping": [["button", JOY_BUTTON_LEFT_STICK]], "draw": [["button", JOY_BUTTON_RIGHT_STICK]],
	"next_soldier": [["button", JOY_BUTTON_RIGHT_SHOULDER]], "prev_soldier": [["button", JOY_BUTTON_LEFT_SHOULDER]],
	"ready": [["button", JOY_BUTTON_START]], "action_1": [["button", JOY_BUTTON_X]],
	"quick_menu": [["button", JOY_BUTTON_Y]], "settings": [["button", JOY_BUTTON_BACK]],
	"pad_left": [["axis", JOY_AXIS_LEFT_X, -1]], "pad_right": [["axis", JOY_AXIS_LEFT_X, 1]],
	"pad_up": [["axis", JOY_AXIS_LEFT_Y, -1]], "pad_down": [["axis", JOY_AXIS_LEFT_Y, 1]],
	"cell_left": [["button", JOY_BUTTON_DPAD_LEFT]], "cell_right": [["button", JOY_BUTTON_DPAD_RIGHT]],
	"cell_up": [["button", JOY_BUTTON_DPAD_UP]], "cell_down": [["button", JOY_BUTTON_DPAD_DOWN]],
}
const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_START: "Start",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_DPAD_UP: "D-pad", JOY_BUTTON_DPAD_DOWN: "D-pad", JOY_BUTTON_DPAD_LEFT: "D-pad", JOY_BUTTON_DPAD_RIGHT: "D-pad",
}

## Section -> key -> default. Steam Deck gets its own defaults (see defaults()).
const DEFAULTS := {
	"graphics": {"window_mode": "windowed", "resolution": "1600x900", "vsync": true, "fps_cap": 0,
		"quality": "high", "render_scale": 1.0, "show_fps": false},
	"gameplay": {"game_speed": 1.0, "shot_cams": true, "confirm_move": true, "auto_ready": true, "edge_pan": true, "confine_mouse": true, "camera_speed": 1.0},
	"accessibility": {"colorblind": "off", "colorblind_strength": 1.0, "ui_scale": 1.0, "text_scale": 1.0,
		"screen_shake": 1.0},
}

## Interface scale tops out where the UI still has a 1280x720 canvas (the base is 1600x900).
const MAX_UI_SCALE := 1.25

static var values := {}
## action -> Array of keycodes (with modifier masks), only when changed from the default.
static var bindings := {}
static var loaded := false
## Where settings are read and written (tests point this somewhere harmless).
static var file := PATH


# --- reading --------------------------------------------------------------------------------

static func is_steam_deck() -> bool:
	return OS.get_environment("SteamDeck") == "1"


static func defaults() -> Dictionary:
	var d: Dictionary = DEFAULTS.duplicate(true)
	if is_steam_deck():
		d.graphics.window_mode = "fullscreen"
		d.graphics.resolution = "1280x800"
		d.graphics.quality = "medium"
		d.graphics.fps_cap = 60
		d.accessibility.text_scale = 1.15
	return d


static func get_value(section: String, key: String) -> Variant:
	if not loaded:
		_ensure_values()
	return values.get(section, {}).get(key, defaults()[section][key])


static func set_value(section: String, key: String, v: Variant, save_now := true) -> void:
	_ensure_values()
	values[section][key] = v
	_apply_one(section, key)
	if save_now:
		save()


static func preset() -> Dictionary:
	return PRESETS.get(str(get_value("graphics", "quality")), PRESETS.high)


static func game_speed() -> float:
	return float(get_value("gameplay", "game_speed"))


static func auto_ready() -> bool:
	return bool(get_value("gameplay", "auto_ready"))


static func edge_pan() -> bool:
	return bool(get_value("gameplay", "edge_pan"))


static func confine_mouse() -> bool:
	return bool(get_value("gameplay", "confine_mouse"))


static func camera_speed() -> float:
	return float(get_value("gameplay", "camera_speed"))


static func screen_shake() -> float:
	return float(get_value("accessibility", "screen_shake"))


## How many infection puddles may carry a light on this quality preset.
static func puddle_lights() -> int:
	return int(preset().lights)


# --- load / save ----------------------------------------------------------------------------

static func _ensure_values() -> void:
	if values.is_empty():
		values = defaults()


static func load_settings() -> void:
	values = defaults()
	bindings = {}
	var cfg := ConfigFile.new()
	if cfg.load(file) == OK:
		for section in values:
			for key in values[section]:
				var def: Variant = values[section][key]
				var v: Variant = cfg.get_value(section, key, def)
				values[section][key] = _coerce(v, def)
		for a in ACTIONS:
			if cfg.has_section_key("controls", a[0]):
				var keys: Array = []
				for k in cfg.get_value("controls", a[0], []):
					keys.append(int(k))
				bindings[a[0]] = keys
	_validate()
	loaded = true


static func save() -> void:
	var cfg := ConfigFile.new()
	for section in values:
		for key in values[section]:
			cfg.set_value(section, key, values[section][key])
	for action in bindings:
		cfg.set_value("controls", action, bindings[action])
	cfg.save(file)


static func reset_section(section: String) -> void:
	_ensure_values()
	if section == "controls":
		bindings = {}
		apply_input_map()
	else:
		values[section] = defaults()[section].duplicate(true)
		for key in values[section]:
			_apply_one(section, key)
	save()


static func _coerce(v: Variant, def: Variant) -> Variant:
	match typeof(def):
		TYPE_BOOL: return bool(v)
		TYPE_INT: return int(v)
		TYPE_FLOAT: return float(v)
		TYPE_STRING: return str(v)
	return v


## Clamps loaded values so a hand-edited or old file can't break anything.
static func _validate() -> void:
	var d := defaults()
	var g: Dictionary = values.graphics
	if not WINDOW_MODES.has(g.window_mode): g.window_mode = d.graphics.window_mode
	if not QUALITIES.has(g.quality): g.quality = d.graphics.quality
	if not FPS_CAPS.has(g.fps_cap): g.fps_cap = d.graphics.fps_cap
	if _parse_resolution(g.resolution) == Vector2i.ZERO: g.resolution = d.graphics.resolution
	g.render_scale = clampf(g.render_scale, 0.5, 1.0)
	var p: Dictionary = values.gameplay
	if not GAME_SPEEDS.has(p.game_speed): p.game_speed = 1.0
	p.camera_speed = clampf(p.camera_speed, 0.25, 3.0)
	var a: Dictionary = values.accessibility
	if not COLORBLIND.has(a.colorblind): a.colorblind = "off"
	a.colorblind_strength = clampf(a.colorblind_strength, 0.0, 1.0)
	a.ui_scale = clampf(a.ui_scale, 0.75, MAX_UI_SCALE)
	a.text_scale = clampf(a.text_scale, 0.85, 1.5)
	a.screen_shake = clampf(a.screen_shake, 0.0, 1.0)


static func _parse_resolution(s: String) -> Vector2i:
	var p := s.split("x")
	if p.size() != 2 or not p[0].is_valid_int() or not p[1].is_valid_int():
		return Vector2i.ZERO
	var v := Vector2i(int(p[0]), int(p[1]))
	return v if v.x >= 640 and v.y >= 360 else Vector2i.ZERO


# --- applying -------------------------------------------------------------------------------

## Everything at once (startup).
static func apply_all() -> void:
	_ensure_values()
	apply_input_map()
	for section in values:
		for key in values[section]:
			_apply_one(section, key)


static func _root() -> Window:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree != null else null


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func _apply_one(section: String, key: String) -> void:
	var v: Variant = values[section][key]
	match [section, key]:
		["graphics", "window_mode"], ["graphics", "resolution"]:
			_apply_window()
		["graphics", "vsync"]:
			if not _headless():
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v else DisplayServer.VSYNC_DISABLED)
		["graphics", "fps_cap"]:
			Engine.max_fps = int(v)
		["graphics", "quality"], ["graphics", "render_scale"]:
			_apply_quality()
		["gameplay", "shot_cams"]:
			EventPlayer.cinematics = bool(v)
		["accessibility", "ui_scale"]:
			var root := _root()
			if root != null:
				root.content_scale_factor = minf(float(v), MAX_UI_SCALE)
		["accessibility", "text_scale"]:
			Styles.text_scale = float(v)
	if section == "accessibility" and key.begins_with("colorblind") or [section, key] == ["graphics", "show_fps"]:
		var host := _host()
		if host != null:
			host.refresh_overlays()


static func _apply_window() -> void:
	if _headless():
		return
	var mode: String = values.graphics.window_mode
	match mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var size := _parse_resolution(values.graphics.resolution)
			var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			size = Vector2i(mini(size.x, screen.size.x), mini(size.y, screen.size.y))
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


## Shadow atlases, MSAA, mesh LOD and 3D render scale for the whole game. Effects that
## live on each scene's Environment are applied by apply_environment().
static func _apply_quality() -> void:
	var p := preset()
	RenderingServer.directional_shadow_atlas_set_size(int(p.sun_shadow), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(p.soft) as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality(int(p.soft) as RenderingServer.ShadowQuality)
	var root := _root()
	if root == null:
		return
	root.positional_shadow_atlas_size = int(p.spot_shadow)
	root.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X}[int(p.msaa)]
	root.mesh_lod_threshold = float(p.lod)
	var scale := float(values.graphics.render_scale)
	root.scaling_3d_scale = scale
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if scale >= 0.999 or not _forward_plus() else Viewport.SCALING_3D_MODE_FSR
	for env in _environments():
		apply_environment(env)


static func _forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## Every live WorldEnvironment's Environment (so a preset change shows at once).
static func _environments() -> Array[Environment]:
	var out: Array[Environment] = []
	var root := _root()
	if root == null:
		return out
	for n in root.find_children("*", "WorldEnvironment", true, false):
		if (n as WorldEnvironment).environment != null:
			out.append((n as WorldEnvironment).environment)
	return out


## Turns the costly Environment effects on or off for the current preset. Scenes that
## build an Environment call this after setting it up.
static func apply_environment(env: Environment) -> void:
	var p := preset()
	if not env.has_meta("full_glow"):
		env.set_meta("full_glow", env.glow_enabled)
		env.set_meta("full_ssao", env.ssao_enabled)
		env.set_meta("full_ssil", env.ssil_enabled)
		env.set_meta("full_volumetric", env.volumetric_fog_enabled)
	env.glow_enabled = bool(env.get_meta("full_glow")) and bool(p.glow)
	env.ssao_enabled = bool(env.get_meta("full_ssao")) and bool(p.ssao)
	env.ssil_enabled = bool(env.get_meta("full_ssil")) and bool(p.ssil)
	env.volumetric_fog_enabled = bool(env.get_meta("full_volumetric")) and bool(p.volumetric)


# --- key bindings ---------------------------------------------------------------------------

static func keys_for(action: String) -> Array:
	if bindings.has(action):
		return bindings[action]
	for a in ACTIONS:
		if a[0] == action:
			return a[2]
	return []


## Sets one slot (0 primary, 1 secondary) of an action's keys. keycode 0 clears the slot.
## The key is taken off any other action that used it, so one key never does two things.
static func bind_key(action: String, slot: int, keycode: int) -> void:
	var keys: Array = keys_for(action).duplicate()
	while keys.size() <= slot:
		keys.append(0)
	keys[slot] = keycode
	if keycode != 0:
		for a in ACTIONS:
			if a[0] != action and keys_for(a[0]).has(keycode):
				var other: Array = keys_for(a[0]).duplicate()
				other[other.find(keycode)] = 0
				bindings[a[0]] = _trim(other)
	bindings[action] = _trim(keys)
	apply_input_map()
	save()


static func _trim(keys: Array) -> Array:
	var out: Array = []
	for k in keys:
		out.append(k)
	while not out.is_empty() and out.back() == 0:
		out.pop_back()
	return out


## Human-readable key name for a binding ("Shift+Tab", "F10").
static func key_name(keycode: int) -> String:
	return OS.get_keycode_string(keycode) if keycode != 0 else ""


## Short label for an action's keys, e.g. "W / Up". Handy for help text.
static func action_label(action: String) -> String:
	var names: Array = []
	for k in keys_for(action):
		if k != 0:
			names.append(key_name(k))
	return " / ".join(names)


static func pad_label(action: String) -> String:
	if not PAD.has(action):
		return ""
	var names: Array = []
	for b in PAD[action]:
		if b[0] == "button":
			names.append(PAD_NAMES.get(b[1], "Button %d" % b[1]))
		else:
			names.append({JOY_AXIS_LEFT_X: "Left stick", JOY_AXIS_LEFT_Y: "Left stick", JOY_AXIS_RIGHT_X: "Right stick",
				JOY_AXIS_RIGHT_Y: "Right stick", JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}.get(b[1], "Axis"))
	return " / ".join(names)


## Rebuilds the game's InputMap actions from the defaults, the player's key changes and the
## fixed gamepad layout.
static func apply_input_map() -> void:
	for a in ACTIONS:
		_reset_action(a[0])
		for k in keys_for(a[0]):
			if k == 0:
				continue
			var ev := InputEventKey.new()
			ev.keycode = (k & KEY_CODE_MASK) as Key
			ev.shift_pressed = (k & KEY_MASK_SHIFT) != 0
			ev.ctrl_pressed = (k & KEY_MASK_CTRL) != 0
			ev.alt_pressed = (k & KEY_MASK_ALT) != 0
			InputMap.action_add_event(a[0], ev)
	for action in PAD:
		if not InputMap.has_action(action):
			_reset_action(action)
		for b in PAD[action]:
			if b[0] == "button":
				var jb := InputEventJoypadButton.new()
				jb.button_index = b[1]
				InputMap.action_add_event(action, jb)
			else:
				var jm := InputEventJoypadMotion.new()
				jm.axis = b[1]
				jm.axis_value = float(b[2])
				InputMap.action_add_event(action, jm)


## Builds the InputMap actions if nothing has yet (tests and tools run without SettingsHost).
static func ensure_input_map() -> void:
	if not InputMap.has_action("ready"):
		apply_input_map()


static func _reset_action(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action, 0.25)


# --- menu -----------------------------------------------------------------------------------

static func _host() -> Node:
	var root := _root()
	return root.get_node_or_null("SettingsHost") if root != null else null


## Opens the Settings screen (optionally on a tab: graphics, audio, gameplay, accessibility, controls).
static func open_menu(tab := "") -> void:
	var host := _host()
	if host != null:
		host.open_menu(tab)


static func is_menu_open() -> bool:
	var host := _host()
	return host != null and host.is_menu_open()
