extends RefCounted
## Builds every UI screen with sample data, for screenshots (tools/shot_ui.gd) and the text
## overflow sweep (tests/ui_overflow_sweep.gd):
##   await UiScreens.build(tree, "loadout", 2)
## Each screen goes straight onto tree.root; clear() takes it all away again.

const MAIN := preload("res://scenes/main.tscn")
const APP := preload("res://scenes/app.tscn")
const W := preload("res://ui/widgets.gd")
const GearDemo := preload("res://ui/gear/gear_demo.gd")
const MainMenu := preload("res://ui/main_menu.gd")
const FieldHQ := preload("res://ui/meta/field_hq.gd")
const ArchiveScreen := preload("res://ui/story/archive_screen.gd")
const StoryScene := preload("res://ui/story/story_scene.gd")
const Director := preload("res://ui/story/story_director.gd")
const EndingScreen := preload("res://ui/story/ending_screen.gd")

## Every screen, in the order the sweep visits them. "training:N" opens lesson N.
static var SCREENS: Array[String] = _screens()

## Nodes the engine and the autoloads own; clear() leaves them be.
const KEEP := ["SettingsHost", "Soundscape", "UiFeel", "Platform", "TermTips", "GameSettings"]


static func _screens() -> Array[String]:
	var out: Array[String] = ["title", "lobby", "solo-lobby", "hotseat-lobby", "sound", "map", "map_start", "event", "depot", "hospital",
		"survivors", "reward", "loadout", "doctrine", "kit", "rankup", "rankup_reward", "hud", "aim", "quick", "debrief", "lost",
		"runend", "pause", "settings_graphics", "settings_audio", "settings_gameplay", "settings_accessibility",
		"settings_controls", "depot_grafts", "hospital_grafts", "reward_grafts", "loadout_grafts", "hq_unlocks", "hq_severity", "hq_record", "hq_achievements", "archive", "story",
		"ending_vote", "offer_training", "reward_compare", "mutation_compare", "guns_compare", "kit_compare", "reward_loadout", "depot_compare",
		"event_loadout", "loadout_veteran", "rankup_ability"]
	for i in TutorialScript.STEPS.size():
		out.append("training:%d" % i)
	return out


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


