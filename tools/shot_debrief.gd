extends SceneTree
## Renders the end-of-fight debrief over a run fight to a PNG (dev check):
## godot -s tools/shot_debrief.gd -- out.png [players] [lost | beacon]

const MAIN := preload("res://scenes/main.tscn")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://debrief.png"
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
	var s := l.state
	v.start(s, true)
	v.player.flush()
	var squad := s.living(Types.Team.PLAYER).filter(func(u: Unit) -> bool: return u.status.has("sid"))
	var foes := s.living(Types.Team.ENEMY)
	for i in foes.size():
		Rules.deal_damage(s, foes[i], 999, squad[i % 2])
	Rules.deal_damage(s, squad[0], 3, foes[0])
	Infection.add(s, squad[1], 12)
	if args.has("beacon"):   # a lost Hold the beacon: the squad lives, the objective fails
		s.grid.objective = "hold"
		s.objective.kind = "hold"
		s.objective.result = Types.Result.DEFEAT
	elif args.has("lost"):
		for u in squad:
			u.hp = 0
	else:
		s.objective.result = Types.Result.VICTORY
	Rules.check_end(s)
	v.player.flush()
	v.hud.debrief.skip()
	for i in 40:
		await process_frame
	root.get_texture().get_image().save_png(out)
	quit()
