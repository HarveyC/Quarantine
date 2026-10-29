extends TestCase
## Story: wave count, Echoes, intel logs, the ending vote, the story profile and scene specs.

const Director := preload("res://ui/story/story_director.gd")
const TEST_PROFILE := "user://test_story_profile.cfg"


func _meta(echoes: Array = [], lore: Array = [], runs := 0) -> Dictionary:
	return {"story": {"wave": StoryData.FIRST_WAVE + runs, "runs": runs, "last_result": "lost" if runs > 0 else "",
		"last_ending": "", "last_wave": StoryData.FIRST_WAVE + runs - 1, "endings": [], "lore": lore,
		"source_reached": false, "echoes": echoes}}


func _echo(key: String, kind := "trooper", name := "Vasquez", wave := 7) -> Dictionary:
	return {"key": key, "kind": kind, "name": name, "act": 2, "wave": wave}


func _settle(run: RunState) -> void:
	RunAutoplay.settle(run, func(a: Dictionary) -> void: RunRules.apply(run, a))


## Builds the current fight, kills every enemy, and reports a win.
func _win(run: RunState) -> GameState:
	var s := MatchConfig.build(run.fight_config)
	Rules.start_mission(s)
	for u in s.living(Types.Team.ENEMY):
		u.hp = 0
	s.objective.result = Types.Result.VICTORY
	Rules.check_end(s)
	RunRules.apply(run, {"type": RunRules.FIGHT_END, "player": 0, "outcome": RunRules.fight_outcome(s, false)})
	_settle(run)
	return s


## Jumps a run to the act 3 boss fight.
func _to_final_boss(run: RunState) -> void:
	run.act = 3
	run.map = RunMap.generate(run.rng, 3)
	run.phase = RunState.Phase.MAP
	var boss: Dictionary = run.map.filter(func(n: Dictionary) -> bool: return n.type == RunMap.BOSS)[0]
	RunRules.enter_node(run, boss.id)


func test_new_run_takes_up_to_two_echoes_from_the_profile() -> void:
	var run := RunRules.new_run(1, 11, _meta([_echo("a"), _echo("b", "ghost_class"), _echo("c", "medic", "Reyes"), _echo("d")]))
	assert_eq(run.story.wave, StoryData.FIRST_WAVE, "first wave")
	var keys: Array = run.story.echoes.map(func(e: Dictionary) -> String: return e.key)
	assert_eq(keys, ["a", "c"], "two echoes, unknown classes skipped")
	var bare := RunRules.new_run(1, 11)
	assert_eq(bare.story.echoes.size(), 0, "no profile, no echoes")


func test_echo_joins_a_fight_as_a_named_turned_enemy() -> void:
	var run := RunRules.new_run(1, 21, _meta([_echo("w7_3", "marksman", "Lindqvist")]))
	RunRules.start_run(run)
	_settle(run)
	run.fights_won = 1
	var plain_run := RunRules.new_run(1, 21)
	plain_run.map = run.map   # the same map, so the same boss and faction pack
	var plain := MatchConfig.for_fight(plain_run, {"kind": RunMap.SKIRMISH, "objective": "extract", "seed": 99})
	var cfg := MatchConfig.for_fight(run, {"kind": RunMap.SKIRMISH, "objective": "extract", "seed": 99})
	assert_eq(cfg.echo.get("key", ""), "w7_3", "the echo is in this fight")
	assert_eq(cfg.enemies.size(), plain.enemies.size() - 1, "the echo takes one enemy's place")
	assert_true(run.story.echoes[0].met, "marked met")
	var s := MatchConfig.build(cfg)
	var echo: Array = s.units.filter(func(u: Unit) -> bool: return u.status.has("echo"))
	assert_eq(echo.size(), 1, "one echo unit")
	var u: Unit = echo[0]
	assert_eq(u.team, Types.Team.ENEMY, "hostile")
	assert_eq(u.kind, "marksman", "keeps their class")
	assert_true(u.status.get("turned", false) and u.ai_controlled, "a Turned soldier")
	assert_eq(u.display_name, "Echo Lindqvist", "keeps their name")
	assert_eq(u.max_hp, UnitData.SOLDIERS.marksman.max_hp * Story.ECHO_HP_MULT, "elite health")
	var again := MatchConfig.for_fight(run, {"kind": RunMap.SKIRMISH, "objective": "extract", "seed": 98})
	assert_true(again.echo.is_empty(), "an echo comes once per run")