static func build(tree: SceneTree, screen: String, players := 2) -> void:
	var root := tree.root
	match screen:
		"title":
			root.add_child(MainMenu.new())
		"lobby":
			var net := NetSession.new()
			root.add_child(net)
			var m := MainMenu.new()
			root.add_child(m)
			await tree.process_frame
			net.host(24690, "Harvey")
			if players > 1:
				net.lobby[7] = {"player": 1, "name": "Kestrel", "squad": ["marksman"]}
				net.lobby[1]["squad"] = ["trooper", "medic", "breacher"]
			m.show_lobby(net)
		"solo-lobby", "hotseat-lobby":
			var m := MainMenu.new()
			root.add_child(m)
			await tree.process_frame
			m.show_local_lobby(1 if screen == "solo-lobby" else players)
			if screen == "hotseat-lobby":
				m._local_picks = {0: ["trooper", "medic"], 1: ["breacher", "marksman"]}
				m._edit_player = 1
				m._sel = 1
				m._refresh_lobby()
		"sound":
			root.add_child(MainMenu.new())
			await tree.process_frame
			root.get_node("/root/Soundscape").toggle_settings()
		"map", "map_start", "runend":
			var session := LocalSession.new()
			session.save_enabled = false
			root.add_child(session)
			session.start_run(players, 4242)
			var run := session.run
			run.steps.clear()
			run.phase = RunState.Phase.MAP
			session.player_names = {0: "Harvey", 1: "Kestrel"}
			if screen != "map_start":
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
			if screen != "runend":
				for i in 4:
					await tree.process_frame
				view._map.set_hover(run.reachable_nodes()[0])
		"event", "depot", "hospital", "survivors", "depot_grafts", "hospital_grafts":
			var run := RunRules.new_run(players, 31)
			GearRun.init_run(run)
			RunRules.start_run(run)
			run.phase = RunState.Phase.NODE
			run.supplies = 140
			run.intel = 2
			# A squad in mixed shape, so the squad panel has something to say.
			var hurt := [2, 3, 0, 4]
			var inf := [30, 12, 52, 41]
			for i in run.squad().size():
				var r: Dictionary = run.squad()[i]
				r.hp = maxi(1, r.max_hp - hurt[i % 4])
				r.infection = inf[i % 4]
				if i % 4 == 2:
					RunAccess.add_random_mutation(run, r)
				if i % 4 == 0:
					Loadout.equip(run, r, GearData.items_with("", "uncommon", "armor")[0])
			var kind := screen.trim_suffix("_grafts")
			if kind != screen:   # Act 2, Rank 3: Refit and Amputate on offer
				run.act = 2
				GearDemo._graft_squad(run.squad())
				run.squad()[0].prog.grafts["arm"] = "bloom_limb"
			NodeRules.enter(run, kind, "the_trial" if screen == "event" else "")
			_full_screen(root, NodeRules.screen(kind).new(), run)
		"reward", "loadout", "loadout_veteran", "doctrine", "kit", "reward_grafts", "loadout_grafts":
			if screen == "loadout_veteran":
				_sample_profile()   # finished runs: every gear tag shows
			var run := GearDemo.make_run(screen.trim_suffix("_veteran"))
			var ctl: Control = (GearRun.loadout_screen() if screen.begins_with("loadout") else GearRun.reward_screen()).new()
			_full_screen(root, ctl, run)
		"reward_compare", "mutation_compare", "guns_compare", "kit_compare", "reward_loadout":
			# The compare column with a card hovered (the Marksman's set-completing flare
			# launcher, a gun, a deployment order), or the loadout opened over the pick.
			var run := GearDemo.make_run(screen.trim_suffix("_compare").replace("reward_loadout", "reward").replace("mutation", "reward"))
			var ctl: Control = GearRun.reward_screen().new()
			_full_screen(root, ctl, run)
			if screen != "kit_compare" and screen != "mutation_compare":
				ctl._sid = run.squad()[1].id
				ctl._refresh()
			ctl._select(0)
			if screen == "reward_loadout":
				ctl.open_loadout()
			else:
				ctl._hovered = 1 if screen in ["kit_compare", "mutation_compare"] else 0
				ctl._show_compare()
		"depot_compare", "event_loadout":
			# A depot buy's compare card for real (TermTips), or the loadout over an event.
			var run := RunRules.new_run(players, 31)
			GearRun.init_run(run)
			RunRules.start_run(run)
			run.phase = RunState.Phase.NODE
			run.supplies = 140
			for r in run.squad():
				Loadout.equip(run, r, GearData.items_with("", "common", "armor")[0])
				Loadout.equip(run, r, "laser_sight")
			NodeRules.enter(run, "depot" if screen == "depot_compare" else "event", "" if screen == "depot_compare" else "the_trial")
			var scr: Control = NodeRules.screen("depot" if screen == "depot_compare" else "event").new()
			_full_screen(root, scr, run)
			for i in 4:
				await tree.process_frame
			if screen == "event_loadout":
				scr.open_loadout()
			else:
				var tips := root.get_node_or_null("TermTips")
				for b in scr.find_children("*", "Button", true, false):
					if tips != null and b.has_meta("tip") and b.get_meta("tip").ctx is Callable and b.is_visible_in_tree():
						# Rest the pointer on it too, so the card stays up.
						var at: Vector2 = b.get_global_rect().get_center()
						var mm := InputEventMouseMotion.new()
						mm.position = at
						mm.global_position = at
						Input.parse_input_event(mm)
						root.warp_mouse(at)
						tips.show_for(b, at)
						break
		"rankup", "rankup_reward", "rankup_ability":
			var run := RunRules.new_run(players, 81)
			RunRules.start_run(run)
			for r in run.squad():
				Progression.grant_perk_pick(run, r)
				r.infection = 30
			var first: Dictionary = run.squad()[0]
			first.prog.bonus_picks = 0
			if screen == "rankup_ability":
				first.prog.rank = Signatures.UNLOCK_RANK   # the signature's reveal card shows above the perks
				first.prog.picks = 1
			if screen != "rankup_ability":
				first.prog.offers.append({"cards": ["hollow_bones", "shared_blood", "rampage"], "source": "nest"})
			# rankup_reward: the step as players see it, inside the reward screen (title, squad
			# panel), with the run's opening deployment orders already taken.
			GearRun.state(run).offers.clear()
			var ctl: Control = GearRun.reward_screen().new() if screen == "rankup_reward" else Progression.pick_screen().new()
			_full_screen(root, ctl, run)
		"hud", "aim", "quick", "debrief", "lost", "pause":
			await _mission(tree, screen, players)
		"hq_unlocks", "hq_severity", "hq_record", "hq_achievements":
			_sample_profile()
			var hq := FieldHQ.new()
			root.add_child(hq)
			await tree.process_frame
			hq.show_tab(screen.trim_prefix("hq_"))
		"archive":
			root.add_child(ArchiveScreen.new())
		"story":
			var run := _story_run(players)
			var scene := StoryScene.new()
			root.add_child(scene)
			scene.play(Director.intro_spec(run))
			# Let a few captions come up.
			await tree.create_timer(5.0).timeout
		"ending_vote":
			var run := _story_run(players)
			run.seen_events.append("the_trial")
			run.story.open = true
			run.phase = RunState.Phase.REWARD
			var l := LocalSession.new()
			l.save_enabled = false
			l.run = run
			root.add_child(l)
			var es := EndingScreen.new()
			es.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_backdrop(root)
			root.add_child(es)
			es.setup(run, l)
		"offer_training":
			var app := APP.instantiate()
			root.add_child(app)
			await tree.process_frame
			app.coach.offer_training(func() -> void: pass, func() -> void: pass)
		_:
			if screen.begins_with("settings_"):
				root.add_child(MainMenu.new())
				await tree.process_frame
				root.get_node("SettingsHost").open_menu(screen.trim_prefix("settings_"))
			elif screen.begins_with("training:"):
				var app := APP.instantiate()
				root.add_child(app)
				await tree.process_frame
				app._start_training()
				await tree.process_frame
				app.session.jump_to(int(screen.get_slice(":", 1)))
			else:
				push_error("unknown screen " + screen)


