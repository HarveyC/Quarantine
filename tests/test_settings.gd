extends TestCase
## Settings: save/load, validation, key rebinding, quality presets and the Settings screen.

const MAIN := preload("res://scenes/main.tscn")
const Styles := preload("res://ui/styles.gd")
const SettingsMenu := preload("res://ui/settings_menu.gd")
const QuickMenu := preload("res://ui/quick_menu.gd")
const CameraRig := preload("res://view/camera_rig.gd")
const TEST_FILE := "user://test_settings.cfg"


func _fresh() -> void:
	GameSettings.file = TEST_FILE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE))
	GameSettings.load_settings()
	GameSettings.apply_input_map()


func _restore() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE))
	GameSettings.load_settings()
	GameSettings.apply_all()
	GameSettings.file = GameSettings.PATH


func test_values_round_trip_through_the_file() -> void:
	_fresh()
	assert_eq(GameSettings.get_value("graphics", "quality"), "high", "default preset")
	GameSettings.set_value("graphics", "quality", "low")
	GameSettings.set_value("gameplay", "game_speed", 2.0)
	GameSettings.set_value("accessibility", "colorblind", "deuteranopia")
	GameSettings.values = {}
	GameSettings.load_settings()
	assert_eq(GameSettings.get_value("graphics", "quality"), "low", "preset saved")
	assert_eq(GameSettings.game_speed(), 2.0, "speed saved")
	assert_eq(GameSettings.get_value("accessibility", "colorblind"), "deuteranopia", "colour mode saved")
	_restore()


func test_bad_values_fall_back_to_safe_ones() -> void:
	_fresh()
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", "potato")
	cfg.set_value("graphics", "resolution", "12x")
	cfg.set_value("gameplay", "game_speed", 40.0)
	cfg.set_value("accessibility", "ui_scale", 9.0)
	cfg.set_value("accessibility", "screen_shake", -1.0)
	cfg.save(TEST_FILE)
	GameSettings.load_settings()
	assert_eq(GameSettings.get_value("graphics", "quality"), "high", "unknown preset")
	assert_eq(GameSettings.get_value("graphics", "resolution"), "1600x900", "broken resolution")
	assert_eq(GameSettings.game_speed(), 1.0, "speed")
	assert_eq(GameSettings.get_value("accessibility", "ui_scale"), GameSettings.MAX_UI_SCALE, "ui scale clamped")
	assert_eq(GameSettings.screen_shake(), 0.0, "shake clamped")
	_restore()


func test_rebinding_moves_a_key_and_drives_the_fight() -> void:
	_fresh()
	GameSettings.bind_key("ready", 0, KEY_K)
	assert_eq(GameSettings.keys_for("ready"), [KEY_K], "ready is K")
	GameSettings.bind_key("focus", 0, KEY_K)
	assert_eq(GameSettings.keys_for("ready"), [], "K moved off ready")
	assert_eq(GameSettings.keys_for("focus"), [KEY_K], "and onto focus")
	GameSettings.bind_key("ready", 1, KEY_J)
	assert_eq(GameSettings.keys_for("ready"), [0, KEY_J], "alternate slot")
	var v: MissionView = MAIN.instantiate()
	v.start(MissionView.default_mission(1234))
	v.player.flush()
	var k := InputEventKey.new()
	k.keycode = KEY_SPACE
	k.pressed = true
	v.input._unhandled_input(k)
	assert_true(not v.state.ready.get(0, false), "Space no longer readies")
	k.keycode = KEY_J
	v.input._unhandled_input(k)
	assert_eq(v.state.ready.get(0), true, "J readies")
	v.free()
	GameSettings.reset_section("controls")
	assert_eq(GameSettings.keys_for("ready"), [KEY_SPACE], "defaults restored")
	_restore()


