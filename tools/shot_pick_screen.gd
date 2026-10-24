extends SceneTree
## Renders the rank-up pick screen to a PNG (dev check): godot -s tools/shot_pick_screen.gd -- out.png

func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://pick.png"
	var run := RunRules.new_run(2, 81)
	RunRules.start_run(run)
	for r in run.squad():
		Progression.grant_perk_pick(run, r)
		r.infection = 30
	var first: Dictionary = run.squad()[0]
	first.prog.bonus_picks = 0
	first.prog.offers.append({"cards": ["hollow_bones", "shared_blood", "rampage"], "source": "nest"})
	root.size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.color = Color("1d1f1c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var screen: PanelContainer = Progression.pick_screen().new()
	screen.theme = preload("res://ui/styles.gd").make_theme()
	screen.position = Vector2(40, 40)
	screen.size = Vector2(1200, 640)
	root.add_child(screen)
	screen.setup(run, null)
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out)
	quit()
