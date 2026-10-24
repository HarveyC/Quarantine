extends SceneTree
## Renders one UI screen to a PNG at 1920x1080 (dev check for the UI polish pass):
##   godot -s tools/shot_ui.gd -- <screen> out.png [players=2]
## Screens: title, lobby, sound, map, event, depot, hospital, survivors, reward, loadout, doctrine,
## kit, rankup, hud, aim, debrief, lost, runend, pause.
## Run under xvfb-run with --rendering-driver opengl3 (software GL renders the 3D board dark).

const MAIN := preload("res://scenes/main.tscn")
const GearDemo := preload("res://ui/gear/gear_demo.gd")
const MainMenu := preload("res://ui/main_menu.gd")


class StubSession:
	extends RefCounted
	var run: RunState
	var players: Array[int] = []
	var player_names := {0: "Harvey", 1: "Kestrel"}

	func local_players() -> Array[int]:
		return players

	func is_local(p: int) -> bool:
		return players.has(p)

	func submit_run(action: Dictionary) -> void:
		if run.phase == RunState.Phase.NODE:
			NodeRules.apply(run, action)
		else:
			RunRules.apply(run, action)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var screen: String = args[0] if args.size() > 0 else "title"
	var out: String = args[1] if args.size() > 1 else "user://ui.png"
	var players := int(args[2]) if args.size() > 2 else 2
	root.size = Vector2i(1920, 1080)
	match screen:
		"title":
			var m := MainMenu.new()
			root.add_child(m)
		"lobby":
			var net := NetSession.new()
			root.add_child(net)
			var m := MainMenu.new()
			root.add_child(m)
			await process_frame
			net.host(24690, "Harvey")
			if players > 1:
				net.lobby[7] = {"player": 1, "name": "Kestrel"}
			m.show_lobby(net)
		"sound":
			var m := MainMenu.new()
			root.add_child(m)
			await process_frame
			root.get_node("/root/Soundscape").toggle_settings()
		"map", "runend":
			var session := LocalSession.new()
			session.save_enabled = false
			root.add_child(session)
			session.start_run(players, 4242)
			var run := session.run
			run.steps.clear()
			run.phase = RunState.Phase.MAP
			session.player_names = {0: "Harvey", 1: "Kestrel"}
			var row1 := run.map.filter(func(n: Dictionary) -> bool: return n.row == 1)
			var first: Dictionary = row1[0]
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
				run.votes[0] = run.reachable_nodes()[-1]
			if screen == "runend":
				run.phase = RunState.Phase.ENDED
				run.result = Types.Result.DEFEAT
				run.fights_won = 4
			var view := RunView.new()
			root.add_child(view)
			view.setup(session)
			if screen == "map":
				for i in 4:
					await process_frame
				view._map.set_hover(run.reachable_nodes()[0])
		"event", "depot", "hospital", "survivors":
			var run := RunRules.new_run(players, 31)
			GearRun.init_run(run)
			RunRules.start_run(run)
			run.phase = RunState.Phase.NODE
			run.supplies = 140
			run.intel = 2
			for r in run.squad():
				r.hp = maxi(1, r.max_hp - 2)
				r.infection = 30
			NodeRules.enter(run, screen, "the_trial" if screen == "event" else "")
			_full_screen(NodeRules.screen(screen).new(), run)
		"reward", "loadout", "doctrine", "kit":
			var run := GearDemo.make_run(screen)
			var ctl: Control = (GearRun.loadout_screen() if screen == "loadout" else GearRun.reward_screen()).new()
			_full_screen(ctl, run)
		"rankup":
			var run := RunRules.new_run(players, 81)
			RunRules.start_run(run)
			for r in run.squad():
				Progression.grant_perk_pick(run, r)
				r.infection = 30
			var first: Dictionary = run.squad()[0]
			first.prog.bonus_picks = 0
			first.prog.offers.append({"cards": ["hollow_bones", "shared_blood", "rampage"], "source": "nest"})
			_full_screen(Progression.pick_screen().new(), run)
		"hud", "aim", "debrief", "lost", "pause":
			await _mission(screen, players)
	for i in 30:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("[shot-ui] saved ", out)
	quit()


func _full_screen(ctl: Control, run: RunState) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.025)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var s := StubSession.new()
	s.run = run
	s.players.assign(run.players)
	root.add_child(ctl)
	ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctl.setup(run, s)


func _mission(screen: String, players: int) -> void:
	var l := LocalSession.new()
	l.save_enabled = false
	root.add_child(l)
	l.start_run(players, 31)
	RunAutoplay.settle(l.run, l.submit_run)
	var node: int = l.run.reachable_nodes()[0]
	for p in players:
		l.submit_run({"type": RunRules.VOTE, "player": p, "node": node})
	var v: MissionView = MAIN.instantiate()
	v.auto_start = false
	v.session = l
	root.add_child(v)
	var s := l.state
	v.start(s, true)
	v.player.flush()
	var squad := s.living(Types.Team.PLAYER).filter(func(u: Unit) -> bool: return u.status.has("sid"))
	var foes := s.living(Types.Team.ENEMY)
	match screen:
		"hud", "aim", "pause":
			Rules.deal_damage(s, squad[0], 2, foes[0])
			Infection.add(s, squad[0], 30)
			v.player.flush()
			for i in 10:
				await process_frame
			v.input.select(squad[0].id)
			if screen == "aim":
				v.input.trigger("shoot")
			if screen == "pause" and v.has_method("toggle_pause"):
				v.toggle_pause()
		"debrief", "lost":
			for i in foes.size():
				Rules.deal_damage(s, foes[i], 999, squad[i % squad.size()])
			Rules.deal_damage(s, squad[0], 3, foes[0])
			Infection.add(s, squad[-1], 12)
			if screen == "lost":
				for u in squad:
					u.hp = 0
			else:
				s.objective.result = Types.Result.VICTORY
			Rules.check_end(s)
			v.player.flush()
			v.hud.debrief.skip()
