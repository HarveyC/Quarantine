extends SceneTree
## Dev check for Settings: renders the Settings tabs over a fight, the quick action menu, the
## colour vision filters, and times frames on each quality preset.
## godot -s tools/shot_settings.gd -- out_dir [bench]
## Needs a real renderer (xvfb-run ...). Frame times under a software renderer only compare
## presets with each other; they say nothing about real GPUs.

const MAIN := preload("res://scenes/main.tscn")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	root.size = Vector2i(1280, 720)
	GameSettings.file = "user://shot_settings.cfg"
	GameSettings.load_settings()
	GameSettings.apply_all()
	await process_frame
	var v: MissionView = MAIN.instantiate()
	v.auto_start = false
	root.add_child(v)
	v.start(MissionView.default_mission(6), true)
	v.player.flush()
	_lift(v)
	for i in 30:
		await process_frame
	var host: Node = root.get_node("SettingsHost")
	for tab in ["graphics", "accessibility", "controls"]:
		host.open_menu(tab)
		await _frames(8)
		_save("%s/settings_%s.png" % [out, tab])
	host.close_menu()
	await _frames(4)
	v.input.cycle(1)
	v.input.open_quick_menu()
	await _frames(8)
	_save("%s/quick_menu.png" % out)
	for m in v.hud.get_parent().get_children():
		if m.is_in_group("pad_focus"):
			m.queue_free()
	await _frames(4)
	for mode in GameSettings.COLORBLIND:
		GameSettings.set_value("accessibility", "colorblind", mode)
		await _frames(6)
		_save("%s/colour_%s.png" % [out, mode])
	GameSettings.set_value("accessibility", "colorblind", "off")
	if args.has("bench"):
		for q in GameSettings.QUALITIES:
			GameSettings.set_value("graphics", "quality", q)
			v.start(MissionView.default_mission(6), true)   # rebuild so lights follow the preset
			v.player.flush()
			_lift(v)
			await _frames(20)
			var t0 := Time.get_ticks_usec()
			await _frames(60)
			print("[bench] %-6s %.1f ms/frame" % [q, (Time.get_ticks_usec() - t0) / 60000.0])
			_save("%s/quality_%s.png" % [out, q])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.file))
	quit()


## The software renderer under xvfb comes out much darker than a real GPU: lift it.
func _lift(v: MissionView) -> void:
	for we in v.find_children("*", "WorldEnvironment", true, false):
		(we as WorldEnvironment).environment.ambient_light_energy = 2.2
		(we as WorldEnvironment).environment.tonemap_exposure = 1.8


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(path: String) -> void:
	root.get_texture().get_image().save_png(path)
	print("[shot_settings] ", path)
