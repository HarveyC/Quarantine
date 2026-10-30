extends SceneTree
## Renders the read-only loadout over a run fight to a PNG (dev check):
## godot -s tools/shot_fight_loadout.gd -- out.png [players]

const MAIN := preload("res://scenes/main.tscn")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://fight_loadout.png"
	var players := int(args[1]) if args.size() > 1 else 1
	var l := LocalSession.new()
	l.save_enabled = false
	root.add_child(l)
	l.start_run(players, 31)
	RunAutoplay.settle(l.run, l.submit_run)
	var node: int = l.run.reachable_nodes()[0]
	for p in players:
		l.submit_run({"type": RunRules.VOTE, "player": p, "node": node})
	root.size = Vector2i(1600, 900)
	var v: MissionView = MAIN.instantiate()
	v.auto_start = false
	v.session = l
	root.add_child(v)
	v.start(l.state, true)
	v.player.flush()
	for i in 20:
		await process_frame
	if args.has("hud"):
		root.get_texture().get_image().save_png(out)
		quit()
		return
	v.hud.open_loadout()
	for i in 30:
		await process_frame
	root.get_texture().get_image().save_png(out)
	quit()