## Frees everything build() added, ready for the next screen.
static func clear(tree: SceneTree) -> void:
	var host := tree.root.get_node_or_null("SettingsHost")
	if host != null:
		host.close_menu()
	var tips := tree.root.get_node_or_null("TermTips")
	if tips != null:
		tips.close_all()
	var sound := tree.root.get_node_or_null("Soundscape")
	if sound != null and sound.has_method("close_settings"):
		sound.close_settings()
	for c in tree.root.get_children():
		if not KEEP.has(String(c.name)):
			tree.root.remove_child(c)
			c.queue_free()


static func _backdrop(root: Node) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.025)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)


static func _full_screen(root: Node, ctl: Control, run: RunState) -> void:
	_backdrop(root)
	var s := StubSession.new()
	s.run = run
	s.players.assign(run.players)
	# The pick screen is always hosted in a screen with a FitBox (reward, hospital); stand in for it.
	if ctl.get_script() == Progression.pick_screen():
		var fit := W.FitBox.new()
		fit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(fit)
		ctl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		fit.add_child(ctl)
	else:
		root.add_child(ctl)
		ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctl.setup(run, s)


static func _mission(tree: SceneTree, screen: String, players: int) -> void:
	var root := tree.root
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
		"hud", "aim", "pause", "quick":
			Rules.deal_damage(s, squad[0], 2, foes[0])
			Infection.add(s, squad[0], 30)
			v.player.flush()
			for i in 10:
				await tree.process_frame
			v.input.select(squad[0].id)
			if screen == "aim":
				v.input.trigger("shoot")
			if screen == "pause" and v.has_method("toggle_pause"):
				v.toggle_pause()
			if screen == "quick":
				v.input.open_quick_menu()
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


static func _story_run(players: int) -> RunState:
	var run := RunRules.new_run(players, 77, {"story": {"wave": 9, "runs": 2, "last_result": "won",
		"last_ending": "burn", "last_wave": 8, "lore": [StoryData.CARRY_LORE], "echoes": []}})
	for i in run.squad().size():
		run.squad()[i].infection = [10, 35, 60, 88][i % 4]
	return run


## A few finished runs, some Field Data spent, Severity 3 picked (for the Field HQ tabs).
static func _sample_profile() -> void:
	Profile.path = "user://ui_screens_profile.cfg"
	DirAccess.remove_absolute(Profile.path)
	var runs := [
		[1, false, {"skirmish": 2}, [], 0, 1],
		[2, false, {"skirmish": 3, "nest": 1, "boss": 1}, [1], 0, 2],
		[1, true, {"skirmish": 4, "nest": 2, "boss": 3}, [1, 2, 3], 0, 3],
		[4, true, {"skirmish": 5, "nest": 3, "boss": 3}, [1, 2, 3], 1, 4],
		[1, false, {"skirmish": 4, "nest": 1, "boss": 2}, [1, 2], 2, 5],
		[2, true, {"skirmish": 4, "nest": 1, "boss": 3}, [1, 2, 3], 2, 6],
	]
	for r in runs:
		var run := RunRules.new_run(r[0], r[5] * 101, {"packs": [], "severity": r[4]})
		run.tally = {"fights": r[2], "boss_acts": r[3], "bonus": 2, "dead": 1 if not r[1] else 0, "turned": 1 if r[5] == 5 else 0, "lost_fights": 0}
		run.phase = RunState.Phase.ENDED
		run.result = Types.Result.VICTORY if r[1] else Types.Result.DEFEAT
		run.act = 3 if r[1] else r[3].size() + 1
		run.row = 5 if r[1] else 3
		run.meta["start_flags"] = []
		if r[5] >= 2:
			run.meta["act1_boss_beaten"] = true
		Profile.record_run(run)
	var cf := ConfigFile.new()
	cf.load(Profile.path)
	cf.set_value("field", "data", cf.get_value("field", "data", 0) + 300)
	cf.save(Profile.path)
	Profile.buy("gear_1")
	Profile.buy("field_kit")
	Profile.set_severity(3)