func test_no_echo_before_the_first_win_or_in_a_boss_fight() -> void:
	var run := RunRules.new_run(1, 22, _meta([_echo("x")]))
	assert_true(Story.fight_echo(run, {"kind": RunMap.SKIRMISH}).is_empty(), "not in the first fight")
	run.fights_won = 3
	assert_true(Story.fight_echo(run, {"kind": RunMap.BOSS}).is_empty(), "not in a boss fight")
	assert_eq(Story.fight_echo(run, {"kind": RunMap.NEST}).get("key", ""), "x", "a nest is fine")


func test_killing_an_echo_pays_and_recovers_intel() -> void:
	var run := RunRules.new_run(1, 23, _meta([_echo("k1")], ["cordon_7"]))
	RunRules.start_run(run)
	_settle(run)
	_vote_fight(run)
	run.fights_won = 1
	# the echo shows up from the second fight; start a new fight now that one was "won"
	run.fight_config = MatchConfig.for_fight(run, {"kind": RunMap.SKIRMISH, "objective": "extract", "seed": 5})
	var supplies := run.supplies
	_win(run)
	assert_true(run.story.echoes[0].laid, "laid to rest")
	assert_eq(run.story.lore, ["survey_0419"], "the next unknown log, in order")
	assert_true(run.supplies >= supplies + Story.ECHO_SUPPLIES, "dog tags pay out")


func _vote_fight(run: RunState) -> void:
	var opts := run.reachable_nodes()
	for id in opts:
		if RunMap.is_fight(RunMap.shown_type(run.get_node(id))):
			RunRules.apply(run, {"type": RunRules.VOTE, "player": 0, "node": id})
			return


func test_final_boss_opens_the_ending_vote_and_burn_wins_the_run() -> void:
	var run := RunRules.new_run(1, 31)
	RunRules.start_run(run)
	_settle(run)
	_to_final_boss(run)
	assert_eq(run.phase, RunState.Phase.FIGHT, "boss fight")
	var s := MatchConfig.build(run.fight_config)
	Rules.start_mission(s)
	for u in s.living(Types.Team.ENEMY):
		u.hp = 0
	s.objective.result = Types.Result.VICTORY
	Rules.check_end(s)
	RunRules.apply(run, {"type": RunRules.FIGHT_END, "player": 0, "outcome": RunRules.fight_outcome(s, false)})
	assert_eq(run.phase, RunState.Phase.REWARD, "waits for the ending")
	assert_true(Story.has_pending(run), "ending vote open")
	assert_eq(run.story.lore.size(), 1, "the boss carried intel")
	var opts := Story.ending_options(run)
	assert_eq(opts.map(func(o: Dictionary) -> bool: return o.ok), [true, false, false], "only Burn it is open")
	assert_true(RunRules.validate(run, {"type": Story.ENDING_VOTE, "player": 0, "ending": "carry"}) != "", "carry is locked")
	assert_true(RunRules.apply(run, {"type": Story.ENDING_VOTE, "player": 0, "ending": "burn"}), "vote")
	_settle(run)
	assert_eq(run.phase, RunState.Phase.ENDED, "run over")
	assert_eq(run.result, Types.Result.VICTORY, "won")
	assert_eq(run.story.ending, "burn", "burned")