func test_gamepad_buttons_reach_the_fight() -> void:
	_fresh()
	var v: MissionView = MAIN.instantiate()
	v.start(MissionView.default_mission(1234))
	v.player.flush()
	var first := v.input.selected_id
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_RIGHT_SHOULDER
	b.pressed = true
	v.input._unhandled_input(b)
	assert_true(v.input.selected_id != first and v.input.selected_id >= 0, "RB cycles soldiers")
	v.input.step_cursor(Vector2i(1, 0))
	assert_true(v.input.hover_cell != v.input.NO_CELL, "d-pad parks the pointer on a cell")
	var from := v.input.hover_cell
	v.input.step_cursor(Vector2i(1, 0))
	assert_eq(absi(v.input.hover_cell.x - from.x) + absi(v.input.hover_cell.y - from.y), 1, "one cell per press")
	b.button_index = JOY_BUTTON_START
	v.input._unhandled_input(b)
	assert_eq(v.state.ready.get(0), true, "Start readies")
	v.free()
	_restore()


func test_quality_presets_switch_costly_effects() -> void:
	_fresh()
	var env := Environment.new()
	env.ssao_enabled = true
	env.ssil_enabled = true
	env.volumetric_fog_enabled = true
	env.glow_enabled = true
	GameSettings.set_value("graphics", "quality", "low")
	GameSettings.apply_environment(env)
	assert_true(not env.ssao_enabled and not env.ssil_enabled and not env.volumetric_fog_enabled, "low drops SSAO, SSIL, volumetrics")
	assert_true(env.glow_enabled, "glow stays (the infection look)")
	assert_eq(GameSettings.puddle_lights(), 0, "no puddle lights on low")
	GameSettings.set_value("graphics", "quality", "high")
	GameSettings.apply_environment(env)
	assert_true(env.ssao_enabled and env.ssil_enabled and env.volumetric_fog_enabled, "high restores them")
	var off := Environment.new()
	GameSettings.apply_environment(off)
	assert_true(not off.ssao_enabled, "a preset never turns on what a scene left off")
	_restore()


func test_accessibility_scales_text_and_shake() -> void:
	_fresh()
	GameSettings.set_value("accessibility", "text_scale", 1.3)
	var l := Styles.label("x", 20)
	assert_eq(l.get_theme_font_size("font_size"), 26, "text 130%")
	GameSettings.set_value("accessibility", "text_scale", 1.0)
	GameSettings.set_value("accessibility", "screen_shake", 0.0)
	var rig := CameraRig.new()
	rig.shake(1.0)
	rig.kick(1.0)
	assert_eq(rig._shake, 0.0, "no shake")
	assert_eq(rig._kick, 0.0, "no recoil punch")
	rig.free()
	GameSettings.set_value("gameplay", "shot_cams", false)
	assert_true(not preload("res://view/event_player.gd").cinematics, "shot cams follow the setting")
	_restore()


func test_confirm_move_defaults_on() -> void:
	_fresh()
	assert_true(bool(GameSettings.get_value("gameplay", "confirm_move")), "two-click moves are the default")
	_restore()


func test_settings_screen_builds_every_tab() -> void:
	_fresh()
	var menu: Control = SettingsMenu.new()
	menu._build()
	for t in SettingsMenu.TABS:
		menu.show_tab(t[0])
		assert_true(menu._content.get_child_count() > 1, "tab %s has rows" % t[0])
	menu.show_tab("controls")
	var grid: GridContainer = menu._content.get_child(1)
	var blocks: int = SettingsMenu.CONTROL_BLOCKS
	var rows := ceili(GameSettings.ACTIONS.size() / float(blocks))
	assert_eq(grid.get_child_count(), (rows + 1) * blocks * 3, "every rebindable action sits in a block")
	menu.free()
	_restore()


func test_quick_menu_lists_actions() -> void:
	var m: Control = QuickMenu.new()
	var acts: Array[Dictionary] = [{"key": "shoot", "label": "Shoot", "enabled": true, "hotkey": "1"},
		{"key": "hunker", "label": "Hunker", "enabled": false, "hotkey": "2"}]
	m.setup("Trooper", acts)
	m._ready()
	var picked := []
	m.picked.connect(func(k: String) -> void: picked.append(k))
	m._first.pressed.emit()
	assert_eq(picked, ["shoot"], "A on the first enabled action uses it")
	m.free()
