extends SceneTree
## Renders the run's node map screen mid-act to a PNG (dev check):
##   godot -s tools/shot_run_map.gd -- out.png [players=2] [hover=1] [start]
## With "start" the squad is still at the drop point.
## Row 1 is cleared, the squad is hurt and infected, in co-op the host has voted, and the first
## open route is hovered.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://run_map.png"
	var players: int = int(args[1]) if args.size() > 1 else 2
	var hover: bool = args.size() <= 2 or args[2] != "0"
	root.size = Vector2i(1920, 1080)
	var session := LocalSession.new()
	session.save_enabled = false
	root.add_child(session)
	session.start_run(players, 4242)
	var run := session.run
	run.steps.clear()
	run.phase = RunState.Phase.MAP
	var row1 := run.map.filter(func(n: Dictionary) -> bool: return n.row == 1)
	row1.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.links.size() > b.links.size())
	var first: Dictionary = row1[0]
	if not args.has("start"):
		first.visited = true
		run.node = first.id
		run.row = 1
	run.outbreak = 4
	run.supplies = 100
	var hurt := [3, 0, 5, 1]
	var inf := [12, 38, 0, 61]
	for i in run.squad().size():
		var r: Dictionary = run.squad()[i]
		r.hp = maxi(1, r.max_hp - hurt[i % 4])
		r.infection = inf[i % 4]
	if players > 1:
		var opts := run.reachable_nodes()
		session.player_names = {0: "Harvey", 1: "Kestrel"}
		run.votes[0] = opts[opts.size() - 1]
	var view := RunView.new()
	root.add_child(view)
	view.setup(session)
	for i in 6:
		await process_frame
	if hover:
		var target: int = run.reachable_nodes()[0]
		view._map.set_hover(target)
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out)
	quit()