func test_sample_and_carry_unlock() -> void:
	var run := RunRules.new_run(1, 32, _meta([], [StoryData.CARRY_LORE]))
	run.seen_events.append("the_trial")
	run.story.open = true
	var opts := Story.ending_options(run)
	assert_true(opts[1].ok, "met Halden-Voss: sample open")
	assert_true(not opts[2].ok and opts[2].reason == StoryData.ENDINGS.carry.locked_soldier, "carry needs a Critical soldier")
	var r: Dictionary = run.squad()[2]
	r.infection = 88
	assert_true(Story.ending_options(run)[2].ok, "carry open")
	RunRules.apply(run, {"type": Story.ENDING_VOTE, "player": 0, "ending": "carry"})
	assert_eq(run.story.ending, "carry", "carried")
	assert_eq(run.story.carrier, r.id, "the Critical soldier carries it")
	var spec := Director.ending_spec(run)
	assert_eq(spec.carrier_index, 2, "the scene stages that soldier")
	assert_true(spec.lines[0][1].contains(r.name), "named in the scene")


func test_coop_ending_vote_tie_goes_to_host() -> void:
	var run := RunRules.new_run(2, 33)
	run.seen_events.append("field_chapel")
	run.story.open = true
	run.phase = RunState.Phase.REWARD
	RunRules.apply(run, {"type": Story.ENDING_VOTE, "player": 1, "ending": "burn"})
	assert_eq(run.story.ending, "", "waits for everyone")
	RunRules.apply(run, {"type": Story.ENDING_VOTE, "player": 0, "ending": "sample"})
	assert_eq(run.story.ending, "sample", "host breaks the tie")


func test_story_survives_save_and_resume() -> void:
	var run := RunRules.new_run(1, 34, _meta([_echo("s1")], ["cordon_7"], 3))
	var back := RunState.from_save_string(run.save_string())
	assert_eq(back.story, run.story, "story state round trips")
	assert_eq(back.checksum(), run.checksum(), "checksum matches")


func test_profile_records_wave_echoes_and_lore_once() -> void:
	var keep := Profile.path
	Profile.path = TEST_PROFILE
	StoryProfile.clear()
	assert_eq(StoryProfile.wave(), StoryData.FIRST_WAVE, "fresh profile")
	var run := RunRules.new_run(1, 41, {"story": StoryProfile.snapshot()})
	run.story.lore.append("cordon_7")
	run.echoes.append({"sid": 2, "kind": "medic", "name": "Okoro", "act": 2})
	run.phase = RunState.Phase.ENDED
	run.result = Types.Result.DEFEAT
	StoryProfile.record_run(run)
	StoryProfile.record_run(run)   # every peer, after every action: still one run
	var snap := StoryProfile.snapshot()
	assert_eq(snap.runs, 1, "one run counted")
	assert_eq(snap.wave, StoryData.FIRST_WAVE + 1, "next wave")
	assert_eq(snap.lore, ["cordon_7"], "intel kept")
	assert_eq(snap.echoes.size(), 1, "the Turned medic waits as an echo")
	assert_eq(snap.last_result, "lost", "lost")
	# the next run meets and lays that echo to rest
	var run2 := RunRules.new_run(1, 42, {"story": snap})
	assert_eq(run2.story.echoes.size(), 1, "echo comes back")
	assert_eq(Director.intro_spec(run2).lines[0][1], StoryData.fill(StoryData.INTRO_OPENERS.lost[0][1], {"last_wave": StoryData.FIRST_WAVE}), "briefing remembers the lost wave")
	run2.story.echoes[0].laid = true
	run2.story.ending = "carry"
	run2.phase = RunState.Phase.ENDED
	run2.result = Types.Result.VICTORY
	StoryProfile.record_run(run2)
	snap = StoryProfile.snapshot()
	assert_eq(snap.echoes.size(), 0, "laid echoes leave the pool")
	assert_eq(snap.endings, ["carry"], "ending seen")
	assert_eq(snap.last_ending, "carry", "last ending")
	StoryProfile.clear()
	Profile.path = keep


func test_scene_specs() -> void:
	var run := RunRules.new_run(1, 51)
	var intro := Director.intro_spec(run)
	assert_eq(intro.title, "Wave %d" % StoryData.FIRST_WAVE, "wave title")
	assert_eq(intro.lines.size(), StoryData.INTRO_OPENERS.first.size() + StoryData.INTRO_ORDERS.size(), "full first briefing")
	assert_eq(intro.cast.size(), 4, "the squad is in the shot")
	run.story.source_reached = true
	assert_eq(Director.act_spec(run, 3).lines[1], StoryData.SOURCE_REMEMBERS, "the Source remembers")
	var squad_line: Array = Director.act_spec(run, 2).lines[2]
	assert_true(squad_line[0] != "SQUAD" and squad_line[0].contains(run.squad()[0].name), "a squad line gets a real soldier")
	for boss in EnemyRoster.BOSS_OF_ACT.values():
		assert_true(not Director.boss_spec(run, boss).is_empty(), "boss intro for %s" % boss)
	assert_true(Director.act_spec(run, 1).is_empty(), "act 1 has the briefing instead")
	assert_eq(StoryData.garble("one two three four five six seven eight", 0), "one two three... five six seven...", "radio static")


func test_lore_runs_out_cleanly() -> void:
	var all: Array = StoryData.LORE.map(func(e: Dictionary) -> String: return e.id)
	var run := RunRules.new_run(1, 61, _meta([], all))
	assert_eq(Story.recover_lore(run), "", "nothing left to find")
	assert_true(Story.knows(run, StoryData.CARRY_LORE), "carry log known")


## Fight chatter waits for what's on screen: Rules resolves the enemy turn at once, but the
## "down" call only comes once the death beat has played, and run events that land mid-fight
## (an Echo laid to rest) wait for the queue to drain.
func test_fight_chatter_waits_for_the_beats() -> void:
	var v: MissionView = preload("res://scenes/main.tscn").instantiate()
	v.start(MissionView.default_mission(1234), true)
	v.player.flush()
	var d := Director.new()
	(Engine.get_meta("test_tree") as SceneTree).root.add_child(d)
	d._run = RunRules.new_run(1, 61)
	var u: Unit = v.state.controllable_units(0)[0]
	u.status["sid"] = d._run.squad()[0].id
	var foe: Unit = v.state.living(Types.Team.ENEMY)[0]
	d._bind_player(v.player, v.state)
	var radio := func() -> int: return d._radio_box.get_child_count()
	v.player.enqueue({"type": "enemy_phase", "turn": 1})
	v.player.enqueue({"type": "shot", "unit": foe.id, "target": u.id, "hit": true, "chance": 70})
	v.player.enqueue({"type": "damage", "unit": u.id, "amount": 9, "hp": 0, "source": foe.id})
	v.player.enqueue({"type": "died", "unit": u.id})
	d._on_run_event({"type": "echo_laid", "key": "e1", "name": "Vasquez"})
	assert_eq(radio.call(), 0, "nothing said while the attack is still queued")
	var died_started := [false]
	v.player.beat_started.connect(func(ev: Dictionary) -> void:
		if ev.type == "died":
			died_started[0] = true)
	var steps := 0
	while not died_started[0] and steps < 3000:
		v.player.advance(1.0 / 30.0)
		steps += 1
	assert_true(died_started[0], "death beat reached")
	assert_eq(radio.call(), 0, "not called down while the body is still falling")
	d._release_held()
	assert_eq(radio.call(), 0, "the Echo line waits for the fight's beats")
	v.player.flush()
	assert_eq(radio.call(), 1, "called down once the death has played")
	d._release_held()
	assert_eq(radio.call(), 2, "then the held Echo line")
	d._bind_player(null, null)
	d.free()
	v.free()
